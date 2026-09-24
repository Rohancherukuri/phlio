"""
Thin wrapper around the Anthropic SDK.

Isolated behind this module so `app/domains/agent` never imports the
`anthropic` package directly — the domain layer stays testable and free of
any particular vendor SDK (architecture doc section 15: "The AI service
should not directly bypass domain APIs to mutate sensitive state," and more
generally, infrastructure concerns stay out of the domain layer).

When `ANTHROPIC_API_KEY` is not configured, `is_available` is False and
`app/domains/agent/planner.py` uses the deterministic rule-based planner
instead — the agent endpoint always returns a useful response either way.
"""

from __future__ import annotations

import logging

from anthropic import AsyncAnthropic

from app.config import Settings

logger = logging.getLogger("phlio.ai")


class AgentLLMClient:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: AsyncAnthropic | None = (
            AsyncAnthropic(api_key=settings.anthropic_api_key)
            if settings.anthropic_api_key
            else None
        )

    @property
    def is_available(self) -> bool:
        return self._client is not None

    async def complete(self, *, system_prompt: str, user_message: str, max_tokens: int = 1024) -> str:
        """Returns Claude's plain-text reply to a single-turn prompt.

        Raises the underlying SDK exception on failure — callers (the agent
        planner) are responsible for catching it and falling back to the
        rule-based planner, so a transient AI-service outage never takes
        down the agent endpoint entirely.
        """
        if self._client is None:
            raise RuntimeError("AgentLLMClient used without an API key configured")

        response = await self._client.messages.create(
            model=self._settings.anthropic_model,
            max_tokens=max_tokens,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        text_blocks = [block.text for block in response.content if block.type == "text"]
        return "\n".join(text_blocks).strip()
