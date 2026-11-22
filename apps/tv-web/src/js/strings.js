// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Ekrandaki metinler. Dil TV'nin dilinden: Türkçe, Arapça, değilse İngilizce.
(function (root) {
  'use strict';

  // Menü adları (Samsung ayarları, PS5 ayarları) cihazın kendi menü adlarıdır.
  var TR = {
    step1: 'Nino\'yu Mac\'te, Windows\'ta Ya Da Android Telefonda Başlatın',
    step2: 'Cihazlar Aynı Wi-Fi Ağına Bağlı Olsun',
    step3: 'Kalanını Nino Yapar',
    awaiting: 'Bağlanmayı Bekliyor',
    tvAddress: 'TV adresi: %1',
    searching: 'Nino ağda aranıyor…',
    pointer: 'Oyunda Altyazı Böyle Görünür',
    previewTag: 'TANITIM',
    previewNote: 'Oyunun İngilizce konuşmaları burada Türkçe çıkar. Kapatmak için Geri tuşuna basın.',
    brandName: 'Nino',
    stateOk: 'Çeviriye hazır',
    stateWait: 'Nino\'yu bekliyor',
    stateBad: 'Bağlantı kesildi',
    lastLabel: 'Son gelen altyazı',
    hdmi: 'HDMI',
    loading: 'açılıyor',
    pictureReady: 'görüntü var',
    playing: 'oynuyor',
    inputFailed: 'giriş açılmadı',
    inputUnsupported: 'bu giriş desteklenmiyor',
    pictureLost: 'görüntü yeniden alınıyor',
    lgInputTitle: 'PS5 görüntüsü Nino\'nun içinde.',
    lgInputHow: 'TV\'nin kaynak (giriş) menüsünden HDMI\'ya geçmeyin: Nino kapanır, altyazı gelmez. PS5\'in girişini Nino\'nun içinden seçin: kumandada 1–4 tuşları ya da Tamam ile açılan panelde ◀▶.',
    auto: 'otomatik',
    noConsole: 'PS5 görünmüyor',
    testLine: 'Deneme yazısı: bunu oyunun üstünde görebiliyor musunuz?',
    placeHint: 'Altyazılar burada çıkacak',
    startedNote: 'Nino: Altyazılar Çevriliyor. İyi Oyunlar!',
    autoInputTitle: 'TV kendiliğinden HDMI girişine geçti.',
    autoInputHow: 'Bunu önlemek için Ayarlar › Tüm Ayarlar › Bağlantı › Harici Cihaz Yöneticisi bölümünde Anynet+ (HDMI-CEC) ile Otomatik Kaynak Değiştirme\'yi kapatın.',
    autoInputClose: 'Tamam ya da Geri tuşu bu notu kapatır.',
    signalTitle: 'HDMI görüntüsü gelmiyor',
    signalMissing: 'HDMI %1 girişinde görüntü yok.',
    signalFailed: 'Bu uygulama HDMI %1 girişini açamadı.',
    signalPick: 'PS5 başka bir girişteyse onu aşağıdan seçin (◀▶ ve Tamam ya da 1–4 tuşları).',
    signalHelp: 'Doğru girişte de ekran siyahsa PS5\'te HDR\'yi kapatın (Ayarlar › Ekran ve Video › Video Çıkışı › HDR: Kapalı); Uzaktan Oynatma sırasında HDR görüntüyü karartabilir. Düzelmezse TV, HDMI görüntüsünü uygulamalara vermiyor ya da HDCP engel oluyor olabilir: PS5\'te Ayarlar › Sistem › HDMI › HDCP\'yi Etkinleştir seçeneğini kapatıp yeniden deneyin. Yine olmazsa Nino\'yu kapatın, TV\'yi kumandayla PS5\'in girişine alın ve altyazıları telefonda ya da bilgisayarda izleyin.',
    signalLeave: 'Kapat ve TV girişine geç',
    signalDismiss: 'Vazgeç'
  };

  var EN = {
    step1: 'Start Nino On Your Mac, Windows PC Or Android Phone',
    step2: 'Keep Everything On One Wi-Fi Network',
    step3: 'Nino Handles The Rest',
    awaiting: 'Waiting To Connect',
    tvAddress: 'TV address: %1',
    searching: 'Searching the network for Nino…',
    pointer: 'Subtitles Look Like This In Game',
    previewTag: 'PREVIEW',
    previewNote: 'The game\'s English lines show up here in Turkish. Press Back to leave.',
    brandName: 'Nino',
    stateOk: 'Ready to translate',
    stateWait: 'Waiting on Nino',
    stateBad: 'Disconnected',
    lastLabel: 'Latest subtitle',
    hdmi: 'HDMI',
    loading: 'opening',
    pictureReady: 'picture available',
    playing: 'running',
    inputFailed: 'input did not open',
    inputUnsupported: 'this input is not supported',
    pictureLost: 'getting the picture back',
    lgInputTitle: 'The PS5 picture is inside Nino.',
    lgInputHow: 'Do not switch to HDMI from the TV\'s source (input) menu: Nino closes and subtitles stop. Pick the PS5 input inside Nino: keys 1–4 on the remote, or ◀▶ in the panel that OK opens.',
    auto: 'auto',
    noConsole: 'no PS5 found',
    testLine: 'Test line: can you see this over the game?',
    placeHint: 'Subtitles will show up here',
    startedNote: 'Nino: Translating Subtitles. Have Fun!',
    autoInputTitle: 'The TV jumped to the HDMI input on its own.',
    autoInputHow: 'To stop this, turn off Anynet+ (HDMI-CEC) and Auto Source Switching under Settings › All Settings › Connection › External Device Manager.',
    autoInputClose: 'OK or Back closes this note.',
    signalTitle: 'The HDMI picture is not coming through',
    signalMissing: 'HDMI %1 has no picture.',
    signalFailed: 'This app could not open HDMI %1.',
    signalPick: 'If the PS5 is on a different input, pick it below (◀▶ and OK, or keys 1–4).',
    signalHelp: 'Still black on the right input? Switch HDR off on the PS5 (Settings › Screen and Video › Video Output › HDR: Off), since HDR can darken the picture during Remote Play. If that does not help, the TV may not share its HDMI picture with apps, or HDCP may be blocking it: try switching off Settings › System › HDMI › Enable HDCP on the PS5. If it stays black, close Nino, put the TV on the PS5 input with your remote and follow the subtitles on your phone or computer.',
    signalLeave: 'Close and go to the TV input',
    signalDismiss: 'Dismiss'
  };

  var AR = {
    step1: 'شغّل Nino على Mac أو Windows أو هاتف Android',
    step2: 'اجعل الأجهزة على شبكة Wi-Fi واحدة',
    step3: 'ويتولى Nino ما تبقّى',
    awaiting: 'في انتظار الاتصال',
    tvAddress: 'عنوان التلفاز: %1',
    searching: 'يجري البحث عن Nino في الشبكة…',
    pointer: 'هكذا تبدو الترجمة في اللعبة',
    previewTag: 'تجربة',
    previewNote: 'هنا تظهر ترجمة الحوار الإنجليزي في اللعبة. للخروج اضغط «رجوع».',
    brandName: 'Nino',
    stateOk: 'الترجمة جاهزة',
    stateWait: 'في انتظار Nino',
    stateBad: 'الاتصال مقطوع',
    lastLabel: 'آخر ترجمة وصلت',
    hdmi: 'HDMI',
    loading: 'يجري الفتح',
    pictureReady: 'الصورة متاحة',
    playing: 'يعمل',
    inputFailed: 'لم يُفتح المدخل',
    inputUnsupported: 'هذا المدخل غير مدعوم',
    pictureLost: 'يجري استعادة الصورة',
    lgInputTitle: 'صورة PS5 تظهر داخل Nino.',
    lgInputHow: 'لا تنتقل إلى HDMI من قائمة المصادر (المدخلات) في التلفاز، فسيُغلق Nino وتتوقف الترجمة. اختر مدخل PS5 من داخل Nino: الأزرار 1–4 في جهاز التحكم، أو ◀▶ في اللوحة التي يفتحها OK.',
    auto: 'آلي',
    noConsole: 'جهاز PS5 غير ظاهر',
    testLine: 'نص للتجربة: هل تراه فوق اللعبة؟',
    placeHint: 'ستظهر الترجمة في هذا المكان',
    startedNote: 'Nino: الترجمة تعمل الآن. لعبًا ممتعًا!',
    autoInputTitle: 'انتقل التلفاز من تلقاء نفسه إلى مدخل HDMI.',
    autoInputHow: 'لمنع ذلك أوقف Anynet+ (HDMI-CEC) وتبديل المصدر التلقائي من الإعدادات › كل الإعدادات › الاتصال › إدارة الأجهزة الخارجية.',
    autoInputClose: 'تُغلق هذه الملاحظة بزر OK أو «رجوع».',
    signalTitle: 'صورة HDMI لا تصل',
    signalMissing: 'لا توجد صورة في مدخل HDMI %1.',
    signalFailed: 'لم يتمكن هذا التطبيق من فتح مدخل HDMI %1.',
    signalPick: 'إذا كان PS5 على مدخل آخر فاختره من الأسفل (◀▶ ثم OK، أو الأزرار 1–4).',
    signalHelp: 'إذا بقيت الشاشة سوداء على المدخل الصحيح فأوقف HDR في PS5 (الإعدادات › الشاشة والفيديو › إخراج الفيديو › HDR: إيقاف)، لأن HDR قد يُعتم الصورة أثناء التشغيل عن بُعد. وإن لم يتحسن الأمر فقد لا يتيح التلفاز صورة HDMI للتطبيقات أو قد يمنعها HDCP: جرّب إيقاف الإعدادات › النظام › HDMI › تمكين HDCP في PS5. وإن بقيت سوداء فأغلق Nino، وحوّل التلفاز إلى مدخل PS5 بجهاز التحكم، وتابع الترجمة على الهاتف أو الكمبيوتر.',
    signalLeave: 'أغلق وانتقل إلى مدخل التلفاز',
    signalDismiss: 'تراجع'
  };

  var tag = String((root.navigator && root.navigator.language) || 'en').toLowerCase();
  var language = tag.indexOf('tr') === 0 ? 'tr' : (tag.indexOf('ar') === 0 ? 'ar' : 'en');
  var table = { tr: TR, en: EN, ar: AR }[language];

  function say(key, value) {
    var text = table[key] || EN[key] || key;
    return value === undefined ? text : text.replace('%1', value);
  }

  // data-say niteliği taşıyan öğelere metinlerini yazar; Arapçada yazı yönü sağdan sola olur.
  function fill(scope) {
    var nodes = (scope || root.document).querySelectorAll('[data-say]');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].textContent = say(nodes[i].getAttribute('data-say'));
      if (language === 'ar') nodes[i].setAttribute('dir', 'rtl');
    }
  }

  root.Nino = root.Nino || {};
  root.Nino.say = say;
  root.Nino.fillTexts = fill;
  root.Nino.language = language;
})(window);
