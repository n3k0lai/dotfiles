{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.zoom = {
    enable = mkEnableOption "Zoom video conferencing";
  };

  config = mkIf config.modules.work.zoom.enable {
    users.users.nicho.packages = with pkgs; [
      zoom-us
    ];
  };
}
