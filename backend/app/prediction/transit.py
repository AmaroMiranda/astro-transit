"""Transit detection and temporal refinement (RF-012, RF-013).

Given an aircraft state, a celestial position and an observer, this module finds the
instant of closest angular approach and classifies the resulting event.

The celestial body is treated as fixed over the short (<=120 s) horizon: the Sun and
Moon move ~0.004 deg/s across the sky, which is negligible next to aircraft angular
rates. If higher fidelity is ever required, ``body_at`` can be made time-dependent.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

from app.domain.models import (
    CATEGORY_WINGSPAN_M,
    AircraftState,
    CelestialPosition,
    ObserverLocation,
    TransitCandidate,
    TransitClass,
)
from app.geometry.angles import angular_separation_deg, angular_size_deg
from app.geometry.coordinates import observer_relative
from app.prediction.projection import project_state

# Classification is expressed as a fraction of the *body* radius, so it scales with
# whichever body is selected. ``overlap`` = how far the aircraft centre is inside the
# disc, normalized: 0 = centre dead-on, 1 = grazing the limb.
_NEAR_CENTRAL_FRACTION = 0.25
_PARTIAL_FRACTION = 0.75


@dataclass(frozen=True)
class _Sample:
    separation_deg: float
    aircraft_az: float
    aircraft_alt: float


def _separation_at(
    state: AircraftState,
    body: CelestialPosition,
    observer: ObserverLocation,
    t: float,
) -> _Sample:
    projected = project_state(state, t)
    topo = observer_relative(
        projected.latitude_deg, projected.longitude_deg, projected.altitude_m, observer
    )
    sep = angular_separation_deg(
        topo.azimuth_deg, topo.altitude_deg, body.azimuth_deg, body.altitude_deg
    )
    return _Sample(sep, topo.azimuth_deg, topo.altitude_deg)


def _golden_section_min(
    f: Callable[[float], float], lo: float, hi: float, tol: float
) -> float:
    """Return the ``t`` in [lo, hi] minimizing unimodal ``f`` (RF-013)."""
    inv_phi = (5.0 ** 0.5 - 1.0) / 2.0          # 1/phi
    inv_phi2 = (3.0 - 5.0 ** 0.5) / 2.0         # 1/phi^2
    a, b = lo, hi
    h = b - a
    c = a + inv_phi2 * h
    d = a + inv_phi * h
    fc, fd = f(c), f(d)
    while h > tol:
        if fc < fd:
            b, d, fd = d, c, fc
            h = b - a
            c = a + inv_phi2 * h
            fc = f(c)
        else:
            a, c, fc = c, d, fd
            h = b - a
            d = a + inv_phi * h
            fd = f(d)
    return (a + b) / 2.0


def _classify(
    min_sep_deg: float, body_radius_deg: float, aircraft_radius_deg: float, margin_deg: float
) -> TransitClass:
    threshold = body_radius_deg + aircraft_radius_deg + margin_deg
    if min_sep_deg > threshold:
        return TransitClass.NONE
    # Aircraft centre relative to the disc limb.
    if min_sep_deg > body_radius_deg + aircraft_radius_deg:
        return TransitClass.APPROACH
    if min_sep_deg >= body_radius_deg:
        return TransitClass.GRAZE
    # Aircraft centre is inside the disc; grade by how central it is.
    overlap_fraction = min_sep_deg / body_radius_deg if body_radius_deg > 0 else 1.0
    if overlap_fraction <= _NEAR_CENTRAL_FRACTION:
        return TransitClass.CENTRAL if overlap_fraction <= 0.05 else TransitClass.NEAR_CENTRAL
    if overlap_fraction <= _PARTIAL_FRACTION:
        return TransitClass.NEAR_CENTRAL
    return TransitClass.PARTIAL


def find_transit_candidate(
    state: AircraftState,
    body: CelestialPosition,
    observer: ObserverLocation,
    horizon_s: float = 120.0,
    coarse_step_s: float = 1.0,
    refine_tol_s: float = 0.1,
    margin_deg: float = 0.05,
) -> Optional[TransitCandidate]:
    """Find the closest approach of ``state`` to ``body`` within ``horizon_s``.

    Returns ``None`` for aircraft on the ground or when the body is below the horizon.
    Otherwise returns a :class:`TransitCandidate` (possibly classified ``APPROACH`` /
    ``NONE``) describing the closest approach, refined to ``refine_tol_s`` (RF-013).
    """
    if state.on_ground or body.altitude_deg <= 0.0:
        return None

    def sep_fn(t: float) -> float:
        return _separation_at(state, body, observer, t).separation_deg

    # Coarse scan on a 1 s grid to locate the minimum bracket (RF stage 2).
    best_t = 0.0
    best_sep = sep_fn(0.0)
    t = coarse_step_s
    while t <= horizon_s + 1e-9:
        sep = sep_fn(t)
        if sep < best_sep:
            best_sep, best_t = sep, t
        t += coarse_step_s

    # Refine within the neighbouring interval using golden-section search (RF stage 3).
    lo = max(0.0, best_t - coarse_step_s)
    hi = min(horizon_s, best_t + coarse_step_s)
    refined_t = _golden_section_min(sep_fn, lo, hi, refine_tol_s)

    sample = _separation_at(state, body, observer, refined_t)

    # Apparent size of the aircraft at the refined instant.
    projected = project_state(state, refined_t)
    topo = observer_relative(
        projected.latitude_deg, projected.longitude_deg, projected.altitude_m, observer
    )
    wingspan = CATEGORY_WINGSPAN_M[state.category]
    aircraft_radius_deg = angular_size_deg(wingspan, topo.range_m) / 2.0

    transit_class = _classify(
        sample.separation_deg, body.angular_radius_deg, aircraft_radius_deg, margin_deg
    )

    return TransitCandidate(
        icao24=state.icao24,
        body=body.body,
        time_to_transit_s=refined_t,
        min_separation_deg=sample.separation_deg,
        body_radius_deg=body.angular_radius_deg,
        aircraft_radius_deg=aircraft_radius_deg,
        transit_class=transit_class,
        aircraft_azimuth_deg=sample.aircraft_az,
        aircraft_altitude_deg=sample.aircraft_alt,
        body_azimuth_deg=body.azimuth_deg,
        body_altitude_deg=body.altitude_deg,
    )
