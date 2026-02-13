# ─── .zprofile ─────────────────────────────────────────────────
# Runs ONCE per login session. Environment variables & PATH only.

# ─── Homebrew (architecture-aware) ─────────────────────────────
if [ "$(arch)" = "arm64" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    eval "$(/usr/local/bin/brew shellenv)"
fi

# ─── Setup Directory ──────────────────────────────────────────
# Points to the my_setup repo. Override in ~/.zshenv if cloned elsewhere.
export MY_SETUP_DIR="${MY_SETUP_DIR:-${HOME}/my_setup}"

# ─── Environment Variables ─────────────────────────────────────
export EDITOR="code --wait"
export VISUAL="code --wait"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# ─── Go ───────────────────────────────────────────────────────
export PATH="${HOME}/go/bin:${PATH}"

# ─── PATH (deduplicated) ──────────────────────────────────────
typeset -U PATH
export PATH="${HOME}/bin:${HOME}/.local/bin:${PATH}"

# ─── mise (polyglot version manager for Node, Python, Ruby) ──
command -v mise &>/dev/null && eval "$(mise activate zsh)"
