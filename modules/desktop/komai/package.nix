# Komai Matrix client (https://komai.chat). Not in nixpkgs as of 2026-11-20,
# so this wraps the official x86_64 AppImage with appimageTools.wrapType2.
# Call this with the flake's pkgs-komai (glibc 2.44). The 2026.10.25.0
# AppImage needs glibc >= 2.43; nixos-26.05 still has 2.42.
{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "komai";
  version = "2026.10.25.0";

  src = fetchurl {
    url = "https://github.com/etkecc/komai/releases/download/v${version}/komai-${version}-x86_64.AppImage";
    hash = "sha256-vZPJ02jVNkxeQvpmkyYEiO9lkQ1PPuI/HpO2CgbE438=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/usr/share/applications/cc.etke.komai.desktop \
      $out/share/applications/cc.etke.komai.desktop
    mkdir -p $out/share/icons
    cp -r --no-preserve=mode ${appimageContents}/usr/share/icons/hicolor $out/share/icons/
    rm -f $out/share/icons/hicolor/icon-theme.cache
  '';

  meta = {
    description = "Desktop-first Matrix chat client (Rust, C++, QML)";
    homepage = "https://komai.chat";
    changelog = "https://github.com/etkecc/komai/releases/tag/v${version}";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "komai";
  };
}
