# Artemis — BLE shooting sports telemetry project
# DigitalOcean droplet serving the artemis.bond website
# and hosting dev infrastructure for the React Native platform.
#
# What this VPS does:
#   - Static site hosting (artemis.bond landing page)
#   - Expo web builds (app.artemis.bond)
#   - Postgres for shot telemetry data (local, low-traffic)
#   - GitHub webhook for auto-deploy on push
#   - Claude Code dev environment (orchestrated by Ene via SSH)
#
# What this VPS does NOT do:
#   - Run a JVM (Kotlin runs on-device as BLE layer)
#   - Serve comfy.sh domains (that's ene's job)
#   - Run OpenClaw (Ene manages Artemis as a subordinate)
{ config, pkgs, lib, ... }:

{
  imports = [];

  # --- Identity ---
  networking.hostName = "artemis";

  # --- Networking ---
  # DigitalOcean static IP
  networking.useDHCP = false;
  networking.interfaces.ens3.ipv4.addresses = [
    {
      address = "137.184.149.221";
      prefixLength = 20;
    }
    {
      address = "10.10.0.5";  # DO reserved IP anchor (routes 167.172.1.51 → here)
      prefixLength = 16;
    }
    {
      address = "10.116.0.4";  # DO VPC private IP
      prefixLength = 20;
    }
  ];
  networking.defaultGateway = "137.184.144.1";
  networking.nameservers = [ "67.207.67.2" "67.207.67.3" ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (Caddy redirect)
      443   # HTTPS (Caddy TLS)
    ];
    # Trust Tailscale interface for internal traffic
    interfaces."tailscale0" = {
      allowedTCPPorts = [
        5432  # Postgres (mesh-only, not public)
      ];
    };
  };

  # --- SSH ---
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Ene agent SSH access (for Claude Code orchestration)
  users.users.nicho.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEeEsL4tBtpESb3zDgJADhMRE5jjurVEPgScck0XjMV1 ene@comfy.sh"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+G43Ywb5PT0dJ9UiLQA00BpuXtp8XpsG/Ag0+bvRpY nicholai@comfy.sh"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEY/771JoQwVjyX4rWDguty90/vsw7o3qG9b7ez8YtA3 nicholai@comfy.sh"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZJ90yThhjn8Fh5Gv42Ec7T/yvXPgk+P6+IhqV72/rx JuiceSSH"
  ];

  # --- Security ---
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
      factor = "4";
    };
  };

  # --- DigitalOcean ---
  services.do-agent.enable = true;

  # --- System packages ---
  environment.systemPackages = with pkgs; [
    # Dev tools
    git
    nodejs_22
    nodePackages.npm

    # System
    htop
    ncdu
    jq
  ];

  # --- Caddy (static site + reverse proxy) ---
  services.caddy = {
    enable = true;
    virtualHosts = {
      # Landing page
      "artemis.bond" = {
        extraConfig = ''
          root * /var/www/artemis/site
          file_server
        '';
      };
      # Expo web build + future API
      "app.artemis.bond" = {
        extraConfig = ''
          root * /var/www/artemis/app
          file_server

          # API reverse proxy (when backend exists)
          handle /api/* {
            reverse_proxy localhost:8080
          }

          # GitHub webhook
          handle /webhook {
            reverse_proxy localhost:9000
          }
        '';
      };
    };
  };

  # --- Postgres (shot telemetry data) ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "artemis" ];
    ensureUsers = [
      {
        name = "artemis";
        ensureDBOwnership = true;
      }
    ];
    settings = {
      # Listen on localhost + Tailscale for mesh access
      listen_addresses = lib.mkForce "localhost,100.75.158.50";
      # Tuned for 2GB RAM VPS
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      work_mem = "4MB";
      maintenance_work_mem = "64MB";
    };
    authentication = lib.mkForce ''
      # Local connections
      local all all trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
      # Tailscale mesh (ene agent)
      host  artemis artemis 100.111.1.42/32 md5
    '';
  };

  # --- GitHub webhook auto-deploy ---
  systemd.services.artemis-deploy-webhook = {
    description = "GitHub Webhook for Artemis Platform Deploy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ git nodejs_22 bash ];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs_22}/bin/node /opt/artemis/webhook.js";
      Restart = "always";
      RestartSec = 5;
      User = "nicho";
      Group = "users";
      WorkingDirectory = "/opt/artemis";
      EnvironmentFile = "/opt/artemis/.env";
    };
  };

  # --- Memory optimization ---
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "23.11";
}
