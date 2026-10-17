# Grok Bot desktop app. Unfree Electron client from the Cursor release feed.
#
# Usage: import this module and set modules.editors.grok-bot.enable = true.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.grok-bot;
  grok-bot = pkgs.callPackage ./grok-bot/package.nix { };
in
{
  options.modules.editors.grok-bot = {
    enable = mkEnableOption "Grok Bot desktop";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ grok-bot ];

    xdg.mime.enable = true;
    xdg.mime.defaultApplications = {
      "x-scheme-handler/grokbot" = "grok-bot.desktop";
      "x-scheme-handler/sand" = "grok-bot.desktop";
    };
  };
}
