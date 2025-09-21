# Dockerfile: n8n-provisioner (Browser Automation Method)
FROM node:18-alpine

# ติดตั้งเครื่องมือและไลบรารีที่ Puppeteer + Chromium ต้องใช้
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ttf-freefont \
    udev \
    dumb-init \
    && rm -rf /var/cache/apk/*

# ตั้ง environment สำหรับ Puppeteer
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    PUPPETEER_PRODUCT=chrome \
    NODE_PATH=/usr/local/lib/node_modules

# ตั้ง working directory
WORKDIR /work

# Copy script เข้า image
COPY work/generate-api-key.sh /work/

# ให้ script สามารถรันได้
RUN chmod +x /work/generate-api-key.sh

# ใช้ dumb-init เป็น entrypoint เพื่อจัดการ signal ได้ถูกต้อง
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# คำสั่ง default (จะแทนที่ด้วย custom command บน Northflank ได้)
CMD ["echo", "n8n-provisioner ready (Browser Automation method)"]
