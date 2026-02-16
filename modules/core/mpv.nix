# modules/core/mpv.nix
# MPV media player with custom scripts
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.mpv;
in {
  options.modules.core.mpv = {
    enable = mkEnableOption "MPV media player";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      mpv
    ];

    home-manager.users.nicho = {
      # Symlink mpv config for hot-reload
      xdg.configFile."mpv" = {
        source = ./config/mpv;
        recursive = true;
      };
      
      # Alternative: use programs.mpv for declarative config
      # programs.mpv = {
      #   enable = true;
      #   config = {
      #     # your mpv settings here
      #   };
      #   scripts = with pkgs.mpvScripts; [
      #     # mpv scripts from nixpkgs
      #   ];
      # };
    };
  };
}
