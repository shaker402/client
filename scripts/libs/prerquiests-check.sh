#!/usr/bin/env bash
set -eo pipefail
# Verify if the required packages are installed
sudo apt-get install -y jq
# List of required packages
REQUIRED_PACKAGES=${REQUIRED_PACKAGES:-("curl" "git" "docker" "docker-compose")}

# Function to check if a package is installed
check_package_installed() {
  local package=$1
  if command -v "$package" &> /dev/null; then
    echo "$package is installed."
  else
    echo "$package is not installed."
    exit 1
  fi
}

# Function to check a list of required packages
check_required_packages() {
  local packages=("$@")
  printf "Checking required packages...\n"
  for package in "${packages[@]}"; do
    check_package_installed "$package"
  done
  print_green "All required packages are installed."
}

# Check if the required packages are installed
check_required_packages "${REQUIRED_PACKAGES[@]}"
