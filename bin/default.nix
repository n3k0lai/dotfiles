# ./bin/default.nix
# Fish shell configuration with script management
{ config, lib, pkgs, ... }:

{
  home-manager.users.nicho = {
    # Symlink fish functions and other dirs for hot-reload
    # Note: config.fish is managed by programs.fish below
    xdg.configFile."fish/functions" = {
      source = ./fish/functions;
      recursive = true;
    };
    xdg.configFile."fish/conf.d" = {
      source = ./fish/conf.d;
      recursive = true;
    };
    xdg.configFile."fish/completions" = {
      source = ./fish/completions;
      recursive = true;
    };
    xdg.configFile."fish/themes" = {
      source = ./fish/themes;
      recursive = true;
    };
    
    # Enable fish via home-manager
    programs.fish = {
      enable = true;
      
      # Fish-specific shell initialization
      # Read the actual config.fish content
      shellInit = builtins.readFile ./fish/config.fish;
      
      interactiveShellInit = ''
        # Call set_profile if it exists
        if functions -q set_profile
            set_profile
        end
      '';
      
      # Shell aliases (optional - can also go in fish/config.fish)
      shellAliases = {
        # Add any nix-managed aliases here
      };
    };
  };
}
