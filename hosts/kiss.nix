# My main pc. The motherload. The queen.
# where I live and where I build.
{ config, lib, pkgs, hermes-agent, ... }:

with lib;

let
  # Native Wayland + NVIDIA EGL. The stock wrapper forces X11 and the GUI
  # then paints with SwiftShader; that surface goes white when a display is
  # replugged or its mode changes, while mullvad-daemon keeps running.
  # WaylandLinuxDrmSyncobj is the explicit-sync feature that keeps this
  # Electron GPU process from blanking on NVIDIA workspace switches.
  mullvad-vpn = pkgs.mullvad-vpn.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      libPath="${lib.makeLibraryPath [ pkgs.libglvnd ]}:/run/opengl-driver/lib"
      for b in mullvad-vpn mullvad-gui; do
        wrapProgram $out/bin/$b \
          --set NIXOS_OZONE_WL 1 \
          --prefix LD_LIBRARY_PATH : "$libPath" \
          --set __EGL_VENDOR_LIBRARY_DIRS /run/opengl-driver/share/glvnd/egl_vendor.d \
          --add-flags "--ozone-platform=wayland --enable-features=WaylandLinuxDrmSyncobj"
      done
    '';
  });
in {
  imports = [
    ../modules/hardware/scarlett.nix
    ../modules/hardware/unicorne.nix
    ../modules/hardware/clicks.nix
    ../modules/hardware/scuf.nix
    ../modules/hardware/svalbard.nix
    ../modules/hardware/sammy.nix
    ../modules/desktop/fcitx5.nix
    ../modules/editors/cad.nix
    ../modules/editors/opencode.nix
    ../modules/editors/opencut.nix
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

    modules.editors.opencode.enable = true;
    modules.editors.opencut.enable = true;
    # cargo run from ~/Code/OpenCut when present; else the Nix binary.
    modules.editors.opencut.dev.enable = true;
    modules.editors.opencut.dev.repoPath = "/home/nicho/Code/OpenCut";

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

    # League of Legends — Moonlight client (Vanguard blocks native Linux; needs Windows Sunshine host)
    modules.gaming.riot.enable = true;

    # EVE Online — first-class (dedicated launcher; Steam App 8500 backup)
    modules.gaming.eve-online.enable = true;

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

    # Steam Frame / Steam Link discovery is LAN multicast. Mullvad blocks LAN
    # by default, which makes the headset fail to find this host (and Tailscale
    # already occupies another interface that vrlink likes to bind).
    systemd.services.mullvad-allow-lan = {
      description = "Allow LAN through Mullvad (Steam Frame / Steam Link)";
      after = [ "mullvad-daemon.service" ];
      wants = [ "mullvad-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 3;
        ExecStart = "${config.services.mullvad-vpn.package}/bin/mullvad lan set allow";
      };
    };
  };
}
