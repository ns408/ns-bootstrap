# Modern CLI Tools

## Migration Table

| Legacy | Modern | Why |
|--------|--------|-----|
| `grep` | `ripgrep` (`rg`) | 10-100x faster, respects .gitignore, better defaults |
| `find` | `fd` | Simpler syntax, faster, respects .gitignore |
| `cat` | `bat` | Syntax highlighting, line numbers, git integration |
| `ls` | `eza` | Colors, git status, tree view built-in |
| `cd` | `zoxide` | Frecency-based directory jumping |
| `top`/`htop` | `btop` | Beautiful UI, mouse support, per-process I/O |
| `du` | `dust` | Visual disk usage with tree layout |
| `df` | `duf` | Colored, grouped by filesystem type |
| `diff` | `delta` | Side-by-side, syntax-highlighted git diffs |
| `dig` | `doggo` | Human-friendly DNS lookups |
| `curl` | `httpie` | Intuitive HTTP client with JSON support |
| `Ctrl+R` | `atuin` | SQLite-backed shell history with full-text search |
| `ping` | `gping` | Graphical ping with multiple hosts |
| `ps` | `procs` | Colored process list with tree view |

## fzf Integration

```bash
# Use fd for file search (respects .gitignore)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'

# Preview with bat
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :200 {}'"
```

`fzf-tab` replaces standard zsh tab completion with an fzf popup — install as an oh-my-zsh custom plugin.

## atuin

SQLite-backed shell history with cross-machine sync (optional):

```toml
# ~/.config/atuin/config.toml
sync_frequency = "0"     # Disable sync (local only)
update_check = false
style = "compact"
```

## mise (version manager)

Unified polyglot version manager replacing nvm, pyenv, rbenv, etc.:

```bash
# Install and use
mise use node@20
mise use python@3.12

# Activate in shell
eval "$(mise activate zsh)"
```

Config file (`.mise.toml` or `.tool-versions`) in project root pins versions per-project.

## delta (git diff)

```ini
# .gitconfig
[core]
    pager = delta
[delta]
    navigate = true
    side-by-side = true
    line-numbers = true
[merge]
    conflictstyle = zdiff3
```
