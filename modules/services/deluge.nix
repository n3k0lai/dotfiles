{ config, options, pkgs, lib, my, ... }:

with lib;
with lib.my;
let cfg = config.modules.services.deluge;
in {
  options.modules.services.deluge = {
    enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable {
    services.deluge = {
      enable = true;
      home = "${config.user.home}/torrents";
      settings = {
        incomplete-dir-enabled = true;
        rpc-whitelist = "127.0.0.1,192.168.*.*";
        rpc-host-whitelist = "*";
        rpc-host-whitelist-enabled = true;
        ratio-limit = 0;
        ratio-limit-enabled = true;
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 51413 ];
      allowedUDPPorts = [ 51413 ];
    };

    user.extraGroups = [ "deluge" ];
  };
}