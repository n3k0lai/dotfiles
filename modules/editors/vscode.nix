{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.vscode;
in {
  options.modules.editors.vscode = {
    enable = mkEnableOption "VSCode with extensions and dependencies";
    
    enableInsiders = mkOption {
      type = types.bool;
      default = false;
      description = "Use VSCode Insiders instead of stable";
    };
  };

  config = mkIf cfg.enable {
    # Install VSCode
    environment.systemPackages = [
      (if cfg.enableInsiders then pkgs.vscode-insiders else pkgs.vscode)
    ] ++ (with pkgs; [
      # Emacs Lisp language server support
      eask-cli          # Emacs Lisp development tool & language server
      emacs             # Emacs interpreter for Elisp support
      
      # Development helper tools
      imagemagick
      graphicsmagick
      file
      tree
      htop
      btop
      eza
      bat
      fzf
      zoxide
      delta
      duf
      ncdu
    ]);
    
    # Environment variables for VSCode
    environment.sessionVariables = {
      # Enable Wayland for VSCode
      NIXOS_OZONE_WL = "1";
    };
  };
}
