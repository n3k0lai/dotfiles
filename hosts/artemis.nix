# artemis.bond — platform web + marketing static (DigitalOcean)
{ config, pkgs, lib, ... }:

let
  deployPlatform = pkgs.writeShellScriptBin "artemis-deploy-platform" ''
    set -euo pipefail
    PLATFORM_DIR="''${PLATFORM_DIR:-/opt/artemis/platform}"
    DEPLOY_DIR="''${DEPLOY_DIR:-/var/www/artemis/app}"
    cd "$PLATFORM_DIR"
    git pull --ff-only origin main
    npm ci
    npx expo export --platform web
    rsync -a --delete dist/ "$DEPLOY_DIR/"
    echo "Deployed $(git rev-parse --short HEAD) → app.artemis.bond"
  '';

  webhookScript = pkgs.writeShellScriptBin "artemis-deploy-webhook" ''
    exec ${pkgs.nodejs_22}/bin/node /opt/artemis/webhook.js
  '';

in
{
  imports = [] ++ lib.optional (builtins.pathExists ./artemis-local.nix) ./artemis-local.nix;

  networking.hostName = "artemis";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
    interfaces."tailscale0".allowedTCPPorts = [ 5432 ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  age.secrets.artemis-authorized-keys = {
    file = ../modules/servers/secrets/artemis_authorized_keys.age;
    owner = "nicho";
    group = "users";
    mode = "0600";
  };

  system.activationScripts.artemis-authorized-keys = lib.stringAfter [ "users" "groups" "agenixInstall" ] ''
    install -d -m 700 -o nicho -g users /home/nicho/.ssh
    install -m 600 -o nicho -g users ${config.age.secrets.artemis-authorized-keys.path} /home/nicho/.ssh/authorized_keys
  '';

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

  services.do-agent.enable = true;

  environment.systemPackages = with pkgs; [
    git
    nodejs_22
    nodePackages.npm
    rsync
    deployPlatform
    htop
    ncdu
    jq
  ];

  services.caddy = {
    enable = true;
    virtualHosts = {
      "artemis.bond" = {
        extraConfig = ''
          root * /var/www/artemis/site
          file_server
        '';
      };
      "app.artemis.bond" = {
        extraConfig = ''
          root * /var/www/artemis/app
          file_server
          handle /api/* {
            reverse_proxy localhost:8080
          }
          handle /webhook {
            reverse_proxy localhost:9000
          }
        '';
      };
    };
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "artemis" ];
    ensureUsers = [
      { name = "artemis"; ensureDBOwnership = true; }
    ];
    settings = {
      listen_addresses = lib.mkForce "localhost";
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      work_mem = "4MB";
      maintenance_work_mem = "64MB";
    };
    authentication = lib.mkForce ''
      local all all trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';
  };

  # Install webhook listener; deploy body is artemis-deploy-platform
  systemd.services.artemis-deploy-webhook = {
    description = "GitHub Webhook for Artemis Platform Deploy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ git nodejs_22 bash rsync deployPlatform ];
    serviceConfig = {
      ExecStart = "${webhookScript}/bin/artemis-deploy-webhook";
      Restart = "always";
      RestartSec = 5;
      User = "nicho";
      Group = "users";
      WorkingDirectory = "/opt/artemis";
      EnvironmentFile = "/opt/artemis/.env";
    };
  };

  system.activationScripts.artemis-opt = lib.stringAfter [ "users" "groups" ] ''
    mkdir -p /opt/artemis
    chown nicho:users /opt/artemis
    install -m 0644 ${../bin/artemis-webhook.js} /opt/artemis/webhook.js
    ln -sf ${deployPlatform}/bin/artemis-deploy-platform /opt/artemis/deploy-platform.sh
  '';

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "23.11";
}