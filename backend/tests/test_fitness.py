"""Phlio Fit: water, steps from the phone's sensor, food log, goals,
history and the dashboard's Foxy tab."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.asyncio


async def test_fitness_day(client: AsyncClient, auth_headers: dict) -> None:
    api = "/api/v1/fitness"
    d = (await client.get(f"{api}/day", headers=auth_headers)).json()
    assert d["steps"] == 0 and d["goals"]["steps"] == 8000

    for ml in (250, 500, -100):
        d = (await client.post(f"{api}/water", headers=auth_headers, json={"ml": ml})).json()
    assert d["water_ml"] == 650

    # Sensor totals since boot: 10 000 is the baseline, then +1 200; a reboot
    # to 300 keeps the 1 200 and counts on.
    for total in (10_000, 11_200, 300, 800):
        d = (await client.post(f"{api}/steps", headers=auth_headers, json={"total": total})).json()
    assert d["steps"] == 1700
    d = (await client.post(f"{api}/steps", headers=auth_headers, json={"add": 300})).json()
    assert d["steps"] == 2000 and d["burned_kcal"] == 80

    foods = (await client.get(f"{api}/foods", headers=auth_headers, params={"q": "dosa"})).json()["items"]
    dosa = next(f for f in foods if f["name"] == "Masala dosa")
    r = await client.post(f"{api}/meals", headers=auth_headers, json=dict(dosa, meal="breakfast", servings=2))
    assert r.status_code == 201, r.text
    d = r.json()
    assert d["eaten"]["kcal"] == 774 and d["meals"][0]["servings"] == 2
    assert (await client.post(f"{api}/meals", headers=auth_headers, json=dict(dosa, meal="brunch"))).status_code == 422

    g = (await client.put(f"{api}/goals", headers=auth_headers, json={"steps": 10000, "water_ml": 3000})).json()
    assert g["steps"] == 10000 and g["calories"] == 2000
    d = (await client.get(f"{api}/day", headers=auth_headers)).json()
    assert d["progress"]["steps"] == 0.2

    d = (await client.delete(f"{api}/meals/{d['meals'][0]['id']}", headers=auth_headers)).json()
    assert d["eaten"]["kcal"] == 0

    h = (await client.get(f"{api}/history", headers=auth_headers, params={"days": 7})).json()
    assert len(h["days"]) == 7 and h["days"][-1]["steps"] == 2000 and h["best_steps"] == 2000

    dash = (await client.get("/api/v1/profile/dashboard", headers=auth_headers, params={"days": 7})).json()
    fit = {s["id"]: s for s in dash["sections"]}["agent"]["extra"]["fitness"]
    assert fit["tracked"] and fit["days"][-1]["water_ml"] == 650
