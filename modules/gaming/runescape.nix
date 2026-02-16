{ config, lib, pkgs, pkgs-unstable, ... }:

with lib;

let
  cfg = config.modules.gaming.runescape;
in {
  options.modules.gaming.runescape = {
    enable = mkEnableOption "RuneScape with Jagex Launcher support";
  };

  config = mkIf cfg.enable {
    # Enable Wine module
    modules.gaming.wine.enable = true;

    environment.systemPackages = [
      pkgs.runelite
      pkgs-unstable.bolt-launcher  # Not in nixpkgs 24.11, use unstable
    ];
  };
}
