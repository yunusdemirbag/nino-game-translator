// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Bekleme ekranının yağmurlu gece şehri: gökyüzü, ay, bulutlar, projektörler, iki sıra bina (pencereleriyle) ve
// çatıda pelerinli bir kahraman silueti. Çizim burada veriden kurulur; görünüm nino.css'te (#lobby-scene).
(function (root) {
  'use strict';

  var SVG = 'http://www.w3.org/2000/svg';

  // Binaların çatı çizgisi: [bitiş x, çatı y] (0–1920 × 0–700 tuvalde, soldan sağa).
  var FAR = [[90, 420], [150, 360], [240, 430], [300, 300], [330, 250], [380, 300], [470, 410], [560, 340], [600, 200],
    [620, 160], [660, 200], [760, 380], [860, 320], [940, 430], [1020, 280], [1110, 350], [1150, 230], [1170, 180],
    [1210, 230], [1300, 400], [1390, 330], [1480, 260], [1570, 420], [1660, 310], [1760, 380], [1840, 290], [1920, 410]];
  var NEAR = [[120, 500], [210, 430], [330, 520], [420, 380], [520, 470], [640, 560], [700, 450], [760, 400],
    [880, 470], [980, 540], [1080, 420], [1920, 600]];

  function node(name, attrs, parent) {
    var el = root.document.createElementNS(SVG, name);
    for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k)) el.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(el);
    return el;
  }

  // Her açılışta aynı pencereler yansın diye sabit tohumlu sayı üreteci.
  function seeded(seed) {
    var s = seed;
    return function () {
      s = (s * 1103515245 + 12345) % 2147483648;
      return s / 2147483648;
    };
  }

  function skyline(kind, steps, color, chance, seed) {
    var svg = node('svg', { 'class': 'skyline ' + kind, viewBox: '0 0 1920 700', preserveAspectRatio: 'none' });
    var d = 'M0 700';
    var x = 0;
    for (var i = 0; i < steps.length; i++) {
      d += ' V' + steps[i][1] + ' H' + steps[i][0];
    }
    node('path', { d: d + ' V700 Z' }, svg);
    var lights = node('g', {}, svg);
    var random = seeded(seed);
    var shades = [0.55, 0.75, 0.9];
    for (var j = 0; j < steps.length; j++) {
      var right = steps[j][0], roof = steps[j][1];
      for (var cx = x + 10; cx + 10 <= right - 6; cx += 22) {
        for (var cy = roof + 16; cy + 14 <= 700; cy += 30) {
          if (random() < chance) {
            node('rect', { x: cx, y: cy, width: 10, height: 14, fill: color, opacity: shades[Math.floor(random() * 3)] }, lights);
          }
        }
      }
      x = right;
    }
    return svg;
  }

  function rooftop() {
    var svg = node('svg', { 'class': 'rooftop', viewBox: '380 280 1540 800', preserveAspectRatio: 'xMaxYMax slice' });
    // Çatı ve kenarındaki taş çıkıntı.
    node('polygon', { points: '1180,1080 1180,900 1240,900 1240,870 1920,870 1920,1080' }, svg);
    node('polygon', { points: '1290,870 1300,840 1400,840 1410,870' }, svg);
    // Çömelmiş kahraman: baş, omuzlar, gövde; arkasında rüzgârda dalgalanan pelerin. Logo ya da kulak yok.
    node('path', { 'class': 'cloak', d: 'M1344 754 C1314 784 1276 826 1240 846 C1268 847 1302 843 1328 838 ' +
      'C1314 851 1298 861 1282 867 C1318 866 1346 857 1362 840 Z' }, svg);
    node('circle', { cx: 1356, cy: 731, r: 15 }, svg);
    node('path', { d: 'M1340 750 C1350 744 1364 744 1372 752 C1386 770 1394 792 1394 814 C1394 830 1390 840 1382 843 ' +
      'L1350 843 C1332 841 1320 824 1322 803 C1324 782 1332 764 1340 750 Z' }, svg);
    return svg;
  }

  function div(cls) {
    var el = root.document.createElement('div');
    el.className = cls;
    return el;
  }

  function build(host) {
    if (!host || host.firstChild) return;
    var parts = [div('sky'), div('moon'), div('cloud one'), div('cloud two'), div('glow'), div('light'), div('light two'),
      skyline('far', FAR, '#ffd78a', 0.16, 7), skyline('near', NEAR, '#ffcf7a', 0.11, 11), rooftop(), div('shadow')];
    for (var i = 0; i < parts.length; i++) host.appendChild(parts[i]);
  }

  root.Nino = root.Nino || {};
  root.Nino.buildScene = build;
})(window);
