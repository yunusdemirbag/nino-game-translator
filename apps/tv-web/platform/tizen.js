// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Samsung Tizen'e özgü işler (NINO_PLATFORM). HDMI görüntüsü TVWindow API'siyle sayfanın arkasında gösterilir.
(function (root) {
  'use strict';

  // Renkli tuşlar ve 0–4 kaydedilmezse TV onları kendisi kullanır.
  var REMOTE_KEYS = ['ColorF0Red', 'ColorF1Green', 'ColorF3Blue', '0', '1', '2', '3', '4'];

  function api() { return root.tizen; }
  function nothing() {}

  // Hata vermeden sistem bilgisi okur: bulamazsa fallback() çağrılır.
  function property(name, found, fallback) {
    try {
      api().systeminfo.getPropertyValue(name, found, fallback);
    } catch (e) {
      fallback();
    }
  }

  root.addEventListener('load', function () {
    setTimeout(function () {
      property('BUILD', function (build) { root.ninoReportTv('samsung', build ? build.model : ''); }, nothing);
    }, 1000);
  });

  // HDMI kaynakları: önce bağlı olanlar, sonra bağlı olmayanlar.
  function hdmiInputs(callback) {
    function keepHdmi(list) {
      return (list || []).filter(function (s) { return s.type === 'HDMI'; });
    }
    property('VIDEOSOURCE', function (vs) {
      callback(keepHdmi(vs.connected), keepHdmi(vs.disconnected));
    }, function () {
      callback([], []);
    });
  }

  // Gönderici uygulamayı açarken parametreleri AppControl'ün PAYLOAD verisinde (JSON) verir.
  function launchData() {
    var request;
    try { request = api().application.getCurrentApplication().getRequestedAppControl(); } catch (e) { return null; }
    var entries = (request && request.appControl && request.appControl.data) || [];
    var found = entries.filter(function (d) { return d.key === 'PAYLOAD' && d.value && d.value.length > 0; })[0];
    if (!found) return null;
    var parsed;
    try { parsed = JSON.parse(found.value[0]); } catch (e) { return null; }
    if (parsed && typeof parsed === 'object' && 'values' in parsed && parsed.values !== undefined) return parsed.values;
    return parsed;
  }

  root.NINO_PLATFORM = {
    backKey: 10009,
    brand: 'samsung',
    telemetryName: 'tizen',
    osName: function () {
      try {
        return 'Tizen ' + api().systeminfo.getCapability('http://tizen.org/feature/platform.version');
      } catch (e) {
        return 'Tizen';
      }
    },
    sourceSwitchTip: true,
    tipKeys: 'autoInput',
    noPictureHelp: true,

    init: function () {
      REMOTE_KEYS.forEach(function (name) {
        try { api().tvinputdevice.registerKey(name); } catch (e) {}
      });
      // TV boşta sanıp ekran koruyucuyu açmasın, ekranı karartmasın. Eski TV'lerde API yoksa geçilir.
      try {
        var common = root.webapis.appcommon;
        common.setScreenSaver(common.AppCommonScreenSaverState.SCREEN_SAVER_OFF);
      } catch (e) {}
      try { api().power.request('SCREEN', 'SCREEN_NORMAL'); } catch (e) {}
    },

    launchParams: launchData,

    onRelaunch: function (handler) {
      root.addEventListener('appcontrol', function () {
        var data = launchData();
        if (data) handler(data);
      });
    },

    showHdmi: function (port, host, report) {
      var wanted = port || 1;
      report('loading');
      hdmiInputs(function (plugged, unplugged) {
        var input = plugged.concat(unplugged).filter(function (s) { return s.number === wanted; })[0];
        if (!input) {
          report('sourceError');
          return;
        }
        var broken = function () { report('inputError'); };
        var fullScreen = ['0', '0', '100%', '100%'];
        try {
          api().tvwindow.setSource(input, function () {
            api().tvwindow.show(function () { report('playing'); }, broken, fullScreen, 'MAIN', 'BEHIND');
          }, broken);
        } catch (e) {
          broken();
        }
      });
    },

    // Önce kablolu, sonra kablosuz ağın adresi.
    localAddress: function (done) {
      var order = ['ETHERNET_NETWORK', 'WIFI_NETWORK'];
      (function next(i) {
        if (i >= order.length) return done(null);
        property(order[i], function (net) {
          if (net && net.ipAddress) done(net.ipAddress);
          else next(i + 1);
        }, function () { next(i + 1); });
      })(0);
    },

    // Tek bağlı HDMI varsa odur; birden çoksa TV'nin o anki girişi.
    findConsolePort: function (done) {
      hdmiInputs(function (plugged) {
        var choice = null;
        if (plugged.length === 1) {
          choice = plugged[0];
        } else if (plugged.length > 1) {
          try {
            var shown = api().tvwindow.getSource();
            if (shown.type === 'HDMI') choice = plugged.filter(function (s) { return s.number === shown.number; })[0] || null;
          } catch (e) {}
        }
        if (choice) done(choice.number, 'HDMI ' + choice.number);
        else done(null, null);
      });
    },

    exit: function () {
      try { api().application.getCurrentApplication().exit(); } catch (e) {}
    }
  };
})(window);
