# Legacy migration map

The exact history of `Seb-Yan/dotfiles-mac-nix` remains available on the `legacy/dotfiles-mac-nix` branch.
The maintained `main` line keeps the new repository architecture and ports personal behavior in focused commits.

## Personal system and development configuration

Commit `a67a5bf` ports the user identity, macOS defaults, declared Homebrew inventory, Nix packages, Git, zsh, tmux, Treehouse, fonts, and language tooling.
It carries forward legacy commits `b635f92`, `2b74346`, `472cf06`, `3bcb454`, `c0a64ec`, `9fdd4cd`, `2028e05`, and `82799e1`.

## Shared agent and editor configuration

Commit `896d075` ports the shared agent policy, opinions and voice files, cross-harness skills, Claude security configuration, VS Code settings, and Treehouse defaults.
It carries forward legacy commits `08e3241`, `0471fb8`, `291f467`, `2028e05`, `2e85347`, `bc3dcd8`, `93a547f`, `48e5608`, `efe6f17`, and `176383b`.

## WezTerm workflow

Commit `71f997b` ports the workspace, tab, pane, fullscreen, notification, and presentation workflow while retaining the maintained repository's unfocused-window dimming behavior.
It carries forward legacy commits `86f02bf`, `291f467`, and `2069c0f`.

## Slack and MCP services

Commit `d8a82d2` ports the Slack gateway, Slack Copilot MCP, Outlook MCP wrapper, cross-harness registration, launch agent, package documentation, and tests.
It carries forward legacy commits `b8f11d5`, `9618e7a`, and `efe6f17`.

## Replaced by the maintained architecture

The legacy Neovim commit `06b90a5` is represented by the maintained repository's `home/.config/nvim` configuration instead of restoring the old inline Home Manager Lua block.
The old bootstrap commits `dc13ccf` and `9697e58` are represented by the maintained repository's `bootstrap.sh` and its `~/.dotfiles` model.
The old repository-noise commit `f9e3ac7` is represented by the maintained `.gitignore`, including the migrated `.no-mistakes/` and Python cache rules.
Merge commits `81d1f1b`, `889af18`, `cab439d`, `abaf466`, and `24bc1dd` carry topology rather than additional migration behavior and remain available on the legacy branch.
The original root commit `d2769f7` also remains available on the legacy branch.

## Compatibility adjustments

The untrusted AdoptOpenJDK 11 cask is replaced by the maintained Temurin 11 cask.
Codex is installed through its maintained Homebrew cask, and MCP reconciliation targets `/opt/homebrew/bin/codex`.
The no-mistakes agent switchers now fail clearly when their local config is absent and avoid interpolating replacement text through Nix.
