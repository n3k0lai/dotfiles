# modules/core/kitty.nix
# Kitty terminal emulator with theme integration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.kitty;
  theme = config.modules.desktop.theme;
in {
  options.modules.core.kitty = {
    enable = mkEnableOption "Kitty terminal emulator";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      kitty
    ];

    home-manager.users.nicho = {
      # Symlink kitty config for hot-reload
      xdg.configFile."kitty" = {
        source = ./config/kitty;
        recursive = true;
      };
      
      # Alternative: use programs.kitty for declarative config with theme integration
      # Uncomment and customize if you prefer declarative over file-based config
      # programs.kitty = {
      #   enable = true;
      #   font = {
      #     name = theme.fonts.main;
      #     size = theme.fonts.size;
      #   };
      #   settings = {
      #     foreground = "#${theme.colors.foreground}";
      #     background = "#${theme.colors.background}";
      #     color0 = "#${theme.colors.color0}";
      #     color1 = "#${theme.colors.color1}";
      #     # ... rest of colors
      #   };
      # };
    };
  };
}
