" since I use fish :v
set shell=bash

set nocompatible              " be iMproved, required
filetype off                  " required

" force unicode support
scriptencoding utf-8
set encoding=utf-8

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" *=================================================================*
" *                        Personal Plugins                         *
" *=================================================================*

" colorscheme management
Plugin 'flazz/vim-colorschemes'

" ctrl-p tool
Plugin 'kien/ctrlp.vim'

" dank emojis
Plugin 'chrisbra/unicode.vim'

" JSON syntax
Plugin 'elzr/vim-json'

" fish syntax
Plugin 'dag/vim-fish'

" typescript syntax
Plugin 'leafgarland/typescript-vim'
" typescript Typings syntax
Plugin 'mhartington/vim-typings'
" typescript omniplugin shiz
Plugin 'Quramy/tsuquyomi'
" needed for tsuquyomi
Plugin 'Shougo/vimproc', {'rtp': ['autoload/*,lib/*,plugin/*']}

" for editing view stuff
Plugin 'kovetskiy/sxhkd-vim'


" *==========================End Plugins============================*

call vundle#end()            " required
filetype plugin indent on    " required

" *=================================================================*
" *                        Generic Settings                         *
" *=================================================================*

" color scheme
colorscheme heroku 

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
    
    " a:mmode is currently ignored. In the future, we should probably do something
    " about that. the matcher behaves like 'full-line'.
    let cmd = 'matcher --limit '.a:limit.' --manifest '.cachefile.' '
    if!(exists('g:ctrlp_dotfiles') && g:ctrlp_dotfiles)
      let cmd = cmd.'--no-dotfiles'
    endif
    
    let cmd = cmd.a:str
  
    return split(system(cmd), "\n")
  
  endfunction
end
