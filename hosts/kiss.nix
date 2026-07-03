# My main pc. The motherload. The queen.
# where I live and where I build.
{ config, lib, pkgs, ... }:

with lib;

let
  # Mullvad's Electron GUI blanks on native Wayland when switching Hyprland
  # workspaces on NVIDIA (renderer buffer lost). Force XWayland instead.
  mullvad-vpn = pkgs.mullvad-vpn.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      wrapProgram $out/bin/mullvad-vpn \
        --set NIXOS_OZONE_WL 0 \
        --add-flags "--ozone-platform=x11"
    '';
  });
in {
  imports = [
    ../modules/hardware/scarlett.nix
    ../modules/hardware/unicorne.nix
    ../modules/hardware/svalbard.nix
    ../modules/hardware/sammy.nix
    ../modules/servers/garmin.nix
    ../modules/desktop/fcitx5.nix
    ../modules/editors/cad.nix
    ../modules/editors/opencode.nix
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
    modules.editors.opencode.enable = true;

    # Agenix CLI for managing encrypted secrets
    environment.systemPackages = with pkgs; [
      agenix
      zed-editor
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
      vesktop
      obs-studio
      obsidian
      protonmail-desktop
      prismlauncher # minecraft
    ];

    # Enable Scarlett audio interface
    hardware.scarlett.enable = true;
    
    # Enable Unicorne keyboard
    hardware.unicorne.enable = true;

    # Enable Svalbard RAID array auto-mounting
    hardware.svalbard.enable = true;

    # Enable Samsung USB-C drive auto-mounting
    hardware.sammy.enable = true;

    # Input method (fcitx5 with Pinyin)
    modules.desktop.fcitx5.enable = true;

    # Artemis hardware design & prototyping tools
    modules.editors.cad.kicad.enable = true;
    modules.editors.cad.openscad.enable = true;
    modules.editors.cad.freecad.enable = true;
    modules.editors.cad.diylc.enable = true;
    modules.editors.cad.hardware.enable = true;

    # Battle.net / WoW — Steam+Proton launcher, WowUp for Classic/Retail addons
    modules.gaming.battlenet.enable = true;

    # League of Legends — Moonlight client (Vanguard blocks native Linux; needs Windows Sunshine host)
    modules.gaming.riot.enable = true;

    # Mullvad VPN (GUI) — resolved required for DNS resolution
    services.resolved.enable = true;
    services.mullvad-vpn.enable = true;
    services.mullvad-vpn.package = mullvad-vpn;

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
      extraPackages = with pkgs; [ mesa vulkan-loader ];
      extraPackages32 = with pkgs; [ pkgsi686Linux.mesa ];
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
    };
  };
}
