{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.vpn = {
    enable = mkEnableOption "OpenVPN (required for work flake)";
  };

  config = mkIf config.modules.work.vpn.enable {
    users.users.nicho.packages = with pkgs; [
      openvpn
    ];
  };
}
