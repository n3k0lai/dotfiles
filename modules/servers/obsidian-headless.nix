{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.obsidian-headless;
  nodePkg = pkgs.nodejs_24;
  hermesHome = config.users.users.hermes.home;
  vaultPath = "${hermesHome}/.hermes/workspace/vault";

  # ob sync uses pwd — caller MUST cd into the vault first.
  # Pin PATH so npx-installed bins (#!/usr/bin/env node) use the same Node ABI
  # as npx itself. Without this, hermes' nodejs_24 profile shadows npx's node
  # and better-sqlite3 fails with NODE_MODULE_VERSION mismatch.
  obsidianHeadless = pkgs.writeShellScriptBin "ob" ''
    set -euo pipefail
    export PATH="${nodePkg}/bin''${PATH:+:}$PATH"
    vault="${vaultPath}"
    pwd_resolved="$(cd "$(pwd)" && pwd -P)"
    vault_resolved="$(cd "$vault" && pwd -P)"
    if [ "$pwd_resolved" != "$vault_resolved" ]; then
      echo "ob: must run from inside the vault (ob sync uses pwd)" >&2
      echo "ob:   expected: $vault_resolved" >&2
      echo "ob:   got:      $pwd_resolved" >&2
      echo "ob:   try: cd $vault && ob \"\$@\"" >&2
      exit 1
    fi
    if [ -e "$vault/result" ]; then
      echo "ob: refusing — nix build artifact './result' in vault (remove it first)" >&2
      echo "ob:   nixos-rebuild build creates ./result in cwd; never build from the vault" >&2
      exit 1
    fi
    exec ${nodePkg}/bin/npx --yes obsidian-headless "$@"
  '';

  obProvision = pkgs.writeShellScriptBin "ob-provision" ''
    set -e
    export HOME=${hermesHome}
    export PATH="${nodePkg}/bin:$PATH"
    cd ${vaultPath}
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