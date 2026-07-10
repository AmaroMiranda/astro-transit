"""GET /v1/astronomy/position (SPEC section 14)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query

from app.api.deps import get_ephemeris
from app.api.schemas import CelestialPositionOut
from app.astronomy.ephemeris import EphemerisService
from app.domain.models import CelestialBody, ObserverLocation

router = APIRouter(prefix="/astronomy", tags=["astronomy"])


@router.get("/position", response_model=CelestialPositionOut)
async def astronomy_position(
    latitude: float = Query(..., ge=-90, le=90),
    longitude: float = Query(..., ge=-180, le=180),
    target: CelestialBody = Query(CelestialBody.MOON),
    altitude_m: float = 0.0,
    timestamp: Optional[datetime] = None,
    refraction: bool = False,
    ephemeris: EphemerisService = Depends(get_ephemeris),
) -> CelestialPositionOut:
    observer = ObserverLocation(
        latitude_deg=latitude, longitude_deg=longitude, altitude_m=altitude_m
    )
    when = timestamp or datetime.now(timezone.utc)
    position = ephemeris.position(target, observer, when, apply_refraction=refraction)
    return CelestialPositionOut.of(position)
