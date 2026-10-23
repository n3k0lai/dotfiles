# modules/core/imv.nix
# Wayland image viewer. feh is X11-only and would come up as an XWayland
# client under Hyprland; imv is the tiling-WM viewer with a native Wayland
# window (and an X11 one, if WAYLAND_DISPLAY is unset).
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.imv;
in {
  options.modules.core.imv = {
    enable = mkEnableOption "imv image viewer";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      imv
    ];

    home-manager.users.nicho = {
      xdg.configFile."imv" = {
        source = ./config/imv;
        recursive = true;
      };
    };

    # System mimeapps.list, same option hypr and bspwm use. The locked
    # home-manager has xdg.mimeApps, not xdg.mime.defaultApplications.
    xdg.mime.enable = true;
    xdg.mime.defaultApplications = {
      "image/jpeg" = "imv.desktop";
      "image/png" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/bmp" = "imv.desktop";
      "image/tiff" = "imv.desktop";
      "image/heif" = "imv.desktop";
      "image/heic" = "imv.desktop";
      "image/avif" = "imv.desktop";
      "image/jxl" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
    };
  };
}
