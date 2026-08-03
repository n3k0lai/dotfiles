# Caddy for Rook's home server (unused — Rook uses inline caddy in hosts/rook.nix)
# Kept as a sketch for local Tailscale reverse proxies.
{ config, pkgs, lib, ... }:

{
  services.caddy = {
    enable = true;
    virtualHosts = {
      ":80" = {
        extraConfig = ''
          reverse_proxy localhost:18789
        '';
      };
    };
  };
}
