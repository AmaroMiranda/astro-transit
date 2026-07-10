"""Tests for the geographic transit corridor estimate (RF-014)."""

import pytest

from app.domain.models import CelestialBody, CelestialPosition, ObserverLocation
from app.geometry.corridor import estimate_corridor

OBSERVER = ObserverLocation(latitude_deg=0.0, longitude_deg=0.0, altitude_m=0.0)


def _body(azimuth_deg: float, altitude_deg: float) -> CelestialPosition:
    return CelestialPosition(
        body=CelestialBody.MOON,
        azimuth_deg=azimuth_deg,
        altitude_deg=altitude_deg,
        distance_m=384_400_000.0,
        angular_radius_deg=0.259,
    )


def test_body_overhead_centers_on_aircraft_subpoint():
    body = _body(azimuth_deg=45.0, altitude_deg=90.0)
    result = estimate_corridor(
        OBSERVER,
        body,
        aircraft_lat_deg=0.1,
        aircraft_lon_deg=0.1,
        aircraft_altitude_m=10_000.0,
        aircraft_radius_deg=0.01,
        margin_deg=0.0,
    )
    # Directly overhead: horizontal offset should collapse to ~0.
    assert result.center_lat_deg == pytest.approx(0.1, abs=1e-3)
    assert result.center_lon_deg == pytest.approx(0.1, abs=1e-3)


def test_low_altitude_body_shifts_center_away_from_azimuth():
    # Body due north (az=0) and low on the horizon.
    body = _body(azimuth_deg=0.0, altitude_deg=10.0)
    result = estimate_corridor(
        OBSERVER,
        body,
        aircraft_lat_deg=0.0,
        aircraft_lon_deg=0.0,
        aircraft_altitude_m=10_000.0,
        aircraft_radius_deg=0.01,
        margin_deg=0.0,
    )
    # Central point should be south of the aircraft (away from the body's azimuth).
    assert result.center_lat_deg < 0.0


def test_higher_altitude_body_gives_smaller_offset_than_lower():
    high = estimate_corridor(
        OBSERVER,
        _body(azimuth_deg=0.0, altitude_deg=60.0),
        aircraft_lat_deg=0.0,
        aircraft_lon_deg=0.0,
        aircraft_altitude_m=10_000.0,
        aircraft_radius_deg=0.01,
        margin_deg=0.0,
    )
    low = estimate_corridor(
        OBSERVER,
        _body(azimuth_deg=0.0, altitude_deg=15.0),
        aircraft_lat_deg=0.0,
        aircraft_lon_deg=0.0,
        aircraft_altitude_m=10_000.0,
        aircraft_radius_deg=0.01,
        margin_deg=0.0,
    )
    # Lower altitude -> larger horizontal offset from the aircraft's subpoint.
    assert abs(low.center_lat_deg) > abs(high.center_lat_deg)


def test_half_width_positive_and_scales_with_tolerance():
    body = _body(azimuth_deg=90.0, altitude_deg=45.0)
    narrow = estimate_corridor(
        OBSERVER, body, 0.05, 0.05, 9_000.0, aircraft_radius_deg=0.005, margin_deg=0.0
    )
    wide = estimate_corridor(
        OBSERVER, body, 0.05, 0.05, 9_000.0, aircraft_radius_deg=0.05, margin_deg=0.0
    )
    assert narrow.half_width_m > 0
    assert wide.half_width_m > narrow.half_width_m


def test_distance_and_bearing_from_observer_are_consistent():
    body = _body(azimuth_deg=200.0, altitude_deg=30.0)
    result = estimate_corridor(
        OBSERVER, body, 0.2, 0.2, 10_000.0, aircraft_radius_deg=0.01, margin_deg=0.0
    )
    assert result.distance_from_observer_m > 0
    assert 0.0 <= result.bearing_from_observer_deg < 360.0
