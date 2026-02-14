#!/usr/bin/env bash
# Docker utility functions and aliases

DOCKER_SAVE_DIR="${DATA_DIR:-${HOME}}/docker"

function docker_save_images() {
  images=$(docker images | grep -v 'REPOSITORY' | cut -f1 -d' ')
  for list in $images; do
    listmod=${list/\//SLASH}
    docker save -o "${DOCKER_SAVE_DIR}/${listmod}.tar" $list
  done
}

function docker_restore_images() {
  images=$(ls -1 "${DOCKER_SAVE_DIR}")
  for img in $images; do
    docker load -i "${DOCKER_SAVE_DIR}/$img"
  done
}

docker_tags() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: docker_tags <image> [filter]"
    echo "  e.g.: docker_tags ubuntu 22"
    return 1
  fi
  local image="$1"
  local filter="${2:-}"
  local tags
  tags=$(skopeo list-tags "docker://docker.io/library/${image}" | jq -r '.Tags[]')
  if [[ -n "$filter" ]]; then
    tags=$(echo "$tags" | grep "$filter")
  fi
  echo "$tags"
}

# Cleanup — uses built-in Docker prune (safer, supports filters)
alias docker_prune="docker system prune -f"
alias docker_nuke="docker system prune -a --volumes -f"
alias docker_ami='docker run -it amazonlinux:latest /bin/bash'
