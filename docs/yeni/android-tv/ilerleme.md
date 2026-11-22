<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Android TV (yeni): ilerleme

Klasör: `apps/android-tv/`. Paket: `com.ninotranslator.tv`. Sürüm 4.5.0, versionCode 45 (kurulu 4.0.3/40'ın
üstüne güncelleme olarak kurulur; kullanıcının kararı).
Tarif: `tarif.md`. Eski `tv-android/` olduğu gibi duruyor.

## Sabah nasıl denenir (TV: iFFALCON/TCL 192.168.0.110)

Hazır paketler (bu dalda, depoya girmez; **hata ayıklama imzalı**, yayın için bkz. "Yayın imzası"): `apps/android-tv/dist/nino-androidtv_4.5.0.apk` (masaüstünün kurduğu,
katmanlı) ve `nino-androidtv-play_4.5.0.apk` (Play çeşidi). 4.5.0 / versionCode 45, minSdk 24, bu Mac'in geliştirme
anahtarıyla imzalı (eski 4.0.3 APK'larıyla aynı anahtar: SHA-256 `43c0151b…5f04efb`).

**Önce bilinmesi gereken:** kurulu Mac Nino'sunun içindeki TV uygulaması eski paket adını taşıyor
(eski TV uygulamasının paket kimliği, LegacyNames'te kodlu). Yeni uygulama `com.ninotranslator.tv`. TV'de hangisinin
kurulu olduğuna bakın: `~/platform-tools/adb shell pm list packages -3` çıktısını bu iki kimlikle karşılaştırın.
- `com.ninotranslator.tv` (4.0.3) kuruluysa 4.5.0 onun üstüne güncelleme olarak kurulur (ayarlar kalır).
- Yalnız eski TV uygulamasının paket kimliği (LegacyNames'te kodlu) varsa yeni uygulama yanına ayrı bir uygulama olarak kurulur.
- Yeni TV uygulaması **iki yolu birlikte** konuşur: yeni göndericiler 47800'deki sunucusuna bağlanır; eski
  göndericiler (sahadaki Mac/iPhone/Android/Windows, 8787) eski uygulamadaki gibi bulunur: masaüstünün açılışta
  verdiği adres (`params`), kayıtlı adres ya da ağ taraması. Öykünücüde kurulu Mac Nino'suna (8787) bağlandı, sahte
  eski gönderici ile altyazı katmanda çizildi, kayıtlı adres ölünce tarama 8787'yi buldu.

Adımlar (kullanıcıyla birlikte; TV'ye kurulum kullanıcının onayıyla):
1. Yedek: `adb shell pm path com.ninotranslator.tv` ve `adb pull <yol> eski-tv.apk` (kuruluysa).
2. Kurulum: `adb install -r apps/android-tv/dist/nino-androidtv_4.5.0.apk`, sonra
   `adb shell appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow`.
3. Kumandadan Nino'yu açın → **ana ekran** ("PS5, HDMI 2 girişinde" ve bağlantı bekleme satırı). İzin verilmemişse **izin ekranı** çıkar; izin gelince kendiliğinden ana ekrana geçer.
4. Bağlantıyı denemek için gönderici gerekmez: Mac'ten
   `curl http://192.168.0.110:47800/nino/info` (TV'nin adı ve kimliği döner) ve
   `curl -X POST --data '{"app":"nino","type":"show","id":1,"text":"Deneme"}' http://192.168.0.110:47800/nino/show`
   → TV'de altyazı çıkar (katmanda, HDMI 2'deyken oyunun üstünde). 20 sn sonra kendiliğinden kalkar.
5. Yeni Mac/telefon uygulamasıyla: göndericide TV seçilir (Bonjour `_nino._tcp`, adı TV'nin adı) ya da IP elle
   yazılır. Çeviri başlayınca sol üstte "çeviri başladı" balonu, sol altta rozet ve altyazı görünür.
6. Göndericide görüntü modu "uygulama içinde" seçilirse katman kapanır, oyun Nino'nun içinde açılır; "katman"
   seçilirse geri döner. HDMI görüntüsü Nino'nun içinde 10 sn gelmezse kendiliğinden katmana geçer.
7. Kumanda (uygulama içinde): 1–4 HDMI, 0 PS5'i yeniden ara, Yeşil/Tamam panel, Kırmızı deneme yazısı, Mavi demo,
   ▲▼ altyazı yüksekliği, Geri çıkış.

Mac'te öykünücüyle deneme (TV'siz): `~/.android/avd/nino_tvtest` (telefon kalıbı, 1920×1080 yatay):
`~/Library/Android/sdk/emulator/emulator -avd nino_tvtest -no-window -port 5590`, sonra
`adb -s emulator-5590 install -r …apk`, `adb -s emulator-5590 forward tcp:47994 tcp:47800`. 22 Kasım gecesi burada
denendi: izin ekranı → izin → ana ekran, katman başka uygulamanın üstünde (başladı balonu, rozet, altyazı),
`displayMode` ile katman ↔ uygulama içi, ortak sayfanın bekleme sahnesi. HDMI (TvView) öykünücüde yok; o kısım
yalnız TV'de denenebilir.

Ortak sayfanın `/v1/config` CORS sorunu tv-web `9aaa52b8`'de giderildi (ayrı istek kalktı); APK bu sürümü içeriyor.

APK özetleri (SHA-256, 22 Kasım son derleme; içindeki ortak sayfa tv-web `d8d58d61`):
`nino-androidtv_4.5.0.apk` `e77fd15b…` (4 izin), `nino-androidtv-play_4.5.0.apk` `…` (yalnız
İnternet izni).

## Ölçüm (olcum.md)

- `Metrics` (Android) + `metrics/Outbox` (saf Java, 10 test): disk kuyruğu ≤2000, parça ≤300, aynı `batch` ile
  yeniden deneme, 200/400/413/429/5xx kuralları, günlük sınır (çökme hariç), aynı hata kodunu birleştirme, sunucu
  ayarı (`telemetry`), gzip.
- TV'de ayar ekranı yok; ölçüm varsayılan açık, sunucu `telemetry.enabled=false` ile kapatabilir.
- Olaylar: `launch`; `crash` (sonraki açılışta; Android 11+'da sistemin çıkış nedeniyle: çökme, `anr`, `oom`; kod =
  istisna sınıf adı, yer = uygulama içi sembol, mesaj yok); `tv_connect` (gönderici el sıkıştı, ms) ve `tv_drop`
  (`network_lost`; göndericinin düzgün kapatması ve değiştirilmesi sayılmaz); `error` kodları:
  `tv.overlay.denied` (izin ekranı, süreç başına bir), `tv.hdmi.dark` (giriş açık, görüntü yok),
  `tv.hdmi.empty` (girişte cihaz yok), `tv.hdmi.noaccess` (TV girişleri uygulamaya açmıyor),
  `tv.page.crashed` / `tv.page.oom` (WebView süreci gitti; sayfa yeniden kuruldu). Eski yol (8787) için de
  `tv_connect` / `tv_drop` (`proto: legacy`) sayfadan ölçülür; uygulama yalnız bilinen alanları alır.
- Kurulum kimliği havuzla aynı: sayfanın `ninoTvId`'si varsa uygulama onu alır, yoksa uygulamanınki sayfaya yazılır.
- Sürüm derlemesi Nino havuzuna gönderir (`/v1/events` henüz canlı değil: 404 alır, saklar, bekler). Hata ayıklama
  derlemesi göndermez; `-PninoMetricsUrl=http://10.0.2.2:<port>` ile sahte havuza denendi (öykünücü): açılış, izin
  yok, bağlanma 9 ms, ağ kopması, sayfa süreci çökmesi, uygulama çökmesi → sonraki açılışta `crash`, ana ekrana
  dönünce tek parça gzip gönderim.

## Durum (22 Kasım 2026)

- [x] Tarif yazıldı.
- [x] Protokol sunucusu (saf Java, kütüphane yok): HTTP + WebSocket 47800, `/nino/info|ws|show|clear`,
      el sıkışma, 5 sn hello, `replaced`, 16 KB sınırı, id'li clear, `durationMs`, 20 sn sessizlik, yalnız ev ağı.
- [x] Ağda görünme: `NsdManager` ile `_nino._tcp` (TXT `v=1`, `id`).
- [x] Açılış kararı (ana ekran / sessiz katman / izin ekranı / uygulama içi), katman servisi, izin yoklama.
- [x] Uygulama içi HDMI: TvView, PS5 girişini bulma, yeniden deneme, 10 sn görüntüsüz → katman ya da giriş
      seçici, TV kendi oynatıcısını öne çekince (5 sn) → katman, kaynak tuşu yedeği.
- [x] Sayfa: altyazı (üst üste üç satır, okuma süresi, 6 sn kopma payı, üstte/altta), ana ekran, izin ekranı,
      bekleme demosu (yeni çizim ve yeni örnek cümleler), Mavi tuş demosu, bilgi paneli, ▲▼ ile yükseklik.
- [x] Dil: Türkçe, İngilizce, Arapça.
- [x] 66 JVM testi ve 13 sayfa testi (`node --test apps/android-tv/web/test`) geçiyor (gerçek soketlerle sunucu testi dahil). `sideload` ve `play` sürüm derlemeleri ve
      lint temiz. Play APK'sında katman izni yok (`aapt dump permissions`).
- [x] Benim yazmadığım istemcilerle denendi: Apple `URLSessionWebSocketTask` (el sıkışma, ping/pong, WebSocket ping
      çerçevesi, 300 baytlık çerçeve, id'li clear, 20 KB → `too_large`) ve `curl` (`/nino/info`, `/nino/show`,
      bozuk gövde → 400).
- [x] Nino uzantı mesajları (LG/Samsung oturumunun `baglanti.md`'si: `style`, `screen`, `region`, `started`…;
      `show`'daki `box`, `paragraphs`, `replace`…) sunucudan sayfaya olduğu gibi iletiliyor ve ortak sayfa bunları
      eskisi gibi çiziyor; son `style` yeni açılan sayfaya da veriliyor.
- [ ] TV'ye kurma ve canlı deneme: kullanıcıya sorulacak.

## Ortak sayfa (22 Kasım, ana oturumun onayı)

- Görünüm LG/Samsung'la ortak: derlemede `apps/tv-web/src` + `platform/common.js` + `web/androidtv.js` (+ `.css`)
  `assets/tv`'ye konur (Gradle görevi `assembleTvPage`). Dallar birleşene kadar ortak kaynağın yeri verilir:
  `-PninoTvWeb=<yeni-tv-web worktree>/apps/tv-web`. Ortak sayfa bulunamazsa derleme açık bir hatayla durur
  (yedek sayfa kaldırıldı).
- `web/androidtv.js`: Android köprüsü (`window.ninoAndroid.receive`), yerel bağlantı (`NINO_PLATFORM.makeLink`;
  tv-web commit ae396f74 ve sonrası gerekir), home/permission/overlay görünümleri,
  kumanda tuşları, TV modeli bildirimi (`/v1/tv`, common.js; günde bir, anonim).
- Altyazı, yığın, stil, ekran çevirisi, köşe yazıları, başladı/durdu, bekleme sahnesi ve panel artık LG/Samsung'la
  aynı kod. HDMI ve giriş seçici Android'de (TvView); sayfa hangi girişin açılacağına karar verir.
- Mesaj sınırı ortak kararla 512 KB (örtü görseli için).
- Tarayıcıda dört modda denendi (sahte köprüyle): bekleme sahnesi, bağlanınca durma, "başladı" balonu, yığın,
  ana ekran, izin ekranı tuşları, katmanda yalnız altyazı ve 5 sn sonra kopukluk noktası.

## Derleme

```
cd apps/android-tv
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=~/Library/Android/sdk gradle --offline \
  -PninoTvWeb=../../../yeni-tv-web-2fe593/apps/tv-web assembleSideloadRelease test   # birleşince -P gerekmez
```

Sayfayı tarayıcıda görmek: `.claude/launch.json` › `androidtv-sayfa`, sonra `index.html?mode=home|permission|inapp|overlay`.

## Bilinen hata ve düzeltmesi (22 Kasım 16:31)

TV'ye kurulan ilk 4.5.0'da sayfanın kendi bağlantı katmanı, ağ taramasında yeni Mac Nino'sunun 47800'deki
dinleyicisini bulup ona da bağlanıyordu; Mac de TV'nin sunucusuna bağlı olduğundan aynı TV iki kez bağlıydı ve Mac
1–2 sn'de bir birini "replaced" ile düşürüyordu. Düzeltme (`web/androidtv.js` `onlyLegacy`): Android TV'de sayfanın
bağlantı katmanı yalnız eski göndericiler (8787) içindir; yeni yol adresleri reddedilir, tarama yalnız 8787'yi yoklar.

İkinci düzeltme (16:35): döngü eski yolda sürdü. Nino arka planda açıkken ana ekran sayfası ve katman sayfası aynı anda
eski yoldan bağlanıyordu (Mac 8787 uyumluluk girişi her 2 sn "replaced"). Kural: eski yolu uygulama genelinde tek
sayfa çalıştırır (`LinkHub` tutucu: katman varsa o, yoksa en son açılan); yeni yoldan gönderici bağlıyken eski yol
tamamen kapanır (bağlantı, tarama, yeniden denemeler); eski yolun durumu öbür sayfalara bildirilir. Eski yol açılmadan önce
6 sn beklenir (açılışta ve yeni yol kopunca): bu sürede yeni gönderici bağlanırsa eski yol hiç açılmaz, gönderici aynı
TV'yi kısa süre bile iki yoldan görmez. Mac'in yeni `duplicate` cevabı (göndericinin 47800 girişi) Android TV'yi
ilgilendirmez: Android TV o girişe bağlanmaz.

## Yayın imzası (kullanıcı yapacak)

`dist/` içindeki APK'lar bu Mac'in **hata ayıklama** anahtarıyla imzalı. Sahadaki TV'lerde (Play ya da GitHub/gh-pages
`tv.apk` ile kurulmuş `com.ninotranslator.tv`) uygulama **sürüm anahtarıyla** imzalı; hata ayıklama imzalı bir APK onların
üstüne kurulmaz (Philips'te "Paket geçersiz", adb'de `INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

Yayın derlemesi (anahtar kullanıcıda; yoksa derleme açık bir hatayla durur, sessizce hata ayıklama anahtarına düşmez):

```
cd apps/android-tv
TV_KEYSTORE_FILE=<nino-tv anahtar dosyası> TV_KEYSTORE_PASSWORD=<parola> [TV_KEY_ALIAS=nino-tv] \
[TV_UPLOAD_KEYSTORE_FILE=… TV_UPLOAD_KEYSTORE_PASSWORD=… TV_UPLOAD_KEY_ALIAS=upload] \
JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=~/Library/Android/sdk \
gradle -PninoPublish assembleSideloadRelease bundlePlayRelease
```

Sonra imzayı önceki yayınla karşılaştır: `apksigner verify --print-certs <yeni apk>` ile gh-pages'teki eski `tv.apk`'nın
sertifika SHA-256'sı aynı olmalı. Mac ve telefon uygulamalarına gömülen TV APK'sı da bu yayın APK'sı olmalı (onlar
yeniden derlenir).

İmza uyuşmazlığında ne olur (22 Kasım'da 4.5 dallarında bakıldı):
- Mac (`AndroidTVInstaller.swift`) ve Windows (`AndroidTvAppInstaller.cs`): TV'de `com.ninotranslator.tv` kuruluysa
  önce kaldırıp sonra kurar (Windows uyuşmazlıkta bir daha dener); uyuşmazlık oluşmaz, izin yeniden verilir.
- Telefon (`AndroidTvInstaller.kt`) ve iPhone (`AndroidTVInstall.swift`): uyuşmazlığı yakalar, kullanıcıya eski kopyayı
  kaldırmasını söyler (Play kopyası / başka kopya ayrımıyla).
- TV'de elle kurulumda ("Paket geçersiz") hatayı Android'in kendi yükleyicisi gösterir; TV uygulaması o anda çalışmadığı
  için bir şey gösteremez. Yönlendirme indirme sayfasında (gh-pages / site) yazılmalı: "Nino yüklenmiyorsa eski Nino'yu
  kaldırıp yeniden kurun."

## Eskisinden farklar (bilerek)

- TV yeni göndericiler için **sunucu** (47800). Eski göndericiler için eski yol (8787 SSE, `params`, kayıt, tarama)
  ortak sayfanın bağlantı katmanıyla aynen sürüyor (geriye uyum).
- Görünüm ayarları, ekran çevirisi, köşe yazıları, örtü, başladı/durdu ve `displayMode` artık protokol uzantılarıyla
  geliyor (`protokol-karari-tv.md`) ve ortak sayfa bunları eskisi gibi çiziyor.
- `displayMode`: göndericilerin varsayılanı "inApp"tir; kayıt yokken gelen "inApp" değişiklik sayılmaz (katman
  kapanmaz). Kullanıcı göndericide "katman"dan "uygulama içinde"ye geçerse izin olsa da oyun Nino'nun içinde gösterilir;
  "katman" seçilirse katmana dönülür. Yalnız gerçek değişiklik görünümü değiştirir.

## Otomatik teşhis (otomatik-teshis.md)

- `metrics/Watchman` (saf Java): iz halka tamponu (10 dk, 200 adım, bildirimde son 40), susturma (açılışın ilk 60 sn,
  arka plan/ön plan ve uyku sonrası 2 dk), sınırlar (kural çalışma başına 1, günde 5, kural başına günde 2), tek kök
  (5 dk içinde yalnız en önemli kural), `telemetry.diag` (off, limits). `diag` günlük olay sınırından muaf.
- TV'de çalışan kurallar: `tv.flapping` (10 dk'da 3 kopma; sebep `write_error` / `closed` / `timeout` / `resume`
  (öne gelişten sonraki 10 sn; bağlantı katmanı sebebi biliyorsa o geçerli) / `replaced` (başka gönderici aldı), karışıksa `mixed`; yeni ve eski yolun kopmaları
  birlikte; arka plan susturmaz, yalnız açılışın ilk 60 sn'si, uyku/uyanma ve kullanıcının durdurması), `app.hang` (ana iş parçacığı 5 sn yanıtsız; saniyede bir
  izlenir), `app.resources` (PSS > 400 MB 2 dk ya da sistemin bellek uyarısı). İşlemci ölçümü yok.
- Askıda biten çalışma yalnız `crash` (`code: anr`) olarak gider, ayrıca `app.hang` gönderilmez (ölçüm kararı).
- `diag-scenarios.json` (ortak) birim testi olarak çalışıyor: TV kuralları beklenenle aynı, öbür kurallarda hiçbir şey
  gönderilmiyor. Öykünücüde üç ağ kopması → `tv.flapping` / `closed` bildirimi kuyruğa düştü.
- Ortak sayfanın kendi ölçümü ve bekçisi (js/telemetry.js, js/diag.js) Android TV'de kapalıdır (platformda
  `telemetryName` yok); çift bildirim olmaz, ölçümü ve teşhisi uygulama (Java) yapar.

## Temiz oda (22 Kasım, veri-dosyalari-karari.md)

- Tarifin alıntılı ilk hâli depo dışında: `~/NinoYedek/tarif-arsiv/android-tv/`. Depodaki `tarif.md` ekran yazılarını
  alıntılamaz; yeni metin anahtarlarıyla anar.
- Eski ağaçtan gelen veri dosyası: yalnız uygulama simgesi ve TV afişi (`res/mipmap-nodpi/icon.png`,
  `res/drawable-nodpi/banner.png`); kararla kullanıcının görselleri, kalıyor. Sözlük, test vektörü, paket yok.
- `scripts/temiz-oda-tarama.py` (Mac dalı) Android TV klasörlerine (Java/JS/XML/CSS/MD) uyarlanarak çalıştırıldı:
  yalnız `genel` sınıfında 33 eşleşme (paket kimliği, "incoming", "bekleme süresi"); veri/sözlük/metin eşleşmesi yok.

## Eskiyle aynı kalanlar (bilerek)

Kod satır satır yeniden yazıldı; eskiden kopya yok. Ama "aynı görünsün" isteği için şunlar **eskisiyle aynı**:
- Renk, ölçü ve süreler (ana ekran ışıkları, kart, düğmeler; altyazı ve sahne artık ortak sayfanın). Bunlar
  `tarif.md`'de yazılı.
- Ekrandaki yazılar aynı anlamda ama yeniden yazıldı (Türkçe, İngilizce, Arapça). Yalnız Android'in kendi ayar adları
  ("Diğer uygulamaların üzerinde göster", "Her zaman izin ver") aynen geçer, çünkü kullanıcı TV'de onları arar.
- Marka görselleri (TV simgesi ve afişi) eskisinden alındı; bunlar kod değil.
- Android'in standart çağrıları (TvView, pencere bayrakları, bildirim) doğal olarak benzer.
Kullanıcı isterse renk/yazılar da değiştirilebilir.

## LG/Samsung ile birleşme (karar verildi)

Ana oturumun kararıyla Android TV, LG/Samsung'un ortak sayfasını (`apps/tv-web/src`) kullanıyor; yalnız bağlantının
yönü farklı (Android TV dinler, web TV'ler göndericiye bağlanır). Ortak sayfa `platform.makeLink` ve
`window.nino.receive` girişlerini Android TV için ekledi; Android'in kendi mesajları `window.ninoAndroid`'den gelir.

## Kullanıcıya sorulacaklar

Ana oturum: TV'ye kurmayı uygulama hazır olunca kullanıcıya kendisi soracak; o zamana kadar kurulmaz.

1. TV'ye kurma: aynı paket kimliği, yani çalışan 4.0.3'ün **yerine geçer**. Kurulunca şimdiki masaüstü Nino
   (8787) TV'ye altyazı gönderemez. Yeni APK eskisinin üstüne ancak aynı imza anahtarıyla kurulur; yerelde anahtar
   yoksa geliştirme anahtarıyla imzalanır ve önce eskisini kaldırmak gerekir. Öncesinde eski APK
   `adb pull` ile yedeklenebilir.
2. Kurulumdan sonra `adb shell appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow`.
3. Canlı deneme için yeni protokolü konuşan bir gönderici gerekiyor (yeni Mac/telefon uygulaması). Yoksa
   `POST /nino/show` ile elle denenebilir.
