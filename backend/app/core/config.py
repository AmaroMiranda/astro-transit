"""Application settings (RNF-006: keys only on the backend, from the environment)."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ASTRO_", env_file=".env", extra="ignore")

    # Search geometry (RF-004)
    default_radius_km: float = 80.0
    min_radius_km: float = 20.0
    max_radius_km: float = 250.0

    # Prediction horizon (RF-007)
    default_horizon_s: float = 120.0

    # Provider selection & failover (RF-005/006). airplanes.live and adsb.fi lead
    # for their community-feeder coverage over Brazil; adsb.lol/OpenSky back them up.
    aircraft_providers: list[str] = ["airplaneslive", "adsbfi", "adsblol", "opensky"]
    provider_timeout_s: float = 4.0
    cache_ttl_s: float = 5.0
    stale_after_s: float = 20.0  # beyond this, high-confidence alerts are suppressed

    # Optional OpenSky OAuth2 credentials (leave empty to use the anonymous tier)
    opensky_client_id: str = ""
    opensky_client_secret: str = ""

    # Satellite transits (ISS + Tiangong/CSS). NORAD catalogue ids; TLEs are fetched
    # from Celestrak and cached, then propagated with Skyfield.
    satellites_enabled: bool = True
    satellite_norad_ids: list[int] = [25544, 48274]  # ISS (ZARYA), CSS (TIANHE)
    tle_source_url: str = "https://celestrak.org/NORAD/elements/gp.php"
    tle_cache_hours: float = 6.0


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
