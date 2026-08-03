# -*- mode: nix -*-
# modules/editors/grokbuild.nix
# Grok CLI from x.ai — system `grok-update` helper.
#
# Usage:
#   modules.editors.grokbuild.enable = true;
#
# Interactive use goes through bin/fish/functions/grok.fish (update-then-run).
# Hermes and non-fish contexts can still call grok-update + ~/.grok/bin/grok.

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
    echo "Run 'grok' (fish) or ~/.grok/bin/grok to start."
  '';

in
{
  options.modules.editors.grokbuild = {
    enable = lib.mkEnableOption "Grok CLI build tool (grok + agent) from x.ai";
  };

  config = lib.mkIf cfg.enable {
    # `grok` itself is bin/fish/functions/grok.fish (update-then-run), deployed
    # via bin/default.nix → ~/.config/fish/functions/.
    environment.systemPackages = [ updateScript ];
  };
}
