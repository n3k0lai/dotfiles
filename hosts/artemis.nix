# Artemis - BLE shooting sports telemetry server
# DigitalOcean droplet running the Kotlin engine API + Postgres
{ config, pkgs, lib, ... }:

{
  imports = [
  ];

  # Boot loader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";

  # Machine hostname
  networking.hostName = "artemis";

  # Networking - update when droplet is provisioned
  networking.useDHCP = false;
  networking.interfaces.ens3.ipv4.addresses = [
    {
      address = "137.184.149.221";
      prefixLength = 20;
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
      80    # HTTP
      443   # HTTPS
    ];
  };

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

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

  # DigitalOcean monitoring
  services.do-agent.enable = true;

  environment.systemPackages = with pkgs; [
    git
    nodejs_22
  ];

  # --- Postgres for sensor data ---
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
      listen_addresses = lib.mkForce "localhost";
    };
    authentication = lib.mkForce ''
      # Local
      local all all trust
      host all all 127.0.0.1/32 trust
      host all all ::1/128 trust
    '';
  };

  # Service user
  users.users.artemis = {
    isSystemUser = true;
    group = "artemis";
    home = "/opt/artemis";
    createHome = true;
  };
  users.groups.artemis = {};

  # --- Caddy ---
  services.caddy = {
    enable = true;
    virtualHosts = {
      "artemis.comfy.sh" = {
        extraConfig = ''
          root * /var/www/artemis/dist
          file_server
          handle /api/* {
            reverse_proxy localhost:8080
          }
        '';
      };
    };
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # --- GitHub webhook auto-deploy ---
  # Listens on :9000 for push events, pulls + builds platform
  systemd.services.artemis-deploy-webhook = {
    description = "GitHub Webhook for Artemis Platform Deploy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ git nodejs_22 bash ];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs_22}/bin/node ${../bin/artemis-webhook.js}";
      Restart = "always";
      RestartSec = 5;
      User = "artemis";
      Group = "artemis";
      WorkingDirectory = "/opt/artemis";
      EnvironmentFile = "/opt/artemis/.env";
    };
  };

  # Memory optimization for low-RAM VPS
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "24.11";
}
