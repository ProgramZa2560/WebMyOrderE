# WebMyOrderE — เว็บควบคุม Order แยกเครื่อง

แยก **แผงระยะไกล** (เดิมพอร์ต 8770 ในแอป Order) ออกมาไว้อีกเครื่อง เปิดจากเบราว์เซอร์ได้ทุกที่ (มือถือ/คอมไหนก็ได้)

```
เบราว์เซอร์ (ที่ไหนก็ได้) ──https──▶ เครื่องเว็บ (repo นี้) ◀──ต่อออกเอง── แอป Order (เครื่องร้าน)
```

- แอป Order **ต่อออกไปหา**เครื่องเว็บเอง (long-poll) → เครื่องร้านไม่ต้องเปิดพอร์ต/ไม่ต้องรัน tunnel
- หน้าเว็บ = แผงเดียวกับในแอป (แอปส่งมาให้ตอนเชื่อม → ตรงเวอร์ชันแอปเสมอ)
- รหัสผ่านเว็บ = `key` เดิมใน `web.json` ของแอป; แอปยืนยันตัวกับเครื่องเว็บด้วย `agentKey`
- ไม่มี dependency (Node ≥ 20 อย่างเดียว)

## 1) ติดตั้งบนเครื่องเว็บ (Mac อีกเครื่อง)

```bash
brew install node cloudflared
git clone https://github.com/ProgramZa2560/WebMyOrderE.git
cd WebMyOrderE
zsh install.sh
```

`install.sh` จะลง launchd (เปิดเองตอนล็อกอิน + ล่มแล้วเปิดใหม่) แล้วพิมพ์:
- **URL เว็บ** (เช่น `https://xxxx.trycloudflare.com`)
- **relayKey** (= `agentKey` ใน `config.json`)

### URL ถาวร (แนะนำ)
quick tunnel ของ cloudflared เปลี่ยน URL ทุกครั้งที่รีสตาร์ท → ต้องไปแก้ `relayUrl` ในแอปทุกครั้ง
ใช้ Cloudflare named tunnel แทน: สร้าง tunnel ใน Cloudflare Zero Trust ชี้ service `http://127.0.0.1:8780`
แล้วสร้างไฟล์ `.env` (ดู `.env.example`):

```
CF_TOKEN=<token ของ tunnel>
CF_HOST=order.yourdomain.com
```

แล้วรัน `zsh install.sh` อีกรอบ

## 2) ตั้งค่าแอป Order (เครื่องร้าน)

แก้ `~/Library/Application Support/Order/web.json` เพิ่ม 2 ค่า (คง `key` เดิมไว้):

```json
{ "key": "…เดิม…", "relayUrl": "https://order.yourdomain.com", "relayKey": "<relayKey จากข้อ 1>" }
```

ปิด-เปิดแอป Order → ปุ่ม 🌐 ในแผงจะแสดงลิงก์ของเครื่องเว็บ (`https://…/?k=รหัส`)
มี `relayUrl` แล้ว แอปจะไม่เปิด tunnel ของตัวเอง (ลบ 2 ค่านี้ = กลับไปแบบเดิม)

> ต้องใช้แอป Order เวอร์ชันที่มี `startRelay()` ใน `order-app/main.js` (repo MyOrderAuto)

## ตรวจสถานะ

```bash
curl -s http://127.0.0.1:8780/health     # {"ok":true,"appOnline":true,"version":"1.0.73",…}
tail -f web.log
```

| อาการ | วิธี |
|---|---|
| หน้าเว็บขึ้น "แอป Order ยังไม่ออนไลน์" | เปิดแอปบนเครื่องร้าน / ตรวจ `relayUrl` `relayKey` ใน web.json |
| 🌐 ในแอปขึ้น "relayKey ไม่ถูก" | คัดลอก `agentKey` จาก `config.json` เครื่องเว็บใหม่ |
| URL เปลี่ยนเอง | ใช้ named tunnel (ด้านบน) |
| ถาม "รหัสผ่านเว็บควบคุม" | ใช้ `key` ใน web.json ของแอป (หรือเปิดลิงก์จากปุ่ม 🌐 ที่มี `?k=`) |

## ถอนการติดตั้ง

```bash
launchctl unload ~/Library/LaunchAgents/th.myorder.webmyordere.plist && rm ~/Library/LaunchAgents/th.myorder.webmyordere.plist
```

## ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `server.js` | relay: `/` หน้าแผง, `/rpc` เบราว์เซอร์, `/agent/*` แอป Order, `/health` |
| `start.sh` | รัน server + cloudflared |
| `install.sh` | ติดตั้ง launchd + สร้าง `agentKey` |
| `config.json` | `agentKey` (สร้างเอง, ไม่อยู่ใน git) |
