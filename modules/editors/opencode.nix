# -*- mode: nix -*-
# modules/editors/opencode.nix
# OpenCode CLI AI coding agent — centralized NixOS integration with cache fix.
#
# Problem: opencode bundles a Bun-based runtime whose internal npm deps
# don't unpack properly on NixOS, causing ProviderInitError on first run.
# Fix: a systemd user service pre-seeds ~/.cache/opencode/node_modules.
# See: https://github.com/opencode-ai/opencode
#
# Usage: import this module and set modules.editors.opencode.enable = true.
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.editors.opencode;

  # Shell script that patches the Bun cache on first login
  cacheFixScript = pkgs.writeShellScript "opencode-cache-fix" ''
    export PATH="${lib.makeBinPath [ pkgs.nodejs_22 pkgs.coreutils pkgs.gnugrep ]}"
    CACHE_DIR="$HOME/.cache/opencode"
    mkdir -p "$CACHE_DIR"

    # Only run if the missing dep isn't already present
    if [ ! -d "$CACHE_DIR/node_modules/@ai-sdk/openai-compatible" ] && \
       [ ! -d "$CACHE_DIR/node_modules/@ai-sdk/openai-compatible@beta" ]; then
      echo "[opencode] Seeding NixOS cache fix for @ai-sdk/openai-compatible..."
      ${pkgs.nodejs_22}/bin/npm install --prefix "$CACHE_DIR" @ai-sdk/openai-compatible@beta 2>/dev/null || true
    fi
  '';
in
{
  options.modules.editors.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI AI coding agent with NixOS cache fix";
  };

  config = lib.mkIf cfg.enable {
    # Make the CLI available globally
    environment.systemPackages = with pkgs; [ opencode ];

    # NixOS-only: systemd user service auto-fixes the Bun cache on login.
    # Non-Linux hosts (Darwin, nix-on-droid) just get the package — they
    # don't hit this dynamically-linked-Bun issue.
    systemd.user.services.opencode-cache-fix = lib.mkIf pkgs.stdenv.isLinux {
      description = "Fix OpenCode npm cache for NixOS";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = cacheFixScript;
      };
      wantedBy = [ "default.target" ];
    };
  };
}
