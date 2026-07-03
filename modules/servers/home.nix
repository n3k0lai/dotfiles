# Home Assistant automation server module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.homeAssistant;
  hermesCfg = config.modules.servers.hermes;
  trustedProxies = [ "127.0.0.1" "::1" ] ++ cfg.trustedProxyCidrs;
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

    enableWebhookBridge = mkOption {
      type = types.bool;
      default = true;
      description = "Enable HA alert webhook bridge to Hermes (requires Hermes on same host)";
    };

    longLivedTokenFile = mkOption {
      type = types.path;
      default = ../servers/secrets/ha_long_lived_token.age;
      description = "Agenix file with Home Assistant long-lived access token";
    };

    trustedProxyCidrs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra CIDRs/IPs trusted as reverse proxies";
    };
  };

  imports = [
    ./ha-hermes-bridge.nix
  ];

  config = mkIf cfg.enable {
    age.secrets.ha-long-lived-token = {
      file = cfg.longLivedTokenFile;
      owner = "hermes";
      group = "users";
      mode = "0400";
    };

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
        # Cameras
        "generic"
        "onvif"
        "ffmpeg"
        # Network discovery
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

        http = {
          server_port = cfg.port;
          use_x_forwarded_for = true;
          trusted_proxies = trustedProxies;
        };

        mqtt = mkIf cfg.enableMqtt {
          broker = "127.0.0.1";
          port = 1883;
          discovery = true;
          discovery_prefix = "homeassistant";
        };

        default_config = {};
      };
    };

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

    services.caddy.virtualHosts = {
      "${config.networking.hostName}" = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.port}
        '';
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.enableMqtt [ 1883 ];

    modules.servers.haHermesBridge.enable =
      cfg.enableWebhookBridge && (config.modules.servers.hermes.enable or false);
    systemd.services.hermes-agent = mkIf (hermesCfg.enable or false) {
      environment = {
        HA_URL = "http://127.0.0.1:${toString cfg.port}";
        HA_TOKEN_FILE = config.age.secrets.ha-long-lived-token.path;
      };
    };
  };
}