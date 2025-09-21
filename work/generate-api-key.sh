#!/bin/bash

echo "Creating N8N API Key using Browser Automation (Container-Optimized)..."

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

# สร้าง Node.js script ที่เหมาะกับ container environment
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
    
    console.log('=== Container-Optimized Browser Automation ===');
    console.log('N8N URL:', N8N_URL);
    console.log('Email:', EMAIL);
    console.log('Password length:', PASSWORD.length);
    
    let browser = null;
    let page = null;
    
    try {
        // ปรับ config สำหรับ container environment เพื่อป้องกัน Target closed
        console.log('Launching browser with container-optimized settings...');
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/chromium-browser',
            headless: 'new',  // ใช้ new headless mode แทน true
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
                '--single-process',  // สำคัญ: ป้องกัน Target closed ใน container
                '--disable-background-timer-throttling',
                '--disable-backgrounding-occluded-windows',
                '--disable-renderer-backgrounding',
                '--disable-features=TranslateUI',
                '--disable-ipc-flooding-protection',
                '--memory-pressure-off',
                '--max_old_space_size=2048'
            ],
            // ลด timeout เพื่อหลีกเลี่ยง race condition
            timeout: 60000,
            protocolTimeout: 60000,
            // กำหนด pipe เป็น false เพื่อหลีกเลี่ยง Target closed
            pipe: false
        });
        
        console.log('✅ Browser launched successfully');
        
        // สร้าง page ด้วย error handling
        page = await browser.newPage();
        console.log('✅ New page created');
        
        // ตั้งค่า page
        await page.setViewport({ width: 1280, height: 800 });
        await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36');
        
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
        
        console.log('Navigating to N8N signin page...');
        
        // Navigate with shorter timeout และ robust error handling
        try {
            await page.goto(`${N8N_URL}/signin`, { 
                waitUntil: 'domcontentloaded',
                timeout: 60000  // ลดเป็น 1 นาที
            });
            console.log('✅ Navigation successful');
        } catch (navError) {
            console.log('Navigation failed, trying alternative approach...');
            // ลองไปหน้าหลักก่อนแล้ว redirect
            await page.goto(N8N_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
            await page.goto(`${N8N_URL}/signin`, { waitUntil: 'domcontentloaded', timeout: 60000 });
        }
        
        // รอให้หน้าเสถียร
        await page.waitForTimeout(3000);
        await page.screenshot({ path: '/work/01-signin.png' });
        
        console.log('Looking for login form...');
        
        // หา login form elements ด้วย timeout สั้น
        let emailInput = null;
        let passwordInput = null;
        
        try {
            emailInput = await page.waitForSelector('input[type="email"], input[name="email"]', {
                timeout: 30000,
                visible: true
            });
            console.log('✅ Email input found');
            
            passwordInput = await page.waitForSelector('input[type="password"], input[name="password"]', {
                timeout: 10000,
                visible: true
            });
            console.log('✅ Password input found');
            
        } catch (selectorError) {
            throw new Error(`Login form not found: ${selectorError.message}`);
        }
        
        // Fill form
        console.log('Filling login form...');
        await emailInput.click();
        await emailInput.type(EMAIL, { delay: 50 });
        
        await passwordInput.click();
        await passwordInput.type(PASSWORD, { delay: 50 });
        
        await page.screenshot({ path: '/work/02-form-filled.png' });
        
        // Submit form
        console.log('Submitting form...');
        await passwordInput.press('Enter');
        
        // Wait for login with timeout
        try {
            await page.waitForNavigation({ 
                waitUntil: 'domcontentloaded',
                timeout: 30000 
            });
            console.log('✅ Login successful');
        } catch (loginError) {
            const currentUrl = await page.url();
            if (currentUrl.includes('/signin')) {
                throw new Error('Login failed - credentials might be incorrect');
            }
            console.log('✅ Login appears successful (URL changed)');
        }
        
        await page.screenshot({ path: '/work/03-after-login.png' });
        
        // Navigate to API settings
        console.log('Going to API settings...');
        await page.goto(`${N8N_URL}/settings/api`, {
            waitUntil: 'domcontentloaded',
            timeout: 60000
        });
        
        await page.waitForTimeout(3000);
        await page.screenshot({ path: '/work/04-api-page.png' });
        
        // Find create button
        console.log('Looking for create API key button...');
        let createButton = null;
        
        const buttonSelectors = [
            'button:contains("Create API key")',
            'button:contains("Create API Key")',
            'button:contains("Create")',
            '.el-button--primary'
        ];
        
        for (const selector of buttonSelectors) {
            try {
                createButton = await page.waitForSelector(selector, { 
                    timeout: 10000,
                    visible: true 
                });
                if (createButton) {
                    console.log(`✅ Found button: ${selector}`);
                    break;
                }
            } catch (e) {
                console.log(`Button ${selector} not found`);
            }
        }
        
        if (!createButton) {
            throw new Error('Create API key button not found');
        }
        
        // Click create button
        console.log('Creating API key...');
        await createButton.click();
        await page.waitForTimeout(5000);
        
        await page.screenshot({ path: '/work/05-after-create.png' });
        
        // Extract API key
        console.log('Extracting API key...');
        let apiKey = null;
        
        // Try different methods to find the key
        const keySelectors = [
            'code',
            'pre',
            'input[readonly]',
            'textarea[readonly]',
            '[data-test*="api-key"]',
            '.el-input__inner[readonly]'
        ];
        
        for (const selector of keySelectors) {
            try {
                const elements = await page.$$(selector);
                for (const element of elements) {
                    const text = await element.evaluate(el => 
                        el.textContent || el.value || el.getAttribute('value') || ''
                    );
                    
                    // Check if it looks like an API key
                    if (text && text.length > 20 && /^[a-zA-Z0-9_-]{20,}$/.test(text.trim())) {
                        apiKey = text.trim();
                        console.log(`✅ Found API key with ${selector}`);
                        break;
                    }
                }
                if (apiKey) break;
            } catch (e) {
                console.log(`Selector ${selector} failed: ${e.message}`);
            }
        }
        
        // Fallback: scan page content
        if (!apiKey) {
            console.log('Scanning page content for API key...');
            const pageContent = await page.content();
            const matches = pageContent.match(/[a-zA-Z0-9_-]{32,}/g);
            
            if (matches && matches.length > 0) {
                apiKey = matches.reduce((longest, current) => 
                    current.length > longest.length ? current : longest
                );
                console.log('✅ Found API key from page scan');
            }
        }
        
        if (!apiKey) {
            await page.screenshot({ path: '/work/06-error-no-key.png' });
            throw new Error('Could not extract API key');
        }
        
        console.log('🎉 API Key extracted successfully!');
        console.log('Length:', apiKey.length);
        console.log('Preview:', apiKey.substring(0, 10) + '...');
        
        // Save key
        fs.writeFileSync('/work/n8n-api-key.txt', apiKey);
        console.log('✅ API key saved to file');
        
        return apiKey;
        
    } catch (error) {
        console.error('❌ Automation error:', error.message);
        
        // Emergency screenshot
        if (page) {
            try {
                await page.screenshot({ path: '/work/99-error.png' });
                console.log('Error screenshot saved');
            } catch (e) {
                console.log('Could not take error screenshot');
            }
        }
        
        throw error;
        
    } finally {
        // Cleanup
        console.log('Cleaning up browser resources...');
        if (page) {
            try {
                await page.close();
                console.log('✅ Page closed');
            } catch (e) {
                console.log('Page close error:', e.message);
            }
        }
        
        if (browser) {
            try {
                await browser.close();
                console.log('✅ Browser closed');
            } catch (e) {
                console.log('Browser close error:', e.message);
            }
        }
    }
}

// Run with proper error handling
createApiKey()
    .then((apiKey) => {
        console.log('🎊 SUCCESS: API key generation completed');
        console.log('Final key length:', apiKey ? apiKey.length : 0);
        process.exit(0);
    })
    .catch(error => {
        console.error('💥 FAILED: API key generation failed');
        console.error('Final error:', error.message);
        process.exit(1);
    });
EOF

    echo "✅ Container-optimized automation script created"
}

# Simple health check (N8N พร้อมแล้วจาก log)
wait_for_n8n_simple() {
    echo "Quick N8N availability check..."
    
    local n8n_urls=()
    
    if [ -n "$N8N_HOST" ]; then
        n8n_urls+=("https://$N8N_HOST")
        n8n_urls+=("http://$N8N_HOST")
    fi
    
    n8n_urls+=("http://n8n:5678")
    
    echo "Testing URLs: ${n8n_urls[*]}"
    
    for url in "${n8n_urls[@]}"; do
        echo "Testing: $url/healthz"
        
        if curl -f -s --connect-timeout 10 --max-time 20 "$url/healthz" > /dev/null 2>&1; then
            export N8N_WORKING_URL="$url"
            echo "✅ N8N ready: $url"
            return 0
        fi
    done
    
    echo "❌ N8N not accessible"
    return 1
}

# Simple owner setup
setup_owner() {
    echo "Setting up owner account..."
    
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    
    local response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-Admin}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Owner setup: $response"
    return 0
}

# Main execution - simplified
main() {
    echo "=== Container-Optimized N8N API Key Generation ==="
    echo "🕐 Started: $(date)"
    echo "🐳 Container: $(hostname)"
    echo "💾 Memory: $(free -h | grep Mem)"
    
    # Step 1: Check environment
    echo ""
    echo "Step 1: Environment check"
    check_env_vars
    
    echo "Environment status:"
    echo "- N8N_HOST: ${N8N_HOST}"
    echo "- N8N_USER_EMAIL: ${N8N_USER_EMAIL}"
    echo "- Password length: ${#N8N_USER_PASSWORD}"
    
    # Step 2: Quick N8N check
    echo ""
    echo "Step 2: N8N accessibility"
    if ! wait_for_n8n_simple; then
        echo "❌ N8N not ready"
        exit 1
    fi
    
    # Step 3: Owner setup
    echo ""
    echo "Step 3: Owner setup"
    setup_owner
    
    # Step 4: Create script
    echo ""
    echo "Step 4: Script preparation"
    create_automation_script
    
    # Step 5: Run automation
    echo ""
    echo "Step 5: Browser automation"
    echo "🕐 Starting automation: $(date)"
    
    cd /work
    export NODE_PATH="/work/node_modules:$NODE_PATH"
    
    # Run with moderate timeout
    if timeout 300 node create-api-key.js; then  # 5 minutes
        echo "✅ Automation completed"
    else
        local exit_code=$?
        echo "❌ Automation failed: exit code $exit_code"
        exit 1
    fi
    
    # Step 6: Validate result
    echo ""
    echo "Step 6: Result validation"
    
    if [ -f /work/n8n-api-key.txt ]; then
        local key_length=$(wc -c < /work/n8n-api-key.txt)
        local key_preview=$(head -c 10 /work/n8n-api-key.txt)
        
        echo "🎉 SUCCESS!"
        echo "📁 File: /work/n8n-api-key.txt"
        echo "📏 Length: $key_length chars"
        echo "🔑 Preview: ${key_preview}..."
        echo "🕐 Completed: $(date)"
        
        if [ $key_length -gt 20 ]; then
            exit 0
        else
            echo "⚠️ Key too short: $key_length chars"
            exit 1
        fi
    else
        echo "❌ No API key file created"
        echo "Debug info:"
        ls -la /work/
        ls -la /work/*.png 2>/dev/null || echo "No screenshots"
        exit 1
    fi
}

# Execute
main "$@"
