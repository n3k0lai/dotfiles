# Waves — Nicholai's M4 MacBook Air 13" coffeeshop laptop.
# Named after the core branding asset. Portable, light, social.
#
# Hardware: Apple M4, 16GB unified, 256GB SSD
# OS: macOS with nix-darwin overlay
# Tailscale: "waves" (mesh member, not an agent)
# Purpose: Coffeeshop coding, Unity/Blender (pookie), travel, presentations
#
# Architecture:
#   - nix-darwin for system config (replaces System Preferences tweaks)
#   - home-manager for dotfiles (fish, git, ssh, etc.)
#   - nix-homebrew for GUI apps (casks: browsers, editors, Discord, etc.)
#   - CLI tools from nixpkgs directly
#
# Bootstrap:
#   1. Install Determinate Nix: curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh
#   2. Clone dotfiles: git clone https://github.com/n3k0lai/dotfiles ~/Code/nix
#   3. First build: darwin-rebuild switch --flake ~/Code/nix#waves
#   4. Tailscale: brew install tailscale && tailscale up
{ pkgs, lib, inputs, hostname, username, ... }:

{
  # ── System ─────────────────────────────────────────────
  networking.hostName = "waves";
  system.stateVersion = 6;  # nix-darwin state version

  # ── Nix settings ───────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "nicholai" ];
  };
  nixpkgs.config.allowUnfree = true;

  # ── Users ──────────────────────────────────────────────
  users.users.nicholai = {
    home = "/Users/nicholai";
    shell = pkgs.fish;
  };
  programs.fish.enable = true;

  # ── macOS system preferences ───────────────────────────
  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;          # don't rearrange spaces by recent use
      show-recents = false;
      tilesize = 48;
    };
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "clmv";  # column view
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyle = "Dark";
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.swipescrolldirection" = false;  # natural scrolling off
    };
    trackpad = {
      Clicking = true;              # tap to click
      TrackpadRightClick = true;
    };
    CustomUserPreferences = {
      "com.apple.screencapture" = {
        location = "~/Screenshots";
        type = "png";
      };
    };
  };

  # ── Security ───────────────────────────────────────────
  security.pam.services.sudo_local.touchIdAuth = true;

  # ── Homebrew (GUI apps via casks) ──────────────────────
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";             # remove anything not declared here
    };
    casks = [
      # Browsers
      "firefox"
      "zen-browser"

      # Dev
      "visual-studio-code"
      "unity-hub"
      "blender"
      "iterm2"

      # Chat & Social
      "discord"
      "slack"

      # Productivity
      "obsidian"
      "raycast"

      # Media
      "vlc"
      "spotify"

      # Utilities
      "tailscale"
      "rectangle"                  # window management
      "stats"                      # menubar system monitor
      "the-unarchiver"
      "1password"                  # or whatever password manager
    ];
    brews = [
      # CLI tools that are better from brew on macOS
      "mas"                        # Mac App Store CLI
    ];
    masApps = {
      # Mac App Store apps (need to be signed in)
      # "Xcode" = 497799835;       # uncomment if needed for Unity iOS builds
    };
  };

  # ── CLI packages (from Nix) ────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core
    git
    git-lfs
    fish
    tmux
    starship
    direnv

    # Dev tools
    ripgrep
    fd
    jq
    bat
    eza
    fzf
    delta                          # git diff pager
    gh                             # GitHub CLI
    tree

    # Languages / build
    rustup
    nodejs
    python3

    # Nix tools
    nixfmt-rfc-style
    nil                            # nix LSP

    # Network
    curl
    wget
    openssh
  ];

  # ── home-manager ───────────────────────────────────────
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.nicholai = { pkgs, ... }: {
    home.stateVersion = "24.11";

    programs.git = {
      enable = true;
      userName = "Nicholai";
      userEmail = "n3k0lai@proton.me";
      delta.enable = true;
      extraConfig = {
        push.autoSetupRemote = true;
        init.defaultBranch = "main";
        credential."https://github.com" = {
          helper = "!${pkgs.gh}/bin/gh auth git-credential";
        };
      };
    };

    programs.fish = {
      enable = true;
      shellAliases = {
        ls = "eza --icons";
        ll = "eza -la --icons";
        cat = "bat";
        rebuild = "darwin-rebuild switch --flake ~/Code/nix#waves";
      };
    };

    programs.starship.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    programs.fzf.enable = true;

    programs.ssh = {
      enable = true;
      matchBlocks = {
        "ene" = {
          hostname = "100.111.1.42";
          user = "nicho";
        };
        "chat" = {
          hostname = "100.114.138.5";
          user = "nicho";
        };
        "kiss" = {
          hostname = "100.76.133.110";
          user = "nicho";
        };
        "artemis" = {
          hostname = "100.75.158.50";
          user = "nicho";
        };
      };
    };
  };
}
