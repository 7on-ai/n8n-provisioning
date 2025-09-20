#!/bin/bash

echo "Starting N8N API key generation with 8man..."

# สร้าง 8man config file
create_8man_config() {
    cat > /work/8man-config.json << EOF
{
  "n8nApiUrl": "http://${N8N_HOST}:5678",
  "restCliClient": {
    "webhookUrl": "http://${N8N_HOST}:5678/webhook-test/import-workflow",
    "user": "${N8N_USER_EMAIL}",
    "password": "${N8N_USER_PASSWORD}"
  }
}
EOF
    echo "8man config created successfully"
}

# รอให้ N8N พร้อม
wait_for_n8n() {
    echo "Waiting for N8N to be ready..."
    for i in 1 2 3 4 5 6 7 8 9 10; do
        echo "Health check attempt $i/10..."
        
        if curl -f -s --connect-timeout 10 "http://${N8N_HOST}:5678/healthz" > /dev/null 2>&1; then
            echo "N8N health check passed!"
            return 0
        fi
        
        echo "N8N not ready, waiting 30 seconds..."
        sleep 30
    done
    
    echo "N8N failed to become ready after 10 attempts"
    return 1
}

# สร้าง owner account ด้วย 8man
setup_owner() {
    echo "Setting up N8N owner account with 8man..."
    
    # ลอง owner creation ด้วย 8man
    if 8man --config /work/8man-config.json owner create; then
        echo "Owner account created successfully with 8man!"
        return 0
    else
        echo "8man owner creation failed, trying direct REST API..."
        
        # Fallback เป็น direct REST API
        local owner_response=$(curl -s -X POST "http://${N8N_HOST}:5678/rest/owner/setup" \
            -H "Content-Type: application/json" \
            -d "{
                \"email\": \"${N8N_USER_EMAIL}\",
                \"firstName\": \"${N8N_FIRST_NAME:-User}\",
                \"lastName\": \"${N8N_LAST_NAME:-User}\",
                \"password\": \"${N8N_USER_PASSWORD}\"
            }")
        
        echo "Direct owner setup response: $owner_response"
        return 0
    fi
}

# สร้าง API key ด้วย 8man
create_api_key() {
    echo "Creating N8N API key with 8man..."
    
    local api_label="provisioned-key-$(date +%s)"
    
    # สร้าง API key ด้วย 8man
    local api_output=$(8man --config /work/8man-config.json apiKey create --label "$api_label" 2>&1)
    echo "8man API key creation output: $api_output"
    
    # ดึง API key จาก output
    local api_key=$(echo "$api_output" | grep -oE 'n8n_[a-zA-Z0-9]{32,}' | head -1)
    
    if [ -n "$api_key" ]; then
        echo "API key created successfully: ${api_key:0:10}...[HIDDEN]"
        echo "Full API key: $api_key"
        return 0
    else
        echo "Failed to extract API key from 8man output"
        echo "Trying alternative extraction methods..."
        
        # ลองหาใน output รูปแบบอื่น
        api_key=$(echo "$api_output" | grep -i "api.key\|key" | grep -oE '[a-zA-Z0-9_]{35,}' | head -1)
        
        if [ -n "$api_key" ]; then
            echo "API key found with alternative method: ${api_key:0:10}...[HIDDEN]"
            echo "Full API key: $api_key"
            return 0
        else
            echo "Could not find API key in output"
            return 1
        fi
    fi
}

# Main execution function
main() {
    echo "=== N8N API Key Generation with 8man Started ==="
    
    # Step 1: รอให้ N8N พร้อม
    if ! wait_for_n8n; then
        echo "ERROR: N8N failed to become ready"
        exit 1
    fi
    
    # Step 2: สร้าง 8man config
    echo "Creating 8man configuration..."
    create_8man_config
    
    # Step 3: รอเพิ่มเติมเพื่อให้ N8N initialize เสร็จสิ้น
    echo "Waiting additional 60 seconds for full N8N initialization..."
    sleep 60
    
    # Step 4: Setup owner account
    if ! setup_owner; then
        echo "WARNING: Owner setup may have failed, but continuing..."
    fi
    
    # Step 5: สร้าง API key
    if create_api_key; then
        echo "SUCCESS: N8N API key creation completed successfully!"
        exit 0
    else
        echo "ERROR: Failed to create N8N API key"
        exit 1
    fi
}

# เรียกใช้ main function
main
