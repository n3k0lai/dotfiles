# Dev mode for hot-reloading configs without nixos-rebuild
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.devMode;
in {
  options.modules.core.devMode = {
    enable = mkEnableOption "dev mode for hot-reloading configs";

    repoPath = mkOption {
      type = types.str;
      default = "/home/nicho/Code/nix";
      description = "Path to the nix config repository";
    };
  };

  # No config here - individual modules check devMode.enable
}
