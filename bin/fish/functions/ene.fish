# ene - Build/deploy the Ene server configuration
# On kiss: builds locally, deploys remotely to ene via SSH
# On ene: builds and activates locally
function ene --argument-names cmd
    set -l hostname (uname -n)
    set -l flake_dir (test -n "$ENE_FLAKE_DIR"; and echo "$ENE_FLAKE_DIR"; or echo "$HOME/dotfiles")
    set -l target "ene"

    # Determine build mode based on hostname
    set -l rebuild_cmd
    switch "$hostname"
        case "kiss"
            set rebuild_cmd "nixos-rebuild --flake $flake_dir#$target --target-host nicho@$target --use-remote-sudo"
        case "ene"
            set rebuild_cmd "sudo nixos-rebuild --flake $flake_dir#$target"
        case "*"
            if test -n "$ENE_FLAKE_DIR"
                echo "Unknown host '$hostname'. Using local rebuild because ENE_FLAKE_DIR is set."
                set rebuild_cmd "sudo nixos-rebuild --flake $flake_dir#$target"
            else
                echo "ene: unknown host '$hostname' (expected: kiss or ene)"
                echo "Set ENE_FLAKE_DIR to force a local rebuild, or run from kiss/ene."
                return 1
            end
    end

    switch "$cmd"
        case test t
            echo "🔨 nix build test for #ene..."
            eval "$rebuild_cmd test"
        case switch s
            echo "🚀 nix rebuild switch for #ene..."
            eval "$rebuild_cmd switch"
        case build b
            echo "📦 nix build (no activate) for #ene..."
            eval "$rebuild_cmd build"
        case diff d
            echo "📋 showing what would change for #ene..."
            eval "$rebuild_cmd build"
            and nix store diff-closures /run/current-system ./result
        case update u
            echo "🔄 updating flake inputs for ene..."
            nix flake update --flake "$flake_dir"
        case ""
            echo "ene - Ene server rebuild helper"
            echo ""
            echo "  ene test|t      build + activate (no boot entry)"
            echo "  ene switch|s    build + activate + boot entry"
            echo "  ene build|b     build only (no activate)"
            echo "  ene diff|d      build + show closure diff"
            echo "  ene update|u    update flake inputs"
            echo ""
            echo "  host:   $hostname"
            echo "  target: #ene → flake: $flake_dir"
            if test "$hostname" = "kiss"
                echo "  mode:   remote deploy (kiss → ene)"
            else if test "$hostname" = "ene"
                echo "  mode:   local rebuild"
            end
        case "*"
            echo "unknown command: $cmd (try: test, switch, build, diff, update)"
            return 1
    end
end
