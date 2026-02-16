# modules/desktop/theme/waves.nix
# Waves theme - Orange/warm colorscheme inspired by ocean waves
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.theme.waves;
in {
  options.modules.desktop.theme.waves = {
    enable = mkEnableOption "Waves theme";
  };

  config = mkIf cfg.enable {
    # Export theme colors for other modules to use
    modules.desktop.theme = {
      name = "waves";
      
      colors = {
        # Terminal colorscheme (from fish config)
        foreground = "fef3e9";
        background = "191919";
        
        # Black
        color0 = "191919";
        color8 = "3f3f3f";
        
        # Red (not defined in original, using defaults)
        color1 = "cc6666";
        color9 = "ff6666";
        
        # Green (not defined in original, using defaults)
        color2 = "b5bd68";
        color10 = "c5cc68";
        
        # Yellow
        color3 = "af9976";
        color11 = "ffe8c5";
        
        # Blue
        color4 = "6495fc";
        color12 = "83d9f7";
        
        # Magenta (not defined in original, using defaults)
        color5 = "b294bb";
        color13 = "c294fb";
        
        # Cyan
        color6 = "39928d";
        color14 = "adf0e7";
        
        # White
        color7 = "c5c8c6";
        color15 = "fef3e9";
        
        # Additional UI colors
        accent = "6495fc";  # Blue
        accentAlt = "af9976";  # Yellow
        border = "3f3f3f";
        borderFocused = "6495fc";
      };
      
      wallpapers = {
        video = "waves.mp4";
        static = "waves.png";
      };
      
      fonts = {
        main = "Martian Mono";
        alt = "Hurmit Nerd Font";
        size = 12;
      };
    };
    
    # Symlink wallpaper assets to ~/.local/share/assets/
    home-manager.users.nicho = {
      xdg.dataFile."assets/waves.mp4".source = ../../../assets/waves/waves.mp4;
      xdg.dataFile."assets/waves.png".source = ../../../assets/waves/waves.png;
    };
  };
}
