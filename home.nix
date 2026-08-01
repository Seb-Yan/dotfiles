{ config, lib, pkgs, treehouse, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  vscodeBin = "/opt/homebrew/bin/code";
  vscodeExtensions = [
    "ms-python.python"
    "charliermarsh.ruff"
    "ms-toolsai.jupyter"
    "redhat.vscode-yaml"
    "tamasfe.even-better-toml"
    "jnoortheen.nix-ide"
    "yzhang.markdown-all-in-one"
    "james-yu.latex-workshop"
    "editorconfig.editorconfig"
  ];
  outlookMcpPackage = "@softeria/ms-365-mcp-server@0.131.3";
  outlookMcp = pkgs.writeShellApplication {
    name = "outlook-mcp";
    runtimeInputs = [ pkgs.nodejs_22 ];
    text = ''
      package=${lib.escapeShellArg outlookMcpPackage}
      scopes="User.Read Mail.ReadWrite Mail.Send Calendars.ReadWrite Contacts.Read"

      run_server() {
        exec npx --yes "$package" \
          --preset outlook \
          --allowed-scopes "$scopes" \
          --toon \
          "$@"
      }

      case "''${1:-}" in
        server)
          shift
          run_server "$@"
          ;;
        login)
          shift
          exec npx --yes "$package" \
            --preset outlook \
            --allowed-scopes "$scopes" \
            --login \
            "$@"
          ;;
        logout)
          shift
          exec npx --yes "$package" --logout "$@"
          ;;
        accounts)
          shift
          exec npx --yes "$package" --list-accounts "$@"
          ;;
        permissions)
          shift
          exec npx --yes "$package" \
            --preset outlook \
            --allowed-scopes "$scopes" \
            --list-permissions \
            "$@"
          ;;
        help|--help|-h)
          printf '%s\n' \
            'bin: outlook-mcp' \
            'description: Run and authenticate the shared Outlook MCP server' \
            'commands[5]{name,description}:' \
            '  server,Start the stdio MCP server' \
            '  login,Authenticate an Outlook account with Microsoft device login' \
            '  logout,Remove cached Outlook authentication' \
            '  accounts,List authenticated Outlook accounts' \
            '  permissions,Show the Microsoft Graph permissions requested'
          ;;
        "")
          printf '%s\n' \
            'bin: outlook-mcp' \
            'description: Run and authenticate the shared Outlook MCP server' \
            'status: setup requires a one-time human login' \
            'help[2]:' \
            '  Run outlook-mcp login to authenticate' \
            '  Run outlook-mcp accounts to inspect authenticated accounts'
          ;;
        *)
          printf 'error: unknown command %s\n' "$1"
          printf '%s\n' 'help: valid commands are server, login, logout, accounts, permissions, help'
          exit 2
          ;;
      esac
    '';
  };
  slackAgentGateway = pkgs.callPackage ./packages/slack-agent-gateway/package.nix { };
  slackAgentConfigDir = "${config.home.homeDirectory}/.config/slack-agent-gateway";
  slackAgentEnvFile = "${slackAgentConfigDir}/env";
  slackCopilotMcp = pkgs.callPackage ./packages/slack-copilot-mcp/package.nix { };
  slackCopilotConfigDir = "${config.home.homeDirectory}/.config/slack-copilot";
  slackCopilotEnvFile = "${slackCopilotConfigDir}/env";
  claudeBin = "${config.home.homeDirectory}/.local/bin/claude";
  codexBin = "${config.home.homeDirectory}/.npm-global/bin/codex";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.language.base = "en_US.UTF-8";
  home.packages = with pkgs; [
    git
    curl
    wget
    jq
    fd
    fzf
    fastfetch
    mdcat
    ripgrep
    killall
    lazygit
    neovim
    tree
    bun
    rustup
    uv
    nodejs_22
    gh
    htop
    btop
    rclone
    cmake
    nil
    lua-language-server
    pyright
    typescript-language-server
    awscli2
    zip
    unzip
    texlive.combined.scheme-medium
    poppler-utils
    treehouse.packages.${pkgs.stdenv.hostPlatform.system}.default
    nerd-fonts.hack
    roboto
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
    outlookMcp
    slackAgentGateway
    slackCopilotMcp
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    JAVA_HOME = "/Library/Java/JavaVirtualMachines/jdk-23.jdk/Contents/Home";
  };
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  programs.npm = {
    enable = true;
    package = pkgs.nodejs_22;
    settings.prefix = "${config.home.homeDirectory}/.npm-global";
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;
    settings = {
      user = {
        name = "Yuwei Yan";
        email = "yuweiyan@uchicago.edu";
      };
      core.editor = "nvim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      rebase.updateRefs = true;
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = lib.mkAfter ''
      bindkey '^f' autosuggest-accept

      # Keep Nix-managed tools ahead of conda and Homebrew on PATH.
      export PATH="/etc/profiles/per-user/${user}/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"

      twget() {
        local repo
        repo=$(basename "$(git rev-parse --show-toplevel)") || return 1
        local label="''${1:-$repo}"
        local wt_path
        wt_path=$(treehouse get --lease --lease-holder "$label") || return 1
        if [ -n "$TMUX" ]; then
          tmux new-window -c "$wt_path" -n "$label"
        else
          cd "$wt_path" || return 1
        fi
      }

      twreturn() {
        local wt_path
        wt_path=$(pwd)
        treehouse return "$wt_path" "$@" || return 1
        if [ -n "$TMUX" ]; then
          tmux kill-window
        fi
      }

      firstmate() {
        local fm_dir="$HOME/github/firstmate"
        if [ ! -d "$fm_dir/.git" ]; then
          echo "First Mate checkout not found at $fm_dir." >&2
          return 1
        fi

        cd "$fm_dir" || return 1
        if [ "$#" -gt 0 ]; then
          "$@"
        elif command -v claude >/dev/null 2>&1; then
          claude
        else
          echo "No default harness found. Run: firstmate codex, firstmate opencode, or firstmate pi" >&2
          return 1
        fi
      }
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      amend = "git commit --amend";
      push = "git push";
      pushf = "git push --force";
      pull = "git pull";
      m = "git switch main";
      mst = "git switch master";
      rebasem = "git rebase -i main";
      rebasemst = "git rebase -i master";
      rebuild = "${dotfiles}/rebuild.sh";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
      directory.style = "blue";
      git_branch = {
        format = "[$branch]($style)";
        style = "bright-black";
      };
      git_status = {
        format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
        style = "cyan";
        stashed = "≡";
      };
      git_state = {
        format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
        style = "bright-black";
      };
    };
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 50000;
    terminal = "tmux-256color";
    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      {
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-strategy-nvim 'session'
        '';
      }
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];
    extraConfig = ''
      set -g renumber-windows on
      set -ga terminal-overrides ",*256col*:Tc"
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind -r h select-pane -L
      bind -r j select-pane -D
      bind -r k select-pane -U
      bind -r l select-pane -R
      set -g status-position top
      set -g status-style "bg=default,fg=#908caa"
      set -g status-left "#[fg=#c4a7e7,bold] #S "
      set -g status-right "#[fg=#908caa] %Y-%m-%d %H:%M "
      setw -g window-status-current-format "#[fg=#e0def4,bold] #I:#W "
      setw -g window-status-format "#[fg=#6e6a86] #I:#W "
    '';
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".gemini/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".gemini/GEMINI.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  home.file."OPINIONS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/OPINIONS.md";
  home.file."VOICE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/VOICE.md";

  home.file."Library/Application Support/Code/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/vscode/settings.json";
  home.file.".claude/hooks/bash-guard.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/hooks/bash-guard.sh";

  home.file.".agents/skills/adaptive-professional-communication".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/adaptive-professional-communication";
  home.file.".claude/skills/adaptive-professional-communication".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/adaptive-professional-communication";
  home.file.".agents/skills/outlook-mail".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/outlook-mail";
  home.file.".claude/skills/outlook-mail".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/outlook-mail";
  home.file.".agents/skills/slack-copilot".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/slack-copilot";
  home.file.".claude/skills/slack-copilot".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/slack-copilot";
  home.file.".agents/skills/wezterm-workspace-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/wezterm-workspace-manager";
  home.file.".claude/skills/wezterm-workspace-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/wezterm-workspace-manager";
  home.file.".agents/skills/latex-tikz-flowcharts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/latex-tikz-flowcharts";
  home.file.".claude/skills/latex-tikz-flowcharts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/latex-tikz-flowcharts";
  home.file.".agents/skills/beamer".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/beamer";
  home.file.".claude/skills/beamer".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/beamer";

  home.file.".claude/skills/github-multi-account/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/github-multi-account/SKILL.md";
  home.file.".claude/skills/setup-bitbucket-mirror/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/setup-bitbucket-mirror/SKILL.md";
  home.file.".claude/skills/setup-dev-trunk/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/setup-dev-trunk/SKILL.md";
  home.file.".claude/skills/ship-pr/SKILL.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/skills/ship-pr/SKILL.md";

  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    mcp.outlook = {
      type = "local";
      command = [ "outlook-mcp" "server" ];
      enabled = true;
    };
    mcp."slack-copilot" = {
      type = "local";
      command = [
        "slack-copilot-mcp"
        "server"
        "--env-file"
        slackCopilotEnvFile
      ];
      enabled = true;
    };
  };
  home.file.".gemini/config/mcp_config.json".text = builtins.toJSON {
    mcpServers.outlook = {
      command = "outlook-mcp";
      args = [ "server" ];
    };
    mcpServers."slack-copilot" = {
      command = "slack-copilot-mcp";
      args = [ "server" "--env-file" slackCopilotEnvFile ];
    };
  };
  home.file.".gemini/config/skills.json".text = builtins.toJSON {
    entries = [
      { path = "${config.home.homeDirectory}/.agents/skills"; }
    ];
  };
  home.file.".gemini/antigravity-cli/mcp_config.json".text = builtins.toJSON {
    mcpServers.outlook = {
      command = "outlook-mcp";
      args = [ "server" ];
    };
    mcpServers."slack-copilot" = {
      command = "slack-copilot-mcp";
      args = [ "server" "--env-file" slackCopilotEnvFile ];
    };
  };

  home.activation.installVscodeExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x ${lib.escapeShellArg vscodeBin} ]; then
      installed_extensions="$(${lib.escapeShellArg vscodeBin} --list-extensions)"
      for extension in ${lib.concatMapStringsSep " " lib.escapeShellArg vscodeExtensions}; do
        if ! printf '%s\n' "$installed_extensions" | ${pkgs.gnugrep}/bin/grep -Fqx "$extension"; then
          run ${lib.escapeShellArg vscodeBin} --install-extension "$extension"
        fi
      done
    else
      echo "warning: VS Code CLI not found at ${vscodeBin}; extensions will be installed on the next rebuild"
    fi
  '';

  home.activation.configurePersonalMcps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH=${lib.escapeShellArg (lib.makeBinPath [ pkgs.nodejs_22 ])}:"$PATH"

    if [ -x ${lib.escapeShellArg claudeBin} ]; then
      run ${lib.escapeShellArg claudeBin} mcp remove --scope user outlook >/dev/null 2>&1 || true
      run ${lib.escapeShellArg claudeBin} mcp add --scope user outlook -- outlook-mcp server
      run ${lib.escapeShellArg claudeBin} mcp remove --scope user slack-copilot >/dev/null 2>&1 || true
      run ${lib.escapeShellArg claudeBin} mcp add --scope user slack-copilot -- \
        slack-copilot-mcp server --env-file ${lib.escapeShellArg slackCopilotEnvFile}
    fi

    if [ -x ${lib.escapeShellArg codexBin} ]; then
      run ${lib.escapeShellArg codexBin} mcp remove outlook >/dev/null 2>&1 || true
      run ${lib.escapeShellArg codexBin} mcp add outlook -- outlook-mcp server
      run ${lib.escapeShellArg codexBin} mcp remove slack-copilot >/dev/null 2>&1 || true
      run ${lib.escapeShellArg codexBin} mcp add slack-copilot -- \
        slack-copilot-mcp server --env-file ${lib.escapeShellArg slackCopilotEnvFile}
    fi
  '';

  home.activation.prepareSlackConfiguration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.coreutils}/bin/install -d -m 0700 \
      ${lib.escapeShellArg slackAgentConfigDir} \
      ${lib.escapeShellArg "${slackAgentConfigDir}/logs"} \
      ${lib.escapeShellArg slackCopilotConfigDir}
  '';

  launchd.agents.slack-agent-gateway = {
    enable = true;
    config = {
      ProgramArguments = [
        "${slackAgentGateway}/bin/slack-agent-gateway"
        "serve"
        "--env-file"
        slackAgentEnvFile
      ];
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        LANG = "en_US.UTF-8";
        PATH = lib.concatStringsSep ":" [
          "${config.home.homeDirectory}/.local/bin"
          "${config.home.homeDirectory}/.npm-global/bin"
          "${config.home.homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/${user}/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
        ];
        USER = config.home.username;
      };
      WorkingDirectory = config.home.homeDirectory;
      RunAtLoad = true;
      KeepAlive.Crashed = true;
      ProcessType = "Background";
      ThrottleInterval = 30;
      StandardOutPath = "${slackAgentConfigDir}/logs/stdout.log";
      StandardErrorPath = "${slackAgentConfigDir}/logs/stderr.log";
    };
  };
}
