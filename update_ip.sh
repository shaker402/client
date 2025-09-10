#!/bin/bash
set -eo pipefail

# Function to replace IP in a file
replace_ip() {
    local file="$1"
    local old_ip="$2"
    local new_ip="$3"
    
    if [ -f "$file" ]; then
        echo "Updating $file"
        sudo sed -i "s/$old_ip/$new_ip/g" "$file"
    else
        echo "Warning: File $file not found, skipping"
    fi
}

# Function to replace IP in docker container file
replace_ip_in_container() {
    local container="$1"
    local file_path="$2"
    local old_ip="$3"
    local new_ip="$4"
    
    if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
        echo "Updating $file_path in container $container"
        docker exec "$container" sh -c "sed -i 's/$old_ip/$new_ip/g' $file_path"
    else
        echo "Warning: Container $container is not running, skipping file $file_path"
    fi
}

# Ask user for new IP
read -p "Enter your new IP address: " NEW_IP

# Validate IP format (basic validation)
if [[ ! $NEW_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format"
    exit 1
fi

OLD_IP="75.119.148.152"
BASE_DIR="/home/tenroot/setup_platform"

echo "Replacing $OLD_IP with $NEW_IP in all configuration files..."

# Update files on host
replace_ip "$BASE_DIR/resources/default.env" "$OLD_IP" "$NEW_IP"
replace_ip "$BASE_DIR/workdir/.env" "$OLD_IP" "$NEW_IP"
replace_ip "$BASE_DIR/workdir/risx-mssp/frontend/.env" "$OLD_IP" "$NEW_IP"
replace_ip "$BASE_DIR/workdir/risx-mssp/backend/.env" "$OLD_IP" "$NEW_IP"
replace_ip "$BASE_DIR/workdir/elk/.env" "$OLD_IP" "$NEW_IP"
replace_ip "$BASE_DIR/workdir/velociraptor/.env" "$OLD_IP" "$NEW_IP"

# Update file in container
replace_ip_in_container "risx-mssp-backend" "/python-scripts/modules/Velociraptor/dependencies/api.config.yaml" "$OLD_IP" "$NEW_IP"

echo "IP address replacement completed successfully!"

cd /home/tenroot/setup_platform/
./start_all_services.sh

