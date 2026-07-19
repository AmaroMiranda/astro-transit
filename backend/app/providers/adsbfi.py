"""adsb.fi provider (RF-005).

adsb.fi exposes a free, community-fed open-data API using the readsb schema, but with
the aircraft array under the ``aircraft`` key and a lat/lon/dist URL shape:

    GET https://opendata.adsb.fi/api/v2/lat/{lat}/lon/{lon}/dist/{radius_nm}

No API key is required.
"""

from __future__ import annotations

from app.providers.readsb import ReadsbPointProvider

_BASE_URL = "https://opendata.adsb.fi/api/v2"


class AdsbFiProvider(ReadsbPointProvider):
    name = "adsbfi"
    aircraft_key = "aircraft"

    def _build_url(self, lat_deg: float, lon_deg: float, radius_nm: int) -> str:
        return f"{_BASE_URL}/lat/{lat_deg}/lon/{lon_deg}/dist/{radius_nm}"
