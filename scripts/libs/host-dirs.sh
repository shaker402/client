#!/bin/bash
###
# Define a common volumes on the host machine and share them in the containers
###
set -eo pipefail

source "./libs/main.sh"
define_env
define_paths

printf "Prepare common directories on the host machine...\n"
DIRS=${HOST_COMMON_DIRS:-"logs tmp plaso"}
DIRS=($DIRS)

function create_dir() {
  local dir=$1
  if [ -z "$dir" ]; then
    print_red "Usage: %s <dir>\n" "$0"
    exit 1
  fi
  if [ -z "$workdir" ]; then
    print_red "\$workdir is not defined\n"
    exit 1
  fi

  mkdir -p "${workdir}/${dir}"
  chmod -R 755 "${workdir}/${dir}"
  chown -R 1000:1000 "${workdir}/${dir}"
  print_green "Directory ${workdir}/${dir} is ready"
}

function make_common_dirs() {
  for dir in "${DIRS[@]}"; do
    create_dir "$dir"
  done
  print_green_v2 "Common directories" "are ready"
}

function cleanup_common_dirs() {
  printf "Cleaning up common directories on the host machine...\n"
  if [ -z "$workdir" ]; then
    print_red "\$workdir is not defined\n"
    exit 1
  fi
  for dir in "${DIRS[@]}"; do
    rm -rf "${workdir}/${dir}"
  done
  print_green_v2 "Common directories" "are cleaned up"
}
