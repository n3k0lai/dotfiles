{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.hyprland;
  devMode = config.modules.core.devMode;
in {
  options.modules.desktop.hyprland = {
    enable = mkEnableOption "Hyprland window manager";

    # kiss is NVIDIA-primary. blade is Intel-primary (MX150 offload only) —
    # importing this module there must not export GBM/GLX/VAAPI=nvidia.
    nvidia = mkOption {
      type = types.bool;
      default = true;
      description = "Set NVIDIA GBM/GLX/VAAPI session variables. Disable on Intel-primary hosts.";
    };

    # Sourced as ~/.config/hypr-host/monitors.conf (outside the hypr/ dir
    # symlink). kiss = desk grid; blade = eDP at 0x0.
    monitorsLayout = mkOption {
      type = types.enum [ "kiss" "blade" ];
      default = "kiss";
      description = "Which monitors-*.conf to source from hyprland.conf.";
    };
  };

  config = mkIf cfg.enable {
    # Hyprland program
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = false;  # Disable UWSM systemd session wrapper (greetd launches Hyprland directly)
    };

    # Required for hyprlock password authentication to work via PAM.
    security.pam.services.hyprlock.enable = true;

    # Environment variables for Wayland/Hyprland
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      XMODIFIERS = "@im=fcitx";  # For XWayland apps
      SDL_IM_MODULE = "fcitx";
      GLFW_IM_MODULE = "ibus";  # Fallback for some games
    } // optionalAttrs cfg.nvidia {
      LIBVA_DRIVER_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      WLR_NO_HARDWARE_CURSORS = "1";
      NVD_BACKEND = "direct";

      # Firefox + NVIDIA + Wayland stability
      # MOZ_DISABLE_RDD_SANDBOX=1 avoids RDD sandbox + VA-API presentation hangs
      # that manifest as frozen fullscreen YouTube/video windows (common on this stack).
      MOZ_DISABLE_RDD_SANDBOX = "1";
    };
    
    # Polkit authentication agent (needed for pkexec, e.g. SteamVR setcap)
    security.polkit.enable = true;
    systemd.user.services.polkit-gnome = {
      description = "Polkit GNOME Authentication Agent";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    # Hyprland ecosystem packages
    environment.systemPackages = with pkgs; [
      # Hyprland components
      hyprpaper
      hypridle
      hyprlock
      hyprpicker
      hyprcursor
      polkit_gnome
      
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
      brightnessctl
      
      # Launcher
      wofi

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

      # Host monitor grid — not inside hypr/ because that directory is a
      # single out-of-store symlink in dev mode.
      xdg.configFile."hypr-host/monitors.conf".source =
        mkFileSource
          "modules/desktop/config/hypr/monitors-${cfg.monitorsLayout}.conf"
          (./config/hypr + "/monitors-${cfg.monitorsLayout}.conf");

      xdg.configFile."hypr-host/extras.conf".source =
        mkFileSource
          "modules/desktop/config/hypr/extras-${cfg.monitorsLayout}.conf"
          (./config/hypr + "/extras-${cfg.monitorsLayout}.conf");

      # Symlink eww configs
      xdg.configFile."eww" = mkDirConfig "modules/desktop/config/eww" ./config/eww;

      # Symlink dunst config (without enabling service, systemd handles it in bspwm)
      xdg.configFile."dunst/dunstrc".source =
        mkFileSource "modules/desktop/config/dunst/dunstrc" ./config/dunst/dunstrc;

      # wofi default paths — Hyprland exec does not expand ~ in -s ~/.config/...
      xdg.configFile."wofi/style.css".source =
        mkFileSource "modules/desktop/config/hypr/wofi.css" ./config/hypr/wofi.css;
      xdg.configFile."wofi/config".source =
        mkFileSource "modules/desktop/config/hypr/wofi.conf" ./config/hypr/wofi.conf;
    };

    # XDG portals for Hyprland
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
      config.common.default = "*";
    };

    # Fonts
    # Martian Mono covers Latin only — CJK (fortune-zh, fcitx5, host icon 吻吻)
    # and Nerd symbols need explicit packages + fontconfig fallbacks, otherwise
    # terminals/UI show tofu boxes for missing glyphs.
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        martian-mono
        nerd-fonts.hurmit
        nerd-fonts.symbols-only
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        # 25.05: noto-fonts-emoji. unstable 26.11: renamed to color-emoji.
        (pkgs.noto-fonts-color-emoji or pkgs.noto-fonts-emoji)
      ];
      fontconfig = {
        defaultFonts = {
          serif = [ "Noto Serif" "Noto Sans CJK SC" ];
          sansSerif = [ "Noto Sans" "Noto Sans CJK SC" ];
          monospace = [
            "Martian Mono"
            "Symbols Nerd Font Mono"
            "Noto Sans Mono CJK SC"
          ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
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
