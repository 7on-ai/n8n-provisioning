#!/bin/bash

echo "Creating N8N API Key using Browser Automation (Simple Fixed Version)..."

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
        echo "[$(date -Iseconds)] ERROR: Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}

# สร้าง Node.js script ที่แก้ไขปัญหาหลักเท่านั้น
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
    
    console.log(`${new Date().toISOString()} === Browser Automation Start ===`);
    console.log(`${new Date().toISOString()} N8N URL: ${N8N_URL}`);
    console.log(`${new Date().toISOString()} Email: ${EMAIL}`);
    console.log(`${new Date().toISOString()} Password length: ${PASSWORD.length}`);
    
    let browser = null;
    let page = null;
    
    try {
        console.log(`${new Date().toISOString()} Launching browser...`);
        
        // ใช้ browser args ที่เรียบง่ายและทดสอบแล้ว
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/chromium',
            headless: 'new',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
                '--disable-web-security',
                '--disable-extensions',
                '--disable-plugins',
                '--disable-images',
                '--disable-css',
                '--no-zygote',
                '--single-process',
                '--memory-pressure-off',
                '--max_old_space_size=1024'
            ],
            timeout: 60000,
            protocolTimeout: 60000
        });
        
        console.log(`${new Date().toISOString()} Browser launched successfully`);
        
        page = await browser.newPage();
        console.log(`${new Date().toISOString()} New page created`);
        
        // ตั้งค่า page พื้นฐาน
        await page.setViewport({ width: 1280, height: 800 });
        await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36');
        
        // ปิดการโหลด resources ที่ไม่จำเป็น
        await page.setRequestInterception(true);
        page.on('request', (req) => {
            const resourceType = req.resourceType();
            if (['image', 'font', 'media'].includes(resourceType)) {
                req.abort();
            } else {
                req.continue();
            }
        });
        
        console.log(`${new Date().toISOString()} Navigating to signin page: ${N8N_URL}/signin`);
        
        // Navigate with simple settings
        await page.goto(`${N8N_URL}/signin`, { 
            waitUntil: 'domcontentloaded',
            timeout: 90000
        });
        
        console.log(`${new Date().toISOString()} Page loaded, waiting for form elements...`);
        
        // รอให้หน้าเสถียร
        await page.waitForTimeout(3000);
        
        // หา login form elements
        let emailInput = null;
        let passwordInput = null;
        
        try {
            console.log(`${new Date().toISOString()} Looking for email input...`);
            emailInput = await page.waitForSelector('input[type="email"], input[name="email"], input[id*="email"]', {
                timeout: 30000,
                visible: true
            });
            console.log(`${new Date().toISOString()} Email input found`);
            
            console.log(`${new Date().toISOString()} Looking for password input...`);
            passwordInput = await page.waitForSelector('input[type="password"], input[name="password"], input[id*="password"]', {
                timeout: 10000,
                visible: true
            });
            console.log(`${new Date().toISOString()} Password input found`);
            
        } catch (selectorError) {
            console.error(`${new Date().toISOString()} Login form not found: ${selectorError.message}`);
            throw new Error(`Login form not found`);
        }
        
        // Fill form
        console.log(`${new Date().toISOString()} Filling login form...`);
        
        await emailInput.click({ clickCount: 3 });
        await emailInput.type(EMAIL, { delay: 50 });
        
        await passwordInput.click({ clickCount: 3 });
        await passwordInput.type(PASSWORD, { delay: 50 });
        
        console.log(`${new Date().toISOString()} Form filled, submitting...`);
        
        // Submit form
        await passwordInput.press('Enter');
        
        // Wait for login - แก้ไขให้รองรับหลายกรณี
        try {
            await page.waitForNavigation({ 
                waitUntil: 'domcontentloaded',
                timeout: 30000 
            });
            console.log(`${new Date().toISOString()} Login navigation completed`);
        } catch (navError) {
            console.log(`${new Date().toISOString()} Navigation timeout, checking current URL...`);
            const currentUrl = await page.url();
            console.log(`${new Date().toISOString()} Current URL: ${currentUrl}`);
            
            if (currentUrl.includes('/signin') || currentUrl.includes('/login')) {
                throw new Error('Login failed - still on signin page');
            }
            console.log(`${new Date().toISOString()} Login appears successful (URL changed)`);
        }
        
        // Navigate to API settings
        console.log(`${new Date().toISOString()} Going to API settings...`);
        await page.goto(`${N8N_URL}/settings/api`, {
            waitUntil: 'domcontentloaded',
            timeout: 60000
        });
        
        await page.waitForTimeout(5000);
        console.log(`${new Date().toISOString()} API settings page loaded`);
        
        // Find create button - ใช้วิธีง่ายๆ
        console.log(`${new Date().toISOString()} Looking for create API key button...`);
        let createButton = null;
        
        // ลองหา button ตามลำดับ
        const buttonSelectors = [
            'button[data-test-id*="create"]',
            'button:has-text("Create API key")',
            'button:has-text("Create API Key")', 
            'button:has-text("Create")',
            '.el-button--primary',
            'button.btn-primary'
        ];
        
        for (const selector of buttonSelectors) {
            try {
                createButton = await page.waitForSelector(selector, { 
                    timeout: 5000,
                    visible: true 
                });
                if (createButton) {
                    console.log(`${new Date().toISOString()} Found button: ${selector}`);
                    break;
                }
            } catch (e) {
                console.log(`${new Date().toISOString()} Button ${selector} not found`);
            }
        }
        
        // Fallback: หา button ที่มี text "create"
        if (!createButton) {
            const buttons = await page.$$('button');
            console.log(`${new Date().toISOString()} Scanning ${buttons.length} buttons for create text...`);
            
            for (const button of buttons) {
                const text = await button.evaluate(el => el.textContent?.toLowerCase() || '');
                if (text.includes('create') || text.includes('api')) {
                    createButton = button;
                    console.log(`${new Date().toISOString()} Found button by text: ${text}`);
                    break;
                }
            }
        }
        
        if (!createButton) {
            throw new Error('Create API key button not found');
        }
        
        // Click create button
        console.log(`${new Date().toISOString()} Clicking create button...`);
        await createButton.click();
        console.log(`${new Date().toISOString()} Button clicked, waiting for API key...`);
        
        // รอให้ API key ปรากฏ
        await page.waitForTimeout(8000);
        
        // Extract API key
        console.log(`${new Date().toISOString()} Extracting API key...`);
        let apiKey = null;
        
        // ใช้วิธีหลักเดิมที่ใช้ได้
        const keySelectors = [
            'code',
            'pre',
            'input[readonly]',
            'textarea[readonly]',
            '[data-test*="api-key"]',
            '.api-key',
            '.el-input__inner[readonly]',
            'span[style*="font-family: monospace"]'
        ];
        
        for (const selector of keySelectors) {
            try {
                const elements = await page.$$(selector);
                console.log(`${new Date().toISOString()} Found ${elements.length} elements for ${selector}`);
                
                for (const element of elements) {
                    const text = await element.evaluate(el => 
                        el.textContent || el.value || el.getAttribute('value') || ''
                    );
                    
                    // ตรวจสอบว่าเป็น API key (มากกว่า 20 ตัวอักษร และเป็น alphanumeric)
                    if (text && text.length > 20 && /^[a-zA-Z0-9_.-]{20,}$/.test(text.trim())) {
                        apiKey = text.trim();
                        console.log(`${new Date().toISOString()} Found API key with ${selector} (length: ${apiKey.length})`);
                        break;
                    }
                }
                if (apiKey) break;
            } catch (e) {
                console.log(`${new Date().toISOString()} Selector ${selector} failed: ${e.message}`);
            }
        }
        
        // Fallback: scan page content
        if (!apiKey) {
            console.log(`${new Date().toISOString()} Scanning page content for API key pattern...`);
            const pageContent = await page.content();
            const matches = pageContent.match(/[a-zA-Z0-9_.-]{25,}/g);
            
            if (matches && matches.length > 0) {
                // หา match ที่ยาวที่สุด (API keys มักจะยาว)
                apiKey = matches.reduce((longest, current) => 
                    current.length > longest.length ? current : longest
                );
                console.log(`${new Date().toISOString()} Found API key from page scan (length: ${apiKey.length})`);
            }
        }
        
        if (!apiKey) {
            throw new Error('Could not extract API key from page');
        }
        
        console.log(`${new Date().toISOString()} SUCCESS: API Key extracted!`);
        console.log(`${new Date().toISOString()} Length: ${apiKey.length}`);
        console.log(`${new Date().toISOString()} Preview: ${apiKey.substring(0, 10)}...`);
        
        // Save key
        fs.writeFileSync('/work/n8n-api-key.txt', apiKey);
        console.log(`${new Date().toISOString()} API key saved to file`);
        
        return apiKey;
        
    } catch (error) {
        console.error(`${new Date().toISOString()} ERROR: ${error.message}`);
        throw error;
        
    } finally {
        // Cleanup - ทำให้เรียบง่าย
        console.log(`${new Date().toISOString()} Cleaning up...`);
        
        if (page) {
            try {
                await page.close();
                console.log(`${new Date().toISOString()} Page closed`);
            } catch (e) {
                console.log(`${new Date().toISOString()} Page close warning: ${e.message}`);
            }
        }
        
        if (browser) {
            try {
                await browser.close();
                console.log(`${new Date().toISOString()} Browser closed`);
            } catch (e) {
                console.log(`${new Date().toISOString()} Browser close warning: ${e.message}`);
            }
        }
    }
}

// Run - เรียบง่าย
createApiKey()
    .then((apiKey) => {
        console.log(`${new Date().toISOString()} FINAL SUCCESS: API key created (${apiKey.length} chars)`);
        process.exit(0);
    })
    .catch(error => {
        console.error(`${new Date().toISOString()} FINAL ERROR: ${error.message}`);
        process.exit(1);
    });
EOF

    echo "[$(date -Iseconds)] ✅ Simple automation script created: /work/create-api-key.js"
}

# Simple health check (เหมือนเดิม)
wait_for_n8n_simple() {
    echo "[$(date -Iseconds)] Quick N8N availability check..."
    
    local n8n_urls=()
    
    if [ -n "$N8N_HOST" ]; then
        n8n_urls+=("https://$N8N_HOST")
        n8n_urls+=("http://$N8N_HOST")
    fi
    
    n8n_urls+=("http://n8n:5678")
    
    echo "[$(date -Iseconds)] Testing URLs:" "${n8n_urls[@]}"
    
    for url in "${n8n_urls[@]}"; do
        echo "[$(date -Iseconds)] Testing: $url/healthz"
        
        if curl -f -s --connect-timeout 5 --max-time 10 "$url/healthz" > /dev/null 2>&1; then
            export N8N_WORKING_URL="$url"
            echo "[$(date -Iseconds)] ✅ N8N ready: $url"
            return 0
        fi
    done
    
    echo "[$(date -Iseconds)] ❌ N8N not accessible"
    return 1
}

# Simple owner setup (เหมือนเดิม)
setup_owner() {
    echo "[$(date -Iseconds)] Setting up owner account..."
    
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    
    local response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-Admin}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "[$(date -Iseconds)] Owner setup: $response"
    return 0
}

# Main execution - ย้อนกลับให้เรียบง่าย
main() {
    echo "[$(date -Iseconds)] === Simple N8N API Key Generation ==="
    
    # Check environment
    check_env_vars
    
    # Check chromium - แค่ตรวจสอบว่ามีไฟล์
    if [ ! -x "/usr/bin/chromium" ]; then
        echo "[$(date -Iseconds)] ❌ Chromium not found"
        exit 1
    fi
    echo "[$(date -Iseconds)] ✅ Chromium found"
    
    # Check puppeteer
    if ! node -e "require('puppeteer')" 2>/dev/null; then
        echo "[$(date -Iseconds)] ❌ Puppeteer not found"
        exit 1
    fi
    echo "[$(date -Iseconds)] ✅ Puppeteer available"
    
    # Quick N8N check
    if ! wait_for_n8n_simple; then
        echo "[$(date -Iseconds)] ❌ N8N not ready"
        exit 1
    fi
    
    # Owner setup
    setup_owner
    
    # Create script
    create_automation_script
    
    # Show basic info
    echo "[$(date -Iseconds)] Node version: $(node --version)"
    echo "[$(date -Iseconds)] PUPPETEER_EXECUTABLE_PATH: $PUPPETEER_EXECUTABLE_PATH"
    
    # Run automation - เรียบง่าย
    echo "[$(date -Iseconds)] 🕐 Starting automation: $(date -Iseconds)"
    
    cd /work
    
    # Run with simple timeout
    if timeout 300 node create-api-key.js; then  
        echo "[$(date -Iseconds)] ✅ Automation completed successfully"
    else
        local exit_code=$?
        echo "[$(date -Iseconds)] ❌ Automation failed: exit code $exit_code"
        exit 1
    fi
    
    # Validate result - เรียบง่าย
    if [ -f /work/n8n-api-key.txt ]; then
        local key_length=$(wc -c < /work/n8n-api-key.txt)
        local key_preview=$(head -c 10 /work/n8n-api-key.txt)
        
        echo "[$(date -Iseconds)] 🎉 SUCCESS!"
        echo "[$(date -Iseconds)] File: /work/n8n-api-key.txt"
        echo "[$(date -Iseconds)] Length: $key_length chars"
        echo "[$(date -Iseconds)] Preview: ${key_preview}..."
        
        if [ $key_length -gt 20 ]; then
            exit 0
        else
            echo "[$(date -Iseconds)] ⚠️ Key too short: $key_length chars"
            exit 1
        fi
    else
        echo "[$(date -Iseconds)] ❌ No API key file created"
        exit 1
    fi
}

# Execute
main "$@"
