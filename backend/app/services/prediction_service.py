"""Transit prediction orchestration (SPEC section 10, steps 1-16).

Wires together astronomy, providers, geometry, prediction and confidence into a single
call. Pre-filtering (SPEC section 11.1) discards aircraft that cannot possibly produce
a transit before the expensive per-aircraft refinement runs.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from app.astronomy.ephemeris import EphemerisService
from app.astronomy.satellites import SatelliteCatalog
from app.confidence.scoring import (
    ConfidenceInputs,
    ConfidenceResult,
    SatelliteConfidenceInputs,
    score_candidate,
    score_satellite_candidate,
)
from app.domain.models import (
    AircraftState,
    CelestialBody,
    CelestialPosition,
    ObserverLocation,
    TransitCandidate,
    TransitObjectKind,
)
from app.geometry.angles import angular_separation_deg
from app.geometry.coordinates import observer_relative
from app.geometry.corridor import CorridorEstimate, estimate_corridor
from app.prediction.projection import project_state
from app.prediction.satellite_transit import find_satellite_transit
from app.prediction.transit import find_transit_candidate
from app.providers.registry import AircraftFetchResult, ProviderRegistry

# Pre-filter: keep aircraft whose current OR near-future line of sight is within this
# angular window of the body. A fast, generous gate before the exact search.
_PREFILTER_CONE_DEG = 8.0
_PREFILTER_SAMPLE_STEP_S = 10.0

# Margin used both for transit detection (matches prediction.transit default) and
# for sizing the geographic corridor around the central line (RF-014).
_CORRIDOR_MARGIN_DEG = 0.05


@dataclass(frozen=True)
class TransitPrediction:
    candidate: TransitCandidate
    confidence: ConfidenceResult
    callsign: Optional[str]
    aircraft_distance_m: float
    data_age_s: float
    corridor: Optional[CorridorEstimate] = None


@dataclass(frozen=True)
class PredictionResponse:
    observer: ObserverLocation
    generated_at_utc: datetime
    bodies: list[CelestialPosition]
    predictions: list[TransitPrediction]
    provider_name: str
    data_degraded: bool
    aircraft_considered: int


class PredictionService:
    def __init__(
        self,
        ephemeris: EphemerisService,
        registry: ProviderRegistry,
        satellite_catalog: Optional[SatelliteCatalog] = None,
    ):
        self._ephemeris = ephemeris
        self._registry = registry
        self._satellites = satellite_catalog

    def _passes_prefilter(
        self,
        state: AircraftState,
        body: CelestialPosition,
        observer: ObserverLocation,
        horizon_s: float,
    ) -> bool:
        """Cheap angular gate over look-ahead samples spanning the full horizon
        (SPEC 11.1). Samples must cover ``horizon_s`` — a fixed sample set that
        stops short of the requested horizon would silently miss transits
        beyond that point.
        """
        if state.on_ground:
            return False
        sample_count = max(2, int(horizon_s // _PREFILTER_SAMPLE_STEP_S) + 1)
        lookahead_s = [
            i * horizon_s / (sample_count - 1) for i in range(sample_count)
        ]
        for t in lookahead_s:
            projected = project_state(state, t)
            topo = observer_relative(
                projected.latitude_deg,
                projected.longitude_deg,
                projected.altitude_m,
                observer,
            )
            if topo.altitude_deg <= 0.0:
                continue
            sep = angular_separation_deg(
                topo.azimuth_deg, topo.altitude_deg, body.azimuth_deg, body.altitude_deg
            )
            if sep <= _PREFILTER_CONE_DEG:
                return True
        return False

    async def _predict_satellites(
        self,
        observer: ObserverLocation,
        visible_bodies: list[CelestialPosition],
        when: datetime,
        horizon_s: float,
    ) -> list[TransitPrediction]:
        """Transits of the tracked satellites (ISS, Tiangong) across the visible
        bodies. TLE fetching is best-effort: a network failure yields no satellite
        predictions rather than failing the whole request.
        """
        if self._satellites is None:
            return []
        try:
            satellites = await self._satellites.get_satellites()
        except Exception:  # pragma: no cover - defensive; catalog already guards fetch
            return []

        results: list[TransitPrediction] = []
        for loaded in satellites:
            for body in visible_bodies:
                st = find_satellite_transit(
                    loaded, body.body, self._ephemeris, observer, when, horizon_s=horizon_s
                )
                if st is None or not st.candidate.is_transit:
                    continue

                confidence = score_satellite_candidate(
                    st.candidate,
                    SatelliteConfidenceInputs(
                        tle_age_hours=st.tle_age_hours,
                        altitude_deg=st.candidate.aircraft_altitude_deg,
                        gps_accuracy_m=observer.horizontal_accuracy_m,
                    ),
                )

                corridor = None
                try:
                    corridor = estimate_corridor(
                        observer,
                        body,
                        aircraft_lat_deg=st.subpoint_lat_deg,
                        aircraft_lon_deg=st.subpoint_lon_deg,
                        aircraft_altitude_m=st.subpoint_alt_m,
                        aircraft_radius_deg=st.candidate.aircraft_radius_deg,
                        margin_deg=_CORRIDOR_MARGIN_DEG,
                    )
                except (ValueError, ZeroDivisionError):
                    pass

                results.append(
                    TransitPrediction(
                        candidate=st.candidate,
                        confidence=confidence,
                        callsign=st.candidate.object_label,
                        aircraft_distance_m=st.slant_range_m,
                        data_age_s=st.tle_age_hours * 3600.0,
                        corridor=corridor,
                    )
                )
        return results

    async def predict(
        self,
        observer: ObserverLocation,
        targets: list[CelestialBody],
        horizon_s: float = 120.0,
        radius_km: float = 80.0,
        when: Optional[datetime] = None,
    ) -> PredictionResponse:
        when = when or datetime.now(timezone.utc)

        # Steps 3: body positions.
        bodies = [
            self._ephemeris.position(body, observer, when) for body in targets
        ]
        visible_bodies = [b for b in bodies if b.altitude_deg > 0.0]

        # Step 4: fetch aircraft (with failover + cache).
        fetch: AircraftFetchResult = await self._registry.get_aircraft_near(
            observer.latitude_deg, observer.longitude_deg, radius_km
        )

        predictions: list[TransitPrediction] = []
        considered = 0

        for state in fetch.aircraft:
            data_age = max(state.age_seconds, fetch.age_seconds)
            for body in visible_bodies:
                # Steps 7: pre-filter.
                if not self._passes_prefilter(state, body, observer, horizon_s):
                    continue
                considered += 1
                # Steps 8-13: exact candidate search + refinement.
                candidate = find_transit_candidate(
                    state, body, observer, horizon_s=horizon_s
                )
                if candidate is None or not candidate.is_transit:
                    continue

                # Distance to the aircraft at closest approach, for confidence.
                projected = project_state(state, candidate.time_to_transit_s)
                topo = observer_relative(
                    projected.latitude_deg,
                    projected.longitude_deg,
                    projected.altitude_m,
                    observer,
                )

                # Steps 15: confidence.
                confidence = score_candidate(
                    candidate,
                    ConfidenceInputs(
                        data_age_s=data_age,
                        from_cache=fetch.from_cache,
                        degraded=fetch.degraded,
                        aircraft_distance_m=topo.range_m,
                        gps_accuracy_m=observer.horizontal_accuracy_m,
                        track_points=1,
                    ),
                )

                # Step 13: geographic corridor (RF-014), best-effort — skip
                # rather than fail the whole prediction if the geometry is
                # degenerate (e.g. body essentially on the horizon).
                corridor = None
                try:
                    corridor = estimate_corridor(
                        observer,
                        body,
                        aircraft_lat_deg=projected.latitude_deg,
                        aircraft_lon_deg=projected.longitude_deg,
                        aircraft_altitude_m=projected.altitude_m,
                        aircraft_radius_deg=candidate.aircraft_radius_deg,
                        margin_deg=_CORRIDOR_MARGIN_DEG,
                    )
                except (ValueError, ZeroDivisionError):
                    pass

                predictions.append(
                    TransitPrediction(
                        candidate=candidate,
                        confidence=confidence,
                        callsign=state.callsign,
                        aircraft_distance_m=topo.range_m,
                        data_age_s=data_age,
                        corridor=corridor,
                    )
                )

        # Satellite transits (ISS, Tiangong) cross the same visible bodies via
        # orbital propagation rather than ADS-B projection.
        predictions.extend(
            await self._predict_satellites(observer, visible_bodies, when, horizon_s)
        )

        # Soonest, most-confident first.
        predictions.sort(
            key=lambda p: (p.candidate.time_to_transit_s, -p.confidence.score)
        )

        return PredictionResponse(
            observer=observer,
            generated_at_utc=when,
            bodies=bodies,
            predictions=predictions,
            provider_name=fetch.provider_name,
            data_degraded=fetch.degraded,
            aircraft_considered=considered,
        )
