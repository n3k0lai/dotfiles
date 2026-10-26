# My main pc. The motherload. The queen.
# where I live and where I build.
{ config, lib, pkgs, hermes-agent, ... }:

with lib;

{
  imports = [
    ../modules/hardware/scarlett.nix
    ../modules/hardware/unicorne.nix
    ../modules/hardware/clicks.nix
    ../modules/hardware/scuf.nix
    ../modules/hardware/svalbard.nix
    ../modules/hardware/sammy.nix
    ../modules/hardware/ems64m.nix
    ../modules/hardware/chromatic.nix
    ../modules/desktop/fcitx5.nix
    ../modules/editors/cad.nix
    ../modules/editors/cursor.nix
    ../modules/editors/grok-bot.nix
    ../modules/editors/opencode.nix
    ../modules/editors/opencut.nix
    # Substitute from rook's Attic cache (tailnet; falls back if unreachable)
    ../modules/core/nix-cache.nix
  ];

  options.hardware.kiss.gpu = {
    vendor = mkOption {
      type = types.str;
      default = "nvidia";
      description = "GPU vendor";
    };
    
    cudaSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Whether CUDA support is enabled";
    };
    
    driverPackage = mkOption {
      type = types.package;
      default = config.boot.kernelPackages.nvidiaPackages.latest;
      description = "NVIDIA driver package";
    };
  };

  config = {
    hardware.scuf.enable = true;
    # rook cache as substituter. remoteBuilder.enable offloads kiss's builds to
    # rook too; needs a root key, see docs/rook-build-server.md.
    modules.core.nixCache.enable = true;

    modules.editors.cursor.enable = true;
    modules.editors.grok-bot.enable = true;
    modules.editors.opencode.enable = true;
    modules.editors.opencut.enable = true;
    # cargo run from ~/Code/OpenCut when present; else the Nix binary.
    modules.editors.opencut.dev.enable = true;
    modules.editors.opencut.dev.repoPath = "/home/nicho/Code/OpenCut";

    # Agenix CLI for managing encrypted secrets
    environment.systemPackages = with pkgs; [
      agenix
      zed-editor
      bubblewrap # grok --sandbox (interns layer)
      # Qt6 dependencies for PrismLauncher
      qt6.qtwayland
      qt6.qtbase
      qt6.qt5compat
      qt6.qtimageformats
      qt6.qtsvg
      libGL
      mesa
      libxkbcommon
    ];

    # Desktop UI applications
    home-manager.users.nicho.home.packages = with pkgs; [
      firefox
      brave        # for usevia.app
      discord # official client: Vesktop arRPC accepts presence locally and does not publish it
      obs-studio
      obsidian
      protonmail-desktop
      prismlauncher # minecraft
    ];

    # Hermes Desktop (Electron) for nicho — ~/.hermes, not the ene/rook
    # systemd gateway. CLI + wofi launcher; first run can attach to a
    # remote gateway or install a local backend.
    home-manager.users.nicho.imports = [
      hermes-agent.homeManagerModules.default
    ];
    home-manager.users.nicho.programs.hermes-agent = {
      enable = true;
      desktop.enable = true;
    };

    # Enable Scarlett audio interface
    hardware.scarlett.enable = true;
    
    # Enable Unicorne keyboard
    hardware.unicorne.enable = true;

    # Clicks Power Keyboard over BLE (Intel AX200). Channel 2 suggested.
    hardware.clicks.enable = true;

    # Enable Svalbard RAID array auto-mounting
    hardware.svalbard.enable = true;

    # Enable Samsung USB-C drive auto-mounting
    hardware.sammy.enable = true;

    # EMS GB USB 64M flash cart (ems-flasher + uaccess udev rule)
    hardware.ems64m.enable = true;

    # ModRetro Chromatic (MR Updater + uaccess udev rules)
    hardware.chromatic.enable = true;

    # Input method (fcitx5 with Pinyin)
    modules.desktop.fcitx5.enable = true;

    # Artemis hardware design & prototyping tools
    modules.editors.cad.kicad.enable = true;
    modules.editors.cad.openscad.enable = true;
    modules.editors.cad.freecad.enable = true;
    modules.editors.cad.diylc.enable = true;
    modules.editors.cad.hardware.enable = true;

    # Battle.net prefix — bnet / bnet-wc3 / bnet-wow / bnet-w3c (umu+Proton)
    modules.gaming.bnet.enable = true;
    # Discord: Forever character/level/place, and Minecraft world/dimension.
    modules.gaming.presence.enable = true;

    # League of Legends — Moonlight client (Vanguard blocks native Linux; needs Windows Sunshine host)
    modules.gaming.riot.enable = true;

    # EVE Online — first-class (dedicated launcher; Steam App 8500 backup)
    modules.gaming.eve-online.enable = true;

    # Stub resolver so Tailscale split DNS (*.ts.net) stays in front of the LAN DNS.
    services.resolved.enable = true;

    # Firefox network geolocation via BeaconDB (looked up at runtime; the
    # stock Google endpoint has no API key in this build). Firefox reads
    # /etc/firefox/policies, so this also covers the home-manager firefox.
    programs.firefox = {
      enable = true;
      preferences."geo.provider.network.url" = "https://api.beacondb.net/v1/geolocate";
      preferencesStatus = "default";
    };

    # IPv6 disabled on the wired NIC until router IPv6 is fixed (temporary).
    # A declared profile, because NetworkManager re-enables IPv6 over a sysctl.
    # Tailscale IPv6 is unaffected.
    networking.networkmanager.ensureProfiles.profiles.wired-noipv6 = {
      connection = {
        id = "wired-noipv6";
        type = "ethernet";
        interface-name = "enp7s0";
        autoconnect-priority = 10;
      };
      ipv4.method = "auto";
      ipv6.method = "disabled";
    };

    # Machine-specific hostname
    networking.hostName = "kiss";

    # Hardware-specific environment variables
    environment.sessionVariables = {
      # NVIDIA shader cache — prevent driver from pruning fossilize_replay caches
      __GL_SHADER_DISK_CACHE = "1";
      __GL_SHADER_DISK_CACHE_SIZE = "10737418240";  # 10 GB

      # Window manager fixes for this hardware
      _JAVA_AWT_WM_NONREPARENTING = "1";  # Android Studio X11 UI fix
      XCURSOR_SIZE = "24";
      SXHKD_SHELL = "sh";
    };

    ##################################################################################
    #                        Bootloader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ##################################################################################
    #                        Swap
    boot.kernelParams = [
      "resume=/dev/disk/by-label/swap"
      "resume_offset=<offset>"
      "nvidia-drm.modeset=1"
      "nvidia-drm.fbdev=1"
      # Note: fbcon=rotate affects ALL monitors globally, can't do per-monitor
      # rotation at kernel level. SDDM/Hyprland handle per-monitor rotation.
    ];
    powerManagement.enable = true;
    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;
    
    ##################################################################################
    #                        Graphics - NVIDIA RTX 3070
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [ mesa vulkan-loader ];
      extraPackages32 = with pkgs; [
        pkgsi686Linux.mesa
        pkgsi686Linux.vulkan-loader
      ];
    };
    
    services.xserver.videoDrivers = [ "nvidia" ];

    # Gaming monitor (DP-3) is always primary (used by bspwm/X11 sessions)
    services.xserver.xrandrHeads = [
      { output = "DP-3"; primary = true; }
      { output = "DP-2"; }
    ];
    
    hardware.nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;
      # Keep the GPU initialized so NVENC/SteamVR do not hitch after DPMS or
      # when the Frame is the only "display". Runtime PM is a stutter source.
      nvidiaPersistenced = true;
      powerManagement.enable = false;
    };

  };
}
