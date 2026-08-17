# Razer Blade Stealth 13" (2019) — model RZ09-0281x
# Make/model (from vault hardware/laptop, 2026-08-03):
#   Razer Blade Stealth 13" 2019
# Support / FAQs:
#   https://mysupport.razer.com/app/answers/detail/a_id/3701/~/razer-blade-stealth-13”-%282019%29-%7C-rz09-0281x-support-%26-faqs
# NVIDIA MX150 mobile + Intel UHD 620 (Optimus)
# eGPU capable (Thunderbolt 3)
# Primary portable workstation + car diagnostic VM host
#
# Boot:
#   sudo nixos-rebuild boot --flake ~/dotfiles#blade   # write entry, stay on current gen
#   sudo nixos-rebuild switch --flake ~/dotfiles#blade # activate now
#
# Gen 11 (26.05 / kernel 6.18) stalled after initrd waiting for
# /dev/disk/by-label/{nixos,boot}. Disks are UUID-only — see blade-hardware.nix.
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    # fcitx5 needs home-manager — add when you wire HM into the blade flake
    # ../modules/desktop/fcitx5.nix
    # opencode: unstable nixpkgs smoke test segfaults on blade (exit 139); enable when fixed
    # ../modules/editors/opencode.nix
  ];

  config = {
    nixpkgs.config.allowUnfree = true;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    # Fresh installs often ship Nix 2.18.5; 6.12 kernel initrd needs >= 2.18.9
    nix.package = pkgs.nixVersions.latest;
    # Original install was 24.05 — do not bump this with the flake channel
    system.stateVersion = "24.05";

    ##################################################################################
    #                        Machine Identity
    networking.hostName = "blade";
    networking.networkmanager.enable = true;
    time.timeZone = "America/New_York";
    i18n.defaultLocale = "en_US.UTF-8";

    programs.fish.enable = true;
    security.sudo.wheelNeedsPassword = false;
    services.openssh.enable = true;

    ##################################################################################
    #                        Bootloader
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.timeout = 8;
    boot.loader.systemd-boot.configurationLimit = 12;
    # Match the known-good dao 24.05 kernel on this 2019 chassis (MX150 + UHD 620).
    # Unstable's default 6.18 was what gen 11 shipped.
    boot.kernelPackages = pkgs.linuxPackages_6_6;

    ##################################################################################
    #                        Swap
    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;

    ##################################################################################
    #                        Graphics — Intel display + MX150 compute
    #
    # Internal eDP is wired to UHD 620. That iGPU is the compositor, VAAPI,
    # and daily desktop. MX150 (Pascal, 2 GB) stays a secondary device:
    #   nvidia-offload <app>     GL/Vulkan on the dGPU
    #   CUDA / nvidia-smi        works without the wrapper
    # Do not import modules/desktop/hypr.nix as-is — it forces NVIDIA as
    # GBM/GLX/VAAPI, which is correct for kiss (RTX 3070) and wrong here.
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        mesa
        vulkan-loader
        intel-media-driver   # iHD — UHD 620 (Gen 9.5)
        intel-vaapi-driver   # i965 fallback
        libvdpau-va-gl
      ];
    };

    services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

    hardware.nvidia = {
      # Needed so nvidia-drm exists for offload / CUDA. Intel still owns KMS.
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      # MX150 is Pascal. 590+ (including production 595) dropped it; 580 is last.
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      # Runtime PM: dGPU can power down when nothing is using it.
      # finegrained is Turing+ only — leave it off.
      powerManagement.enable = true;

      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        # 0000:00:02.0 Intel UHD 620 / 0000:02:00.0 NVIDIA MX150
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:2:0:0";
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
        freerdp
        slack
        code-cursor

        # car diagnostic
        tio          # serial terminal (Miia, OBDLink, Flipper)
        can-utils    # CAN bus tools (socketcan, candump, etc.)
        usbutils     # lsusb
        lshw         # hardware enumeration
        pciutils     # lspci
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

      # GPU: Intel = display, MX150 = offload/CUDA
      intel-gpu-tools        # intel_gpu_top
      libva-utils            # vainfo (should report iHD)
      vulkan-tools           # vulkaninfo
      nvtopPackages.full     # intel + nvidia
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
      # Compositor / video decode on UHD 620. Do not set GBM_BACKEND or
      # __GLX_VENDOR_LIBRARY_NAME to nvidia — that makes Hyprland grab the MX150.
      LIBVA_DRIVER_NAME = "iHD";
      VDPAU_DRIVER = "va_gl";
    };
  };
}
