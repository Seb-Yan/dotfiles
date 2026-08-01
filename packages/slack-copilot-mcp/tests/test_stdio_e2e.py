import os
import sys
from pathlib import Path

import pytest
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


@pytest.mark.asyncio
async def test_real_stdio_server_lists_expected_tools(tmp_path: Path) -> None:
    env_file = tmp_path / "env"
    env_file.write_text(
        "SLACK_COPILOT_USER_TOKEN=xoxp-test\nSLACK_COPILOT_WORKSPACE_ID=T012345678\n",
        encoding="utf-8",
    )
    env_file.chmod(0o600)
    parameters = StdioServerParameters(
        command=sys.executable,
        args=[
            "-m",
            "slack_copilot_mcp",
            "server",
            "--env-file",
            str(env_file),
        ],
        env=dict(os.environ),
    )

    async with (
        stdio_client(parameters) as streams,
        ClientSession(*streams) as session,
    ):
        await session.initialize()
        result = await session.list_tools()

    assert {tool.name for tool in result.tools} == {
        "slack_identity",
        "slack_list_conversations",
        "slack_read_channel",
        "slack_read_thread",
        "slack_search_messages",
        "slack_list_users",
        "slack_get_permalink",
        "slack_post_reply",
    }
