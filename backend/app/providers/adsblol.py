"""ADSB.lol provider (RF-005).

ADSB.lol exposes an open, community-fed API using the tar1090/ADSBExchange v2 schema:

    GET https://api.adsb.lol/v2/point/{lat}/{lon}/{radius_nm}

Normalization is shared with the other readsb feeds in :mod:`app.providers.readsb`.
"""

from __future__ import annotations

from app.providers.readsb import ReadsbPointProvider

_BASE_URL = "https://api.adsb.lol/v2"


class AdsbLolProvider(ReadsbPointProvider):
    name = "adsblol"
    aircraft_key = "ac"

    def _build_url(self, lat_deg: float, lon_deg: float, radius_nm: int) -> str:
        return f"{_BASE_URL}/point/{lat_deg}/{lon_deg}/{radius_nm}"
