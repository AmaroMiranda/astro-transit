"""OpenSky Network provider (RF-005).

OpenSky returns state vectors constrained by a bounding box:

    GET https://opensky-network.org/api/states/all?lamin=&lomin=&lamax=&lomax=

The endpoint enforces usage limits (SPEC RF-004); an optional OAuth2 client-credentials
token raises those limits when configured. Positions are already SI (m, m/s).
"""

from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.domain.models import AircraftState
from app.providers.base import (
    AircraftDataProvider,
    BoundingBox,
    ProviderError,
    ProviderStatus,
)

_STATES_URL = "https://opensky-network.org/api/states/all"
_TOKEN_URL = (
    "https://auth.opensky-network.org/auth/realms/opensky-network/"
    "protocol/openid-connect/token"
)

# OpenSky state-vector array indices.
_IDX_ICAO24 = 0
_IDX_CALLSIGN = 1
_IDX_LON = 5
_IDX_LAT = 6
_IDX_BARO_ALT = 7
_IDX_ON_GROUND = 8
_IDX_VELOCITY = 9
_IDX_TRUE_TRACK = 10
_IDX_VERTICAL_RATE = 11
_IDX_GEO_ALT = 13
_IDX_LAST_CONTACT = 4


class OpenSkyProvider(AircraftDataProvider):
    name = "opensky"

    def __init__(
        self,
        client: Optional[httpx.AsyncClient] = None,
        timeout_s: float = 6.0,
        client_id: str = "",
        client_secret: str = "",
    ):
        self._client = client or httpx.AsyncClient(timeout=timeout_s)
        self._owns_client = client is None
        self._client_id = client_id
        self._client_secret = client_secret
        self._token: Optional[str] = None
        self._token_expiry: float = 0.0
        self._last_update: Optional[datetime] = None
        self._last_latency_ms: Optional[float] = None
        self._last_count: Optional[int] = None
        self._healthy = True

    async def _auth_headers(self) -> dict:
        if not (self._client_id and self._client_secret):
            return {}
        if self._token and time.time() < self._token_expiry - 30:
            return {"Authorization": f"Bearer {self._token}"}
        try:
            resp = await self._client.post(
                _TOKEN_URL,
                data={
                    "grant_type": "client_credentials",
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                },
            )
            resp.raise_for_status()
            tok = resp.json()
            self._token = tok["access_token"]
            self._token_expiry = time.time() + float(tok.get("expires_in", 1800))
            return {"Authorization": f"Bearer {self._token}"}
        except (httpx.HTTPError, KeyError, ValueError):
            # Fall back to the anonymous tier rather than failing outright.
            return {}

    async def get_aircraft_near(
        self, lat_deg: float, lon_deg: float, radius_km: float
    ) -> list[AircraftState]:
        box = BoundingBox.around(lat_deg, lon_deg, radius_km)
        params = {
            "lamin": box.lat_min,
            "lamax": box.lat_max,
            "lomin": box.lon_min,
            "lomax": box.lon_max,
        }
        headers = await self._auth_headers()
        started = time.perf_counter()
        try:
            resp = await self._client.get(_STATES_URL, params=params, headers=headers)
            resp.raise_for_status()
            payload = resp.json()
            self._last_latency_ms = (time.perf_counter() - started) * 1000.0
            self._healthy = True
        except (httpx.HTTPError, ValueError) as exc:
            self._healthy = False
            raise ProviderError(f"opensky request failed: {exc}") from exc

        states = [self._normalize(s) for s in (payload.get("states") or [])]
        states = [s for s in states if s is not None]
        self._last_update = datetime.now(timezone.utc)
        self._last_count = len(states)
        return states

    def _normalize(self, s: list) -> Optional[AircraftState]:
        try:
            icao = s[_IDX_ICAO24]
            lat = s[_IDX_LAT]
            lon = s[_IDX_LON]
        except IndexError:
            return None
        if icao is None or lat is None or lon is None:
            return None

        geo_alt = s[_IDX_GEO_ALT] if len(s) > _IDX_GEO_ALT else None
        baro_alt = s[_IDX_BARO_ALT]
        altitude_m = geo_alt if geo_alt is not None else (baro_alt or 0.0)
        last_contact = s[_IDX_LAST_CONTACT] or time.time()
        callsign = (s[_IDX_CALLSIGN] or "").strip() or None

        # "Unknown" is not "zero" — see readsb.py. Missing altitude/velocity/track
        # excludes the aircraft from the prediction engine (still shown on map).
        on_ground = bool(s[_IDX_ON_GROUND])
        telemetry_complete = on_ground or not (
            (geo_alt is None and baro_alt is None)
            or s[_IDX_VELOCITY] is None
            or s[_IDX_TRUE_TRACK] is None
        )

        return AircraftState(
            icao24=str(icao).lower(),
            latitude_deg=float(lat),
            longitude_deg=float(lon),
            geometric_altitude_m=float(altitude_m or 0.0),
            ground_speed_mps=float(s[_IDX_VELOCITY] or 0.0),
            track_deg=float(s[_IDX_TRUE_TRACK] or 0.0),
            vertical_rate_mps=float(s[_IDX_VERTICAL_RATE] or 0.0),
            callsign=callsign,
            on_ground=on_ground,
            timestamp_utc=datetime.fromtimestamp(float(last_contact), tz=timezone.utc),
            telemetry_complete=telemetry_complete,
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
