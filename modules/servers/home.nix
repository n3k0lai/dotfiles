# Home Assistant automation server module (rook primary)
# Matter via python-matter-server; MQTT; Hue/Nanoleaf; weather (NWS + Met.no)
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

    enableMatter = mkOption {
      type = types.bool;
      default = true;
      description = "Enable python-matter-server + HA Matter integration (Wi‑Fi Matter; Thread needs a border router)";
    };

    matterPort = mkOption {
      type = types.port;
      default = 5580;
      description = "python-matter-server WebSocket port (localhost; HA connects here)";
    };

    enableBluetooth = mkOption {
      type = types.bool;
      default = true;
      description = "Enable BlueZ + HA bluetooth component (BLE commissioning / proxies)";
    };

    # Allow matter-server to touch the BT adapter for BLE commissioning.
    # Stock NixOS unit is heavily sandboxed (PrivateDevices) and cannot use BT.
    matterBluetoothCommissioning = mkOption {
      type = types.bool;
      default = true;
      description = "Relax matter-server sandbox enough for Bluetooth LE commissioning";
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

    # Public repo: no more precise than Fairfax County, VA (Northern Virginia).
    latitude = mkOption {
      type = types.float;
      default = 38.8462;
      description = "Home latitude (Fairfax County centroid — do not refine in public git)";
    };

    longitude = mkOption {
      type = types.float;
      default = -77.3064;
      description = "Home longitude (Fairfax County centroid — do not refine in public git)";
    };

    elevation = mkOption {
      type = types.int;
      default = 100;
      description = "Home elevation (meters)";
    };

    timeZone = mkOption {
      type = types.str;
      default = "America/New_York";
      description = "IANA timezone for Home Assistant";
    };

    unitSystem = mkOption {
      type = types.enum [ "metric" "us_customary" ];
      default = "us_customary";
      description = "HA unit system";
    };

    # Edge nodes (e.g. pati0) that publish into this broker / are documented here
    edgeMqttPeers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "pati0.bushbaby-mercat.ts.net" ];
      description = "Documented MQTT/edge peers (informational; used in comments + firewall notes)";
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

    # --- Bluetooth (motherboard / USB adapter) ---
    # rook: Intel BT USB 8087:0a2b → hci0 present; enable stack when requested.
    hardware.bluetooth = mkIf cfg.enableBluetooth {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true; # better LE device class support
          ControllerMode = "dual";
        };
      };
    };
    services.blueman.enable = mkIf cfg.enableBluetooth false; # headless — no GUI

    # --- Matter Server (primary fabric controller) ---
    services.matter-server = mkIf cfg.enableMatter {
      enable = true;
      port = cfg.matterPort;
      logLevel = "info";
      # extraArgs = [ "--log-level-sdk" "error" ];
    };

    # BLE commissioning needs real devices + AF_BLUETOOTH; stock unit blocks both.
    systemd.services.matter-server = mkIf (cfg.enableMatter && cfg.matterBluetoothCommissioning) {
      serviceConfig = {
        PrivateDevices = mkForce false;
        DevicePolicy = mkForce "auto";
        RestrictAddressFamilies = mkForce [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
          "AF_BLUETOOTH"
        ];
        # matter-server / chip may need rfkill + hidraw during commission
        BindPaths = [ "/dev/rfkill" ];
        SupplementaryGroups = [ "dialout" ];
      };
    };

    services.home-assistant = {
      enable = true;
      package = pkgs.home-assistant;

      extraComponents = [
        # Lighting
        "hue"
        "nanoleaf"
        # HVAC — Venstar local API (see vault Projects/home-automation/thermostat)
        "venstar"
        # Media
        "cast"
        # IoT protocols
        "mqtt"
        # Matter (Wi‑Fi devices: Deco, GE Cync Matter, etc.)
        "matter"
        # Thread UI / diagnostics (needs a border router on the LAN to be useful)
        "thread"
        # Bluetooth (adapters, passive monitoring; pairs with matter BLE commission)
        "bluetooth"
        "bluetooth_adapters"
        # Weather — NWS for Northern Virginia / Fairfax County; met kept for cleanup/re-add
        "met"
        "nws"
        "accuweather"
        # Cameras
        "generic"
        "onvif"
        "ffmpeg"
        # Network discovery
        "zeroconf"
        "ssdp"
        "dhcp"
        # Mobile / system
        "mobile_app"
        "webhook"
        "history"
        "logbook"
        "energy"
      ];

      config = {
        homeassistant = {
          name = "Home";
          latitude = cfg.latitude;
          longitude = cfg.longitude;
          elevation = cfg.elevation;
          unit_system = cfg.unitSystem;
          time_zone = cfg.timeZone;
          currency = "USD";
          country = "US";
          allowlist_external_dirs = [ "/tmp" ];
          # External / edge nodes reach HA over Tailscale; trusted proxies optional
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

        # Matter is configured in the UI → ws://127.0.0.1:<matterPort>/ws
        # (do not bake secrets into yaml)

        default_config = {};

        # Recorder / history stay on default_config defaults unless we outgrow SD/disk
      };
    };

    services.mosquitto = mkIf cfg.enableMqtt {
      enable = true;
      listeners = [
        {
          port = 1883;
          # LAN+TS IoT. Tighten with passwords when pati0 is live.
          settings.allow_anonymous = true;
          acl = [ "topic readwrite #" ];
        }
      ];
    };

    # Local hostname vhost (Tailscale MagicDNS / LAN hostname)
    services.caddy.virtualHosts = {
      "${config.networking.hostName}" = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.port}
        '';
      };
    };

    # Firewall:
    # - 8123 stays CLOSED on LAN (rook security model: Tailscale-only for HA UI)
    # - MQTT open for edge nodes (pati0, bulbs bridges) — prefer Tailscale later
    # - matter-server stays on localhost; no public 5580
    networking.firewall.allowedTCPPorts =
      mkIf cfg.enableMqtt [ 1883 ];

    # Ensure HA starts after matter-server when both enabled
    systemd.services.home-assistant = mkIf cfg.enableMatter {
      after = [ "matter-server.service" ];
      wants = [ "matter-server.service" ];
    };

    modules.servers.haHermesBridge.enable =
      cfg.enableWebhookBridge && (config.modules.servers.hermes.enable or false);

    systemd.services.hermes-agent = mkIf (hermesCfg.enable or false) {
      environment = {
        HA_URL = "http://127.0.0.1:${toString cfg.port}";
        HA_TOKEN_FILE = config.age.secrets.ha-long-lived-token.path;
        # Edge peer list (space-separated) for scripts / future skills
        HA_EDGE_PEERS = concatStringsSep " " cfg.edgeMqttPeers;
      } // optionalAttrs cfg.enableMatter {
        MATTER_SERVER_URL = "ws://127.0.0.1:${toString cfg.matterPort}/ws";
      };
    };
  };
}
