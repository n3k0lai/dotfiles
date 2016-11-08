" since I use fish :v
set shell=bash

set nocompatible              " be iMproved, required
filetype off                  " required

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
  set grepprg=ag\ --nogroup\ --nocolor
  let g:ctrlp_user_command = 'ag %s -l --nocolor --hidden -g ""'
endif

let g:ctrlp_show_hidden = 1
