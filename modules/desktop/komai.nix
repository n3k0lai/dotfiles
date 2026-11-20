# Komai — native Rust/QML Matrix desktop client (etke.cc, nheko fork).
# Packaged from the upstream x86_64 AppImage; not in nixpkgs as of 2026-11-20.
# Enable on a host, then activate with nixos-rebuild (home-manager is a
# NixOS module here, so there is no rootless home-manager switch).
{
  config,
  lib,
  pkgs,
  pkgs-komai ? pkgs,
  ...
}:

let
  cfg = config.modules.desktop.komai;
  # pkgs-komai is a newer nixpkgs pin (glibc 2.44) passed from the flake.
  # The official AppImage needs glibc >= 2.43; 26.05 still has 2.42.
  komai = pkgs-komai.callPackage ./komai/package.nix { };
in
{
  options.modules.desktop.komai = {
    enable = lib.mkEnableOption "Komai Matrix desktop client";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.nicho = {
      home.packages = [ komai ];
      # Ships the Waves theme; does not select it. Choose "Waves" in Settings.
      xdg.dataFile."komai/themes/waves.yml".source = ./komai/waves.yml;
    };
  };
}
