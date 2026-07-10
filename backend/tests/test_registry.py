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
    primary = FakeProvider([], healthy=False)
    secondary = FakeProvider([_ac("secondary_ac")])
    secondary.name = "secondary"
    registry = ProviderRegistry(providers=[primary, secondary], retry_delay_s=0.01)

    result = await registry.get_aircraft_near(0.0, 0.0, 50.0)
    assert result.degraded
    assert result.provider_name == "secondary"
    assert result.aircraft[0].icao24 == "secondary_ac"


@pytest.mark.asyncio
async def test_stale_cache_used_before_secondary_within_window():
    primary = FakeProvider([_ac()])
    secondary = FakeProvider([_ac("should_not_be_used")])
    registry = ProviderRegistry(
        providers=[primary, secondary], cache_ttl_s=0.0, stale_after_s=60.0, retry_delay_s=0.01
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
