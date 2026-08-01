from collections.abc import Mapping
from typing import Any

import pytest
from slack_copilot_mcp.config import CopilotConfig
from slack_copilot_mcp.service import CopilotError, SlackCopilotService
from slack_sdk.web.slack_response import SlackResponse


class FakeSlackApi:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []

    def _record(
        self,
        name: str,
        kwargs: dict[str, Any],
        response: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        self.calls.append((name, kwargs))
        return response

    def auth_test(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "auth_test",
            kwargs,
            {
                "ok": True,
                "team_id": "T012345678",
                "team": "Example",
                "user_id": "U012345678",
                "user": "seb",
            },
        )

    def conversations_list(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "conversations_list",
            kwargs,
            {
                "ok": True,
                "channels": [
                    {"id": "C012345678", "name": "allowed", "is_member": True},
                    {"id": "C987654321", "name": "blocked", "is_member": True},
                ],
            },
        )

    def conversations_history(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "conversations_history",
            kwargs,
            {
                "ok": True,
                "messages": [
                    {
                        "ts": "1750000000.000001",
                        "user": "U012345678",
                        "text": "Status update",
                    }
                ],
            },
        )

    def conversations_replies(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "conversations_replies",
            kwargs,
            {"ok": True, "messages": []},
        )

    def search_messages(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "search_messages",
            kwargs,
            {
                "ok": True,
                "messages": {
                    "matches": [
                        {
                            "channel": {"id": "C012345678", "name": "allowed"},
                            "ts": "1750000000.000001",
                            "username": "seb",
                            "text": "Allowed result",
                        },
                        {
                            "channel": {"id": "C987654321", "name": "blocked"},
                            "ts": "1750000001.000001",
                            "username": "seb",
                            "text": "Blocked result",
                        },
                    ]
                },
            },
        )

    def users_list(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "users_list",
            kwargs,
            {
                "ok": True,
                "members": [
                    {
                        "id": "U012345678",
                        "name": "seb",
                        "profile": {
                            "display_name": "Seb",
                            "real_name": "Seb Yan",
                            "email": "must-not-leak@example.com",
                        },
                    }
                ],
            },
        )

    def chat_postMessage(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "chat_postMessage",
            kwargs,
            {"ok": True, "ts": "1750000002.000001"},
        )

    def chat_getPermalink(self, **kwargs: Any) -> Mapping[str, Any]:
        return self._record(
            "chat_getPermalink",
            kwargs,
            {"ok": True, "permalink": "https://example.slack.com/archives/C/p1"},
        )


def _service(*, enable_write: bool = False) -> tuple[SlackCopilotService, FakeSlackApi]:
    config = CopilotConfig(
        user_token="xoxp-test",
        workspace_id="T012345678",
        allowed_channels=frozenset({"C012345678"}),
        enable_write=enable_write,
    )
    client = FakeSlackApi()
    return SlackCopilotService(config, client), client


def test_identity_checks_workspace() -> None:
    service, _ = _service()

    assert service.identity()["user"] == "seb"


def test_identity_accepts_real_slack_sdk_response_shape() -> None:
    service, client = _service()
    response = SlackResponse(
        client=client,
        http_verb="POST",
        api_url="https://slack.com/api/auth.test",
        req_args={},
        data={
            "ok": True,
            "team_id": "T012345678",
            "team": "Example",
            "user_id": "U012345678",
            "user": "seb",
        },
        headers={},
        status_code=200,
    )
    client.auth_test = lambda **_kwargs: response  # type: ignore[method-assign]

    assert service.identity()["workspace_id"] == "T012345678"


def test_read_channel_returns_normalized_messages() -> None:
    service, _ = _service()

    result = service.read_channel(channel_id="C012345678")

    assert result["messages"] == [
        {
            "ts": "1750000000.000001",
            "user": "U012345678",
            "text": "Status update",
        }
    ]


def test_channel_allowlist_filters_list_and_search() -> None:
    service, _ = _service()

    conversations = service.list_conversations()
    search = service.search_messages(query="status")

    assert [item["id"] for item in conversations["conversations"]] == ["C012345678"]
    assert [item["text"] for item in search["matches"]] == ["Allowed result"]


def test_list_users_omits_email_addresses() -> None:
    service, _ = _service()

    result = service.list_users()

    assert result["users"] == [
        {
            "id": "U012345678",
            "name": "seb",
            "display_name": "Seb",
            "real_name": "Seb Yan",
            "is_bot": False,
            "deleted": False,
        }
    ]


def test_post_reply_is_disabled_by_default() -> None:
    service, client = _service()

    with pytest.raises(CopilotError, match="disabled"):
        service.post_reply(
            channel_id="C012345678",
            thread_ts="1750000000.000001",
            text="Ship it",
        )

    assert not any(name == "chat_postMessage" for name, _ in client.calls)


def test_post_reply_targets_existing_thread_and_returns_permalink() -> None:
    service, client = _service(enable_write=True)

    result = service.post_reply(
        channel_id="C012345678",
        thread_ts="1750000000.000001",
        text="Ship it",
    )

    post = next(kwargs for name, kwargs in client.calls if name == "chat_postMessage")
    assert post == {
        "channel": "C012345678",
        "thread_ts": "1750000000.000001",
        "text": "Ship it",
        "unfurl_links": False,
        "unfurl_media": False,
    }
    assert result["permalink"] == "https://example.slack.com/archives/C/p1"
