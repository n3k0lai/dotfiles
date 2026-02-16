{ pkgs }:

pkgs.stdenv.mkDerivation {
  pname = "sddm-waves-theme";
  version = "1.0";

  src = ./.;

  # No build phase needed - just copying files
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/share/sddm/themes/waves
    cp -r $src/* $out/share/sddm/themes/waves/
  '';

  meta = {
    description = "Animated wave SDDM theme inspired by waves colorscheme";
    license = pkgs.lib.licenses.mit;
  };
}
