# Shell Cross-Platform Patterns

## Script Directory Resolution

`BASH_SOURCE[0]` is empty in zsh. Use a portable pattern:

```bash
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${(%):-%x}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
    SCRIPT_DIR="${FALLBACK_DIR}"
fi
```

## OS Detection

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux — parse /etc/os-release for distro details
fi
```

Architecture: `$(arch)` returns `arm64` (Apple Silicon) or `x86_64` (Intel/AMD).

## compinit in Multi-User Setups

When Homebrew completions are owned by a different user (e.g. admin installed brew, daily user sources completions), `compinit` flags them as insecure:

```bash
# -u skips the ownership check (safe when you control both accounts)
compinit -u
```

Cache the completion dump to speed up shell startup — only rebuild if older than 24 hours:

```bash
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
    compinit -u
else
    compinit -u -C
fi
```

## Shell Loader Pattern

Auto-source all `.sh` files from organized directories:

```
shell/
  aliases/         # Alias definitions
  functions/       # Shell functions
  platform/macos/  # macOS-only scripts
  platform/ubuntu/ # Ubuntu-only scripts
```

The loader iterates `aliases/*.sh` and `functions/*.sh`, then conditionally sources `platform/<os>/*.sh` based on `$OSTYPE`.

## Template Variable Pattern

Commit config files with `${PLACEHOLDER}` variables. Process them at bootstrap time:

```bash
process_template() {
    local src="$1" dest="$2"
    local content
    content="$(cat "$src")"
    content="${content//\$\{GIT_NAME\}/$GIT_NAME}"
    content="${content//\$\{GIT_EMAIL\}/$GIT_EMAIL}"
    printf '%s\n' "$content" > "$dest"
}
```

This keeps secrets out of the repo while maintaining readable templates.

## PATH Deduplication

In zsh, prevent duplicate PATH entries when re-sourcing configs:

```bash
typeset -U PATH
```

## History Best Practices

```bash
setopt EXTENDED_HISTORY       # Timestamp each entry
setopt SHARE_HISTORY          # Share across sessions
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicates
setopt HIST_IGNORE_SPACE      # Don't record commands starting with space
setopt HIST_FIND_NO_DUPS      # Skip dupes in reverse search
```

## Starship Prompt

Must be initialized last in `.zshrc` (it sets PS1). Disable oh-my-zsh theme when using Starship: `ZSH_THEME=""`.
