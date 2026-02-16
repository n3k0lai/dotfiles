{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.greetd;
  sessionData = config.services.displayManager.sessionData.desktops;
in {
  options.modules.desktop.greetd = {
    enable = mkEnableOption "greetd display manager with tuigreet";
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = !config.modules.desktop.sddm.enable;
      message = "greetd and SDDM cannot be enabled simultaneously";
    }];

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = concatStringsSep " " [
            "${pkgs.greetd.tuigreet}/bin/tuigreet"
            "--time"
            "--remember"
            "--remember-user-session"
            "--asterisks"
            "--sessions ${sessionData}/share/wayland-sessions:${sessionData}/share/xsessions"
          ];
          user = "greeter";
        };
      };
    };

    # tuigreet needs to be available system-wide for session listing
    environment.systemPackages = [ pkgs.greetd.tuigreet ];
  };
}
