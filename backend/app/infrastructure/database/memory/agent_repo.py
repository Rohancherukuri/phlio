"""In-memory implementation of `AgentRepository` (short-term chat memory)."""

from __future__ import annotations

import asyncio
from collections import defaultdict

from app.domains.agent.entities import AgentMessage


class InMemoryAgentRepository:
    def __init__(self) -> None:
        # keyed by (user_id, conversation_id)
        self._messages: dict[tuple[str, str], list[AgentMessage]] = defaultdict(list)
        self._lock = asyncio.Lock()

    async def append_message(self, user_id: str, message: AgentMessage) -> AgentMessage:
        async with self._lock:
            self._messages[(user_id, message.conversation_id)].append(message)
            return message

    async def list_messages(self, user_id: str, conversation_id: str) -> list[AgentMessage]:
        return list(self._messages.get((user_id, conversation_id), []))

    async def list_user_messages(self, user_id: str, since: str | None = None) -> list[AgentMessage]:
        """Every message of every conversation (the dashboard's Agent tab)."""
        out = [m for (uid, _), msgs in self._messages.items() if uid == user_id for m in msgs
               if not since or m.created_at.isoformat() >= since]
        return sorted(out, key=lambda m: m.created_at)
