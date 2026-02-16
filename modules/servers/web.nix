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
    sha256 = "sha256-sPxIp9ltNBWeXDioqAxiUMQ6+CD2526YB/LJggkkU4s="; # placeholder — will fail on first build, nix prints the real hash
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
          root * ${bruhxd}/dist
          file_server
        '';
      };

      # OpenClaw dashboard (Ene)
      "ene.comfy.sh" = {
        extraConfig = ''
          reverse_proxy localhost:18789
        '';
      };

      # === PLANNED BUT NOT YET LIVE ===
      # Uncomment as DNS records are added and content is ready

      # "itsnicholai.fyi" = {
      #   extraConfig = ''
      #     root * ${portfolio}
      #     file_server
      #   '';
      # };

      # "comfy.sh" = {
      #   extraConfig = ''
      #     root * ${blog}
      #     file_server
      #   '';
      # };

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
