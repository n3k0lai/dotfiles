{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.rdp = {
    enable = mkEnableOption "Remote desktop (FreeRDP) for work PC access";
  };

  config = mkIf config.modules.work.rdp.enable {
    users.users.nicho.packages = with pkgs; [
      freerdp  # For werk command to connect to Windows PC
    ];
  };
}
