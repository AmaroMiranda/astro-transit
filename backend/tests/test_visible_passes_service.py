"""Passagens VISÍVEIS da estação (a olho nu).

Estratégia: TLE real da ISS + efemérides reais (de421) — determinístico. Como
a visibilidade depende da sombra da Terra e da altura REAL do Sol, não dá para
"fixar" o Sol como nos testes de trânsito; então validamos por INVARIANTES que
toda passagem retornada tem de satisfazer, o que exercita exatamente a lógica:
cada passagem listada precisa estar iluminada, com o observador no escuro e
culminando acima do mínimo.
"""

from __future__ import annotations

from datetime import datetime, timezone

import numpy as np
import pytest
from skyfield.api import EarthSatellite, wgs84

from app.astronomy.ephemeris import get_ephemeris_service
from app.astronomy.satellites import LoadedSatellite
from app.domain.models import CelestialBody, ObserverLocation
from app.services.visible_passes_service import (
    VisiblePassesService,
    _MIN_CULMINATION_DEG,
    _SUN_DARK_DEG,
    _approx_magnitude,
)

try:
    _EPHEMERIS = get_ephemeris_service()
except Exception:
    _EPHEMERIS = None

pytestmark = pytest.mark.skipif(
    _EPHEMERIS is None, reason="ephemeris unavailable (offline?)"
)

_L1 = "1 25544U 98067A   24007.53703703  .00016717  00000+0  30074-3 0  9998"
_L2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49444143  9999"
_OBS = ObserverLocation(latitude_deg=-23.5, longitude_deg=-46.6, altitude_m=760.0)
# Início ancorado numa TEMPORADA DE VISIBILIDADE da ISS sobre SP (a estação só
# faz passagens visíveis em janelas de ~1-2 semanas; medido para este TLE, as
# primeiras aparecem a partir de 2024-01-12). Numa janela fora da temporada, a
# lista corretamente sai vazia — o que quebraria o teste sem indicar bug.
_BASE = datetime(2024, 1, 12, 12, 0, 0, tzinfo=timezone.utc)


class _FakeCatalog:
    def __init__(self, sats):
        self._sats = sats

    async def get_satellites(self):
        return self._sats


def _loaded_iss():
    sat = EarthSatellite(_L1, _L2, "ISS (ZARYA)", _EPHEMERIS.timescale)
    return LoadedSatellite(norad_id=25544, label="ISS", size_m=100.0, satellite=sat)


@pytest.mark.asyncio
async def test_visible_passes_satisfy_visibility_invariants():
    service = VisiblePassesService(_EPHEMERIS, _FakeCatalog([_loaded_iss()]))
    passes = await service.upcoming(_OBS, hours=72.0, start=_BASE)

    # Dentro da temporada de visibilidade, tem de haver passagens em 72 h.
    assert passes, "esperava ao menos uma passagem visível na temporada"

    site = wgs84.latlon(_OBS.latitude_deg, _OBS.longitude_deg, elevation_m=_OBS.altitude_m)
    iss = _loaded_iss().satellite
    ts = _EPHEMERIS.timescale

    prev_culm = None
    for p in passes:
        # Estrutura temporal coerente.
        assert p.start_utc <= p.culmination_utc <= p.end_utc
        # Culminação acima do mínimo.
        assert p.max_elevation_deg >= _MIN_CULMINATION_DEG
        # Ordenadas por culminação.
        if prev_culm is not None:
            assert p.culmination_utc >= prev_culm
        prev_culm = p.culmination_utc

        # INVARIANTE-CHAVE 1: no auge, o observador está no escuro.
        t = ts.from_datetime(p.culmination_utc)
        sun_alt, _, _ = _EPHEMERIS.altaz_series(
            CelestialBody.SUN, _OBS, ts.from_datetimes([p.culmination_utc])
        )
        assert float(sun_alt[0]) < _SUN_DARK_DEG, (
            f"passagem listada com Sol a {float(sun_alt[0]):.1f}° "
            "(observador não estava no escuro)"
        )
        # INVARIANTE-CHAVE 2: no auge, a estação está iluminada pelo Sol.
        assert bool(iss.at(t).is_sunlit(_EPHEMERIS.eph)), (
            "passagem listada com a estação na sombra da Terra"
        )
        # A estação está mesmo acima do horizonte no auge.
        alt, _, _ = (iss - site).at(t).altaz()
        assert alt.degrees > 0


@pytest.mark.asyncio
async def test_no_satellites_returns_empty():
    service = VisiblePassesService(_EPHEMERIS, _FakeCatalog([]))
    assert await service.upcoming(_OBS, hours=24.0, start=_BASE) == []


def test_magnitude_dims_with_distance_and_low_passes():
    # Mais longe = mais fraco (magnitude maior).
    near = _approx_magnitude(80.0, 500.0)
    far = _approx_magnitude(80.0, 1500.0)
    assert far > near
    # Passagem baixa perde brilho por absorção atmosférica.
    high = _approx_magnitude(80.0, 800.0)
    low = _approx_magnitude(10.0, 800.0)
    assert low > high
