# Personal Slack copilot MCP

The personal Slack copilot lets Codex and other local agents read Slack messages on demand, summarize or translate them, draft responses, and reply to an existing thread after approval.
It uses a Slack user OAuth token so reads and replies follow the authenticated user's Slack access.
It does not listen for events, mirror a workspace, or store message history.

## Security model

Slack messages are untrusted external content.
The MCP server never treats instructions inside a Slack message as agent instructions.
The server requires a workspace ID and rejects a token authenticated to a different workspace.
An optional channel allowlist narrows access further.
Writes are disabled unless `SLACK_COPILOT_ENABLE_WRITE=true`.
The only write tool posts a reply to an existing thread.
There are no tools for deleting or editing messages, sending new top-level messages, managing channels, or inviting users.

The user token can be powerful.
Keep it outside Git and the Nix store, and do not reuse it for the separate Slack agent gateway.

## Create the Slack app

Create a new Slack app from [the checked-in manifest](slack-app-manifest.yaml).
Use a separate app from Local Coding Agent so Slack-to-Codex and Codex-to-Slack access can be revoked independently.
Install the app into the intended workspace and copy the User OAuth Token beginning with `xoxp-`.
If workspace policy requires administrator approval, complete that approval before continuing.

The manifest requests user scopes for:

- Listing public channels, private channels, direct messages, and group direct messages.
- Reading message and thread history.
- Looking up users.
- Searching messages.
- Posting replies as the authenticated user.

The app does not use Socket Mode, event subscriptions, a bot token, or a public HTTP endpoint.

## Configure and rebuild

Copy the example to the mutable configuration path:

```bash
mkdir -p ~/.config/slack-copilot
cp packages/slack-copilot-mcp/.env.example ~/.config/slack-copilot/env
chmod 600 ~/.config/slack-copilot/env
```

Replace the example token and workspace ID.
The workspace ID is the `T...` segment in a Slack browser URL such as `https://app.slack.com/client/T0123456789/...`.
Keep writes disabled during initial read testing.
Set `SLACK_COPILOT_ALLOWED_CHANNELS` to a comma-separated list of Slack conversation IDs when access should be narrower than the authenticated user's normal visibility.

Apply the Nix package, shared skill, and MCP registrations:

```bash
rebuild
```

Check the installed configuration without printing the token:

```bash
slack-copilot-mcp doctor \
  --env-file ~/.config/slack-copilot/env
```

After read operations work as expected, enable replies:

```dotenv
SLACK_COPILOT_ENABLE_WRITE=true
```

Restart Codex after the first rebuild so it discovers the new MCP server and skill.

## Agent harness compatibility

The MCP server uses standard stdio MCP and contains no Codex-specific or Claude-specific behavior.
Home Manager registers the same server command for Codex, Claude Code, Antigravity CLI (`agy`), Gemini CLI, and OpenCode.

The workflow has one source of truth at `files/agents/skills/slack-copilot/SKILL.md`.
Home Manager exposes that source through `~/.agents/skills/slack-copilot` for Codex and Antigravity, and through `~/.claude/skills/slack-copilot` for Claude Code.
Antigravity receives the shared global skill directory through `~/.gemini/config/skills.json`.

Start a new conversation after rebuilding because harnesses discover MCP tools and skill metadata at session startup.

## Example prompts

```text
Summarize the last 50 messages in #project and include permalinks to decisions.
```

```text
Read this Slack thread and translate the important points into Chinese.
```

```text
Search Slack for deployment failures from Alice this week and explain the current status.
```

```text
Draft a concise reply to this thread, but do not send it.
```

```text
Show me the final reply and, after I approve it, post it to this thread.
```

## Tools

- `slack_identity` verifies the token, user, and workspace.
- `slack_list_conversations` lists visible, locally permitted conversations.
- `slack_read_channel` reads recent messages from one conversation.
- `slack_read_thread` reads a thread from its root timestamp.
- `slack_search_messages` performs a user-scoped Slack search.
- `slack_list_users` resolves message author IDs without returning email addresses.
- `slack_get_permalink` returns a canonical message URL.
- `slack_post_reply` replies to an existing thread when local writes are enabled.

Read responses intentionally contain only a compact subset of Slack message fields.
Files and rich blocks are outside the first version.

## Configuration

- `SLACK_COPILOT_USER_TOKEN` is the required Slack user OAuth token.
- `SLACK_COPILOT_WORKSPACE_ID` is the required expected workspace ID.
- `SLACK_COPILOT_ALLOWED_CHANNELS` is an optional comma-separated conversation ID allowlist.
- `SLACK_COPILOT_ENABLE_WRITE` defaults to `false`.

The configuration parser accepts only these documented keys.
It refuses symlinked, non-regular, or group-readable environment files.
