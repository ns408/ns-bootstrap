#!/usr/bin/env bash
# Modern CLI Tools Aliases
# Optional aliases to use modern tools by default while keeping originals available

# NOTE: These aliases are OPTIONAL. Uncomment the ones you want to use.
# The traditional commands will still be available with 'old' prefix.

# === Search & Find ===

# Use ripgrep instead of grep (much faster, respects .gitignore)
# alias grep='rg'
# alias oldgrep='command grep'

# Use fd instead of find (faster, better syntax)
# alias find='fd'
# alias oldfind='command find'

# === File Viewing ===

# Use bat instead of cat (syntax highlighting, git integration)
# alias cat='bat --style=auto'
# alias oldcat='command cat'

# Bat without decorations (like cat but with highlighting)
alias bcat='bat --style=plain --paging=never'

# === Directory Listing ===

# Use eza instead of ls (better formatting, git integration, icons)
# alias ls='eza --icons'
# alias ll='eza -lah --icons --git'
# alias la='eza -a --icons'
# alias lt='eza --tree --icons'
# alias oldls='command ls'

# Or keep ls but add helpful variants
alias lsa='eza -lah --icons --git'        # All files with details
alias lst='eza --tree --icons --level=2'  # Tree view
alias lsg='eza -lah --icons --git'        # With git status

# === System Monitoring ===

# Use btop instead of top (better interface, more info)
# alias top='btop'
# alias oldtop='command top'

# Use dust instead of du (better tree view)
# alias du='dust'
# alias olddu='command du'

# Use duf instead of df (prettier, more informative)
# alias df='duf'
# alias olddf='command df'

# Use procs instead of ps (modern, colorful)
# alias ps='procs'
# alias oldps='command ps'

# === Networking ===

# Use doggo instead of dig (modern DNS client, DoH/DoT/DoQ support)
# alias dig='doggo'
# alias olddig='command dig'

# Use gping instead of ping (with graph)
# alias ping='gping'
# alias oldping='command ping'

# Use httpie instead of curl (simpler syntax, better output)
alias http='httpie'
alias https='httpie https://'

# === Git ===

# Delta is set in .gitconfig as core.pager
# But you can use it standalone:
alias gdiff='git diff | delta'
alias gshow='git show | delta'

# === FZF Integrations ===

# Fuzzy cd into directory
alias fcd='cd $(fd -t d | fzf)'

# Fuzzy edit file
alias fvim='vim $(fd -t f | fzf)'
alias fcode='code $(fd -t f | fzf)'

# Fuzzy kill process
fkill() { ps aux | fzf | awk '{print $2}' | xargs kill; }

# Fuzzy git checkout branch
alias fco='git branch | fzf | xargs git checkout'

# Fuzzy history search (Ctrl+R alternative)
alias fh='history | fzf | sed "s/^[0-9 ]*//" | sh'

# === Zoxide (Smart CD) ===

# Zoxide replaces cd when initialized with: eval "$(zoxide init zsh)"
# Then use: z <directory-substring>
# Examples:
#   z doc    # jumps to ~/Documents or most frecent match
#   zi       # interactive selection with fzf
#   z -       # go back

# Keep traditional cd available
alias oldcd='command cd'

# === Additional Utilities ===

# tldr - simplified man pages
alias help='tldr'

# Better tar extraction
alias untar='tar -xvf'
alias targz='tar -xzvf'

# Better JSON pretty-print with syntax highlighting
alias json='jq . | bat -l json'

# Quick HTTP server (Python)
alias serve='python3 -m http.server'

# Modern cat with line numbers
alias catn='bat --style=numbers --paging=never'

# Disk usage for current directory
alias duu='dust -d 1'

# Monitor bandwidth per process
alias bandwidth='bandwhich'

# === Helpful Functions ===

# Interactive file preview with fzf and bat
fpreview() {
    fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'
}

# Search content and preview with fzf
rgsearch() {
    local query="$1"
    rg --line-number --no-heading --color=always "$query" | \
        fzf --ansi --preview "bat --style=numbers --color=always --highlight-line {2} {1}"
}

# Quick benchmark comparison
bench() {
    hyperfine "$@"
}

# Bat configuration
if command -v bat &> /dev/null; then
    export BAT_THEME="TwoDark"
    export BAT_STYLE="numbers,changes,header"
fi

# === Tips ===
#
# Run 'modern-tools-help' for a quick reference
#
modern-tools-help() {
    cat << 'EOF'
Modern CLI Tools Quick Reference:

Search & Find:
  rg <pattern>              - Search for pattern (respects .gitignore)
  fd <pattern>              - Find files matching pattern
  fzf                       - Interactive fuzzy finder

File Viewing:
  bat <file>                - View file with syntax highlighting
  bcat <file>               - View without decorations

Directory Listing:
  eza -lah                  - Detailed list with git status
  eza --tree                - Tree view

System Monitoring:
  btop                      - Interactive process viewer
  dust                      - Disk usage analyzer
  duf                       - Disk usage with better formatting
  procs                     - Process viewer

Navigation:
  z <dir>                   - Jump to directory (frecency-based)
  zi                        - Interactive directory selector

Network:
  doggo <domain>            - DNS lookup (DoH/DoT/DoQ support)
  gping <host>              - Ping with graph
  httpie <url>              - HTTP client

Git:
  git diff                  - Uses delta pager automatically
  gdiff                     - Standalone delta diff

For full documentation:
  man <tool>                - Traditional man pages
  tldr <tool>               - Simplified examples
  <tool> --help             - Built-in help

To enable default aliases, edit: shell/aliases/modern-tools.sh
EOF
}
