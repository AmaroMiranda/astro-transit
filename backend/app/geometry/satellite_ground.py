"""Satellite transit ground track: exact ray-ellipsoid geometry (RF-014 for satellites).

The aircraft corridor (:mod:`app.geometry.corridor`) linearizes over a local tangent
plane — valid for objects a few km up, whose shadow lands a few km away. A satellite
at 400+ km breaks every assumption of that construction: the shadow line from the
body through the satellite meets the Earth far from the sub-satellite point, and
Earth curvature dominates. Here the central point is computed exactly:

    ground = first intersection of the ray  p(s) = sat_ecef - s * u   (s > 0)
             with the WGS84 ellipsoid,

where ``u`` is the unit vector pointing *toward* the body (so ``-u`` is the direction
sunlight/moonlight travels). Everything is done in ECEF; the result is converted back
to geodetic coordinates with Bowring's method.

The body direction is taken at the observer; over the few-hundred-km span involved
the Sun's direction is constant to <0.001 deg and the Moon's to <0.1 deg (parallax),
both far below the corridor's own width.
"""

from __future__ import annotations

import math
from typing import Optional, Tuple

from app.domain.models import ObserverLocation
from app.geometry.coordinates import WGS84_A, WGS84_E2

Vec3 = Tuple[float, float, float]

_WGS84_B = WGS84_A * math.sqrt(1.0 - WGS84_E2)          # semi-minor axis (m)
_EP2 = (WGS84_A * WGS84_A - _WGS84_B * _WGS84_B) / (_WGS84_B * _WGS84_B)


def ecef_to_geodetic(x: float, y: float, z: float) -> Tuple[float, float, float]:
    """ECEF (m) -> geodetic lat/lon (deg) and height (m), Bowring's method.

    Non-iterative; accurate to well under a metre for near-Earth points, which is
    orders of magnitude below the corridor width this feeds.
    """
    lon = math.atan2(y, x)
    p = math.hypot(x, y)
    if p < 1e-9:  # polar axis
        lat = math.copysign(math.pi / 2.0, z)
        return math.degrees(lat), math.degrees(lon), abs(z) - _WGS84_B
    theta = math.atan2(z * WGS84_A, p * _WGS84_B)
    st, ct = math.sin(theta), math.cos(theta)
    lat = math.atan2(z + _EP2 * _WGS84_B * st**3, p - WGS84_E2 * WGS84_A * ct**3)
    sin_lat = math.sin(lat)
    n = WGS84_A / math.sqrt(1.0 - WGS84_E2 * sin_lat * sin_lat)
    alt = p / math.cos(lat) - n
    return math.degrees(lat), math.degrees(lon), alt


def az_alt_to_ecef_direction(
    azimuth_deg: float, altitude_deg: float, observer: ObserverLocation
) -> Vec3:
    """Unit ECEF vector of the direction seen from ``observer`` at az/alt.

    Inverse rotation of :func:`app.geometry.coordinates.ecef_to_enu` (the ENU
    basis vectors expressed in ECEF).
    """
    az = math.radians(azimuth_deg)
    alt = math.radians(altitude_deg)
    e = math.cos(alt) * math.sin(az)
    n = math.cos(alt) * math.cos(az)
    u = math.sin(alt)

    lat = math.radians(observer.latitude_deg)
    lon = math.radians(observer.longitude_deg)
    sin_lat, cos_lat = math.sin(lat), math.cos(lat)
    sin_lon, cos_lon = math.sin(lon), math.cos(lon)

    x = -sin_lon * e - sin_lat * cos_lon * n + cos_lat * cos_lon * u
    y = cos_lon * e - sin_lat * sin_lon * n + cos_lat * sin_lon * u
    z = cos_lat * n + sin_lat * u
    return (x, y, z)


def satellite_shadow_point(
    sat_ecef: Vec3, body_dir_ecef: Vec3
) -> Optional[Tuple[float, float]]:
    """Ground point where the body-satellite line meets the WGS84 ellipsoid.

    ``body_dir_ecef`` must point from the ground *toward* the body. Returns
    ``(lat_deg, lon_deg)`` of the first intersection below the satellite, or
    ``None`` when the ray misses the Earth (body too low / grazing geometry).
    """
    # Scale space so the ellipsoid becomes the unit sphere.
    wx, wy, wz = sat_ecef[0] / WGS84_A, sat_ecef[1] / WGS84_A, sat_ecef[2] / _WGS84_B
    dx, dy, dz = (
        body_dir_ecef[0] / WGS84_A,
        body_dir_ecef[1] / WGS84_A,
        body_dir_ecef[2] / _WGS84_B,
    )
    # |w - s d|^2 = 1  ->  (d.d) s^2 - 2 (w.d) s + (w.w - 1) = 0
    dd = dx * dx + dy * dy + dz * dz
    wd = wx * dx + wy * dy + wz * dz
    ww = wx * wx + wy * wy + wz * wz
    disc = wd * wd - dd * (ww - 1.0)
    if disc < 0.0 or dd <= 0.0:
        return None
    sqrt_disc = math.sqrt(disc)
    # Smallest positive root = first surface hit walking down-ray from the satellite.
    s = (wd - sqrt_disc) / dd
    if s <= 0.0:
        return None
    gx = sat_ecef[0] - s * body_dir_ecef[0]
    gy = sat_ecef[1] - s * body_dir_ecef[1]
    gz = sat_ecef[2] - s * body_dir_ecef[2]
    lat, lon, _ = ecef_to_geodetic(gx, gy, gz)
    return (lat, lon)
