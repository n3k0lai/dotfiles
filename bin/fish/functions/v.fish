function v --wraps=nvim --description 'Open files in Neovim'
  if not command -q nvim
    echo "v: nvim not found (enable modules.editors.vim)" >&2
    return 127
  end
  command nvim $argv
end
