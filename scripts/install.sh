#!/bin/sh

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-h] [-core] [-gui] [-util]...
    -h          display this help and exit
    -core       install normal developer/environment utils
    -gui        install an X11 desktop
    -osx        install an OSX desktop
    -util       install GUI utils
    
extras:
    -weechat    install weechat config
    -newsbeuter install newsbeuter config
EOF
}
# Resetting OPTIND is necessary if getopts was used previously in the script.
# It is a good idea to make OPTIND local if you process options in a function.
OPTIND=1 

basedir=$(pwd)
target=~/.config

while getopts hvf: opt; do
    case $opt in
        h|help)
            show_help
            exit 0
            ;;

        c|core)  
            # ====================== CORE ======================
            # Packages:
            #   git
            #   vim
            #   tmux
            #   fish
            #   nvm 

            # git
            mkdir -p ~/.config/git
            ln -s $basedir/gitignore_global ~/.config/git/ignore

            # vim
            mkdir -p ~/.config/vim
            mkdir -p ~/.vim/bundle/repos
            ln -s $basedir/vimrc ~/.vimrc
            echo "bash $basedir/install_dein.sh ~/.vim/bundle"
            
            # tmux
            ln -s $basedir/tmux.conf ~/.tmux.conf
            
            # fish
            mkdir -p ~/.config/fish/functions
            ln -s $basedir/fish/config.fish ~/.config/fish/config.fish
            ln -s $basedir/fish/fishfile ~/.config/fish/fishfile
            ln -s $basedir/fish/functions/fisher.fish ~/.config/fish/functions/fisher.fish

            # nvm
            echo "bash $basedir/install_nvm.sh"
            ;;

        g|gui)
            # ==================== GUI LINUX ====================
            # Packages:
            #   X11
            #   rxvt-unicode-256color
            #   sxhkd
            #   bspwm
            #   rofi
            #   lemonbar

            # X11
            ln -s $basedir/x11/xinitrc ~/.xinitrc
            
            # urxvt
            ln -s $basedir/x11/Xdefaults ~/.Xdefaults
            
            # sxhkd
            mkdir -p ~/.config/sxhkd
            ln -s $basedir/sxhkd/sxhkdrc ~/.config/sxhkd/sxhkdrc
            
            # bspwm
            mkdir -p ~/.config/bsmpwm
            ln -s $basedir/bspwm/bspwmrc ~/.config/bspwm/bspwmrc
            
            # convert to lemonbar
            # mkdir -p ~/.config/statusbar
            # ln -s $basedir/statusbar/index.js ~/.config/statusbar/index.js
            # pushd $basedir/statusbar
            # npm install
            # popd
            ;;

        u|util)
            # ==================== GUI UTIL ====================
            # packages:
            #   ranger
            #   feh
            #   mpv
            #   mpd
            #   ncmpcpp
            #   zathura
            
            mkdir -p ~/.config/mpv
            ln -s $basedir/mpv/mpv.conf ~/.config/mpv/mpv.conf
            
            mkdir -p ~/.config/ranger
            ln -s $basedir/ranger/commands.py ~/.config/ranger/commands.py
            ln -s $basedir/ranger/rc.conf ~/.config/ranger/rc.conf
            ln -s $basedir/ranger/rifle.conf ~/.config/ranger/rifle.conf
            ln -s $basedir/ranger/scope.sh ~/.config/ranger/scope.sh
            
            mkdir -p ~/.ncmpcpp
            ln -s $basedir/ncmpcpp/config ~/.ncmpcpp/config
            ln -s $basedir/ncmpcpp/mpdconf ~/.mpdconf
            
            mkdir -p ~/.config/zathura
            ln -s $basedir/zathura/zuthurarc ~/.config/zathura/zathurarc
            ;;

        o|osx)
            # ==================== GUI OSX =====================
            # packages:
            #   skhd
            #   chunkwm
            #   kitty terminal
            
            ln -s $basedir/osx/skhdrc ~/.skhdrc
            ln -s $basedir/osx/chunkwmrc ~/.chunkwmrc
            ;;

            # =================== OTHER =======================
            # packages:
            #   weechat
            #   newsbeuter

        weechat)
            mkdir -p ~/.weechat/scripts
            ln -s $basedir/weechat/scripts/buffers.pl ~/.weechat/scripts/buffers.pl
            ;;

        newsbeuter)
            mkdir -p ~/.newsbeuter
            ln -s $basedir/newsbeuter/urls ~/.newsbeuter/urls
            ;;

        ?|*)
            show_help >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"   # Discard the options and sentinel --
