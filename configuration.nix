# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
#
# This configuration is used by the flake for the 'kiss' desktop system.
# Build with: sudo nixos-rebuild switch --flake .#kiss

{ config, lib, pkgs, ... }:
let
  fortune-zh-module = import ./modules/core/fortune-zh.nix { inherit pkgs; };
in
{
  imports =
    [ # Note: hardware-configuration.nix, home-manager, and agenix
      # are now imported via flake.nix

      # User configuration
      ./users/nicho.nix
      
      # Fish shell and scripts
      ./bin/default.nix
      
      # Theme system
      ./modules/desktop/theme/default.nix
      ./modules/desktop/theme/waves.nix
      # ./modules/desktop/theme/ene.nix  # Alternative theme
      
      # System hardening
      ./modules/core/security.nix

      # Dev mode (hot-reload configs)
      ./modules/core/dev-mode.nix

      # Core utilities
      ./modules/core/kitty.nix
      ./modules/core/foot.nix
      ./modules/core/mpv.nix
      ./modules/core/zathura.nix
      ./modules/core/tmux.nix
      ./modules/core/mpd.nix
      ./modules/core/ssh.nix
      
      # Editors
      ./modules/editors/emacs.nix
      ./modules/editors/vscode.nix
      ./modules/editors/claude.nix
      ./modules/editors/android.nix
      
      # Gaming
      ./modules/gaming/steam.nix
      ./modules/gaming/vr.nix
      ./modules/gaming/chatterino.nix
      ./modules/gaming/wine.nix
      ./modules/gaming/runescape.nix

      # Music
      ./modules/music/nanoloop.nix
      ./modules/music/tunes.nix

      # Desktop environment
      ./modules/desktop/hypr.nix
      ./modules/desktop/bspwm.nix
      ./modules/desktop/sddm.nix
      ./modules/desktop/greetd.nix
      
      # Work
      ./modules/work/slack.nix
      ./modules/work/zoom.nix
      ./modules/work/rdp.nix
      ./modules/work/yubi.nix
      ./modules/work/vpn.nix
    ];

  nixpkgs.config.allowUnfree = true;
  # Note: agenix overlay is now provided via flake.nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets = {
    id_ed25519 = {
      file = ./modules/core/config/secrets/id_ed25519.age;
      owner = "nicho";
      path = "/home/nicho/.ssh/id_ed25519";
      mode = "0400";
    };
    ssh_config = {
      file = ./modules/core/config/secrets/ssh_config.age;
      owner = "nicho";
      path = "/home/nicho/.ssh/config";
      mode = "0600";
    };
    work_creds = {
      file = ./modules/core/config/secrets/work_creds.age;
      owner = "nicho";
      mode = "0400";
    };
    user_password = {
      file = ./modules/core/config/secrets/user_password.age;
      owner = "root";
      mode = "0400";
    };
    garmin_email = {
      file = ./modules/core/config/secrets/garmin_email.age;
      owner = "root";
      mode = "0400";
    };
    garmin_password = {
      file = ./modules/core/config/secrets/garmin_password.age;
      owner = "root";
      mode = "0400";
    };
    gdrive_credentials = {
      file = ./modules/core/config/secrets/gdrive_credentials.age;
      owner = "root";
      mode = "0400";
    };
    gdrive_token = {
      file = ./modules/core/config/secrets/gdrive_token.age;
      owner = "root";
      mode = "0400";
    };
  };
  home-manager.backupFileExtension = "hm-bak";
  
  ##################################################################################
  #                        Dev Mode (symlinks to repo for hot-reload)
  modules.core.devMode.enable = true;

  ##################################################################################
  #                        Core Utilities
  modules.core.kitty.enable = true;
  modules.core.foot.enable = true;
  modules.core.mpv.enable = true;
  modules.core.zathura.enable = true;
  modules.core.tmux.enable = true;
  modules.core.ssh.enable = true;
  # modules.core.mpd.enable = true;  # Enable if you use MPD/ncmpcpp
  
  ##################################################################################
  #                        Theme
  modules.desktop.theme.waves.enable = true;
  
  ##################################################################################
  #                        Editors
  modules.editors.emacs.enable = true;
  
  modules.editors.vscode = {
    enable = true;
    enableInsiders = false;
  };
  
  modules.editors.claude.enable = true;
  modules.editors.android.enable = true;
  
  ##################################################################################
  #                        Gaming
  modules.gaming.steam.enable = true;
  modules.gaming.vr.enable = true;
  modules.gaming.chatterino.enable = true;
  modules.gaming.runescape.enable = true;

  ##################################################################################
  #                        Music
  modules.music.nanoloop.enable = true;
  modules.music.tunes.enable = true;

  ##################################################################################
  #                        Desktop
  modules.desktop.hyprland.enable = true;
  modules.desktop.bspwm.enable = true;
  # modules.desktop.sddm.enable = true;  # Replaced by greetd
  modules.desktop.greetd.enable = true;

  ##################################################################################
  #                        Work
  modules.work.slack.enable = true;
  modules.work.zoom.enable = true;
  modules.work.rdp.enable = true;
  modules.work.yubi.enable = true;
  modules.work.vpn.enable = true;
  #################################################################################
  #                      Networking 
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";
  
  #sops.secrets.surfshark-wg = {
  #  sopsFile = ./.ssh/surfshark.yaml;
  #  owner    = config.users.users.nicho.name;
  #  mode     = "0400";
  #};
  
  #networking.wg-quick.interfaces = {
  #  surfshark = {
  #    address = [ "10.14.0.2/16" ];
  #    dns     = [ "162.252.172.57" "149.154.159.92" ];  # Surfshark leak-proof DNS

  #    privateKeyFile = config.sops.secrets.surfshark-wg.path;

  #    peers = [{
  #      publicKey           = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";
  #      allowedIPs          = [ "0.0.0.0/0" "::/0" ];
  #      endpoint            = "162.252.175.111:51820";  # ← Hard-coded New York WireGuard gateway
  #      persistentKeepalive = 25;
  #    }];
  #  };
  #};

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  
  ################################################################################
  #                      Input
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "ter-v24n";
    packages = [ pkgs.terminus_font ];
    keyMap = "us";
  };
  
  # Enable CUPS to print documents.
  # services.printing.enable = true;

  ###############################################################################
  #                        Sound.
  # PipeWire handles all audio (PulseAudio compatibility is via pipewire-pulse)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;
  

  ###############################################################################
  #                       User 
  programs.fish.enable = true;
  users.users.nicho = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "input" ]; # Enable 'sudo' for the user.
    hashedPasswordFile = config.age.secrets.user_password.path;
    shell = pkgs.fish;
    packages = with pkgs; [
      fish
      fortune-zh-module.fortune-with-zh
      firefox
      brave # for usevia.app
      discord
      obs-studio 
      obsidian
      protonmail-desktop
      prismlauncher # minecraft
    ];
  };

  # User-specific home-manager config is now in ./users/nicho.nix
  security.sudo.wheelNeedsPassword = false;
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    git
    age
    # Zed
    zed-editor
    # audio
    alsa-utils
    usbutils
    # utils
    tailscale
    kitty
    ranger
    fastfetch
    # Qt6 dependencies for PrismLauncher
    qt6.qtwayland
    qt6.qtbase
    qt6.qt5compat
    qt6.qtimageformats
    qt6.qtsvg
    libGL
    mesa
    libxkbcommon
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.tailscale.enable = true;
  
  # Enable smartcard/Yubikey support
  services.pcscd.enable = true;
  programs.ssh = {
    #enable = true;  # Now managed by modules.core.ssh
    startAgent = true;
    #matchBlocks = {
    # "github.com" = {
    #   host = "github.com";
    #   identityFile = "~/.ssh/id_ed25519";
    #   identitiesOnly = true;
    #  };
    #};
  };
  programs.git = {
    enable = true;
    lfs.enable = true;
    #userName = "n3k0lai";
    #userEmail = "nicholai@comfy.sh";
    #extraConfig = {
    #  url."git@github.com:".insteadOf = "https://github.com";
    #};
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 
    80 
    443
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.05"; # Did you read the comment?

}

