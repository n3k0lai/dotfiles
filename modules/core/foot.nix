# modules/core/foot.nix
# Foot terminal emulator (Wayland-native)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.foot;
in {
  options.modules.core.foot = {
    enable = mkEnableOption "Foot terminal emulator";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      foot
    ];

    home-manager.users.nicho = {
      # Symlink foot config for hot-reload
      xdg.configFile."foot" = {
        source = ./config/foot;
        recursive = true;
      };
    };
  };
}
