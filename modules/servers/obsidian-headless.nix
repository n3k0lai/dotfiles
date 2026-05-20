{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.obsidian-headless;

  # Wrapper that forces obsidian-headless to always operate inside the canonical vault
  obsidianHeadless = pkgs.writeShellScriptBin "ob" ''
    cd ${config.users.users.hermes.home}/.hermes/workspace/vault && \
    exec ${pkgs.nodejs}/bin/npx --yes obsidian-headless "$@"
  '';
in
{
  options.modules.servers.obsidian-headless = {
    enable = lib.mkEnableOption "Obsidian Headless Sync client";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ obsidianHeadless ];
    users.users.hermes.packages = [ obsidianHeadless ];
  };
}