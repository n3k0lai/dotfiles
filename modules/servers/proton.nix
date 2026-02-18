# ProtonMail Bridge - headless IMAP/SMTP for ene@comfy.sh
# Uses `pass` as keyring backend (required by bridge for session storage).
# First-time setup:
#   1. sudo nixos-rebuild switch --flake ~/Code/nix
#   2. gpg --batch --gen-key <<EOF
#      %no-protection
#      Key-Type: RSA
#      Key-Length: 2048
#      Name-Real: Ene
#      Name-Email: ene@comfy.sh
#      Expire-Date: 0
#      %commit
#      EOF
#   3. pass init $(gpg --list-keys ene@comfy.sh | grep -A1 pub | tail -1 | tr -d ' ')
#   4. protonmail-bridge --cli → login
#   5. sudo systemctl enable --now protonmail-bridge
{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    protonmail-bridge
    pass
    gnupg
  ];

  programs.gnupg.agent.enable = true;

  systemd.services.protonmail-bridge = {
    description = "ProtonMail Bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = []; # Enable after interactive login

    serviceConfig = {
      User = "nicho";
      Group = "users";
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
      Restart = "always";
      RestartSec = 10;
      Environment = [
        "HOME=/home/nicho"
        "GNUPGHOME=/home/nicho/.gnupg"
        "PASSWORD_STORE_DIR=/home/nicho/.password-store"
      ];
    };
  };
}
