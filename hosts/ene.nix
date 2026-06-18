# My server in the data center. Currently a DigitalOcean droplet.
{ config, pkgs, lib, ... }:

{
  imports = [
    # Web server (Caddy)
    ../modules/servers/web.nix
    # Hermes Agent (Ene)
    ../modules/servers/hermes.nix
    ../modules/editors/grokbuild.nix
    # ../modules/editors/opencode.nix
    # Minecraft server
    ../modules/servers/minecraft.nix
    # IRC server (Ergo) — Chatterino + OpenClaw agent mesh
    ../modules/servers/irc.nix
    # Obsidian Headless Sync (for vault access + future MCP)
    ../modules/servers/obsidian-headless.nix
    ../modules/servers/even-g2.nix
    # TODO: enable when ready
    # ../modules/servers/git.nix
    # ../modules/servers/api.nix
    # ../modules/servers/wiki.nix
  ] ++ lib.optional (builtins.pathExists ./ene-local.nix) ./ene-local.nix;

  # Machine hostname
  networking.hostName = "ene";

  # Use on-disk build dir (not /tmp tmpfs ~2G) for large hermes npm builds
  # (ui-tui + web share ~900MB npmDeps cache; "make cache writable" + node_modules
  # + vite/esbuild artifacts easily exceed tmpfs during hermes-tui/web derivations).
  # Must be under non-world-writable path (e.g. not directly under /var/tmp which is 1777)
  # or nix complains "Path ... is world-writable ... not allowed for security".
  nix.settings.build-dir = "/var/nix/builds";

  # Pre-create (and on activation) so first builds after setting have the dir.
  systemd.tmpfiles.rules = [
    "d /var/nix 0755 root root - -"
    "d /var/nix/builds 0755 root root - -"
  ];

  # Belt-and-suspenders: ensure the build dir exists *before* any nix builds that
  # might run as part of activation or early services (tmpfiles runs a bit later).
  system.activationScripts.ensure-nix-build-dir = {
    text = ''
      mkdir -p /var/nix/builds
      chmod 755 /var/nix/builds
    '';
    deps = [ "users" "groups" ];
  };

  # Bootstrap note: nix.settings.build-dir updates /etc/nix/nix.conf (used by
  # nix-daemon at startup). The *first* nixos-rebuild after adding/changing this
  # (or similar restricted settings) will still use the *old* running daemon config,
  # so large hermes npm builds (web + tui monorepo cache copies + node_modules + vite)
  # will hit ENOSPC on the tiny /tmp tmpfs (~2G on this 4G RAM box).
  #
  # Full bootstrap sequence (run these, then plain `nixos-rebuild` works forever after):
  #   sudo mkdir -p /var/nix/builds
  #   sudo chmod 755 /var/nix/builds
  #   sudo nixos-rebuild switch --flake .#ene --option build-dir /var/nix/builds --option max-jobs 1
  #
  # (max-jobs 1 prevents tui + web from consuming separate multi-GB cache copies in parallel.)
  # After activation, `nix-daemon.service` is restarted with the new nix.conf containing
  # the build-dir, and systemd-tmpfiles keeps /var/nix/builds around.
  #
  # The /var/nix/builds location is deliberately *not* under /var/tmp (which is 1777
  # world-writable); Nix rejects build-dir under world-writable parents for security.

  modules.servers.hermes = {
    enable = true;
    tailscaleServe.enable = true;
  };
  modules.editors.grokbuild.enable = true;
  modules.servers.obsidian-headless.enable = true;
  modules.servers.even-g2.enable = true;
  # modules.editors.opencode.enable = true;

  environment.systemPackages = with pkgs; [
    obsidian
  ];

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

      # Configure anchor IP for Reserved IP (DigitalOcean requirement)
      # See: https://docs.digitalocean.com/products/networking/reserved-ips/how-to/outbound-traffic/
      FLOATING_IP=$(${pkgs.curl}/bin/curl -sf http://169.254.169.254/metadata/v1/floating_ip/ipv4/ip_address || true)
      if [ -n "$FLOATING_IP" ]; then
        echo "Reserved IP $FLOATING_IP active — configuring anchor IP 10.10.0.6/16"
        ${pkgs.iproute2}/bin/ip addr add 10.10.0.6/16 dev "$INTERFACE" || true
        # Loose mode rp_filter for proper floating IP routing
        echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
        echo 2 > /proc/sys/net/ipv4/conf/"$INTERFACE"/rp_filter
      fi
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

  # Mosh server (UDP 60000–61000; initial handshake still uses SSH)
  programs.mosh.enable = true;

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
