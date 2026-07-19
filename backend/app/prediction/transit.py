"""Transit detection and temporal refinement (RF-012, RF-013).

Given an aircraft state, a celestial position and an observer, this module finds the
instant of closest angular approach and classifies the resulting event.

The Sun/Moon move ~0.004 deg/s across the sky — about one full disc diameter over a
120 s horizon — so the body must NOT be frozen during the search: freezing it can
shift the detected instant by tens of seconds or flip a transit into a miss. The
caller passes the body position at the start *and* end of the horizon
(``body_end``) and the search interpolates linearly in between. Linear interpolation
is exact to well under 1 mdeg over <=600 s (the az/alt rates change on hour scales),
matching the approach validated in the satellite engine.
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


def _make_body_at(
    body: CelestialPosition,
    body_end: Optional[CelestialPosition],
    horizon_s: float,
) -> Callable[[float], tuple[float, float, float]]:
    """Return ``t -> (azimuth, altitude, angular_radius)`` for the body.

    Interpolates linearly (shortest-arc in azimuth) between the position at the
    start and at the end of the horizon. With ``body_end`` omitted the body is
    frozen — acceptable only for tests/synthetic scenarios.
    """
    if body_end is None or horizon_s <= 0.0:
        return lambda t: (
            body.azimuth_deg,
            body.altitude_deg,
            body.angular_radius_deg,
        )
    d_az = ((body_end.azimuth_deg - body.azimuth_deg + 180.0) % 360.0) - 180.0
    d_alt = body_end.altitude_deg - body.altitude_deg
    d_rad = body_end.angular_radius_deg - body.angular_radius_deg

    def at(t: float) -> tuple[float, float, float]:
        f = min(max(t / horizon_s, 0.0), 1.0)
        return (
            (body.azimuth_deg + f * d_az) % 360.0,
            body.altitude_deg + f * d_alt,
            body.angular_radius_deg + f * d_rad,
        )

    return at


def _separation_at(
    state: AircraftState,
    body_at: Callable[[float], tuple[float, float, float]],
    observer: ObserverLocation,
    t: float,
) -> _Sample:
    projected = project_state(state, t)
    topo = observer_relative(
        projected.latitude_deg, projected.longitude_deg, projected.altitude_m, observer
    )
    body_az, body_alt, _ = body_at(t)
    sep = angular_separation_deg(
        topo.azimuth_deg, topo.altitude_deg, body_az, body_alt
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


def classify_transit(
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
    body_end: Optional[CelestialPosition] = None,
) -> Optional[TransitCandidate]:
    """Find the closest approach of ``state`` to ``body`` within ``horizon_s``.

    ``body`` is the position at t=0 and ``body_end`` at t=``horizon_s``; the search
    interpolates between them so the body moves during the window (P0: freezing the
    Sun/Moon shifts the detected instant by up to tens of seconds).

    Returns ``None`` for aircraft on the ground or when the body is below the horizon.
    Otherwise returns a :class:`TransitCandidate` (possibly classified ``APPROACH`` /
    ``NONE``) describing the closest approach, refined to ``refine_tol_s`` (RF-013).
    """
    if state.on_ground or body.altitude_deg <= 0.0:
        return None

    body_at = _make_body_at(body, body_end, horizon_s)

    def sep_fn(t: float) -> float:
        return _separation_at(state, body_at, observer, t).separation_deg

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

    sample = _separation_at(state, body_at, observer, refined_t)
    body_az_t, body_alt_t, body_radius_t = body_at(refined_t)

    # Apparent size of the aircraft at the refined instant.
    projected = project_state(state, refined_t)
    topo = observer_relative(
        projected.latitude_deg, projected.longitude_deg, projected.altitude_m, observer
    )
    wingspan = CATEGORY_WINGSPAN_M[state.category]
    aircraft_radius_deg = angular_size_deg(wingspan, topo.range_m) / 2.0

    transit_class = classify_transit(
        sample.separation_deg, body_radius_t, aircraft_radius_deg, margin_deg
    )

    return TransitCandidate(
        icao24=state.icao24,
        body=body.body,
        time_to_transit_s=refined_t,
        min_separation_deg=sample.separation_deg,
        body_radius_deg=body_radius_t,
        aircraft_radius_deg=aircraft_radius_deg,
        transit_class=transit_class,
        aircraft_azimuth_deg=sample.aircraft_az,
        aircraft_altitude_deg=sample.aircraft_alt,
        body_azimuth_deg=body_az_t,
        body_altitude_deg=body_alt_t,
    )
