"""Tests for angular separation and apparent size calculations."""

import math

import pytest

from app.geometry.angles import (
    MOON_RADIUS_M,
    SUN_RADIUS_M,
    angular_separation_deg,
    angular_size_deg,
    apparent_radius_deg,
    az_alt_to_unit_vector,
)


def test_unit_vector_is_unit_length():
    for az, alt in [(0, 0), (90, 30), (215, -10), (359, 89)]:
        v = az_alt_to_unit_vector(az, alt)
        assert math.sqrt(sum(c * c for c in v)) == pytest.approx(1.0, abs=1e-12)


def test_separation_identical_directions_is_zero():
    assert angular_separation_deg(120.0, 45.0, 120.0, 45.0) == pytest.approx(0.0, abs=1e-9)


def test_separation_opposite_directions_is_180():
    assert angular_separation_deg(0.0, 0.0, 180.0, 0.0) == pytest.approx(180.0, abs=1e-6)


def test_separation_ninety_degrees():
    # North horizon vs zenith = 90 deg.
    assert angular_separation_deg(0.0, 0.0, 0.0, 90.0) == pytest.approx(90.0, abs=1e-6)


def test_separation_small_azimuth_step():
    # 1 deg apart in azimuth on the horizon -> ~1 deg separation.
    assert angular_separation_deg(100.0, 0.0, 101.0, 0.0) == pytest.approx(1.0, abs=1e-6)


def test_sun_apparent_radius_about_quarter_degree():
    # 1 AU ~= 1.496e11 m; Sun's apparent radius ~0.2666 deg.
    au = 1.496e11
    r = apparent_radius_deg(SUN_RADIUS_M, au)
    assert r == pytest.approx(0.2666, abs=0.01)


def test_moon_apparent_radius_about_quarter_degree():
    # Mean Earth-Moon distance ~384400 km; apparent radius ~0.259 deg.
    r = apparent_radius_deg(MOON_RADIUS_M, 384_400_000.0)
    assert r == pytest.approx(0.259, abs=0.01)


def test_apparent_radius_rejects_nonpositive_distance():
    with pytest.raises(ValueError):
        apparent_radius_deg(MOON_RADIUS_M, 0.0)


def test_aircraft_angular_size_narrowbody():
    # A 35 m wingspan at 10 km -> ~0.2 deg.
    size = angular_size_deg(35.0, 10_000.0)
    assert size == pytest.approx(math.degrees(2 * math.atan(35 / 20000)), abs=1e-9)
    assert size == pytest.approx(0.2005, abs=0.01)


def test_angular_size_shrinks_with_distance():
    near = angular_size_deg(60.0, 5_000.0)
    far = angular_size_deg(60.0, 50_000.0)
    assert near > far
