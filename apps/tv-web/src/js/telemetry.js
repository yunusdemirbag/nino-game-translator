// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Anonim hata ve bağlantı ölçümü (tarif: NinoCore docs/tarif/olcum.md). TV'nin gönderdikleri: launch, crash
// (önceki çalışma düzgün kapanmadıysa), error (yalnız kod), tv_connect, tv_drop. Metin, adres, ad ya da hata mesajı
// hiçbir zaman gitmez. Olaylar tarayıcı deposunda kuyrukta bekler ve toplu gönderilir.
// Tarayıcıya özgü nesneler env ile verilir (testler).
(function (root) {
  'use strict';

  var MAX_QUEUE = 2000;
  var MAX_BATCH = 300;
  var FLUSH_AT = 100;
  var MAX_BACKOFF_S = 3600;
  var FIRST_FLUSH_MS = 30000;
  var KEY = { queue: 'nino.telemetry.queue', pending: 'nino.telemetry.pending', day: 'nino.telemetry.day',
    running: 'nino.telemetry.running', off: 'nino.telemetry.off' };
  var CODE_OK = /^[A-Za-z0-9_.$-]{1,64}$/;
  var PLATFORMS = { mac: 1, windows: 1, linux: 1, android: 1, ios: 1, androidtv: 1, webos: 1, tizen: 1 };

  function uuid(random) {
    var hex = '0123456789abcdef';
    var out = '';
    for (var i = 0; i < 32; i++) {
      var d = Math.floor(random() * 16);
      if (i === 12) d = 4;
      if (i === 16) d = 8 + (d & 3);
      out += hex.charAt(d);
      if (i === 7 || i === 11 || i === 15 || i === 19) out += '-';
    }
    return out;
  }

  function clip(value, max, pattern) {
    var s = String(value === undefined || value === null ? '' : value).slice(0, max);
    return !pattern || pattern.test(s) ? s : '';
  }

  // options:
  //   ctx: {platform, app, os, device, tv, channel} ya da bunu döndüren işlev (model sonradan öğrenilir)
  //   install(): kurulum kimliği (havuzla aynı UUID)
  //   endpoint: havuzun kök adresi
  //   env: {XMLHttpRequest, setTimeout, clearTimeout, now() (ms), random(), storage}
  function Telemetry(options) {
    var env = options.env || {};
    this.o = options;
    this.env = {
      XMLHttpRequest: env.XMLHttpRequest || root.XMLHttpRequest,
      setTimeout: env.setTimeout || function (fn, ms) { return root.setTimeout(fn, ms); },
      clearTimeout: env.clearTimeout || function (id) { root.clearTimeout(id); },
      now: env.now || function () { return new Date().getTime(); },
      random: env.random || Math.random,
      storage: env.storage || safeStorage()
    };
    this.config = { enabled: true, maxPerDay: 1000, flushSeconds: 600 };
    this.sending = false;
    this.timer = null;
    this.waitUntil = 0;
    this.failures = 0;
  }

  function safeStorage() {
    try { return root.localStorage; } catch (e) { return null; }
  }

  Telemetry.prototype.read = function (key, fallback) {
    try {
      var raw = this.env.storage && this.env.storage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) {
      return fallback;
    }
  };

  Telemetry.prototype.write = function (key, value) {
    try {
      if (!this.env.storage) return;
      if (value === null) this.env.storage.removeItem(key);
      else this.env.storage.setItem(key, JSON.stringify(value));
    } catch (e) { /* depo dolu ya da kapalı */ }
  };

  Telemetry.prototype.ctx = function () { return typeof this.o.ctx === 'function' ? this.o.ctx() : this.o.ctx; };

  Telemetry.prototype.seconds = function () { return Math.floor(this.env.now() / 1000); };

  Telemetry.prototype.enabled = function () {
    return this.config.enabled && !this.read(KEY.off, false) && !!PLATFORMS[this.ctx().platform];
  };

  // Olay ekler. Aynı hata kodu art arda gelirse birleştirilir (n).
  Telemetry.prototype.add = function (event) {
    if (!this.enabled()) return;
    var e = {};
    for (var k in event) if (Object.prototype.hasOwnProperty.call(event, k)) e[k] = event[k];
    e.t = e.t || this.seconds();
    if (e.code !== undefined) e.code = clip(e.code, 64, CODE_OK) || 'other';
    if (typeof e.r === 'string' && e.r !== 'ok') e.r = clip(e.r, 64, CODE_OK) || 'other';
    var queue = this.read(KEY.queue, []);
    var last = queue[queue.length - 1];
    if (e.k === 'error' && last && last.k === 'error' && last.code === e.code && last.http === e.http) {
      last.n = (last.n || 1) + 1;
    } else {
      queue.push(e);
    }
    // Dolunca en eski (çökme olmayan) olay atılır.
    while (queue.length > MAX_QUEUE) {
      var drop = 0;
      while (drop < queue.length - 1 && queue[drop].k === 'crash') drop++;
      queue.splice(drop, 1);
    }
    this.write(KEY.queue, queue);
    if (queue.length >= FLUSH_AT) this.flush();
  };

  Telemetry.prototype.error = function (code, http) {
    var e = { k: 'error', code: code };
    if (typeof http === 'number') e.http = http;
    this.add(e);
  };

  // Günlük sınır: aşılınca yalnız crash ve diag gider (teşhisin kendi sınırları var).
  Telemetry.prototype.limitDay = function (events) {
    var today = Math.floor(this.env.now() / 86400000);
    var day = this.read(KEY.day, { d: today, n: 0 });
    if (day.d !== today) day = { d: today, n: 0 };
    var kept = [];
    for (var i = 0; i < events.length; i++) {
      if (events[i].k === 'crash' || events[i].k === 'diag' || day.n < this.config.maxPerDay) { kept.push(events[i]); day.n++; }
    }
    this.write(KEY.day, day);
    return kept;
  };

  Telemetry.prototype.body = function (batch, events) {
    var c = this.ctx();
    return JSON.stringify({
      v: 1,
      batch: batch,
      install: this.o.install(),
      ctx: {
        platform: c.platform,
        app: clip(c.app, 24, /^[0-9A-Za-z.+-]*$/),
        os: clip(c.os, 40),
        device: clip(c.device, 60),
        tv: clip(c.tv, 16),
        channel: c.channel || 'release'
      },
      events: events
    });
  };

  // Kuyruğu gönderir. Bekleyen (yanıtı gelmemiş) parça varsa aynı batch kimliğiyle o yeniden denenir.
  Telemetry.prototype.flush = function () {
    if (this.sending || !this.enabled() || this.env.now() < this.waitUntil) return;
    var pending = this.read(KEY.pending, null);
    if (!pending) {
      var queue = this.read(KEY.queue, []);
      if (!queue.length) return;
      var events = this.limitDay(queue.slice(0, MAX_BATCH));
      this.write(KEY.queue, queue.slice(MAX_BATCH));
      if (!events.length) return;
      pending = { batch: uuid(this.env.random), events: events };
      this.write(KEY.pending, pending);
    }
    this.send(pending);
  };

  Telemetry.prototype.send = function (pending) {
    var self = this;
    var request;
    try {
      request = new this.env.XMLHttpRequest();
      request.open('POST', this.o.endpoint + '/v1/events');
      request.setRequestHeader('Content-Type', 'application/json');
    } catch (e) {
      return;
    }
    this.sending = true;
    request.onload = function () { self.sending = false; self.answered(request, pending); };
    request.onerror = request.ontimeout = function () { self.sending = false; self.later(0); };
    try {
      request.timeout = 15000;
      request.send(this.body(pending.batch, pending.events));
    } catch (e) {
      this.sending = false;
    }
  };

  Telemetry.prototype.answered = function (request, pending) {
    var status = request.status;
    if (status === 200) {
      this.write(KEY.pending, null);
      this.failures = 0;
      try { this.apply((JSON.parse(request.responseText || '{}') || {}).config); } catch (e) {}
      if (this.read(KEY.queue, []).length) this.flush();
    } else if (status === 413 && pending.events.length > 1) {
      // Çok büyük: iki parçaya bölünür, yeni kimliklerle sıraya girer.
      var half = Math.ceil(pending.events.length / 2);
      this.write(KEY.queue, pending.events.slice(half).concat(this.read(KEY.queue, [])));
      this.write(KEY.pending, { batch: uuid(this.env.random), events: pending.events.slice(0, half) });
      this.flush();
    } else if (status === 400 || status === 413) {
      this.write(KEY.pending, null);
    } else if (status === 429) {
      var after = parseInt(request.getResponseHeader && request.getResponseHeader('retry-after'), 10);
      this.waitUntil = this.env.now() + (after > 0 ? after : 3600) * 1000;
    } else {
      this.later(status);
    }
  };

  // Sunucuya ulaşılamadı: 1, 2, 4… dakika, en çok 1 saat sonra yeniden.
  Telemetry.prototype.later = function () {
    var wait = Math.min(MAX_BACKOFF_S, 60 * Math.pow(2, this.failures));
    this.failures++;
    this.waitUntil = this.env.now() + wait * 1000;
  };

  Telemetry.prototype.apply = function (config) {
    var t = config && config.telemetry;
    if (!t) return;
    if (this.onConfig) this.onConfig(t);
    if (typeof t.enabled === 'boolean') this.config.enabled = t.enabled;
    if (typeof t.maxPerDay === 'number' && t.maxPerDay >= 0) this.config.maxPerDay = t.maxPerDay;
    if (typeof t.flushSeconds === 'number' && t.flushSeconds >= 30) this.config.flushSeconds = t.flushSeconds;
    if (!this.config.enabled) {
      this.write(KEY.queue, null);
      this.write(KEY.pending, null);
    }
    this.schedule();
  };

  Telemetry.prototype.schedule = function () {
    var self = this;
    this.env.clearTimeout(this.timer);
    this.timer = this.env.setTimeout(function () { self.flush(); self.schedule(); }, this.config.flushSeconds * 1000);
  };

  // Açılış: önceki çalışmanın işareti duruyorsa çökme sayılır; launch eklenir; çalışma işareti yazılır.
  Telemetry.prototype.start = function (launchMs) {
    if (!this.enabled()) return; // tanınmayan platform (tarayıcı önizlemesi): hiçbir şey yazılmaz, istenmez
    var mark = this.read(KEY.running, null);
    if (mark && mark.at) {
      this.add({ k: 'crash', code: clip(mark.code, 64, CODE_OK) || 'unclean_exit', ver: clip(mark.ver, 24),
        up: Math.max(0, Math.round((this.env.now() - mark.at) / 1000)) });
    }
    var launch = { k: 'launch' };
    if (typeof launchMs === 'number' && launchMs >= 0) launch.ms = Math.round(launchMs);
    this.add(launch);
    this.awake();
    this.schedule();
    // Uzaktan ayar her /v1/events cevabıyla gelir (o adres CORS'a açık). Ayrı GET /v1/config yapılmaz: web TV'de
    // sayfa file:// kökenli olduğundan o istek CORS'a takılıyordu. Ayar erken gelsin diye ilk gönderim kısa sürede.
    var self = this;
    this.env.setTimeout(function () { self.flush(); }, FIRST_FLUSH_MS);
  };

  // Uygulama öne geldi: çalışma işareti yeniden yazılır.
  Telemetry.prototype.awake = function () {
    this.write(KEY.running, { ver: this.ctx().app, at: this.env.now() });
  };

  // Arka plana geçti ya da kapanıyor: işaret silinir (TV'nin uygulamayı kapatması çökme değildir), kuyruk gönderilir.
  Telemetry.prototype.sleep = function () {
    this.write(KEY.running, null);
    this.flush();
  };

  // Yakalanmayan hata: işarete yalnız sınıf adı yazılır; olay error kodu olarak da eklenir.
  Telemetry.prototype.uncaught = function (name) {
    var code = clip(name, 40, /^[A-Za-z0-9_$]+$/) || 'Error';
    this.error('app.js.' + code);
  };

  var api = { Telemetry: Telemetry, uuid: uuid, KEY: KEY };
  root.Nino = root.Nino || {};
  root.Nino.telemetry = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
