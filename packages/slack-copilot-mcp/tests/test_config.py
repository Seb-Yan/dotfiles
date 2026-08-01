from pathlib import Path

import pytest
from slack_copilot_mcp.config import ConfigError, CopilotConfig, load_env_file


def test_config_requires_user_token_and_workspace() -> None:
    with pytest.raises(ConfigError, match="USER_TOKEN"):
        CopilotConfig.from_env({})


def test_config_parses_write_and_channel_allowlist() -> None:
    config = CopilotConfig.from_env(
        {
            "SLACK_COPILOT_USER_TOKEN": "xoxp-test",
            "SLACK_COPILOT_WORKSPACE_ID": "T012345678",
            "SLACK_COPILOT_ALLOWED_CHANNELS": "C012345678,D012345678",
            "SLACK_COPILOT_ENABLE_WRITE": "true",
        }
    )

    assert config.enable_write is True
    assert config.permits_channel("C012345678")
    assert not config.permits_channel("G012345678")


def test_env_file_must_be_owner_private(tmp_path: Path) -> None:
    path = tmp_path / "env"
    path.write_text(
        "SLACK_COPILOT_USER_TOKEN=xoxp-test\nSLACK_COPILOT_WORKSPACE_ID=T012345678\n",
        encoding="utf-8",
    )
    path.chmod(0o644)

    with pytest.raises(ConfigError, match="0600"):
        load_env_file(path)


def test_env_file_rejects_unknown_keys(tmp_path: Path) -> None:
    path = tmp_path / "env"
    path.write_text("PATH=/tmp\n", encoding="utf-8")
    path.chmod(0o600)

    with pytest.raises(ConfigError, match="unsupported"):
        load_env_file(path)
