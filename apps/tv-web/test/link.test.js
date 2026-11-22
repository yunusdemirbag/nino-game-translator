// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Uçtan uca: sahte gönderici (tools/fake-sender.js) ile TV bağlantısı (src/js/link.js) gerçek WebSocket üstünden.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
require('../src/js/protocol.js');
require('../src/js/link.js');
const sender = require('../tools/fake-sender.js');
const P = globalThis.Nino.protocol;

// Tarayıcının XMLHttpRequest'inin yalnız taramanın kullandığı kısmı, fetch ile.
class FetchXHR {
  open(method, url) { this.url = url; }
  send() {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), this.timeout || 1200);
    fetch(this.url, { signal: ctrl.signal })
      .then(async (r) => { this.status = r.status; this.responseText = await r.text(); clearTimeout(t); this.onload(); })
      .catch(() => { clearTimeout(t); this.onerror(); });
  }
}

function makeLink(extra = {}) {
  const intervals = [];
  const env = {
    WebSocket: globalThis.WebSocket,
    XMLHttpRequest: FetchXHR,
    setTimeout, clearTimeout,
    setInterval: (fn, ms) => { const id = setInterval(fn, ms); intervals.push(id); return id; }
  };
  const seen = { status: [], commands: [], drops: 0 };
  const saved = {};
  const link = new globalThis.Nino.Link(Object.assign({
    env,
    platform: { localAddress: (cb) => cb('127.0.0.1') },
    store: { get: (k) => saved[k], set: (k, v) => { saved[k] = v; } },
    name: () => 'Test TV',
    id: () => 'tv-kimligi-1',
    model: () => '',
    onStatus: (k) => seen.status.push(k),
    onCommand: (c) => seen.commands.push(c),
    onDrop: () => { seen.drops++; }
  }, extra));
  return { link, seen, saved, stop: () => { intervals.forEach(clearInterval); link.close(); link.cancelScan(); } };
}

function until(check, ms = 3000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    (function poll() {
      if (check()) return resolve();
      if (Date.now() - start > ms) return reject(new Error('zaman aşımı'));
      setTimeout(poll, 10);
    })();
  });
}

test('TV göndericiye bağlanır, el sıkışır, show/clear alır, ping\'e cevap verir', async () => {
  const s = await sender.start(0);
  const t = makeLink();
  try {
    assert.ok(t.link.connect('ws://127.0.0.1:' + s.port + '/nino/ws'));
    await until(() => t.seen.status.includes('ok') && s.received.length >= 1);
    assert.deepStrictEqual(s.received[0], { app: 'nino', type: 'welcome', version: 1, name: 'Test TV', id: 'tv-kimligi-1' });
    s.send({ type: 'show', id: 7, text: 'Buraya gel.', source: 'Come here.' });
    s.send({ type: 'ping', t: 99 });
    s.send({ type: 'clear', id: 7 });
    await until(() => t.seen.commands.length === 2 && s.received.length === 2);
    assert.strictEqual(t.seen.commands[0].text, 'Buraya gel.');
    assert.deepStrictEqual(t.seen.commands[1], { kind: 'clear', id: 7 });
    assert.deepStrictEqual(s.received[1], { app: 'nino', type: 'pong', t: 99 });
    assert.strictEqual(t.saved.server, 'ws://127.0.0.1:' + s.port + '/nino/ws');
  } finally {
    t.stop();
    await s.close();
  }
});

test('desteklenmeyen sürümle gelen gönderici reddedilir', async () => {
  const s = await sender.start(0, { version: 9 });
  const t = makeLink();
  try {
    t.link.connect('ws://127.0.0.1:' + s.port + '/nino/ws');
    await until(() => s.received.length === 1);
    assert.deepStrictEqual(s.received[0], { app: 'nino', type: 'error', code: 'version_unsupported', versions: [1] });
    await until(() => t.seen.status.includes('bad'));
    assert.ok(!t.seen.status.includes('ok'));
  } finally {
    t.stop();
    await s.close();
  }
});

test('gönderici kapanınca TV yeniden bağlanır', async () => {
  const s = await sender.start(0);
  const port = s.port;
  const t = makeLink();
  try {
    t.link.connect('ws://127.0.0.1:' + port + '/nino/ws');
    await until(() => t.seen.status.includes('ok'));
    await s.close();
    await until(() => t.seen.status.includes('bad'));
    const again = await sender.start(port);
    try {
      await until(() => again.received.some((m) => m.type === 'welcome'), 6000);
    } finally {
      await again.close();
    }
  } finally {
    t.stop();
  }
});

test('adres bilinmiyorsa ağ taranır ve gönderici bulunur', async (t) => {
  let s;
  try {
    s = await sender.start(P.DEFAULT_PORT);
  } catch (e) {
    return t.skip('47800 kullanımda');
  }
  const tv = makeLink();
  try {
    tv.link.scan();
    await until(() => tv.seen.status.includes('ok'), 20000);
    assert.strictEqual(tv.saved.server, 'ws://127.0.0.1:47800/nino/ws');
  } finally {
    tv.stop();
    await s.close();
  }
});
