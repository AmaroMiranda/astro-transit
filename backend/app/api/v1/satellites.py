"""GET /v1/satellites/passes — multi-day ISS/Tiangong transit planning.

Unlike aircraft (ADS-B, minutes of predictability), satellite transits are
deterministic: this endpoint scans the next N hours (default 48) and returns
every Sun/Moon crossing visible from the given point.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Query, Request

from app.api.schemas import SatellitePassesOut, SatellitePassOut
from app.domain.models import ObserverLocation
from app.services.passes_service import PassesService

router = APIRouter(prefix="/satellites", tags=["satellites"])


def get_passes_service(request: Request) -> Optional[PassesService]:
    return getattr(request.app.state, "passes_service", None)


@router.get("/passes", response_model=SatellitePassesOut)
async def satellite_passes(
    request: Request,
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    altitude_m: float = Query(0.0, ge=-500, le=9000),
    hours: float = Query(48.0, ge=1, le=72),
    max_distance_km: float = Query(30.0, ge=0, le=100),
) -> SatellitePassesOut:
    service = get_passes_service(request)
    now = datetime.now(timezone.utc)
    if service is None:
        return SatellitePassesOut(
            generated_at_utc=now, hours=hours, count=0, passes=[]
        )
    observer = ObserverLocation(
        latitude_deg=latitude, longitude_deg=longitude, altitude_m=altitude_m
    )
    passes = await service.upcoming(
        observer, hours=hours, max_center_distance_km=max_distance_km
    )
    return SatellitePassesOut(
        generated_at_utc=now,
        hours=hours,
        count=len(passes),
        passes=[SatellitePassOut.of(p) for p in passes],
    )
