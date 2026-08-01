"""Slack event handling independent of the Bolt transport."""

from __future__ import annotations

import logging
from collections.abc import Mapping
from typing import Any, Protocol

from slack_agent_gateway.config import GatewayConfig
from slack_agent_gateway.context import build_prompt, strip_mentions
from slack_agent_gateway.runners import AgentRunner

logger = logging.getLogger(__name__)


class SlackClient(Protocol):
    def conversations_replies(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def chat_postMessage(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def reactions_add(self, **kwargs: Any) -> Mapping[str, Any]: ...


class GatewayService:
    def __init__(self, config: GatewayConfig, runner: AgentRunner) -> None:
        self.config = config
        self.runner = runner

    def handle(self, event: Mapping[str, Any], client: SlackClient) -> bool:
        user_id = str(event.get("user") or "")
        channel_id = str(event.get("channel") or "")
        timestamp = str(event.get("ts") or "")
        if not user_id or not channel_id or not timestamp:
            logger.warning("Ignoring malformed Slack event")
            return False
        if event.get("bot_id") or event.get("subtype"):
            return False
        if not self.config.permits(user_id=user_id, channel_id=channel_id):
            logger.warning(
                "Rejected Slack request from user=%s channel=%s", user_id, channel_id
            )
            return False

        request = strip_mentions(str(event.get("text") or ""))
        if not request:
            self._post(
                client,
                channel_id=channel_id,
                thread_ts=str(event.get("thread_ts") or timestamp),
                text="Please include a request after mentioning me.",
            )
            return True

        thread_ts = str(event.get("thread_ts") or timestamp)
        try:
            client.reactions_add(channel=channel_id, timestamp=timestamp, name="eyes")
        except Exception:
            logger.debug("Could not add acknowledgment reaction", exc_info=True)

        try:
            response = client.conversations_replies(
                channel=channel_id,
                ts=thread_ts,
                limit=self.config.max_context_messages,
                inclusive=True,
            )
            messages = response.get("messages", [])
            prompt = build_prompt(
                request=request,
                thread_messages=messages if isinstance(messages, list) else [],
                max_messages=self.config.max_context_messages,
                requester=user_id,
            )
            result = self.runner.run(prompt)
            text = result.text
        except Exception:
            logger.exception("Slack agent request failed")
            text = "The agent gateway failed while processing this request. Check the gateway logs."

        self._post(client, channel_id=channel_id, thread_ts=thread_ts, text=text)
        return True

    def _post(
        self,
        client: SlackClient,
        *,
        channel_id: str,
        thread_ts: str,
        text: str,
    ) -> None:
        chunks = _split_message(text, self.config.max_response_chars)
        for chunk in chunks:
            client.chat_postMessage(
                channel=channel_id,
                thread_ts=thread_ts,
                text=chunk,
                unfurl_links=False,
                unfurl_media=False,
            )


def _split_message(text: str, limit: int) -> list[str]:
    cleaned = text.strip() or "The agent returned an empty response."
    if len(cleaned) <= limit:
        return [cleaned]
    chunks: list[str] = []
    remaining = cleaned
    while remaining:
        if len(remaining) <= limit:
            chunks.append(remaining)
            break
        split_at = remaining.rfind("\n", 0, limit)
        if split_at < limit // 2:
            split_at = limit
        chunks.append(remaining[:split_at].rstrip())
        remaining = remaining[split_at:].lstrip()
    return chunks
