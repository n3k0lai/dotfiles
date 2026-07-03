# League of Legends — Moonlight client (Vanguard blocks native Linux)
#
# Requires a Windows host running Sunshine + Riot Client:
#   1. Install Sunshine on Windows
#   2. Install Riot Client + League of Legends
#   3. Open firewall: TCP 47984, 47989, 48010; UDP 47998–48000
#   4. Pair kiss → host from moonlight-qt (PIN at https://<host>:47990)
#   5. Add League as a custom Sunshine app if auto-detection misses it
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.riot;
in {
  options.modules.gaming.riot = {
    enable = mkEnableOption "League of Legends via Moonlight (requires Windows host running Sunshine + Riot Client)";

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Windows Sunshine host hostname or IP (for docs / launcher helper)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      moonlight-qt
    ];
  };
}