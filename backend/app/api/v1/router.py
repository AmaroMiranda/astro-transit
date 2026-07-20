"""Aggregates all v1 routers."""

from fastapi import APIRouter

from app.api.v1 import aircraft, astronomy, satellites, transits

api_router = APIRouter(prefix="/v1")
api_router.include_router(astronomy.router)
api_router.include_router(aircraft.router)
api_router.include_router(transits.router)
api_router.include_router(satellites.router)
