"""Angular geometry: unit vectors, separation, apparent radii/sizes.

Implements RF-009 (angular separation), RF-010 (apparent radius of the body) and
RF-011 (apparent angular size of the aircraft).
"""

from __future__ import annotations

import math
from typing import Tuple

Vec3 = Tuple[float, float, float]

# Physical radii used for the apparent-radius calculation (RF-010).
SUN_RADIUS_M = 6.957e8
MOON_RADIUS_M = 1.7374e6


def az_alt_to_unit_vector(azimuth_deg: float, altitude_deg: float) -> Vec3:
    """Unit vector in the observer's ENU frame for a given azimuth/altitude.

    x = East, y = North, z = Up. Azimuth is measured from North, clockwise.
    """
    az = math.radians(azimuth_deg)
    alt = math.radians(altitude_deg)
    cos_alt = math.cos(alt)
    east = cos_alt * math.sin(az)
    north = cos_alt * math.cos(az)
    up = math.sin(alt)
    return (east, north, up)


def angular_separation_deg(
    az1_deg: float, alt1_deg: float, az2_deg: float, alt2_deg: float
) -> float:
    """Great-circle angular separation between two directions (RF-009).

    Uses ``theta = arccos(clamp(A . B, -1, 1))`` on the unit vectors, matching the
    SPEC. Robust for the small separations that matter for transits.
    """
    a = az_alt_to_unit_vector(az1_deg, alt1_deg)
    b = az_alt_to_unit_vector(az2_deg, alt2_deg)
    dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    dot = max(-1.0, min(1.0, dot))
    return math.degrees(math.acos(dot))


def apparent_radius_deg(physical_radius_m: float, distance_m: float) -> float:
    """Apparent angular radius of a sphere of ``physical_radius_m`` at ``distance_m``.

    Uses ``arcsin`` (exact for a sphere). ``distance_m`` is measured to the centre.
    """
    if distance_m <= 0.0:
        raise ValueError("distance_m must be positive")
    ratio = physical_radius_m / distance_m
    ratio = max(-1.0, min(1.0, ratio))
    return math.degrees(math.asin(ratio))


def angular_size_deg(physical_size_m: float, distance_m: float) -> float:
    """Apparent full angular size of an object of ``physical_size_m`` (RF-011).

    ``size ~= 2 * atan(realSize / (2 * distance))``.
    """
    if distance_m <= 0.0:
        raise ValueError("distance_m must be positive")
    return math.degrees(2.0 * math.atan(physical_size_m / (2.0 * distance_m)))
