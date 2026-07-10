"""Provider registry with failover and short-lived cache (RF-006).

Failover order for a query (SPEC RF-006):
  1. try the primary provider (one short retry);
  2. serve a recent cached result if the primary fails;
  3. try the secondary provider;
  4. report reduced precision via :class:`AircraftFetchResult.degraded`;
  5. mark data as stale so the caller can suspend high-confidence alerts.

The cache is a tiny in-process TTL map keyed by a rounded query cell. In production
this would sit in Redis (SPEC section 12.1); the interface is the same.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from app.domain.models import AircraftState
from app.providers.base import AircraftDataProvider, ProviderError, ProviderStatus


@dataclass
class AircraftFetchResult:
    """Aircraft plus provenance so callers can be honest about data quality."""

    aircraft: list[AircraftState]
    provider_name: str
    fetched_at_utc: datetime
    from_cache: bool = False
    degraded: bool = False          # a fallback path was used
    age_seconds: float = 0.0        # age of the underlying data

    @property
    def is_stale(self) -> bool:
        return self.from_cache and self.age_seconds > 0.0


@dataclass
class _CacheEntry:
    result: list[AircraftState]
    provider_name: str
    stored_at: float
    fetched_at_utc: datetime


@dataclass
class ProviderRegistry:
    providers: list[AircraftDataProvider]
    cache_ttl_s: float = 5.0
    stale_after_s: float = 20.0
    retry_delay_s: float = 0.4
    _cache: dict[str, _CacheEntry] = field(default_factory=dict)

    @staticmethod
    def _cache_key(lat: float, lon: float, radius_km: float) -> str:
        # ~1 km cells so nearby observers share cached results.
        return f"{round(lat, 2)}:{round(lon, 2)}:{round(radius_km)}"

    async def get_aircraft_near(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> AircraftFetchResult:
        key = self._cache_key(lat_deg, lon_deg, radius_km)
        now = time.monotonic()

        # Fresh cache hit — return immediately.
        cached = self._cache.get(key)
        if cached and (now - cached.stored_at) <= self.cache_ttl_s:
            return AircraftFetchResult(
                aircraft=cached.result,
                provider_name=cached.provider_name,
                fetched_at_utc=cached.fetched_at_utc,
                from_cache=True,
                age_seconds=now - cached.stored_at,
            )

        primary, *secondaries = self.providers

        # 1) Primary with one short retry.
        for attempt in range(2):
            try:
                aircraft = await primary.get_aircraft_near(lat_deg, lon_deg, radius_km)
                return self._store(key, aircraft, primary.name, degraded=False)
            except ProviderError:
                if attempt == 0:
                    await asyncio.sleep(self.retry_delay_s)

        # 2) Stale cache beats nothing, if it is within the staleness window.
        if cached and (now - cached.stored_at) <= self.stale_after_s:
            return AircraftFetchResult(
                aircraft=cached.result,
                provider_name=cached.provider_name,
                fetched_at_utc=cached.fetched_at_utc,
                from_cache=True,
                degraded=True,
                age_seconds=now - cached.stored_at,
            )

        # 3) Secondary providers.
        for provider in secondaries:
            try:
                aircraft = await provider.get_aircraft_near(lat_deg, lon_deg, radius_km)
                return self._store(key, aircraft, provider.name, degraded=True)
            except ProviderError:
                continue

        # 4) Everything failed — surface an empty, clearly-degraded result.
        return AircraftFetchResult(
            aircraft=[],
            provider_name="none",
            fetched_at_utc=datetime.now(timezone.utc),
            from_cache=False,
            degraded=True,
        )

    def _store(
        self, key: str, aircraft: list[AircraftState], provider_name: str, degraded: bool
    ) -> AircraftFetchResult:
        fetched_at = datetime.now(timezone.utc)
        self._cache[key] = _CacheEntry(
            result=aircraft,
            provider_name=provider_name,
            stored_at=time.monotonic(),
            fetched_at_utc=fetched_at,
        )
        return AircraftFetchResult(
            aircraft=aircraft,
            provider_name=provider_name,
            fetched_at_utc=fetched_at,
            from_cache=False,
            degraded=degraded,
        )

    async def statuses(self) -> list[ProviderStatus]:
        return [await p.get_status() for p in self.providers]

    async def aclose(self) -> None:
        for p in self.providers:
            await p.aclose()
