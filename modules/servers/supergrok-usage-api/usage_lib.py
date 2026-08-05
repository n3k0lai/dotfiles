#!/usr/bin/env python3
"""Shared SuperGrok weekly bucket math (Ene client + Rook API)."""
from __future__ import annotations

import os
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")
DEFAULT_RESET_NEXT = datetime(2026, 8, 10, 12, 7, tzinfo=ET)
LONG_LIVED_SEC = 3 * 86400
SCHEMA_VERSION = 1


def hermes_home() -> Path:
    return Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))


def default_state_db() -> Path:
    return hermes_home() / "state.db"


def load_reset_next(meta_dir: Path | None = None) -> datetime:
    """Prefer coefficient-history.jsonl reset_next; else default."""
    if meta_dir is None:
        meta_dir = hermes_home() / "workspace" / "vault" / "Meta" / "supergrok"
    hist = meta_dir / "coefficient-history.jsonl"
    if hist.exists():
        last = None
        for line in hist.read_text().splitlines():
            line = line.strip()
            if line:
                import json

                last = json.loads(line)
        if last and last.get("reset_next"):
            dt = datetime.fromisoformat(last["reset_next"])
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=ET)
            return dt
    return DEFAULT_RESET_NEXT


def week_bounds(reset_next: datetime, n_back: int = 4) -> list[tuple[str, datetime, datetime]]:
    out: list[tuple[str, datetime, datetime]] = []
    end = reset_next
    for i in range(n_back):
        start = end - timedelta(days=7)
        label = "W0" if i == 0 else f"W-{i}"
        out.append((label, start, end))
        end = start
    return list(reversed(out))


def sum_week(conn: sqlite3.Connection, t0: float, t1: float) -> dict:
    row = conn.execute(
        """
        SELECT
          coalesce(sum(api_call_count),0),
          coalesce(sum(input_tokens),0),
          coalesce(sum(output_tokens),0),
          coalesce(sum(cache_read_tokens),0),
          coalesce(sum(reasoning_tokens),0),
          count(*),
          count(distinct session_id)
        FROM session_model_usage
        WHERE first_seen >= ? AND first_seen < ?
          AND (last_seen - first_seen) < ?
        """,
        (t0, t1, LONG_LIVED_SEC),
    ).fetchone()
    calls, inp, out, cache, reason, rows, sessions = row
    by_src: dict = {}
    for src, c, i, o, n in conn.execute(
        """
        SELECT coalesce(s.source,'(unknown)'),
          coalesce(sum(u.api_call_count),0),
          coalesce(sum(u.input_tokens),0),
          coalesce(sum(u.output_tokens),0),
          count(distinct u.session_id)
        FROM session_model_usage u
        LEFT JOIN sessions s ON s.id = u.session_id
        WHERE u.first_seen >= ? AND u.first_seen < ?
          AND (u.last_seen - u.first_seen) < ?
        GROUP BY 1
        """,
        (t0, t1, LONG_LIVED_SEC),
    ):
        by_src[src] = {
            "api_calls": c,
            "input_tokens": i,
            "output_tokens": o,
            "input_plus_output_tokens": i + o,
            "sessions": n,
        }
    return {
        "api_calls": calls,
        "input_tokens": inp,
        "output_tokens": out,
        "input_plus_output_tokens": inp + out,
        "cache_read_tokens": cache,
        "reasoning_tokens": reason,
        "rows": rows,
        "sessions": sessions,
        "by_source": by_src,
    }


def build_weekly_payload(
    host: str,
    db_path: Path | None = None,
    reset_next: datetime | None = None,
    weeks: int = 4,
) -> dict:
    db_path = db_path or default_state_db()
    reset_next = reset_next or load_reset_next()
    reset_last = reset_next - timedelta(days=7)
    weeks = max(1, min(int(weeks), 8))

    if not db_path.exists():
        raise FileNotFoundError(f"state.db not found: {db_path}")

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        bounds = week_bounds(reset_next, weeks)
        now = datetime.now(ET)
        out_weeks = []
        for label, start, end in bounds:
            m = sum_week(conn, start.timestamp(), end.timestamp())
            kind = "partial" if label == "W0" and now < end else "full"
            out_weeks.append(
                {
                    "bucket": label,
                    "start": start.isoformat(),
                    "end": end.isoformat(),
                    "kind": kind,
                    **m,
                }
            )
    finally:
        conn.close()

    return {
        "schema_version": SCHEMA_VERSION,
        "host": host,
        "generated_at": datetime.now(ET).isoformat(),
        "reset_last": reset_last.isoformat(),
        "reset_next": reset_next.isoformat(),
        "method": "first_seen in [start,end); exclude sessions with duration >= 3d",
        "weeks": out_weeks,
    }
