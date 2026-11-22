# Windows yeniden yazımı: ilerleme

Yeni uygulama `apps/windows/` (Nino.Windows.slnx). Eski `windows/` yerinde, yeni koda bağı yok.

## Durum (22 Kasım 2026, gece)
- [x] Tarifler (eski kodu okuyan 9 ajan, kod yok): kimlikler-veri, ayarlar-modeli, okuma-hatti(+2), telefon-harita, ceviri,
      havuz-paketler, tv-baglanti (+§12 kararlar), tv-kurulum, kaynaklar, yerel-kopru, denetleyici, saglik-bildirim-sor,
      ana-ekran, kurulum, tasarim-dili, ayarlar, yan-pencereler. Denetleyici API'si: denetleyici-api.md.
- [x] Yazım (yalnız tariflerden, eski kod açılmadan):
  - Nino.Core: veri klasörü + eski klasör taşıma, secure.dat kasası (DPAPI arayüzü; eski ek anahtardan geçiş), ayarlar (eski PascalCase
    biçim), günlükler, ölçüm istemcisi (olcum.md), TV bağlantısı (8787 SSE kalıcı + 47800 girişi + Android TV istemcisi + OBS sayfası),
    TV bulma/eşleştirme/LG geliştirici modu, okuma hattı, çeviri zinciri, havuz, oyun paketleri (16 hex anahtar, bulanık eşleme),
    telefon/harita, sağlık/sorun bildirimi/Nino'ya Sor, 12 dilde yeniden yazılmış metinler (1033+), tasarım belirteçleri.
  - Nino.Translation (ONNX Marian, CT2 işçisi + yeni worker.py, DeepL/yapay zekâ), Nino.RemotePlay, Nino.TvInstall, Nino.TvHelper,
    Nino.Shell (arayüzsüz denetleyici; Linux da kullanıyor), Nino.App (WPF: kabuk, ana ekran, kurulum, ayarlar, tüm yan pencereler,
    yayın penceresi, Windows hizmetleri, --render-screens).
  - native/: resmî chiaki-ng v1.10.1 üstüne yeni C köprüsü (eski yamalar yok). Mac'te .dylib derlendi, C testleri geçti.
- [x] Mac'te: çözüm derleniyor; 2174 test geçiyor, 5 atlanıyor (köprü, kare çözücü, gerçek model dosyaları yok). tools/check-headers.sh temiz.
- [x] Uyum: eski uygulamanın yazdığı veri dosyaları (settings.json, secure.dat iç JSON'u, önbellek, geçmiş, havuz, sorunlar…) ve 8787 akışı
      eski kod kâhin olarak çalıştırılıp fikstür alındı (tests/Nino.Core.Tests/Fixtures/Compat); yeni kod aynı okuyor, bayt bayt aynı yazıyor
      (yalnız `at` zaman damgası değişken). 7 uyuşmazlık bulunup düzeltildi.
- [x] Sürüm 4.5.0 (aynı Velopack kimliği/kanalı: eski kurulumun üstüne güncelleme).
- [x] TV bağlantı başına bağlanma/kopma olayları ve nedenleri (closed, write_failed, silence, handshake, replaced, stopped, error):
      altyazı günlüğüne ve tv_connect/tv_drop ölçümüne gerçek nedenle (tv-baglanti.md §13).
- [x] Otomatik teşhis (otomatik-teshis.md): 9 kural bekçisi, iz tamponu, diag olayı, uzak ayar; 9 senaryo testi geçiyor.
- [x] Ölçüm istemcisi bağlı (kapatma yok, Hakkında'da satır); Velopack betiği tools/package-windows.ps1 (denenmedi); SourceLink kapalı.
- [x] Temiz oda: yerleşik oyun paketleri kaldırıldı, sözlük ve deneme vektörleri kendi örneklerimizle yeniden üretildi (tools/gen-vectors.py);
      12 dildeki metinler, tarif ve testlerdeki eski alıntılar ve koddaki günlük/istem dizgeleri yeniden yazıldı. tools/clean-room-scan.py
      düzeltilmesi gereken 0; izinli adlar temiz-oda.md'de. 25 belirteçlik parça ortaklığı eski kodla %0,79 (XAML kalıpları, zorunlu adlar).
      Tariflerin ilk hâli depo dışında: ~/NinoYedek/tarif-arsiv/windows/.
- [x] Kullanıcı hatalarından Windows'a düşenler (22 Kasım):
  - Xbox uygulaması penceresi bulunamıyordu: `GameWindowRules` artık XboxPcApp/XboxApp/Xbox/GamingApp/"Microsoft Gaming App"
    süreçlerini (tam ad; Game Bar ve Xbox hizmetleri hariç), ApplicationFrameHost'taki UWP çerçevesini (sınıf ApplicationFrameWindow +
    başlıkta Xbox) ve birçok dilde "uzaktan oynatma" başlığını (aksan/harf duyarsız) tanır; Xbox uygulamasının uzaktan oynatma başlıklı
    penceresi kütüphane penceresinden önce gelir; Sony'nin penceresi Xbox sayılmaz, Xbox'ın "Remote Play" penceresi PS5 sayılmaz. Pencere
    listesi pencere sınıfını, UWP çerçevesinin içerik sürecini (CoreWindow alt penceresi) okur ve gizlenmiş (cloaked) pencereleri atlar.
    Pencere ~15 sn bulunamazsa ilgili adaylar (süreç, sınıf, başlık) altyazı günlüğüne bir kez yazılır. Tarayıcı (xbox.com/play) kuralı aynı.
    Testler: XboxWindowRulesTests. **Denenmedi:** gerçek Xbox uygulamasının süreç/sınıf adları Windows'ta görülmedi; kütüphane penceresi
    (yayın yokken) eskisi gibi kabul edilir.
  - Kart (capture card) çevirisi hep altta sabitti: kartta pencere kullanıcının kaydettiği yere (`Overlay`) oturur; kayıt yoksa okunan
    İngilizce satırın üstüne (yerleşim "altında" ise altına; sığmazsa öbür yana; "sabit" ise eski yer) konur ve çakışmadıkça kıpırdamaz
    (`CardOverlaySeat`). Bunun için yerel altyazı olayı İngilizce kutusunu da taşır. Not: kayıtlı yer bir kez yazılınca kartta hep o
    kullanılır (otomatik yere dönmek için ayar yok).
  - Telefon/harita panelleri bilgisayarda da çizilir: `TvWire.Local` örtülü `screen` olaylarını yeni `LocalEventKind.Overlay` olayına
    (öğeleriyle) çevirir (tarif §4.6 "yerel dinleyiciye gitmez" diyordu; kullanıcı hatası esas alındı). Altyazı yığınına girmez;
    oyunun alanının üstünde duran tıklama geçiren `GamePanelWindow` (kart oynatıcısı ve oyunun kendi penceresi için) çizer; çizim hesabı
    `ScreenPanelLayout` (card opak + vurgu çizgisi, side yuvarlak gölgeli, backdrop zemin, plain kutusuz, `⟦…⟧` pembe). Oyunun penceresinden
    okunurken ekran kopyasından gizlenir. Yayıncı penceresi (OBS) panelleri çizmez. **Denenmedi:** WPF görünüşü.
  - Sabit görev yazısı yeni satırları engelliyordu: Mac çekirdeğinin adım 12'si (`StaleLineFilter`): yeni bir satır varken 9 sn ve daha
    uzun duran satırlar atılır, yalnız eski satırlar varsa atılmaz; görev çizgisinden sonra, dev satırlardan önce. Linux da alır.
  - Xbox sık kopuyordu: `XboxStreamQuality` ayarı (dosyada sayı, 0 kendiliğinden / 1 = 720p; varsayılanken yazılmaz, eski dosyada yoksa
    kendiliğinden), Ayarlar › görüntü kaynağı Xbox kartında (Xbox yayını seçili değilse görünmez), değişince yayın yeniden başlar,
    `IXboxService.CreateStream`'e geçer. **Xbox köprüsü kapalı olduğundan bugün etkisiz:** köprü açılınca 720p'de oturum isteğindeki
    ekran boyu (kaynaklar §4.1 1920×1080) 1280×720 olmalı ve oynatıcıda çözünürlük üst sınırı 720p verilmeli.
- Veri dosyaları: yerleşik oyun paketleri kaldırıldı (paketler /v1/packs ile havuzdan iner); glossary-en-tr.json, test vektörleri
  ve deneme paketleri tools/gen-vectors.py ile kendi örneklerimizden yeniden üretildi; ai-models.json yeniden yazıldı. Kullanıcının
  oyun kareleri, görseller, OFL yazı tipleri, Samsung CA pem'leri (Tizen'den).

## DENENMEDİ (dürüst not)
Mac'te yalnız derlendi ve mantık testleri koştu. Şunlar Windows'ta hiç çalıştırılmadı: WPF pencerelerinin görünüşü ve
davranışı, DPAPI, Windows OCR ve yazım denetimi, pencere/kart yakalama, güvenlik duvarı (COM `dynamic` ile — ilk bakılacak yer),
Velopack, kısayollar, WebView2 PSN girişi, nino_native.dll (MSYS2 betiği yazıldı, denenmedi). Gerçek PS5/TV ile hiçbir şey
denenmedi. "Eskisiyle pencere pencere aynı" tariflere göre yazıldı ama gözle karşılaştırılmadı.

## Nasıl denenir (Windows 11 makinesinde)
1. `native/scripts/build-windows-msys2.sh` ile `nino_native.dll` derle (MSYS2 MinGW64; FFmpeg betiği `build-ffmpeg.sh`).
2. `dotnet build apps/windows/src/Nino.App -c Release` (ya da `dotnet publish -r win-x64`), DLL'i çıktının yanına koy.
3. Ekran karşılaştırması: eski `Nino.exe --render-screens <klasör>` ve yeni `Nino.exe --render-screens <klasör>` çıktılarını yan yana
   koy (açık + koyu tema, ~30 ekran).
4. Eski kurulumu olan bir kullanıcıda aç: ayarlar, PS5 eşleşmesi (secure.dat) ve TV kendiliğinden gelmeli; yeniden eşleştirme istememeli.
5. Eski TV uygulaması (8787) ve yeni TV uygulamaları (47800) ile altyazı gelmeli.
6. Testler: `dotnet test apps/windows/Nino.Windows.slnx`; köprü testleri için `NINO_NATIVE_LIBRARY`, model testleri için `NINO_TEST_MODELS`.

## Doğrulama araçları (depo dışı yedek)
- ~/NinoYedek/windows-dogrulama/: uyum kâhini (oracle/: eski windows/src'yi çağıran deneme programı; eski klasör silinirse git
  geçmişindeki windows/ ile çalışır), benzerlik ölçerleri (shingle.py, shingle2.py, sh3.py; %0,79 bununla ölçüldü), Mac'in tarama betiği.
- ~/NinoYedek/tarif-arsiv/windows/: tariflerin alıntılı ilk hâli.
- Ölçüm olayları sunucunun doğrulayıcısıyla (nino-pool/src/events.js) karşılaştırıldı: tüm kodlar, via/proto/brand değerleri ve ölçüm adları geçerli.

## Gözden geçirilmesi gerekenler (sabah)
- 12 dildeki metinler (her dilde ~560–720 değer) eski metinlerden bağımsız olsun diye makineyle yeniden yazıldı; yalnız anahtar ve
  yer tutucu testleri var. Türkçe "siz" hitabıyla tutarlı (taramayla denetlendi), ama bir kez göz atılmalı. Diğer diller gözden geçirilmedi.
- Yeni genel sözlük (glossary-en-tr.json: 26 terim, 61 hazır satır, argo kuralları) makineyle yazıldı, gözden geçirilmedi.

## Bilinen eksikler
- [x] Türkçe belirteçleyici gerçek source.spm + vocab.json ile (sabit revizyon, SHA doğrulamalı, yalnız scratchpad'e indirildi) sınandı: depodaki
      test ve arşivdeki 13 satırlık Hugging Face başvuru tablosu birebir tuttu. Türkçe modelin kendisi (CT2, ~475 MB) indirilmedi; çeviri denenmedi.
- [ ] Sözlük izi Windows'ta yeni (`gcf7f6091`); Mac/iPhone/Android hâlâ eski izi kullanıyor — önbellek anahtarları platformlar arasında ayrıştı.
- [ ] Ana depodaki dist/tv-app'te eski adlı TV paketleri var; yeni TV uygulamaları üretilince değiştirilmeli (worktree'de yok).
- [ ] Xbox köprüsü ve Xbox yayını kapalı (sona bırakıldı; eski xbox-bridge npm paketleri için karar gerek).
- [ ] Takion riski: eski chiaki yaması (kapanan bağlantıya paket gönderme koruması) yok; köprü kendi tarafını koruyor, PS5'le durdurma denenmeli.
- [ ] remoteplay.log zaman damgası: kimlikler-veri §8 ile kaynaklar §1.9 çelişiyor; §1.9'a uyuldu.
- [ ] Koyu temalı telefon karesi (`gta6-telefon-koyu-rydeme`) Mac'in JPG çözücüsüyle bulunamıyor; Windows WIC ile denenmeli (2 test atlanıyor).
- [ ] Kart (yakalama aygıtı) kaynağının tam ekran komutu ana ekranda yok (tarif çelişkisi); `ProblemsChanged` Windows'ta dinlenmiyor (2 sn yenileme).
- [ ] `WicFrameDecoder` uygulamada kullanılmıyor; paket içe aktarma, serbest alan, PSN penceresi ekran dökümünde yok.
- [ ] "Türkçe" diyen bazı metinler (ör. cam anahtar) başka çeviri dilinde dilin adını mı göstermeli: ürün kararı.
- [ ] tools/check-headers.sh'nin "aynı satır" denetimi kaba bir sezgidir: 150 satıra kadar izin var (XAML kalıpları, tarif verileri,
      sıradan API satırları). Bazı ajanlar rastlantıyla aynı çıkan satırları yeniden biçimlendirdi; kopya değil, ama kanıt da sayılmaz.

## Kararlar
- Telefon hafızası Windows'ta eskisi gibi yalnız bellekte.
- Eski asıl uygulamanın kurulum klasörü ve exe adı LegacyNames'te (eski kodda yanlışlıkla "NinoApp" olmuştu).
- tv-baglanti.md §12: 16 KB sığdırma, mDNS + /nino/info taraması, `replaced` sonrası kendiliğinden bağlanmama, server+link birlikte, 8787'ye `stopped`.
- Çeviri: ekran çevirisinin (`translation.screen.translate`) toplu isteği gerçekten toplu; ölü /v1/lines kuyruğu yazılmadı; önbellek adları Windows biçiminde.
- Bozuk settings.json / secure.dat silinmeden önce kenara alınır (eski uygulama sessizce siliyordu).
- Linux için: FreeModelStore keepLegacyTurkish; denetleyici veri klasörünü dışarıdan alır.
