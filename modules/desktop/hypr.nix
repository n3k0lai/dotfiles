{ options, config, lib, pkgs, ... }:

with lib;
with lib.my;
let cfg = config.modules.desktop.hyprland;
    configDir = config.dotfiles.configDir;
in {
  options.modules.desktop.hyprland = {
    enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable {
    modules.theme.onReload.hyprland = ''
      ${pkgs.hyprland}/bin/bspc wm -r
      source $XDG_CONFIG_HOME/hyprland/hyprland
    '';

    environment.systemPackages = with pkgs; [
      lightdm
      dunst
      libnotify
      (waybar.override {
        pulseSupport = true;
        nlSupport = true;
      })
    ];

    services = {
      picom.enable = true;
      redshift.enable = true;
      xserver = {
        enable = true;
        displayManager = {
          defaultSession = "none+hyprland";
          lightdm.enable = true;
          lightdm.greeters.mini.enable = true;
        };
        windowManager.hyprland.enable = true;
      };
    };

    systemd.user.services."dunst" = {
      enable = true;
      description = "";
      wantedBy = [ "default.target" ];
      serviceConfig.Restart = "always";
      serviceConfig.RestartSec = 2;
      serviceConfig.ExecStart = "${pkgs.dunst}/bin/dunst";
    };

    # link recursively so other modules can link files in their folders
    home.configFile = {
      "sxhkd".source = "${configDir}/sxhkd";
      "hyprland" = {
        source = "${configDir}/hypr/hyperland.conf";
        recursive = true;
      };
    };
  };
}