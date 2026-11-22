// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Android TV platform katmanı: LG ve Samsung'la ortak sayfanın (apps/tv-web) NINO_PLATFORM'u. Derlemede ortak
// platform/common.js'in arkasına eklenip platform.js olarak sayfaya konur.
//
// Farkı: Android TV'de bağlantıyı sayfa kurmaz. Uygulama (Java) 47800'de Nino Bağlantı Protokolü'nü dinler, el
// sıkışmayı kendisi yapar ve mesajları window.ninoAndroid.receive(...) ile verir. Altyazı ve uzantılar ortak sayfanın
// kendi girişine (window.nino.receive) gider; bağlantı durumu için sayfa Link yerine yerel köprüyü kullanır
// (NINO_PLATFORM.makeLink). Ayrıca üç Android'e özgü görünüm var (NinoNative.setup().mode):
//   home        Nino ana ekranı: bağlantı durumu ve "PS5'iniz HDMI n'de" (katman arkada hazır)
//   permission  bir kerelik izin ekranı
//   overlay     TV'nin kendi HDMI ekranının üstündeki şeffaf pencere: yalnız altyazı ve ekran çevirisi
//   inapp       ortak sayfa olduğu gibi (HDMI Nino'nun içinde)
(function (root) {
  'use strict';

  var doc = root.document;
  var bridge = root.NinoNative;
  var setup = {};
  try { setup = JSON.parse(bridge.setup()) || {}; } catch (e) { setup = {}; }
  var mode = setup.mode || 'inapp';

  // Bağlantı kopukken katmanda küçük nokta bu kadar sonra görünür.
  var DOT_AFTER_MS = 5000;
  // Bir anlık kopma ekranı silmez; gönderici geri gelmezse temizlenir (ortak sayfadaki süreyle aynı).
  var DROP_MS = 6000;
  // Eski yol (8787) açılmadan önce yeni göndericiye (47800) tanınan süre: açılışta ya da yeni yol kopunca yeni gönderici
  // genellikle birkaç saniyede bağlanır; eski yol o arada açılırsa gönderici aynı TV'yi kısa süre iki yoldan görür.
  var LEGACY_GRACE_MS = typeof setup.legacyGraceMs === 'number' ? setup.legacyGraceMs : 6000;

  var css = doc.createElement('link');
  css.rel = 'stylesheet';
  css.href = 'androidtv.css';
  doc.head.appendChild(css);

  // ---------- Yerel köprü: sayfanın Link'inin yerine ----------

  // Protokol mesajını ortak sayfanın komut biçimine çevirir (tv-web protocol.js'teki biçimle aynı alanlar).
  function command(m) {
    if (m.type === 'show') {
      if (typeof m.text !== 'string') return null;
      return {
        kind: 'show',
        id: typeof m.id === 'number' ? m.id : null,
        text: m.text,
        durationMs: typeof m.durationMs === 'number' && m.durationMs > 0 ? m.durationMs : 0,
        position: m.position === 'top' ? 'top' : 'bottom',
        box: m.box || null,
        paragraphs: m.paragraphs === true,
        replace: m.replace === true,
        light: typeof m.light === 'number' ? m.light : null,
        cover: typeof m.cover === 'string' ? m.cover : ''
      };
    }
    // Uygulama id'li clear'ı zaten süzdü: buraya gelen clear ekrandakini kaldırır.
    if (m.type === 'clear') return { kind: 'clear', id: null };
    if (m.type === 'style') return { kind: 'style', style: m };
    if (m.type === 'screen') {
      return { kind: 'screen', items: m.items || [], overlay: m.overlay === true, durationMs: m.durationMs || m.duration };
    }
    if (m.type === 'region') return { kind: 'region', region: m };
    if (m.type === 'screen-clear' || m.type === 'region-clear' || m.type === 'started' || m.type === 'stopped') {
      return { kind: m.type };
    }
    return null;
  }

  var link = null;

  /**
   * Sayfanın bağlantısı: iki yol birlikte çalışır.
   * - Yeni göndericiler (Nino Bağlantı Protokolü) uygulamanın 47800'deki sunucusuna bağlanır; mesajlar
   *   window.ninoAndroid'den gelir ("yerel" yol).
   * - Eski göndericiler (8787: /hello ve /events) ile göndericide dinleyen yeni göndericiler için sayfanın kendi
   *   Link'i çalışır: adres açılış bilgisinden (params), kayıttan ya da ağ taramasından bulunur ("web" yol).
   * Yerel yol açıkken web yolundan gelen komutlar yok sayılır (aynı gönderici iki yoldan bağlıysa yazı iki kez
   * gelmesin). Ortak sayfaya Link ile aynı yüz verilir: known(), connect(), scan(), address.
   */
  function NativeLink(options) {
    var self = this;
    this.o = options;
    this.open = false;
    this.webKind = null;
    // Ana ekran, izin ekranı ve katmanda bekleme sahnesi hiç oynamaz.
    this.ever = mode !== 'inapp';
    this.dropTimer = null;
    link = this;
    var WebLink = root.Nino && root.Nino.Link;
    this.web = WebLink ? new WebLink({
      platform: options.platform,
      store: options.store,
      name: options.name,
      model: options.model,
      env: options.env,
      onStatus: function (kind) {
        if (!self.webOn) return; // kapı kapanırken gelen son durumlar sayılmaz
        self.webKind = kind;
        self.measure(kind);
        self.legacyState();
        self.report(kind === 'connecting');
      },
      onCommand: function (cmd) { self.fromWeb(cmd); },
      onDrop: function () { if (!self.open) self.o.onDrop(); },
      onTvAddress: function (ip) { if (options.onTvAddress) options.onTvAddress(setup.address || ip); }
    }) : null;
    // Eski yolu uygulama genelinde tek sayfa çalıştırır (setup.legacy / "legacy" mesajı); yeni yol bağlıyken hiç.
    this.holder = !!setup.legacy;
    this.otherLegacy = false;
    this.webOn = false;
    if (this.web) {
      onlyLegacy(this.web);
      gate(this.web, function () { return self.webOn; });
    }
    if (options.onTvAddress && setup.address) options.onTvAddress(setup.address);
    setTimeout(function () { self.applyWeb(); }, 0);
  }

  /**
   * Web yolu (eski 8787) açılmalı mı: bu sayfa tutucuysa ve yeni yoldan gönderici bağlı değilse. Kapanınca bağlantı
   * kapanır, tarama ve yeniden denemeler durur; açılınca bilinen adrese bağlanılır, yoksa kayıtlı adrese, o da yoksa
   * ağ taranır. (Uygulama içi görünümde ortak sayfa da kayıtlı adresi ve taramayı dener; kapalıyken bunlar bekler.)
   */
  NativeLink.prototype.applyWeb = function () {
    if (!this.web) return;
    var self = this;
    var want = this.holder && !this.open;
    if (!want) {
      clearTimeout(this.graceTimer);
      this.graceTimer = null;
    } else if (!this.webOn) {
      // Açmadan önce bekle; bu sürede yeni gönderici bağlanırsa eski yol hiç açılmaz.
      if (this.graceTimer) return;
      this.graceTimer = setTimeout(function () {
        self.graceTimer = null;
        if (self.holder && !self.open) self.openWeb();
      }, LEGACY_GRACE_MS);
      return;
    }
    if (want === this.webOn) return;
    this.webOn = want;
    if (!want) {
      this.web.close();
      if (this.web.cancelScan) this.web.cancelScan();
      if (this.webKind === 'ok') { this.webKind = null; this.legacyState(); }
      this.webKind = null;
      return;
    }
  };

  NativeLink.prototype.openWeb = function () {
    if (this.webOn) return;
    this.webOn = true;
    if (this.web.address) { this.web.open(); return; }
    var saved = this.o.store && this.o.store.get('server');
    if (!saved || !this.web.connect(saved)) this.web.scan();
  };

  /** Bu sayfa tutucuysa eski yolun durumunu uygulamaya (öbür sayfalara) bildirir. */
  NativeLink.prototype.legacyState = function () {
    if (this.holder && bridge.legacyLinked) {
      try { bridge.legacyLinked(this.webKind === 'ok'); } catch (e) { /* yok */ }
    }
  };

  /**
   * Web yolunun kendiliğinden bağlanmasını (yeniden deneme, bekçi, tarama zamanlayıcısı) kapıdan geçirir: kapı kapalıyken
   * hiçbir bağlantı açılmaz. Adres yine kaydedilir; kapı açılınca kullanılır.
   */
  function gate(web, isOpen) {
    var open = web.open, scan = web.scan;
    web.open = function () { if (isOpen()) return open.apply(web, arguments); };
    web.scan = function () { if (isOpen()) return scan.apply(web, arguments); };
  }

  /**
   * Eski yolun (8787 ya da göndericide dinleyen yeni gönderici) ölçümü: deneme başı → sonuç (tv_connect), bağlıyken
   * kopma (tv_drop). Bir kesinti boyunca başarısız denemeler bir kez sayılır (tarama ve yeniden denemeler sık olur).
   * Yeni yol (47800) uygulamanın kendi sunucusunda ölçülür. Yalnız kod ve sayı gider.
   */
  NativeLink.prototype.measure = function (kind) {
    if (!bridge.measure) return;
    var now = new Date().getTime();
    var proto = this.web && this.web.address && this.web.address.kind === 'nino' ? 'nino' : 'legacy';
    var event = null;
    if (kind === 'connecting') {
      if (!this.tries) this.tries = { at: now, told: false };
    } else if (kind === 'ok') {
      event = { k: 'tv_connect', r: 'ok', ms: this.tries ? now - this.tries.at : 0, proto: proto };
      this.tries = null;
      this.upSince = now;
    } else if (kind === 'bad') {
      if (this.upSince) {
        var silent = this.web && this.web.problem === 'timeout';
        event = { k: 'tv_drop', code: silent ? 'timeout' : 'network_lost', after: Math.round((now - this.upSince) / 1000),
          proto: proto };
        this.upSince = 0;
        this.tries = { at: now, told: false };
      } else if (this.tries && !this.tries.told) {
        this.tries.told = true;
        event = { k: 'tv_connect', r: 'tv.connect.refused', ms: now - this.tries.at, proto: proto };
      }
    }
    if (event) { try { bridge.measure(JSON.stringify(event)); } catch (e) { /* ölçüm isteğe bağlı */ } }
  };

  /**
   * Android TV'de yeni göndericiler (Nino Bağlantı Protokolü) uygulamanın 47800'deki sunucusuna kendileri bağlanır.
   * Sayfanın Link'i de göndericinin dinleyen girişine (ws://…:47800) bağlanırsa aynı TV'den iki bağlantı olur ve
   * gönderici birini öbürüyle değiştirip durur (her 1–2 sn "replaced"). Bu yüzden sayfanın Link'i burada yalnız eski
   * göndericiler (8787: /hello, /events) için çalışır: yeni yol adresleri reddedilir, tarama yalnız 8787'yi yoklar.
   */
  function onlyLegacy(web) {
    var P = root.Nino && root.Nino.protocol;
    if (!P || !P.parseAddress) return;
    var connect = web.connect;
    web.connect = function (raw) {
      var a = P.parseAddress(raw);
      if (!a || a.kind !== 'legacy') return false;
      return connect.call(web, raw);
    };
    if (typeof web.probe === 'function') {
      var port = P.LEGACY_PORT || 8787;
      web.probeHost = function (host, done) {
        web.probe('http://' + host + ':' + port + '/hello', function (t) { return String(t).indexOf('nino') >= 0; },
          function (ok) { done(ok ? 'http://' + host + ':' + port : null); });
      };
    }
  }

  NativeLink.prototype.linked = function () { return this.open || this.webKind === 'ok' || this.otherLegacy; };
  NativeLink.prototype.known = function () { return this.ever || !!(this.web && this.web.known()); };
  NativeLink.prototype.connect = function (raw) { return this.web ? this.web.connect(raw) : false; };
  NativeLink.prototype.scan = function () { if (this.web) this.web.scan(); };
  NativeLink.prototype.close = function () { if (this.web && this.web.close) this.web.close(); };
  // Sayfa öne gelince ortak sayfa çağırır: web yolu (eski 8787) ölü bağlantıdan kurtulur. Yerel yolu uygulama tutar.
  NativeLink.prototype.resume = function () { if (this.web && this.web.resume) this.web.resume(); };

  // Ortak sayfa link.address'e bakar (aynı adrese yeniden bağlanmamak için): web yolunun adresi.
  try {
    Object.defineProperty(NativeLink.prototype, 'address', {
      get: function () {
        if (this.web && this.web.address) return this.web.address;
        return this.ever ? { kind: 'native', url: 'native:' } : null;
      }
    });
  } catch (e) { /* çok eski motor */ }

  /** İki yolun birleşik durumu ortak sayfaya: biri bağlıysa "ok". */
  NativeLink.prototype.report = function (trying) {
    if (this.linked()) this.o.onStatus('ok');
    else if (trying) this.o.onStatus('connecting');
    else if (this.known()) this.o.onStatus('bad');
    welcomeStatus();
    dot();
  };

  /** Yerel yolun (47800) durumu. */
  NativeLink.prototype.state = function (open) {
    var self = this;
    this.open = open;
    clearTimeout(this.dropTimer);
    if (open && !this.ever) {
      this.ever = true;
      // Bekleme sahnesi ve demo dursun (ortak sayfa "connecting"te durdurur).
      this.o.onStatus('connecting');
    }
    this.applyWeb();
    this.report(false);
    if (!open && this.webKind !== 'ok' && !this.otherLegacy) {
      this.dropTimer = setTimeout(function () { self.o.onDrop(); }, DROP_MS);
    }
  };

  /** Yerel yoldan gelen mesaj: ortak sayfanın kendi girişi çevirir (aynı kurallar); yoksa buradaki çeviri. */
  NativeLink.prototype.command = function (m) {
    var shared = root.nino && root.nino.receive;
    if (shared && root.Nino.protocol && root.Nino.protocol.toCommand) { shared(m); return; }
    var cmd = command(m);
    if (cmd) this.o.onCommand(cmd);
  };

  /** Web yolundan (eski 8787 ya da göndericide dinleyen yeni gönderici) gelen komut. */
  NativeLink.prototype.fromWeb = function (cmd) {
    if (this.open) return;
    // Eski göndericinin görünüm modu seçimi (katman / uygulama içi) uygulamaya iletilir.
    if (cmd && cmd.kind === 'style' && cmd.style && typeof cmd.style.displayMode === 'string' && bridge.setDisplayMode) {
      bridge.setDisplayMode(cmd.style.displayMode);
    }
    this.o.onCommand(cmd);
  };

  // ---------- Uygulamadan gelenler ----------

  var waiting = [];
  var relaunch = null;

  function isLinked() { return !!(link && link.linked()); }

  root.ninoAndroid = {
    receive: function (m) {
      if (!m || typeof m.type !== 'string') return;
      if (m.type === 'key') return key(m.code);
      if (m.type === 'hdmi') return hdmiState(m);
      if (m.type === 'visible') return;
      if (!link) { waiting.push(m); return; }
      if (m.type === 'link') { link.state(!!m.open); return; }
      if (m.type === 'relaunch') { if (relaunch) relaunch(m.params); return; }
      if (m.type === 'legacy') { link.holder = !!m.on; link.applyWeb(); link.report(false); return; }
      if (m.type === 'legacyLink') { link.otherLegacy = !!m.open && !link.holder; link.report(false); return; }
      link.command(m);
    }
  };

  function flush() {
    var queued = waiting;
    waiting = [];
    for (var i = 0; i < queued.length; i++) root.ninoAndroid.receive(queued[i]);
  }

  // Kumanda: uygulama tuşları sayfaya gönderir; ortak sayfa document keydown dinler.
  function key(code) {
    var e;
    try {
      e = new root.Event('keydown', { bubbles: true, cancelable: true });
    } catch (old) {
      e = doc.createEvent('Event');
      e.initEvent('keydown', true, true);
    }
    try { Object.defineProperty(e, 'keyCode', { get: function () { return code; } }); } catch (x) { e.keyCode = code; }
    doc.dispatchEvent(e);
  }

  // ---------- HDMI ----------

  var report = null;
  var reportPort = 0;

  function hdmiState(m) {
    if (report && (!m.port || !reportPort || m.port === reportPort)) report(m.state);
  }

  // ---------- Katman: yalnız altyazı ve küçük kopukluk noktası ----------

  var dotEl = null;
  var dotTimer = null;

  function dot() {
    if (!dotEl) return;
    clearTimeout(dotTimer);
    if (isLinked()) { dotEl.className = 'off'; return; }
    dotTimer = setTimeout(function () { dotEl.className = ''; }, DOT_AFTER_MS);
  }

  // ---------- Ana ekran ve izin ekranı ----------

  var lang = (root.navigator.language || 'en').slice(0, 2).toLowerCase();

  // Ana ekran ve izin ekranının yazıları. "Diğer uygulamaların üzerinde göster", Android'in kendi ayarının adıdır.
  var WORDS = {
    tr: {
      linked: 'Nino ile bağlantı kuruldu',
      waiting: 'Bağlantı bekleniyor: Nino\'yu telefonda ya da bilgisayarda açın',
      goTitle: function (p, label) {
        return p ? 'PS5, HDMI ' + p + ' girişinde' + (label ? ' · ' + label : '') : 'Kumandayla PS5\'in girişini seçin';
      },
      goText: function (p) {
        return 'Kumandadaki kaynak (giriş) tuşuna basıp ' + (p ? 'HDMI ' + p + ' girişini' : 'PS5\'in takılı olduğu girişi') +
          ' seçin. Türkçe altyazı, oyunun kendi altyazısının üstünde belirecek.';
      },
      askTitle: 'Tek seferlik bir izin lazım',
      askText: 'Nino\'nun altyazıyı oyunun üstüne çizebilmesi için “Diğer uygulamaların üzerinde göster” izni gerekiyor. ' +
        'TV\'de USB hata ayıklama açıksa çeviriyi telefondaki ya da bilgisayardaki Nino\'dan başlatın; TV sorunca ' +
        '“Her zaman izin ver”i işaretleyip onaylayın, izin kendiliğinden tanınır. Açık değilse aşağıdakilerden birini seçin.',
      askGrant: 'TV ayarlarından izin ver',
      askSkip: 'İzinsiz sürdür',
      askHint: 'İzinsiz sürdürürseniz oyun Nino\'nun içinde açılır; bazı TV\'lerde görüntü gelmeyebilir.',
      foot: 'Geri tuşu: çıkış'
    },
    en: {
      linked: 'Linked to Nino',
      waiting: 'Waiting for a link: open Nino on your phone or computer',
      goTitle: function (p, label) {
        return p ? 'PS5 found on HDMI ' + p + (label ? ' · ' + label : '') : 'Pick your PS5\'s input with the remote';
      },
      goText: function (p) {
        return 'Press the source (input) button on your remote and choose ' + (p ? 'HDMI ' + p : 'the input your PS5 uses') +
          '. Translations will show up on top of the game\'s own subtitles.';
      },
      askTitle: 'Nino needs one permission, once',
      askText: 'Nino can only draw subtitles on top of the game with the “Display over other apps” permission. If USB ' +
        'debugging is on, start translating from Nino on your phone or computer; when the TV asks, tick “Always allow” and ' +
        'confirm, and the permission is set for you. If not, pick one of the options below.',
      askGrant: 'Allow in TV settings',
      askSkip: 'Carry on without it',
      askHint: 'Without it, the game plays inside Nino; some TVs may then show a black picture.',
      foot: 'Back button: exit'
    },
    ar: {
      linked: 'تم الاتصال بـ Nino',
      waiting: 'بانتظار الاتصال: افتح Nino على الهاتف أو الكمبيوتر',
      goTitle: function (p, label) {
        return p ? 'PS5 على منفذ HDMI ' + p + (label ? ' · ' + label : '') : 'اختر منفذ PS5 بجهاز التحكم';
      },
      goText: function (p) {
        return 'اضغط زر المصدر في جهاز التحكم واختر ' + (p ? 'منفذ HDMI ' + p : 'المنفذ الموصول به PS5') +
          '. ستظهر الترجمة فوق ترجمة اللعبة الأصلية.';
      },
      askTitle: 'يلزم إذن واحد لمرة واحدة',
      askText: 'لا يستطيع Nino رسم الترجمة فوق اللعبة إلا بإذن «العرض فوق التطبيقات الأخرى». إن كان تصحيح USB مفعّلًا ' +
        'فابدأ الترجمة من Nino على الهاتف أو الكمبيوتر، وعندما يسأل التلفاز اختر «السماح دائمًا» ثم وافق، فيُمنح الإذن ' +
        'تلقائيًا. وإلا فاختر أحد الخيارين أدناه.',
      askGrant: 'السماح من إعدادات التلفاز',
      askSkip: 'المتابعة بلا إذن',
      askHint: 'بلا إذن تُعرض اللعبة داخل Nino، وقد تبقى الصورة سوداء في بعض أجهزة التلفاز.',
      foot: 'زر الرجوع: خروج'
    }
  };
  var W = WORDS[lang] || WORDS.en;

  var welcome = null;
  var picked = 0;

  function buildWelcome() {
    var asking = mode === 'permission';
    welcome = doc.createElement('section');
    welcome.id = 'nino-welcome';
    if (asking) welcome.className = 'asking';
    welcome.innerHTML =
      '<div class="glow blue"></div><div class="glow red"></div>' +
      '<div class="brand"><img class="logo" src="img/logo.png" alt=""><div class="name">Nino</div>' +
      '<div class="tag">GAME TRANSLATOR</div></div>' +
      '<div class="status"><i></i><span></span></div>' +
      '<div class="card"><h1></h1><p class="say"></p>' +
      (asking ? '<div class="choices"><div class="choice"></div><div class="choice"></div></div><p class="hint"></p>' : '') +
      '</div><div class="foot"></div>';
    doc.body.appendChild(welcome);
    doc.body.className += ' native-welcome';
    var p = setup.consolePort || 0;
    welcome.querySelector('h1').textContent = asking ? W.askTitle : W.goTitle(p, setup.consoleLabel || '');
    welcome.querySelector('.say').textContent = asking ? W.askText : W.goText(p);
    welcome.querySelector('.foot').textContent = W.foot + (setup.version ? '  ·  Nino ' + setup.version : '');
    if (asking) {
      var choices = welcome.querySelectorAll('.choice');
      choices[0].textContent = W.askGrant;
      choices[1].textContent = W.askSkip;
      welcome.querySelector('.hint').textContent = W.askHint;
      pick(0);
    }
    welcomeStatus();
    // Ana ekranda kumanda yalnız bunlar içindir; ortak sayfanın tuşları çalışmaz.
    doc.addEventListener('keydown', function (e) {
      var k = e.keyCode;
      e.stopImmediatePropagation();
      e.preventDefault();
      if (k === 4 || k === 27 || k === 8) return bridge.leave();
      if (!asking) return;
      if (k === 37 || k === 39) pick(k === 37 ? 0 : 1);
      else if (k === 13) { if (picked === 0) bridge.grantPermission(); else bridge.continueWithout(); }
    }, true);
  }

  function pick(i) {
    picked = i;
    var choices = welcome.querySelectorAll('.choice');
    for (var j = 0; j < choices.length; j++) choices[j].className = 'choice' + (j === i ? ' on' : '');
  }

  function welcomeStatus() {
    if (!welcome) return;
    var line = welcome.querySelector('.status');
    var on = isLinked();
    line.className = 'status' + (on ? ' on' : '');
    line.querySelector('span').textContent = on ? W.linked : W.waiting;
  }

  // ---------- NINO_PLATFORM ----------

  root.NINO_PLATFORM = {
    backKey: 4,
    // Görüntü gelmeyince giriş seçiciyi uygulama kendisi gösterir.
    noPictureHelp: false,

    init: function () {
      doc.body.className += ' androidtv mode-' + mode;
      if (mode === 'home' || mode === 'permission') buildWelcome();
      if (mode === 'overlay') {
        dotEl = doc.createElement('div');
        dotEl.id = 'nino-offline';
        dotEl.className = 'off';
        doc.body.appendChild(dotEl);
        dot();
      }
      // Kurulum kimliği havuzla ölçümde aynı olsun: sayfada önceden varsa uygulama onu alır, yoksa uygulamanınki yazılır.
      try {
        var ls = root.localStorage;
        var id = ls && ls.getItem('ninoTvId');
        if (id) { if (bridge.adoptInstall) bridge.adoptInstall(id); }
        else if (ls && setup.install) ls.setItem('ninoTvId', setup.install);
      } catch (e) { /* depolama yok */ }
      // Kurulu TV'nin markası ve modeli (common.js; panel istatistiği, günde bir kez, anonim).
      setTimeout(function () { if (root.ninoReportTv) root.ninoReportTv('androidtv', setup.model || ''); }, 1000);
      // Ortak sayfa kurulduktan sonra (main.js init'ten sonra Link'i kurar) bekleyen mesajlar verilir.
      setTimeout(function () {
        // Ortak sayfa açılışta adres satırını boşaltır; TV'nin adresi (telefonda elle yazılabilsin) yeniden yazılır.
        if (link && link.o.onTvAddress && setup.address) link.o.onTvAddress(setup.address);
        flush();
        bridge.ready();
      }, 0);
    },

    // Eski gönderici uygulamayı adresiyle açtıysa ({"server":"http://ip:8787"}); ortak sayfa bağlanır.
    launchParams: function () { return setup.params || null; },
    onRelaunch: function (callback) { relaunch = callback; },

    showHdmi: function (port, host, onState) {
      report = onState;
      reportPort = port || 0;
      // Katmanda ve ana ekranda giriş TV'nindir; Nino hiçbir girişi açmaz.
      if (mode !== 'inapp') { onState('ready'); return; }
      onState('loading');
      bridge.pickHdmi(port || 0);
    },

    findConsolePort: function (callback) {
      var p = bridge.consolePort ? bridge.consolePort() : (setup.consolePort || 0);
      callback(p > 0 ? p : null, p > 0 ? 'HDMI ' + p : null);
    },

    localAddress: function (done) { done(setup.address || null); },

    exit: function () { bridge.leave(); },

    // Ortak sayfa bağlantıyı kendisi kurmaz; uygulamanın sunucusundan gelenleri yerel köprü verir.
    makeLink: function (options) { return new NativeLink(options); }
  };
})(window);
