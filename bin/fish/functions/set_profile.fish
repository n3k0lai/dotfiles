function set_profile
    # NOTE: This function is now mostly deprecated
    # Environment variables have been moved to users/nicho.nix (home-manager)
    # This function remains for backwards compatibility
    # Only fish-specific customizations should go here
    
    # Colorscheme variables (these will eventually be set by theme modules)
    # Keeping them here temporarily for compatibility
    set -gx foreground fef3e9
    set -gx background 191919
    # black
    set -gx color0 191919
    set -gx color8 3f3f3f
    # yellow
    set -gx color3 af9976
    set -gx color11 ffe8c5
    # blue 
    set -gx color4 6495fc
    set -gx color12 83d9f7
    # cyan
    set -gx color6 39928d
    set -gx color14 adf0e7
    # white
    set -gx color15 fef3e9
end
