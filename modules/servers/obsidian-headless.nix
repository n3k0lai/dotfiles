{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.obsidian-headless;

  # Wrapper that correctly invokes obsidian-headless via npx
  obsidianHeadless = pkgs.writeShellScriptBin "ob" ''
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