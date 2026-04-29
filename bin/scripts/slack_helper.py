#!/usr/bin/env python3
"""
Slack helper for Rook — quick CLI for common Slack operations.

Usage:
  slack_helper.py history <channel_id> [limit]
  slack_helper.py info <channel_id>
  slack_helper.py users [query]
"""
import os, sys, json
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

TOKEN = os.environ.get("SLACK_USER_TOKEN")
if not TOKEN:
    print("SLACK_USER_TOKEN not set", file=sys.stderr)
    sys.exit(1)

client = WebClient(token=TOKEN)

def history(channel, limit=20):
    try:
        resp = client.conversations_history(channel=channel, limit=limit)
        msgs = [m for m in resp.get("messages", []) if not m.get("subtype")]
        for m in msgs:
            ts = float(m["ts"])
            from datetime import datetime
            dt = datetime.fromtimestamp(ts).isoformat()
            text = (m.get("text") or "").replace("\n", " ")
            user = m.get("user", m.get("bot_id", "?"))
            print(f"[{dt}] {user}: {text[:300]}{'...' if len(text) > 300 else ''}")
    except SlackApiError as e:
        print(f"Slack error: {e.response['error']}", file=sys.stderr)

def info(channel):
    try:
        resp = client.conversations_info(channel=channel)
        c = resp["channel"]
        print(json.dumps({
            "id": c["id"],
            "name": c.get("name"),
            "is_im": c.get("is_im"),
            "user": c.get("user"),
            "num_members": c.get("num_members"),
        }, indent=2))
    except SlackApiError as e:
        print(f"Slack error: {e.response['error']}", file=sys.stderr)

def users_list(query=None):
    try:
        resp = client.users_list(limit=200)
        members = resp.get("members", [])
        if query:
            members = [m for m in members if query.lower() in m.get("real_name","").lower() or query.lower() in m.get("name","").lower()]
        for m in members[:20]:
            print(f"{m['id']:15} @{m.get('name',''):15} {m.get('real_name','')}")
    except SlackApiError as e:
        print(f"Slack error: {e.response['error']}", file=sys.stderr)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "history":
        history(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 20)
    elif cmd == "info":
        info(sys.argv[2])
    elif cmd == "users":
        users_list(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        print(__doc__)
