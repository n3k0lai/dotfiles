# Dev mode for hot-reloading configs without nixos-rebuild.
#
# repoPath is the ONE place that says where the dotfiles checkout lives.
# Everything else derives from it:
#   - mkOutOfStoreSymlink targets in hypr/bspwm/fcitx5 (when enable = true)
#   - $DOTFILES for the fish rebuild helpers (nx, blade, ene, rook, uploads)
#   - /etc/nixos/flake.nix -> <repoPath>/flake.nix, so a bare
#     `sudo nixos-rebuild switch` works from any directory
#     (nixos-rebuild resolves the symlink and uses the hostname as the target)
# Move the repo? Change repoPath and rebuild once with --flake <new path>.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.core.devMode;
in {
  options.modules.core.devMode = {
    enable = mkEnableOption "dev mode for hot-reloading configs";

    repoPath = mkOption {
      type = types.str;
      default = "/home/nicho/dotfiles";
      description = "Absolute path to the dotfiles flake checkout.";
    };

    linkEtcFlake = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Symlink /etc/nixos/flake.nix to the checkout so nixos-rebuild finds
        the flake without --flake, from any working directory.
      '';
    };
  };

  config = {
    environment.sessionVariables.DOTFILES = cfg.repoPath;

    # A string (not a path literal) so it stays a live symlink into the
    # checkout instead of being copied into the store.
    environment.etc."nixos/flake.nix" = mkIf cfg.linkEtcFlake {
      source = "${cfg.repoPath}/flake.nix";
    };
  };
}
