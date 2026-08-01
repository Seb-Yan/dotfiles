---
name: wezterm-workspace-manager
description: Guide and operate Seb's WezTerm workspace, window, tab, and pane organization. Use whenever the user asks how to organize concurrent terminal tasks, create or inspect a named WezTerm workspace, create tabs or panes, rename or pin a tab, build a standard development layout, switch terminal context, or keep multi-project terminal work easy to remember.
compatibility: Requires WezTerm CLI and the bundled wezterm-workspace script.
---

# WezTerm Workspace Manager

Use the bundled `scripts/wezterm-workspace` command for deterministic WezTerm operations.
Resolve the script path relative to this `SKILL.md` rather than assuming it is installed on `PATH`.

## Mental model

Treat a workspace as one project or durable task.
Treat a tab as one role such as `editor`, `server`, `tests`, or `logs`.
Treat a pane as a temporary simultaneous view within a role.

Use short responsibility-based names rather than generic names such as `tab-1` or `shell`.
Use the `📌 ` prefix for important tabs that should remain visually prominent.
WezTerm does not implement true pinned tabs, so never claim that the prefix prevents closing.

## Safe operating workflow

Inspect the live state before mutating it:

```sh
scripts/wezterm-workspace list
```

Creating tabs, panes, or workspaces changes the user's live GUI session.
Do it when the user explicitly asks to create or arrange them.
If the execution environment requires approval to access the WezTerm GUI socket, request that approval instead of working around the sandbox.

Never send commands or text into a pane unless the user explicitly asks for those exact commands.
The layout command only starts login shells and names their tabs.
It does not start servers, tests, deployments, or other workloads.

## Common operations

Create a named workspace in a new WezTerm window:

```sh
scripts/wezterm-workspace create quant-api --cwd /path/to/quant-api --title "📌 editor"
```

Create a standard workspace with `📌 editor`, `server`, `tests`, and `logs` tabs:

```sh
scripts/wezterm-workspace layout dev quant-api --cwd /path/to/quant-api
```

Create a named tab in a known window:

```sh
scripts/wezterm-workspace new-tab server --window-id 3 --cwd /path/to/quant-api
```

Split a known pane:

```sh
scripts/wezterm-workspace split right --pane-id 7 --cwd /path/to/quant-api
```

Rename a tab:

```sh
scripts/wezterm-workspace rename-tab "📌 editor" --tab-id 4
```

Rename a workspace:

```sh
scripts/wezterm-workspace rename-workspace quant-api --workspace default
```

## Guidance responses

When the user asks for advice rather than execution, recommend the smallest clear layout.
Explain the proposed workspace, tabs, and panes in Chinese when the user writes in Chinese.
Mention relevant configured shortcuts when useful:

- `Cmd+Alt+R` renames the active tab.
- `Cmd+Alt+P` marks the active tab with `📌` and moves it left.
- `Cmd+Alt+W` creates or switches to a named workspace.
- `Cmd+Alt+F` searches tabs and workspaces.
- `Cmd+Alt+Z` toggles pane zoom.
- `Cmd+Alt+Shift+[` and `Cmd+Alt+Shift+]` move a tab.
- `Cmd+Alt+O` returns to the previously active tab.

Report the pane, tab, window, or workspace identifiers returned by the script after an operation.
If no GUI is running or no unambiguous target exists, explain what target information is needed rather than guessing.
