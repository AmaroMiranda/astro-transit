"""Passagens VISÍVEIS de satélites (ISS/Tiangong) para um observador.

Diferente do planejador de TRÂNSITOS (`passes_service`, que só acha o satélite
cruzando o Sol/Lua), aqui listamos toda passagem em que a estação pode ser VISTA
a olho nu — o que permite ao usuário registrá-la mesmo quando não há trânsito.

Uma passagem é visível quando, ao mesmo tempo:
  1. o satélite está acima do horizonte (culminando acima de um mínimo);
  2. o satélite está ILUMINADO pelo Sol (fora da sombra da Terra) — senão é um
     ponto escuro invisível;
  3. o OBSERVADOR está no escuro (Sol abaixo de ~-6°, crepúsculo civil ou mais
     escuro) — de dia o céu ofusca a estação.

Para cada passagem reportamos início/culminação/fim, elevação máxima, azimutes
de subida e descida, e a magnitude aproximada. E marcamos `is_transit` quando a
passagem COINCIDE com um trânsito do Sol/Lua (reaproveitando o motor fino já
validado) — é o mesmo destaque que os aviões candidatos recebem.

A varredura é vetorizada (grade de 30 s) como o planejador de trânsitos; o
refino de subida/culminação/descida é feito por interpolação sobre a grade
fina o suficiente para a precisão de segundos que a UI mostra.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

import numpy as np
from skyfield.api import wgs84

from app.astronomy.ephemeris import EphemerisService
from app.astronomy.satellites import SatelliteCatalog
from app.domain.models import CelestialBody, ObserverLocation
from app.prediction.satellite_transit import find_satellite_transit
from app.services.passes_service import _segments  # reutiliza o detector de segmentos

_COARSE_STEP_S = 30.0
_MAX_HOURS = 72.0
# Culminação mínima para valer a pena listar (abaixo disso o horizonte costuma
# bloquear, igual ao planejador de trânsitos).
_MIN_CULMINATION_DEG = 10.0
# O observador precisa estar ao menos no crepúsculo civil para a estação
# destacar do céu. -6° = fim do crepúsculo civil.
_SUN_DARK_DEG = -6.0
# Gate angular para decidir se a passagem também é um trânsito (mesmo do
# planejador: ~4° = corredor a ~40 km, "dirija até a linha").
_TRANSIT_GATE_DEG = 4.0


@dataclass(frozen=True)
class VisiblePass:
    satellite_id: str
    satellite_label: str
    start_utc: datetime          # subida acima do mínimo, já iluminada
    culmination_utc: datetime
    end_utc: datetime
    duration_s: float
    max_elevation_deg: float
    start_azimuth_deg: float
    end_azimuth_deg: float
    approx_magnitude: float
    tle_age_hours: float
    is_transit: bool             # coincide com trânsito do Sol/Lua
    transit_body: Optional[CelestialBody]  # qual corpo, se trânsito


def _approx_magnitude(max_elevation_deg: float, slant_range_km: float) -> float:
    """Magnitude aparente aproximada da ISS.

    Modelo simples e honesto: a ISS tem magnitude padrão ~-1.8 a 1000 km na
    distância de referência; escurece com o quadrado da distância (lei do
    inverso do quadrado → +5·log10(d/d0) em magnitudes) e um pequeno ajuste por
    elevação (mais baixa = mais atmosfera). Não é fotométrico — é uma
    estimativa para o usuário saber se a passagem é brilhante ou fraca.
    """
    d0 = 1000.0
    base = -1.8
    mag = base + 5.0 * np.log10(max(slant_range_km, 1.0) / d0)
    # Passagens muito baixas perdem ~0.5 mag por absorção atmosférica.
    if max_elevation_deg < 20.0:
        mag += 0.5
    return round(float(mag), 1)


class VisiblePassesService:
    def __init__(self, ephemeris: EphemerisService, catalog: SatelliteCatalog):
        self._ephemeris = ephemeris
        self._catalog = catalog

    async def upcoming(
        self,
        observer: ObserverLocation,
        hours: float = 48.0,
        start: Optional[datetime] = None,
    ) -> list[VisiblePass]:
        hours = min(max(hours, 1.0), _MAX_HOURS)
        start = (start or datetime.now(timezone.utc)).astimezone(timezone.utc)

        satellites = await self._catalog.get_satellites()
        if not satellites:
            return []

        ts = self._ephemeris.timescale
        n = int(hours * 3600.0 / _COARSE_STEP_S) + 1
        offsets = np.arange(n) * _COARSE_STEP_S
        times = ts.from_datetimes(
            [start + timedelta(seconds=float(o)) for o in offsets]
        )

        # Elevação do Sol (para saber quando o observador está no escuro).
        sun_alt, _, _ = self._ephemeris.altaz_series(
            CelestialBody.SUN, observer, times
        )
        observer_dark = sun_alt < _SUN_DARK_DEG

        site = wgs84.latlon(
            observer.latitude_deg,
            observer.longitude_deg,
            elevation_m=observer.altitude_m,
        )

        out: list[VisiblePass] = []
        for loaded in satellites:
            topo = (loaded.satellite - site).at(times)
            sat_alt, sat_az, sat_range = topo.altaz()
            alt_deg = sat_alt.degrees
            az_deg = sat_az.degrees
            range_km = sat_range.km
            # Iluminada pelo Sol? (Skyfield usa o ephemeris para a sombra.)
            sunlit = loaded.satellite.at(times).is_sunlit(self._ephemeris.eph)

            visible = (alt_deg > 0.0) & sunlit & observer_dark
            for i0, i1 in _segments(visible):
                seg_alt = alt_deg[i0 : i1 + 1]
                max_i_local = int(np.argmax(seg_alt))
                max_elev = float(seg_alt[max_i_local])
                if max_elev < _MIN_CULMINATION_DEG:
                    continue
                max_i = i0 + max_i_local

                start_at = start + timedelta(seconds=float(offsets[i0]))
                end_at = start + timedelta(seconds=float(offsets[i1]))
                culm_at = start + timedelta(seconds=float(offsets[max_i]))

                mag = _approx_magnitude(max_elev, float(range_km[max_i]))

                # Esta passagem também é um trânsito do Sol/Lua? Roda o motor
                # fino na janela da passagem para cada corpo.
                is_transit = False
                transit_body: Optional[CelestialBody] = None
                tle_age = 0.0
                seg_span = float(offsets[i1] - offsets[i0]) + 2 * _COARSE_STEP_S
                seg_start = start + timedelta(
                    seconds=max(0.0, float(offsets[i0]) - _COARSE_STEP_S)
                )
                for body in (CelestialBody.SUN, CelestialBody.MOON):
                    st = find_satellite_transit(
                        loaded,
                        body,
                        self._ephemeris,
                        observer,
                        seg_start,
                        horizon_s=seg_span,
                        approach_gate_deg=_TRANSIT_GATE_DEG,
                        keep_no_overlap=False,
                    )
                    if st is not None:
                        tle_age = st.tle_age_hours
                        if st.candidate.is_transit:
                            is_transit = True
                            transit_body = body
                            break

                out.append(
                    VisiblePass(
                        satellite_id=loaded.object_id,
                        satellite_label=loaded.label,
                        start_utc=start_at,
                        culmination_utc=culm_at,
                        end_utc=end_at,
                        duration_s=round(float(offsets[i1] - offsets[i0]), 1),
                        max_elevation_deg=round(max_elev, 1),
                        start_azimuth_deg=round(float(az_deg[i0]), 1),
                        end_azimuth_deg=round(float(az_deg[i1]), 1),
                        approx_magnitude=mag,
                        tle_age_hours=round(tle_age, 1),
                        is_transit=is_transit,
                        transit_body=transit_body,
                    )
                )

        out.sort(key=lambda p: p.culmination_utc)
        return out
