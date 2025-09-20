#!/bin/sh
for i in 1 2 3 4 5; do
  echo "Waiting for n8n..."
  sleep 15
  TOKEN=$(curl -s -X POST http://$N8N_HOST:5678/rest/login \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$N8N_USER_EMAIL\",\"password\":\"$N8N_USER_PASSWORD\"}" \
    | jq -r .data.token)
  if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
    echo "Got token: $TOKEN"
    curl -s -X POST http://$N8N_HOST:5678/rest/api-key \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name":"default-key"}'
    exit 0
  fi
done
exit 1
