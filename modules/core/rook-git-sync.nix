# modules/core/rook-git-sync.nix
# Back up core repos to rook git (Forgejo on rook, modules/servers/git.nix) on
# a user timer, so nothing depends on GitHub alone. The script is
# scripts/rook-git-sync.sh: it fetches GitHub plus local clones and pushes
# branches and tags with normal pushes only (no force, no deletes), into
# private repos under the n3k0lai org on rook git.
#
# Not managed here (set up once by hand, kept off the store):
#   ~/.config/rook-git/token   Forgejo token for user `ene` (mode 600)
#   ~/.config/rook-git/repos   optional repo list override (see the script)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.rookGitSync;
  deps = with pkgs; [ bash git openssh curl jq coreutils util-linux gnugrep ];
  sync = pkgs.writeShellScriptBin "rook-git-sync" ''
    export PATH=${makeBinPath deps}:$PATH
    exec ${pkgs.bash}/bin/bash ${../../scripts/rook-git-sync.sh} "$@"
  '';
in
{
  options.modules.core.rookGitSync = {
    enable = mkEnableOption "periodic backup of core repos to rook git";

    user = mkOption {
      type = types.str;
      default = "nicho";
      description = "User whose clones, SSH key and token the sync uses.";
    };

    schedule = mkOption {
      type = types.str;
      default = "00/4:30";
      description = "systemd OnCalendar expression (default: every 4 hours at :30).";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${cfg.user} = { lib, ... }: {
      home.packages = [ sync ];

      systemd.user.services.rook-git-sync = {
        Unit = {
          Description = "Back up core repos to rook git (normal pushes only)";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${sync}/bin/rook-git-sync";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.rook-git-sync = {
        Unit.Description = "Back up core repos to rook git";
        Timer = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = "10min";
        };
        Install.WantedBy = [ "timers.target" ];
      };

      # Drop the hand-installed copies from before this module existed.
      home.activation.rookGitSyncCleanup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        for f in "$HOME/.config/systemd/user/rook-git-sync.service" \
                 "$HOME/.config/systemd/user/rook-git-sync.timer" \
                 "$HOME/.config/systemd/user/timers.target.wants/rook-git-sync.timer" \
                 "$HOME/.local/bin/rook-git-sync"; do
          [ -L "$f" ] && case "$(readlink "$f")" in /nix/store/*) continue;; esac
          rm -f "$f"
        done
      '';
    };
  };
}
