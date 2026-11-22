// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Ekran çevirisi (telefon balonları, harita kartı, görev yazısı) ve köşe yazıları. Tarif: tarif.md §4.
(function (root) {
  'use strict';

  var doc = root.document;
  var caption = root.Nino.caption;
  var valid = caption.validBox;

  var board = doc.getElementById('board');
  var areas = doc.getElementById('areas');

  var PAD = 0.004, PAD_X = 0.018, PAD_Y = 0.008;
  var MIN_FONT = 14, MAX_FONT = 96, BUBBLE_MIN = 11;
  var DEFAULT_MS = 20000;
  var timer = null;

  function hex(v) { return typeof v === 'string' && /^#[0-9a-fA-F]{6}$/.test(v) ? v : null; }
  function rgba(color, alpha) {
    return 'rgba(' + parseInt(color.substr(1, 2), 16) + ',' + parseInt(color.substr(3, 2), 16) + ',' +
      parseInt(color.substr(5, 2), 16) + ',' + alpha + ')';
  }
  function size() { return { w: root.innerWidth || 1920, h: root.innerHeight || 1080 }; }
  function lineHeight(item, h, fallback) { return typeof item.line === 'number' && item.line > 0 ? item.line * h : fallback; }

  function place(el, b, s) {
    el.style.left = (b.left * 100) + '%';
    el.style.top = (b.top * 100) + '%';
    if (s) {
      el.style.width = ((b.right - b.left) * s.w) + 'px';
      el.style.height = ((b.bottom - b.top) * s.h) + 'px';
    }
  }

  // Bir düz öğe aşağıya doğru en çok nereye kadar uzayabilir: altında yatayda çakışan bağımsız öğenin üstüne kadar.
  function roomBelow(items, b, left, width, s) {
    var limit = s.h;
    for (var i = 0; i < items.length; i++) {
      var other = items[i];
      var ob = valid(other && other.box);
      if (!ob || !other.text || ob.top < b.bottom) continue;
      var oLeft = Math.max(0, ob.left - PAD_X) * s.w;
      var oWidth = Math.max(80, Math.min(1, ob.right + PAD) * s.w - oLeft);
      if (left < oLeft + oWidth && left + width > oLeft) limit = Math.min(limit, Math.max(0, ob.top - PAD_Y) * s.h);
    }
    return limit;
  }

  // title: panelin başlığı (gönderenin adı). Eski göndericide panelin kendi metnidir; yeni göndericide (NinoCore)
  // panelin üst kısmındaki ayrı bir sade yazı öğesidir ve prepare() onu panele bağlar. İkisi de ortalı çizilir.
  function panel(item, b, s, title) {
    var el = doc.createElement('div');
    el.className = 'piece panel';
    el.setAttribute('data-text', '');
    el.style.background = rgba(item.fill, typeof item.alpha === 'number' ? item.alpha : 1);
    place(el, b, s);
    var mark = doc.createElement('img');
    mark.src = 'img/nino-badge.png';
    mark.alt = '';
    el.appendChild(mark);
    var head = title || (typeof item.text === 'string' && item.text ? { text: item.text, line: item.line } : null);
    if (head) {
      var from = doc.createElement('div');
      from.className = 'from';
      from.textContent = head.text;
      from.style.fontSize = Math.max(BUBBLE_MIN, Math.round(lineHeight(head, s.h, 24) * 1.05)) + 'px';
      if (hex(head.ink)) from.style.color = head.ink;
      el.appendChild(from);
    }
    return el;
  }

  function bubble(item, b, s, index, fill) {
    var el = doc.createElement('div');
    el.className = 'piece bubble' + (item.frost === true ? ' frost' : '') + (item.side === true ? ' side' : '');
    el.setAttribute('data-text', String(item.text));
    caption.rich(el, item.text, undefined, item.icons);
    el.style.background = typeof item.alpha === 'number' && item.alpha >= 0 && item.alpha < 1 ? rgba(fill, item.alpha) : fill;
    el.style.color = hex(item.ink) || '#1c1c1e';
    if (item.side === true) el.style.animationDelay = el.style.webkitAnimationDelay = (Math.min(index, 8) * 60) + 'ms';
    var w = Math.max(40, (b.right - b.left) * s.w);
    var h = Math.max(12, (b.bottom - b.top) * s.h);
    place(el, b);
    el.style.width = w + 'px';
    el.style.height = h + 'px';
    var font = Math.max(BUBBLE_MIN, Math.min(64, Math.round(lineHeight(item, s.h, h) * 0.98)));
    el.style.fontSize = font + 'px';
    var tilt = typeof item.angle === 'number' ? Math.abs(item.angle) : 0;
    if (tilt >= 0.3 && tilt <= 30) {
      el.style.transform = el.style.webkitTransform = 'rotate(' + item.angle + 'deg)';
    }
    board.appendChild(el);
    // Türkçe çoğu zaman uzundur: balona sığana kadar küçülür.
    while ((el.scrollHeight > h + 1 || el.scrollWidth > w + 1) && font > BUBBLE_MIN) {
      font -= 1;
      el.style.fontSize = font + 'px';
    }
    return el;
  }

  // Balonun yeri, boyu ve eğikliği (yeniden çizmeden güncellenebilsin diye ayrı).
  function placeBubble(el, item, b, s) {
    place(el, b);
    el.style.width = Math.max(40, (b.right - b.left) * s.w) + 'px';
    el.style.height = Math.max(12, (b.bottom - b.top) * s.h) + 'px';
    var tilt = typeof item.angle === 'number' ? Math.abs(item.angle) : 0;
    el.style.transform = el.style.webkitTransform = tilt >= 0.3 && tilt <= 30 ? 'rotate(' + item.angle + 'deg)' : '';
  }

  // card: harita kartı kutusuna tam oturur (gönderici kutuyu kartın oyundaki çerçevesi olarak yollar): pay yok,
  // yükseklik de kutu kadar.
  function placePiece(el, b, s, card) {
    if (card) {
      place(el, b, s);
      el.style.minWidth = el.style.minHeight = '';
      return;
    }
    var left = Math.max(0, b.left - PAD_X);
    var width = Math.max(80, (Math.min(1, b.right + PAD) - left) * s.w);
    place(el, { left: left, top: Math.max(0, b.top - PAD_Y) });
    el.style.width = width + 'px';
    // Sade yazı (görev şeridi) yazısı kadar daralır; yine de oyundaki İngilizcenin tamamını örtsün diye en az kutu
    // genişliğindedir (canlı oyun: "Lose the Kolts"un pembe "Kolts"u sağda açıkta kalıyordu).
    el.style.minWidth = width + 'px';
  }

  function piece(items, item, b, s) {
    var el = doc.createElement('div');
    el.className = 'piece' + (item.paragraphs === true ? ' lines' : '') + (item.plain === true ? ' plain' : '') +
      (item.card === true ? ' map' : '') + (item.italic === true ? ' italic' : '');
    caption.rich(el, item.text, undefined, item.icons);
    if (item.card === true) return mapCard(el, item, b, s);
    // Süslü İngilizce harfler kutudan taşar: örtü solda ve dikeyde geniş, sağda (düğme simgesine doğru) dar.
    var left = Math.max(0, b.left - PAD_X);
    var top = Math.max(0, b.top - PAD_Y);
    var boxHeight = (b.bottom - b.top + 2 * PAD_Y) * s.h;
    var width = Math.max(80, (Math.min(1, b.right + PAD) - left) * s.w);
    placePiece(el, b, s);
    if (b.left > 0.5) el.style.textAlign = 'right';
    var room = Math.max(0, Math.floor(roomBelow(items, b, left * s.w, width, s) - top * s.h) - 1);
    el.style.minHeight = Math.min(Math.round(boxHeight), room) + 'px';
    var line = lineHeight(item, s.h, (b.bottom - b.top) * s.h);
    var font = Math.max(MIN_FONT, Math.min(MAX_FONT, Math.round(line * 0.95)));
    el.style.fontSize = font + 'px';
    board.appendChild(el);
    var limit = Math.min(room, Math.max(boxHeight * 1.5, line * 2.6));
    while (el.scrollHeight > limit && font > MIN_FONT) {
      font = Math.max(MIN_FONT, font - 2);
      el.style.fontSize = font + 'px';
    }
    return el;
  }

  // Harita kartı: kutuya tam oturur; yazı satır boyundan başlar, sığana kadar 1 px küçülür.
  function mapCard(el, item, b, s) {
    placePiece(el, b, s, true);
    var height = (b.bottom - b.top) * s.h;
    var font = Math.max(MIN_FONT, Math.min(MAX_FONT, Math.round(lineHeight(item, s.h, height) * 0.95)));
    el.style.fontSize = font + 'px';
    board.appendChild(el);
    while (el.scrollHeight > el.clientHeight + 1 && font > MIN_FONT) {
      font -= 1;
      el.style.fontSize = font + 'px';
    }
    return el;
  }

  // --- Çizim planı ---
  // Gelen listeden çizilecek parçalar: {kind: panel|bubble|piece, item, box, title?}. Yeni göndericinin telefon
  // başlığı (panelin üst %15'indeki, zeminsiz sade yazı) ayrı parça olmaz, panelin ortalı başlığı olur.
  function prepare(items) {
    var plan = [];
    var panels = [];
    var i, item, b;
    for (i = 0; i < items.length; i++) {
      item = items[i];
      b = valid(item && item.box);
      if (b && item.backdrop === true && hex(item.fill)) panels.push({ item: item, box: b, entry: null });
    }
    function headerOf(it, bx) {
      if (it.plain !== true || hex(it.fill) || !it.text) return null;
      for (var p = 0; p < panels.length; p++) {
        var pb = panels[p].box;
        var high = pb.top + (pb.bottom - pb.top) * 0.15;
        var inside = bx.left >= pb.left - 0.01 && bx.right <= pb.right + 0.01 && bx.top >= pb.top - 0.01 && bx.top <= high;
        if (inside && !panels[p].title && !panels[p].item.text) return panels[p];
      }
      return null;
    }
    for (i = 0; i < items.length; i++) {
      item = items[i];
      b = valid(item && item.box);
      if (!b) continue;
      var fill = hex(item.fill);
      if (item.backdrop === true && fill) {
        var entry = { kind: 'panel', item: item, box: b };
        for (var p = 0; p < panels.length; p++) if (panels[p].item === item) panels[p].entry = entry;
        plan.push(entry);
        continue;
      }
      if (!item.text) continue;
      var owner = headerOf(item, b);
      if (owner) {
        owner.title = { text: String(item.text), line: item.line, ink: item.ink };
        if (owner.entry) owner.entry.title = owner.title;
        continue;
      }
      plan.push({ kind: fill ? 'bubble' : 'piece', item: item, box: b });
    }
    // Başlık panelden önce geldiyse de bağlansın.
    for (var q = 0; q < panels.length; q++) if (panels[q].entry && panels[q].title) panels[q].entry.title = panels[q].title;
    return plan;
  }

  // İçeriğin imzası: yer, boy, eğiklik ve satır boyu dışındaki her şey. İmza aynıysa liste "aynı" sayılır.
  var SAME_KEYS = ['text', 'fill', 'ink', 'alpha', 'paragraphs', 'plain', 'card', 'italic', 'frost', 'side', 'backdrop'];
  function signature(plan) {
    var out = [];
    for (var i = 0; i < plan.length; i++) {
      var it = plan[i].item;
      var part = [plan[i].kind, plan[i].title ? plan[i].title.text : ''];
      for (var k = 0; k < SAME_KEYS.length; k++) part.push(it[SAME_KEYS[k]] === undefined ? null : it[SAME_KEYS[k]]);
      out.push(part);
    }
    return JSON.stringify(out);
  }

  var drawn = [];        // çizili parçalar: {kind, el}
  var drawnSig = null;

  // Aynı içerik yeniden geldiyse (gönderici listeyi tazeliyor ya da telefon elde sallanıyor) hiçbir şey yeniden
  // çizilmez, canlandırma oynamaz: yalnız yerler yumuşakça güncellenir ve süre sayacı baştan başlar.
  function refresh(plan, sig, ms) {
    var live = board.className === '' || board.className === 'steady';
    if (!live || sig !== drawnSig || drawn.length !== plan.length || !plan.length) return false;
    var s = size();
    for (var i = 0; i < plan.length; i++) {
      var d = drawn[i];
      if (d.kind === 'panel') place(d.el, plan[i].box, s);
      else if (d.kind === 'bubble') placeBubble(d.el, plan[i].item, plan[i].box, s);
      else placePiece(d.el, plan[i].box, s, plan[i].item.card === true);
    }
    restart(ms);
    if (caption.reflow) caption.reflow();
    return true;
  }

  // ms: > 0 bu kadar sonra kalkar; 0 = süresiz (screen-clear ya da yeni screen kaldırır); null = varsayılan 20 sn.
  function restart(ms) {
    clearTimeout(timer);
    timer = null;
    if (ms === 0) return;
    timer = setTimeout(hide, ms > 0 ? ms : DEFAULT_MS);
  }

  function show(items, ms, overlay) {
    var plan = prepare(items || []);
    var sig = signature(plan);
    if (refresh(plan, sig, ms)) return;
    var steady = (board.className === '' || board.className === 'steady') && !!board.querySelector('.piece.panel');
    if (overlay !== true) caption.hide('screen');
    board.innerHTML = '';
    board.className = steady ? 'steady' : '';
    drawn = [];
    drawnSig = sig;
    var s = size();
    for (var i = 0; i < plan.length; i++) {
      var e = plan[i];
      var el;
      if (e.kind === 'panel') el = board.appendChild(panel(e.item, e.box, s, e.title));
      else if (e.kind === 'bubble') el = bubble(e.item, e.box, s, i, hex(e.item.fill));
      else el = piece(items, e.item, e.box, s);
      drawn.push({ kind: e.kind, el: el });
    }
    restart(ms);
    if (caption.reflow) caption.reflow();
  }

  function hide() {
    clearTimeout(timer);
    drawn = [];
    drawnSig = null;
    if (board.className !== 'off' && board.querySelector('.piece.side, .piece.panel')) {
      board.className = 'leaving';
      timer = setTimeout(function () { board.className = 'off'; board.innerHTML = ''; }, 320);
    } else {
      board.className = 'off';
      board.innerHTML = '';
    }
    // Ekran çevirisi gitti: kaçmak için yukarı itilmiş altyazı yerine döner.
    if (caption.reflow) caption.reflow();
  }

  // --- Köşe yazıları ---

  var open = {};
  var A_PAD = 0.004, A_MIN = 18, A_MAX = 44, ABOVE_MAX_H = 0.16;

  function showArea(data) {
    var id = (data && typeof data.id === 'string' && data.id) || '';
    if (!id) return;
    var b = valid(data.box);
    if (!data.text || !b) return hideArea(id);
    var el = open[id];
    if (!el) {
      el = doc.createElement('div');
      areas.appendChild(el);
      open[id] = el;
    }
    areas.className = '';
    var s = size();
    caption.rich(el, String(data.text), false, data.icons);
    ['left', 'right', 'top', 'bottom'].forEach(function (side) { el.style[side] = ''; });
    var rightHalf = (b.left + b.right) / 2 > 0.5;
    var lowerHalf = (b.top + b.bottom) / 2 > 0.5;
    if (rightHalf) el.style.right = (Math.max(0, 1 - b.right - A_PAD) * 100) + '%';
    else el.style.left = (Math.max(0, b.left - A_PAD) * 100) + '%';
    // Alt yarıdaki kısa yazının çevirisi yazının üstünde durur; asıl yazı görünür kalır.
    var above = lowerHalf && b.bottom - b.top <= ABOVE_MAX_H;
    el.className = above ? 'area above' : 'area';
    if (above) el.style.bottom = (Math.min(1, 1 - b.top + A_PAD * 2) * 100) + '%';
    else if (lowerHalf) el.style.bottom = (Math.max(0, 1 - b.bottom - A_PAD) * 100) + '%';
    else el.style.top = (Math.max(0, b.top - A_PAD) * 100) + '%';
    var width = (b.right - b.left + 2 * A_PAD) * s.w;
    el.style.minWidth = Math.round(width) + 'px';
    el.style.maxWidth = Math.round(Math.max(width, s.w * 0.3)) + 'px';
    el.style.fontSize = Math.max(A_MIN, Math.min(A_MAX, Math.round(lineHeight(data, s.h, 30) * 0.9))) + 'px';
  }

  function hideArea(id) {
    if (!open[id]) return;
    areas.removeChild(open[id]);
    delete open[id];
  }

  function hideAreas() {
    for (var id in open) if (Object.prototype.hasOwnProperty.call(open, id)) areas.removeChild(open[id]);
    open = {};
    areas.className = 'off';
  }

  // Çizili parçaların ekrandaki dikdörtgenleri (altyazı bunlarla çakışmasın diye). Telefon paneli ve balonlar
  // dahildir; kalkmakta olan (solan) ekran sayılmaz.
  function rects() {
    if (board.className === 'off' || board.className === 'leaving') return [];
    var out = [];
    for (var i = 0; i < drawn.length; i++) {
      var r = drawn[i].el && drawn[i].el.getBoundingClientRect ? drawn[i].el.getBoundingClientRect() : null;
      if (r && r.width > 0 && r.height > 0) out.push({ left: r.left, top: r.top, right: r.right, bottom: r.bottom });
    }
    return out;
  }

  root.Nino.board = { show: show, hide: hide, showArea: showArea, hideAreas: hideAreas, rects: rects, prepare: prepare, signature: signature };
})(window);
