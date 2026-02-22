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

      # OpenClaw dashboards + private services
      # Tailscale IPs pass through; public access gets basic auth
      "ene.comfy.sh" = {
        extraConfig = ''
          @tailscale remote_ip 100.64.0.0/10
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy localhost:18789
        '';
      };

      "rook.comfy.sh" = {
        extraConfig = ''
          @tailscale remote_ip 100.64.0.0/10
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy 100.95.242.40:18789
        '';
      };

      "chat.comfy.sh" = {
        extraConfig = ''
          @tailscale remote_ip 100.64.0.0/10
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy 100.114.138.5:18789
        '';
      };

      # Home Assistant — proxied to Chat via Tailscale
      "home.comfy.sh" = {
        extraConfig = ''
          @tailscale remote_ip 100.64.0.0/10
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy 100.114.138.5:8123 {
            header_up Host {host}
            header_up X-Forwarded-Proto {scheme}
          }
        '';
      };

      # Calibre-Web (lib) — proxied to Chat via Tailscale
      "lib.comfy.sh" = {
        extraConfig = ''
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy 100.114.138.5:8083
        '';
      };

      # Obsidian LiveSync (wiki) — CouchDB on Chat via Tailscale
      "wiki.comfy.sh" = {
        extraConfig = ''
          basicauth {
            nicholai $2a$14$jUGrOohCVC2HK8TPOtH7YOrX.mnykNfEViaTd8WsTS1Z2DC3EDRMy
          }

          reverse_proxy 100.114.138.5:5984 {
            header_up Host {host}
            header_up X-Forwarded-Proto {scheme}
          }
          header Access-Control-Allow-Origin "*"
          header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, HEAD, OPTIONS"
          header Access-Control-Allow-Headers "accept, authorization, content-type, origin, referer, if-match, if-none-match, etag"
          header Access-Control-Allow-Credentials "true"
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
