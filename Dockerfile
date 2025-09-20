# Dockerfile: n8n-provisioner (Alpine with curl, jq, bash)
FROM alpine:3.18

# ติดตั้งเครื่องมือที่ต้องการ (curl, jq, bash)
RUN apk add --no-cache curl jq bash

# ตั้ง working dir (ไม่จำเป็นแต่ทำให้อ่านง่าย)
WORKDIR /work

# ENTRYPOINT เป็น sh -c เพื่อให้ Northflank custom command ทำงานได้
ENTRYPOINT ["/bin/sh", "-c"]

# คำสั่ง default (จะถูก override โดย Northflank custom command)
CMD ["echo 'n8n-provisioner image ready'"]
