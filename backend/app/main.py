"""FastAPI application entrypoint.

Heavy singletons (ephemeris with its local JPL data, HTTP-backed aircraft providers,
the provider registry and the prediction service) are created once at startup and
attached to ``app.state`` — see SPEC section 8.4 (backend responsibilities: protect
keys, normalize APIs, share cache, execute heavy calculations).
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.astronomy.ephemeris import EphemerisService
from app.astronomy.satellites import SatelliteCatalog
from app.core.config import get_settings
from app.providers.adsbfi import AdsbFiProvider
from app.providers.adsblol import AdsbLolProvider
from app.providers.airplaneslive import AirplanesLiveProvider
from app.providers.base import AircraftDataProvider
from app.providers.opensky import OpenSkyProvider
from app.providers.registry import ProviderRegistry
from app.services.prediction_service import PredictionService

_PROVIDER_FACTORIES = {
    "airplaneslive": lambda s: AirplanesLiveProvider(timeout_s=s.provider_timeout_s),
    "adsbfi": lambda s: AdsbFiProvider(timeout_s=s.provider_timeout_s),
    "adsblol": lambda s: AdsbLolProvider(timeout_s=s.provider_timeout_s),
    "opensky": lambda s: OpenSkyProvider(
        timeout_s=s.provider_timeout_s,
        client_id=s.opensky_client_id,
        client_secret=s.opensky_client_secret,
    ),
}


def _build_providers(settings) -> list[AircraftDataProvider]:
    providers = []
    for name in settings.aircraft_providers:
        factory = _PROVIDER_FACTORIES.get(name)
        if factory is not None:
            providers.append(factory(settings))
    return providers


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()

    app.state.ephemeris = EphemerisService()
    providers = _build_providers(settings)
    app.state.registry = ProviderRegistry(
        providers=providers,
        cache_ttl_s=settings.cache_ttl_s,
        stale_after_s=settings.stale_after_s,
    )

    app.state.satellites = None
    if settings.satellites_enabled and settings.satellite_norad_ids:
        app.state.satellites = SatelliteCatalog(
            timescale=app.state.ephemeris.timescale,
            norad_ids=settings.satellite_norad_ids,
            source_url=settings.tle_source_url,
            cache_ttl_s=settings.tle_cache_hours * 3600.0,
        )

    app.state.prediction_service = PredictionService(
        app.state.ephemeris, app.state.registry, satellite_catalog=app.state.satellites
    )

    yield

    await app.state.registry.aclose()
    if app.state.satellites is not None:
        await app.state.satellites.aclose()


app = FastAPI(
    title="AstroTransit API",
    version="0.1.0",
    description="Previsão de trânsitos de aeronaves diante do Sol e da Lua.",
    lifespan=lifespan,
)

# Flutter clients talk to this API over HTTPS from mobile networks; no cookies/auth
# are exchanged yet, so a permissive CORS policy is acceptable for the MVP.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/health", tags=["meta"])
async def health() -> dict:
    return {"status": "ok"}
