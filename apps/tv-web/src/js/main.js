// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Uygulamanın ana akışı: HDMI, bekleme sahnesi ve demo, bilgi paneli, "görüntü yok" kutusu, kumanda, bağlantı.
// Markaya bağlı kısımlar platform.js'te (NINO_PLATFORM). Tarif: docs/yeni/tv-web/tarif.md.
(function (root) {
  'use strict';

  var VERSION = '4.5.0';
  var LABEL = 'V4.5';

  var doc = root.document;
  var N = root.Nino;
  var say = N.say;
  var caption = N.caption;
  var board = N.board;
  var platform = root.NINO_PLATFORM;
  var config = root.NINO_CONFIG || {};
  var KEY = { OK: 13, LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, RED: 403, GREEN: 404, BLUE: 406, BACK: platform.backKey };

  function $(id) { return doc.getElementById(id); }
  function on(el, yes) {
    var list = (' ' + el.className + ' ').replace(' off ', ' ');
    el.className = (yes ? list : list + 'off').replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
  }
  function isOn(el) { return (' ' + el.className + ' ').indexOf(' off ') < 0; }
  function now() { return new Date().getTime(); }

  var store = {
    get: function (k) { try { return root.localStorage.getItem('nino.' + k); } catch (e) { return null; } },
    set: function (k, v) { try { root.localStorage.setItem('nino.' + k, String(v)); } catch (e) {} }
  };

  root.NINO_APP_VERSION = VERSION;

  // --- Ölçüm (NinoCore docs/tarif/olcum.md) ---
  // Yalnız gerçek TV'de (LG: webos, Samsung: tizen) gider; tarayıcı önizlemesinde platform tanınmadığı için kapalıdır.
  var POOL = 'https://nino-pool.y-demirbag2506.workers.dev';
  // İlk açılışta üretilip saklanan rastgele kimlik.
  function storedId(key) {
    var id = null;
    try { id = root.localStorage.getItem(key); } catch (e) {}
    if (!id) {
      id = N.telemetry.uuid(Math.random);
      try { root.localStorage.setItem(key, id); } catch (e) {}
    }
    return id;
  }
  // Kurulum kimliği: yalnız havuza ve ölçüme gider (sunucu tuzlu özetini tutar).
  function installId() { return storedId('ninoTvId'); }
  // Bağlantı kimliği: göndericiye welcome'da giden, kurulum kimliğinden AYRI kalıcı kimlik. İkisi bilerek farklıdır:
  // ev ağındaki gönderici bu kimliği görse de TV'nin ölçümleriyle eşleştiremez.
  function linkId() { return storedId('nino.linkId'); }

  // Altyazı ekran çevirisinin parçalarıyla çakışmasın (görev şeridi vb.).
  caption.obstacles(board.rects);

  var meter = new N.telemetry.Telemetry({
    endpoint: POOL,
    install: installId,
    ctx: function () {
      return {
        platform: platform.telemetryName || 'browser',
        app: VERSION,
        os: platform.osName ? platform.osName() : '',
        device: root.NINO_TV_MODEL || '',
        tv: platform.brand || '',
        channel: 'release'
      };
    }
  });

  root.addEventListener('error', function (e) {
    meter.uncaught((e && e.error && e.error.name) || 'Error');
  });

  // --- Otomatik teşhis (NinoCore docs/tarif/otomatik-teshis.md): TV'de tv.flapping, app.hang, app.resources ---
  // Bekçi isteğe bağlıdır: sayfayı kendi dosya listesiyle paketleyen bir platformda diag.js eksik kalsa da sayfa çalışır.
  var NoWatchdog = function () {};
  NoWatchdog.prototype.configure = NoWatchdog.prototype.mark = NoWatchdog.prototype.background =
    NoWatchdog.prototype.foreground = NoWatchdog.prototype.tvConnect = NoWatchdog.prototype.tvDrop =
    NoWatchdog.prototype.tick = NoWatchdog.prototype.memory = NoWatchdog.prototype.userStop = function () {};
  var dog = new (N.diag ? N.diag.Watchdog : NoWatchdog)({
    now: function () { return Math.floor(now() / 1000); },
    emit: function (event) { meter.add(event); },
    storage: (function () { try { return root.localStorage; } catch (e) { return null; } })(),
    tv: function () {
      var tv = { brand: platform.brand || '', app: VERSION };
      if (root.NINO_TV_MODEL) tv.model = String(root.NINO_TV_MODEL).slice(0, 60);
      return tv;
    },
    ver: function () { return { tvApp: VERSION }; }
  });
  meter.onConfig = function (t) { dog.configure(t.diag); };
  // Saniyede bir tik: görünürken sayfa 5 sn'den uzun donarsa (tik arası ~6 sn) bildirilir. Bellek (tarayıcı söylüyorsa) 10 sn'de bir.
  // Askıdan dönüşteki ilk tik donma sayılmasın: görünürlük değişince sayaç baştan başlar.
  var beatLast = now();
  doc.addEventListener('visibilitychange', function () { beatLast = now(); });
  (function () {
    var beats = 0;
    setInterval(function () {
      var t = now();
      dog.tick(t - beatLast, !doc.hidden, 1000);
      beatLast = t;
      beats++;
      var mem = root.performance && root.performance.memory;
      if (mem && beats % 10 === 0) dog.memory(mem.usedJSHeapSize / 1048576);
    }, 1000);
  })();
  root.NINO_APP_LABEL = LABEL + ' (' + VERSION + ')';

  // --- Bilgi paneli ---

  var statusBox = $('status');
  var statusTimer = null;

  function setLink(kind) { statusBox.querySelector('.top').setAttribute('data-link', kind === 'ok' || kind === 'bad' ? kind : 'wait'); }
  function setPort(text, bad) { var el = $('status-port'); el.textContent = text; el.className = bad ? 'bad' : ''; }
  function setPicture(text) { $('status-picture').textContent = text; }

  function showStatus(autoClose) {
    on(statusBox, true);
    clearTimeout(statusTimer);
    if (autoClose) statusTimer = setTimeout(hideStatus, 8000);
    refreshLobby();
  }
  function hideStatus() { on(statusBox, false); refreshLobby(); }
  function toggleStatus() { if (isOn(statusBox)) hideStatus(); else showStatus(false); }

  function noteLast(text) {
    statusBox.querySelector('.last .text').textContent = text.length > 60 ? text.slice(0, 60) + '…' : text;
    on($('status-last'), true);
  }

  // --- HDMI ---

  var savedPort = Number(store.get('hdmi'));
  var port = savedPort || 0;
  var NO_PICTURE_MS = 10 * 1000;
  var pictureTimer = null;
  var pictureOk = false;
  var noSignalClosed = false;

  var PICTURE = { loading: 'loading', ready: 'pictureReady', playing: 'playing', inputError: 'inputFailed', sourceError: 'inputUnsupported', lost: 'pictureLost' };

  // Son açılan giriş ve zamanı: aynı giriş yeniden istenince HDMI görüntüsü baştan kurulmaz (LG'de her yeniden kuruluş
  // ekranı bir an karartıyordu; gönderici uygulamayı her öne getirişinde aynı girişi yolluyor).
  var opened = null;
  var openedAt = 0;
  var recoveries = 0;

  function openHdmi(p) {
    opened = p;
    openedAt = now();
    setPort(p ? String(p) : say('auto'));
    pictureOk = false;
    if (pictureTimer) clearTimeout(pictureTimer);
    noSignalClosed = false;
    closeNoSignal();
    if (platform.noPictureHelp) {
      pictureTimer = setTimeout(function () { // görüntü bekleme süresi doldu
        // Kimi TV resmi çizip haber vermiyor; resim zaten varsa uyarı açılmaz.
        var seen = pictureOk || (typeof platform.hasPicture === 'function' && platform.hasPicture());
        if (!seen) showNoSignal(p, false);
      }, NO_PICTURE_MS);
    }
    platform.showHdmi(p, $('hdmi'), function (kind) {
      setPicture(say(PICTURE[kind]));
      if (p !== port) return;
      var good = kind === 'ready' || kind === 'playing';
      var bad = kind === 'inputError' || kind === 'sourceError';
      if (good) {
        pictureOk = true;
        clearTimeout(pictureTimer);
        closeNoSignal();
      } else if (kind === 'lost') {
        // Yalnız gelmiş görüntü kaybolduysa (açılıştaki ilk olaylar sayılmaz).
        if (pictureOk) { pictureOk = false; recoverPicture(); }
      } else if (bad) {
        clearTimeout(pictureTimer);
        if (platform.noPictureHelp) showNoSignal(p, true);
      }
    });
  }

  function choosePort(p, withStatus) {
    port = p;
    store.set('hdmi', p);
    // Aynı giriş açık ve görüntü geliyor (ya da yeni açıldı, gelmek üzere): dokunulmaz.
    var settled = opened === p && (pictureOk || now() - openedAt < NO_PICTURE_MS);
    if (!settled) openHdmi(p);
    if (withStatus) showStatus(true);
  }

  // Görüntü gelirken kayboldu (PS5 çıkış biçimini değiştirdi: ikinci hesap Remote Play'e bağlandı, HDR/çözünürlük
  // değişti). Giriş sessizce yeniden açılır; 1 dk içinde 3 denemeden sonra "görüntü yok" kutusu kendi süresiyle gelir.
  var lastRecovery = 0;
  function recoverPicture() {
    var t = now();
    if (t - lastRecovery > 60000) recoveries = 0;
    if (recoveries >= 3) return;
    recoveries++;
    lastRecovery = t;
    if (dog.mark) dog.mark('hdmi.lost', recoveries);
    setTimeout(function () { openHdmi(port); }, 1000);
  }

  // Bazı TV'ler kaybı olayla bildirmiyor: görüntü gelmişken 2 yoklamada üst üste yoksa yeniden açılır.
  var missing = 0;
  setInterval(function () {
    if (!pictureOk || doc.hidden || typeof platform.hasPicture !== 'function') { missing = 0; return; }
    if (platform.hasPicture()) { missing = 0; return; }
    missing++;
    if (missing >= 2) {
      missing = 0;
      pictureOk = false;
      recoverPicture();
    }
  }, 3000);

  function findConsole(onMissing) {
    platform.findConsolePort(function (found, label) {
      if (!found) { if (onMissing) onMissing(); return; }
      if (found !== port || opened !== found) { port = found; openHdmi(found); }
      setPort(found + ' — ' + label + ' (' + say('auto') + ')');
    });
  }

  // --- "Görüntü yok" kutusu ---

  var noSignal = $('no-signal');
  var choices = [];
  var focus = 0;
  var lastOk = 0;

  function showNoSignal(p, failed) {
    if (noSignalClosed || pictureOk || demo.running()) return;
    noSignal.querySelector('.why').textContent = say(failed ? 'signalFailed' : 'signalMissing', p) + ' ' + say('signalPick');
    var host = noSignal.querySelector('.choices');
    host.innerHTML = '';
    choices = [];
    for (var i = 1; i <= 4; i++) choices.push({ label: 'HDMI ' + i, port: i });
    choices.push({ label: say('signalLeave'), exit: true });
    choices.push({ label: say('signalDismiss'), close: true });
    for (var j = 0; j < choices.length; j++) {
      var el = doc.createElement('div');
      el.className = 'choice' + (choices[j].port === p ? ' current' : '');
      el.textContent = choices[j].label;
      el.addEventListener('click', clickChoice(j));
      el.addEventListener('mouseover', hoverChoice(j)); // LG işaretçisi
      choices[j].el = el;
      host.appendChild(el);
    }
    on(statusBox, false);
    on(noSignal, true);
    refreshLobby();
    setFocus(p % 4); // açık olandan sonraki giriş
  }

  function clickChoice(i) {
    return function (e) {
      e.stopPropagation();
      if (now() - lastOk < 400) return; // Tamam tuşunun ardından gelen tıklama
      setFocus(i);
      runChoice(choices[i]);
    };
  }
  function hoverChoice(i) { return function () { if (i !== focus) setFocus(i); }; }

  function setFocus(i) {
    focus = (i + choices.length) % choices.length;
    for (var k = 0; k < choices.length; k++) {
      choices[k].el.className = 'choice' + (choices[k].port === port ? ' current' : '') + (k === focus ? ' focused' : '');
    }
  }

  // ▲▼: bir üst/alt satırdaki, yatayda en yakın düğme.
  function focusRow(step) {
    var here = choices[focus].el;
    var centre = here.offsetLeft + here.offsetWidth / 2;
    var best = -1;
    var bestRow = 0;
    var bestSide = 0;
    for (var i = 0; i < choices.length; i++) {
      var el = choices[i].el;
      var row = (el.offsetTop - here.offsetTop) * step;
      if (row <= 2) continue;
      var side = Math.abs(el.offsetLeft + el.offsetWidth / 2 - centre);
      if (best < 0 || row < bestRow - 2 || (Math.abs(row - bestRow) <= 2 && side < bestSide)) { best = i; bestRow = row; bestSide = side; }
    }
    if (best >= 0) setFocus(best);
  }

  function runChoice(c) {
    if (c.exit) { closeNoSignal(); leaving = true; platform.exit(); }
    else if (c.close) { noSignalClosed = true; closeNoSignal(); }
    else choosePort(c.port, true);
  }

  function closeNoSignal() {
    if (!isOn(noSignal)) return;
    on(noSignal, false);
    refreshLobby();
  }

  // --- Bekleme sahnesi ve demo ---

  // Örnek konuşma: [oyunun İngilizcesi, Nino'nun Türkçesi, hızlı mı (yığını gösterir)].
  var LINES = [
    ['Somebody has to keep an eye on this city.', 'Birinin bu şehre göz kulak olması lazım.', 0],
    ['Here they come. Keep your head down.', 'İşte geliyorlar. Başını kaldırma.', 0],
    ['Who goes there?', 'Kim o?', 1],
    ['Not this time.', 'Bu sefer olmaz.', 0],
    ['The rain covers our tracks.', 'Yağmur izlerimizi siliyor.', 0],
    ['Up to the roof. Move!', 'Çatıya, çabuk!', 1],
    ['We are not done yet.', 'Daha işimiz bitmedi.', 0]
  ];

  // Mavi tuş demosu: örnek satırlar, hızlı olanlar yığını gösterir.
  var demo = (function () {
    var timer = null, i = 0;
    function step() {
      var line = LINES[i];
      caption.show({ text: line[1], durationMs: 3200 });
      i = (i + 1) % LINES.length;
      timer = setTimeout(step, line[2] ? 1000 : 3900);
    }
    return {
      running: function () { return timer !== null; },
      start: function () {
        if (timer !== null) return;
        hideStatus();
        on($('demo-note'), true);
        i = 0;
        step();
        refreshLobby();
      },
      stop: function () {
        clearTimeout(timer);
        timer = null;
        caption.hide('demo');
        on($('demo-note'), false);
        refreshLobby();
      }
    };
  })();

  // Bekleme sahnesi: önce oyunun İngilizcesi, 0,9 sn sonra Türkçesi üstüne biner.
  var lobby = (function () {
    var timer = null, i = 0;
    var english = $('lobby-english');
    function step() {
      var line = LINES[i];
      i = (i + 1) % LINES.length;
      english.textContent = line[0];
      english.className = 'on';
      timer = setTimeout(function () {
        caption.show({ text: line[1], durationMs: 3000 });
        timer = setTimeout(function () {
          english.className = '';
          timer = setTimeout(step, 900);
        }, 3000);
      }, 900);
    }
    return {
      running: function () { return timer !== null; },
      start: function () {
        if (timer !== null) return;
        N.buildScene($('lobby-scene'));
        on($('lobby'), true);
        doc.body.className += ' lobby';
        i = 0;
        timer = setTimeout(step, 1200);
      },
      stop: function () {
        clearTimeout(timer);
        timer = null;
        on($('lobby'), false);
        english.className = '';
        doc.body.className = doc.body.className.replace(/(^| )lobby( |$)/, ' ').replace(/^\s+|\s+$/g, '');
        caption.hide('lobby');
      }
    };
  })();

  // Sahne yalnız gönderici bilinmiyorken ve önünde başka bir şey yokken oynar.
  function refreshLobby() {
    var want = !link.known() && !demo.running() && !isOn(statusBox) && !isOn(noSignal);
    if (want && !lobby.running()) lobby.start();
    else if (!want && lobby.running()) lobby.stop();
  }

  function renderWhere(ip) {
    $('lobby-where').textContent = (ip ? say('tvAddress', ip) + ' · ' : '') + say('searching');
  }

  // --- Çeviri sürüyor rozeti ve "başladı" bildirimi ---

  var BADGE_IDLE_MS = 90 * 1000;
  var badgeTimer = null;
  function badge(yes) {
    clearTimeout(badgeTimer);
    on($('watermark'), yes);
    if (yes) badgeTimer = setTimeout(function () { badge(false); }, BADGE_IDLE_MS);
  }

  var helloTimer = null;
  function sayStarted() {
    var el = $('hello');
    if (!el) {
      el = doc.createElement('div');
      el.id = 'hello';
      el.innerHTML = '<span class="face"><img src="img/nino-bot.png" alt=""></span><span class="say"></span>';
      doc.body.appendChild(el);
    }
    el.querySelector('.say').textContent = say('startedNote');
    el.offsetWidth; // geçiş baştan oynasın
    el.className = 'on';
    clearTimeout(helloTimer);
    helloTimer = setTimeout(function () { el.className = ''; }, 7000);
  }

  function clearAll() {
    caption.hide('drop');
    board.hide();
    board.hideAreas();
    badge(false);
  }

  // --- Gönderici komutları ---

  function command(cmd) {
    switch (cmd.kind) {
      case 'show':
        if (typeof cmd.light === 'number') caption.applyLight(cmd.light);
        caption.applyFrost(cmd.cover);
        caption.show(cmd);
        badge(true);
        noteLast(cmd.text);
        break;
      case 'clear': caption.clear(cmd.id); break;
      case 'style':
        caption.applyStyle(cmd.style, store.set);
        var b = cmd.style.bottomPercent;
        if (b >= 0 && String(b) !== store.get('appBottom')) {
          store.set('appBottom', b);
          store.set('bottom', '');
          caption.setBottom(b);
        }
        break;
      case 'screen':
        board.show(cmd.items, cmd.durationMs, cmd.overlay);
        if (cmd.items && cmd.items.length) badge(true);
        break;
      case 'screen-clear': board.hide(); break;
      case 'region': board.showArea(cmd.region); break;
      case 'region-clear': board.hideAreas(); break;
      case 'started': sayStarted(); badge(true); break;
      case 'stopped': badge(false); clearAll(); if (dog.userStop) dog.userStop(); break;
    }
  }

  // TV bağlantısının ölçümü: deneme başı → sonuç (tv_connect), bağlıyken kopma (tv_drop). Bir kesinti boyunca
  // başarısız deneme yalnız bir kez sayılır (yeniden denemeler saniyede bir olabilir).
  // tv_drop nedeni: timeout (sessizlik/asılı bağlantı), resume (uygulama öne geldi), closed (karşı taraf kapattı),
  // replaced (gönderici, bu bağlantının yerini başka bir bağlantının aldığını söyledi: aynı TV yeniden bağlandı ya da
  // TV başka göndericiye geçti).
  var DROP_REASONS = { timeout: 1, resume: 1, closed: 1, replaced: 1 };
  var tries = null;
  var upSince = 0;
  function noteLink(kind) {
    var t = now();
    var proto = link && link.address ? link.address.kind : 'nino';
    var brand = platform.brand || '';
    if (kind === 'connecting') {
      if (!tries) tries = { at: t, told: false };
    } else if (kind === 'ok') {
      meter.add({ k: 'tv_connect', r: 'ok', ms: tries ? t - tries.at : 0, brand: brand, proto: proto });
      dog.tvConnect(proto);
      tries = null;
      upSince = t;
    } else if (kind === 'bad') {
      var problem = link ? link.problem : null;
      if (upSince) {
        meter.add({ k: 'tv_drop', code: DROP_REASONS[problem] ? problem : 'other', brand: brand,
          after: Math.round((t - upSince) / 1000) });
        dog.tvDrop(problem);
        upSince = 0;
        tries = { at: t, told: false };
      } else if (tries && !tries.told) {
        tries.told = true;
        meter.add({ k: 'tv_connect', r: problem === 'tv.protocol.mismatch' ? problem : (problem === 'timeout' ? 'tv.connect.timeout' : 'tv.connect.refused'),
          ms: t - tries.at, brand: brand, proto: proto });
      }
    }
  }

  function tvName() { return root.NINO_TV_MODEL || 'TV'; }

  // Platform kendi bağlantısını verebilir (Android TV: yerel köprü); yoksa sayfa göndericiye kendisi bağlanır.
  // Verilen nesne Link'in connect, known, scan ve address alanlarını taşımalı.
  var linkOptions = {
    platform: platform,
    store: store,
    name: tvName,
    id: linkId,
    model: function () { return root.NINO_TV_MODEL || ''; },
    // Her bağlanma denemesi (tarama sonucu dahil) demoyu durdurur, bekleme sahnesini kaldırır.
    onStatus: function (kind) {
      noteLink(kind);
      setLink(kind === 'connecting' ? 'wait' : kind);
      if (kind === 'connecting' && demo.running()) demo.stop();
      refreshLobby();
    },
    onCommand: command,
    onDrop: clearAll,
    onTvAddress: renderWhere
  };
  var link = platform.makeLink ? platform.makeLink(linkOptions) : new N.Link(linkOptions);

  function useServer(address) {
    if (!address) return;
    var parsed = N.protocol.parseAddress(address);
    if (!parsed || (link.address && link.address.url === parsed.url)) return;
    if (demo.running()) demo.stop();
    link.connect(address);
    refreshLobby();
  }

  // Yerel köprü: Android TV kendi sunucusunda el sıkışmayı yapıp hazır mesajları buraya verir
  // (window.nino.receive({type: 'show', ...})). LG ve Samsung bunu kullanmaz.
  root.nino = root.nino || {};
  root.nino.receive = function (message) {
    var cmd = N.protocol.toCommand(message);
    if (cmd) command(cmd);
  };

  // --- Açılış parametreleri ---

  function params(raw) {
    if (!raw) return {};
    if (typeof raw !== 'string') return raw;
    try {
      return JSON.parse(raw) || {};
    } catch (e) {
      return {};
    }
  }

  function applyParams(p) {
    if (p.hdmi >= 1 && p.hdmi <= 4) choosePort(Number(p.hdmi), false);
    useServer(p.link || p.server);
  }

  // --- Samsung: Anynet+ girişi kendisi HDMI'ya çevirdi ---

  var visibleSince = now();
  var hiddenAt = [];
  var leaving = false;
  var tipTimer = null;
  var tip = $('source-note');

  function noteHidden() {
    if (leaving || !platform.sourceSwitchTip) return;
    var t = now();
    hiddenAt.push(t);
    while (hiddenAt.length && t - hiddenAt[0] > 300000) hiddenAt.shift();
    if (t - visibleSince < 10000 || hiddenAt.length >= 3) store.set('sourceSwitch', t);
  }

  // Not metni platforma göre: Samsung'da Anynet+'ın girişi kendisi değiştirdiğini söyleyen not, LG'de "girişi Nino'dan seçin".
  function tipTexts() {
    var prefix = platform.tipKeys || 'autoInput';
    tip.querySelector('b').textContent = say(prefix + 'Title');
    tip.querySelector('span').textContent = say(prefix + 'How');
  }

  function maybeTip() {
    if (!platform.sourceSwitchTip) return;
    // LG: ilk açılışta bir kez de gösterilir (giriş menüsünden HDMI'ya geçince uygulama kapanıyordu).
    var first = platform.tipOnFirstRun && !store.get('inputHintShown');
    if (!first && !store.get('sourceSwitch')) return;
    if (first) store.set('inputHintShown', '1');
    store.set('sourceSwitch', '');
    tipTexts();
    on(tip, true);
    clearTimeout(tipTimer);
    tipTimer = setTimeout(closeTip, 30000);
  }
  function closeTip() { clearTimeout(tipTimer); on(tip, false); }

  doc.addEventListener('visibilitychange', function () {
    if (doc.hidden) { meter.sleep(); dog.background(); } else { meter.awake(); dog.foreground(); }
    if (doc.hidden) noteHidden();
    else {
      visibleSince = now();
      maybeTip();
      // Askıdan dönünce bağlantı ölmüş olabilir (Samsung saha hatası): hemen tazelenir.
      if (link && link.resume) link.resume();
    }
  });

  // --- Kumanda ---

  function back() {
    if (isOn(tip)) return closeTip();
    if (isOn(noSignal)) { noSignalClosed = true; return closeNoSignal(); }
    if (demo.running()) return demo.stop();
    if (isOn(statusBox)) return hideStatus();
    leaving = true;
    platform.exit();
  }

  function nudge(step) {
    if (!caption.fixed()) return;
    caption.setBottom(caption.bottom() + step);
    store.set('bottom', caption.bottom());
    if (!caption.visible()) caption.show({ text: say('placeHint'), durationMs: 2500 });
  }

  doc.addEventListener('click', function () {
    if (now() - lastOk < 400) return;
    if (isOn(tip)) closeTip();
    else if (isOn(noSignal)) return;
    else if (!demo.running()) toggleStatus();
  });

  doc.addEventListener('keydown', function (e) {
    var k = e.keyCode;
    var handled = true;
    if (k === KEY.OK) lastOk = now();
    if (k === KEY.OK && isOn(tip)) closeTip();
    else if (isOn(noSignal) && (k === KEY.LEFT || k === KEY.RIGHT)) setFocus(focus + (k === KEY.RIGHT ? 1 : -1));
    else if (isOn(noSignal) && (k === KEY.UP || k === KEY.DOWN)) focusRow(k === KEY.DOWN ? 1 : -1);
    else if (isOn(noSignal) && k === KEY.OK) runChoice(choices[focus]);
    else if (k === 48) {
      store.set('hdmi', '');
      findConsole(function () { setPort(port + ' (' + say('noConsole') + ')', true); });
      showStatus(true);
    } else if (k >= 49 && k <= 52) choosePort(k - 48, true);
    else if (k === KEY.RED) caption.show({ text: say('testLine'), durationMs: 4000 });
    else if (k === KEY.GREEN) toggleStatus();
    else if (k === KEY.BLUE) { if (demo.running()) demo.stop(); else demo.start(); }
    else if (k === KEY.OK && !demo.running()) toggleStatus();
    else if ((k === KEY.LEFT || k === KEY.RIGHT) && isOn(statusBox)) choosePort((port + (k === KEY.RIGHT ? 1 : -1) + 3) % 4 + 1, true);
    else if (k === KEY.BACK) back();
    else if (k === KEY.UP || k === KEY.DOWN) nudge(k === KEY.UP ? 3 : -3);
    else handled = false;
    if (handled && (k === KEY.BACK || (k >= KEY.LEFT && k <= KEY.DOWN))) e.preventDefault();
  });

  // --- Başlangıç ---

  platform.onRelaunch(function (raw) { applyParams(params(raw)); });
  var timing = root.performance && root.performance.timing;
  meter.start(timing && timing.navigationStart ? now() - timing.navigationStart : undefined);
  root.addEventListener('pagehide', function () { meter.sleep(); });
  platform.init();
  N.fillTexts();
  caption.setStack(store.get('stackPrevious') !== '0');
  var savedBottom = store.get('bottom') || store.get('appBottom');
  if (savedBottom) caption.setBottom(Number(savedBottom));
  // HDMI açılışta bir kez açılır: açılış parametresindeki giriş, yoksa kayıtlı giriş, yoksa bulunan konsol (bulunamazsa
  // HDMI 1). Eskiden önce HDMI 1 açılıp konsol bulununca ikinci kez açılıyordu: LG'de açılışta ekran kararıp geliyordu.
  var first = params(platform.launchParams());
  if (first.hdmi >= 1 && first.hdmi <= 4) choosePort(Number(first.hdmi), false);
  else if (savedPort) openHdmi(port);
  else findConsole(function () { openHdmi(port || 1); });
  renderWhere(null);
  maybeTip();

  applyParams(first);
  if (!link.known()) useServer(store.get('server') || config.server);
  if (!link.known()) link.scan();
  if (link.known()) showStatus(true); else hideStatus();
  refreshLobby();
})(window);
