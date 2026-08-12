# NixOS host: rook
# Personal infrastructure box. Tailscale-only access.
#
# Boot:
#   1. sudo nixos-rebuild switch --flake ~/Code/nix#rook
#   2. sudo tailscale up
{ config, pkgs, lib, ... }:

let
  fortune-zh-module = import ../modules/core/fortune-zh.nix { inherit pkgs; };
in
{
  imports = [
    # Hermes Agent
    ../modules/servers/hermes.nix
    ../modules/editors/opencode.nix
    # Obsidian Headless Sync (official Sync — not LiveSync/CouchDB)
    ../modules/servers/obsidian-headless.nix
    # Svalbard RAID storage
    ../modules/hardware/svalbard.nix
    # Home automation (lights, IoT)
    ../modules/servers/home.nix
    # Droneforge Nimbus hangar (USB on Rook)
    ../modules/servers/hangar.nix
    # Samba NAS sharing
    ../modules/servers/samba.nix
    # Calibre-Web ebook server
    ../modules/servers/lib.nix
    # Stream bouncer — RTMP relay with fallback scene
    ../modules/servers/stream-bouncer.nix
    ../modules/servers/octoprint.nix
    # SuperGrok weekly buckets API for Ene (Tailscale-only)
    ../modules/servers/supergrok-usage-api.nix
  ] ++ lib.optional (builtins.pathExists ./rook-local.nix) ./rook-local.nix;

  networking.hostName = "rook";

  # MagicDNS used to advertise as "chat"; pin Tailscale machine name to match NixOS.
  # (extraSetFlags → systemd tailscaled-set on every boot/switch)
  services.tailscale.extraSetFlags = [ "--hostname=rook" ];

  # A2A: tailnet peer with ene. Tokens in rook_env.age.
  modules.servers.hermes = {
    enable = true;
    envFile = ../modules/servers/secrets/rook_env.age;
    # hermes_ssh_config.age is recipients ene+nicho only until re-encrypted for rook.
    # Without this, agenixInstall fails: "no identity matched any of the recipients".
    enableSshConfig = false;
    a2a = {
      enable = true;
      agentName = "rook";
      publicUrl = "http://rook.bushbaby-mercat.ts.net:9900";
      trustedPeers = [ "ene" ];
      peers.ene = {
        url = "http://ene.bushbaby-mercat.ts.net:9900";
        capabilities = [ "life" "research" ];
        outboundTokenEnv = "A2A_OUTBOUND_TOKEN_ENE";
      };
    };
  };

  # Ene fetches GET /v1/usage/weekly over tailnet (MagicDNS rook.bushbaby-mercat.ts.net:9855)
  modules.servers.supergrokUsageApi = {
    enable = true;
    hostName = "rook";
    port = 9855;
  };

  # Same module as ene: wraps `ob` → obsidian-headless for ~/.hermes/workspace/vault
  modules.servers.obsidian-headless.enable = true;

  modules.editors.opencode.enable = true;
  # grok + nvim + user PATH: users/nicho.nix via configuration-server.nix

  # Home-manager state version (pinned from first HM on this host)
  home-manager.users.nicho.home.stateVersion = "24.11";

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # No WiFi needed on this box
  boot.blacklistedKernelModules = [ "iwlwifi" ];

  # NTFS support for Svalbard
  boot.supportedFilesystems = [ "ntfs" ];

  # Build dependencies
  environment.systemPackages = with pkgs; [
    cmake
    gnumake
    gcc
    ntfs3g
    keychain
    fortune-zh-module.fortune-with-zh
    # Playwright needs a real browser on NixOS (can't use dynamically linked downloads)
    chromium
    # X11 forwarding for headful browser sessions from Kiss
    xorg.xauth
    # Python with Slack SDK — used by AI agent scripts for Slack API access
    (python3.withPackages (ps: [ ps.slack-sdk ]))
    # jackchuka/slackcli v0.3.10 — read-only Slack DM monitoring
    # Built declaratively with Go 1.25 (go.mod patched from 1.26.1)
    # Requires SLACK_USER_TOKEN env var. --read-only flag blocks writes.
    (let
      buildGoModule' = pkgs.buildGoModule.override { go = pkgs.go_1_25; };
    in buildGoModule' {
      pname = "slackcli";
      version = "0.3.10";
      src = pkgs.fetchFromGitHub {
        owner = "jackchuka";
        repo = "slackcli";
        rev = "v0.3.10";
        hash = "sha256-tWNv4HLf9vviKr8LJGBNSMQ/SVCjPd1Pe5XTPzz/BhM=";
      };
      overrideModAttrs = old: {
        preConfigure = (old.preConfigure or "") + ''
          sed -i 's/go 1.26.1/go 1.25.5/' go.mod
        '';
      };
      postPatch = ''
        sed -i 's/go 1.26.1/go 1.25.5/' go.mod
      '';
      vendorHash = "sha256-EGDCn9yYgGKlBMLripo5k2HtjTD8CB9JVE4T18CAtZI=";
    })
    openvpn
    # Azure CLI + DevOps extension — replaces raw curl + PAT for ADO operations
    (azure-cli.withExtensions [ azure-cli.extensions."azure-devops" ])
  ];

  # === OPENVPN ===
  # Staging VPN for internal services.
  # Credentials: /var/lib/hermes/.hermes/vpn/staging/auth.txt
  services.openvpn.servers = {
    staging = {
      config = ''
        remote openvpn.zoomph-staging.com 1194 udp
        remote openvpn.zoomph-staging.com 1194 udp
        remote openvpn.zoomph-staging.com 443 tcp-client
        nobind
        dev tun
        pull
        auth-user-pass /var/lib/hermes/.hermes/vpn/staging/auth.txt
        tls-client
        ca /var/lib/hermes/.hermes/vpn/staging/ca.crt
        cert /var/lib/hermes/.hermes/vpn/staging/cert.crt
        key /var/lib/hermes/.hermes/vpn/staging/key.key
        tls-auth /var/lib/hermes/.hermes/vpn/staging/ta.key 1
        verb 3
        comp-lzo no
        rcvbuf 0
        sndbuf 0
        reneg-sec 604800
        ns-cert-type server
        server-poll-timeout 4
        setenv FORWARD_COMPATIBLE 1
        setenv opt tls-version-min 1.0 or-highest
        setenv PUSH_PEER_INFO
        cipher AES-256-CBC
      '';
      autoStart = true;
    };
  };

  # === NETWORK SECURITY ===
  # Tailscale is the ONLY way in. No public ports except SSH on LAN.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22  # SSH (LAN only — Tailscale handles remote)
    ];
    trustedInterfaces = [ "tailscale0" ];
    checkReversePath = "loose";
  };

  # === SSH ===
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = true;
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "4h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
      factor = "4";
    };
  };

  # === STORAGE ===
  # Svalbard RAID — read-write for Calibre, Plex, Obsidian attachments, media
  hardware.svalbard = {
    enable = true;
  };

  # CouchDB / Obsidian LiveSync removed 2026-07-28 — vault uses paid Obsidian Sync (ob).

  # === HOME AUTOMATION (primary HA + Matter fabric) ===
  # UI: Tailscale-only (8123 not opened on LAN). MQTT :1883 for edge nodes (pati0).
  # Matter server :5580 localhost only — commission via HA UI.
  # Bluetooth: Intel USB 8087:0a2b (hci0) — enabled for BLE commissioning.
  modules.servers.homeAssistant = {
    enable = true;
    port = 8123;
    enableMqtt = true;
    enableMatter = true;
    enableBluetooth = true;
    matterBluetoothCommissioning = true;
    enableWebhookBridge = true;
    # Location: HA UI only (not configuration.yaml / not public git)
    timeZone = "America/New_York";
    unitSystem = "us_customary";
    edgeMqttPeers = [
      "pati0" # patio Pi — edge node (cameras, fans); see hosts/pati0.nix
    ];
  };

  # === DRONEFORGE HANGAR ===
  modules.servers.hangar = {
    enable = true;
    requireConfirmation = true;
  };
  # NOTE: home.nix uses pkgs.home-assistant. Old config had unstable + custom
  # Python overrides for aiohue/aionanoleaf. Re-enable if integrations break.

  # === SAMBA ===
  modules.servers.samba = {
    enable = true;
    sharePath = "/mnt/svalbard";
    shareName = "svalbard";
  };

  # === CALIBRE-WEB ===
  modules.servers.calibre = {
    enable = true;
    libraryPath = "/mnt/svalbard/calibre";
  };

  # Override calibre-web to listen on all interfaces (Tailscale access)
  services.calibre-web.listen.ip = lib.mkForce "0.0.0.0";

  # === CADDY (Tailscale-only reverse proxy) ===
  # Ene handles public-facing Caddy. This is for local Tailscale dashboards.
  # Calibre module may add its own virtualHosts.
  services.caddy = {
    enable = true;
    virtualHosts = {
      # Hermes dashboard — Tailscale only
      ":18780" = {
        extraConfig = ''
          reverse_proxy localhost:9119
        '';
      };
    };
  };

  # === STREAM BOUNCER ===
  # Headless RTMP relay — Kiss/phone → Rook → Twitch (+ X when enabled)
  # Falls back to chat overlay + clips if source drops
  # TODO: Uncomment after `agenix -e` creates these secrets from Kiss
  # age.secrets.twitch_stream_key = {
  #   file = ../modules/servers/secrets/twitch_stream_key.age;
  #   owner = "stream-bouncer";
  # };
  # age.secrets.x_stream_key = {
  #   file = ../modules/servers/secrets/x_stream_key.age;
  #   owner = "stream-bouncer";
  # };

  # === POSTGRES PASSWORD SECRETS (agenix) ===
  # Encrypted in repo, decrypted at runtime to /run/agenix/
  # Create with: cd ~/Code/nix && agenix -e modules/servers/secrets/<name>.age
  # Each file should contain ONLY the password (no newline)
  age.secrets.pg_mesh_password = {
    file = ../modules/servers/secrets/pg_mesh_password.age;
    owner = "postgres";
  };
  age.secrets.pg_mesh_reader_password = {
    file = ../modules/servers/secrets/pg_mesh_reader_password.age;
    owner = "postgres";
  };
  age.secrets.pg_finance_admin_password = {
    file = ../modules/servers/secrets/pg_finance_admin_password.age;
    owner = "postgres";
  };
  age.secrets.pg_personal_admin_password = {
    file = ../modules/servers/secrets/pg_personal_admin_password.age;
    owner = "postgres";
  };
  age.secrets.pg_work_admin_password = {
    file = ../modules/servers/secrets/pg_work_admin_password.age;
    owner = "postgres";
  };

  # Apply rotated passwords on boot from agenix secrets
  systemd.services.pg-password-sync = {
    description = "Sync Postgres role passwords from agenix secrets";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      set -euo pipefail
      PSQL="${pkgs.postgresql_16}/bin/psql"
      apply_password() {
        local role="$1" file="$2"
        if [ -f "$file" ]; then
          local pw
          pw=$(cat "$file")
          $PSQL -c "ALTER ROLE $role WITH PASSWORD '$pw';" 2>/dev/null || true
        fi
      }
      apply_password mesh          /run/agenix/pg_mesh_password
      apply_password mesh_reader   /run/agenix/pg_mesh_reader_password
      apply_password finance_admin /run/agenix/pg_finance_admin_password
      apply_password personal_admin /run/agenix/pg_personal_admin_password
      apply_password work_admin    /run/agenix/pg_work_admin_password
    '';
  };
  services.stream-bouncer = {
    enable = false;  # Disabled until stream key secrets are created
    chatOverlayUrl = "https://chatis.is2511.com/";
    # enableX = true;  # Uncomment when X streaming is ready
    # xStreamKeyFile = config.age.secrets.x_stream_key.path;
  };

  # === POSTGRESQL ===
  # Chat history archive for the AI mesh.
  # Stores: conversations with Nicholai (all agents), scraped Grok/Perplexity/Claude logs
  # Data lives on Svalbard for durability; WAL on NVMe for performance.
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    # NVMe for proper Unix permissions (NTFS on Svalbard can't chmod).
    # We'll use pg_dump to backup to Svalbard periodically.
    dataDir = "/var/lib/postgresql/16";
    settings = {
      # Listen on all interfaces (Tailscale firewall handles access)
      listen_addresses = lib.mkForce "*";
      port = 5432;
      # Performance tuning for 16GB RAM shared with other services
      shared_buffers = "1GB";
      effective_cache_size = "4GB";
      work_mem = "64MB";
      maintenance_work_mem = "256MB";
      # WAL settings
      wal_level = "replica";
      max_wal_size = "2GB";
      # Logging
      log_statement = "ddl";
      log_min_duration_statement = 1000;  # Log slow queries >1s
    };
    # pg_hba: mesh agent access rules loaded from local file at build time
    # Base rules are in pg_hba_mesh.conf (committed, no specific IPs)
    # Per-host specific IPs can be added in pg_hba_mesh.local.conf (gitignored)
    authentication = lib.mkForce (
      let
        baseFile = ../modules/servers/pg_hba_mesh.conf;
        localFile = ../modules/servers/pg_hba_mesh.local.conf;
        base = builtins.readFile baseFile;
        local = if builtins.pathExists localFile then builtins.readFile localFile else "";
      in base + "\n" + local
    );
    # Create databases and roles on first boot
    ensureDatabases = [ "svalbard" ];
    ensureUsers = [
      {
        name = "mesh";
      }
    ];
    # Initial schema setup
    initialScript = pkgs.writeText "pg-init.sql" ''
      -- Mesh agent role (read/write for all agents)
      -- Passwords set manually via psql, not in repo
      GRANT ALL PRIVILEGES ON DATABASE svalbard TO mesh;

      -- Read-only role for queries
      CREATE ROLE mesh_reader WITH LOGIN;

      -- Grant read access
      ALTER DEFAULT PRIVILEGES FOR ROLE mesh IN SCHEMA public
        GRANT SELECT ON TABLES TO mesh_reader;

      -- Chat history table
      CREATE TABLE IF NOT EXISTS conversations (
        id BIGSERIAL PRIMARY KEY,
        agent TEXT NOT NULL,           -- 'ene', 'rook'
        source TEXT NOT NULL,          -- 'hermes', 'grok', 'perplexity', 'claude-web'
        project TEXT,                  -- project name (nullable)
        role TEXT NOT NULL,            -- 'user', 'assistant', 'system'
        content TEXT NOT NULL,
        metadata JSONB DEFAULT '{}',   -- extra fields (model, tokens, etc.)
        timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        session_id TEXT,               -- group messages by session
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      -- Indexes for common queries
      CREATE INDEX IF NOT EXISTS idx_conv_agent ON conversations(agent);
      CREATE INDEX IF NOT EXISTS idx_conv_source ON conversations(source);
      CREATE INDEX IF NOT EXISTS idx_conv_project ON conversations(project);
      CREATE INDEX IF NOT EXISTS idx_conv_timestamp ON conversations(timestamp);
      CREATE INDEX IF NOT EXISTS idx_conv_session ON conversations(session_id);
      CREATE INDEX IF NOT EXISTS idx_conv_content_search ON conversations USING gin(to_tsvector('english', content));

      -- Session metadata table
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        agent TEXT NOT NULL,
        source TEXT NOT NULL,
        project TEXT,
        title TEXT,
        started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ended_at TIMESTAMPTZ,
        metadata JSONB DEFAULT '{}'
      );

      -- Scraped conversation imports tracking
      CREATE TABLE IF NOT EXISTS imports (
        id BIGSERIAL PRIMARY KEY,
        source TEXT NOT NULL,           -- 'grok', 'perplexity', 'claude-web'
        external_id TEXT,               -- ID from the source platform
        project TEXT,
        status TEXT DEFAULT 'pending',  -- 'pending', 'imported', 'failed'
        imported_at TIMESTAMPTZ,
        error TEXT,
        metadata JSONB DEFAULT '{}'
      );
    '';
  };

  # === RESOURCE MANAGEMENT ===
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  system.stateVersion = "24.11";
}
