" since I use fish :v
set shell=bash

set nocompatible " be iMproved, required
filetype off " required

" force unicode support
scriptencoding utf-8
set encoding=utf-8

" chinese support
set fileencodings=utf8,cp936,gb18030,big5

" bootstrapper
let $CACHE = expand('~/.cache')
if !isdirectory($CACHE)
  call mkdir($CACHE, 'p')
endif
if &runtimepath !~# '/dein.vim'
  let s:dein_dir = fnamemodify('dein.vim', ':p')
  if !isdirectory(s:dein_dir)
    let s:dein_dir = $CACHE .. '/dein/repos/github.com/Shougo/dein.vim'
    if !isdirectory(s:dein_dir)
      execute '!git clone https://github.com/Shougo/dein.vim' s:dein_dir
    endif
  endif
  execute 'set runtimepath^=' .. substitute(
        \ fnamemodify(s:dein_dir, ':p') , '[/\\]$', '', '')
endif

" include Dein and initialize

let s:dein_base = '~/.cache/dein/'
let s:dein_src = '~/.cache/dein/repos/github.com/Shougo/dein.vim'
execute 'set runtimepath+=' .. s:dein_src

call dein#begin(s:dein_base)

" let Dein manage Dein
call dein#add(s:dein_src)

" *==========================================*
" *              Personal Plugins            *
" *==========================================*
call dein#add('github/copilot.vim')
" shougo
"call dein#add('Shougo/neocomplete.vim')
"call dein#add('Shougo/neosnippet.vim')
"call dein#add('Shougo/neosnippet-snippets')
"call dein#add('Shougo/unite.vim')
"call dein#add('Shougo/vimfiler.vim')

" go lang
"call dein#add('fatih/vim-go')
" remember to call :GoInstallBinaries after initial dein install

" colorscheme management
"call dein#add('flazz/vim-colorschemes')

" world famous multicursor
"call dein#add('terryma/vim-multiple-cursors')

" super tight linter
"call dein#add('w0rp/ale')

" dank emojis
"call dein#add('chrisbra/unicode.vim')

" JSON syntax
"call dein#add('elzr/vim-json')

" fish syntax
call dein#add('dag/vim-fish')

" node gigaplugin
"call dein#add('moll/vim-node')

" needed for lua omniplugin
"call dein#add('xolox/vim-misc')
" lua omniplugin
"call dein#add('xolox/vim-lua-ftplugin')
" moonscript syntax
call dein#add('leafo/moonscript-vim')
" love2d plugin 
"call dein#add('davisdude/vim-love-docs')

" vue syntax
"call dein#add('posva/vim-vue')

" for editing view stuff
"call dein#add('kovetskiy/sxhkd-vim')

" super tight datetime utility
"call dein#add('tpope/vim-speeddating')

" makes vim pretty :>
"call dein#add('junegunn/goyo.vim')

" neovim only
if !has('nvim')
  "call dein#add('github/copilot.vim')
endif
" *==========End Plugins==============*

call dein#end()            " required

filetype plugin indent on    " required

" *===================================*
" *           Generic Settings        *
" *===================================*

" color scheme
" colorscheme heroku 

" show existing tab with 2 spaces width
set tabstop=2

" when indenting with 'v', use 2 spaces width
set shiftwidth=2

" On pressing tab, insert 4 space
set expandtab

" keep on syntax highlighting
syntax enable

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

" enable autocomplete
"let g:neocomplete#enable_at_startup = 1

" enable file explorer
"let g:vimfiler_as_default_explorer = 1

" command for super-write
command! -nargs=0 Sw w !sudo tee % > /dev/null
