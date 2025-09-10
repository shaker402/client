#!/bin/bash
set -eo pipefail

# Define the base directory
BASE_DIR="/home/tenroot/setup_platform"
SOURCE_DIR="${BASE_DIR}/workdir/risx-mssp/backend/python-scripts/agent_scripts"
CONTAINER_NAME="risx-mssp-backend"
DEST_DIR="/python-scripts/agent_scripts"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory $SOURCE_DIR does not exist."
    exit 1
fi

# Check if container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Error: Container $CONTAINER_NAME is not running."
    exit 1
fi

# Set permissions on host files first
echo "Setting permissions on host files..."
sudo chmod -R 755 "$SOURCE_DIR"
sudo chown -R root:root "$SOURCE_DIR"

# Copy files to container
echo "Copying agent scripts to container..."
docker cp "$SOURCE_DIR"/. "$CONTAINER_NAME:$DEST_DIR"

# Source environment variables
if [ -f "${BASE_DIR}/workdir/.env" ]; then
    set -a
    source "${BASE_DIR}/workdir/.env"
    set +a
fi

# Create the directory structure on the host if it doesn't exist
VELOCIRAPTOR_CONFIG_DIR="${BASE_DIR}/workdir/risx-mssp/backend/python-scripts/modules/Velociraptor/dependencies"
echo "Creating Velociraptor config directory on host..."
sudo mkdir -p "$VELOCIRAPTOR_CONFIG_DIR"
sudo chown -R 1000:1000 "${BASE_DIR}/workdir/risx-mssp/backend/python-scripts/modules/Velociraptor"

# Generate Velociraptor API config
echo "Generating Velociraptor API configuration..."
cd "${BASE_DIR}/workdir/velociraptor/velociraptor/"
sudo ./velociraptor --config server.config.yaml config api_client \
  --name api --role api,administrator \
  "$VELOCIRAPTOR_CONFIG_DIR/api.config.yaml"
cd -

# Set ownership of the generated config file
sudo chown 1000:1000 "$VELOCIRAPTOR_CONFIG_DIR/api.config.yaml"

# Update IP address in the config file
echo "Updating IP address in Velociraptor API configuration..."
sed -i "s/0.0.0.0:8001/${MYIP}:8001/g" "$VELOCIRAPTOR_CONFIG_DIR/api.config.yaml"

# Create the directory structure in the container if it doesn't exist
echo "Creating Velociraptor dependencies directory in container..."
docker exec "$CONTAINER_NAME" mkdir -p "/python-scripts/modules/Velociraptor/dependencies"

# Copy the updated config file to the container
echo "Copying updated Velociraptor API configuration to container..."
docker cp "$VELOCIRAPTOR_CONFIG_DIR/api.config.yaml" \
  "$CONTAINER_NAME:/python-scripts/modules/Velociraptor/dependencies/api.config.yaml"


cd "${BASE_DIR}/workdir/nginx"
docker compose restart

cd "${BASE_DIR}/workdir/risx-mssp"
docker compose restart


echo "All operations completed successfully!"
