// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Ölçüm istemcisi (src/js/telemetry.js) — tarif: NinoCore docs/tarif/olcum.md.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { Telemetry, KEY } = require('../src/js/telemetry.js');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function harness(opts = {}) {
  const store = new Map();
  const storage = { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) };
  const sent = [];
  let clock = 1763300000000;
  const replies = opts.replies || [];
  class XHR {
    open(method, url) { this.method = method; this.url = url; this.headers = {}; }
    setRequestHeader(k, v) { this.headers[k] = v; }
    getResponseHeader(k) { return (this.replyHeaders || {})[k] || null; }
    send(body) {
      if (this.method === 'GET') return;
      sent.push({ url: this.url, body: JSON.parse(body), headers: this.headers });
      const r = replies.shift() || { status: 200, body: '{"ok":true}' };
      this.status = r.status;
      this.responseText = r.body || '';
      this.replyHeaders = r.headers;
      if (r.status === 0) this.onerror(); else this.onload();
    }
  }
  const t = new Telemetry({
    endpoint: 'https://havuz.example',
    install: () => '8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f',
    ctx: Object.assign({ platform: 'webos', app: '4.0.3', os: 'webOS 23', device: 'LG OLED55C3', tv: 'lg', channel: 'release' }, opts.ctx),
    env: { XMLHttpRequest: XHR, setTimeout: () => 0, clearTimeout: () => {}, now: () => clock, random: Math.random, storage }
  });
  return { t, sent, store, storage, tick: (ms) => { clock += ms; }, queue: () => JSON.parse(store.get(KEY.queue) || '[]') };
}

test('gövde tarifteki biçimde', () => {
  const h = harness();
  h.t.add({ k: 'launch', ms: 900 });
  h.t.add({ k: 'tv_connect', r: 'ok', ms: 420, brand: 'lg', proto: 'nino' });
  h.t.flush();
  assert.strictEqual(h.sent.length, 1);
  const { url, body, headers } = h.sent[0];
  assert.strictEqual(url, 'https://havuz.example/v1/events');
  assert.strictEqual(headers['Content-Type'], 'application/json');
  assert.strictEqual(body.v, 1);
  assert.match(body.batch, UUID);
  assert.strictEqual(body.install, '8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f');
  assert.deepStrictEqual(body.ctx, { platform: 'webos', app: '4.0.3', os: 'webOS 23', device: 'LG OLED55C3', tv: 'lg', channel: 'release' });
  assert.deepStrictEqual(body.events.map((e) => e.k), ['launch', 'tv_connect']);
  assert.strictEqual(body.events[0].t, 1763300000);
  assert.strictEqual(h.queue().length, 0);
});

test('aynı hata art arda birleşir; kodlar süzülür', () => {
  const h = harness();
  h.t.error('tv.connect.refused');
  h.t.error('tv.connect.refused');
  h.t.error('içinde boşluk ve /yol');
  assert.deepStrictEqual(h.queue().map((e) => [e.code, e.n]), [['tv.connect.refused', 2], ['other', undefined]]);
});

test('önceki çalışma düzgün kapanmadıysa crash; arka plana geçince işaret silinir', () => {
  const h = harness();
  h.t.start(1200);
  assert.deepStrictEqual(h.queue().map((e) => e.k), ['launch']);
  assert.strictEqual(h.queue()[0].ms, 1200);
  h.tick(90000);
  const again = harness();
  again.storage.setItem(KEY.running, h.storage.getItem(KEY.running));
  again.tick(90000);
  again.t.start();
  const crash = again.queue().find((e) => e.k === 'crash');
  assert.deepStrictEqual([crash.code, crash.ver, crash.up], ['unclean_exit', '4.0.3', 90]);
  const clean = harness();
  clean.t.start();
  clean.t.sleep();
  assert.strictEqual(clean.storage.getItem(KEY.running), null);
});

test('400 parçayı siler, 5xx saklar ve aynı batch ile yeniden dener', () => {
  const h = harness({ replies: [{ status: 503 }, { status: 200, body: '{}' }] });
  h.t.add({ k: 'launch' });
  h.t.flush();
  assert.ok(h.storage.getItem(KEY.pending));
  h.t.flush(); // bekleme süresi dolmadı
  assert.strictEqual(h.sent.length, 1);
  h.tick(61000);
  h.t.flush();
  assert.strictEqual(h.sent.length, 2);
  assert.strictEqual(h.sent[0].body.batch, h.sent[1].body.batch);
  assert.strictEqual(h.storage.getItem(KEY.pending), null);

  const bad = harness({ replies: [{ status: 400 }] });
  bad.t.add({ k: 'launch' });
  bad.t.flush();
  assert.strictEqual(bad.storage.getItem(KEY.pending), null);
});

test('413 ikiye böler; 429 retry-after kadar bekler', () => {
  const h = harness({ replies: [{ status: 413 }, { status: 200 }, { status: 200 }] });
  for (let i = 0; i < 4; i++) h.t.add({ k: 'error', code: 'c' + i });
  h.t.flush();
  assert.deepStrictEqual(h.sent.map((s) => s.body.events.length), [4, 2, 2]);
  assert.notStrictEqual(h.sent[1].body.batch, h.sent[2].body.batch);

  const slow = harness({ replies: [{ status: 429, headers: { 'retry-after': '120' } }, { status: 200 }] });
  slow.t.add({ k: 'launch' });
  slow.t.flush();
  slow.tick(119000);
  slow.t.flush();
  assert.strictEqual(slow.sent.length, 1);
  slow.tick(2000);
  slow.t.flush();
  assert.strictEqual(slow.sent.length, 2);
});

test('sunucu kapatırsa kuyruk silinir, gönderim durur; günlük sınırda yalnız crash gider', () => {
  const h = harness({ replies: [{ status: 200, body: '{"ok":true,"config":{"telemetry":{"enabled":false}}}' }] });
  h.t.add({ k: 'launch' });
  h.t.flush();
  h.t.add({ k: 'launch' });
  assert.strictEqual(h.queue().length, 0);

  const day = harness({ replies: [{ status: 200, body: '{"config":{"telemetry":{"enabled":true,"maxPerDay":1}}}' }, { status: 200 }] });
  day.t.add({ k: 'launch' });
  day.t.flush();
  day.t.add({ k: 'error', code: 'a' });
  day.t.add({ k: 'crash', code: 'unclean_exit' });
  day.t.flush();
  assert.deepStrictEqual(day.sent[1].body.events.map((e) => e.k), ['crash']);
});

test('tarayıcı önizlemesinde (platform tanınmıyor) hiçbir şey birikmez', () => {
  const h = harness({ ctx: { platform: 'browser' } });
  h.t.start();
  h.t.add({ k: 'launch' });
  h.t.flush();
  assert.strictEqual(h.queue().length, 0);
  assert.strictEqual(h.sent.length, 0);
  assert.strictEqual(h.storage.getItem(KEY.running), null);
});

test('kuyruk 2000 olayı geçmez, en eski çökme olmayan atılır', () => {
  const h = harness({ replies: Array(50).fill({ status: 503 }) });
  h.t.sending = true; // gönderim sürüyormuş gibi: yalnız kuyruk denenir
  h.t.add({ k: 'crash', code: 'unclean_exit' });
  for (let i = 0; i < 2100; i++) h.t.add({ k: 'error', code: 'e' + i });
  const q = h.queue();
  assert.strictEqual(q.length, 2000);
  assert.strictEqual(q[0].k, 'crash');
  assert.strictEqual(q[q.length - 1].code, 'e2099');
});

test('açılışta ayrı /v1/config isteği yok; ilk gönderim 30 sn sonra', () => {
  const h = harness();
  const urls = [];
  const timers = [];
  h.t.env.setTimeout = (fn, ms) => { timers.push([ms, fn]); return timers.length; };
  const Original = h.t.env.XMLHttpRequest;
  h.t.env.XMLHttpRequest = class extends Original { open(m, u) { urls.push(m + ' ' + u); super.open(m, u); } };
  h.t.start();
  assert.deepStrictEqual(urls, []);
  const first = timers.find(([ms]) => ms === 30000);
  assert.ok(first);
  first[1]();
  assert.deepStrictEqual(urls, ['POST https://havuz.example/v1/events']);
});

test('diag günlük olay sınırından muaf; telemetry.diag ayarı bekçiye iletilir', () => {
  const h = harness({ replies: [{ status: 200, body: '{"config":{"telemetry":{"maxPerDay":0,"diag":{"off":["app.hang"]}}}}' }, { status: 200 }] });
  let seen = null;
  h.t.onConfig = (t) => { seen = t.diag; };
  h.t.add({ k: 'launch' });
  h.t.flush();
  assert.deepStrictEqual(seen, { off: ['app.hang'] });
  h.t.add({ k: 'error', code: 'a' });
  h.t.add({ k: 'diag', rule: 'tv.flapping', cause: 'timeout', sev: 'warn', state: {}, trail: [] });
  h.t.flush();
  assert.deepStrictEqual(h.sent[1].body.events.map((e) => e.k), ['diag']);
});
