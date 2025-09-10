curl -u elastic:changeme -X PUT -k "https://127.0.0.1/elasticsearch/_ingest/pipeline/velociraptor_add_at_timestamp" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "Rename '\''timestamp'\'' and cast Keywords to string if too large",
    "processors": [
      {
        "rename": {
          "field": "timestamp",
          "target_field": "@timestamp",
          "ignore_missing": true
        }
      },
      {
        "script": {
          "description": "Convert _Event.System.Keywords to string to avoid long overflow",
          "lang": "painless",
          "source": "if (ctx.containsKey(\"_Event\") && ctx._Event.containsKey(\"System\") && ctx._Event.System.containsKey(\"Keywords\")) { ctx._Event.System.Keywords = ctx._Event.System.Keywords.toString(); }"
        }
      }
    ]
  }'
