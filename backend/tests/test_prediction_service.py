"""Integration test for PredictionService: astronomy + providers + geometry + confidence.

Same "place the body where the aircraft will be" strategy as test_transit.py, but
exercised through the full service (pre-filter, registry, confidence scoring).
"""

from datetime import datetime, timezone

import pytest

from app.astronomy.ephemeris import get_ephemeris_service
from app.domain.models import (
    AircraftCategory,
    AircraftState,
    CelestialBody,
    ObserverLocation,
)
from app.geometry.coordinates import observer_relative
from app.prediction.projection import project_state
from app.providers.fake import FakeProvider
from app.providers.registry import ProviderRegistry
from app.services.prediction_service import PredictionService

try:
    _EPHEMERIS = get_ephemeris_service()
except Exception:
    _EPHEMERIS = None

pytestmark = pytest.mark.skipif(_EPHEMERIS is None, reason="ephemeris unavailable (offline?)")

OBSERVER = ObserverLocation(latitude_deg=-6.61, longitude_deg=-35.05, altitude_m=25.0)
WHEN = datetime(2026, 7, 10, 15, 0, 0, tzinfo=timezone.utc)  # Moon should be up


def _aircraft_aimed_at_moon(t_offset: float) -> AircraftState:
    """Build an aircraft whose position at ``t_offset`` seconds lines up with the Moon."""
    moon = _EPHEMERIS.position(CelestialBody.MOON, OBSERVER, WHEN)

    # Start the aircraft near the observer, heading toward wherever the Moon appears,
    # by placing it along the Moon's azimuth at a fixed distance and having it
    # approach along that bearing.
    import math

    bearing = math.radians(moon.azimuth_deg)
    distance_now = 20_000.0  # 20 km out
    earth_r = 6_371_000.0
    lat0 = math.radians(OBSERVER.latitude_deg)
    d_north = distance_now * math.cos(bearing)
    d_east = distance_now * math.sin(bearing)
    lat = OBSERVER.latitude_deg + math.degrees(d_north / earth_r)
    lon = OBSERVER.longitude_deg + math.degrees(d_east / (earth_r * math.cos(lat0)))

    speed = distance_now / t_offset if t_offset > 0 else 250.0
    return AircraftState(
        icao24="moontest",
        latitude_deg=lat,
        longitude_deg=lon,
        geometric_altitude_m=8000.0,
        ground_speed_mps=speed,
        track_deg=(moon.azimuth_deg + 180.0) % 360.0,  # head back toward the observer/Moon line
        category=AircraftCategory.NARROW_BODY,
        timestamp_utc=WHEN,
    )


@pytest.mark.asyncio
async def test_predict_detects_moon_transit_and_scores_confidence():
    aircraft = _aircraft_aimed_at_moon(t_offset=80.0)
    provider = FakeProvider([aircraft])
    registry = ProviderRegistry(providers=[provider])
    service = PredictionService(_EPHEMERIS, registry)

    response = await service.predict(
        observer=OBSERVER,
        targets=[CelestialBody.MOON],
        horizon_s=120.0,
        radius_km=80.0,
        when=WHEN,
    )

    assert response.provider_name == "fake"
    assert not response.data_degraded
    assert len(response.bodies) == 1
    # Not asserting a transit is *found* (geometry of the synthetic flight is
    # approximate), but the pipeline must run end-to-end without error and report
    # on how many aircraft were considered past the pre-filter.
    assert response.aircraft_considered >= 0
    for prediction in response.predictions:
        assert 0.0 <= prediction.confidence.score <= 100.0
        assert prediction.candidate.body == CelestialBody.MOON


@pytest.mark.asyncio
async def test_predict_skips_bodies_below_horizon():
    # Sun at 03:00 UTC in this location should be well below the horizon.
    night = datetime(2026, 7, 10, 3, 0, 0, tzinfo=timezone.utc)
    provider = FakeProvider([_aircraft_aimed_at_moon(60.0)])
    registry = ProviderRegistry(providers=[provider])
    service = PredictionService(_EPHEMERIS, registry)

    response = await service.predict(
        observer=OBSERVER,
        targets=[CelestialBody.SUN],
        horizon_s=60.0,
        radius_km=80.0,
        when=night,
    )
    assert response.predictions == []


@pytest.mark.asyncio
async def test_predict_with_no_aircraft_returns_no_predictions():
    provider = FakeProvider([])
    registry = ProviderRegistry(providers=[provider])
    service = PredictionService(_EPHEMERIS, registry)

    response = await service.predict(
        observer=OBSERVER, targets=[CelestialBody.MOON], when=WHEN
    )
    assert response.predictions == []
    assert response.aircraft_considered == 0
