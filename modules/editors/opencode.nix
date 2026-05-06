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

  # Wrapper overlay: before every opencode invocation, ensure the Bun
  # runtime cache has the provider SDK dep that NixOS's read-only store
  # + Bun's installer can't resolve on its own.
  opencodeWrapped = pkgs.opencode.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/opencode \
        --run 'CACHE="$HOME/.cache/opencode"; mkdir -p "$CACHE"; if [ ! -d "$CACHE/node_modules/@ai-sdk/openai-compatible" ]; then ${pkgs.nodejs_22}/bin/npm install --prefix "$CACHE" @ai-sdk/openai-compatible@beta >/dev/null 2>&1 || true; fi'
    '';
  });
in
{
  options.modules.editors.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI AI coding agent with NixOS cache fix";
  };

  config = lib.mkIf cfg.enable {
    # Install the cache-seeding wrapper instead of the stock binary
    environment.systemPackages = [ opencodeWrapped ];
  };
}
