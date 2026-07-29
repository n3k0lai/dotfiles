# Hermes agent-browser on NixOS (ene) — durable fix

**Host:** ene · **User:** hermes · **Date locked in:** 2026-07-29

## Root cause

1. Hermes browser tools shell out to the **agent-browser** CLI even when
   `cloud_provider` is browser-use / Browserbase (`BROWSER_USE_API_KEY` is
   necessary but not sufficient).
2. Resolution order in Hermes (`tools/browser_tool.py` → `_find_agent_browser`):
   `shutil.which("agent-browser")` → extended PATH → local node_modules →
   **`npx agent-browser` fallback**.
3. `npx` installs a **fresh generic Linux ELF** under
   `/var/lib/hermes/.npm/_npx/<hash>/…/agent-browser-linux-x64`.
4. NixOS has no FHS `/lib64/ld-linux-x86-64.so.2`. Unpatched ELFs die with:
   `Could not start dynamically linked executable` (stub-ld).
5. Historical oneshot `hermes-agent-browser-fix.service` used
   `RemainAfterExit=true` **without** `PartOf=hermes-agent.service`, so after
   the first success (e.g. 2026-07-07) restarts of hermes-agent **did not**
   re-run the patcher when new npx drops appeared.
6. `systemd.services.hermes-agent.environment = lib.mkForce { … }` wiped the
   `PATH` synthesized from `path = [ agentBrowserWrapper … ]`, so the gateway
   never saw the Nix wrapper and always fell through toward npx.

## Why oneshot / activation alone fail long-term

| Mechanism | When it runs | Misses |
|-----------|--------------|--------|
| `system.activationScripts.hermes-browser-fix` | `nixos-rebuild switch` | Mid-session npx; agent restarts without rebuild |
| oneshot + `RemainAfterExit` only | First pull-in while unit is inactive | Agent restart while unit still "active (exited)" |
| Bulk fix at boot only | Boot / start | New `.npm/_npx/*` tree created by tool use |

## Ranked durable design

### 1. **Chosen: layered fix (wrapper + PATH + re-run)** — implement in `hermes.nix`

| Layer | Role |
|-------|------|
| **A. Patch-before-exec wrapper** | `agent-browser` store script always `patchelf`s the chosen native, then `exec`s. Covers new npx drops **at tool invoke time**. |
| **B. Re-run bulk fix on agent start** | `PartOf=hermes-agent.service` on the oneshot + `ExecStartPre=hermes-browser-fix` (store-pinned paths). |
| **C. PATH ordering** | `path = lib.mkBefore [ agentBrowserWrapper … ]` and **no** whole-`environment` `mkForce` (per-key only). Hermes finds wrapper → runnable `--version` → never npx. |
| **D. Soft pin** | Provision installs `agent-browser@0.33.1` into npm-global when native missing (not `command -v`, which hits the wrapper). |

**Tradeoffs:** Wrapper pays a tiny `find`+`patchelf --print-interpreter` cost per invoke (noop when already patched). Does not ban npx globally (other tools may use it); browser path simply never needs it.

### 2. Ban npx for browser only (harder)

Force `AGENT_BROWSER` / patch Hermes to never use npx fallback. Requires upstream or a venv overlay; higher maintenance.

### 3. path unit on `~/.npm/_npx`

`PathExistsGlob` / inotify re-run fix on every drop. More moving parts; wrapper already covers exec time.

### 4. Fully FHS / buildFHSEnv for agent-browser

Heavy; unnecessary once interpreter is patched.

## Concrete pieces in `hermes.nix`

- `agentBrowserFix` — bulk `patchelf --set-interpreter` + chromium `config.json`
- `agentBrowserWrapper` — newest native by mtime, **patch-before-exec**
- `agentBrowserProvision` — install pinned native if missing
- `hermes-agent-browser-fix.service` — `PartOf=hermes-agent.service`
- `hermes-agent.service` — `ExecStartPre=…/hermes-browser-fix`, `path = mkBefore [ wrapper … ]`

## Smoke test (nicho / fish on ene)

After `sudo nixos-rebuild switch --flake ~/dotfiles#ene` (or your usual path):

```fish
# 1) Wrapper is first and runnable
sudo -u hermes bash -lc 'type -a agent-browser; agent-browser --version'

# 2) Gateway PATH includes wrapper (after restart)
systemctl restart hermes-agent
systemctl show hermes-agent -p Environment --value | tr ' ' '\n' | grep PATH=
# expect …-agent-browser/bin early in PATH

# 3) Unpatched binary gets healed by wrapper (simulate)
set bin (sudo -u hermes bash -lc 'find /var/lib/hermes/.npm -name agent-browser-linux-x64 -type f | head -1')
# optional: only if you can restore from a known-good later
# sudo patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 $bin  # will fail on NixOS intentionally
sudo -u hermes agent-browser --version   # wrapper should re-patch

# 4) Browser tool path (cloud key already in ~/.hermes/.env)
# From chat: browser_navigate to https://example.com — expect success, not stub-ld.

# 5) Oneshot re-runs with agent (not stuck for weeks)
systemctl stop hermes-agent
systemctl status hermes-agent-browser-fix --no-pager   # should be inactive after PartOf
systemctl start hermes-agent
systemctl status hermes-agent-browser-fix --no-pager   # active (exited), recent timestamp
```

One-liner post-incident:

```fish
sudo -u hermes /run/current-system/sw/bin/hermes-browser-fix; and sudo systemctl restart hermes-agent
```

(`hermes-browser-fix` is on the profile if packaged; otherwise use the store path from `systemctl cat hermes-agent-browser-fix`.)

## Secrets

Do **not** put `BROWSER_USE_API_KEY` (or any keys) in this repo. Gateway loads
`EnvironmentFile=-/var/lib/hermes/.hermes/.env` plus agenix `hermes-env`.

## Related commits / history

- Initial patchelf + wrapper (2026-06)
- `.env` load + path attempts (2026-07-20) — still broken under `environment mkForce`
- This durable stack (2026-07-29): patch-before-exec + PartOf + PATH fix
