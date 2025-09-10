
#!/bin/bash



# Configuration
ELASTIC_URL="https://127.0.0.1/elasticsearch"
USERNAME="elastic"
PASSWORD="changeme"
PIPELINE_NAME="windows_field_normalization"
PIPELINE_FILE="Lowercase_Normalization_Pipeline.json"

# Check if file exists
if [ ! -f "$PIPELINE_FILE" ]; then
  echo "Error: Pipeline file $PIPELINE_FILE not found!"
  exit 1
fi

# Upload the pipeline
echo "Uploading pipeline..."
response=$(curl -sk -u "$USERNAME:$PASSWORD" -X PUT "$ELASTIC_URL/_ingest/pipeline/$PIPELINE_NAME" \
  -H "Content-Type: application/json" \
  -d "@$PIPELINE_FILE")

# Check response
if echo "$response" | grep -q "\"acknowledged\":true"; then
  echo "Pipeline created successfully!"
  exit 0
else
  echo "Error creating pipeline:"
  echo "$response"
  exit 1
fi
