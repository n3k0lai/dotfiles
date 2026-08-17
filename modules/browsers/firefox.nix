# modules/browsers/firefox.nix
# Package only — Firefox owns ~/.mozilla (see README.md).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.browsers.firefox;
in {
  options.modules.browsers.firefox = {
    enable = mkEnableOption "Firefox (default browser, package only)";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.firefox ];
  };
}
