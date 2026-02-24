# nix build/switch helper — auto-detects hostname for flake target
function nx --argument-names cmd
    set -l host (hostname)
    set -l flake_dir "$HOME/Code/nix"

    if not test -d "$flake_dir"
        echo "flake dir not found: $flake_dir"
        return 1
    end

    switch "$cmd"
        case test t
            echo "🔨 nix build test for #$host..."
            sudo nixos-rebuild test --flake "$flake_dir#$host"
        case switch s
            echo "🚀 nix rebuild switch for #$host..."
            sudo nixos-rebuild switch --flake "$flake_dir#$host"
        case build b
            echo "📦 nix build (no activate) for #$host..."
            sudo nixos-rebuild build --flake "$flake_dir#$host"
        case diff d
            echo "📋 showing what would change for #$host..."
            sudo nixos-rebuild build --flake "$flake_dir#$host" 2>/dev/null
            and nix store diff-closures /run/current-system ./result
        case update u
            echo "🔄 updating flake inputs..."
            nix flake update --flake "$flake_dir"
        case ""
            echo "nx - NixOS rebuild helper"
            echo ""
            echo "  nx test|t      build + activate (no boot entry)"
            echo "  nx switch|s    build + activate + boot entry"
            echo "  nx build|b     build only (no activate)"
            echo "  nx diff|d      build + show closure diff"
            echo "  nx update|u    update flake inputs"
            echo ""
            echo "  host: $host → flake: $flake_dir#$host"
        case "*"
            echo "unknown command: $cmd (try: test, switch, build, diff, update)"
            return 1
    end
end
