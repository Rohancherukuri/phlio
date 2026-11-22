"""Durable Phlio Agent conversation history on SurrealDB, table ``agent_message``.

The Agent's short-term memory (and its plan cards) now survives restarts and
deploys like every other platform's data.
"""

from __future__ import annotations

from dataclasses import asdict

from app.domains.agent.attachments import AgentAttachment
from app.domains.agent.entities import AgentMessage, AgentPlan, MessageRole, PlanItem, PlanItemKind
from app.infrastructure.database.surreal.client import record
from app.infrastructure.database.surreal.pay_repo import _raw_id, _when


def _attachment(value):
    if isinstance(value, dict):
        try:
            return AgentAttachment(**value)
        except TypeError:
            return value
    return value


class SurrealAgentRepository:
    def __init__(self, db):
        self._db = db

    async def append_message(self, user_id: str, message: AgentMessage) -> AgentMessage:
        data = asdict(message)
        data.pop("id")
        data.update(user_id=user_id, role=str(message.role), created_at=message.created_at.isoformat(),
                    attachments=[asdict(a) if hasattr(a, "__dataclass_fields__") else a
                                 for a in message.attachments])
        if message.plan is not None:
            data["plan"]["items"] = [dict(i, kind=str(i["kind"])) for i in data["plan"]["items"]]
        await self._db.query("UPSERT $id CONTENT $data", {"id": record("agent_message:" + message.id), "data": data})
        return message

    async def list_messages(self, user_id: str, conversation_id: str) -> list[AgentMessage]:
        rows = await self._db.rows(
            "SELECT * FROM agent_message WHERE user_id = $u AND conversation_id = $c ORDER BY created_at ASC",
            {"u": user_id, "c": conversation_id})
        return self._messages(rows)

    async def list_user_messages(self, user_id: str, since: str | None = None) -> list[AgentMessage]:
        """Every message of every conversation (the dashboard's Agent tab)."""
        rows = await self._db.rows(
            "SELECT * FROM agent_message WHERE user_id = $u AND created_at >= $s ORDER BY created_at ASC",
            {"u": user_id, "s": since or ""})
        return self._messages(rows)

    def _messages(self, rows) -> list[AgentMessage]:
        out = []
        for r in rows:
            plan = r.get("plan")
            if isinstance(plan, dict):
                plan = AgentPlan(
                    id=plan["id"], summary=plan.get("summary", ""),
                    items=[PlanItem(**dict(i, kind=PlanItemKind(i["kind"]))) for i in plan.get("items") or []],
                    estimated_total_min_minor_units=int(plan.get("estimated_total_min_minor_units") or 0),
                    estimated_total_max_minor_units=int(plan.get("estimated_total_max_minor_units") or 0),
                    currency=plan.get("currency", "INR"))
            out.append(AgentMessage(id=_raw_id(r), conversation_id=r["conversation_id"], role=MessageRole(r["role"]),
                                    text=r.get("text", ""), plan=plan, created_at=_when(r["created_at"]),
                                    attachments=[_attachment(a) for a in r.get("attachments") or []]))
        return out
