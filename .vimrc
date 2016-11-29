" since I use fish :v
set shell=bash

set nocompatible              " be iMproved, required
filetype off                  " required

" force unicode support
scriptencoding utf-8
set encoding=utf-8

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/repos/github.com/Shougo/dein.vim

call dein#begin('~/.vim/bundle')

" let Dein manage Dein
call dein#add('~/.vim/bundle/repos/github.com/Shougo/dein.vim')

" *=================================================================*
" *                        Personal Plugins                         *
" *=================================================================*

" colorscheme management
call dein#add('flazz/vim-colorschemes')

" ctrl-p tool
call dein#add('kien/ctrlp.vim')

" dank emojis
call dein#add('chrisbra/unicode.vim')

" JSON syntax
call dein#add('elzr/vim-json')

" fish syntax
call dein#add('dag/vim-fish')

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
