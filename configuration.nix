{ pkgs, user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
    shell = pkgs.zsh;
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
      "com.apple.swipescrolldirection" = true;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
    };
    dock.autohide = true;
    finder = {
      FXPreferredViewStyle = "Nlsv";  # list view by default
      CreateDesktop = false;          # clean desktop
      AppleShowAllExtensions = true;
      ShowPathbar = true;
    };
    trackpad.Clicking = false;
  };
  nix-homebrew = {
    enable = true;
    inherit user;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    brews = [
      "apache-arrow"
      "autoconf"
      "awscli"
      "btop"
      "c-blosc"
      "cmake"
      "gh"
      "git"
      "git-lfs"
      "glow"
      "gsl"
      "hdf5"
      "htop"
      "libomp"
      "libpq"
      "lua-language-server"
      "marksman"
      "mdcat"
      "mole"
      "mysql"
      "neovim"
      "opencode"
      "pandoc"
      "pokerstove"
      "postgresql@17"
      "python@3.11"
      "rclone"
      "redis"
      "ta-lib"
      "tectonic"
      "telnet"
      "tmux"
      "typst"
      "uv"
      "herdr"
    ];
    casks = [
      "amethyst"
      "antigravity-cli"
      "claude-code"
      "font-hack-nerd-font"
      "ngrok"
      "opensuperwhisper"
      "orbstack"
      "session-manager-plugin"
      "stats"
      "temurin@11"
      "visual-studio-code"
      "wezterm"
    ];
  };

  environment.systemPath = [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${user}/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];
}
