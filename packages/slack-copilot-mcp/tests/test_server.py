from slack_copilot_mcp.config import CopilotConfig
from slack_copilot_mcp.server import create_server
from slack_copilot_mcp.service import SlackCopilotService
from test_service import FakeSlackApi


def test_tools_advertise_read_and_write_boundaries() -> None:
    service = SlackCopilotService(
        CopilotConfig(
            user_token="xoxp-test",
            workspace_id="T012345678",
            allowed_channels=frozenset(),
            enable_write=True,
        ),
        FakeSlackApi(),
    )
    server = create_server(service)
    tools = {tool.name: tool for tool in server._tool_manager.list_tools()}

    assert set(tools) == {
        "slack_identity",
        "slack_list_conversations",
        "slack_read_channel",
        "slack_read_thread",
        "slack_search_messages",
        "slack_list_users",
        "slack_get_permalink",
        "slack_post_reply",
    }
    assert tools["slack_read_channel"].annotations.readOnlyHint is True
    assert tools["slack_post_reply"].annotations.readOnlyHint is False
    assert tools["slack_post_reply"].annotations.destructiveHint is False
