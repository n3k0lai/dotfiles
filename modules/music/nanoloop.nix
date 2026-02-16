# modules/music/nanoloop.nix
# Dual mGBA instances with PipeWire crossfader for nanoloop
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.music.nanoloop;
in {
  options.modules.music.nanoloop = {
    enable = mkEnableOption "nanoloop dual mGBA with PipeWire crossfader";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mgba
      qpwgraph
      a2jmidid
    ];

    # Create two PipeWire virtual sinks for crossfading
    services.pipewire.extraConfig.pipewire."20-nanoloop" = {
      "context.modules" = [
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "nanoloop-a";
            "capture.props" = {
              "node.name" = "nanoloop-a";
              "media.class" = "Audio/Sink";
              "audio.position" = [ "FL" "FR" ];
            };
            "playback.props" = {
              "node.name" = "nanoloop-a-output";
              "node.passive" = true;
              "audio.position" = [ "FL" "FR" ];
            };
          };
        }
        {
          name = "libpipewire-module-loopback";
          args = {
            "node.description" = "nanoloop-b";
            "capture.props" = {
              "node.name" = "nanoloop-b";
              "media.class" = "Audio/Sink";
              "audio.position" = [ "FL" "FR" ];
            };
            "playback.props" = {
              "node.name" = "nanoloop-b-output";
              "node.passive" = true;
              "audio.position" = [ "FL" "FR" ];
            };
          };
        }
      ];
    };

    home-manager.users.nicho = {
      xdg.configFile."fish/functions/nanoloop.fish" = {
        source = ./config/fish/nanoloop.fish;
      };
      xdg.configFile."fish/functions/nanoloop-fade.fish" = {
        source = ./config/fish/nanoloop-fade.fish;
      };
    };
  };
}
