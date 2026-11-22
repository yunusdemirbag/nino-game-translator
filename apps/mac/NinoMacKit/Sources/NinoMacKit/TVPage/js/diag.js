// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Otomatik teşhis bekçisi, TV tarafı (tarif: NinoCore docs/tarif/otomatik-teshis.md). TV'ye uyan kurallar:
//   tv.flapping    10 dk içinde 3 kopma; sebep kopmaların çoğunun nedeni
//   app.hang       sayfa (ana iş parçacığı) 5 sn'den uzun yanıt vermedi
//   app.resources  JS belleği 400 MB'ı 2 dk boyunca aştı (tarayıcı bunu söyleyebiliyorsa)
// Serbest metin gitmez: yalnız kod, sayı ve iz ([kaç sn önce, kod, sayı?]). Olay ölçüm kuyruğuna `diag` olarak girer.
(function (root) {
  'use strict';

  var TRAIL_SEC = 600;
  var TRAIL_MAX = 200;
  var TRAIL_SEND = 40;
  var QUIET_SEC = 120;        // arka plan, uyku, yeni açılış sonrası susma
  var LAUNCH_QUIET_SEC = 60;
  var ROOT_WINDOW_SEC = 300;  // tek kök, tek bildirim
  var PER_DAY = 5;
  var PER_RULE_DAY = 2;
  var PRIORITY = ['app.hang', 'ps5.no_return', 'tv.flapping', 'ocr.stalled', 'tr.errors', 'tr.slow', 'ocr.silent',
    'app.resources', 'pack.download'];
  var DEFAULTS = { tvFlapWindowMin: 10, tvFlapCount: 3, hangSec: 5, memHighMB: 400, memHighSec: 120 };
  var FLAP_CAUSES = { write_error: 1, timeout: 1, closed: 1, resume: 1, network_change: 1, replaced: 1 };
  var CODE = /^[A-Za-z0-9_.$-]{1,64}$/;

  function rank(rule) {
    var i = PRIORITY.indexOf(rule);
    return i < 0 ? PRIORITY.length : i;
  }

  // options:
  //   now(): saniye (Unix)
  //   emit(event): diag olayını ölçüm kuyruğuna ekler
  //   tv(): {brand, model, app}   ver(): {tvApp, …}
  //   storage: günlük sınır sayacı için (isteğe bağlı)
  function Watchdog(options) {
    this.o = options;
    this.trail = [];
    this.limits = {};
    for (var k in DEFAULTS) if (Object.prototype.hasOwnProperty.call(DEFAULTS, k)) this.limits[k] = DEFAULTS[k];
    this.off = {};
    this.started = options.now();
    this.quietUntil = this.started + LAUNCH_QUIET_SEC;
    this.firedThisRun = {};
    this.lastSent = null;       // {rule, t}
    this.drops = [];            // {t, cause, upSec}
    this.upSince = null;
    this.proto = '';
    this.memSince = null;
  }

  // Uzaktan ayar: telemetry.diag = { off: [...], limits: {...} }
  Watchdog.prototype.configure = function (diag) {
    if (!diag || typeof diag !== 'object') return;
    this.off = {};
    var off = diag.off || [];
    for (var i = 0; i < off.length; i++) this.off[off[i]] = true;
    var lim = diag.limits || {};
    for (var k in lim) {
      if (Object.prototype.hasOwnProperty.call(DEFAULTS, k) && typeof lim[k] === 'number' && lim[k] > 0) this.limits[k] = lim[k];
    }
  };

  // İz adımı. Son 10 dk, en çok 200 adım.
  Watchdog.prototype.mark = function (code, n) {
    if (!CODE.test(String(code))) return;
    var t = this.o.now();
    var step = [t, String(code)];
    if (typeof n === 'number' && isFinite(n)) step.push(Math.round(n));
    this.trail.push(step);
    while (this.trail.length > TRAIL_MAX || (this.trail.length && t - this.trail[0][0] > TRAIL_SEC)) this.trail.shift();
  };

  // Susturma: arka plan, uyku/uyanma ya da açılıştan sonraki ilk dakika.
  Watchdog.prototype.quiet = function () { return this.o.now() < this.quietUntil; };

  Watchdog.prototype.hush = function () { this.quietUntil = Math.max(this.quietUntil, this.o.now() + QUIET_SEC); };

  // Kullanıcı çeviriyi durdurdu (gönderici `stopped` yolladı): ardından gelen kopmalar sorun sayılmaz.
  Watchdog.prototype.userStop = function () {
    this.mark('session.stop');
    this.stoppedUntil = this.o.now() + QUIET_SEC;
    this.drops = [];
  };

  Watchdog.prototype.background = function () { this.mark('app.background'); this.hush(); this.memSince = null; };
  Watchdog.prototype.foreground = function () { this.mark('app.foreground'); this.hush(); };

  // --- TV bağlantısı ---

  Watchdog.prototype.tvConnect = function (proto) {
    this.mark('tv.connect');
    this.upSince = this.o.now();
    if (proto) this.proto = proto;
  };

  // cause: timeout · closed · resume · write_error · network_change · başka (other)
  Watchdog.prototype.tvDrop = function (cause) {
    var t = this.o.now();
    this.mark('tv.drop');
    this.drops.push({ t: t, cause: FLAP_CAUSES[cause] ? cause : 'other', up: this.upSince === null ? 0 : t - this.upSince });
    this.upSince = null;
    var windowSec = this.limits.tvFlapWindowMin * 60;
    while (this.drops.length && t - this.drops[0].t > windowSec) this.drops.shift();
    if (this.drops.length < this.limits.tvFlapCount) return;
    var counts = {}, best = null, total = 0, up = 0;
    for (var i = 0; i < this.drops.length; i++) {
      var c = this.drops[i].cause;
      counts[c] = (counts[c] || 0) + 1;
      up += this.drops[i].up;
    }
    for (var key in counts) {
      if (!Object.prototype.hasOwnProperty.call(counts, key)) continue;
      total += counts[key];
      if (!best || counts[key] > counts[best]) best = key;
    }
    var cause = best && counts[best] * 2 > total && best !== 'other' ? best : 'mixed';
    var state = { drops: this.drops.length, avgUpSec: Math.round(up / this.drops.length) };
    if (this.proto) state.proto = this.proto;
    this.fire('tv.flapping', cause, 'warn', state);
  };

  // --- Askıda kalma ---
  // Sayfa tickMs'de (1 sn) bir tik atar. İki tik arası beklenenden hangSec (5 sn) fazla sürdüyse (görünürken) ana iş
  // parçacığı o kadar tıkanmıştır: 5 sn donan sayfada tik arası ~6 sn ölçülür.
  Watchdog.prototype.tick = function (gapMs, visible, tickMs) {
    if (!visible) return;
    var blockedMs = gapMs - (tickMs || 1000);
    if (blockedMs >= this.limits.hangSec * 1000) {
      var blocked = Math.round(blockedMs / 1000);
      this.mark('app.hang', blocked);
      this.fire('app.hang', 'main_thread', 'error', { blockedSec: blocked });
    }
  };

  // --- Bellek ---
  Watchdog.prototype.memory = function (mb) {
    if (typeof mb !== 'number' || !isFinite(mb)) return;
    var t = this.o.now();
    if (mb <= this.limits.memHighMB) { this.memSince = null; return; }
    if (this.memSince === null) { this.memSince = t; this.mark('mem.high', mb); return; }
    if (t - this.memSince >= this.limits.memHighSec) this.fire('app.resources', 'memory_high', 'warn', { memMB: Math.round(mb) });
  };

  // --- Gönderim ---

  Watchdog.prototype.dayCounts = function () {
    var day = Math.floor(this.o.now() / 86400);
    var stored = null;
    try { stored = JSON.parse((this.o.storage && this.o.storage.getItem('nino.diag.day')) || 'null'); } catch (e) {}
    if (!stored || stored.d !== day) stored = { d: day, n: 0, rules: {} };
    return stored;
  };

  Watchdog.prototype.saveDay = function (counts) {
    try { if (this.o.storage) this.o.storage.setItem('nino.diag.day', JSON.stringify(counts)); } catch (e) {}
  };

  Watchdog.prototype.fire = function (rule, cause, sev, state) {
    var t = this.o.now();
    if (this.off[rule] || this.firedThisRun[rule]) return false;
    // app.hang susturulmaz (donma görünürken ölçülür). tv.flapping yalnız açılışın ilk dakikasında ve kullanıcı
    // durdurduktan sonra susar (tarif böyle netleşti, 22 Kasım): TV'de
    // "arka plana gidip gelme" kopmanın kendisidir (sebep resume), arka plan susturması onu hiç göstermezdi.
    var flapQuiet = t < this.started + LAUNCH_QUIET_SEC || t < (this.stoppedUntil || 0);
    if (rule === 'tv.flapping' ? flapQuiet : (rule !== 'app.hang' && this.quiet())) return false;
    // Tek kök: son 5 dk'da daha öncelikli (ya da aynı) bir bildirim gittiyse bu yalnız iz adımı olur.
    if (this.lastSent && t - this.lastSent.t < ROOT_WINDOW_SEC && rank(this.lastSent.rule) <= rank(rule)) {
      this.mark(rule);
      return false;
    }
    var day = this.dayCounts();
    if (day.n >= PER_DAY || (day.rules[rule] || 0) >= PER_RULE_DAY) return false;
    day.n++;
    day.rules[rule] = (day.rules[rule] || 0) + 1;
    this.saveDay(day);
    this.firedThisRun[rule] = true;
    this.lastSent = { rule: rule, t: t };
    var trail = [];
    var from = Math.max(0, this.trail.length - TRAIL_SEND);
    for (var i = from; i < this.trail.length; i++) {
      var step = [Math.max(-3600, this.trail[i][0] - t), this.trail[i][1]];
      if (this.trail[i].length > 2) step.push(this.trail[i][2]);
      trail.push(step);
    }
    var event = { k: 'diag', t: t, rule: rule, cause: cause || 'unknown', sev: sev, state: state || {}, trail: trail };
    var tv = this.o.tv && this.o.tv();
    if (tv) event.tv = tv;
    var ver = this.o.ver && this.o.ver();
    if (ver) event.ver = ver;
    this.o.emit(event);
    return true;
  };

  var api = { Watchdog: Watchdog, PRIORITY: PRIORITY, DEFAULTS: DEFAULTS };
  root.Nino = root.Nino || {};
  root.Nino.diag = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
