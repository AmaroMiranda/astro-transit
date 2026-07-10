"""Tests for constant-velocity trajectory projection."""

import pytest

from app.domain.models import AircraftState
from app.prediction.projection import EARTH_RADIUS_M, project_state


def _state(**kwargs) -> AircraftState:
    base = dict(
        icao24="abc123",
        latitude_deg=0.0,
        longitude_deg=0.0,
        geometric_altitude_m=10_000.0,
        ground_speed_mps=250.0,
        track_deg=0.0,
    )
    base.update(kwargs)
    return AircraftState(**base)


def test_zero_offset_returns_same_position():
    s = _state()
    p = project_state(s, 0.0)
    assert p.latitude_deg == pytest.approx(0.0)
    assert p.longitude_deg == pytest.approx(0.0)
    assert p.altitude_m == pytest.approx(10_000.0)


def test_northbound_moves_latitude_up():
    s = _state(track_deg=0.0, ground_speed_mps=250.0)
    p = project_state(s, 60.0)  # 15 km north
    assert p.latitude_deg > 0.0
    assert p.longitude_deg == pytest.approx(0.0, abs=1e-9)
    # 15 km / earth radius, in degrees
    import math
    expected = math.degrees(15_000.0 / EARTH_RADIUS_M)
    assert p.latitude_deg == pytest.approx(expected, rel=1e-6)


def test_eastbound_moves_longitude_up():
    s = _state(track_deg=90.0)
    p = project_state(s, 40.0)
    assert p.longitude_deg > 0.0
    assert p.latitude_deg == pytest.approx(0.0, abs=1e-9)


def test_climb_increases_altitude():
    s = _state(vertical_rate_mps=10.0)
    p = project_state(s, 30.0)
    assert p.altitude_m == pytest.approx(10_300.0)


def test_descent_decreases_altitude():
    s = _state(vertical_rate_mps=-8.0)
    p = project_state(s, 15.0)
    assert p.altitude_m == pytest.approx(9_880.0)


def test_longitude_wraps_into_range():
    s = _state(longitude_deg=179.99, track_deg=90.0, ground_speed_mps=300.0)
    p = project_state(s, 120.0)
    assert -180.0 <= p.longitude_deg <= 180.0
