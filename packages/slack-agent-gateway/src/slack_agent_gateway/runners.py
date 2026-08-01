"""Non-interactive Codex and Claude Code subprocess adapters."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from slack_agent_gateway.config import GatewayConfig


@dataclass(frozen=True)
class AgentResult:
    text: str
    provider: str
    succeeded: bool


class AgentRunner(Protocol):
    def run(self, prompt: str) -> AgentResult: ...


def _subprocess_env(source: Mapping[str, str] | None = None) -> dict[str, str]:
    env = os.environ if source is None else source
    allowed = {
        "ANTHROPIC_API_KEY",
        "CODEX_HOME",
        "HOME",
        "LANG",
        "LC_ALL",
        "OPENAI_API_KEY",
        "PATH",
        "SHELL",
        "SSL_CERT_FILE",
        "TERM",
        "TMPDIR",
        "USER",
    }
    return {key: value for key, value in env.items() if key in allowed}


def _failure(provider: str, message: str) -> AgentResult:
    return AgentResult(
        text=f"{provider} could not complete the request: {message}",
        provider=provider,
        succeeded=False,
    )


class CodexRunner:
    def __init__(self, config: GatewayConfig) -> None:
        self.config = config

    def run(self, prompt: str) -> AgentResult:
        executable = shutil.which("codex")
        if not executable:
            return _failure("codex", "the codex executable is not available on PATH")

        with tempfile.TemporaryDirectory(prefix="slack-agent-codex-") as temp_dir:
            output_path = Path(temp_dir) / "last-message.txt"
            command = [
                executable,
                "exec",
                "--cd",
                str(self.config.workspace),
                "--sandbox",
                self.config.mode,
                "--ephemeral",
                "--color",
                "never",
                "--output-last-message",
                str(output_path),
                "--config",
                "shell_environment_policy.inherit=none",
                "-",
            ]
            try:
                completed = subprocess.run(
                    command,
                    input=prompt,
                    text=True,
                    capture_output=True,
                    timeout=self.config.timeout_seconds,
                    env=_subprocess_env(),
                    check=False,
                )
            except subprocess.TimeoutExpired:
                return _failure(
                    "codex", f"timed out after {self.config.timeout_seconds} seconds"
                )
            except OSError as exc:
                return _failure("codex", str(exc))

            text = (
                output_path.read_text(encoding="utf-8").strip()
                if output_path.exists()
                else ""
            )
            if completed.returncode != 0:
                return _failure("codex", _last_error(completed.stderr))
            if not text:
                return _failure("codex", "no final response was produced")
            return AgentResult(text=text, provider="codex", succeeded=True)


class ClaudeRunner:
    def __init__(self, config: GatewayConfig) -> None:
        self.config = config

    def run(self, prompt: str) -> AgentResult:
        executable = shutil.which("claude")
        if not executable:
            return _failure("claude", "the claude executable is not available on PATH")

        command = [
            executable,
            "--print",
            "--output-format",
            "json",
            "--no-session-persistence",
        ]
        if self.config.mode == "read-only":
            command.extend(["--permission-mode", "plan", "--tools", "Read,Glob,Grep"])
        else:
            command.extend(["--permission-mode", "acceptEdits"])
        command.append(prompt)

        try:
            completed = subprocess.run(
                command,
                cwd=self.config.workspace,
                text=True,
                capture_output=True,
                timeout=self.config.timeout_seconds,
                env=_subprocess_env(),
                check=False,
            )
        except subprocess.TimeoutExpired:
            return _failure(
                "claude", f"timed out after {self.config.timeout_seconds} seconds"
            )
        except OSError as exc:
            return _failure("claude", str(exc))

        if completed.returncode != 0:
            return _failure("claude", _last_error(completed.stderr))
        try:
            payload = json.loads(completed.stdout)
            text = str(payload["result"]).strip()
        except (json.JSONDecodeError, KeyError, TypeError):
            return _failure("claude", "returned an invalid response")
        if not text:
            return _failure("claude", "no final response was produced")
        return AgentResult(text=text, provider="claude", succeeded=True)


def _last_error(stderr: str) -> str:
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    return lines[-1][:500] if lines else "the process exited unsuccessfully"


def build_runner(config: GatewayConfig) -> AgentRunner:
    if config.provider == "codex":
        return CodexRunner(config)
    return ClaudeRunner(config)
