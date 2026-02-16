# modules/core/mpd.nix
# Music Player Daemon with ncmpcpp client
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.mpd;
in {
  options.modules.core.mpd = {
    enable = mkEnableOption "MPD music server with ncmpcpp";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mpd
      ncmpcpp
      mpc-cli  # CLI client for mpd
    ];

    # Enable MPD service
    services.mpd = {
      enable = true;
      user = "nicho";
      musicDirectory = "/home/nicho/Music";
      extraConfig = ''
        audio_output {
          type "pipewire"
          name "PipeWire Sound Server"
        }
        
        audio_output {
          type "fifo"
          name "Visualizer feed"
          path "/tmp/mpd.fifo"
          format "44100:16:2"
        }
      '';
    };

    home-manager.users.nicho = {
      # Symlink ncmpcpp config for hot-reload
      xdg.configFile."ncmpcpp" = {
        source = ./config/ncmpcpp;
        recursive = true;
      };
    };
  };
}
