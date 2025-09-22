#!/bin/bash

# Enhanced N8N API Key Generator with Stability Improvements
set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Logging functions
log_info() {
    echo "[$(date -Iseconds)] INFO: $*"
}

log_error() {
    echo "[$(date -Iseconds)] ERROR: $*" >&2
}

log_warn() {
    echo "[$(date -Iseconds)] WARN: $*" >&2
}

# Enhanced environment variable checking
check_env_vars() {
    local required_vars=("N8N_USER_EMAIL" "N8N_USER_PASSWORD")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}" >&2
        exit 1
    fi
    
    log_info "Environment variables validated successfully"
}

# System requirements check
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check available memory
    if [ -f /proc/meminfo ]; then
        local available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local available_mb=$((available_mem / 1024))
        log_info "Available memory: ${available_mb}MB"
        
        if [ $available_mb -lt 256 ]; then
            log_warn "Low memory detected: ${available_mb}MB (recommended: 512MB+)"
        fi
    fi
    
    # Check disk space
    local disk_space=$(df /work | awk 'NR==2 {print $4}')
    local disk_mb=$((disk_space / 1024))
    log_info "Available disk space: ${disk_mb}MB"
    
    # Check Chromium
    if [ ! -x "/usr/bin/chromium" ]; then
        log_error "Chromium not found at /usr/bin/chromium"
        exit 1
    fi
    
    # Test Chromium launch
    log_info "Testing Chromium launch..."
    if timeout 10 /usr/bin/chromium --version > /dev/null 2>&1; then
        log_info "Chromium test successful: $(chromium --version)"
    else
        log_error "Chromium test failed"
        exit 1
    fi
    
    # Check Node.js and Puppeteer
    if ! command -v node > /dev/null; then
        log_error "Node.js not found"
        exit 1
    fi
    
    if ! node -e "require('puppeteer')" 2>/dev/null; then
        log_error "Puppeteer not found"
        exit 1
    fi
    
    log_info "System requirements check passed"
}

# Enhanced N8N availability check with better retry logic
wait_for_n8n() {
    log_info "Checking N8N availability..."
    
    local n8n_urls=()
    local max_attempts=30
    local attempt=1
    
    # Build URL list
    if [ -n "${N8N_HOST:-}" ]; then
        n8n_urls+=("https://$N8N_HOST")
        n8n_urls+=("http://$N8N_HOST")
    fi
    n8n_urls+=("http://n8n:5678")
    n8n_urls+=("http://localhost:5678")
    
    log_info "Testing URLs: ${n8n_urls[*]}"
    
    while [ $attempt -le $max_attempts ]; do
        log_info "N8N availability check attempt $attempt/$max_attempts"
        
        for url in "${n8n_urls[@]}"; do
            log_info "Testing: $url"
            
            # Test both /healthz and root path
            for path in "/healthz" ""; do
                local test_url="${url}${path}"
                
                if curl -f -s --connect-timeout 5 --max-time 10 "$test_url" > /dev/null 2>&1; then
                    export N8N_WORKING_URL="$url"
                    log_info "✅ N8N ready: $url"
                    return 0
                fi
            done
        done
        
        log_info "N8N not ready, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    log_error "N8N not accessible after $max_attempts attempts"
    return 1
}

# Enhanced owner setup with better error handling
setup_owner() {
    log_info "Setting up owner account..."
    
    local setup_url="${N8N_WORKING_URL}/rest/owner/setup"
    local response
    local http_code
    
    # Check if owner already exists
    local owner_check_response
    owner_check_response=$(curl -s -w "\n%{http_code}" "${N8N_WORKING_URL}/rest/login" 2>&1 || true)
    local owner_check_code
    owner_check_code=$(echo "$owner_check_response" | tail -n1)
    
    if [ "$owner_check_code" = "200" ] || [ "$owner_check_code" = "401" ]; then
        log_info "N8N instance already has an owner, skipping setup"
        return 0
    fi
    
    # Setup owner
    local setup_payload
    setup_payload=$(cat <<EOF
{
    "email": "${N8N_USER_EMAIL}",
    "firstName": "${N8N_FIRST_NAME:-Admin}",
    "lastName": "${N8N_LAST_NAME:-User}",
    "password": "${N8N_USER_PASSWORD}"
}
EOF
)
    
    response=$(curl -s -w "\n%{http_code}" -X POST "$setup_url" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$setup_payload" 2>&1)
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n -1)
    
    log_info "Owner setup response code: $http_code"
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log_info "Owner setup successful"
    elif [ "$http_code" = "400" ]; then
        log_info "Owner already exists (400 response)"
    else
        log_warn "Owner setup response: $response_body"
    fi
    
    return 0
}

# Create enhanced automation script with all improvements
create_enhanced_automation_script() {
    log_info "Creating enhanced automation script..."
    
    # Use the enhanced JavaScript from the artifact above
    cat > /work/create-api-key.js << 'ENHANCED_EOF'
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
    
    console.log(`${new Date().toISOString()} === Enhanced Browser Automation Start ===`);
    console.log(`${new Date().toISOString()} N8N URL: ${N8N_URL}`);
    console.log(`${new Date().toISOString()} Email: ${EMAIL}`);
    console.log(`${new Date().toISOString()} Password length: ${PASSWORD.length}`);
    
    let browser = null;
    let page = null;
    let retryCount = 0;
    const maxRetries = 3;
    
    // Retry wrapper function
    async function withRetry(operation, context = 'operation') {
        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                console.log(`${new Date().toISOString()} ${context} - attempt ${attempt}/${maxRetries}`);
                return await operation();
            } catch (error) {
                console.log(`${new Date().toISOString()} ${context} failed on attempt ${attempt}: ${error.message}`);
                
                if (attempt === maxRetries) {
                    throw error;
                }
                
                // Progressive delay between retries
                const delay = attempt * 2000;
                console.log(`${new Date().toISOString()} Waiting ${delay}ms before retry...`);
                await new Promise(resolve => setTimeout(resolve, delay));
                
                // Cleanup and restart browser if needed
                if (page && !page.isClosed()) {
                    try { await page.close(); } catch (e) {}
                }
                if (browser && browser.connected) {
                    try { await browser.close(); } catch (e) {}
                }
                browser = null;
                page = null;
            }
        }
    }
    
    try {
        await withRetry(async () => {
            console.log(`${new Date().toISOString()} Launching browser with enhanced stability...`);
            
            browser = await puppeteer.launch({
                executablePath: '/usr/bin/chromium',
                headless: 'new',
                args: [
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-dev-shm-usage',
                    '--memory-pressure-off',
                    '--max_old_space_size=512',
                    '--aggressive-cache-discard',
                    '--no-zygote',
                    '--single-process',
                    '--disable-background-timer-throttling',
                    '--disable-backgrounding-occluded-windows',
                    '--disable-renderer-backgrounding',
                    '--disable-web-security',
                    '--disable-extensions',
                    '--disable-plugins',
                    '--disable-gpu',
                    '--disable-software-rasterizer',
                    '--disable-background-networking',
                    '--disable-default-apps',
                    '--disable-sync',
                    '--disable-images',
                    '--disable-javascript-harmony-shipping',
                    '--disable-ipc-flooding-protection',
                    '--disable-features=TranslateUI,BlinkGenPropertyTrees,VizDisplayCompositor',
                    '--window-size=1280,800',
                    '--virtual-time-budget=30000'
                ],
                timeout: 30000,
                protocolTimeout: 30000,
                slowMo: 50
            });
            
            console.log(`${new Date().toISOString()} Browser launched successfully`);
        }, 'Browser launch');

        await withRetry(async () => {
            page = await browser.newPage();
            console.log(`${new Date().toISOString()} New page created`);
            
            await page.setViewport({ width: 1280, height: 800 });
            await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36');
            
            page.setDefaultTimeout(30000);
            page.setDefaultNavigationTimeout(30000);
            
            await page.setRequestInterception(true);
            page.on('request', (req) => {
                const resourceType = req.resourceType();
                const url = req.url();
                
                if (['image', 'font', 'media', 'stylesheet'].includes(resourceType)) {
                    req.abort();
                } else if (url.includes('google-analytics') || 
                          url.includes('gtag') || 
                          url.includes('facebook') ||
                          url.includes('twitter') ||
                          url.includes('linkedin')) {
                    req.abort();
                } else {
                    req.continue();
                }
            });
            
            page.on('error', (err) => {
                console.log(`${new Date().toISOString()} Page error: ${err.message}`);
            });
            
            page.on('pageerror', (err) => {
                console.log(`${new Date().toISOString()} Page script error: ${err.message}`);
            });
            
        }, 'Page setup');
        
        // Login process with retry
        await withRetry(async () => {
            console.log(`${new Date().toISOString()} Navigating to signin page: ${N8N_URL}/signin`);
            
            await page.goto(`${N8N_URL}/signin`, { 
                waitUntil: 'domcontentloaded',
                timeout: 45000
            });
            
            await page.waitForTimeout(3000);
            console.log(`${new Date().toISOString()} Page loaded, looking for login form...`);
            
            let emailInput = null;
            let passwordInput = null;
            
            const emailSelectors = [
                'input[type="email"]',
                'input[name="email"]',
                'input[id*="email"]',
                'input[placeholder*="email"]',
                'input[autocomplete="email"]'
            ];
            
            for (const selector of emailSelectors) {
                try {
                    emailInput = await page.waitForSelector(selector, {
                        timeout: 5000,
                        visible: true
                    });
                    if (emailInput) {
                        console.log(`${new Date().toISOString()} Email input found with: ${selector}`);
                        break;
                    }
                } catch (e) {
                    console.log(`${new Date().toISOString()} Email selector ${selector} not found`);
                }
            }
            
            const passwordSelectors = [
                'input[type="password"]',
                'input[name="password"]',
                'input[id*="password"]',
                'input[placeholder*="password"]',
                'input[autocomplete*="password"]'
            ];
            
            for (const selector of passwordSelectors) {
                try {
                    passwordInput = await page.waitForSelector(selector, {
                        timeout: 5000,
                        visible: true
                    });
                    if (passwordInput) {
                        console.log(`${new Date().toISOString()} Password input found with: ${selector}`);
                        break;
                    }
                } catch (e) {
                    console.log(`${new Date().toISOString()} Password selector ${selector} not found`);
                }
            }
            
            if (!emailInput || !passwordInput) {
                throw new Error('Login form elements not found');
            }
            
            console.log(`${new Date().toISOString()} Filling login form...`);
            
            await emailInput.click({ clickCount: 3 });
            await page.waitForTimeout(500);
            await emailInput.type(EMAIL, { delay: 100 });
            
            await passwordInput.click({ clickCount: 3 });
            await page.waitForTimeout(500);
            await passwordInput.type(PASSWORD, { delay: 100 });
            
            console.log(`${new Date().toISOString()} Form filled, submitting...`);
            
            await Promise.all([
                page.waitForNavigation({ 
                    waitUntil: 'domcontentloaded',
                    timeout: 30000 
                }),
                passwordInput.press('Enter')
            ]);
            
            console.log(`${new Date().toISOString()} Login completed successfully`);
            
        }, 'Login process');
        
        await withRetry(async () => {
            console.log(`${new Date().toISOString()} Navigating to API settings...`);
            
            await page.goto(`${N8N_URL}/settings/api`, {
                waitUntil: 'domcontentloaded',
                timeout: 45000
            });
            
            await page.waitForTimeout(5000);
            console.log(`${new Date().toISOString()} API settings page loaded`);
            
        }, 'API settings navigation');
        
        const apiKey = await withRetry(async () => {
            console.log(`${new Date().toISOString()} Looking for create API key button...`);
            
            let createButton = null;
            
            const buttonSelectors = [
                'button[data-test-id*="create"]',
                'button[data-test-id*="api"]',
                'button:has-text("Create API key")',
                'button:has-text("Create API Key")', 
                'button:has-text("Create")',
                'button:has-text("Generate")',
                '.el-button--primary',
                'button.btn-primary',
                'button[type="submit"]',
                '[role="button"]:has-text("Create")'
            ];
            
            for (const selector of buttonSelectors) {
                try {
                    const elements = await page.$(selector);
                    for (const element of elements) {
                        const isVisible = await element.isIntersectingViewport();
                        if (isVisible) {
                            createButton = element;
                            console.log(`${new Date().toISOString()} Found visible button: ${selector}`);
                            break;
                        }
                    }
                    if (createButton) break;
                } catch (e) {
                    console.log(`${new Date().toISOString()} Button selector ${selector} failed: ${e.message}`);
                }
            }
            
            if (!createButton) {
                const buttons = await page.$('button, [role="button"]');
                console.log(`${new Date().toISOString()} Scanning ${buttons.length} buttons for create text...`);
                
                for (const button of buttons) {
                    try {
                        const text = await button.evaluate(el => el.textContent?.toLowerCase() || '');
                        const isVisible = await button.isIntersectingViewport();
                        
                        if (isVisible && (text.includes('create') || text.includes('generate') || text.includes('api'))) {
                            createButton = button;
                            console.log(`${new Date().toISOString()} Found button by text: "${text}"`);
                            break;
                        }
                    } catch (e) {
                        // Skip this button
                    }
                }
            }
            
            if (!createButton) {
                throw new Error('Create API key button not found');
            }
            
            console.log(`${new Date().toISOString()} Clicking create button...`);
            
            await createButton.scrollIntoView();
            await page.waitForTimeout(1000);
            
            await createButton.click();
            console.log(`${new Date().toISOString()} Button clicked, waiting for API key...`);
            
            await page.waitForTimeout(8000);
            
            let apiKey = null;
            
            const keySelectors = [
                'code',
                'pre',
                'input[readonly]',
                'textarea[readonly]',
                '[data-test*="api-key"]',
                '[data-test*="token"]',
                '.api-key',
                '.token',
                '.el-input__inner[readonly]',
                'span[style*="font-family: monospace"]',
                '[class*="monospace"]',
                '[class*="code"]'
            ];
            
            console.log(`${new Date().toISOString()} Searching for API key...`);
            
            for (const selector of keySelectors) {
                try {
                    const elements = await page.$(selector);
                    console.log(`${new Date().toISOString()} Found ${elements.length} elements for ${selector}`);
                    
                    for (const element of elements) {
                        const text = await element.evaluate(el => {
                            return el.textContent || el.value || el.getAttribute('value') || '';
                        });
                        
                        const cleanText = text.trim();
                        if (cleanText && 
                            cleanText.length > 25 && 
                            cleanText.length < 200 &&
                            /^[a-zA-Z0-9_.-]{25,}$/.test(cleanText)) {
                            apiKey = cleanText;
                            console.log(`${new Date().toISOString()} Found API key with ${selector} (length: ${apiKey.length})`);
                            return apiKey;
                        }
                    }
                } catch (e) {
                    console.log(`${new Date().toISOString()} Selector ${selector} failed: ${e.message}`);
                }
            }
            
            if (!apiKey) {
                console.log(`${new Date().toISOString()} Scanning entire page content...`);
                const pageContent = await page.content();
                const matches = pageContent.match(/[a-zA-Z0-9_.-]{30,80}/g);
                
                if (matches && matches.length > 0) {
                    const candidates = matches.filter(match => 
                        match.length > 25 && 
                        match.length < 200 &&
                        !match.includes('http') &&
                        !match.includes('www')
                    );
                    
                    if (candidates.length > 0) {
                        apiKey = candidates.reduce((longest, current) => 
                            current.length > longest.length ? current : longest
                        );
                        console.log(`${new Date().toISOString()} Found API key from page scan (length: ${apiKey.length})`);
                    }
                }
            }
            
            if (!apiKey) {
                throw new Error('Could not extract API key from page');
            }
            
            return apiKey;
            
        }, 'API key creation');
        
        console.log(`${new Date().toISOString()} SUCCESS: API Key extracted!`);
        console.log(`${new Date().toISOString()} Length: ${apiKey.length}`);
        console.log(`${new Date().toISOString()} Preview: ${apiKey.substring(0, 12)}...`);
        
        fs.writeFileSync('/work/n8n-api-key.txt', apiKey);
        console.log(`${new Date().toISOString()} API key saved to file`);
        
        return apiKey;
        
    } catch (error) {
        console.error(`${new Date().toISOString()} FINAL ERROR: ${error.message}`);
        console.error(`${new Date().toISOString()} Stack: ${error.stack}`);
        throw error;
        
    } finally {
        console.log(`${new Date().toISOString()} Starting cleanup...`);
        
        if (page && !page.isClosed()) {
            try {
                page.removeAllListeners();
                await page.close();
                console.log(`${new Date().toISOString()} Page closed successfully`);
            } catch (e) {
                console.log(`${new Date().toISOString()} Page close warning: ${e.message}`);
            }
        }
        
        if (browser && browser.connected) {
            try {
                await browser.close();
                console.log(`${new Date().toISOString()} Browser closed successfully`);
            } catch (e) {
                console.log(`${new Date().toISOString()} Browser close warning: ${e.message}`);
            }
        }
        
        console.log(`${new Date().toISOString()} Cleanup completed`);
    }
}

process.on('unhandledRejection', (reason, promise) => {
    console.error(`${new Date().toISOString()} Unhandled Rejection at:`, promise, 'reason:', reason);
    process.exit(1);
});

process.on('uncaughtException', (error) => {
    console.error(`${new Date().toISOString()} Uncaught Exception:`, error);
    process.exit(1);
});

const timeoutId = setTimeout(() => {
    console.error(`${new Date().toISOString()} Script timeout after 5 minutes`);
    process.exit(1);
}, 300000);

createApiKey()
    .then((apiKey) => {
        clearTimeout(timeoutId);
        console.log(`${new Date().toISOString()} FINAL SUCCESS: API key created (${apiKey.length} chars)`);
        process.exit(0);
    })
    .catch(error => {
        clearTimeout(timeoutId);
        console.error(`${new Date().toISOString()} FINAL ERROR: ${error.message}`);
        process.exit(1);
    });
ENHANCED_EOF
    
    log_info "✅ Enhanced automation script created: /work/create-api-key.js"
}

# Enhanced validation function
validate_result() {
    local key_file="/work/n8n-api-key.txt"
    
    if [ ! -f "$key_file" ]; then
        log_error "API key file not created: $key_file"
        log_info "Listing /work contents:"
        ls -la /work/ || true
        return 1
    fi
    
    local key_length
    key_length=$(wc -c < "$key_file" 2>/dev/null || echo "0")
    local key_preview
    key_preview=$(head -c 12 "$key_file" 2>/dev/null || echo "")
    
    log_info "🎉 SUCCESS!"
    log_info "File: $key_file"
    log_info "Length: $key_length chars"
    log_info "Preview: ${key_preview}..."
    
    # Validate key format and length
    if [ "$key_length" -lt 25 ]; then
        log_error "API key too short: $key_length chars (expected: 25+ chars)"
        return 1
    fi
    
    # Check if key contains valid characters
    local key_content
    key_content=$(cat "$key_file" 2>/dev/null || echo "")
    
    if [[ ! "$key_content" =~ ^[a-zA-Z0-9_.-]{25,}$ ]]; then
        log_error "API key format appears invalid"
        log_info "Key content preview: ${key_content:0:20}..."
        return 1
    fi
    
    log_info "✅ API key validation passed"
    return 0
}

# Enhanced main execution with comprehensive error handling
main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "=== Enhanced Container-Optimized N8N API Key Generation ==="
    log_info "Start time: $(date -Iseconds)"
    
    # Trap for cleanup on exit
    trap 'log_info "Script interrupted, cleaning up..."; exit 130' INT TERM
    
    # Step 1: Environment validation
    check_env_vars
    
    # Step 2: System requirements check
    check_system_requirements
    
    # Step 3: N8N availability check
    if ! wait_for_n8n; then
        log_error "N8N not available, aborting"
        exit 1
    fi
    
    # Step 4: Owner setup
    if ! setup_owner; then
        log_warn "Owner setup had issues, but continuing..."
    fi
    
    # Step 5: Create enhanced automation script
    create_enhanced_automation_script
    
    # Step 6: Environment info
    log_info "Environment Information:"
    log_info "Node version: $(node --version)"
    log_info "PUPPETEER_EXECUTABLE_PATH: ${PUPPETEER_EXECUTABLE_PATH:-not set}"
    log_info "Available memory: $(free -m | awk 'NR==2{print $7}')MB"
    log_info "Working directory contents:"
    ls -la /work/ || true
    
    # Step 7: Execute automation with enhanced monitoring
    log_info "🕐 Starting enhanced automation: $(date -Iseconds)"
    
    cd /work
    
    # Set resource limits
    ulimit -v 1048576 2>/dev/null || true  # 1GB virtual memory limit
    
    # Run with comprehensive timeout and monitoring
    local automation_pid
    local exit_code=0
    
    # Start automation in background to monitor it
    timeout 420 node create-api-key.js &  # 7 minutes timeout
    automation_pid=$!
    
    # Monitor the process
    while kill -0 $automation_pid 2>/dev/null; do
        sleep 5
        log_info "Automation running (PID: $automation_pid)..."
    done
    
    # Get exit code
    wait $automation_pid
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_info "✅ Automation completed successfully"
    elif [ $exit_code -eq 124 ]; then
        log_error "❌ Automation timed out after 7 minutes"
        exit 1
    else
        log_error "❌ Automation failed with exit code: $exit_code"
        exit 1
    fi
    
    # Step 8: Validate result
    if ! validate_result; then
        log_error "Result validation failed"
        exit 1
    fi
    
    # Step 9: Success summary
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "🎉 COMPLETE SUCCESS!"
    log_info "Total execution time: ${duration} seconds"
    log_info "API key successfully generated and saved to /work/n8n-api-key.txt"
    
    exit 0
}

# Execute main function with all arguments
main "$@"
