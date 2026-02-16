# modules/desktop/theme/ene.nix
# Ene theme - Pink/cute colorscheme inspired by ene character
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.theme.ene;
in {
  options.modules.desktop.theme.ene = {
    enable = mkEnableOption "Ene theme";
  };

  config = mkIf cfg.enable {
    # Export theme colors for other modules to use
    modules.desktop.theme = {
      name = "ene";
      
      colors = {
        # Terminal colorscheme (pink/cute variant)
        foreground = "fef3e9";
        background = "1a1a1a";
        
        # Black
        color0 = "1a1a1a";
        color8 = "4a4a4a";
        
        # Red/Pink (ene accent)
        color1 = "ff6b9d";
        color9 = "ff8fb3";
        
        # Green
        color2 = "a8e6a0";
        color10 = "c8f6c0";
        
        # Yellow
        color3 = "ffd700";
        color11 = "ffe44d";
        
        # Blue
        color4 = "7aa2f7";
        color12 = "9ac2ff";
        
        # Magenta/Pink (main ene color)
        color5 = "ff69b4";
        color13 = "ff85cc";
        
        # Cyan
        color6 = "73daca";
        color14 = "a0f0e0";
        
        # White
        color7 = "dcdcdc";
        color15 = "ffffff";
        
        # Additional UI colors
        accent = "ff69b4";  # Hot pink
        accentAlt = "7aa2f7";  # Blue
        border = "4a4a4a";
        borderFocused = "ff69b4";
      };
      
      wallpapers = {
        animated = "ene.gif";
        static = "ene.png";
        thumbnail = "ene.jpg";
      };
      
      fonts = {
        main = "Martian Mono";
        alt = "Hurmit Nerd Font";
        size = 12;
      };
    };
    
    # Symlink wallpaper assets to ~/.local/share/assets/
    home-manager.users.nicho = {
      xdg.dataFile."assets/ene.gif".source = ../../../assets/ene/ene.gif;
      xdg.dataFile."assets/ene.png".source = ../../../assets/ene/ene.png;
      xdg.dataFile."assets/ene.jpg".source = ../../../assets/ene/ene.jpg;
    };
  };
}
