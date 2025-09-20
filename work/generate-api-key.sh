#!/bin/bash

echo "Starting N8N API key generation with 8man..."

# รอให้ N8N พร้อม - ปรับปรุงการตรวจสอบ URL
wait_for_n8n() {
    echo "Waiting for N8N to be ready..."
    
    # ลองหา N8N URL ที่ถูกต้อง - Northflank ใช้ HTTPS
    local n8n_urls=(
        "https://${N8N_HOST}"           # Northflank public URL (ใช้แบบนี้)
        "http://n8n:5678"               # Internal service name
        "http://${N8N_HOST}:5678"       # Backup - HTTP with port
    )
    
    local working_url=""
    
    # ตรวจสอบ URL ไหนทำงานได้
    echo "Testing N8N URLs..."
    for url in "${n8n_urls[@]}"; do
        echo "Testing: $url/healthz"
        if curl -f -s --connect-timeout 5 --max-time 10 "$url/healthz" > /dev/null 2>&1; then
            working_url="$url"
            echo "Found working N8N URL: $working_url"
            export N8N_WORKING_URL="$working_url"
            return 0
        fi
    done
    
    # ถ้าไม่เจอ URL ที่ทำงาน รอแป็นช่วงสั้นๆ
    for i in {1..10}; do
        echo "Extended health check attempt $i/10..."
        
        for url in "${n8n_urls[@]}"; do
            if curl -f -s --connect-timeout 10 --max-time 15 "$url/healthz" > /dev/null 2>&1; then
                working_url="$url"
                echo "N8N health check passed with URL: $working_url"
                export N8N_WORKING_URL="$working_url"
                return 0
            fi
        done
        
        echo "N8N not ready, waiting 30 seconds... (attempt $i/10)"
        sleep 30
    done
    
    echo "N8N failed to become ready after 10 attempts"
    return 1
}

# สร้าง 8man config file - ใช้ URL ที่ work และเพิ่ม owner config
create_8man_config() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    
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

# สร้าง owner account ด้วย 8man
setup_owner() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Setting up N8N owner account with 8man using URL: $n8n_url"
    
    # ลอง owner creation ด้วย 8man
    echo "Attempting owner creation with 8man..."
    local owner_output=$(8man --config /work/8man-config.json owner create 2>&1)
    echo "8man owner creation output: $owner_output"
    
    # ตรวจสอบว่าสำเร็จหรือไม่
    if echo "$owner_output" | grep -qi "success\|created\|ok" || [ $? -eq 0 ]; then
        echo "Owner account created successfully with 8man!"
        return 0
    else
        echo "8man owner creation failed or unclear, trying direct REST API..."
        
        # Fallback เป็น direct REST API
        local setup_url="${n8n_url}/rest/owner/setup"
        echo "Trying direct owner setup at: $setup_url"
        
        local owner_response=$(curl -s -X POST "$setup_url" \
            -H "Content-Type: application/json" \
            -d "{
                \"email\": \"${N8N_USER_EMAIL}\",
                \"firstName\": \"${N8N_FIRST_NAME:-User}\",
                \"lastName\": \"${N8N_LAST_NAME:-User}\",
                \"password\": \"${N8N_USER_PASSWORD}\"
            }" 2>&1)
        
        echo "Direct owner setup response: $owner_response"
        return 0  # Continue anyway - owner might already exist
    fi
}

# สร้าง API key ด้วย 8man - แก้ไขตามโค้ดเดิมที่ทำงาน
create_api_key() {
    echo "Creating N8N API key with 8man..."
    
    # สร้าง API key ด้วย 8man (ไม่ใช้ --label ที่ไม่มี)
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
        api_key=$(echo "$api_output" | grep -i "api.key\|key" | grep -oE '[a-zA-Z0-9_]{35,}' | head -1)
    fi
    
    if [ -z "$api_key" ]; then
        # Method 3: หาใน JSON response
        api_key=$(echo "$api_output" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
    fi
    
    if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
        echo "API key created successfully: ${api_key:0:10}...[HIDDEN]"
        echo "Full API key: $api_key"
        
        # บันทึก API key ลงไฟล์
        echo "$api_key" > /work/n8n-api-key.txt
        
        return 0
    else
        echo "Failed to extract API key from 8man output"
        echo "Trying manual API key creation via N8N REST API..."
        
        # Fallback: ลองสร้าง API key ผ่าน N8N REST API โดยตรง
        create_api_key_direct
        return $?
    fi
}

# สร้าง API key โดยตรงผ่าน N8N REST API (fallback)
create_api_key_direct() {
    local n8n_url="${N8N_WORKING_URL:-https://${N8N_HOST}}"
    echo "Attempting direct API key creation via N8N REST API..."
    
    # Login เพื่อเอา auth token - แก้ไข request body
    local login_response=$(curl -s -X POST "${n8n_url}/rest/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Login response: $login_response"
    
    # ดึง token จาก response
    local token=$(echo "$login_response" | jq -r '.token // .data.token // .access_token // empty' 2>/dev/null)
    
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "Login successful, attempting API key creation..."
        
        # ลอง API key endpoints หลายตัว
        local api_endpoints=(
            "${n8n_url}/rest/api-keys"
            "${n8n_url}/api/v1/api-keys"
            "${n8n_url}/rest/settings/api-keys"
        )
        
        for endpoint in "${api_endpoints[@]}"; do
            echo "Trying API key endpoint: $endpoint"
            local api_response=$(curl -s -X POST "$endpoint" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"label\": \"auto-generated-$(date +%s)\"
                }" 2>&1)
            
            echo "API key creation response: $api_response"
            
            # ดึง API key
            local api_key=$(echo "$api_response" | jq -r '.apiKey // .data.apiKey // .key // empty' 2>/dev/null)
            
            if [ -n "$api_key" ] && [ "$api_key" != "null" ]; then
                echo "API key created successfully via direct method: ${api_key:0:10}...[HIDDEN]"
                echo "Full API key: $api_key"
                echo "$api_key" > /work/n8n-api-key.txt
                return 0
            fi
        done
    fi
    
    echo "Direct API key creation also failed"
    return 1
}

# Debug function - แสดงข้อมูลสำคัญ
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
        echo "ERROR: N8N failed to become ready after extended wait"
        exit 1
    fi
    
    # Step 2: สร้าง 8man config
    echo "Step 2: Creating 8man configuration..."
    create_8man_config
    
    # Step 3: รอเพิ่มเติมเพื่อให้ N8N initialize เสร็จสิ้น
    echo "Step 3: Waiting additional 60 seconds for full N8N initialization..."
    sleep 60
    
    # Step 4: Setup owner account
    echo "Step 4: Setting up owner account..."
    if ! setup_owner; then
        echo "WARNING: Owner setup may have failed, but continuing..."
    fi
    
    # Step 5: รออีกนิดเพื่อให้ owner setup เสร็จสิ้น
    echo "Step 5: Waiting 30 seconds after owner setup..."
    sleep 30
    
    # Step 6: สร้าง API key
    echo "Step 6: Creating API key..."
    if create_api_key; then
        echo "SUCCESS: N8N API key creation completed successfully!"
        
        # แสดงไฟล์ที่สร้าง
        if [ -f /work/n8n-api-key.txt ]; then
            echo "API key saved to: /work/n8n-api-key.txt"
            echo "API key content: $(cat /work/n8n-api-key.txt | head -c 10)...[HIDDEN]"
        fi
        
        exit 0
    else
        echo "ERROR: Failed to create N8N API key"
        exit 1
    fi
}

# เรียกใช้ main function
main
