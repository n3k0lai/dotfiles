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

    enableGo2rtc = mkOption {
      type = types.bool;
      default = true;
      description = "go2rtc on localhost for rack USB cams + optional Tapo RTSP (HA consumes streams)";
    };

    # Stable V4L path for Logitech BRIO on the rack (entryway promotion)
    brioDevice = mkOption {
      type = types.str;
      default = "/dev/v4l/by-id/usb-046d_Logitech_BRIO_873011C9-video-index0";
      description = "V4L capture node for rack entryway BRIO (use by-id, not video0)";
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

    # Location (lat/long/elevation) is intentionally NOT set in configuration.yaml.
    # Public git must not carry residence coords. Set once in HA UI
    # (Settings → System → General); stored in .storage, not regenerated from Nix.

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

    # --- go2rtc: rack cameras (BRIO entryway; C200 Elon when RTSP ready) ---
    # API: http://127.0.0.1:1984  (not opened on LAN firewall)
    # HA Generic Camera:
    #   still:  http://127.0.0.1:1984/api/frame.jpeg?src=rack_entryway
    #   stream: http://127.0.0.1:1984/api/stream.mjpeg?src=rack_entryway
    #   rtsp:   rtsp://127.0.0.1:8554/rack_entryway
    services.go2rtc = mkIf cfg.enableGo2rtc {
      enable = true;
      settings = {
        api.listen = "127.0.0.1:1984";
        rtsp.listen = "127.0.0.1:8554";
        ffmpeg.bin = lib.getExe pkgs.ffmpeg-headless;
        streams = {
          # Primary entryway — Logitech BRIO on rook USB (promoted from printer)
          # MJPEG capture; software path (6600K — no fragile #hardware dependency)
          rack_entryway = "ffmpeg:device?video=${cfg.brioDevice}&input_format=mjpeg&video_size=1280x720";
          entryway = "ffmpeg:device?video=${cfg.brioDevice}&input_format=mjpeg&video_size=1280x720";
          # Elon / printer — C200 upside-down. Set RTSP after cam is on LAN:
          # elon = "rtsp://USER:PASS@IP:554/stream1";
          # Prefer Tapo app Rotate 180; or elon_flip with vflip,hflip.
        };
      };
    };

    services.udev.extraRules = mkIf cfg.enableGo2rtc ''
      SUBSYSTEM=="video4linux", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="085e", GROUP="video", MODE="0660"
    '';

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
          # No latitude / longitude / elevation — set in HA UI (.storage).
          # Keeps residence coords out of public n3k0lai/dotfiles.
          unit_system = cfg.unitSystem;
          time_zone = cfg.timeZone;
          currency = "USD";
          country = "US";
          allowlist_external_dirs = [ "/tmp" ];
        };

        http = {
          server_port = cfg.port;
          use_x_forwarded_for = true;
          trusted_proxies = trustedProxies;
        };

        # MQTT broker settings are NOT valid in configuration.yaml on HA 2022+.
        # Mosquitto still runs locally (services.mosquitto below). Add once in UI:
        #   Settings → Devices & services → MQTT → broker 127.0.0.1 port 1883
        #   (discovery on, no user/pass — allow_anonymous on local listener)
        # Matter is UI → ws://127.0.0.1:<matterPort>/ws

        default_config = { };

        # UI editors write these YAML files under /var/lib/hass. Without the
        # includes, script/automation/scene setup times out ("saved but waiting
        # for setup has timed out" / configuration.yaml parse message).
        # NixOS keeps configuration.yaml as a store symlink; the *include targets*
        # stay writable in the state dir.
        "automation ui" = "!include automations.yaml";
        "script ui" = "!include scripts.yaml";
        "scene ui" = "!include scenes.yaml";

        # Stream/ffmpeg for camera proxy + future RTSP. Patio camera is a
        # config-entry only (Settings → Generic Camera); YAML platform:generic
        # is rejected by HA 2025+ ("Unused YAML configuration for generic").
        ffmpeg = { };
        # Live entry: camera.192_168_68_60 → http://192.168.68.60:8081/{snapshot.jpg,stream.mjpg}

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

    # Writable stubs for HA UI script/automation/scene editors (include targets).
    # Create only if missing so we never clobber user content.
    systemd.tmpfiles.rules = [
      "f /var/lib/hass/automations.yaml 0644 hass hass - {}"
      "f /var/lib/hass/scripts.yaml 0644 hass hass - {}"
      "f /var/lib/hass/scenes.yaml 0644 hass hass - {}"
    ];

    # Ensure HA starts after matter-server when both enabled
    systemd.services.home-assistant = {
      path = [ pkgs.ffmpeg ];
    } // optionalAttrs cfg.enableMatter {
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
