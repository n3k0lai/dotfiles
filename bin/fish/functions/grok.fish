# Grok CLI launcher — update then run the user install under ~/.grok/bin.
# Real binary is not in the nix store; install.sh only patches bashrc, so fish
# always goes through this function when modules.editors.grokbuild is enabled.
function grok --description 'Update Grok CLI then run it'
    set -l bin $HOME/.grok/bin/grok

    if set -q GROK_SKIP_UPDATE
        # Escape hatch for rapid iteration / offline use
    else
        if not command -q grok-update
            echo "grok: grok-update not on PATH (enable modules.editors.grokbuild)" >&2
            return 127
        end
        echo "Updating Grok CLI..."
        if not grok-update
            echo "grok: update failed" >&2
            return 1
        end
    end

    if not test -x $bin
        echo "grok: binary not found at $bin" >&2
        echo "Try: grok-update && grok login" >&2
        return 127
    end

    # Absolute path so we never recurse into this function
    command $bin $argv
end
