#!/bin/bash
set -eo pipefail

# Define container name
CONTAINER_NAME="risx-mssp-backend"
FILE_TO_REMOVE="/python-scripts/.interval_zsoar_last_run"

# Check if container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Error: Container $CONTAINER_NAME is not running."
    exit 1
fi

# Remove the specific file inside the container
echo "Removing file $FILE_TO_REMOVE from container $CONTAINER_NAME..."
docker exec "$CONTAINER_NAME" sh -c "rm -f $FILE_TO_REMOVE"

# List the contents of /python-scripts directory in the container
echo "Listing contents of /python-scripts directory in container:"
docker exec "$CONTAINER_NAME" ls -la /python-scripts

echo "Operation completed successfully!"
