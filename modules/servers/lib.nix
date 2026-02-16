# Calibre-Web ebook server module
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.calibre;
in {
  options.modules.servers.calibre = {
    enable = mkEnableOption "Calibre-Web ebook server";

    port = mkOption {
      type = types.port;
      default = 8083;
      description = "Port for Calibre-Web interface";
    };

    libraryPath = mkOption {
      type = types.path;
      default = "/mnt/svalbard/Calibre";
      description = "Path to Calibre library";
    };
  };

  config = mkIf cfg.enable {
    services.calibre-web = {
      enable = true;
      listen = {
        ip = "127.0.0.1";
        port = cfg.port;
      };
      options = {
        calibreLibrary = cfg.libraryPath;
        enableBookUploading = true;
        enableBookConversion = true;
      };
    };

    # Caddy reverse proxy for Calibre-Web
    services.caddy.virtualHosts = {
      "${config.networking.hostName}/calibre" = {
        extraConfig = ''
          reverse_proxy localhost:${toString cfg.port}
        '';
      };
    };
  };
}
