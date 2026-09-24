"""Repository contract for agent conversation history (short-term memory).

Maps to the "Short-term" memory category in architecture doc section 17.
Episodic/semantic/preference memory are out of scope for this build stage.
"""

from __future__ import annotations

from typing import Protocol

from app.domains.agent.entities import AgentMessage


class AgentRepository(Protocol):
    async def append_message(self, user_id: str, message: AgentMessage) -> AgentMessage: ...

    async def list_messages(self, user_id: str, conversation_id: str) -> list[AgentMessage]: ...
