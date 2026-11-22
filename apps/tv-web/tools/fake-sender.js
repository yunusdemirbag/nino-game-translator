// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Geliştirme ve test için sahte gönderici (Mac/telefon yerine). Ek kütüphane kullanmaz.
//   - Nino Bağlantı Protokolü, ters arama: GET /nino/info, GET /nino/ws (WebSocket; bağlanınca hello yollar)
//   - Eski gönderici: GET /hello, GET /events (Server-Sent Events)
//   - Denetim: POST /send  {"type": "show", ...}  → protokol istemcilerine aynen, eski istemcilere olay olarak
//   - Testler için: pingMs (yeni protokolde ping aralığı), legacyPingMs, noHello (el sıkışmayı hiç başlatma),
//     mute() (açık bağlantılara artık hiçbir şey yazma ama kapatma: "sessizce bırakan" gönderici)
//
// Komut satırı: node apps/tv-web/tools/fake-sender.js [port]   (varsayılan 47800)
'use strict';

const http = require('node:http');
const crypto = require('node:crypto');

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function frame(text) {
  const payload = Buffer.from(text, 'utf8');
  let head;
  if (payload.length < 126) head = Buffer.from([0x81, payload.length]);
  else if (payload.length < 65536) { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 126; head.writeUInt16BE(payload.length, 2); }
  else { head = Buffer.alloc(10); head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(payload.length), 2); }
  return Buffer.concat([head, payload]);
}

// İstemci çerçevelerini (maskeli) çözer; tamamlanmış metin mesajlarını döner.
function reader(onText, onClose) {
  let buf = Buffer.alloc(0);
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const op = buf[0] & 0x0f;
      let len = buf[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const masked = (buf[1] & 0x80) !== 0;
      const need = off + (masked ? 4 : 0) + len;
      if (buf.length < need) return;
      let data = buf.subarray(off + (masked ? 4 : 0), need);
      if (masked) {
        const mask = buf.subarray(off, off + 4);
        data = Buffer.from(data.map((b, i) => b ^ mask[i % 4]));
      }
      buf = buf.subarray(need);
      if (op === 0x1) onText(data.toString('utf8'));
      else if (op === 0x8) return onClose();
    }
  };
}

const LEGACY = { show: 'subtitle', clear: 'clear' };

function start(port, options = {}) {
  const sockets = new Set();
  let connections = 0;
  const streams = new Set();
  const received = [];
  const name = options.name || 'Sahte Mac';

  function sendAll(message) {
    const text = JSON.stringify(Object.assign({ app: 'nino' }, message));
    for (const s of sockets) if (s.ready && !s.muted) s.write(frame(text));
    const event = LEGACY[message.type] || message.type;
    const data = Object.assign({}, message);
    delete data.app; delete data.type;
    if (message.type === 'show' && message.durationMs) data.duration = message.durationMs;
    for (const r of streams) if (!r.muted) r.write('event: ' + event + '\ndata: ' + JSON.stringify(data) + '\n\n');
  }

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    res.setHeader('Access-Control-Allow-Origin', '*');
    if (url.pathname === '/nino/info') {
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ app: 'nino', type: 'info', version: 1, versions: [1], name, id: 'sahte', role: 'sender' }));
    }
    if (url.pathname === '/hello') return res.end('nino');
    if (url.pathname === '/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
      res.write(': merhaba\n\n');
      streams.add(res);
      connections++;
      const ping = setInterval(() => { if (!res.muted) res.write('event: ping\ndata: {}\n\n'); }, options.legacyPingMs || 15000);
      req.on('close', () => { clearInterval(ping); streams.delete(res); });
      return;
    }
    if (url.pathname === '/send' && req.method === 'POST') {
      let body = '';
      req.on('data', (c) => { body += c; });
      req.on('end', () => {
        try { sendAll(JSON.parse(body)); res.end('ok'); } catch (e) { res.statusCode = 400; res.end(String(e)); }
      });
      return;
    }
    res.statusCode = 404;
    res.end();
  });

  server.on('upgrade', (req, socket) => {
    if (new URL(req.url, 'http://x').pathname !== '/nino/ws') return socket.destroy();
    const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + WS_GUID).digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
    sockets.add(socket);
    socket.on('data', reader((text) => {
      const msg = JSON.parse(text);
      received.push(msg);
      if (msg.type === 'welcome') socket.ready = true;
    }, () => socket.end()));
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => sockets.delete(socket));
    connections++;
    if (options.pingMs) {
      const timer = setInterval(() => {
        if (socket.ready && !socket.muted) socket.write(frame(JSON.stringify({ app: 'nino', type: 'ping', t: Date.now() })));
      }, options.pingMs);
      socket.on('close', () => clearInterval(timer));
    }
    if (options.noHello) return;
    socket.write(frame(JSON.stringify({ app: 'nino', type: 'hello', version: options.version || 1, device: 'Mac', client: 'nino-sahte/1' })));
  });

  return new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, () => resolve({
    port: server.address().port,
    send: sendAll,
    received,
    clients: () => sockets.size + streams.size,
    connections: () => connections,
    mute: () => { for (const x of sockets) x.muted = true; for (const x of streams) x.muted = true; },
    close: () => new Promise((r) => {
      for (const s of sockets) s.destroy();
      for (const e of streams) e.end();
      server.close(r);
    })
  })); });
}

module.exports = { start };

if (require.main === module) {
  const port = Number(process.argv[2] || 47800);
  start(port, { pingMs: 5000 }).then((s) => console.log('Sahte gönderici: http://localhost:' + s.port + '  (POST /send ile mesaj)'));
}
