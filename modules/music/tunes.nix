# modules/music/tunes.nix
# Sync nanoloop .sav files via git
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.music.tunes;
in {
  options.modules.music.tunes = {
    enable = mkEnableOption "tunes repo sync for nanoloop saves";

    repoPath = mkOption {
      type = types.str;
      default = "/home/nicho/Code/tunes";
      description = "Local path for the tunes repository";
    };

    repoUrl = mkOption {
      type = types.str;
      default = "git@github.com:n3k0lai/tunes.git";
      description = "Git remote URL for the tunes repository";
    };
  };

  config = mkIf cfg.enable {
    home-manager.users.nicho = {
      xdg.configFile."fish/functions/tunes-push.fish" = {
        source = ./config/fish/tunes-push.fish;
      };
      xdg.configFile."fish/functions/tunes-pull.fish" = {
        source = ./config/fish/tunes-pull.fish;
      };
    };
  };
}
