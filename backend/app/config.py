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

from pydantic import AliasChoices, Field, model_validator
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
    razorpay_key_id: str = Field(default='', repr=False)
    razorpay_key_secret: str = Field(default='', repr=False)
    pay_gateway_database: str = 'data/pay_gateway.sqlite3'
    giphy_api_key: str = Field(default="", repr=False)
    # Spotify OAuth configuration. Keep credentials out of Settings repr/logs.
    # A client ID alone does not enable account linking or music playback.
    spotify_client_id: str = Field(default="", repr=False)
    music_database: str = 'data/music.sqlite3'
    spotify_callback_url: str = Field(
        default="",
        validation_alias=AliasChoices("SPOTIFY_CALLBACK_URL", "SPOTIFY_REDIRECT_URI"),
    )

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

    # --- Object storage (optional; Cloudflare R2 or any S3-compatible bucket) ---
    # Set these on disk-less hosts (Render free): SQLite databases and DM
    # files are restored from / backed up to the bucket, new uploads are
    # pushed to it, and /media files that aren't on disk redirect to
    # media_public_url (the bucket's public URL, e.g. https://pub-….r2.dev).
    # See app/infrastructure/media_sync.py.
    object_store_endpoint: str = ""  # R2: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
    object_store_bucket: str = ""
    object_store_access_key: str = Field(default="", repr=False)
    object_store_secret_key: str = Field(default="", repr=False)
    object_store_region: str = "auto"
    # A second, PRIVATE bucket for state (SQLite databases with DMs and
    # payments, DM attachments, snap photos). The media bucket is public
    # (MEDIA_PUBLIC_URL), and a public r2.dev bucket serves every object in it,
    # so state must not live there. Same endpoint and keys as the media bucket.
    object_store_state_bucket: str = ""
    media_public_url: str = ""
    state_sync_interval: float = 60  # seconds between backups to the bucket
    # Free hosting sleeps after 15 idle minutes; see app/infrastructure/keep_awake.py.
    keep_awake: bool = False
    keep_awake_url: str = ""  # default: RENDER_EXTERNAL_URL (set by Render)
    keep_awake_interval: float = 600

    social_video_database: str = 'data/social_videos.sqlite3'
    messaging_database: str = 'data/messages.sqlite3'
    livekit_url: str = ''
    livekit_api_url: str = ''
    livekit_api_key: str = ''
    livekit_api_secret: str = ''
    messaging_media_root: str = 'data/dm_files'
    calls_ice_servers: list[dict] = Field(
        default_factory=lambda: [{'urls': 'stun:stun.l.google.com:19302'}]
    )

    # --- Auth --------------------------------------------------------------
    jwt_secret: str = "dev-only-change-me-dev-only-change-me"
    # Sign in with Google / Apple: the OAuth client ids whose ID tokens we
    # accept (comma separated). Google: the web client id the app passes as
    # serverClientId (plus the iOS client id). Apple: the app's bundle id
    # (iOS) and the Services ID (Android / web).
    google_client_ids: str = ""
    apple_client_ids: str = ""
    # Also accepted (merged into the lists above), so the ids can be set
    # under the same names the app uses.
    google_server_client_id: str = ""
    google_ios_client_id: str = ""
    apple_ios_bundle_id: str = ""
    apple_service_id: str = ""
    # Android package, for the Sign in with Apple web-flow callback redirect.
    android_package_name: str = "com.example.phlio"
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

    # --- Hardening (see app/middleware/security.py) ---------------------------
    # JSON/form bodies above this are rejected with 413 (uploads are exempt).
    max_json_body_bytes: int = 4 * 1024 * 1024
    # Swagger UI / ReDoc / openapi.json. Unset = on everywhere except
    # production; set API_DOCS_ENABLED=true to expose them in production.
    api_docs_enabled: bool | None = None

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allow_origins.split(",") if origin.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def docs_enabled(self) -> bool:
        return self.api_docs_enabled if self.api_docs_enabled is not None else not self.is_production

    @model_validator(mode="after")
    def _refuse_insecure_production(self) -> "Settings":
        """Fail fast instead of serving production with a guessable JWT key.

        Anyone who knows the signing secret can mint access tokens for any
        account, so the development default (which is public in this repo)
        or a short secret must never reach production. Render's blueprint
        generates a random JWT_SECRET, so deployments there pass this check.
        """
        if self.is_production:
            if self.jwt_secret == "dev-only-change-me-dev-only-change-me" or len(self.jwt_secret) < 32:
                raise ValueError(
                    "JWT_SECRET must be set to a random value of at least 32 characters in "
                    "production (e.g. `python -c \"import secrets; print(secrets.token_urlsafe(48))\"`)."
                )
            if self.debug:
                # DEBUG would expose stack traces; production always runs without it.
                object.__setattr__(self, "debug", False)
        return self


@lru_cache
def get_settings() -> Settings:
    """Returns a cached, process-wide Settings instance.

    Cached with `lru_cache` so environment parsing happens exactly once per
    process, and so FastAPI's dependency system can cheaply request it
    anywhere via `Depends(get_settings)`.
    """
    return Settings()
