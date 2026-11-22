// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// LG webOS'a özgü işler (NINO_PLATFORM). Luna servisleri PalmServiceBridge ile çağrılır.
(function (root) {
  'use strict';

  var APP_ID = 'com.ninotranslator.tv';

  // Köprü nesneleri çöpe gitmesin diye cevap gelene kadar burada tutulur.
  var keep = [];

  function luna(uri, params, onReply) {
    var bridge = new root.PalmServiceBridge();
    bridge.onservicecallback = function (text) {
      var reply = null;
      try { reply = JSON.parse(text); } catch (e) { reply = null; }
      onReply(reply);
    };
    bridge.call(uri, JSON.stringify(params || {}));
    keep.push(bridge);
    if (keep.length > 40) keep.shift();
    return bridge;
  }

  function once(callback, fallbackMs) {
    var done = false;
    var timer = setTimeout(function () { finish(null); }, fallbackMs);
    function finish() {
      if (done) return;
      done = true;
      clearTimeout(timer);
      callback.apply(null, arguments);
    }
    return finish;
  }

  root.addEventListener('load', function () {
    setTimeout(function () {
      try {
        var info = JSON.parse((root.PalmSystem && root.PalmSystem.deviceInfo) || '{}');
        root.ninoReportTv('lg', info.modelName || info.modelNameAscii);
      } catch (e) {}
    }, 1000);
  });

  // Oyun kumandayla oynanır, TV kumandası boşta kalır: TV ekran koruyucuyu açmadan önce sorar, "hayır" denir.
  // Kayıt TV sürecinde yaşar; uygulama yeniden açılınca eski ad ölü kalabildiği için her açılışta yeni ad
  // kullanılır, reddedilirse başka adla en çok 4 kez denenir. (appinfo.json: screenSaverProperties.preferredType 2.)
  function holdScreenSaver() {
    var session = (+new Date()).toString(36);
    var tries = 0;
    function register() {
      var name = [APP_ID, session].concat(tries ? [tries] : []).join('.');
      tries++;
      var retried = false;
      luna('luna://com.webos.service.tvpower/power/registerScreenSaverRequest', { subscribe: true, clientName: name }, function (r) {
        if (!r) return;
        if (r.returnValue === false) {
          if (!retried && tries < 4) { retried = true; setTimeout(register, 1000); }
          return;
        }
        if (r.timestamp === undefined) return;
        luna('luna://com.webos.service.tvpower/power/responseScreenSaverRequest',
          { clientName: name, ack: false, timestamp: r.timestamp }, function () {});
      });
    }
    try {
      register();
    } catch (e) { /* servis yok */ }
  }

  root.NINO_PLATFORM = {
    backKey: 461,
    brand: 'lg',
    // PS5 girişine TV'nin kaynak menüsünden geçince Nino kapanıyor ya da ekran kararıyor: yönlendirme notu.
    sourceSwitchTip: true,
    tipOnFirstRun: true,
    tipKeys: 'lgInput',
    telemetryName: 'webos',
    osName: function () {
      try {
        var info = JSON.parse(root.PalmSystem.deviceInfo || '{}');
        return 'webOS ' + (info.platformVersion || info.version || '');
      } catch (e) {
        return 'webOS';
      }
    },
    noPictureHelp: true,

    init: holdScreenSaver,

    // 'playing' olayı gelmese de <video> kare aldıysa görüntü vardır.
    hasPicture: function () {
      var v = root.document.querySelector('#hdmi video');
      return !!v && (v.readyState >= 2 || v.videoWidth > 0);
    },

    launchParams: function () { return root.PalmSystem && root.PalmSystem.launchParams; },

    onRelaunch: function (handler) {
      root.document.addEventListener('webOSRelaunch', function (event) { handler(event.detail); });
    },

    // HDMI girişi <video> öğesiyle açılır; durumlar: loading, ready, playing, inputError, sourceError.
    showHdmi: function (port, host, report) {
      var doc = root.document;
      var player = doc.createElement('video');
      var input = doc.createElement('source');
      input.type = 'service/webos-external';
      input.src = 'ext://hdmi:' + (port || 1); // bilinmiyorsa HDMI 1
      player.autoplay = true;
      player.appendChild(input);
      // emptied/ended: görüntü gelirken giriş kayboldu (PS5 çıkış biçimini değiştirdi); sayfa yeniden açar.
      var says = { loadeddata: 'ready', playing: 'playing', error: 'inputError', emptied: 'lost', ended: 'lost' };
      Object.keys(says).forEach(function (event) {
        player.addEventListener(event, function () { report(says[event]); });
      });
      input.addEventListener('error', function () { report('sourceError'); });
      while (host.firstChild) host.removeChild(host.firstChild);
      report('loading');
      host.appendChild(player);
    },

    // Konsolun bağlı olduğu HDMI: GAME türü ya da PlayStation etiketi; etkin olan öncelikli.
    findConsolePort: function (done) {
      var answer = once(done, 3000);
      function isGame(d) {
        var words = [d.label, d.spdProductDescription].join(' ');
        return d.spdSourceDeviceInfo === 'GAME' || /playstation|ps5/i.test(words);
      }
      function firstActive(list) { return list.filter(function (d) { return d.activate; })[0]; }
      try {
        luna('luna://com.webos.service.eim/getAllInputStatus', {}, function (reply) {
          var inputs = ((reply && reply.devices) || []).filter(function (d) { return /^HDMI_/.test(d.id); });
          var games = inputs.filter(isGame);
          var best = firstActive(games) || games[0] || firstActive(inputs);
          if (best) answer(best.port, best.label);
          else answer(null, null);
        });
      } catch (e) {
        answer(null);
      }
    },

    // TV'nin yerel IPv4 adresi (kablolu öncelikli).
    localAddress: function (done) {
      var answer = once(done, 2000);
      try {
        luna('luna://com.webos.service.connectionmanager/getStatus', {}, function (reply) {
          var links = [(reply && reply.wired) || {}, (reply && reply.wifi) || {}];
          var up = links.filter(function (l) { return l.state === 'connected' && l.ipAddress; })[0];
          var any = links.filter(function (l) { return l.ipAddress; })[0];
          answer(up ? up.ipAddress : (any ? any.ipAddress : null));
        });
      } catch (e) {
        answer(null);
      }
    },

    exit: function () {
      if (root.PalmSystem && root.PalmSystem.platformBack) root.PalmSystem.platformBack();
    }
  };
})(window);
