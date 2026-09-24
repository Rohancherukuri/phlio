"""
Agent planning.

Two planner implementations share one interface (`AgentPlanner`):

- `RuleBasedPlanner` — zero dependencies, always available. Extracts a
  budget, group size and day-of-week from the message with plain string
  parsing, then calls the deterministic tools in `tools.py` to assemble a
  plan. This is the default and the guaranteed fallback.
- `AnthropicPlanner` — when `ANTHROPIC_API_KEY` is configured, asks Claude
  to turn the same deterministic tool results into a warmer, more natural
  summary. Claude only ever rewrites the *narration*; it never chooses
  which rooms/products/posts end up in the plan and it never sees or
  produces anything resembling a payment action. This split is intentional
  — see `service.py` for why.

Both planners return the exact same `AgentPlan` shape, so the API layer and
the Flutter client never need to know or care which one produced it.
"""

from __future__ import annotations

import re
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Protocol

from app.domains.agent.entities import AgentPlan, PlanItem, PlanItemKind
from app.domains.agent.tools import AgentTools
from app.infrastructure.ai.anthropic_client import AgentLLMClient

IdFactory = Callable[[str], Awaitable[str]]

_BUDGET_PATTERN = re.compile(r"(?:₹|rs\.?|inr)\s?([\d,]+)", re.IGNORECASE)
_GROUP_PATTERN = re.compile(r"(\d+)\s*(?:friends|people|folks|guys)", re.IGNORECASE)
_WEEKDAYS = [
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
]

DEFAULT_BUDGET_MINOR_UNITS = 4_000_00  # ₹4,000 — matches the reference UI's example plan


@dataclass(slots=True, frozen=True)
class ParsedIntent:
    budget_minor_units: int
    group_size: int | None
    day: str | None


def parse_intent(message: str) -> ParsedIntent:
    """Very small, deterministic NLU pass — no ML involved.

    This intentionally does not try to be clever. Its job is only to
    extract the handful of structured facts the rule-based planner needs;
    anything it misses simply falls back to a sensible default rather than
    failing the request.
    """
    budget = DEFAULT_BUDGET_MINOR_UNITS
    if budget_match := _BUDGET_PATTERN.search(message):
        digits = budget_match.group(1).replace(",", "")
        if digits.isdigit():
            budget = int(digits) * 100  # message gives rupees, we store paise

    group_size = None
    if group_match := _GROUP_PATTERN.search(message):
        group_size = int(group_match.group(1))

    day = next((d for d in _WEEKDAYS if d in message.lower()), None)

    return ParsedIntent(budget_minor_units=budget, group_size=group_size, day=day)


class AgentPlanner(Protocol):
    async def create_plan(self, *, message: str, tools: AgentTools) -> AgentPlan: ...


class RuleBasedPlanner:
    """Deterministic planner: always available, no external dependencies."""

    def __init__(self, id_factory: IdFactory) -> None:
        self._id_factory = id_factory

    async def create_plan(self, *, message: str, tools: AgentTools) -> AgentPlan:
        intent = parse_intent(message)
        items: list[PlanItem] = []
        total_min = 0
        total_max = 0

        # 1. A community/room suggestion — always free to join.
        rooms = await tools.search_rooms(limit=1)
        if rooms:
            room = rooms[0]
            items.append(
                PlanItem(
                    kind=PlanItemKind.ROOM,
                    ref_id=room.id,
                    title=f"Join {room.name}",
                    subtitle=f"{room.member_count} members · {room.description[:60]}",
                )
            )

        # 2. A product within budget, leaving headroom for the other items.
        product_budget = max(int(intent.budget_minor_units * 0.6), 0)
        products = await tools.search_products(max_price_minor_units=product_budget, limit=1)
        if products:
            product = products[0]
            items.append(
                PlanItem(
                    kind=PlanItemKind.PRODUCT,
                    ref_id=product.id,
                    title=product.title,
                    subtitle=f"From Phlio Shop · {product.description[:60]}",
                    image_url=product.image_urls[0] if product.image_urls else None,
                    price_minor_units=product.price_minor_units,
                    currency=product.currency,
                )
            )
            total_min += product.price_minor_units
            total_max += product.price_minor_units

        # 3. A social post for inspiration / something to do together.
        posts = await tools.search_posts(limit=1)
        if posts:
            post = posts[0]
            items.append(
                PlanItem(
                    kind=PlanItemKind.POST,
                    ref_id=post.id,
                    title="See what's trending",
                    subtitle=post.text[:80],
                )
            )

        # Small buffer so the range feels like an estimate, not a quote.
        total_max = int(total_max * 1.15) if total_max else int(intent.budget_minor_units * 0.5)

        group_phrase = f" for {intent.group_size} friends" if intent.group_size else ""
        day_phrase = f" this {intent.day.capitalize()}" if intent.day else ""
        summary = (
            f"Here's a plan{day_phrase}{group_phrase}, aiming to stay within your budget."
            if items
            else "I couldn't find enough to build a full plan yet — try exploring Rooms or Shop first."
        )

        return AgentPlan(
            id=await self._id_factory("plan"),
            summary=summary,
            items=items,
            estimated_total_min_minor_units=total_min,
            estimated_total_max_minor_units=max(total_max, total_min),
        )


class AnthropicPlanner:
    """Wraps `RuleBasedPlanner`'s deterministic item selection with an
    LLM-written summary. Falls back to the rule-based summary on any error
    so an AI-service outage never breaks the agent endpoint."""

    def __init__(self, llm_client: AgentLLMClient, id_factory: IdFactory) -> None:
        self._llm_client = llm_client
        self._fallback = RuleBasedPlanner(id_factory)

    async def create_plan(self, *, message: str, tools: AgentTools) -> AgentPlan:
        plan = await self._fallback.create_plan(message=message, tools=tools)
        if not self._llm_client.is_available or not plan.items:
            return plan

        item_lines = "\n".join(f"- {item.title}: {item.subtitle}" for item in plan.items)
        prompt = (
            f'The user asked: "{message}"\n\n'
            f"Here is the plan already assembled from real Phlio data:\n{item_lines}\n\n"
            "Write a single warm, concise sentence (max 30 words) introducing this plan. "
            "Do not invent items, prices, or availability beyond what's listed."
        )
        try:
            summary = await self._llm_client.complete(
                system_prompt=(
                    "You are the Phlio Agent, a friendly planning assistant represented by a fox "
                    "character. You narrate plans; you never invent facts or authorize purchases."
                ),
                user_message=prompt,
                max_tokens=120,
            )
            if summary:
                plan.summary = summary
        except Exception:
            # Any SDK/network error: keep the deterministic summary. The
            # plan's *contents* were never at risk since they come from the
            # tool layer, not the LLM.
            pass
        return plan
