// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Mac'in gizli TV sayfası (yalnız admin/debug yapısı; AppSupport/TVPageRenderer.swift). Sayfanın geri kalanı
// apps/tv-web/src'nin aynısıdır; yalnız bu dosya farklı: HDMI yok (saydam), ağ yok, göndericiye bağlanılmaz.
// Mesajlar Mac'ten window.nino.receive ile gelir (TV'lere giden protokol mesajlarının aynısı).
(function (root) {
  'use strict';

  root.ninoReportTv = function () {};
  root.NINO_PLATFORM = {
    brand: 'mac-onizleme',
    backKey: 27,
    noPictureHelp: false,
    init: function () {},
    launchParams: function () { return null; },
    onRelaunch: function () {},
    showHdmi: function (port, host, report) {
      host.innerHTML = '';
      host.style.background = 'transparent';
      report('playing');
    },
    findConsolePort: function (callback) { callback(1); },
    localAddress: function (done) { done(null); },
    exit: function () {},
    // Bağlıymış gibi duran sahte bağlantı: bekleme sahnesi açılmaz, tarama ve ağ yok.
    makeLink: function (options) {
      var link = {
        address: { kind: 'nino', url: 'mac://onizleme' },
        known: function () { return true; },
        connect: function () {},
        scan: function () {},
        resume: function () {}
      };
      setTimeout(function () { if (options.onStatus) options.onStatus('ok'); }, 0);
      return link;
    }
  };
})(window);
