# ene - Build/test the Ene agent configuration from nicho user
# Targets /var/lib/hermes/dotfiles (Ene's dotfiles) specifically for the #ene flake
function ene --argument-names cmd
    set -l flake_dir "/var/lib/hermes/dotfiles"
    set -l target "ene"

    if not test -d "$flake_dir"
        echo "Ene flake dir not found: $flake_dir"
        return 1
    end

    switch "$cmd"
        case test t
            echo "🔨 nix build test for #ene..."
            sudo nixos-rebuild test --flake "$flake_dir#$target"
        case switch s
            echo "🚀 nix rebuild switch for #ene..."
            sudo nixos-rebuild switch --flake "$flake_dir#$target"
        case build b
            echo "📦 nix build (no activate) for #ene..."
            sudo nixos-rebuild build --flake "$flake_dir#$target"
        case diff d
            echo "📋 showing what would change for #ene..."
            sudo nixos-rebuild build --flake "$flake_dir#$target" 2>/dev/null
            and nix store diff-closures /run/current-system ./result
        case update u
            echo "🔄 updating flake inputs for ene..."
            nix flake update --flake "$flake_dir"
        case home h
            echo "🏠 creating /home/ene symlink to /var/lib/hermes..."
            sudo ln -s /var/lib/hermes /home/ene
            echo "Done. /home/ene → /var/lib/hermes"
        case ""
            echo "ene - Ene agent rebuild helper"
            echo ""
            echo "  ene test|t      build + activate (no boot entry)"
            echo "  ene switch|s    build + activate + boot entry"
            echo "  ene build|b     build only (no activate)"
            echo "  ene diff|d      build + show closure diff"
            echo "  ene update|u    update flake inputs"
            echo "  ene home|h      create /home/ene symlink"
            echo ""
            echo "  target: #ene → flake: $flake_dir"
        case "*"
            echo "unknown command: $cmd (try: test, switch, build, diff, update, home)"
            return 1
    end
end
