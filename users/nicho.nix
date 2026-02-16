# users/nicho.nix
# User-specific configuration for nicho
{ config, lib, pkgs, ... }:

{
  home-manager.users.nicho = { pkgs, ... }: {
    # User environment variables
    home.sessionVariables = {
      # Default programs
      EDITOR = "emacs";
      TERMINAL = "kitty";
      BROWSER = "firefox";
      BROWSER_MIN = "luakit";
      
      # XDG directories
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_DATA_HOME = "$HOME/.local/share";
      
      # Development paths
      GOPATH = "$HOME/.local/share/go";
      
      # Emacs/Doom
      DOOMDIR = "$HOME/.config/doom";
      EMACSDIR = "$HOME/.config/emacs";
      
      # Application fixes
      MOZ_USE_XINPUT2 = "1";  # Mozilla smooth scrolling/touchpads
      OBS_USE_EGL = "1";  # OBS game capture on X11
      
      # Display (if not set by display manager)
      DISPLAY = ":0";
    };
    
    # Additional PATH entries
    home.sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.local/share/go/bin"
      "$HOME/.config/emacs/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.dotnet/tools"
    ];
    
    # Fish-specific interactive shell init
    programs.fish = {
      interactiveShellInit = ''
        # Call set_profile for fish-specific customizations
        if functions -q set_profile
            set_profile
        end
      '';
    };
    
    home.stateVersion = "25.05";
  };
}
