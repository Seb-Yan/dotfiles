"""Slack gateway for invoking local coding agents."""

from slack_agent_gateway.config import GatewayConfig
from slack_agent_gateway.runners import AgentResult, build_runner

__all__ = ["AgentResult", "GatewayConfig", "build_runner"]
