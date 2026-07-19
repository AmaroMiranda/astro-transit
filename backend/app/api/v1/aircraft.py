"""GET /v1/aircraft/nearby (SPEC section 14)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.api.deps import get_registry
from app.api.schemas import AircraftOut, NearbyOut
from app.domain.models import ObserverLocation
from app.geometry.coordinates import observer_relative
from app.providers.registry import ProviderRegistry

router = APIRouter(prefix="/aircraft", tags=["aircraft"])


@router.get("/nearby", response_model=NearbyOut)
async def aircraft_nearby(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(80.0, gt=0, le=250),
    altitude_m: float = Query(0.0, ge=-500, le=9000),
    registry: ProviderRegistry = Depends(get_registry),
) -> NearbyOut:
    result = await registry.get_aircraft_near(latitude, longitude, radius_km)
    # The query point is the observer; add its topocentric direction to each
    # aircraft so a client (e.g. the radar) can plot it in the sky directly.
    observer = ObserverLocation(
        latitude_deg=latitude, longitude_deg=longitude, altitude_m=altitude_m
    )
    out: list[AircraftOut] = []
    for a in result.aircraft:
        topo = observer_relative(
            a.latitude_deg, a.longitude_deg, a.geometric_altitude_m, observer
        )
        out.append(
            AircraftOut(
                icao24=a.icao24,
                callsign=a.callsign,
                latitude=a.latitude_deg,
                longitude=a.longitude_deg,
                altitude_m=a.geometric_altitude_m,
                ground_speed_mps=a.ground_speed_mps,
                track_deg=a.track_deg,
                vertical_rate_mps=a.vertical_rate_mps,
                on_ground=a.on_ground,
                category=a.category.value,
                age_s=round(a.age_seconds, 1),
                azimuth_deg=round(topo.azimuth_deg, 2),
                altitude_deg=round(topo.altitude_deg, 2),
                distance_m=round(topo.range_m, 1),
            )
        )
    return NearbyOut(
        provider=result.provider_name,
        data_degraded=result.degraded,
        count=len(out),
        aircraft=out,
    )
