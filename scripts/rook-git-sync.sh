#!/usr/bin/env bash
# rook-git-sync: back up core repos to rook git (Forgejo on rook, tailnet-only),
# so nothing depends on GitHub alone.
#
# For each repo it fetches GitHub (if any) and the local clones into a bare
# cache under ~/.cache/rook-git-sync, picks the newest commit for every branch,
# and pushes branches and tags to http://rook...:3000/<org>/<name>.git.
#
# Safety:
#   - Normal pushes only. Never --force, never --mirror, never deletes a ref.
#     A branch or tag that would need a force is logged as SKIP and left alone.
#   - Every rook repo is created private, and the script refuses to push to one
#     that the API does not report as private.
#   - The only push target is rook git. Local-only repos (magination) are read
#     from their working tree and never pushed anywhere else.
#   - The token is read from a file (mode 600) via a git credential helper and a
#     curl header file; it never appears in argv or in the log.
#
# Config (env):
#   ROOK_GIT_URL        default http://rook.bushbaby-mercat.ts.net:3000
#   ROOK_GIT_ORG        default n3k0lai
#   ROOK_GIT_USER       default ene
#   ROOK_GIT_TOKEN_FILE default ~/.config/rook-git/token
#   ROOK_GIT_REPOS      default ~/.config/rook-git/repos (falls back to the list below)
#   ROOK_GIT_CACHE      default ~/.cache/rook-git-sync
#
# Repo list format, one per line:  name|github owner/repo or -|local paths (space separated)
# Usage: rook-git-sync [name ...]   (no args = all repos)
set -uo pipefail

ROOK_GIT_URL=${ROOK_GIT_URL:-http://rook.bushbaby-mercat.ts.net:3000}
ROOK_GIT_ORG=${ROOK_GIT_ORG:-n3k0lai}
ROOK_GIT_USER=${ROOK_GIT_USER:-ene}
export ROOK_GIT_TOKEN_FILE=${ROOK_GIT_TOKEN_FILE:-$HOME/.config/rook-git/token}
ROOK_GIT_REPOS=${ROOK_GIT_REPOS:-$HOME/.config/rook-git/repos}
ROOK_GIT_CACHE=${ROOK_GIT_CACHE:-$HOME/.cache/rook-git-sync}
export ROOK_GIT_USER

DEFAULT_REPOS='
magirecomp|n3k0lai/magirecomp|~/Code/magirecomp
tunes|n3k0lai/tunes|~/Code/tunes
soul|n3k0lai/soul|~/soul ~/Code/soul
dotfiles|n3k0lai/dotfiles|~/dotfiles
hermes|n3k0lai/hermes|
saves|-|~/saves
magination|-|~/Code/magination
'

case "$ROOK_GIT_URL" in *github*) echo "refusing: ROOK_GIT_URL points at GitHub" >&2; exit 2;; esac
[ -r "$ROOK_GIT_TOKEN_FILE" ] || { echo "no token at $ROOK_GIT_TOKEN_FILE" >&2; exit 2; }

errors=0; skips=0
log()  { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
warn() { log "SKIP $*"; skips=$((skips+1)); }
err()  { log "ERROR $*"; errors=$((errors+1)); }

# git with the rook credential helper only (token read from file at call time).
HELPER='!f() { test "$1" = get || exit 0; echo "username=$ROOK_GIT_USER"; printf "password=%s\n" "$(cat "$ROOK_GIT_TOKEN_FILE")"; }; f'
rgit() { git -c credential.helper= -c "credential.helper=$HELPER" -c core.askPass=true "$@"; }

api() { # api METHOD PATH [JSON] -> sets $api_code and $api_body (no subshell)
  local m=$1 p=$2 d=${3:-} out
  api_code=000; api_body=
  out=$(curl -sS -m 30 -X "$m" -w '\n%{http_code}' \
        -H @<(printf 'Authorization: token %s\n' "$(cat "$ROOK_GIT_TOKEN_FILE")") \
        -H 'Content-Type: application/json' ${d:+--data "$d"} \
        "$ROOK_GIT_URL/api/v1$p") || return 1
  api_code=${out##*$'\n'}; api_body=${out%$'\n'*}
}

ensure_repo() { # name -> 0 if private repo exists (creating it if needed)
  local name=$1
  api GET "/repos/$ROOK_GIT_ORG/$name"
  if [ "$api_code" = 404 ]; then
    api POST "/orgs/$ROOK_GIT_ORG/repos" \
      "{\"name\":\"$name\",\"private\":true,\"description\":\"Backup, synced from kiss by rook-git-sync\"}"
    [ "$api_code" = 201 ] || { err "$name: create failed ($api_code)"; return 1; }
    log "$name: created private repo $ROOK_GIT_ORG/$name"
  elif [ "$api_code" != 200 ]; then
    err "$name: repo lookup failed ($api_code)"; return 1
  fi
  [ "$(printf '%s' "$api_body" | jq -r .private)" = true ] \
    || { err "$name: $ROOK_GIT_ORG/$name is NOT private on rook git; refusing to push"; return 1; }
}

expand() { case "$1" in "~"/*) printf '%s' "$HOME/${1#\~/}";; *) printf '%s' "$1";; esac; }

sync_repo() { # name github locals...
  local name=$1 gh=$2; shift 2
  local cache="$ROOK_GIT_CACHE/$name.git" have_src=0 i=0 p
  ensure_repo "$name" || return
  [ -d "$cache" ] || git init -q --bare "$cache"
  local G=(git -C "$cache")
  "${G[@]}" config remote.rook.url "$ROOK_GIT_URL/$ROOK_GIT_ORG/$name.git"

  if [ "$gh" != - ]; then
    if "${G[@]}" fetch -q --prune --no-tags "git@github.com:$gh.git" \
         '+refs/heads/*:refs/src/gh/heads/*' '+refs/tags/*:refs/src/gh/tags/*' 2>&1; then
      have_src=1
    else err "$name: fetch from GitHub $gh failed"; fi
  fi
  for p in "$@"; do
    p=$(expand "$p"); i=$((i+1))
    [ -d "$p" ] && git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || { [ "$gh" = - ] && log "$name: no local repo at $p yet"; continue; }
    if "${G[@]}" fetch -q --prune --no-tags "$p" \
         "+refs/heads/*:refs/src/l$i/heads/*" "+refs/tags/*:refs/src/l$i/tags/*" 2>&1; then
      have_src=1
    else err "$name: fetch from $p failed"; fi
  done
  [ $have_src = 1 ] || { log "$name: no source yet, repo ready and empty"; return; }
  rgit -C "$cache" fetch -q --prune --no-tags rook \
    '+refs/heads/*:refs/rook/heads/*' '+refs/tags/*:refs/rook/tags/*' 2>&1 \
    || { err "$name: fetch from rook failed"; return; }

  local -A best=() tag=()
  local ref sha src b cur rk specs=()
  # Branches: GitHub first, then local clones; take a local one only if it is
  # a fast-forward of what we have. A diverged local branch is kept as
  # kiss/<branch> so its commits are still backed up.
  while read -r sha ref; do
    src=${ref#refs/src/}; src=${src%%/*}
    case "$ref" in "refs/src/$src/heads/"*) b=${ref#refs/src/"$src"/heads/};; *) continue;; esac
    cur=${best[$b]:-}
    if [ -z "$cur" ] || "${G[@]}" merge-base --is-ancestor "$cur" "$sha"; then best[$b]=$sha
    elif ! "${G[@]}" merge-base --is-ancestor "$sha" "$cur"; then
      if [ "$src" = gh ]; then best[$b]=$sha; else
        log "$name: local $b diverged from GitHub; backing it up as kiss/$b"
        best["kiss/$b"]=$sha
      fi
    fi
  done < <("${G[@]}" for-each-ref --format='%(objectname) %(refname)' refs/src/)  # refname order: gh before l1, l2, ...
  for b in "${!best[@]}"; do
    sha=${best[$b]}; rk=$("${G[@]}" rev-parse -q --verify "refs/rook/heads/$b^{commit}" 2>/dev/null || true)
    if [ "$rk" = "$sha" ]; then continue
    elif [ -z "$rk" ] || "${G[@]}" merge-base --is-ancestor "$rk" "$sha"; then specs+=("$sha:refs/heads/$b")
    elif "${G[@]}" merge-base --is-ancestor "$sha" "$rk"; then : # rook already ahead
    else warn "$name: branch $b would need a force push (rook has ${rk:0:9}, source ${sha:0:9})"; fi
  done
  # Tags: first source wins; a tag that already exists on rook is never moved.
  while read -r sha ref; do
    src=${ref#refs/src/}; src=${src%%/*}
    case "$ref" in "refs/src/$src/tags/"*) b=${ref#refs/src/"$src"/tags/};; *) continue;; esac
    [ -n "${tag[$b]:-}" ] || tag[$b]=$sha
  done < <("${G[@]}" for-each-ref --format='%(objectname) %(refname)' refs/src/)
  for b in "${!tag[@]}"; do
    rk=$("${G[@]}" rev-parse -q --verify "refs/rook/tags/$b" 2>/dev/null || true)
    if [ -z "$rk" ]; then specs+=("${tag[$b]}:refs/tags/$b")
    elif [ "$rk" != "${tag[$b]}" ]; then warn "$name: tag $b differs on rook; left alone"; fi
  done

  if [ ${#specs[@]} = 0 ]; then log "$name: up to date (${#best[@]} branches, ${#tag[@]} tags)"; return; fi
  local out rc
  out=$(rgit -C "$cache" push --porcelain --no-verify rook "${specs[@]}" 2>&1); rc=$?
  while IFS=$'\t' read -r flag r summary; do
    case "$flag" in '!') warn "$name: rook rejected $r ($summary)";; esac
  done <<< "$out"
  [ $rc = 0 ] || [ "$(grep -c $'^!\t' <<< "$out")" -gt 0 ] || err "$name: push failed: $(tail -n1 <<< "$out")"
  log "$name: pushed ${#specs[@]} ref(s) (${#best[@]} branches, ${#tag[@]} tags known)"
}

repos=$( [ -r "$ROOK_GIT_REPOS" ] && cat "$ROOK_GIT_REPOS" || printf '%s' "$DEFAULT_REPOS" )
mkdir -p "$ROOK_GIT_CACHE"
exec 9>"$ROOK_GIT_CACHE/.lock"; flock -n 9 || { log "another sync is running"; exit 0; }
while IFS='|' read -r name gh locals; do
  [ -n "$name" ] && [ "${name:0:1}" != "#" ] || continue
  if [ $# -gt 0 ]; then printf '%s\n' "$@" | grep -qx "$name" || continue; fi
  # shellcheck disable=SC2086
  sync_repo "$name" "$gh" $locals
done <<< "$repos"
log "done: $errors error(s), $skips skipped ref(s)"
[ $errors = 0 ]
