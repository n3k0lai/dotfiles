# modules/core/zathura.nix
# Zathura PDF viewer
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.zathura;
in {
  options.modules.core.zathura = {
    enable = mkEnableOption "Zathura PDF viewer";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      zathura
    ];

    home-manager.users.nicho = {
      # Symlink zathura config for hot-reload
      xdg.configFile."zathura" = {
        source = ./config/zathura;
        recursive = true;
      };
    };
  };
}
