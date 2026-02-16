# My home server
{ config, pkgs, lib, ... }:

{
  imports = [
    # Home automation
    ../modules/servers/home.nix
    # Calibre ebook server
    ../modules/servers/lib.nix
    # Obsidian sync (CouchDB)
    ../modules/servers/wiki.nix
    # Samba file sharing
    ../modules/hardware/svalbard.nix
    ../modules/servers/samba.nix
    # Windows VM for work
    ../modules/servers/work-server.nix
  ];

  # Machine hostname
  networking.hostName = "chat";

  # Enable server modules
  modules.servers = {
    homeAssistant.enable = true;
    calibre.enable = true;
    wiki.enable = true;
    samba.enable = true;
    workVm.enable = true;
  };

  # Boot configuration - UEFI
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Caddy reverse proxy - modules add their own virtualHosts
  services.caddy.enable = true;

  # Allow Caddy to use Tailscale HTTPS certificates
  services.tailscale.permitCertUid = "caddy";

  # NVIDIA GTX 1070 drivers
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    open = false;
    nvidiaSettings = true;
  };
  hardware.graphics.enable = true;

  # Docker for containerized services
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Add user to docker group
  users.users.nicho.extraGroups = [ "docker" ];

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP
      443   # HTTPS
      139   # SMB/NetBIOS
      445   # SMB
      8123  # Home Assistant
    ];
    allowedUDPPorts = [
      137   # SMB/NetBIOS
      138   # SMB/NetBIOS
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

  system.stateVersion = "25.05";
}
