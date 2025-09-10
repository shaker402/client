#!/bin/bash
set -eo pipefail

# Change to workdir
cd /home/tenroot/setup_platform/workdir

# Create network (ignore error if already exists)
docker network create main_network || true

# Start Velociraptor
echo "Starting Velociraptor..."
cd velociraptor
docker compose up -d
cd ..

# Start ELK stack
echo "Starting ELK stack..."
cd elk
# First run setup container
docker compose up -d
# Wait for setup to complete
echo "Waiting for ELK setup to complete..."
sleep 30
# Start all ELK services
docker compose up -d
cd ..

# Start OSSIEM (Wazuh)
echo "Starting OSSIEM..."
cd OSSIEM
docker compose up -d
cd ..

# Set permissions and start RISX-MSSP
echo "Starting RISX-MSSP..."
cd risx-mssp
# Set permissions
chmod -R 777 backend
# Start services
docker compose up -d
cd ..

# Start Nginx
echo "Starting Nginx..."
cd nginx
docker compose up -d
cd ..

# Run ELK setup again
echo "Running ELK setup again..."
cd elk
docker compose up setup
cd ..

# Change to scripts directory and run new_endtoend.sh
echo "Running final setup script..."
cd /home/tenroot/setup_platform/scripts
./new_endtoend.sh

echo "All services started successfully!"
