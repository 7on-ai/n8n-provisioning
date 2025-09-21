# Dockerfile (Debian slim) - Recommended for Puppeteer
FROM node:18-bullseye-slim

# Install chromium dependencies and chromium (or install google-chrome-stable if preferred)
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
    dumb-init \
    curl \
    jq \
    bash \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work

ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    NODE_ENV=production

RUN npm init -y \
 && npm install puppeteer@21 --omit=dev --no-audit --no-fund \
 && npm prune --production

COPY work/generate-api-key.sh /work/
RUN chmod +x /work/generate-api-key.sh

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["echo", "n8n-provisioner ready (Browser Automation method)"]
