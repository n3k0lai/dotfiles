{ config, lib, pkgs, ... }:

with lib;

{
  options.modules.work.rdp = {
    enable = mkEnableOption "Remote desktop (FreeRDP) for work PC access";
  };

  config = mkIf config.modules.work.rdp.enable {
    users.users.nicho.packages = with pkgs; [
      freerdp  # Provides xfreerdp (used by the `werk` fish function)
    ];

    # werk.fish sources /run/agenix/work_creds (WORK_IP / WORK_USR / WORK_PWD).
    age.secrets.work_creds = {
      file = ../core/config/secrets/work_creds.age;
      owner = "nicho";
      mode = "0400";
    };

    # wofi --show drun only lists .desktop files, not fish functions.
    home-manager.users.nicho.xdg.desktopEntries.werk = {
      name = "werk";
      genericName = "Work RDP";
      comment = "RDP session to the work PC (werk.fish)";
      exec = "fish -c werk";
      icon = "preferences-desktop-remote-desktop";
      terminal = false;
      categories = [ "Network" "RemoteAccess" ];
    };
  };
}
