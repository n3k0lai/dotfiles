# modules/servers/attic.nix
# Attic binary cache (atticd) on rook. Tailnet-only: plain HTTP on tailscale0,
# blocked on LAN/WAN by the host firewall. Narinfos are signed by the cache's own
# keypair (kept in atticd's SQLite DB), so clients verify every path regardless
# of transport.
#
# Storage stays on the NVMe (/var/lib/atticd), not Svalbard: Svalbard is NTFS
# over ntfs-3g/USB, mounted by a oneshot that silently skips if the enclosure is
# absent (atticd would then write into the bare mount point), and Attic's
# hundreds of thousands of small chunk files are a bad fit for FUSE NTFS. Same
# reasoning as Postgres in hosts/rook.nix. GC + retention keep it bounded; the
# small server.db (holds the signing key) is copied to Svalbard nightly.
#
# Secrets (agenix, see secrets.nix):
#   attic_env.age         ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="<base64 RSA PEM>"
#   attic_push_token.age  a JWT from `atticd-atticadm make-token` (push+pull)
# Each part stays off (with an eval warning) until its .age file exists, so
# the repo evaluates before the secrets are created.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.attic;
  envReady = builtins.pathExists cfg.envSecret;
  tokenReady = builtins.pathExists cfg.pushTokenSecret;
  localEndpoint = "http://127.0.0.1:${toString cfg.port}";
in
{
  options.modules.servers.attic = {
    enable = mkEnableOption "Attic binary cache server (tailnet-only)";

    port = mkOption {
      type = types.port;
      default = 8190; # 8080 is taken by mjpg-streamer (octoprint.nix)
      description = "atticd listen port (reachable on tailscale0 only).";
    };

    hostName = mkOption {
      type = types.str;
      default = "rook.bushbaby-mercat.ts.net";
      description = "MagicDNS name clients use; becomes the api-endpoint.";
    };

    cacheName = mkOption {
      type = types.str;
      default = "rook";
      description = "Cache that watch-store pushes into (create it once with `attic cache create`).";
    };

    storagePath = mkOption {
      type = types.str;
      default = "/var/lib/atticd/storage";
      description = "Local chunk storage. Keep it on a POSIX filesystem (not NTFS).";
    };

    retention = mkOption {
      type = types.str;
      default = "30 days";
      description = "Default retention for paths not accessed recently (per-cache override: attic cache configure --retention-period).";
    };

    gcInterval = mkOption {
      type = types.str;
      default = "12 hours";
      description = "How often atticd garbage-collects expired objects.";
    };

    envSecret = mkOption {
      type = types.path;
      default = ./secrets/attic_env.age;
      description = "agenix file with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64.";
    };

    pushTokenSecret = mkOption {
      type = types.path;
      default = ./secrets/attic_push_token.age;
      description = "agenix file with a push-capable Attic token for watch-store.";
    };

    watchStore = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run `attic watch-store`, which pushes every new path in rook's /nix/store
        to the cache: nightly fleet builds, --build-host builds, remote-builder
        jobs. Paths already on cache.nixos.org are skipped by Attic.
      '';
    };

    dbBackupDir = mkOption {
      type = types.nullOr types.str;
      default = "/mnt/svalbard/backups/attic";
      description = "Nightly copy of server.db (holds the cache signing key). null = off. Skipped if Svalbard is not mounted.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      warnings =
        optional (!envReady) "modules.servers.attic: ${baseNameOf cfg.envSecret} missing; atticd stays off. See modules/servers/attic.nix."
        ++ optional (cfg.watchStore && !tokenReady) "modules.servers.attic: ${baseNameOf cfg.pushTokenSecret} missing; attic-watch-store stays off.";

      environment.systemPackages = [ pkgs.attic-client ];
    }

    (mkIf envReady {
      age.secrets.attic_env.file = cfg.envSecret;

      services.atticd = {
        enable = true;
        environmentFile = config.age.secrets.attic_env.path;
        settings = {
          listen = "[::]:${toString cfg.port}";
          api-endpoint = "http://${cfg.hostName}:${toString cfg.port}/";
          # Empty allowed-hosts = accept any Host header; the firewall already
          # limits reachability to the tailnet.
          storage = {
            type = "local";
            path = cfg.storagePath;
          };
          compression.type = "zstd";
          garbage-collection = {
            interval = cfg.gcInterval;
            default-retention-period = cfg.retention;
          };
        };
      };

      # Tailnet only (rook already trusts tailscale0; explicit for other hosts).
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
    })

    (mkIf (envReady && cfg.dbBackupDir != null) {
      systemd.services.atticd-db-backup = {
        description = "Copy atticd server.db (cache signing key) to Svalbard";
        serviceConfig = { Type = "oneshot"; Nice = 19; };
        path = [ pkgs.sqlite pkgs.util-linux pkgs.coreutils pkgs.findutils ];
        script = ''
          set -euo pipefail
          db=/var/lib/private/atticd/server.db
          mnt=${escapeShellArg config.hardware.svalbard.mountPoint}
          if ! mountpoint -q "$mnt"; then echo "Svalbard not mounted, skipping"; exit 0; fi
          [ -f "$db" ] || { echo "no $db yet"; exit 0; }
          dest=${escapeShellArg cfg.dbBackupDir}
          mkdir -p "$dest"
          sqlite3 "$db" ".backup '$dest/server-$(date +%F).db'"
          # keep 14 copies
          ls -1t "$dest"/server-*.db | tail -n +15 | xargs -r rm -f
        '';
      };
      systemd.timers.atticd-db-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = { OnCalendar = "*-*-* 05:10"; Persistent = true; };
      };
    })

    (mkIf (envReady && tokenReady && cfg.watchStore) {
      age.secrets.attic_push_token.file = cfg.pushTokenSecret;

      systemd.services.attic-watch-store = {
        description = "Push new /nix/store paths to the ${cfg.cacheName} Attic cache";
        wantedBy = [ "multi-user.target" ];
        after = [ "atticd.service" "network-online.target" ];
        wants = [ "atticd.service" "network-online.target" ];
        path = [ pkgs.attic-client ];
        environment.HOME = "/var/lib/attic-watch-store";
        serviceConfig = {
          DynamicUser = true;
          StateDirectory = "attic-watch-store";
          LoadCredential = "token:${config.age.secrets.attic_push_token.path}";
          Restart = "always";
          RestartSec = 30;
          Nice = 19;
          IOSchedulingClass = "idle";
        };
        script = ''
          set -euo pipefail
          attic login --set-default local ${localEndpoint} "$(cat "$CREDENTIALS_DIRECTORY/token")"
          exec attic watch-store local:${cfg.cacheName}
        '';
      };
    })
  ]);
}
