"""Pydantic request/response models for the v1 API (SPEC section 14).

These are the wire contracts. They are intentionally separate from the domain
dataclasses so the internal model can evolve without breaking clients, and vice versa.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.confidence.scoring import ConfidenceResult
from app.domain.models import (
    CelestialBody,
    CelestialPosition,
    TransitCandidate,
    TransitClass,
    TransitObjectKind,
)
from app.services.prediction_service import PredictionResponse, TransitPrediction


# --------------------------------------------------------------------------- #
# Requests
# --------------------------------------------------------------------------- #

class ObserverIn(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    altitude_m: float = 0.0
    horizontal_accuracy_m: Optional[float] = None


class PredictIn(BaseModel):
    observer: ObserverIn
    targets: list[CelestialBody] = [CelestialBody.SUN, CelestialBody.MOON]
    horizon_seconds: float = Field(120.0, gt=0, le=600)
    max_radius_km: float = Field(80.0, gt=0, le=250)


# --------------------------------------------------------------------------- #
# Responses
# --------------------------------------------------------------------------- #

class CelestialPositionOut(BaseModel):
    target: CelestialBody
    azimuth_deg: float
    altitude_deg: float
    angular_radius_deg: float
    distance_m: float
    illumination: Optional[float] = None
    timestamp_utc: datetime

    @classmethod
    def of(cls, p: CelestialPosition) -> "CelestialPositionOut":
        return cls(
            target=p.body,
            azimuth_deg=round(p.azimuth_deg, 4),
            altitude_deg=round(p.altitude_deg, 4),
            angular_radius_deg=round(p.angular_radius_deg, 5),
            distance_m=p.distance_m,
            illumination=p.illumination,
            timestamp_utc=p.timestamp_utc,
        )


class ConfidenceFactorOut(BaseModel):
    name: str
    penalty: float
    detail: str


class ConfidenceOut(BaseModel):
    score: float
    category: str
    factors: list[ConfidenceFactorOut]

    @classmethod
    def of(cls, c: ConfidenceResult) -> "ConfidenceOut":
        return cls(
            score=round(c.score, 1),
            category=c.category.value,
            factors=[
                ConfidenceFactorOut(name=f.name, penalty=f.penalty, detail=f.detail)
                for f in c.factors
            ],
        )


class TransitCandidateOut(BaseModel):
    icao24: str
    body: CelestialBody
    time_to_transit_s: float
    min_separation_deg: float
    body_radius_deg: float
    aircraft_radius_deg: float
    transit_class: TransitClass
    aircraft_azimuth_deg: float
    aircraft_altitude_deg: float
    object_kind: TransitObjectKind = TransitObjectKind.AIRCRAFT
    object_label: Optional[str] = None

    @classmethod
    def of(cls, c: TransitCandidate) -> "TransitCandidateOut":
        return cls(
            icao24=c.icao24,
            body=c.body,
            time_to_transit_s=round(c.time_to_transit_s, 2),
            min_separation_deg=round(c.min_separation_deg, 5),
            body_radius_deg=round(c.body_radius_deg, 5),
            aircraft_radius_deg=round(c.aircraft_radius_deg, 5),
            transit_class=c.transit_class,
            aircraft_azimuth_deg=round(c.aircraft_azimuth_deg, 3),
            aircraft_altitude_deg=round(c.aircraft_altitude_deg, 3),
            object_kind=c.object_kind,
            object_label=c.object_label,
        )


class CorridorOut(BaseModel):
    center_latitude: float
    center_longitude: float
    half_width_m: float
    distance_from_observer_m: float
    bearing_from_observer_deg: float

    @classmethod
    def of(cls, c) -> "CorridorOut":
        return cls(
            center_latitude=round(c.center_lat_deg, 6),
            center_longitude=round(c.center_lon_deg, 6),
            half_width_m=round(c.half_width_m, 1),
            distance_from_observer_m=round(c.distance_from_observer_m, 1),
            bearing_from_observer_deg=round(c.bearing_from_observer_deg, 1),
        )


class TransitPredictionOut(BaseModel):
    candidate: TransitCandidateOut
    confidence: ConfidenceOut
    callsign: Optional[str]
    aircraft_distance_m: float
    data_age_s: float
    corridor: Optional[CorridorOut] = None

    @classmethod
    def of(cls, p: TransitPrediction) -> "TransitPredictionOut":
        return cls(
            candidate=TransitCandidateOut.of(p.candidate),
            confidence=ConfidenceOut.of(p.confidence),
            callsign=p.callsign,
            aircraft_distance_m=round(p.aircraft_distance_m, 1),
            data_age_s=round(p.data_age_s, 1),
            corridor=CorridorOut.of(p.corridor) if p.corridor else None,
        )


class PredictionOut(BaseModel):
    generated_at_utc: datetime
    provider: str
    data_degraded: bool
    aircraft_considered: int
    bodies: list[CelestialPositionOut]
    predictions: list[TransitPredictionOut]

    @classmethod
    def of(cls, r: PredictionResponse) -> "PredictionOut":
        return cls(
            generated_at_utc=r.generated_at_utc,
            provider=r.provider_name,
            data_degraded=r.data_degraded,
            aircraft_considered=r.aircraft_considered,
            bodies=[CelestialPositionOut.of(b) for b in r.bodies],
            predictions=[TransitPredictionOut.of(p) for p in r.predictions],
        )


class SatellitePassOut(BaseModel):
    """One upcoming (multi-day) satellite transit — deterministic planning."""

    satellite_id: str
    satellite_label: str
    body: CelestialBody
    transit_at_utc: datetime
    transit_class: TransitClass
    duration_s: float
    elevation_deg: float
    azimuth_deg: float
    slant_range_m: float
    min_separation_deg: float
    body_radius_deg: float
    tle_age_hours: float
    corridor: Optional[CorridorOut] = None

    @classmethod
    def of(cls, p) -> "SatellitePassOut":
        c = p.transit.candidate
        return cls(
            satellite_id=p.satellite_id,
            satellite_label=p.satellite_label,
            body=c.body,
            transit_at_utc=p.transit_at_utc,
            transit_class=c.transit_class,
            duration_s=round(p.transit.transit_duration_s, 2),
            elevation_deg=round(c.aircraft_altitude_deg, 2),
            azimuth_deg=round(c.aircraft_azimuth_deg, 2),
            slant_range_m=round(p.transit.slant_range_m, 0),
            min_separation_deg=round(c.min_separation_deg, 5),
            body_radius_deg=round(c.body_radius_deg, 5),
            tle_age_hours=round(p.transit.tle_age_hours, 1),
            corridor=CorridorOut.of(p.corridor) if p.corridor else None,
        )


class SatellitePassesOut(BaseModel):
    generated_at_utc: datetime
    hours: float
    count: int
    passes: list[SatellitePassOut]


class VisiblePassOut(BaseModel):
    """Uma passagem VISÍVEL da estação (a olho nu), para registro — mesmo sem
    trânsito. `is_transit` marca as que também cruzam o Sol/Lua."""

    satellite_id: str
    satellite_label: str
    start_utc: datetime
    culmination_utc: datetime
    end_utc: datetime
    duration_s: float
    max_elevation_deg: float
    start_azimuth_deg: float
    end_azimuth_deg: float
    approx_magnitude: float
    tle_age_hours: float
    is_transit: bool
    transit_body: Optional[CelestialBody] = None

    @classmethod
    def of(cls, p) -> "VisiblePassOut":
        return cls(
            satellite_id=p.satellite_id,
            satellite_label=p.satellite_label,
            start_utc=p.start_utc,
            culmination_utc=p.culmination_utc,
            end_utc=p.end_utc,
            duration_s=p.duration_s,
            max_elevation_deg=p.max_elevation_deg,
            start_azimuth_deg=p.start_azimuth_deg,
            end_azimuth_deg=p.end_azimuth_deg,
            approx_magnitude=p.approx_magnitude,
            tle_age_hours=p.tle_age_hours,
            is_transit=p.is_transit,
            transit_body=p.transit_body,
        )


class VisiblePassesOut(BaseModel):
    generated_at_utc: datetime
    hours: float
    count: int
    passes: list[VisiblePassOut]


class AircraftOut(BaseModel):
    icao24: str
    callsign: Optional[str]
    latitude: float
    longitude: float
    altitude_m: float
    ground_speed_mps: float
    track_deg: float
    vertical_rate_mps: float
    on_ground: bool
    category: str
    age_s: float
    # Topocentric direction as seen from the query point — lets clients (radar)
    # plot every aircraft in the sky without redoing the geodetic geometry.
    azimuth_deg: Optional[float] = None
    altitude_deg: Optional[float] = None
    distance_m: Optional[float] = None


class NearbyOut(BaseModel):
    provider: str
    data_degraded: bool
    count: int
    aircraft: list[AircraftOut]
