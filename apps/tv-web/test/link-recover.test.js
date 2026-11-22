// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Kopmadan kurtulma (saha hatası, Samsung Tizen 8 + eski 8787 düzeni, 22 Kasım 2026: altyazı bir süre geliyor, sonra
// TV takılıyor ve geri bağlanmıyordu). Gönderici bağlantıyı sessizce bırakınca, el sıkışma asılı kalınca ya da
// uygulama öne gelince TV kendisi yeniden bağlanmalı.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
require('../src/js/protocol.js');
require('../src/js/link.js');
const sender = require('../tools/fake-sender.js');

// Node'da EventSource yok: testin ihtiyacı kadar küçük bir karşılığı (yalnız olay adı + data satırı).
class MiniEventSource {
  constructor(url) {
    this.readyState = 0;
    this.listeners = {};
    this.req = http.get(url, (res) => {
      this.readyState = 1;
      if (this.onopen) this.onopen();
      let buf = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        buf += chunk;
        let cut;
        while ((cut = buf.indexOf('\n\n')) >= 0) {
          const block = buf.slice(0, cut);
          buf = buf.slice(cut + 2);
          const name = (/^event: (.*)$/m.exec(block) || [])[1];
          const data = (/^data: (.*)$/m.exec(block) || [])[1];
          if (name) (this.listeners[name] || []).forEach((fn) => fn({ data }));
        }
      });
      res.on('end', () => { this.readyState = 2; if (this.onerror) this.onerror(); });
    });
    this.req.on('error', () => { this.readyState = 2; if (this.onerror) this.onerror(); });
  }
  addEventListener(name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); }
  close() { this.readyState = 2; this.req.destroy(); }
}

const FAST = { dropMs: 300, backoff: [100], silenceMs: 600, connectMs: 600, legacySilenceMs: 600, legacyStuckMs: 600, watchMs: 100 };

function makeLink(timing = FAST, env = {}) {
  const seen = { status: [], drops: [], commands: [] };
  const link = new globalThis.Nino.Link({
    env: Object.assign({ WebSocket: globalThis.WebSocket, EventSource: MiniEventSource, setTimeout, clearTimeout, setInterval, clearInterval }, env),
    timing,
    platform: {},
    store: { get: () => null, set: () => {} },
    name: () => 'Test TV',
    model: () => '',
    onStatus: (k) => { seen.status.push(k); if (k === 'bad') seen.drops.push(link.problem); },
    onCommand: (c) => seen.commands.push(c),
    onDrop: () => {}
  });
  return { link, seen };
}

function until(check, ms = 5000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    (function poll() {
      if (check()) return resolve();
      if (Date.now() - start > ms) return reject(new Error('zaman aşımı'));
      setTimeout(poll, 20);
    })();
  });
}

const welcomes = (s) => s.received.filter((m) => m.type === 'welcome').length;

test('yeni protokol: gönderici sessizce bırakınca TV yeniden bağlanır (neden: timeout)', async () => {
  const s = await sender.start(0, { pingMs: 100 });
  const { link, seen } = makeLink();
  try {
    link.connect('ws://127.0.0.1:' + s.port + '/nino/ws');
    await until(() => welcomes(s) === 1 && seen.status.includes('ok'));
    await new Promise((r) => setTimeout(r, 400)); // pingler gelirken bağlantı kopmamalı
    assert.strictEqual(welcomes(s), 1);
    s.mute();
    await until(() => welcomes(s) >= 2);
    assert.ok(seen.drops.includes('timeout'));
    s.send({ type: 'show', id: 1, text: 'Geri geldim' });
    await until(() => seen.commands.some((c) => c.text === 'Geri geldim'));
  } finally {
    link.stop();
    await s.close();
  }
});

test('yeni protokol: el sıkışma asılı kalırsa bırakılıp yeniden denenir', async () => {
  const s = await sender.start(0, { noHello: true });
  const { link, seen } = makeLink();
  try {
    link.connect('ws://127.0.0.1:' + s.port + '/nino/ws');
    await until(() => s.connections() >= 3, 4000);
    assert.ok(!seen.status.includes('ok'));
  } finally {
    link.stop();
    await s.close();
  }
});

test('uygulama öne gelince bağlantı tazelenir (neden: resume)', async () => {
  const s = await sender.start(0, { pingMs: 100 });
  const { link, seen } = makeLink();
  try {
    link.connect('ws://127.0.0.1:' + s.port + '/nino/ws');
    await until(() => seen.status.includes('ok'));
    link.resume();
    await until(() => welcomes(s) >= 2);
    assert.deepStrictEqual(seen.drops, ['resume']);
    await until(() => seen.status[seen.status.length - 1] === 'ok');
  } finally {
    link.stop();
    await s.close();
  }
});

test('eski 8787 düzeni: ping kesilince TV olay akışını baştan kurar', async () => {
  const s = await sender.start(0, { legacyPingMs: 100 });
  const { link, seen } = makeLink();
  try {
    link.connect('http://127.0.0.1:' + s.port);
    await until(() => s.connections() === 1 && seen.status.includes('ok'));
    await new Promise((r) => setTimeout(r, 300));
    s.mute();
    await until(() => s.connections() >= 2);
    assert.ok(seen.drops.includes('timeout'));
    s.send({ type: 'show', id: 2, text: 'Eski yoldan geri' });
    await until(() => seen.commands.some((c) => c.text === 'Eski yoldan geri'));
  } finally {
    link.stop();
    await s.close();
  }
});

test('varsayılan sürelerle sessiz kopmadan 30 sn içinde yeniden bağlanma denenir', () => {
  // Sahte saat ve sahte WebSocket: el sıkışma biter, sonra karşıdan hiç mesaj gelmez.
  let now = 0;
  const timers = [];
  const sockets = [];
  class FakeSocket {
    constructor() { sockets.push(this); this.at = now; setImmediate(() => {}); }
    send() {}
    close() { this.closed = true; }
  }
  const env = {
    WebSocket: FakeSocket,
    // Ağ taraması da başlar: her yoklama hemen başarısız olur.
    XMLHttpRequest: class { open() {} send() { this.onerror(); } },
    now: () => now,
    setTimeout: (fn, ms) => { timers.push({ fn, at: now + ms, every: 0 }); return timers.length; },
    clearTimeout: (id) => { if (timers[id - 1]) timers[id - 1].dead = true; },
    setInterval: (fn, ms) => { timers.push({ fn, at: now + ms, every: ms }); return timers.length; },
    clearInterval: (id) => { if (timers[id - 1]) timers[id - 1].dead = true; }
  };
  const { link } = makeLink(undefined, env);
  link.connect('ws://192.168.1.72:47800/nino/ws');
  const first = sockets[0];
  first.onopen();
  first.onmessage({ data: JSON.stringify({ app: 'nino', type: 'hello', version: 1 }) });
  assert.ok(link.ready);
  function advance(ms) {
    const end = now + ms;
    for (;;) {
      const due = timers.filter((t) => !t.dead && t.at <= end).sort((a, b) => a.at - b.at)[0];
      if (!due) break;
      now = due.at;
      if (due.every) due.at += due.every; else due.dead = true;
      due.fn();
    }
    now = end;
  }
  advance(30000);
  assert.ok(first.closed, 'ölü bağlantı kapatılmalı');
  const retry = sockets.find((s) => s !== first);
  assert.ok(retry && retry.at <= 21000, 'yeniden deneme en geç 21. saniyede: ' + (retry && retry.at));
  link.stop();
});
