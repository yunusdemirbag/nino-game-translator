<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# LG ve Samsung TV uygulaması: ilerleme

Dal: `claude/yeni-tv-web-2fe593`. Yeni uygulama: `apps/tv-web/` (eski `tv-webos/`, `tv-tizen/` silinmedi).

## Bitenler (22 Kasım 2026)

- Davranış tarifi: `tarif.md`. Bağlantı kararı: `baglanti.md`.
- Tek ortak web uygulaması, ES5, ek kütüphane yok:
  - `src/js/protocol.js` TV tarafı protokol oturumu (el sıkışma, sürüm, 16 KB, ping/pong, 20 sn sessizlik, uzantılar)
  - `src/js/link.js` bağlantı: yeni gönderici (WebSocket, TV arar), eski gönderici (8787, EventSource), ağ tarama
  - `src/js/caption.js` altyazı, `board.js` ekran çevirisi ve köşe yazıları, `scene.js` bekleme sahnesi,
    `main.js` panel, HDMI, "görüntü yok" kutusu, demo, kumanda, `strings.js` Türkçe/İngilizce/Arapça
  - `platform/webos.js`, `platform/tizen.js` TV'ye özgü işler; `src/platform.js` tarayıcı önizlemesi için sahte TV
- Paketler: `python3 apps/tv-web/tools/package.py` →
  `dist/com.ninotranslator.tv_4.5.0_all.ipk` (LG) ve `dist/nino-samsung_4.5.0.wgt` (Samsung, imzasız).
- Testler: `node --test apps/tv-web/test` → 79 test (47800 doluysa tarama testi atlanır). Protokol testleri
  TV tarafını kendi sahte göndericimize (`tools/fake-sender.js`) karşı dener; NinoCore koduyla birlikte denenmedi.
- Tarayıcı önizlemesi (`.claude/launch.json`: `tv-web-yeni`, `tv-web-gonderici`): eski uygulamanın aynı sahte TV ile
  açılmış kopyasıyla karşılaştırıldı. Altyazı, örtü, yığın, cam görünüm, ekran çevirisi parçaları, köşe yazısı,
  "görüntü yok" kutusu ve panelin yer ve boyları piksel piksel aynı; hem yeni protokolle (WebSocket) hem eski
  yolla (8787 olay akışı) denendi. Tarama yolu da denendi: kayıtlı adres yokken TV göndericiyi bulup bekleme
  ekranını kapatıyor.
- Tarif belgelerinin eski hâli depo dışında arşivlendi: `~/NinoYedek/tarif-arsiv/tv-web/` (ana oturum kararı); depodaki
  tariflerde eski ekran metni alıntısı yok, metinler anahtar adıyla anılıyor. Metin anahtarları da yeniden adlandırıldı.
- Eski koddan satır kalmadı mı: boşlukları sadeleştirilmiş, 25 karakterden uzun satırlar `tv-webos`/`tv-tizen` ile
  karşılaştırıldı. Kod satırlarındaki eşleşmeler yeniden yazıldı. Kalan eşleşmeler: arayüz metinleri (Türkçe,
  İngilizce, Arapça; aynı kalmaları gerekiyor), CSS'teki tasarım değerleri (renk, ölçü, gölge satırları), platformun
  zorunlu yazımı (`config.xml` izinleri, `appinfo.json` alanları), `<meta viewport>`, lisans başlığı. Bekleme sahnesindeki pencere ışıkları ve
  çatıdaki kahraman yeniden çizildi (benzer, birebir değil).

## Gece eklenenler (22 Kasım)

- Ekran metinleri ve bekleme ekranındaki örnek konuşma Türkçe, İngilizce ve Arapça olarak aynı anlamla yeniden
  yazıldı; eski metin kalmadı. Menü adları (Samsung ve PS5 ayarları) cihazdaki adlarıyla duruyor.
- Protokol uzantılarının (style, screen, region, cover, light, started/stopped) hepsi eski uygulamayla yan yana
  ölçüldü: yer, boy, yazı tipi, zemin, gölge, dönme ve bulanıklık değerleri aynı (yalnız yeni metinlerin uzunluğu
  farklı).
- Ortak protokol kararı: mesaj sınırı 512 KB; Android TV için `window.nino.receive` girişi ve `platform.makeLink`.
- Ölçüm istemcisi (`src/js/telemetry.js`, tarif: NinoCore `docs/tarif/olcum.md`): launch, crash (çalışma işareti),
  error (yalnız kod; yakalanmayan JS hatası `app.js.<Tür>`), tv_connect (r, ms, brand, proto), tv_drop (code, after).
  Kuyruk tarayıcı deposunda, 10 dk'da bir ya da 100 olayda, arka plana geçerken gönderilir; 200/400/413/429/5xx
  kurallı. Yalnız gerçek TV'de çalışır (platform `webos`/`tizen`); tarayıcı önizlemesinde hiçbir şey yazılmaz ve
  gönderilmez. Ayarlarda kapatma düğmesi yok (ana oturum kararı); sunucu `telemetry.enabled=false` ile durdurabilir.
  8 testi var.
- Eski kurulu Nino (8787) ile tarayıcıda denendi: yeni sayfa bağlanıyor ve Nino'nun ayarlarını alıyor.

## Sürüm

TV uygulaması 4.5.0 (kullanıcı kararı); kurulu 4.0.3'ün üstüne güncelleme olarak kurulabilsin diye LG kimliği
`com.ninotranslator.tv`, Samsung kimliği `NinoTVApps.Nino` ve Samsung widget kimliği eski paketteki gibi.

## Kopmadan kurtulma (saha hatası, 22 Kasım)

Samsung Tizen 8 + eski TV uygulaması 4.0.3: altyazı bir süre geliyor, sonra TV takılıyor, geri bağlanmıyordu. Yeni
uygulamada (`src/js/link.js`, bekçi 5 sn'de bir):
- Yeni protokol: bağlıyken 15 sn hiç mesaj (ping dahil) gelmezse bağlantı bırakılır ve yeniden kurulur; el sıkışma
  10 sn'de bitmezse de. Yeniden deneme 1, 2, 4, 8 sn arayla hiç bitmez; 3 başarısızlıktan sonra ağ yeniden taranır
  (gönderici adres değiştirdiyse bulunur).
- Eski 8787 düzeni: akış kapanırsa, 30 sn "bağlanıyor"da kalırsa ya da ping görülmüşken 25 sn sessizse baştan kurulur.
- Uygulama öne gelince (kaynak değişimi, ekran koruyucu, askıdan dönüş: `visibilitychange`) bağlantı hemen tazelenir.
- Ölçüm: `tv_drop.code` = `timeout` · `resume` · `closed` · `replaced` (gönderici `error` `replaced` yolladıysa) · `other`; başarısız bağlanma `tv.connect.timeout` /
  `tv.connect.refused` / `tv.protocol.mismatch`.
- Testler (`test/link-recover.test.js`): gönderici sessizce bırakınca yeniden bağlanma (yeni ve eski düzen), asılı
  el sıkışma, öne gelince tazeleme, varsayılan sürelerle sessiz kopmadan en geç 21 sn'de yeniden deneme.

## Otomatik teşhis (bekçi)

Tarif: NinoCore `docs/tarif/otomatik-teshis.md` (ortak klasörde `otomatik-teshis.md`). `src/js/diag.js`, ölçüm
kuyruğuna `k: "diag"` olayı ekler (günlük olay sınırından muaf, kendi sınırları: kural başına çalışmada 1, günde
toplam 5, kural başına 2; tek kök için 5 dk öncelik). TV kuralları:
- `tv.flapping`: 10 dk içinde 3 kopma; sebep kopma nedenlerinin çoğunluğu (`timeout`, `closed`, `resume` …), yoksa `mixed`.
  Açılışın ilk dakikasında ve kullanıcı durdurduktan sonra (`stopped`) susar; arka plan susturması bu kurala uygulanmaz (TV'de arka plana gidip gelme kopmanın
  kendisidir).
- `app.hang`: sayfa görünürken 5 sn'den uzun donarsa (saniyelik tik arası ~6 sn, `blockedSec`); askıdan dönüş sayılmaz.
- `app.resources`: JS belleği 400 MB'ı 2 dk aşarsa (tarayıcı `performance.memory` veriyorsa).
- İz: son 10 dk, 200 adım (`tv.connect`, `tv.drop`, `app.background`, `app.foreground`, `app.hang`, `mem.high`).
- Uzaktan ayar `telemetry.diag` (`off`, `limits`) her olay gönderiminin cevabından okunur.
- Testler: `test/diag.test.js` ortak senaryo dosyasının kopyasını (`test/fixtures/diag-scenarios.json`) çalıştırır.
- `diag.js` yüklenmezse sayfa bekçisiz çalışır (Android TV sayfayı kendi listesiyle paketliyor).

## Telefon paneli (canlı oyundan, 22 Kasım)

- Başlık: yeni gönderici (NinoCore PhoneLayout) telefon başlığını ayrı bir sade yazı öğesi olarak yollar; sayfa onu
  sola yaslı çiziyordu. Artık panelin üst %15'indeki zeminsiz sade yazı, metni olmayan panelin ortalı başlığı olur
  (eski göndericideki panel metniyle aynı görünüm). `board.prepare`.
- Yenilenme: aynı içerik (yer, boy, eğiklik, satır boyu dışında aynı) yeniden gelince hiçbir şey yeniden çizilmez,
  canlandırma oynamaz; yalnız yerler yumuşakça güncellenir ve süre sayacı baştan başlar. Önceden bu yalnız bütün
  öğeler renkli balonsa çalışıyordu; başlık öğesi yüzünden telefon paneli her tazelemede baştan çiziliyordu.
- Testler: `test/board.test.js`; tarayıcıda: başlık ortası = panel ortası, aynı liste iki kez + kayma: aynı öğeler,
  yeni canlandırma yok.

## Canlı kare düzeltmeleri (17:23, 22 Kasım)

- Örtme kipinde çeviri örtüden taşıyordu (cam görünümün yuvarlak yazı tipi sonradan yüklenip yazıyı genişletiyordu):
  örtü ve yerleşim 120 ms sonra ve yazı tipleri yüklenince yeniden ölçülür (`settleLater`). Örtü her zaman en az
  çevirinin genişliğindedir; çeviri kırpılmaz.
- Görev şeridi (sade yazı) oyundaki İngilizceyi tam örtmüyordu: en az kutu genişliğinde ve opak zeminli
  (`rgba(0,0,0,0.92)`; önceden %38 saydam ve yazısı kadar daralıyordu).
- Altyazı ekran çevirisinin bir parçasıyla çakışırsa o parçanın üstüne itilir (`Nino.text.lift`); örtme kipinde yazı
  kendi zeminini alır; ekran çevirisi kalkınca altyazı yerine döner.
- Testler: `text.test.js` (lift); tarayıcıda ölçüldü: yazı örtünün içinde, çakışma yok, temizleyince yerine dönüyor.
- Harita kartı (`card:true`, Mac isteği): kutuya tam oturur (pay yok, yükseklik kutu kadar), zemin opak
  `rgb(38,38,50)`, yazı satır boyundan başlayıp sığana kadar 1 px küçülür. Tarayıcıda Mac'in 17:18 örneğiyle ölçüldü:
  kart dikdörtgeni kutuyla birebir, yazı sığıyor.

## Yazı boyu ayarı (kullanıcı bildirdi)

- Otomatik boy açıkken (varsayılan) ve altyazı oyundakine bağlıyken (örtme, üstünde, altında) boy İngilizce satırdan
  hesaplanıyor, kullanıcının "Yazı boyu" ayarı yok sayılıyordu (eski uygulamada da böyleydi). Artık ayar çarpan olarak
  uygulanır: `boy = ölçülen × (fontSize / 46)`, çarpan 0,5–2,5, en çok ekran yüksekliğinin %14'ü (`Nino.text.autoFont`).
- `style` gelince ekrandaki altyazı hemen yeni boyla yeniden yerleşir (ölçüm geçmişi büyümeden).
- Tarayıcıda: örtme kipinde 46 → 39 px, 69 gelince hemen 59 px; sabit yerleşimde 69 → 69 px, 40 → 40 px.
- Kullanıcı isteği: otomatik boyda alttaki altyazı oyunun satırından **%25 büyük** (`Nino.text.AUTO_BOOST`); yazı boyu
  ayarı bunun üstüne çarpılır. Kart, harita ve telefon bindirmeleri değişmedi. Uzun çeviri iki satırı aşarsa sığana kadar
  küçülür (iki satıra bölme küçültmesi korunur), ama oyunun kendi altyazısından küçük olmaz. Tarayıcıda: kısa satır
  39 → 49 px; uzun satır 2 satır; yazı boyu ×2'de kısa 98 px, uzun 54 px ile 2 satır, ekran içinde.

## Hata listesi denetimi (kullanıcı bildirimleri)

**Konuşanın adı sarı.** `show.speaker` (isteğe bağlı, en çok 60 karakter) ya da yazının başındaki büyük harfli
`AD:` etiketi (en çok 3 sözcük) sarı (#FFE135) çizilir; üstteki önceki satırlarda da. Büyük-küçük harfi olmayan
yazıda (Arapça) yalnız `speaker` alanı kullanılır; ad satırın başında, sağdan sola düzende doğru tarafta durur.
`Nino.text.speakerOf`, testleri `text.test.js` / `protocol.test.js`.

**LG (gerçek LG yok; koddan):**
- (a) Ekran ~1 dk'da bir kapanıp açılıyor, açılışta kendi kendine açılıp kapanıyor. Koddaki en olası neden: HDMI
  görüntüsünün gereksiz yeniden kurulması. Gönderici uygulamayı her öne getirişinde (webOSRelaunch) aynı `hdmi`
  parametresini yollar; sayfa her seferinde `<video>`'yu baştan kuruyordu ve LG'de bu ekranın bir an kararması
  demek. Açılışta da önce HDMI 1 açılıp konsol bulununca ikinci kez açılıyordu. Düzeltme: aynı giriş açıkken (görüntü
  geliyor ya da 10 sn içinde açıldı) yeniden açılmaz; açılışta HDMI bir kez açılır (parametre > kayıt > bulunan
  konsol > HDMI 1). Ekran koruyucu ertelemesi (`holdScreenSaver`, tvpower) aynı kaldı: istek gelince hemen
  `ack:false` döner; yeni sürümde kayıt reddedilirse 4 kez başka adla denenir. Mac'in TV'yi uyandırma/açma
  çağrılarını (SSAP) sık yapmaması da önemli: her çağrı bir relaunch'tır (Mac oturumuna not).
- (b) İkinci PSN hesabı bağlanınca görüntü gidiyor: PS5 Remote Play başlayınca HDMI çıkış biçimini (çözünürlük, HDR)
  değiştirebilir; TV'nin giriş akışı yeniden eşlenir ve `<video>` boş kalır. Düzeltme: görüntü gelmişken kaybolursa
  (`emptied`/`ended` olayı ya da 3 sn'lik yoklamada iki kez görüntü yok) giriş 1 sn sonra sessizce yeniden açılır
  (dakikada en çok 3 kez; sonra "görüntü yok" kutusu kendi süresiyle gelir). Panelde "görüntü yeniden alınıyor".
  Kalıcı çözüm için PS5'te HDR'yi kapatmak ("görüntü yok" kutusundaki açıklama) yine geçerli.
- (c) PS girişine geçince siyah ekran / uygulamadan atma: LG'de TV'nin kaynak menüsünden HDMI'ya geçmek uygulamayı
  kapatır. Uygulama içi HDMI zaten varsayılan; LG'de artık ilk açılışta ve uygulama kaynak değişimiyle arka plana
  düşüp dönünce sağ üstte not çıkar: "PS5 görüntüsü Nino'nun içinde… girişi Nino'dan seçin (1–4 ya da panelde ◀▶)".
- Tarayıcıda (sahte TV, `?lg=1`): açılışta HDMI 1 kez açıldı; aynı girişle relaunch → yeniden açılmadı; farklı
  girişle → açıldı; görüntü kaybı → 1 sn sonra yeniden açıldı; LG notu ilk açılışta göründü.

## Tuş simgeleri (kullanıcı şikâyeti, 23 Kasım)

"Hold [yön tuşu] to interact…" çevirisinde tuş kayboluyordu. Gönderici metne `⟦T1⟧` gibi yer tutucu koyar ve
`icons: [{id: "T1", name?, png?}]` yollar (show, screen öğesi, region; alan adı Mac oturumuyla kesinleşecek).
- Bilinen adlar kendi SVG çizimimizle: `cross` `circle` `square` `triangle` (yüz tuşları), `dpad-up/down/left/right`
  (artı biçimli pad, basılan yön beyaz), `L1`–`R3`, `options`, `create`, `touchpad`. Ad yoksa `png` (base64) resim
  olarak, yazı yüksekliğinde (1.1em), dikey ortalı. İkisi de yoksa ya da liste yoksa yer tutucu hiç görünmez.
- `⟦sözcük⟧` vurgusu eskisi gibi; yer tutucu yalnız `⟦T` + sayı`⟧`.
- Üstteki önceki satırlar da artık simge ve vurguyla çizilir (önceden `⟦…⟧` işaretleri düz metin olarak kalabiliyordu).
- Testler: `text.test.js` (parts, wrap), `protocol.test.js` (icons süzme: en çok 8, bozuklar atılır).
- Tarayıcıda: simge 52 px (yazı 46), dikey ortalı; PNG 41 px; Arapçada sağdan sola doğru; uzun satır 2 satır;
  ekran öğesinde ve köşe yazısında da simge.

## Nasıl denenir (sabah)

Bu oturumda LG ya da Samsung TV yok (test TV'si TCL Google TV); o TV'de bu sayfa Android TV uygulamasının içinden
çalışır (Android TV oturumu). Burada üç yol var:

1. **Mac'te tarayıcıda, gerçek Nino ile (en kolay):**
   - Nino açıkken ve çeviri çalışırken uç birimde:
     `python3 -m http.server 8771 -d apps/tv-web/src`
   - Tarayıcıda: `http://localhost:8771/?server=http%3A%2F%2F127.0.0.1%3A8787`
   - Pencereyi tam ekran yapın (1920 genişlikte düzenlenir). PS5'te oyun açın; altyazı, telefon balonları, harita
     kartı ve köşe yazıları eskisi gibi çıkmalı. Esc: geri; klavyede kumanda tuşları yok, panel için sayfaya tıklayın.
2. **Yeni Mac göndericisiyle (NinoCore `NinoSenderIngress`, 47800):**
   `http://localhost:8771/?server=ws%3A%2F%2F127.0.0.1%3A47800%2Fnino%2Fws`
   ya da adres vermeden taramayla: `http://localhost:8771/?ip=127.0.0.1`
3. **Sahte gönderici ile (PS5'siz):**
   - `node apps/tv-web/tools/fake-sender.js 47811`
   - Tarayıcıda `http://localhost:8771/?server=ws%3A%2F%2F127.0.0.1%3A47811%2Fnino%2Fws`
   - Mesaj yollamak: `curl -X POST localhost:47811/send -d '{"type":"show","id":1,"text":"Merhaba"}'`
   - `?hdmi=yok` eklenirse HDMI görüntüsü yok uyarısı görünür.

Testler: `node --test apps/tv-web/test` (79 test; 47800 doluysa tarama testi atlanır).
Paketler: `python3 apps/tv-web/tools/package.py` → `apps/tv-web/dist/com.ninotranslator.tv_4.5.0_all.ipk` ve
`apps/tv-web/dist/nino-samsung_4.5.0.wgt` (imzasız). LG'ye kurmak için geliştirici modu ve webOS kurulum aracı,
Samsung'a kurmak için Tizen sertifikasıyla imza gerekir; ikisi de kullanıcıyla yapılacak.

## Bilinen farklar

- Eski göndericiler (8787) ile çalışır. Yeni protokolle çalışması için göndericinin 47800'de dinlemesi gerekir
  (`baglanti.md` "Göndericiler için yapılacak"). NinoCore'da bu yok.
- LG .ipk ve Samsung .wgt yalnız yapı olarak denetlendi (ar/tar başlıkları eski paketle aynı biçimde); hiçbir
  TV'ye kurulmadı.
- Vurgu rengi (`⟦…⟧`) eskisi gibi yalnız ekran çevirisinde.

## Yapılmayanlar

- TV'ye kurma ve canlı deneme (kullanıcıya sorulacak).
- Masaüstü uygulamaların yeni paket adlarını/yerini kullanması (`dist/tv-app/` yerine `apps/tv-web/dist/`).
- Ölçüm ayrı `GET /v1/config` yapmaz (web TV'de sayfa file:// kökenli, o adres CORS vermiyor); ayar her
  `/v1/events` cevabıyla gelir, ilk gönderim açılıştan 30 sn sonra. `/v1/events` ölçüm dalında CORS'lu; Cloudflare'e
  yayınlanana kadar gönderim başarısız olur ve sessizce bekler (en çok saatte bir dener).
