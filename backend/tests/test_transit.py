"""End-to-end tests for transit detection and refinement.

Strategy: build a self-consistent scenario. Pick an aircraft trajectory, project it
to a chosen instant, read off the direction the observer sees it, and *place the body
exactly there*. The detector must then rediscover that instant with a near-zero
separation — exercising projection, ECEF/ENU, separation and refinement together.
"""

import pytest

from app.domain.models import (
    AircraftCategory,
    AircraftState,
    CelestialBody,
    CelestialPosition,
    ObserverLocation,
    TransitClass,
)
from app.geometry.coordinates import observer_relative
from app.prediction.projection import project_state
from app.prediction.transit import find_transit_candidate

OBSERVER = ObserverLocation(latitude_deg=0.0, longitude_deg=0.0, altitude_m=0.0)


def _aircraft(**kwargs) -> AircraftState:
    base = dict(
        icao24="test01",
        latitude_deg=-0.10,          # starts south of the observer
        longitude_deg=0.05,          # ~5.5 km east
        geometric_altitude_m=10_000.0,
        ground_speed_mps=250.0,
        track_deg=0.0,               # heading due north
        category=AircraftCategory.NARROW_BODY,
    )
    base.update(kwargs)
    return AircraftState(**base)


def _body_on_aircraft_line(state: AircraftState, t: float, radius_deg: float) -> CelestialPosition:
    """Place a body exactly where the aircraft will appear at time ``t``."""
    p = project_state(state, t)
    topo = observer_relative(p.latitude_deg, p.longitude_deg, p.altitude_m, OBSERVER)
    return CelestialPosition(
        body=CelestialBody.MOON,
        azimuth_deg=topo.azimuth_deg,
        altitude_deg=topo.altitude_deg,
        distance_m=384_400_000.0,
        angular_radius_deg=radius_deg,
    )


def test_perfect_alignment_is_detected_as_transit():
    ac = _aircraft()
    body = _body_on_aircraft_line(ac, t=30.0, radius_deg=0.259)

    cand = find_transit_candidate(ac, body, OBSERVER, horizon_s=120.0)

    assert cand is not None
    assert cand.is_transit
    assert cand.time_to_transit_s == pytest.approx(30.0, abs=0.2)
    assert cand.min_separation_deg < 0.05


def test_central_transit_classification():
    ac = _aircraft()
    body = _body_on_aircraft_line(ac, t=45.0, radius_deg=0.259)
    cand = find_transit_candidate(ac, body, OBSERVER, horizon_s=120.0)
    assert cand is not None
    assert cand.transit_class in (TransitClass.CENTRAL, TransitClass.NEAR_CENTRAL)


def test_aircraft_on_ground_yields_no_candidate():
    ac = _aircraft(on_ground=True)
    body = _body_on_aircraft_line(_aircraft(), t=30.0, radius_deg=0.259)
    assert find_transit_candidate(ac, body, OBSERVER) is None


def test_body_below_horizon_yields_no_candidate():
    ac = _aircraft()
    body = CelestialPosition(
        body=CelestialBody.SUN,
        azimuth_deg=90.0,
        altitude_deg=-5.0,           # below the horizon
        distance_m=1.496e11,
        angular_radius_deg=0.266,
    )
    assert find_transit_candidate(ac, body, OBSERVER) is None


def test_miss_is_classified_none_or_approach():
    ac = _aircraft()
    # Body 5 deg away from the aircraft's closest approach direction.
    body = _body_on_aircraft_line(ac, t=30.0, radius_deg=0.259)
    far_body = CelestialPosition(
        body=body.body,
        azimuth_deg=body.azimuth_deg + 5.0,
        altitude_deg=body.altitude_deg,
        distance_m=body.distance_m,
        angular_radius_deg=body.angular_radius_deg,
    )
    cand = find_transit_candidate(ac, far_body, OBSERVER, horizon_s=120.0)
    assert cand is not None
    assert not cand.is_transit
    assert cand.min_separation_deg > 1.0


def test_refinement_improves_on_coarse_grid():
    # Align the body at a fractional second (17.4 s) that the 1 s grid cannot hit.
    ac = _aircraft()
    body = _body_on_aircraft_line(ac, t=17.4, radius_deg=0.259)
    cand = find_transit_candidate(ac, body, OBSERVER, horizon_s=60.0, refine_tol_s=0.05)
    assert cand is not None
    assert cand.time_to_transit_s == pytest.approx(17.4, abs=0.1)
