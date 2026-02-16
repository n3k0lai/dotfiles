{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.editors.claude;
in {
  options.modules.editors.claude = {
    enable = mkEnableOption "Claude Code CLI tool";
  };

  config = mkIf cfg.enable {
    # Install Node.js for Claude Code
    environment.systemPackages = with pkgs; [
      nodejs
      nodePackages.npm
    ];

    # Install Claude Code via home-manager activation
    home-manager.users.nicho = {
      home.activation.installClaude = ''
        export PATH="${pkgs.nodejs}/bin:$PATH"
        export NPM_CONFIG_PREFIX="$HOME/.npm-global"
        mkdir -p "$HOME/.npm-global"
        if ! command -v claude &> /dev/null; then
          echo "Installing Claude Code..."
          npm install -g @anthropic-ai/claude-code || echo "Failed to install Claude Code, run manually"
        fi
      '';
    };
  };
}