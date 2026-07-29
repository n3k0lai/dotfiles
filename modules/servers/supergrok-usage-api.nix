# SuperGrok weekly usage API — Rook publishes buckets; Ene fetches over Tailscale.
# Auth model A: tailnet reachability only (no bearer). Bind 0.0.0.0; WAN blocked by
# host firewall except trustedInterfaces = tailscale0.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.servers.supergrokUsageApi;
  python = pkgs.python3;
  src = ./supergrok-usage-api;
  app = pkgs.writeShellApplication {
    name = "supergrok-usage-api";
    runtimeInputs = [ python ];
    text = ''
      export PYTHONPATH="${src}''${PYTHONPATH:+:$PYTHONPATH}"
      export SUPERGROK_USAGE_HOST="${cfg.hostName}"
      export HERMES_STATE_DB="${cfg.stateDb}"
      export HERMES_HOME="${cfg.hermesHome}"
      exec ${python.interpreter} ${src}/server.py --host ${cfg.bind} --port ${toString cfg.port}
    '';
  };
in
{
  options.modules.servers.supergrokUsageApi = {
    enable = lib.mkEnableOption "SuperGrok weekly usage HTTP API (Tailscale-only)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 9855;
      description = "Listen port (reachable via tailscale0 trusted interface)";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "rook";
      description = "host field in JSON payload";
    };
    stateDb = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/.hermes/state.db";
      description = "Hermes state.db path (read-only)";
    };
    hermesHome = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/.hermes";
      description = "HERMES_HOME for coefficient reset_next lookup";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.supergrok-usage-api = {
      description = "SuperGrok weekly usage API (Tailscale)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${app}/bin/supergrok-usage-api";
        Restart = "on-failure";
        RestartSec = 5;
        User = cfg.user;
        Group = cfg.group;
        NoNewPrivileges = true;
        PrivateTmp = true;
        # Same posture as hermes-agent: need to read ~/.hermes/state.db
        ProtectHome = false;
        ProtectSystem = "strict";
        ReadWritePaths = [ ];
      };
    };
  };
}
