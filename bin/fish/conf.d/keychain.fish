# Keychain SSH agent management
# Install keychain (nix/brew) to use this.
#
# Set keys once (replaces list — do not use set -Ua or duplicates accumulate):
#   set -U SSH_KEYS_TO_AUTOLOAD ~/.ssh/id_ed25519
# Multiple keys:
#   set -U SSH_KEYS_TO_AUTOLOAD ~/.ssh/id_ed25519 ~/.ssh/work
# Clear:
#   set -eU SSH_KEYS_TO_AUTOLOAD

if status is-login
    and status is-interactive
    and command -q keychain
    # Prefer explicit list; otherwise default to the usual key if present.
    set -l keys
    if set -q SSH_KEYS_TO_AUTOLOAD
        and test (count $SSH_KEYS_TO_AUTOLOAD) -gt 0
        set keys $SSH_KEYS_TO_AUTOLOAD
    else if test -f $HOME/.ssh/id_ed25519
        set keys $HOME/.ssh/id_ed25519
    end

    # Deduplicate and skip missing paths (e.g. desktop-only keys on a server).
    set -l load
    for k in $keys
        set -l path (string replace -r '^~' $HOME -- $k)
        if not contains -- $path $load
            and test -f $path
            set -a load $path
        end
    end

    if test (count $load) -gt 0
        keychain --eval --quiet $load | source
    end
end
