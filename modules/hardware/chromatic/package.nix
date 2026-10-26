# MR Updater, ModRetro's Chromatic firmware updater. Upstream ships an
# AppImage (a PyInstaller/PySide6 app that vendors esptool, openFPGALoader
# and libusb) inside a zip at an unversioned S3 URL, so the hash below pins
# the build that was live when this was packaged (Last-Modified 2026-10-10).
# When ModRetro publishes a new build the fetch fails on the hash; bump
# `version` and the hash together.
{ lib, runtimeShell, appimageTools, fetchzip, writeTextDir, symlinkJoin }:

let
  pname = "mr-updater";
  version = "2026-10-10";

  zip = fetchzip {
    url = "https://s3.us-east-1.amazonaws.com/updates.modretro.com/apps/ChromaticFirmwareUpdater-linux-x86_64.zip";
    hash = "sha256-8cI6vX2wfm5LfKEb/q4pX8hdHM6ZH0QzQUaEnFg55FI=";
  };

  src = "${zip}/ChromaticFirmwareUpdater-x86_64.AppImage";

  contents = appimageTools.extractType2 { inherit pname version src; };

  app = appimageTools.wrapType2 {
    inherit pname version src;

    # Qt 6.5+ wants xcb-util-cursor for its xcb plugin; the bundled Qt may
    # still miss it, so the launcher below prefers Wayland.
    extraPkgs = pkgs: [ pkgs.xcb-util-cursor ];

    # The startup check looks for /etc/udev/rules.d/99-modretro.rules, which
    # the AppImage sandbox doesn't see on NixOS, and otherwise demands root.
    # Our rules are installed system-wide, so skip that check.
    extraBwrapArgs = [ "--ro-bind-try" "/etc/udev" "/etc/udev" ];

    extraInstallCommands = ''
      # Belt and braces for the udev check: pass --dopc
      # (--disable_os_permissions_check) so it never demands root.
      mv $out/bin/mr-updater $out/bin/.mr-updater-wrapped
      cat > $out/bin/mr-updater <<EOS
      #!${runtimeShell}
      export QT_QPA_PLATFORM="\''${QT_QPA_PLATFORM:-wayland;xcb}"
      exec $out/bin/.mr-updater-wrapped --dopc "\$@"
      EOS
      chmod +x $out/bin/mr-updater
      install -Dm444 ${contents}/ChromaticFirmwareUpdater.desktop \
        $out/share/applications/mr-updater.desktop
      substituteInPlace $out/share/applications/mr-updater.desktop \
        --replace-fail "Name=ChromaticFirmwareUpdater" "Name=MR Updater (Chromatic)" \
        --replace-fail "Exec=ChromaticFirmwareUpdater" "Exec=mr-updater" \
        --replace-fail "Icon=icon_256x256" "Icon=mr-updater"
      install -Dm444 ${contents}/icon_256x256.png \
        $out/share/icons/hicolor/256x256/apps/mr-updater.png
    '';
  };

  # USB IDs come from the app's own bundled resources/linux/99-modretro.rules
  # and flashing_tool/chromaticv2: 374e:0101 is the Chromatic (ESP32 MCU
  # serial console plus the FPGA programming interface), 33aa:0120 is the
  # Gowin USB cable ID it also probes. Upstream sets MODE 0666; we use
  # uaccess instead. uaccess has to be tagged before 73-seat-late.rules,
  # hence the 70- prefix.
  rules = writeTextDir "lib/udev/rules.d/70-modretro-chromatic.rules" ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="33aa", ATTR{idProduct}=="0120", MODE="0660", TAG+="uaccess"
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="374e", ATTRS{idProduct}=="0101", MODE="0660", TAG+="uaccess"
  '';

  # On start the app checks that /etc/udev/rules.d/99-modretro.rules exists
  # and, if not, refuses to run unless launched as root (it then copies its
  # own rules in). NixOS manages /etc/udev/rules.d, so ship a file by that
  # name; the real rules live in the 70- file above.
  stub = writeTextDir "lib/udev/rules.d/99-modretro.rules" ''
    # Placeholder so MR Updater's startup check finds its rules file.
    # The Chromatic's access rules are in 70-modretro-chromatic.rules.
  '';
in
symlinkJoin {
  name = "${pname}-${version}";
  paths = [ app rules stub ];
  meta = {
    description = "ModRetro MR Updater: Chromatic firmware and Cart Clinic updater";
    homepage = "https://support.modretro.com/en_us/chromatic-firmware-updater-ryhoYnzCx";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "mr-updater";
  };
}
