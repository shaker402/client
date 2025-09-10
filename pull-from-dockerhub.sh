#!/bin/bash
set -e

# Configuration
DOCKERHUB_USERNAME="shakr402k"

# List of images to pull (same as you pushed)
IMAGES=(
    "risx-mssp-backend:latest"
    "risx-mssp-mysql:latest"
    "risx-mssp-frontend:latest"
    "velociraptor-tenroot:latest"
    "elastic-agent:8.17.4"
    "elk-elasticsearch:latest"
    "elk-setup:latest"
    "elk-kibana:latest"
    "elk-logstash:latest"
    "wazuh-dashboard:4.9.0"
    "wazuh-indexer:4.9.0"
    "wazuh-manager:4.9.0"
    "wazuh-certs-generator:0.0.2"
    "nginx:1.19.3-alpine"
)

echo "Pulling images from Docker Hub..."
for image in "${IMAGES[@]}"; do
    # Pull from Docker Hub
    full_image="$DOCKERHUB_USERNAME/${image%%:*}:${image##*:}"
    echo "Pulling $full_image"
    docker pull "$full_image"

    # Optional: Retag to original name if needed
    echo "Tagging $full_image as $image"
    docker tag "$full_image" "$image"
done

./update_ip.sh
echo "All images have been pulled and tagged successfully!"
