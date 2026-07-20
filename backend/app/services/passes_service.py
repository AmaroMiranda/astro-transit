"""Multi-day satellite transit planner (modelo ISS Transit Finder).

Aircraft transits are only knowable ~minutes ahead (ADS-B), but satellite transits
are **deterministic**: with a fresh TLE, ISS/Tiangong crossings of the Sun/Moon can
be predicted days in advance — that is the core feature of the established tools in
this niche (transit-finder.com scans 14 days; Sky & Telescope's tool 5 days).

We scan up to 72 h (default 48 h): beyond that, TLE drift starts to move the
few-km-wide ground track by more than its own width, so longer windows would be
precision theatre. The scan is two-phase and fully vectorized:

1. coarse sweep (30 s grid) of satellite AND body altitude to find the pass
   segments where both are simultaneously above the horizon;
2. for each segment, run the already-validated fine engine
   (:func:`find_satellite_transit`) which does the 2 s coarse + 61-sample
   refinement and returns the transit (if any) with duration and ground point.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

import numpy as np
from skyfield.api import wgs84

from app.astronomy.ephemeris import EphemerisService
from app.astronomy.satellites import SatelliteCatalog
from app.domain.models import CelestialBody, ObserverLocation
from app.geometry.corridor import CorridorEstimate
from app.prediction.satellite_transit import SatelliteTransit, find_satellite_transit
from app.services.prediction_service import satellite_corridor

_COARSE_STEP_S = 30.0
# Passes culminating below this elevation are skipped: geometry is fragile and
# the view is usually blocked anyway (matches the confidence model's low-pass
# penalty).
_MIN_SAT_ELEVATION_DEG = 5.0
_MAX_HOURS = 72.0
# Wide angular gate: a 4 deg miss at ISS ranges is a ground track ~40 km away —
# still catchable by car, which is exactly how the established tools are used
# (find the centerline, drive to it).
_PLANNER_GATE_DEG = 4.0


@dataclass(frozen=True)
class SatellitePass:
    """One upcoming satellite transit, absolute-time stamped."""

    transit: SatelliteTransit
    transit_at_utc: datetime
    satellite_id: str
    satellite_label: str
    corridor: Optional[CorridorEstimate]


class PassesService:
    def __init__(self, ephemeris: EphemerisService, catalog: SatelliteCatalog):
        self._ephemeris = ephemeris
        self._catalog = catalog

    async def upcoming(
        self,
        observer: ObserverLocation,
        hours: float = 48.0,
        bodies: Optional[list[CelestialBody]] = None,
        start: Optional[datetime] = None,
        max_center_distance_km: float = 30.0,
    ) -> list[SatellitePass]:
        hours = min(max(hours, 1.0), _MAX_HOURS)
        bodies = bodies or [CelestialBody.SUN, CelestialBody.MOON]
        start = (start or datetime.now(timezone.utc)).astimezone(timezone.utc)

        satellites = await self._catalog.get_satellites()
        if not satellites:
            return []

        ts = self._ephemeris.timescale
        n = int(hours * 3600.0 / _COARSE_STEP_S) + 1
        offsets = np.arange(n) * _COARSE_STEP_S
        times = ts.from_datetimes(
            [start + timedelta(seconds=float(o)) for o in offsets]
        )

        # Body elevations over the whole window, one vectorized call per body.
        body_alt: dict[CelestialBody, np.ndarray] = {}
        for body in bodies:
            alt, _, _ = self._ephemeris.altaz_series(body, observer, times)
            body_alt[body] = alt

        site = wgs84.latlon(
            observer.latitude_deg,
            observer.longitude_deg,
            elevation_m=observer.altitude_m,
        )

        passes: list[SatellitePass] = []
        for loaded in satellites:
            sat_alt, _, _ = (loaded.satellite - site).at(times).altaz()
            sat_up = sat_alt.degrees > _MIN_SAT_ELEVATION_DEG
            for body in bodies:
                both_up = sat_up & (body_alt[body] > 0.0)
                for i0, i1 in _segments(both_up):
                    # Pad one coarse step on each side so the fine engine sees
                    # the whole pass even when the mask starts mid-step.
                    seg_start = start + timedelta(
                        seconds=max(0.0, offsets[i0] - _COARSE_STEP_S)
                    )
                    seg_horizon = (
                        (i1 - i0 + 2) * _COARSE_STEP_S
                    )
                    st = find_satellite_transit(
                        loaded,
                        body,
                        self._ephemeris,
                        observer,
                        seg_start,
                        horizon_s=seg_horizon,
                        approach_gate_deg=_PLANNER_GATE_DEG,
                        keep_no_overlap=True,
                    )
                    if st is None:
                        continue
                    corridor = satellite_corridor(observer, st)
                    # Keep the pass when it is a transit right here, OR when the
                    # ground centerline runs close enough to travel to — the
                    # defining workflow of the established transit planners.
                    at_observer = st.candidate.is_transit
                    near_centerline = (
                        corridor is not None
                        and corridor.distance_from_observer_m
                        <= max_center_distance_km * 1000.0
                    )
                    if not at_observer and not near_centerline:
                        continue
                    passes.append(
                        SatellitePass(
                            transit=st,
                            transit_at_utc=seg_start
                            + timedelta(seconds=st.candidate.time_to_transit_s),
                            satellite_id=loaded.object_id,
                            satellite_label=loaded.label,
                            corridor=corridor,
                        )
                    )

        passes.sort(key=lambda p: p.transit_at_utc)
        return _dedupe(passes)


def _segments(mask: np.ndarray) -> list[tuple[int, int]]:
    """Contiguous True runs of ``mask`` as inclusive (start, end) index pairs."""
    if not mask.any():
        return []
    idx = np.flatnonzero(mask)
    breaks = np.flatnonzero(np.diff(idx) > 1)
    starts = np.concatenate(([idx[0]], idx[breaks + 1]))
    ends = np.concatenate((idx[breaks], [idx[-1]]))
    return list(zip(starts.tolist(), ends.tolist()))


def _dedupe(passes: list[SatellitePass]) -> list[SatellitePass]:
    """Drop duplicates (same satellite+body within 2 min — overlapping segments)."""
    result: list[SatellitePass] = []
    for p in passes:
        duplicate = any(
            q.satellite_id == p.satellite_id
            and q.transit.candidate.body == p.transit.candidate.body
            and abs((q.transit_at_utc - p.transit_at_utc).total_seconds()) < 120.0
            for q in result
        )
        if not duplicate:
            result.append(p)
    return result
