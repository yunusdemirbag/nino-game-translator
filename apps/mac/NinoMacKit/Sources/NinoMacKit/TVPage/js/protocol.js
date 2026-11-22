// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Nino Bağlantı Protokolü, TV (gösterici) tarafı. Ağdan bağımsızdır: metin alır, metin yollar. Tarayıcıda ve Node'da
// (testler) aynı dosya çalışır. Eski TV tarayıcıları için ES5. Bkz. docs/yeni/tv-web/baglanti.md.
(function (root) {
  'use strict';

  var VERSIONS = [1];
  // Protokol 16 KB der; TV'ler buzlu zemin görseli (show.cover) için 512 KB'a kadar kabul eder
  // (ortak karar: side-session-notes/protokol-karari-tv.md). Göndericiler cover'sız mesajları 16 KB altında tutar.
  var MAX_BYTES = 512 * 1024;
  var HANDSHAKE_MS = 5000;
  var IDLE_MS = 20000;
  var DEFAULT_PORT = 47800;
  var LEGACY_PORT = 8787;

  // Protokolün kendi türleri dışında anlaşılan Nino uzantıları (isteğe bağlı; bilmeyen gösterici yok sayar).
  var EXTENSIONS = { style: 1, screen: 1, 'screen-clear': 1, region: 1, 'region-clear': 1, started: 1, stopped: 1 };

  function utf8Length(text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 0x80) bytes += 1;
      else if (c < 0x800) bytes += 2;
      else if (c >= 0xD800 && c <= 0xDBFF) { bytes += 4; i++; }
      else bytes += 3;
    }
    return bytes;
  }

  function isInt(v) { return typeof v === 'number' && isFinite(v) && Math.floor(v) === v; }

  function message(type, fields) {
    var out = { app: 'nino', type: type };
    for (var k in fields) if (Object.prototype.hasOwnProperty.call(fields, k) && fields[k] !== undefined) out[k] = fields[k];
    return JSON.stringify(out);
  }

  // Gelen JSON'u uygulamanın tek biçimli komutuna çevirir. Hem protokol hem eski SSE olayları buradan geçer.
  // durationMs: null = eski davranış (uzunluğa göre), 0 = clear gelene kadar, > 0 = bu kadar ms.
  // Tuş simgeleri: [{id: "T1", name?: "cross"|"dpad-up"|…, png?: base64}]; en çok 8, bozuk olanlar atılır.
  function iconList(list) {
    if (!list || typeof list.length !== 'number') return null;
    var out = [];
    for (var i = 0; i < list.length && out.length < 8; i++) {
      var it = list[i];
      if (!it || typeof it.id !== 'string' || !/^T\d{1,2}$/.test(it.id)) continue;
      var icon = { id: it.id };
      if (typeof it.name === 'string' && it.name.length <= 24) icon.name = it.name;
      if (typeof it.png === 'string' && it.png.length <= 200000) icon.png = it.png;
      if (icon.name || icon.png) out.push(icon);
    }
    return out.length ? out : null;
  }

  function showCommand(o, legacy) {
    var duration;
    if (legacy) duration = typeof o.duration === 'number' && o.duration > 0 ? o.duration : null;
    else duration = typeof o.durationMs === 'number' && o.durationMs > 0 ? o.durationMs : 0;
    return {
      kind: 'show',
      id: isInt(o.id) ? o.id : null,
      text: String(o.text),
      durationMs: duration,
      position: o.position === 'top' ? 'top' : 'bottom',
      box: o.box || null,
      paragraphs: o.paragraphs === true,
      replace: o.replace === true,
      light: typeof o.light === 'number' ? o.light : null,
      cover: typeof o.cover === 'string' ? o.cover : '',
      speaker: typeof o.speaker === 'string' && o.speaker ? o.speaker.slice(0, 60) : null,
      icons: iconList(o.icons)
    };
  }

  // Ekran çevirisinin süresi: > 0 bu kadar ms; 0 = screen-clear ya da yeni screen gelene kadar (yalnız yeni protokolde,
  // açıkça 0 yazılırsa); null = varsayılan (20 sn). Eski 8787 düzeninde 0 ya da yok varsayılandır (eski uygulama gibi).
  function screenDuration(o, legacy) {
    var d = legacy ? o.duration : (typeof o.durationMs === 'number' ? o.durationMs : o.duration);
    if (typeof d !== 'number' || !isFinite(d) || d < 0) return null;
    if (d === 0) return legacy || typeof o.durationMs !== 'number' ? null : 0;
    return d;
  }

  function extensionCommand(type, o, legacy) {
    switch (type) {
      case 'style': return { kind: 'style', style: o };
      case 'screen':
        return { kind: 'screen', items: o.items || [], overlay: o.overlay === true, durationMs: screenDuration(o, legacy) };
      case 'region': return { kind: 'region', region: o };
      default: return { kind: type };
    }
  }

  // Eski göndericinin (8787, Server-Sent Events) olayı. Tanınmayan olay null döner.
  function fromLegacy(event, o) {
    o = o || {};
    if (event === 'subtitle') return o.text ? showCommand(o, true) : null;
    if (event === 'clear') return { kind: 'clear', id: null };
    if (EXTENSIONS[event]) return extensionCommand(event, o, true);
    return null;
  }

  // TV tarafı oturum. options:
  //   name: TV'nin görünen adı
  //   id: TV'nin kalıcı rastgele kimliği (welcome'da gider)
  //   send(text), close(): taşıyıcı (WebSocket)
  //   onCommand(cmd): show/clear/uzantı komutları
  //   onReady(version, hello): el sıkışma bitti
  //   onIdle(): 20 sn hiç mesaj gelmedi (ekran temizlenir)
  //   onFail(code): oturum hata koduyla kapandı (ölçüm için)
  //   onPeerError(code): gönderici error mesajı yolladı (ölçüm için)
  //   setTimeout, clearTimeout: sahte saat için (yoksa genel olanlar)
  function DisplaySession(options) {
    this.o = options;
    this.state = 'new';
    this.version = null;
    this.handshakeTimer = null;
    this.idleTimer = null;
    var self = this;
    this.later = options.setTimeout || function (fn, ms) { return root.setTimeout(fn, ms); };
    this.cancel = options.clearTimeout || function (id) { root.clearTimeout(id); };
    this.onHandshakeTimeout = function () { self.fail('bad_handshake', 'hello gelmedi'); };
    this.onIdleTimeout = function () { self.idleTimer = null; if (self.o.onIdle) self.o.onIdle(); };
  }

  DisplaySession.prototype.open = function () {
    if (this.state !== 'new') return;
    this.state = 'waiting';
    this.handshakeTimer = this.later(this.onHandshakeTimeout, HANDSHAKE_MS);
  };

  DisplaySession.prototype.send = function (type, fields) {
    if (this.state === 'closed') return;
    try { this.o.send(message(type, fields || {})); } catch (e) { /* taşıyıcı kapanmış olabilir */ }
  };

  DisplaySession.prototype.fail = function (code, text, extra) {
    if (this.state === 'closed') return;
    var fields = extra || {};
    fields.code = code;
    if (this.o.onFail) this.o.onFail(code);
    if (text) fields.message = text;
    this.send('error', fields);
    this.shut();
    try { this.o.close(); } catch (e) {}
  };

  // Taşıyıcı kapandı (ya da kapatıldı): zamanlayıcılar durur.
  DisplaySession.prototype.shut = function () {
    this.state = 'closed';
    this.cancel(this.handshakeTimer);
    this.cancel(this.idleTimer);
    this.handshakeTimer = this.idleTimer = null;
  };

  DisplaySession.prototype.touch = function () {
    this.cancel(this.idleTimer);
    this.idleTimer = this.later(this.onIdleTimeout, IDLE_MS);
  };

  DisplaySession.prototype.receive = function (text) {
    if (this.state === 'closed' || this.state === 'new') return;
    text = String(text);
    if (utf8Length(text) > MAX_BYTES) return this.fail('too_large', 'en fazla ' + MAX_BYTES + ' bayt');
    var o = null;
    try { o = JSON.parse(text); } catch (e) { o = null; }
    var nino = !!o && typeof o === 'object' && o.app === 'nino' && typeof o.type === 'string';
    if (this.state === 'waiting') return this.greet(nino ? o : null);
    this.touch();
    if (!nino) return this.send('error', { code: 'bad_message', message: 'Nino mesajı değil' });
    this.handle(o);
  };

  DisplaySession.prototype.greet = function (o) {
    if (!o || o.type !== 'hello') return this.fail('bad_handshake', 'ilk mesaj hello olmalı');
    if (!isInt(o.version) || VERSIONS.indexOf(o.version) < 0) {
      return this.fail('version_unsupported', null, { versions: VERSIONS.slice() });
    }
    this.cancel(this.handshakeTimer);
    this.handshakeTimer = null;
    this.state = 'ready';
    this.version = o.version;
    // id: TV'nin kalıcı kimliği; gönderici aynı TV'nin yeniden bağlandığını bundan anlar (yoksa uzak adresten).
    this.send('welcome', { version: o.version, name: this.o.name || 'TV', id: this.o.id || undefined });
    this.touch();
    if (this.o.onReady) this.o.onReady(o.version, o);
  };

  DisplaySession.prototype.handle = function (o) {
    var deliver = this.o.onCommand || function () {};
    switch (o.type) {
      case 'ping':
        return this.send('pong', { t: o.t });
      case 'show':
        if (!isInt(o.id) || typeof o.text !== 'string') {
          return this.send('error', { code: 'bad_message', message: 'show: id ve text gerekli' });
        }
        return deliver(showCommand(o, false));
      case 'clear':
        return deliver({ kind: 'clear', id: isInt(o.id) ? o.id : null });
      case 'hello':
        return this.send('error', { code: 'bad_message', message: 'el sıkışma zaten yapıldı' });
      case 'error':
        // Karşı tarafın hatası yalnız kodu için okunur (ör. replaced: bu bağlantının yerini başka bir bağlantı aldı).
        if (this.o.onPeerError && typeof o.code === 'string') this.o.onPeerError(o.code);
        return;
      default:
        if (EXTENSIONS[o.type]) return deliver(extensionCommand(o.type, o, false));
        // Bilinmeyen tür (pong, error, ileride eklenecekler) yok sayılır; bağlantı kapanmaz.
    }
  };

  // --- Adresler ---

  var PRIVATE_V4 = [[10, 0, 8], [127, 0, 8], [192, 168, 16], [169, 254, 16], [172, 16, 12]];

  function isLocalHost(host) {
    var h = String(host || '').toLowerCase().replace(/^\[|\]$/g, '');
    var percent = h.indexOf('%');
    if (percent >= 0) h = h.slice(0, percent);
    if (h.indexOf('::ffff:') === 0) h = h.slice(7);
    var m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h);
    if (m) {
      var a = +m[1], b = +m[2];
      if (+m[3] > 255 || +m[4] > 255 || a > 255 || b > 255) return false;
      for (var i = 0; i < PRIVATE_V4.length; i++) {
        var r = PRIVATE_V4[i];
        if (r[2] === 8 && a === r[0]) return true;
        if (r[2] === 16 && a === r[0] && b === r[1]) return true;
        if (r[2] === 12 && a === r[0] && b >= 16 && b <= 31) return true;
      }
      return false;
    }
    if (h === '::1') return true;
    return /^fe[89ab]/.test(h) || /^f[cd]/.test(h);
  }

  // Göndericinin adresini çözer. Kabul edilenler: "ws://ip:47800/nino/ws", "http://ip:47800", "http://ip:8787",
  // "ip", "ip:port". Dönüş: {kind: 'nino'|'legacy', host, port, url} ya da null (yerel ağ dışı ya da bozuk).
  function parseAddress(raw) {
    var m = /^(?:(wss?|https?):\/\/)?(\[[^\]]+\]|[^\/:]+)(?::(\d+))?(\/.*)?$/i.exec(String(raw || '').replace(/^\s+|\s+$/g, ''));
    if (!m || !isLocalHost(m[2])) return null;
    var scheme = (m[1] || '').toLowerCase();
    var port = m[3] ? +m[3] : (scheme.charAt(0) === 'w' || !scheme ? DEFAULT_PORT : LEGACY_PORT);
    var host = m[2].replace(/%(?!25)/, '%25');
    var legacy = scheme.charAt(0) === 'h' && port !== DEFAULT_PORT;
    return {
      kind: legacy ? 'legacy' : 'nino',
      host: host,
      port: port,
      url: legacy ? 'http://' + host + ':' + port : 'ws://' + host + ':' + port + '/nino/ws',
      base: 'http://' + host + ':' + port
    };
  }

  // Bir taramada /nino/info cevabı gönderici mi? TV'ler (göstericiler) role alanı göndermez; yalnız "sender" kabul.
  function isSenderInfo(text) {
    try {
      var o = JSON.parse(text);
      return !!o && o.app === 'nino' && o.type === 'info' && o.role === 'sender';
    } catch (e) {
      return false;
    }
  }

  // Yerel köprü (Android TV): el sıkışması bitmiş, ayrıştırılmış mesajı komuta çevirir; tanınmayan ya da eksik
  // alanlı mesaj null döner.
  function toCommand(o) {
    if (!o || typeof o.type !== 'string') return null;
    if (o.type === 'show') return typeof o.text === 'string' ? showCommand(o, false) : null;
    if (o.type === 'clear') return { kind: 'clear', id: isInt(o.id) ? o.id : null };
    if (EXTENSIONS[o.type]) return extensionCommand(o.type, o, false);
    return null;
  }

  var api = {
    VERSIONS: VERSIONS,
    MAX_BYTES: MAX_BYTES,
    HANDSHAKE_MS: HANDSHAKE_MS,
    IDLE_MS: IDLE_MS,
    DEFAULT_PORT: DEFAULT_PORT,
    LEGACY_PORT: LEGACY_PORT,
    DisplaySession: DisplaySession,
    fromLegacy: fromLegacy,
    toCommand: toCommand,
    iconList: iconList,
    message: message,
    utf8Length: utf8Length,
    isLocalHost: isLocalHost,
    parseAddress: parseAddress,
    isSenderInfo: isSenderInfo
  };
  root.Nino = root.Nino || {};
  root.Nino.protocol = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
