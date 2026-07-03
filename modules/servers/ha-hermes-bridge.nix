# Home Assistant alert webhook → Rook Hermes gateway.
# HA automations POST to http://127.0.0.1:<port>/alert with X-HA-Secret header.
{ config, pkgs, lib, ... }:

let
  cfg = config.modules.servers.haHermesBridge;

  bridgePy = pkgs.writeText "ha-hermes-bridge.py" ''
    #!/usr/bin/env python3
    """Forward Home Assistant security alerts to the local Hermes gateway."""
    import json
    import os
    import sys
    import urllib.error
    import urllib.request
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    PORT = int(os.environ.get("BRIDGE_PORT", "8124"))
    BIND = os.environ.get("BRIDGE_BIND", "127.0.0.1")
    HA_SECRET = os.environ.get("HA_WEBHOOK_SECRET", "")
    GATEWAY_URL = os.environ.get(
        "HERMES_GATEWAY_URL", "http://127.0.0.1:18789/api/sessions/send"
    )
    GATEWAY_TOKEN = os.environ.get("HERMES_GATEWAY_TOKEN", "")
    SESSION_KEY = os.environ.get("HERMES_SESSION_KEY", "agent:main:main")


    def forward_to_hermes(payload: dict) -> tuple[int, str]:
        event = payload.get("event", "home_alert")
        entity = payload.get("entity_id", "unknown")
        severity = payload.get("severity", "info")
        context = payload.get("context", {})
        incident_id = payload.get("incident_id") or context.get("incident_id", "")

        lines = [
            f"[HA ALERT] event={event} entity={entity} severity={severity}",
        ]
        if incident_id:
            lines.append(f"incident_id={incident_id}")
        if context:
            lines.append(f"context={json.dumps(context, sort_keys=True)}")
        lines.append("Triage this home alert and dispatch hangar only with explicit confirmation.")
        message = "\n".join(lines)

        body = json.dumps({
            "sessionKey": SESSION_KEY,
            "message": message,
        }).encode("utf-8")

        headers = {"Content-Type": "application/json"}
        if GATEWAY_TOKEN:
            headers["Authorization"] = f"Bearer {GATEWAY_TOKEN}"

        req = urllib.request.Request(GATEWAY_URL, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.status, resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")
            return e.code, detail
        except urllib.error.URLError as e:
            return 502, str(e.reason)


    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            sys.stderr.write(f"[ha-hermes-bridge] {self.address_string()} - {fmt % args}\n")

        def _reject(self, code: int, msg: str):
            self.send_response(code)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(msg.encode("utf-8"))

        def do_GET(self):
            if self.path == "/health":
                self._reject(200, "ok")
            else:
                self._reject(404, "not found")

        def do_POST(self):
            if self.path != "/alert":
                self._reject(404, "not found")
                return

            if HA_SECRET:
                provided = self.headers.get("X-HA-Secret", "")
                if provided != HA_SECRET:
                    self._reject(403, "forbidden")
                    return

            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                self._reject(400, "invalid json")
                return

            status, detail = forward_to_hermes(payload)
            self.send_response(200 if status < 400 else 502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "hermes_status": status,
                "hermes_response": detail[:2000],
            }).encode("utf-8"))


    def main():
        server = ThreadingHTTPServer((BIND, PORT), Handler)
        sys.stderr.write(f"[ha-hermes-bridge] listening on {BIND}:{PORT}\n")
        server.serve_forever()


    if __name__ == "__main__":
        main()
  '';

  bridgeRunner = pkgs.writeShellScriptBin "ha-hermes-bridge" ''
    set -euo pipefail
    export HA_WEBHOOK_SECRET=$(cat ${config.age.secrets.ha-webhook-secret.path})
    exec ${pkgs.python3}/bin/python3 ${bridgePy}
  '';

in {
  options.modules.servers.haHermesBridge = {
    enable = lib.mkEnableOption "Home Assistant alert webhook bridge to Hermes";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8124;
      description = "Localhost port for HA webhook POST /alert";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address (localhost only — never expose to tailnet)";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:18789/api/sessions/send";
      description = "Hermes gateway sessions/send endpoint";
    };

    sessionKey = lib.mkOption {
      type = lib.types.str;
      default = "agent:main:main";
      description = "Hermes session key for alert messages";
    };

    webhookSecretFile = lib.mkOption {
      type = lib.types.path;
      default = ../servers/secrets/ha_webhook_secret.age;
      description = "Agenix file containing the X-HA-Secret value";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.ha-webhook-secret = {
      file = cfg.webhookSecretFile;
      owner = "hermes";
      group = "users";
      mode = "0400";
    };

    systemd.services.ha-hermes-bridge = {
      description = "Home Assistant alert webhook → Hermes gateway";
      after = [ "network.target" "hermes-agent.service" ];
      wants = [ "hermes-agent.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${bridgeRunner}/bin/ha-hermes-bridge";
        Restart = "always";
        RestartSec = 5;
        User = "hermes";
        Group = "users";
        EnvironmentFile = config.age.secrets.hermes-env.path;
        Environment = [
          "BRIDGE_PORT=${toString cfg.port}"
          "BRIDGE_BIND=${cfg.bindAddress}"
          "HERMES_GATEWAY_URL=${cfg.gatewayUrl}"
          "HERMES_SESSION_KEY=${cfg.sessionKey}"
        ];
      };
    };
  };
}