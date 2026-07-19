"""Temporal-coherence fixes (auditoria P0.1/P0.2/P0.3/P0.6).

These tests pin the physics-correctness contracts:

* P0.1 — a stale ADS-B fix must be dead-reckoned to the request epoch before the
  search, so the predicted instant is measured from *now*, not from packet time.
* P0.2 — the Sun/Moon must move during the search window; the detection must use
  the interpolated position, not the frozen t=0 one.
* P0.3 — the satellite ground point comes from an exact ray-ellipsoid
  intersection that round-trips in ECEF.
* P0.6 — aircraft with missing telemetry never enter the engine.
"""

from __future__ import annotations

import math
from dataclasses import replace
from datetime import datetime, timedelta, timezone

import pytest

from app.domain.models import (
    AircraftCategory,
    AircraftState,
    CelestialBody,
    CelestialPosition,
    ObserverLocation,
)
from app.geometry.coordinates import geodetic_to_ecef, observer_relative
from app.geometry.satellite_ground import (
    az_alt_to_ecef_direction,
    ecef_to_geodetic,
    satellite_shadow_point,
)
from app.prediction.projection import project_state
from app.prediction.transit import find_transit_candidate
from app.providers.fake import FakeProvider
from app.providers.registry import ProviderRegistry
from app.services.prediction_service import PredictionService

OBSERVER = ObserverLocation(latitude_deg=-23.55, longitude_deg=-46.63, altitude_m=760.0)
WHEN = datetime(2026, 7, 19, 15, 0, 0, tzinfo=timezone.utc)


def _aircraft(track_deg: float = 40.0, speed: float = 220.0) -> AircraftState:
    """An arbitrary but fully-specified airborne state near the observer."""
    return AircraftState(
        icao24="coherent",
        latitude_deg=OBSERVER.latitude_deg - 0.10,
        longitude_deg=OBSERVER.longitude_deg - 0.12,
        geometric_altitude_m=9000.0,
        ground_speed_mps=speed,
        track_deg=track_deg,
        category=AircraftCategory.NARROW_BODY,
        timestamp_utc=WHEN,
    )


def _sightline_at(state: AircraftState, t: float) -> tuple[float, float]:
    """Az/alt of ``state`` as seen from OBSERVER after ``t`` seconds."""
    p = project_state(state, t)
    topo = observer_relative(p.latitude_deg, p.longitude_deg, p.altitude_m, OBSERVER)
    return topo.azimuth_deg, topo.altitude_deg


def _body_at_sightline(az: float, alt: float) -> CelestialPosition:
    return CelestialPosition(
        body=CelestialBody.SUN,
        azimuth_deg=az,
        altitude_deg=alt,
        distance_m=1.496e11,
        angular_radius_deg=0.266,
    )


class _StubEphemeris:
    """position() pins the body to a fixed sightline regardless of time."""

    def __init__(self, position: CelestialPosition):
        self._position = position

    def position(self, body, observer, when=None):
        return self._position


# --------------------------------------------------------------------- P0.1 ---

@pytest.mark.asyncio
async def test_stale_fix_is_advanced_to_request_epoch():
    """A 20 s-old fix back-projected along the same trajectory must yield the
    same transit instant as the fresh fix — the engine must dead-reckon it."""
    fresh = _aircraft()
    az, alt = _sightline_at(fresh, 60.0)          # guaranteed transit at t=60
    ephemeris = _StubEphemeris(_body_at_sightline(az, alt))

    # Same physical trajectory, reported 20 s earlier from 20 s further back.
    back = project_state(fresh, -20.0)
    stale = replace(
        fresh,
        latitude_deg=back.latitude_deg,
        longitude_deg=back.longitude_deg,
        geometric_altitude_m=back.altitude_m,
        timestamp_utc=WHEN - timedelta(seconds=20),
    )

    results = {}
    for label, state in (("fresh", fresh), ("stale", stale)):
        service = PredictionService(
            ephemeris, ProviderRegistry(providers=[FakeProvider([state])])
        )
        response = await service.predict(
            observer=OBSERVER, targets=[CelestialBody.SUN],
            horizon_s=120.0, when=WHEN,
        )
        assert response.predictions, f"{label}: transito nao encontrado"
        results[label] = response.predictions[0].candidate.time_to_transit_s

    # Both describe the same physical event at WHEN+60. Without the fix the
    # stale case reports ~80 s (60 s + the 20 s of data age).
    assert abs(results["fresh"] - 60.0) < 3.0
    assert abs(results["stale"] - results["fresh"]) < 3.0


@pytest.mark.asyncio
async def test_ancient_fix_is_excluded():
    fresh = _aircraft()
    az, alt = _sightline_at(fresh, 60.0)
    ephemeris = _StubEphemeris(_body_at_sightline(az, alt))
    ancient = replace(fresh, timestamp_utc=WHEN - timedelta(seconds=120))

    service = PredictionService(
        ephemeris, ProviderRegistry(providers=[FakeProvider([ancient])])
    )
    response = await service.predict(
        observer=OBSERVER, targets=[CelestialBody.SUN], horizon_s=120.0, when=WHEN
    )
    assert response.predictions == []
    assert response.aircraft_considered == 0


# --------------------------------------------------------------------- P0.2 ---

def test_moving_body_is_tracked_by_the_search():
    """Body drifts through the aircraft's future sightline: interpolation must
    catch the rendezvous; the frozen t=0 position must not be what's used."""
    state = _aircraft()
    az60, alt60 = _sightline_at(state, 60.0)

    # Body crosses the t=60 sightline exactly at t=60 of a 120 s window,
    # drifting 0.48 deg in altitude across the window (realistic solar rate x2).
    drift = 0.24
    body_start = _body_at_sightline(az60, alt60 - drift)
    body_end = _body_at_sightline(az60, alt60 + drift)

    moving = find_transit_candidate(
        state, body_start, OBSERVER, horizon_s=120.0, body_end=body_end
    )
    frozen = find_transit_candidate(
        state, body_start, OBSERVER, horizon_s=120.0
    )

    assert moving is not None
    # The moving-body search must land on the rendezvous with tiny separation.
    assert moving.min_separation_deg < 0.05
    assert abs(moving.time_to_transit_s - 60.0) < 5.0
    # ...and report the interpolated body altitude, not the t=0 one.
    assert abs(moving.body_altitude_deg - alt60) < 0.05
    # The frozen search misses by roughly the drift — proving the fix matters.
    assert frozen is None or frozen.min_separation_deg > moving.min_separation_deg


# --------------------------------------------------------------------- P0.3 ---

def test_satellite_shadow_point_round_trips_in_ecef():
    """Placing the satellite at ground + s*u must shadow back to the ground
    point, and the recovered ray must be parallel to the body direction."""
    ground_lat, ground_lon = -22.90, -47.10
    body_az, body_alt = 310.0, 55.0

    u = az_alt_to_ecef_direction(body_az, body_alt, OBSERVER)
    g = geodetic_to_ecef(ground_lat, ground_lon, 0.0)
    s = 620_000.0  # ~ISS slant range
    sat = (g[0] + s * u[0], g[1] + s * u[1], g[2] + s * u[2])

    shadow = satellite_shadow_point(sat, u)
    assert shadow is not None
    lat, lon = shadow
    assert abs(lat - ground_lat) < 1e-5
    assert abs(lon - ground_lon) < 1e-5

    # ecef_to_geodetic self-check at satellite altitude.
    slat, slon, salt = ecef_to_geodetic(*sat)
    back = geodetic_to_ecef(slat, slon, salt)
    err = math.dist(back, sat)
    assert err < 1.0  # metres


def test_shadow_point_none_when_ray_misses_earth():
    # Body essentially at the horizon "behind" the satellite: ray skims off.
    u = az_alt_to_ecef_direction(0.0, 89.9, OBSERVER)  # body at zenith
    g = geodetic_to_ecef(OBSERVER.latitude_deg, OBSERVER.longitude_deg, 0.0)
    sat = (g[0] + 500_000.0 * u[0], g[1] + 500_000.0 * u[1], g[2] + 500_000.0 * u[2])
    # Ray direction pointing *away* from Earth center laterally
    sideways = az_alt_to_ecef_direction(0.0, -0.5, OBSERVER)
    result = satellite_shadow_point(sat, tuple(-c for c in sideways))
    assert result is None


# --------------------------------------------------------------------- P0.6 ---

@pytest.mark.asyncio
async def test_incomplete_telemetry_never_enters_the_engine():
    fresh = _aircraft()
    az, alt = _sightline_at(fresh, 60.0)
    ephemeris = _StubEphemeris(_body_at_sightline(az, alt))
    incomplete = replace(fresh, telemetry_complete=False)

    service = PredictionService(
        ephemeris, ProviderRegistry(providers=[FakeProvider([incomplete])])
    )
    response = await service.predict(
        observer=OBSERVER, targets=[CelestialBody.SUN], horizon_s=120.0, when=WHEN
    )
    assert response.predictions == []
    assert response.aircraft_considered == 0
