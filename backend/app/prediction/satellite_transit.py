"""Satellite transit detection (ISS, Tiangong) across the Sun/Moon disc.

Geometrically this is the same problem as an aircraft transit — a small object
silhouetted against the disc — but a satellite moves ~0.5-1.3 deg/s across the sky, so
a whole crossing lasts well under a second. Two consequences drive the design:

* We cannot linearly project a constant-velocity ground track (as aircraft do); we
  propagate the real orbit with Skyfield/SGP4 at each instant.
* The Sun/Moon's own ~0.004 deg/s drift is negligible per crossing but not over the
  full look-ahead window, so both bodies are evaluated at every sample.

The search is fully vectorized: build one Skyfield ``Time`` array over the horizon,
evaluate the satellite and the body together, then find and refine the closest
angular approach. This keeps a two-satellite / two-body prediction well under the
per-request budget.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

import numpy as np
from skyfield.api import wgs84

from app.astronomy.ephemeris import EphemerisService
from app.astronomy.satellites import LoadedSatellite
from app.domain.models import (
    CelestialBody,
    ObserverLocation,
    TransitCandidate,
    TransitClass,
    TransitObjectKind,
)
from app.geometry.angles import angular_size_deg, apparent_radius_deg
from app.prediction.transit import classify_transit

# Coarse look-ahead step. The separation-vs-time curve over a single pass is smooth
# and single-valleyed, so 2 s locates the closest-approach bracket; refinement then
# pins the instant to well under the sub-second transit duration.
_COARSE_STEP_S = 2.0
_REFINE_SAMPLES = 61
# Skip the expensive refinement unless the coarse minimum is at least in the
# neighbourhood of the disc (body radius ~0.27 deg; 1.5 deg is a generous gate).
_APPROACH_GATE_DEG = 1.5
_MARGIN_DEG = 0.05


@dataclass(frozen=True)
class SatelliteTransit:
    """A satellite transit candidate plus the extras the service/map need."""

    candidate: TransitCandidate
    subpoint_lat_deg: float          # ground point under the satellite at transit
    subpoint_lon_deg: float
    subpoint_alt_m: float            # satellite geometric altitude there
    slant_range_m: float             # observer-to-satellite distance at transit
    tle_age_hours: float


def _separation_deg_array(
    alt1: np.ndarray, az1: np.ndarray, alt2: np.ndarray, az2: np.ndarray
) -> np.ndarray:
    """Great-circle separation (deg) between two alt/az directions, vectorized.

    Spherical law of cosines — equivalent to the ENU dot product used elsewhere
    (RF-009), clamped for numerical safety.
    """
    a1, z1 = np.radians(alt1), np.radians(az1)
    a2, z2 = np.radians(alt2), np.radians(az2)
    cos_sep = np.sin(a1) * np.sin(a2) + np.cos(a1) * np.cos(a2) * np.cos(z1 - z2)
    cos_sep = np.clip(cos_sep, -1.0, 1.0)
    return np.degrees(np.arccos(cos_sep))


def _times_from_offsets(ts, when: datetime, offsets_s: np.ndarray):
    base = when.astimezone(timezone.utc)
    return ts.from_datetimes(
        [base + timedelta(seconds=float(o)) for o in offsets_s]
    )


def _tle_age_hours(satellite, when: datetime) -> float:
    epoch = satellite.epoch.utc_datetime()
    return max(0.0, (when.astimezone(timezone.utc) - epoch).total_seconds() / 3600.0)


def find_satellite_transit(
    loaded: LoadedSatellite,
    body: CelestialBody,
    ephemeris: EphemerisService,
    observer: ObserverLocation,
    when: datetime,
    horizon_s: float = 120.0,
) -> Optional[SatelliteTransit]:
    """Closest approach of ``loaded`` to ``body`` within ``horizon_s`` of ``when``.

    Returns ``None`` when the satellite never rises above the horizon while the body
    is up, or when the closest approach is nowhere near the disc. The returned
    candidate may still be classified ``APPROACH`` (the caller filters non-transits).
    """
    ts = ephemeris.timescale
    site = wgs84.latlon(
        observer.latitude_deg, observer.longitude_deg, elevation_m=observer.altitude_m
    )
    difference = loaded.satellite - site

    # Coarse scan.
    n = max(2, int(horizon_s / _COARSE_STEP_S) + 1)
    offsets = np.linspace(0.0, horizon_s, n)
    times = _times_from_offsets(ts, when, offsets)

    topocentric = difference.at(times)
    sat_alt, sat_az, _ = topocentric.altaz()
    body_alt, body_az, _ = ephemeris.altaz_series(body, observer, times)

    sep = _separation_deg_array(sat_alt.degrees, sat_az.degrees, body_alt, body_az)
    both_up = (sat_alt.degrees > 0.0) & (body_alt > 0.0)
    sep = np.where(both_up, sep, np.inf)
    if not np.isfinite(sep).any():
        return None

    i = int(np.argmin(sep))
    if not np.isfinite(sep[i]) or sep[i] > _APPROACH_GATE_DEG:
        return None

    # Refine around the coarse minimum on a fine grid (one vectorized evaluation).
    lo = max(0.0, offsets[i] - _COARSE_STEP_S)
    hi = min(horizon_s, offsets[i] + _COARSE_STEP_S)
    fine_offsets = np.linspace(lo, hi, _REFINE_SAMPLES)
    fine_times = _times_from_offsets(ts, when, fine_offsets)

    fine_topo = difference.at(fine_times)
    fsat_alt, fsat_az, fsat_dist = fine_topo.altaz()
    fbody_alt, fbody_az, _ = ephemeris.altaz_series(body, observer, fine_times)
    fine_sep = _separation_deg_array(
        fsat_alt.degrees, fsat_az.degrees, fbody_alt, fbody_az
    )
    fine_sep = np.where(
        (fsat_alt.degrees > 0.0) & (fbody_alt > 0.0), fine_sep, np.inf
    )
    if not np.isfinite(fine_sep).any():
        return None
    j = int(np.argmin(fine_sep))
    refined_t = float(fine_offsets[j])
    min_sep = float(fine_sep[j])
    sat_altitude = float(fsat_alt.degrees[j])
    sat_azimuth = float(fsat_az.degrees[j])
    slant_range_m = float(fsat_dist.m[j])

    # Body apparent radius at the refined instant (RF-010).
    refined_when = when.astimezone(timezone.utc) + timedelta(seconds=refined_t)
    body_pos = ephemeris.position(body, observer, refined_when)

    sat_radius_deg = angular_size_deg(loaded.size_m, slant_range_m) / 2.0
    transit_class = classify_transit(
        min_sep, body_pos.angular_radius_deg, sat_radius_deg, _MARGIN_DEG
    )
    if transit_class in (TransitClass.NONE,):
        return None

    # Sub-satellite ground point at transit (for the map corridor).
    geocentric = loaded.satellite.at(_times_from_offsets(ts, when, np.array([refined_t])))
    sub = wgs84.subpoint(geocentric)
    subpoint_lat = float(np.atleast_1d(sub.latitude.degrees)[0])
    subpoint_lon = float(np.atleast_1d(sub.longitude.degrees)[0])
    subpoint_alt = float(np.atleast_1d(sub.elevation.m)[0])

    candidate = TransitCandidate(
        icao24=loaded.object_id,
        body=body,
        time_to_transit_s=refined_t,
        min_separation_deg=min_sep,
        body_radius_deg=body_pos.angular_radius_deg,
        aircraft_radius_deg=sat_radius_deg,
        transit_class=transit_class,
        aircraft_azimuth_deg=sat_azimuth,
        aircraft_altitude_deg=sat_altitude,
        body_azimuth_deg=body_pos.azimuth_deg,
        body_altitude_deg=body_pos.altitude_deg,
        object_kind=TransitObjectKind.SATELLITE,
        object_label=loaded.label,
    )
    return SatelliteTransit(
        candidate=candidate,
        subpoint_lat_deg=subpoint_lat,
        subpoint_lon_deg=subpoint_lon,
        subpoint_alt_m=subpoint_alt,
        slant_range_m=slant_range_m,
        tle_age_hours=_tle_age_hours(loaded.satellite, when),
    )
