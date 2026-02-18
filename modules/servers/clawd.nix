# OpenClaw (Ene) - AI assistant + Grok fallback proxy
{ config, pkgs, lib, ... }:

let
  nodePkg = pkgs.nodejs_22;
  grokPython = pkgs.python3.withPackages (ps: [ ps.aiohttp ]);
in
{
  environment.systemPackages = with pkgs; [
    nodePkg
    gh
  ];

  systemd.services.openclaw-gateway = {
    description = "OpenClaw Gateway (Ene)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/home/nicho";
      GOG_KEYRING_PASSWORD = "openclaw-ene";
      GOG_ACCOUNT = "theguy@itsnicholai.fyi";
    };

    path = [ nodePkg ];

    serviceConfig = {
      User = "nicho";
      Group = "users";
      ExecStart = "${nodePkg}/bin/node /home/nicho/.npm-global/lib/node_modules/openclaw/dist/index.js gateway --port 18789";
      Restart = "always";
      RestartSec = 5;
      KillMode = "process";
      Environment = [
        "PATH=/home/nicho/bin:/home/nicho/.npm-global/bin:${nodePkg}/bin:/run/current-system/sw/bin"
      ];
    };
  };

  # Cost-effective Grok fallback — Claude primary, Grok for bulk/cheap tasks
  systemd.services.grok-proxy = {
    description = "Grok API Proxy for OpenClaw";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "nicho";
      Group = "users";
      ExecStart = "${grokPython}/bin/python3 /home/nicho/bin/grok-proxy.py";
      Restart = "always";
      RestartSec = 5;
      EnvironmentFile = "/home/nicho/.config/grok-proxy.env";
    };
  };
}
