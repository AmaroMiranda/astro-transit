"""airplanes.live provider (RF-005).

airplanes.live is a community ADS-B network with strong coverage. Its REST API mirrors
the ADSBExchange v2 schema (aircraft under the ``ac`` key):

    GET https://api.airplanes.live/v2/point/{lat}/{lon}/{radius_nm}

Rate-limited to ~1 request/second and rejects the default python User-Agent, so the
shared base sends an explicit identifier. No API key is required.
"""

from __future__ import annotations

from app.providers.readsb import ReadsbPointProvider

_BASE_URL = "https://api.airplanes.live/v2"


class AirplanesLiveProvider(ReadsbPointProvider):
    name = "airplaneslive"
    aircraft_key = "ac"

    def _build_url(self, lat_deg: float, lon_deg: float, radius_nm: int) -> str:
        return f"{_BASE_URL}/point/{lat_deg}/{lon_deg}/{radius_nm}"
