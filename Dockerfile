# Dockerfile: n8n-provisioner (Browser Automation Method)
FROM node:18-alpine

# ติดตั้งเครื่องมือที่จำเป็น
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    chromium \
    nss \
    freetype \
    harfbuzz

# ตั้ง environment สำหรับ Puppeteer
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# ตั้ง working directory
WORKDIR /work

# Copy script เข้า image
COPY work/generate-api-key.sh /work/

# ให้ script สามารถรันได้
RUN chmod +x /work/generate-api-key.sh

# ENTRYPOINT เป็น sh -c เพื่อให้ Northflank custom command ทำงานได้
ENTRYPOINT ["/bin/sh", "-c"]

# คำสั่ง default
CMD ["echo 'n8n-provisioner ready (Browser Automation method)'"]
