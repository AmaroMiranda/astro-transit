"""GET /v1/aircraft/nearby (SPEC section 14)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.api.deps import get_registry
from app.api.schemas import AircraftOut, NearbyOut
from app.providers.registry import ProviderRegistry

router = APIRouter(prefix="/aircraft", tags=["aircraft"])


@router.get("/nearby", response_model=NearbyOut)
async def aircraft_nearby(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(80.0, gt=0, le=250),
    registry: ProviderRegistry = Depends(get_registry),
) -> NearbyOut:
    result = await registry.get_aircraft_near(latitude, longitude, radius_km)
    return NearbyOut(
        provider=result.provider_name,
        data_degraded=result.degraded,
        count=len(result.aircraft),
        aircraft=[
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
            )
            for a in result.aircraft
        ],
    )
