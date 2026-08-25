#!/usr/bin/env bash
# Update ONLY the hermes-agent flake input, then build #ene.
# Never nixos-rebuild switch/test. Activation is nicho.
set -euo pipefail

DOTFILES="${HERMES_DOTFILES:-}"
if [[ -z "$DOTFILES" ]]; then
  for c in \
    /var/lib/hermes/dotfiles \
    "${HOME}/.hermes/workspace/dotfiles" \
    "${HOME}/dotfiles" \
    /var/lib/hermes/.hermes/workspace/dotfiles
  do
    if [[ -f "$c/flake.lock" && -f "$c/flake.nix" ]]; then
      DOTFILES=$c
      break
    fi
  done
fi
if [[ -z "${DOTFILES:-}" ]]; then
  echo "hermes-flake-bump: flake not found (set HERMES_DOTFILES)" >&2
  exit 1
fi

HOST="${1:-ene}"
echo "dotfiles: $DOTFILES"
echo "updating input: hermes-agent"
nix flake lock --update-input hermes-agent --flake "$DOTFILES"
echo "building #$HOST (no switch)..."
nixos-rebuild build --flake "$DOTFILES#$HOST"
echo "build ok. nicho: sudo nixos-rebuild switch --flake $DOTFILES#$HOST"
