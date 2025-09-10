#!/bin/bash
set -eo pipefail

# Define container name and file paths
CONTAINER_NAME="risx-mssp-backend"
BASE_DIR="/home/tenroot/setup_platform"
PASSWORD_FILE="${BASE_DIR}/workdir/risx-mssp/shoresh.passwd"
TEMP_FILE="/tmp/container_env"
ZSOAR_CONFIG="/python-scripts/Z-SOAR/configs/zsoar_config.yml"
TEMP_ZSOAR_CONFIG="/tmp/zsoar_config.yml"

# Check if the password file exists
if [ ! -f "$PASSWORD_FILE" ]; then
    echo "Error: Password file $PASSWORD_FILE does not exist."
    exit 1
fi

# Check if container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    echo "Error: Container $CONTAINER_NAME is not running."
    exit 1
fi

# Read the new password from the file
NEW_PASSWORD=$(cat "$PASSWORD_FILE" | tr -d '\n')

# First, let's find where the .env file is located in the container
echo "Looking for .env file in container..."
ENV_PATH=$(docker exec "$CONTAINER_NAME" sh -c "find / -name '.env' -type f 2>/dev/null | head -1")

if [ -z "$ENV_PATH" ]; then
    echo "Error: Could not find .env file in container."
    exit 1
fi

echo "Found .env file at: $ENV_PATH"

# Copy the .env file from the container to a temporary location
echo "Copying .env file from container..."
docker cp "$CONTAINER_NAME:$ENV_PATH" "$TEMP_FILE"

# Update the DATABASE_PASSWORD in the temporary file
echo "Updating DATABASE_PASSWORD..."
sed -i "s/^DATABASE_PASSWORD=.*/DATABASE_PASSWORD=$NEW_PASSWORD/" "$TEMP_FILE"

# Copy the modified file back to the container
echo "Copying updated .env file back to container..."
docker cp "$TEMP_FILE" "$CONTAINER_NAME:$ENV_PATH"

# Clean up the temporary file
rm -f "$TEMP_FILE"

# Verify the change was made
echo "Verifying the password update..."
docker exec "$CONTAINER_NAME" sh -c "grep '^DATABASE_PASSWORD=' $ENV_PATH"

# Update Z-SOAR configuration
echo "Updating Z-SOAR daemon configuration..."
# Copy the Z-SOAR config file from the container
docker cp "$CONTAINER_NAME:$ZSOAR_CONFIG" "$TEMP_ZSOAR_CONFIG"

# Update the daemon enabled setting - fix the sed command
sed -i '/daemon:/{n;s/enabled: false/enabled: true/}' "$TEMP_ZSOAR_CONFIG"

# Copy the modified file back to the container
docker cp "$TEMP_ZSOAR_CONFIG" "$CONTAINER_NAME:$ZSOAR_CONFIG"

# Clean up the temporary file
rm -f "$TEMP_ZSOAR_CONFIG"

# Verify the change was made
echo "Verifying Z-SOAR daemon configuration update..."
docker exec "$CONTAINER_NAME" sh -c "grep -A 1 'daemon:' $ZSOAR_CONFIG"

echo "All updates completed successfully!"
