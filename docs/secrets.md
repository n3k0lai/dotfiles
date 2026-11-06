# Secrets and host keys

Agenix rules live in `secrets.nix` (paths + recipients). Public keys are in
`secrets-keys.nix`. Encrypted files stay next to those paths.

## Identity paths

Each host decrypts with, in order of preference:

1. `/etc/ssh/host_ed25519` — dedicated host key (hlissner-style), used on
   new installs provisioned by `push-keys`
2. `/etc/ssh/ssh_host_ed25519_key` — the existing NixOS SSH host key

Do not remove path 2 on live hosts. Re-encrypting secrets is not required
as long as that key stays in `age.identityPaths`.

The `agenix` wrapper on PATH adds `--identity` when you omit it, and sets
`AGENIX_RULES` to `./secrets.nix` when you run it from a checkout.

`modules.agenix` also materializes `age.secrets` for every `secrets.nix`
entry whose `publicKeys` list includes this host's key from
`secrets-keys.nix`. Existing `age.secrets` declarations keep their `owner`,
`mode`, `path`, and `symlink` attrs; they merge with the auto-mapped `file`.

## Bitwarden items (create these yourself)

Nothing is written to Bitwarden automatically. Use `rbw` after you log in
(`rbw login`, `rbw unlock`). Suggested item names:

| Item name | What to store |
| --- | --- |
| `dotfiles/host-key/<hostname>` | Private key for `/etc/ssh/host_ed25519`. Put the OpenSSH private key in the item **password** field (or the **notes** field). Optional custom field `public_key`. |
| `dotfiles/age-identity/nicho` | Personal identity used to edit secrets (`nicho` in `secrets-keys.nix`). Same storage as above. Copied to `~/.config/age/identity` on the target if the item exists. |

`<hostname>` matches NixOS `networking.hostName` (`kiss`, `ene`, `rook`,
`blade`, `artemis`, `pati0`, …).

## Bootstrap a new host

From a machine where `rbw` already works:

```
push-keys rook
# or: push-keys rook root@192.0.2.5   # any reachable SSH target
```

`push-keys` fetches those items and copies them before the first
`nixos-rebuild`. It never creates or updates Bitwarden items.

## Private inventory

LAN IPs, Tailscale host IPs, MACs, and network labels: see
`modules/private/README.md` and `n3k0lai/dotfiles-private`.
