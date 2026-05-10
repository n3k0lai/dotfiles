# Caddy web server module
# Serves static sites and reverse proxies to services
{ config, pkgs, lib, ... }:

let
  # Static sites fetched from GitHub at build time
  # TODO: fill sha256 hashes (run `nix-prefetch-url --unpack <url>` to get them)
  bruhxd = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "bruhxd";
    rev = "master";
    sha256 = "sha256-sPxIp9ltNBWeXDioqAxiUMQ6+CD2526YB/LJggkkU4s=";
  };

  comfysh = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "comfy.sh";
    rev = "main";
    sha256 = "sha256-X+6bYuF/VVc1GnAZfqigrK8TVxyYemdnuVby1XVrkrw=";
  };
in
{
  services.caddy = {
    enable = true;
    globalConfig = ''
      servers {
        timeouts {
          read_body 120s
        }
      }
    '';
    virtualHosts = {
      # === ACTIVE SITES ===

      "bruhxd.com" = {
        extraConfig = ''
          root * /var/www/bruhxd/dist
          file_server
        '';
      };

      # Hermes dashboards + private services
      # Basic auth with password hash loaded from agenix secret at runtime
      # TODO: migrate to agenix secret file — for now use import from local file
      "ene.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy localhost:9119
        '';
      };

      "rook.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy {$ROOK_TAILSCALE_IP:127.0.0.1}:9119
        '';
      };

      # Home Assistant — proxied to Rook via Tailscale
      "home.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy {$ROOK_TAILSCALE_IP:127.0.0.1}:8123 {
            header_up Host {host}
            header_up X-Forwarded-Proto {scheme}
          }
        '';
      };

      # Calibre-Web (lib) — proxied to Rook via Tailscale
      "lib.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy {$ROOK_TAILSCALE_IP:127.0.0.1}:8083
        '';
      };

      # Obsidian LiveSync (wiki) — CouchDB on Rook via Tailscale
      "wiki.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy {$ROOK_TAILSCALE_IP:127.0.0.1}:5984 {
            header_up Host {host}
            header_up X-Forwarded-Proto {scheme}
          }
          header Access-Control-Allow-Origin "*"
          header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, HEAD, OPTIONS"
          header Access-Control-Allow-Headers "accept, authorization, content-type, origin, referer, if-match, if-none-match, etag"
          header Access-Control-Allow-Credentials "true"
        '';
      };

      # OctoPrint — proxied to Rook via Tailscale
      "factory.comfy.sh" = {
        extraConfig = ''
          import /etc/caddy/auth.conf
          reverse_proxy {$ROOK_TAILSCALE_IP:127.0.0.1}:5000 {
            header_up Host {host}
            header_up X-Forwarded-Proto https
            header_up X-Forwarded-Host {host}
            header_up X-Scheme https
          }
        '';
      };

      # === PLANNED BUT NOT YET LIVE ===
      # Uncomment as DNS records are added and content is ready

      # itsnicholai.fyi — served via GitHub Pages (n3k0lai.github.io)
      # DNS CNAME points to n3k0lai.github.io, GitHub handles TLS

      "comfy.sh" = {
        extraConfig = ''
          root * ${comfysh}
          file_server
        '';
      };

      # "nicho.yoga" = {
      #   extraConfig = ''
      #     root * ${yoga}
      #     file_server
      #   '';
      # };

      # 7TV emote proxy — serves n3k0lai's emote collection
      "emotes.comfy.sh" = {
        extraConfig = ''
          reverse_proxy localhost:9100
        '';
      };

      # "api.itsnicholai.fyi" = {
      #   extraConfig = ''
      #     reverse_proxy localhost:3000
      #   '';
      # };

      # "wiki.itsnicholai.fyi" = {
      #   extraConfig = ''
      #     reverse_proxy localhost:5984
      #   '';
      # };
    };
  };

  # Open ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
