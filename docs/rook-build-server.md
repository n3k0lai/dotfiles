# Rook build server

Rook builds for the fleet, serves a binary cache (Attic), and hosts a git forge
(Forgejo). Everything is tailnet-only: plain HTTP on `tailscale0`, which rook's
firewall trusts; nothing new is opened on LAN or WAN.

| Service | URL | Module |
| --- | --- | --- |
| Attic cache | `http://rook.bushbaby-mercat.ts.net:8190/rook` | `modules/servers/attic.nix` |
| Forgejo | `http://rook.bushbaby-mercat.ts.net:3000` (ssh: `forgejo@rook…:owner/repo.git`) | `modules/servers/git.nix` |
| Scheduled fleet builds, low-priority daemon, remote builder | — | `modules/servers/build-server.nix` |
| Client side (substituter, optional remote builder) | — | `modules/core/nix-cache.nix` |

## How builds flow

- Anything that lands in rook's `/nix/store` that isn't on cache.nixos.org is
  pushed to the `rook` cache by `attic-watch-store`. That covers the scheduled
  fleet builds from `master` (`nix-fleet-build-nightly`: rook + ene at 02:30;
  `nix-fleet-build-weekly`: kiss on Sunday 04:00, since its CUDA closure is
  not on cache.nixos.org), `--build-host rook` deploys, and remote-builder jobs.
- There is no `system.autoUpgrade` on the servers any more (it had no flake
  set and would build locally). To update: bump `flake.lock`, push, let rook
  build (or start the timer), then switch each host.
- ene never builds. Deploy it from kiss:
  ```sh
  nixos-rebuild switch --flake .#ene --build-host nicho@rook --target-host nicho@ene --sudo
  ```
  kiss evaluates, rook builds, the closure is copied to ene (or substituted
  from the cache), and ene only activates.
- kiss can keep building locally, but substitutes from rook first. Set
  `modules.core.nixCache.remoteBuilder.enable = true` to offload its builds.

## Deploy order (nothing loses its cache mid-way)

Clients only get the substituter once `modules.core.nixCache.publicKey` is set,
and that key only exists after the cache is created. So:

1. **Secrets** (on kiss, step 1 below), commit the two `.age` files.
2. **rook**: `sudo nixos-rebuild switch --flake .#rook` on rook. atticd,
   Forgejo, watch-store and the nightly timer start. ene/kiss are unaffected
   (no key yet, so no substituter).
3. **Create the cache** (step 2 below), paste the public key into
   `modules/core/nix-cache.nix`, commit.
4. **Warm the cache**: `sudo systemctl start nix-fleet-build-nightly` on rook
   (and `nix-fleet-build-weekly` before step 6, or wait for the timers).
   `journalctl -fu attic-watch-store` shows the pushes.
5. **ene** from kiss with the `--build-host` command above.
6. **kiss**: `sudo nixos-rebuild switch --flake .#kiss`.

If rook is down later, clients time out after 5 s and fall back to
cache.nixos.org or a local build (`connect-timeout = 5`, `fallback = true`).

## Cache size

Rook's NVMe root (WD SN530, 226G filesystem, ~160G free when measured) holds
the cache at `/var/lib/atticd/storage`, with a budget of about 60 GB:

- Retention is 14 days since last access, and GC runs every 6 hours.
- Only paths missing from cache.nixos.org are stored, and chunks are
  deduplicated, so normal use is the uncached part of ~14 nightly rook+ene
  builds plus 2 weekly kiss builds.
- `atticd-size-check` runs daily at 06:00 and fails (`systemctl --failed`,
  `journalctl -u atticd-size-check`) above 60 GB
  (`modules.servers.attic.sizeWarnGB`).
- If it creeps up, lower `modules.servers.attic.retention`, or per cache:
  `attic cache configure rook --retention-period '7 days'`.

Future option: rook's `sda` (931.5G Seagate ST1000LM048 laptop HDD) isn't
mounted or referenced anywhere in this repo. Formatted ext4 and mounted via
`fileSystems` (by UUID, `nofail`), it could hold the cache by pointing
`modules.servers.attic.storagePath` at it, at the cost of HDD latency.
Svalbard (`sdb`, the 3.6T WD Red, NTFS) stays unsuitable because it has no
POSIX permissions.

## Manual steps

### 1. Secrets (on kiss, in the repo)

```sh
# atticd JWT signing secret
printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="%s"\n' \
  "$(openssl genrsa -traditional 4096 | base64 -w0)" > /tmp/attic_env
agenix -e modules/servers/secrets/attic_env.age   # paste /tmp/attic_env, then shred it
shred -u /tmp/attic_env
```

`attic_push_token.age` needs atticd running, so create it after the first rook
switch (step 2). Until it exists, atticd runs and watch-store stays off.

### 2. Cache and tokens (on rook, after the first switch)

```sh
# Admin token for you (kept in your password manager, not in the repo)
sudo atticd-atticadm make-token --sub nicho --validity '1y' \
  --pull '*' --push '*' --delete '*' --create-cache '*' --configure-cache '*' \
  --configure-cache-retention '*' --destroy-cache '*'

attic login local http://127.0.0.1:8190 <admin-token>
attic cache create rook
attic cache configure rook --public        # tailnet-only, so pull needs no token
attic cache info local:rook                # copy "Public Key: rook:…"

# Push token for watch-store
sudo atticd-atticadm make-token --sub rook-watch-store --validity '2y' --pull rook --push rook
```

Then on kiss: `agenix -e modules/servers/secrets/attic_push_token.age` (paste
the token, one line), set `publicKey` in `modules/core/nix-cache.nix`, commit,
and switch rook again so watch-store starts.

The cache's signing key lives in atticd's SQLite DB. `atticd-db-backup` copies
it to `/mnt/svalbard/backups/attic` nightly; losing it means re-keying every
client.

### 3. Forgejo admin user (on rook)

```sh
forgejo-cli admin user create \
  --admin --username nicholai --email nicholai@comfy.sh --random-password
```

Log in at `http://rook.bushbaby-mercat.ts.net:3000`, change the password, add
your SSH key, and enable 2FA.

### 4. Pull mirrors of GitHub repos

Create a fine-grained GitHub token with read-only Contents (and Metadata) on
the repos to mirror; public repos need no token. Then for each repo, in the web
UI: **+ → New migration → GitHub**, paste the URL, tick **This repository will
be a mirror**, add the token, and set the interval (default 8 h). Or with the
API:

```sh
curl -sS -X POST http://rook.bushbaby-mercat.ts.net:3000/api/v1/repos/migrate \
  -H "Authorization: token <forgejo-token>" -H 'Content-Type: application/json' \
  -d '{"clone_addr":"https://github.com/n3k0lai/dotfiles","repo_name":"dotfiles",
       "repo_owner":"nicholai","service":"github","mirror":true,
       "mirror_interval":"8h","private":true,"auth_token":"<github-token>"}'
```

Suggested set: `dotfiles`, `soul`, the hermes fork (`n3k0lai/hermes`),
`waves-android`, and `horology` once it exists on GitHub.

To make Forgejo the primary later: convert a mirror to a normal repo and add
a **push** mirror back to GitHub under Settings → Repository → Mirror settings.

### 5. Optional: rook as a remote builder for kiss/ene

```sh
sudo ssh-keygen -t ed25519 -N '' -f /root/.ssh/nix-remote-builder   # on the client
```

Add the `.pub` to `modules.servers.buildServer.builderKeys` in
`hosts/rook.nix` (enables the `nix-ssh` user, forced to `nix-daemon --stdio`),
switch rook, then set `modules.core.nixCache.remoteBuilder.enable = true` on
the client. Not needed for `--build-host nicho@rook`.
