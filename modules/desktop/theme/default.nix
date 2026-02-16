# modules/desktop/theme/default.nix
# Base theme configuration that specific themes populate
{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.desktop.theme = {
    name = mkOption {
      type = types.str;
      default = "waves";
      description = "Active theme name";
    };
    
    colors = mkOption {
      type = types.attrs;
      default = {};
      description = "Theme color palette";
    };
    
    wallpapers = mkOption {
      type = types.attrs;
      default = {};
      description = "Theme wallpaper paths (relative to ~/.local/share/assets/)";
    };
    
    fonts = mkOption {
      type = types.attrs;
      default = {
        main = "Martian Mono";
        alt = "Hurmit Nerd Font";
        size = 12;
      };
      description = "Theme font configuration";
    };
  };
}
