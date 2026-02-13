set shiftwidth=2
set expandtab
set cc=80
set ruler
" syntax enable
color ron
" colorscheme pablo
" colorscheme koehler

set number
set hlsearch
set nocompatible
set backspace=indent,eol,start
" set mouse+=a

" Problems copying text on Mac OS Sierra: https://github.com/tmux/tmux/issues/543
set clipboard=unnamed

" Native packages (~/.vim/pack/plugins/start/) — no plugin manager needed
" Install plugins:
"   mkdir -p ~/.vim/pack/plugins/start
"   git clone <repo> ~/.vim/pack/plugins/start/<name>
syntax on
filetype plugin indent on

" A nicer default Vim rc
set tabstop=2
" set softtabstop=0 noexpandtab
" set softtabstop=2
" set smarttab
set ai
set cursorline
set incsearch
set t_Co=256

:hi CursorLine cterm=NONE ctermbg=darkgray ctermfg=green
:highlight ExtraWhitespace ctermbg=red guibg=red
:match ExtraWhitespace /\s\+$/

" Ruby identation using vim-ruby plugin
autocmd FileType ruby set shiftwidth=2
