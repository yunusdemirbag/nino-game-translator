// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// TV tarafı protokol oturumunun testleri (docs/yeni/tv-web/baglanti.md, NinoCore docs/tarif/protokol.md).
// Çalıştırma: node --test apps/tv-web/test
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const P = require('../src/js/protocol.js');

function clock() {
  let now = 0;
  let seq = 0;
  const timers = new Map();
  return {
    setTimeout(fn, ms) { const id = ++seq; timers.set(id, { fn, at: now + ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
    advance(ms) {
      const end = now + ms;
      for (;;) {
        let next = null;
        for (const [id, t] of timers) if (t.at <= end && (!next || t.at < next[1].at)) next = [id, t];
        if (!next) break;
        timers.delete(next[0]);
        now = next[1].at;
        next[1].fn();
      }
      now = end;
    }
  };
}

function session(extra) {
  const c = clock();
  const sent = [];
  const commands = [];
  const state = { closed: false, idle: 0, ready: null };
  const s = new P.DisplaySession(Object.assign({
    name: 'Salon TV',
    send: (t) => sent.push(JSON.parse(t)),
    close: () => { state.closed = true; },
    onCommand: (cmd) => commands.push(cmd),
    onIdle: () => { state.idle++; },
    onReady: (v) => { state.ready = v; },
    setTimeout: c.setTimeout,
    clearTimeout: c.clearTimeout
  }, extra));
  s.open();
  return { s, c, sent, commands, state, recv: (o) => s.receive(typeof o === 'string' ? o : JSON.stringify(o)) };
}

const hello = { app: 'nino', type: 'hello', version: 1, device: 'Mac', client: 'nino-mac/0.1.0' };

test('el sıkışma: hello → welcome', () => {
  const t = session();
  t.recv(hello);
  assert.deepStrictEqual(t.sent, [{ app: 'nino', type: 'welcome', version: 1, name: 'Salon TV' }]);
  assert.strictEqual(t.state.ready, 1);
  assert.strictEqual(t.s.state, 'ready');
});

test('desteklenmeyen sürüm: version_unsupported ve kapanır', () => {
  const t = session();
  t.recv({ app: 'nino', type: 'hello', version: 2 });
  assert.deepStrictEqual(t.sent, [{ app: 'nino', type: 'error', code: 'version_unsupported', versions: [1] }]);
  assert.ok(t.state.closed);
});

test('hello öncesi başka mesaj ya da app ≠ nino: bad_handshake', () => {
  for (const first of [{ app: 'nino', type: 'show', id: 1, text: 'x' }, { app: 'other', type: 'hello', version: 1 }, 'bozuk{']) {
    const t = session();
    t.recv(first);
    assert.strictEqual(t.sent[0].code, 'bad_handshake');
    assert.ok(t.state.closed);
    assert.strictEqual(t.commands.length, 0);
  }
});

test('5 sn içinde hello gelmezse kapanır', () => {
  const t = session();
  t.c.advance(4999);
  assert.ok(!t.state.closed);
  t.c.advance(1);
  assert.ok(t.state.closed);
});

test('ping → aynı t ile pong', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'ping', t: 1732233600000 });
  assert.deepStrictEqual(t.sent[1], { app: 'nino', type: 'pong', t: 1732233600000 });
});

test('show ve clear komutları', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'show', id: 42, text: 'Buraya gel.', source: 'Come here.', position: 'top', durationMs: 0 });
  t.recv({ app: 'nino', type: 'clear', id: 42 });
  t.recv({ app: 'nino', type: 'clear' });
  assert.strictEqual(t.commands[0].kind, 'show');
  assert.strictEqual(t.commands[0].id, 42);
  assert.strictEqual(t.commands[0].text, 'Buraya gel.');
  assert.strictEqual(t.commands[0].position, 'top');
  assert.strictEqual(t.commands[0].durationMs, 0);
  assert.deepStrictEqual(t.commands[1], { kind: 'clear', id: 42 });
  assert.deepStrictEqual(t.commands[2], { kind: 'clear', id: null });
});

test('eksik alanlı show: bad_message, bağlantı açık kalır', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'show', text: 'id yok' });
  assert.strictEqual(t.sent[1].code, 'bad_message');
  assert.ok(!t.state.closed);
  assert.strictEqual(t.commands.length, 0);
});

test('bilinmeyen tür ve bilinmeyen alanlar yok sayılır', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'gelecekte', x: 1 });
  t.recv({ app: 'nino', type: 'show', id: 1, text: 'a', yeniAlan: true });
  assert.strictEqual(t.sent.length, 1);
  assert.strictEqual(t.commands.length, 1);
  assert.ok(!t.state.closed);
});

test('512 KB üstü mesaj: too_large ve kapanır; buzlu zeminli büyük show geçer', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'show', id: 1, text: 'a', cover: 'A'.repeat(200 * 1024) });
  assert.strictEqual(t.commands.length, 1);
  assert.strictEqual(t.commands[0].cover.length, 200 * 1024);
  t.recv({ app: 'nino', type: 'show', id: 2, text: 'ş'.repeat(300 * 1024) });
  assert.strictEqual(t.sent[1].code, 'too_large');
  assert.ok(t.state.closed);
});

test('20 sn hiç mesaj gelmezse ekran temizlenir; mesaj sayacı sıfırlar', () => {
  const t = session();
  t.recv(hello);
  t.c.advance(15000);
  t.recv({ app: 'nino', type: 'ping', t: 1 });
  t.c.advance(15000);
  assert.strictEqual(t.state.idle, 0);
  t.c.advance(5000);
  assert.strictEqual(t.state.idle, 1);
});

test('Nino uzantıları komut olur', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'style', fontSize: 50 });
  t.recv({ app: 'nino', type: 'screen', items: [{ text: 'a' }], durationMs: 3000 });
  t.recv({ app: 'nino', type: 'started' });
  assert.deepStrictEqual(t.commands.map((c) => c.kind), ['style', 'screen', 'started']);
  assert.strictEqual(t.commands[1].durationMs, 3000);
});

test('eski SSE olayları aynı komutlara çevrilir', () => {
  const show = P.fromLegacy('subtitle', { text: 'Selam', duration: 2500, replace: true });
  assert.strictEqual(show.kind, 'show');
  assert.strictEqual(show.durationMs, 2500);
  assert.strictEqual(show.replace, true);
  assert.strictEqual(P.fromLegacy('subtitle', { text: 'Selam' }).durationMs, null);
  assert.strictEqual(P.fromLegacy('subtitle', {}), null);
  assert.deepStrictEqual(P.fromLegacy('clear', {}), { kind: 'clear', id: null });
  assert.strictEqual(P.fromLegacy('region-clear', {}).kind, 'region-clear');
  assert.strictEqual(P.fromLegacy('bilinmeyen', {}), null);
});

test('yerel ağ adresleri', () => {
  for (const ok of ['192.168.0.20', '10.1.2.3', '172.20.0.1', '169.254.1.1', '127.0.0.1', '::1', 'fe80::1%en0', 'fd00::1']) {
    assert.ok(P.isLocalHost(ok), ok);
  }
  for (const bad of ['8.8.8.8', '172.32.0.1', 'example.com', '2001:db8::1', '']) assert.ok(!P.isLocalHost(bad), bad);
});

test('adres çözme: yeni ve eski gönderici', () => {
  assert.deepStrictEqual(P.parseAddress('192.168.0.20'),
    { kind: 'nino', host: '192.168.0.20', port: 47800, url: 'ws://192.168.0.20:47800/nino/ws', base: 'http://192.168.0.20:47800' });
  assert.strictEqual(P.parseAddress('ws://192.168.0.20:47800/nino/ws').kind, 'nino');
  assert.strictEqual(P.parseAddress('http://192.168.0.20:47800').kind, 'nino');
  const old = P.parseAddress('http://192.168.0.20:8787');
  assert.strictEqual(old.kind, 'legacy');
  assert.strictEqual(old.url, 'http://192.168.0.20:8787');
  assert.strictEqual(P.parseAddress('http://8.8.8.8:8787'), null);
});

test('tarama cevabı', () => {
  assert.ok(P.isSenderInfo('{"app":"nino","type":"info","version":1,"versions":[1],"name":"Mac","id":"x","role":"sender"}'));
  assert.ok(!P.isSenderInfo('{"app":"nino","type":"info","role":"display"}'));
  assert.ok(!P.isSenderInfo('{"app":"nino","type":"info","version":1,"versions":[1],"name":"Salon TV","id":"b1"}'));
  assert.ok(!P.isSenderInfo('<html>nino</html>'));
});

test('yerel köprü mesajları aynı komutlara çevrilir', () => {
  assert.strictEqual(P.toCommand({ type: 'show', id: 3, text: 'Selam', durationMs: 0 }).text, 'Selam');
  assert.deepStrictEqual(P.toCommand({ type: 'clear' }), { kind: 'clear', id: null });
  assert.strictEqual(P.toCommand({ type: 'region', id: 'a', text: 'x' }).kind, 'region');
  assert.strictEqual(P.toCommand({ type: 'link', open: true }), null);
  assert.strictEqual(P.toCommand({ type: 'show' }), null);
});

test('göndericinin error mesajı yalnız kodu için okunur, bağlantı açık kalır', () => {
  const codes = [];
  const t = session({ onPeerError: (c) => codes.push(c) });
  t.recv(hello);
  t.recv({ app: 'nino', type: 'error', code: 'replaced', message: 'serbest metin' });
  assert.deepStrictEqual(codes, ['replaced']);
  assert.strictEqual(t.sent.length, 1);
  assert.ok(!t.state.closed);
});

test('welcome kalıcı id taşır (verildiyse)', () => {
  const t = session({ id: '8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f' });
  t.recv(hello);
  assert.deepStrictEqual(t.sent[0], { app: 'nino', type: 'welcome', version: 1, name: 'Salon TV', id: '8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f' });
});

test('screen süresi: 0 = süresiz (yalnız yeni protokolde), yoksa varsayılan, eski düzende 0 = varsayılan', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'screen', items: [], durationMs: 0 });
  t.recv({ app: 'nino', type: 'screen', items: [], durationMs: 120000 });
  t.recv({ app: 'nino', type: 'screen', items: [] });
  assert.deepStrictEqual(t.commands.map((c) => c.durationMs), [0, 120000, null]);
  assert.strictEqual(P.fromLegacy('screen', { items: [], duration: 0 }).durationMs, null);
  assert.strictEqual(P.fromLegacy('screen', { items: [], duration: 5000 }).durationMs, 5000);
  assert.strictEqual(P.fromLegacy('screen', { items: [] }).durationMs, null);
});

test('show.speaker komuta geçer (en çok 60 karakter)', () => {
  const t = session();
  t.recv(hello);
  t.recv({ app: 'nino', type: 'show', id: 5, text: 'Gidelim.', speaker: 'Lucia' });
  t.recv({ app: 'nino', type: 'show', id: 6, text: 'Gidelim.' });
  assert.strictEqual(t.commands[0].speaker, 'Lucia');
  assert.strictEqual(t.commands[1].speaker, null);
});

test('show.icons komuta geçer; bozuk ya da fazla simge atılır', () => {
  const t = session();
  t.recv(hello);
  const many = Array.from({ length: 12 }, (_, i) => ({ id: 'T' + (i + 1), name: 'cross' }));
  t.recv({ app: 'nino', type: 'show', id: 7, text: '⟦T1⟧ bas', icons: [{ id: 'T1', name: 'dpad-up' }, { id: 'X', name: 'cross' }, { id: 'T2' }] });
  t.recv({ app: 'nino', type: 'show', id: 8, text: 'a', icons: many });
  t.recv({ app: 'nino', type: 'show', id: 9, text: 'b' });
  assert.deepStrictEqual(t.commands[0].icons, [{ id: 'T1', name: 'dpad-up' }]);
  assert.strictEqual(t.commands[1].icons.length, 8);
  assert.strictEqual(t.commands[2].icons, null);
});
