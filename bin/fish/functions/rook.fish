# rook - Build/deploy the Rook server configuration
# On kiss: builds locally, deploys remotely to rook via SSH
# On rook: builds and activates locally
function rook --argument-names cmd
    set -l hostname (uname -n)
    set -l flake_dir (test -n "$ROOK_FLAKE_DIR"; and echo "$ROOK_FLAKE_DIR"; or echo "$HOME/dotfiles")
    set -l target "rook"

    # Determine build mode based on hostname
    set -l rebuild_cmd
    switch "$hostname"
        case "kiss"
            set rebuild_cmd "nixos-rebuild --flake $flake_dir#$target --target-host nicho@$target --use-remote-sudo"
        case "rook"
            set rebuild_cmd "sudo nixos-rebuild --flake $flake_dir#$target"
        case "*"
            if test -n "$ROOK_FLAKE_DIR"
                echo "Unknown host '$hostname'. Using local rebuild because ROOK_FLAKE_DIR is set."
                set rebuild_cmd "sudo nixos-rebuild --flake $flake_dir#$target"
            else
                echo "rook: unknown host '$hostname' (expected: kiss or rook)"
                echo "Set ROOK_FLAKE_DIR to force a local rebuild, or run from kiss/rook."
                return 1
            end
    end

    switch "$cmd"
        case test t
            echo "🔨 nix build test for #rook..."
            eval "$rebuild_cmd test"
        case switch s
            echo "🚀 nix rebuild switch for #rook..."
            eval "$rebuild_cmd switch"
        case build b
            echo "📦 nix build (no activate) for #rook..."
            eval "$rebuild_cmd build"
        case diff d
            echo "📋 showing what would change for #rook..."
            eval "$rebuild_cmd build"
            and nix store diff-closures /run/current-system ./result
        case update u
            echo "🔄 updating flake inputs for rook..."
            nix flake update --flake "$flake_dir"
        case ""
            echo "rook - Rook server rebuild helper"
            echo ""
            echo "  rook test|t      build + activate (no boot entry)"
            echo "  rook switch|s    build + activate + boot entry"
            echo "  rook build|b     build only (no activate)"
            echo "  rook diff|d      build + show closure diff"
            echo "  rook update|u    update flake inputs"
            echo ""
            echo "  host:   $hostname"
            echo "  target: #rook → flake: $flake_dir"
            if test "$hostname" = "kiss"
                echo "  mode:   remote deploy (kiss → rook)"
            else if test "$hostname" = "rook"
                echo "  mode:   local rebuild"
            end
        case "*"
            echo "unknown command: $cmd (try: test, switch, build, diff, update)"
            return 1
    end
end
