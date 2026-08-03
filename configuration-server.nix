# Shared server configuration for ene + rook (+ artemis).
# This is the server equivalent of configuration.nix for the desktop.
{ config, lib, pkgs, ... }:

{
  # Allow unfree packages (for some monitoring tools if needed)
  nixpkgs.config.allowUnfree = true;

  # Enable flakes + keep rebuilds from dying on EMFILE / full download buffers.
  # Default download-buffer-size is 64MiB; when it fills, nix opens more concurrent
  # fetches until "creating pipe: Too many open files". Applies to ene + rook.
  #
  # trusted-users includes nicho so kiss can `nixos-rebuild --target-host nicho@…`
  # and import locally-built (unsigned) store paths. Without this, remote copy
  # fails with: "cannot add path … because it lacks a signature by a trusted key".
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    download-buffer-size = 268435456; # 256 MiB
    max-substitution-jobs = 8;       # default 16 is FD-heavy during big switches
    trusted-users = [ "root" "nicho" ];
  };

  # Raise FD ceiling for the daemon (client soft limit via PAM below).
  systemd.services.nix-daemon.serviceConfig.LimitNOFILE = lib.mkForce 1048576;
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65536"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "1048576"; }
  ];

  # Garbage collection to keep disk usage low
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  imports = [
    ./modules/core/security.nix
    # nicho's account: CLI tools (grok, nvim, PATH, fish init) — same as kiss
    ./users/nicho.nix
    # fish functions (incl. grok.fish) + conf.d for nicho
    ./bin/default.nix
  ];

  # Agenix secrets configuration
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # Note: Add server-specific secrets here as needed
  # age.secrets = { };

  # Timezone and locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # User configuration (packages / shell env live in users/nicho.nix)
  programs.fish.enable = true;
  home-manager.backupFileExtension = "hm-bak";

  users.users.nicho = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # Example: "ssh-ed25519 AAAAC3... nicho@kiss"
    ];
  };

  # Passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Core system packages
  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    vim
    htop
    tmux
    wget
    curl
    age

    # Network utilities
    tailscale
    dig
    traceroute

    # System monitoring
    btop
    ncdu
    lsof

    # Media tools
    yt-dlp
  ];

  # Tailscale for secure networking
  services.tailscale.enable = true;

  # Automatic security updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;  # Don't auto-reboot, just stage updates
    dates = "04:00";
  };
}
