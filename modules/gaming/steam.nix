{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.steam;
in
{
  options.modules.gaming.steam = {
    enable = mkEnableOption "Steam gaming platform with gamemode";
    
    enableRemotePlay = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open firewall for Steam Remote Play";
    };
  };

  config = mkIf cfg.enable {
    # Assert GPU is configured (optional but recommended)
    assertions = [
      {
        assertion = config.hardware.graphics.enable or false;
        message = "Steam gaming requires hardware.graphics to be enabled";
      }
    ];

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = cfg.enableRemotePlay;
    };
    
    programs.gamemode.enable = true;
    hardware.steam-hardware.enable = true;
    
    # Steam and gaming-related packages for users
    environment.systemPackages = with pkgs; [
      gamescope
      mangohud
      protonup-qt
      lutris
      vulkan-tools
      vulkan-loader
    ];
  };
}
