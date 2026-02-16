{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.bspwm;
  devMode = config.modules.core.devMode;
in {
  options.modules.desktop.bspwm = {
    enable = mkEnableOption "bspwm window manager";
  };

  config = mkIf cfg.enable {
    # Enable X11 and bspwm
    services.xserver = {
      enable = true;
      windowManager.bspwm = {
        enable = true;
      };
    };

    # Required packages for bspwm environment
    environment.systemPackages = with pkgs; [
      # Window manager essentials
      bspwm
      sxhkd
      
      # System utilities
      polkit_gnome
      arandr
      xorg.xsetroot
      
      # Application launcher and menus
      rofi
      
      # Status bar
      polybar
    
    # Notifications
    dunst
    
    # Wallpaper
    nitrogen
    
    # Desktop utilities
    dex
    networkmanagerapplet
    
    # Screenshot
    scrot
    
    # Audio control
    alsa-utils
    pulseaudio
    
    # Brightness control
    xorg.xbacklight
    
    # File manager
    kdePackages.dolphin
    
    # Terminal
    kitty
    
    # Browser
    firefox
  ];

  # Polkit authentication agent
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

  # Dunst notification daemon
  systemd.user.services.dunst = {
    description = "Dunst notification daemon";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.dunst}/bin/dunst";
    };
  };

  # NetworkManager applet
  systemd.user.services.nm-applet = {
    description = "Network Manager Applet";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
    };
  };

  # Enable dbus for various desktop services
  services.dbus.enable = true;

  # Enable network manager
  networking.networkmanager.enable = true;

  # Input method configuration
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons
      fcitx5-mozc
      fcitx5-gtk
      kdePackages.fcitx5-qt
      fcitx5-rime
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
  
  # Home-manager config for per-user settings
  home-manager.users.nicho = { config, ... }:
  let
    # Helper for directory configs: in dev mode, link directly to repo; otherwise use store with recursive
    mkDirConfig = relativePath: storeSource:
      if devMode.enable
      then { source = config.lib.file.mkOutOfStoreSymlink "${devMode.repoPath}/${relativePath}"; }
      else { source = storeSource; recursive = true; };
  in {
    # Symlink bspwm configs (out-of-store in dev mode for hot-reload)
    xdg.configFile."bspwm" = mkDirConfig "modules/desktop/config/bspwm" ./config/bspwm;

    # Symlink sxhkd config
    xdg.configFile."sxhkd" = mkDirConfig "modules/desktop/config/sxhkd" ./config/sxhkd;

    # Symlink polybar config
    xdg.configFile."polybar" = mkDirConfig "modules/desktop/config/polybar" ./config/polybar;
  };
  };
}
