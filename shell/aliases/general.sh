#!/usr/bin/env bash
# General aliases - cross-platform

# Tmux
alias tsn="tmux new -s system"
alias tsl="tmux list-sessions"
alias tsa="tmux attach -t system || tsn"

# Network utilities
alias mypublicip='dig +short @208.67.222.220 myip.opendns.com'
alias checknet='ping google.com'

if [[ "$OSTYPE" == "darwin"* ]]; then
    alias open_ports_lsof='sudo lsof -nP -i'
    alias route_print='sudo netstat -nr'
    alias open_ports='sudo netstat -natp tcp | grep -i "listen"'
    alias open_ports1='sudo lsof -i -n -P | grep -i "listen"'
else
    alias open_ports='ss -tlnp'
    alias route_print='ip route'
    alias open_ports1='ss -tulnp'
fi

# Curl
alias curl_headers='curl -s -o /dev/null -D -'
alias curl_download="curl -O --"

# SOCKS5 proxy
alias bash_socks5="export http_proxy=socks5://127.0.0.1:8080 https_proxy=socks5://127.0.0.1:8080"

# Process / system
alias wtf='watch -n 1 w -hs'
alias wth='ps uxa | less'
alias disk_space="sudo df -Ht"

# Pager
alias less="less -eRiXF"
export PAGER="less -eRiXF"

# Misc
alias tzdate_utc='TZ="UTC" date'
alias website_download="wget -rkpNl0 --mirror -p --convert-links -P \$1 \$2"

# Line generator (pbcopy is macOS only)
if command -v pbcopy &>/dev/null; then
  alias pbcopy_line="generate_line | pbcopy"
fi


# Wget
alias wget_mirror="wget -r -m -k"
function wget_restricted() {
  wget -c "$2" --limit-rate="$1"
}

# MySQL
function mysql_connect_tunneled() {
  mysql --host=127.0.0.1 --port="${1}" -u "${2}" -p
}

# Vagrant
alias vagrant_refresh_plugins="vagrant plugin repair"

# MySQL client path (Homebrew on Apple Silicon)
[[ -d "/opt/homebrew/opt/mysql-client/bin" ]] && export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
