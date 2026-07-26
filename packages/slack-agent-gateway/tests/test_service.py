from pathlib import Path
from typing import Any

from slack_agent_gateway.config import GatewayConfig
from slack_agent_gateway.runners import AgentResult
from slack_agent_gateway.service import GatewayService, _split_message


class FakeRunner:
    def __init__(self, text: str = "done") -> None:
        self.text = text
        self.prompts: list[str] = []

    def run(self, prompt: str) -> AgentResult:
        self.prompts.append(prompt)
        return AgentResult(text=self.text, provider="codex", succeeded=True)


class FakeSlackClient:
    def __init__(self) -> None:
        self.posts: list[dict[str, Any]] = []
        self.reactions: list[dict[str, Any]] = []

    def conversations_replies(self, **kwargs: Any) -> dict[str, Any]:
        return {"messages": [{"user": "U1", "text": "<@BOT> run tests"}]}

    def chat_postMessage(self, **kwargs: Any) -> dict[str, Any]:
        self.posts.append(kwargs)
        return {"ok": True}

    def reactions_add(self, **kwargs: Any) -> dict[str, Any]:
        self.reactions.append(kwargs)
        return {"ok": True}


def config(tmp_path: Path) -> GatewayConfig:
    return GatewayConfig.from_env(
        {
            "SLACK_BOT_TOKEN": "xoxb-test",
            "SLACK_APP_TOKEN": "xapp-test",
            "SLACK_AGENT_ALLOWED_USERS": "U1",
            "SLACK_AGENT_WORKSPACE": str(tmp_path),
        }
    )


def test_authorized_event_runs_agent_and_replies_in_thread(tmp_path: Path) -> None:
    runner = FakeRunner()
    client = FakeSlackClient()
    service = GatewayService(config(tmp_path), runner)

    handled = service.handle(
        {"user": "U1", "channel": "C1", "ts": "100.1", "text": "<@BOT> run tests"},
        client,
    )

    assert handled
    assert len(runner.prompts) == 1
    assert "run tests" in runner.prompts[0]
    assert client.posts[0]["thread_ts"] == "100.1"
    assert client.posts[0]["text"] == "done"
    assert client.reactions[0]["name"] == "eyes"


def test_unauthorized_event_is_ignored(tmp_path: Path) -> None:
    runner = FakeRunner()
    client = FakeSlackClient()
    service = GatewayService(config(tmp_path), runner)

    handled = service.handle(
        {"user": "U2", "channel": "C1", "ts": "100.1", "text": "run tests"},
        client,
    )

    assert not handled
    assert not runner.prompts
    assert not client.posts


def test_long_responses_are_split() -> None:
    assert _split_message("abcdef", 4) == ["abcd", "ef"]
