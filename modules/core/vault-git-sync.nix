# modules/core/vault-git-sync.nix
# Relaxed two-way sync between the kiss Obsidian vault (a git working copy of
# the private repo n3k0lai/vault) and GitHub, via a home-manager user timer.
#
# Every 20 min: git add -A, gitleaks protect --staged (abort on hit), commit as
# nicholai, git pull --rebase, push. On a rebase conflict it aborts the rebase,
# writes Meta/vault-sync-conflict.md and skips runs until that file is deleted.
# Obsidian Sync stays on and remains the source for the files .gitignore
# excludes (mp3s, two large yoga files, workspace*.json).
#
# Enabled from configuration.nix (kiss entry in flake.nix). Does not touch
# hosts/kiss.nix. Check status with: systemctl --user status vault-git-sync
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.vaultGitSync;
  deps = with pkgs; [ bash git gitleaks openssh coreutils util-linux gnugrep hostname ];
  sync = pkgs.writeShellScriptBin "vault-git-sync" ''
    export PATH=${makeBinPath deps}:$PATH
    exec ${pkgs.bash}/bin/bash ${../../scripts/vault-git-sync.sh} "$@"
  '';
in
{
  options.modules.core.vaultGitSync = {
    enable = mkEnableOption "20-minute git sync of the Obsidian vault with n3k0lai/vault";

    user = mkOption {
      type = types.str;
      default = "nicho";
      description = "User whose home-manager config owns the timer.";
    };

    vaultDir = mkOption {
      type = types.str;
      default = "/home/nicho/vault/vault";
      description = "Vault working copy (must already be a git clone of n3k0lai/vault).";
    };

    interval = mkOption {
      type = types.str;
      default = "20min";
      description = "Time between runs.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ sync ];

    home-manager.users.${cfg.user}.systemd.user = {
      services.vault-git-sync = {
        Unit.Description = "Sync Obsidian vault with GitHub (n3k0lai/vault)";
        Service = {
          Type = "oneshot";
          Environment = [ "VAULT_DIR=${cfg.vaultDir}" ];
          ExecStart = "${sync}/bin/vault-git-sync";
          Nice = 15;
          IOSchedulingClass = "idle";
        };
      };
      timers.vault-git-sync = {
        Unit.Description = "Run vault-git-sync every ${cfg.interval}";
        Timer = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.interval;
          RandomizedDelaySec = "60";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
