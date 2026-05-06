# Razer Blade 13" Stealth (RZ09-0281)
# NVIDIA MX150 mobile + Intel UHD 620 (Optimus)
# eGPU capable (Thunderbolt 3)
# Primary portable workstation + car diagnostic VM host
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    # Desktop input method (Chinese study)
    ../modules/desktop/fcitx5.nix
    ../modules/editors/opencode.nix
  ];

  config = {
    modules.editors.opencode.enable = true;

    ##################################################################################
    #                        Machine Identity
    networking.hostName = "dao";

    ##################################################################################
    #                        Bootloader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    ##################################################################################
    #                        Swap
    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;

    ##################################################################################
    #                        Graphics — Optimus (Intel + NVIDIA MX150)
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [ mesa vulkan-loader ];
    };

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.latest;

      # Prime offloading for Optimus laptop
      # Run apps on dGPU: __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        # Bus IDs — verify with `lspci | grep -E "VGA|3D"`
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };

    ##################################################################################
    #                        Virtualisation — Forscan VM
    virtualisation.libvirtd.enable = true;

    ##################################################################################
    #                        User Account
    users.users.nicho = {
      isNormalUser = true;
      description = "Nicholai";
      extraGroups = [
        "networkmanager"
        "wheel"
        "audio"
        "video"
        "render"
        "input"
        "dialout"
        "kvm"
        "libvirtd"
      ];
      shell = pkgs.fish;
      packages = with pkgs; [
        # UI
        hyprland
        wofi
        eww
        foot

        # streaming
        chatterino2
        obs-studio
        discord

        # work
        zoom-us
        freerdp3
        slack
        code-cursor

        # car diagnostic
        tio          # serial terminal (Miia, OBDLink, Flipper)
        can-utils    # CAN bus tools (socketcan, candump, etc.)
        usbutils     # lsusb
        lshw         # hardware enumeration
      ];
    };

    ##################################################################################
    #                        System Packages
    environment.systemPackages = with pkgs; [
      # Deps
      git
      ripgrep
      coreutils
      fd
      clang

      # VM / Car diagnostic host
      qemu
      qemu_kvm
      virt-manager
      spice-gtk

      # Services
      tailscale

      # CLI
      fish
      ranger
      bat
    ];

    ##################################################################################
    #                        Services
    services.tailscale.enable = true;

    # Enable pipewire audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    ##################################################################################
    #                        Environment
    environment.sessionVariables = {
      _JAVA_AWT_WM_NONREPARENTING = "1";
      XCURSOR_SIZE = "24";
    };
  };
}
