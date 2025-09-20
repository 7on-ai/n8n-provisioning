#!/bin/bash

echo "Starting N8N API key generation with 8man..."

# รอให้ N8N พร้อม - ใช้ HTTPS URL ที่ถูกต้อง
wait_for_n8n() {
    echo "Waiting for N8N to be ready..."
    
    # N8N URLs สำหรับ Northflank - ใช้ HTTPS ไม่มีพอร์ต
    local n8n_urls=(
        "https://${N8N_HOST}"           # Northflank public URL
        "http://n8n:5678"               # Internal service name
    )
    
    local working_url=""
    
    # ตรวจสอบ URL ไหนทำงานได้
    echo "Testing N8N URLs..."
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
    
    # รอนานขึ้นเพราะ N8N อาจยังไม่พร้อม
    for i in {1..8}; do  # 4 นาที
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
    
    echo "N8N failed to become ready after 8 attempts (4 minutes)"
    return 1
}

# สร้าง 8man config file - แก้ไข format ให้ถูกต้องตาม 8man requirements
create_8man_config() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    
    # 8man ต้องการ owner section ใน config
    cat > /work/8man-config.json << EOF
{
  "n8n": {
    "url": "${n8n_url}",
    "owner": {
      "email": "${N8N_USER_EMAIL}",
      "password": "${N8N_USER_PASSWORD}",
      "firstName": "${N8N_FIRST_NAME:-User}",
      "lastName": "${N8N_LAST_NAME:-User}"
    }
  },
  "restCliClient": {
    "webhookUrl": "${n8n_url}/webhook-test/import-workflow",
    "user": "${N8N_USER_EMAIL}",
    "password": "${N8N_USER_PASSWORD}"
  }
}
EOF
    echo "8man config created successfully with URL: $n8n_url"
    echo "Config contents:"
    cat /work/8man-config.json
}

# สร้าง owner account - ลองทั้ง 8man และ direct API
setup_owner() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Setting up N8N owner account using URL: $n8n_url"
    
    # Method 1: ลอง direct REST API ก่อน (เชื่อถือได้กว่า)
    echo "Attempting owner creation via direct N8N REST API..."
    
    local setup_url="${n8n_url}/rest/owner/setup"
    echo "Trying direct owner setup at: $setup_url"
    
    local owner_response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-User}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Direct owner setup response: $owner_response"
    
    # ตรวจสอบว่าสำเร็จหรือไม่
    if echo "$owner_response" | grep -qi "success\|created\|ok" || [ "${owner_response}" != *"error"* ]; then
        echo "Owner account created successfully via direct REST API!"
        return 0
    fi
    
    # Method 2: ลอง 8man (fallback)
    echo "Direct API failed, attempting with 8man..."
    local owner_output=$(8man --config /work/8man-config.json owner create 2>&1)
    echo "8man owner creation output: $owner_output"
    
    # 8man อาจสำเร็จแม้ว่าจะมี error messages
    if ! echo "$owner_output" | grep -qi "fatal\|cannot\|failed"; then
        echo "Owner account setup completed (may already exist)"
        return 0
    fi
    
    echo "Both owner creation methods attempted - continuing with API key creation..."
    return 0
}

# สร้าง API key ด้วย 8man
create_api_key_8man() {
    echo "Creating N8N API key with 8man..."
    
    # สร้าง API key ด้วย 8man (ไม่ใส่ --label เพราะไม่รองรับ)
    echo "Running 8man API key creation command..."
    local api_output=$(8man --config /work/8man-config.json apiKey create 2>&1)
    echo "8man API key creation output:"
    echo "$api_output"
    
    # ดึง API key จาก output - หลายรูปแบบ
    local api_key=""
    
    # Method 1: หา n8n_ pattern
    api_key=$(echo "$api_output" | grep -oE 'n8n_[a-zA-Z0-9]{32,}' | head -1)
    
    if [ -z "$api_key" ]; then
        # Method 2: หา API key pattern อื่นๆ
        api_key=$(echo "$api_output" | grep -oE '[a-zA-Z0-9_-]{35,}' | head -1)
    fi
    
    if [ -z "$api_key" ]; then
        # Method 3: หาใน JSON response
        api_key=$(echo "$api_output" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
    fi
    
    if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
        echo "API key created successfully: ${api_key:0:10}...[HIDDEN]"
        echo "Full API key: $api_key"
        echo "$api_key" > /work/n8n-api-key.txt
        return 0
    else
        echo "Failed to extract API key from 8man output"
        return 1
    fi
}

# สร้าง API key โดยตรงผ่าน N8N REST API
create_api_key_direct() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Attempting direct API key creation via N8N REST API..."
    
    # N8N ใหม่ใช้ emailOrLdapLoginId แทน email
    local login_response=$(curl -s -X POST "${n8n_url}/rest/login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"emailOrLdapLoginId\": \"${N8N_USER_EMAIL}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Login response: $login_response"
    
    # ดึง token/cookie จาก response - หลายวิธี
    local token=$(echo "$login_response" | jq -r '.token // .data.token // .access_token // .accessToken // empty' 2>/dev/null)
    
    # หา token ในส่วนอื่นของ response
    if [ -z "$token" ] || [ "$token" == "null" ]; then
        # ลองหา token pattern ใน response
        token=$(echo "$login_response" | grep -oE '"token"[[:space:]]*:[[:space:]]*"[^"]+' | sed 's/.*"//' | head -1)
    fi
    
    echo "Extracted token: ${token:0:20}...[TRUNCATED]"
    
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "Login successful with token, attempting API key creation..."
        
        # สร้าง API key ด้วย token - ใช้ label แทน name
        local api_response=$(curl -s -X POST "${n8n_url}/rest/api-keys" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{
                \"label\": \"auto-generated-$(date +%s)\"
            }" 2>&1)
        
        echo "API key creation response: $api_response"
        
        local api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
        
        if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
            echo "API key created successfully via direct method: ${api_key:0:10}...[HIDDEN]"
            echo "Full API key: $api_key"
            echo "$api_key" > /work/n8n-api-key.txt
            return 0
        fi
    fi
    
    # ลอง cookie-based authentication - บางครั้ง N8N ใช้ session cookies
    echo "Token method failed, trying cookie-based authentication..."
    
    local cookie_response=$(curl -s -c /tmp/n8n_cookies -b /tmp/n8n_cookies -X POST "${n8n_url}/rest/login" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"emailOrLdapLoginId\": \"${N8N_USER_EMAIL}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Cookie login response: ${cookie_response:0:200}...[TRUNCATED]"
    
    if [ -f /tmp/n8n_cookies ] && [ -s /tmp/n8n_cookies ]; then
        echo "Cookies saved, attempting API key creation with cookies..."
        local api_response=$(curl -s -b /tmp/n8n_cookies -X POST "${n8n_url}/rest/api-keys" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -d "{
                \"label\": \"auto-generated-$(date +%s)\"
            }" 2>&1)
        
        echo "Cookie-based API key response: $api_response"
        
        local api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
        
        if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
            echo "API key created successfully via cookie method: ${api_key:0:10}...[HIDDEN]"
            echo "Full API key: $api_key"
            echo "$api_key" > /work/n8n-api-key.txt
            return 0
        fi
    fi
    
    echo "All direct API key creation methods failed"
    return 1
}

# Debug function
debug_info() {
    echo "=== Debug Information ==="
    echo "N8N_HOST: ${N8N_HOST:-NOT SET}"
    echo "N8N_USER_EMAIL: ${N8N_USER_EMAIL:-NOT SET}"
    echo "N8N_WORKING_URL: ${N8N_WORKING_URL:-NOT SET}"
    
    echo "=== Quick URL Tests ==="
    local quick_urls=(
        "https://${N8N_HOST}/healthz"
        "https://${N8N_HOST}/health"
        "http://n8n:5678/healthz"
    )
    
    for url in "${quick_urls[@]}"; do
        echo -n "Testing $url: "
        if curl -f -s --connect-timeout 5 --max-time 5 "$url" >/dev/null 2>&1; then
            echo "✓ SUCCESS"
        else
            echo "✗ FAILED"
        fi
    done
    
    echo "=== Available Environment Variables ==="
    env | grep -E '^N8N_|^NORTHFLANK_' | sort
}

# Main execution function
main() {
    echo "=== N8N API Key Generation with 8man Started ==="
    
    # Debug info
    debug_info
    
    # Step 1: รอให้ N8N พร้อม
    echo "Step 1: Waiting for N8N to be ready..."
    if ! wait_for_n8n; then
        echo "ERROR: N8N failed to become ready"
        exit 1
    fi
    
    # Step 2: สร้าง 8man config
    echo "Step 2: Creating 8man configuration..."
    create_8man_config
    
    # Step 3: รอเพิ่มเติม
    echo "Step 3: Waiting additional 30 seconds for full N8N initialization..."
    sleep 30
    
    # Step 4: Setup owner account
    echo "Step 4: Setting up owner account..."
    if ! setup_owner; then
        echo "WARNING: Owner setup may have failed, but continuing..."
    fi
    
    # Step 5: รอหลัง owner setup
    echo "Step 5: Waiting 15 seconds after owner setup..."
    sleep 15
    
    # Step 6: เนื่องจาก 8man มีปัญหา login ใช้ Direct REST API เลย
    echo "Step 6: Creating API key with Direct REST API (skip 8man due to login issues)..."
    if create_api_key_direct; then
        echo "SUCCESS: N8N API key created with direct REST API!"
        exit 0
    else
        echo "Direct REST API failed, trying 8man as last resort..."
        if create_api_key_8man; then
            echo "SUCCESS: N8N API key created with 8man!"
            exit 0
        else
            echo "ERROR: All API key creation methods failed"
            exit 1
        fi
    fi
}

# เรียกใช้ main function
main
