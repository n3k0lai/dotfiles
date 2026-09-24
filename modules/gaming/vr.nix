# VR host for Steam Frame (SteamVR Link) plus leftover Quest/ALVR tooling.
#
# Steam Frame is streaming-first: this PC runs Steam + SteamVR + VRChat
# (Proton), and the headset connects over the bundled Wi-Fi 6E USB adapter
# (dedicated 6 GHz P2P) or over LAN Steam Link. Controllers stay on the
# headset — no Watchman dongles on the host.
{ config, lib, pkgs, pkgs-unstable, ... }:

with lib;

let
  cfg = config.modules.gaming.vr;

  # Use stable WiVRn 0.23.2 — sideload matching APK to Quest
  # 26.2.3 segfaults on RTX 3070 + NixOS, 25.12 has no Quest APK
  baseWivrn = pkgs.wivrn;

  cudaSupport = config.hardware.kiss.gpu.cudaSupport or false;

  # Override WiVRn with CUDA support if GPU supports it
  wivrnPackage =
    if cudaSupport
    then baseWivrn.override { cudaSupport = true; }
    else baseWivrn;
in
{
  options.modules.gaming.vr = {
    enable = mkEnableOption "VR gaming support (Steam Frame / SteamVR Link host)";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Run WiVRn as a systemd service on startup";
    };

    defaultRuntime = mkOption {
      type = types.bool;
      default = true;
      description = "Set WiVRn as the default OpenXR runtime";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.graphics.enable or false;
        message = "VR gaming requires hardware.graphics to be enabled";
      }
    ];

    # Firmware for USB Wi-Fi 6E (Steam Frame wireless adapter) and BT.
    hardware.enableRedistributableFirmware = true;

    # Unity Hub requirements (VRC world/avatar tooling)
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      stdenv.cc.cc.lib   # core libc/libm
      openssl           # SSL/TLS (Unity Hub/editor networking)
      zlib              # compression
      libglvnd          # OpenGL/Vulkan (critical for GPU)
      glib              # GObject stuff
      gtk3              # Theme/dialogs (Unity uses GTK file pickers)
      dbus              # System bus
      alsa-lib          # Audio fallback
      libpulseaudio     # PulseAudio
      libuuid           # UUID generation
      curl              # Networking/downloads
      gdk-pixbuf        # image/icon loading in Unity UI
      icu               # Unity Licensing Client needs this

      # X11/XWayland fixes
      xorg.libX11
      xorg.libXcursor
      xorg.libXrandr
      xorg.libXi
    ];

    # WiVRn — disabled, 26.2.3 segfaults on RTX 3070, Meta store fights sideloading.
    # Steam Frame uses SteamVR Link, not WiVRn; leave SteamVR as the OpenXR runtime.
    # services.wivrn = {
    #   enable = true;
    #   openFirewall = true;
    #   defaultRuntime = cfg.defaultRuntime;
    #   autoStart = cfg.autoStart;
    #   package = wivrnPackage;
    # };

    networking.firewall = {
      # ALVR (Quest)
      allowedTCPPorts = [
        9943
        9944
        # Steam Remote Play extra (missing from nixos-25.05 steam module)
        27037
      ];
      allowedUDPPorts = [
        9943
        9944
        # SteamVR Link / Steam Link VR (headset stream). Validated as the
        # missing piece for Linux hosts; nixos-25.05 remotePlay.openFirewall
        # does not open these yet (added in nixpkgs#446932).
        10400
        10401
      ];
    };

    # mDNS — Steam Link / Frame discovery on LAN (adapter path is P2P and
    # does not need this, but LAN fallback does).
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    # Steam Frame wireless adapter (Valve SteamVR Link Dongle, 28de:2432).
    # USB 3 Wi-Fi 6E, 6 GHz only — SteamVR brings up a dedicated AP. Keep
    # NetworkManager off it and disable USB autosuspend so the link does
    # not drop mid-session. hardware.steam-hardware already tags Valve USB
    # as uaccess via steam-devices; these rules cover the network iface.
    services.udev.extraRules = ''
      # Valve Steam Frame / SteamVR Link wireless adapter
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2432", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2432", TEST=="power/autosuspend", ATTR{power/autosuspend}="-1"
      SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2432", TAG+="uaccess", MODE="0660"
      SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2432", ENV{NM_UNMANAGED}="1"
    '';

    users.users.nicho.packages = with pkgs; [
      unityhub
      vrc-get
      (pkgs.writeShellScriptBin "alcom" ''
        exec ${pkgs.alcom}/bin/alcom "$@"
      '')
      blender  # hair/gun kitbash: weight transfer, armature fit, FBX export
      pkgs-unstable.vrcx
      pkgs-unstable.slimevr
      sidequest
    ];

    environment.systemPackages = with pkgs; [
      alvr
      (pkgs.writeShellScriptBin "ALCOM" ''
        export WEBKIT_DISABLE_DMABUF_RENDERER=1
        exec ${pkgs.alcom}/bin/alcom "$@"
      '')
    ];
  };
}
