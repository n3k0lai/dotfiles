# hlissner-style agenix helpers: identity paths, auto-mapped secrets, CLI wrapper.
# Existing hosts keep decrypting via /etc/ssh/ssh_host_ed25519_key.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.agenix;
  repoRoot = ../..;
  keys = import ../../secrets-keys.nix;
  hostName = config.networking.hostName;
  hostPub = keys.${hostName} or null;

  secretName = n: removeSuffix ".age" (baseNameOf n);

  fromRules = dir: rules:
    let
      fileOf = n: (if dir == null then repoRoot else dir) + "/${n}";
    in
    mapAttrs'
      (n: v:
        nameValuePair (secretName n) ({
          file = fileOf n;
        } // removeAttrs v [ "publicKeys" "armor" ]))
      (filterAttrs (n: v:
        hostPub != null
        && elem hostPub (v.publicKeys or [ ])
        && pathExists (fileOf n)
      ) rules);

  fromDir = dir:
    let rulesFile = "${dir}/secrets.nix";
    in if pathExists rulesFile then fromRules dir (import rulesFile) else { };

  rootSecrets =
    let rulesFile = "${repoRoot}/secrets.nix";
    in if pathExists rulesFile then fromRules null (import rulesFile) else { };

  mapped =
    foldl' (a: b: a // b) rootSecrets (map fromDir cfg.dirs);
in {
  options.modules.agenix = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install the agenix wrapper and auto-map secrets this host can decrypt.";
    };

    hostKey = mkOption {
      type = types.str;
      default = "/etc/ssh/host_ed25519";
      description = "Preferred agenix identity (provision with push-keys). Missing files are skipped.";
    };

    dirs = mkOption {
      type = types.listOf (types.either types.str types.path);
      default = [ ];
      description = "Extra directories that contain a secrets.nix to auto-map into age.secrets.";
    };
  };

  config = mkIf cfg.enable {
    age.identityPaths = [ cfg.hostKey ];

    # Auto-mapped entries only set `file` (plus any extra attrs from secrets.nix).
    # Host modules still set owner/mode/path on the same names, or under hyphenated aliases.
    age.secrets = mapped;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "agenix" ''
        ARGS=( "$@" )
        if [[ "''${ARGS[*]}" != *"--identity"* && "''${ARGS[*]}" != *"-i"* ]]; then
          for hostkey in ${lib.escapeShellArg cfg.hostKey} /etc/ssh/ssh_host_ed25519_key; do
            if [[ -f "$hostkey" ]]; then
              ARGS=( --identity "$hostkey" "''${ARGS[@]}" )
              break
            fi
          done
        fi
        if [[ -z "''${AGENIX_RULES:-}" && -z "''${RULES:-}" && -f ./secrets.nix ]]; then
          export AGENIX_RULES="$PWD/secrets.nix"
        fi
        exec ${pkgs.agenix}/bin/agenix "''${ARGS[@]}"
      '')
      (pkgs.writeShellScriptBin "push-keys" (
        let raw = builtins.readFile ../../bin/push-keys;
        in lib.removePrefix "#!/usr/bin/env bash\n" raw
      ))
    ];
  };
}
