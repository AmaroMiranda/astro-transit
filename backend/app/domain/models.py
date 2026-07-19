"""Core domain models.

These are pure data containers (no I/O, no framework dependencies) so they can be
reused by the astronomy, geometry and prediction layers and unit-tested in isolation.
All angles are stored in **degrees** unless the field name says otherwise; all
distances in **metres**; all timestamps are timezone-aware UTC.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# --------------------------------------------------------------------------- #
# Observer & targets
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class ObserverLocation:
    """Topocentric location of the observer (RF-001)."""

    latitude_deg: float
    longitude_deg: float
    altitude_m: float = 0.0
    horizontal_accuracy_m: Optional[float] = None
    vertical_accuracy_m: Optional[float] = None
    timestamp_utc: datetime = field(default_factory=_utcnow)


class CelestialBody(str, Enum):
    SUN = "sun"
    MOON = "moon"


@dataclass(frozen=True)
class CelestialPosition:
    """Apparent topocentric position of Sun or Moon (RF-002, RF-003, RF-010)."""

    body: CelestialBody
    azimuth_deg: float
    altitude_deg: float
    distance_m: float
    angular_radius_deg: float
    illumination: Optional[float] = None  # 0..1, meaningful for the Moon
    timestamp_utc: datetime = field(default_factory=_utcnow)


# --------------------------------------------------------------------------- #
# Aircraft
# --------------------------------------------------------------------------- #

class AircraftCategory(str, Enum):
    SMALL = "small"
    NARROW_BODY = "narrow_body"
    WIDE_BODY = "wide_body"
    CARGO = "cargo"
    HELICOPTER = "helicopter"
    UNKNOWN = "unknown"


# Representative wingspan (m) per category, used when the exact model is unknown
# (RF-011). Wingspan is the dominant dimension seen against the disc for an
# aircraft crossing roughly perpendicular to the line of sight.
CATEGORY_WINGSPAN_M: dict[AircraftCategory, float] = {
    AircraftCategory.SMALL: 12.0,
    AircraftCategory.NARROW_BODY: 35.0,
    AircraftCategory.WIDE_BODY: 60.0,
    AircraftCategory.CARGO: 65.0,
    AircraftCategory.HELICOPTER: 14.0,
    AircraftCategory.UNKNOWN: 35.0,
}


@dataclass(frozen=True)
class AircraftState:
    """A single ADS-B state vector (RF-004), normalized across providers (RF-005)."""

    icao24: str
    latitude_deg: float
    longitude_deg: float
    geometric_altitude_m: float
    ground_speed_mps: float
    track_deg: float               # heading over ground, 0 = north, clockwise
    vertical_rate_mps: float = 0.0
    callsign: Optional[str] = None
    on_ground: bool = False
    category: AircraftCategory = AircraftCategory.UNKNOWN
    timestamp_utc: datetime = field(default_factory=_utcnow)
    # False when the feed omitted altitude, speed or track and a placeholder was
    # substituted. Such aircraft may be *displayed*, but must never enter the
    # prediction engine — "unknown" is not "zero" (a missing track would be
    # silently treated as flying due north).
    telemetry_complete: bool = True

    @property
    def age_seconds(self) -> float:
        return (_utcnow() - self.timestamp_utc).total_seconds()


@dataclass(frozen=True)
class ProjectedAircraftState:
    """Aircraft position projected forward in time (RF-007)."""

    icao24: str
    latitude_deg: float
    longitude_deg: float
    altitude_m: float
    offset_seconds: float          # seconds ahead of the source state


# --------------------------------------------------------------------------- #
# Observer-relative geometry
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class TopocentricVector:
    """Direction + range of a target relative to the observer (RF-008)."""

    azimuth_deg: float
    altitude_deg: float
    range_m: float


# --------------------------------------------------------------------------- #
# Transit prediction
# --------------------------------------------------------------------------- #

class TransitClass(str, Enum):
    CENTRAL = "central"
    NEAR_CENTRAL = "near_central"
    PARTIAL = "partial"
    GRAZE = "graze"
    APPROACH = "approach"
    NONE = "none"


class TransitObjectKind(str, Enum):
    """What kind of object is crossing the disc — an aircraft or a satellite.

    The transit geometry is identical (a small body silhouetted against the disc),
    but the data source, angular rate and confidence model differ (RF-005).
    """

    AIRCRAFT = "aircraft"
    SATELLITE = "satellite"


@dataclass(frozen=True)
class TransitCandidate:
    """Result of evaluating one crossing object against one body at closest approach.

    ``icao24`` is the generic object id (an ICAO24 hex for aircraft, a NORAD id string
    for satellites). ``aircraft_radius_deg`` is the crossing object's apparent radius
    regardless of kind — kept named for wire compatibility.
    """

    icao24: str
    body: CelestialBody
    time_to_transit_s: float          # seconds from the reference epoch
    min_separation_deg: float         # smallest angular gap centre-to-centre
    body_radius_deg: float
    aircraft_radius_deg: float
    transit_class: TransitClass
    aircraft_azimuth_deg: float
    aircraft_altitude_deg: float
    body_azimuth_deg: float
    body_altitude_deg: float
    object_kind: TransitObjectKind = TransitObjectKind.AIRCRAFT
    object_label: Optional[str] = None   # human-friendly name (callsign / "ISS")

    @property
    def is_transit(self) -> bool:
        return self.transit_class not in (TransitClass.APPROACH, TransitClass.NONE)
