# Vanilla Terraria dedicated server (nixpkgs services.terraria).
# Clients: stock Steam Terraria on kiss. No tModLoader / Calamity.
#
# After deploy:
#   Console:  sudo -u terraria tmux -S /opt/terraria/terraria.sock attach
#             (C-b d to detach)
#   Join:     ene:7777 (MagicDNS)  (tailnet only)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.servers.terraria;
in
{
  options.modules.servers.terraria = {
    enable = mkEnableOption "Vanilla Terraria dedicated server";

    dataDir = mkOption {
      type = types.str;
      default = "/opt/terraria";
      description = "State directory (worlds, tmux socket)";
    };

    worldName = mkOption {
      type = types.str;
      default = "comfy";
      description = "World file stem (written as <dataDir>/worlds/<name>.wld)";
    };

    port = mkOption {
      type = types.port;
      default = 7777;
      description = "Listen port (TCP + UDP)";
    };

    maxPlayers = mkOption {
      type = types.ints.u8;
      default = 8;
    };

    password = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Server password; null for none (tailnet isolation is the gate)";
    };

    autoCreatedWorldSize = mkOption {
      type = types.enum [ "small" "medium" "large" ];
      default = "medium";
    };
  };

  config = mkIf cfg.enable {
    services.terraria = {
      enable = true;
      inherit (cfg) dataDir port maxPlayers password autoCreatedWorldSize;
      worldPath = "${cfg.dataDir}/worlds/${cfg.worldName}.wld";
      openFirewall = false;
      noUPnP = true;
      secure = true;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 2770 terraria terraria -"
      "d ${cfg.dataDir}/worlds 2770 terraria terraria -"
    ];

    users.users.nicho.extraGroups = [ "terraria" ];
    environment.systemPackages = [ pkgs.tmux ];

    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ cfg.port ];
    };
  };
}
