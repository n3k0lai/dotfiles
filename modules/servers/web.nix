# my caddy server module
# either routes to other services or to static sites that are generated
{ config, pkgs, lib, ... }:

let
  # Static sites from GitHub
  portfolio = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "n3k0lai.github.io";
    rev = "master"; # or specific commit
    sha256 = ""; # need to fill this
  };

  yoga = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "yoga";
    rev = "master";
    sha256 = "";
  };

  dating = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "nicho.dating";
    rev = "master";
    sha256 = "";
  };

  bruhxd = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "bruhxd";
    rev = "master";
    sha256 = "";
  };

  blog = pkgs.fetchFromGitHub {
    owner = "n3k0lai";
    repo = "comfy.sh";
    rev = "master";
    sha256 = "";
  };

  nix_install = pkgs.writeTextDir "index.html" ''
    #!/usr/bin/env bash
    set -euo pipefail

    REPO="https://github.com/n3k0lai/nix.git"
    NIX_DIR="$HOME/Code/nix"

    echo "nix.comfy.sh"
    echo "============"
    echo ""

    # detect host type
    HOST=""
    if [ -f /etc/nix-on-droid ]; then
      HOST="droid"
      echo "detected: nix-on-droid (android)"
    elif [ -f /etc/NIXOS ]; then
      HOSTNAME=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "")
      case "$HOSTNAME" in
        kiss|ene|chat) HOST="$HOSTNAME" ;;
        *)
          echo "available hosts: kiss ene chat"
          printf "which host? "
          read -r HOST
          ;;
      esac
      echo "detected: NixOS ($HOST)"
    else
      echo "error: not a NixOS or nix-on-droid system"
      echo "install nix first: https://nixos.org/download"
      exit 1
    fi

    # enable flakes
    mkdir -p "$HOME/.config/nix"
    if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
      echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
      echo "enabled flakes"
    fi

    # install git if missing
    if ! command -v git &>/dev/null; then
      echo "installing git..."
      nix-env -iA nixpkgs.git
    fi

    # clone repo
    if [ -d "$NIX_DIR" ]; then
      echo "repo exists at $NIX_DIR, pulling..."
      git -C "$NIX_DIR" pull --rebase || true
    else
      echo "cloning config..."
      mkdir -p "$HOME/Code"
      git clone "$REPO" "$NIX_DIR"
    fi

    # apply config
    echo ""
    echo "applying $HOST config..."
    if [ "$HOST" = "droid" ]; then
      nix-on-droid switch --flake "$NIX_DIR#droid"
    else
      sudo nixos-rebuild switch --flake "$NIX_DIR#$HOST"
    fi

    # ssh key setup
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
      echo ""
      echo "generating ssh key..."
      mkdir -p "$HOME/.ssh"
      ssh-keygen -t ed25519 -C "$HOST@comfy.sh" -f "$HOME/.ssh/id_ed25519" -N ""
    fi

    # switch remote to ssh
    git -C "$NIX_DIR" remote set-url origin git@github.com:n3k0lai/nix.git

    echo ""
    echo "done. add this key to github:"
    echo ""
    cat "$HOME/.ssh/id_ed25519.pub"
    echo ""
  '';
in
{
  services.caddy = {
    enable = true;
    virtualHosts = {
      "itsnicholai.fyi" = {
        extraConfig = ''
          root * ${portfolio}
          file_server
        '';
      };
      "api.itsnicholai.fyi" = {
        extraConfig = ''
          reverse_proxy localhost:3000
        '';
      };
      "games.comfy.sh" = {
        extraConfig = ''
          reverse_proxy localhost:25565
        '';
      };
      "comfy.sh" = {
        extraConfig = ''
          root * ${blog}
          file_server
        '';
      };
      "nicho.yoga" = {
        extraConfig = ''
          root * ${yoga}
          file_server
        '';
      };
      "nicho.dating" = {
        extraConfig = ''
          root * ${dating}
          file_server
        '';
      };
      "bruhxd.com" = {
        extraConfig = ''
          root * ${bruhxd}
          file_server
        '';
      };
      "ene.comfy.sh" = {
        extraConfig = ''
          reverse_proxy localhost:3001
        '';
      };
      "wiki.itsnicholai.fyi" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      "nix.comfy.sh" = {
        extraConfig = ''
          root * ${nix_install}
          header Content-Type text/plain
          file_server
        '';
      };
    };
  };

  # Open ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}