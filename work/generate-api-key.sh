#!/bin/bash

echo "Creating N8N API Key using Browser Automation (Simple Fix)..."

# ตรวจสอบ environment variables ที่จำเป็น
check_env_vars() {
    local required_vars=("N8N_USER_EMAIL" "N8N_USER_PASSWORD")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "ERROR: Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}

# Browser automation script (เหมือนเดิม - ไม่เปลี่ยน)
create_automation_script() {
    cat > /work/create-api-key.js << 'EOF'
const puppeteer = require('puppeteer');
const fs = require('fs');

async function createApiKey() {
    const N8N_URL = process.env.N8N_WORKING_URL;
    const EMAIL = process.env.N8N_USER_EMAIL;
    const PASSWORD = process.env.N8N_USER_PASSWORD;
    
    if (!N8N_URL || !EMAIL || !PASSWORD) {
        console.error('Missing required environment variables');
        process.exit(1);
    }
    
    console.log('Launching browser...');
    console.log('N8N URL:', N8N_URL);
    console.log('Email:', EMAIL);
    
    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/chromium-browser',
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-web-security',
            '--disable-features=VizDisplayCompositor'
        ]
    });
    
    try {
        const page = await browser.newPage();
        
        await page.setViewport({ width: 1280, height: 800 });
        await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        
        console.log('Navigating to N8N login...');
        await page.goto(`${N8N_URL}/signin`, { 
            waitUntil: 'networkidle0', 
            timeout: 60000 
        });
        
        await page.waitForTimeout(3000);
        await page.screenshot({ path: '/work/login-page.png' });
        
        console.log('Looking for login form...');
        
        // Find email input
        let emailInput = null;
        const emailSelectors = [
            'input[type="email"]',
            'input[name="email"]',
            'input[data-test-id="email"]',
            'input[placeholder*="email" i]',
            '.el-input__inner[type="email"]'
        ];
        
        for (const selector of emailSelectors) {
            try {
                emailInput = await page.$(selector);
                if (emailInput) {
                    console.log(`Found email input with: ${selector}`);
                    break;
                }
            } catch (e) {}
        }
        
        // Find password input
        let passwordInput = null;
        const passwordSelectors = [
            'input[type="password"]',
            'input[name="password"]',
            'input[data-test-id="password"]',
            '.el-input__inner[type="password"]'
        ];
        
        for (const selector of passwordSelectors) {
            try {
                passwordInput = await page.$(selector);
                if (passwordInput) {
                    console.log(`Found password input with: ${selector}`);
                    break;
                }
            } catch (e) {}
        }
        
        if (!emailInput || !passwordInput) {
            await page.screenshot({ path: '/work/error-no-inputs.png' });
            throw new Error('Login form not found');
        }
        
        // Fill and submit
        console.log('Filling login form...');
        await emailInput.click();
        await emailInput.type(EMAIL, { delay: 100 });
        
        await passwordInput.click();
        await passwordInput.type(PASSWORD, { delay: 100 });
        
        console.log('Submitting login form...');
        await passwordInput.press('Enter');
        
        await page.waitForNavigation({ 
            waitUntil: 'networkidle0', 
            timeout: 30000 
        });
        
        console.log('Login successful! Navigating to API settings...');
        await page.goto(`${N8N_URL}/settings/api`, { 
            waitUntil: 'networkidle0', 
            timeout: 30000 
        });
        
        await page.waitForTimeout(3000);
        await page.screenshot({ path: '/work/api-settings-page.png' });
        
        console.log('Looking for create API key button...');
        const createButtonSelectors = [
            'button:contains("Create API key")',
            'button:contains("Create API Key")',
            'button:contains("Create")',
            '.el-button--primary',
            'button.el-button--primary'
        ];
        
        let createButton = null;
        for (const selector of createButtonSelectors) {
            try {
                await page.waitForSelector(selector, { timeout: 5000 });
                createButton = await page.$(selector);
                if (createButton) {
                    console.log(`Found create button with: ${selector}`);
                    break;
                }
            } catch (e) {}
        }
        
        if (!createButton) {
            throw new Error('Could not find create API key button');
        }
        
        console.log('Creating API key...');
        await createButton.click();
        await page.waitForTimeout(5000);
        await page.screenshot({ path: '/work/after-create-click.png' });
        
        // Look for API key
        let apiKey = null;
        const keySelectors = [
            '[data-test*="api-key"]',
            '.api-key',
            'code',
            'pre',
            'input[readonly]',
            '.el-input__inner[readonly]',
            'textarea[readonly]'
        ];
        
        for (const selector of keySelectors) {
            try {
                const elements = await page.$$(selector);
                for (const element of elements) {
                    const text = await element.evaluate(el => 
                        el.textContent || el.value || el.getAttribute('value') || ''
                    );
                    
                    if (text && text.length > 20 && text.match(/^[a-zA-Z0-9_-]+$/)) {
                        apiKey = text.trim();
                        console.log(`Found API key with selector: ${selector}`);
                        break;
                    }
                }
                if (apiKey) break;
            } catch (e) {}
        }
        
        if (!apiKey) {
            const pageContent = await page.content();
            const keyPattern = /[a-zA-Z0-9_-]{32,}/g;
            const matches = pageContent.match(keyPattern);
            
            if (matches && matches.length > 0) {
                apiKey = matches.reduce((longest, current) => 
                    current.length > longest.length ? current : longest
                );
                console.log('Found potential API key from page scan');
            }
        }
        
        if (!apiKey) {
            await page.screenshot({ path: '/work/final-error-screenshot.png' });
            throw new Error('Could not extract API key from page');
        }
        
        console.log('API Key created successfully!');
        console.log('API Key (first 10 chars):', apiKey.substring(0, 10) + '...');
        
        fs.writeFileSync('/work/n8n-api-key.txt', apiKey);
        console.log('SUCCESS: API key saved to /work/n8n-api-key.txt');
        
        return apiKey;
        
    } catch (error) {
        console.error('Browser automation error:', error);
        
        try {
            await page.screenshot({ path: '/work/final-error.png' });
        } catch (e) {}
        
        throw error;
    } finally {
        await browser.close();
    }
}

createApiKey()
    .then(() => {
        console.log('API key generation completed successfully');
        process.exit(0);
    })
    .catch(error => {
        console.error('API key generation failed:', error.message);
        process.exit(1);
    });
EOF
}

# แก้ไข Health Check - เอาออกการตรวจสอบ signin page
wait_for_n8n_simple() {
    echo "Simple N8N readiness check..."
    
    # ใช้ N8N_HOST จาก environment variable ที่ส่งมาจาก template
    local n8n_urls=()
    
    if [ -n "$N8N_HOST" ]; then
        n8n_urls+=("https://$N8N_HOST")
        n8n_urls+=("http://$N8N_HOST")
    fi
    
    # เพิ่ม default URLs
    n8n_urls+=("http://n8n:5678")
    
    local max_attempts=10  # ลดเหลือ 10 attempts เพราะ N8N พร้อมแล้ว
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Health check attempt $attempt/$max_attempts"
        
        for url in "${n8n_urls[@]}"; do
            echo "Testing: $url/healthz"
            
            # ตรวจสอบแค่ health endpoint อย่างเดียว เพราะนี่คือสิ่งที่เชื่อถือได้
            if curl -f -s --connect-timeout 10 --max-time 15 "$url/healthz" > /dev/null 2>&1; then
                export N8N_WORKING_URL="$url"
                echo "✅ Found working N8N URL: $url"
                return 0
            fi
        done
        
        sleep 5  # ลดเวลารอเหลือ 5 วินาที
        ((attempt++))
    done
    
    echo "❌ N8N health check failed after $max_attempts attempts"
    return 1
}

# Setup owner - ปรับให้เรียบง่าย
setup_owner() {
    if [ -z "$N8N_WORKING_URL" ]; then
        echo "ERROR: N8N_WORKING_URL not set"
        return 1
    fi
    
    echo "Setting up N8N owner account..."
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    
    local owner_response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-Admin}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Owner setup response: $owner_response"
    return 0  # ไม่ fail ถ้า owner มีอยู่แล้ว
}

# Main execution - เรียบง่าย
main() {
    echo "=== N8N API Key Generation (Simple Fix) ==="
    
    echo "Step 1: Checking environment variables..."
    check_env_vars
    
    echo "Step 2: Quick health check..."
    if ! wait_for_n8n_simple; then
        echo "ERROR: N8N health check failed"
        echo "Available environment:"
        echo "N8N_HOST: $N8N_HOST"
        exit 1
    fi
    
    echo "Step 3: Setting up owner account..."
    setup_owner
    
    echo "Step 4: Creating automation script..."
    create_automation_script
    
    echo "Step 5: Running browser automation (no extra waiting)..."
    cd /work
    export NODE_PATH="/work/node_modules:$NODE_PATH"
    
    node create-api-key.js
    
    if [ -f /work/n8n-api-key.txt ]; then
        echo "🎉 SUCCESS: API key created"
        echo "Key length: $(wc -c < /work/n8n-api-key.txt) characters"
        echo "First 10 chars: $(head -c 10 /work/n8n-api-key.txt)..."
        exit 0
    else
        echo "❌ ERROR: No API key file created"
        ls -la /work/
        ls -la /work/*.png 2>/dev/null || echo "No screenshots"
        exit 1
    fi
}

main "$@"
