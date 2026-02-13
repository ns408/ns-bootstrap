#!/usr/bin/env bash
# General utility functions

DATA_DIR="${DATA_DIR:-${HOME}/data}"

# Create a line separator
function generate_line() {
  for ((x = 0; x < 80; x++)); do printf %s -; done; echo
}

# YouTube/media downloads (uses yt-dlp as youtube-dl replacement)
Y_dirpath="${DATA_DIR}/youtube_videos"
Y_dl='yt-dlp --user-agent Safari/537.1 --referer http://www.youtube.com/youtube?feature=inp-yo-heh'

alias youtube_audio="cd $Y_dirpath && $Y_dl --audio-format mp3 -f bestaudio -x"
alias youtube_video="cd $Y_dirpath && $Y_dl --no-playlist"

download_youtube() {
  input="$1"
  echo $input
  if [[ "$input" == "video" || "$input" == "audio" ]]; then
    while read list; do "youtube-${input}" $list; done < "${Y_dirpath}/video_download.txt"
  else
    echo -e "\nUse either 'audio' or 'video' and '-k' to keep video after audio download"
  fi
}

# Port knocking
function knock() {
  for i in 60032 38206 54462; do nmap -r -Pn --max-retries 0 $1 -p $i; done
}

check_port() {
  if [ -z "$1" -a -z "$2" ]; then
    echo -e "check_port hostname port\n"
  else
    nc -z -w5 $1 $2
  fi
}

# Password generation
genpass() {
  local l="${1:-32}"
  tr -dc 'A-Za-z0-9_!@#$%' < /dev/urandom | head -c "$l"
  echo
}

gen_pass() {
  local l="${1:-32}"
  openssl rand -base64 "$l"
}

# Find all images
function find_all_images() {
  SAVEIFS=$IFS
  IFS="$(printf '\n\t')"
  find . -regex ".*\.\(jpg\|gif\|png\|jpeg\)"
  find . -name '*' -exec file {} \; | grep -o -P '^.+: \w+ image'
  IFS=$SAVEIFS
}

# SSL/TLS certificate inspection
function ssl_from_site {
  local host=$1
  local port=$2
  openssl s_client -servername $host -connect ${host}:${port} < /dev/null 2> /dev/null | openssl x509 -text
}

function ssl_test_tls1.2 {
  local host=$1
  local port=$2
  openssl s_client -connect ${host}:${port} -tls1_2
}

# YAML validation
yaml_check() {
  if command -v yq &>/dev/null; then
    yq eval '.' "$1" > /dev/null
  else
    python3 -c "import yaml; yaml.safe_load(open('$1'))"
  fi
}

# Virtual environment activation
function activate_venv {
  local VENV=$1
  local VENV_DIR="${DATA_DIR}/virtualenvs"
  source "${VENV_DIR}/${VENV}/bin/activate"
}

# Mount ext filesystem (macOS with fuse-ext2)
function mount_ext {
  local MNT_DIR="${DATA_DIR}/mnt"
  test -d "$MNT_DIR" || mkdir -p "$MNT_DIR"
  sudo "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/fuse-ext2" -o ro "$1" "$MNT_DIR"
}

# NFS mount
function nfs_mount {
  local MNT_DIR="${DATA_DIR}/mnt"
  sudo mount -t nfs -o resvport ${1} "$MNT_DIR/"
}

# Tmux utilities
function tmux_send_command() {
  local acommand="$@"
  tmux send -t system: ${acommand} ENTER
}

# PDF compression
# Usage: compresspdf [input file] [output file] [screen*|ebook|printer|prepress]
function compresspdf() {
  gs -sDEVICE=pdfwrite -dNOPAUSE -dQUIET -dBATCH -dPDFSETTINGS=/${3:-"screen"} -dCompatibilityLevel=1.4 -sOutputFile="$2" "$1"
}

# GPG key export
function gpg_export_secret_key() {
  gpg --armor --gen-random 1 20
  gpg --armor --export-secret-keys "${1}" | gpg --armor --symmetric --output mygpgkey.sec.asc
}

# GPG signature verification
function gpg_check_signature() {
  local sigfile=$1
  local archive=$2
  gpg --verify $sigfile $archive
}
