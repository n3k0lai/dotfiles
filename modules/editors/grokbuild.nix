# -*- mode: nix -*-
# modules/editors/grokbuild.nix
# Grok CLI (grok + agent) from x.ai — simple update wrapper.
#
# Usage:
#   modules.editors.grokbuild.enable = true;
#
# After enabling, run `grok-update` to install or upgrade the Grok CLI.

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

in
{
  options.modules.editors.grokbuild = {
    enable = lib.mkEnableOption "Grok CLI build tool (grok + agent) from x.ai";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ updateScript ];
  };
}