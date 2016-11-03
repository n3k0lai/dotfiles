#!/bin/bash

#====================== Repos =======================
#infinality
# add-apt-repository ppa:no1wantdthisname/ppa
#node 
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -

#================== Update System ===================
apt-get update
apt-get upgrade

apt-get install git vim nodejs mosh tmux fish fortune 

# get vim plugins in place
vim +PluginInstall +qall

# get node in place
sudo chown -R $USER:$GROUP ~/.npm
npm install -g yarn

#if ubuntu
chsh -s `which fish`

# if graphics are wanted
apt-get install livestreamer x11-utils xdg-utils mpv
yarn install -g grunt-cli bower
sudo chown -R $USER:$GROUP ~/.cache/bower

git clone https://github.com/bastimeyer/livestreamer-twitch-gui.git
cd livestreamer-twitch-gui
yarn install
grunt release
mv build/releases/livestreamer-twitch-gui/linux64 /opt/livestreamer-twitch-gui
cd ../
rm -rf livestreamer-twitch-gui
/opt/livestreamer-twitch-gui/add-menuitem.sh

# if dev is wanted
yarn install -g mongodb typescript

