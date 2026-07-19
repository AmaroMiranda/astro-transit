"""Normalization + URL-shape tests for the readsb-family ADS-B providers.

Each provider shares one normalization path (:mod:`app.providers.readsb`) but differs
in endpoint shape and the JSON key that holds the aircraft array. A mocked transport
lets us assert both without touching the network.
"""

from __future__ import annotations

import httpx
import pytest

from app.providers.adsbfi import AdsbFiProvider
from app.providers.adsblol import AdsbLolProvider
from app.providers.airplaneslive import AirplanesLiveProvider
from app.domain.models import AircraftCategory

_SAMPLE_AC = {
    "hex": "E48DF6",
    "flight": "GLO1234 ",
    "lat": -23.5,
    "lon": -46.6,
    "alt_geom": 35000,
    "gs": 450.0,
    "track": 270.0,
    "geom_rate": -640,
    "category": "A3",
    "seen_pos": 1.2,
}


def _client_returning(payload: dict, captured: list[str]) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        captured.append(str(request.url))
        return httpx.Response(200, json=payload)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


@pytest.mark.asyncio
async def test_airplaneslive_normalizes_ac_key_and_point_url():
    captured: list[str] = []
    client = _client_returning({"ac": [_SAMPLE_AC]}, captured)
    provider = AirplanesLiveProvider(client=client)

    states = await provider.get_aircraft_near(-23.5, -46.6, 80.0)

    assert len(states) == 1
    ac = states[0]
    assert ac.icao24 == "e48df6"
    assert ac.callsign == "GLO1234"
    assert ac.category == AircraftCategory.NARROW_BODY
    assert ac.geometric_altitude_m == pytest.approx(35000 * 0.3048, rel=1e-6)
    assert ac.ground_speed_mps == pytest.approx(450.0 * 0.514444, rel=1e-6)
    # point/{lat}/{lon}/{radius_nm}; 80 km -> 43 nm
    assert "/point/-23.5/-46.6/43" in captured[0]
    await client.aclose()


@pytest.mark.asyncio
async def test_adsbfi_reads_aircraft_key_and_latlon_url():
    captured: list[str] = []
    client = _client_returning({"aircraft": [_SAMPLE_AC]}, captured)
    provider = AdsbFiProvider(client=client)

    states = await provider.get_aircraft_near(-23.5, -46.6, 80.0)

    assert len(states) == 1
    assert states[0].icao24 == "e48df6"
    assert "/lat/-23.5/lon/-46.6/dist/43" in captured[0]
    await client.aclose()


@pytest.mark.asyncio
async def test_adsblol_still_reads_ac_key():
    captured: list[str] = []
    client = _client_returning({"ac": [_SAMPLE_AC]}, captured)
    provider = AdsbLolProvider(client=client)

    states = await provider.get_aircraft_near(-23.5, -46.6, 80.0)

    assert len(states) == 1
    assert "/point/-23.5/-46.6/43" in captured[0]
    await client.aclose()


@pytest.mark.asyncio
async def test_ground_aircraft_and_missing_position_are_handled():
    captured: list[str] = []
    payload = {
        "ac": [
            {"hex": "abc", "lat": -1.0, "lon": -2.0, "alt_baro": "ground", "seen_pos": 0.0},
            {"hex": "def"},  # no position -> dropped
        ]
    }
    client = _client_returning(payload, captured)
    provider = AirplanesLiveProvider(client=client)

    states = await provider.get_aircraft_near(-1.0, -2.0, 40.0)

    assert len(states) == 1
    assert states[0].on_ground is True
    assert states[0].geometric_altitude_m == 0.0
    await client.aclose()
