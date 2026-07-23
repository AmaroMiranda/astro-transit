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
    # Quando True, consulta TODOS os provedores em paralelo e UNE os resultados
    # por ICAO24 (o estado mais recente de cada avião vence), em vez de usar só
    # o primeiro que responde. Cada provedor agrega feeders diferentes, então a
    # união amplia a cobertura para o conjunto de todos os feeders — foi o que
    # motivou isto: um jato comercial (que sempre transmite ADS-B) foi avistado
    # sem aparecer no radar porque estava num buraco de cobertura de UM
    # provedor. Failover sequencial continua sendo o fallback se a mesclagem
    # não render nada.
    merge_providers: bool = True
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

        if not self.providers:
            return AircraftFetchResult(
                aircraft=[],
                provider_name="none",
                fetched_at_utc=datetime.now(timezone.utc),
                from_cache=False,
                degraded=True,
            )

        # 0) Merge mode: query every provider in parallel and union by ICAO24.
        if self.merge_providers and len(self.providers) > 1:
            merged = await self._merged_fetch(lat_deg, lon_deg, radius_km)
            if merged is not None:
                return self._store(
                    key, merged.aircraft, merged.provider_name,
                    degraded=merged.degraded,
                )
            # else: every provider failed — fall through to the sequential path,
            # which can still serve a stale cache before giving up.

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

    async def _merged_fetch(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> Optional[AircraftFetchResult]:
        """Consulta todos os provedores em paralelo e une por ICAO24.

        Retorna None só se TODOS falharem (o chamador então tenta o caminho
        sequencial + cache). Um provedor que falha ou estoura o timeout é
        ignorado — os que responderem ainda contribuem. Para cada avião visto
        por mais de um provedor, vence o estado com ``timestamp_utc`` mais
        recente (posição menos defasada). `degraded=True` se algum provedor
        ficou de fora, para o cliente saber que a cobertura pode estar parcial.
        """
        results = await asyncio.gather(
            *(p.get_aircraft_near(lat_deg, lon_deg, radius_km) for p in self.providers),
            return_exceptions=True,
        )
        by_icao: dict[str, AircraftState] = {}
        contributing: list[str] = []
        any_failed = False
        for provider, res in zip(self.providers, results):
            if isinstance(res, BaseException):
                any_failed = True
                continue
            contributing.append(provider.name)
            for a in res:
                prev = by_icao.get(a.icao24)
                if prev is None or a.timestamp_utc > prev.timestamp_utc:
                    by_icao[a.icao24] = a
        if not contributing:
            return None
        name = "+".join(contributing) if len(contributing) > 1 else contributing[0]
        return AircraftFetchResult(
            aircraft=list(by_icao.values()),
            provider_name=name,
            fetched_at_utc=datetime.now(timezone.utc),
            from_cache=False,
            degraded=any_failed,
        )

    def _store(
        self, key: str, aircraft: list[AircraftState], provider_name: str, degraded: bool
    ) -> AircraftFetchResult:
        fetched_at = datetime.now(timezone.utc)
        now = time.monotonic()
        self._cache[key] = _CacheEntry(
            result=aircraft,
            provider_name=provider_name,
            stored_at=now,
            fetched_at_utc=fetched_at,
        )
        # Opportunistic eviction so the cache doesn't grow unbounded across
        # distinct observer locations over a long-running process (a proper
        # Redis deployment would use TTL expiry instead — see module docstring).
        expired = [
            k for k, v in self._cache.items() if (now - v.stored_at) > self.stale_after_s
        ]
        for k in expired:
            del self._cache[k]
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
