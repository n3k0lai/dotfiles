# ene-law-upload — kiss → ene firearms law document upload
#
#   ene-law-upload va bills enrolled ~/Downloads/HB217-SB749.pdf
#   ene-law-upload md code firearms ~/Downloads/MD-PS-Article-5.pdf
function ene-law-upload --description "Upload law document kiss → ene"
    set -l script "$HOME/dotfiles/bin/ene-law-upload.sh"
    if not test -f $script
        echo "ene-law-upload: $script not found (git pull dotfiles?)"
        return 1
    end
    if test (count $argv) -lt 4
        echo "Usage:"
        echo "  ene-law-upload <jurisdiction> <corpus> <kind> <file>"
        echo ""
        echo "Examples:"
        echo "  ene-law-upload va bills enrolled ~/Downloads/HB217.pdf"
        echo "  ene-law-upload fed cfr ffl ~/Downloads/27-CFR-478.pdf"
        return 1
    end
    nix-shell -p rsync openssh --run "$script $argv"
end