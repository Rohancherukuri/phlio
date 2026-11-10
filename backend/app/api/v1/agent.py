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
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field, model_validator
from starlette.responses import FileResponse

from app.api.deps import get_agent_service, get_agent_tools, get_container, get_current_user
from app.core.container import Container
from app.domains.agent.attachments import AgentFileStore
from app.domains.agent.entities import AgentMessage, AgentPlan, MessageRole, PlanItem, PlanItemKind
from app.domains.agent.service import AgentService
from app.domains.agent.tools import AgentTools
from app.domains.identity.entities import User

router = APIRouter(prefix="/agent", tags=["agent"])


class SendMessageRequest(BaseModel):
    text: str = Field(default="", max_length=2000)
    conversation_id: str | None = Field(
        default=None, description="Omit to start a new conversation."
    )
    attachments: list[str] = Field(
        default_factory=list, max_length=10, description="Ids from POST /agent/files."
    )

    @model_validator(mode="after")
    def has_content(self):
        if not self.text.strip() and not self.attachments:
            raise ValueError("Write a message or attach a file.")
        return self


def _store(c: Container) -> AgentFileStore:
    return AgentFileStore(Path(c.settings.messaging_media_root).resolve())


def _files_prefix(c: Container) -> str:
    return f"{c.settings.api_v1_prefix}/agent/files"


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
    attachments: list[dict] = Field(default_factory=list)

    @classmethod
    def from_entity(cls, message: AgentMessage) -> AgentMessageResponse:
        return cls(
            id=message.id,
            conversation_id=message.conversation_id,
            role=message.role,
            text=message.text,
            plan=PlanResponse.from_entity(message.plan) if message.plan else None,
            created_at=message.created_at,
            attachments=[a.public() for a in message.attachments],
        )


@router.post("/files", status_code=status.HTTP_201_CREATED)
async def upload_files(
    files: list[UploadFile] = File(...),
    c: Container = Depends(get_container),
    current_user: User = Depends(get_current_user),
) -> list[dict]:
    """Photos, clips, audio and documents for Foxy (up to ten at once)."""
    if not 1 <= len(files) <= 10:
        raise HTTPException(422, "Attach up to ten files.")
    store = _store(c)
    saved = []
    for f in files:
        item = await run_in_threadpool(
            store.save, current_user.id, f.filename or "file", f.file, _files_prefix(c))
        saved.append(item.public())
    return saved


@router.get("/files/{file_id}")
async def get_file(
    file_id: str,
    c: Container = Depends(get_container),
    current_user: User = Depends(get_current_user),
):
    store = _store(c)
    item = store.get(current_user.id, file_id)
    if item is None:
        raise HTTPException(404, "File not found.")
    return FileResponse(store.path(file_id), media_type=item.mime, filename=item.name)


@router.post("/messages", response_model=AgentMessageResponse, status_code=status.HTTP_201_CREATED)
async def send_message(
    body: SendMessageRequest,
    agent_service: AgentService = Depends(get_agent_service),
    tools: AgentTools = Depends(get_agent_tools),
    c: Container = Depends(get_container),
    current_user: User = Depends(get_current_user),
) -> AgentMessageResponse:
    conversation_id = body.conversation_id or str(uuid.uuid4())
    store = _store(c)
    attachments = []
    for file_id in dict.fromkeys(body.attachments):
        item = store.get(current_user.id, file_id)
        if item is None:
            raise HTTPException(404, "One of the attachments is no longer available.")
        attachments.append(item)
    reply = await agent_service.send_message(
        user_id=current_user.id,
        conversation_id=conversation_id,
        text=body.text.strip(),
        tools=tools,
        attachments=attachments,
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
