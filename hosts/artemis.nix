# Artemis - BLE shooting sports telemetry server
# DigitalOcean droplet running the Kotlin engine API + Postgres
{ config, pkgs, lib, ... }:

{
  imports = [
    ../modules/servers/web.nix
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

  # --- JDK for Kotlin engine ---
  environment.systemPackages = with pkgs; [
    temurin-bin-21  # Eclipse Temurin JDK 21 LTS
    gradle
    git
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

  # --- Artemis Engine service ---
  # Runs the Kotlin/Gradle fat jar
  # Build: cd /opt/artemis/engine && gradle shadowJar
  # Output: engine/build/libs/engine-all.jar
  systemd.services.artemis-engine = {
    description = "Artemis Telemetry Engine (Kotlin)";
    after = [ "network.target" "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.temurin-bin-21}/bin/java -jar /opt/artemis/engine/build/libs/engine-all.jar";
      Restart = "always";
      RestartSec = 5;
      User = "artemis";
      Group = "artemis";
      WorkingDirectory = "/opt/artemis";
      EnvironmentFile = "/opt/artemis/.env";
      # Hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "/opt/artemis" ];
    };
  };

  # Service user
  users.users.artemis = {
    isSystemUser = true;
    group = "artemis";
    home = "/opt/artemis";
    createHome = true;
  };
  users.groups.artemis = {};

  # --- Caddy reverse proxy ---
  services.caddy.virtualHosts."artemis.comfy.sh" = {
    extraConfig = ''
      reverse_proxy localhost:8080
    '';
  };

  # Memory optimization for low-RAM VPS
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "24.11";
}
