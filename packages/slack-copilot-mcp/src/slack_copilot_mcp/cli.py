"""CLI entry point for the Slack copilot MCP server."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import NoReturn

from slack_sdk import WebClient

from slack_copilot_mcp.config import ConfigError, CopilotConfig, load_env_file
from slack_copilot_mcp.server import create_server
from slack_copilot_mcp.service import CopilotError, SlackCopilotService


def _quote(value: object) -> str:
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


class CopilotParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        print(f"error: {_quote(message)}")
        print(
            'help: "Valid commands are server and doctor; '
            'the valid command flag is --env-file"'
        )
        raise SystemExit(2)


def _parser() -> CopilotParser:
    parser = CopilotParser(
        prog="slack-copilot-mcp",
        description="Read and reply to personal Slack messages through MCP.",
    )
    subparsers = parser.add_subparsers(dest="command")
    for command, help_text, example in (
        (
            "server",
            "Run the stdio MCP server",
            "slack-copilot-mcp server --env-file ~/.config/slack-copilot/env",
        ),
        (
            "doctor",
            "Validate configuration and Slack authentication",
            "slack-copilot-mcp doctor --env-file ~/.config/slack-copilot/env",
        ),
    ):
        subparser = subparsers.add_parser(
            command,
            help=help_text,
            epilog=f"example: {example}",
        )
        subparser.add_argument(
            "--env-file",
            type=Path,
            help="read settings from an owner-private KEY=value file",
        )
    return parser


def _load_config(
    env_file: Path | None,
    *,
    require_credentials: bool,
) -> CopilotConfig:
    environment = dict(os.environ)
    selected_env_file = env_file or Path.home() / ".config/slack-copilot/env"
    environment.update(load_env_file(selected_env_file.expanduser().resolve()))
    return CopilotConfig.from_env(
        environment,
        require_credentials=require_credentials,
    )


def _service(config: CopilotConfig) -> SlackCopilotService:
    assert config.user_token is not None
    return SlackCopilotService(config, WebClient(token=config.user_token))


def _home(config: CopilotConfig | None, error: str | None = None) -> int:
    executable = Path(sys.argv[0]).expanduser()
    home = Path.home()
    try:
        display = "~/" + str(executable.resolve().relative_to(home))
    except ValueError:
        display = str(executable.resolve())
    print(f"bin: {_quote(display)}")
    print('description: "Read and reply to personal Slack messages through MCP"')
    if error:
        print('status: "not ready"')
        print(f"error: {_quote(error)}")
        print("help[2]:")
        print('  - "Create ~/.config/slack-copilot/env with mode 0600"')
        print(
            '  - "Run slack-copilot-mcp doctor --env-file ~/.config/slack-copilot/env"'
        )
        return 1
    assert config is not None
    try:
        identity = _service(config).identity()
    except CopilotError as exc:
        print('status: "not ready"')
        print(f"error: {_quote(exc)}")
        return 1
    print('status: "ready"')
    print("slack:")
    print(f"  workspace: {_quote(identity['workspace'])}")
    print(f"  workspace_id: {_quote(identity['workspace_id'])}")
    print(f"  user: {_quote(identity['user'])}")
    print(f"  user_id: {_quote(identity['user_id'])}")
    print(f"  write_enabled: {str(config.enable_write).lower()}")
    print(f"  allowed_channels: {len(config.allowed_channels)}")
    return 0


def main(argv: list[str] | None = None) -> None:
    parser = _parser()
    args = parser.parse_args(argv)
    command = args.command or "doctor"
    try:
        config = _load_config(
            getattr(args, "env_file", None),
            require_credentials=True,
        )
    except ConfigError as exc:
        raise SystemExit(_home(None, str(exc))) from None

    if command == "doctor":
        raise SystemExit(_home(config))
    if command == "server":
        create_server(_service(config)).run(transport="stdio")
        return
    parser.error(f"unknown command: {command}")
