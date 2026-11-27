#!/usr/bin/env bash
# vault-state-backup: snapshot vault JSON/YAML (Obsidian Sync does not carry
# these) into a staging git repo on kiss, then push to private rook Forgejo
# and to a bare repo on ene. The Obsidian vault itself stays gitless.
#
# Safety:
#   - Never git init, and never write a .git into, the Obsidian vault.
#   - No GitHub remote. Refuses to push if a remote URL points at GitHub
#     or at a Hermes path.
#   - Normal pushes only. Never --force, never --mirror, never deletes a ref.
#   - Forgejo repo must already be private (created if missing); aborts if not.
#   - The Forgejo token is read from a mode-600 file via a git credential
#     helper; it never appears in argv or in the log.
#
# Config (env):
#   VAULT_PATH              default /home/nicho/vault/vault
#   VAULT_STATE_WORKTREE    default ~/Code/vault-state
#   ROOK_GIT_URL            default http://rook.bushbaby-mercat.ts.net:3000
#   ROOK_GIT_ORG            default n3k0lai
#   ROOK_GIT_USER           default ene
#   ROOK_GIT_TOKEN_FILE     default ~/.config/rook-git/token
#   ENE_SSH                 default ene   (existing ~/.ssh/config Host)
#   ENE_BARE                default /home/nicho/backups/vault-state.git
set -euo pipefail

VAULT_PATH=${VAULT_PATH:-/home/nicho/vault/vault}
WORKTREE=${VAULT_STATE_WORKTREE:-$HOME/Code/vault-state}
ROOK_GIT_URL=${ROOK_GIT_URL:-http://rook.bushbaby-mercat.ts.net:3000}
ROOK_GIT_ORG=${ROOK_GIT_ORG:-n3k0lai}
ROOK_GIT_USER=${ROOK_GIT_USER:-ene}
export ROOK_GIT_TOKEN_FILE=${ROOK_GIT_TOKEN_FILE:-$HOME/.config/rook-git/token}
export ROOK_GIT_USER
ENE_SSH=${ENE_SSH:-ene}
ENE_BARE=${ENE_BARE:-/home/nicho/backups/vault-state.git}
REPO_NAME=vault-state

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR $*"; exit 1; }

# git with the rook credential helper only (token read from file at call time).
HELPER='!f() { test "$1" = get || exit 0; echo "username=$ROOK_GIT_USER"; printf "password=%s\n" "$(cat "$ROOK_GIT_TOKEN_FILE")"; }; f'
rgit() { git -c credential.helper= -c "credential.helper=$HELPER" -c core.askPass=true "$@"; }

abs() { realpath -m "$1"; }

forbidden_url() {
  local u=$1
  case "$u" in
    *github.com*|*github.com:*|*gist.github*) return 0;;
    */.hermes/*|*/hermes/.hermes/*|/var/lib/hermes/*) return 0;;
  esac
  return 1
}

api() { # api METHOD PATH [JSON] -> sets $api_code and $api_body
  local m=$1 p=$2 d=${3:-} out
  api_code=000; api_body=
  out=$(curl -sS -m 30 -X "$m" -w '\n%{http_code}' \
        -H @<(printf 'Authorization: token %s\n' "$(cat "$ROOK_GIT_TOKEN_FILE")") \
        -H 'Content-Type: application/json' ${d:+--data "$d"} \
        "$ROOK_GIT_URL/api/v1$p") || return 1
  api_code=${out##*$'\n'}; api_body=${out%$'\n'*}
}

ensure_forgejo_private() {
  case "$ROOK_GIT_URL" in *github*) die "ROOK_GIT_URL points at GitHub";; esac
  [ -r "$ROOK_GIT_TOKEN_FILE" ] || die "no token at $ROOK_GIT_TOKEN_FILE"
  api GET "/repos/$ROOK_GIT_ORG/$REPO_NAME"
  if [ "$api_code" = 404 ]; then
    api POST "/orgs/$ROOK_GIT_ORG/repos" \
      "{\"name\":\"$REPO_NAME\",\"private\":true,\"auto_init\":false,\"description\":\"Kiss-only vault JSON/YAML skill-state backup. No GitHub. ITAR/PII: keep private and off China-hosted services.\"}"
    [ "$api_code" = 201 ] || die "Forgejo create failed (HTTP $api_code)"
    log "created private $ROOK_GIT_ORG/$REPO_NAME on rook git"
  elif [ "$api_code" != 200 ]; then
    die "Forgejo repo lookup failed (HTTP $api_code)"
  fi
  [ "$(printf '%s' "$api_body" | jq -r .private)" = true ] \
    || die "$ROOK_GIT_ORG/$REPO_NAME is NOT private on rook git; refusing to push"
}

ene_bash() {
  # ene's login shell is fish; send bash on stdin so fish never parses the script.
  ssh -o BatchMode=yes -o ConnectTimeout=15 "$ENE_SSH" bash -s -- "$@"
}

ensure_ene_bare() {
  case "$ENE_BARE" in
    */.hermes/*|/var/lib/hermes/*) die "ENE_BARE is a Hermes path: $ENE_BARE";;
  esac
  ene_bash "$ENE_BARE" << 'EOF'
set -euo pipefail
bare=$1
case "$bare" in */.hermes/*|/var/lib/hermes/*) echo "ERROR hermes path" >&2; exit 2;; esac
mkdir -p "$(dirname "$bare")"
chmod 700 "$(dirname "$bare")" 2>/dev/null || true
if [ ! -d "$bare" ]; then
  git init --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/master
  echo "created bare $bare"
else
  git -C "$bare" rev-parse --is-bare-repository >/dev/null
fi
chmod 700 "$bare" 2>/dev/null || true
EOF
}

write_readme() {
  local f=$WORKTREE/README.md
  [ -f "$f" ] && return 0
  cat > "$f" << 'EOF'
# vault-state

Private backup of JSON and YAML skill-state from Nicholai's Obsidian vault
on kiss (`/home/nicho/vault/vault`). Obsidian Sync does not carry these
types (only md/canvas/base plus image, audio, PDF and video).

This repo is **not** the vault. The vault stays gitless. A timer on kiss
rsyncs the files into `vault/` here, commits when something changed, and
pushes to two private remotes:

- `rook` — rook Forgejo, tailnet only: `n3k0lai/vault-state`
- `ene` — bare repo on the ene VPS: `/home/nicho/backups/vault-state.git`

There is no GitHub remote. Do not add one.

## Sensitivity

This tree includes:

- Artemis loadout and law-annotation YAML (ITAR / no-China lane)
- Shooting session logs
- Yoga class rosters with student names
- Personal health and food registries
- Tarot, lifting, grocery, interns, and related skill state

Keep it private, on his own machines, and **off GitHub and any
China-hosted service**.

## Schedule

`vault-state-backup.timer` runs every 4 hours at :15 (America/New_York)
once the kiss Nix module is enabled. Until then, run
`vault-state-backup` by hand (or the script in the dotfiles branch).

## Restore

```bash
git clone http://rook.bushbaby-mercat.ts.net:3000/n3k0lai/vault-state.git /tmp/vault-state
# or: git clone ene:/home/nicho/backups/vault-state.git /tmp/vault-state
rsync -a /tmp/vault-state/vault/ /home/nicho/vault/vault/
```

That only writes JSON/YAML (and the restore manifest). It will not
overwrite Markdown notes. Review a known file before deleting `/tmp/vault-state`.

Full plan: `Meta/grokbot/vault-state-backup.md` and
`Meta/grokbot/restores/vault-backup-plan.md` in the vault.
EOF
}

[ "$(id -u)" -ne 0 ] || die "refusing to run as root"
[ -d "$VAULT_PATH" ] || die "vault not found: $VAULT_PATH"

vault_abs=$(abs "$VAULT_PATH")
work_abs=$(abs "$WORKTREE")
case "$work_abs/" in
  "$vault_abs"|"$vault_abs"/*) die "worktree resolves inside the vault ($work_abs); refusing to git init here";;
esac
case "$vault_abs/" in
  "$work_abs"/*) die "vault resolves inside the worktree ($vault_abs)";;
esac
# Hard stop: never create .git in the vault, even if paths later change.
[ ! -e "$vault_abs/.git" ] || log "WARNING: $vault_abs/.git already exists (this script did not create it and will not touch it)"

command -v rsync >/dev/null && command -v git >/dev/null && command -v curl >/dev/null && command -v jq >/dev/null \
  || die "need rsync, git, curl, and jq"

mkdir -p "$(dirname "$WORKTREE")"
mkdir -p "$WORKTREE"
chmod 700 "$WORKTREE"

lockdir=${XDG_CACHE_HOME:-$HOME/.cache}/vault-state-backup
mkdir -p "$lockdir"
exec 9>"$lockdir/lock"
flock -n 9 || { log "another vault-state-backup is running"; exit 0; }

ensure_forgejo_private
ensure_ene_bare

if [ ! -d "$WORKTREE/.git" ]; then
  git init -b master "$WORKTREE"
  log "initialized staging repo at $WORKTREE"
fi

git -C "$WORKTREE" config user.name "vault-state-backup"
git -C "$WORKTREE" config user.email "ene@comfy.sh"
git -C "$WORKTREE" symbolic-ref HEAD refs/heads/master >/dev/null

# Remotes: rook = Forgejo HTTP (token helper), ene = existing SSH host. Never GitHub.
rook_url="$ROOK_GIT_URL/$ROOK_GIT_ORG/$REPO_NAME.git"
ene_url="$ENE_SSH:$ENE_BARE"
forbidden_url "$rook_url" && die "rook remote URL is forbidden: $rook_url"
forbidden_url "$ene_url" && die "ene remote URL is forbidden: $ene_url"

if git -C "$WORKTREE" remote get-url rook >/dev/null 2>&1; then
  git -C "$WORKTREE" remote set-url rook "$rook_url"
else
  git -C "$WORKTREE" remote add rook "$rook_url"
fi
if git -C "$WORKTREE" remote get-url ene >/dev/null 2>&1; then
  git -C "$WORKTREE" remote set-url ene "$ene_url"
else
  git -C "$WORKTREE" remote add ene "$ene_url"
fi

# Refuse a GitHub (or Hermes) remote if one was added by hand.
while read -r name url; do
  [ -n "${name:-}" ] || continue
  forbidden_url "$url" && die "remote $name points at a forbidden URL; refusing to run"
done < <(git -C "$WORKTREE" remote -v | awk '{print $1, $2}')

write_readme
if [ ! -f "$WORKTREE/.gitignore" ]; then
  printf '%s\n' '.backup.lock' '.backup.lock~' > "$WORKTREE/.gitignore"
fi
# Drop a lockfile if an earlier run committed it into the worktree.
rm -f "$WORKTREE/.backup.lock"

mkdir -p "$WORKTREE/vault"
# --delete applies only under dest vault/, so the staging repo's .git is safe.
# Includes every JSON/YAML (emote-library data included) plus the restore manifest.
rsync -a --delete --prune-empty-dirs \
  --exclude '.obsidian/' \
  --exclude '.trash/' \
  --exclude '.git/' \
  --include '*/' \
  --include '*.json' \
  --include '*.yaml' \
  --include '*.yml' \
  --include 'Meta/grokbot/restores/vault-skill-state-MANIFEST.txt' \
  --exclude '*' \
  "$vault_abs/" \
  "$WORKTREE/vault/"

git -C "$WORKTREE" add -A
if [ -z "$(git -C "$WORKTREE" status --porcelain)" ]; then
  log "up to date; nothing to commit"
else
  tz_now=$(date '+%Y-%m-%d %H:%M %Z')
  file_count=$(git -C "$WORKTREE" ls-files 'vault/' | wc -l)
  git -C "$WORKTREE" commit -m "vault-state: snapshot ${tz_now} (${file_count} files)"
  log "committed $file_count files at $tz_now"
fi

head=$(git -C "$WORKTREE" rev-parse HEAD)
log "local HEAD ${head:0:12}"

# Normal pushes only.
rgit -C "$WORKTREE" push --porcelain --no-verify rook HEAD:master \
  || die "push to rook Forgejo failed"
log "pushed to rook"

GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15" \
  git -C "$WORKTREE" push --porcelain --no-verify ene HEAD:master \
  || die "push to ene failed"
log "pushed to ene"

rook_head=$(rgit -C "$WORKTREE" ls-remote rook refs/heads/master | awk '{print $1}')
ene_head=$(GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15" \
  git -C "$WORKTREE" ls-remote ene refs/heads/master | awk '{print $1}')
log "rook HEAD ${rook_head:0:12}"
log "ene  HEAD ${ene_head:0:12}"
[ "$head" = "$rook_head" ] && [ "$head" = "$ene_head" ] \
  || die "HEAD mismatch: local=$head rook=$rook_head ene=$ene_head"
log "ok: local, rook, and ene HEAD match"
