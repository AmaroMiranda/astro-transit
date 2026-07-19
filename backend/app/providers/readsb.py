"""Shared base for readsb/tar1090-style ADS-B feeds (RF-005).

adsb.lol, airplanes.live and adsb.fi all expose the same community "aircraft.json"
schema popularised by tar1090/readsb (and the ADSBExchange v2 API): a JSON object
whose aircraft array holds ``hex``, ``lat``, ``lon``, ``alt_geom``/``alt_baro``,
``gs``, ``track``, ``category`` and ``seen_pos`` fields. Only the URL shape and the
name of the aircraft array differ between them, so the normalization lives here once
and each concrete provider just supplies the endpoint.
"""

from __future__ import annotations

import time
from abc import abstractmethod
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx

from app.domain.models import AircraftCategory, AircraftState
from app.providers.base import AircraftDataProvider, ProviderError, ProviderStatus
from app.providers.units import feet_to_m, fpm_to_mps, knots_to_mps

_KM_TO_NM = 0.539957
_MAX_RADIUS_NM = 250

# ADS-B emitter category (A1..A7) -> our coarse categories (RF-011).
_CATEGORY_MAP = {
    "A1": AircraftCategory.SMALL,
    "A2": AircraftCategory.NARROW_BODY,
    "A3": AircraftCategory.NARROW_BODY,
    "A4": AircraftCategory.WIDE_BODY,
    "A5": AircraftCategory.WIDE_BODY,
    "A6": AircraftCategory.WIDE_BODY,
    "A7": AircraftCategory.HELICOPTER,
}

# Some feeds (airplanes.live) reject requests carrying the default httpx/python
# User-Agent. A plain, honest identifier keeps us within their fair-use policy.
_DEFAULT_HEADERS = {"User-Agent": "AstroTransit/1.0 (+https://github.com/AmaroMiranda/astro-transit)"}


class ReadsbPointProvider(AircraftDataProvider):
    """Base class for point-radius readsb feeds. Subclasses set :attr:`name`,
    :attr:`aircraft_key` and implement :meth:`_build_url`."""

    #: Top-level key holding the aircraft array (``"ac"`` or ``"aircraft"``).
    aircraft_key: str = "ac"

    def __init__(self, client: Optional[httpx.AsyncClient] = None, timeout_s: float = 4.0):
        self._client = client or httpx.AsyncClient(timeout=timeout_s, headers=_DEFAULT_HEADERS)
        self._owns_client = client is None
        self._last_update: Optional[datetime] = None
        self._last_latency_ms: Optional[float] = None
        self._last_count: Optional[int] = None
        self._healthy = True

    @abstractmethod
    def _build_url(self, lat_deg: float, lon_deg: float, radius_nm: int) -> str:
        """Return the point-radius query URL for this feed."""

    async def get_aircraft_near(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> list[AircraftState]:
        radius_nm = min(round(radius_km * _KM_TO_NM), _MAX_RADIUS_NM)
        url = self._build_url(lat_deg, lon_deg, radius_nm)
        started = time.perf_counter()
        try:
            resp = await self._client.get(url)
            resp.raise_for_status()
            payload = resp.json()
            self._last_latency_ms = (time.perf_counter() - started) * 1000.0
            self._healthy = True
        except (httpx.HTTPError, ValueError) as exc:
            self._healthy = False
            raise ProviderError(f"{self.name} request failed: {exc}") from exc

        raw = payload.get(self.aircraft_key) or []
        states = [self._normalize(ac) for ac in raw]
        states = [s for s in states if s is not None]
        self._last_update = datetime.now(timezone.utc)
        self._last_count = len(states)
        return states

    def _normalize(self, ac: dict) -> Optional[AircraftState]:
        hex_id = ac.get("hex")
        lat = ac.get("lat")
        lon = ac.get("lon")
        if hex_id is None or lat is None or lon is None:
            return None

        alt_raw = ac.get("alt_geom", ac.get("alt_baro"))
        on_ground = alt_raw == "ground"
        altitude_m = 0.0 if on_ground else (feet_to_m(alt_raw) or 0.0)

        vrate = ac.get("geom_rate", ac.get("baro_rate"))
        seen = ac.get("seen_pos", ac.get("seen", 0.0)) or 0.0
        timestamp = datetime.now(timezone.utc) - timedelta(seconds=float(seen))

        callsign = (ac.get("flight") or "").strip() or None
        category = _CATEGORY_MAP.get(ac.get("category"), AircraftCategory.UNKNOWN)

        return AircraftState(
            icao24=str(hex_id).lower(),
            latitude_deg=float(lat),
            longitude_deg=float(lon),
            geometric_altitude_m=altitude_m,
            ground_speed_mps=knots_to_mps(ac.get("gs")) or 0.0,
            track_deg=float(ac.get("track") or 0.0),
            vertical_rate_mps=fpm_to_mps(vrate) or 0.0,
            callsign=callsign,
            on_ground=on_ground,
            category=category,
            timestamp_utc=timestamp,
        )

    async def get_status(self) -> ProviderStatus:
        return ProviderStatus(
            name=self.name,
            healthy=self._healthy,
            last_update_utc=self._last_update,
            latency_ms=self._last_latency_ms,
            aircraft_count=self._last_count,
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()
