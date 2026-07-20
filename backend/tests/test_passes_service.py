"""Multi-day satellite pass planner tests.

Same strategy as test_satellite_transit: a real ISS TLE drives real SGP4
propagation, while a fake ephemeris pins the "Sun" onto the peak of a known
pass — so the scanner MUST find that transit, deterministically.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import numpy as np
import pytest
from skyfield.api import EarthSatellite, wgs84

from app.astronomy.ephemeris import get_ephemeris_service
from app.astronomy.satellites import LoadedSatellite
from app.domain.models import CelestialBody, CelestialPosition, ObserverLocation
from app.services.passes_service import PassesService, _segments

try:
    _EPHEMERIS = get_ephemeris_service()
except Exception:
    _EPHEMERIS = None

pytestmark = pytest.mark.skipif(_EPHEMERIS is None, reason="ephemeris unavailable (offline?)")

_L1 = "1 25544U 98067A   24007.53703703  .00016717  00000+0  30074-3 0  9998"
_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49444143  9999"
_OBS = ObserverLocation(latitude_deg=-23.5, longitude_deg=-46.6, altitude_m=760.0)
_BASE = datetime(2024, 1, 7, 0, 0, 0, tzinfo=timezone.utc)


class _FakeCatalog:
    def __init__(self, sats):
        self._sats = sats

    async def get_satellites(self):
        return self._sats


class _PinnedEphemeris:
    """Body fixed at one alt/az; supports both scalar and vectorized queries."""

    def __init__(self, real, alt_deg, az_deg):
        self._real = real
        self._alt = alt_deg
        self._az = az_deg

    @property
    def timescale(self):
        return self._real.timescale

    def altaz_series(self, body, observer, times):
        n = len(np.atleast_1d(times.tt))
        return (np.full(n, self._alt), np.full(n, self._az), np.full(n, 1.5e11))

    def position(self, body, observer, when=None):
        return CelestialPosition(
            body=body, azimuth_deg=self._az, altitude_deg=self._alt,
            distance_m=1.496e11, angular_radius_deg=0.266,
        )


def _loaded_iss():
    sat = EarthSatellite(_L1, _L2, "ISS (ZARYA)", _EPHEMERIS.timescale)
    return LoadedSatellite(norad_id=25544, label="ISS", size_m=100.0, satellite=sat)


def _peak(loaded):
    ts = _EPHEMERIS.timescale
    site = wgs84.latlon(_OBS.latitude_deg, _OBS.longitude_deg, elevation_m=_OBS.altitude_m)
    diff = loaded.satellite - site
    best = None
    for m in range(0, 1440):
        t = ts.from_datetime(_BASE + timedelta(minutes=m))
        alt, az, _ = diff.at(t).altaz()
        if best is None or alt.degrees > best[1]:
            best = (m, float(alt.degrees), float(az.degrees))
    return best


def test_segments_helper():
    mask = np.array([False, True, True, False, False, True, False, True])
    assert _segments(mask) == [(1, 2), (5, 5), (7, 7)]
    assert _segments(np.zeros(4, dtype=bool)) == []


@pytest.mark.asyncio
async def test_planner_finds_planted_transit_with_absolute_time_and_duration():
    loaded = _loaded_iss()
    minute, alt, az = _peak(loaded)
    peak_when = _BASE + timedelta(minutes=minute)
    fake = _PinnedEphemeris(_EPHEMERIS, alt, az)

    service = PassesService(fake, _FakeCatalog([loaded]))
    # Scan a 2 h window that contains the pass.
    start = peak_when - timedelta(minutes=60)
    passes = await service.upcoming(
        _OBS, hours=2.0, bodies=[CelestialBody.SUN], start=start
    )

    assert passes, "o planejador nao encontrou o transito plantado"
    p = passes[0]
    # Absolute timestamp lands on the (known) peak instant.
    assert abs((p.transit_at_utc - peak_when).total_seconds()) < 30.0
    assert p.satellite_label == "ISS"
    assert p.transit.candidate.is_transit
    # A central planted transit must have a physical, sub-second-to-seconds
    # duration (ISS angular rate near culmination ~ 0.3-1.2 deg/s, disc 0.53 deg).
    assert 0.05 < p.transit.transit_duration_s < 10.0
    # Ground corridor present with sane geometry.
    assert p.corridor is not None
    assert p.corridor.half_width_m > 100.0


@pytest.mark.asyncio
async def test_planner_includes_near_miss_when_centerline_is_close():
    """Body ~1.5 deg off the pass peak: no transit at the observer, but the
    ground centerline runs a travelable distance away — the planner must keep
    it (transit-finder workflow) and drop it when the allowed distance is 0."""
    loaded = _loaded_iss()
    minute, alt, az = _peak(loaded)
    peak_when = _BASE + timedelta(minutes=minute)
    fake = _PinnedEphemeris(_EPHEMERIS, alt - 1.5, az)  # miss by ~1.5 deg

    service = PassesService(fake, _FakeCatalog([loaded]))
    start = peak_when - timedelta(minutes=30)

    near = await service.upcoming(
        _OBS, hours=1.0, bodies=[CelestialBody.SUN], start=start,
        max_center_distance_km=60.0,
    )
    assert near, "quase-transito com faixa proxima deveria entrar na lista"
    p = near[0]
    assert not p.transit.candidate.is_transit          # nao e transito AQUI
    assert p.corridor is not None
    assert 0 < p.corridor.distance_from_observer_m <= 60_000.0

    strict = await service.upcoming(
        _OBS, hours=1.0, bodies=[CelestialBody.SUN], start=start,
        max_center_distance_km=0.0,
    )
    assert strict == []


@pytest.mark.asyncio
async def test_planner_empty_when_body_never_up():
    loaded = _loaded_iss()
    fake = _PinnedEphemeris(_EPHEMERIS, -30.0, 100.0)  # body below horizon
    service = PassesService(fake, _FakeCatalog([loaded]))
    passes = await service.upcoming(
        _OBS, hours=3.0, bodies=[CelestialBody.SUN], start=_BASE
    )
    assert passes == []


@pytest.mark.asyncio
async def test_planner_real_ephemeris_24h_smoke():
    """Real Sun/Moon + real TLE over 24 h: must complete quickly and cleanly
    (usually zero passes — transits are rare — but never an error)."""
    import time

    loaded = _loaded_iss()
    service = PassesService(_EPHEMERIS, _FakeCatalog([loaded]))
    t0 = time.perf_counter()
    passes = await service.upcoming(_OBS, hours=24.0, start=_BASE)
    elapsed = time.perf_counter() - t0
    assert elapsed < 20.0, f"varredura de 24 h lenta demais: {elapsed:.1f}s"
    for p in passes:
        assert p.transit.candidate.is_transit
        assert p.transit_at_utc >= _BASE
