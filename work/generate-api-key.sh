#!/bin/bash

echo "Creating N8N API Key using Browser Automation..."

# Install browser dependencies
install_browser_deps() {
    echo "Installing browser automation dependencies..."
    
    # Install Puppeteer globally
    npm install -g puppeteer
    
    echo "Puppeteer installed successfully"
}

# สร้าง Node.js script สำหรับ browser automation
create_automation_script() {
    cat > /work/create-api-key.js << 'EOF'
const puppeteer = require('puppeteer');

async function createApiKey() {
    const N8N_URL = process.env.N8N_WORKING_URL;
    const EMAIL = process.env.N8N_USER_EMAIL;
    const PASSWORD = process.env.N8N_USER_PASSWORD;
    
    console.log('Launching browser...');
    
    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/chromium-browser',
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu'
        ]
    });
    
    try {
        const page = await browser.newPage();
        
        // Set viewport
        await page.setViewport({ width: 1280, height: 800 });
        
        console.log('Navigating to N8N login...');
        await page.goto(`${N8N_URL}/signin`, { waitUntil: 'networkidle2', timeout: 30000 });
        
        // Wait for login form to appear
        await page.waitForSelector('input[name="email"], input[data-test-id="email"], [data-test="email"]', { timeout: 10000 });
        
        // Login - try multiple selectors
        console.log('Filling login form...');
        const emailSelector = await page.$('input[name="email"]') || await page.$('input[data-test-id="email"]') || await page.$('[data-test="email"]');
        const passwordSelector = await page.$('input[name="password"]') || await page.$('input[data-test-id="password"]') || await page.$('[data-test="password"]');
        
        if (emailSelector && passwordSelector) {
            await emailSelector.type(EMAIL);
            await passwordSelector.type(PASSWORD);
        } else {
            // Fallback to generic input selectors
            const inputs = await page.$('input');
            if (inputs.length >= 2) {
                await inputs[0].type(EMAIL);
                await inputs[1].type(PASSWORD);
            } else {
                throw new Error('Could not find login form inputs');
            }
        }
        
        // Click login button - try multiple selectors
        const loginButton = await page.$('button[data-test-id="signin-button"]') || 
                           await page.$('button[type="submit"]') || 
                           await page.$('button:contains("Sign in")');
        
        if (loginButton) {
            await loginButton.click();
        } else {
            await page.keyboard.press('Enter');
        }
        
        await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 });
        
        console.log('Login successful, navigating to settings...');
        
        // Navigate to settings - try multiple approaches
        let settingsLoaded = false;
        try {
            await page.goto(`${N8N_URL}/settings/api`, { waitUntil: 'networkidle2', timeout: 30000 });
            settingsLoaded = true;
        } catch (e) {
            console.log('Direct settings navigation failed, trying menu navigation...');
            await page.goto(`${N8N_URL}`, { waitUntil: 'networkidle2' });
            
            // Look for settings menu
            const settingsMenu = await page.$('[data-test-id="menu-settings"]') || await page.$('a[href="/settings"]') || await page.$('a:contains("Settings")');
            if (settingsMenu) {
                await settingsMenu.click();
                await page.waitForTimeout(2000);
                
                // Click API submenu
                const apiMenu = await page.$('a[href="/settings/api"]') || await page.$('a:contains("API")');
                if (apiMenu) {
                    await apiMenu.click();
                    await page.waitForTimeout(2000);
                    settingsLoaded = true;
                }
            }
        }
        
        if (!settingsLoaded) {
            throw new Error('Could not navigate to API settings page');
        }
        
        console.log('Looking for create API key button...');
        
        // Wait for and click create API key button - multiple selectors
        let createButton;
        const buttonSelectors = [
            '[data-test-id="create-api-key-button"]',
            'button:contains("Create API Key")',
            'button:contains("Create")',
            '.el-button--primary',
            'button[type="button"]'
        ];
        
        for (const selector of buttonSelectors) {
            try {
                createButton = await page.waitForSelector(selector, { timeout: 5000 });
                if (createButton) {
                    console.log(`Found create button with selector: ${selector}`);
                    break;
                }
            } catch (e) {
                console.log(`Selector ${selector} not found, trying next...`);
            }
        }
        
        if (!createButton) {
            throw new Error('Could not find create API key button');
        }
        
        console.log('Creating API key...');
        await createButton.click();
        
        // Wait for API key to be generated - multiple approaches
        await page.waitForTimeout(3000);
        
        let apiKey = null;
        const keySelectors = [
            '[data-test-id="api-key-value"]',
            '.api-key-value',
            'code',
            'pre',
            'input[readonly]',
            '.el-input__inner[readonly]'
        ];
        
        for (const selector of keySelectors) {
            try {
                const element = await page.$(selector);
                if (element) {
                    const text = await element.evaluate(el => el.textContent || el.value);
                    if (text && text.length > 20) {  // API keys are usually long
                        apiKey = text.trim();
                        console.log(`Found API key with selector: ${selector}`);
                        break;
                    }
                }
            } catch (e) {
                console.log(`Selector ${selector} failed, trying next...`);
            }
        }
        
        if (!apiKey) {
            // Last resort - screenshot for debugging
            await page.screenshot({ path: '/work/debug-screenshot.png' });
            throw new Error('Could not extract API key from page');
        }
        
        console.log('API Key created successfully:', apiKey.substring(0, 10) + '...[HIDDEN]');
        console.log('Full API Key:', apiKey);
        
        // Save to file
        require('fs').writeFileSync('/work/n8n-api-key.txt', apiKey);
        
        console.log('SUCCESS: API key saved to file');
        
    } catch (error) {
        console.error('Browser automation error:', error);
        process.exit(1);
    } finally {
        await browser.close();
    }
}

createApiKey();
EOF

    echo "Browser automation script created"
}

# รอให้ N8N พร้อม
wait_for_n8n() {
    echo "Waiting for N8N to be ready..."
    
    local n8n_urls=(
        "https://${N8N_HOST}"
        "http://n8n:5678"
    )
    
    for url in "${n8n_urls[@]}"; do
        echo "Testing: $url/healthz"
        if curl -f -s --connect-timeout 10 --max-time 15 "$url/healthz" > /dev/null 2>&1; then
            export N8N_WORKING_URL="$url"
            echo "Found working N8N URL: $url"
            return 0
        fi
    done
    
    echo "N8N failed to become ready"
    return 1
}

# Setup owner account
setup_owner() {
    local n8n_url="${N8N_WORKING_URL}"
    echo "Setting up N8N owner account..."
    
    local setup_url="${n8n_url}/rest/owner/setup"
    
    local owner_response=$(curl -s -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${N8N_USER_EMAIL}\",
            \"firstName\": \"${N8N_FIRST_NAME:-User}\",
            \"lastName\": \"${N8N_LAST_NAME:-User}\",
            \"password\": \"${N8N_USER_PASSWORD}\"
        }" 2>&1)
    
    echo "Owner setup response: $owner_response"
    return 0
}

# Main execution
main() {
    echo "=== N8N API Key Generation via Browser Automation ==="
    
    # Step 1: Wait for N8N
    if ! wait_for_n8n; then
        echo "ERROR: N8N failed to become ready"
        exit 1
    fi
    
    # Step 2: Setup owner
    setup_owner
    
    # Step 3: Install dependencies
    echo "Installing browser automation dependencies..."
    install_browser_deps
    
    # Step 4: Create automation script
    create_automation_script
    
    # Step 5: Wait for N8N UI to be fully ready
    echo "Waiting for N8N UI to be ready..."
    sleep 60
    
    # Step 6: Run browser automation
    echo "Running browser automation..."
    cd /work
    node create-api-key.js
    
    if [ -f /work/n8n-api-key.txt ]; then
        echo "SUCCESS: API key created via browser automation"
        exit 0
    else
        echo "ERROR: Browser automation failed"
        exit 1
    fi
}

main
