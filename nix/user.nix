{ config, lib, pkgs, treehouse, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles-mac-nix";
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
  slackAgentGateway = pkgs.callPackage ../packages/slack-agent-gateway/package.nix { };
  slackAgentConfigDir = "${config.home.homeDirectory}/.config/slack-agent-gateway";
  slackAgentEnvFile = "${slackAgentConfigDir}/env";
  slackCopilotMcp = pkgs.callPackage ../packages/slack-copilot-mcp/package.nix { };
  slackCopilotConfigDir = "${config.home.homeDirectory}/.config/slack-copilot";
  slackCopilotEnvFile = "${slackCopilotConfigDir}/env";
  claudeBin = "${config.home.homeDirectory}/.local/bin/claude";
  codexBin = "${config.home.homeDirectory}/.npm-global/bin/codex";
in
{
  home.username = "yuweiyan";
  home.homeDirectory = "/Users/yuweiyan";
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";

  home.packages = with pkgs; [
    git
    curl
    wget
    jq
    fd
    fastfetch
    mdcat
    ripgrep
    killall
    lazygit
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
    # Git worktree manager for running parallel agent sessions without
    # them stepping on each other (github.com/kunchenguid/treehouse)
    treehouse.packages.${pkgs.system}.default
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
    EDITOR = "vim";
    JAVA_HOME = "/Library/Java/JavaVirtualMachines/jdk-23.jdk/Contents/Home";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.cargo/bin"
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  # The Nix-provided Node lives in the read-only /nix/store, so `npm install -g`
  # needs its own writable global prefix instead of trying to write next to it.
  programs.npm = {
    enable = true;
    package = pkgs.nodejs_22;
    settings = {
      prefix = "${config.home.homeDirectory}/.npm-global";
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = false;
    withPython3 = false;
    withRuby = false;
    viAlias = true;
    vimAlias = true;
    plugins = with pkgs.vimPlugins; [
      neogit
      diffview-nvim
      telescope-nvim
      plenary-nvim
      neo-tree-nvim
      nui-nvim
      nvim-web-devicons
      rose-pine
      (nvim-treesitter.withPlugins (p: with p; [
        bash
        c
        css
        html
        javascript
        json
        lua
        markdown
        markdown_inline
        nix
        python
        rust
        toml
        tsx
        typescript
        vim
        vimdoc
        yaml
      ]))
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      cmp_luasnip
      gitsigns-nvim
      lualine-nvim
      which-key-nvim
    ];
    initLua = ''
      vim.g.mapleader = " "
      vim.g.maplocalleader = " "

      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.signcolumn = "yes"
      vim.opt.termguicolors = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.updatetime = 250
      vim.opt.timeoutlen = 400
      vim.opt.winblend = 10
      vim.opt.pumblend = 10

      vim.cmd("packloadall")
      for _, plugin_dir in ipairs(vim.fn.globpath(vim.o.packpath, "pack/*/start/*", false, true)) do
        vim.opt.runtimepath:prepend(plugin_dir)
      end

      local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
      end

      require("rose-pine").setup({
        variant = "moon",
        dark_variant = "moon",
        styles = {
          transparency = true,
        },
        highlight_groups = {
          EndOfBuffer = { bg = "NONE" },
          LineNr = { bg = "NONE" },
          CursorLineNr = { bg = "NONE" },
          NeoTreeNormal = { bg = "NONE" },
          NeoTreeNormalNC = { bg = "NONE" },
          NeoTreeEndOfBuffer = { bg = "NONE" },
          NeoTreeWinSeparator = { fg = "muted", bg = "NONE" },
          NeogitNormal = { bg = "NONE" },
          NeogitPopupSwitchKey = { bg = "NONE" },
          NeogitPopupOptionKey = { bg = "NONE" },
          NeogitPopupConfigKey = { bg = "NONE" },
          NeogitPopupActionKey = { bg = "NONE" },
          CmpDocumentation = { bg = "NONE" },
          CmpDocumentationBorder = { bg = "NONE" },
        },
      })
      vim.cmd("colorscheme rose-pine-moon")

      require("which-key").setup({})
      require("lualine").setup({
        options = {
          theme = "rose-pine",
        },
      })
      require("gitsigns").setup({})
      require("nvim-treesitter").setup({})
      vim.api.nvim_create_autocmd("FileType", {
        pattern = {
          "bash",
          "c",
          "css",
          "html",
          "javascript",
          "json",
          "lua",
          "markdown",
          "nix",
          "python",
          "rust",
          "toml",
          "typescript",
          "typescriptreact",
          "vim",
          "yaml",
        },
        callback = function()
          pcall(vim.treesitter.start)
        end,
      })

      require("neo-tree").setup({
        filesystem = {
          follow_current_file = { enabled = true },
          use_libuv_file_watcher = true,
        },
      })

      require("telescope").setup({})
      local telescope_builtin = require("telescope.builtin")
      require("neogit").setup({
        integrations = {
          diffview = true,
          telescope = true,
        },
      })

      local cmp = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
          { name = "buffer" },
        }),
      })

      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      local servers = {
        "nil_ls",
        "lua_ls",
        "pyright",
        "rust_analyzer",
        "ts_ls",
      }
      for _, server in ipairs(servers) do
        vim.lsp.config(server, { capabilities = capabilities })
        vim.lsp.enable(server)
      end

      map("n", "<leader>e", "<cmd>Neotree toggle<cr>", "Toggle file tree")
      map("n", "<leader>ff", function()
        telescope_builtin.find_files({ hidden = true })
      end, "Find files")
      map("n", "<leader>fg", telescope_builtin.live_grep, "Search text")
      map("n", "<leader>fb", telescope_builtin.buffers, "Find buffers")
      map("n", "<leader>gg", "<cmd>Neogit<cr>", "Open Neogit")
      map("n", "<leader>gd", vim.lsp.buf.definition, "Go to definition")
      map("n", "<leader>gr", vim.lsp.buf.references, "Find references")
      map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
      map("n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
      map("n", "<leader>df", vim.diagnostic.open_float, "Show diagnostic")
      map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
      map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
    '';
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
      core.editor = "vim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      rebase.updateRefs = true;
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      command_timeout = 1000;
      add_newline = false;
      format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$character";

      directory.style = "blue";

      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };

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

      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };

      python = {
        format = "[$virtualenv]($style) ";
        style = "bright-black";
      };
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ".." = "cd ..";
      m = "git switch main";
      mst = "git switch master";
      pull = "git pull";
      push = "git push";
      pushf = "git push --force";
      add = "git add .";
      amend = "git commit --amend";
      reset = "git reset --soft HEAD^";
      rebasem = "git rebase -i main";
      rebasemst = "git rebase -i master";
      rebuild = "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles-mac-nix#mac";
    };
    initContent = ''
      bindkey '^f' autosuggest-accept

      # >>> conda initialize >>>
      # !! Contents within this block are managed by 'conda init' !!
      __conda_setup="$('/Users/yuweiyan/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
      if [ $? -eq 0 ]; then
          eval "$__conda_setup"
      else
          if [ -f "/Users/yuweiyan/miniconda3/etc/profile.d/conda.sh" ]; then
              . "/Users/yuweiyan/miniconda3/etc/profile.d/conda.sh"
          else
              export PATH="/Users/yuweiyan/miniconda3/bin:$PATH"
          fi
      fi
      unset __conda_setup
      # <<< conda initialize <<<

      # Ensure nix-managed tools (e.g. uv, node) take priority over conda's,
      # since conda init above prepends its own bin dir to PATH.
      export PATH="/etc/profiles/per-user/yuweiyan/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"

      # Acquire a Treehouse worktree in lease mode and open it in a new tmux
      # window (or just cd there outside tmux), so a parallel agent session
      # gets its own isolated working directory. Usage: twget [label]
      twget() {
        local repo
        repo=$(basename "$(git rev-parse --show-toplevel)") || return 1
        local label="$1"
        [ -z "$label" ] && label="$repo"
        # Not named "path": zsh ties that name to the $PATH array, and
        # localizing it empties $PATH for the rest of this function.
        local wt_path
        wt_path=$(treehouse get --lease --lease-holder "$label") || return 1
        if [ -n "$TMUX" ]; then
          tmux new-window -c "$wt_path" -n "$label"
        else
          cd "$wt_path"
        fi
      }

      # Return the Treehouse worktree for the current directory and close the
      # tmux window it was opened in. Usage: twreturn [treehouse-return-flags]
      twreturn() {
        local wt_path
        wt_path=$(pwd)
        treehouse return "$wt_path" "$@" || return 1
        if [ -n "$TMUX" ]; then
          tmux kill-window
        fi
      }

      # Start First Mate from its managed checkout. Pass a harness command to
      # override the default, e.g. `firstmate codex`.
      firstmate() {
        local fm_dir="$HOME/github/firstmate"
        if [ ! -d "$fm_dir/.git" ]; then
          echo "First Mate checkout not found at $fm_dir. Run setup/mac.sh first." >&2
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

      # no-mistakes agent switchers with dynamic effort
      use-claude() {
        local effort="''${1:-medium}"
        sed -i ''' 's/^agent: .*/agent: claude/' ~/.no-mistakes/config.yaml
        perl -0777 -pi -e "s/(--effort\n\s+)\w+/\''${1}$effort/" ~/.no-mistakes/config.yaml
        echo "Switched to claude (effort: $effort)"
      }

      use-codex() {
        local effort="''${1:-medium}"
        sed -i ''' 's/^agent: .*/agent: codex/' ~/.no-mistakes/config.yaml
        perl -pi -e "s/(model_reasoning_effort=\")\w+(\")/\''${1}$effort\''${2}/" ~/.no-mistakes/config.yaml
        echo "Switched to codex (effort: $effort)"
      }

      use-opencode() {
        sed -i ''' 's/^agent: .*/agent: opencode/' ~/.no-mistakes/config.yaml
        echo "Switched to opencode"
      }

      show-agent() {
        local agent
        agent=$(awk '/^agent:/ {print $2}' ~/.no-mistakes/config.yaml)
        local effort="N/A"
        if [ "$agent" = "claude" ]; then
          effort=$(awk '/claude:/ {flag=1} flag && /--effort/ {getline; print $2; exit}' ~/.no-mistakes/config.yaml)
        elif [ "$agent" = "codex" ]; then
          effort=$(awk -F'"' '/codex:/ {flag=1} flag && /model_reasoning_effort=/ {print $2; exit}' ~/.no-mistakes/config.yaml)
        fi
        echo "Active Agent: $agent"
        echo "Effort Level: $effort"
      }
    '';
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

      # Split panes in the current path with | and -, keep default % and " too
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # Vim-style pane navigation, repeatable
      bind -r h select-pane -L
      bind -r j select-pane -D
      bind -r k select-pane -U
      bind -r l select-pane -R

      # Status bar
      set -g status-position top
      set -g status-style "bg=default,fg=#908caa"
      set -g status-left "#[fg=#c4a7e7,bold] #S "
      set -g status-right "#[fg=#908caa] %Y-%m-%d %H:%M "
      setw -g window-status-current-format "#[fg=#e0def4,bold] #I:#W "
      setw -g window-status-format "#[fg=#6e6a86] #I:#W "
    '';
  };

  home.file = {
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";

    # Global agent memory file, shared across harnesses. Each one insists on
    # its own path/filename (unlike skills, which several of them already
    # read from a common ~/.agents/skills dir), so we symlink all of them to
    # the same source instead of maintaining five copies.
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";
    ".config/opencode/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";
    ".pi/agent/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";
    # Antigravity CLI (Google) reads AGENTS.md and still supports the legacy
    # GEMINI.md filename it inherited from Gemini CLI.
    ".gemini/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";
    ".gemini/GEMINI.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/AGENTS.md";

    # Referenced conditionally from AGENTS.md above (not loaded by default
    # into every session, only read when the task calls for it).
    "OPINIONS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/OPINIONS.md";
    "VOICE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/VOICE.md";

    # Personal cross-harness skills use the same shared source directory as
    # globally installed skills. Claude also needs its own discovery link.
    ".agents/skills/adaptive-professional-communication".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/adaptive-professional-communication";
    ".claude/skills/adaptive-professional-communication".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/adaptive-professional-communication";
    ".agents/skills/outlook-mail".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/outlook-mail";
    ".claude/skills/outlook-mail".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/outlook-mail";
    ".agents/skills/slack-copilot".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/slack-copilot";
    ".claude/skills/slack-copilot".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/slack-copilot";
    ".agents/skills/wezterm-workspace-manager".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/wezterm-workspace-manager";
    ".claude/skills/wezterm-workspace-manager".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/wezterm-workspace-manager";
    ".agents/skills/latex-tikz-flowcharts".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/latex-tikz-flowcharts";
    ".claude/skills/latex-tikz-flowcharts".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/agents/skills/latex-tikz-flowcharts";

    # OpenCode and Antigravity can consume the shared Outlook MCP server from
    # declarative JSON. Claude Code and Codex keep MCP entries inside mutable
    # user config files, so the activation step below upserts those entries.
    ".config/opencode/opencode.json".text = builtins.toJSON {
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
    ".gemini/config/mcp_config.json".text = builtins.toJSON {
      mcpServers.outlook = {
        command = "outlook-mcp";
        args = [ "server" ];
      };
      mcpServers."slack-copilot" = {
        command = "slack-copilot-mcp";
        args = [ "server" "--env-file" slackCopilotEnvFile ];
      };
    };
    ".gemini/config/skills.json".text = builtins.toJSON {
      entries = [
        { path = "${config.home.homeDirectory}/.agents/skills"; }
      ];
    };
    ".gemini/antigravity-cli/mcp_config.json".text = builtins.toJSON {
      mcpServers.outlook = {
        command = "outlook-mcp";
        args = [ "server" ];
      };
      mcpServers."slack-copilot" = {
        command = "slack-copilot-mcp";
        args = [ "server" "--env-file" slackCopilotEnvFile ];
      };
    };

    # Claude Code's sandbox/permissions/hooks config. Deliberately NOT
    # symlinked to a single cross-harness source like AGENTS.md above: unlike
    # a plain-text memory file, this is consumed by Claude Code's own JSON
    # schema and hook protocol, which Codex (TOML config, coarse
    # sandbox_mode enum, no domain allowlist, non-blocking notify) and
    # OpenCode (JS/TS plugin hooks, no core OS sandbox) and Pi (no built-in
    # permission system at all) don't share. If those harnesses get
    # equivalent policy later, it belongs in files/codex/, files/opencode/,
    # files/pi/ as their own native config, not a symlink to this file.
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/settings.json";
    ".claude/hooks/bash-guard.sh".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/hooks/bash-guard.sh";

    # Claude-only skills: haven't been ported to any other harness yet, so
    # they live under files/claude/ rather than the shared ~/.agents/skills
    # tree. These were previously ad hoc files living only in ~/.claude/skills
    # with no backup - captured here so a fresh machine setup doesn't lose them.
    ".claude/skills/github-multi-account/SKILL.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/skills/github-multi-account/SKILL.md";
    ".claude/skills/setup-bitbucket-mirror/SKILL.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/skills/setup-bitbucket-mirror/SKILL.md";
    ".claude/skills/setup-dev-trunk/SKILL.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/skills/setup-dev-trunk/SKILL.md";
    ".claude/skills/ship-pr/SKILL.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/claude/skills/ship-pr/SKILL.md";
  };

  # Preserve the rest of Claude Code's and Codex's mutable user configuration
  # while declaratively reconciling the named personal MCP entries.
  home.activation.configurePersonalMcps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Home Manager activations do not inherit the interactive shell PATH.
    # Codex's npm launcher uses `#!/usr/bin/env node`, so provide Node explicitly.
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
          "/etc/profiles/per-user/yuweiyan/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
        ];
        USER = config.home.username;
      };
      WorkingDirectory = config.home.homeDirectory;
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
      };
      ProcessType = "Background";
      ThrottleInterval = 30;
      StandardOutPath = "${slackAgentConfigDir}/logs/stdout.log";
      StandardErrorPath = "${slackAgentConfigDir}/logs/stderr.log";
    };
  };
}
