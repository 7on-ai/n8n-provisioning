#!/bin/sh

# ลูป retry login
for i in 1 2 3 4 5; do
  echo "Waiting for n8n..."
  sleep 15

  # Login และดึง token
  TOKEN=$(curl -s -X POST http://${N8N_HOST}:5678/rest/login \
    -H "Content-Type: application/json" \
    -d "$(printf '{"email":"%s","password":"%s"}' "$N8N_USER_EMAIL" "$N8N_USER_PASSWORD")" \
    | jq -r '.data.token')

  if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then
    echo "Got token: $TOKEN"

    # สร้าง API key
    curl -s -X POST http://${N8N_HOST}:5678/rest/api-key \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name":"default-key"}'

    exit 0
  fi
done

echo "Failed to get token"
exit 1
