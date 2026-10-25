#!/usr/bin/env python3
"""netaudit-report: per-device daily summary of router DNS, DHCP and conntrack logs.

Reads the JSONL files written by the netaudit collector (Vector) under
<root>/{dns,dhcp,conn,fw,bw,inventory}/YYYY-MM-DD.jsonl[.gz] and writes
<root>/reports/YYYY-MM-DD.md.

Device names come from (in order): the private known-devices file
(<root>/known-devices.json, never committed anywhere), DHCP hostnames seen
in the logs, then "unknown". Nothing about the network is hardcoded here.

"New" devices and destinations are tracked in <root>/state/seen.json, so a
device or destination is new on the first day it is ever seen (within the
state window), not just new versus the previous day's file.
"""

import argparse
import datetime as dt
import gzip
import ipaddress
import json
import os
import re
import sys
from collections import Counter, defaultdict

MAC_RE = re.compile(r"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$")
QUERY_RE = re.compile(r"query\[(\w+)\] (\S+) from (\S+)")
ANSWER_RE = re.compile(r"(?:reply|cached|cached-stale) (\S+) is (\S+)")
DHCP_RE = re.compile(r"DHCPACK\(\S+\) (\S+) ([0-9a-fA-F:]{17})(?: (\S+))?")
NEIGH_RE = re.compile(r"^(\S+) dev \S+ lladdr ([0-9a-fA-F:]{17})")
CT_EVENT_RE = re.compile(r"\[(NEW|DESTROY|UPDATE)\]")
CT_TS_RE = re.compile(r"^\[(\d+)(?:\.\d+)?\]")
FW_KV_RE = re.compile(r"(\w+)=(\S*)")
WAN_KEY = "router/wan"


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--root", default=os.environ.get("NETAUDIT_ROOT", "/var/lib/netaudit"))
    p.add_argument("--date", help="day to report on (YYYY-MM-DD, default: yesterday)")
    p.add_argument("--since", help="ad-hoc window ending now, e.g. 1h, 30m, 2d; prints to stdout, no state update")
    p.add_argument("--top", type=int, default=15, help="rows per device section")
    p.add_argument("--state-days", type=int, default=90,
                   help="forget devices/destinations not seen for this many days")
    p.add_argument("--include-local", action="store_true",
                   help="include flows to private/LAN destinations (default: internet-bound only)")
    p.add_argument("--stdout", action="store_true", help="print the report instead of writing it")
    p.add_argument("--no-state", action="store_true", help="do not read or update state/seen.json")
    return p.parse_args(argv)


def parse_window(s):
    m = re.fullmatch(r"(\d+)([smhd])", s.strip())
    if not m:
        raise SystemExit(f"bad --since value: {s!r} (use e.g. 30m, 1h, 2d)")
    n, unit = int(m.group(1)), m.group(2)
    unit_name = {"s": "seconds", "m": "minutes", "h": "hours", "d": "days"}[unit]
    return dt.timedelta(**{unit_name: n})


def open_day(root, kind, day):
    base = os.path.join(root, kind, day.isoformat() + ".jsonl")
    for path, opener in ((base, open), (base + ".gz", gzip.open)):
        if os.path.exists(path):
            return opener(path, "rt", encoding="utf-8", errors="replace")
    return None


def iter_events(root, kind, days):
    for day in days:
        fh = open_day(root, kind, day)
        if fh is None:
            continue
        with fh:
            for line in fh:
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if isinstance(ev, dict):
                    yield ev


def event_time(ev):
    ts = ev.get("timestamp") or ev.get("received_at")
    if not isinstance(ts, str):
        return None
    try:
        t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def ip_obj(s):
    try:
        return ipaddress.ip_address(s.split("%", 1)[0])
    except ValueError:
        return None


def is_local(ip):
    a = ip_obj(ip)
    if a is None:
        return True
    return a.is_private or a.is_link_local or a.is_loopback or a.is_multicast or a.is_unspecified


def human_bytes(n):
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return str(n)


class Devices:
    """IP -> MAC -> name mapping from DHCP, lease/neighbour snapshots and the private known file."""

    def __init__(self, known):
        self.ip_mac = {}
        self.mac_host = {}
        self.known = {k.lower(): v for k, v in known.items()}

    def learn(self, ip, mac, host=None):
        if not ip or not mac:
            return
        mac = mac.lower()
        if not MAC_RE.match(mac):
            return
        self.ip_mac[ip] = mac
        if host and host not in ("*", "-"):
            self.mac_host[mac] = host

    def key(self, ip):
        return self.ip_mac.get(ip, ip)

    def name(self, key):
        if key == WAN_KEY:
            return "router itself / inbound from internet"
        if key in self.known:
            return self.known[key]
        if key in self.mac_host:
            return self.mac_host[key]
        return "unknown"

    def is_known(self, key):
        return key in self.known


def load_known(root):
    path = os.path.join(root, "known-devices.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict) and isinstance(data.get("devices"), dict):
        data = data["devices"]
    if not isinstance(data, dict):
        return {}
    out = {}
    for k, v in data.items():
        if isinstance(v, dict):
            v = v.get("name", "")
        out[str(k)] = str(v)
    return out


def build_devices(root, days, known):
    devs = Devices(known)
    for ev in iter_events(root, "dhcp", days):
        m = DHCP_RE.search(ev.get("message", ""))
        if m:
            devs.learn(m.group(1), m.group(2), m.group(3))
    for ev in iter_events(root, "inventory", days):
        msg = ev.get("message", "")
        app = ev.get("appname", "")
        if app == "leases":
            parts = msg.split()
            if len(parts) >= 4 and MAC_RE.match(parts[1].lower()):
                devs.learn(parts[2], parts[1], parts[3])
        else:
            m = NEIGH_RE.match(msg)
            if m:
                devs.learn(m.group(1), m.group(2))
    return devs


def parse_conntrack(msg):
    m = CT_EVENT_RE.search(msg)
    if not m:
        return None
    rec = {"event": m.group(1), "orig": {}, "reply": {}}
    ts = CT_TS_RE.match(msg)
    if ts:
        rec["ts"] = int(ts.group(1))
    tokens = msg[m.end():].split()
    if len(tokens) >= 3:
        rec["l3"] = tokens[0]
        rec["proto"] = tokens[2]
    side = "orig"
    for tok in tokens:
        if "=" not in tok:
            continue
        k, v = tok.split("=", 1)
        if k == "src" and "src" in rec["orig"]:
            side = "reply"
        rec[side].setdefault(k, v)
    if "src" not in rec["orig"] or "dst" not in rec["orig"]:
        return None
    return rec


def collect(root, days, window_start, args, devs):
    # IP -> domain from DNS answers (current window plus the day before, for long-lived lookups)
    ip_domain = {}
    queries = defaultdict(Counter)
    dns_days = sorted(set(days) | {min(days) - dt.timedelta(days=1)})
    for ev in iter_events(root, "dns", dns_days):
        msg = ev.get("message", "")
        a = ANSWER_RE.search(msg)
        if a and ip_obj(a.group(2)) is not None:
            ip_domain[a.group(2)] = a.group(1)
            continue
        if ev_day(ev) not in days:
            continue
        if window_start and (event_time(ev) or window_start) < window_start:
            continue
        q = QUERY_RE.search(msg)
        if q:
            client = q.group(3).split("/", 1)[0]
            queries[devs.key(client)][q.group(2).lower().rstrip(".")] += 1

    flows = defaultdict(lambda: defaultdict(lambda: {"flows": 0, "up": 0, "down": 0, "ports": set()}))
    new_flows = Counter()
    for ev in iter_events(root, "conn", days):
        rec = parse_conntrack(ev.get("message", ""))
        if rec is None:
            continue
        if window_start:
            t = rec.get("ts")
            t = dt.datetime.fromtimestamp(t, dt.timezone.utc) if t else event_time(ev)
            if t and t < window_start:
                continue
        src, dst = rec["orig"]["src"], rec["orig"]["dst"]
        if not args.include_local and is_local(dst):
            continue
        # Flows sourced from a public address are the router's own (WAN side) or inbound.
        dev = devs.key(src) if is_local(src) else WAN_KEY
        if rec["event"] == "NEW":
            new_flows[dev] += 1
            continue
        if rec["event"] != "DESTROY":
            continue
        dest = ip_domain.get(dst, dst)
        row = flows[dev][dest]
        row["flows"] += 1
        row["up"] += int(rec["orig"].get("bytes", 0) or 0)
        row["down"] += int(rec["reply"].get("bytes", 0) or 0)
        port = rec["orig"].get("dport")
        row["ports"].add(f"{rec.get('proto', '?')}/{port}" if port else rec.get("proto", "?"))

    fw = defaultdict(Counter)
    for ev in iter_events(root, "fw", days):
        msg = ev.get("message", "")
        if window_start and (event_time(ev) or window_start) < window_start:
            continue
        kv = dict(FW_KV_RE.findall(msg))
        src = kv.get("SRC")
        if not src:
            continue
        mac = kv.get("MAC", "")
        parts = mac.split(":")
        if len(parts) >= 12:
            devs.learn(src, ":".join(parts[6:12]))
        prefix = re.sub(r"^\[\s*[\d.]+\]\s*", "", msg.split("IN=", 1)[0]).strip().rstrip(":") or "fw"
        proto_port = f"{kv.get('PROTO', '?').lower()}/{kv.get('DPT', '-')}"
        if not is_local(src):
            # Internet scanners hitting WAN input: aggregate by port, not per source.
            fw[WAN_KEY][f"{prefix}: {proto_port}"] += 1
            continue
        dst = kv.get("DST", "?")
        fw[devs.key(src)][f"{prefix}: {ip_domain.get(dst, dst)} {proto_port}"] += 1

    bw = {}
    header = None
    for ev in iter_events(root, "bw", days):
        cols = [c.strip('"\'') for c in re.split(r"[\t;,\s]+", ev.get("message", "").strip()) if c]
        if "rx_bytes" in cols:
            header = cols
            continue
        if not header or len(cols) != len(header):
            continue
        row = dict(zip(header, cols))
        mac = row.get("mac", "").lower()
        ip = row.get("ip", "")
        if MAC_RE.match(mac) and ip:
            devs.learn(ip, mac)
        key = mac if MAC_RE.match(mac) else devs.key(ip)
        try:
            bw[key] = (int(row.get("rx_bytes", 0)), int(row.get("tx_bytes", 0)))
        except ValueError:
            pass

    return queries, flows, new_flows, fw, bw


def ev_day(ev):
    t = event_time(ev)
    return t.astimezone().date() if t else None


def load_state(path):
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, ValueError):
            pass
    return {"devices": {}, "dests": {}}


def touch(entry_map, key, day):
    e = entry_map.get(key)
    d = day.isoformat()
    if e is None:
        entry_map[key] = {"first": d, "last": d}
        return True
    e["first"] = min(e["first"], d)
    e["last"] = max(e["last"], d)
    return e["first"] == d


def prune_state(state, day, keep_days):
    cutoff = (day - dt.timedelta(days=keep_days)).isoformat()
    state["devices"] = {k: v for k, v in state["devices"].items() if v["last"] >= cutoff}
    for dev in list(state["dests"]):
        kept = {k: v for k, v in state["dests"][dev].items() if v["last"] >= cutoff}
        if kept:
            state["dests"][dev] = kept
        else:
            del state["dests"][dev]


def render(title, devs, queries, flows, new_flows, fw, bw, new_devices, new_dests, baseline, top):
    all_devs = set(queries) | set(flows) | set(new_flows) | set(fw) | set(bw)

    def total_bytes(d):
        return sum(r["up"] + r["down"] for r in flows.get(d, {}).values())

    order = sorted(all_devs, key=lambda d: (-total_bytes(d), -sum(queries.get(d, {}).values()), d))
    out = [f"# netaudit report: {title}", ""]
    out.append(f"Devices seen: {len(all_devs)}. "
               f"DNS queries: {sum(sum(c.values()) for c in queries.values())}. "
               f"Internet flows closed: {sum(r['flows'] for f in flows.values() for r in f.values())}.")
    out.append("")
    if baseline:
        out += ["_First run (no prior state): everything is new, so the new-device and "
                "new-destination lists are suppressed. They start tomorrow._", ""]

    out.append("## New devices")
    if baseline or not new_devices:
        out.append("- none" if not baseline else "- (baseline run)")
    else:
        for d in sorted(new_devices):
            out.append(f"- `{d}` ({devs.name(d)})")
    out.append("")

    unknown = sorted(d for d in all_devs if not devs.is_known(d) and d != WAN_KEY)
    out.append("## Not in known-devices.json")
    out += [f"- `{d}` ({devs.name(d)})" for d in unknown] or ["- none"]
    out.append("")

    out.append("## Firewall rejects (quarantine hits, WAN input)")
    if fw:
        for d in sorted(fw, key=lambda d: -sum(fw[d].values())):
            out.append(f"- `{d}` ({devs.name(d)}): {sum(fw[d].values())} rejects")
            for what, n in fw[d].most_common(top):
                out.append(f"  - {n} x {what}")
    else:
        out.append("- none")
    out.append("")

    out.append("## Per device")
    for d in order:
        out.append(f"### {devs.name(d)} (`{d}`)")
        f = flows.get(d, {})
        up = sum(r["up"] for r in f.values())
        down = sum(r["down"] for r in f.values())
        line = (f"- flows opened {new_flows.get(d, 0)}, closed {sum(r['flows'] for r in f.values())}, "
                f"up {human_bytes(up)}, down {human_bytes(down)}")
        if d in bw:
            line += f"; nlbwmon period total rx {human_bytes(bw[d][0])}, tx {human_bytes(bw[d][1])}"
        out.append(line)
        nd = sorted(new_dests.get(d, ()))
        if nd and not baseline:
            out.append(f"- **new destinations ({len(nd)})**: " + ", ".join(f"`{x}`" for x in nd[:top])
                       + (" ..." if len(nd) > top else ""))
        q = queries.get(d)
        if q:
            out.append(f"- top domains ({len(q)} distinct, {sum(q.values())} queries):")
            out += [f"  - {n} x `{name}`" for name, n in q.most_common(top)]
        if f:
            out.append(f"- top destinations ({len(f)} distinct):")
            rows = sorted(f.items(), key=lambda kv: (-(kv[1]["up"] + kv[1]["down"]), -kv[1]["flows"]))
            for dest, r in rows[:top]:
                ports = ",".join(sorted(r["ports"])[:5])
                out.append(f"  - `{dest}` {r['flows']} flows, up {human_bytes(r['up'])}, "
                           f"down {human_bytes(r['down'])} [{ports}]")
        out.append("")
    return "\n".join(out) + "\n"


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    root = args.root
    now = dt.datetime.now(dt.timezone.utc)
    window_start = None
    if args.since:
        window_start = now - parse_window(args.since)
        first = window_start.astimezone().date()
        last = now.astimezone().date()
        days = [first + dt.timedelta(days=i) for i in range((last - first).days + 1)]
        title = f"last {args.since} (ending {now.astimezone():%Y-%m-%d %H:%M %Z})"
        args.stdout = True
        args.no_state = True
    else:
        day = dt.date.fromisoformat(args.date) if args.date else dt.date.today() - dt.timedelta(days=1)
        days = [day]
        title = day.isoformat()

    known = load_known(root)
    inv_days = [days[0] - dt.timedelta(days=i) for i in range(30, 0, -1)] + days
    devs = build_devices(root, inv_days, known)
    queries, flows, new_flows, fw, bw = collect(root, days, window_start, args, devs)

    new_devices, new_dests, baseline = set(), defaultdict(set), False
    state_path = os.path.join(root, "state", "seen.json")
    if not args.no_state:
        state = load_state(state_path)
        baseline = not state["devices"]
        day = days[-1]
        for d in set(queries) | set(flows) | set(new_flows) | set(fw):
            if touch(state["devices"], d, day) and d != WAN_KEY:
                new_devices.add(d)
            dmap = state["dests"].setdefault(d, {})
            for dest in flows.get(d, {}):
                if touch(dmap, dest, day):
                    new_dests[d].add(dest)
            for name in queries.get(d, {}):
                touch(dmap, "dns:" + name, day)
        prune_state(state, day, args.state_days)

    report = render(title, devs, queries, flows, new_flows, fw, bw, new_devices, new_dests,
                    baseline, args.top)

    if args.stdout:
        sys.stdout.write(report)
    else:
        os.makedirs(os.path.join(root, "reports"), exist_ok=True)
        path = os.path.join(root, "reports", f"{days[0].isoformat()}.md")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(report)
        os.replace(tmp, path)
        print(f"wrote {path}")

    if not args.no_state:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        tmp = state_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh, separators=(",", ":"))
        os.replace(tmp, state_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
