"""Framework-agnostic domain entities for the Phlio Agent."""

from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field
from enum import StrEnum


class MessageRole(StrEnum):
    USER = "user"
    AGENT = "agent"


class PlanItemKind(StrEnum):
    ROOM = "room"
    PRODUCT = "product"
    POST = "post"


@dataclass(slots=True, frozen=True)
class PlanItem:
    kind: PlanItemKind
    ref_id: str
    title: str
    subtitle: str
    image_url: str | None = None
    price_minor_units: int | None = None
    currency: str | None = None


@dataclass(slots=True)
class AgentPlan:
    id: str
    summary: str
    items: list[PlanItem]
    estimated_total_min_minor_units: int
    estimated_total_max_minor_units: int
    currency: str = "INR"


@dataclass(slots=True)
class AgentMessage:
    id: str
    conversation_id: str
    role: MessageRole
    text: str
    plan: AgentPlan | None = None
    created_at: dt.datetime = field(default_factory=lambda: dt.datetime.now(dt.UTC))
