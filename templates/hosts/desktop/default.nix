{ pkgs, config, lib, ... }:
{
  imports = [
    ../home.nix
    ./hardware-configuration.nix
  ];

  ## Modules
  modules = {
    desktop = {
      hyprland.enable = true;
      fcitx5.enable = true;
      apps = {
        wofi.enable = true;
        godot.enable = true;
      };
      browsers = {
        default = "opera";
        opera.enable = true;
        firefox.enable = true;
        luakit.enable = true;
      };
      gaming = {
        steam.enable = true;
      };
      media = {
        daw.enable = true;
        documents.enable = true;
        graphics.enable = true;
        mpv.enable = true;
        recording.enable = true;
        spotify.enable = true;
      };
      term = {
        default = "foot";
        foot.enable = true;
      };
      vm = {
        qemu.enable = true;
      };
    };
    dev = {
      node.enable = true;
      go.enable = true;
    };
    editors = {
      default = "emacs";
      emacs.enable = true;
      vim.enable = true;
    };
    shell = {
      direnv.enable = true;
      git.enable    = true;
      tmux.enable   = true;
      fortune.enable = true;
      fish.enable   = true;
    };
    services = {
      ssh.enable = true;
      docker.enable = true;
      # Needed occasionally to help the parental units with PC problems
      # teamviewer.enable = true;
    };
    theme.active = "dracula";
  };


  ## Local config
  programs.ssh.startAgent = true;
  services.openssh.startWhenNeeded = true;

  networking.networkmanager.enable = true;
}