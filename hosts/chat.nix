# Chat's domain — Nicholai's home server.
# Handles home-scoped data: Obsidian vault, home automation, CouchDB.
# Chat is an OpenClaw AI instance managing the home environment.
#
# Machine: Linux (Tailscale: "chat", 100.114.138.5)
# Agent:   Chat (OpenClaw instance)
# Scope:   Obsidian vault, home automation, CouchDB, local/physical data
#
# Boot checklist:
#   1. Physical access: reconnect Tailscale (tailscale up)
#   2. Apply dotfiles flake (nixos-rebuild switch --flake .#chat)
#   3. Install OpenClaw (npm i -g openclaw)
#   4. Run openclaw configure (wizard)
#   5. Set up Discord bot (clawdbot for chat, app id 1473545693946843136)
#   6. Join wavy gang server
{ config, pkgs, lib, ... }:

{
  imports = [
    # OpenClaw + Grok proxy
    ../modules/servers/clawd.nix
    # Web server (Caddy) for CouchDB proxy
    ../modules/servers/web-chat.nix
    # TODO: enable after hardware config is finalized
    # ../modules/servers/home.nix
  ];

  networking.hostName = "chat";

  # Tailscale for mesh connectivity
  services.tailscale.enable = true;

  # CouchDB for Obsidian sync
  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 5984;
  };

  # SSH for remote management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Firewall — only expose what's needed
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (Caddy)
      443   # HTTPS (Caddy)
    ];
    # Tailscale traffic is trusted
    trustedInterfaces = [ "tailscale0" ];
  };

  # Fail2ban
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };

  system.stateVersion = "23.11";
}
