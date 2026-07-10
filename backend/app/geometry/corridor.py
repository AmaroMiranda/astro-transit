"""Geographic transit corridor estimation (RF-014).

Approximates the ground swath from which a transit is visible, using the
standard "shadow line" construction used by aircraft/ISS transit calculators:
the Sun/Moon is treated as a fixed direction (valid because the corridor spans
only tens of km, negligible next to body distance — even lunar parallax shifts
by less than an arcsecond over such a span). The central line is where the
straight line from the body, through the aircraft, meets the ground; the
corridor width is the angular tolerance (body + aircraft radius + margin)
projected back to a ground distance using the aircraft's slant range.

Earth curvature is ignored over the corridor span (a few to a few dozen km),
consistent with the linear trajectory projection already used in RF-007.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from app.prediction.projection import EARTH_RADIUS_M


@dataclass(frozen=True)
class CorridorEstimate:
    """Ground footprint of a transit (RF-014)."""

    center_lat_deg: float
    center_lon_deg: float
    half_width_m: float
    distance_from_observer_m: float
    bearing_from_observer_deg: float  # direction to travel from the observer


def _destination_point(
    lat_deg: float, lon_deg: float, distance_m: float, bearing_deg: float
) -> tuple[float, float]:
    """Move ``distance_m`` from (lat, lon) along ``bearing_deg`` (great-circle)."""
    lat1 = math.radians(lat_deg)
    lon1 = math.radians(lon_deg)
    bearing = math.radians(bearing_deg)
    delta = distance_m / EARTH_RADIUS_M

    lat2 = math.asin(
        math.sin(lat1) * math.cos(delta)
        + math.cos(lat1) * math.sin(delta) * math.cos(bearing)
    )
    lon2 = lon1 + math.atan2(
        math.sin(bearing) * math.sin(delta) * math.cos(lat1),
        math.cos(delta) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), ((math.degrees(lon2) + 180.0) % 360.0) - 180.0


def _great_circle_distance_bearing(
    lat1_deg: float, lon1_deg: float, lat2_deg: float, lon2_deg: float
) -> tuple[float, float]:
    """Haversine distance (m) and initial bearing (deg) from point 1 to point 2."""
    lat1, lon1 = math.radians(lat1_deg), math.radians(lon1_deg)
    lat2, lon2 = math.radians(lat2_deg), math.radians(lon2_deg)
    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    distance = 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(a)))

    bearing = math.degrees(
        math.atan2(
            math.sin(dlon) * math.cos(lat2),
            math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon),
        )
    ) % 360.0
    return distance, bearing


def estimate_corridor(
    observer: ObserverLocation,
    body: CelestialPosition,
    aircraft_lat_deg: float,
    aircraft_lon_deg: float,
    aircraft_altitude_m: float,
    aircraft_radius_deg: float,
    margin_deg: float,
) -> CorridorEstimate:
    """Estimate the central line and half-width of the visible transit corridor.

    ``body`` supplies the azimuth/altitude used to build the body-aircraft
    shadow line; ``aircraft_*`` describe the aircraft's position at the
    instant of closest approach (already-projected geodetic coordinates).
    """
    alt_rad = math.radians(max(body.altitude_deg, 0.5))  # guard near-horizon blowup

    # Horizontal distance from the aircraft's ground sub-point to the central
    # line, moving away from the body's azimuth (see module docstring).
    horizontal_offset_m = aircraft_altitude_m / math.tan(alt_rad)
    central_bearing_deg = (body.azimuth_deg + 180.0) % 360.0

    center_lat, center_lon = _destination_point(
        aircraft_lat_deg, aircraft_lon_deg, horizontal_offset_m, central_bearing_deg
    )

    # Corridor half-width: angular tolerance projected via the aircraft's
    # slant range (not just horizontal distance — see module docstring).
    slant_range_m = aircraft_altitude_m / math.sin(alt_rad)
    tolerance_rad = math.radians(body.angular_radius_deg + aircraft_radius_deg + margin_deg)
    half_width_m = tolerance_rad * slant_range_m

    distance_m, bearing_deg = _great_circle_distance_bearing(
        observer.latitude_deg, observer.longitude_deg, center_lat, center_lon
    )

    return CorridorEstimate(
        center_lat_deg=center_lat,
        center_lon_deg=center_lon,
        half_width_m=half_width_m,
        distance_from_observer_m=distance_m,
        bearing_from_observer_deg=bearing_deg,
    )
