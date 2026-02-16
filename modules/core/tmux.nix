# modules/core/tmux.nix
# Tmux terminal multiplexer
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.tmux;
in {
  options.modules.core.tmux = {
    enable = mkEnableOption "Tmux terminal multiplexer";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      tmux
    ];

    home-manager.users.nicho = {
      # Create default tmux config if none exists
      xdg.configFile."tmux/tmux.conf".text = ''
        # Tmux configuration
        # Managed by NixOS
        
        # Set prefix to Ctrl-a
        unbind C-b
        set -g prefix C-a
        bind C-a send-prefix
        
        # Enable mouse support
        set -g mouse on
        
        # Start windows and panes at 1, not 0
        set -g base-index 1
        setw -g pane-base-index 1
        
        # Reload config with prefix + r
        bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"
        
        # Better split commands
        bind | split-window -h
        bind - split-window -v
        
        # Vi mode
        setw -g mode-keys vi
        
        # Status bar
        set -g status-position bottom
        set -g status-justify left
        set -g status-style 'bg=colour0 fg=colour7'
      '';
    };
  };
}
