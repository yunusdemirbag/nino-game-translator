// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Yazıyla ilgili saf işler (DOM yok): uzun çeviriyi bölme, iki satırın aynı olup olmadığı, Arapça algılama,
// düğme simgesi ve vurgu parçaları. Tarif: docs/yeni/tv-web/tarif.md §3.1, §3.3, §3.6.
(function (root) {
  'use strict';

  var LINE_CHARS = 56;
  var MAX_LINES = 2;
  var MIN_SCALE = 0.75;

  function charCount(text) {
    // Vekil çiftler tek karakter sayılır.
    return String(text).replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, '_').length;
  }

  // Sözcükler; konuşan adı ("ARTHUR:") sonraki sözcükle tek parça kalır.
  function words(text) {
    var list = String(text).split(/\s+/);
    var out = [];
    for (var i = 0; i < list.length; i++) if (list[i]) out.push(list[i]);
    var limit = Math.min(3, out.length);
    for (var j = 0; j < limit; j++) {
      var last = out[j].charAt(out[j].length - 1);
      if (last === ':' || last === '：') {
        if (j + 1 < out.length) out.splice(0, j + 2, out.slice(0, j + 2).join(' '));
        break;
      }
    }
    return out;
  }

  // Parçaları "parts" satıra en dengeli biçimde dağıtır: önce en uzun satır kısa, sonra kareler toplamı küçük.
  function balance(list, parts) {
    var n = list.length;
    var prefix = [0];
    for (var i = 0; i < n; i++) prefix.push(prefix[i] + charCount(list[i]));
    function width(a, b) { return prefix[b] - prefix[a] + (b - a - 1); }
    var best = null;
    function score(cuts) {
      var edges = [0].concat(cuts, [n]);
      var longest = 0, squares = 0;
      for (var k = 0; k + 1 < edges.length; k++) {
        var w = width(edges[k], edges[k + 1]);
        if (w > longest) longest = w;
        squares += w * w;
      }
      if (!best || longest < best.longest || (longest === best.longest && squares < best.squares)) {
        best = { longest: longest, squares: squares, cuts: cuts };
      }
    }
    var a, b;
    if (parts >= 3 && n >= 3) {
      for (a = 1; a < n - 1; a++) for (b = a + 1; b < n; b++) score([a, b]);
    } else {
      for (a = 1; a < n; a++) score([a]);
    }
    if (!best) return list.join(' ');
    var cuts = [0].concat(best.cuts, [n]);
    var lines = [];
    for (var c = 0; c + 1 < cuts.length; c++) lines.push(list.slice(cuts[c], cuts[c + 1]).join(' '));
    return lines.join('\n');
  }

  // Dönüş: {text, scale}. Kısa yazı ve elle bölünmüş yazı olduğu gibi kalır.
  function wrap(text) {
    text = String(text);
    var length = charCount(text);
    if (length <= LINE_CHARS || text.indexOf('\n') >= 0) return { text: text, scale: 1 };
    var list = words(text);
    if (list.length < 2) return { text: text, scale: 1 };
    var scale = Math.min(1, Math.max(MIN_SCALE, LINE_CHARS * MAX_LINES / length));
    var perLine = Math.floor(LINE_CHARS / scale);
    var lines = Math.min(MAX_LINES, Math.max(2, Math.ceil(length / perLine)));
    return { text: balance(list, Math.min(lines, list.length)), scale: scale };
  }

  var PUNCTUATION = /[.,!?;:…"'“”‘’«»()\[\]\-–—،؟؛]+/g;

  function plain(text) {
    return String(text).toLowerCase().replace(PUNCTUATION, '').replace(/\s+/g, ' ').replace(/^ | $/g, '');
  }

  function containsWord(sentence, word) {
    return (' ' + sentence + ' ').indexOf(' ' + word + ' ') >= 0;
  }

  // İki altyazı aynı cümle mi (biri ötekinin devamı da sayılır)? Tek sözcük ancak tam sözcük olarak geçerse.
  function sameLine(a, b) {
    var x = plain(a), y = plain(b);
    if (!x || !y) return !x && !y;
    var cx = x.replace(/ /g, ''), cy = y.replace(/ /g, '');
    if (cy === cx) return true;
    if (cx.indexOf(cy) >= 0) return y.indexOf(' ') >= 0 || containsWord(x, y);
    if (cy.indexOf(cx) >= 0) return x.indexOf(' ') >= 0 || containsWord(y, x);
    return false;
  }

  var ARABIC = /[ؠ-يٮ-ۓۺ-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]/;
  function isArabic(text) { return ARABIC.test(String(text)); }

  // Yazıdaki düğme simgeleri.
  var ICONS = /(✕|○|△|□|●|[←-↓]|✜|▦|◆|[Ⓐ-Ⓩ]|\b[LR][123]\b|\bOPTIONS\b|\bTOUCHPAD\b)/;
  var FACES = { '✕': 1, '○': 1, '△': 1, '□': 1 };

  function iconPart(token) {
    if (FACES[token]) return { icon: 'face', key: token };
    if (/^[Ⓐ-Ⓩ]$/.test(token)) return { icon: 'marker', label: String.fromCharCode(token.charCodeAt(0) - 0x24B6 + 65) };
    if (/^[←-↓✜]$/.test(token)) return { icon: 'dpad', label: token };
    if (token === '▦' || token === 'TOUCHPAD') return { icon: 'pad', label: '' };
    if (/^[LR][12]$/.test(token) || token.length > 2) return { icon: 'pill', label: token };
    if (/^[LR]3$/.test(token)) return { icon: 'stick', label: token };
    return { icon: 'round', label: token };
  }

  // Göndericinin koyduğu tuş yer tutucusu (⟦T1⟧) için simge: icons listesindeki {id, name?, png?}.
  // Bilinen PS5 tuş adı kendi çizimimizle, yoksa PNG resim olarak çizilir. İkisi de yoksa yer tutucu hiç görünmez.
  var NAMED = {
    cross: { icon: 'face', key: '\u2715' }, circle: { icon: 'face', key: '\u25CB' },
    square: { icon: 'face', key: '\u25A1' }, triangle: { icon: 'face', key: '\u25B3' },
    options: { icon: 'pill', label: 'OPTIONS' }, create: { icon: 'pill', label: 'CREATE' },
    touchpad: { icon: 'pad', label: '' },
    'dpad-up': { icon: 'cross-pad', dir: 'up' }, 'dpad-down': { icon: 'cross-pad', dir: 'down' },
    'dpad-left': { icon: 'cross-pad', dir: 'left' }, 'dpad-right': { icon: 'cross-pad', dir: 'right' },
    dpad: { icon: 'cross-pad', dir: '' }
  };
  var PLACEHOLDER = /^T\d{1,2}$/;

  function givenIcon(id, icons) {
    for (var i = 0; icons && i < icons.length; i++) {
      var it = icons[i];
      if (!it || it.id !== id) continue;
      var name = typeof it.name === 'string' ? it.name.toLowerCase() : '';
      if (NAMED[name]) return NAMED[name];
      if (/^[lr][123]$/.test(name)) return { icon: name.charAt(1) === '3' ? 'stick' : 'pill', label: name.toUpperCase() };
      if (typeof it.png === 'string' && /^[A-Za-z0-9+\/=]+$/.test(it.png)) return { icon: 'image', src: 'data:image/png;base64,' + it.png };
      return null;
    }
    return null;
  }

  // Yazıyı parçalara ayırır: {text, accent?} ya da simge parçası. ⟦…⟧ vurgulu; ⟦Tn⟧ tuş yer tutucusu (icons'tan
  // simge olur, bulunamazsa atılır); tek kalan işaretler atılır.
  function parts(text, icons) {
    var out = [];
    var pieces = String(text).split(ICONS);
    for (var i = 0; i < pieces.length; i++) {
      if (!pieces[i]) continue;
      if (i % 2 === 1) { out.push(iconPart(pieces[i])); continue; }
      var bits = pieces[i].split(/(⟦[^⟧]*⟧)/);
      for (var b = 0; b < bits.length; b++) {
        var bit = bits[b];
        if (!bit) continue;
        if (bit.charAt(0) === '⟦' && bit.charAt(bit.length - 1) === '⟧') {
          var inner = bit.slice(1, -1);
          if (PLACEHOLDER.test(inner)) {
            var found = givenIcon(inner, icons);
            if (found) out.push(found);
          } else {
            out.push({ text: inner, accent: true });
          }
        }
        else out.push({ text: bit.replace(/[⟦⟧]/g, '') });
      }
    }
    return out;
  }

  // Altyazının dikdörtgeni engellerle çakışıyorsa ne kadar (piksel) yukarı çıkması gerektiği; çakışmıyorsa 0.
  // Yukarı çıkınca başka bir engele çarparsa onun da üstüne geçer.
  function lift(rect, obstacles, gap) {
    var up = 0;
    for (var round = 0; round < 8; round++) {
      var top = rect.top - up, bottom = rect.bottom - up;
      var hit = null;
      for (var i = 0; i < obstacles.length; i++) {
        var o = obstacles[i];
        if (rect.left < o.right && rect.right > o.left && top < o.bottom && bottom > o.top && (!hit || o.top < hit.top)) hit = o;
      }
      if (!hit) return up;
      up += bottom - hit.top + gap;
    }
    return up;
  }

  // Kullanıcının yazı boyu ayarı (bilgisayardaki "Yazı boyu", varsayılan 46 px) otomatik boya çarpan olarak uygulanır:
  // örtme ve oyuna bağlı yerleşimde boy İngilizce satırdan hesaplansa da kullanıcı büyütmesi etkili olur.
  var DEFAULT_SIZE = 46;
  // Otomatik boyda alttaki altyazı oyunun satırından %25 büyük çizilir (kullanıcı isteği, 22 Kasım); kullanıcının
  // yazı boyu ayarı bunun üstüne çarpılır.
  var AUTO_BOOST = 1.25;
  function autoFont(base, userSize, screenHeight) {
    var scale = typeof userSize === 'number' && userSize > 0 ? userSize / DEFAULT_SIZE : 1;
    scale = Math.max(0.5, Math.min(2.5, scale));
    var size = Math.round(base * AUTO_BOOST * scale);
    return Math.max(14, Math.min(Math.round(screenHeight * 0.14), size));
  }

  // Konuşanın adı. speaker verilmişse o; yoksa yazının başındaki büyük harfli "AD:" etiketi (en çok 3 sözcük,
  // ör. "ARTHUR:", "UNCLE JACK:"). Dönüş: {label, rest, inText} ya da null.
  //   inText: etiket yazının içinde mi (değilse çizerken başa eklenir)
  // Büyük-küçük harfi olmayan yazılarda (Arapça) yalnız speaker alanı kullanılır: "ملاحظة:" gibi sözcükler ad sanılmasın.
  function speakerOf(text, speaker) {
    text = String(text);
    var name = typeof speaker === 'string' ? speaker.replace(/^\s+|\s+$/g, '').replace(/[:\uFF1A]$/, '') : '';
    if (name) {
      var head = text.slice(0, name.length);
      var mark = text.charAt(name.length);
      if (head.toLowerCase() === name.toLowerCase() && (mark === ':' || mark === '\uFF1A')) {
        return { label: text.slice(0, name.length + 1), rest: text.slice(name.length + 1), inText: true };
      }
      return { label: name + ':', rest: ' ' + text, inText: false };
    }
    var m = /^((?:[^\s:\uFF1A]+ ){0,2}[^\s:\uFF1A]+)([:\uFF1A])(?=\s|$)/.exec(text);
    if (!m) return null;
    var word = m[1];
    var cased = word.toUpperCase() !== word.toLowerCase();
    if (!cased || word !== word.toUpperCase() || word.length < 2) return null;
    return { label: m[1] + m[2], rest: text.slice(m[0].length), inText: true };
  }

  var api = {
    lift: lift,
    speakerOf: speakerOf,
    autoFont: autoFont,
    AUTO_BOOST: AUTO_BOOST,
    DEFAULT_SIZE: DEFAULT_SIZE,
    LINE_CHARS: LINE_CHARS,
    wrap: wrap,
    words: words,
    plain: plain,
    sameLine: sameLine,
    isArabic: isArabic,
    parts: parts,
    charCount: charCount
  };
  root.Nino = root.Nino || {};
  root.Nino.text = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
