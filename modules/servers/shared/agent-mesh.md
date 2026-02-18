# Agent Mesh Architecture

Three peer agents on a Tailscale mesh. Each owns a domain and communicates
via OpenClaw gateway APIs over the tailnet.

## Agents

### Ene (Project Manager)
- **Host:** DigitalOcean VPS (NixOS)
- **Tailscale:** ene-1 / 100.111.1.42
- **Gateway:** port 18789
- **Always-on:** Yes (VPS)
- **Scope:** Public infrastructure, email (ene@comfy.sh), Google Calendar,
  Gmail (theguy@itsnicholai.fyi), Discord, coordination between agents
- **Role:** Secretary/PM. Knows about everything, delegates to specialists.
  Does NOT hold confidential work data or local home data.

### Rook (Work)
- **Host:** Windows workstation
- **Tailscale:** work / 100.95.242.40
- **Gateway:** port TBD
- **Always-on:** During work hours (machine may sleep)
- **Scope:** Day job, coding agents, CI/CD, confidential work projects
- **Role:** Work specialist. Handles everything money-making and employer-related.
  Confidential by default — doesn't share work details unless Nicholai asks.

### Chat (Home)
- **Host:** Home Linux machine
- **Tailscale:** chat / 100.114.138.5
- **Gateway:** port TBD
- **Always-on:** When home machine is on
- **Scope:** Obsidian vault, home automation, physical location data, local files
- **Role:** Home specialist. Owns the knowledge base (Obsidian), location context,
  and anything tied to physical space.

## Communication Model

```
        Ene (PM/coordinator)
       /         \
    Rook         Chat
   (work)       (home)
```

- **Ene ↔ Rook:** Ene can ask Rook for work status updates, delegate coding tasks.
  Rook reports progress. Rook does NOT share confidential details unprompted.
- **Ene ↔ Chat:** Ene can query Chat for Obsidian notes, location context, home status.
  Chat provides data for Ene's scheduling/calendar decisions.
- **Rook ↔ Chat:** Rarely direct. Usually coordinated through Ene.
  Exception: Rook may query Chat for personal notes relevant to work.

## Transport

Each agent runs an OpenClaw gateway. Communication options:

### Option A: Node Pairing (subordinate)
One gateway registers as a node of another. Gives command execution
access but creates a hierarchy. NOT recommended for peer mesh.

### Option B: Gateway API (peer)
Each gateway exposes its API on the tailnet. Agents send messages to
each other's sessions via HTTP.

```bash
# Ene sends a message to Rook's main session
curl -X POST http://100.95.242.40:<port>/api/sessions/send \
  -H "Authorization: Bearer <rook-token>" \
  -d '{"sessionKey":"agent:main:main","message":"Hey Rook, status update?"}'
```

### Option C: Shared Discord Channel (simple)
All three agents in a Discord channel. Mention-based responses only.
Simplest but least structured. Good for casual coordination.

## Recommended: Hybrid

1. **Discord** for casual multi-agent chat (mention-only, no auto-reply loops)
2. **Gateway API** for structured task delegation and status reports
3. **Shared git repo** (dotfiles) for configuration and documentation sync

## Security Boundaries

- **Rook** never leaks work data to Discord or other agents without explicit ask
- **Chat** owns personal/home data — Ene queries but doesn't store
- **Ene** is the public face — handles all external communication
- **API tokens** are per-agent, stored in each host's agenix secrets
- **Tailscale ACLs** can restrict which agents talk to which (future)

## Implementation Status

- [x] Ene: Running, gateway on 18789, Tailscale Serve enabled
- [x] Rook: Running on Windows, gateway port TBD
- [ ] Chat: Offline (home machine), needs OpenClaw setup
- [ ] Inter-agent API communication
- [ ] Shared Discord channel with loop prevention
- [ ] Tailscale ACLs for agent-to-agent access
