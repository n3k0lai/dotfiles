# My server in the data center. Currently a DigitalOcean droplet.
{ config, pkgs, lib, ... }:

{
  imports = [
    # Web server (Caddy)
    ../modules/servers/web.nix
    # Clawd chatbot/AI (Ene)
    ../modules/servers/clawd.nix
    # Minecraft server
    ../modules/servers/minecraft.nix
    # TODO: enable when ready
    # ../modules/servers/git.nix
    # ../modules/servers/api.nix
    # ../modules/servers/wiki.nix
  ];

  # Machine hostname
  networking.hostName = "ene";

  # Boot configuration for DigitalOcean virtio
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  # Networking
  networking.useDHCP = lib.mkDefault true;

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

  # Memory optimization for low-RAM VPS
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "25.05";
}
