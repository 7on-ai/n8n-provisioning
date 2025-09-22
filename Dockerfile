# Dockerfile (Debian slim) - Recommended for Puppeteer
FROM node:18-bullseye-slim

# Install Chromium and all required dependencies for Puppeteer
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    ca-certificates \
    fonts-liberation \
    libnss3 \
    libxss1 \
    libasound2 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libappindicator3-1 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    lsb-release \
    xdg-utils \
    dumb-init \
    curl \
    jq \
    bash \
 && rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /work

# Puppeteer config (skip Chromium download, use system-installed Chromium)
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    NODE_ENV=production

# Install puppeteer (system Chromium will be used)
RUN npm init -y \
 && npm install puppeteer@21 --omit=dev --no-audit --no-fund \
 && npm prune --production

# Copy script
COPY work/generate-api-key.sh /work/
RUN chmod +x /work/generate-api-key.sh

# Entrypoint
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Default CMD
CMD ["echo", "n8n-provisioner ready (Browser Automation method)"]
