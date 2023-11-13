{ config, lib, pkgs, ... }:

{
  modules.services.cgit = {
    enable = true;
    domain = "git.idreamof.ryukyu";
    reposDirectory = "/srv/git";
    extraConfig = ''
      robots=noindex, nofollow
      enable-index-owner=0
      enable-http-clone=1
      enable-commit-graph=1
      clone-prefix=https://git.idreamof.ryukyu
    '';
  };

  services.nginx.virtualHosts."git.idreamof.ryukyu" = {
    http2 = true;
    forceSSL = true;
    enableACME = true;
  };
}