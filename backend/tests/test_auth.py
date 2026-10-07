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
    login = await client.post("/api/v1/auth/login", json={"identifier": "arjun", "password": "password123"})
    refresh_token = login.json()["tokens"]["refresh_token"]

    response = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert response.status_code == 200
    assert "access_token" in response.json()


async def test_me_requires_authentication(client: AsyncClient) -> None:
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 401


async def test_account_details_private_and_phone_login(client: AsyncClient) -> None:
    payload = {
        "full_name": "Private User",
        "username": "privateuser",
        "email": "private@example.com",
        "password": "correct-horse-battery",
        "date_of_birth": "2000-02-29",
        "phone_number": "+91 (98765) 43210",
    }
    response = await client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 201, response.text
    user = response.json()["user"]
    assert user["date_of_birth"] == "2000-02-29"
    assert user["phone_number"] == "+919876543210"
    login = await client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "+91 98765-43210",
            "password": payload["password"],
        },
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": "Bearer " + login.json()["tokens"]["access_token"]}
    me = await client.get("/api/v1/auth/me", headers=headers)
    assert me.json()["date_of_birth"] == "2000-02-29"
    assert me.json()["phone_number"] == "+919876543210"
    public = await client.get("/api/v1/users/privateuser")
    assert public.status_code == 200
    assert "date_of_birth" not in public.json()
    assert "phone_number" not in public.json()
    payload.update(username="seconduser", email="second@example.com", phone_number="+919876543210")
    duplicate = await client.post("/api/v1/auth/register", json=payload)
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "phone_taken"


@pytest.mark.parametrize(
    "details",
    [
        {"date_of_birth": "2999-01-01"},
        {"date_of_birth": "2001-02-29"},
        {"date_of_birth": "1899-01-01"},
        {"phone_number": "9876543210"},
        {"phone_number": "+0123456789"},
        {"phone_number": "+1234567890123456"},
    ],
)
async def test_invalid_account_details(client: AsyncClient, details: dict) -> None:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Invalid User",
            "username": "invaliduser",
            "email": "invalid@example.com",
            "password": "correct-horse-battery",
            **details,
        },
    )
    assert response.status_code == 422
