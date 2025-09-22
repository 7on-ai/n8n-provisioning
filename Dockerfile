# Enhanced Dockerfile for stable Puppeteer execution in containers
FROM node:18-bullseye-slim

# Install essential dependencies and Chromium
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core system packages
    ca-certificates \
    curl \
    jq \
    bash \
    dumb-init \
    procps \
    # Chromium and browser dependencies
    chromium \
    chromium-sandbox \
    # Font and rendering support
    fonts-liberation \
    fonts-dejavu-core \
    fontconfig \
    # Essential browser libraries
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
    libxkbcommon0 \
    # Additional stability packages
    lsb-release \
    xdg-utils \
    # Memory management tools
    && echo "kernel.unprivileged_userns_clone=1" >> /etc/sysctl.conf \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for better security
RUN groupadd -r automation && useradd -r -g automation -G audio,video automation \
    && mkdir -p /work \
    && chown -R automation:automation /work

# Set workdir
WORKDIR /work

# Environment variables for Puppeteer optimization
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_ARGS="--no-sandbox --disable-setuid-sandbox" \
    NODE_ENV=production \
    NODE_OPTIONS="--max-old-space-size=512" \
    DEBIAN_FRONTEND=noninteractive \
    # Memory and performance tuning
    NODE_MAX_OLD_SPACE_SIZE=512 \
    UV_THREADPOOL_SIZE=4

# Install Node.js dependencies as root first
RUN npm init -y \
    && npm install puppeteer@21 --omit=dev --no-audit --no-fund \
    && npm prune --production \
    && npm cache clean --force

# Copy scripts and set permissions
COPY work/generate-api-key.sh /work/
RUN chmod +x /work/generate-api-key.sh \
    && chown -R automation:automation /work

# Switch to non-root user
USER automation

# Create directories with proper permissions
RUN mkdir -p /work/screenshots /work/logs \
    && chmod 755 /work/screenshots /work/logs

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "console.log('Container healthy')" || exit 1

# Use dumb-init for proper signal handling
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# Default command
CMD ["echo", "n8n-provisioner ready (Enhanced Browser Automation)"]
