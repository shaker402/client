#!/usr/bin/env bash
# --- The minimal set of functions which uses almost everywhere in the scripts

set -eo pipefail

# Define color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print green message
print_green() {
  local message=$1
  printf "${GREEN}%s${NC}\n" "$message"
}

print_green_v2() {
  local message=$1
  local action=$2
  printf "${GREEN}✔${NC} %s ${GREEN}%s${NC}\n" "$message" "$action"
}

# Function to print red message
print_red() {
  local message=$1
  printf "${RED}%s${NC}\n" "$message"
}

# Function to print yellow message
print_yellow() {
  local message=$1
  printf "${YELLOW}%s${NC}\n" "$message"
}

print_with_border() {
  local input_string="$1"
  local length=${#input_string}
  local border="===================== "
  # Calculate the length of the border
  local border_length=$(((80 - length - ${#border}) / 2))
  # Print the top border
  printf "%s" "$border"
  for ((i = 0; i < border_length; i++)); do
    printf "="
  done
  printf " %s " "$input_string"
  for ((i = 0; i < border_length; i++)); do
    printf "="
  done
  printf "%s\n" "$border"
}

### Business functions ###
# Function to define env variables
define_env() {
  local env_file=${1:-"../workdir/.env"}

  if [ -f "$env_file" ]; then
    source "$env_file"
    printf "%s is loaded\n" "$env_file"
  else
    print_red "Can't find the .env:\"$env_file\" file. Continue without an .env file."
    print_yellow "Try load from the default.env file"
    define_env ../resources/default.env
  fi
}

# Function to define path's
define_paths() {
  local home_path=${1}
  # username should be defined in the .env file
  # If the username is not defined, then ask user to enter the username
  if [ -z "$username" ]; then
    current_user=$(whoami)
    read -p "Enter username for home directory setup (default: $current_user): " username
    username=${username:-$current_user}
  fi
  if [ -z "$home_path" ]; then
    home_path="/home/$username/setup_platform"
  fi

  printf "Home path %s \n" "$home_path"
  resources_dir="$home_path/resources"
  scripts_dir="$home_path/scripts"
  workdir="$home_path/workdir"
}

