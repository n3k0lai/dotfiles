{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.hyprland;
  devMode = config.modules.core.devMode;
in {
  options.modules.desktop.hyprland = {
    enable = mkEnableOption "Hyprland window manager";
  };

  config = mkIf cfg.enable {
    # Hyprland program
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = false;  # Disable UWSM systemd session wrapper (greetd launches Hyprland directly)
    };

    # Environment variables for Wayland/Hyprland
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      LIBVA_DRIVER_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      XMODIFIERS = "@im=fcitx";  # For XWayland apps
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "ibus";  # Fallback for some games
    };
    
    # Hyprland ecosystem packages
    environment.systemPackages = with pkgs; [
      # Hyprland components
      hyprpaper
      hypridle
      hyprlock
      hyprpicker
      hyprcursor
      hyprlauncher
      # hyprtoolkit  # Not in nixpkgs 24.11
      
      # Animated wallpapers
      mpvpaper
      
      # Widget system
      eww
      
      # Notifications
      dunst
      
      # Utilities
      jq  # For wallpaper script
      socat  # For eww workspace script (hyprland socket)
      sqlite  # For eww claude-usage script (reads Firefox cookies)
      curl-impersonate  # For eww claude-usage script (bypasses Cloudflare TLS fingerprinting)
      grim  # Screenshot
      slurp  # Screen selection
      wl-clipboard  # Clipboard
      cliphist  # Clipboard manager
      wtype  # Key simulation for fcitx5 emoji picker
      swaylock
      
      # File manager
      kdePackages.dolphin
    ];
    
    # Home-manager config for per-user settings
    home-manager.users.nicho = { config, ... }:
    let
      # Helper for directory configs: in dev mode, link directly to repo; otherwise use store with recursive
      mkDirConfig = relativePath: storeSource:
        if devMode.enable
        then { source = config.lib.file.mkOutOfStoreSymlink "${devMode.repoPath}/${relativePath}"; }
        else { source = storeSource; recursive = true; };

      # Helper for file configs
      mkFileSource = relativePath: storeSource:
        if devMode.enable
        then config.lib.file.mkOutOfStoreSymlink "${devMode.repoPath}/${relativePath}"
        else storeSource;
    in {
      # Symlink hyprland configs (out-of-store in dev mode for hot-reload)
      xdg.configFile."hypr" = mkDirConfig "modules/desktop/config/hypr" ./config/hypr;

      # Symlink eww configs
      xdg.configFile."eww" = mkDirConfig "modules/desktop/config/eww" ./config/eww;

      # Symlink dunst config (without enabling service, systemd handles it in bspwm)
      xdg.configFile."dunst/dunstrc".source =
        mkFileSource "modules/desktop/config/dunst/dunstrc" ./config/dunst/dunstrc;
    };

    # XDG portals for Hyprland
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
      config.common.default = "*";
    };

    # Fonts
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        martian-mono
        (nerdfonts.override { fonts = [ "Hermit" "NerdFontsSymbolsOnly" ]; })
        font-awesome
      ];
    };

    # XDG MIME configuration
    xdg.mime.enable = true;
    xdg.mime.defaultApplications = {
      "text/html" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
    };
  };
}
