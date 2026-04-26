# Agent Mesh Architecture

Two peer agents on a Tailscale mesh. Each owns a domain and communicates
via Hermes gateway APIs over the tailnet.

## Agents

### Ene (Project Manager)
- **Host:** DigitalOcean VPS (NixOS)
- **Tailscale:** ene-1 / `<ENE_TAILSCALE_IP>`
- **Gateway:** port 18789
- **Always-on:** Yes (VPS)
- **Scope:** Public infrastructure, email (ene@comfy.sh), Google Calendar,
  Gmail (theguy@itsnicholai.fyi), Discord, coordination between agents
- **Role:** Secretary/PM. Knows about everything, delegates to specialists.
  Does NOT hold confidential work data or local home data.

### Rook (Work + Home)
- **Host:** Home Linux machine (NixOS, formerly Chat)
- **Tailscale:** rook / `<ROOK_TAILSCALE_IP>`
- **Gateway:** port 18789
- **Always-on:** Yes (home server)
- **Scope:** Work tasks, coding agents, Slack/ADO integration, confidential work
  projects, Obsidian vault, home automation, physical location data, local files
- **Role:** Work specialist and home guardian. Handles everything money-making
  and employer-related, plus owns the knowledge base (Obsidian), location context,
  and anything tied to physical space. Confidential by default.

## Communication Model

```
        Ene (PM/coordinator)
              /         \
       Personal       Work/Home
      (questions)    (Rook)
```

- **Ene ↔ Rook:** Ene can ask Rook for work status updates, delegate coding tasks.
  Rook reports progress. Rook does NOT share confidential details unprompted.
  Ene can also query Rook for Obsidian notes, location context, home status.
  Rook provides data for Ene's scheduling/calendar decisions.

## Transport

Each agent runs a Hermes gateway. Communication options:

### Option A: Node Pairing (subordinate)
One gateway registers as a node of another. Gives command execution
access but creates a hierarchy. NOT recommended for peer mesh.

### Option B: Gateway API (peer)
Each gateway exposes its API on the tailnet. Agents send messages to
each other's sessions via HTTP.

```bash
# Ene sends a message to Rook's main session
curl -X POST http://<ROOK_TAILSCALE_IP>:<port>/api/sessions/send \
  -H "Authorization: Bearer *** \
  -d '{"sessionKey":"agent:main:main","message":"Hey Rook, status update?"}'
```

### Option C: Shared Discord Channel (simple)
Both agents in a Discord channel. Mention-based responses only.
Simplest but least structured. Good for casual coordination.

## Recommended: Hybrid

1. **Discord** for casual multi-agent chat (mention-only, no auto-reply loops)
2. **Gateway API** for structured task delegation and status reports
3. **Shared git repo** (dotfiles) for configuration and documentation sync

## Security Boundaries

- **Rook** never leaks work data to Discord or other agents without explicit ask
- **Rook** owns personal/home data — Ene queries but doesn't store
- **Ene** is the public face — handles all external communication
- **API tokens** are per-agent, stored in each host's agenix secrets
- **Tailscale ACLs** can restrict which agents talk to which (future)

## Implementation Status

- [x] Ene: Running, gateway on 18789, Tailscale Serve enabled
- [x] Rook: Running on home server, gateway on 18789, Hermes Agent
- [ ] Inter-agent API communication
- [ ] Shared Discord channel with loop prevention
- [ ] Tailscale ACLs for agent-to-agent access
