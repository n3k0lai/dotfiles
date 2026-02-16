{ config, lib, ... }:

with lib;

let
  cfg = config.modules.core.ssh;
in
{
  options.modules.core.ssh = {
    enable = mkEnableOption "SSH configuration";
  };

  config = mkIf cfg.enable {
    # SSH agent is already enabled in configuration.nix
    # programs.ssh.startAgent = true;

    # SSH config is now deployed via agenix (see configuration.nix age.secrets.ssh_config)
    # Only symlink the public key here
    home-manager.users.nicho = {
      home.file = {
        ".ssh/id_ed25519.pub".source = ./config/ssh/id_ed25519.pub;
      };
    };
  };
}