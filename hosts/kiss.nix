# My main pc. The motherload. The queen.
# where I live and where I build.
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ../modules/hardware/scarlett.nix
    ../modules/hardware/unicorne.nix
    ../modules/hardware/svalbard.nix
    ../modules/hardware/sammy.nix
    ../modules/servers/garmin.nix
    ../modules/desktop/fcitx5.nix
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
      default = config.boot.kernelPackages.nvidiaPackages.production;
      description = "NVIDIA driver package";
    };
  };

  config = {
    # Agenix CLI for managing encrypted secrets
    # Moonlight for streaming from Rook (League, etc)
    environment.systemPackages = [ pkgs.agenix pkgs.moonlight-qt ];

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

    # Machine-specific hostname
    networking.hostName = "kiss";

    # Hardware-specific environment variables
    environment.sessionVariables = {
      # Wine configuration for gaming on this machine
      WINEDEBUG = "fps";
      FREETYPE_PROPERTIES = "truetype:interpreter-version=35";
      WINEARCH = "win64";
      WINEPREFIX = "$HOME/.wine-battlenet";
      WINE_SIMULATE_WRITECOPY = "1";
      
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
      package = config.boot.kernelPackages.nvidiaPackages.production;
    };
  };
}
