from slack_agent_gateway.runners import _subprocess_env


def test_subprocess_environment_drops_slack_tokens() -> None:
    result = _subprocess_env(
        {
            "PATH": "/bin",
            "HOME": "/home/test",
            "SLACK_BOT_TOKEN": "xoxb-secret",
            "SLACK_APP_TOKEN": "xapp-secret",
            "UNRELATED_SECRET": "secret",
        }
    )

    assert result == {"PATH": "/bin", "HOME": "/home/test"}
