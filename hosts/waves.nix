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
#   2. Clone dotfiles: git clone https://github.com/n3k0lai/dotfiles ~/Developer/dotfiles
#   3. First build: darwin-rebuild switch --flake ~/Developer/dotfiles#waves
#   4. Tailscale: brew install tailscale && tailscale up
{ pkgs, lib, inputs, hostname, username, ... }:

{
  # ── System ─────────────────────────────────────────────
  networking.hostName = "waves";
  system.stateVersion = 6;  # nix-darwin state version
  system.primaryUser = "nicho";

  # ── Nix settings ───────────────────────────────────────
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "nicho" ];
  };
  nixpkgs.config.allowUnfree = true;

  # ── Users ──────────────────────────────────────────────
  users.users.nicho = {
    home = "/Users/nicho";
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
  # NOTE: Disabled due to nix-darwin 25.05 incompatibility with Homebrew's
  # Ruby 4.0 requirement. Install casks manually with `brew install --cask`.
  # Casks to install: firefox, zen-browser, visual-studio-code, unity-hub,
  # blender, iterm2, discord, slack, obsidian, raycast, vlc, spotify,
  # tailscale, rectangle, stats, the-unarchiver, 1password
  #
  # homebrew = {
  #   enable = true;
  #   onActivation = {
  #     autoUpdate = true;
  #     cleanup = "zap";
  #   };
  #   casks = [ ... ];
  # };

  # ── CLI packages (from Nix) ────────────────────────────
  environment.systemPackages = with pkgs; [
    # Core
    git
    git-lfs
    fish
    tmux
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
    agenix                         # secrets decryption CLI
    age                            # encryption tool

    # Network
    curl
    wget
    openssh
  ];

  # ── home-manager ───────────────────────────────────────
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "hm-bak";
  home-manager.users.nicho = { pkgs, ... }: {
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
        rebuild = "darwin-rebuild switch --flake ~/Developer/dotfiles#waves";
      };
      interactiveShellInit = ''
        if functions -q set_profile
            set_profile
        end
      '';
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    programs.fzf.enable = true;

    # Symlink fish functions, completions, themes, and conf.d from the repo
    xdg.configFile."fish/functions" = {
      source = ../bin/fish/functions;
      recursive = true;
    };
    xdg.configFile."fish/conf.d" = {
      source = ../bin/fish/conf.d;
      recursive = true;
    };
    xdg.configFile."fish/completions" = {
      source = ../bin/fish/completions;
      recursive = true;
    };
    xdg.configFile."fish/themes" = {
      source = ../bin/fish/themes;
      recursive = true;
    };

    # SSH config is kept as-is from existing ~/.ssh/config
    # (managed manually to avoid leaking Tailscale IPs in the repo)
  };
}
