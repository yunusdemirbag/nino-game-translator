// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Otomatik teşhis bekçisi (src/js/diag.js). Ortak senaryolar: test/fixtures/diag-scenarios.json (ana oturumun
// otomatik-teshis tarifiyle gelen dosyanın kopyası). TV yalnız kendi kurallarını (tv.flapping, app.hang,
// app.resources) bildirir; PS5, yazı tanıma ve çeviri kuralları göndericilerindir.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { Watchdog } = require('../src/js/diag.js');
const scenarios = require('./fixtures/diag-scenarios.json').scenarios;

const TV_RULES = new Set(['tv.flapping', 'app.hang', 'app.resources']);
const START = 1763300000;

function dog(extra = {}) {
  let t = START;
  const sent = [];
  const store = new Map();
  const d = new Watchdog(Object.assign({
    now: () => t,
    emit: (e) => sent.push(e),
    storage: { getItem: (k) => store.get(k) || null, setItem: (k, v) => store.set(k, v) },
    tv: () => ({ brand: 'samsung', model: 'Samsung QE55Q80C', app: '4.5.0' }),
    ver: () => ({ tvApp: '4.5.0' })
  }, extra));
  return { d, sent, at: (s) => { t = START + s; }, store };
}

// Senaryonun zaman çizelgesini bekçiye verir.
function play(scenario) {
  const h = dog();
  const drops = (scenario.dropCodes || []).slice();
  for (const [sec, code, n] of scenario.timeline) {
    h.at(sec);
    if (code === 'tv.drop') h.d.tvDrop(drops.shift() || 'other');
    else if (code === 'tv.connect') h.d.tvConnect('legacy');
    else if (code === 'app.background') h.d.background();
    else if (code === 'app.foreground') h.d.foreground();
    else h.d.mark(code, n);
  }
  return h.sent.map((e) => ({ at: e.t - START, rule: e.rule, cause: e.cause, sev: e.sev, e }));
}

for (const scenario of scenarios) {
  test('senaryo: ' + scenario.name, () => {
    const got = play(scenario);
    const expected = scenario.expect.filter((x) => TV_RULES.has(x.rule));
    assert.deepStrictEqual(got.map(({ at, rule, cause, sev }) => ({ at, rule, cause, sev })), expected);
  });
}

test('tv.flapping bildirimi tarifteki biçimde: kod, sayı ve iz, serbest metin yok', () => {
  const s = scenarios.find((x) => x.expect.some((e) => e.rule === 'tv.flapping'));
  const [first] = play(s);
  const e = first.e;
  assert.strictEqual(e.k, 'diag');
  assert.deepStrictEqual(Object.keys(e.state).sort(), ['avgUpSec', 'drops', 'proto']);
  assert.strictEqual(e.state.drops, 3);
  assert.ok(e.trail.length > 0 && e.trail.length <= 40);
  for (const step of e.trail) {
    assert.ok(step[0] <= 0 && step[0] >= -3600);
    assert.match(step[1], /^[A-Za-z0-9_.$-]{1,64}$/);
  }
  assert.deepStrictEqual(e.tv, { brand: 'samsung', model: 'Samsung QE55Q80C', app: '4.5.0' });
  assert.deepStrictEqual(e.ver, { tvApp: '4.5.0' });
});

test('tv.flapping sebebi: çoğunluk yoksa mixed; 10 dk dışındaki kopmalar sayılmaz', () => {
  const h = dog();
  for (const [sec, cause] of [[100, 'timeout'], [200, 'resume'], [300, 'closed']]) { h.at(sec); h.d.tvDrop(cause); }
  assert.strictEqual(h.sent[0].cause, 'mixed');
  const slow = dog();
  for (const sec of [100, 800, 1500]) { slow.at(sec); slow.d.tvDrop('timeout'); }
  assert.strictEqual(slow.sent.length, 0);
});

test('açılışın ilk dakikasında susar; arka plandan dönüş kopmaları (resume) yine de bildirilir', () => {
  const early = dog();
  for (const sec of [10, 20, 30]) { early.at(sec); early.d.tvDrop('timeout'); }
  assert.strictEqual(early.sent.length, 0);
  const h = dog();
  for (const sec of [100, 200, 300]) { h.at(sec); h.d.background(); h.at(sec + 5); h.d.foreground(); h.d.tvDrop('resume'); }
  assert.strictEqual(h.sent[0].cause, 'resume');
});

test('app.hang: görünürken 5 sn donma bildirilir (tik arası 6 sn); 4 sn bildirilmez; arka planda sayılmaz', () => {
  const h = dog();
  h.at(100);
  h.d.tick(1000, true);
  h.d.tick(30000, false);
  assert.strictEqual(h.sent.length, 0);
  h.d.tick(4900, true, 1000);
  assert.strictEqual(h.sent.length, 0);
  h.d.tick(6000, true, 1000);
  assert.deepStrictEqual([h.sent[0].rule, h.sent[0].cause, h.sent[0].sev, h.sent[0].state.blockedSec], ['app.hang', 'main_thread', 'error', 5]);
});

test('app.resources: bellek 400 MB üstünde 2 dk kalırsa', () => {
  const h = dog();
  h.at(100); h.d.memory(450);
  h.at(160); h.d.memory(460);
  assert.strictEqual(h.sent.length, 0);
  h.at(230); h.d.memory(470);
  assert.deepStrictEqual([h.sent[0].rule, h.sent[0].cause, h.sent[0].state.memMB], ['app.resources', 'memory_high', 470]);
});

test('tek kök tek bildirim; aynı kural bir çalışmada bir kez; günde en çok 5', () => {
  const h = dog();
  h.at(100);
  h.d.tick(9000, true);              // app.hang (en öncelikli)
  for (const sec of [110, 120, 130]) { h.at(sec); h.d.tvDrop('timeout'); }
  assert.deepStrictEqual(h.sent.map((e) => e.rule), ['app.hang']);
  h.at(200);
  h.d.tick(9000, true);
  assert.strictEqual(h.sent.length, 1);

  const day = dog();
  day.store.set('nino.diag.day', JSON.stringify({ d: Math.floor((START + 100) / 86400), n: 5, rules: {} }));
  day.at(100);
  day.d.tick(9000, true);
  assert.strictEqual(day.sent.length, 0);
});

test('uzaktan ayar: kural kapatılabilir, eşik değiştirilebilir', () => {
  const off = dog();
  off.d.configure({ off: ['tv.flapping'] });
  for (const sec of [100, 200, 300]) { off.at(sec); off.d.tvDrop('timeout'); }
  assert.strictEqual(off.sent.length, 0);
  const strict = dog();
  strict.d.configure({ limits: { tvFlapCount: 2, bilinmeyen: 9 } });
  for (const sec of [100, 200]) { strict.at(sec); strict.d.tvDrop('closed'); }
  assert.strictEqual(strict.sent[0].cause, 'closed');
});

test('kullanıcı durdurunca ardından gelen kopmalar tv.flapping sayılmaz', () => {
  const h = dog();
  h.at(100); h.d.tvDrop('closed');
  h.at(200); h.d.userStop();
  for (const sec of [210, 220, 230]) { h.at(sec); h.d.tvDrop('closed'); }
  assert.strictEqual(h.sent.length, 0);
});

test('replaced kopmaları tv.flapping sebebi olur', () => {
  const h = dog();
  for (const sec of [100, 200, 300]) { h.at(sec); h.d.tvDrop('replaced'); }
  assert.strictEqual(h.sent[0].cause, 'replaced');
});
