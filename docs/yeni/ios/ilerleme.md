# iOS yeniden yazımı: ilerleme

Yeni uygulama `apps/ios/` altında. Eski `nino-ios/` olduğu gibi duruyor (karşılaştırma için).

Proje: `cd apps/ios && ./scripts/generate.sh` (NinoCore yolu `NINO_CORE`, verilmezse `~/Desktop/NinoCore`).
Testler: `xcodebuild -project Nino.xcodeproj -scheme Nino -destination '<simülatör>' test` → 50 test, hepsi geçiyor.
Cihaz derlemesi (`generic/platform=iOS`, Debug ve Release, imzasız) başarılı.
Metinler: `Nino/Resources/Localizable.xcstrings` (356 anahtar, 12 dil) bu sürüm için baştan yazıldı; eski kataloglardan
alınmadı. `scripts/check-strings.py` koddaki her anahtarın 12 dilde ve doğru yer tutucularla bulunduğunu denetler.

## Sabah nasıl denenir (iPhone + PS5 + TV)

1. **Derle:** `cd apps/ios && ./scripts/generate.sh && open Nino.xcodeproj` (NinoCore `~/Desktop/NinoCore`'da olmalı).
   Xcode'da Nino hedefi › Signing & Capabilities › Team: kendi geliştirici hesabınız. iPhone'u kabloyla bağlayıp ▶︎.
   (Paket kimliği `com.ninotranslator.ios`: App Store'daki Nino'nun üstüne kurulur; eski ayarlar korunur. Anahtar
   Zinciri kayıtları ancak aynı takımla imzalıysa okunur; okunmazsa PSN girişi ve PS5 eşlemesi yeniden yapılır.)
2. **Mac'teki Nino'yu kapatın.** O da 8787'de dinliyor; TV yanlış cihaza bağlanabilir.
3. **Kurulum:** Konsol: PlayStation 5 → Sony ile giriş (ikinci hesap) → PS5'te Ayarlar › Sistem › Uzaktan Oynatma ›
   Cihazı Eşleştir, 8 haneli kodu girin → Altyazı nerede: "Bu telefonda" ya da listedeki TV.
4. **TV:** TV'deki mevcut (eski) Nino TV uygulaması telefonu ağda 8787'de kendisi bulur; ayrıca bir şey yapmayın.
   Yeni TV uygulamaları da çalışır (web TV'ler telefona 47800'den bağlanır, yeni Android TV'ye telefon bağlanır).
   Ayarlar › "Deneme altyazısı gönder" ile TV'de satır çıkıp çıkmadığına bakın (çeviri kapalıyken de çalışır).
5. **Çeviri:** Ana ekranda fişi prize takın. Durum "Bağlanıyor" → "TV'de canlı" olmalı; oyunda altyazılı bir sahne açın.
   Telefon ekranında görmek için Çıkış karosundan "Telefon" seçin ya da telefonu yan çevirin.
6. **Bakılacaklar:** PS5 uykudaysa uyanıyor mu; uygulamayı arka plana atıp dönünce yeniden bağlanıyor mu; fişi çekince
   TV'deki altyazı kalkıyor mu; Geçmiş'e satırlar düşüyor mu; GTA V / RDR2 gibi paketli oyunda satırlar "Paket" diye mi
   işaretleniyor.
7. **Xbox (Beta):** Konsol seçiminde Xbox → "Microsoft ile Giriş Yap": kod panoya kopyalanır ve microsoft.com/link
   açılır; kodu yapıştırıp Xbox'taki hesapla giriş yapın, Nino'ya dönün (giriş kendiliğinden biter). Xbox'ta Ayarlar ›
   Cihazlar ve bağlantılar › Uzak özellikler açık olmalı; listede yeşil tikli Xbox'u seçin → altyazının yeri. Ana ekranda
   fişi takınca durum "Bağlanıyor…" → "Bağlı" olmalı (ilk bağlantı 10–30 sn sürebilir; Xbox açık olmalı). Bakılacaklar:
   telefonda görüntü önizlemesi geliyor mu, altyazı okunuyor mu, "Xbox sesi bu cihazda" açıkken ses telefondan geliyor
   mu, 1–2 dakika sonra yayın kopuyor mu (kare onayı çalışmıyorsa ~40 sn'de kopar). Günlük: Xcode konsolunda "xbox"
   kategorisi (jeton/kod yazılmaz). Mikrofon izni sorulursa reddedilebilir.
8. **TV uygulamasını telefondan kurma** (Ayarlar › "TV uygulamasını bu telefonla yükle"):
   - **Android TV (TCL, 192.168.0.110):** TV'de Geliştirici seçenekleri › USB hata ayıklama açık (ADB 5555 zaten açık).
     "Android TV" sekmesi → listede TV'yi seçin (ya da adresi yazın) → "Yükle ve aç". İlk seferde TV'de "USB hata
     ayıklamaya izin verilsin mi?" çıkar: "her zaman izin ver" + İzin ver. Nino APK'yı akıtıp kurar, katman iznini
     (`appops … SYSTEM_ALERT_WINDOW allow`) verir ve açar; sonra TV altyazı hedefi olarak eşlenir. Kablosuz hata ayıklama
     yolunu da deneyin: "Kablosuz hata ayıklama" seçili, TV'deki "Cihazı eşleme kodu ile eşle" penceresinin adres:port'u
     ve 6 haneli kod + TV'nin kendi adres:port'u.
     **Dikkat:** GitHub'daki son sürümün `Nino-TV.apk` dosyası şu an Nino'nun paket kimliğini (`com.ninotranslator.tv`)
     taşımıyor (aapt ile bakıldı); uygulama bu paketi reddeder. TV'de Nino zaten kuruluysa yine izin verilip açılır ve
     TV eşlenir; kurulu değilse "TV paketi yok" der. Kalıcı çözüm: sürüme doğru kimlikli `Nino-TV.apk` yükleyin, ya da
     doğru APK'yı `dist/tv-app/nino-androidtv_<sürüm>.apk` olarak koyun (ya da `NINO_TV_APK=<yol>`); derleme adımı
     (`scripts/tv-packages.py`) kimliğini denetleyip uygulamaya gömer.
   - **Samsung / LG:** paketler (`nino-samsung.wgt`, `nino-lg.ipk`) derlemede kaynaktan üretilip uygulamaya girer.
     Samsung'da ilk kurulum Samsung hesabıyla giriş ister (uygulama içi sayfa); LG'de TV'deki Passphrase yazılır.
   - Sorun olursa ekrandaki "Kurulum günlüğünü paylaş" (`tv/tvinstall.log`).
9. **Sorun olursa:** Ayarlar › Cihaz bilgileri › kopyala; Xcode konsolundaki günlük. PS5 bağlantı hata metinleri ana
   ekranda ve tam ekranın ortasında yazar.

Simülatörde denemek: `xcrun simctl launch <cihaz> com.ninotranslator.ios` ortam değişkenleriyle
`SIMCTL_CHILD_NINO_SCREENSHOT=welcome|home|tour` (kurulum bitmiş gibi, ağa ve Anahtar Zinciri'ne dokunmaz),
`SIMCTL_CHILD_NINO_SCREENSHOT_LANG=ar` (dil), `SIMCTL_CHILD_NINO_SCREENSHOT_ROUTE=tvinstall` (TV kurulumu ekranı; ağ
taranmaz).

## Tarifler (eski koddan, kod kopyalanmadan)
- `tasarim.md` tasarım sistemi · `kurulum.md` ilk açılış ve kurulum · `ana-ekran.md` ana ekran ve çeviri
- `ayarlar.md` alt sayfalar · `kalicilik.md` veri sözleşmesi · `davranis.md` model davranışı
- `ekranlar/yeni/` yeni uygulamanın simülatör görüntüleri. Karşılaştırma için alınan eski uygulama görüntüleri depo dışında (~/NinoYedek/tarif-arsiv/ios/ekranlar-eski).
  `docs/screenshots/telefon` eski, koyu bir taslağa ait; karşılaştırmada kullanılmadı.

## Durum
| Parça | Durum |
|---|---|
| İskelet; NinoCore + NinoRemotePlay ile simülatör ve cihaz (arm64) derlemesi | bitti |
| Tasarım katmanı (jetonlar, iskelet, düğme, karo, sahne, robot, yazı tipleri, açılış animasyonu) | bitti |
| Kalıcılık: Anahtar Zinciri (aynı hizmet ve hesap adları, eski hizmetten taşıma), ayarlar (zorunlu/hoşgörülü alan kuralları, bilinmeyen alanlar korunur), geçmiş, klasör taşıma | bitti, testli |
| Karşılama, konsol seçimi, PSN girişi (Sony sayfası + hesap kimliği), PS5 eşleme (8 hane), altyazının yeri, kullanım turu | bitti |
| Ana ekran: salon sahnesi (fiş/priz, kablo, ışıklar, sayaç, açılış animasyonu), durumlar, kısa yollar, demo, tam ekran altyazı, yan çevirme | bitti |
| Ayarlar, Profil, Paketler, Geçmiş, Hakkında, Nino'ya Sor, Sorun Bildir | bitti (eksikler aşağıda) |
| Çeviri akışı: Remote Play → Vision okuma → çeviri (paket, cihaz içi, kullanıcının anahtarıyla DeepL/Gemini/OpenAI/yerel model) → TV (Nino Bağlantı Protokolü) ve telefon | bitti; uçtan uca testli (kare → okuma → çeviri → NinoDisplayServer) |
| Telefondan TV kurulumu (Android TV, Samsung, LG): adb/sdb, SPAKE2 eşleme, TLS 1.3, Samsung imzası, SSH; paketler indirme → önbellek → gömülü | bitti; sahte sunucularla testli, gerçek TV'de denenmedi |
| Oturum bekçisi: kopunca 2/4/8/16/30 sn ile yeniden bağlanma, 8 sn görüntü yoksa yenileme, uyuyan PS5'i uyandırma, kalıcı hatada durma | bitti; yönlendirilemeyen adresle testli |

## Ekran karşılaştırması (eski 4.0.5 ↔ yeni, aynı simülatörler)
Birebir (piksel düzeyinde) aynı: karşılama (iPhone, iPad), altyazının yeri (iPhone, iPad), ana ekran (iPhone, iPad),
demo ana ekranı, Profil (ilk sayfa). Ayarlar aynı; tek fark GTA 6 karosunun yokluğu (aşağıda). Arapça (sağdan sola)
yeni uygulamada denendi (eskiyle yan yana konmadı).
Yan yana karşılaştırılmayanlar: konsol seçimi ve PSN ekranı (kök yönlendirme yeniden yazıldıktan sonra), PS5 eşleme,
kullanım turu adımları, PSN ekranından açılan PS5'siz önizleme, tam ekran altyazı, Ayarlar 2–4. sayfalar, Profil 2–3.
sayfalar, Nino'ya Sor, Sorun Bildir, Paketler, Geçmiş.

## Yapılmayanlar (bu sürümde yok)
- **Telefondan TV'ye kurulum:** yazıldı (Android TV: adb + kablosuz eşleme; Samsung: sdb + Samsung sertifikası + .wgt
  imzası; LG: Key Server + SSH + süre uzatma). Birim testleri yerel sahte sunucularla geçiyor; gerçek TV'de denenmedi.
  Elle doğrulananlar: SSH istemcisi Mac'teki OpenSSH 10.3'e (modern ve eski algoritmalarla: group14/group1-sha1, ssh-rsa,
  aes-ctr, hmac-sha1; 1,3 MB girdi) bağlandı; eşleme şifresi gerçek `adb pair` istemcisiyle uyumlu çıktı. Eksik: ana
  ekrandaki "TV uygulamasının yeni sürümü var" kartı (§7.6; sürüm denetimi yok, `tvUpdate` yolu ekranı açıyor).
- **Ortak havuz ve GTA 6 ortak çevirisi**, Ayarlar'daki **GTA 6 karosu**, oyun sorusu, havuza satır gönderme.
- **Ekranı çevir**, **Ek alanlar** karosu. (Köşe/ipucu, mesaj/arama kartı, telefon paneli ve harita kartı 22 Kasım'da eklendi.)
- **Paket içe aktarma** (sunucudan paket indirme var).
- **Toplam indirme sayısı** sunucudan alınmıyor; yalnız önceki sürümün sakladığı son değer gösteriliyor.
- **Dil paketi indirme karosu** (iOS 26 dil paketi), Sorun Bildir'de fotoğraf ve günlük ekleme, otomatik sorun bildirimi,
  sağlık kaydı. Nino'ya Sor'da fotoğraf ekleme.
- **PS5 giriş şifresi** kaydediliyor ama PS5'e gönderilmiyor (NinoRemotePlay'de arayüzü yok).
- Kaydedilen ama henüz uygulanmayan ayarlar: konuşan adı, değişmeyen alanı sık okuma, ortak havuz.
- Claude motoru: seçilebiliyor, çeviri yapmıyor (cihaz içi çeviriye düşer).

## Xbox (Beta) — 22 Kasım
- `Services/Xbox/`: Microsoft cihaz kodu girişi, jeton yenileme (Anahtar Zinciri `xboxUserToken`, eski kayıt aynen
  okunur; boş `refresh_token` = girişsiz), Xbox Live/XSTS, hesaptaki Xbox listesi, ev yayını sinyalleşmesi (play, state,
  connect, SDP, ICE + Teredo kısayolu, canlı tutma, kapatma), WebRTC (stasel/WebRTC 150.0.0, BSD-3) ile görüntü; kareler
  NinoCore `FrameSource` olarak okuma hattına girer. Veri kanallarında el sıkışma ve kare onayları; kumanda girdisi yok.
- Oturum kuralları (`XboxSessionPlan`): kopmada 5/15/45 sn sonra yeniden, üçten sonra durur; konsol reddi (`Failed`,
  dolu `errorDetails`) ve giriş/profil sorunları hiç denenmez; 60 sn canlı kalan yayın sayacı sıfırlar. Öne gelince
  hemen yeniden bağlanır. Durum metinleri ana ekranda (Xbox'ta "diğer" nedenin metni gösterilir).
- Ekranlar `Screens/Setup/XboxScreens.swift`'te (giriş kodu karosu, Xbox listesi). `ekranlar/yeni/ipad-xbox-giris.png`.
- Testler (`XboxTests`, 24): eski kayıtlar, ayrıştırma, yenileme, cihaz kodu, XErr, oturum kuralları, sahte uçlar +
  sahte WebRTC ile oturum ve model. **Gerçek Microsoft hesabı ve Xbox ile hiç denenmedi**; WebRTC bağlantısı yalnız
  derleniyor (simülatör + cihaz).
- Info.plist: mikrofon ve kamera açıklamaları (WebRTC kitaplığı yüzünden; Nino ikisini de açmaz).

## Bilinen sorunlar
- **NinoRemotePlay kilitlenmesi:** PS5 oturumu kapanınca kütüphanenin oturum iş parçacığı kendi kilidinde takılıyor
  (`RemotePlaySession.handle(.quit)` → `finish()` → `onTermination` → `stop()`). Uygulama kapanma olayına bakarak devam
  ediyor ve takılan oturuma dokunmuyor; ama her kopma ve durdurmada bir iş parçacığı boşa takılı kalıyor. Düzeltmesi
  NinoRemotePlay'de (ana oturuma ve ortak notlara yazıldı).
- Paket araması açık bütün paketlerde yapılıyor, ilk bulan kazanıyor; oyuna göre paket seçilmiyor (kısa bir satır başka
  oyunun çevirisini alabilir).
- "Eşleme geçersiz" ve "Uzaktan Oynama kapalı" kütüphanenin kapanma nedenlerinden ayrılamıyor; kalıcı hata sayılmayıp
  yeniden deneniyor.
- TV seçilirken yanıt vermeyen TV de kaydediliyor; ekranda TV'nin bağlı olmadığını gösteren bir şey yok
  (`tvConnected` henüz arayüzde kullanılmıyor).
- Protokol uzantılarından `box`, `replace`, ekran örtüleri (`screen`, `region`) henüz gönderilmiyor.

## Doğrulanmayanlar
- PSN girişi ve PS5 eşleme gerçek Sony hizmetleri ve PS5 ile hiç denenmedi.
- **Gerçek PS5 ve TV ile canlı deneme yapılmadı** (kullanıcı oyundayken dokunulmadı). TV'ye gönderim yalnız
  çekirdekteki gösterici sunucusuyla, PS5 yalnız yönlendirilemeyen adresle denendi.
- **Anahtar Zinciri devri** (PSN hesabı, PS5 kaydı) simülatörde doğrulanamadı: eski yapı farklı imzayla kurulu olduğu için
  yeni yapı onun Anahtar Zinciri kayıtlarını okuyamıyor. UserDefaults (ayarlar, karşılama, Şimdilik Geç, sayaç) eski
  uygulamanın üstüne kurulunca okundu. Gerçek devir aynı geliştirici takımıyla imzalanmış cihaz yapısında denenmeli.
- Yeni TV uygulamaları (Nino Bağlantı Protokolü) henüz yayında değil; eski TV uygulamaları bu sürümle konuşmaz.

## Bağımlılık notları
- Oyun paketleri uygulamaya gömülmez (veri dosyaları kararı): açılışta ve 24 saatte bir Nino sunucusundan (`/v1/packs`)
  `Application Support/Nino/Packs/files` altına iner; Paketler ekranında "şimdi yenile" düğmesi var. Sunucu canlı
  değilken ve ilk açılışta internet yokken paket yoktur.
- Testler NinoCore'un `a99c71f` commit'inin kopyasıyla geçti (çalışma ağacı Mac oturumunun yarım değişiklikleri yüzünden
  o an derlenmiyordu).
- NinoRemotePlay'de `ConsoleInfo`/`RegisteredConsole` için public init yok; JSON'dan kuruluyor. Elle yazılan PS5 adresi
  için eşleme, önce ağda o adresteki PS5'in bulunmasını gerektiriyor.
- Paket araması cümle cümle yapılıyor (paketlerdeki `segments` anahtarları); iki cümlelik satırın tam satır anahtarı
  ancak NinoCore satır düzeyinde aramaya geçince kullanılır.

## Ana oturumun cevapladığı kararlar
iOS 17+ evet · Xbox ve telefondan TV kurulumu yapılacak (indirme izni var) · eski metinler kullanılmaz, yeniden yazılır
(yapıldı) · fontlar ve renk/ölçü değerleri aynı kalabilir.

## 22 Kasım gece eklenenler
- NinoCore 4e68010'a geçildi (Remote Play kilitlenmesi orada düzeldi; yeni eşleme hataları, giriş şifresi PS5'e gönderiliyor).
- TV yolu `DisplayHub` ile: eski TV uygulamaları 8787'den (SSE), web TV'ler 47800 girişinden, yeni Android TV doğrudan;
  görünüm (`style`) ve başladı/durdu olayları gidiyor, altyazı telefondayken TV'ler temizleniyor. 8787 yolu testli.
- Paketler NinoCore `LegacyLibrary`/`PackScope` ile (oyun kapsamı, bulanık arama); açılışta arka planda yüklenir.
- Ölçüm istemcisi (NinoCore `Telemetry`): açılış, arka plan, PS5 bağlantı/kopma, oturum. Kapatma düğmesi yok (karar).
  Gizlilik bildirimine anonim teşhis verisi türleri eklendi.
- Metinler 12 dilde yeniden yazıldı; `tokens.json` uygulamadan kaldırıldı (kod okumuyordu).
- Ekranlar yeni metinlerle yeniden çekildi (`ekranlar/yeni/iphone-*.png`, `ipad-*.png`): yerleşim eskisiyle aynı,
  cümleler farklı (karar gereği).


## Xbox ve telefondan TV kurulumu (22 Kasım gece, birleştirildi)
- Xbox: Microsoft cihaz kodu girişi, jeton yenileme, Xbox listesi, ev yayını (stasel/WebRTC 150.0.0, BSD-3); kareler
  okuma/çeviri hattına giriyor. Eski Xbox kayıtları okunuyor. Gerçek hesap ve Xbox ile denenmedi.
- TV kurulumu (`Services/TVInstall/`): Android TV (adb, kablosuz eşleme SPAKE2 + TLS), Samsung (sdb, sertifika, .wgt imzası),
  LG (Key Server, SSH, süre uzatma). Sahte adbd/sdbd/LG kabuğuyla testli; gerçek TV'ye dokunulmadı.
- Dikkat: `scripts/tv-packages.py` Samsung/LG paketlerini şimdilik eski `tv-webos`/`tv-tizen` klasörlerinden üretiyor; yeni
  web TV uygulaması (`apps/tv-web`) birleşince ona çevrilmeli. GitHub'daki son sürümün Android TV APK'sı eski paket
  kimliğiyle olduğu için uygulama onu reddediyor; doğru APK sürüme yüklenmeli (ya da `dist/tv-app/` altına konmalı).
- 86 test geçiyor (biri yalnız elle çalışır), 448 metin anahtarı 12 dilde, sıfır sorun.
- Ekranlar yeniden çekildi (`ekranlar/yeni/iphone-*`, `ipad-*`, `*-xbox.png`): yerleşim eskisiyle aynı, cümleler yeni.

## Kararlar
- iOS en az 17 (NinoCore öyle istiyor; eski uygulama 16'ydı). Sürüm 4.5.0 (29); App Store Connect’teki son iOS yapısı 28 (21 Kasım).
- Arayüz metinleri `L("anahtar")` ile seçili arayüz dilinin paketinden okunur; dil değişince hepsi anında değişir.
- TV bağlantısı yeni protokolle: telefon TV'yi Bonjour (`_nino._tcp`) ile bulur ve ona bağlanır. Eski kayıtlı TV'nin
  adresi kullanılır; adres kayıtlı değilse (Android TV) TV ağda aranır.
- Hakkında'daki türetme satırı koda yazılmadı; uygulamaya konan `NOTICE` dosyasından okunur.

## Metin örtüşme taraması (22 Kasım)
`python3 apps/ios/scripts/check-overlap.py mac/Nino/Resources/Localizable.xcstrings nino-ios/Nino/Resources/Home.xcstrings`
eski kataloglarla birebir (≥12 karakter) ve 4-gram (dört kelime) örtüşmeyi arar. İlk taramada 359 anahtarda 2594 dil girdisi
çıktı; hepsi 12 dilde yeniden yazıldı. Kalan 23 girdi (14 anahtar) yalnız cihazdaki gerçek menü/seçenek adları, değişirse
kullanıcı ekranda bulamaz:
- PS5: Settings › System › Remote Play › Pair Device; Settings › Network › Connection Status (ms, fil)
- iPhone: Privacy & Security › Local Network (fil)
- Xbox: Settings › Devices & connections › Remote features (ms)
- Android TV: “Pair device with pairing code” (en, tr, nl, fil); Apps › See all apps › Nino TV › Uninstall; Android TV OS build (fil)
- Samsung: Device Care › Self Diagnosis; General › System Manager › Time (fil)
- nl `settings.title` = "Instellingen" (tek kelimelik standart karşılık)
Dar ekranda (iPhone 17 Pro) uzayan düğmeler denetlendi; nl/hi/ur/id/ms "PS5'siz dene" ve nl "neden iki hesap" kısaltıldı.
Bilinen: giriş yapılmış PSN ekranında robot alt satırı daraltıyor, tr'de iki kısa bağlantı kesiliyor (önceden de vardı).

## Otomatik teşhis bekçisi (22 Kasım)
Tarif: NinoCore docs/tarif/otomatik-teshis.md. Derleme için NinoCore ≥ 9635864 gerekir (TelemetryEvent.diag; şu an 6db409d
anlık kopyasıyla derlendi).
- `Nino/Services/Diagnosis/DiagWatch.swift`: saatten bağımsız bekçi. Kurallar: ps5.no_return, tv.flapping, ocr.silent,
  ocr.stalled, tr.slow, tr.errors, app.hang, app.resources, pack.download. Susturma (uyku/arka plan/durdurma 2 dk, açılışın
  ilk 60 sn yalnız bildirimi engeller), ağ yokken ağ dışı kurallar susar, 5 dk içinde tek kök, oturumda kural başına 1,
  günde 5 / kural başına 2. Saatte 5 sn'den büyük boşluk uyanma sayılır (iOS askıya alma). İz: son 10 dk/200 adım, art
  arda gelen ocr.text/tr.ok/ps5.frame tek adımda toplanır.
- `AppDiagnosis.swift`: ağ (NWPathMonitor), bellek/ısı (30 sn), ana iş parçacığı donması (ayrı iş parçacığı), kare
  hızı ve 8×8 parlaklık izi, yazı tanıma ve çeviri hizmeti süreleri (sargılar), paket indirme sonuçları (sayaç kalıcı).
  Sunucu ayarı (`telemetry.diag`: off, limits) 2 dakikada bir okunur. Kapatma düğmesi yok, serbest metin yok.
- Testler: `DiagWatchTests` ortak `diag-scenarios.json`'ın 9 senaryosunu birebir oynatır (+ sınırlar, uzaktan ayar,
  öncelik, askıya alma, iz birleştirme).
- Yapılmayanlar: bir sonraki açılışta bildirilen app.hang (eski "çalışıyorum" damgası), cpu_high, paketin 24 saattir
  inmemesi koşulu, "Sistem sağlığı" ekranı. TV kopma sebebi iOS'ta hep `closed` (DisplayHub sebep vermiyor). Eşik
  anahtarları tarifteki adlarla (`ps5NoReturnSec`, `trSlowP90Ms`…) ve noktalı biçimle (`tr.slow.p90Ms`) okunur;
  sunucunun gerçek anahtar adları doğrulanmadı.

## Oyun okuma hattı ve ekran öğeleri (22 Kasım)
- Okuma NinoCore `GameReading.Reader` ile (eski `ReadingPipeline`/`NinoEngine` yolu kalktı): `Services/Reading/ReadingSession.swift`
  (çeviri sırası, konuşan etiketi ayrı, buzlu zemin, paket önce), `ScreenLayer.swift` (köşe turu, tuş ipuçları, mesaj ve
  arama kartı, telefon paneli, harita kartı → `ElementsBoard`), `ElementTranslation.swift` (paket → oturum çevirmeni;
  iOS'ta havuza soru/bildirim yok). Yazı tanıma: Vision + takılma bekçisi (`GuardedTextReader`, işlemci yedeği).
- TV kapısı NinoCore `ScreenItemSender` (d143e44): liste değişince `screen`, boşalınca `screen-clear`, değişmeyen liste
  60 sn'de bir yeniden; harita kartı 3 ardışık kaçırma + ≥4 sn + kart bölgesi görüntüsel değişmeden kalkmaz; menü kapanınca
  ya da telefon oyunu bitince hemen kalkar.
- Telefon oyunu kararı (GTA 6): ekrandan tanınan oyun kesin, paket isabeti tahmin, yoksa son oyun (`ninoLastGamePoolFirst`)
  ya da Türkçe hedef. Ekrandan tanınınca karar hemen okuyucuya ve katmana uygulanır.
- Testler (`ScreenLayerTests`, Fixtures/gta6): gerçek telefon karesi → telefon paneli TV'ye; gerçek harita karesi +
  karedeki yazılar → oyun ekrandan tanınır, harita kartı TV'ye, durunca `screen-clear`. Gerçek Vision ile harita testi de
  geçiyor (NinoCore d143e44 tuş simgeli satırları, ör. "RECENTER L3", tanıyor).
- Derleme NinoCore d143e44 kopyasıyla.

## Hata listesinden (22 Kasım akşam)
- **TV uygulaması sürüm denetimi:** TV uygulaması 8787'ye ya da 47800'e bağlanırken bildirdiği sürüm (`?app=` / hello)
  ve kurulumda okunan sürüm, telefonun kurabileceği paketin sürümüyle (önbellek ya da uygulamadaki paket) karşılaştırılır.
  Eskiyse ana ekranda "TV'deki Nino eski kaldı · TV'de: x → yenisi: y" kartı; düğme TV kurulum sayfasını güncelleme
  kipinde açar (eşli TV'nin adresiyle kendiliğinden başlar). Görünen sürüm `tvAppInstalled`'a yazılır.
  Ekran: ekranlar/yeni/tv-guncelleme-karti.png (`NINO_SCREENSHOT_TVUPDATE=1`).
- **Dil paketi kartı (iOS 26+):** Apple çevirisinin paketi yoksa ana ekranda kart; "İndir" `translationTask` +
  `prepareTranslation()` ile sistemin indirme penceresini açar, bitince durum yeniden okunur (kart kaybolur).
  Simülatörde paket yüklü olduğu için kart görülmedi; gerçek cihazda dil değiştirerek denenmeli.
- **Xbox:** Profil'de "Xbox görüntüsü 720p" anahtarı (`xboxLowResolution`, Xbox'a 1280×720 ister). Yayın başlatma
  hatası (`StartStreamingSession`) ayrı sorun: Xbox'ı tamamen yeniden başlatma ve uzaktan oynatmayı kapatıp açma önerisi.
- **Oyun kimliği (gta-6 / gta-v):** NinoCore'daki ortak takma ad tablosu bekleniyor; gelince bağlanacak.
