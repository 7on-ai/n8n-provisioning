#!/bin/bash

echo "Creating N8N API Key using Browser Automation (Stable Fixed Version)..."

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

# สร้าง Node.js script ที่แก้ไขปัญหา frame detachment
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
    let retryCount = 0;
    const maxRetries = 2;
    
    while (retryCount <= maxRetries) {
        try {
            console.log(`${new Date().toISOString()} Attempt ${retryCount + 1}/${maxRetries + 1} - Launching browser...`);
            
            // แก้ไข browser args เพื่อป้องกัน frame detachment
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
                    '--no-zygote',
                    '--single-process',
                    '--memory-pressure-off',
                    '--max_old_space_size=512',
                    // เพิ่ม flags สำหรับความเสถียร
                    '--disable-background-timer-throttling',
                    '--disable-backgrounding-occluded-windows',
                    '--disable-renderer-backgrounding',
                    '--disable-features=TranslateUI,BlinkGenPropertyTrees',
                    '--disable-ipc-flooding-protection',
                    '--disable-component-extensions-with-background-pages'
                ],
                timeout: 30000,
                protocolTimeout: 30000,
                // เพิ่มการจัดการ error
                handleSIGINT: false,
                handleSIGTERM: false,
                handleSIGHUP: false
            });
            
            console.log(`${new Date().toISOString()} Browser launched successfully`);
            
            page = await browser.newPage();
            console.log(`${new Date().toISOString()} New page created`);
            
            // ตั้งค่า page สำหรับความเสถียร
            await page.setViewport({ width: 1280, height: 800 });
            await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36');
            
            // เพิ่ม error handlers
            page.on('error', (err) => {
                console.log(`${new Date().toISOString()} Page error: ${err.message}`);
            });
            
            page.on('pageerror', (err) => {
                console.log(`${new Date().toISOString()} Page script error: ${err.message}`);
            });
            
            // ปิดการโหลด resources ที่ไม่จำเป็น
            await page.setRequestInterception(true);
            page.on('request', (req) => {
                const resourceType = req.resourceType();
                if (['image', 'font', 'media', 'stylesheet'].includes(resourceType)) {
                    req.abort();
                } else {
                    req.continue();
                }
            });
            
            console.log(`${new Date().toISOString()} Navigating to signin page: ${N8N_URL}/signin`);
            
            // Navigate with retry mechanism
            await page.goto(`${N8N_URL}/signin`, { 
                waitUntil: 'networkidle0',
                timeout: 60000
            });
            
            console.log(`${new Date().toISOString()} Page loaded, waiting for form elements...`);
            
            // รอให้หน้าเสถียร
            await page.waitForTimeout(2000);
            
            // หา login form elements with better error handling
            let emailInput = null;
            let passwordInput = null;
            
            try {
                console.log(`${new Date().toISOString()} Looking for email input...`);
                emailInput = await page.waitForSelector('input[type="email"], input[name="email"], input[id*="email"]', {
                    timeout: 20000,
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
                throw new Error(`Login form not found on attempt ${retryCount + 1}`);
            }
            
            // Fill form with stability improvements
            console.log(`${new Date().toISOString()} Filling login form...`);
            
            await emailInput.click({ clickCount: 3 });
            await page.waitForTimeout(100);
            await emailInput.type(EMAIL, { delay: 25 });
            
            await passwordInput.click({ clickCount: 3 });
            await page.waitForTimeout(100);
            await passwordInput.type(PASSWORD, { delay: 25 });
            
            console.log(`${new Date().toISOString()} Form filled, submitting...`);
            
            // Submit form และรอผล
            await Promise.all([
                page.waitForNavigation({ 
                    waitUntil: 'networkidle0',
                    timeout: 20000 
                }),
                passwordInput.press('Enter')
            ]);
            
            console.log(`${new Date().toISOString()} Login navigation completed`);
            
            // ตรวจสอบว่า login สำเร็จ
            const currentUrl = await page.url();
            if (currentUrl.includes('/signin') || currentUrl.includes('/login')) {
                throw new Error('Login failed - still on signin page');
            }
            
            // Navigate to API settings
            console.log(`${new Date().toISOString()} Going to API settings...`);
            await page.goto(`${N8N_URL}/settings/api`, {
                waitUntil: 'networkidle0',
                timeout: 30000
            });
            
            await page.waitForTimeout(3000);
            console.log(`${new Date().toISOString()} API settings page loaded`);
            
            // Find create button with improved selector strategy
            console.log(`${new Date().toISOString()} Looking for create API key button...`);
            let createButton = null;
            
            // ลองหา button ตามลำดับที่ปรับปรุงแล้ว
            const buttonSelectors = [
                'button[data-test-id*="create"]',
                'button:has-text("Create API key")',
                'button:has-text("Create API Key")', 
                'button:has-text("Create")',
                'button.el-button--primary',
                'button.btn-primary',
                '.el-button[type="button"]'
            ];
            
            for (const selector of buttonSelectors) {
                try {
                    await page.waitForSelector(selector, { timeout: 3000 });
                    createButton = await page.$(selector);
                    if (createButton) {
                        const isVisible = await createButton.isIntersectingViewport();
                        if (isVisible) {
                            console.log(`${new Date().toISOString()} Found visible button: ${selector}`);
                            break;
                        }
                    }
                } catch (e) {
                    // Continue to next selector
                }
            }
            
            // Fallback: หา button ที่มี text "create"
            if (!createButton) {
                const buttons = await page.$$('button');
                console.log(`${new Date().toISOString()} Scanning ${buttons.length} buttons for create text...`);
                
                for (const button of buttons) {
                    const text = await button.evaluate(el => el.textContent?.toLowerCase() || '');
                    const isVisible = await button.isIntersectingViewport();
                    if ((text.includes('create') || text.includes('api')) && isVisible) {
                        createButton = button;
                        console.log(`${new Date().toISOString()} Found button by text: ${text}`);
                        break;
                    }
                }
            }
            
            if (!createButton) {
                throw new Error('Create API key button not found');
            }
            
            // Click create button with stability
            console.log(`${new Date().toISOString()} Clicking create button...`);
            await createButton.click();
            console.log(`${new Date().toISOString()} Button clicked, waiting for API key...`);
            
            // รอให้ API key ปรากฏ
            await page.waitForTimeout(5000);
            
            // Extract API key with improved method
            console.log(`${new Date().toISOString()} Extracting API key...`);
            let apiKey = null;
            
            const keySelectors = [
                'code',
                'pre', 
                'input[readonly]',
                'textarea[readonly]',
                '[data-test*="api-key"]',
                '.api-key',
                '.el-input__inner[readonly]',
                'span[style*="font-family: monospace"]',
                'div[class*="api-key"]'
            ];
            
            for (const selector of keySelectors) {
                try {
                    const elements = await page.$$(selector);
                    
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
                    // Continue to next selector
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
            console.error(`${new Date().toISOString()} Attempt ${retryCount + 1} failed: ${error.message}`);
            
            // Cleanup current attempt
            if (page) {
                try {
                    await page.close();
                } catch (e) {}
                page = null;
            }
            
            if (browser) {
                try {
                    await browser.close();
                } catch (e) {}
                browser = null;
            }
            
            retryCount++;
            
            if (retryCount <= maxRetries) {
                console.log(`${new Date().toISOString()} Waiting 5 seconds before retry...`);
                await new Promise(resolve => setTimeout(resolve, 5000));
            } else {
                throw new Error(`All ${maxRetries + 1} attempts failed. Last error: ${error.message}`);
            }
        }
    }
}

// Improved cleanup function
async function cleanup(browser, page) {
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

// Main execution with proper error handling
async function main() {
    try {
        const apiKey = await createApiKey();
        console.log(`${new Date().toISOString()} FINAL SUCCESS: API key created (${apiKey.length} chars)`);
        process.exit(0);
    } catch (error) {
        console.error(`${new Date().toISOString()} FINAL ERROR: ${error.message}`);
        process.exit(1);
    }
}

// Handle process termination gracefully
process.on('SIGTERM', () => {
    console.log('Received SIGTERM, exiting gracefully...');
    process.exit(1);
});

process.on('SIGINT', () => {
    console.log('Received SIGINT, exiting gracefully...');
    process.exit(1);
});

// Run
main();
EOF

    echo "[$(date -Iseconds)] ✅ Stable automation script created: /work/create-api-key.js"
}

# รุ่นที่ปรับปรุงแล้วของ wait_for_n8n_simple
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
        
        if curl -f -s --connect-timeout 3 --max-time 8 "$url/healthz" > /dev/null 2>&1; then
            export N8N_WORKING_URL="$url"
            echo "[$(date -Iseconds)] ✅ N8N ready: $url"
            return 0
        fi
    done
    
    echo "[$(date -Iseconds)] ❌ N8N not accessible"
    return 1
}

# รุ่นปรับปรุงของ setup_owner
setup_owner() {
    echo "[$(date -Iseconds)] Setting up owner account..."
    
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    
    local response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --connect-timeout 10 \
        --max-time 15 \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-Admin}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "[$(date -Iseconds)] Owner setup: $response"
    return 0
}

# Main execution - รุ่นปรับปรุง
main() {
    echo "[$(date -Iseconds)] === Stable N8N API Key Generation ==="
    
    # Check environment
    check_env_vars
    
    # Check chromium
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
    
    # N8N health check
    if ! wait_for_n8n_simple; then
        echo "[$(date -Iseconds)] ❌ N8N not ready"
        exit 1
    fi
    
    # Owner setup
    setup_owner
    
    # Create stable script
    create_automation_script
    
    # Show environment info
    echo "[$(date -Iseconds)] Node version: $(node --version)"
    echo "[$(date -Iseconds)] PUPPETEER_EXECUTABLE_PATH: $PUPPETEER_EXECUTABLE_PATH"
    
    # Run automation with proper timeout
    echo "[$(date -Iseconds)] 🕐 Starting stable automation: $(date -Iseconds)"
    
    cd /work
    
    # Run with reasonable timeout (5 minutes)
    if timeout 300 node create-api-key.js; then  
        echo "[$(date -Iseconds)] ✅ Automation completed successfully"
    else
        local exit_code=$?
        echo "[$(date -Iseconds)] ❌ Automation failed: exit code $exit_code"
        exit 1
    fi
    
    # Validate result
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

# Execute main function
main "$@"
