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
  tags=$(curl -sL "https://hub.docker.com/v2/repositories/library/${image}/tags?page_size=100" | jq -r '.results[].name')
  if [[ -n "$filter" ]]; then
    tags=$(echo "$tags" | grep "$filter")
  fi
  echo "$tags"
}

alias docker-pull-images="for l in nginx mysql centos postgres; do docker pull \$l; done"
alias docker_prune_dangling="docker images | grep -i '<none>' | awk '{ print \$3 }' | xargs docker rmi"
alias docker-update_all_images="docker images | awk '{print \$1 }' | grep -v -E \"<none>|REPOSITORY\" | xargs -L1 docker pull"
alias docker_nuke_containers="docker ps -a -q | xargs docker rm -f"
alias docker_nuke_images="docker images -q | xargs docker rmi -f"
alias docker_nuke_volumes="docker volume ls -q | xargs docker volume rm"
alias docker_nuke_all="docker_nuke_images; (docker_nuke_containers || docker_nuke_containers); docker_nuke_volumes"
alias docker_ami='docker run -it amazonlinux:latest /bin/bash'
