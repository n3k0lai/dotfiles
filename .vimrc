" since I use fish :v
set shell=bash

set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" The following are examples of different formats supported.
" Keep Plugin commands between vundle#begin/end.
" plugin on GitHub repo
Plugin 'tpope/vim-fugitive'
" plugin from http://vim-scripts.org/vim/scripts.html
Plugin 'L9'
" Git plugin not hosted on GitHub
Plugin 'git://git.wincent.com/command-t.git'
" git repos on your local machine (i.e. when working on your own plugin)
Plugin 'file:///home/gmarik/path/to/plugin'
" The sparkup vim script is in a subdirectory of this repo called vim.
" Pass the path to set the runtimepath properly.
Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
" Install L9 and avoid a Naming conflict if you've already installed a
" different version somewhere else.
" Plugin 'ascenator/L9', {'name': 'newL9'}

" *=================================================================*
" *                        Personal Plugins                         *
" *=================================================================*
" colorscheme management
Plugin 'flazz/vim-colorschemes', {'name':'vim-colorschemes'}

" maui colorscheme
"Plugin 'zsoltf/vim-maui', {'name':'maui'}

" JS syntax
Plugin 'pangloss/vim-javascript', {'name': 'vim-javascript'}

" JSON syntax
Plugin 'elzr/vim-json', {'name': 'vim-json'}

" typescript syntax
Plugin 'leafgarland/typescript-vim', {'name': 'typescript-vim'}
" typescript Typings syntax
Plugin 'mhartington/vim-typings', {'name': 'vim-typings'}
" typescript omniplugin shiz
" Plugin 'Quramy/tsuquyomi', {'name': 'tsuquyami'}

" *==========================End Plugins============================*

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just
" :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line

" *=================================================================*
" *                        Generic Settings                         *
" *=================================================================*

filetype plugin indent on

" color scheme
colorscheme molokai 

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

