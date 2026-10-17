# modules/servers/git.nix
# My backup git server: Forgejo on rook, tailnet-only.
#
# - HTTP on tailscale0 only (port 3000, plain HTTP inside WireGuard). Not via
#   `tailscale serve`: hermes.nix's serve unit runs `tailscale serve reset` on
#   stop, which would wipe any other serve config on the host.
# - git-over-SSH through the system sshd as user `forgejo` (no second sshd).
# - SQLite: rook's Postgres has a hand-managed pg_hba (mkForce) and role
#   activation scripts; SQLite needs none of that for a single-user forge.
# - Data on the NVMe (/var/lib/forgejo). Svalbard is NTFS (no POSIX perms,
#   which git hooks and Forgejo need). Daily `forgejo dump` archives are copied
#   to Svalbard when it is mounted.
# - Pull mirrors of GitHub repos are created in the web UI or API; see
#   docs/rook-build-server.md. This module only enables mirroring.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.git;
  fj = config.services.forgejo;
in
{
  options.modules.servers.git = {
    enable = mkEnableOption "Forgejo git forge (tailnet-only)";

    port = mkOption {
      type = types.port;
      default = 3000;
    };

    domain = mkOption {
      type = types.str;
      default = "rook.bushbaby-mercat.ts.net";
    };

    offloadDir = mkOption {
      type = types.nullOr types.str;
      default = "/mnt/svalbard/backups/forgejo";
      description = "Copy each daily dump here when Svalbard is mounted. null = keep dumps local only.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      services.forgejo = {
        enable = true;
        database.type = "sqlite3";
        lfs.enable = true;
        dump = {
          enable = true;
          type = "tar.zst";
          age = "7d"; # local copies pruned by tmpfiles
        };
        settings = {
          DEFAULT.APP_NAME = "rook git";
          server = {
            DOMAIN = cfg.domain;
            HTTP_ADDR = "0.0.0.0"; # LAN/WAN blocked by firewall; tailscale0 trusted
            HTTP_PORT = cfg.port;
            ROOT_URL = "http://${cfg.domain}:${toString cfg.port}/";
            SSH_DOMAIN = cfg.domain;
            SSH_PORT = 22;
            START_SSH_SERVER = false; # use system sshd
            LANDING_PAGE = "login";
          };
          service = {
            DISABLE_REGISTRATION = true; # admin user created by CLI
            REQUIRE_SIGNIN_VIEW = true; # other tailnet devices/agents see nothing anonymously
          };
          session.COOKIE_SECURE = false; # plain HTTP inside the tailnet
          repository = {
            DEFAULT_PRIVATE = "private";
            DEFAULT_BRANCH = "master";
          };
          mirror = {
            ENABLED = true;
            DEFAULT_INTERVAL = "8h";
            MIN_INTERVAL = "10m";
          };
          actions.ENABLED = false; # CI lives elsewhere for now
          "cron.update_checker".ENABLED = false; # no phoning home
          other.SHOW_FOOTER_VERSION = false;
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

      # `forgejo-cli admin user create ...` etc. with the service's env + user.
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "forgejo-cli" ''
          exec sudo -u ${fj.user} env HOME=${fj.stateDir} \
            FORGEJO_WORK_DIR=${fj.stateDir} FORGEJO_CUSTOM=${fj.customDir} \
            ${getExe fj.package} "$@"
        '')
      ];
    }

    (mkIf (cfg.offloadDir != null) {
      systemd.services.forgejo-dump.unitConfig.OnSuccess = [ "forgejo-dump-offload.service" ];
      systemd.services.forgejo-dump-offload = {
        description = "Copy the latest Forgejo dump to Svalbard";
        serviceConfig = { Type = "oneshot"; Nice = 19; IOSchedulingClass = "idle"; };
        path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils ];
        script = ''
          set -euo pipefail
          mnt=${escapeShellArg config.hardware.svalbard.mountPoint}
          if ! mountpoint -q "$mnt"; then echo "Svalbard not mounted, skipping"; exit 0; fi
          latest=$(ls -1t ${escapeShellArg fj.dump.backupDir}/* 2>/dev/null | head -n1 || true)
          [ -n "$latest" ] || { echo "no dump found"; exit 0; }
          dest=${escapeShellArg cfg.offloadDir}
          mkdir -p "$dest"
          cp --no-preserve=mode,ownership "$latest" "$dest/"
          # keep 14 on Svalbard
          ls -1t "$dest"/* | tail -n +15 | xargs -r rm -f
        '';
      };
    })
  ]);
}
