#!/usr/bin/env python3
"""Minimal Tailscale-only SuperGrok weekly usage HTTP API (Rook)."""
from __future__ import annotations

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

# Allow running from Nix store or alongside usage_lib.py
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from usage_lib import build_weekly_payload  # noqa: E402


class Handler(BaseHTTPRequestHandler):
    server_version = "supergrok-usage-api/1"

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _send(self, code: int, body: dict | list, extra_headers: dict | None = None) -> None:
        data = json.dumps(body, indent=2).encode("utf-8") + b"\n"
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = parse_qs(parsed.query)

        if path in ("/health", "/v1/health"):
            self._send(200, {"ok": True, "service": "supergrok-usage-api"})
            return

        if path != "/v1/usage/weekly":
            self._send(404, {"error": "not_found", "path": path})
            return

        weeks = 4
        if "weeks" in qs:
            try:
                weeks = int(qs["weeks"][0])
            except ValueError:
                self._send(400, {"error": "invalid_weeks"})
                return

        host = os.environ.get("SUPERGROK_USAGE_HOST", "rook")
        db = os.environ.get("HERMES_STATE_DB") or os.environ.get("SUPERGROK_STATE_DB")
        db_path = Path(db) if db else None

        try:
            payload = build_weekly_payload(host=host, db_path=db_path, weeks=weeks)
        except FileNotFoundError as e:
            self._send(503, {"error": "state_db_missing", "detail": str(e)})
            return
        except Exception as e:
            self._send(500, {"error": "internal", "detail": str(e)})
            return

        self._send(200, payload)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--host", default="0.0.0.0", help="bind address")
    ap.add_argument("--port", type=int, default=9855)
    args = ap.parse_args()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"supergrok-usage-api listening on {args.host}:{args.port}", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("shutting down", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
