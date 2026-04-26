# Caddy for Rook's home server
# Proxies CouchDB (Obsidian sync) and Hermes gateway
{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;
    virtualHosts = {
      # CouchDB reverse proxy (Obsidian LiveSync)
      # Access via Tailscale: http://rook:5984
      ":80" = {
        extraConfig = ''
          reverse_proxy /db/* localhost:5984
          reverse_proxy localhost:18789
        '';
      };
    };
  };
}
