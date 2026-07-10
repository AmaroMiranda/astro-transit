"""Sanity tests for the Skyfield-backed ephemeris service.

These require the JPL ephemeris file. If it is not cached and cannot be downloaded
(offline CI), the whole module is skipped rather than failing.
"""

from datetime import datetime, timezone

import pytest

from app.domain.models import CelestialBody, ObserverLocation

try:
    from app.astronomy.ephemeris import get_ephemeris_service

    _SERVICE = get_ephemeris_service()
except Exception as exc:  # pragma: no cover - environment dependent
    _SERVICE = None
    _REASON = str(exc)

pytestmark = pytest.mark.skipif(
    _SERVICE is None, reason="ephemeris unavailable (offline?)"
)

OBS = ObserverLocation(latitude_deg=-6.61, longitude_deg=-35.05, altitude_m=25.0)
NOON_LOCAL = datetime(2026, 7, 10, 15, 0, 0, tzinfo=timezone.utc)  # ~12:00 UTC-3


def test_sun_is_up_around_local_noon():
    sun = _SERVICE.position(CelestialBody.SUN, OBS, NOON_LOCAL)
    assert sun.altitude_deg > 30.0
    assert 0.0 <= sun.azimuth_deg < 360.0


def test_sun_apparent_radius_in_plausible_range():
    sun = _SERVICE.position(CelestialBody.SUN, OBS, NOON_LOCAL)
    # Sun's apparent radius varies ~0.262-0.271 deg over the year.
    assert 0.25 < sun.angular_radius_deg < 0.28


def test_moon_apparent_radius_in_plausible_range():
    moon = _SERVICE.position(CelestialBody.MOON, OBS, NOON_LOCAL)
    # Moon's apparent radius varies ~0.245-0.28 deg with distance.
    assert 0.24 < moon.angular_radius_deg < 0.29


def test_moon_illumination_is_a_fraction():
    moon = _SERVICE.position(CelestialBody.MOON, OBS, NOON_LOCAL)
    assert moon.illumination is not None
    assert 0.0 <= moon.illumination <= 1.0


def test_refraction_raises_altitude_near_horizon():
    # Choose a time; compare with/without refraction. Refraction never lowers altitude.
    for hour in range(0, 24, 3):
        when = datetime(2026, 7, 10, hour, 0, 0, tzinfo=timezone.utc)
        plain = _SERVICE.position(CelestialBody.SUN, OBS, when, apply_refraction=False)
        refr = _SERVICE.position(CelestialBody.SUN, OBS, when, apply_refraction=True)
        assert refr.altitude_deg >= plain.altitude_deg - 1e-6
