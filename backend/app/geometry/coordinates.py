"""Geodetic / ECEF / ENU coordinate transforms (RF-008).

Flow (SPEC section RF-008):

    lat/lon/alt  ->  ECEF  ->  vector relative to observer  ->  ENU  ->  az/alt/range

All functions are pure and vectorization-friendly. WGS84 is used throughout.
"""

from __future__ import annotations

import math
from typing import Tuple

from app.domain.models import ObserverLocation, TopocentricVector

# WGS84 ellipsoid constants
WGS84_A = 6_378_137.0                     # semi-major axis (m)
WGS84_F = 1.0 / 298.257223563             # flattening
WGS84_E2 = WGS84_F * (2.0 - WGS84_F)      # first eccentricity squared

Vec3 = Tuple[float, float, float]


def geodetic_to_ecef(lat_deg: float, lon_deg: float, alt_m: float) -> Vec3:
    """Convert geodetic coordinates to Earth-Centered, Earth-Fixed (metres)."""
    lat = math.radians(lat_deg)
    lon = math.radians(lon_deg)
    sin_lat = math.sin(lat)
    cos_lat = math.cos(lat)
    n = WGS84_A / math.sqrt(1.0 - WGS84_E2 * sin_lat * sin_lat)
    x = (n + alt_m) * cos_lat * math.cos(lon)
    y = (n + alt_m) * cos_lat * math.sin(lon)
    z = (n * (1.0 - WGS84_E2) + alt_m) * sin_lat
    return (x, y, z)


def ecef_to_enu(target_ecef: Vec3, observer: ObserverLocation) -> Vec3:
    """Rotate an ECEF vector into the observer's local East/North/Up frame."""
    lat = math.radians(observer.latitude_deg)
    lon = math.radians(observer.longitude_deg)
    obs_ecef = geodetic_to_ecef(
        observer.latitude_deg, observer.longitude_deg, observer.altitude_m
    )
    dx = target_ecef[0] - obs_ecef[0]
    dy = target_ecef[1] - obs_ecef[1]
    dz = target_ecef[2] - obs_ecef[2]

    sin_lat, cos_lat = math.sin(lat), math.cos(lat)
    sin_lon, cos_lon = math.sin(lon), math.cos(lon)

    east = -sin_lon * dx + cos_lon * dy
    north = -sin_lat * cos_lon * dx - sin_lat * sin_lon * dy + cos_lat * dz
    up = cos_lat * cos_lon * dx + cos_lat * sin_lon * dy + sin_lat * dz
    return (east, north, up)


def enu_to_az_alt_range(enu: Vec3) -> TopocentricVector:
    """Convert a local ENU vector to azimuth (from North, clockwise), altitude, range."""
    east, north, up = enu
    horizontal = math.hypot(east, north)
    azimuth = math.degrees(math.atan2(east, north)) % 360.0
    altitude = math.degrees(math.atan2(up, horizontal))
    rng = math.sqrt(east * east + north * north + up * up)
    return TopocentricVector(azimuth_deg=azimuth, altitude_deg=altitude, range_m=rng)


def observer_relative(
    lat_deg: float, lon_deg: float, alt_m: float, observer: ObserverLocation
) -> TopocentricVector:
    """Full pipeline: geodetic target -> az/alt/range as seen by ``observer``."""
    ecef = geodetic_to_ecef(lat_deg, lon_deg, alt_m)
    enu = ecef_to_enu(ecef, observer)
    return enu_to_az_alt_range(enu)
