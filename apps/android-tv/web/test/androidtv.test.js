// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Android TV platform katmanı (web/androidtv.js): iki bağlantı yolu (uygulamanın 47800 sunucusu ve sayfanın kendi
// eski 8787 / tarama yolu), açılış bilgisi, görüntü modu. Çalıştırma: node --test apps/android-tv/web/test
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SOURCE = fs.readFileSync(path.join(__dirname, '..', 'androidtv.js'), 'utf8');

function element() {
  return { className: '', style: {}, appendChild() {}, setAttribute() {}, querySelector: () => element(),
    querySelectorAll: () => [], textContent: '' };
}

/** androidtv.js'i sahte bir sayfada yükler. mode: inapp | overlay | home | permission. */
function load(mode, extra) {
  const calls = [];
  const webLinks = [];
  const stored = Object.assign({}, (extra && extra.stored) || {});
  const protocol = {
    LEGACY_PORT: 8787,
    parseAddress(raw) {
      const m = /^(?:(wss?|https?):\/\/)?([^/:]+)(?::(\d+))?/.exec(String(raw || ''));
      if (!m) return null;
      const scheme = m[1] || '';
      const port = m[3] ? +m[3] : (scheme.startsWith('w') || !scheme ? 47800 : 8787);
      const legacy = scheme.startsWith('h') && port !== 47800;
      return { kind: legacy ? 'legacy' : 'nino', url: legacy ? 'http://' + m[2] + ':' + port : 'ws://' + m[2] + ':' + port + '/nino/ws' };
    },
  };
  class FakeWebLink {
    constructor(options) {
      this.o = options;
      this.address = null;
      this.connected = [];
      this.scans = 0;
      webLinks.push(this);
    }
    known() { return !!this.address; }
    connect(raw) { this.address = { kind: 'legacy', url: raw }; this.connected.push(raw); this.open(); return true; }
    open() { this.opened = (this.opened || 0) + 1; }
    close() { this.closed = (this.closed || 0) + 1; }
    cancelScan() {}
    scan() { this.scans++; }
    probe(url, check, done) { (this.probed = this.probed || []).push(url); done(url.endsWith('/hello')); }
    probeHost(host, done) { done('ws://' + host + ':47800/nino/ws'); }
    resume() { this.resumed = (this.resumed || 0) + 1; }
  }
  // Elle ilerletilen saat: zamanlamalı davranışlar makinenin yüküne bağlı olmadan denensin.
  let now = 0;
  let seq = 0;
  const timers = new Map();
  const fakeSetTimeout = (fn, ms) => { const id = ++seq; timers.set(id, { at: now + (ms || 0), fn }); return id; };
  const fakeClearTimeout = (id) => { timers.delete(id); };
  const advance = (ms) => {
    const until = now + ms;
    for (;;) {
      let next = null;
      for (const [id, t] of timers) if (t.at <= until && (!next || t.at < next[1].at || (t.at === next[1].at && id < next[0]))) next = [id, t];
      if (!next) break;
      timers.delete(next[0]);
      now = next[1].at;
      next[1].fn();
    }
    now = until;
  };
  const window = {
    navigator: { language: 'tr-TR' },
    document: { createElement: element, head: element(), body: element(), addEventListener() {} },
    setTimeout: fakeSetTimeout, clearTimeout: fakeClearTimeout,
    Nino: { Link: FakeWebLink, protocol },
    NinoNative: {
      setup: () => JSON.stringify(Object.assign({ mode, address: '192.168.0.110', params: '', legacy: true, legacyGraceMs: 0 }, (extra && extra.setup) || {})),
      legacyLinked: (open) => calls.push('legacyLinked ' + open),
      setDisplayMode: (m) => calls.push('mode ' + m),
      pickHdmi: (p) => calls.push('hdmi ' + p),
      ready: () => calls.push('ready'),
      leave: () => calls.push('leave'),
      consolePort: () => 2,
      measure: (json) => calls.push('measure ' + json),
    },
  };
  window.window = window;
  vm.runInNewContext(SOURCE, window);
  const statuses = [];
  const commands = [];
  let drops = 0;
  const link = window.NINO_PLATFORM.makeLink({
    platform: window.NINO_PLATFORM,
    store: { get: (k) => stored[k] || null, set: (k, v) => { stored[k] = v; } },
    name: () => 'TV', model: () => 'TCL',
    onStatus: (k) => statuses.push(k),
    onCommand: (c) => commands.push(c),
    onDrop: () => { drops++; },
    onTvAddress() {},
  });
  return { window, link, web: webLinks[0], calls, statuses, commands, drops: () => drops, advance };
}

// Sayfanın sıfır süreli zamanlayıcıları (kurulum, bekleme) için saati biraz ilerletir.
const tick = (t) => t.advance(40);

test('yeni gönderici bağlanınca bekleme biter, durum ok olur', () => {
  const t = load('inapp');
  assert.strictEqual(t.link.known(), false);
  t.window.ninoAndroid.receive({ type: 'link', open: true });
  assert.deepStrictEqual(t.statuses, ['connecting', 'ok']);
  assert.strictEqual(t.link.known(), true);
});

test('eski gönderici (8787) web yolundan bağlanır; komutları ve görüntü modu iletilir', async () => {
  const t = load('inapp');
  tick(t);
  assert.strictEqual(t.link.connect('http://192.168.0.219:8787'), true);
  assert.deepStrictEqual(t.web.connected, ['http://192.168.0.219:8787']);
  assert.strictEqual(t.link.address.url, 'http://192.168.0.219:8787');
  t.web.o.onStatus('connecting');
  t.web.o.onStatus('ok');
  assert.deepStrictEqual(t.statuses.slice(-2), ['connecting', 'ok']);
  t.web.o.onCommand({ kind: 'style', style: { displayMode: 'overlay', fontSize: 30 } });
  t.web.o.onCommand({ kind: 'show', text: 'Buraya gel.' });
  assert.deepStrictEqual(t.calls.filter((c) => c.startsWith('mode')), ['mode overlay']);
  assert.deepStrictEqual(t.commands.map((c) => c.kind), ['style', 'show']);
});

test('yeni yol bağlanınca eski yol kapanır, yeni yol kopunca eski yol yeniden açılır', async () => {
  const t = load('inapp');
  tick(t);
  t.link.connect('http://192.168.0.219:8787');
  t.web.o.onStatus('ok');
  const opened = t.web.opened;
  t.window.ninoAndroid.receive({ type: 'link', open: true });
  assert.strictEqual(t.web.closed, 1);
  t.web.o.onCommand({ kind: 'show', text: 'çift' });
  assert.strictEqual(t.commands.length, 0);
  t.window.ninoAndroid.receive({ type: 'link', open: false });
  tick(t);
  assert.strictEqual(t.web.opened, opened + 1);
  t.web.o.onStatus('ok');
  t.web.o.onCommand({ kind: 'show', text: 'tek' });
  assert.strictEqual(t.commands.length, 1);
});

test('web yolu koparsa yerel yol açıkken ekran temizlenmez', () => {
  const t = load('inapp');
  t.window.ninoAndroid.receive({ type: 'link', open: true });
  t.web.o.onDrop();
  assert.strictEqual(t.drops(), 0);
  t.window.ninoAndroid.receive({ type: 'link', open: false });
  t.web.o.onDrop();
  assert.strictEqual(t.drops(), 1);
});

test('açılış bilgisi (params) sayfaya verilir, yeniden açılış bildirilir', () => {
  const t = load('overlay', { setup: { params: '{"server":"http://192.168.0.219:8787"}' } });
  assert.strictEqual(t.window.NINO_PLATFORM.launchParams(), '{"server":"http://192.168.0.219:8787"}');
  let got = null;
  t.window.NINO_PLATFORM.onRelaunch((raw) => { got = raw; });
  t.window.ninoAndroid.receive({ type: 'relaunch', params: '{"server":"http://192.168.0.5:8787"}' });
  assert.strictEqual(got, '{"server":"http://192.168.0.5:8787"}');
});

test('katmanda kayıtlı adrese bağlanılır, kayıt yoksa ağ taranır', async () => {
  const saved = load('overlay', { stored: { server: 'http://192.168.0.219:8787' } });
  const fresh = load('home');
  tick(saved);
  tick(fresh);
  assert.deepStrictEqual(saved.web.connected, ['http://192.168.0.219:8787']);
  assert.strictEqual(saved.web.scans, 0);
  assert.strictEqual(fresh.web.scans, 1);
  // Katmanda bekleme sahnesi hiç oynamaz.
  assert.strictEqual(fresh.link.known(), true);
});

test('uygulama içinde de kayıtlı adres yoksa eski yol için ağ taranır', async () => {
  const t = load('inapp');
  tick(t);
  assert.strictEqual(t.web.scans, 1);
});

test('eski yolu yalnız tutucu sayfa çalıştırır: öbürü hiç bağlanmaz, durumu bildirimle görür', async () => {
  const t = load('home', { setup: { legacy: false }, stored: { server: 'http://192.168.0.219:8787' } });
  tick(t);
  assert.deepStrictEqual(t.web.connected, []);
  assert.strictEqual(t.web.scans, 0);
  assert.strictEqual(t.link.connect('http://192.168.0.219:8787'), true);
  assert.strictEqual(t.web.opened, undefined, 'kapı kapalıyken bağlantı açılmaz');
  t.window.ninoAndroid.receive({ type: 'legacyLink', open: true });
  assert.strictEqual(t.link.linked(), true);
  // Tutucu olunca açılır, tutuculuk gidince kapanır.
  t.window.ninoAndroid.receive({ type: 'legacy', on: true });
  tick(t);
  assert.strictEqual(t.web.opened, 1);
  t.web.o.onStatus('ok');
  assert.ok(t.calls.includes('legacyLinked true'));
  t.window.ninoAndroid.receive({ type: 'legacy', on: false });
  assert.strictEqual(t.web.closed, 1);
  // "Bağlı değil" bilgisini tutuculuk el değiştirirken uygulama (LinkHub.pickLegacyHolder) yayar.
});

test('eski yolun bağlanması ve kopması ölçülür; başarısız denemeler bir kez sayılır', async () => {
  const t = load('inapp');
  tick(t);
  t.link.connect('http://192.168.0.219:8787');
  const web = t.web.o;
  web.onStatus('connecting');
  web.onStatus('bad');
  web.onStatus('connecting');
  web.onStatus('bad');
  web.onStatus('connecting');
  web.onStatus('ok');
  web.onStatus('bad');
  const events = t.calls.filter((c) => c.startsWith('measure ')).map((c) => JSON.parse(c.slice(8)));
  assert.deepStrictEqual(events.map((e) => e.k + ':' + (e.r || e.code)),
    ['tv_connect:tv.connect.refused', 'tv_connect:ok', 'tv_drop:network_lost']);
  assert.strictEqual(events[1].proto, 'legacy');
});

test('sayfa öne gelince web yolu tazelenir', () => {
  const t = load('inapp');
  t.link.resume();
  assert.strictEqual(t.web.resumed, 1);
});

test('sayfanın kendi bağlantısı yeni yola (47800) hiç bağlanmaz: aynı TV iki kez bağlanmasın', () => {
  const t = load('inapp');
  assert.strictEqual(t.link.connect('ws://192.168.0.219:47800/nino/ws'), false);
  assert.strictEqual(t.link.connect('192.168.0.219'), false);
  assert.deepStrictEqual(t.web.connected, []);
  assert.strictEqual(t.link.connect('http://192.168.0.219:8787'), true);
  let found = null;
  t.web.probeHost('192.168.0.219', (url) => { found = url; });
  assert.strictEqual(found, 'http://192.168.0.219:8787');
  assert.deepStrictEqual(t.web.probed, ['http://192.168.0.219:8787/hello']);
});

test('kayıtlı yeni yol adresi yok sayılır, katmanda tarama başlar', async () => {
  const t = load('overlay', { stored: { server: 'ws://192.168.0.219:47800/nino/ws' } });
  tick(t);
  assert.deepStrictEqual(t.web.connected, []);
  assert.strictEqual(t.web.scans, 1);
});

test('eski yol açılmadan önce yeni göndericiye süre tanınır; o arada bağlanırsa eski yol hiç açılmaz', async () => {
  const t = load('overlay', { setup: { legacyGraceMs: 300 }, stored: { server: 'http://192.168.0.219:8787' } });
  tick(t);
  t.window.ninoAndroid.receive({ type: 'link', open: true });
  t.advance(80);
  assert.deepStrictEqual(t.web.connected, [], 'yeni gönderici bağlı: eski yol açılmadı');
  t.window.ninoAndroid.receive({ type: 'link', open: false });
  tick(t);
  assert.deepStrictEqual(t.web.connected, [], 'kopunca da hemen açılmaz');
  t.advance(450);
  assert.deepStrictEqual(t.web.connected, ['http://192.168.0.219:8787']);
});
