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

let
  fortune-zh-module = import ../modules/core/fortune-zh.nix { inherit pkgs; };
in
{
  imports = [
    # Same desktop/user stack as configuration.nix. Host extras (VM, OBD)
    # stay below. Games / work / cad / emacs later, same pattern as kiss.nix.
    ../users/nicho.nix
    ../bin/default.nix
    ../modules/core/dev-mode.nix
    ../modules/core/kitty.nix
    ../modules/core/foot.nix
    ../modules/core/mpv.nix
    ../modules/core/zathura.nix
    ../modules/core/tmux.nix
    ../modules/core/ssh.nix
    ../modules/desktop/hypr.nix
    ../modules/desktop/fcitx5.nix
    ../modules/desktop/greetd.nix
    ../modules/desktop/sddm.nix
    ../modules/desktop/audio-idle-inhibit.nix
    ../modules/desktop/theme/default.nix
    ../modules/desktop/theme/waves.nix
    ../modules/browsers/firefox.nix
    ../modules/work/rdp.nix
    ../modules/servers/work-server.nix
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
    # hypr.nix nvidia=false below — do not export GBM/GLX/VAAPI=nvidia.
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
    #                        Virtualisation — Forscan (Windows) + USB OBD
    #
    # Forscan is a lightweight Win32 diagnostic UI. It needs a COM port, not a
    # GPU. Do not VFIO the MX150 for this guest:
    #   - 2 GB Pascal, no panel output, NVIDIA code-43 is common on Optimus
    #   - binding vfio-pci steals CUDA / nvidia-offload from the host
    #   - inspect IOMMU groups after the first boot with intel_iommu=on before
    #     even considering it (`find /sys/kernel/iommu_groups -type l`)
    # Guest display: SPICE + virtio-gpu. Attach OBD via virt-manager USB
    # redirect (Redirect USB device) or a USB hostdev on the domain.
    # Suggested domain: q35, OVMF, TPM 2.0 (swtpm), 6G RAM, 4 vCPU, virtio
    # disk/net. VirtIO driver ISO is at /etc/virtio-win.
    modules.servers.workVm = {
      enable = true;
      memoryMB = 6144;
      cores = 4;
      iommu = true;
      gpuPassthrough = false;
    };

    # OBDLink EX (ScanTool, FTDI 0403:6015, serial 223230387593) — live on
    # bus 1-3 as /dev/ttyUSB0. Stable host node: /dev/obdlink
    #   tio /dev/obdlink
    # For Forscan: close tio, then virt-manager → Redirect USB device
    # (host ftdi_sio must not hold it). Other adapters stay on the generic
    # vendor matches below.
    services.udev.extraRules = ''
      # This OBDLink EX — tty + USB device node
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", ATTRS{serial}=="223230387593", SYMLINK+="obdlink", GROUP="dialout", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6015", ATTR{serial}=="223230387593", MODE="0660", GROUP="libvirtd", TAG+="uaccess"

      # Other FTDI (OBDLink SX, many ELM cables)
      SUBSYSTEM=="usb", ATTR{idVendor}=="0403", MODE="0660", GROUP="libvirtd", TAG+="uaccess"
      # Silicon Labs CP210x (ELM327, some OBDLink)
      SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", MODE="0660", GROUP="libvirtd", TAG+="uaccess"
      # Prolific PL2303 (cheap clones — flaky, but people have them)
      SUBSYSTEM=="usb", ATTR{idVendor}=="067b", MODE="0660", GROUP="libvirtd", TAG+="uaccess"
      # Flipper Zero CDC
      SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="5740", MODE="0660", GROUP="libvirtd", TAG+="uaccess"
    '';

    ##################################################################################
    #                        Session — same modules as kiss
    #
    # leftover ~/.config from the 2024 dao checkout is renamed *.hm-bak
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "hm-bak";
    # blade tracks nixpkgs-unstable (26.11); the flake pins HM 25.05 like kiss.
    home-manager.users.nicho.home.enableNixpkgsReleaseCheck = false;
    home-manager.users.nicho.home.stateVersion = "24.05";

    modules.core.devMode.enable = true;
    modules.core.devMode.repoPath = "/home/nicho/dotfiles";
    modules.core.kitty.enable = true;
    modules.core.foot.enable = true;
    modules.core.mpv.enable = true;
    modules.core.zathura.enable = true;
    modules.core.tmux.enable = true;
    # Do not enable modules.core.ssh — that deploys kiss's agenix user key.
    # Blade GitHub key is machine-local (~/.ssh/id_ed25519_blade); pubkey in
    # modules/core/config/ssh/blade_ed25519.pub. Not an age recipient.

    modules.desktop.theme.waves.enable = true;
    modules.desktop.hyprland.enable = true;
    modules.desktop.hyprland.nvidia = false;
    modules.desktop.hyprland.monitorsLayout = "blade";
    modules.desktop.fcitx5.enable = true;
    modules.desktop.greetd.enable = true;
    modules.desktop.audioIdleInhibit.enable = true;
    modules.browsers.firefox.enable = true;
    modules.work.rdp.enable = true;
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # WiFi PSKs live in KWallet from the old Plasma install (psk-flags=1).
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;
    programs.nm-applet.enable = true;
    networking.networkmanager.wifi.powersave = false;
    networking.networkmanager.wifi.scanRandMacAddress = false;
    # USB ethernet vanish is "down" with the device already gone. NM often
    # leaves wifi disconnected; poke it back onto the best saved network.
    networking.networkmanager.dispatcherScripts = [{
      type = "basic";
      source = pkgs.writeText "wifi-on-ethernet-down" ''
        #!/bin/sh
        IFACE="$1"
        STATUS="$2"
        case "$IFACE" in
          en*|eth*) ;;
          *) exit 0 ;;
        esac
        case "$STATUS" in
          down|pre-down|off) ;;
          *) exit 0 ;;
        esac
        nmcli radio wifi on >/dev/null 2>&1 || true
        nmcli device set wlo1 autoconnect yes >/dev/null 2>&1 || true
        nmcli device connect wlo1 >/dev/null 2>&1 || true
      '';
    }];

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
        fortune-zh-module.fortune-with-zh

        # streaming / work — dedicated modules later
        chatterino2
        obs-studio
        discord
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

      # Services
      tailscale

      # CLI
      fish
      ranger
      bat
      fortune-zh-module.fortune-with-zh

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
      # fish_greeting.fish — skip the /nix/store scan
      CHINESE_FORTUNE_FILE = "${fortune-zh-module.fortune-with-zh}/share/games/fortunes/chinese";
    };
  };
}
