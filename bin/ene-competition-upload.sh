#!/usr/bin/env bash
# kiss → ene competition rulebook upload (lives in dotfiles so git pull is enough).
# See also: bin/fish/functions/ene-competition-upload.fish
#
#   nix-shell -p rsync openssh --run '~/dotfiles/bin/ene-competition-upload.sh issf ~/Downloads/issf.pdf'
set -euo pipefail

ENE_HOST="${ENE_HOST:-ene}"
ENE_USER="${ENE_USER:-nicho}"
REMOTE_ROOT="/var/lib/hermes/.hermes/workspace/mcp/guns/competition"
INBOX="/var/lib/hermes/inbox"

usage() {
  echo "Usage: $0 <org-id> <local.pdf>"
  echo "       $0 uspsa <corpus> <doc-type> <local.pdf>"
  echo "       $0 idpa <corpus> <doc-type> <local.pdf>"
  echo "       $0 msw <event-slug> <local.pdf>"
  echo "       $0 moonsout <local.pdf>"
  echo ""
  echo "USPSA: competition|rsm + rulebook|changelog"
  echo "IDPA: match-rules|equipment-indices|match-administration|classifiers-*"
  echo "PCSL: general-rulebook|changelog|html-chapters|forms"
  echo "SSH: \$ENE_USER@\$ENE_HOST (default nicho@ene) — not hermes@ene"
  exit 1
}

[[ $# -lt 2 ]] && usage

TARGET="${1,,}"

if [[ "$TARGET" == "uspsa" && $# -ge 4 ]]; then
  FILE="${4}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" uspsa "${2,,}" "${3,,}")
elif [[ "$TARGET" == "idpa" && $# -ge 4 ]]; then
  FILE="${4}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" idpa "${2,,}" "${3,,}")
elif [[ "$TARGET" == "pcsl" && $# -ge 4 ]]; then
  FILE="${4}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" pcsl "${2,,}" "${3,,}")
elif [[ "$TARGET" == "msw" ]]; then
  [[ $# -lt 3 ]] && usage
  SLUG="${2,,}"
  FILE="${3}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" msw "$SLUG")
elif [[ "$TARGET" == "moonsout" ]]; then
  FILE="${2}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" moonsout)
else
  FILE="${2}"
  REMOTE_CMD=(sudo -u hermes "$REMOTE_ROOT/receive_upload.sh" "$TARGET")
fi

[[ -f "$FILE" ]] || { echo "Not found: $FILE" >&2; exit 1; }

BASENAME="$(basename "$FILE")"
REMOTE_STAGING="$INBOX/$BASENAME"
SSH_TARGET="$ENE_USER@$ENE_HOST"

echo "→ $SSH_TARGET:$REMOTE_STAGING (then install as hermes)"

ssh -q "$SSH_TARGET" "sudo mkdir -p '$INBOX' && sudo chown hermes:hermes '$INBOX' && sudo chmod 2775 '$INBOX'"
rsync -avz "$FILE" "$SSH_TARGET:$REMOTE_STAGING"
ssh -q "$SSH_TARGET" "sudo chown hermes:hermes '$REMOTE_STAGING'"

REMOTE_ARGS=("${REMOTE_CMD[@]}" "$REMOTE_STAGING")
# shellcheck disable=SC2029
ssh -q "$SSH_TARGET" "${REMOTE_ARGS[*]}"

echo "✓ Uploaded and reindexed on ene."