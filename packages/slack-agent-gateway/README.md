# Slack agent gateway

The Slack agent gateway lets an allowlisted Slack user invoke Codex or Claude Code from a direct message or an `@mention`.
It retrieves the current Slack thread, supplies that thread as untrusted context, runs the selected agent in the configured workspace, and posts the final answer back to the same thread.

## Security model

The gateway refuses to start unless `SLACK_AGENT_ALLOWED_USERS` contains at least one Slack user ID.
An optional channel allowlist can narrow access further.
The default agent mode is `read-only`.
Slack credentials are removed from the subprocess environment, and Codex shell commands inherit no gateway environment variables.
Slack content is still untrusted input, so only grant access to users and workspaces whose instructions you are willing to execute.

Do not run the gateway with a broad workspace such as your home directory.
Use a dedicated repository and keep `workspace-write` disabled until read-only behavior has been verified.

## Create the Slack app

Create a Slack app from [the checked-in manifest](slack-app-manifest.yaml).
Generate an app-level token with the `connections:write` scope.
Install the app into the workspace and copy the bot token beginning with `xoxb-`.
Invite the bot to each public or private channel where it should receive mentions.

The manifest enables Socket Mode, so the gateway does not need a public HTTP endpoint.
It subscribes to direct messages and app mentions and requests only the history, reply, reaction, and posting permissions used by the gateway.

## Configure and apply

Copy the example to the external configuration path:

```bash
mkdir -p ~/.config/slack-agent-gateway
cp packages/slack-agent-gateway/.env.example ~/.config/slack-agent-gateway/env
chmod 600 ~/.config/slack-agent-gateway/env
```

Replace the example values with the real Slack tokens, your Slack member ID, and the repository or parent directory the agent may access.
The parser accepts only documented `SLACK_*` gateway keys and refuses symlinked or group-readable files.
No token is stored in Git or the Nix store.

Apply the package and launchd agent:

```bash
rebuild
```

Check readiness without printing any token:

```bash
slack-agent-gateway doctor --env-file ~/.config/slack-agent-gateway/env
```

Inspect service logs:

```bash
tail -f ~/.config/slack-agent-gateway/logs/stderr.log
```

Mention the app in a channel with `@Local Coding Agent inspect the failing tests`.
In a direct message, send the request without a mention.
The gateway acknowledges accepted requests with an eyes reaction and posts the result in the originating thread.

## Configuration

- `SLACK_AGENT_PROVIDER` selects `codex` or `claude` and defaults to `codex`.
- `SLACK_AGENT_MODE` selects `read-only` or `workspace-write` and defaults to `read-only`.
- `SLACK_AGENT_ALLOWED_USERS` is a required comma-separated list of Slack user IDs.
- `SLACK_AGENT_ALLOWED_CHANNELS` is an optional comma-separated list of channel IDs.
- `SLACK_AGENT_TIMEOUT_SECONDS` defaults to `900`.
- `SLACK_AGENT_MAX_WORKERS` defaults to `1`.
- `SLACK_AGENT_MAX_CONTEXT_MESSAGES` defaults to `40`.
- `SLACK_AGENT_MAX_RESPONSE_CHARS` defaults to `12000`.

Codex runs with an ephemeral session, the selected sandbox, and no shell environment inheritance.
Claude Code runs without session persistence and uses only its read tools in read-only mode.
Both providers must already be installed and authenticated on the machine running the gateway.
Slack event listeners hand accepted work to a bounded background pool so Socket Mode can acknowledge events promptly.
The single-worker default serializes repository access and should remain in place for writable agents sharing one workspace.

## Operational notes

The current implementation is a single-process personal or small-team gateway managed by Home Manager and launchd.
The launchd agent starts during rebuild and is restarted if it crashes.
For a multi-tenant deployment, add durable job storage, distributed locking, per-workspace credentials, audit retention, and an approval workflow before allowing write operations.
