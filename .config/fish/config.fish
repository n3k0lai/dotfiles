# Terminal greeting
set fish_greeting (fortune);

# Prompt aesthetics
function fish_prompt
  echo -n (prompt_pwd);
  set_color brgreen;
  echo -n " ~";
  set_color brcyan;
  echo -n "> ";
end

# make sure su uses fish
function su
  /bin/su --shell=/usr/bin/fish $argv
end

# make sure ag uses .agignore
function ag
  /bin/ag --path-to-ignore $HOME/.agignore
end

# command to quick-update vundle 
function updatevim
  set -lx SHELL (which sh)
  vim +BundleInstall! +BundleClean +qall
end

# path variables
set -xU EDITOR vim
set -xU GOPATH $HOME/.local/share/go $PATH 
