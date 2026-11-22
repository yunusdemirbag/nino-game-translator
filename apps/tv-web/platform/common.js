// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// İki TV'nin ortak küçük işi: kurulu TV'nin markası ve modeli günde bir kez anonim olarak Nino havuzuna bildirilir
// (rastgele kimlik, marka, model, uygulama sürümü; ad, adres ya da hesap yok). Model göndericiye de söylenir.
// Paketleme bu dosyayı platform.js'in başına ekler.
(function (root) {
  'use strict';

  var POOL = 'https://nino-pool.y-demirbag2506.workers.dev/v1/tv';
  var DAY_MS = 20 * 3600 * 1000;
  var BRANDS = { lg: 'LG', samsung: 'Samsung' };

  // Rastgele bir UUID (sürüm 4 biçiminde).
  function randomId() {
    function hex(count) {
      var s = '';
      while (s.length < count) s += (Math.random() * 0x10000 | 0).toString(16);
      return s.slice(0, count);
    }
    var variant = '89ab'.charAt(Math.random() * 4 | 0);
    return [hex(8), hex(4), '4' + hex(3), variant + hex(3), hex(12)].join('-');
  }

  root.ninoReportTv = function (brand, model) {
    try {
      if (!model) return;
      root.NINO_TV_MODEL = (BRANDS[brand] ? BRANDS[brand] + ' ' : '') + model;
      var ls = root.localStorage;
      if (!ls) return;
      var t = new Date().getTime();
      if (t - parseInt(ls.getItem('ninoTvPing') || '0', 10) < DAY_MS) return;
      var id = ls.getItem('ninoTvId');
      if (!id) { id = randomId(); ls.setItem('ninoTvId', id); }
      ls.setItem('ninoTvPing', String(t));
      new root.Image().src = POOL + '?install=' + id + '&brand=' + brand + '&model=' +
        encodeURIComponent(String(model).slice(0, 60)) + '&app=' + encodeURIComponent(root.NINO_APP_VERSION || '');
    } catch (e) { /* isteğe bağlı */ }
  };
})(window);
