// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Ekran çevirisinin çizim planı (src/js/board.js prepare/signature). Canlı oyunda görülen iki sorun (22 Kasım):
// telefon başlığı TV'de sola yaslı çiziliyordu; aynı liste yeniden gelince her şey baştan çizilip canlandırılıyordu.
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

// board.js'i en küçük sahte sayfayla yükler (yalnız plan işlevleri denenir).
function loadBoard() {
  const el = () => ({ className: 'off', style: {}, children: [], appendChild() {}, querySelector() { return null; } });
  const window = {
    innerWidth: 1920, innerHeight: 1080,
    document: { getElementById: el, createElement: el },
    Nino: { caption: { validBox: (b) => (b && b.right > b.left && b.bottom > b.top ? b : null), hide() {}, rich() {} } }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/js/board.js'), 'utf8'), { window, setTimeout, clearTimeout });
  return window.Nino.board;
}

const raw = loadBoard();
// vm bağlamından gelen nesneler düz JSON'a çevrilir (deepStrictEqual farklı ortamın dizilerini ayrı sayar).
const plain = (x) => JSON.parse(JSON.stringify(x));
const board = { prepare: (items) => plain(raw.prepare(items)), signature: (plan) => raw.signature(plan) };

// Yeni göndericinin (NinoCore PhoneLayout) telefon paneli: zemin, ayrı başlık öğesi, balonlar.
const phone = [
  { text: '', backdrop: true, fill: '#f2f2f7', alpha: 0.6, line: 0.02, box: { left: 0.05, top: 0.10, right: 0.30, bottom: 0.60 } },
  { text: 'Vicki', plain: true, ink: '#1c1c1e', line: 0.024, box: { left: 0.06, top: 0.11, right: 0.29, bottom: 0.14 } },
  { text: 'Neredesin?', fill: '#34c759', ink: '#ffffff', side: true, line: 0.022, box: { left: 0.07, top: 0.20, right: 0.25, bottom: 0.25 } }
];

test('yeni göndericinin telefon başlığı panelin ortalı başlığı olur, ayrı (sola yaslı) parça olmaz', () => {
  const plan = board.prepare(phone);
  assert.deepStrictEqual(plan.map((p) => p.kind), ['panel', 'bubble']);
  assert.deepStrictEqual(plan[0].title, { text: 'Vicki', line: 0.024, ink: '#1c1c1e' });
});

test('eski göndericide başlık panelin kendi metnidir; panelin dışındaki sade yazı başlık sayılmaz', () => {
  const old = [{ text: 'Lamar', backdrop: true, fill: '#f2f2f7', box: { left: 0.05, top: 0.1, right: 0.3, bottom: 0.6 } },
    { text: 'İlerle', plain: true, box: { left: 0.6, top: 0.3, right: 0.75, bottom: 0.33 } }];
  const plan = board.prepare(old);
  assert.deepStrictEqual(plan.map((p) => p.kind), ['panel', 'piece']);
  assert.strictEqual(plan[0].title, undefined);
  // Panelin ortasındaki sade yazı da başlık değildir (üst %15 dışında).
  const middle = board.prepare([phone[0], Object.assign({}, phone[1], { box: { left: 0.06, top: 0.4, right: 0.29, bottom: 0.43 } })]);
  assert.deepStrictEqual(middle.map((p) => p.kind), ['panel', 'piece']);
});

test('yer ve eğiklik oynasa da imza aynı; metin ya da biçim değişince farklı', () => {
  const base = board.signature(board.prepare(phone));
  const moved = phone.map((it) => Object.assign({}, it, { angle: 2.5, line: (it.line || 0) + 0.001,
    box: { left: it.box.left + 0.004, top: it.box.top + 0.003, right: it.box.right + 0.004, bottom: it.box.bottom + 0.003 } }));
  assert.strictEqual(board.signature(board.prepare(moved)), base);
  const retitled = phone.map((it, i) => (i === 1 ? Object.assign({}, it, { text: 'Jason' }) : it));
  assert.notStrictEqual(board.signature(board.prepare(retitled)), base);
  const recolored = phone.map((it, i) => (i === 2 ? Object.assign({}, it, { fill: '#0a84ff' }) : it));
  assert.notStrictEqual(board.signature(board.prepare(recolored)), base);
});
