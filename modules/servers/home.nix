# Home Assistant automation server module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.homeAssistant;
in {
  options.modules.servers.homeAssistant = {
    enable = mkEnableOption "Home Assistant automation server";

    port = mkOption {
      type = types.port;
      default = 8123;
      description = "Port for Home Assistant web interface";
    };

    enableMqtt = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Mosquitto MQTT broker for IoT devices";
    };

  };

  config = mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      package = pkgs.home-assistant;

      extraComponents = [
        # Lighting
        "hue"
        "nanoleaf"
        # Media
        "cast"
        # IoT protocols
        "mqtt"
        # Network
        "zeroconf"
        "ssdp"
      ];

      config = {
        homeassistant = {
          name = "Home";
          latitude = 40.7128;
          longitude = -74.0060;
          elevation = 10;
          unit_system = "metric";
          allowlist_external_dirs = [ "/tmp" ];
        };

        # HTTP configuration for reverse proxy
        http = {
          server_port = cfg.port;
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1"
            "::1"
          ];
        };

        # Enable default integrations
        default_config = {};
      };
    };

    # Mosquitto MQTT broker for IoT devices
    services.mosquitto = mkIf cfg.enableMqtt {
      enable = true;
      listeners = [
        {
          port = 1883;
          settings.allow_anonymous = true;
          acl = [ "topic readwrite #" ];
        }
      ];
    };

    # Caddy reverse proxy for Home Assistant
    services.caddy.virtualHosts = {
      "${config.networking.hostName}" = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.port}
        '';
      };
    };

    # Open MQTT port if enabled
    networking.firewall.allowedTCPPorts = mkIf cfg.enableMqtt [ 1883 ];
  };
}
