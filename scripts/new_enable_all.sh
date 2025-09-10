#!/usr/bin/env bash
set -euo pipefail

# Source the environment variables like the main script does
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${SCRIPT_DIR}/../workdir"

if [ -f "${WORKDIR}/.env" ]; then
    set -a
    source "${WORKDIR}/.env"
    set +a
else
    echo "❌ Error: .env file not found at ${WORKDIR}/.env"
    exit 1
fi

# Validate that required variables are set
if [ -z "${MYIP:-}" ]; then
    echo "❌ Error: MYIP is not set in the environment"
    exit 1
fi

PROTO=${PROTO:-https}

#### CONFIGURATION ####
KIBANA_BASE="${PROTO}://${MYIP}/kibana"
AUTH="elastic:${ELASTIC_PASSWORD:-changeme}"
PER_PAGE=1000
CHUNK_SIZE=100  # Kibana bulk limit is 100 IDs per request
#######################

echo "Using Kibana at: $KIBANA_BASE"
echo "1/4 ▶ Calculating total disabled rule count..."
total_rules=$(curl -sk -u "$AUTH" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  "$KIBANA_BASE/api/detection_engine/rules/_find?per_page=1&filter=alert.attributes.enabled:false" | jq '.total')

if [ "$total_rules" -eq 0 ]; then
  echo "⚠️  No disabled rules found. Exiting."
  exit 0
fi

PAGES=$(( (total_rules + PER_PAGE - 1) / PER_PAGE ))
echo "✔ Found $total_rules disabled rules across $PAGES pages."

echo "2/4 ▶ Fetching all disabled rule IDs..."
rule_ids=()
for ((page=1; page<=PAGES; page++)); do
  printf "   • Fetching page %d/%d... " "$page" "$PAGES"
  
  page_rules=$(curl -sk -u "$AUTH" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    "$KIBANA_BASE/api/detection_engine/rules/_find?per_page=$PER_PAGE&page=$page&filter=alert.attributes.enabled:false")
  
  mapfile -t page_ids < <(jq -r '.data[] | .id' <<<"$page_rules")
  rule_ids+=("${page_ids[@]}")
  
  echo "found ${#page_ids[@]} rules"
done

count=${#rule_ids[@]}
if [ "$count" -eq 0 ]; then
  echo "⚠️  No disabled rules found. Exiting."
  exit 0
fi
echo "✔ Collected $count disabled rules total."

echo "3/4 ▶ Creating chunks of $CHUNK_SIZE rules..."
chunk_count=$(( (count + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo "✔ Will process $chunk_count chunks"

echo "4/4 ▶ Enabling rules in bulk..."
for ((i=0; i<count; i+=CHUNK_SIZE)); do
  end=$((i + CHUNK_SIZE))
  [ $end -gt $count ] && end=$count
  chunk_size=$((end - i))
  chunk_index=$((i/CHUNK_SIZE + 1))
  
  # Extract chunk of IDs
  chunk_ids=("${rule_ids[@]:i:chunk_size}")
  ids_list=$(printf ',"%s"' "${chunk_ids[@]}" | cut -c2-)
  
  printf "   • Enabling chunk %d/%d (%d rules)... " "$chunk_index" "$chunk_count" "$chunk_size"
  
  enable_resp=$(curl -sk -u "$AUTH" \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -X POST "$KIBANA_BASE/api/detection_engine/rules/_bulk_action" \
    -d @- \
    -w "\n%{http_code}" <<EOF
{
  "action": "enable",
  "ids": [$ids_list]
}
EOF
  )

  code=$(printf "%s" "$enable_resp" | tail -n1)
  body=$(printf "%s" "$enable_resp" | sed '$d')

  if [ "$code" != "200" ]; then
    err=$(jq -r '.message? // .error? // "enable error"' <<<"$body" 2>/dev/null || echo "non-JSON error")
    echo "✖ FAILED ($code): $err"
  else
    success_count=$(jq '.attributes.results.updated_count' <<<"$body")
    echo "enabled $success_count rules"
  fi
  
  sleep 0.5  # Rate limiting
done

echo "✅ Successfully processed $count rules!"
