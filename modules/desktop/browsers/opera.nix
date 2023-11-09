# modules/browser/opera.nix
#
# my gamer browser 

{ options, config, lib, pkgs, ... }:

with lib;
with lib.my;
let cfg = config.modules.desktop.browsers.opera;
in {
  options.modules.desktop.browsers.opera = {
    enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable {
    user.packages = with pkgs; [
      opera
      (makeDesktopItem {
        name = "opera-private";
        desktopName = "opera Web Browser";
        genericName = "Open a private opera window";
        icon = "opera";
        exec = "${opera}/bin/opera --incognito";
        categories = [ "Network" ];
      })
    ];
  };
}