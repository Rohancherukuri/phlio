"""
Application configuration.

All runtime configuration is read from environment variables (optionally via
a local `.env` file, see `.env.example`) through a single `Settings` object,
following the twelve-factor principle of keeping config out of code. Nothing
in this module should ever hold a real secret — defaults here are safe-only
for local development and are meant to be overridden in every other
environment (see architecture doc section 33-34, "Development Environments"
/ "Configuration").
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Strongly-typed application settings, validated once at startup."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- General ---------------------------------------------------------
    app_env: Literal["development", "testing", "staging", "production"] = "development"
    debug: bool = True
    app_name: str = "Phlio API"
    api_v1_prefix: str = "/api/v1"

    # --- Persistence -------------------------------------------------------
    # "memory": zero-setup, seeded in-process repositories (default; used in
    #           local dev and in the test suite).
    # "surreal": production-shaped repositories backed by SurrealDB.
    database_backend: Literal["memory", "surreal"] = "memory"

    surreal_url: str = "ws://localhost:8001/rpc"
    surreal_namespace: str = "phlio"
    surreal_database: str = "phlio"
    surreal_user: str = "root"
    surreal_password: str = "root"

    redis_url: str = "redis://127.0.0.1:6379/0"
    news_ingestion_enabled: bool = False
    redis_enabled: bool = False
    redis_namespace: str = "development"

    # Room file uploads stream here (see app/infrastructure/media_storage.py)
    # and are served back under /media by StaticFiles in main.py.
    media_root: str = "media"

    social_video_database: str = 'data/social_videos.sqlite3'
    messaging_database: str = 'data/messages.sqlite3'
    messaging_media_root: str = 'data/dm_files'
    calls_ice_servers: list[dict] = Field(
        default_factory=lambda: [{'urls': 'stun:stun.l.google.com:19302'}]
    )

    # --- Auth --------------------------------------------------------------
    jwt_secret: str = "dev-only-change-me-dev-only-change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 7

    # --- Phlio Agent ---------------------------------------------------------
    anthropic_api_key: str | None = None
    anthropic_model: str = "claude-sonnet-4-6"

    # --- Phlio Core engine (Rust) -------------------------------------------
    core_engine_binary_path: str = "../phlio_core/target/release/phlio-core"

    # --- Logging ---------------------------------------------------------------
    # "text": human-readable, single-line-per-record — best for a local
    #          terminal during development.
    # "json": one JSON object per line — best for a log aggregator
    #          (CloudWatch, Loki, Datadog...) in staging/production. See
    #          Phlio_Final_Product_Blueprint.md section 38, "Observability":
    #          "Use: structured logs; ... error tracking; ...".
    log_level: str = "INFO"
    log_format: Literal["text", "json"] = "text"

    # --- CORS ----------------------------------------------------------------
    cors_allow_origins: str = "http://localhost:3000"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allow_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache
def get_settings() -> Settings:
    """Returns a cached, process-wide Settings instance.

    Cached with `lru_cache` so environment parsing happens exactly once per
    process, and so FastAPI's dependency system can cheaply request it
    anywhere via `Depends(get_settings)`.
    """
    return Settings()
