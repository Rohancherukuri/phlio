"""
Shared pytest fixtures.

Every test gets a brand-new `Container` (fresh in-memory repositories) so
tests never leak state into one another, without needing a real database —
this is exactly what the memory/surreal split in
`app/infrastructure/database` is for: tests exercise the same domain
services and API routes production does, just against the zero-setup
backend.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import Settings
from app.core.container import build_container
from app.core.seed import seed_memory_backend
from app.main import create_app


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        database_backend="memory",
        messaging_database=":memory:",
        social_video_database=":memory:",
        media_root=str(tmp_path / "media"),
        messaging_media_root=str(tmp_path / "dm_files"),
        jwt_secret="test-secret-at-least-32-bytes-long-for-hs256",
        debug=True,
    )


@pytest.fixture
async def client(settings: Settings):
    """An `httpx.AsyncClient` wired to a freshly-built app, seeded with the
    same demo data used in local development."""
    app = create_app(settings)
    container = await build_container(settings)
    await seed_memory_backend(container)
    app.state.container = container

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac


@pytest.fixture
async def auth_headers(client: AsyncClient) -> dict[str, str]:
    """Logs in as the seeded `arjun` user and returns ready-to-use auth headers."""
    response = await client.post(
        "/api/v1/auth/login", json={"identifier": "arjun", "password": "password123"}
    )
    assert response.status_code == 200, response.text
    access_token = response.json()["tokens"]["access_token"]
    return {"Authorization": f"Bearer {access_token}"}
