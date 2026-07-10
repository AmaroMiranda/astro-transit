"""Topocentric Sun & Moon positions using Skyfield and a JPL ephemeris (RF-003).

The ephemeris (``de421.bsp``, valid 1900-2050, ~17 MB) is kept **locally** so no
download happens per request (SPEC RF-003 / section 12.1). Load it once and reuse the
:class:`EphemerisService` instance across requests.

Apparent positions are topocentric: they account for the observer's location and
altitude and (optionally) atmospheric refraction. Angular radius is derived from the
true Earth-to-body distance at the instant of observation (RF-010).
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from functools import lru_cache
from typing import Optional

from skyfield.api import Loader, wgs84
from skyfield.nutationlib import iau2000b  # noqa: F401  (ensures data available)

from app.domain.models import CelestialBody, CelestialPosition, ObserverLocation
from app.geometry.angles import MOON_RADIUS_M, SUN_RADIUS_M, apparent_radius_deg

# Directory that holds the cached ephemeris + Skyfield data files.
_DEFAULT_DATA_DIR = os.environ.get(
    "ASTRO_EPHEMERIS_DIR",
    os.path.join(os.path.dirname(__file__), "_data"),
)
_EPHEMERIS_FILE = "de421.bsp"

_BODY_TARGET = {
    CelestialBody.SUN: "sun",
    CelestialBody.MOON: "moon",
}
_BODY_RADIUS_M = {
    CelestialBody.SUN: SUN_RADIUS_M,
    CelestialBody.MOON: MOON_RADIUS_M,
}


class EphemerisService:
    """Loads the JPL ephemeris once and computes apparent Sun/Moon positions."""

    def __init__(self, data_dir: str = _DEFAULT_DATA_DIR) -> None:
        os.makedirs(data_dir, exist_ok=True)
        self._loader = Loader(data_dir, verbose=False)
        self._ts = self._loader.timescale()
        # Downloads de421.bsp on first call, then reuses the cached file.
        self._eph = self._loader(_EPHEMERIS_FILE)
        self._earth = self._eph["earth"]

    def position(
        self,
        body: CelestialBody,
        observer: ObserverLocation,
        when: Optional[datetime] = None,
        apply_refraction: bool = False,
    ) -> CelestialPosition:
        """Apparent topocentric position of ``body`` for ``observer`` at ``when`` (UTC)."""
        when = when or datetime.now(timezone.utc)
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        t = self._ts.from_datetime(when.astimezone(timezone.utc))

        site = self._earth + wgs84.latlon(
            observer.latitude_deg,
            observer.longitude_deg,
            elevation_m=observer.altitude_m,
        )
        target = self._eph[_BODY_TARGET[body]]
        astrometric = site.at(t).observe(target).apparent()

        if apply_refraction:
            alt, az, distance = astrometric.altaz(temperature_C=10.0, pressure_mbar=1010.0)
        else:
            alt, az, distance = astrometric.altaz()

        distance_m = distance.m
        angular_radius = apparent_radius_deg(_BODY_RADIUS_M[body], distance_m)

        illumination = None
        if body is CelestialBody.MOON:
            illumination = self._moon_illumination(t)

        return CelestialPosition(
            body=body,
            azimuth_deg=az.degrees,
            altitude_deg=alt.degrees,
            distance_m=distance_m,
            angular_radius_deg=angular_radius,
            illumination=illumination,
            timestamp_utc=when.astimezone(timezone.utc),
        )

    def _moon_illumination(self, t) -> float:
        """Fraction of the Moon's disc that is illuminated (0..1)."""
        from skyfield.almanac import fraction_illuminated

        return float(fraction_illuminated(self._eph, "moon", t))


@lru_cache(maxsize=1)
def get_ephemeris_service() -> EphemerisService:
    """Process-wide singleton so the ephemeris is loaded only once."""
    return EphemerisService()
