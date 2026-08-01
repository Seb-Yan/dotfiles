"""Owner-private configuration for the Slack copilot."""

from __future__ import annotations

import os
import re
import stat
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path


class ConfigError(ValueError):
    """Raised when Slack copilot configuration is invalid."""


_ENV_KEY = re.compile(r"^[A-Z][A-Z0-9_]*$")
_WORKSPACE_ID = re.compile(r"^T[A-Z0-9]{8,}$")
_CONVERSATION_ID = re.compile(r"^[CDG][A-Z0-9]{8,}$")
_ALLOWED_ENV_KEYS = {
    "SLACK_COPILOT_ALLOWED_CHANNELS",
    "SLACK_COPILOT_ENABLE_WRITE",
    "SLACK_COPILOT_USER_TOKEN",
    "SLACK_COPILOT_WORKSPACE_ID",
}


def load_env_file(path: Path) -> dict[str, str]:
    """Read a non-executable, owner-private environment file."""
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


def _parse_bool(value: str, name: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ConfigError(f"{name} must be true or false")


def _csv_ids(value: str | None, name: str) -> frozenset[str]:
    values = frozenset(
        item.strip() for item in (value or "").split(",") if item.strip()
    )
    invalid = sorted(item for item in values if not _CONVERSATION_ID.fullmatch(item))
    if invalid:
        raise ConfigError(f"{name} contains invalid Slack IDs: {', '.join(invalid)}")
    return values


@dataclass(frozen=True)
class CopilotConfig:
    """Validated Slack copilot runtime settings."""

    user_token: str | None
    workspace_id: str | None
    allowed_channels: frozenset[str]
    enable_write: bool

    @classmethod
    def from_env(
        cls,
        environ: Mapping[str, str] | None = None,
        *,
        require_credentials: bool = True,
    ) -> CopilotConfig:
        env = os.environ if environ is None else environ
        user_token = env.get("SLACK_COPILOT_USER_TOKEN")
        workspace_id = env.get("SLACK_COPILOT_WORKSPACE_ID")

        if require_credentials and not user_token:
            raise ConfigError("SLACK_COPILOT_USER_TOKEN is required")
        if require_credentials and not workspace_id:
            raise ConfigError("SLACK_COPILOT_WORKSPACE_ID is required")
        if user_token and not user_token.startswith(("xoxp-", "xoxe.xoxp-")):
            raise ConfigError(
                "SLACK_COPILOT_USER_TOKEN must be a Slack user OAuth token"
            )
        if workspace_id and not _WORKSPACE_ID.fullmatch(workspace_id):
            raise ConfigError("SLACK_COPILOT_WORKSPACE_ID is not a valid Slack ID")

        return cls(
            user_token=user_token,
            workspace_id=workspace_id,
            allowed_channels=_csv_ids(
                env.get("SLACK_COPILOT_ALLOWED_CHANNELS"),
                "SLACK_COPILOT_ALLOWED_CHANNELS",
            ),
            enable_write=_parse_bool(
                env.get("SLACK_COPILOT_ENABLE_WRITE", "false"),
                "SLACK_COPILOT_ENABLE_WRITE",
            ),
        )

    def permits_channel(self, channel_id: str) -> bool:
        """Return whether a channel passes the optional allowlist."""
        return not self.allowed_channels or channel_id in self.allowed_channels
