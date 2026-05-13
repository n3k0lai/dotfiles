# Keychain SSH agent management
# Install keychain with `brew install keychain` to use this.
# To add a key: set -Ua SSH_KEYS_TO_AUTOLOAD ~/.ssh/mykey
# To remove a key: set -U --erase SSH_KEYS_TO_AUTOLOAD[index_of_key]

if status is-login
    and status is-interactive
    and command -q keychain
    and set -q SSH_KEYS_TO_AUTOLOAD
    and test (count $SSH_KEYS_TO_AUTOLOAD) -gt 0
    keychain --eval $SSH_KEYS_TO_AUTOLOAD | source
end
