"""
Community fact checks ("Readers added context"), like X's Community Notes,
for Phlio Social (posts, videos, clips), Rooms and News.

Anyone can propose a note on a piece of content: a classification, an
explanation and 1–5 credible https sources. Other people rate it Helpful,
Somewhat helpful or Not helpful. A note is only *shown* under the content
when it is found helpful by people who usually disagree with each other —
the "bridging" rule — not merely by a majority.

How bridging is scored (the open Community Notes model, small scale):

    rating(u, n) ≈ μ + i_u + i_n + f_u · f_n

fitted by regularised gradient descent over every rating. ``f_u`` places a
rater on the axis along which raters tend to disagree, ``f_n`` places the
note on it, and ``i_n`` (the note intercept) is the helpfulness that is
left once that disagreement is explained away. A note becomes **helpful**
when ``i_n >= HELPFUL_INTERCEPT`` (0.35) with at least ``MIN_RATINGS`` ratings *and* helpful
ratings from raters on both sides of the axis; **not helpful** when
``i_n <= -0.05 - 0.8·|f_n|``. Anything else **needs more ratings**.
Scores are recomputed after every rating (fine for tens of thousands of
ratings; move to a periodic job beyond that).

Graph tables: ``fact_note`` (one per note), ``fact_rating`` (one per
rater per note).
"""

from __future__ import annotations

import datetime as dt
import math
import random
import re
import uuid
from typing import Literal
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator

from app.api.deps import get_container, get_current_user
from app.domains.graph.service import key

router = APIRouter(prefix="/fact-checks", tags=["fact-checks"])

TARGET = r"^(social|rooms|news)/[A-Za-z0-9_:\-.]{1,120}$"
MIN_RATINGS = 5
# Community Notes uses 0.40 on millions of ratings; with a fixed 0.5 baseline
# and a small community 0.35 separates bridging notes from one-sided ones.
HELPFUL_INTERCEPT = 0.35
VALUES = {"helpful": 1.0, "somewhat": 0.5, "not_helpful": 0.0}
Classification = Literal["misleading", "missing_context", "satire", "outdated", "accurate"]


def _now() -> str:
    return dt.datetime.now(dt.UTC).isoformat()


class NoteIn(BaseModel):
    target: str = Field(pattern=TARGET)
    classification: Classification
    text: str = Field(min_length=20, max_length=500)
    sources: list[str] = Field(min_length=1, max_length=5)

    @field_validator("sources")
    @classmethod
    def _https(cls, sources):
        clean = []
        for s in sources:
            s = s.strip()
            u = urlparse(s)
            if u.scheme != "https" or not u.netloc or len(s) > 500 or " " in s:
                raise ValueError("Sources must be full https links.")
            clean.append(s)
        return list(dict.fromkeys(clean))

    @field_validator("text")
    @classmethod
    def _text(cls, value):
        value = " ".join(value.split())
        if len(value) < 20:
            raise ValueError("Explain the context in at least 20 characters.")
        return value


class RatingIn(BaseModel):
    rating: Literal["helpful", "somewhat", "not_helpful"]
    # Optional reason tags, like Community Notes asks for.
    reasons: list[Literal["clear", "good_sources", "addresses_claim", "neutral", "incorrect",
                          "biased", "sources_missing", "opinion", "off_topic"]] = Field(default_factory=list, max_length=5)


class BatchIn(BaseModel):
    targets: list[str] = Field(max_length=60)


# ----------------------------------------------------------------- scoring

def score(ratings: list[tuple[str, str, float]], epochs: int = 300, seed: int = 7):
    """Matrix-factorisation scores: ({note: (intercept, factor)}, {rater: factor})."""
    if not ratings:
        return {}, {}
    rng = random.Random(seed)
    users = {u for u, _, _ in ratings}
    notes = {n for _, n, _ in ratings}
    # A fixed neutral baseline (not the global mean): with a small community
    # most ratings are "helpful", and a learned mean would swallow the
    # helpfulness of genuinely good notes.
    mu = 0.5
    iu = {u: 0.0 for u in users}
    inn = {n: 0.0 for n in notes}
    fu = {u: rng.uniform(-0.1, 0.1) for u in sorted(users)}
    fn = {n: rng.uniform(-0.1, 0.1) for n in sorted(notes)}
    lam_i, lam_f, lr = 0.15, 0.03, 0.05
    order = list(ratings)
    for _ in range(epochs):
        rng.shuffle(order)
        for u, n, r in order:
            err = r - (mu + iu[u] + inn[n] + fu[u] * fn[n])
            iu[u] += lr * (err - lam_i * iu[u])
            inn[n] += lr * (err - lam_i * inn[n])
            fu_u = fu[u]
            fu[u] += lr * (err * fn[n] - lam_f * fu[u])
            fn[n] += lr * (err * fu_u - lam_f * fn[n])
    # Factor sign is arbitrary; fix it so results are stable between runs.
    if sum(fu.values()) < 0:
        fu = {u: -v for u, v in fu.items()}
        fn = {n: -v for n, v in fn.items()}
    return {n: (inn[n], fn[n]) for n in notes}, fu


def status_for(note_id: str, ratings: list[tuple[str, str, float]], notes_scores, rater_factors) -> dict:
    mine = [(u, r) for u, n, r in ratings if n == note_id]
    intercept, factor = notes_scores.get(note_id, (0.0, 0.0))
    helpful_sides = {math.copysign(1, rater_factors.get(u, 0.0) or 1e-9) for u, r in mine if r >= 0.75}
    if len(mine) >= MIN_RATINGS and intercept >= HELPFUL_INTERCEPT and len(helpful_sides) == 2:
        status = "helpful"
    elif len(mine) >= MIN_RATINGS and intercept <= -0.05 - 0.8 * abs(factor):
        status = "not_helpful"
    else:
        status = "needs_more_ratings"
    return dict(status=status, intercept=round(intercept, 3), factor=round(factor, 3), rating_count=len(mine))


async def rescore(c) -> None:
    rows = await c.graph.store.rows("fact_rating")
    ratings = [(r["rater"], r["note_id"], VALUES[r["rating"]]) for r in rows if r.get("rating") in VALUES]
    notes_scores, rater_factors = score(ratings)
    for note in await c.graph.store.rows("fact_note"):
        result = status_for(note["note_id"], ratings, notes_scores, rater_factors)
        if any(note.get(k) != v for k, v in result.items()):
            await c.graph.store.put(key("fact_note", note["note_id"]), {**_clean(note), **result, "scored_at": _now()})


# ----------------------------------------------------------------- helpers

def _clean(row: dict) -> dict:
    return {k: v for k, v in row.items() if k != "id"}


async def _present(c, note: dict, viewer: str, ratings: dict[str, dict] | None = None) -> dict:
    mine = (ratings or {}).get(note["note_id"])
    if mine is None:
        r = await c.graph.store.get(key("fact_rating", note["note_id"], viewer))
        mine = r or {}
    return dict(
        id=note["note_id"], target=note["target"], classification=note["classification"],
        text=note["text"], sources=[dict(url=s, host=urlparse(s).netloc.removeprefix("www.")) for s in note["sources"]],
        status=note.get("status", "needs_more_ratings"), rating_count=note.get("rating_count", 0),
        created_at=note["created_at"], mine=note["author"] == viewer, my_rating=mine.get("rating"),
    )


async def _notes_for(c, target: str) -> list[dict]:
    return await c.graph.store.rows("fact_note", {"target": target})


async def _summary(c, target: str, viewer: str) -> dict:
    notes = await _notes_for(c, target)
    shown = sorted([n for n in notes if n.get("status") == "helpful"], key=lambda n: -n.get("intercept", 0))
    proposed = [n for n in notes if n.get("status", "needs_more_ratings") == "needs_more_ratings"]
    return dict(
        target=target,
        shown=[await _present(c, n, viewer) for n in shown[:1]],
        proposed=[await _present(c, n, viewer) for n in sorted(proposed, key=lambda n: n["created_at"], reverse=True)],
        not_helpful_count=sum(1 for n in notes if n.get("status") == "not_helpful"),
    )


# ----------------------------------------------------------------- routes

@router.get("")
async def for_target(target: str, user=Depends(get_current_user), c=Depends(get_container)):
    if not re.match(TARGET, target):
        raise HTTPException(422, "Unknown content.")
    return await _summary(c, target, user.id)


@router.post("/batch")
async def batch(body: BatchIn, user=Depends(get_current_user), c=Depends(get_container)):
    """Shown notes and proposed-note counts for many items (feeds)."""
    out = {}
    targets = [t for t in dict.fromkeys(body.targets) if re.match(TARGET, t)]
    wanted = set(targets)
    by_target: dict[str, list[dict]] = {}
    for note in await c.graph.store.rows("fact_note"):
        if note["target"] in wanted:
            by_target.setdefault(note["target"], []).append(note)
    for t in targets:
        notes = by_target.get(t, [])
        shown = sorted([n for n in notes if n.get("status") == "helpful"], key=lambda n: -n.get("intercept", 0))
        out[t] = dict(
            shown=[await _present(c, n, user.id) for n in shown[:1]],
            proposed_count=sum(1 for n in notes if n.get("status", "needs_more_ratings") == "needs_more_ratings"),
        )
    return out


@router.post("", status_code=201)
async def propose(body: NoteIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, "fact-note", 10)
    existing = await _notes_for(c, body.target)
    if any(n["author"] == user.id for n in existing):
        raise HTTPException(409, "You've already added a note here. Delete it to write a new one.")
    note_id = uuid.uuid4().hex[:20]
    note = dict(note_id=note_id, target=body.target, author=user.id, classification=body.classification,
                text=body.text, sources=body.sources, created_at=_now(), status="needs_more_ratings",
                rating_count=0, intercept=0.0, factor=0.0)
    await c.graph.store.put(key("fact_note", note_id), note)
    return await _present(c, note, user.id)


async def _note(c, note_id: str) -> dict:
    if not re.match(r"^[a-f0-9]{20}$", note_id):
        raise HTTPException(404, "Note not found.")
    note = await c.graph.store.get(key("fact_note", note_id))
    if not note:
        raise HTTPException(404, "Note not found.")
    return note


@router.put("/{note_id}/rating")
async def rate(note_id: str, body: RatingIn, user=Depends(get_current_user), c=Depends(get_container)):
    note = await _note(c, note_id)
    if note["author"] == user.id:
        raise HTTPException(403, "You can't rate your own note.")
    await c.cache.rate_limit(user.id, "fact-rating", 60)
    await c.graph.store.put(key("fact_rating", note_id, user.id), dict(
        note_id=note_id, rater=user.id, rating=body.rating, reasons=body.reasons, created_at=_now()))
    await rescore(c)
    return await _present(c, await _note(c, note_id), user.id)


@router.delete("/{note_id}/rating", status_code=204)
async def unrate(note_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await _note(c, note_id)
    if await c.graph.store.get(key("fact_rating", note_id, user.id)):
        await c.graph.store.delete(key("fact_rating", note_id, user.id))
        await rescore(c)


@router.delete("/{note_id}", status_code=204)
async def delete(note_id: str, user=Depends(get_current_user), c=Depends(get_container)):
    note = await _note(c, note_id)
    if note["author"] != user.id:
        raise HTTPException(403, "Only the author can delete this note.")
    for r in await c.graph.store.rows("fact_rating", {"note_id": note_id}):
        await c.graph.store.delete(key("fact_rating", note_id, r["rater"]))
    await c.graph.store.delete(key("fact_note", note_id))
    await rescore(c)


@router.get("/queue")
async def queue(user=Depends(get_current_user), c=Depends(get_container)):
    """Proposed notes you can help rate (not yours, not rated yet)."""
    rated = {r["note_id"] for r in await c.graph.store.rows("fact_rating", {"rater": user.id})}
    notes = [n for n in await c.graph.store.rows("fact_note")
             if n.get("status", "needs_more_ratings") == "needs_more_ratings"
             and n["author"] != user.id and n["note_id"] not in rated]
    notes.sort(key=lambda n: n["created_at"], reverse=True)
    return {"items": [await _present(c, n, user.id) for n in notes[:30]]}
