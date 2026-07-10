"""Provider abstraction (RF-005).

The domain must not depend on a single aeronautical API (SPEC section 24). Every
provider implements the same async interface and returns **normalized**
:class:`AircraftState` objects so the prediction engine is provider-agnostic.
"""

from __future__ import annotations

import math
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from app.domain.models import AircraftState


class ProviderError(RuntimeError):
    """Raised when a provider request fails, so the registry can fail over (RF-006)."""


@dataclass(frozen=True)
class BoundingBox:
    """Lat/lon window around the observer used to constrain provider queries."""

    lat_min: float
    lat_max: float
    lon_min: float
    lon_max: float

    @classmethod
    def around(cls, lat_deg: float, lon_deg: float, radius_km: float) -> "BoundingBox":
        """A square bounding box that comfortably contains ``radius_km``."""
        dlat = radius_km / 111.0
        cos_lat = max(math.cos(math.radians(lat_deg)), 1e-6)
        dlon = radius_km / (111.0 * cos_lat)
        return cls(lat_deg - dlat, lat_deg + dlat, lon_deg - dlon, lon_deg + dlon)


@dataclass(frozen=True)
class ProviderStatus:
    """Health snapshot for a provider (RF-005 getProviderStatus, RF-016 inputs)."""

    name: str
    healthy: bool
    last_update_utc: Optional[datetime]
    latency_ms: Optional[float]
    aircraft_count: Optional[int] = None
    detail: str = ""

    @property
    def age_seconds(self) -> Optional[float]:
        if self.last_update_utc is None:
            return None
        return (datetime.now(timezone.utc) - self.last_update_utc).total_seconds()


class AircraftDataProvider(ABC):
    """Common interface every aircraft source must implement (RF-005)."""

    name: str = "base"

    @abstractmethod
    async def get_aircraft_near(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> list[AircraftState]:
        """Return normalized aircraft states within ``radius_km`` of the point."""

    @abstractmethod
    async def get_status(self) -> ProviderStatus:
        """Return a health snapshot for failover decisions (RF-006)."""

    async def aclose(self) -> None:  # pragma: no cover - optional hook
        """Release any held resources (HTTP clients, etc.)."""
        return None
