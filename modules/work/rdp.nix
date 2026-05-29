{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.rdp = {
    enable = mkEnableOption "Remote desktop (FreeRDP) for work PC access";
  };

  config = mkIf config.modules.work.rdp.enable {
    users.users.nicho.packages = with pkgs; [
      freerdp  # Provides sdl-freerdp (used by `werk` fish function for native Wayland RDP), plus xfreerdp/wlfreerdp
    ];
  };
}
