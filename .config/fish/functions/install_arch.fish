function install_arch
  # check if dotfiles directory is there
  # if yes,
  #   git submodule download
  #   move everything over
  set -l distro (cat /etc/os-release | gep -oP '(?<=^ID=).+' | tr -d '"')
  set -l emstr, pacstr, yaystr
  # install yay
  # dev
  # git fish tmux yay fortune-mod bat neovim
  #
  # ui
  # xorg-server xorg-xinit xorg-xrandr xorg-xinput kitty bspwm sxhkd polibar rofi dunst betterlockscreen
  # 
  # common 
  # opera luakit feh scrot cmatrix neofetch streamlink vlc ranger zathura
  #
  # chinese
  # fortune-mod-zh noto-fonts noto-fonts-cjk fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-lua fcitx5-qt 
  # 
  # gaming
  #
  # work
  # zoom slack
  switch $distro
    case archlinux
      echo "Archlinux detected"
      sudo pacman -S $pacstr
      yay -S $yaystr
      ;;
    case gentoo
      echo "Gentoo detected"
      sudo emerge $emstr
      ;;
    case '"'
      echo "Unsupported distribution: $distro"
      return 1
      ;;
  end

  echo "Install complete"
end
