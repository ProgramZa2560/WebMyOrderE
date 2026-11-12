#!/bin/zsh
# เปิดเว็บ (relay) + tunnel ให้เปิดได้ทุกที่
#   CF_TOKEN + CF_HOST ใน .env  → Cloudflare named tunnel (URL ถาวร, แนะนำ)
#   ไม่ตั้ง                     → cloudflared quick tunnel (URL เปลี่ยนทุกครั้ง → ต้องแก้ relayUrl ในแอป)
cd "${0:A:h}"
[ -f .env ] && set -a && . ./.env && set +a
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT="${PORT:-8780}"

# อัปเดต relayUrl ใน web.json ของแอป Order ที่รันอยู่เครื่องเดียวกัน (ถ้ามี) — แอป 1.0.81 อ่านซ้ำเองตอน hello ล้ม จึงต่อใหม่ได้เองโดยไม่ต้องรีสตาร์ท
SYNCWEB='const fs=require("fs");const f=process.env.HOME+"/Library/Application Support/Order/web.json";try{const j=JSON.parse(fs.readFileSync(f,"utf8"));if(j.relayUrl&&j.relayUrl!==process.argv[1]){j.relayUrl=process.argv[1];fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n");console.log("web.json relayUrl → "+j.relayUrl)}}catch(e){}'
syncweb() { [ -f "$HOME/Library/Application Support/Order/web.json" ] && node -e "$SYNCWEB" "$1"; return 0; }

node server.js &
SRV=$!
trap 'kill $SRV $TUN 2>/dev/null' EXIT INT TERM

if ! command -v cloudflared >/dev/null; then
  echo "ไม่มี cloudflared (brew install cloudflared) — เปิดได้เฉพาะ http://127.0.0.1:$PORT"
  wait $SRV; exit
fi
if [ -n "$CF_TOKEN" ] && [ -n "$CF_HOST" ]; then
  # (1.0.99-start.sh) cloudflared ตาย (เน็ตหลุด/sleep) = relay หลอกว่ารันอยู่แต่เข้าไม่ได้เลย → วนปลุกใหม่ทุก 5 วิ (เดิมปล่อยตายเงียบ)
  while :; do
    cloudflared tunnel --no-autoupdate run --token "$CF_TOKEN" > /dev/null 2>&1
    echo "cloudflared (named) หยุด ($(date '+%H:%M:%S')) — ปลุกใหม่ใน 5 วิ"
    sleep 5
  done &
  TUN=$!
  echo "https://$CF_HOST" > url.txt
  echo "เว็บ: https://$CF_HOST"
  syncweb "https://$CF_HOST"
  # (named tunnel) URL ถาวร — อัปเดตลิงก์ถาวร (link.json) เมื่อเปลี่ยนโดเมนเท่านั้น
  if ! grep -q "https://$CF_HOST" link.json 2>/dev/null; then
    node -e "const fs=require('fs');fs.writeFileSync('link.json',JSON.stringify({url:process.argv[1],ts:Date.now()})+'\n')" "https://$CF_HOST"
    git pull --rebase -q 2>/dev/null
    git add link.json && git commit -qm link && git push -q 2>/dev/null || echo "⚠️ push link.json ไม่สำเร็จ — ลิงก์ถาวรยังชี้ URL เก่า"
  fi
else
  while :; do
    cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" 2>&1 | while read -r l; do
      # URL จริงของ quick tunnel = hostname หลายคำมีขีด — 'api.trycloudflare.com' ในบรรทัด error ห้ามจับ
      u=$(echo "$l" | grep -oE 'https://[a-z0-9]+-[a-z0-9-]+\.trycloudflare\.com' | head -1)
      if [ -n "$u" ] && [ "$u" != "$(cat url.txt 2>/dev/null)" ]; then
        echo "$u" > url.txt
        echo "เว็บ: $u  (ใส่เป็น relayUrl ในแอป)"
        syncweb "$u"
        # อัปเดตลิงก์ถาวร (GitHub Pages อ่าน link.json แล้วพาไป tunnel ล่าสุด)
        git pull --rebase -q 2>/dev/null
        node -e "const fs=require('fs');fs.writeFileSync('link.json',JSON.stringify({url:process.argv[1],ts:Date.now()})+'\n')" "$u"
        git add link.json && git commit -qm link && git push -q 2>/dev/null || echo "⚠️ push link.json ไม่สำเร็จ — ลิงก์ถาวรยังชี้ URL เก่า"
      fi
    done
    echo "cloudflared หยุด ($(date '+%H:%M:%S')) — ปลุกใหม่ใน 30 วิ"
    sleep 30
  done &
  TUN=$!
fi
wait $SRV
