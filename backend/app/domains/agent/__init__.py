"""Phlio Agent domain — the intelligence layer.

Implements the "Understand -> Plan -> Recommend" slice of the agent
architecture in Phlio_Production_Architecture.md sections 15-18. The agent
orchestrates the domains already built in this stage (rooms, art, social)
through a small set of deterministic tools; it never mutates state or
authorizes a transaction on its own — see `service.py` for the specific
guardrail this implements.

Natural-language understanding is optional and pluggable
(`planner.AnthropicPlanner`): when `ANTHROPIC_API_KEY` is configured the
agent uses Claude to write a warmer summary of a plan; the plan's actual
contents always come from the deterministic tool layer, and the agent
works perfectly well with zero API keys via `planner.RuleBasedPlanner`.
"""
