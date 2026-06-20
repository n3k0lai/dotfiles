#!/usr/bin/env bash
# kiss → ene firearms law document upload.
# See also: bin/fish/functions/ene-law-upload.fish
#
#   nix-shell -p rsync openssh --run '~/dotfiles/bin/ene-law-upload.sh va bills enrolled ~/Downloads/HB217.pdf'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAW_UPLOAD="${HOME}/.hermes/workspace/mcp/guns/law/upload_from_kiss.sh"

if [[ -f "$LAW_UPLOAD" ]]; then
  exec "$LAW_UPLOAD" "$@"
fi

# Fallback: soul repo path when workspace symlink unavailable
SOUL_UPLOAD="/var/lib/hermes/.hermes/workspace/mcp/guns/law/upload_from_kiss.sh"
if [[ -f "$SOUL_UPLOAD" ]]; then
  exec "$SOUL_UPLOAD" "$@"
fi

echo "ene-law-upload: upload_from_kiss.sh not found" >&2
exit 1