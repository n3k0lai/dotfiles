" since I use fish :v
set shell=bash

set nocompatible              " be iMproved, required
filetype off                  " required

" force unicode support
scriptencoding utf-8
set encoding=utf-8

" set the runtime path to include Dein and initialize
set rtp+=~/.vim/bundle/repos/github.com/Shougo/dein.vim

call dein#begin('~/.vim/bundle')

" let Dein manage Dein
call dein#add('Shougo/dein.vim')

" *=================================================================*
" *                        Personal Plugins                         *
" *=================================================================*

" colorscheme management
call dein#add('flazz/vim-colorschemes')

" world famous multicursor
call dein#add('terryma/vim-multiple-cursors')

" ctrl-p tool
call dein#add('kien/ctrlp.vim')

" source tree explorer
call dein#add('scrooloose/nerdtree')

" super tight linter
call dein#add('w0rp/ale')
" dank emojis
call dein#add('chrisbra/unicode.vim')

" JSON syntax
call dein#add('elzr/vim-json')

" fish syntax
call dein#add('dag/vim-fish')

" node gigaplugin
call dein#add('moll/vim-node')

" needed for lua omniplugin
call dein#add('xolox/vim-misc')
" lua omniplugin
call dein#add('xolox/vim-lua-ftplugin')
" moonscript syntax
call dein#add('leafo/moonscript-vim')

" vue syntax
call dein#add('posva/vim-vue')

" typescript syntax
call dein#add('leafgarland/typescript-vim')
" typescript Typings syntax
call dein#add('mhartington/vim-typings')
" needed for tsuquyomi
call dein#add('Shougo/vimproc', {'build': 'make'})
" typescript omniplugin shiz
call dein#add('Quramy/tsuquyomi')

" for editing view stuff
call dein#add('kovetskiy/sxhkd-vim')

" super tight datetime utility
call dein#add('tpope/vim-speeddating')

" makes vim pretty :>
call dein#add('junegunn/goyo.vim')

" *==========================End Plugins============================*

call dein#end()            " required
filetype plugin indent on    " required

" *=================================================================*
" *                        Generic Settings                         *
" *=================================================================*

" color scheme
" colorscheme heroku 

" show existing tab with 2 spaces width
set tabstop=2

" when indenting with 'v', use 2 spaces width
set shiftwidth=2

" On pressing tab, insert 4 space
set expandtab

" keep on syntax highlighting
syntax on

" show line numbers
set number

" highlight matching parens
set showmatch

" search evaluates per char typed
set incsearch

" highlight search matches
set hlsearch

" force vertical movement on sight, not line
nnoremap j gj
nnoremap k gk

" stops screen redraw from interrupting macros
set lazyredraw

" ag + ctrlp integration
if executable("ag")
  set grepprg=ag\ --nogroup\ --nocolor\ --hidden\ --path-to-ignore\ ~/.agignore
  let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden --path-to-ignore ~/.agignore -g ""'
endif

let g:ctrlp_show_hidden = 1

if executable('matcher')
  let g:ctrlp_match_func = { 'match': 'GoodMatch' }

  function! GoodMatch(items, str, limit, mmode, ispath, crfile, regex)

    " Create a cache file if not yet exists
    let cachefile = ctrlp#utils#cachedir().'/matcher.cache'
    if !( filereadable(cachefile) && a:items == readfile(cachefile) )
      call writefile(a:items, cachefile)
    endif
    
    if !filereadable(cachefile)
      return []
    endif
    
    " a:mmode is currently ignored. In the future, we should fix 
    " about that. the matcher behaves like 'full-line'.
    let cmd = 'matcher --limit '.a:limit.' --manifest '.cachefile.' '
    if!(exists('g:ctrlp_dotfiles') && g:ctrlp_dotfiles)
      let cmd = cmd.'--no-dotfiles'
    endif
    
    let cmd = cmd.a:str
  
    return split(system(cmd), "\n")
  
  endfunction
end
" command for super-write
command! -nargs=0 Sw w !sudo tee % > /dev/null

" force autoclose if nerdtree is only open buffer
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

" ctrl-\ toggles open nerdtree
map <C-\> :NERDTreeToggle<CR>
