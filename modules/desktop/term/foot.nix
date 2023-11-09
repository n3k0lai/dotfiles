# modules/desktop/term/foot.nix
#
# 

{ options, config, lib, pkgs, ... }:

with lib;
with lib.my;
let cfg = config.modules.desktop.term.foot;
in {
  options.modules.desktop.term.st = {
    enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable {
    # xst-256color isn't supported over ssh, so revert to a known one
    modules.shell.zsh.rcInit = ''
      [ "$TERM" = foot ] && export TERM=foot
    '';

    user.packages = with pkgs; [
      foot 
      (makeDesktopItem {
        name = "foot";
        desktopName = "Foot Terminal";
        genericName = "Default terminal";
        icon = "utilities-terminal";
        exec = "${foot}/bin/foot";
        categories = [ "Development" "System" "Utility" ];
      })
    ];
  };
}