"""Satellite catalogue: TLEs for the ISS and Tiangong, propagated with Skyfield.

Unlike aircraft (fed continuously over ADS-B), a satellite's motion is fully described
by a Two-Line Element set (TLE) that changes slowly. We fetch the TLEs for the
configured NORAD ids from Celestrak, cache them for a few hours, and build Skyfield
:class:`~skyfield.sgp4lib.EarthSatellite` objects that the transit engine propagates
to any instant. A stale-but-recent TLE is still good to sub-kilometre precision over
the short prediction horizon, so a fetch failure degrades gracefully to the last set
(or to *no* satellites) rather than raising.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Optional

import httpx
from skyfield.api import EarthSatellite

# Friendly, localized labels for the well-known stations (falls back to the TLE name).
_SATELLITE_LABELS = {
    25544: "ISS (Estação Espacial)",
    48274: "Tiangong (Estação Chinesa)",
}

# Characteristic silhouette size (m) — the largest dimension seen against the disc.
# The ISS truss spans ~109 m; Tiangong is a much smaller ~55 m station. Anything else
# falls back to a conservative small-satellite size.
_SATELLITE_SIZE_M = {
    25544: 100.0,
    48274: 55.0,
}
_DEFAULT_SIZE_M = 30.0

_HEADERS = {"User-Agent": "AstroTransit/1.0 (+https://github.com/AmaroMiranda/astro-transit)"}


@dataclass(frozen=True)
class LoadedSatellite:
    """A propagatable satellite plus the metadata the transit layer needs."""

    norad_id: int
    label: str
    size_m: float
    satellite: EarthSatellite

    @property
    def object_id(self) -> str:
        return f"sat-{self.norad_id}"


class SatelliteCatalog:
    """Fetches and caches TLEs, exposing ready-to-propagate satellites.

    ``timescale`` must be the same Skyfield timescale used for the ephemeris, so
    satellite and Sun/Moon positions share one time system.
    """

    def __init__(
        self,
        timescale,
        norad_ids: list[int],
        source_url: str = "https://celestrak.org/NORAD/elements/gp.php",
        cache_ttl_s: float = 6 * 3600.0,
        client: Optional[httpx.AsyncClient] = None,
        timeout_s: float = 6.0,
    ) -> None:
        self._ts = timescale
        self._norad_ids = list(norad_ids)
        self._source_url = source_url
        self._cache_ttl_s = cache_ttl_s
        self._client = client or httpx.AsyncClient(timeout=timeout_s, headers=_HEADERS)
        self._owns_client = client is None
        self._loaded: list[LoadedSatellite] = []
        self._loaded_at: Optional[float] = None

    async def get_satellites(self) -> list[LoadedSatellite]:
        """Return the loaded satellites, refreshing the TLEs if the cache expired.

        Never raises for a network problem: it keeps serving the last good set, or an
        empty list if nothing was ever loaded (the caller then simply reports no
        satellite transits).
        """
        now = time.monotonic()
        fresh = self._loaded_at is not None and (now - self._loaded_at) <= self._cache_ttl_s
        if self._loaded and fresh:
            return self._loaded

        loaded: list[LoadedSatellite] = []
        for norad_id in self._norad_ids:
            try:
                sat = await self._fetch_one(norad_id)
            except (httpx.HTTPError, ValueError):
                sat = None
            if sat is not None:
                loaded.append(sat)

        if loaded:
            self._loaded = loaded
            self._loaded_at = now
        # If every fetch failed, keep whatever we had before (possibly empty).
        return self._loaded

    async def _fetch_one(self, norad_id: int) -> Optional[LoadedSatellite]:
        """Primary (Celestrak) with a JSON-API fallback.

        Celestrak intermittently blocks cloud-provider IP ranges — exactly where
        the backend is hosted — which silently emptied the catalogue in
        production. The fallback keeps satellite features alive from a second,
        independent source.
        """
        sat = None
        try:
            sat = await self._fetch_celestrak(norad_id)
        except (httpx.HTTPError, ValueError):
            sat = None
        if sat is None:
            sat = await self._fetch_fallback(norad_id)
        return sat

    async def _fetch_celestrak(self, norad_id: int) -> Optional[LoadedSatellite]:
        resp = await self._client.get(
            self._source_url, params={"CATNR": norad_id, "FORMAT": "TLE"}
        )
        resp.raise_for_status()
        text = resp.text.strip()
        # Celestrak returns a friendly "No GP data found" body on a bad id.
        if "No GP data" in text or not text:
            return None
        lines = [ln.rstrip() for ln in text.splitlines() if ln.strip()]
        if len(lines) < 3:
            return None
        name, line1, line2 = lines[0].strip(), lines[1], lines[2]
        return self._build(norad_id, name, line1, line2)

    async def _fetch_fallback(self, norad_id: int) -> Optional[LoadedSatellite]:
        try:
            resp = await self._client.get(
                f"https://tle.ivanstanojevic.me/api/tle/{norad_id}"
            )
            resp.raise_for_status()
            data = resp.json()
            line1 = data.get("line1")
            line2 = data.get("line2")
            if not line1 or not line2:
                return None
            return self._build(
                norad_id, str(data.get("name", norad_id)), line1, line2
            )
        except (httpx.HTTPError, ValueError):
            return None

    def _build(
        self, norad_id: int, name: str, line1: str, line2: str
    ) -> LoadedSatellite:
        satellite = EarthSatellite(line1, line2, name, self._ts)
        return LoadedSatellite(
            norad_id=norad_id,
            label=_SATELLITE_LABELS.get(norad_id, name),
            size_m=_SATELLITE_SIZE_M.get(norad_id, _DEFAULT_SIZE_M),
            satellite=satellite,
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()
