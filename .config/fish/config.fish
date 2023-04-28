# Force 256 color
# set -x TERM ansi 
# set -x TERM rxvt-256color

set_profile;

function _git_branch_name
  echo (command git symbolic-ref HEAD ^/dev/null | sed -e 's|^refs/heads/||')
end

function _is_git_dirty
    echo (command git status -s --ignore-submodules=dirty ^/dev/null)
end

# Prompt aesthetics
#function fish_prompt
#  set -l teal (set_color -o cyan)
#  set -l purple (set_color -o green)
#  set -l cream (set_color -o red)
#  set -l violet (set_color white)
#  if [ (_git_branch_name) ]
#    if test (_git_branch_name) = "master"
#      set_color -o red;
#      printf $cream( prompt_pwd )"$purple(m)"
#    else
#      printf $cream( prompt_pwd )"$purple("(_git_branch_name)")"
#    end
#
#    if [ (_is_git_dirty) ]
#      printf " $teal~$purple< "
#    else
#      printf " $teal~$purple> "
#    end
#  else
#    printf "$cr"(prompt_pwd)" $teal~$purple> ";
#  end
#end

# make sure su uses fish
#function su
#  /bin/su --shell=/usr/bin/fish $argv
#end

# make sure ag uses .agignore
function ag
  /bin/ag --path-to-ignore $HOME/.agignore
end

# command to quick-update vundle 
function updatevim
  set -lx SHELL (which sh)
  vim +BundleInstall! +BundleClean +qall
end

# stole this function from bcrypt
function tmux2
  set TERM screen-256color-bce
  tmux
end
# path variables
#set -xU EDITOR vim
#set -xU GOPATH $HOME/.local/share/go $PATH 
