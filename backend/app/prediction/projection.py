"""Linear trajectory projection (RF-007).

The MVP uses a constant-velocity model: the aircraft keeps its ground speed, track
and vertical rate. Position is advanced over the local tangent plane, which is more
than accurate enough for the <=120 s horizons the SPEC targets. Later phases can
swap this out for a model that accounts for turn rate and acceleration.
"""

from __future__ import annotations

import math

from app.domain.models import AircraftState, ProjectedAircraftState

# Mean Earth radius (m) for local tangent-plane advancement.
EARTH_RADIUS_M = 6_371_000.0


def project_state(state: AircraftState, offset_seconds: float) -> ProjectedAircraftState:
    """Project ``state`` forward by ``offset_seconds`` under constant velocity."""
    distance = state.ground_speed_mps * offset_seconds
    track = math.radians(state.track_deg)

    # Displacement in the local North/East plane.
    d_north = distance * math.cos(track)
    d_east = distance * math.sin(track)

    lat = math.radians(state.latitude_deg)
    new_lat = state.latitude_deg + math.degrees(d_north / EARTH_RADIUS_M)

    # Guard against the singularity at the poles.
    cos_lat = math.cos(lat)
    if abs(cos_lat) < 1e-9:
        new_lon = state.longitude_deg
    else:
        new_lon = state.longitude_deg + math.degrees(
            d_east / (EARTH_RADIUS_M * cos_lat)
        )

    new_alt = state.geometric_altitude_m + state.vertical_rate_mps * offset_seconds

    return ProjectedAircraftState(
        icao24=state.icao24,
        latitude_deg=new_lat,
        longitude_deg=((new_lon + 180.0) % 360.0) - 180.0,
        altitude_m=new_alt,
        offset_seconds=offset_seconds,
    )
