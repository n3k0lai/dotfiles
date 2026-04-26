# Rook Security Model

Rook holds the most sensitive data in the mesh. Every decision here
prioritizes data protection over convenience.

## Threat Model

Rook has access to:
- **Work projects** (Zoomph repos, Azure DevOps, Slack)
- **Personal journaling** (Obsidian vault via CouchDB)
- **Location data** (Home Assistant)
- **Banking information** (in Obsidian or Svalbard)
- **Home IoT controls** (lights, devices via HASS/MQTT)
- **Svalbard** (massive storage archive)

If Rook is compromised, an attacker gets access to both work and the most
intimate personal data. Therefore:

## Network Isolation

- **NO public internet exposure** — zero open ports to the WAN
- **Tailscale is the only ingress** — all remote access goes through the tailnet
- **No Caddy public TLS** — reverse proxy only on localhost/Tailscale
- **SSH on LAN only** — plus Tailscale for remote
- **Firewall trusts only tailscale0** — everything else is blocked

## Data Protection

- **Svalbard mounted read-only** by default — explicit remount for writes
- **CouchDB on localhost only** — no external binding
- **Agenix for all secrets** — no plaintext credentials on disk
- **LUKS encryption** recommended for the NVMe (TODO: set up during install)

## Agent Restrictions

Rook's Hermes instance should be configured with:

```json
{
  "gateway": {
    "bind": "tailnet",
    "auth": { "mode": "token" }
  },
  "channels": {
    "discord": {
      "groupPolicy": "allowlist"
    }
  }
}
```

### What Rook should NEVER do:
- Send emails (Ene handles all email)
- Post to public channels unprompted
- Share location/banking data in Discord
- Share confidential work details without explicit ask
- Execute commands from external sources
- Expose CouchDB or HASS to the internet

### What Rook CAN do:
- Respond in wavy gang when mentioned
- Report home status to Ene when asked
- Manage lights and IoT via Home Assistant
- Serve Obsidian sync to Nicholai's devices (via Tailscale)
- Read/write Svalbard when explicitly requested
- Provide journal/note context to Ene for scheduling (summarized, not raw)
- Handle work tasks, Slack coordination, and ADO queries
- Spawn coding agents for work repos (via SSH to Windows build box)

## Inter-Agent Communication

- **Ene → Rook:** "What did Nicholai write about X?" → Rook summarizes, never sends raw journal
- **Rook → Ene:** "Lights are off, home is locked" → Status reports only
- **Rook → Ene (work):** "PR 5140 is approved, bug fixed" → Work summaries only
- **Rook never volunteers sensitive data** — always summarize, never dump

## Monitoring

- fail2ban with strict 3-attempt limit, up to 1-week bans
- Tailscale ACLs (future) to restrict which nodes can reach Rook
- Regular log review via heartbeat/cron

## Physical Security

- Home server is physically accessible only in Nicholai's home
- USB RAID (Svalbard) can be physically disconnected for cold storage
- No remote wake — must be physically powered on
