# ene-competition-upload — kiss → ene rulebook / tacops / MoonsOut PDF upload
#
# Usage:
#   ene-competition-upload issf ~/Downloads/ISSF-Rule-Book-2026.pdf
#   ene-competition-upload moonsout ~/Downloads/Moons-Out-26-RULES.pdf
#   ene-competition-upload msw abkhaz-front ~/tacops.pdf
#
# Requires: nix-shell, ssh/rsync to nicho@ene (Tailscale SSH — not hermes@ene)

function ene-competition-upload --description "Upload competition rulebook PDF kiss → ene"
    set -l script "$HOME/dotfiles/bin/ene-competition-upload.sh"
    if not test -f "$script"
        echo "ene-competition-upload: $script not found (git pull dotfiles?)"
        return 1
    end

    if test (count $argv) -lt 2
        echo "Usage:"
        echo "  ene-competition-upload <org> <file.pdf>"
        echo "  ene-competition-upload uspsa <corpus> <doc-type> <file.pdf>"
        echo "  ene-competition-upload msw <event-slug> <file.pdf>"
        echo "  ene-competition-upload moonsout <file.pdf>"
        echo ""
        echo "USPSA corpus: competition | rsm   doc-type: rulebook | changelog"
        echo "IDPA corpus: match-rules | equipment-indices | match-administration"
        echo "             classifiers-standard | classifiers-5x5 | classifiers-pcc"
        echo "PCSL corpus: general-rulebook | changelog | html-chapters | forms"
        echo ""
        echo "Orgs: uspsa, idpa, issf, pcsl, milsim-west"
        echo "SSH: \$ENE_USER@\$ENE_HOST (default nicho@ene)"
        return 1
    end

    nix-shell -p rsync openssh --run "$script $argv"
end