#!/usr/bin/env bash

ES_USER="elastic"
ES_PASS="changeme"
BASE_URL="https://127.0.0.1/elasticsearch/_ingest/pipeline"
FILE_PATTERN="winlogbeat-*.json"

# Check if any pipeline files exist
files=($FILE_PATTERN)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "Error: No Winlogbeat pipeline files found matching pattern '$FILE_PATTERN' in $(pwd)"
    exit 1
fi

# Process each pipeline file
for file in "${files[@]}"; do
    # Extract pipeline name from filename (remove prefix/suffix)
    pipeline_name=$(basename "$file" .json | sed 's/^winlogbeat-[0-9.]*-//')
    
    echo "Uploading pipeline: $pipeline_name"
    
    # Perform the PUT request
    curl -u ${ES_USER}:${ES_PASS} \
         -X PUT -k "${BASE_URL}/${pipeline_name}" \
         -H "Content-Type: application/json" \
         --data @"$file"
    
    echo # Newline for readability
done
