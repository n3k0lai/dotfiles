#!/bin/sh

basedir=$(pwd)
target=~/.config

# ====================== Core ======================
mkdir -p ~/.config/git
ln -s $basedir/gitignore_global ~/.config/git/ignore

mkdir -p ~/.config/vim
mkdir -p ~/.vim/bundle/repos
ln -s $basedir/vimrc ~/.vimrc

ln -s $basedir/tmux.conf ~/.tmux.conf

mkdir -p ~/.config/fish/functions
ln -s $basedir/fish/config.fish ~/.config/fish/config.fish
ln -s $basedir/fish/fishfile ~/.config/fish/fishfile
ln -s $basedir/fish/functions/fisher.fish ~/.config/fish/functions/fisher.fish

# ====================== Server ====================
mkdir -p ~/.weechat/scripts
ln -s $basedir/weechat/scripts/buffers.pl ~/.weechat/scripts/buffers.pl


# ==================== GUI LINUX ====================
ln -s $basedir/x11/xinitrc ~/.xinitrc
ln -s $basedir/x11/Xdefaults ~/.Xdefaults

mkdir -p ~/.config/sxhkd
ln -s $basedir/sxhkd/sxhkdrc ~/.config/sxhkd/sxhkdrc

mkdir -p ~/.config/bsmpwm
ln -s $basedir/bspwm/bspwmrc ~/.config/bspwm/bspwmrc

# convert to lemonbar
# mkdir -p ~/.config/statusbar
# ln -s $basedir/statusbar/index.js ~/.config/statusbar/index.js
# pushd $basedir/statusbar
# npm install
# popd


# ==================== GUI UTIL ====================
mkdir -p ~/.config/mpv
ln -s $basedir/mpv/mpv.conf ~/.config/mpv/mpv.conf

mkdir -p ~/.config/ranger
ln -s $basedir/ranger/commands.py ~/.config/ranger/commands.py
ln -s $basedir/ranger/rc.conf ~/.config/ranger/rc.conf
ln -s $basedir/ranger/rifle.conf ~/.config/ranger/rifle.conf
ln -s $basedir/ranger/scope.sh ~/.config/ranger/scope.sh

mkdir -p ~/.config/zathura
ln -s $basedir/zathura/zuthurarc ~/.config/zathura/zathurarc

# ==================== GUI OSX =====================
ln -s $basedir/osx/skhdrc ~/.skhdrc
ln -s $basedir/osx/chunkwmrc ~/.chunkwmrc
