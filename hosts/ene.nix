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
    # Vanilla Terraria (Steam clients; tailnet :7777)
    ../modules/servers/terra.nix
    # IRC server (Ergo) — Chatterino + Hermes agent mesh
    ../modules/servers/irc.nix
    # Obsidian Headless Sync (for vault access + future MCP)
    ../modules/servers/obsidian-headless.nix
    ../modules/servers/even-g2.nix
    # Forgejo (modules/servers/git.nix) runs on rook now.
    # Pull from rook's Attic cache instead of building locally.
    ../modules/core/nix-cache.nix
    # Private F-Droid repo for my own APKs (tailnet only, tailscale serve)
    ../modules/servers/fdroid-repo.nix
    # TODO: enable when ready
    # ../modules/servers/api.nix
    # wiki.nix / CouchDB LiveSync retired — vault uses official Obsidian Sync (ob)
    # grok + nvim + user PATH: users/nicho.nix via configuration-server.nix
  ] ++ lib.optional (builtins.pathExists ./ene-local.nix) ./ene-local.nix;

  # Machine hostname
  networking.hostName = "ene";

  # MagicDNS used to be ene-1; pin Tailscale machine name to match NixOS (drop -1).
  services.tailscale.extraSetFlags = [ "--hostname=ene" ];

  # ene-only: tiny /tmp tmpfs (~2G on 4G RAM). Shared FD/download-buffer knobs live
  # in configuration-server.nix (ene + rook).
  #
  # - build-dir: hermes npm still builds ui-tui (esbuild); withWeb=false drops the
  #   Vite hermes-web graph. Path must not be under a world-writable parent
  #   (e.g. /var/tmp is 1777) or nix rejects it for security.
  # - max-jobs 1: avoid parallel multi-GB hermes cache copies on this box.
  nix.settings = {
    build-dir = "/var/nix/builds";
    max-jobs = 1;
  };

  # === BUILDS HAPPEN ON ROOK ===
  # ene (2 vCPU / 4 GB / small disk) no longer builds its own system. Deploy
  # from kiss with rook as the build host (docs/rook-build-server.md):
  #   nixos-rebuild switch --flake .#ene --build-host nicho@rook \
  #     --target-host nicho@ene --sudo
  # ene then only receives store paths (or substitutes them from rook's cache).
  modules.core.nixCache.enable = true;

  # Tighter GC than the shared weekly/30d: daily, keep 7 days of generations,
  # and let the daemon free space mid-operation when the disk gets tight.
  nix.gc = {
    dates = lib.mkForce "daily";
    options = lib.mkForce "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;
  nix.settings = {
    min-free = 2 * 1024 * 1024 * 1024; # start GC below 2 GiB free
    max-free = 6 * 1024 * 1024 * 1024; # stop once 6 GiB are free
  };

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

  # Bootstrap note: nix.settings.* updates /etc/nix/nix.conf (used by nix-daemon
  # at startup). The *first* nixos-rebuild after adding/changing these will still
  # use the *old* running daemon config, so large hermes npm builds can hit ENOSPC
  # on /tmp tmpfs and EMFILE ("creating pipe: Too many open files") under old defaults.
  #
  # Full bootstrap sequence (run these, then plain `nixos-rebuild` works forever after):
  #   sudo mkdir -p /var/nix/builds && sudo chmod 755 /var/nix/builds
  #   sudo nixos-rebuild switch --flake .#ene \
  #     --option build-dir /var/nix/builds \
  #     --option max-jobs 1 \
  #     --option max-substitution-jobs 8 \
  #     --option download-buffer-size 268435456
  #
  # After activation, `nix-daemon.service` restarts with the new nix.conf.

  # Discord + SSH CLI only — no web UI / Tailscale Serve / hermes-web build.
  # A2A: tailnet peer with rook. Tokens in hermes_env.age.
  modules.servers.hermes = {
    enable = true;
    dashboard.enable = false;
    tailscaleServe.enable = false;
    withWeb = false;
    a2a = {
      enable = true;
      agentName = "ene";
      publicUrl = "http://ene.bushbaby-mercat.ts.net:9900";
      trustedPeers = [ "rook" ];
      peers.rook = {
        url = "http://rook.bushbaby-mercat.ts.net:9900";
        capabilities = [ "work" "tickets" ];
        outboundTokenEnv = "A2A_OUTBOUND_TOKEN_ROOK";
      };
    };
  };

  # The leftover Ubuntu BOOT partition (vda16, ext4) gets auto-mounted on /boot
  # by systemd-gpt-auto as vfat, fails, and breaks sandboxed units (caddy 226).
  # GRUB (i386-pc) does not use it.
  boot.kernelParams = [ "systemd.gpt_auto=0" ];

  # Grok Bot (Ene) — manages Minecraft and Caddy. Not wheel; minecraft group
  # for /opt/minecraft, systemd-journal for logs, sudo only for these units.
  # No caddy group: it would expose TLS keys in /var/lib/caddy.
  modules.users.grokbot.agents.ene = {
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFUSP6TF/bEUhvh3q9etB25OudbaXEb7snH4wuUIHsK grokbot-ene@box"
    ];
    # fdroid-inbox: scp APKs into /var/lib/fdroid-repo/inbox (no sudo).
    extraGroups = [ "minecraft" "systemd-journal" "fdroid-inbox" ];
    sudoCommands =
      map (verb: "/run/current-system/sw/bin/systemctl ${verb} minecraft.service")
        [ "start" "stop" "restart" "status" ]
      ++ map (verb: "/run/current-system/sw/bin/systemctl ${verb} caddy.service")
        [ "status" "reload" "restart" ];
  };
  modules.servers.obsidian-headless.enable = true;
  modules.servers.terraria.enable = true;
  modules.servers.even-g2.enable = true;

  # Private F-Droid repo: https://ene.bushbaby-mercat.ts.net/fdroid/repo (tailnet only).
  # Grok Bot uploads to /var/lib/fdroid-repo/inbox as grokbot-ene; the ingest re-checks
  # cert pins + versionCode and signs the index. `fdroid-repo-info` prints the fingerprint + QR.
  modules.servers.fdroid-repo.enable = true;
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
