#!/usr/bin/env bash
set -eo pipefail

source libs/main.sh
source libs/host-dirs.sh
define_env
define_paths

# HELP describe output and options
function show_help() {
  print_with_border "Help for cleanup.sh"
  printf "Usage: %s [OPTIONS]\n" "$0"
  printf "Options:\n"
  printf "  --force Cleanup all docker services and networks on the host\n"
  printf "  --app <app_name>\tCleanup specific app\n"
  printf "  --help\t\tShow help\n"
  printf "######################\n"
  print_green "Default: Cleanup all services defined in the .env file"
}

# docker compose down
app_down() {
  local app_name=$1
  # Find all docker-compose.yml files and stop the services
  while IFS= read -r -d '' file; do
    printf "Stopping the %s app...\n" "$app_name"
    cd "$(dirname "$file")" || exit
    docker compose down --volumes --remove-orphans --timeout 1
    cd - || exit
  done < <(find "${workdir}/${app_name}" -maxdepth 2 -name docker-compose.yaml -print0 -o -name docker-compose.yml -print0 -o -name compose.yaml -print0)
}

cleanup_all_force() {
  print_yellow "Cleaning up FORCE all docker containers and related files ..."
  docker container stop $(docker container ls -aq) || print_yellow "No containers to stop"
  docker container rm $(docker container ls -aq) || print_yellow "No containers to remove"
  docker network rm $(docker network ls -q) || true
  docker volume rm $(docker volume ls -q) || true

  printf "Cleaning up related workdir...\n"
  sudo rm -rf "${workdir}"/*
  sudo rm -rf "${workdir}"/.env
  print_green_v2 "Cleanup force" "finished"
}

# function to delete app dirs and files
delete_app_dirs() {
  local app_name=$1
  if [ -z "$app_name" ]; then
    printf "App name is not provided\n"
    print_red "Usage: %s --app <app_name>\n" "$0"
    exit 1
  fi
  printf "Deleting the %s app files ...\n" "$app_name"
  sudo rm -rf "${workdir}/${app_name}"
}

# Default function
default_cleanup() {
  printf "Default: Cleaning up the docker services...\n"
  # Iterate over APPS_TO_INSTALL and delete the app dirs
  for app in "${APPS_TO_INSTALL[@]}"; do
    app_down "$app"
    delete_app_dirs "$app"
  done

  delete_app_dirs ".env"
  app_down "nginx"
  delete_app_dirs "nginx"
  cleanup_common_dirs

  # If defined NETWORK_NAME , then remove DEFAULT network
  if [ -n "$NETWORK_NAME" ]; then
    printf "Removing the %s network\n" "$NETWORK_NAME"
    # Fix an issue with the removing default docker network.
    print_yellow "Restarting the docker service."
    sudo systemctl restart docker
    docker network rm "$NETWORK_NAME" --force || true
  fi
  docker network prune --force

  print_green_v2 "Cleanup" "finished"

  # Prompt to stop and remove all containers
  read -p "Do you want to stop all running containers and remove them? [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    docker stop $(docker ps -aq) || echo "No running containers to stop."
    docker rm $(docker ps -aq) || echo "No containers to remove."
  else
    echo "Skipped stopping/removing containers."
  fi
}

# Check flags arguments and call related function
if [[ "$#" -eq 0 ]]; then
  default_cleanup
  exit 0
fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --help)
      show_help
      exit 0
      ;;
    --app)
      app_name=$2
      app_down "$app_name"
      delete_app_dirs "$app_name"
      shift 2
      ;;
    --force)
      cleanup_all_force
      # Prompt to stop and remove all containers for --force as well
      read -p "Do you want to stop all running containers and remove them? [y/N]: " answer
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        docker stop $(docker ps -aq) || echo "No running containers to stop."
        docker rm $(docker ps -aq) || echo "No containers to remove."
      else
        echo "Skipped stopping/removing containers."
      fi
      shift
      ;;
    *)
      printf "Unknown argument: %s\n" "$1"
      show_help
      exit 0
      ;;
  esac
done
