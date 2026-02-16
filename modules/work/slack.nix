{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.slack = {
    enable = mkEnableOption "Slack communication";
  };

  config = mkIf config.modules.work.slack.enable {
    users.users.nicho.packages = with pkgs; [
      slack
    ];
  };
}
