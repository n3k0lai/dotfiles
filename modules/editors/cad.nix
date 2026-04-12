# CAD and hardware design tools
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.editors.cad;

  # DIY Layout Creator — perfboard/stripboard/chassis layout tool
  # Java app from https://github.com/bancika/diy-layout-creator
  diylc-appimage = pkgs.stdenv.mkDerivation rec {
    pname = "diylc";
    version = "5.12.0";

    src = pkgs.fetchurl {
      url = "https://github.com/bancika/diy-layout-creator/releases/download/v${version}/diylc-${version}-linux.zip";
      hash = "sha256-SBIMU6Ousa2mLgGLUb67NCqxUUoiBOyUXw0lfviuW4I=";
    };

    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cp DIYLayoutCreator-${version}-x86_64.AppImage $out/diylc.AppImage
      chmod +x $out/diylc.AppImage
    '';
  };

  diylc = pkgs.appimageTools.wrapType2 {
    pname = "diylc";
    version = "5.12.0";

    src = "${diylc-appimage}/diylc.AppImage";

    meta = with lib; {
      description = "DIY Layout Creator — perfboard, stripboard, and chassis layout editor";
      homepage = "https://github.com/bancika/diy-layout-creator";
      license = licenses.gpl3;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  options.modules.editors.cad = {
    kicad.enable = mkEnableOption "KiCad EDA suite for schematic/PCB design";
    diylc.enable = mkEnableOption "DIY Layout Creator for perfboard/stripboard layouts";
    hardware.enable = mkEnableOption "Hardware DIY tools (serial consoles, flashing, embedded dev)";
  };

  config = mkMerge [
    (mkIf cfg.kicad.enable {
      environment.systemPackages = with pkgs; [
        kicad         # Schematic + PCB editor (libraries bundled)
      ];
    })

    (mkIf cfg.diylc.enable {
      environment.systemPackages = [ diylc ];
    })

    (mkIf cfg.hardware.enable {
      environment.systemPackages = with pkgs; [
        screen        # Serial console (CircuitPython REPL)
        minicom       # Serial console (alternative)
        picocom       # Lightweight serial console
        openocd       # On-chip debugger (JTAG/SWD)
        probe-rs-tools # Rust embedded flashing/debugging (probe-rs)
        arduino-cli   # Arduino board/library management
        sigrok-cli    # Logic analyzer / oscilloscope
        pulseview     # GUI for sigrok logic analyzer
      ];

      # Allow users in plugdev/dialout to access serial devices without sudo
      users.groups.dialout = {};
      services.udev.extraRules = ''
        # CircuitPython / Seeed XIAO / Adafruit boards
        SUBSYSTEM=="usb", ATTR{idVendor}=="2886", MODE="0666"
        SUBSYSTEM=="usb", ATTR{idVendor}=="239a", MODE="0666"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="2886", MODE="0666"
        SUBSYSTEM=="tty", ATTRS{idVendor}=="239a", MODE="0666"
        # Sigrok-supported logic analyzers (Saleae, etc)
        SUBSYSTEM=="usb", ATTR{idVendor}=="0925", MODE="0666"
        SUBSYSTEM=="usb", ATTR{idVendor}=="21a9", MODE="0666"
      '';
    })
  ];
}
