# -*- mode: nix -*-
# modules/editors/grokbuild.nix
# Grok CLI (grok + agent) from x.ai — declarative installation & update wrapper.
#
# The official installer lives at https://x.ai/cli/install.sh.
# This module provides:
#   - A `grok-update` command that safely re-runs the installer
#   - Proper PATH + shell integration for Fish (and other shells)
#   - Works on both NixOS and nix-darwin
#
# Usage:
#   modules.editors.grokbuild.enable = true;
#
# After enabling, run `grok-update` to install or upgrade.

{ config, pkgs, lib, ... }:

let
  cfg = config.modules.editors.grokbuild;

  updateScript = pkgs.writeShellScriptBin "grok-update" ''
    set -euo pipefail

    CHANNEL="''${GROK_CHANNEL:-stable}"
    echo "Updating Grok CLI (channel: $CHANNEL)..."

    if [ -n "''${GROK_DEPLOYMENT_KEY:-}" ]; then
      echo "Using GROK_DEPLOYMENT_KEY for auth."
    elif [ -f "$HOME/.grok/auth.json" ]; then
      echo "Using existing ~/.grok/auth.json for auth."
    else
      echo "Warning: no GROK_DEPLOYMENT_KEY or ~/.grok/auth.json found."
      echo "You may need to run 'grok login' after installation."
    fi

    curl -fsSL https://x.ai/cli/install.sh | \
      SHELL=/bin/bash GROK_CHANNEL="$CHANNEL" bash

    echo ""
    echo "Grok CLI updated. Binaries are in ~/.grok/bin/"
    echo "Run 'grok' or 'agent' to start."
  '';

  hmConfig = {
    home.sessionPath = [ "$HOME/.grok/bin" ];

    programs.fish = {
      interactiveShellInit = ''
        # Grok CLI
        fish_add_path --prepend --move $HOME/.grok/bin
      '';
    };
  };

in
{
  options.modules.editors.grokbuild = {
    enable = lib.mkEnableOption "Grok CLI build tool (grok + agent) from x.ai";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ updateScript ];
    })

    # Only apply home-manager config if home-manager is present
    (lib.mkIf (cfg.enable && config ? home-manager) {
      home-manager.users.${config.user.name or config.system.primaryUser or "nicho"} = hmConfig;
    })
  ];
}