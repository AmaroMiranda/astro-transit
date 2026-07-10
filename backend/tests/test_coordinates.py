"""Tests for geodetic / ECEF / ENU transforms."""

import math

import pytest

from app.domain.models import ObserverLocation
from app.geometry.coordinates import (
    WGS84_A,
    ecef_to_enu,
    enu_to_az_alt_range,
    geodetic_to_ecef,
    observer_relative,
)


def test_ecef_at_equator_prime_meridian():
    x, y, z = geodetic_to_ecef(0.0, 0.0, 0.0)
    assert x == pytest.approx(WGS84_A, abs=1.0)
    assert y == pytest.approx(0.0, abs=1e-6)
    assert z == pytest.approx(0.0, abs=1e-6)


def test_ecef_at_north_pole():
    # Polar radius = a * (1 - f) ~= 6356752 m
    x, y, z = geodetic_to_ecef(90.0, 0.0, 0.0)
    assert x == pytest.approx(0.0, abs=1e-3)
    assert y == pytest.approx(0.0, abs=1e-3)
    assert z == pytest.approx(6_356_752.0, abs=2.0)


def test_object_directly_above_is_zenith():
    obs = ObserverLocation(latitude_deg=-6.61, longitude_deg=-35.05, altitude_m=25.0)
    topo = observer_relative(-6.61, -35.05, 10_025.0, obs)  # 10 km straight up
    assert topo.altitude_deg == pytest.approx(90.0, abs=0.05)
    assert topo.range_m == pytest.approx(10_000.0, abs=1.0)


def test_north_and_east_azimuths():
    obs = ObserverLocation(latitude_deg=0.0, longitude_deg=0.0, altitude_m=0.0)

    # A point slightly north, at altitude, should read azimuth ~0.
    north = observer_relative(0.5, 0.0, 5_000.0, obs)
    assert north.azimuth_deg == pytest.approx(0.0, abs=1.0)

    # A point slightly east should read azimuth ~90.
    east = observer_relative(0.0, 0.5, 5_000.0, obs)
    assert east.azimuth_deg == pytest.approx(90.0, abs=1.0)


def test_enu_of_observer_itself_is_origin():
    obs = ObserverLocation(latitude_deg=51.5, longitude_deg=-0.12, altitude_m=30.0)
    ecef = geodetic_to_ecef(51.5, -0.12, 30.0)
    e, n, u = ecef_to_enu(ecef, obs)
    assert math.sqrt(e * e + n * n + u * u) == pytest.approx(0.0, abs=1e-6)


def test_azimuth_is_normalized_0_360():
    obs = ObserverLocation(latitude_deg=10.0, longitude_deg=20.0, altitude_m=0.0)
    # A point to the south-west should give an azimuth in (180, 270).
    topo = observer_relative(9.5, 19.5, 3_000.0, obs)
    assert 180.0 < topo.azimuth_deg < 270.0
