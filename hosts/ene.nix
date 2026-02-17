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

  # Networking - static IP for DigitalOcean
  # Update these values when migrating to a new droplet
  networking.useDHCP = false;
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "198.199.80.235";  # Droplet public IP
      prefixLength = 24;
    }
    {
      address = "10.10.0.6";  # DO reserved IP anchor
      prefixLength = 16;
    }
  ];
  networking.defaultGateway = "198.199.80.1";
  networking.nameservers = [ "67.207.67.2" "67.207.67.3" ];

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

  system.stateVersion = "23.11";
}
