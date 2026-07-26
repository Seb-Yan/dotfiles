from pathlib import Path

import pytest

from slack_agent_gateway.config import ConfigError, GatewayConfig, load_env_file


def valid_env(tmp_path: Path) -> dict[str, str]:
    return {
        "SLACK_BOT_TOKEN": "xoxb-test",
        "SLACK_APP_TOKEN": "xapp-test",
        "SLACK_AGENT_ALLOWED_USERS": "U1,U2",
        "SLACK_AGENT_WORKSPACE": str(tmp_path),
    }


def test_config_requires_an_explicit_user_allowlist(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    env.pop("SLACK_AGENT_ALLOWED_USERS")

    with pytest.raises(ConfigError, match="ALLOWED_USERS"):
        GatewayConfig.from_env(env)


def test_config_defaults_to_codex_read_only(tmp_path: Path) -> None:
    config = GatewayConfig.from_env(valid_env(tmp_path))

    assert config.provider == "codex"
    assert config.mode == "read-only"
    assert config.max_workers == 1
    assert config.permits(user_id="U1", channel_id="C1")
    assert not config.permits(user_id="U3", channel_id="C1")


def test_channel_allowlist_is_enforced(tmp_path: Path) -> None:
    env = valid_env(tmp_path)
    env["SLACK_AGENT_ALLOWED_CHANNELS"] = "C1,C2"
    config = GatewayConfig.from_env(env)

    assert config.permits(user_id="U1", channel_id="C2")
    assert not config.permits(user_id="U1", channel_id="C3")


def test_env_file_requires_private_permissions(tmp_path: Path) -> None:
    path = tmp_path / "env"
    path.write_text("SLACK_AGENT_ALLOWED_USERS=U1\n", encoding="utf-8")
    path.chmod(0o644)

    with pytest.raises(ConfigError, match="0600"):
        load_env_file(path)


def test_env_file_loads_only_supported_keys(tmp_path: Path) -> None:
    path = tmp_path / "env"
    path.write_text(
        "# gateway settings\n"
        "export SLACK_AGENT_ALLOWED_USERS='U1,U2'\n"
        "SLACK_AGENT_PROVIDER=claude\n",
        encoding="utf-8",
    )
    path.chmod(0o600)

    assert load_env_file(path) == {
        "SLACK_AGENT_ALLOWED_USERS": "U1,U2",
        "SLACK_AGENT_PROVIDER": "claude",
    }


def test_env_file_rejects_unrelated_environment_keys(tmp_path: Path) -> None:
    path = tmp_path / "env"
    path.write_text("PATH=/tmp/bin\n", encoding="utf-8")
    path.chmod(0o600)

    with pytest.raises(ConfigError, match="unsupported environment key"):
        load_env_file(path)
