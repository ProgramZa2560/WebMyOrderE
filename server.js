// WebMyOrderE — เว็บควบคุม Order (แผงระยะไกล) แยกเครื่อง
// เบราว์เซอร์ ──/rpc──▶ เครื่องนี้ (relay) ◀──long-poll── แอป Order (อีกเครื่อง, ต่อออกมาเอง ไม่ต้องเปิดพอร์ตฝั่งแอป)
// ไม่มี dependency: Node ≥ 20
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');

const CFG_FILE = path.join(__dirname, 'config.json');
function loadCfg() {
  let c = {}; try { c = JSON.parse(fs.readFileSync(CFG_FILE, 'utf8')); } catch {}
  if (!c.agentKey) { c.agentKey = crypto.randomBytes(18).toString('base64url'); fs.writeFileSync(CFG_FILE, JSON.stringify(c, null, 2), { mode: 0o600 }); }
  return c;
}
const cfg = loadCfg();
const PORT = +process.env.PORT || cfg.port || 8780;
const HOST = process.env.HOST || cfg.host || '127.0.0.1';
const POLL_MS = 25000, RPC_MS = 60000, BODY_MAX = 1e6, OFFLINE_MS = 45000;

const safeEq = (a, b) => { const A = Buffer.from(String(a)), B = Buffer.from(String(b)); return A.length > 0 && A.length === B.length && crypto.timingSafeEqual(A, B); };

// สถานะแอปที่ต่อเข้ามา (มีได้ตัวเดียว)
let panelHtml = '', webKey = '', lastSeen = 0, version = '';
let queue = [];            // งานรอส่งให้แอป [{id, fn, args}]
let poller = null;         // response ของ /agent/poll ที่รออยู่
const pending = new Map(); // id → {res, gz, timer}

const online = () => Date.now() - lastSeen < OFFLINE_MS;
function flush() {
  if (!poller || !queue.length) return;
  const p = poller; poller = null; clearTimeout(p.timer);
  json(p.res, 200, queue.splice(0));
}
function json(res, code, obj, gz) {
  const out = JSON.stringify(obj);
  if (gz && out.length > 1024) { res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Encoding': 'gzip', 'Cache-Control': 'no-store' }); return res.end(zlib.gzipSync(out)); }
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(out);
}
function body(req) {
  return new Promise((ok, bad) => {
    let b = ''; req.on('data', c => { b += c; if (b.length > BODY_MAX * 20) { bad(new Error('too big')); req.destroy(); } });
    req.on('end', () => ok(b)); req.on('error', bad);
  });
}
const page = (code, msg) => `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Order</title><body style="font:16px system-ui;padding:24px;background:#111;color:#eee">${msg}<script>setTimeout(()=>location.reload(),5000)</script>`;

const server = http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];
  try {
    // ---- เบราว์เซอร์ ----
    if (req.method === 'GET' && url === '/') {
      if (!panelHtml || !online()) { res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); return res.end(page(503, '⏳ แอป Order ยังไม่ออนไลน์ — เปิดแอปบนเครื่องร้าน แล้วหน้านี้จะโหลดเอง')); }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' }); return res.end(panelHtml);
    }
    if (req.method === 'GET' && url === '/health') return json(res, 200, { ok: true, appOnline: online(), version, queued: queue.length, waiting: pending.size });
    if (req.method === 'POST' && url === '/rpc') {
      if (!webKey || !safeEq(req.headers['x-key'] || '', webKey)) { res.writeHead(401); return res.end(); }
      const b = await body(req); if (b.length > BODY_MAX) { res.writeHead(413); return res.end(); }
      const { fn, args } = JSON.parse(b);
      if (typeof fn !== 'string') return json(res, 400, { v: 'คำสั่งไม่ถูกต้อง' });
      if (!online()) return json(res, 200, { v: fn === 'msg' ? '' : 'แอป Order ออฟไลน์ (เครื่องร้านปิด/เน็ตหลุด)' });
      const id = crypto.randomUUID(), gz = /gzip/.test(req.headers['accept-encoding'] || '');
      const timer = setTimeout(() => { pending.delete(id); json(res, 200, { v: 'แอป Order ไม่ตอบ (หมดเวลา)' }); }, RPC_MS);
      pending.set(id, { res, gz, timer });
      req.on('close', () => { if (res.writableEnded) return; clearTimeout(timer); pending.delete(id); queue = queue.filter(j => j.id !== id); });
      queue.push({ id, fn, args: Array.isArray(args) ? args : [] }); flush();
      return;
    }

    // ---- แอป Order (agent) ----
    if (url.startsWith('/agent/')) {
      if (!safeEq(req.headers['x-agent-key'] || '', cfg.agentKey)) { res.writeHead(401); return res.end(); }
      const b = await body(req);
      if (req.method === 'POST' && url === '/agent/hello') { // แอปส่งหน้าแผง (ตรงเวอร์ชันแอป) + รหัสผ่านเว็บ
        const j = JSON.parse(b);
        if (!j.html || !j.key) return json(res, 400, { error: 'html/key' });
        panelHtml = String(j.html); webKey = String(j.key); version = String(j.version || ''); lastSeen = Date.now();
        console.log(new Date().toISOString(), 'app online', version);
        return json(res, 200, { ok: true });
      }
      if (req.method === 'POST' && url === '/agent/poll') {
        if (!panelHtml) return json(res, 410, { error: 'hello first' }); // เซิร์ฟเวอร์เพิ่งรีสตาร์ท → แอปต้อง hello ใหม่
        lastSeen = Date.now();
        if (poller) { clearTimeout(poller.timer); json(poller.res, 200, []); }
        poller = { res, timer: setTimeout(() => { if (poller && poller.res === res) { poller = null; json(res, 200, []); } }, POLL_MS) };
        req.on('close', () => { if (poller && poller.res === res) { clearTimeout(poller.timer); poller = null; } });
        return flush();
      }
      if (req.method === 'POST' && url === '/agent/reply') {
        lastSeen = Date.now();
        for (const { id, v } of [].concat(JSON.parse(b))) {
          const p = pending.get(id); if (!p) continue;
          pending.delete(id); clearTimeout(p.timer); json(p.res, 200, { v }, p.gz);
        }
        return json(res, 200, { ok: true });
      }
    }
    res.writeHead(404); res.end();
  } catch (e) {
    if (!res.headersSent) json(res, 400, { v: 'ERR ' + e.message });
  }
});
server.listen(PORT, HOST, () => {
  console.log(`WebMyOrderE ฟังที่ http://${HOST}:${PORT}`);
  console.log(`agentKey (ใส่ใน web.json ของแอป Order เป็น relayKey) อยู่ในไฟล์ ${CFG_FILE}`);
});
