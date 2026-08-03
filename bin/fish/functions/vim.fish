function vim --wraps=nvim --description 'alias vim=nvim'
  if not command -q nvim
    echo "vim: nvim not found (enable modules.editors.vim)" >&2
    return 127
  end
  command nvim $argv
end
