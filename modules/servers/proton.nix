# ProtonMail Bridge - headless IMAP/SMTP for ene@comfy.sh
# Uses `pass` as keyring backend (required by bridge for session storage).
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
    wantedBy = [ "multi-user.target" ];

    path = with pkgs; [ pass gnupg dbus ];

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
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      ];
    };
  };
}
