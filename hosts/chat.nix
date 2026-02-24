# Chat's domain — Nicholai's home server.
# A charismatic tiki bartender who manages lights, guards the vault, and
# holds the most sensitive personal data in the mesh.
#
# Hardware: i5-6600K, 16GB DDR4, 256GB NVMe, Svalbard USB RAID
# GPU: None currently (GTX 970 removed due to boot issues — may return)
# Tailscale: "chat", 100.114.138.5
# Agent: Chat (OpenClaw instance)
# Scope: Obsidian vault, journaling, location, banking, home automation,
#         Svalbard storage, CouchDB sync
#
# SECURITY MODEL:
#   Chat holds the crown jewels. Every design decision here prioritizes
#   data protection over convenience.
#   - NO public internet exposure (Tailscale-only access)
#   - NO email capability (Ene relays if needed)
#   - NO outbound messaging to strangers
#   - Minimal attack surface (Ene runs Caddy public, not us)
#   - CouchDB on all interfaces but firewall blocks public; Tailscale is perimeter
#
# Network topology:
#   Ene (VPS, public Caddy) → Tailscale → Chat (services on Tailscale interface)
#   Obsidian LiveSync (phone) → Ene's Caddy → Tailscale → CouchDB :5984
#
# Boot checklist:
#   1. sudo nixos-rebuild switch --flake ~/Code/nix#chat
#   2. sudo tailscale up
#   3. npm i -g openclaw && openclaw configure
#   4. Discord bot (app id 1473545693946843136) → join wavy gang
{ config, pkgs, lib, ... }:

{
  imports = [
    # OpenClaw + Grok proxy
    ../modules/servers/clawd.nix
    # Svalbard RAID storage
    ../modules/hardware/svalbard.nix
    # Home automation (lights, IoT)
    ../modules/servers/home.nix
    # Samba NAS sharing
    ../modules/servers/samba.nix
    # Calibre-Web ebook server
    ../modules/servers/lib.nix
    # CouchDB/Obsidian wiki sync
    ../modules/servers/wiki.nix
    # Stream bouncer — RTMP relay with fallback scene
    ../modules/servers/stream-bouncer.nix
    ../modules/servers/octoprint.nix
  ];

  networking.hostName = "chat";

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # No WiFi needed on this box
  boot.blacklistedKernelModules = [ "iwlwifi" ];

  # NTFS support for Svalbard
  boot.supportedFilesystems = [ "ntfs" ];

  # Build dependencies (for OpenClaw native modules, etc.)
  environment.systemPackages = with pkgs; [
    cmake
    gnumake
    gcc
    ntfs3g
    # Playwright needs a real browser on NixOS (can't use dynamically linked downloads)
    chromium
    # X11 forwarding for headful browser sessions from Kiss
    xorg.xauth
  ];

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

  # === COUCHDB / OBSIDIAN LIVESYNC ===
  # Wiki module handles CouchDB declaration.
  # We override it here for Chat's specific needs:
  # - Bind 0.0.0.0 so Tailscale interface can reach it (firewall blocks public)
  # - Single node, CORS enabled for LiveSync, require auth
  modules.servers.wiki = {
    enable = true;
    couchdbBindAddress = "0.0.0.0";
  };

  # Additional CouchDB config beyond what the wiki module sets
  services.couchdb = {
    package = pkgs.couchdb3;
    extraConfig = ''
      [couchdb]
      single_node = true

      [chttpd]
      bind_address = 0.0.0.0
      port = 5984
      max_dbs_open = 100

      [httpd]
      enable_cors = true
      bind_address = 0.0.0.0
      port = 5984

      [cors]
      origins = *
      credentials = true
      methods = GET, PUT, POST, HEAD, DELETE
      headers = accept, authorization, content-type, origin, referer, x-csrf-token

      [cluster]
      n = 1
      q = 1

      [chttpd_auth]
      timeout = 600
      require_valid_user = true

      [couch_httpd_auth]
      require_valid_user = true
    '';
  };

  # === HOME AUTOMATION ===
  modules.servers.homeAssistant = {
    enable = true;
    port = 8123;
    enableMqtt = true;
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
  # The wiki and calibre modules add their own virtualHosts to Caddy.
  services.caddy = {
    enable = true;
    virtualHosts = {
      # OpenClaw dashboard — Tailscale only
      ":18780" = {
        extraConfig = ''
          reverse_proxy localhost:18789
        '';
      };
    };
  };

  # === STREAM BOUNCER ===
  # Headless RTMP relay — Kiss/phone → Chat → Twitch (+ X when enabled)
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
    # Deploy /etc/postgresql/pg_hba_mesh.conf on Chat before rebuild
    # Contains: IP-locked role→schema mappings for Tailscale mesh agents
    authentication = lib.mkForce (builtins.readFile ../modules/servers/pg_hba_mesh.conf);
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
        agent TEXT NOT NULL,           -- 'chat', 'ene', 'rook'
        source TEXT NOT NULL,          -- 'openclaw', 'grok', 'perplexity', 'claude-web'
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
