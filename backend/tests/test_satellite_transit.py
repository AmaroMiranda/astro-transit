"""Satellite transit engine tests.

We drive the engine with a *real* ISS TLE (so SGP4 propagation and the sub-point
geometry are exercised for real) but a **fake ephemeris** that pins the Sun exactly on
the ISS's line of sight at the peak of a pass. That guarantees a genuine central
transit whose instant we know, letting us assert that the coarse scan + refinement
lands on it and that classification/labelling are correct — without depending on a
real-world ISS solar transit happening at a convenient time.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import numpy as np
import pytest
from skyfield.api import EarthSatellite, wgs84

from app.astronomy.ephemeris import get_ephemeris_service
from app.astronomy.satellites import LoadedSatellite
from app.domain.models import (
    CelestialBody,
    CelestialPosition,
    ObserverLocation,
    TransitObjectKind,
)
from app.prediction.satellite_transit import find_satellite_transit

try:
    _EPHEMERIS = get_ephemeris_service()
except Exception:
    _EPHEMERIS = None

pytestmark = pytest.mark.skipif(_EPHEMERIS is None, reason="ephemeris unavailable (offline?)")

# A real ISS TLE (epoch 2024-01-07).
_L1 = "1 25544U 98067A   24007.53703703  .00016717  00000+0  30074-3 0  9998"
_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49444143  9999"
_OBS = ObserverLocation(latitude_deg=-23.5, longitude_deg=-46.6, altitude_m=760.0)
_SCAN_BASE = datetime(2024, 1, 7, 0, 0, 0, tzinfo=timezone.utc)


class _FakeEphemeris:
    """Delegates the timescale to the real service but reports a body sitting at a
    fixed alt/az — used to plant a guaranteed transit on the satellite's path."""

    def __init__(self, real, fixed_alt_deg, fixed_az_deg):
        self._real = real
        self._alt = fixed_alt_deg
        self._az = fixed_az_deg

    @property
    def timescale(self):
        return self._real.timescale

    def observer_site(self, observer):
        return self._real.observer_site(observer)

    def altaz_series(self, body, observer, times):
        n = len(np.atleast_1d(times.tt))
        alt = np.full(n, self._alt)
        az = np.full(n, self._az)
        dist = np.full(n, 1.496e11)  # ~1 AU
        return alt, az, dist

    def position(self, body, observer, when=None):
        return CelestialPosition(
            body=body,
            azimuth_deg=self._az,
            altitude_deg=self._alt,
            distance_m=1.496e11,
            angular_radius_deg=0.266,  # Sun's apparent radius
        )


def _loaded_iss():
    sat = EarthSatellite(_L1, _L2, "ISS (ZARYA)", _EPHEMERIS.timescale)
    return LoadedSatellite(norad_id=25544, label="ISS (Estação Espacial)", size_m=100.0, satellite=sat)


def _peak_pass_instant(loaded):
    """Minute of the highest ISS pass over the observer within a day, plus its alt/az."""
    ts = _EPHEMERIS.timescale
    site = wgs84.latlon(_OBS.latitude_deg, _OBS.longitude_deg, elevation_m=_OBS.altitude_m)
    diff = loaded.satellite - site
    best = None
    for m in range(0, 1440):
        t = ts.from_datetime(_SCAN_BASE + timedelta(minutes=m))
        alt, az, _ = diff.at(t).altaz()
        if best is None or alt.degrees > best[1]:
            best = (m, float(alt.degrees), float(az.degrees))
    return best


def test_detects_and_refines_a_planted_iss_transit():
    loaded = _loaded_iss()
    minute, alt, az = _peak_pass_instant(loaded)
    assert alt > 20.0  # a usable pass exists

    peak_when = _SCAN_BASE + timedelta(minutes=minute)
    fake = _FakeEphemeris(_EPHEMERIS, fixed_alt_deg=alt, fixed_az_deg=az)

    # Start 60 s before the peak so the closest approach sits mid-horizon.
    start = peak_when - timedelta(seconds=60)
    result = find_satellite_transit(
        loaded, CelestialBody.SUN, fake, _OBS, start, horizon_s=120.0
    )

    assert result is not None
    cand = result.candidate
    assert cand.is_transit
    assert cand.object_kind == TransitObjectKind.SATELLITE
    assert cand.object_label == "ISS (Estação Espacial)"
    assert cand.icao24 == "sat-25544"
    # Closest approach refined to ~60 s (within a coarse step of the true peak).
    assert 55.0 <= cand.time_to_transit_s <= 65.0
    # Body fixed exactly on the path -> essentially zero separation.
    assert cand.min_separation_deg < 0.05
    # Sub-satellite point should be a sane geographic coordinate.
    assert -90 <= result.subpoint_lat_deg <= 90
    assert -180 <= result.subpoint_lon_deg <= 180
    assert result.subpoint_alt_m > 300_000  # ISS altitude, metres
    assert result.tle_age_hours >= 0.0


def test_no_transit_when_body_far_from_path():
    loaded = _loaded_iss()
    minute, alt, az = _peak_pass_instant(loaded)
    peak_when = _SCAN_BASE + timedelta(minutes=minute)
    # Put the body 40 deg away in azimuth — nowhere near the ISS.
    fake = _FakeEphemeris(_EPHEMERIS, fixed_alt_deg=alt, fixed_az_deg=(az + 40.0) % 360.0)

    result = find_satellite_transit(
        loaded, CelestialBody.SUN, fake, _OBS, peak_when - timedelta(seconds=60), horizon_s=120.0
    )
    assert result is None
