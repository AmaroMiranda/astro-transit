"""Tests for the confidence scoring model (RF-016)."""

import pytest

from app.confidence.scoring import ConfidenceCategory, ConfidenceInputs, categorize, score_candidate
from app.domain.models import (
    CelestialBody,
    TransitCandidate,
    TransitClass,
)


def _candidate(min_sep=0.02, body_radius=0.259) -> TransitCandidate:
    return TransitCandidate(
        icao24="abc123",
        body=CelestialBody.MOON,
        time_to_transit_s=30.0,
        min_separation_deg=min_sep,
        body_radius_deg=body_radius,
        aircraft_radius_deg=0.01,
        transit_class=TransitClass.CENTRAL,
        aircraft_azimuth_deg=100.0,
        aircraft_altitude_deg=40.0,
        body_azimuth_deg=100.0,
        body_altitude_deg=40.0,
    )


def test_pristine_inputs_score_near_100():
    result = score_candidate(
        _candidate(),
        ConfidenceInputs(
            data_age_s=1.0,
            from_cache=False,
            degraded=False,
            aircraft_distance_m=10_000.0,
            gps_accuracy_m=5.0,
            track_points=10,
        ),
    )
    assert result.score > 90
    assert result.category == ConfidenceCategory.VERY_HIGH


def test_stale_degraded_data_scores_low():
    result = score_candidate(
        _candidate(),
        ConfidenceInputs(
            data_age_s=40.0,
            from_cache=True,
            degraded=True,
            aircraft_distance_m=150_000.0,
            gps_accuracy_m=60.0,
            track_points=1,
        ),
    )
    assert result.score < 40
    assert len(result.factors) >= 4


def test_score_never_below_zero():
    result = score_candidate(
        _candidate(min_sep=0.25, body_radius=0.259),
        ConfidenceInputs(
            data_age_s=300.0,
            from_cache=True,
            degraded=True,
            aircraft_distance_m=500_000.0,
            gps_accuracy_m=200.0,
            track_points=1,
            provider_latency_ms=5000.0,
        ),
    )
    assert result.score >= 0.0


def test_graze_reduces_score_more_than_central():
    central = score_candidate(
        _candidate(min_sep=0.01, body_radius=0.259),
        ConfidenceInputs(1.0, False, False, 10_000.0, 5.0, 10),
    )
    graze = score_candidate(
        _candidate(min_sep=0.25, body_radius=0.259),
        ConfidenceInputs(1.0, False, False, 10_000.0, 5.0, 10),
    )
    assert graze.score < central.score


@pytest.mark.parametrize(
    "score,expected",
    [
        (10, ConfidenceCategory.VERY_LOW),
        (35, ConfidenceCategory.LOW),
        (60, ConfidenceCategory.MODERATE),
        (80, ConfidenceCategory.HIGH),
        (95, ConfidenceCategory.VERY_HIGH),
    ],
)
def test_categorize_boundaries(score, expected):
    assert categorize(score) == expected


def test_factors_have_human_readable_detail():
    result = score_candidate(
        _candidate(),
        ConfidenceInputs(
            data_age_s=25.0,
            from_cache=False,
            degraded=False,
            aircraft_distance_m=10_000.0,
            gps_accuracy_m=5.0,
            track_points=10,
        ),
    )
    assert any("Dados de" in f.detail for f in result.factors)
