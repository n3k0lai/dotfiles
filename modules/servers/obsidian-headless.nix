{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.obsidian-headless;

  # Practical wrapper using npx until we can lock a specific version with buildNpmPackage
  obsidianHeadless = pkgs.writeShellScriptBin "ob" ''
    exec ${pkgs.nodejs}/bin/npx --yes obsidian-headless@latest ob "$@"
  '';
in
{
  options.modules.servers.obsidian-headless = {
    enable = lib.mkEnableOption "Obsidian Headless Sync client";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ obsidianHeadless ];

    # Make the `ob` command available to the hermes user (the agent)
    users.users.hermes.packages = [ obsidianHeadless ];
  };
}