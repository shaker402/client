curl -X POST "https://127.0.0.1/kibana/api/saved_objects/index-pattern/3b4fa8a0-e7aa-42ec-afa8-8e91bac6cc70?overwrite=true" \
  -k \
  -u elastic:changeme \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "attributes": {
      "title": "zsham_*",
      "timeFieldName": "@timestamp"
    }
  }'
