"""CLI entry point for the Slack agent gateway."""

from __future__ import annotations

import argparse
import importlib.util
import logging
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import NoReturn

from slack_agent_gateway.config import ConfigError, GatewayConfig, load_env_file
from slack_agent_gateway.runners import build_runner
from slack_agent_gateway.service import GatewayService


def _quote(value: object) -> str:
    text = str(value)
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


class ToonParser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        print(f"error: {_quote(message)}")
        print(f"help: {_quote(f'Run {self.prog} --help for valid commands and flags')}")
        raise SystemExit(2)


def _parser() -> ToonParser:
    parser = ToonParser(
        prog="slack-agent-gateway",
        description="Connect authorized Slack requests to Codex or Claude Code.",
    )
    subparsers = parser.add_subparsers(dest="command")
    serve = subparsers.add_parser("serve", help="Run the Slack Socket Mode gateway")
    serve.add_argument(
        "--log-level",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
        default="INFO",
        help="stderr logging level (default: INFO)",
    )
    serve.add_argument(
        "--env-file",
        type=Path,
        help="read gateway settings from an owner-private KEY=value file",
    )
    doctor = subparsers.add_parser(
        "doctor", help="Show configuration and dependency readiness"
    )
    doctor.add_argument(
        "--env-file",
        type=Path,
        help="read gateway settings from an owner-private KEY=value file",
    )
    return parser


def _home(config: GatewayConfig | None, error: str | None = None) -> int:
    executable = Path(sys.argv[0]).expanduser()
    home = Path.home()
    try:
        display = "~/" + str(executable.resolve().relative_to(home))
    except ValueError:
        display = str(executable)
    print(f"bin: {_quote(display)}")
    print('description: "Connect authorized Slack requests to a local coding agent"')
    if error:
        print('status: "not ready"')
        print(f"error: {_quote(error)}")
        print("help[2]:")
        print('  - "Configure the required environment variables"')
        print('  - "Run slack-agent-gateway doctor"')
        return 1
    assert config is not None
    binary = shutil.which(config.provider)
    slack_installed = importlib.util.find_spec("slack_bolt") is not None
    missing = []
    if not config.bot_token:
        missing.append("SLACK_BOT_TOKEN")
    if not config.app_token:
        missing.append("SLACK_APP_TOKEN")
    if not config.allowed_users:
        missing.append("SLACK_AGENT_ALLOWED_USERS")
    if not binary:
        missing.append(f"{config.provider} executable")
    if not slack_installed:
        missing.append("slack-agent optional dependencies")
    print(f"status: {_quote('ready' if not missing else 'not ready')}")
    print("gateway:")
    print(f"  provider: {_quote(config.provider)}")
    print(f"  mode: {_quote(config.mode)}")
    print(f"  workspace: {_quote(config.workspace)}")
    print(f"  allowed_users: {len(config.allowed_users)}")
    print(f"  allowed_channels: {len(config.allowed_channels)}")
    print(f"  provider_binary: {_quote(binary or 'missing')}")
    print(f"  slack_support: {_quote('installed' if slack_installed else 'missing')}")
    if missing:
        print(f"missing[{len(missing)}]:")
        for item in missing:
            print(f"  - {_quote(item)}")
        print("help[1]:")
        print('  - "Configure missing values, then run slack-agent-gateway doctor"')
        return 1
    print("help[1]:")
    print('  - "Run slack-agent-gateway serve to receive Slack events"')
    return 0


def _serve(config: GatewayConfig, log_level: str) -> int:
    try:
        from slack_bolt import App
        from slack_bolt.adapter.socket_mode import SocketModeHandler
    except ImportError:
        print('error: "Slack support is not installed"')
        print('help: "Run rebuild to reinstall slack-agent-gateway"')
        return 1

    logging.basicConfig(
        level=getattr(logging, log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    service = GatewayService(config, build_runner(config))
    executor = ThreadPoolExecutor(
        max_workers=config.max_workers,
        thread_name_prefix="slack-agent",
    )
    app = App(token=config.bot_token)

    @app.event("app_mention")
    def handle_mention(event: dict[str, object], client: object) -> None:
        executor.submit(service.handle, event, client)

    @app.event("message")
    def handle_message(event: dict[str, object], client: object) -> None:
        channel_type = event.get("channel_type")
        if channel_type == "im":
            executor.submit(service.handle, event, client)

    logging.getLogger(__name__).info(
        "Starting Slack agent gateway provider=%s mode=%s workspace=%s",
        config.provider,
        config.mode,
        config.workspace,
    )
    try:
        SocketModeHandler(app, config.app_token).start()
    finally:
        executor.shutdown(wait=False, cancel_futures=True)
    return 0


def main(argv: list[str] | None = None) -> None:
    parser = _parser()
    args = parser.parse_args(argv)
    require_tokens = args.command == "serve"
    try:
        environment = dict(os.environ)
        env_file = getattr(args, "env_file", None)
        if env_file is not None:
            environment.update(load_env_file(env_file.expanduser().resolve()))
        config = GatewayConfig.from_env(environment, require_tokens=require_tokens)
    except ConfigError as exc:
        if args.command == "serve":
            print(f"error: {_quote(exc)}")
            print('help: "Run slack-agent-gateway doctor after fixing the environment"')
            raise SystemExit(1) from None
        raise SystemExit(_home(None, str(exc))) from None

    if args.command in {None, "doctor"}:
        raise SystemExit(_home(config))
    if args.command == "serve":
        raise SystemExit(_serve(config, args.log_level))
    parser.error(f"unknown command: {args.command}")
