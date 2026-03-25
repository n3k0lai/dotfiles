{ config, lib, pkgs, pkgs-unstable, ... }:

with lib;

let
  cfg = config.modules.gaming.vr;
  
  # Pin WiVRn to v26.2.3 to match Quest store version
  baseWivrn = pkgs-unstable.wivrn.overrideAttrs (old: rec {
    version = "26.2.3";
    src = pkgs.fetchFromGitHub {
      owner = "WiVRn";
      repo = "WiVRn";
      rev = "v${version}";
      hash = "";  # Will fail first build with correct hash
    };
  });
  
  # Override WiVRn with CUDA support if GPU supports it
  wivrnPackage = 
    if (config.hardware.tr1ste.gpu.cudaSupport or false)
    then baseWivrn.override { cudaSupport = true; }
    else baseWivrn;
in
{
  options.modules.gaming.vr = {
    enable = mkEnableOption "VR gaming support with WiVRn";
    
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
    # Assert GPU is configured for VR
    assertions = [
      {
        assertion = config.hardware.graphics.enable or false;
        message = "VR gaming requires hardware.graphics to be enabled";
      }
    ];

    # Unity Hub requirements
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

    services.wivrn = {
      enable = true;
      openFirewall = true;
      defaultRuntime = cfg.defaultRuntime;
      autoStart = cfg.autoStart;
      package = wivrnPackage;
    };

    # Avahi (mDNS) – required for Quest discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };
    
    # VR-related packages
    users.users.nicho.packages = with pkgs; [
      unityhub
      vrc-get
      (pkgs.writeShellScriptBin "alcom" ''
        exec ${pkgs.alcom}/bin/alcom "$@"
      '')
      pkgs-unstable.vrcx
      pkgs-unstable.slimevr
      sidequest
    ];
    
    # ALCOM wrapper with environment variable
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellScriptBin "ALCOM" ''
        export WEBKIT_DISABLE_DMABUF_RENDERER=1
        exec ${pkgs.alcom}/bin/alcom "$@"
      '')
    ];
  };
}
