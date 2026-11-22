# Nino 4.5.0 yayın kontrol listesi

Bu belge yayından önce yapılacakları sırayla toplar. **Hiçbiri henüz yapılmadı**: hiçbir şey GitHub'a, Cloudflare'e ya da
mağazalara gönderilmedi. Her adım kullanıcının onayıyla, kullanıcının kendi hesabıyla yapılır.

## 0. Bu yapının kaynağı

- Birleşik dal: `claude/nino-4-5-hazir-a6275b`. Dallar `scripts/birlestir.sh` ile alınır; yeniden çalıştırınca yalnız
  yeni commit'ler gelir, NinoCore'un son commit'i `core/` klasörüne kopyalanır.
- Birleştirilen dal uçları ve NinoCore commit'i: bkz. [Ek A](#ek-a-kaynak-commitleri).
- Yayın dosyaları: `dist/4.5.0/` (git'e girmez), özetleri `dist/4.5.0/SHA256SUMS.txt`.
- Sürüm numaraları: hepsi 4.5.0. Mac yapı 32, iOS yapı 29, Android telefon versionCode 61, Android TV versionCode 45,
  LG/Samsung 4.5.0, Windows/Linux 4.5.0.

## 1. İmza anahtarları (kullanıcı)

| Uygulama | Gereken | Durum |
|---|---|---|
| Mac (GitHub/DMG) | Developer ID Application sertifikası + notarization, Sparkle EdDSA özel anahtarı (`sign_update`) | `dist/4.5.0` içindeki Mac yapısı yerel geliştirici kimliğiyle imzalı; dağıtım için Developer ID ile yeniden imzalanıp notarize edilmeli |
| Mac App Store | Apple Distribution + App Store profili (takım 2D65S2R5LX) | yapılmadı |
| iPhone/iPad | App Store Connect API anahtarı (`~/NinoCanvasSecrets/apple`), takım 2D65S2R5LX | yalnız simülatör derlemesi yapıldı |
| Android telefon | GitHub APK'sı için sürüm anahtarı (önceki APK'larla aynı imza, SHA-256 `43c015…`; `~/.config/nino/android-signing.properties` ya da `NINO_ANDROID_SIGNING`), Play için yükleme anahtarı | Play yükleme anahtarı bu Mac'te var (`~/.config/nino/play-upload.env`, `upload-mobile.keystore`); **GitHub APK anahtarı yok**. `dist/4.5.0` içindeki APK hata ayıklama imzalı |
| Android TV | `TV_KEYSTORE_FILE` (GitHub/gh-pages APK'sı), `TV_UPLOAD_KEYSTORE_FILE` (Play) | **bu Mac'te bulunamadı**; hata ayıklama imzalı. Mac uygulamasına ve telefon APK'sına gömülen TV APK'sı da hata ayıklama imzalı: yayından önce sürüm anahtarıyla yeniden derlenip onlar da yeniden derlenmeli |
| Samsung TV | Kullanıcının Samsung sertifikası (uygulama TV'ye kurarken kendisi imzalar) | paket imzasız `.wgt`, olağan |
| LG TV | Gerekmez (geliştirici modu) | — |
| Windows | Velopack paketi; isteğe bağlı kod imzalama sertifikası | Mac'te yalnız derleme ve testler yapıldı; kurulum dosyası Windows'ta üretilmeli |

Android APK'yı Play anahtarı yüklüyken derleme: GitHub APK'sı ile Play AAB'si farklı anahtarla imzalanır (önce env'siz
`assembleRelease`, sonra env'li `bundleRelease`; `apksigner verify --print-certs` ile önceki APK'yla karşılaştır).

## 2. Sunucu (Cloudflare, nino-pool) — uygulamalardan ÖNCE

Uygulamalar yeni uçları (`/v1/events`, `/v1/packs`, teşhis, Nino'ya Sor hazır cevapları) kullanır; sunucu önce çıkmalı.

1. `cd nino-pool && npm ci && npm test` (124/124 geçmeli).
2. Yedek yardımcı modelini gerçek anahtarla bir kez dene (yerelde anahtar yoktu):
   `ASSISTANT_PROVIDER=openrouter ASSISTANT_MODEL=google/gemini-2.5-flash-lite OPENROUTER_API_KEY=… node scripts/eval-assistant.mjs`.
   Kötü çıkarsa `wrangler.toml`'da `ASSISTANT_FALLBACK = "0"`.
3. Uzak veritabanına migration'lar, sırayla tek komutla: `npx wrangler d1 migrations apply nino-pool --remote`
   (0016_events → 0017_packs → 0018_tv_links → 0019_diag; 0020 yok, yardımcı yeni tablo eklemiyor).
4. `npx wrangler deploy`. Yeni sır gerekmez (`OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `EXPORT_TOKEN` zaten tanımlı olmalı;
   `npx wrangler secret list` ile bak).
5. İlk oyun paketleri: `curl -X POST -H "Authorization: Bearer $EXPORT_TOKEN" https://nino-pool.y-demirbag2506.workers.dev/v1/packs/build`
   (ya da gece 03:17 cron'unu bekle), sonra `curl …/v1/packs` ile listeye bak.
6. `/panel`: Ölçüm, TV bağlantıları, Otomatik teşhis ve Nino'ya Sor kartları dolmaya başlamalı.

## 3. TV paketleri — masaüstü/telefon uygulamalarından ÖNCE

Mac, iPhone, Android telefon ve Linux TV paketlerini içine gömer; TV paketi değişince onlar yeniden derlenir.

1. Android TV: `cd apps/android-tv && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=~/Library/Android/sdk gradle assembleSideloadRelease`
   (sürüm anahtarıyla) → `dist/tv-app/nino-androidtv_4.5.0.apk`.
2. LG + Samsung: `python3 apps/tv-web/tools/package.py` → `com.ninotranslator.tv_4.5.0_all.ipk`, `nino-samsung_4.5.0.wgt`;
   ikisini `dist/tv-app/`'e koy.
3. gh-pages `tv.apk` (is.gd/ninotvapk) yeni Android TV APK'sıyla değiştirilir — Windows derlemesinden önce.

## 4. Uygulamalar

1. **Mac:** `cd apps/mac && xcodegen generate && xcodebuild -scheme Nino -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO …`
   Developer ID ile imzala, notarize et, `ditto` ile zip, Sparkle `sign_update` (doğru araç:
   `SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`), `appcast.xml`'i güncelle. Ekrandaki "V4.5" etiketi elle
   yazılıdır; değiştiyse denetle.
2. **iPhone/iPad:** arşiv → `xcodebuild -exportArchive` (dışa aktarma ayar dosyası `ExportOptions-upload.plist` yeni depoda yok; App Store yükleme yöntemiyle yeniden yazılmalı) → TestFlight
   grupları → App Store incelemesi. (App Store'da Çin anakarası kapalı kalır.)
3. **Android telefon:** env'siz `gradle :app:assembleRelease` (GitHub APK), sonra env'li `bundleRelease` (Play AAB).
   Play: kapalı test (Google Grubu nino-test) devam ediyor.
4. **Windows:** Windows'ta `apps/windows/native/scripts/build-windows-msys2.sh` (FFmpeg + nino_native.dll),
   `dotnet publish apps/windows/src/Nino.App -c Release -r win-x64`, Velopack paketi. Testler: `dotnet test apps/windows/Nino.Windows.slnx`.
5. **Linux:** `./apps/linux/build.sh` (Docker imajı; chiaki-ng'yi resmî depodan alır). İmaj Mac'te hiç derlenmedi.

## 5. GitHub sürümü

1. Açık depo (`yunusdemirbag/nino-game-translator`) yeni temiz depodan (`~/Desktop/Nino`) beslenir; eski geçmiş
   gönderilmez. Göndermeden önce özel dosyaları çıkar (`CLAUDE.md`, `.claude/`, `docs/nino/tweet.md`, tanıtım taslakları)
   ve anahtar taraması yap.
2. Etiket `v4.5.0`. Mac, Android ve Windows güncelleme denetimi **etiket adını** kendi sürümüyle karşılaştırır: bütün
   masaüstü/telefon dosyaları aynı etiketle yüklenmeli.
3. `gh release create v4.5.0 --latest` + Mac zip, `appcast.xml`, telefon APK, TV APK, Windows kurulum dosyaları, LG `.ipk`,
   Samsung `.wgt`. Sonra `releases/latest/download/…` adreslerini ve appcast sürümünü denetle.
4. Web sitesi (`site/`) ve mağaza metinleri (`store/`) yeni sözlerle yazıldı; eksikleri 7. bölümde.

## 6. Bilinen eksikler (gerçek cihazda denenmedi)

- **Windows:** yalnız Mac'te derlendi ve testleri koştu; gerçek bir Windows bilgisayarda hiç açılmadı (WPF arayüzü,
  WebView2 PSN girişi, MSYS2 FFmpeg derlemesi, Velopack kurulumu denenmedi).
- **Linux:** Docker imajı hiç derlenmedi; Mac'te geçici ortamla kod yolu denendi.
- **iPhone/iPad:** yalnız simülatörde; gerçek telefonda PS5 Remote Play, Xbox, telefondan TV kurulumu denenmedi.
- **Android telefon:** yalnız JVM testleri ve emülatör/derleme; gerçek telefonda PS5, Xbox, ML Kit, TV kurulumu denenmedi.
- **LG ve Samsung TV:** paketler üretildi ve sayfa testleri geçti; gerçek TV'ye kurulmadı.
- **Mac ve Android TV:** kullanıcının Mac'inde ve TCL TV'sinde canlı denendi (en çok denenen ikili).
- Nino'ya Sor'un OpenRouter yedeği gerçek anahtarla hiç çağrılmadı.
- Ölçüm/teşhis uçları canlıda yok; ilk gün paneli izle.

## 7. Mağaza ve site için eksikler

- **Logo:** `nino/brand/logo.png` hâlâ DualSense'e benzeyen bir kol ve PlayStation tuş simgeleri taşıyor; bütün
  ikonlarda ve mağaza görsellerinde görünüyor. Mağazalar reddedebilir; genel bir kol çizimiyle değiştirilmeli.
- **Site adresi (kullanıcı kararı):** varsayılan, şimdiki canlı adres olan GitHub Pages proje sitesi
  `https://yunusdemirbag.github.io/nino-game-translator/`. `site/public` bu dalın `gh-pages`'ine konur; `tv.apk` ve
  `.nojekyll` kalır. Gizlilik adresi `…/nino-game-translator/gizlilik`; mağaza metinlerindeki `<site>/gizlilik` buna
  çevrilmeli. Eski `/rehber/#samsung|#lg|#android-tv|#iphone|#fis` adresleri yeni bölümlere yönlenir. Başka bir alan
  adına taşınırsa yalnız `og:image` ve `hreflang` tam adresleri değişir (ayrıntı `site/README.md`).
- LG ve Samsung: UX senaryo belgesi, LG arka plan görseli ve öz denetim listesi, Samsung'un istediği diğer ikon
  boyutları. Ekran görüntüleri (dil başına 3) yeni TV sayfasından alındı.
- Play: 1024×500 öne çıkan görsel, yeni uygulamadan telefon ekran görüntüleri, destek e-postası, Veri güvenliği formu.

## 8. Bu derlemenin test sonuçları (22 Kasım 2026, bu Mac'te)

| Bölüm | Sonuç |
|---|---|
| NinoCore (`core/`) | 555 test, 0 hata (8 atlandı); NinoRemotePlay derlendi |
| Mac NinoMacKit | 446 test, 0 hata (2 atlandı); Release evrensel (arm64 + x86_64) derlendi |
| iPhone/iPad | simülatörde 100 test: 99 geçti, 1 atlandı (Anahtarlık testleri için yerel imza gerekir; imzasız çalıştırmada 3'ü düşer); Release simülatör derlemesi |
| Android telefon | çekirdek 271 + uygulama 235 test, 0 hata; hata ayıklama APK'sı (TV paketleri içinde) |
| Android TV | 65 JVM + 13 sayfa testi geçti; sideload ve Play hata ayıklama APK'ları |
| LG/Samsung (tv-web) | 73 test (72 geçti, 1 atlandı); `.ipk` ve `.wgt` üretildi |
| Windows | 2266 test, 0 hata (Core 1696, Shell 260, RemotePlay 127, Translation 110, TvInstall 73); Release win-x64 Mac'te derlendi (yerel köprü DLL'i yok) |
| Linux | 91 test, 0 hata; linux-x64 yayını Mac'te derlendi (`nino_native.so` yok) |
| nino-pool | 127 test, 0 hata |

## 9. Kullanıcının onayı gereken değişiklikler ve bilinmesi gerekenler

- **Gizlilik metninde olgu değişti:** havuz çevirisinin hizmetleri `nino-pool/wrangler.toml`'a göre yazıldı (Groq,
  OpenRouter, NVIDIA, DeepL, Google Gemini; Claude kapalı; oyun tanıma kapalı). Canlı ayar farklıysa düzeltilmeli.
  Ayrıca eski türetme cümlesi ("…'tan türetilmiştir") çıkarıldı. Yayından önce okuyup onayla.
- **Android çeviri istemleri yeniden yazıldı** (çevrimiçi hizmetlere giden istek metni değişti); gerçek hizmetle denenmedi.
- **Uygulama dalları geride:** temiz oda düzeltmelerinin çoğu (Android, Windows, iOS, Linux, belgeler) yalnız bu
  birleşik dalda. Uygulama oturumları kendi dallarında aynı satırlara dokunursa `birlestir.sh` çakışma verebilir.
- **Yeni depoda (`~/Desktop/Nino`) ilk derleme:** Mac, iPhone ve Android için önce Remote Play C kütüphanesi kurulmalı
  (`core/NinoRemotePlay/scripts/fetch-deps.sh && build-deps.sh && build-c.sh`; Android: `apps/android/scripts/build-remoteplay.sh arm64-v8a`).
  Bu derlemede `~/Desktop/NinoCore`'dan bağlantı ve önceden derlenmiş `.remoteplay` kullanıldı.
- **Eski yayın yardımcıları alınmadı** (eski projenin `scripts/release-*`, `package-*`, App Store `ExportOptions`,
  sürüm notları). Yayın adımları bu belgede elle; istenirse yeni betikler yazılır.
- **Mac paketi** (`Nino-Mac-4.5.0.zip`) TV paketleri eklenip yeniden imzalandı ve imzası doğrulandı, ama açılıp
  denenmedi (kurulu Nino'yla çakışmasın diye).
- **Nino'ya Sor:** bazı dillerde öneri düğmeleri (TV uygulaması kurulumu: th/hi/bn/ur/fil/vi; "Hangi oyunu oynuyorum?"
  bütün dillerde) hazır cevaba eşleşmiyor, modele gidiyor. Temizlikten önce de böyleydi; hazır cevap tetikleyicileri
  eklenebilir.
- Android TV sayfa testlerindeki zamanlama sorunu Android TV dalında giderildi (af80f2aa).
- **`dist/4.5.0` bu dalın 22 Kasım akşamki hâlinden derlendi.** Sonradan Mac, TV web, Android TV ve sunucu dallarından
  yeni commit'ler geldi; yayından önce bütün paketler bu daldan yeniden derlenmeli.
- Android TV yayın derlemesi: `TV_KEYSTORE_FILE=… TV_KEYSTORE_PASSWORD=… gradle -PninoPublish assembleSideloadRelease bundlePlayRelease`
  (anahtar yoksa açık hatayla durur). Yeni APK'nın sertifika SHA-256'sı gh-pages'teki eski `tv.apk`'nınkiyle aynı olmalı
  (`apksigner verify --print-certs`). TV'de elle kurulumdaki "Paket geçersiz" uyarısının çözümü sitede yazıyor.

## Ek A: kaynak commit'leri

| Dal | Uç |
|---|---|
| claude/yeni-mac-c9961f | c95744ed |
| claude/yeni-ios-4f59d1 | 6679c8e3 |
| claude/yeni-android-14ca98 | 19b5112e |
| claude/yeni-windows-ece87c | 724e34d3 |
| claude/yeni-linux-236454 | 03899574 |
| claude/yeni-tv-web-2fe593 | 3eada6e7 |
| claude/yeni-androidtv-68c732 | 8c8b511d |
| claude/havuz-paketler | 26206b96 |
| claude/olcum-6588ad | b5503e19 |
| claude/yardimci-403336 | 0151fef5 |
| NinoCore (`~/Desktop/NinoCore`, `core/` olarak) | 9ee70e2 |

Birleştirilmeyen dallar (ana oturum kararı): arapca-ceviri, nino-havuz, xbox-destegi, nino/yeni-cekirdek.
