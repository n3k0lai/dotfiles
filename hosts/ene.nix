# My server in the data center. Currently a DigitalOcean droplet.
{ config, pkgs, lib, ... }:

{
  imports = [
    # Web server (Caddy)
    ../modules/servers/web.nix
    # Hermes Agent (Ene)
    ../modules/servers/hermes.nix
    # ../modules/editors/opencode.nix
    # Minecraft server
    ../modules/servers/minecraft.nix
    # IRC server (Ergo) — Chatterino + OpenClaw agent mesh
    ../modules/servers/irc.nix
    # TODO: enable when ready
    # ../modules/servers/git.nix
    # ../modules/servers/api.nix
    # ../modules/servers/wiki.nix
  ] ++ lib.optional (builtins.pathExists ./ene-local.nix) ./ene-local.nix;

  # Machine hostname
  networking.hostName = "ene";

  modules.servers.hermes.enable = true;
  # modules.editors.opencode.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP
      443   # HTTPS
      25565 # Minecraft
    ];
  };

  # Cloud-init style network configuration from DO metadata API.
  # dhcpcd/systemd-networkd both fail to acquire leases from DO's DHCP
  # in NixOS 25.05. Query metadata directly and configure statically.
  networking.dhcpcd.denyInterfaces = [ "ens3" ];

  systemd.services.do-network-setup = {
    description = "Configure network from DO metadata";
    after = [ "network-pre.target" ];
    before = [ "network.target" "network-online.target" "digitalocean-metadata.service" ];
    wants = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -e
      INTERFACE="ens3"

      # Wait for metadata API (up to 30s)
      for i in $(seq 30); do
        if ${pkgs.curl}/bin/curl -s --max-time 2 http://169.254.169.254/metadata/v1/id >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      IP=$(${pkgs.curl}/bin/curl -sf http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
      NETMASK=$(${pkgs.curl}/bin/curl -sf http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/netmask)
      GATEWAY=$(${pkgs.curl}/bin/curl -sf http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/gateway)

      ${pkgs.iproute2}/bin/ip addr flush dev "$INTERFACE"
      ${pkgs.iproute2}/bin/ip addr add "$IP/$NETMASK" dev "$INTERFACE"
      ${pkgs.iproute2}/bin/ip link set "$INTERFACE" up
      ${pkgs.iproute2}/bin/ip route add default via "$GATEWAY" dev "$INTERFACE" onlink || true
    '';
  };

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Fail2ban for brute force protection
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

  # DigitalOcean monitoring agent
  services.do-agent.enable = true;

  # 7TV emote server (emotes.comfy.sh)
  systemd.services.emote-server = {
    description = "7TV Emote Server for comfy network";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node /home/nicho/bin/emote-server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "nicho";
      Environment = "EMOTE_PORT=9100";
    };
  };

  # Disk swap — 80GB drive, use it
  swapDevices = [ { device = "/swapfile"; size = 8192; } ];

  system.stateVersion = "23.11";
}
