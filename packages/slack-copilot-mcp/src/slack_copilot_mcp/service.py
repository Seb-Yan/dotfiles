"""Slack Web API operations with explicit access boundaries."""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any, Protocol

from slack_sdk.errors import SlackClientError

from slack_copilot_mcp.config import CopilotConfig


class CopilotError(RuntimeError):
    """A safe user-facing Slack copilot error."""


class SlackApi(Protocol):
    def auth_test(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def conversations_history(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def conversations_list(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def conversations_replies(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def chat_getPermalink(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def chat_postMessage(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def search_messages(self, **kwargs: Any) -> Mapping[str, Any]: ...

    def users_list(self, **kwargs: Any) -> Mapping[str, Any]: ...


_CHANNEL_ID = re.compile(r"^[CDG][A-Z0-9]{8,}$")
_TIMESTAMP = re.compile(r"^\d{10,}\.\d{6}$")
_CONVERSATION_TYPES = {
    "public_channel",
    "private_channel",
    "im",
    "mpim",
}


def _bounded(value: int, *, name: str, maximum: int) -> int:
    if value < 1 or value > maximum:
        raise CopilotError(f"{name} must be between 1 and {maximum}")
    return value


def _message(message: Mapping[str, Any]) -> dict[str, Any]:
    rendered: dict[str, Any] = {
        "ts": str(message.get("ts") or ""),
        "user": str(message.get("user") or message.get("bot_id") or ""),
        "text": str(message.get("text") or ""),
    }
    for key in ("thread_ts", "reply_count", "latest_reply", "subtype"):
        value = message.get(key)
        if value is not None:
            rendered[key] = value
    reactions = message.get("reactions")
    if isinstance(reactions, list):
        rendered["reactions"] = [
            {
                "name": str(item.get("name") or ""),
                "count": int(item.get("count") or 0),
            }
            for item in reactions
            if isinstance(item, Mapping)
        ]
    return rendered


def _channel(channel: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(channel.get("id") or ""),
        "name": str(channel.get("name") or channel.get("user") or ""),
        "is_private": bool(channel.get("is_private")),
        "is_im": bool(channel.get("is_im")),
        "is_mpim": bool(channel.get("is_mpim")),
        "is_member": bool(channel.get("is_member")),
        "is_archived": bool(channel.get("is_archived")),
        "topic": str((channel.get("topic") or {}).get("value") or ""),
        "purpose": str((channel.get("purpose") or {}).get("value") or ""),
    }


class SlackCopilotService:
    """Perform Slack calls while enforcing workspace and channel constraints."""

    def __init__(self, config: CopilotConfig, client: SlackApi):
        self.config = config
        self.client = client

    def identity(self) -> dict[str, Any]:
        response = self._call(self.client.auth_test)
        actual_workspace = str(response.get("team_id") or "")
        if actual_workspace != self.config.workspace_id:
            raise CopilotError(
                "Slack token workspace does not match SLACK_COPILOT_WORKSPACE_ID"
            )
        return {
            "workspace_id": actual_workspace,
            "workspace": str(response.get("team") or ""),
            "user_id": str(response.get("user_id") or ""),
            "user": str(response.get("user") or ""),
            "write_enabled": self.config.enable_write,
            "allowed_channels": len(self.config.allowed_channels),
        }

    def list_conversations(
        self,
        *,
        types: str = "public_channel,private_channel,im,mpim",
        limit: int = 100,
        cursor: str | None = None,
    ) -> dict[str, Any]:
        requested_types = [item.strip() for item in types.split(",") if item.strip()]
        invalid = sorted(set(requested_types) - _CONVERSATION_TYPES)
        if not requested_types or invalid:
            raise CopilotError(
                "types must contain public_channel, private_channel, im, or mpim"
            )
        limit = _bounded(limit, name="limit", maximum=200)
        kwargs: dict[str, Any] = {
            "types": ",".join(requested_types),
            "exclude_archived": True,
            "limit": limit,
        }
        if cursor:
            kwargs["cursor"] = cursor
        response = self._call(self.client.conversations_list, **kwargs)
        conversations = response.get("channels")
        if not isinstance(conversations, list):
            conversations = []
        visible = [
            _channel(item)
            for item in conversations
            if isinstance(item, Mapping)
            and self.config.permits_channel(str(item.get("id") or ""))
        ]
        return {
            "conversations": visible,
            "next_cursor": self._next_cursor(response),
        }

    def read_channel(
        self,
        *,
        channel_id: str,
        limit: int = 50,
        oldest: str | None = None,
        latest: str | None = None,
        cursor: str | None = None,
    ) -> dict[str, Any]:
        self._require_channel(channel_id)
        limit = _bounded(limit, name="limit", maximum=100)
        kwargs: dict[str, Any] = {"channel": channel_id, "limit": limit}
        if oldest:
            kwargs["oldest"] = self._timestamp(oldest, "oldest")
        if latest:
            kwargs["latest"] = self._timestamp(latest, "latest")
        if cursor:
            kwargs["cursor"] = cursor
        response = self._call(self.client.conversations_history, **kwargs)
        return {
            "channel_id": channel_id,
            "messages": self._messages(response),
            "has_more": bool(response.get("has_more")),
            "next_cursor": self._next_cursor(response),
        }

    def read_thread(
        self,
        *,
        channel_id: str,
        thread_ts: str,
        limit: int = 100,
        cursor: str | None = None,
    ) -> dict[str, Any]:
        self._require_channel(channel_id)
        limit = _bounded(limit, name="limit", maximum=100)
        kwargs: dict[str, Any] = {
            "channel": channel_id,
            "ts": self._timestamp(thread_ts, "thread_ts"),
            "limit": limit,
            "inclusive": True,
        }
        if cursor:
            kwargs["cursor"] = cursor
        response = self._call(self.client.conversations_replies, **kwargs)
        return {
            "channel_id": channel_id,
            "thread_ts": thread_ts,
            "messages": self._messages(response),
            "has_more": bool(response.get("has_more")),
            "next_cursor": self._next_cursor(response),
        }

    def search_messages(
        self,
        *,
        query: str,
        count: int = 20,
        page: int = 1,
    ) -> dict[str, Any]:
        query = query.strip()
        if not query:
            raise CopilotError("query must not be empty")
        count = _bounded(count, name="count", maximum=100)
        page = _bounded(page, name="page", maximum=100)
        response = self._call(
            self.client.search_messages,
            query=query,
            count=count,
            page=page,
            sort="timestamp",
            sort_dir="desc",
            highlight=False,
        )
        envelope = response.get("messages")
        matches = envelope.get("matches") if isinstance(envelope, Mapping) else []
        if not isinstance(matches, list):
            matches = []
        rendered = []
        for item in matches:
            if not isinstance(item, Mapping):
                continue
            raw_channel = item.get("channel")
            channel_id = (
                str(raw_channel.get("id") or "")
                if isinstance(raw_channel, Mapping)
                else str(raw_channel or "")
            )
            if not self.config.permits_channel(channel_id):
                continue
            rendered.append(
                {
                    "channel_id": channel_id,
                    "channel_name": (
                        str(raw_channel.get("name") or "")
                        if isinstance(raw_channel, Mapping)
                        else ""
                    ),
                    "ts": str(item.get("ts") or ""),
                    "user": str(item.get("user_id") or item.get("username") or ""),
                    "text": str(item.get("text") or ""),
                    "permalink": str(item.get("permalink") or ""),
                }
            )
        return {"query": query, "page": page, "matches": rendered}

    def list_users(
        self,
        *,
        limit: int = 200,
        cursor: str | None = None,
    ) -> dict[str, Any]:
        limit = _bounded(limit, name="limit", maximum=200)
        kwargs: dict[str, Any] = {"limit": limit}
        if cursor:
            kwargs["cursor"] = cursor
        response = self._call(self.client.users_list, **kwargs)
        members = response.get("members")
        if not isinstance(members, list):
            members = []
        users = []
        for member in members:
            if not isinstance(member, Mapping):
                continue
            profile = member.get("profile")
            if not isinstance(profile, Mapping):
                profile = {}
            users.append(
                {
                    "id": str(member.get("id") or ""),
                    "name": str(member.get("name") or ""),
                    "display_name": str(profile.get("display_name") or ""),
                    "real_name": str(profile.get("real_name") or ""),
                    "is_bot": bool(member.get("is_bot")),
                    "deleted": bool(member.get("deleted")),
                }
            )
        return {
            "users": users,
            "next_cursor": self._next_cursor(response),
        }

    def get_permalink(self, *, channel_id: str, message_ts: str) -> dict[str, str]:
        self._require_channel(channel_id)
        response = self._call(
            self.client.chat_getPermalink,
            channel=channel_id,
            message_ts=self._timestamp(message_ts, "message_ts"),
        )
        return {
            "channel_id": channel_id,
            "message_ts": message_ts,
            "permalink": str(response.get("permalink") or ""),
        }

    def post_reply(
        self,
        *,
        channel_id: str,
        thread_ts: str,
        text: str,
    ) -> dict[str, str]:
        self._require_channel(channel_id)
        if not self.config.enable_write:
            raise CopilotError(
                "Slack writes are disabled; set SLACK_COPILOT_ENABLE_WRITE=true"
            )
        cleaned = text.strip()
        if not cleaned:
            raise CopilotError("text must not be empty")
        if len(cleaned) > 40_000:
            raise CopilotError("text must not exceed 40000 characters")
        root_ts = self._timestamp(thread_ts, "thread_ts")
        response = self._call(
            self.client.chat_postMessage,
            channel=channel_id,
            thread_ts=root_ts,
            text=cleaned,
            unfurl_links=False,
            unfurl_media=False,
        )
        message_ts = str(response.get("ts") or "")
        permalink = self.get_permalink(
            channel_id=channel_id,
            message_ts=message_ts,
        )
        return {
            "channel_id": channel_id,
            "thread_ts": root_ts,
            "message_ts": message_ts,
            "permalink": permalink["permalink"],
        }

    def _require_channel(self, channel_id: str) -> None:
        if not _CHANNEL_ID.fullmatch(channel_id):
            raise CopilotError("channel_id is not a valid Slack conversation ID")
        if not self.config.permits_channel(channel_id):
            raise CopilotError("channel_id is not in SLACK_COPILOT_ALLOWED_CHANNELS")

    @staticmethod
    def _timestamp(value: str, name: str) -> str:
        if not _TIMESTAMP.fullmatch(value):
            raise CopilotError(f"{name} is not a valid Slack timestamp")
        return value

    @staticmethod
    def _messages(response: Mapping[str, Any]) -> list[dict[str, Any]]:
        messages = response.get("messages")
        if not isinstance(messages, list):
            return []
        return [_message(item) for item in messages if isinstance(item, Mapping)]

    @staticmethod
    def _next_cursor(response: Mapping[str, Any]) -> str:
        metadata = response.get("response_metadata")
        if not isinstance(metadata, Mapping):
            return ""
        return str(metadata.get("next_cursor") or "")

    @staticmethod
    def _call(method: Any, **kwargs: Any) -> Mapping[str, Any]:
        try:
            response = method(**kwargs)
        except SlackClientError as exc:
            error = getattr(getattr(exc, "response", None), "get", lambda _k: None)(
                "error"
            )
            detail = str(error or "transport_error")
            raise CopilotError(f"Slack API request failed: {detail}") from None
        response_data = getattr(response, "data", None)
        if isinstance(response_data, Mapping):
            response = response_data
        if not isinstance(response, Mapping):
            raise CopilotError("Slack API returned an invalid response")
        if response.get("ok") is False:
            raise CopilotError(
                f"Slack API request failed: {response.get('error') or 'unknown_error'}"
            )
        return response
