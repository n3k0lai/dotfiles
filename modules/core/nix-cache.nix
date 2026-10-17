# modules/core/nix-cache.nix
# Client side of rook's build server: use the rook Attic cache as a substituter
# and (optionally) rook as a remote builder. Tailnet-only.
#
# The cache public key is created on rook by `attic cache create rook` and is
# not known until then, so `publicKey` defaults to null and the substituter is
# only added once the key is pasted into the default below. Until then this
# module only sets the timeout/fallback knobs, so it is safe to enable early.
{ config, lib, ... }:

with lib;

let
  cfg = config.modules.core.nixCache;
  rookHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKc43hg3+7eZ8JUTNNi+F0k2fjs8nVusG8wcLCj8Xc4A"; # secrets.nix: rook
in
{
  options.modules.core.nixCache = {
    enable = mkEnableOption "rook Attic cache as a Nix substituter";

    url = mkOption {
      type = types.str;
      default = "http://rook.bushbaby-mercat.ts.net:8190/rook";
      description = "Substituter URL (<atticd api-endpoint>/<cache name>).";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      # TODO(after rook deploy): paste the `Public Key:` line from
      # `attic cache info local:rook`, e.g. "rook:AbC...=".
      default = null;
      description = "Cache signing key (rook:...). null = substituter not added yet.";
    };

    remoteBuilder = {
      enable = mkEnableOption "rook as a nix.buildMachines remote builder (needs a root SSH key, see below)";
      hostName = mkOption {
        type = types.str;
        default = "rook.bushbaby-mercat.ts.net";
      };
      sshUser = mkOption {
        type = types.str;
        default = "nix-ssh"; # nix.sshServe user on rook (modules/servers/build-server.nix)
      };
      sshKey = mkOption {
        type = types.str;
        default = "/root/.ssh/nix-remote-builder";
        description = "Root-readable private key whose .pub is in modules.servers.buildServer.builderKeys on rook.";
      };
      maxJobs = mkOption {
        type = types.int;
        default = 4;
      };
      speedFactor = mkOption {
        type = types.int;
        default = 2;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      nix.settings = {
        # If the host is off the tailnet, give up on rook quickly and fall
        # back to cache.nixos.org / local build instead of hanging.
        connect-timeout = mkDefault 5;
        fallback = mkDefault true;
      };
    }

    (mkIf (cfg.publicKey != null) {
      # Appended after cache.nixos.org (Attic advertises priority 41, nixos 40).
      nix.settings.substituters = [ cfg.url ];
      nix.settings.trusted-public-keys = [ cfg.publicKey ];
    })

    (mkIf cfg.remoteBuilder.enable {
      nix.distributedBuilds = true;
      nix.settings.builders-use-substitutes = true;
      nix.buildMachines = [{
        inherit (cfg.remoteBuilder) hostName sshUser sshKey maxJobs speedFactor;
        protocol = "ssh-ng";
        system = "x86_64-linux";
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
      }];
      programs.ssh.knownHosts.rook-builder = {
        hostNames = [ cfg.remoteBuilder.hostName "rook" ];
        publicKey = rookHostKey;
      };
    })
  ]);
}
