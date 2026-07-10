"""Unit conversions shared by the aircraft providers.

ADS-B feeds report mixed units (knots, feet, feet/min); the domain works in SI.
"""

KNOTS_TO_MPS = 0.514444
FEET_TO_M = 0.3048
FPM_TO_MPS = 0.3048 / 60.0  # feet per minute -> metres per second


def knots_to_mps(v):
    return None if v is None else float(v) * KNOTS_TO_MPS


def feet_to_m(v):
    return None if v is None else float(v) * FEET_TO_M


def fpm_to_mps(v):
    return None if v is None else float(v) * FPM_TO_MPS
