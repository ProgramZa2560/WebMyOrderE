#!/bin/zsh
# ติดตั้งให้เปิดเองตอนล็อกอิน (launchd) — รันซ้ำได้
set -e
cd "${0:A:h}"
DIR="$PWD"
command -v node >/dev/null || { echo "ต้องมี node ≥ 20: brew install node"; exit 1; }
command -v cloudflared >/dev/null || echo "⚠️ ยังไม่มี cloudflared → brew install cloudflared (ไม่งั้นเปิดได้แค่ในเครื่อง)"
chmod +x start.sh
[ -f config.json ] || node -e "require('fs').writeFileSync('config.json',JSON.stringify({agentKey:require('crypto').randomBytes(18).toString('base64url')},null,2),{mode:0o600})"   # agentKey
PL=~/Library/LaunchAgents/th.myorder.webmyordere.plist
sed "s#__DIR__#$DIR#g" th.myorder.webmyordere.plist > "$PL"
launchctl unload "$PL" 2>/dev/null || true
launchctl load "$PL"
sleep 6
echo "✅ ติดตั้งแล้ว (log: $DIR/web.log)"
echo "URL เว็บ : $(cat url.txt 2>/dev/null || echo 'รอ tunnel… ดู web.log')"
echo "relayKey : $(node -p "require('./config.json').agentKey")"
