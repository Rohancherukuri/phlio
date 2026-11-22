"""Foxy Timeline: a visual day planner (timeline + calendar) that Foxy can
fill from your Phlio life — bookings, scheduled Spaces — or from a plain
sentence, and that you can then edit freely.

    GET    /timeline?start=YYYY-MM-DD&days=7   days with their tasks (repeats expanded)
    GET    /timeline/inbox                     tasks without a date
    POST   /timeline/tasks                     create
    PATCH  /timeline/tasks/{id}                edit
    DELETE /timeline/tasks/{id}
    POST   /timeline/tasks/{id}/toggle {date}  done / not done (per day for repeats)
    POST   /timeline/foxy {date, prompt?, sources[]}
                                               Foxy plans the day; returns the
                                               new tasks it added
"""

from __future__ import annotations

import datetime as dt
import re
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container, get_current_user

router = APIRouter(prefix="/timeline", tags=["timeline"])

TABLE = "timeline_task"
REPEATS = {"none", "daily", "weekdays", "weekly"}
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

# keyword → (icon, colour, default minutes)
KEYWORDS = [
    (("gym", "workout", "run", "yoga", "exercise", "walk"), "fitness", "#7BD88F", 60),
    (("study", "read", "learn", "homework", "class", "exam"), "book", "#72A7FF", 90),
    (("work", "meeting", "call", "email", "standup"), "work", "#8D78FF", 60),
    (("lunch", "dinner", "breakfast", "eat", "cook", "coffee"), "food", "#FFB58F", 45),
    (("movie", "watch", "series", "anime", "stream"), "movie", "#F5636B", 120),
    (("shop", "groceries", "buy"), "shop", "#F6B93B", 45),
    (("friends", "hangout", "party", "date"), "people", "#E795D7", 120),
    (("music", "practice", "guitar", "piano", "sing"), "music", "#68D7CD", 45),
    (("sleep", "nap", "rest", "relax", "chill"), "moon", "#A78BFA", 30),
    (("clean", "laundry", "chores"), "home", "#72A7FF", 45),
]


class SubtaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    done: bool = False


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    date: dt.date | None = None
    start: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    duration_min: int = Field(default=30, ge=0, le=24 * 60)
    icon: str = Field(default="spark", max_length=30)
    color: str = Field(default="#FFB58F", max_length=7)
    notes: str = Field(default="", max_length=2000)
    subtasks: list[SubtaskIn] = Field(default_factory=list, max_length=30)
    energy: int = Field(default=2, ge=1, le=5)
    repeat: str = "none"
    source: str = Field(default="manual", max_length=20)
    ref: str | None = Field(default=None, max_length=200)


class TaskPatch(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    date: dt.date | None = None
    clear_date: bool = False
    start: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    clear_start: bool = False
    duration_min: int | None = Field(default=None, ge=0, le=24 * 60)
    icon: str | None = Field(default=None, max_length=30)
    color: str | None = Field(default=None, max_length=7)
    notes: str | None = Field(default=None, max_length=2000)
    subtasks: list[SubtaskIn] | None = Field(default=None, max_length=30)
    energy: int | None = Field(default=None, ge=1, le=5)
    repeat: str | None = None


class ToggleIn(BaseModel):
    date: dt.date | None = None


class FoxyIn(BaseModel):
    date: dt.date
    prompt: str = Field(default="", max_length=500)
    sources: list[str] = Field(default_factory=lambda: ["book", "social", "routine"])


def _check(color: str | None, repeat: str | None) -> None:
    if color is not None and not HEX.match(color):
        raise HTTPException(422, "Colour must look like #FF8800.")
    if repeat is not None and repeat not in REPEATS:
        raise HTTPException(422, "Repeat must be none, daily, weekdays or weekly.")


def _mins(hhmm: str | None) -> int | None:
    if not hhmm:
        return None
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def _hhmm(total: int) -> str:
    total = max(0, min(total, 23 * 60 + 59))
    return f"{total // 60:02d}:{total % 60:02d}"


def _occurs(row: dict, day: dt.date) -> bool:
    if not row.get("date"):
        return False
    first = dt.date.fromisoformat(row["date"])
    if day < first:
        return False
    rep = row.get("repeat", "none")
    if rep == "none":
        return day == first
    if rep == "daily":
        return True
    if rep == "weekdays":
        return day.weekday() < 5
    return day.weekday() == first.weekday()


def _out(row: dict, day: dt.date | None = None) -> dict:
    done = row.get("done", False)
    if row.get("repeat", "none") != "none" and day is not None:
        done = day.isoformat() in row.get("done_dates", [])
    keys = ("title", "start", "duration_min", "icon", "color", "notes", "subtasks",
            "energy", "repeat", "source", "ref", "date")
    return dict({k: row.get(k) for k in keys}, id=row["id"].removeprefix(TABLE + ":"), done=done,
                occurrence=day.isoformat() if day else None)


async def _mine(c, user_id: str) -> list[dict]:
    return await c.graph.store.rows(TABLE, {"user_id": user_id})


async def _get(c, task_id: str, user_id: str) -> dict:
    row = await c.graph.store.get(f"{TABLE}:{task_id.removeprefix(TABLE + ':')}")
    if not row or row["user_id"] != user_id:
        raise HTTPException(404, "Task not found.")
    return row


def _sort(items: list[dict]) -> list[dict]:
    return sorted(items, key=lambda t: (_mins(t["start"]) if t["start"] else 10_000, t["title"]))


@router.get("")
async def timeline(start: dt.date | None = None, days: int = Query(7, ge=1, le=62),
                   user=Depends(get_current_user), c=Depends(get_container)):
    first = start or dt.date.today()
    rows = await _mine(c, user.id)
    out = []
    for i in range(days):
        day = first + dt.timedelta(days=i)
        tasks = _sort([_out(r, day) for r in rows if _occurs(r, day)])
        energy = sum(t["energy"] for t in tasks if not t["done"])
        out.append(dict(date=day.isoformat(), tasks=tasks, energy=energy,
                        dots=[t["color"] for t in tasks][:6]))
    return dict(start=first.isoformat(), days=out)


@router.get("/inbox")
async def inbox(user=Depends(get_current_user), c=Depends(get_container)):
    rows = [r for r in await _mine(c, user.id) if not r.get("date")]
    return dict(items=sorted((_out(r) for r in rows), key=lambda t: t["title"]))


async def _create(c, user_id: str, body: TaskIn) -> dict:
    _check(body.color, body.repeat)
    data = body.model_dump()
    data.update(user_id=user_id, date=body.date.isoformat() if body.date else None,
                subtasks=[s.model_dump() for s in body.subtasks], done=False, done_dates=[],
                created_at=dt.datetime.now(dt.UTC).isoformat())
    return await c.graph.store.put(f"{TABLE}:{uuid.uuid4().hex}", data)


@router.post("/tasks", status_code=201)
async def create(body: TaskIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _create(c, user.id, body)
    return _out(row, body.date)


@router.patch("/tasks/{task_id}")
async def edit(task_id: str, body: TaskPatch, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, task_id, user.id)
    _check(body.color, body.repeat)
    patch = body.model_dump(exclude_unset=True, exclude={"clear_date", "clear_start"})
    if "date" in patch and body.date is not None:
        patch["date"] = body.date.isoformat()
    if "subtasks" in patch and body.subtasks is not None:
        patch["subtasks"] = [s.model_dump() for s in body.subtasks]
    patch = {k: v for k, v in patch.items() if v is not None}
    row.update(patch)
    if body.clear_date:
        row["date"] = None
    if body.clear_start:
        row["start"] = None
    row = await c.graph.store.put(row["id"], {k: v for k, v in row.items() if k != "id"})
    return _out(row, dt.date.fromisoformat(row["date"]) if row.get("date") else None)


@router.delete("/tasks/{task_id}", status_code=204)
async def delete(task_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, task_id, user.id)
    await c.graph.store.delete(row["id"])


@router.post("/tasks/{task_id}/toggle")
async def toggle(task_id: str, body: ToggleIn, user=Depends(get_current_user), c=Depends(get_container)):
    row = await _get(c, task_id, user.id)
    day = body.date or (dt.date.fromisoformat(row["date"]) if row.get("date") else None)
    if row.get("repeat", "none") != "none" and day is not None:
        dates = set(row.get("done_dates", []))
        dates ^= {day.isoformat()}
        row["done_dates"] = sorted(dates)
    else:
        row["done"] = not row.get("done", False)
    row = await c.graph.store.put(row["id"], {k: v for k, v in row.items() if k != "id"})
    return _out(row, day)


# -- Foxy ---------------------------------------------------------------------

def _style(text: str) -> tuple[str, str, int]:
    low = text.lower()
    for words, icon, color, minutes in KEYWORDS:
        if any(re.search(rf"\b{w}", low) for w in words):
            return icon, color, minutes
    return "spark", "#FFB58F", 45


TIME = re.compile(r"\b(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", re.I)
DUR = re.compile(r"\b(?:for\s*)?(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minutes)\b", re.I)


def parse_prompt(prompt: str) -> list[dict]:
    """'gym at 7, study 2 hours and dinner with Neha at 8pm' → task drafts."""
    out = []
    for part in re.split(r",|;|\band then\b|\bthen\b|\band\b|\n", prompt):
        part = part.strip(" .")
        if not part:
            continue
        minutes = None
        if d := DUR.search(part):
            n = float(d.group(1))
            minutes = int(n * 60 if d.group(2).lower().startswith("h") else n)
            part_wo = part[: d.start()] + part[d.end():]
        else:
            part_wo = part
        start = None
        for t in TIME.finditer(part_wo):
            # Need 'at', a colon or am/pm so plain numbers ("2 friends") aren't times.
            if not (t.group(2) or t.group(3) or t.group(0).lower().startswith("at")):
                continue
            h, m = int(t.group(1)), int(t.group(2) or 0)
            ampm = (t.group(3) or "").lower()
            if ampm == "pm" and h < 12:
                h += 12
            elif ampm == "am" and h == 12:
                h = 0
            elif not ampm and 1 <= h <= 6:
                h += 12  # "at 5" means the evening
            if h < 24 and m < 60:
                start = h * 60 + m
                part_wo = part_wo[: t.start()] + part_wo[t.end():]
                break
        title = re.sub(r"\s+", " ", re.sub(r"\b(at|for|from)\s*$", "", part_wo.strip(" .-"))).strip()
        if not title:
            continue
        icon, color, default = _style(title)
        out.append(dict(title=title[:1].upper() + title[1:], start=start,
                        duration_min=minutes or default, icon=icon, color=color))
    return out


def _free_slot(busy: list[tuple[int, int]], length: int, after: int = 9 * 60, before: int = 22 * 60) -> int | None:
    cursor = after
    for s, e in sorted(busy):
        if s - cursor >= length:
            return cursor
        cursor = max(cursor, e + 15)
    return cursor if before - cursor >= length else None


@router.post("/foxy")
async def foxy_plan(body: FoxyIn, user=Depends(get_current_user), c=Depends(get_container)):
    day = body.date
    rows = await _mine(c, user.id)
    existing = [r for r in rows if _occurs(r, day)]
    busy = [(m, m + r.get("duration_min", 30)) for r in existing if (m := _mins(r.get("start"))) is not None]
    titles = {r["title"].lower() for r in existing}
    refs = {r.get("ref") for r in rows if r.get("ref")}
    drafts: list[dict] = []

    if "book" in body.sources:
        cursor = None
        while True:
            page, cursor = await c.book_service.my_bookings(user_id=user.id, cursor=cursor, limit=100)
            for b in page:
                if b.date == day and str(getattr(b.status, "value", b.status)) == "confirmed":
                    icon, color, _ = _style(b.title)
                    drafts.append(dict(title=b.title, start=b.time.strftime("%H:%M") if b.time else None,
                                       duration_min=90, icon=icon if icon != "spark" else "ticket",
                                       color="#E795D7", source="book", ref=f"book:{b.id}",
                                       notes=b.venue or ""))
            if not cursor:
                break

    if "social" in body.sources:
        for s in await c.graph.store.rows("scheduled_space", {"owner": user.id, "status": "scheduled"}):
            when = dt.datetime.fromisoformat(s["starts_at"])
            if when.date() == day:
                drafts.append(dict(title=f"Host Space: {s['title']}", start=when.strftime("%H:%M"),
                                   duration_min=60, icon="mic", color="#8D78FF", source="social",
                                   ref=s["id"]))

    for d in parse_prompt(body.prompt):
        drafts.append(dict(d, source="foxy"))

    if "routine" in body.sources:
        drafts.insert(0, dict(title="Rise and shine", start="08:00", duration_min=0, icon="sun",
                              color="#F6B93B", source="foxy"))
        drafts.append(dict(title="Wind down", start="22:30", duration_min=0, icon="moon",
                           color="#A78BFA", source="foxy"))

    added = []
    for d in drafts:
        if d["title"].lower() in titles or (d.get("ref") and d["ref"] in refs):
            continue
        start = d.get("start")
        start_m = _mins(start) if isinstance(start, str) else start
        length = d.get("duration_min", 30)
        if start_m is None:
            start_m = _free_slot(busy, max(length, 15))
        if start_m is not None:
            busy.append((start_m, start_m + length))
        task = TaskIn(title=d["title"][:120], date=day, start=_hhmm(start_m) if start_m is not None else None,
                      duration_min=length, icon=d.get("icon", "spark"), color=d.get("color", "#FFB58F"),
                      notes=d.get("notes", ""), source=d.get("source", "foxy"), ref=d.get("ref"),
                      energy=3 if length >= 90 else 2 if length >= 30 else 1)
        row = await _create(c, user.id, task)
        titles.add(d["title"].lower())
        added.append(_out(row, day))
    message = (f"I added {len(added)} thing{'s' if len(added) != 1 else ''} to your day."
               if added else "Your day already looks planned — nothing new to add.")
    return dict(added=_sort(added), message=message)
