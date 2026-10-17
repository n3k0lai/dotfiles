# modules/servers/build-server.nix
# Rook as the fleet's builder. Three small pieces:
#   1. nix-daemon at idle CPU/IO priority, so builds never starve Home
#      Assistant, Postgres or the stream bouncer.
#   2. Optional remote-builder endpoint via nix.sshServe (user nix-ssh, forced
#      to `nix-daemon --stdio`, no shell). Off until builderKeys is non-empty.
#      Not needed for `nixos-rebuild --build-host nicho@rook`: nicho is already
#      a trusted user (configuration-server.nix).
#   3. Optional nightly timer that builds nixosConfigurations from master.
#      attic-watch-store (modules/servers/attic.nix) pushes the results.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.buildServer;
in
{
  options.modules.servers.buildServer = {
    enable = mkEnableOption "rook build server (low-priority nix-daemon, remote builder, nightly fleet builds)";

    builderKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Root SSH public keys of hosts that use rook via nix.buildMachines. Empty = nix.sshServe off.";
    };

    nightly = {
      enable = mkEnableOption "nightly build of nixosConfigurations from master";
      flake = mkOption {
        type = types.str;
        default = "github:n3k0lai/dotfiles/master";
        description = "Flake to build. The repo is public, so no token is needed.";
      };
      hosts = mkOption {
        type = types.listOf types.str;
        # blade (unstable, offline) and pati0 (aarch64, no binfmt) skipped.
        default = [ "rook" "ene" "kiss" ];
      };
      onCalendar = mkOption {
        type = types.str;
        default = "*-*-* 02:30";
        description = "Before the 04:00 autoUpgrade and 04:31 Forgejo dump.";
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

    (mkIf cfg.nightly.enable {
      systemd.services.nix-fleet-build = {
        description = "Build nixosConfigurations from ${cfg.nightly.flake}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ config.nix.package pkgs.git ];
        environment.HOME = "/var/lib/nix-fleet-build";
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          StateDirectory = "nix-fleet-build"; # out-links = GC roots for the last good build
          Nice = 19;
          IOSchedulingClass = "idle";
          MemoryHigh = "6G"; # evaluation (kiss is the big one) runs in this unit
          TimeoutStartSec = "6h";
        };
        script = ''
          set -uo pipefail
          failed=()
          for h in ${escapeShellArgs cfg.nightly.hosts}; do
            echo "== $h"
            if ! nix build --refresh --no-update-lock-file \
                 "${cfg.nightly.flake}#nixosConfigurations.$h.config.system.build.toplevel" \
                 --out-link "$STATE_DIRECTORY/$h"; then
              failed+=("$h")
            fi
          done
          if [ ''${#failed[@]} -gt 0 ]; then
            echo "failed: ''${failed[*]}"
            exit 1
          fi
        '';
      };
      systemd.timers.nix-fleet-build = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.nightly.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
      };
    })
  ]);
}
