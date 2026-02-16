{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.sddm;
  theme = config.modules.desktop.theme;
  sddm-waves-theme = pkgs.callPackage ./sddm-theme { };
in {
  options.modules.desktop.sddm = {
    enable = mkEnableOption "SDDM display manager";
  };

  config = mkIf cfg.enable {
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = false;
      theme = theme.name;
      settings = {
        Theme = {
          ThemeDir = "${sddm-waves-theme}/share/sddm/themes";
        };
      };
    };

    environment.systemPackages = [
      sddm-waves-theme
      pkgs.libsForQt5.qt5.qtgraphicaleffects  # Required for DropShadow in theme
    ];
  };
}
