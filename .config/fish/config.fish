# \  _/\_
#  ><_  _*> config.fish
# /   \/


fish_add_path /bin /usr/bin /usr/local/bin
fish_add_path /sbin /usr/sbin /user/local/sbin

# default programs
set -gx EDITOR "nvim"
set -gx TERMINAL "kitty"
set -gx BROWSER "opera"
set -gx BROWSER_MIN "luakit"

# config
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx GOPATH "$XDG_DATA_HOME/go"
 
# colorscheme 
#

# input for multilang
set -gx XMODIFIERS "fcitx5"
set -gx GTK_IM_MODULE "fcitx5"
set -gx QT_IM_MODULE "fcitx5"


set -gx DISPLAY ":0"

# hypr
set -gx _JAVA_AWT_WM_NONREPARENTING "1" # android studio x11 ui fix
set -gx XCURSOR_SIZE "24"

# wine
set -gx WINEDEBUG "fps"
set -gx FREETYPE_PROPERTIES "truetype:interpreter-version=35"

# fixes
set -gx MOZ_USE_XINPUT2 "1" # mozilla smooth scrolling/touchpads
