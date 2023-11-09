function set_profile

    set -l options (fish_opt -s u -l ui)

    fish_add_path /bin /usr/bin /usr/local/bin
    fish_add_path /sbin /usr/sbin /user/local/sbin
    fish_add_path ~/.dotnet/tools
    # default programs
    set -gx EDITOR nvim

    # config
    set -gx XDG_CONFIG_HOME "$HOME/.config"
    set -gx XDG_DATA_HOME "$HOME/.local/share"
    set -gx GOPATH "$XDG_DATA_HOME/go"

    # colorscheme 
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

    if set -q _flag_ui
        set -gx DISPLAY ":0"
        set -gx TERMINAL foot
        set -gx BROWSER opera
        set -gx BROWSER_MIN luakit

        # input for multilang
        set -gx XMODIFIERS fcitx5
        set -gx GTK_IM_MODULE fcitx5
        set -gx QT_IM_MODULE fcitx5

        # wm
        set -gx _JAVA_AWT_WM_NONREPARENTING 1 # android studio x11 ui fix
        set -gx XCURSOR_SIZE 24

        # wine
        set -gx WINEDEBUG fps
        set -gx FREETYPE_PROPERTIES "truetype:interpreter-version=35"

        # fixes
        set -gx MOZ_USE_XINPUT2 1 # mozilla smooth scrolling/touchpads
    end
end
