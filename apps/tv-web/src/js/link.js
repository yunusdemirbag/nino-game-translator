// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Göndericiye (Mac, telefon) bağlantı. Yeni göndericiye Nino Bağlantı Protokolü ile (TV arar, WebSocket), eskisine
// 8787'deki olay akışıyla (EventSource) bağlanır; adres bilinmiyorsa ağı tarar. Bkz. docs/yeni/tv-web/baglanti.md.
// Tarayıcıya özgü nesneler (WebSocket, EventSource, XMLHttpRequest, zamanlayıcılar) env ile değiştirilebilir (testler).
(function (root) {
  'use strict';

  var P = root.Nino.protocol;

  // Süreler (options.timing ile testte kısaltılabilir).
  var TIMING = {
    dropMs: 6000,            // kopmadan bu kadar sonra ekran temizlenir
    backoff: [1000, 2000, 4000, 8000],
    silenceMs: 15000,        // yeni gönderici 5 sn'de bir ping yollar: 15 sn hiç mesaj yoksa bağlantı ölüdür
    connectMs: 10000,        // bu sürede el sıkışma bitmezse bağlantı bırakılıp yeniden denenir
    legacySilenceMs: 25000,  // eski gönderici 15 sn'de bir ping yollar
    legacyStuckMs: 30000,    // eski akış bu kadar süre "bağlanıyor"da kalırsa baştan kurulur
    watchMs: 5000
  };
  // Saha hatası (Samsung Tizen 8, eski 8787 düzeni, 22 Kasım): TV uygulaması arka plana düşüp geri gelince ya da
  // ağ bir an gidince bağlantı ölü kalıyor, TV geri bağlanmıyordu. Bekçi bu yüzden sessizliği, asılı kalan bağlantıyı
  // ve uygulamanın öne gelişini (resume) ayrı ayrı yakalar; yeniden deneme hiç bitmez.
  var SCAN_PARALLEL = 24;
  var SCAN_TIMEOUT_MS = 1200;   // tek adres yoklaması
  var SCAN_AGAIN_MS = 30000;
  var SCAN_SOON_MS = 3000;
  var FAILS_BEFORE_SCAN = 3;    // art arda bu kadar başarısızlıkta hemen tara

  // options: platform, store {get,set}, name(), model(), onStatus(kind), onCommand(cmd), onDrop(), onTvAddress(ip), env
  function Link(options) {
    var env = options.env || root;
    var self = this;
    this.t = {};
    for (var k in TIMING) if (Object.prototype.hasOwnProperty.call(TIMING, k)) this.t[k] = (options.timing && options.timing[k]) || TIMING[k];
    this.o = options;
    this.env = env;
    this.address = null;   // çözülmüş adres {kind, url, base, host}
    this.socket = null;
    this.events = null;
    this.session = null;
    this.failures = 0;
    this.retry = 0;
    this.retryTimer = null;
    this.dropTimer = null;
    this.scanTimer = null;
    this.scanAt = 0;
    this.scanning = false;
    this.lastHeard = 0;
    this.pinged = false;
    this.tvAddress = null;
    this.problem = null;   // son kopmanın nedeni (ölçüm): timeout, resume, closed, tv.protocol.mismatch…
    this.openedAt = 0;
    this.ready = false;
    this.watcher = env.setInterval(function () { self.watch(); }, this.t.watchMs);
  }

  Link.prototype.now = function () { return this.env.now ? this.env.now() : new Date().getTime(); };

  Link.prototype.known = function () { return !!this.address; };

  // Yeni adres (açılış parametresi, kayıt ya da tarama). Aynı adrese bağlıysa dokunulmaz.
  Link.prototype.connect = function (raw) {
    var a = P.parseAddress(raw);
    if (!a) return false;
    if (this.address && this.address.url !== a.url) this.failures = 0;
    this.address = a;
    this.o.store.set('server', a.kind === 'legacy' ? a.base : a.url);
    this.open();
    return true;
  };

  Link.prototype.close = function () {
    var s = this.socket, e = this.events;
    this.socket = this.events = null;
    if (this.session) this.session.shut();
    this.session = null;
    this.env.clearTimeout(this.retryTimer);
    this.retryTimer = null;
    if (s) { s.onopen = s.onclose = s.onerror = s.onmessage = null; try { s.close(); } catch (x) {} }
    if (e) { try { e.close(); } catch (x) {} }
  };

  Link.prototype.open = function () {
    this.close();
    this.o.onStatus('connecting');
    this.lastHeard = this.openedAt = this.now();
    this.pinged = false;
    this.ready = false;
    if (this.address.kind === 'nino') this.openSocket(); else this.openEvents();
  };

  // --- Yeni protokol ---

  Link.prototype.openSocket = function () {
    var self = this;
    var socket;
    try {
      socket = new this.env.WebSocket(this.address.url);
    } catch (x) {
      return this.lost();
    }
    this.socket = socket;
    var session = new P.DisplaySession({
      name: this.o.name(),
      id: this.o.id ? this.o.id() : undefined, // bağlantı kimliği (ölçüm kimliği değil)
      send: function (text) { socket.send(text); },
      close: function () { try { socket.close(); } catch (x) {} },
      onReady: function () {
        self.problem = null;
        self.ready = true;
        self.failures = 0;
        self.retry = 0;
        self.cancelScan();
        self.recovered();
        self.o.onStatus('ok');
      },
      onCommand: function (cmd) { self.o.onCommand(cmd); },
      onPeerError: function (code) {
        if (code === 'replaced') self.problem = 'replaced';
      },
      onFail: function (code) {
        self.problem = code === 'version_unsupported' || code === 'bad_handshake' ? 'tv.protocol.mismatch' : 'other';
      },
      onIdle: function () { self.o.onDrop(); },
      setTimeout: function (fn, ms) { return self.env.setTimeout(fn, ms); },
      clearTimeout: function (id) { self.env.clearTimeout(id); }
    });
    this.session = session;
    socket.onopen = function () { session.open(); };
    socket.onmessage = function (e) {
      self.lastHeard = self.now();
      session.receive(e.data);
    };
    socket.onclose = function () {
      if (self.socket !== socket) return;
      session.shut();
      self.socket = null;
      if (!self.problem) self.problem = 'closed';
      self.lost();
    };
    socket.onerror = function () { /* ardından close gelir */ };
  };

  // Gönderici gitti ya da hiç bağlanılamadı: durum, ekranı temizleme sayacı, yeniden deneme, gerekirse tarama.
  Link.prototype.lost = function () {
    var self = this;
    this.ready = false;
    this.o.onStatus('bad');
    this.armDrop();
    this.noteFailure();
    if (this.address && this.address.kind === 'nino' && !this.retryTimer) {
      var wait = this.t.backoff[Math.min(this.retry, this.t.backoff.length - 1)];
      this.retry++;
      this.retryTimer = this.env.setTimeout(function () {
        self.retryTimer = null;
        if (self.address && !self.socket) self.open();
      }, wait);
    }
  };

  Link.prototype.armDrop = function () {
    var self = this;
    if (this.dropTimer !== null) return;
    this.dropTimer = this.env.setTimeout(function () {
      self.dropTimer = null;
      self.o.onDrop();
    }, this.t.dropMs);
  };

  Link.prototype.recovered = function () {
    this.env.clearTimeout(this.dropTimer);
    this.dropTimer = null;
  };

  // --- Eski gönderici (8787, EventSource) ---

  var LEGACY_EVENTS = ['subtitle', 'clear', 'screen', 'screen-clear', 'region', 'region-clear', 'style', 'started', 'stopped'];

  Link.prototype.openEvents = function () {
    var self = this;
    if (!this.env.EventSource) return this.o.onStatus('bad');
    var model = this.o.model();
    var url = this.address.base + '/events' + (model ? '?model=' + encodeURIComponent(String(model).slice(0, 60)) : '');
    var events = new this.env.EventSource(url);
    this.events = events;
    events.onopen = function () {
      self.problem = null;
      self.ready = true;
      self.lastHeard = self.now();
      self.failures = 0;
      self.cancelScan();
      self.recovered();
      self.o.onStatus('ok');
    };
    events.onerror = function () {
      if (self.events !== events) return;
      self.o.onStatus('bad');
      self.armDrop();
      self.noteFailure();
    };
    events.addEventListener('ping', function () {
      self.lastHeard = self.now();
      self.pinged = true;
    });
    function listen(name) {
      events.addEventListener(name, function (e) {
        self.lastHeard = self.now();
        var data;
        try { data = JSON.parse(e.data); } catch (x) { return; }
        var cmd = P.fromLegacy(name, data);
        if (cmd) self.o.onCommand(cmd);
      });
    }
    for (var i = 0; i < LEGACY_EVENTS.length; i++) listen(LEGACY_EVENTS[i]);
  };

  // Bekçi (5 sn'de bir): ölü ya da asılı bağlantıyı bırakıp yeniden kurar.
  //   yeni protokol: el sıkışma 10 sn'de bitmediyse ya da bağlıyken 15 sn hiç mesaj (ping dahil) gelmediyse
  //   eski akış: kapandıysa (yeniden denemeyi bırakmış), 30 sn "bağlanıyor"da kaldıysa, ping görülmüşken 25 sn sessizse
  Link.prototype.watch = function () {
    if (!this.address) return;
    var t = this.now();
    if (this.address.kind === 'nino') {
      if (!this.socket) return; // yeniden deneme zamanlayıcısı bekliyor
      if (!this.ready && t - this.openedAt > this.t.connectMs) this.drop('timeout');
      else if (this.ready && t - this.lastHeard > this.t.silenceMs) this.drop('timeout');
      return;
    }
    if (!this.events) return;
    var state = this.events.readyState;
    if (state === 2) this.drop('closed');
    else if (state !== 1 && t - this.openedAt > this.t.legacyStuckMs) this.drop('timeout');
    else if (this.pinged && t - this.lastHeard > this.t.legacySilenceMs) this.drop('timeout');
  };

  // Bağlantıyı nedeniyle bırakır ve hemen yeniden kurar (yeni protokolde bekleme sırası korunur).
  Link.prototype.drop = function (reason) {
    this.problem = reason;
    if (this.address.kind === 'nino') {
      this.close();
      this.lost();
    } else {
      this.ready = false;
      this.o.onStatus('bad');
      this.armDrop();
      this.open();
    }
  };

  // Uygulama öne geldi (TV kaynak değiştirip geri döndü, ekran koruyucu, uzun bekleme): askıdayken bağlantı ölmüş
  // olabilir ve TV bunu haber vermeyebilir. Her öne gelişte bağlantı tazelenir, bekleme sırası sıfırlanır.
  Link.prototype.resume = function () {
    if (!this.address) return;
    var wasUp = this.ready;
    this.retry = 0;
    this.problem = 'resume';
    if (wasUp) {
      this.ready = false;
      this.o.onStatus('bad');
    }
    this.open();
  };

  Link.prototype.stop = function () {
    if (this.env.clearInterval) this.env.clearInterval(this.watcher);
    this.close();
    this.cancelScan();
  };

  // --- Ağ tarama ---

  Link.prototype.noteFailure = function () {
    this.failures++;
    this.scanLater(this.failures >= FAILS_BEFORE_SCAN ? SCAN_SOON_MS : SCAN_AGAIN_MS);
  };

  // Daha erken başlayacak bir tarama zaten bekliyorsa korunur.
  Link.prototype.scanLater = function (ms) {
    if (this.scanning) return;
    var self = this;
    var at = this.now() + ms;
    if (this.scanTimer !== null && this.scanAt <= at) return;
    this.env.clearTimeout(this.scanTimer);
    this.scanAt = at;
    this.scanTimer = this.env.setTimeout(function () {
      self.scanTimer = null;
      self.scan();
    }, ms);
  };

  Link.prototype.cancelScan = function () {
    this.env.clearTimeout(this.scanTimer);
    this.scanTimer = null;
  };

  function subnet(host) {
    var m = /^(\d+\.\d+\.\d+)\.\d+$/.exec(host || '');
    return m ? m[1] : null;
  }

  Link.prototype.subnets = function (done) {
    var self = this;
    var answered = false;
    function finish(ip) {
      if (answered) return;
      answered = true;
      if (ip && ip !== self.tvAddress) {
        self.tvAddress = ip;
        if (self.o.onTvAddress) self.o.onTvAddress(ip);
      }
      var list = [];
      var own = subnet(ip);
      var saved = subnet(self.address && self.address.host);
      if (own) list.push(own);
      if (saved && saved !== own) list.push(saved);
      done(list);
    }
    var platform = this.o.platform;
    if (typeof platform.localAddress !== 'function') return finish(null);
    this.env.setTimeout(function () { finish(null); }, 3000);
    try { platform.localAddress(finish); } catch (x) { finish(null); }
  };

  // Tek adresi yoklar; done(true/false).
  Link.prototype.probe = function (url, check, done) {
    var request = new this.env.XMLHttpRequest();
    var over = false;
    function end(ok) { if (!over) { over = true; done(ok); } }
    request.onload = function () { end(request.status === 200 && check(request.responseText || '')); };
    request.onerror = request.ontimeout = function () { end(false); };
    try {
      request.open('GET', url);
      request.timeout = SCAN_TIMEOUT_MS; // open'dan sonra (eski tarayıcılar)
      request.send();
    } catch (x) {
      end(false);
    }
  };

  // Önce yeni protokol (47800), sonra eski gönderici (8787).
  Link.prototype.probeHost = function (host, done) {
    var self = this;
    this.probe('http://' + host + ':' + P.DEFAULT_PORT + '/nino/info', P.isSenderInfo, function (ok) {
      if (ok) return done('ws://' + host + ':' + P.DEFAULT_PORT + '/nino/ws');
      self.probe('http://' + host + ':' + P.LEGACY_PORT + '/hello', function (t) { return t.indexOf('nino') >= 0; },
        function (old) { done(old ? 'http://' + host + ':' + P.LEGACY_PORT : null); });
    });
  };

  Link.prototype.scan = function () {
    if (this.scanning) return;
    var self = this;
    this.cancelScan();
    this.scanning = true;
    this.subnets(function (nets) {
      var hosts = [];
      for (var n = 0; n < nets.length; n++) for (var h = 1; h <= 254; h++) hosts.push(nets[n] + '.' + h);
      var next = 0, busy = 0, found = false;
      function pump() {
        while (!found && busy < SCAN_PARALLEL && next < hosts.length) {
          busy++;
          self.probeHost(hosts[next++], landed);
        }
        if (!found && !busy && next >= hosts.length) {
          self.scanning = false;
          self.scanLater(SCAN_AGAIN_MS);
        }
      }
      function landed(url) {
        busy--;
        if (found) return;
        if (!url) return pump();
        found = true;
        self.scanning = false;
        var same = self.address && P.parseAddress(url).url === self.address.url;
        if (!same) self.connect(url);
        else if (!self.socket && !self.events) self.open();
        else if (self.events && self.events.readyState === 2) self.open();
      }
      pump();
    });
  };

  root.Nino.Link = Link;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
