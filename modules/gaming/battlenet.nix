# Battle.net / World of Warcraft — Steam+Proton launcher, WowUp for addons
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.battlenet;
in {
  options.modules.gaming.battlenet = {
    enable = mkEnableOption "Battle.net and World of Warcraft (Steam+Proton, WowUp addons)";
  };

  config = mkIf cfg.enable {
    modules.gaming.steam.enable = true;

    environment.systemPackages = with pkgs; [
      wowup-cf    # addon manager for Retail, Classic Era, and Classic flavors
      winetricks  # one-off prefix fixes if using the Lutris install scripts
    ];
  };
}