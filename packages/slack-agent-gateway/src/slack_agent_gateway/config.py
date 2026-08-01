"""Environment-backed configuration for the Slack agent gateway."""

from __future__ import annotations

import os
import re
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


class ConfigError(ValueError):
    """Raised when gateway configuration is invalid."""


_ENV_KEY = re.compile(r"^[A-Z][A-Z0-9_]*$")
_ALLOWED_ENV_KEYS = {
    "SLACK_APP_TOKEN",
    "SLACK_BOT_TOKEN",
    "SLACK_AGENT_ALLOWED_CHANNELS",
    "SLACK_AGENT_ALLOWED_USERS",
    "SLACK_AGENT_MAX_CONTEXT_MESSAGES",
    "SLACK_AGENT_MAX_RESPONSE_CHARS",
    "SLACK_AGENT_MAX_WORKERS",
    "SLACK_AGENT_MODE",
    "SLACK_AGENT_PROVIDER",
    "SLACK_AGENT_TIMEOUT_SECONDS",
    "SLACK_AGENT_WORKSPACE",
}


def load_env_file(path: Path) -> dict[str, str]:
    """Read a non-executable, owner-private gateway environment file."""
    try:
        metadata = path.lstat()
    except FileNotFoundError as exc:
        raise ConfigError(f"environment file does not exist: {path}") from exc
    if stat.S_ISLNK(metadata.st_mode):
        raise ConfigError(f"environment file must not be a symlink: {path}")
    if not stat.S_ISREG(metadata.st_mode):
        raise ConfigError(f"environment file is not a regular file: {path}")
    if stat.S_IMODE(metadata.st_mode) & 0o077:
        raise ConfigError(f"environment file must have mode 0600 or stricter: {path}")

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), 1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line.removeprefix("export ").lstrip()
        if "=" not in line:
            raise ConfigError(
                f"invalid environment file line {line_number}: expected KEY=value"
            )
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not _ENV_KEY.fullmatch(key) or key not in _ALLOWED_ENV_KEYS:
            raise ConfigError(
                f"unsupported environment key on line {line_number}: {key}"
            )
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values


def _csv_set(value: str | None) -> frozenset[str]:
    return frozenset(item.strip() for item in (value or "").split(",") if item.strip())


def _positive_int(value: str, name: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer") from exc
    if parsed < 1:
        raise ConfigError(f"{name} must be greater than zero")
    return parsed


@dataclass(frozen=True)
class GatewayConfig:
    """Validated runtime configuration."""

    bot_token: str | None
    app_token: str | None
    provider: str
    workspace: Path
    allowed_users: frozenset[str]
    allowed_channels: frozenset[str]
    mode: str
    timeout_seconds: int
    max_workers: int
    max_context_messages: int
    max_response_chars: int

    @classmethod
    def from_env(
        cls,
        environ: Mapping[str, str] | None = None,
        *,
        require_tokens: bool = True,
    ) -> GatewayConfig:
        env = os.environ if environ is None else environ
        provider = env.get("SLACK_AGENT_PROVIDER", "codex").lower()
        if provider not in {"codex", "claude"}:
            raise ConfigError("SLACK_AGENT_PROVIDER must be codex or claude")

        mode = env.get("SLACK_AGENT_MODE", "read-only").lower()
        if mode not in {"read-only", "workspace-write"}:
            raise ConfigError("SLACK_AGENT_MODE must be read-only or workspace-write")

        workspace = (
            Path(env.get("SLACK_AGENT_WORKSPACE", os.getcwd())).expanduser().resolve()
        )
        if not workspace.is_dir():
            raise ConfigError(f"SLACK_AGENT_WORKSPACE is not a directory: {workspace}")

        allowed_users = _csv_set(env.get("SLACK_AGENT_ALLOWED_USERS"))
        if require_tokens and not allowed_users:
            raise ConfigError(
                "SLACK_AGENT_ALLOWED_USERS is required and must contain at least one Slack user ID"
            )

        bot_token = env.get("SLACK_BOT_TOKEN")
        app_token = env.get("SLACK_APP_TOKEN")
        if require_tokens and not bot_token:
            raise ConfigError("SLACK_BOT_TOKEN is required")
        if require_tokens and not app_token:
            raise ConfigError("SLACK_APP_TOKEN is required")
        if bot_token and not bot_token.startswith("xoxb-"):
            raise ConfigError("SLACK_BOT_TOKEN must start with xoxb-")
        if app_token and not app_token.startswith("xapp-"):
            raise ConfigError("SLACK_APP_TOKEN must start with xapp-")

        return cls(
            bot_token=bot_token,
            app_token=app_token,
            provider=provider,
            workspace=workspace,
            allowed_users=allowed_users,
            allowed_channels=_csv_set(env.get("SLACK_AGENT_ALLOWED_CHANNELS")),
            mode=mode,
            timeout_seconds=_positive_int(
                env.get("SLACK_AGENT_TIMEOUT_SECONDS", "900"),
                "SLACK_AGENT_TIMEOUT_SECONDS",
            ),
            max_workers=_positive_int(
                env.get("SLACK_AGENT_MAX_WORKERS", "1"),
                "SLACK_AGENT_MAX_WORKERS",
            ),
            max_context_messages=_positive_int(
                env.get("SLACK_AGENT_MAX_CONTEXT_MESSAGES", "40"),
                "SLACK_AGENT_MAX_CONTEXT_MESSAGES",
            ),
            max_response_chars=_positive_int(
                env.get("SLACK_AGENT_MAX_RESPONSE_CHARS", "12000"),
                "SLACK_AGENT_MAX_RESPONSE_CHARS",
            ),
        )

    def permits(self, *, user_id: str, channel_id: str) -> bool:
        if user_id not in self.allowed_users:
            return False
        return not self.allowed_channels or channel_id in self.allowed_channels
