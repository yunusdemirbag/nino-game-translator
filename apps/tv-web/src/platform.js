// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Tarayıcı önizlemesi için sahte TV (geliştirme). Paketlerde bunun yerine platform/webos.js ya da platform/tizen.js
// kullanılır. HDMI görüntüsü yerine koyu bir zemin gösterilir; adres sorusu "bilinmiyor" döner.
// Önizleme adresine ?hdmi=yok eklenirse "görüntü yok" kutusu, ?server=… ile bağlantı, ?ip=… ile tarama, ?lg=1 ile
// LG'nin giriş notu denenir.
(function (root) {
  'use strict';

  var noPicture = /[?&]hdmi=yok/.test(root.location.search);
  var lg = /[?&]lg=1/.test(root.location.search);
  // Denemeler için: HDMI kaç kez açıldı, son durum bildirimi, yeniden başlatma (relaunch) taklidi.
  root.__hdmiOpens = 0;
  root.__hdmiReport = null;
  root.__relaunch = null;

  root.ninoReportTv = function () {};
  root.NINO_PLATFORM = {
    backKey: 27, // Esc
    noPictureHelp: noPicture,
    init: function () {},
    launchParams: function () { // ?server=… ile bağlantı denenir
      var m = /[?&]server=([^&]+)/.exec(root.location.search);
      return m ? { server: decodeURIComponent(m[1]) } : null;
    },
    onRelaunch: function (handler) { root.__relaunch = handler; },
    sourceSwitchTip: lg,
    tipOnFirstRun: lg,
    tipKeys: lg ? 'lgInput' : 'autoInput',
    showHdmi: function (port, host, report) {
      root.__hdmiOpens++;
      root.__hdmiReport = report;
      host.innerHTML = '';
      host.style.background = 'linear-gradient(160deg, #1d2633, #0b0f16)';
      report('loading');
      setTimeout(function () { report(noPicture ? 'inputError' : 'playing'); }, 50);
    },
    findConsolePort: function (callback) { callback(null); },
    // ?ip=127.0.0.1 ile ağ taraması da denenir.
    localAddress: function (done) {
      var m = /[?&]ip=([0-9.]+)/.exec(root.location.search);
      done(m ? m[1] : null);
    },
    exit: function () {}
  };
})(window);
