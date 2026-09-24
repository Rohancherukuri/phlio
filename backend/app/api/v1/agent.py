"""
Phlio Agent endpoints.

A single conversational surface: send a message, get back the agent's
reply (and, when relevant, a structured plan assembled from real Phlio
data — see `app/domains/agent/planner.py`). Conversation IDs are
client-generated UUIDs so a client can start a new thread without a round
trip, mirroring how the reference UI's Agent screen behaves.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.api.deps import get_agent_service, get_agent_tools, get_current_user
from app.domains.agent.entities import AgentMessage, AgentPlan, MessageRole, PlanItem, PlanItemKind
from app.domains.agent.service import AgentService
from app.domains.agent.tools import AgentTools
from app.domains.identity.entities import User

router = APIRouter(prefix="/agent", tags=["agent"])


class SendMessageRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    conversation_id: str | None = Field(
        default=None, description="Omit to start a new conversation."
    )


class PlanItemResponse(BaseModel):
    kind: PlanItemKind
    ref_id: str
    title: str
    subtitle: str
    image_url: str | None
    price_minor_units: int | None
    currency: str | None

    @classmethod
    def from_entity(cls, item: PlanItem) -> PlanItemResponse:
        return cls(
            kind=item.kind,
            ref_id=item.ref_id,
            title=item.title,
            subtitle=item.subtitle,
            image_url=item.image_url,
            price_minor_units=item.price_minor_units,
            currency=item.currency,
        )


class PlanResponse(BaseModel):
    id: str
    summary: str
    items: list[PlanItemResponse]
    estimated_total_min_minor_units: int
    estimated_total_max_minor_units: int
    currency: str

    @classmethod
    def from_entity(cls, plan: AgentPlan) -> PlanResponse:
        return cls(
            id=plan.id,
            summary=plan.summary,
            items=[PlanItemResponse.from_entity(i) for i in plan.items],
            estimated_total_min_minor_units=plan.estimated_total_min_minor_units,
            estimated_total_max_minor_units=plan.estimated_total_max_minor_units,
            currency=plan.currency,
        )


class AgentMessageResponse(BaseModel):
    id: str
    conversation_id: str
    role: MessageRole
    text: str
    plan: PlanResponse | None
    created_at: dt.datetime

    @classmethod
    def from_entity(cls, message: AgentMessage) -> AgentMessageResponse:
        return cls(
            id=message.id,
            conversation_id=message.conversation_id,
            role=message.role,
            text=message.text,
            plan=PlanResponse.from_entity(message.plan) if message.plan else None,
            created_at=message.created_at,
        )


@router.post("/messages", response_model=AgentMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    body: SendMessageRequest,
    agent_service: AgentService = Depends(get_agent_service),
    tools: AgentTools = Depends(get_agent_tools),
    current_user: User = Depends(get_current_user),
) -> AgentMessageResponse:
    conversation_id = body.conversation_id or str(uuid.uuid4())
    reply = await agent_service.send_message(
        user_id=current_user.id,
        conversation_id=conversation_id,
        text=body.text,
        tools=tools,
    )
    return AgentMessageResponse.from_entity(reply)


@router.get("/conversations/{conversation_id}/messages", response_model=list[AgentMessageResponse])
async def get_conversation(
    conversation_id: str,
    agent_service: AgentService = Depends(get_agent_service),
    current_user: User = Depends(get_current_user),
) -> list[AgentMessageResponse]:
    messages = await agent_service.get_conversation(
        user_id=current_user.id, conversation_id=conversation_id
    )
    return [AgentMessageResponse.from_entity(m) for m in messages]
