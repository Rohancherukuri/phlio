"""Phlio Fit: steps, water, food and goals (Phlio Agent explore tab).

    GET    /fitness/day?date=YYYY-MM-DD   one day: steps, water, meals, totals,
                                          calories burned (steps + Phlio Move),
                                          goals and progress
    GET    /fitness/history?days=7        per-day series for charts
    PUT    /fitness/goals                 steps, water, calories, active minutes,
                                          protein, weight / target weight
    POST   /fitness/water {ml, date?}     add (or, negative, remove) water
    POST   /fitness/steps                 {total} from the phone's step sensor
                                          (counts since boot), or {add} manual
    POST   /fitness/meals                 log food (name, kcal, macros, meal, servings)
    DELETE /fitness/meals/{id}?date=
    GET    /fitness/foods?q=              a small built-in food list to log fast

Steps from the sensor: the phone reports its running total since boot. The
first total seen on a day is that day's baseline, so steps = latest − base;
a reboot (the total going down) rebases without losing the day's steps.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key
from app.domains.graph.store import now

router = APIRouter(prefix="/fitness", tags=["fitness"])

DAY = "fitness_day"
GOAL = "fitness_goal"
MEALS = ("breakfast", "lunch", "dinner", "snack")
DEFAULT_GOALS = dict(steps=8000, water_ml=2500, calories=2000, active_min=30, protein_g=60,
                     weight_kg=None, target_kg=None)
KCAL_PER_STEP = 0.04  # ≈ 70 kg adult walking

# name, serving, kcal, protein g, carbs g, fat g
FOODS = [
    ("Idli (2)", "2 pieces", 116, 4, 24, 0.4), ("Masala dosa", "1 dosa", 387, 7, 52, 16),
    ("Plain dosa", "1 dosa", 168, 4, 29, 4), ("Sambar", "1 bowl", 130, 6, 18, 4),
    ("Upma", "1 bowl", 250, 6, 38, 8), ("Poha", "1 plate", 270, 5, 45, 8),
    ("Chapati", "1 roti", 104, 3, 18, 3), ("Paratha", "1 piece", 260, 5, 36, 10),
    ("Steamed rice", "1 cup", 205, 4, 45, 0.4), ("Dal tadka", "1 bowl", 198, 10, 26, 6),
    ("Rajma", "1 bowl", 240, 12, 34, 6), ("Chole", "1 bowl", 270, 11, 38, 9),
    ("Paneer butter masala", "1 bowl", 410, 15, 14, 33), ("Palak paneer", "1 bowl", 300, 14, 10, 22),
    ("Chicken biryani", "1 plate", 490, 24, 58, 17), ("Veg biryani", "1 plate", 400, 9, 62, 13),
    ("Butter chicken", "1 bowl", 440, 30, 12, 30), ("Egg (boiled)", "1 egg", 78, 6, 0.6, 5),
    ("Omelette", "2 eggs", 190, 13, 1, 15), ("Curd", "1 bowl", 98, 6, 7, 4),
    ("Banana", "1 medium", 105, 1.3, 27, 0.4), ("Apple", "1 medium", 95, 0.5, 25, 0.3),
    ("Mango", "1 cup", 99, 1.4, 25, 0.6), ("Almonds", "10 pieces", 70, 2.6, 2.4, 6),
    ("Oats with milk", "1 bowl", 290, 11, 46, 7), ("Peanut butter toast", "1 slice", 270, 10, 22, 16),
    ("Greek yogurt", "170 g", 100, 17, 6, 0.7), ("Protein shake", "1 scoop + water", 120, 24, 3, 1.5),
    ("Chicken breast (grilled)", "150 g", 248, 46, 0, 5.4), ("Salmon", "150 g", 312, 33, 0, 19),
    ("Salad bowl", "1 bowl", 150, 4, 14, 9), ("Pizza slice", "1 slice", 285, 12, 36, 10),
    ("Burger", "1 burger", 540, 25, 40, 30), ("French fries", "medium", 365, 4, 48, 17),
    ("Masala chai", "1 cup", 110, 3, 16, 4), ("Coffee with milk", "1 cup", 60, 3, 6, 3),
    ("Black coffee", "1 cup", 2, 0.3, 0, 0), ("Coca-Cola", "330 ml", 139, 0, 35, 0),
    ("Samosa", "1 piece", 262, 4, 24, 17), ("Vada pav", "1 piece", 290, 6, 40, 12),
    ("Gulab jamun", "2 pieces", 300, 4, 44, 12), ("Dark chocolate", "20 g", 110, 1.5, 9, 8),
]


class GoalsIn(BaseModel):
    steps: int | None = Field(default=None, ge=500, le=100_000)
    water_ml: int | None = Field(default=None, ge=250, le=10_000)
    calories: int | None = Field(default=None, ge=800, le=10_000)
    active_min: int | None = Field(default=None, ge=5, le=600)
    protein_g: int | None = Field(default=None, ge=10, le=500)
    weight_kg: float | None = Field(default=None, ge=20, le=400)
    target_kg: float | None = Field(default=None, ge=20, le=400)


class WaterIn(BaseModel):
    ml: int = Field(ge=-5000, le=5000)
    date: dt.date | None = None


class StepsIn(BaseModel):
    total: int | None = Field(default=None, ge=0, le=100_000_000)
    add: int | None = Field(default=None, ge=-100_000, le=100_000)
    date: dt.date | None = None


class MealIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    meal: str = "snack"
    kcal: float = Field(ge=0, le=10_000)
    protein_g: float = Field(default=0, ge=0, le=1000)
    carbs_g: float = Field(default=0, ge=0, le=2000)
    fat_g: float = Field(default=0, ge=0, le=1000)
    servings: float = Field(default=1, gt=0, le=50)
    serving: str = Field(default="", max_length=40)
    date: dt.date | None = None


def _today() -> dt.date:
    return dt.datetime.now().date()


async def _goals(c, uid: str) -> dict:
    row = await c.graph.store.get(key(GOAL, uid)) or {}
    return {k: row.get(k, v) for k, v in DEFAULT_GOALS.items()}


async def _day_row(c, uid: str, day: dt.date) -> dict:
    row = await c.graph.store.get(key(DAY, uid, day.isoformat()))
    return row or dict(user_id=uid, date=day.isoformat(), water_ml=0, steps=0, sensor_base=None,
                       sensor_last=None, meals=[])


async def _save(c, row: dict) -> dict:
    data = {k: v for k, v in row.items() if k != "id"}
    data["updated_at"] = now()
    return await c.graph.store.put(key(DAY, row["user_id"], row["date"]), data)


async def _move_day(c, uid: str, day: dt.date) -> dict:
    """Phlio Move activities that started on [day]."""
    rows = await c.graph.store.rows("phlio_activity", {"user_id": uid})
    out = dict(kcal=0, active_min=0, count=0)
    for r in rows:
        started = dt.datetime.fromisoformat(r["started_at"]).astimezone().date()
        if started == day:
            out["kcal"] += r.get("calories") or 0
            out["active_min"] += round((r.get("moving_s") or r.get("elapsed_s") or 0) / 60)
            out["count"] += 1
    return out


def _totals(meals: list[dict]) -> dict:
    t = dict(kcal=0.0, protein_g=0.0, carbs_g=0.0, fat_g=0.0)
    for m in meals:
        for k in t:
            t[k] += m.get(k, 0)
    return {k: round(v, 1) for k, v in t.items()}


async def _day_out(c, uid: str, day: dt.date, goals: dict | None = None) -> dict:
    goals = goals or await _goals(c, uid)
    row = await _day_row(c, uid, day)
    move = await _move_day(c, uid, day)
    eaten = _totals(row["meals"])
    steps = row.get("steps", 0)
    step_kcal = round(steps * KCAL_PER_STEP)
    # Walking minutes from steps (≈ 100 steps/min) plus recorded activities.
    active = round(steps / 100 * 0.4) + move["active_min"]
    burned = step_kcal + move["kcal"]

    def pct(v, g):
        return round(min(v / g, 9.99), 3) if g else 0

    return dict(
        date=day.isoformat(), steps=steps, water_ml=row.get("water_ml", 0), meals=row["meals"], eaten=eaten,
        burned_kcal=burned, active_min=active, move=move, net_kcal=round(eaten["kcal"] - burned),
        goals=goals,
        progress=dict(steps=pct(steps, goals["steps"]), water=pct(row.get("water_ml", 0), goals["water_ml"]),
                      calories=pct(eaten["kcal"], goals["calories"]), active=pct(active, goals["active_min"]),
                      protein=pct(eaten["protein_g"], goals["protein_g"])),
    )


@router.get("/day")
async def day(date: dt.date | None = None, user=Depends(get_current_user), c=Depends(get_container)):
    return await _day_out(c, user.id, date or _today())


@router.get("/history")
async def history(days: int = Query(7, ge=1, le=90), end: dt.date | None = None,
                  user=Depends(get_current_user), c=Depends(get_container)):
    return await history_for(c, user.id, days, end)


async def history_for(c, uid: str, days: int, end: dt.date | None = None) -> dict:
    """Per-day steps / water / food / burn for charts (also used by the
    profile dashboard's Foxy tab)."""
    last = end or _today()
    goals = await _goals(c, uid)
    out = []
    for i in range(days - 1, -1, -1):
        d = await _day_out(c, uid, last - dt.timedelta(days=i), goals)
        out.append(dict(date=d["date"], steps=d["steps"], water_ml=d["water_ml"], eaten_kcal=d["eaten"]["kcal"],
                        burned_kcal=d["burned_kcal"], active_min=d["active_min"], protein_g=d["eaten"]["protein_g"]))
    def avg(k):
        return round(sum(x[k] for x in out) / len(out)) if out else 0
    hits = sum(1 for x in out if x["steps"] >= goals["steps"])
    return dict(goals=goals, days=out, averages={k: avg(k) for k in ("steps", "water_ml", "eaten_kcal", "burned_kcal", "active_min")},
                step_goal_days=hits, best_steps=max((x["steps"] for x in out), default=0))


@router.put("/goals")
async def set_goals(body: GoalsIn, user=Depends(get_current_user), c=Depends(get_container)):
    goals = await _goals(c, user.id)
    goals.update({k: v for k, v in body.model_dump().items() if v is not None})
    await c.graph.store.put(key(GOAL, user.id), dict(goals, user_id=user.id, updated_at=now()))
    return goals


@router.post("/water")
async def water(body: WaterIn, user=Depends(get_current_user), c=Depends(get_container)):
    d = body.date or _today()
    row = await _day_row(c, user.id, d)
    row["water_ml"] = max(0, min(row.get("water_ml", 0) + body.ml, 20_000))
    await _save(c, row)
    return await _day_out(c, user.id, d)


@router.post("/steps")
async def steps(body: StepsIn, user=Depends(get_current_user), c=Depends(get_container)):
    if body.total is None and body.add is None:
        raise HTTPException(422, "Send the sensor total or steps to add.")
    d = body.date or _today()
    row = await _day_row(c, user.id, d)
    if body.total is not None:
        last = row.get("sensor_last")
        if row.get("sensor_base") is None or last is None:
            row["sensor_base"] = body.total
        elif body.total < last:
            # The phone restarted: keep today's steps, count on from the new total.
            row["sensor_base"] = body.total - (last - row["sensor_base"])
        row["sensor_last"] = body.total
        sensor_steps = max(0, body.total - row["sensor_base"])
        row["steps"] = max(row.get("steps", 0), sensor_steps + row.get("manual_steps", 0))
    if body.add is not None:
        row["manual_steps"] = max(0, row.get("manual_steps", 0) + body.add)
        row["steps"] = max(0, row.get("steps", 0) + body.add)
    await _save(c, row)
    return await _day_out(c, user.id, d)


@router.post("/meals", status_code=201)
async def add_meal(body: MealIn, user=Depends(get_current_user), c=Depends(get_container)):
    if body.meal not in MEALS:
        raise HTTPException(422, "Meal must be breakfast, lunch, dinner or snack.")
    d = body.date or _today()
    row = await _day_row(c, user.id, d)
    s = body.servings
    row["meals"].append(dict(id=uuid.uuid4().hex[:12], name=body.name.strip(), meal=body.meal, servings=s,
                             serving=body.serving, kcal=round(body.kcal * s, 1), protein_g=round(body.protein_g * s, 1),
                             carbs_g=round(body.carbs_g * s, 1), fat_g=round(body.fat_g * s, 1), at=now()))
    await _save(c, row)
    return await _day_out(c, user.id, d)


@router.delete("/meals/{meal_id}")
async def delete_meal(meal_id: str, date: dt.date | None = None, user=Depends(get_current_user), c=Depends(get_container)):
    d = date or _today()
    row = await _day_row(c, user.id, d)
    before = len(row["meals"])
    row["meals"] = [m for m in row["meals"] if m["id"] != meal_id]
    if len(row["meals"]) == before:
        raise HTTPException(404, "That food isn’t in this day’s log.")
    await _save(c, row)
    return await _day_out(c, user.id, d)


@router.get("/foods")
async def foods(q: str = Query("", max_length=60), user=Depends(get_current_user)):
    words = q.lower().split()
    items = [dict(name=n, serving=s, kcal=k, protein_g=p, carbs_g=cb, fat_g=f) for n, s, k, p, cb, f in FOODS
             if all(w in n.lower() for w in words)]
    return dict(items=items[:30])
