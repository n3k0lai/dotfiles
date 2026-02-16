{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.gaming.wine;
in {
  options.modules.gaming.wine = {
    enable = mkEnableOption "Wine with gaming optimizations";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      wineWowPackages.stagingFull
      winetricks
    ];

    # Wine configuration for gaming
    environment.sessionVariables = {
      # Enable Esync for better performance
      WINEESYNC = "1";
      # Enable Fsync if available
      WINEFSYNC = "1";
    };

    # Ensure required kernel features are enabled for Wine
    boot.kernel.sysctl = {
      # Increase file descriptor limit for Esync
      "fs.file-max" = 524288;
    };

    # Allow users to set higher file limits
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "hard";
        item = "nofile";
        value = "524288";
      }
      {
        domain = "*";
        type = "soft";
        item = "nofile";
        value = "524288";
      }
    ];
  };
}
