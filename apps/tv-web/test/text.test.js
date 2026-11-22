// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const T = require('../src/js/text.js');

test('kısa yazı bölünmez', () => {
  assert.deepStrictEqual(T.wrap('Buraya gel.'), { text: 'Buraya gel.', scale: 1 });
});

test('uzun yazı iki dengeli satıra bölünür', () => {
  const text = 'Bu şehrin onu kollayacak birine ihtiyacı var ve bunu sen de benim kadar iyi biliyorsun dostum.';
  const out = T.wrap(text);
  const lines = out.text.split('\n');
  assert.strictEqual(lines.length, 2);
  assert.strictEqual(lines.join(' '), text);
  assert.ok(Math.abs(lines[0].length - lines[1].length) <= 12);
  assert.strictEqual(out.scale, 1);
  const long = T.wrap(text + ' ' + text);
  assert.ok(long.scale < 1 && long.scale >= 0.75);
  assert.strictEqual(long.text.split('\n').length, 2);
});

test('konuşan adı sonraki sözcükten ayrılmaz', () => {
  assert.strictEqual(T.words('ARTHUR: Dutch, dinle beni')[0], 'ARTHUR: Dutch,');
});

test('elle bölünmüş yazı korunur', () => {
  const text = 'Görev\n• Çatıya çık ve orada bekle, kimse seni görmesin, çok önemli bu';
  assert.strictEqual(T.wrap(text).text, text);
});

test('aynı satır kuralı', () => {
  assert.ok(T.sameLine('Kapı.', 'kapı'));
  assert.ok(T.sameLine('Kapı', 'Kapı daha fazla dayanmaz'));
  assert.ok(!T.sameLine('No!', 'Not now!'));
  assert.ok(T.sameLine('Not now!', 'now'));
  assert.ok(!T.sameLine('Merhaba', 'Güle güle'));
  assert.ok(T.sameLine('Ne?', 'ne ؟'));
});

test('Arapça algılama', () => {
  assert.ok(T.isArabic('ATREUS: مرحبا'));
  assert.ok(!T.isArabic('Merhaba'));
});

test('simge ve vurgu parçaları', () => {
  const p = T.parts('✕ ile ⟦odasına⟧ git, R2 bas, Ⓑ işareti, OPTIONS');
  assert.deepStrictEqual(p[0], { icon: 'face', key: '✕' });
  assert.deepStrictEqual(p[2], { text: 'odasına', accent: true });
  assert.ok(p.some((x) => x.icon === 'pill' && x.label === 'R2'));
  assert.ok(p.some((x) => x.icon === 'marker' && x.label === 'B'));
  assert.ok(p.some((x) => x.icon === 'pill' && x.label === 'OPTIONS'));
  assert.deepStrictEqual(T.parts('yarım ⟦ işaret'), [{ text: 'yarım  işaret' }]);
});

test('altyazı ekran çevirisi parçasıyla çakışırsa üstüne çıkar', () => {
  const sub = { left: 749, top: 955, right: 1171, bottom: 990 };
  const strip = { left: 791, top: 958, right: 1083, bottom: 1013 };
  assert.strictEqual(T.lift(sub, [strip], 13), 990 - 958 + 13);
  assert.strictEqual(T.lift(sub, [{ left: 0, top: 1000, right: 1920, bottom: 1040 }], 13), 0);
  assert.strictEqual(T.lift(sub, [{ left: 1200, top: 950, right: 1300, bottom: 1000 }], 13), 0);
  // İkinci engel: ilk itişten sonra üstteki parçaya çarparsa onun da üstüne.
  const upper = { left: 700, top: 905, right: 900, bottom: 935 };
  const up = T.lift(sub, [strip, upper], 13);
  assert.ok(sub.bottom - up <= upper.top - 13);
});

test('otomatik boya kullanıcının yazı boyu çarpan olarak uygulanır', () => {
  // Varsayılan ayarda otomatik boy oyunun satırından %25 büyük; kullanıcı ayarı bunun üstüne çarpılır.
  assert.strictEqual(T.AUTO_BOOST, 1.25);
  assert.strictEqual(T.autoFont(40, 46, 1080), 50);
  assert.strictEqual(T.autoFont(40, 69, 1080), 75);
  assert.strictEqual(T.autoFont(40, 23, 1080), 25);
  assert.strictEqual(T.autoFont(40, undefined, 1080), 50);
  assert.strictEqual(T.autoFont(40, 400, 1080), Math.round(40 * 1.25 * 2.5)); // çarpan en çok 2,5
  assert.strictEqual(T.autoFont(80, 200, 720), Math.round(720 * 0.14)); // ekran yüksekliğinin %14'ünü geçmez
});

test('konuşanın adı: speaker alanı ya da büyük harfli AD: etiketi', () => {
  assert.deepStrictEqual(T.speakerOf('ARTHUR: Dutch, dinle beni'), { label: 'ARTHUR:', rest: ' Dutch, dinle beni', inText: true });
  assert.deepStrictEqual(T.speakerOf('UNCLE JACK: Selam'), { label: 'UNCLE JACK:', rest: ' Selam', inText: true });
  assert.strictEqual(T.speakerOf('Not: bu bir açıklama'), null);            // küçük harfli sözcük ad değil
  assert.strictEqual(T.speakerOf('Saat 10:30 oldu'), null);
  assert.strictEqual(T.speakerOf('ملاحظة: هذا شرح'), null);                 // Arapçada yalnız speaker alanı
  assert.deepStrictEqual(T.speakerOf('Lucia: Gidelim.', 'Lucia'), { label: 'Lucia:', rest: ' Gidelim.', inText: true });
  assert.deepStrictEqual(T.speakerOf('Gidelim.', 'Lucia'), { label: 'Lucia:', rest: ' Gidelim.', inText: false });
  assert.deepStrictEqual(T.speakerOf('آرثر: لنذهب', 'آرثر'), { label: 'آرثر:', rest: ' لنذهب', inText: true });
});

test('tuş yer tutucusu: icons listesinden simge olur, bulunamazsa hiç görünmez', () => {
  const icons = [{ id: 'T1', name: 'dpad-up' }, { id: 'T2', name: 'Cross' }, { id: 'T3', png: 'iVBORw0KGgo=' }, { id: 'T4', name: 'r2' }];
  const p = T.parts('Ortağınla etkileşim için ⟦T1⟧ tuşunu basılı tut, ⟦T2⟧ ya da ⟦T3⟧ ve ⟦T4⟧, ⟦T9⟧ yok', icons);
  assert.deepStrictEqual(p.filter((x) => x.icon).map((x) => x.icon), ['cross-pad', 'face', 'image', 'pill']);
  assert.strictEqual(p.find((x) => x.icon === 'cross-pad').dir, 'up');
  assert.strictEqual(p.find((x) => x.icon === 'image').src, 'data:image/png;base64,iVBORw0KGgo=');
  assert.strictEqual(p.find((x) => x.icon === 'pill').label, 'R2');
  const visible = p.filter((x) => !x.icon).map((x) => x.text).join('');
  assert.ok(!/T\d|⟦|⟧/.test(visible), visible);
  // Simge listesi hiç yoksa da yer tutucu görünmez; vurgu işareti (⟦sözcük⟧) eskisi gibi çalışır.
  const none = T.parts('⟦T1⟧ ile ⟦odaya⟧ git');
  assert.deepStrictEqual(none, [{ text: ' ile ' }, { text: 'odaya', accent: true }, { text: ' git' }]);
  // Bozuk PNG metni resim sayılmaz.
  assert.deepStrictEqual(T.parts('⟦T1⟧', [{ id: 'T1', png: '<script>' }]), []);
});

test('yer tutucu satır bölmede tek sözcük gibi kalır', () => {
  const text = 'Ortağınla etkileşime geçmek için ⟦T1⟧ tuşunu basılı tut ve sonra arabaya binip limana doğru hızla sür';
  const w = T.wrap(text);
  assert.strictEqual(w.text.split('\n').length, 2);
  assert.ok(w.text.includes('⟦T1⟧'));
});
