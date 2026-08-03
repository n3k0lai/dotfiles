# users/nicho.nix
# Account config for user `nicho` on every host that has this account.
# Imported by configuration.nix (kiss) and configuration-server.nix (ene, rook, …).
# CLI tools (grok, nvim, session PATH) live here so they are never host-specific.
{ config, lib, pkgs, ... }: {
  imports = [
    ../modules/editors/grokbuild.nix
    ../modules/editors/vim.nix
  ];

  modules.editors.grokbuild.enable = true;
  modules.editors.vim.enable = true;

  home-manager.users.nicho = { pkgs, ... }: {
    # User environment variables
    home.sessionVariables = {
      # Default programs — nvim for TUI chores; GUI Emacs via `e`
      EDITOR = "nvim";
      VISUAL = "nvim";
      TERMINAL = "kitty";
      BROWSER = "firefox";
      BROWSER_MIN = "luakit";

      # XDG directories
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_DATA_HOME = "$HOME/.local/share";

      # Development paths
      GOPATH = "$HOME/.local/share/go";

      # Emacs/Doom
      DOOMDIR = "$HOME/.config/doom";
      EMACSDIR = "$HOME/.config/emacs";

      # Application fixes
      MOZ_USE_XINPUT2 = "1";  # Mozilla smooth scrolling/touchpads
      OBS_USE_EGL = "1";      # OBS game capture on X11

      # Display (if not set by display manager)
      DISPLAY = ":0";
    };

    # Additional PATH entries.
    # grok itself is bin/fish/functions/grok.fish (update-then-run); ~/.grok/bin
    # stays on PATH for the real binary, agent, and non-fish callers.
    home.sessionPath = [
      "$HOME/.grok/bin"
      "$HOME/.local/bin"
      "$HOME/.local/share/go/bin"
      "$HOME/.config/emacs/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.dotnet/tools"
    ];

    # Fish-specific interactive shell init
    programs.fish = {
      interactiveShellInit = ''
        # Call set_profile for fish-specific customizations
        if functions -q set_profile
            set_profile
        end
      '';
    };

    home.packages = with pkgs; [
      zip
      unzip
      p7zip
      gnutar
      gzip
      xz
    ];

    # Hosts may pin an older value (e.g. rook 24.11) — do not force overwrite.
    home.stateVersion = lib.mkDefault "25.05";
  };
}