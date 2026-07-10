"""In-memory provider for tests, demos and the offline development mode (RF-030)."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from app.domain.models import AircraftState
from app.providers.base import AircraftDataProvider, ProviderStatus


class FakeProvider(AircraftDataProvider):
    """Serves a fixed list of aircraft; never touches the network."""

    name = "fake"

    def __init__(self, aircraft: Optional[list[AircraftState]] = None, healthy: bool = True):
        self._aircraft = aircraft or []
        self._healthy = healthy

    def set_aircraft(self, aircraft: list[AircraftState]) -> None:
        self._aircraft = aircraft

    async def get_aircraft_near(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> list[AircraftState]:
        if not self._healthy:
            from app.providers.base import ProviderError

            raise ProviderError("fake provider is unhealthy")
        return list(self._aircraft)

    async def get_status(self) -> ProviderStatus:
        return ProviderStatus(
            name=self.name,
            healthy=self._healthy,
            last_update_utc=datetime.now(timezone.utc),
            latency_ms=0.0,
            aircraft_count=len(self._aircraft),
        )
