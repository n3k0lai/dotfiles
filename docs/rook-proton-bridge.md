# Proton Mail Bridge on rook

Headless Bridge so Ene can read Proton mail for the morning report without
forwarding anything to Gmail. Module: `modules/servers/proton.nix`, enabled
in `hosts/rook.nix` as `modules.servers.protonmailBridge`.

nixpkgs and home-manager both ship `services.protonmail-bridge`, but those
units are systemd user services tied to `graphical-session.target`. Rook is
a headless box, so this module runs a system service as a dedicated user
(`proton-bridge`, home `/var/lib/proton-bridge`) with
`protonmail-bridge --noninteractive`.

The package is nixpkgs `protonmail-bridge` (binary of the same name).

## Keychain

Bridge needs a keychain. On a desktop that is usually secret-service
(gnome-keyring). On rook there is no session bus, so the service uses
`pass` plus a passphrase-free GPG key owned by `proton-bridge`.

That key only wraps Bridge's local vault (session tokens), not the Proton
account password. The home directory is mode 0700. This is the usual
headless setup; a passphrase-protected key would stall the unit waiting
for pinentry.

## Listen address

Bridge defaults to `127.0.0.1:1143` (IMAP) and `127.0.0.1:1025` (SMTP),
STARTTLS with a self-signed certificate. This module does not patch the
bind host and does not open any firewall ports, including on `tailscale0`.
The sockets serve decrypted mail, so they stay on localhost.

## How Ene reaches it later

Nothing in this change grants Ene or the Rook bot access. After login,
pick one of:

- **SSH tunnel** (preferred while the morning report still runs off rook).
  From the host that should read mail, with a key that can SSH to rook
  (nicho, or grokbot-rook if you later allow it):

  ```sh
  ssh -N -L 1143:127.0.0.1:1143 -L 1025:127.0.0.1:1025 nicho@rook
  ```

  Then IMAP/SMTP are `127.0.0.1:1143` / `127.0.0.1:1025`. Username is the
  Proton address. Password is the per-device Bridge password from `info`
  (store it in agenix; see below). Clients must accept Bridge's self-signed
  STARTTLS cert.

- **Read on rook itself**, against localhost, if you later move the morning
  report there or ask the Rook bot to do it. That is a separate decision;
  this branch does not tell Rook or add mail sudo rules for `grokbot-rook`.

Do not use `tailscale serve` (hermes resets it) and do not publish 1143/1025
on the tailnet.

## Deploy

On your usual checkout (often `~/Code/nix` or `~/dotfiles`):

```sh
cd ~/Code/nix && git fetch origin && git merge origin/ene/rook-proton-bridge
```

Then rebuild rook. On rook:

```sh
sudo nixos-rebuild switch --flake ~/Code/nix#rook
```

Or from kiss, after the merge:

```sh
nixos-rebuild switch --flake .#rook --build-host nicho@rook --target-host nicho@rook --sudo
```

The unit stays inactive until the pass store exists
(`ConditionPathExists` on `/var/lib/proton-bridge/.password-store/.gpg-id`).

Bridge requires a paid Proton plan (Mail Plus or above). Free accounts
cannot log in.

## One-time login (on rook, after the switch)

You need a real terminal. The CLI hangs without a tty, and it cannot run
while the daemon holds the lock.

```sh
# 1. Create the passphrase-free GPG key and pass store for proton-bridge.
sudo proton-bridge-setup

# 2. Stop the daemon if it is up, open the CLI, start the daemon on exit.
#    From another host: ssh -t rook sudo proton-bridge-cli
sudo proton-bridge-cli
```

At the `>>>` prompt:

```
login
```

Enter the Proton username, password, and 2FA if asked. Then:

```
info
```

`info` prints the localhost IMAP/SMTP settings and the **per-device Bridge
password**. That is not your Proton password. Copy it somewhere private
(the terminal only; do not paste it into chat or a commit). Then `exit`.

The wrapper starts `protonmail-bridge.service` when you leave the CLI.
Confirm the localhost listeners:

```sh
sudo systemctl status protonmail-bridge
ss -ltn | grep -E '127.0.0.1:(1143|1025)'
```

Expected: `127.0.0.1:1143` and `127.0.0.1:1025` only.

To use the CLI again later (change settings, re-login), always go through
`sudo proton-bridge-cli` so the daemon is stopped first.

## Store the Bridge password in agenix (your hands only)

On kiss, in the repo, create the secret yourself. One line, no newline,
recipients `rook` and `nicho`:

```sh
agenix -e modules/servers/secrets/proton_bridge_password.age
```

Then uncomment the matching entry in `secrets.nix` (it is left commented
as a placeholder so a missing `.age` file cannot break a rebuild) and
commit. This module does not decrypt or require that file; it is for
Ene's mail client later.

## Checks

```sh
journalctl -u protonmail-bridge -e
```
