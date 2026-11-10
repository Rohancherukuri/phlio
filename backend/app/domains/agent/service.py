"""
Agent domain service.

This is the layer that turns a raw user message into a stored, replayable
conversation. It deliberately does not know how planning works internally
(that's `planner.py`) or how tools reach other domains (`tools.py`) — its
only job is orchestration and persistence of the conversation.

Guardrail: nothing in this module, `planner.py`, or `tools.py` can create a
payment, booking, or any other state-mutating action. Every tool available
to the planner is read-only. This mirrors architecture doc section 16 (the
"Sensitive operations" flow) by construction — there is currently no
sensitive tool for the agent to misuse, rather than relying on it to
correctly ask for confirmation every time.
"""

from __future__ import annotations

import logging

from app.domains.agent.attachments import AgentAttachment, describe
from app.domains.agent.entities import AgentMessage, MessageRole
from app.domains.agent.planner import AgentPlanner
from app.domains.agent.repository import AgentRepository
from app.domains.agent.tools import AgentTools
from app.infrastructure.core_engine.client import CoreEngineClient

logger = logging.getLogger("phlio.agent")


class AgentService:
    def __init__(
        self,
        repository: AgentRepository,
        planner: AgentPlanner,
        core_engine: CoreEngineClient,
    ) -> None:
        self._repository = repository
        self._planner = planner
        self._core_engine = core_engine

    async def send_message(
        self,
        *,
        user_id: str,
        conversation_id: str,
        text: str,
        tools: AgentTools,
        attachments: list[AgentAttachment] | None = None,
    ) -> AgentMessage:
        attachments = attachments or []
        user_message = AgentMessage(
            id=await self._core_engine.generate_id("msg"),
            conversation_id=conversation_id,
            role=MessageRole.USER,
            text=text,
            attachments=attachments,
        )
        await self._repository.append_message(user_id, user_message)

        ack = describe(attachments, text)
        if text.strip():
            plan = await self._planner.create_plan(message=text, tools=tools)
            reply = f"{ack}\n\n{plan.summary}" if ack else plan.summary
        else:
            # Only files, no question yet: acknowledge and ask what to do.
            plan, reply = None, ack
        agent_message = AgentMessage(
            id=await self._core_engine.generate_id("msg"),
            conversation_id=conversation_id,
            role=MessageRole.AGENT,
            text=reply,
            plan=plan,
        )
        await self._repository.append_message(user_id, agent_message)
        # Every plan is logged with exactly what it contains — auditability
        # is the point (see the module docstring's guardrail): if a plan
        # ever looks wrong, this line is where to start.
        if plan is None:
            return agent_message
        logger.info(
            "agent.plan_created user_id=%s conversation_id=%s planner=%s items=%d "
            "estimated_total=%d-%d",
            user_id,
            conversation_id,
            type(self._planner).__name__,
            len(plan.items),
            plan.estimated_total_min_minor_units,
            plan.estimated_total_max_minor_units,
        )
        return agent_message

    async def get_conversation(self, *, user_id: str, conversation_id: str) -> list[AgentMessage]:
        return await self._repository.list_messages(user_id, conversation_id)
