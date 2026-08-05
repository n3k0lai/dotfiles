# Patio fan-lights edge module (pati0)
# Amazon "Fanbulous" outdoor fans — BT app + IR remote; Pi shims into HA via MQTT.
# https://www.amazon.com/dp/B0DPHN3K1S
#
# Primary HA lives on rook. This module only defines the edge contract + packages.
# fanctl daemon implementation TBD (python/bleak or vendor reverse-engineer).
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.fans;
in {
  options.modules.servers.fans = {
    enable = mkEnableOption "Patio fan-light Bluetooth/IR shim toward rook HA";

    mqttHost = mkOption {
      type = types.str;
      default = "100.114.138.5";
      description = "Rook Mosquitto host (Tailscale IP preferred)";
    };

    mqttPort = mkOption {
      type = types.port;
      default = 1883;
    };

    fans = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; example = "patio-fan-1"; };
          mac = mkOption {
            type = types.str;
            description = "Bluetooth MAC of the fan controller";
            example = "D0:39:72:00:00:01";
          };
          lightEntity = mkOption {
            type = types.str;
            description = "HA entity id once MQTT discovery is up";
            example = "light.patio_fan_1_light";
          };
          fanEntity = mkOption {
            type = types.str;
            example = "fan.patio_fan_1";
          };
        };
      });
      default = [
        {
          name = "patio-fan-1";
          mac = "D0:39:72:XX:XX:XX"; # replace when paired
          lightEntity = "light.patio_fan_1_light";
          fanEntity = "fan.patio_fan_1";
        }
        {
          name = "patio-fan-2";
          mac = "D0:39:72:YY:YY:YY"; # replace when paired
          lightEntity = "light.patio_fan_2_light";
          fanEntity = "fan.patio_fan_2";
        }
      ];
    };
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = mkDefault true;

    environment.systemPackages = with pkgs; [
      bluez
      mosquitto
    ];

    # Future: systemd.services.fanctl = { ... }
    environment.etc."pati0/fans.json".text = builtins.toJSON {
      mqtt = {
        host = cfg.mqttHost;
        port = cfg.mqttPort;
      };
      fans = cfg.fans;
    };
  };
}
