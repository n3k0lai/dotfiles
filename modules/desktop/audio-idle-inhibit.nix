{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.desktop.audioIdleInhibit;
in {
  options.modules.desktop.audioIdleInhibit = {
    enable = mkEnableOption ''
      Prevent hypridle from DPMS-offing monitors while audio is playing.

      Uses sway-audio-idle-inhibit to hold a systemd idle inhibitor while
      PipeWire has active playback. Hypridle stops the inhibitor on lock so
      the bedtime flow (lock + walk away → DPMS) still works.
    '';
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.desktop.hyprland.enable;
        message = "modules.desktop.audioIdleInhibit requires modules.desktop.hyprland to be enabled.";
      }
    ];

    environment.systemPackages = [ pkgs.sway-audio-idle-inhibit ];
  };
}