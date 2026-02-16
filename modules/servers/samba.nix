# Samba file sharing module for Svalbard NAS
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.modules.servers.samba;
in {
  options.modules.servers.samba = {
    enable = mkEnableOption "Samba file sharing for Svalbard NAS";

    sharePath = mkOption {
      type = types.path;
      default = "/mnt/svalbard";
      description = "Path to share via Samba";
    };

    shareName = mkOption {
      type = types.str;
      default = "svalbard";
      description = "Name of the Samba share";
    };
  };

  config = mkIf cfg.enable {
    # Samba file server
    services.samba = {
      enable = true;
      openFirewall = true;

      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "chat";
          "netbios name" = "chat";
          security = "user";  # Replaces deprecated securityType
          "invalid users" = [ "root" ];
          "guest account" = "nobody";
          "map to guest" = "Bad User";
        };

        "${cfg.shareName}" = {
          path = cfg.sharePath;
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "nicho";
          "force user" = "nicho";
          "force group" = "users";
          "create mask" = "0644";
          "directory mask" = "0755";
        };
      };
    };

    # WS-Discovery for Windows network browsing
    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    # Avahi/mDNS for macOS/Linux network discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}
