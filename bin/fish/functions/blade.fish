# blade — NixOS rebuild helper for the Razer Blade (flake #blade)
function blade --argument-names cmd
    set -l target blade
    set -l flake_dir (test -n "$BLADE_FLAKE_DIR"; and echo "$BLADE_FLAKE_DIR"; or echo "$HOME/dotfiles")

    if not test -d "$flake_dir"
        echo "flake dir not found: $flake_dir"
        return 1
    end

    set -l rebuild_cmd "sudo nixos-rebuild --flake $flake_dir#$target"

    switch "$cmd"
        case test t
            echo "🔨 nix build test for #$target..."
            $rebuild_cmd test
        case switch s
            echo "🚀 nix rebuild switch for #$target..."
            $rebuild_cmd switch
        case build b
            echo "📦 nix build (no activate) for #$target..."
            $rebuild_cmd build
        case diff d
            echo "📋 showing what would change for #$target..."
            $rebuild_cmd build 2>/dev/null
            and nix store diff-closures /run/current-system ./result
        case update u
            echo "🔄 updating flake inputs for blade..."
            nix flake update --flake "$flake_dir"
        case ""
            echo "blade - NixOS rebuild helper (Razer Blade / #blade)"
            echo ""
            echo "  blade test|t      build + activate (no boot entry)"
            echo "  blade switch|s    build + activate + boot entry"
            echo "  blade build|b     build only"
            echo "  blade diff|d      build + closure diff"
            echo "  blade update|u    update flake inputs"
            echo ""
            echo "  target: #$target → flake: $flake_dir"
        case "*"
            echo "unknown command: $cmd (try: test, switch, build, diff, update)"
            return 1
    end
end
