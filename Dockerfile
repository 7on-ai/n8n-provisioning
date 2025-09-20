# Dockerfile: n8n-provisioner (ลบ 8man - ใช้ Internal REST API)
FROM alpine:3.18

# ติดตั้งเครื่องมือที่จำเป็น (ไม่ต้องการ Node.js/npm)
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates

# ตั้ง working directory
WORKDIR /work

# Copy script เข้า image
COPY work/generate-api-key.sh /work/

# ให้ script สามารถรันได้
RUN chmod +x /work/generate-api-key.sh

# ENTRYPOINT เป็น sh -c เพื่อให้ Northflank custom command ทำงานได้
ENTRYPOINT ["/bin/sh", "-c"]

# คำสั่ง default
CMD ["echo 'n8n-provisioner ready (Internal REST API method)'"]
