"""Dependency wiring for the API.

Heavy singletons (ephemeris, provider registry, prediction service) live on
``app.state`` and are created once during startup (see :mod:`app.main`).
"""

from __future__ import annotations

from fastapi import Request

from app.astronomy.ephemeris import EphemerisService
from app.providers.registry import ProviderRegistry
from app.services.prediction_service import PredictionService


def get_ephemeris(request: Request) -> EphemerisService:
    return request.app.state.ephemeris


def get_registry(request: Request) -> ProviderRegistry:
    return request.app.state.registry


def get_prediction_service(request: Request) -> PredictionService:
    return request.app.state.prediction_service
