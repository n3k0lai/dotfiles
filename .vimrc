filetype plugin indent on

" color scheme
colorscheme maui

" show existing tab with 4 spaces width
set tabstop=2

" when indenting with 'v', use 4 spaces width
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

" ctrlp plugin
set runtimepath^=~/.vim/bundle/ctrlp.vim

" javascript syntax plugin
set runtimepath^=~/.vim/bundle/vim-javascript


