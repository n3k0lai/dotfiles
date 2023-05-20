# \  _/\_
#  ><_  _*> config.fish
# /   \/
set -gx PATH "/bin /usr/bin /usr/local/bin /sbin /usr/sbin/ /user/local/sbin $PATH"
# default programs
set -gx EDITOR "nvim"
set -gx TERMINAL "kitty"
set -gx BROWSER "opera"
set -gx BROWSER_MIN "luakit"

# config
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx GOPATH "$HOME/go" # should be in data
set -gx SXHKD_SHELL '/usr/bin/sh'
 
# colorscheme 
#

# input for multilang
set -gx XMODIFIERS "fcitx5"
set -gx GTK_IM_MODULE "fcitx5"
set -gx QT_IM_MODULE "fcitx5"
#set -gx DISPLAY ":0"
set -gx BETTERLOCKSCREEN_WALLPAPER_COMMAND "mtrx"

# wine
set -gx WINEDEBUG "fps"
set -gx FREETYPE_PROPERTIES "truetype:interpreter-version=35"

# fixes
set -gx MOZ_USE_XINPUT2 "1" # mozilla smooth scrolling/touchpads
set -gx _JAVA_AWT_WM_NONREPARENTING "1" # android studio x11 ui fix

# wmname LG3D

