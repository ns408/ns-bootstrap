# ─── Oh My Zsh ─────────────────────────────────────────────────
export ZSH="${HOME}/.oh-my-zsh"
ZSH_THEME=""  # Disabled — using Starship prompt
ZSH_DISABLE_COMPFIX=true  # Allow shared directories (two-account setup)

# ─── Plugins (curated) ─────────────────────────────────────────
plugins=(
  git                       # Git aliases (gst, gaa, gcmsg, etc.)
  macos                     # macOS utilities (ofd, cdf, pfd)
  python                    # Python aliases
  sudo                      # ESC-ESC to prepend sudo
  vscode                    # VS Code aliases
  history-substring-search  # Up/down arrow history search
  zsh-autosuggestions       # Fish-like autosuggestions
  zsh-completions           # Extra completion definitions
  zsh-syntax-highlighting   # Real-time command syntax coloring
  fzf                       # Fuzzy finder integration
  fzf-tab                   # Replace tab completion with fzf popup
  aws                       # AWS CLI completions
  terraform                 # Terraform aliases (tf, tfa, tfp)
  kubectl                   # kubectl aliases (k, kgp, kgs)
  docker                    # Docker completions
  docker-compose            # Docker Compose completions
  tmux                      # Tmux aliases
  direnv                    # Direnv hook
  extract                   # Universal archive extraction
  copybuffer                # Ctrl+O copies command line to clipboard
)

source "${ZSH}/oh-my-zsh.sh"

# ─── Zsh Options ───────────────────────────────────────────────
# Directory navigation
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT

# Globbing
setopt EXTENDED_GLOB NO_CASE_GLOB NUMERIC_GLOB_SORT

# Correction
setopt CORRECT

# Jobs
setopt LONG_LIST_JOBS NO_BG_NICE

# ─── History ───────────────────────────────────────────────────
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000

setopt EXTENDED_HISTORY          # Timestamps in history
setopt SHARE_HISTORY             # Share across sessions (implies INC_APPEND_HISTORY)
setopt HIST_EXPIRE_DUPS_FIRST    # Expire dupes first
setopt HIST_IGNORE_ALL_DUPS      # Remove older dupes
setopt HIST_IGNORE_SPACE         # Skip space-prefixed commands
setopt HIST_REDUCE_BLANKS        # Remove extra blanks
setopt HIST_VERIFY               # Show before executing from history
setopt HIST_FIND_NO_DUPS         # No dupes in search

# ─── Completion Tuning ─────────────────────────────────────────
# -u: skip ownership check (needed for two-account setup where
#     Homebrew completions are owned by admin user, not daily user)
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
  compinit -u
else
  compinit -u -C
fi

zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${HOME}/.zcompcache"
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
zstyle ':completion:*:warnings' format '%F{red}── no matches ──%f'
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

# ─── Key Bindings ──────────────────────────────────────────────
bindkey -e
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey '^[[3~' delete-char

# ─── fzf Integration ──────────────────────────────────────────
if command -v fzf &>/dev/null; then
  source <(fzf --zsh) 2>/dev/null || { [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh; }
  export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border --info=inline'
  if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
fi

# ─── Lazy-load thefuck (saves ~200ms startup) ─────────────────
if command -v thefuck &>/dev/null; then
  _thefuck_lazy() { unset -f fuck; eval "$(thefuck --alias)"; fuck "$@"; }
  alias fuck='_thefuck_lazy'
fi

# ─── Shortcuts ────────────────────────────────────────────────
alias g=git
alias rzsh='arch -x86_64 zsh'

# ─── Load ns-bootstrap shell functions & aliases ───────────────────
[[ -f "${HOME}/.config/ns-bootstrap/config" ]] && source "${HOME}/.config/ns-bootstrap/config"
[[ -f "${NS_BOOTSTRAP_DIR:-$HOME/ns-bootstrap}/shell/loader.sh" ]] && source "${NS_BOOTSTRAP_DIR:-$HOME/ns-bootstrap}/shell/loader.sh"

# ─── Zoxide (smart cd) ──────────────────────────────────────────
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# ─── Atuin (modern shell history) ───────────────────────────────
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# ─── Starship prompt (must be last — sets PS1) ──────────────────
command -v starship &>/dev/null && eval "$(starship init zsh)"
