# Wiki/knowledge base server module
# CouchDB backend for Obsidian LiveSync
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.wiki;
in {
  options.modules.servers.wiki = {
    enable = mkEnableOption "Wiki/Obsidian sync server";

    couchdbPort = mkOption {
      type = types.port;
      default = 5984;
      description = "Port for CouchDB";
    };

    couchdbBindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address for CouchDB";
    };
  };

  config = mkIf cfg.enable {
    # CouchDB for Obsidian LiveSync
    services.couchdb = {
      enable = true;
      bindAddress = cfg.couchdbBindAddress;
      port = cfg.couchdbPort;
    };

    # Caddy reverse proxy for CouchDB
    services.caddy.virtualHosts = {
      "${config.networking.hostName}/couchdb" = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.couchdbPort}
        '';
      };
    };
  };
}
