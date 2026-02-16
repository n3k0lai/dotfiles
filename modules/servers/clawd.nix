# OpenClaw (Ene) - AI chatbot service
# https://openclaw.ai / https://github.com/n3k0lai/openclaw
{ config, pkgs, lib, ... }:

let
  nodePkg = pkgs.nodejs_22;
in
{
  # Node.js runtime
  environment.systemPackages = with pkgs; [
    nodePkg
    # CLI tools Ene uses
    gog          # Google Workspace CLI (gmail, calendar)
    gh           # GitHub CLI
  ];

  # OpenClaw gateway service
  # Runs as nicho user since it needs access to ~/.openclaw/
  systemd.services.openclaw-gateway = {
    description = "OpenClaw Gateway";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];

    environment = {
      HOME = "/home/nicho";
      GOG_KEYRING_PASSWORD = "openclaw-ene";  # TODO: move to agenix secret
      GOG_ACCOUNT = "theguy@itsnicholai.fyi";
    };

    serviceConfig = {
      User = "nicho";
      Group = "users";
      ExecStart = "${nodePkg}/bin/node /home/nicho/.nvm/versions/node/v24.13.1/lib/node_modules/openclaw/dist/index.js gateway --port 18789";
      Restart = "always";
      RestartSec = 5;
      KillMode = "process";
      # TODO: Once openclaw is installed via nix instead of nvm, update ExecStart path
      # ExecStart = "${pkgs.openclaw}/bin/openclaw gateway --port 18789";
    };
  };
}
