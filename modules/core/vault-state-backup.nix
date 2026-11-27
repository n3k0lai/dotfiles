# modules/core/vault-state-backup.nix
# Snapshot vault JSON/YAML (Obsidian Sync does not carry these) into a
# staging git repo on kiss and push it to private rook Forgejo plus a
# bare repo on ene. The Obsidian vault itself stays gitless.
#
# Enabled from configuration.nix (kiss-only in flake.nix). Do not add this
# to hosts/kiss.nix. The ene bare repo is created by the script over the
# existing `ene` SSH host; no hosts/ene.nix change is required.
#
# Not managed here (already on kiss, kept off the store):
#   ~/.config/rook-git/token   Forgejo token for user `ene` (mode 600)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.vaultStateBackup;
  deps = with pkgs; [ bash git rsync openssh curl jq coreutils util-linux gnugrep gawk ];
  backup = pkgs.writeShellScriptBin "vault-state-backup" ''
    export PATH=${makeBinPath deps}:$PATH
    exec ${pkgs.bash}/bin/bash ${../../scripts/vault-state-backup.sh} "$@"
  '';
in
{
  options.modules.core.vaultStateBackup = {
    enable = mkEnableOption "periodic backup of vault JSON/YAML to rook git and ene";

    user = mkOption {
      type = types.str;
      default = "nicho";
      description = "User whose vault, SSH key and Forgejo token the backup uses.";
    };

    schedule = mkOption {
      type = types.str;
      default = "00/4:15";
      description = "systemd OnCalendar expression (default: every 4 hours at :15, ahead of rook-git-sync at :30).";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.${cfg.user} = {
      home.packages = [ backup ];

      systemd.user.services.vault-state-backup = {
        Unit = {
          Description = "Commit vault JSON/YAML and push to rook git and ene";
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${backup}/bin/vault-state-backup";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

      systemd.user.timers.vault-state-backup = {
        Unit.Description = "Back up vault JSON/YAML every 4 hours";
        Timer = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = "5min";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
