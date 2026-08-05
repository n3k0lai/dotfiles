# Camera edge module (pati0 / other Pi nodes)
# Streams / events toward primary HA on rook via MQTT or generic camera integration.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.cam;
in {
  options.modules.servers.cam = {
    enable = mkEnableOption "Patio/edge camera pipeline toward primary Home Assistant";

    rookHaUrl = mkOption {
      type = types.str;
      default = "http://100.114.138.5:8123";
      description = "Primary HA base URL (Tailscale IP or MagicDNS)";
    };

    devices = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; description = "Entity slug, e.g. patio_door"; };
          device = mkOption {
            type = types.str;
            default = "/dev/video0";
            description = "V4L2 device path";
          };
        };
      });
      default = [ ];
      description = "Camera devices to expose";
    };
  };

  config = mkIf cfg.enable {
    # Real ffmpeg/rtsp services land here when the Pi is imaged.
    # Placeholder keeps the module valid and documents the contract.
    assertions = [
      {
        assertion = cfg.devices != [ ] -> cfg.rookHaUrl != "";
        message = "modules.servers.cam: rookHaUrl required when devices are set";
      }
    ];

    environment.systemPackages = with pkgs; [ ffmpeg v4l-utils ];
  };
}
