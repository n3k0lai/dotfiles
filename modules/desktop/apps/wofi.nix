{ config, options, lib, pkgs, ... }:

with lib;
with lib.my;
let cfg = config.modules.desktop.apps.wofi;
in {
  options.modules.desktop.apps.wofi = {
    enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable {
    # link recursively so other modules can link files in its folder
    # home.xdg.configFile."wofi" = {
    #   source = <config/wofi>;
    #   recursive = true;
    # };

    user.packages = with pkgs; [
      (writeScriptBin "wofi" ''
        #!${stdenv.shell}
        exec ${pkgs.wofi}/bin/wofi -terminal xst -m -1 "$@"
      '')

      # Fake wofi dmenu entries
      (makeDesktopItem {
        name = "wofi-browsermenu";
        desktopName = "Open Bookmark in Browser";
        icon = "bookmark-new-symbolic";
        exec = "${config.dotfiles.binDir}/wofi/browsermenu";
      })
      (makeDesktopItem {
        name = "rofi-browsermenu-history";
        desktopName = "Open Browser History";
        icon = "accessories-clock";
        exec = "${config.dotfiles.binDir}/wofi/browsermenu history";
      })
      (makeDesktopItem {
        name = "rofi-filemenu";
        desktopName = "Open Directory in Terminal";
        icon = "folder";
        exec = "${config.dotfiles.binDir}/wofi/filemenu";
      })
      (makeDesktopItem {
        name = "rofi-filemenu-scratch";
        desktopName = "Open Directory in Scratch Terminal";
        icon = "folder";
        exec = "${config.dotfiles.binDir}/wofi/filemenu -x";
      })

      (makeDesktopItem {
        name = "lock-display";
        desktopName = "Lock screen";
        icon = "system-lock-screen";
        exec = "${config.dotfiles.binDir}/zzz";
      })
    ];
  };
}