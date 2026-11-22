# Yeni Mac uygulaması: ilerleme

Kesilirse buradan devam edilir. Yeni kod `apps/mac/` altında; eski `mac/` dokunulmadan duruyor.

## Yapı

- `apps/mac/NinoMacKit/` — Swift paketi: bütün mantık ve ekranlar. `swift test` ile uygulama açılmadan sınanır.
  NinoCore ve NinoRemotePlay `~/Desktop/NinoCore`'dan (yer `NINOCORE_DIR` ile değişir).
- `apps/mac/App/` — yalnız uygulamayı açan ince hedef. `xcodegen generate` ile proje üretilir.
- Debug: `com.ninotranslator.mac.dev`, klasör "Nino Dev", Anahtarlık hizmeti `.dev`. Kurulu Nino'ya dokunmaz.
- Release: `com.ninotranslator.mac`, klasör "Nino" (kullanıcının gerçek verisi).
- Yedek: `~/NinoYedek/mac-*` (UserDefaults + veri klasörü, 22 Kasım 2026).

## Yöntem (temiz oda)

1. Tarif yazarları eski kodu okuyup `docs/yeni/mac/*.md` yazar (davranış, ölçü, metin; kod yok).
2. Kod yalnız tariflerden, görsellerden ve NinoCore'dan yazılır.

## Durum

| # | Parça | Durum |
|---|---|---|
| 0 | Yedek, iskelet, Xcode projesi | bitti |
| 1 | Tarifler (16 belge, docs/yeni/mac/) + mimari.md | bitti |
| 2 | Ayar modeli (eski kayıt kayıpsız), AppState sözleşmesi, sahte motor | bitti |
| 3 | Storage (Anahtarlık eski biçim, veri klasörü, günlük), Console (PSN, eşleştirme, Remote Play oturumu) | bitti |
| 4 | NinoCore: Library (eski paket/havuz), Providers (çevirmenler), GameReading (zengin okuma), Phone (telefon/harita), Link uzantıları (47800 girişi, eski 8787) | bitti |
| 5 | NinoRemotePlay: kilitlenme, giriş şifresi, eşleştirme hataları, universal (Intel) | bitti |
| 6 | Ekranlar: tasarım dili, ana ekran, ayarlar, kurulum sihirbazı, yan sayfalar | bitti (görüntü testleri; eskisiyle karşılaştırma bekliyor) |
| 7 | TVSetup (LG/Samsung/Android TV), LiveEngine (uçtan uca, gerçek Vision ile test) | bitti |
| 8 | Dalga 3: motor eksikleri + ölçüm, pencere/kart/Xbox kaynakları, Sparkle + kısayollar + admin + yedek OCR, uygulama içi TV yardımcısı (ADB/SDB) | sürüyor |
| 9 | 10 dil daha (ar, bn, fil, hi, id, ms, nl, th, ur, vi), temiz oda son taraması, eskisiyle ekran ekran karşılaştırma, kurulum + canlı deneme | bekliyor |

Temiz oda taraması (22 Kasım gece): eski ad hiçbir yeni dosyada yok. Eski kodla ortak ≥45 karakterlik satırlar
çoğunlukla aynı tarif değerlerinden doğan SwiftUI kalıpları; proje özel adlı olanlar son geçişte yeniden yazılacak.

## Kararlar (kullanıcı, 22 Kasım 2026)

- Sparkle kullanılacak (ekleme izni var).
- macOS 14+, ama Intel de desteklenecek: Remote Play çerçevesi x86_64 için de derlenecek (universal).
- Yazı tipleri (OFL) aynen, lisans dosyalarıyla. tokens.json ve xcstrings KOPYALANMAZ: değerler aynı kalabilir,
  dosyalar kendi yapımızla yeniden yazılır; metinler 12 dilde aynı anlamla yeniden yazılır.
- Kapsam: her şey. Sıra: PS5 + Remote Play + okuma/çeviri + TV + ana ekran/ayarlar → TV kurulum yardımcısı,
  HDMI kartı, Xbox → en son App Store hedefi. Firebase/Meta yok.

## Bağımlılık notu

Uçtan uca TV denemesi, TV oturumunun yeni protokolü (NinoCore, 47800, TV dinler)
uygulamasına bağlı. Eski TV uygulaması eski düzeni (Mac 8787'de sunar) bekliyor.

## Oyun paketleri (karar, 22 Kasım gece)

- Paketler uygulamaya GÖMÜLMEZ. İlk açılışta havuz sunucusundan indirilir; veri klasöründe duran mevcut paketler
  kullanılır. İnternet yoksa uygulama paketsiz çalışır (çeviri hattı bozulmaz).
- Sabah için not: paketlerin havuzda kullanıcının kendi çevirilerinden yeniden üretilmesi (eski paketlerin
  `source` alanında eski projenin adı geçiyor).

## Nasıl denenir (sabah, kullanıcıyla)

Yapı:
```bash
cd apps/mac && xcodegen generate
xcodebuild -scheme Nino -configuration Release -derivedDataPath ../../build/mac-dd build CODE_SIGN_IDENTITY=6DAFCD6A4C16DBA342F6F86915B9016CB3F0DD6F CODE_SIGN_STYLE=Manual
```
Birim ve uçtan uca testler (uygulama açılmaz): `cd apps/mac/NinoMacKit && swift test`.

1. **Deneme kopyası (güvenli):** `build/mac-dd/Build/Products/Debug/Nino Dev.app`. Ayrı kimlik (`com.ninotranslator.mac.dev`),
   ayrı klasör ("Nino Dev"), ayrı Anahtarlık; kendiliğinden hiçbir şey başlatmaz. Kurulum sihirbazıyla açılır.
2. **Gerçek veriyle (kurulum):** Önce eski `/Applications/Nino.app` → `~/NinoYedek/` (kopya), sonra Release yapısı
   `/Applications/Nino.app` olarak konur. Aynı kimlik ve imza: ayarlar, PS5 eşleşmesi, TV ve öğrenilmiş veriler
   olduğu gibi okunmalı (sihirbaz çıkmamalı, ana ekran "PS5 · hazır" göstermeli).
   Açmadan önce başka Nino kopyası kapalı olmalı (8787 çakışır).
3. **PS5:** PS5 açıkken fişi tak / anahtarı aç. Beklenen: "Bağlanıyor…" → "Bağlı", TV'de altyazı. Eski kayıtta
   konsol kimliği yok: ağda bulunup tamamlanmalı, yeniden eşleştirme istememeli.
   Kontrol: `~/Library/Logs/Nino/remoteplay.log`, ana ekrandaki durum metni.
4. **TV (iFFALCON, Android TV, 192.168.0.110):** Kurulu eski TV uygulaması 8787'ye bağlanmalı (eski uyumluluk sunucusu).
   Yeni TV uygulaması kurulursa Mac 47800 üzerinden TV'ye bağlanır. Kurulum yardımcısı (ADB) ilk bağlantıda TV'de
   onay sormamalı (eski `adb/adbkey` kullanılır).
5. **Çeviri:** paket → havuz → önbellek → çevrimiçi motor → cihaz içi sırası. İnternet kesikken paketsiz/cihaz içi sürmeli.
6. **GTA 6:** telefon ve harita kartları TV'de; oyun "GTA 6" olarak tanınmalı.
7. **Karşılaştırma:** aynı ekranlar eski uygulamayla yan yana (ana ekran salon/anahtar, ayarlar bölümleri, kurulum adımları).
   Görüntü testleri: `apps/mac/snapshots/*.png` (git'e girmez, `swift test` üretir).

Bilinen eksikler ve sabah doğrulanacaklar: her ajanın raporundaki "canlı denenecek" maddeleri aşağıda toplanır.
- PS5: uyandırma, giriş şifresi akışı, gerçek hata satırları, 20 kare/sn, host-id büyük/küçük harf.
- TV: LG 3001 sertifikası, SSDP/24 tarama, Samsung 8002, Android ADB anahtarı ve APK kurulumu.
- Kaynaklar: PS Remote Play / chiaki penceresi, yakalama kartı, Greenlight indirme.
- Samsung TV kurulumu: imza sertifikası akışı (tarif §9; sahte sunucuyla sınandı).
- Yerel ağ izni tahmini, uyku/uyanma, Sparkle güncellemesi (Release'te).

## Kurulum (22 Kasım 2026, ~08:40)

- Yeni Nino 4.1.0 (yapı 31, evrensel) `/Applications/Nino.app` olarak kuruldu. NinoCore: 652f2bf (kurulum anında
  NinoCore'da 0 commit edilmemiş dosya vardı; başka oturumların işi).
- Yedek: `~/NinoYedek/mac-20261122-0836-kurulum-oncesi/` → `Nino-applications-orijinal.app` (eski 4.0.6),
  `Nino/` (veri klasörü), `legacy-support/`, `com.ninotranslator.mac.plist` (ayarlar).
- İlk açılış (çeviri başlatmadan, admin kipi geçici kapalı): ayar kaydı birebir aynı kaldı; Anahtarlık kayıtlarının
  hiçbiri değişmedi; veri klasörüne yalnız `altyazi-yeri.json` ve `telemetry/` eklendi; pencere 1040×752.
  Ekran kilitli olduğu için görüntü alınamadı; ana ekranın açıldığı sabah gözle doğrulanacak. Admin kipi geri açıldı.
- PS5 o sırada ağda yoktu (`nino-rp bul` bulamadı) → PS5 ve TV ile canlı deneme YAPILMADI, sabah.
- Ekran karşılaştırması: yalnız Hakkında eski uygulamayla gerçek görüntüden karşılaştırıldı (farklar düzeltildi).
  Diğer ekranlar tariften yapıldı; eskisiyle gözle karşılaştırma bekliyor.

### Geri alma

```bash
osascript -e 'tell application id "com.ninotranslator.mac" to quit'
```
```bash
mv /Applications/Nino.app ~/NinoYedek/Nino-yeni-4.1.0.app && ditto ~/NinoYedek/mac-20261122-0836-kurulum-oncesi/Nino-applications-orijinal.app /Applications/Nino.app
```
```bash
defaults import com.ninotranslator.mac ~/NinoYedek/mac-20261122-0836-kurulum-oncesi/com.ninotranslator.mac.plist
```
Veri klasörü yeni uygulamayla uyumlu kaldığı için genelde geri yüklemek gerekmez; gerekirse aynı yedekteki `Nino/`.

### Açık kalanlar

- Oyun paketleri: eski 9 paket uygulamanın içinde geliyordu (veri klasöründe paket yok); yeni uygulama gömmüyor →
  yayına kadar paketsiz. `/v1/packs` havuz sunucusuna eklendi (dal `claude/havuz-paketler`, ölçüm dalının üstüne;
  migration 0017). Sabah: önce ölçüm dalı, sonra bu dal; remote migration + deploy + `POST /v1/packs/build`.
- Sunucu düzeltmelerinden sonra kurulu uygulama yeniden derlenip güncellendi (sunucu-uyumu.md).

- App Store hedefi (en son yapılacak), paket içe aktarma, kumanda simgesi tanıma ve vurgu renkleri (öncelik 3).
- `gecmis-hakkinda-saglik.md` Hakkında tarifi koddan eski (kod kullanıcının isteğine göre).
- Her ajan raporundaki "canlı denenecek" maddeleri (yukarıda).

## Hata ayıklama kaydı (22 Kasım 2026)

Sürekli, kullanıcıya görünmeyen halka tampon kaydı. Ayarı ya da ekranı yok.

- **Ne zaman açık:** admin modunun kuralıyla aynı (`AdminModeRules.isOn`): Debug yapısında (`.dev`) her zaman,
  yayın yapısında yalnız `defaults write com.ninotranslator.mac ninoAdminMode -bool YES` ile. Normal kullanıcıda
  hiçbir parçası kurulmaz, klasör bile açılmaz (test: `testNothingRunsWithoutAdminMode`).
- **Nerede:** `~/Library/Logs/Nino/debug-kayit/` (deneme yapısında `~/Library/Logs/Nino Dev/debug-kayit/`).
  Akışların toplamı 2 GB'ı geçince en eski dosyalar silinir (30 sn'de bir). `cikti/` ve `olcum.json` sayılmaz.
  - `ps5/<başlangıç>-<bitiş>.mov`: Nino'nun okuduğu PS5 karesi, 960×540, 2 kare/sn, H.264 (donanım kodlayıcı), 2 dk'lık
    parçalar. Çizimler: okuma bölgesi sarı kesikli, okunan altyazının kutusu kırmızı, TV'ye giden kutular (altyazı,
    ekran öğeleri, ek alanlar) camgöbeği, altta okunan/çeviri. Kare zamanı = adındaki başlangıç + sunum zamanı.
    1 sn'lik film parçacıklarıyla yazıldığı için yazılırken ve çökmeden sonra da okunur.
  - `mac/…mov`: ana pencerenin görüntüsü, en çok 1280×800, 1 kare/sn (yalnız görünürken; ekran kaydı izni istemez).
  - `olay/<zaman>.jpg`: satır okunduğunda/gösterildiğinde, TV/PS5 olayında tam boy çizimli kare (en sık 5 sn'de bir).
  - `tv/<zaman>.png`: eşli TV Android TV ise ve çeviri açıkken dakikada bir `screencap -p` (adb). Yalnız TV'nin zaten
    onayladığı anahtarla; TV tanımazsa onay kutusu çıkmaz, o oturumda bir daha denenmez; erişilemezse 5 dk bekler.
  - `gunluk/…jsonl`: `altyazi.log` ve `remoteplay.log` satırlarının aynısı (aynı zaman damgasıyla) ve `durum:` satırları
    (PS5 kaynağı, çeviri, TV sayısı, oyun, eşli TV; değiştikçe).
  - `mesaj/…jsonl`: hub'ın TV'lere dağıttığı her protokol mesajı (sığdırılmış hâliyle, `{"t","tv","j"}`); "altyazı
    yalnız bilgisayarda" iken TV'ye gitmeyen altyazı buraya da girmez. Girmeyenler: bir TV (yeniden) bağlanınca yalnız
    ona yollanan tekrar (style, started, son altyazı; "TV bağlandı" satırından hemen sonra) ve 8787'deki eski TV'lere
    giden eski biçim (içerik aynı, biçim farklı).
- **Kancalar (motora dokunmadan):** kareler `NinoAppSupport.tap`, TV mesajları hub'a eklenen `DebugHubTap`
  (anahtar `debug-kayit`), günlük `RotatingLog.mirror`, durumlar AppState'ten saniyede bir. Kod:
  `AppSupport/DebugRecorder.swift`, `AppSupport/DebugRecording.swift`, çekirdek `Sources/NinoDebugKit/`, araç
  `Sources/nino-debug/`. `ADBConnection.handshake(offerKey:)` eklendi (varsayılan eski davranış).
- **Bütçe:** tek `.utility` seri kuyruk, akış başına en çok bir bekleyen iş (yetişemezse kare atılır). Kayıtçı kendi iş
  parçacığı CPU süresini ölçer; 5 sn'lik pencerede %5'i ya da 150 MB'ı geçerse kare aralıkları iki katına çıkar (en çok
  8×), üç sakin pencereden sonra yarıya iner. Son ölçüm `olcum.json`'da (30 sn'de bir).
- **Ölçüm (kıyas testi `testBenchmarkRecorderCost`, Apple Silicon, yapay 1080p gürültü kareleri = en kötü durum):**
  PS5 karesi başına 4,9 ms iş parçacığı / 8,4 ms süreç CPU → 2 kare/sn'de kayıtçı ~%1 (süreç toplamıyla ~%1,7);
  olay karesi 29 ms; bellek ~23 MB (kodlayıcı + tamponlar); disk PS5 videosu en çok ~6,6 MB/dk (bit hızı sınırı),
  olay kareleri gerçek oyunda ~0,2 MB'lık JPEG. 2 GB yaklaşık 3–5 saatlik geçmiş tutar. Pencere görüntüsü
  (`cacheDisplay`, ana iş parçacığı) testte ölçülemez; süresi bütçeye eklenir, canlıda `olcum.json`'dan okunur.
- **Araç:** `Nino.app/Contents/MacOS/nino-debug` (uygulamayla aynı kimlikle imzalı; `swift run nino-debug` da olur).
  ```
  nino-debug son 5dk
  nino-debug 16:05-16:10
  nino-debug son 30sn --cikti ~/Desktop/inceleme
  nino-debug durum
  ```
  Çıktı (varsayılan `debug-kayit/cikti/<zaman>/`): `ps5/` ve `pencere/` PNG kareler, `olay/`, `tv-ekran/`,
  `gunluk.txt`, `tv-mesajlari.jsonl`, `ozet.md` (okunan/gösterilen satır, çeviri ortalama/p95 kaynağa göre, atılan ve
  kaçırılan satırlar nedenleriyle, TV bağlanma/kopmaları, PS5 durumları, oyun, kayıt bütçesi). `--kok` ile başka kök.
- **Canlıda denenmedi:** gerçek PS5 kareleri, pencere görüntüsünün süresi ve SwiftUI penceresini tam çizip çizmediği,
  adb ekran görüntüsü. TV görüntüsü yalnız Nino'nun adb anahtarı TV'de zaten onaylıysa alınır (yoksa sessizce kapalı).
  Bütçe yalnız kayıtçı iş parçacıklarının CPU'sunu sayar (süreç toplamı kıyasta ~1,7 katı); bellek tarafı sabit bir
  tahmin olduğundan pratikte yalnız CPU yavaşlatır. Dağıtımda Developer ID ile yeniden imzalarken
  `Contents/MacOS/nino-debug` da imzalanmalı.
- **Canlı bulgulardan düzeltmeler (22 Kasım akşam):** pencere hiç kaydedilmiyordu ("pencere kareleri: 0"): ilk
  sürüm yalnız örtülmemiş pencereyi alıyordu, oyun sırasında Nino penceresi hep arkada. Artık görünür ya da küçültülmüş
  ana pencere kendine çizdirilir (`cacheDisplay`); izin gerekmez, Sistem sağlığına bir şey eklenmedi. Pencere kapalıysa
  `olcum.json`'da `macMissing` artar. `ps5Dropped` yanlış sayıyordu (önceki iş sürerken gelen her kaynak karesi);
  şimdi yalnız zamanı gelmiş ama alınamayan kare `ps5Busy`, kodlayıcının almadığı `ps5Dropped`; özet ikisinin oranını
  yazar (kaydın kendi oranı; okuma hattı beklemez). Özette ayrıca `screen`, `screen-clear` ve "değişmeyen liste yeniden
  gönderimi" (bir öncekiyle aynı öğe listesini taşıyan `screen`) ayrı satırda.
- **Eksik:** tek tek OCR satırlarının kutuları NinoCore'da dışarı açık değil (`Reader.lastLines` private); çizimde
  okuma bölgesi, okunan altyazının kutusu ve TV kutuları var. Öneri: NinoCore'a salt okunur `recentLines` erişimi.

## Bileşik kare, video kaydı ve admin TV önizlemesi (22 Kasım 2026)

- **Bileşik kare:** `frames/f-*.jpg` ve `frames/latest.jpg` artık PS5 karesi + TV'nin çizdiği katmanın aynısı + okuma
  kutuları. Katman, TV web sayfasının kopyası (`Sources/NinoMacKit/TVPage/`, apps/tv-web/src 3eada6e7 (harita kartı kutuya tam ve opak); yalnız
  `platform.js` farklı: HDMI saydam, ağ yok, sahte bağlantı) gizli, ekran dışı bir WKWebView'da 1920×1080 çalışır.
  TV'lere giden protokol mesajları hub dinleyicisinden aynen `window.nino.receive` ile verilir (telefon balonları,
  harita kartı, köşe çevirileri, altyazı kutusu; screen/show bayraklarıyla). Ağ içerik kuralıyla kapalı, veri kalıcı
  değil; sayfanın TV'ye özgü parçaları (bekleme sahnesi, durum kutusu, ipuçları) gizli. Kare 2 sn'de bir ve TV katmanı
  değişince (show/clear/screen/region/style/stopped; 0,35 sn sonra) yazılır. Ayrı `c-` dosyası yok.
  Sayfayı güncellemek: `git archive <tv-web dalı> apps/tv-web/src | tar -x` ile alıp `platform.js` dışındakileri kopyala.
  Okuma kutuları (sarı bölge, mavi köşeler, kırmızı okunan yazı) ince kesikli ve TV katmanının ALTINDA çizilir; kartın
  kırmızı-beyaz üst çizgisi TV sayfasınındır.
- **GTA 6 bindirme (22 Kasım 17:18):** görev şeridi `plain` değil (TV kutu genişliğinde, opak), pembe sözcük
  `GameReading.Accent` ile bulunur ve çeviride `⟦…⟧` ile işaretlenir (vurgulu ifade ayrıca çevrilir, kök eşlemesi);
  harita kartı kartın üstüne oturur ve alt satırları da çevirir; iki okuma arasındaki titreme NinoCore'da giderildi.
- **Video kaydı:** eskisi gibi `frames/video/KAYIT` dosyası varken; artık JPEG yığını yerine `frames/video/<başlangıç>-<bitiş>.mov`
  (ham PS5 karesi, saniyede 10, 1920×1080 tuval, H.264 8 Mbit/sn ≈ 60 MB/dk, 2 dk'lık parçalar, yazılırken de okunur).
  Klasör 2 GB'ı geçince en eski parça silinir (debug-kayit'ten ayrı bütçe). **Ses yok:** Remote Play kitaplığı
  (NinoRemotePlay) oturumu sesi kapalı açıyor (`CHIAKI_AUDIO_DISABLED`); `appendAudio` duruyor ama çağıran yok.
  Öneri: NinoRemotePlay'e ses akışı (NinoCore değişikliği).
- **Admin önizlemesi:** `AppState.adminTVPreview` (yeni alan, `AdminTVPreview` türü) her bileşik karede güncellenir.
  Salon sahnesinde çeviri açıkken TV'nin içi bu kareyi gösterir; anahtar görünümünde sağ altta 320×180 önizleme.
  Yalnız admin modunda dolar.
- Testler: `CompositeFrameTests` (gerçek WKWebView ile saydam katman, altyazı ve kart çizimi, son durumun tekrarı,
  bileşim pikselleri, değişince hemen kare, KAYIT ile video ve halka).

## Sıradaki (22 Kasım akşam, kullanıcı hata listesi)

- [sürüyor] Sabit görüntüde okuma süre tabanlı (en geç 1,5 sn); "yalnız altyazıyı çevir" çekirdek seçeneği; show'a `speaker` alanı (konuşan adı sarı, çizim tv-web).
- [bekliyor] Ayarlar'a "Yalnız altyazıyı çevir" düğmesi (çekirdek bitince).
- [bekliyor] Kurulum TV adımında "Akıllı TV veya akıllı monitör" (Samsung Smart Monitor/Odyssey, LG MyView) seçeneği.
- [sürüyor] Kurulum çeviri adımı (varsayılan Ücretsiz, maskotlu Nino Kütüphanesi kartı, açık API key alanı), Enter ile fiş, yazı boyu çarpanı, oyun kimliği takma adları → deneme-3.

### 22 Kasım 23:32: 4.5.0 deneme-3 (yayın adayı)

- Mac c957059e + NinoCore 2e84792; `swift test` 473 test, 0 hata. Evrensel (arm64 + x86_64), Release, geliştirici imzası
  (Developer ID imzası, notarizasyon ve Sparkle yayını yok).
- İçindeki TV paketleri: LG ipk + Samsung wgt 4.5.0 (tv-web c9ed6515), Android TV 4.5.0 (a6194151).
- Bu deneme ile gelenler: LG açık tutma bağlıyken launch göndermez; TVPage tv-web c9ed6515 ile eşit (otomatik boy %25);
  Ayarlar'da "Yalnız altyazıyı çevir", kütüphanede tek GTA 6 satırı; API anahtarı adımı, Enter ile fiş, oyun kimlikleri,
  sabit görüntü okuma, konuşan adı, harita kartı (ajan commit'leri 80616ff2, 1a18787c, 61c49814, 31bc41ab, c4454c16,
  bbd13d57, da990cb6).
- Kurulu: /Applications/Nino.app (admin açık); yedek ~/NinoYedek/mac-20261122-2331-deneme3-oncesi.
- Arkadaş zip'i: ~/Downloads/Nino-4.5.0-deneme-3.zip (NinoAdminDisabled), SHA-256
  870f05736e51e8c45b1bc3be192b2cde3f5513e332901ce4fcce2f929c1e1d4b.
- Bilinen: NinoCore'un yerleşik OpenAI model listesi boş (OpenAI anahtarıyla istek gitmez, yedeğe düşer); eski TV
  sayfaları `speaker` alanını tanımaz (ad görünmez); docs ayarlar.md §6.3 "kaydırıcı kilitli" demeye devam ediyor.

### 23 Kasım 00:08: 4.5.0 deneme-4

- Mac b97a4bd7 + NinoCore b3cc670; TV paketleri aynı (tv-web c9ed6515, Android TV a6194151).
- Gelenler: menüden çıkınca altyazı kaçmaz + atlanma nedeni günlükte (b3cc670, b97a4bd7); sol üst görev kartı (852a61a);
  Ayarlar › Çeviri baştan (maskotlu kütüphane kartı, "Şu an: <oyun>", sağlayıcı akordiyonu, Gelişmiş yok; deb11d73);
  Sorun Bildir tek ekran + ekler + otomatik teşhis bildirimi, Hakkında yalnız iki ad + Güncellemeleri Denetle (56c1d227);
  Enter ipucu fiş balonunda, oyun seçici kalktı, admin etiketleri yalnız geliştirici kipinde (3ab9cb54);
  deneme altyazısı hedef dilde (97ad7b3b).
- Kurulu /Applications/Nino.app (yedek ~/NinoYedek/mac-20261123-0008-deneme4-oncesi); açılışta PS5'e bağlandı, okudu, TV'de gösterdi.
- Zip ~/Downloads/Nino-4.5.0-deneme-4.zip (NinoAdminDisabled), SHA-256 8a7cd8e2431fd727665944f7b67822e8cf00ac9a65d84f978871f8bc56806770.
- Sürüyor (deneme-5): kaçırma ölçer + gecenin kayıtları; telefon/harita panelleri Mac ekranında.
