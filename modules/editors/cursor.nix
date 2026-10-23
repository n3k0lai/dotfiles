# modules/editors/cursor.nix
# Cursor IDE (pkgs.code-cursor). Unfree.
#
# Usage: import this module and set modules.editors.cursor.enable = true.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.cursor;
in {
  options.modules.editors.cursor = {
    enable = mkEnableOption "Cursor IDE";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.code-cursor ];

    # Electron on Wayland. The VS Code module sets the same variable.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    xdg.mime.enable = true;
    xdg.mime.defaultApplications."application/x-cursor-workspace" = "cursor.desktop";
  };
}
