#!/bin/bash

# Configuration
KIBANA_URL="https://127.0.0.1/kibana"
USER="elastic"
PASS="changeme"

# Retrieve all agent policies
response=$(curl -s -k -u "$USER:$PASS" \
  -X GET "$KIBANA_URL/api/fleet/agent_policies")

# Loop through each policy
echo "$response" | jq -c '.items[]' | while read -r policy; do
  id=$(echo "$policy" | jq -r '.id')
  name=$(echo "$policy" | jq -r '.name')
  description=$(echo "$policy" | jq -r '.description')
  namespace=$(echo "$policy" | jq -r '.namespace')
  # Get current monitoring_enabled array, or empty if missing
  current_monitoring=$(echo "$policy" | jq -r '.monitoring_enabled // empty | @sh' | tr -d "'")
  
  # If monitoring_enabled is missing, set to empty array
  if [ -z "$current_monitoring" ]; then
    monitoring_enabled='[]'
  else
    monitoring_enabled=$(echo "$policy" | jq '.monitoring_enabled')
  fi

  # Test if logs is already enabled
  has_logs=$(echo "$monitoring_enabled" | jq 'index("logs")')
  # Test if metrics is already present
  has_metrics=$(echo "$monitoring_enabled" | jq 'index("metrics")')

  # Prepare new monitoring_enabled array
  if [[ "$has_logs" == "null" ]]; then
    # Add logs (and metrics if already present)
    if [[ "$has_metrics" != "null" ]]; then
      new_monitoring='["logs","metrics"]'
    else
      new_monitoring='["logs"]'
    fi
    # Prepare JSON payload (add more fields as needed)
    payload=$(jq -n \
      --arg name "$name" \
      --arg namespace "$namespace" \
      --arg description "$description" \
      --argjson monitoring_enabled "$new_monitoring" \
      '{
        name: $name,
        namespace: $namespace,
        description: $description,
        monitoring_enabled: $monitoring_enabled
      }'
    )

    echo "[$name] logs not enabled. Enabling logs..."
    curl -s -k -u "$USER:$PASS" \
      -X PUT "$KIBANA_URL/api/fleet/agent_policies/$id" \
      -H "kbn-xsrf: true" \
      -H "Content-Type: application/json" \
      -d "$payload"
    echo
  else
    echo "[$name] logs already enabled. Skipping."
  fi
done

echo "All policies processed."
