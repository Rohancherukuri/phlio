"""Tests for registration, login, refresh, and /auth/me."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_register_then_me(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Test User",
            "username": "testuser",
            "email": "testuser@example.com",
            "password": "correct-horse-battery",
            "interests": ["art", "tech"],
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["user"]["username"] == "testuser"
    access_token = body["tokens"]["access_token"]

    me = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {access_token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "testuser@example.com"


async def test_register_duplicate_username_is_rejected(client: AsyncClient) -> None:
    payload = {
        "full_name": "Dup User",
        "username": "arjun",  # already exists in seed data
        "email": "someone-else@example.com",
        "password": "correct-horse-battery",
    }
    response = await client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "username_taken"


async def test_login_with_wrong_password_is_unauthorized(client: AsyncClient) -> None:
    response = await client.post(
        "/api/v1/auth/login", json={"identifier": "arjun", "password": "wrong-password"}
    )
    assert response.status_code == 401


async def test_refresh_issues_new_access_token(client: AsyncClient, auth_headers: dict) -> None:
    login = await client.post(
        "/api/v1/auth/login", json={"identifier": "arjun", "password": "password123"}
    )
    refresh_token = login.json()["tokens"]["refresh_token"]

    response = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert response.status_code == 200
    assert "access_token" in response.json()


async def test_me_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 401
