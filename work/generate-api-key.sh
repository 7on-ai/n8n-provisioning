#!/bin/bash

echo "Creating N8N API Key using Browser Automation (Final Fix)..."

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

# สร้าง Node.js script ที่แก้ไขปัญหา timeout และ performance
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
        console.error('N8N_URL:', N8N_URL);
        console.error('EMAIL:', EMAIL);
        console.error('PASSWORD:', PASSWORD ? 'SET' : 'NOT SET');
        process.exit(1);
    }
    
    console.log('=== Browser Automation Start ===');
    console.log('N8N URL:', N8N_URL);
    console.log('Email:', EMAIL);
    console.log('Password length:', PASSWORD.length);
    
    // เพิ่มการ configure browser สำหรับ container environment
    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/chromium-browser',
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-web-security',
            '--disable-features=VizDisplayCompositor',
            '--disable-extensions',
            '--disable-plugins',
            '--disable-images',  // ปิดการโหลดรูปภาพเพื่อความเร็ว
            '--disable-javascript',  // ปิด JS บางอย่างที่ไม่จำเป็น
            '--no-zygote',
            '--single-process',
            '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows',
            '--disable-renderer-backgrounding'
        ],
        // เพิ่ม timeout สำหรับการเชื่อมต่อ browser
        protocolTimeout: 120000,  // 2 นาที
        timeout: 120000
    });
    
    let page;
    try {
        page = await browser.newPage();
        
        // ตั้งค่า page สำหรับ performance
        await page.setViewport({ width: 1280, height: 800 });
        await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        
        // ปิดการโหลด resources ที่ไม่จำเป็น
        await page.setRequestInterception(true);
        page.on('request', (req) => {
            const resourceType = req.resourceType();
            if (resourceType === 'image' || resourceType === 'font' || resourceType === 'media') {
                req.abort();
            } else {
                req.continue();
            }
        });
        
        // เพิ่ม timeout และ retry mechanism
        console.log('Attempting to navigate to N8N login page...');
        
        let loginPageLoaded = false;
        let retryCount = 0;
        const maxRetries = 3;
        
        while (!loginPageLoaded && retryCount < maxRetries) {
            try {
                console.log(`Navigation attempt ${retryCount + 1}/${maxRetries}`);
                
                // เพิ่ม timeout เป็น 3 นาที และใช้ domcontentloaded แทน networkidle
                await page.goto(`${N8N_URL}/signin`, { 
                    waitUntil: 'domcontentloaded',  // เปลี่ยนจาก networkidle0
                    timeout: 180000  // 3 นาที
                });
                
                loginPageLoaded = true;
                console.log('✅ Successfully navigated to login page');
                
            } catch (navigationError) {
                retryCount++;
                console.log(`❌ Navigation attempt ${retryCount} failed:`, navigationError.message);
                
                if (retryCount < maxRetries) {
                    console.log('Retrying navigation in 10 seconds...');
                    await new Promise(resolve => setTimeout(resolve, 10000));
                } else {
                    throw new Error(`Failed to navigate to signin page after ${maxRetries} attempts: ${navigationError.message}`);
                }
            }
        }
        
        // รอให้หน้าโหลดเสร็จ
        console.log('Waiting for page to stabilize...');
        await page.waitForTimeout(5000);
        
        // Take screenshot for debugging
        await page.screenshot({ path: '/work/01-signin-page.png' });
        console.log('Screenshot saved: 01-signin-page.png');
        
        console.log('Looking for login form elements...');
        
        // รอให้ form elements โหลด
        let formReady = false;
        let formRetry = 0;
        const maxFormRetries = 10;
        
        while (!formReady && formRetry < maxFormRetries) {
            try {
                // รอหา email input
                await page.waitForSelector('input[type="email"], input[name="email"], input[data-test-id="email"]', {
                    timeout: 10000,
                    visible: true
                });
                
                // รอหา password input
                await page.waitForSelector('input[type="password"], input[name="password"], input[data-test-id="password"]', {
                    timeout: 5000,
                    visible: true
                });
                
                formReady = true;
                console.log('✅ Login form elements found');
                
            } catch (formError) {
                formRetry++;
                console.log(`Form check attempt ${formRetry}/${maxFormRetries} failed`);
                
                if (formRetry < maxFormRetries) {
                    await page.waitForTimeout(2000);
                } else {
                    throw new Error(`Login form not found after ${maxFormRetries} attempts`);
                }
            }
        }
        
        // Find and fill email
        const emailInput = await page.$('input[type="email"], input[name="email"], input[data-test-id="email"]');
        if (!emailInput) {
            throw new Error('Email input not found');
        }
        
        console.log('Filling email field...');
        await emailInput.click();
        await emailInput.clear();
        await emailInput.type(EMAIL, { delay: 100 });
        
        // Find and fill password
        const passwordInput = await page.$('input[type="password"], input[name="password"], input[data-test-id="password"]');
        if (!passwordInput) {
            throw new Error('Password input not found');
        }
        
        console.log('Filling password field...');
        await passwordInput.click();
        await passwordInput.clear();
        await passwordInput.type(PASSWORD, { delay: 100 });
        
        await page.screenshot({ path: '/work/02-form-filled.png' });
        console.log('Screenshot saved: 02-form-filled.png');
        
        // Submit form
        console.log('Submitting login form...');
        await passwordInput.press('Enter');
        
        // รอการ navigate หลัง login ด้วย timeout ที่เหมาะสม
        console.log('Waiting for login to complete...');
        try {
            await page.waitForNavigation({ 
                waitUntil: 'domcontentloaded', 
                timeout: 60000 
            });
            console.log('✅ Login navigation completed');
        } catch (navError) {
            console.log('Navigation timeout, checking URL...');
            const currentUrl = await page.url();
            if (currentUrl.includes('/signin')) {
                throw new Error('Login failed - still on signin page');
            }
            console.log('✅ Login appears successful based on URL change');
        }
        
        await page.screenshot({ path: '/work/03-after-login.png' });
        console.log('Screenshot saved: 03-after-login.png');
        
        // Navigate to API settings
        console.log('Navigating to API settings...');
        const apiSettingsUrl = `${N8N_URL}/settings/api`;
        
        await page.goto(apiSettingsUrl, { 
            waitUntil: 'domcontentloaded', 
            timeout: 120000  // 2 นาที
        });
        
        await page.waitForTimeout(5000);
        await page.screenshot({ path: '/work/04-api-settings.png' });
        console.log('Screenshot saved: 04-api-settings.png');
        
        // Look for create API key button with extended timeout
        console.log('Looking for create API key button...');
        
        let createButton = null;
        const buttonSelectors = [
            'button:contains("Create API key")',
            'button:contains("Create API Key")',
            'button:contains("Create")',
            '[data-test*="create"]',
            '.el-button--primary',
            'button.el-button--primary',
            'button[type="button"]'
        ];
        
        for (const selector of buttonSelectors) {
            try {
                console.log(`Trying selector: ${selector}`);
                createButton = await page.waitForSelector(selector, { 
                    timeout: 10000,
                    visible: true 
                });
                if (createButton) {
                    console.log(`✅ Found create button with: ${selector}`);
                    break;
                }
            } catch (e) {
                console.log(`Selector ${selector} not found`);
            }
        }
        
        if (!createButton) {
            // Fallback - ดูปุ่มทั้งหมดในหน้า
            console.log('Fallback: Looking for any button that might create API key...');
            const allButtons = await page.$$('button');
            console.log(`Found ${allButtons.length} buttons on page`);
            
            for (let i = 0; i < allButtons.length; i++) {
                const buttonText = await allButtons[i].evaluate(el => el.textContent || el.innerText || '');
                console.log(`Button ${i}: "${buttonText}"`);
                
                if (buttonText.toLowerCase().includes('create') || buttonText.toLowerCase().includes('api')) {
                    createButton = allButtons[i];
                    console.log(`✅ Found create button by text: "${buttonText}"`);
                    break;
                }
            }
        }
        
        if (!createButton) {
            throw new Error('Could not find create API key button');
        }
        
        console.log('Clicking create API key button...');
        await createButton.click();
        
        // รอให้ API key ถูกสร้าง
        console.log('Waiting for API key generation...');
        await page.waitForTimeout(10000);  // รอ 10 วินาที
        
        await page.screenshot({ path: '/work/05-after-create.png' });
        console.log('Screenshot saved: 05-after-create.png');
        
        // หา API key ที่สร้างขึ้น
        console.log('Searching for generated API key...');
        let apiKey = null;
        
        const keySelectors = [
            '[data-test*="api-key"]',
            '[data-test*="key"]',
            '.api-key',
            'code',
            'pre',
            'input[readonly]',
            '.el-input__inner[readonly]',
            'textarea[readonly]',
            '.copy-input',
            '[class*="key"]',
            '[class*="token"]'
        ];
        
        // ลองหาจาก selectors ต่างๆ
        for (const selector of keySelectors) {
            try {
                const elements = await page.$$(selector);
                console.log(`Found ${elements.length} elements for selector: ${selector}`);
                
                for (let i = 0; i < elements.length; i++) {
                    const text = await elements[i].evaluate(el => 
                        el.textContent || el.value || el.getAttribute('value') || el.innerText || ''
                    );
                    
                    console.log(`Element ${i} text: "${text.substring(0, 50)}..."`);
                    
                    if (text && text.length > 20 && text.match(/^[a-zA-Z0-9_-]{20,}$/)) {
                        apiKey = text.trim();
                        console.log(`✅ Found API key with selector: ${selector}`);
                        break;
                    }
                }
                if (apiKey) break;
            } catch (e) {
                console.log(`Error with selector ${selector}:`, e.message);
            }
        }
        
        // ถ้ายังหาไม่เจอ ลอง scan หน้าทั้งหมด
        if (!apiKey) {
            console.log('Final attempt: Scanning entire page content for API key pattern...');
            const pageContent = await page.content();
            
            // หา pattern ที่เป็น API key
            const keyPatterns = [
                /[a-zA-Z0-9_-]{32,}/g,
                /n8n_api_[a-zA-Z0-9_-]{20,}/g,
                /api_key_[a-zA-Z0-9_-]{20,}/g
            ];
            
            for (const pattern of keyPatterns) {
                const matches = pageContent.match(pattern);
                if (matches && matches.length > 0) {
                    // เอาที่ยาวที่สุด
                    apiKey = matches.reduce((longest, current) => 
                        current.length > longest.length ? current : longest
                    );
                    
                    if (apiKey.length > 20) {
                        console.log(`✅ Found potential API key from page scan (${apiKey.length} chars)`);
                        break;
                    }
                }
            }
        }
        
        if (!apiKey) {
            await page.screenshot({ path: '/work/06-final-error.png' });
            console.log('Screenshot saved: 06-final-error.png');
            
            // Debug: แสดง page content
            const pageText = await page.evaluate(() => document.body.innerText);
            console.log('Page content sample:', pageText.substring(0, 500));
            
            throw new Error('Could not extract API key from page after all attempts');
        }
        
        console.log('🎉 API Key created successfully!');
        console.log('API Key length:', apiKey.length);
        console.log('API Key (first 10 chars):', apiKey.substring(0, 10) + '...');
        console.log('API Key (last 10 chars): ...' + apiKey.substring(apiKey.length - 10));
        
        // Save to file
        fs.writeFileSync('/work/n8n-api-key.txt', apiKey);
        console.log('✅ API key saved to /work/n8n-api-key.txt');
        
        return apiKey;
        
    } catch (error) {
        console.error('❌ Browser automation error:', error.message);
        console.error('Error stack:', error.stack);
        
        // Take final error screenshot
        if (page) {
            try {
                await page.screenshot({ path: '/work/99-final-error.png' });
                console.log('Error screenshot saved: 99-final-error.png');
                
                // Debug info
                const url = await page.url();
                console.log('Current URL:', url);
                
                const title = await page.title();
                console.log('Page title:', title);
                
            } catch (screenshotError) {
                console.log('Could not take error screenshot:', screenshotError.message);
            }
        }
        
        throw error;
    } finally {
        if (browser) {
            await browser.close();
        }
    }
}

// Run with comprehensive error handling
createApiKey()
    .then((apiKey) => {
        console.log('🎊 SUCCESS: API key generation completed');
        console.log('Final API key length:', apiKey.length);
        process.exit(0);
    })
    .catch(error => {
        console.error('💥 FINAL ERROR: API key generation failed');
        console.error('Error message:', error.message);
        process.exit(1);
    });
EOF

    echo "✅ Enhanced browser automation script created"
}

# ปรับปรุง Health Check ให้ validate การเชื่อมต่อจริง
wait_for_n8n_validated() {
    echo "Validating N8N readiness with actual page tests..."
    
    local n8n_urls=()
    
    if [ -n "$N8N_HOST" ]; then
        n8n_urls+=("https://$N8N_HOST")
        n8n_urls+=("http://$N8N_HOST")
        echo "Testing N8N_HOST: $N8N_HOST"
    fi
    
    n8n_urls+=("http://n8n:5678")
    echo "Will test URLs: ${n8n_urls[*]}"
    
    local max_attempts=15  # เพิ่มเป็น 15 attempts
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Validation attempt $attempt/$max_attempts"
        
        for url in "${n8n_urls[@]}"; do
            echo "Testing: $url"
            
            # Test 1: Health endpoint
            if curl -f -s --connect-timeout 15 --max-time 30 "$url/healthz" > /dev/null 2>&1; then
                echo "✅ Health endpoint OK"
                
                # Test 2: Main page accessibility
                local main_response=$(curl -s --connect-timeout 15 --max-time 30 "$url/" 2>/dev/null)
                if [ ${#main_response} -gt 100 ]; then
                    echo "✅ Main page accessible"
                    
                    # Test 3: Signin page accessibility
                    local signin_response=$(curl -s --connect-timeout 15 --max-time 30 "$url/signin" 2>/dev/null)
                    if [ ${#signin_response} -gt 100 ]; then
                        echo "✅ Signin page accessible"
                        
                        export N8N_WORKING_URL="$url"
                        echo "🎯 N8N is validated and ready: $url"
                        return 0
                    else
                        echo "⚠️ Signin page not ready"
                    fi
                else
                    echo "⚠️ Main page not ready"
                fi
            else
                echo "❌ Health endpoint failed: $url"
            fi
        done
        
        sleep 10
        ((attempt++))
    done
    
    echo "❌ N8N validation failed after $max_attempts attempts"
    return 1
}

# Setup owner với better error handling
setup_owner() {
    if [ -z "$N8N_WORKING_URL" ]; then
        echo "ERROR: N8N_WORKING_URL not set"
        return 1
    fi
    
    echo "Setting up N8N owner account..."
    echo "Using validated URL: $N8N_WORKING_URL"
    
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    echo "Setup endpoint: $setup_url"
    
    local owner_response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --connect-timeout 15 --max-time 30 \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-Admin}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Owner setup response: $owner_response"
    
    # Extract HTTP code
    local http_code=$(echo "$owner_response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    echo "HTTP response code: $http_code"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "✅ Owner account created successfully"
    elif echo "$owner_response" | grep -q "already setup\|already exists"; then
        echo "✅ Owner account already exists"
    elif [ "$http_code" = "400" ]; then
        echo "⚠️ Owner setup returned 400 (likely already exists)"
    else
        echo "⚠️ Unexpected owner setup response, but proceeding..."
    fi
    
    return 0
}

# Main execution with comprehensive logging
main() {
    echo "=== N8N API Key Generation (Final Fix Version) ==="
    echo "🕐 Started at: $(date)"
    echo "🐳 Container environment: $(uname -a)"
    echo "📊 Memory info: $(free -h | head -2)"
    
    # Step 1: Environment validation
    echo ""
    echo "📋 Step 1: Environment validation"
    check_env_vars
    
    echo "Environment variables status:"
    echo "- N8N_HOST: ${N8N_HOST:-'NOT SET'}"
    echo "- N8N_USER_EMAIL: ${N8N_USER_EMAIL:-'NOT SET'}"
    echo "- N8N_USER_PASSWORD: ${N8N_USER_PASSWORD:+SET (${#N8N_USER_PASSWORD} chars)}"
    echo "- N8N_FIRST_NAME: ${N8N_FIRST_NAME:-'NOT SET'}"
    echo "- N8N_LAST_NAME: ${N8N_LAST_NAME:-'NOT SET'}"
    
    # Step 2: Enhanced N8N validation
    echo ""
    echo "🔍 Step 2: N8N comprehensive validation"
    if ! wait_for_n8n_validated; then
        echo "❌ ERROR: N8N validation failed"
        echo "This could indicate:"
        echo "- N8N service not ready"
        echo "- Network connectivity issues"
        echo "- DNS resolution problems"
        echo "- Resource constraints"
        exit 1
    fi
    
    # Step 3: Owner setup
    echo ""
    echo "👤 Step 3: Owner account setup"
    if ! setup_owner; then
        echo "❌ ERROR: Owner setup failed"
        exit 1
    fi
    
    # Step 4: Browser automation preparation
    echo ""
    echo "🤖 Step 4: Browser automation preparation"
    create_automation_script
    
    # Step 5: Additional stabilization wait
    echo ""
    echo "⏳ Step 5: Stabilization wait"
    echo "Allowing N8N UI components to fully initialize..."
    sleep 30
    
    # Step 6: Run enhanced browser automation
    echo ""
    echo "🚀 Step 6: Enhanced browser automation"
    echo "🕐 Automation started at: $(date)"
    
    cd /work
    export NODE_PATH="/work/node_modules:$NODE_PATH"
    
    # Run with extended timeout
    if timeout 900 node create-api-key.js; then  # 15 minutes timeout
        echo "✅ Browser automation completed successfully"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "❌ ERROR: Browser automation timed out (15 minutes)"
        else
            echo "❌ ERROR: Browser automation failed with exit code: $exit_code"
        fi
        exit 1
    fi
    
    # Step 7: Final validation
    echo ""
    echo "✅ Step 7: Result validation"
    echo "🕐 Validation at: $(date)"
    
    if [ -f /work/n8n-api-key.txt ]; then
        local key_length=$(wc -c < /work/n8n-api-key.txt)
        local key_preview=$(head -c 10 /work/n8n-api-key.txt)
        
        echo "🎉 SUCCESS: API key generation completed!"
        echo "📁 File: /work/n8n-api-key.txt"
        echo "📏 Length: $key_length characters"
        echo "🔑 Preview: ${key_preview}..."
        echo "🕐 Total time: Started earlier, completed at $(date)"
        
        # Validate key format
        if [ $key_length -gt 20 ]; then
            echo "✅ API key format validation passed"
            exit 0
        else
            echo "⚠️ WARNING: API key seems too short ($key_length chars)"
            exit 1
        fi
    else
        echo "❌ ERROR: API key file not created"
        
        echo ""
        echo "🔍 Debug information:"
        echo "Working directory contents:"
        ls -la /work/
        
        echo ""
        echo "Screenshots available:"
        ls -la /work/*.png 2>/dev/null || echo "No screenshots found"
        
        echo ""
        echo "Process list:"
        ps aux | grep -E "(node|chromium)" || echo "No relevant processes"
        
        exit 1
    fi
}

# Execute with error trapping
set -e
trap 'echo "❌ Script failed at line $LINENO"; exit 1' ERR

main "$@"
