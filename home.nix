{ config, lib, pkgs, treehouse, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
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
}
