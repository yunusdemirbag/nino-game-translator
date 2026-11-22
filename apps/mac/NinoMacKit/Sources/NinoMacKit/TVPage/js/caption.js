// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Altyazı katmanı: gösterme, okuma payı, hızlı konuşma yığını, yerleşim, örtü ve biçim.
// Tarif: docs/yeni/tv-web/tarif.md §3.
(function (root) {
  'use strict';

  var doc = root.document;
  var T = root.Nino.text;

  var STACK_MS = 1500;        // önceki satır bu süre içinde geldiyse üstte kalır
  var OLD_HOLD_MS = 1500;     // üstteki satır bu kadar durur
  var OLD_FADE_MS = 400;      // sonra bu sürede solar
  var MIN_SHOW_MS = 1200;
  var READ_MAX_MS = 5000;     // "temizle" bu okuma payından önce silmez
  var SHADE_PAD = 0.012;
  var EDGE = 0.05;
  var MIN_BOTTOM = 3;
  var MAX_BOTTOM = 85;
  var COLORS = { white: '#FFFFFF', yellow: '#FFE135' };
  var PLACES = { fixed: 1, cover: 1, above: 1, below: 1 };

  var box = doc.getElementById('caption');
  var shade = doc.getElementById('shade');
  var current = box.querySelector('.current');
  var older = box.querySelector('.line.older');
  var old = box.querySelector('.line.old');

  var state = {
    size: 46,
    bottom: 7,
    place: 'fixed',
    stack: true,
    autoSize: true,
    band: false,
    textFill: '',
    shadeFill: '',
    shownAt: 0,
    paragraphs: false,
    readUntil: 0,
    target: null,     // oyundaki İngilizce satırın kutusu
    id: null,         // protokoldeki altyazı numarası
    position: 'bottom',
    heights: [],
    sizes: []
  };
  var hideTimer = null;
  var lineTimers = [];
  var hooks = { hidden: function () {}, obstacles: function () { return []; } };

  function now() { return new Date().getTime(); }
  function bodyFlag(name, on) {
    var list = ' ' + doc.body.className + ' ';
    list = list.replace(' ' + name + ' ', ' ');
    doc.body.className = (on ? list + name : list).replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
  }
  function hasFlag(name) { return (' ' + doc.body.className + ' ').indexOf(' ' + name + ' ') >= 0; }
  function screenHeight() { return doc.documentElement.clientHeight || root.innerHeight || 1080; }
  function screenWidth() { return doc.documentElement.clientWidth || root.innerWidth || 1920; }
  function visible() { return box.className.indexOf('off') < 0; }

  function validBox(b) {
    if (!b || typeof b !== 'object') return null;
    var sides = ['left', 'top', 'right', 'bottom'];
    for (var i = 0; i < sides.length; i++) {
      var v = b[sides[i]];
      if (typeof v !== 'number' || v < 0 || v > 1) return null;
    }
    return b.right > b.left && b.bottom > b.top ? b : null;
  }

  // --- Yazı ---

  var faceDefs = false;
  var FACE = {
    '✕': ['#a9cbff', '<line x1="35" y1="35" x2="65" y2="65"/><line x1="65" y1="35" x2="35" y2="65"/>'],
    '○': ['#ff9494', '<circle r="17" cx="50" cy="50"/>'],
    '△': ['#6eebc0', '<polygon points="50,31.5 69,64 31,64"/>'],
    '□': ['#ffa8e4', '<rect rx="2.5" x="33" y="33" width="34" height="34"/>']
  };

  // Dört yüz tuşunun ortak degradeleri sayfaya bir kez eklenir.
  function addFaceDefs() {
    if (faceDefs) return;
    faceDefs = true;
    var holder = doc.createElement('div');
    holder.style.cssText = 'position: absolute; overflow: hidden; width: 0; height: 0';
    holder.innerHTML = '<svg width="0" height="0"><defs>' +
      '<radialGradient id="nk-body" cx="50%" cy="30%" r="75%"><stop offset="0" stop-color="#3b3e48"/>' +
      '<stop offset="0.6" stop-color="#1c1d23"/><stop offset="1" stop-color="#0c0d10"/></radialGradient>' +
      '<linearGradient id="nk-edge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.75"/>' +
      '<stop offset="0.55" stop-color="#fff" stop-opacity="0.18"/><stop offset="1" stop-opacity="0.35" stop-color="#fff"/></linearGradient>' +
      '<linearGradient id="nk-shine" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.22"/>' +
      '<stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient></defs></svg>';
    doc.body.appendChild(holder);
  }

  function faceSvg(key) {
    var f = FACE[key];
    var ink = ' fill="none" stroke="' + f[0] + '" stroke-linecap="round" stroke-linejoin="round"';
    return '<svg viewBox="0 0 100 100">' +
      '<circle cx="50" cy="50" r="47" fill="url(#nk-body)"/>' +
      '<circle cx="50" cy="50" r="45.5" fill="none" stroke="url(#nk-edge)" stroke-width="3"/>' +
      '<ellipse cx="50" cy="27" rx="31" ry="15" fill="url(#nk-shine)"/>' +
      '<g' + ink + ' stroke-width="15" opacity="0.22">' + f[1] + '</g>' +
      '<g' + ink + ' stroke-width="8">' + f[1] + '</g></svg>';
  }

  function direction(el, text) {
    if (T.isArabic(text)) el.setAttribute('dir', 'rtl'); else el.removeAttribute('dir');
  }

  // Yazıyı simgeleri ve vurgularıyla öğeye yazar. Metin hiçbir zaman HTML olarak yorumlanmaz.
  // speaker: konuşanın adı (show.speaker) ya da null; ad sarı çizilir (yazıda "AD:" etiketi varsa o da).
  // Yön tuşu: artı biçimli pad, basılan yön parlak (kendi çizimimiz).
  function crossPadSvg(dir) {
    var arms = { up: 'M40 14h20v26H40z', down: 'M40 60h20v26H40z', left: 'M14 40h26v20H14z', right: 'M60 40h26v20H60z' };
    var lit = arms[dir] ? '<path d="' + arms[dir] + '" fill="#ffffff"/>' : '';
    return '<svg viewBox="0 0 100 100">' +
      '<circle cx="50" cy="50" r="47" fill="url(#nk-body)"/>' +
      '<circle cx="50" cy="50" r="45.5" fill="none" stroke="url(#nk-edge)" stroke-width="3"/>' +
      '<path d="M40 14h20v26h26v20H60v26H40V60H14V40h26z" fill="#8a8e99"/>' + lit +
      '<ellipse cx="50" cy="27" rx="31" ry="15" fill="url(#nk-shine)"/></svg>';
  }

  // icons: göndericinin tuş simgeleri ({id, name?, png?}); yazıdaki ⟦Tn⟧ yer tutucuları bunlarla çizilir.
  function rich(el, text, speaker, icons) {
    el.textContent = '';
    direction(el, text);
    var who = speaker === false ? null : T.speakerOf(text, speaker);
    if (who) {
      var name = doc.createElement('span');
      name.className = 'speaker';
      name.textContent = who.label;
      el.appendChild(name);
      text = who.rest;
    }
    var list = T.parts(text, icons);
    for (var n = 0; n < list.length; n++) {
      var p = list[n];
      var span;
      if (p.icon) {
        span = doc.createElement('span');
        if (p.icon === 'face') {
          addFaceDefs();
          span.className = 'key face';
          span.innerHTML = faceSvg(p.key);
        } else if (p.icon === 'cross-pad') {
          addFaceDefs();
          span.className = 'key face';
          span.innerHTML = crossPadSvg(p.dir);
        } else if (p.icon === 'image') {
          span.className = 'key shot';
          var img = doc.createElement('img');
          img.alt = '';
          img.src = p.src;
          span.appendChild(img);
        } else {
          span.className = p.icon === 'round' ? 'key' : 'key ' + p.icon;
          span.textContent = p.label;
        }
        el.appendChild(span);
      } else if (p.accent) {
        span = doc.createElement('span');
        span.className = 'accent'; // vurgulu sözcük
        span.textContent = p.text;
        el.appendChild(span);
      } else {
        el.appendChild(doc.createTextNode(p.text));
      }
    }
  }

  // Satırı yazar (simgeler, vurgu, konuşanın adı). Üstteki önceki satırlar da aynı biçimde, küçük boyda çizilir:
  // ⟦…⟧ işaretleri ya da tuş yer tutucuları hiçbir satırda düz metin olarak görünmez.
  function write(el, text, lines, size, withIcons, speaker, icons) {
    var w = lines ? { text: text, scale: 1 } : T.wrap(text);
    el.ninoText = text;
    el.ninoSpeaker = speaker;
    el.ninoIcons = icons;
    el.ninoScale = w.scale;
    rich(el, w.text, lines ? false : speaker, icons);
    el.style.whiteSpace = 'pre-line'; // satır sonları korunur
    el.style.fontSize = Math.round(size * w.scale) + 'px';
  }

  function textOf(el) { return el.ninoText !== undefined ? el.ninoText : el.textContent; }

  // --- Üstteki (önceki) satırlar ---

  function lineSlot(el) { return el === older ? 0 : 1; }

  function showLine(el, text, speaker, icons) {
    var i = lineSlot(el);
    clearTimeout(lineTimers[i * 2]);
    clearTimeout(lineTimers[i * 2 + 1]);
    write(el.firstChild, text, false, Math.round(state.size * 0.8), false, speaker, icons);
    el.className = el === older ? 'line older' : 'line old';
    lineTimers[i * 2] = setTimeout(function () {
      el.className += ' fading';
      lineTimers[i * 2 + 1] = setTimeout(function () { hideLine(el); }, OLD_FADE_MS);
    }, OLD_HOLD_MS);
  }

  function hideLine(el) {
    var i = lineSlot(el);
    clearTimeout(lineTimers[i * 2]);
    clearTimeout(lineTimers[i * 2 + 1]);
    el.className = (el === older ? 'line older' : 'line old') + ' off';
  }

  function lineShown(el) { return el.className.indexOf('off') < 0 && el.className.indexOf('fading') < 0; }

  function pushUp(text, speaker, icons) {
    var waiting = textOf(old.firstChild);
    if (lineShown(old) && waiting && !T.sameLine(waiting, text)) showLine(older, waiting, old.firstChild.ninoSpeaker, old.firstChild.ninoIcons);
    else hideLine(older);
    showLine(old, text, speaker, icons);
  }

  function dropLines() { hideLine(old); hideLine(older); }

  // --- Göster / kaldır ---

  // cmd: {text, durationMs (null: uzunluğa göre, 0: temizlenene kadar), box, paragraphs, replace, id, position}
  function show(cmd) {
    var t = now();
    var text = String(cmd.text);
    var shownText = textOf(current);
    var replacing = cmd.replace === true && !cmd.paragraphs && visible() && !!current.textContent;
    if (replacing) {
      // üstteki daha eski satırlar yerinde kalır
    } else if (state.stack && visible() && shownText && t - state.shownAt < STACK_MS && !cmd.paragraphs &&
        !state.paragraphs && !T.sameLine(shownText, text)) {
      pushUp(shownText, current.ninoSpeaker, current.ninoIcons);
    } else {
      dropLines();
    }
    state.shownAt = t;
    state.paragraphs = !!cmd.paragraphs;
    state.readUntil = t + Math.min(READ_MAX_MS, 2000 + text.length * 60);
    state.target = validBox(cmd.box);
    state.id = typeof cmd.id === 'number' ? cmd.id : null;
    state.position = cmd.position === 'top' ? 'top' : 'bottom';
    write(current, text, cmd.paragraphs, state.size, true, typeof cmd.speaker === 'string' ? cmd.speaker : null, cmd.icons || null);
    current.style.textAlign = cmd.paragraphs ? 'start' : '';
    box.className = '';
    layout();
    clearTimeout(hideTimer);
    hideTimer = null;
    var d = cmd.durationMs;
    if (d === 0) return; // protokol: clear gelene kadar
    var ms = d > 0 ? Math.max(MIN_SHOW_MS, d) : Math.min(8000, 2000 + text.length * 60);
    hideTimer = setTimeout(function () { hide('timer'); }, ms);
  }

  function hide(reason) {
    clearTimeout(hideTimer);
    hideTimer = null;
    var was = visible();
    box.className = 'off';
    shade.className = 'off';
    dropLines();
    if (was) hooks.hidden(reason);
  }

  // "Temizle": id verilmişse yalnız o altyazı; okuma payı dolmadıysa pay bitince.
  function clear(id) {
    if (typeof id === 'number' && state.id !== null && id !== state.id) return;
    var left = state.readUntil - now();
    if (left <= 0 || !visible()) return hide('clear');
    clearTimeout(hideTimer);
    hideTimer = setTimeout(function () { hide('clear-held'); }, left);
  }

  // --- Yerleşim ---

  function resetPlace() {
    box.style.left = '8%';
    box.style.right = '8%';
    if (state.position === 'top') {
      box.style.top = state.bottom + '%';
      box.style.bottom = 'auto';
    } else {
      box.style.top = 'auto';
      box.style.bottom = state.bottom + '%';
    }
    shade.className = 'off';
    bodyFlag('covering', false);
    current.style.background = state.textFill;
  }

  function measureSize(b, height) {
    var h = b.bottom - b.top;
    state.heights.push(h);
    if (state.heights.length > 24) state.heights.shift();
    var sorted = state.heights.slice().sort(function (a, c) { return a - c; });
    var single = sorted[Math.floor((sorted.length - 1) * 0.3)];
    var lines = Math.max(1, Math.round(h / Math.max(0.01, single)));
    state.sizes.push(Math.round(h * height / lines * 1.022));
    if (state.sizes.length > 7) state.sizes.shift();
    var mid = state.sizes.slice().sort(function (a, c) { return a - c; })[Math.floor(state.sizes.length / 2)];
    state.autoBase = Math.max(27, Math.min(Math.round(height * 0.0508), mid));
  }

  // Otomatik boy: İngilizce satırdan ölçülen boy × kullanıcının yazı boyu çarpanı.
  // Uzun çevirinin iki satıra sığdırma küçültmesi (T.wrap) korunur; yine de iki satırı aşarsa (dar alan, büyük boy)
  // sığana kadar küçülür, ama oyunun kendi altyazısından (ölçülen boy) küçük olmaz.
  function applyAutoFont(height) {
    if (!state.autoBase) return;
    var size = T.autoFont(state.autoBase, state.size, height);
    old.firstChild.style.fontSize = older.firstChild.style.fontSize = Math.round(size * 0.8) + 'px';
    var font = Math.round(size * (current.ninoScale || 1));
    var floor = Math.min(font, Math.max(27, state.autoBase));
    current.style.fontSize = font + 'px';
    while (font > floor && linesOf(current) > 2) {
      font -= 1;
      current.style.fontSize = font + 'px';
    }
  }

  function linesOf(el) {
    var cs = root.getComputedStyle ? root.getComputedStyle(el) : null;
    if (!cs) return 1;
    var lh = parseFloat(cs.lineHeight) || parseFloat(cs.fontSize) * 1.3;
    var pad = (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0);
    return Math.round((el.offsetHeight - pad) / lh);
  }

  function placeShade(b, text) {
    var w = screenWidth(), h = screenHeight();
    var left = (b.left - SHADE_PAD) * w, top = (b.top - SHADE_PAD) * h;
    var right = (b.right + SHADE_PAD) * w, bottom = (b.bottom + SHADE_PAD) * h;
    // Çeviri İngilizceden büyükse örtü onu da kaplar.
    if (text && text.width * text.height > 0) {
      left = Math.min(text.left, left);
      top = Math.min(text.top, top);
      right = Math.max(text.right, right);
      bottom = Math.max(text.bottom, bottom);
    }
    if (state.band) { left = 0; right = w; }
    shade.style.left = Math.round(left) + 'px';
    shade.style.top = 'auto';
    shade.style.bottom = Math.round(h - bottom) + 'px';
    shade.style.width = Math.round(right - left) + 'px';
    shade.style.height = Math.round(bottom - top) + 'px';
    shade.style.background = state.shadeFill;
    shade.className = '';
  }

  // remeasure: false ise otomatik boy yeniden ölçülmez (yalnız yerleşim tazelenir: yazı tipi geç yüklendi, ekran
  // çevirisi değişti). Ölçüm geçmişi her çağrıda büyümesin diye.
  function layout(remeasure) {
    resetPlace();
    var b = state.place === 'fixed' ? null : state.target;
    if (!b || !visible()) { avoid(); return; }
    var height = screenHeight();
    var mode = state.place;
    if (mode === 'below' && b.bottom > 0.88) mode = 'above';
    if (mode === 'above' && b.top < 0.12) mode = 'below';
    var middle = (b.left + b.right) / 2;
    var half = Math.max(0.3, Math.min(middle, 1 - middle));
    box.style.left = (Math.max(EDGE, middle - half) * 100) + '%';
    box.style.right = (Math.max(EDGE, 1 - middle - half) * 100) + '%';
    if (state.autoSize) {
      if (remeasure !== false || !state.autoBase) measureSize(b, height);
      applyAutoFont(height);
    }
    var gap = Math.round(0.012 * height);
    if (mode === 'cover') {
      var centre = (1 - (b.top + b.bottom) / 2) * height;
      box.style.top = 'auto';
      box.style.bottom = Math.max(0, Math.round(centre - current.offsetHeight / 2)) + 'px';
      placeShade(b, current.getBoundingClientRect());
      current.style.background = 'transparent';
      bodyFlag('covering', true);
    } else if ('above' === mode) {
      box.style.top = 'auto';
      box.style.bottom = Math.round((1 - b.top) * height + gap) + 'px';
    } else {
      box.style.bottom = 'auto';
      box.style.top = Math.round(b.bottom * height + gap) + 'px';
    }
    // Ekran dışına düştüyse (TV sayfa yüksekliğini yanlış bildiriyor olabilir) sabit yere döner.
    var r = box.getBoundingClientRect();
    var onScreen = r.height > 0 && r.top >= -2 && r.bottom <= height + 2 && r.right > 0 && r.left < screenWidth();
    if (!onScreen) resetPlace();
    avoid();
    // Yazı tipi sonradan yüklenirse (cam görünümün yuvarlak yazısı) çeviri genişler; örtü ve yer o zaman yeniden
    // ölçülür, yoksa çevirinin baş ve son harfleri örtünün dışında kalıyordu (canlı oyun, 22 Kasım).
    if (mode === 'cover') settleLater();
  }

  var settleTimer = null;
  function settleLater() {
    clearTimeout(settleTimer);
    settleTimer = setTimeout(function () { if (visible()) layout(false); }, 120);
    var fonts = doc.fonts;
    if (fonts && fonts.status !== 'loaded' && fonts.ready && fonts.ready.then) {
      fonts.ready.then(function () { if (visible()) layout(false); });
    }
  }

  // --- Ekran çevirisiyle çakışma ---
  // Altyazının kutusu ekran çevirisinin bir parçasıyla (ör. alttaki görev şeridi) çakışırsa altyazı o parçanın
  // üstüne itilir; örtü İngilizce satırın yerinde kalır. Parça listesi board.js'ten gelir (hooks.obstacles).
  function avoid() {
    if (!visible()) return;
    var list = hooks.obstacles();
    if (!list || !list.length) return;
    var height = screenHeight();
    var up = T.lift(current.getBoundingClientRect(), list, Math.round(0.012 * height));
    if (!up) return;
    // Örtme kipinde yazı örtüden ayrılır: kendi zeminini geri alır (yoksa zeminsiz kalırdı).
    if (hasFlag('covering')) {
      bodyFlag('covering', false);
      current.style.background = state.textFill;
    }
    var boxRect = box.getBoundingClientRect();
    box.style.top = 'auto';
    box.style.bottom = Math.max(0, Math.round(height - boxRect.bottom + up)) + 'px';
  }

  function setBottom(value) {
    state.bottom = Math.max(MIN_BOTTOM, Math.min(MAX_BOTTOM, value));
    layout();
  }

  // --- Biçim ---

  function eachText(fn) { fn(current); fn(old.firstChild); fn(older.firstChild); }

  function applyStyle(s, store) {
    if (typeof s.watermark === 'boolean') bodyFlag('no-watermark', !s.watermark);
    if (s.fontSize) {
      state.size = s.fontSize;
      var shownText = textOf(current);
      if (current.ninoText !== undefined && shownText) write(current, shownText, state.paragraphs, state.size, true, current.ninoSpeaker, current.ninoIcons);
      else current.style.fontSize = s.fontSize + 'px';
      old.firstChild.style.fontSize = older.firstChild.style.fontSize = Math.round(s.fontSize * 0.8) + 'px';
    }
    if (PLACES[s.placement]) state.place = s.placement;
    state.band = s.backgroundShape === 'band';
    bodyFlag('band', state.band);
    if (typeof s.background === 'number') {
      var a = Math.max(0, Math.min(100, s.background)) / 100;
      bodyFlag('thin-bg', a < 0.3);
      state.textFill = 'rgba(0, 0, 0, ' + a + ')';
      state.shadeFill = s.background >= 100 ? '#000' : state.textFill;
      var glass = s.background >= 90;
      bodyFlag('glass', glass);
      if (glass) {
        state.textFill = 'rgba(16, 16, 16, 0.8)';
        state.shadeFill = 'rgba(16, 16, 16, 0.86)';
      }
      current.style.background = state.textFill;
      old.firstChild.style.background = older.firstChild.style.background = 'rgba(0, 0, 0, ' + (a * 0.83).toFixed(2) + ')';
    }
    // Ayarı göndermeyen gönderici eski davranışı bekler: önceki satırlar üstte kalır.
    state.stack = typeof s.stackPrevious === 'boolean' ? s.stackPrevious : true;
    store('stackPrevious', state.stack ? '1' : '0');
    if (!state.stack) dropLines();
    if (typeof s.bold === 'boolean') eachText(function (el) { el.style.fontWeight = s.bold ? '700' : '600'; });
    if (typeof s.autoSize === 'boolean') state.autoSize = s.autoSize;
    if (typeof s.font === 'string') doc.body.setAttribute('data-font', s.font);
    if (typeof s.theme === 'string') doc.body.setAttribute('data-theme', s.theme);
    if (COLORS[s.textColor]) eachText(function (el) { el.style.color = COLORS[s.textColor]; });
    // Biçim değişti: ekrandaki altyazı hemen yeni boy ve biçimle yeniden yerleşir (ölçüm geçmişi büyümez).
    layout(false);
  }

  // Sahne ışığı (cam görünümde): aydınlık sahnede zemin koyulaşır.
  function applyLight(light) {
    var l = Math.max(0, Math.min(1, light));
    if (!hasFlag('glass')) return;
    state.textFill = 'rgba(10, 10, 10, ' + (0.3 + 0.55 * l).toFixed(2) + ')';
    shade.style.setProperty('box-shadow', '0 0 ' + Math.round(14 + 22 * l) + 'px ' + Math.round(2 + 8 * l) +
      'px rgba(10, 10, 10, ' + (0.5 + 0.4 * l).toFixed(2) + ')', 'important');
  }

  // Buzlu örtü: sahnenin bulanık hali (base64 JPEG) örtünün zemini olur.
  function applyFrost(jpeg) {
    if (jpeg && hasFlag('glass')) {
      shade.style.setProperty('background', 'linear-gradient(rgba(0, 0, 0, 0.16), rgba(0, 0, 0, 0.16)), url(data:image/jpeg;base64,' +
        jpeg + ') center / 100% 100% no-repeat', 'important');
      shade.style.setProperty('box-shadow', 'none', 'important');
      bodyFlag('frosted', true);
    } else {
      shade.style.removeProperty('background');
      bodyFlag('frosted', false);
    }
  }

  root.Nino.caption = {
    show: show,
    hide: hide,
    clear: clear,
    layout: layout,
    applyStyle: applyStyle,
    applyLight: applyLight,
    applyFrost: applyFrost,
    setBottom: setBottom,
    visible: visible,
    rich: rich,
    validBox: validBox,
    bottom: function () { return state.bottom; },
    fixed: function () { return state.place === 'fixed'; },
    setStack: function (on) { state.stack = on; },
    onHidden: function (fn) { hooks.hidden = fn; },
    obstacles: function (fn) { hooks.obstacles = fn; },
    reflow: function () { if (visible()) layout(false); }
  };
})(window);
