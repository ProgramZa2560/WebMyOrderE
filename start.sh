#!/bin/zsh
# เปิดเว็บ (relay) + tunnel ให้เปิดได้ทุกที่
#   CF_TOKEN + CF_HOST ใน .env  → Cloudflare named tunnel (URL ถาวร, แนะนำ)
#   ไม่ตั้ง                     → cloudflared quick tunnel (URL เปลี่ยนทุกครั้ง → ต้องแก้ relayUrl ในแอป)
cd "${0:A:h}"
[ -f .env ] && set -a && . ./.env && set +a
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT="${PORT:-8780}"

node server.js &
SRV=$!
trap 'kill $SRV $TUN 2>/dev/null' EXIT INT TERM

if ! command -v cloudflared >/dev/null; then
  echo "ไม่มี cloudflared (brew install cloudflared) — เปิดได้เฉพาะ http://127.0.0.1:$PORT"
  wait $SRV; exit
fi
if [ -n "$CF_TOKEN" ] && [ -n "$CF_HOST" ]; then
  cloudflared tunnel --no-autoupdate run --token "$CF_TOKEN" &
  TUN=$!
  echo "https://$CF_HOST" > url.txt
  echo "เว็บ: https://$CF_HOST"
else
  cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" 2>&1 | while read -r l; do
    u=$(echo "$l" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
    [ -n "$u" ] && echo "$u" > url.txt && echo "เว็บ: $u  (ใส่เป็น relayUrl ในแอป)"
  done &
  TUN=$!
fi
wait $SRV
