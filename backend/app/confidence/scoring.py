"""Transit confidence scoring (RF-016).

Produces a 0-100 score plus the list of factors that *reduced* it, so the UI can show
both the category and the reasons (SPEC RF-016: "o usuário deverá visualizar tanto a
categoria quanto os fatores que reduziram a confiança").

The model is deliberately transparent: start at 100 and subtract weighted penalties.
Weights are first-cut values meant to be recalibrated with field data (Fase 6).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

from app.domain.models import TransitCandidate


class ConfidenceCategory(str, Enum):
    VERY_LOW = "very_low"
    LOW = "low"
    MODERATE = "moderate"
    HIGH = "high"
    VERY_HIGH = "very_high"


def categorize(score: float) -> ConfidenceCategory:
    if score < 30:
        return ConfidenceCategory.VERY_LOW
    if score < 50:
        return ConfidenceCategory.LOW
    if score < 70:
        return ConfidenceCategory.MODERATE
    if score < 85:
        return ConfidenceCategory.HIGH
    return ConfidenceCategory.VERY_HIGH


@dataclass(frozen=True)
class ConfidenceFactor:
    """A single penalty applied to the score."""

    name: str
    penalty: float
    detail: str


@dataclass(frozen=True)
class ConfidenceResult:
    score: float
    category: ConfidenceCategory
    factors: tuple[ConfidenceFactor, ...]  # reasons the score is below 100


@dataclass(frozen=True)
class ConfidenceInputs:
    """Everything the scorer needs, decoupled from I/O for testability."""

    data_age_s: float                 # age of the ADS-B fix
    from_cache: bool
    degraded: bool                    # a provider fallback was used
    aircraft_distance_m: float
    gps_accuracy_m: Optional[float]
    track_points: int = 1             # number of recent positions available
    provider_latency_ms: Optional[float] = None


def score_candidate(
    candidate: TransitCandidate, inputs: ConfidenceInputs
) -> ConfidenceResult:
    """Score a transit candidate from 0-100 with itemized penalties (RF-016)."""
    factors: list[ConfidenceFactor] = []

    def penalize(name: str, penalty: float, detail: str) -> None:
        if penalty > 0:
            factors.append(ConfidenceFactor(name, penalty, detail))

    # 1) Data age — the single biggest driver (RF-006/016).
    age = inputs.data_age_s
    if age > 30:
        penalize("data_age", 45, f"Dados de {age:.0f}s")
    elif age > 20:
        penalize("data_age", 30, f"Dados de {age:.0f}s")
    elif age > 10:
        penalize("data_age", 15, f"Dados de {age:.0f}s")
    elif age > 5:
        penalize("data_age", 6, f"Dados de {age:.0f}s")

    # 2) Degraded / cached source.
    if inputs.degraded:
        penalize("degraded_source", 15, "Provedor de reserva ou cache em uso")
    elif inputs.from_cache:
        penalize("cache", 4, "Resultado servido do cache")

    # 3) Distance — far aircraft carry more positional angular error.
    dist_km = inputs.aircraft_distance_m / 1000.0
    if dist_km > 120:
        penalize("distance", 18, f"Aeronave a {dist_km:.0f} km")
    elif dist_km > 60:
        penalize("distance", 10, f"Aeronave a {dist_km:.0f} km")
    elif dist_km > 30:
        penalize("distance", 4, f"Aeronave a {dist_km:.0f} km")

    # 4) GPS accuracy of the observer.
    acc = inputs.gps_accuracy_m
    if acc is not None:
        if acc > 50:
            penalize("gps", 15, f"GPS ±{acc:.0f} m")
        elif acc > 20:
            penalize("gps", 7, f"GPS ±{acc:.0f} m")

    # 5) Trajectory support — few points means a fragile projection.
    if inputs.track_points <= 1:
        penalize("track_support", 10, "Trajetória com um único ponto")
    elif inputs.track_points < 4:
        penalize("track_support", 4, "Poucos pontos de trajetória")

    # 6) Margin within the disc — a central transit is more robust than a graze.
    if candidate.body_radius_deg > 0:
        margin = 1.0 - min(candidate.min_separation_deg / candidate.body_radius_deg, 1.0)
        if margin < 0.1:
            penalize("graze", 12, "Passagem próxima à borda do disco")
        elif margin < 0.3:
            penalize("edge", 5, "Trânsito não central")

    # 7) Provider latency.
    lat = inputs.provider_latency_ms
    if lat is not None and lat > 1500:
        penalize("latency", 5, f"Latência de {lat:.0f} ms")

    score = max(0.0, 100.0 - sum(f.penalty for f in factors))
    return ConfidenceResult(
        score=score,
        category=categorize(score),
        factors=tuple(factors),
    )


@dataclass(frozen=True)
class SatelliteConfidenceInputs:
    """Confidence drivers specific to a TLE-propagated satellite transit.

    A satellite's position is *predicted* from orbital elements, not sampled over
    ADS-B, so the aircraft penalties (distance, single track point, GPS positional
    error) don't apply. Precision is instead governed by how fresh the TLE is and how
    low the pass sits in the sky (atmospheric refraction + timing sensitivity grow
    near the horizon), plus how central the crossing is.
    """

    tle_age_hours: float
    altitude_deg: float
    gps_accuracy_m: Optional[float] = None


def score_satellite_candidate(
    candidate: TransitCandidate, inputs: SatelliteConfidenceInputs
) -> ConfidenceResult:
    """Score a satellite transit candidate 0-100 with itemized penalties (RF-016)."""
    factors: list[ConfidenceFactor] = []

    def penalize(name: str, penalty: float, detail: str) -> None:
        if penalty > 0:
            factors.append(ConfidenceFactor(name, penalty, detail))

    # 1) TLE freshness — the dominant driver for orbital predictions.
    age_h = inputs.tle_age_hours
    if age_h > 72:
        penalize("tle_age", 40, f"Efemérides (TLE) de {age_h / 24:.0f} dias")
    elif age_h > 36:
        penalize("tle_age", 22, f"Efemérides (TLE) de {age_h:.0f} h")
    elif age_h > 18:
        penalize("tle_age", 10, f"Efemérides (TLE) de {age_h:.0f} h")
    elif age_h > 8:
        penalize("tle_age", 4, f"Efemérides (TLE) de {age_h:.0f} h")

    # 2) Elevation — low passes are geometrically fragile and often blocked.
    alt = inputs.altitude_deg
    if alt < 10:
        penalize("low_pass", 25, f"Passagem baixa ({alt:.0f}° acima do horizonte)")
    elif alt < 20:
        penalize("low_pass", 12, f"Passagem a {alt:.0f}° de altura")
    elif alt < 30:
        penalize("low_pass", 4, f"Passagem a {alt:.0f}° de altura")

    # 3) Observer GPS accuracy — the satellite path is only a few km wide on the
    #    ground, so where you stand matters.
    acc = inputs.gps_accuracy_m
    if acc is not None:
        if acc > 50:
            penalize("gps", 12, f"GPS ±{acc:.0f} m")
        elif acc > 20:
            penalize("gps", 5, f"GPS ±{acc:.0f} m")

    # 4) How central the crossing is.
    if candidate.body_radius_deg > 0:
        margin = 1.0 - min(candidate.min_separation_deg / candidate.body_radius_deg, 1.0)
        if margin < 0.1:
            penalize("graze", 12, "Passagem próxima à borda do disco")
        elif margin < 0.3:
            penalize("edge", 5, "Trânsito não central")

    score = max(0.0, 100.0 - sum(f.penalty for f in factors))
    return ConfidenceResult(
        score=score,
        category=categorize(score),
        factors=tuple(factors),
    )
