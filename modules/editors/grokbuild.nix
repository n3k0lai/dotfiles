# -*- mode: nix -*-
# modules/editors/grokbuild.nix
# Grok CLI (grok + agent) from x.ai — declarative installation & update wrapper.
#
# The official installer lives at https://x.ai/cli/install.sh.
# This module provides:
#   - A `grok-update` command that safely re-runs the installer
#   - Proper PATH handling for ~/.grok/bin
#   - Channel selection (stable / alpha / enterprise)
#
# Usage:
#   modules.editors.grokbuild.enable = true;
#   modules.editors.grokbuild.channel = "stable";   # or "alpha"
#
# After enabling, run `grok-update` to install or upgrade.

{ config, pkgs, lib, ... }:

let
  cfg = config.modules.editors.grokbuild;

  updateScript = pkgs.writeShellScriptBin "grok-update" ''
    set -euo pipefail

    CHANNEL="''${GROK_CHANNEL:-${cfg.channel}}"
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
      GROK_CHANNEL="$CHANNEL" bash

    echo ""
    echo "Grok CLI updated. Binaries are in ~/.grok/bin/"
    echo "Run 'grok' or 'agent' to start."
  '';

in
{
  options.modules.editors.grokbuild = {
    enable = lib.mkEnableOption "Grok CLI build tool (grok + agent) from x.ai";

    channel = lib.mkOption {
      type = lib.types.enum [ "stable" "alpha" "enterprise" ];
      default = "stable";
      description = "Release channel to install from (stable, alpha, or enterprise).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Provide the update command
    environment.systemPackages = [ updateScript ];

    # Ensure ~/.grok/bin is on PATH
    environment.sessionVariables = {
      PATH = [ "$HOME/.grok/bin" ];
    };
  };
}