#!/usr/bin/env python3
"""Compare locked hermes-agent flake input vs GitHub releases/HEAD.

Stable stdout (no clocks) so Hermes cron monitor_script can hash it.
Never updates flake.lock. Never nixos-rebuild switch.

Usage:
  hermes-flake-watch.py            # human + stable report
  hermes-flake-watch.py --stable   # monitor-safe (same body, no extra chatter)
  hermes-flake-watch.py --json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = "NousResearch/hermes-agent"
INPUT_NAME = "hermes-agent"
MODEL_RE = re.compile(
    r"\b(grok|xai|model.?catalog|models\.dev|/model)\b",
    re.I,
)


def _which(name: str) -> str | None:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return None


def _run(argv: list[str], timeout: int = 30) -> tuple[int, str]:
    try:
        p = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, str(exc)


def find_dotfiles() -> Path:
    env = os.environ.get("HERMES_DOTFILES")
    candidates = []
    if env:
        candidates.append(Path(env))
    home = Path.home()
    candidates.extend(
        [
            Path("/var/lib/hermes/dotfiles"),
            home / ".hermes" / "workspace" / "dotfiles",
            home / "dotfiles",
            Path("/var/lib/hermes/.hermes/workspace/dotfiles"),
        ]
    )
    seen: set[Path] = set()
    for raw in candidates:
        try:
            p = raw.resolve()
        except OSError:
            continue
        if p in seen:
            continue
        seen.add(p)
        if (p / "flake.lock").is_file() and (p / "flake.nix").is_file():
            return p
    raise SystemExit("hermes-flake-watch: flake.lock not found (set HERMES_DOTFILES)")


def lock_node(dotfiles: Path, name: str = INPUT_NAME) -> dict:
    data = json.loads((dotfiles / "flake.lock").read_text())
    node = data.get("nodes", {}).get(name)
    if not node:
        raise SystemExit(f"hermes-flake-watch: no flake.lock node {name!r}")
    locked = node.get("locked") or {}
    original = node.get("original") or {}
    return {
        "rev": locked.get("rev") or "",
        "narHash": locked.get("narHash") or "",
        "lastModified": locked.get("lastModified"),
        "owner": locked.get("owner") or original.get("owner") or "NousResearch",
        "repo": locked.get("repo") or original.get("repo") or "hermes-agent",
        "ref": original.get("ref") or "",
        "type": locked.get("type") or original.get("type") or "github",
    }


def running_hermes() -> dict:
    exe = _which("hermes")
    if not exe:
        return {"available": False}
    code, out = _run([exe, "--version"])
    text = out.strip()
    ver = None
    cal = None
    m = re.search(r"Hermes Agent v([0-9.]+)", text)
    if m:
        ver = m.group(1)
    m = re.search(r"\((v?[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}(?:\.[0-9]+)?)\)", text)
    if m:
        cal = m.group(1)
    behind = None
    m = re.search(r"(\d+)\s+commits behind", text)
    if m:
        behind = int(m.group(1))
    return {
        "available": code == 0 or bool(ver),
        "version": ver,
        "calendar": cal,
        "commits_behind_cli": behind,
        "install": exe,
        "raw_first_line": text.splitlines()[0] if text else "",
    }


def gh_json(path: str) -> object | None:
    gh = _which("gh")
    if gh:
        code, out = _run([gh, "api", path], timeout=45)
        if code == 0:
            try:
                return json.loads(out)
            except json.JSONDecodeError:
                return None
    url = f"https://api.github.com/{path.lstrip('/')}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "ene-hermes-flake-watch",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


def latest_release() -> dict:
    data = gh_json(f"repos/{REPO}/releases?per_page=5")
    if not isinstance(data, list) or not data:
        return {}
    for rel in data:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        tag = rel.get("tag_name") or ""
        sha = ""
        tag_info = gh_json(f"repos/{REPO}/git/ref/tags/{tag}")
        if isinstance(tag_info, dict):
            obj = tag_info.get("object") or {}
            sha = obj.get("sha") or ""
            if obj.get("type") == "tag":
                peeled = gh_json(f"repos/{REPO}/git/tags/{sha}")
                if isinstance(peeled, dict):
                    sha = ((peeled.get("object") or {}).get("sha")) or sha
        return {
            "tag": tag,
            "name": rel.get("name") or tag,
            "published_at": (rel.get("published_at") or "")[:10],
            "sha": sha,
        }
    return {}


def repo_head() -> dict:
    data = gh_json(f"repos/{REPO}/commits?per_page=1")
    if isinstance(data, list) and data:
        c = data[0]
        return {
            "sha": c.get("sha") or "",
            "msg": ((c.get("commit") or {}).get("message") or "").split("\n", 1)[0],
        }
    return {}


def compare(base: str, head: str) -> dict:
    if not base or not head:
        return {}
    data = gh_json(f"repos/{REPO}/compare/{base}...{head}")
    if not isinstance(data, dict):
        return {}
    commits = []
    for c in data.get("commits") or []:
        msg = ((c.get("commit") or {}).get("message") or "").split("\n", 1)[0]
        commits.append({"sha": (c.get("sha") or "")[:8], "msg": msg})
    return {
        "status": data.get("status"),
        "ahead_by": data.get("ahead_by"),
        "behind_by": data.get("behind_by"),
        "total_commits": data.get("total_commits"),
        "commits": commits,
    }


def model_hits(commits: list[dict]) -> list[dict]:
    return [c for c in commits if MODEL_RE.search(c.get("msg") or "")]


def collect() -> dict:
    dotfiles = find_dotfiles()
    locked = lock_node(dotfiles)
    running = running_hermes()
    release = latest_release()
    head = repo_head()
    vs_rel = compare(locked["rev"], release.get("sha") or release.get("tag") or "")
    vs_head = compare(locked["rev"], head.get("sha") or "HEAD")
    vs_rel_from_run = {}
    if running.get("calendar"):
        tag = running["calendar"]
        if not tag.startswith("v"):
            tag = f"v{tag}"
        vs_rel_from_run = compare(tag, release.get("tag") or "")
    all_gap = (vs_rel.get("commits") or []) + (vs_head.get("commits") or [])
    # de-dupe by sha, keep order
    seen: set[str] = set()
    uniq = []
    for c in all_gap:
        if c["sha"] in seen:
            continue
        seen.add(c["sha"])
        uniq.append(c)
    return {
        "dotfiles": str(dotfiles),
        "input": INPUT_NAME,
        "repo": REPO,
        "locked": locked,
        "running": running,
        "latest_release": release,
        "head": head,
        "lock_vs_release": vs_rel,
        "lock_vs_head": vs_head,
        "running_tag_vs_release": vs_rel_from_run,
        "model_catalog_hits": model_hits(uniq)[:12],
    }


def format_report(info: dict) -> str:
    locked = info["locked"]
    running = info["running"]
    rel = info["latest_release"]
    head = info["head"]
    vs_rel = info["lock_vs_release"] or {}
    vs_head = info["lock_vs_head"] or {}
    hits = info.get("model_catalog_hits") or []

    lock_short = (locked.get("rev") or "?")[:10]
    rel_tag = rel.get("tag") or "unknown"
    rel_sha = (rel.get("sha") or "")[:10]
    head_sha = (head.get("sha") or "")[:10]
    lock_ref = locked.get("ref") or "(default branch)"

    run_line = "unavailable"
    if running.get("available"):
        run_line = f"v{running.get('version') or '?'} ({running.get('calendar') or '?'})"
        if running.get("commits_behind_cli") is not None:
            run_line += f" · cli says {running['commits_behind_cli']} commits behind"

    ahead_rel = vs_rel.get("ahead_by")
    ahead_head = vs_head.get("ahead_by")
    if ahead_rel is None:
        rel_state = "compare-unavailable"
    elif ahead_rel == 0:
        rel_state = "current"
    else:
        rel_state = f"behind {ahead_rel}"

    if ahead_head is None:
        head_state = "compare-unavailable"
    elif ahead_head == 0:
        head_state = "current"
    else:
        head_state = f"behind {ahead_head}"

    lines = [
        "HERMES_FLAKE_WATCH v1",
        f"repo: {info['repo']}",
        f"dotfiles: {info['dotfiles']}",
        f"lock.rev: {lock_short}",
        f"lock.ref: {lock_ref}",
        f"lock.nar: {locked.get('narHash') or '?'}",
        f"running: {run_line}",
        f"github.release: {rel_tag} {rel_sha} ({rel.get('published_at') or '?'}) {rel.get('name') or ''}".rstrip(),
        f"github.head: {head_sha} {head.get('msg') or ''}".rstrip(),
        f"lock_vs_release: {rel_state}",
        f"lock_vs_head: {head_state}",
    ]
    if hits:
        lines.append("model_catalog_commits:")
        for c in hits[:8]:
            lines.append(f"  {c['sha']} {c['msg']}")
    else:
        lines.append("model_catalog_commits: none-in-compare-window")

    tail = (vs_head.get("commits") or vs_rel.get("commits") or [])[-5:]
    if tail:
        lines.append("recent_gap_commits:")
        for c in tail:
            lines.append(f"  {c['sha']} {c['msg']}")

    if rel_state == "current" and (ahead_head or 0) > 0:
        lines.append(
            "note: on latest GitHub *release*; main is ahead (pre-release). bump only if you want tip."
        )
    elif ahead_rel:
        lines.append(
            "action: nix flake lock --update-input hermes-agent && nixos-rebuild build --flake <dotfiles>#ene"
        )
        lines.append("action: nicho activates (ene switch). hermes never switch.")
    else:
        lines.append("action: none")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--stable", action="store_true", help="full report, no clocks")
    ap.add_argument(
        "--monitor",
        action="store_true",
        help="hash-stable: lock + latest GitHub *release* only (ignore busy main)",
    )
    args = ap.parse_args()
    info = collect()
    if args.json:
        sys.stdout.write(json.dumps(info, indent=2, sort_keys=True) + "\n")
        return 0
    if args.monitor:
        locked = info["locked"]
        rel = info["latest_release"]
        running = info["running"]
        sys.stdout.write(
            "\n".join(
                [
                    "HERMES_FLAKE_MONITOR v1",
                    f"lock.rev: {(locked.get('rev') or '?')[:12]}",
                    f"release.tag: {rel.get('tag') or '?'}",
                    f"release.sha: {(rel.get('sha') or '?')[:12]}",
                    f"running.version: {running.get('version') or '?'}",
                    f"running.calendar: {running.get('calendar') or '?'}",
                    "",
                ]
            )
        )
        return 0
    sys.stdout.write(format_report(info))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
