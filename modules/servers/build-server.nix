# modules/servers/build-server.nix
# Rook as the fleet's builder. Three small pieces:
#   1. nix-daemon at idle CPU/IO priority, so builds never starve Home
#      Assistant, Postgres or the stream bouncer.
#   2. Optional remote-builder endpoint via nix.sshServe (user nix-ssh, forced
#      to `nix-daemon --stdio`, no shell). Off until builderKeys is non-empty.
#      Not needed for `nixos-rebuild --build-host nicho@rook`: nicho is already
#      a trusted user (configuration-server.nix).
#   3. Optional scheduled builds of nixosConfigurations from master: rook +
#      ene nightly, kiss weekly. attic-watch-store (modules/servers/attic.nix) pushes the results.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.buildServer;
in
{
  options.modules.servers.buildServer = {
    enable = mkEnableOption "rook build server (low-priority nix-daemon, remote builder, scheduled fleet builds)";

    builderKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Root SSH public keys of hosts that use rook via nix.buildMachines. Empty = nix.sshServe off.";
    };

    fleetBuild = {
      enable = mkEnableOption "scheduled builds of nixosConfigurations from master";
      flake = mkOption {
        type = types.str;
        default = "github:n3k0lai/dotfiles/master";
        description = "Flake to build. The repo is public, so no token is needed.";
      };
      # One oneshot + timer per schedule: nix-fleet-build-<name>.
      # blade (unstable, offline) and pati0 (aarch64, no binfmt) are not built.
      schedules = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            hosts = mkOption { type = types.listOf types.str; };
            onCalendar = mkOption { type = types.str; };
          };
        });
        default = {
          # Small servers: every night, before the 04:31 Forgejo dump.
          nightly = { hosts = [ "rook" "ene" ]; onCalendar = "*-*-* 02:30"; };
          # kiss is big (CUDA etc. is not on cache.nixos.org): once a week,
          # Sunday after the nightly run.
          weekly = { hosts = [ "kiss" ]; onCalendar = "Sun *-*-* 04:00"; };
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      nix.daemonCPUSchedPolicy = "idle";
      nix.daemonIOSchedClass = "idle";
      nix.settings = {
        builders-use-substitutes = true;
        keep-outputs = false;
      };
    }

    (mkIf (cfg.builderKeys != [ ]) {
      nix.sshServe = {
        enable = true;
        protocol = "ssh-ng";
        write = true;
        # Remote builds copy unsigned inputs in, which needs a trusted user.
        # The keys are root keys of our own hosts only.
        trusted = true;
        keys = cfg.builderKeys;
      };
    })

    (mkIf cfg.fleetBuild.enable {
      systemd.services = mapAttrs' (name: sch: nameValuePair "nix-fleet-build-${name}" {
        description = "Build ${concatStringsSep ", " sch.hosts} from ${cfg.fleetBuild.flake} (${name})";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ config.nix.package pkgs.git ];
        environment.HOME = "/var/lib/nix-fleet-build-${name}";
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          # Per-schedule state dir (dynamic UIDs differ per unit); the
          # out-links are GC roots for each host's last good build.
          StateDirectory = "nix-fleet-build-${name}";
          Nice = 19;
          IOSchedulingClass = "idle";
          MemoryHigh = "6G"; # evaluation (kiss is the big one) runs in this unit
          TimeoutStartSec = "8h";
        };
        script = ''
          set -uo pipefail
          failed=()
          # shellcheck disable=SC2043 # a schedule may list a single host
          for h in ${escapeShellArgs sch.hosts}; do
            echo "== $h"
            if ! nix build --refresh --no-update-lock-file \
                 "${cfg.fleetBuild.flake}#nixosConfigurations.$h.config.system.build.toplevel" \
                 --out-link "$STATE_DIRECTORY/$h"; then
              failed+=("$h")
            fi
          done
          if [ ''${#failed[@]} -gt 0 ]; then
            echo "failed: ''${failed[*]}"
            exit 1
          fi
        '';
      }) cfg.fleetBuild.schedules;

      systemd.timers = mapAttrs' (name: sch: nameValuePair "nix-fleet-build-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = sch.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
      }) cfg.fleetBuild.schedules;
    })
  ]);
}
