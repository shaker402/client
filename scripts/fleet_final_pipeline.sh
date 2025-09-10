#!/usr/bin/env bash

# This script updates the .fleet_final_pipeline-1 ingest pipeline in Elasticsearch
# It uses the same endpoint you verified manually:
# https://127.0.0.1/elasticsearch/_ingest/pipeline/.fleet_final_pipeline-1
# and ignores TLS verification errors (-k).

ES_USER="elastic"
ES_PASS="changeme"
ES_URL="https://127.0.0.1/elasticsearch/_ingest/pipeline/logs-system.security@custom"
JSON_FILE="fleet_final_pipeline.json"

# Check if the JSON file exists
if [[ ! -f "$JSON_FILE" ]]; then
  echo "Error: $JSON_FILE not found in $(pwd)"
  exit 1
fi

# Perform the PUT request, skipping TLS verification
curl -u ${ES_USER}:${ES_PASS} \
     -X PUT -k "${ES_URL}" \
     -H "Content-Type: application/json" \
     --data @${JSON_FILE}

# Print a newline for readability
echo
