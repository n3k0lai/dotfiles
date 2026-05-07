# My server in the data center. Currently a DigitalOcean droplet.
{ config, pkgs, lib, ... }:

{
  imports = [
    # Web server (Caddy)
    ../modules/servers/web.nix
    # Hermes Agent (Ene)
    ../modules/servers/hermes.nix
    # ../modules/editors/opencode.nix
    # Minecraft server
    ../modules/servers/minecraft.nix
    # ProtonMail Bridge (ene@comfy.sh)
    ../modules/servers/proton.nix
    # IRC server (Ergo) — Chatterino + OpenClaw agent mesh
    ../modules/servers/irc.nix
    # TODO: enable when ready
    # ../modules/servers/git.nix
    # ../modules/servers/api.nix
    # ../modules/servers/wiki.nix
  ] ++ lib.optional (builtins.pathExists ./ene-local.nix) ./ene-local.nix;

  # Machine hostname
  networking.hostName = "ene";

  modules.servers.hermes.enable = true;
  # modules.editors.opencode.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP
      443   # HTTPS
      25565 # Minecraft
    ];
  };

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Fail2ban for brute force protection
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
      factor = "4";
    };
  };

  # DigitalOcean monitoring agent
  services.do-agent.enable = true;

  # 7TV emote server (emotes.comfy.sh)
  systemd.services.emote-server = {
    description = "7TV Emote Server for comfy network";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node /home/nicho/bin/emote-server.js";
      Restart = "on-failure";
      RestartSec = 5;
      User = "nicho";
      Environment = "EMOTE_PORT=9100";
    };
  };

  # Memory optimization for low-RAM VPS
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "23.11";
}
