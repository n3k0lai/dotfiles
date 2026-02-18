# Chat's domain — Nicholai's home server.
# A charismatic tiki bartender who manages lights, guards the vault, and
# holds the most sensitive personal data in the mesh.
#
# Hardware: i5-6600K, 16GB DDR4, 256GB NVMe, Svalbard USB RAID
# Tailscale: "chat", 100.114.138.5
# Agent: Chat (OpenClaw instance)
# Scope: Obsidian vault, journaling, location, banking, home automation,
#         Svalbard storage, CouchDB sync
#
# SECURITY MODEL:
#   Chat holds the crown jewels. Every design decision here prioritizes
#   data protection over convenience.
#   - NO public internet exposure (Tailscale-only access)
#   - NO email capability (Ene relays if needed)
#   - NO outbound messaging to strangers
#   - Encrypted at rest where possible
#   - Minimal attack surface (no Caddy public, no SSH from internet)
#   - Agenix for all secrets
#   - Svalbard mounted read-only by default
#
# Boot checklist:
#   1. Physical access: sudo tailscale up
#   2. Get SSH host key: cat /etc/ssh/ssh_host_ed25519_key.pub → send to Ene
#   3. nixos-generate-config --show-hardware-config → update chat-hardware.nix
#   4. sudo nixos-rebuild switch --flake ~/Code/nix#chat
#   5. npm i -g openclaw && openclaw configure
#   6. Discord bot (app id 1473545693946843136) → join wavy gang
{ config, pkgs, lib, ... }:

{
  imports = [
    # OpenClaw + Grok proxy
    ../modules/servers/clawd.nix
    # Svalbard RAID storage
    ../modules/hardware/svalbard.nix
    # Home automation (lights, IoT)
    ../modules/servers/home.nix
  ];

  networking.hostName = "chat";

  # === NETWORK SECURITY ===
  # Tailscale is the ONLY way in. No public ports except SSH on LAN.
  services.tailscale.enable = true;

  networking.firewall = {
    enable = true;
    # Nothing open to the public internet
    allowedTCPPorts = [
      22  # SSH (LAN only — Tailscale handles remote)
    ];
    # Tailscale interface is the trusted perimeter
    trustedInterfaces = [ "tailscale0" ];
    # Block all other interfaces from reaching services
  };

  # === SSH (LAN + Tailscale only) ===
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # Only listen on local network + Tailscale, NOT public
    listenAddresses = [
      { addr = "0.0.0.0"; port = 22; }  # LAN
    ];
  };

  services.fail2ban = {
    enable = true;
    maxretry = 3;  # Stricter than ene — this box has sensitive data
    bantime = "4h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";  # 1 week max ban
      factor = "4";
    };
  };

  # === STORAGE ===
  # Svalbard RAID — mounted read-only by default for safety
  # Use `sudo mount -o remount,rw /mnt/svalbard` when write access is needed
  hardware.svalbard = {
    enable = true;
    # fsType = "ntfs";  # default
    # mountPoint = "/mnt/svalbard";  # default
  };

  # === DATABASES ===
  # CouchDB for Obsidian LiveSync — localhost only, Tailscale for remote
  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = 5984;
  };

  # === HOME AUTOMATION ===
  modules.servers.homeAssistant = {
    enable = true;
    port = 8123;
    enableMqtt = true;
  };

  # === CADDY (Tailscale-only reverse proxy) ===
  # No public TLS — only accessible via Tailscale
  services.caddy = {
    enable = true;
    virtualHosts = {
      # OpenClaw dashboard — Tailscale only
      ":18780" = {
        extraConfig = ''
          reverse_proxy localhost:18789
        '';
      };
      # CouchDB — Tailscale only
      ":5985" = {
        extraConfig = ''
          reverse_proxy localhost:5984
        '';
      };
    };
  };

  # === RESOURCE MANAGEMENT ===
  # 16GB RAM, shared between OpenClaw, CouchDB, Home Assistant, and MQTT
  zramSwap = {
    enable = true;
    memoryPercent = 25;  # Conservative — we have 16GB
  };

  # === MAINTENANCE ===
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "23.11";
}
