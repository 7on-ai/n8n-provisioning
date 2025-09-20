#!/bin/bash

echo "Starting N8N API key generation using Internal REST API..."

# รอให้ N8N พร้อม
wait_for_n8n() {
    echo "Waiting for N8N to be ready..."
    
    local n8n_urls=(
        "https://${N8N_HOST}"
        "http://n8n:5678"
    )
    
    local working_url=""
    
    for url in "${n8n_urls[@]}"; do
        echo "Testing: $url/healthz"
        if curl -f -s --connect-timeout 10 --max-time 15 "$url/healthz" > /dev/null 2>&1; then
            working_url="$url"
            echo "Found working N8N URL: $working_url"
            export N8N_WORKING_URL="$working_url"
            return 0
        fi
    done
    
    echo "No working N8N URL found yet, trying extended wait..."
    for i in {1..8}; do
        echo "Extended health check attempt $i/8..."
        for url in "${n8n_urls[@]}"; do
            if curl -f -s --connect-timeout 10 --max-time 15 "$url/healthz" > /dev/null 2>&1; then
                working_url="$url"
                echo "N8N health check passed with URL: $working_url"
                export N8N_WORKING_URL="$working_url"
                return 0
            fi
        done
        echo "N8N not ready, waiting 30 seconds... (attempt $i/8)"
        sleep 30
    done
    
    echo "N8N failed to become ready after 8 attempts"
    return 1
}

# Setup owner account
setup_owner() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Setting up N8N owner account using URL: $n8n_url"
    
    local setup_url="${n8n_url}/rest/owner/setup"
    echo "Attempting owner setup at: $setup_url"
    
    local owner_response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-User}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Owner setup response: $owner_response"
    
    # Owner setup มักจะสำเร็จแม้ว่าจะมี error "already setup"
    if echo "$owner_response" | grep -qi "already.setup\|success\|created"; then
        echo "Owner account is ready!"
        return 0
    fi
    
    echo "Owner setup completed (may already exist)"
    return 0
}

# Login to N8N and get session cookies
login_to_n8n() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Logging into N8N at: $n8n_url"
    
    local login_url="${n8n_url}/rest/login"
    local login_payload='{
        "emailOrLdapLoginId": "'${N8N_USER_EMAIL}'",
        "password": "'${N8N_USER_PASSWORD}'"
    }'
    
    echo "Attempting N8N login..."
    local login_response=$(curl -s -c /tmp/n8n_cookies -X POST "$login_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "User-Agent: N8N-Provisioner/1.0" \
        -d "$login_payload" 2>&1)
    
    echo "Login response: ${login_response:0:200}...[TRUNCATED]"
    
    # ตรวจสอบว่า login สำเร็จ
    if echo "$login_response" | grep -qi '"data".*"id"'; then
        echo "Login successful - checking cookies..."
        
        if [ -f /tmp/n8n_cookies ] && [ -s /tmp/n8n_cookies ]; then
            echo "Session cookies saved successfully"
            echo "Cookie file contents:"
            cat /tmp/n8n_cookies | head -5
            return 0
        else
            echo "Login successful but no cookies saved"
            return 1
        fi
    else
        echo "Login failed or unexpected response"
        return 1
    fi
}

# สร้าง API key ใช้ N8N Internal REST API
create_api_key_internal() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Creating API key using N8N Internal REST API..."
    
    if [ ! -f /tmp/n8n_cookies ]; then
        echo "No session cookies found"
        return 1
    fi
    
    # ตรวจสอบ API keys endpoint ที่มีอยู่
    echo "Testing API keys endpoint..."
    local test_response=$(curl -s -b /tmp/n8n_cookies -X GET "${n8n_url}/rest/api-keys" \
        -H "Accept: application/json" 2>&1)
    
    echo "Existing API keys response: ${test_response:0:200}...[TRUNCATED]"
    
    # สร้าง API key ใหม่ - ลองหลาย payload format
    echo "Attempting to create new API key..."
    
    # Method 1: Basic format
    local api_payload_1='{
        "label": "auto-generated-'$(date +%s)'"
    }'
    
    echo "Trying Method 1: Basic label only"
    local api_response=$(curl -s -b /tmp/n8n_cookies -X POST "${n8n_url}/rest/api-keys" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$api_payload_1" 2>&1)
    
    echo "Method 1 response: $api_response"
    
    # ตรวจสอบผลลัพธ์
    local api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
    
    if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
        echo "SUCCESS: API key created with Method 1"
        echo "API Key: $api_key"
        echo "$api_key" > /work/n8n-api-key.txt
        return 0
    fi
    
    # Method 2: With scopes (ตาม error ที่เจอ)
    local api_payload_2='{
        "label": "auto-generated-'$(date +%s)'",
        "scopes": ["*"]
    }'
    
    echo "Trying Method 2: With scopes"
    api_response=$(curl -s -b /tmp/n8n_cookies -X POST "${n8n_url}/rest/api-keys" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$api_payload_2" 2>&1)
    
    echo "Method 2 response: $api_response"
    
    api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
    
    if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
        echo "SUCCESS: API key created with Method 2"
        echo "API Key: $api_key"
        echo "$api_key" > /work/n8n-api-key.txt
        return 0
    fi
    
    # Method 3: Full format with common scopes
    local api_payload_3='{
        "label": "auto-generated-'$(date +%s)'",
        "scopes": ["workflow:read", "workflow:write", "credential:read", "credential:write"]
    }'
    
    echo "Trying Method 3: With specific scopes"
    api_response=$(curl -s -b /tmp/n8n_cookies -X POST "${n8n_url}/rest/api-keys" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$api_payload_3" 2>&1)
    
    echo "Method 3 response: $api_response"
    
    api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
    
    if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
        echo "SUCCESS: API key created with Method 3"
        echo "API Key: $api_key"
        echo "$api_key" > /work/n8n-api-key.txt
        return 0
    fi
    
    echo "All API key creation methods failed"
    echo "Last response: $api_response"
    return 1
}

# Debug function
debug_info() {
    echo "=== Debug Information ==="
    echo "N8N_HOST: ${N8N_HOST:-NOT SET}"
    echo "N8N_USER_EMAIL: ${N8N_USER_EMAIL:-NOT SET}"
    echo "N8N_WORKING_URL: ${N8N_WORKING_URL:-NOT SET}"
    
    echo "=== Environment Variables ==="
    env | grep -E '^N8N_|^NORTHFLANK_' | sort
}

# Main execution function
main() {
    echo "=== N8N API Key Generation Started (Internal REST API Method) ==="
    
    # Debug info
    debug_info
    
    # Step 1: Wait for N8N
    echo "Step 1: Waiting for N8N to be ready..."
    if ! wait_for_n8n; then
        echo "ERROR: N8N failed to become ready"
        exit 1
    fi
    
    # Step 2: Setup owner
    echo "Step 2: Setting up owner account..."
    if ! setup_owner; then
        echo "WARNING: Owner setup may have failed, continuing..."
    fi
    
    # Step 3: Wait a bit
    echo "Step 3: Waiting 30 seconds after owner setup..."
    sleep 30
    
    # Step 4: Login to N8N
    echo "Step 4: Logging into N8N..."
    if ! login_to_n8n; then
        echo "ERROR: Failed to login to N8N"
        exit 1
    fi
    
    # Step 5: Wait after login
    echo "Step 5: Waiting 10 seconds after login..."
    sleep 10
    
    # Step 6: Create API key
    echo "Step 6: Creating API key using Internal REST API..."
    if create_api_key_internal; then
        echo "SUCCESS: N8N API key created successfully!"
        
        if [ -f /work/n8n-api-key.txt ]; then
            echo "API key saved to: /work/n8n-api-key.txt"
            echo "API key: $(cat /work/n8n-api-key.txt)"
        fi
        
        exit 0
    else
        echo "ERROR: Failed to create N8N API key using Internal REST API"
        exit 1
    fi
}

# Run main function
main
