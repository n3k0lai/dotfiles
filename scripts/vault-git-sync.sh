#!/usr/bin/env bash
# vault-git-sync: relaxed two-way sync between the kiss Obsidian vault and
# the private GitHub repo n3k0lai/vault. Runs from a user timer (every 20 min).
#
#   add -A -> gitleaks protect --staged (abort on hit) -> commit as nicholai
#   -> pull --rebase -> (conflict: rebase --abort, write marker, stop) -> push
#
# Never force-pushes, never resets, never discards local edits. If the marker
# file exists, the run is skipped until Nicholai or Ene deletes it.
set -uo pipefail

VAULT_DIR="${VAULT_DIR:-$HOME/vault/vault}"
BRANCH="${VAULT_BRANCH:-main}"
MARKER_REL="Meta/vault-sync-conflict.md"
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=20}"
export GIT_TERMINAL_PROMPT=0

log() { printf 'vault-git-sync: %s\n' "$*"; }

cd "$VAULT_DIR" || { log "vault dir missing: $VAULT_DIR"; exit 1; }
[ -d .git ] || { log "not a git working copy: $VAULT_DIR"; exit 1; }

# Single instance (timer overlap, manual runs)
exec 9>.git/vault-git-sync.lock
flock -n 9 || { log "another run is active, skipping"; exit 0; }

MARKER="$VAULT_DIR/$MARKER_REL"
if [ -e "$MARKER" ]; then
  log "marker $MARKER_REL exists; skipping until it is deleted"
  exit 0
fi

write_marker() { # $1 = reason, $2 = detail
  mkdir -p "$(dirname "$MARKER")"
  {
    printf '# Vault sync stopped\n\n'
    printf -- '- When: %s\n- Host: %s\n- Reason: %s\n\n' "$(date '+%Y-%m-%d %H:%M %Z')" "$(hostname)" "$1"
    printf '%s\n\n' "$2"
    printf 'Sync skips every run while this file exists. Fix the cause, then delete this file.\n'
    printf 'Local commits are safe (nothing was reset or force-pushed). Check `git status` and `git log origin/%s..HEAD` in the vault.\n' "$BRANCH"
  } > "$MARKER"
}

if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -e .git/MERGE_HEAD ]; then
  write_marker "unfinished rebase/merge found" "A previous git operation was left half-done in the vault."
  log "unfinished rebase/merge; wrote marker"
  exit 1
fi

[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = "$BRANCH" ] || {
  write_marker "wrong branch" "Vault is not on $BRANCH."
  log "not on $BRANCH; wrote marker"; exit 1; }

# 1. Stage everything not ignored
git add -A || { log "git add failed"; exit 1; }

# 2. Secret scan on exactly what would be committed
if ! git diff --cached --quiet; then
  if ! gitleaks protect --staged --redact --verbose --no-color --no-banner >/tmp/vault-git-sync-leaks.$$ 2>&1; then
    summary="$(grep -E '^(RuleID|File|Line):' /tmp/vault-git-sync-leaks.$$ | head -30)"
    rm -f /tmp/vault-git-sync-leaks.$$
    git restore --staged . 2>/dev/null || true   # unstage only; files untouched
    write_marker "gitleaks found possible secrets in staged changes" "Findings (values redacted):

$summary"
    log "gitleaks hit; unstaged, wrote marker, aborting"
    exit 1
  fi
  rm -f /tmp/vault-git-sync-leaks.$$

  # 3. Commit as nicholai
  git -c user.name=nicholai -c user.email=nicholai@comfy.sh \
    commit -q -m "vault sync $(hostname) $(date '+%Y-%m-%d %H:%M')" \
    || { log "commit failed"; exit 1; }
  log "committed local changes"
fi

# 4. Bring in remote changes (Ene, other bots)
if ! git pull --rebase --no-edit origin "$BRANCH" >/tmp/vault-git-sync-pull.$$ 2>&1; then
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    conflicted="$(git diff --name-only --diff-filter=U | head -50)"
    git rebase --abort
    write_marker "rebase conflict with origin/$BRANCH" "Conflicting files:

$conflicted"
    log "conflict; rebase aborted, wrote marker"
    rm -f /tmp/vault-git-sync-pull.$$
    exit 1
  fi
  # Not a conflict (offline, auth, remote down): try again next tick
  log "pull failed, will retry next run: $(tail -n 2 /tmp/vault-git-sync-pull.$$ | tr '\n' ' ')"
  rm -f /tmp/vault-git-sync-pull.$$
  exit 0
fi
rm -f /tmp/vault-git-sync-pull.$$

# 5. Normal push (never --force)
if [ -n "$(git log "origin/$BRANCH..HEAD" --oneline 2>/dev/null)" ]; then
  git push origin "HEAD:$BRANCH" || { log "push failed, will retry next run"; exit 0; }
  log "pushed"
else
  log "nothing to push"
fi
