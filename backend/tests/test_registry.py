"""Tests for the provider registry: caching and failover (RF-006)."""

import asyncio

import pytest

from app.domain.models import AircraftState
from app.providers.base import ProviderError, ProviderStatus
from app.providers.fake import FakeProvider
from app.providers.registry import ProviderRegistry


def _ac(icao="abc123") -> AircraftState:
    return AircraftState(
        icao24=icao,
        latitude_deg=1.0,
        longitude_deg=2.0,
        geometric_altitude_m=10_000.0,
        ground_speed_mps=200.0,
        track_deg=90.0,
    )


class FlakyProvider(FakeProvider):
    """Fails the first N calls, then succeeds."""

    def __init__(self, fail_times: int, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._fail_times = fail_times
        self._calls = 0

    async def get_aircraft_near(self, lat_deg, lon_deg, radius_km):
        self._calls += 1
        if self._calls <= self._fail_times:
            raise ProviderError("simulated failure")
        return await super().get_aircraft_near(lat_deg, lon_deg, radius_km)


@pytest.mark.asyncio
async def test_primary_success_is_not_degraded():
    primary = FakeProvider([_ac()])
    registry = ProviderRegistry(providers=[primary])
    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert not result.degraded
    assert not result.from_cache
    assert result.provider_name == "fake"
    assert len(result.aircraft) == 1


@pytest.mark.asyncio
async def test_cache_hit_within_ttl():
    primary = FakeProvider([_ac()])
    registry = ProviderRegistry(providers=[primary], cache_ttl_s=60.0)
    first = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert not first.from_cache

    # Change underlying data; cached response should still be served.
    primary.set_aircraft([_ac("changed")])
    second = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert second.from_cache
    assert second.aircraft[0].icao24 == "abc123"


@pytest.mark.asyncio
async def test_retry_recovers_primary_without_secondary():
    primary = FlakyProvider(fail_times=1, aircraft=[_ac()])
    registry = ProviderRegistry(providers=[primary], retry_delay_s=0.01)
    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert not result.degraded
    assert result.provider_name == "fake"


@pytest.mark.asyncio
async def test_falls_back_to_secondary_when_primary_fails():
    # Caminho SEQUENCIAL (merge desligado): quando o primário falha, o
    # secundário assume. Fixado em merge_providers=False de propósito — este
    # teste exercita o fallback, que continua existindo por baixo da mesclagem.
    primary = FakeProvider([], healthy=False)
    secondary = FakeProvider([_ac("secondary_ac")])
    secondary.name = "secondary"
    registry = ProviderRegistry(
        providers=[primary, secondary], retry_delay_s=0.01, merge_providers=False
    )

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.degraded
    assert result.provider_name == "secondary"
    assert result.aircraft[0].icao24 == "secondary_ac"


@pytest.mark.asyncio
async def test_stale_cache_used_before_secondary_within_window():
    # Também um contrato do caminho sequencial (cache velho antes do
    # secundário). Com a mesclagem LIGADA o comportamento é melhor — dado
    # fresco do secundário em vez de cache velho —, coberto por
    # test_merge_serves_fresh_secondary_instead_of_stale_cache abaixo.
    primary = FakeProvider([_ac()])
    secondary = FakeProvider([_ac("should_not_be_used")])
    registry = ProviderRegistry(
        providers=[primary, secondary], cache_ttl_s=0.0, stale_after_s=60.0,
        retry_delay_s=0.01, merge_providers=False,
    )
    first = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert first.provider_name == "fake"

    await asyncio.sleep(0.02)  # ensure monotonic clock registers elapsed time
    primary._healthy = False
    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.from_cache
    assert result.degraded
    assert result.aircraft[0].icao24 == "abc123"


@pytest.mark.asyncio
async def test_all_providers_failing_returns_empty_degraded_result():
    primary = FakeProvider([], healthy=False)
    secondary = FakeProvider([], healthy=False)
    registry = ProviderRegistry(providers=[primary, secondary], retry_delay_s=0.01)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.degraded
    assert result.aircraft == []
    assert result.provider_name == "none"


@pytest.mark.asyncio
async def test_statuses_reports_all_providers():
    primary = FakeProvider([_ac()])
    secondary = FakeProvider([])
    secondary.name = "secondary"
    registry = ProviderRegistry(providers=[primary, secondary])

    statuses = await registry.statuses()
    assert {s.name for s in statuses} == {"fake", "secondary"}
    assert all(isinstance(s, ProviderStatus) for s in statuses)


@pytest.mark.asyncio
async def test_empty_provider_list_returns_degraded_empty_result_without_crashing():
    registry = ProviderRegistry(providers=[])
    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.aircraft == []
    assert result.degraded
    assert result.provider_name == "none"


@pytest.mark.asyncio
async def test_cache_does_not_grow_unbounded_across_distinct_locations():
    primary = FakeProvider([_ac()])
    registry = ProviderRegistry(providers=[primary], cache_ttl_s=0.0, stale_after_s=0.01)

    for i in range(20):
        await registry.get_aircraft_near(float(i), float(i), 50.0)
        await asyncio.sleep(0.02)

    # Every earlier entry should have expired past stale_after_s by the time
    # later ones are stored, so the cache shouldn't accumulate all 20 keys.
    assert len(registry._cache) < 20


# --- Mesclagem de provedores (cobertura pela união dos feeders) --------------

from datetime import datetime, timedelta, timezone  # noqa: E402


def _ac_at(icao: str, ts: datetime, lat: float = 1.0) -> AircraftState:
    return AircraftState(
        icao24=icao,
        latitude_deg=lat,
        longitude_deg=2.0,
        geometric_altitude_m=10_000.0,
        ground_speed_mps=200.0,
        track_deg=90.0,
        timestamp_utc=ts,
    )


@pytest.mark.asyncio
async def test_merge_unions_aircraft_from_all_providers():
    # O ponto central da feature: cada provedor vê aviões diferentes, e a
    # mesclagem entrega a UNIÃO — o avião que só o provedor B captou (o buraco
    # de cobertura que motivou tudo) passa a aparecer.
    a = FakeProvider([_ac("only_in_a")])
    a.name = "a"
    b = FakeProvider([_ac("only_in_b")])
    b.name = "b"
    registry = ProviderRegistry(providers=[a, b], cache_ttl_s=0.0)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    icaos = {ac.icao24 for ac in result.aircraft}
    assert icaos == {"only_in_a", "only_in_b"}
    assert not result.degraded  # os dois responderam
    assert "a" in result.provider_name and "b" in result.provider_name


@pytest.mark.asyncio
async def test_merge_keeps_the_most_recent_state_for_a_shared_aircraft():
    # Mesmo avião em dois provedores: vence o timestamp mais novo (posição
    # menos defasada).
    old = datetime.now(timezone.utc) - timedelta(seconds=30)
    new = datetime.now(timezone.utc)
    stale = FakeProvider([_ac_at("shared", old, lat=1.0)])
    stale.name = "stale"
    fresh = FakeProvider([_ac_at("shared", new, lat=9.0)])
    fresh.name = "fresh"
    registry = ProviderRegistry(providers=[stale, fresh], cache_ttl_s=0.0)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert len(result.aircraft) == 1
    assert result.aircraft[0].latitude_deg == 9.0  # o estado fresco


@pytest.mark.asyncio
async def test_merge_tolerates_one_provider_failing():
    good = FakeProvider([_ac("from_good")])
    good.name = "good"
    bad = FakeProvider([], healthy=False)
    bad.name = "bad"
    registry = ProviderRegistry(providers=[good, bad], cache_ttl_s=0.0)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert {ac.icao24 for ac in result.aircraft} == {"from_good"}
    assert result.degraded  # um provedor ficou de fora → cobertura parcial
    assert result.provider_name == "good"


@pytest.mark.asyncio
async def test_merge_all_failing_falls_through_to_sequential_then_empty():
    a = FakeProvider([], healthy=False)
    b = FakeProvider([], healthy=False)
    registry = ProviderRegistry(providers=[a, b], cache_ttl_s=0.0, retry_delay_s=0.01)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.aircraft == []
    assert result.degraded
