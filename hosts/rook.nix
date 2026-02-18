# Rook's domain — Nicholai's work Windows PC.
# Not a NixOS host (yet), but documents the machine's role and Rook's setup.
# Rook is an OpenClaw AI instance managing the work environment.
#
# Machine: Windows workstation (Tailscale: "work", 100.95.242.40)
# WSL:     Tailscale: "work-wsl" (when active)
# Agent:   Rook (OpenClaw instance)
# Scope:   Work tasks, coding agents, CI/CD, dev environment
#
# Communication:
#   Ene (ene.comfy.sh) and Rook share the same human (Nicholai) but have
#   separate domains. They coordinate via Discord or shared docs, not SSH.
#   - Ene: VPS, personal infra, email, calendar, Minecraft, public services
#   - Rook: Work PC, coding agents, dev tools, work projects
#
# Grok Integration:
#   Same proxy approach as ene — see modules/servers/clawd.nix comments
#   and memory/grok-setup-guide.md for setup instructions.
#
# Future:
#   - WSL NixOS config (if work-wsl becomes managed)
#   - Cross-agent communication protocol (Ene ↔ Rook)
#   - Shared memory/context via synced workspace files
{ ... }:

{
  # Placeholder — uncomment when/if WSL gets NixOS-managed
  # imports = [];
  # networking.hostName = "rook";
}
