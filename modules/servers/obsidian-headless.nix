{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.obsidian-headless;
  nodePkg = pkgs.nodejs_24;
  hermesHome = config.users.users.hermes.home;

  # Pin PATH so npx-installed bins (#!/usr/bin/env node) use the same Node ABI
  # as npx itself. Without this, hermes' nodejs_24 profile shadows nodejs_22 npx
  # and better-sqlite3 fails with NODE_MODULE_VERSION mismatch.
  obsidianHeadless = pkgs.writeShellScriptBin "ob" ''
    export PATH="${nodePkg}/bin''${PATH:+:}$PATH"
    cd ${hermesHome}/.hermes/workspace/vault && \
    exec ${nodePkg}/bin/npx --yes obsidian-headless "$@"
  '';

  # Warm the npx cache on activation so the first real `ob sync` is not slow/broken.
  obProvision = pkgs.writeShellScriptBin "ob-provision" ''
    set -e
    export HOME=${hermesHome}
    export PATH="${nodePkg}/bin:$PATH"
    cd ${hermesHome}/.hermes/workspace/vault
    ${nodePkg}/bin/npx --yes obsidian-headless --help >/dev/null 2>&1 || true
  '';
in
{
  options.modules.servers.obsidian-headless = {
    enable = lib.mkEnableOption "Obsidian Headless Sync client";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ obsidianHeadless ];
    users.users.hermes.packages = [ obsidianHeadless ];

    system.activationScripts.ob-provision = lib.stringAfter [ "users" "groups" ] ''
      ${obProvision}/bin/ob-provision
    '';
  };
}