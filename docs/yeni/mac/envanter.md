# Özellik envanteri: eski Mac uygulaması ve eski çekirdek

Her satır bir özellik. Yeni kod tariflerden yazılır; eski kaynak dosyalarına bakılmaz.

Kısaltmalar:
- `NC/` = `~/Desktop/NinoCore/Sources/NinoCore/`, `NRP/` = `~/Desktop/NinoCore/NinoRemotePlay/Sources/NinoRemotePlay/`.

NinoCore sütunu: **var** (aynı işi görüyor), **kısmi** (temeli var, eski davranışın bir kısmı eksik), **yok**.

Öncelik: **1** = PS5 → okuma → çeviri → TV akışı için şart, **2** = ana ekranlar ve günlük kullanım, **3** = sonra.

## Bağlantı: PS5 ve Remote Play

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| PS5 bulma | Yerel ağda PS5'leri bulur, adını ve durumunu (açık/uykuda, çalışan oyun) okur | var: `NRP/ConsoleDiscovery.swift` (gerçek ağda denendi) | 1 |
| PS5 uyandırma | Uykudaki PS5'i kayıt anahtarıyla uyandırır | kısmi: `NRP/RemotePlaySession.swift`, `nino-rp` (oturum içinde) | 1 |
| PS5 eşleştirme | PS5'in "Cihazı bağla" ekranındaki 8 haneli kodla kayıt; adres süzgeci, 3 deneme | var: `NRP/ConsoleRegistration.swift` (canlı denenmedi; kayıt biçimi farklı, bkz. veri-uyumu.md) | 1 |
| PSN girişi (ikinci hesap) | Sony giriş sayfasını gömülü tarayıcıda açar, dönüş adresinden hesap kimliğini (8 bayt) alır | yok (çekirdek base64 hesap kimliği bekliyor) | 1 |
| PS5 giriş şifresi | İkinci hesabın 4 haneli PS5 şifresi; PS5 isterse oturumda gönderilir | yok | 2 |
| Remote Play oturumu | PS5'e bağlanır, H.264 görüntüyü çözer, okuma hattına kare verir; kopunca yeniden bağlanır | var: `NRP/RemotePlaySession.swift`, `NRP/H264Decoder.swift` (720p 30 fps, her 4. kare) | 1 |
| PS5 sesi | Remote Play sesini (Opus) çözer (eski dublaj ve ses izleme için) | yok (yeni oturum sesi kapatıyor) | 3 |
| PS5 adresi değişince yeniden bulma | Kayıtlı adres cevap vermezse ağda adla bulur, kaydı yeni adresle günceller | yok | 2 |
| Remote Play günlüğü | `remoteplay.log`, 1 MB döner | kısmi: `NC/Settings/NinoDirectories.swift` (`logs/` klasörü var, yazıcı yok) | 2 |
| Bilgisayarda açık Remote Play'in penceresi | Sony PS Remote Play veya chiaki-ng penceresini ekran yakalamayla okur (PS5 eşleşmesi gerekmez) | kısmi: `NC/Capture/FrameSource.swift` (yalnız arayüz) | 2 |
| HDMI yakalama kartı | Mac'e takılı karttan görüntü alır; kurulum rehberi ve canlı önizleme | kısmi: `FrameSource` arayüzü | 3 |
| Xbox | Greenlight ya da tarayıcıdaki xbox.com/play penceresini okur; Greenlight'ı indirip kurar | yok | 3 |

## Okuma (OCR) hattı

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Vision ile yazı okuma | Cihaz üstünde OCR, satırlar yukarıdan aşağı | var: `NC/Reading/VisionTextRecognizer.swift` | 1 |
| Yedek okuyucu süreci | OCR takılırsa ayrı süreçte okur (uygulama `--ocr-helper` ile açılır) | yok | 2 |
| Okunacak kareyi seçme | Bölge boş/değişmezken OCR yapılmaz; aynı anda tek kare | kısmi: `NC/Engine/NinoEngine.swift` (sırayla okur, eski kare atılır) | 1 |
| Altyazı bölgesi | Hazır seçimler (alt/üst/tam/özel), sürükleyerek ayar, canlı önizleme | kısmi: `NC/Reading/ReadingPipeline.swift` (tek dikdörtgen; hazır seçim yok) | 1 |
| Öğrenilen altyazı yeri | Oyun başına altyazı şeridini öğrenir; şeridin altını HUD sayar, öğrenince yalnız şeridi okur | yok | 1 |
| OCR gürültüsü | Süslü yazıda bozulan harfleri düzeltir, çöp satırları atar | kısmi: `NC/Reading/NoiseFilter.swift` (güven, harf oranı, bilinen arayüz yazıları) | 1 |
| Sabitleme | Aynı altyazının yeniden okumalarını, uzayan ve düzelen okumayı tanır | var: `NC/Reading/Stabilizer.swift`, `TextSimilarity.swift` | 1 |
| Cümle bölme | Çevirmene cümle cümle verir, kısaltmaları korur | var: `NC/Reading/SentenceSplitter.swift` | 1 |
| Konuşmacı adı | "ARTHUR: …" adını ayırır, çeviriye sokmaz, istenirse başa geri koyar | yok | 1 |
| Kumanda simgeleri | OCR'ın atladığı düğme simgelerini görüntüden tanır | yok | 3 |
| Vurgu renkli sözcükler | Oyunun pembe/renkli vurgusunu Türkçede aynı sözcüğe taşır | yok | 3 |
| Menü okuma | Duraklatma menüleri ve menü yazılarını altyazıdan ayırır | yok | 2 |
| Zaten hedef dilde | PS5'in Türkçe menüleri gibi zaten çevrilmiş yazıyı çevirmene göndermez | yok | 2 |
| Hızlı altyazı algılama | Değişmeyen bölgeyi en çok iki kare yeniden kullanır (ayar) | yok | 3 |
| Takılınca kendini yeniden açma | OCR kalıcı takılırsa süreç örneği alır, uygulamayı yeniden açar, çeviriyi sürdürür | yok | 2 |

## Çeviri

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Ücretsiz cihaz üstü çeviri | Apple çevirisi; dil paketi yoksa indirme ister. Kısa satır önceki cümleyle birlikte çevrilir | var: `NC/Translation/OnDeviceTranslationProvider.swift` (bağlamla çeviri yok) | 1 |
| Oyun deyimleri | "hit the deck" gibi kalıpları düz İngilizceye çevirip öyle çevirir | yok | 2 |
| Terim sözlüğü | Genel + kullanıcı sözlükleri (`Glossary/*.json`): terim, koru, tam koru, deyim, hazır satır | kısmi: `NC/Translation/Translation.swift` (`userTerms`), paket `terms` | 2 |
| Terim koruma | Terimi çeviriden korur, Türkçe ekini doğru takar | var: `NC/Translation/TermProtector.swift` (ek uyumu kısmi) | 1 |
| Türkçe son düzeltme | Cihaz çevirisinin bilinen Türkçe hatalarını düzeltir | var: `NC/Translation/TurkishPostProcessor.swift` | 1 |
| Kalıcı çeviri önbelleği | Motor ve dil çifti başına JSONL, 20 000 kayıt | var (biçimi farklı): `NC/Translation/TranslationCache.swift` | 1 |
| Oyun paketleri | Oyuna özel hazır çeviri (hash anahtarlı, gzip), bulanık eşleme, 9 yerleşik paket | kısmi: `NC/Packs/TranslationPack.swift` (yeni biçim; eski paketleri okumaz) | 1 |
| Paket güncelleme | Sunucudan yeni/güncellenen paketleri indirir, SHA-256 doğrular; günde bir ve yeni oyunda | yok | 2 |
| Paket içe aktarma | Topluluk paketini önizleyip kurar (telefonda; Mac'te kullanılmıyor) | yok | 3 |
| Nino havuzu (satır gönderme) | Pakette olmayan İngilizce satırları kalıcı kuyruğa yazar, parça parça sunucuya yollar | yok | 2 |
| Havuz çevirileri (ücretsiz zincir) | Sunucudaki çevirileri oyun başına indirir; havuz öncelikli oyunlarda (GTA 6) satırı önce havuza sorar. Sunucu tarafında ücretsiz zincir: Gemini, DeepL Free, Mistral, Groq, OpenRouter, NVIDIA, Workers AI (Claude kapalı) | yok | 1 |
| DeepL (kendi anahtarı) | Kullanıcının DeepL anahtarıyla çeviri; terimler etiketle korunur | kısmi: `NC/Translation/HTTPTranslationProvider.swift` (genel HTTP) | 2 |
| Gemini / OpenAI / Claude (kendi anahtarı) | Yapay zekâ çevirisi, model listesi `ai-models.json`, dakikalık istek sınırı | kısmi: genel HTTP sağlayıcı + `ProviderChain.swift` | 2 |
| Yerel model: Ollama veya LM Studio | Bilgisayardaki modelle çeviri; önerilen modeli Ayarlar'dan indirir | kısmi: genel HTTP sağlayıcı | 3 |
| Çevirmen zinciri ve yedek | Çevrimiçi motor olmazsa ücretsiz çeviriye düşer; hata durumunu ana ekranda gösterir | var: `NC/Translation/ProviderChain.swift` (3 hata → 60 sn dinlenme) | 1 |
| Anahtar deneme | Girilen anahtarı dener, sonucu söyler | yok | 2 |
| Hedef dil | 11 çeviri dili (tr, ar, hi, id, th, vi, ur, bn, ms, tl, nl); arayüz dili çeviri dilini izler; ilk açılışta sistem dili | kısmi: `NC/Settings/NinoSettings.swift` (`targetLanguage` alanı) | 2 |
| Sağdan sola | Arapça/Urduca çeviri ve arayüz sağdan sola | yok | 2 |

## Ekrandaki diğer yazılar

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Ekranı çevir | Kısayolla bütün kare okunur, gruplara ayrılır, her grup yerinde çevrilir | yok | 2 |
| Ek alanlar | En çok 3 sürekli okunan alan (görev, bildirim, telefon); TV'de kendi kutusunda | yok | 3 |
| Köşe yazıları | Sol üstteki ipucu/görev kutusunu kendiliğinden çevirir; haritadaki yer adlarını ayırır | yok | 2 |
| Mesaj kartı | Telefona gelen mesaj kartını (gönderen + mesaj) altyazıdan ayırıp çevirir | yok | 3 |
| Telefon kartı (GTA 6) | Oyundaki telefonu bulur, takip eder, sohbet mesajlarını telefonun yanında balonlarla çevirir; çeviriler diske yazılır | yok | 3 |
| Telefon araması | "X aranıyor" yazısını eğik sade yazıyla çevirir | yok | 3 |
| Harita kartı (GTA 6) | Haritada seçili görevin kartını oyunun kartı gibi çevirir | yok | 3 |
| Buzlu zemin ve akıllı koyuluk | Altyazının arkasını bulanıklaştırıp TV'ye gönderir; sahne aydınlığına göre zemin | yok | 3 |

## Oyun tanıma

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| PS5'in bildirdiği oyun | Keşif cevabındaki çalışan oyun kimliği ve adı | kısmi: `NRP/ConsoleDiscovery.swift` | 2 |
| Paketten tanıma | Son 20 satırın 5'i aynı paketten gelince oyun o paketin oyunu | yok | 2 |
| Ekrandan tanıma (GTA 6 vb.) | Oyuna özgü ekran yazılarından, sunucuya sormadan tanır | yok | 2 |
| Oyuna sor kartı | Oyun tanınmazsa 2 dk sonra oyunu soran kart (`sheets.game.title`); seçim PS5 adına göre hatırlanır | kısmi: `NC/Settings/NinoSettings.swift` (`selectedGameID`) | 2 |
| Oyuna özel fon | Salon sahnesinde tanınan oyunun buzlu fonu; kullanıcı `Covers/` klasörüne görsel koyabilir | yok | 3 |

## TV ve çıktı

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Altyazı sunucusu (8787, SSE) | TV'lerin ve OBS'nin bağlandığı sunucu; stil, altyazı, ekran, bölge olayları | kısmi: `NC/Link/*` (yeni protokol, TV dinler; eski TV'lerle uyumsuz) | 1 |
| Altyazı yığını ve sarma | Önceki satır soluk kalır; uzun çeviri satırlara bölünür | yok | 1 |
| Altyazı stili ve temalar | 6 tema, 4 yazı tipi, boyut, yer, zemin, renk, rozet; TV'ye `style` olayı | kısmi: yalnız `position` | 2 |
| TV bulma | LG'yi SSDP ile, Samsung ve Android TV'yi ağ taramasıyla bulur; adres değişince yeniden bulur | kısmi: `NC/Link/NinoBrowser.swift` (Bonjour, yeni TV uygulaması için) | 1 |
| TV eşleştirme ve uygulamayı açma | LG (SSAP) ve Samsung (uzaktan kumanda soketi) ile izin alır, TV uygulamasını sunucu adresiyle başlatır, açık tutar | yok | 1 |
| TV kurulumu: LG | Geliştirici modu anahtarıyla uygulamayı kurar, sürümü okur, süreyi günde bir uzatır | yok | 2 |
| TV kurulumu: Samsung | Geliştirici modu denetimi (port 26101), eksik adımı anlatır, gömülü yardımcıyla kurar | yok | 2 |
| TV kurulumu: Android TV | ADB (port 5555) ile APK kurar, katman iznini verir | yok | 2 |
| Deneme altyazısı | Deneme altyazısı (`setup.test.line`) TV'ye gönderilir | yok | 2 |
| Bilgisayar ekranında altyazı | TV yoksa ya da istenirse her şeyin üstünde saydam pencere; tıklama geçirme | yok | 2 |
| OBS katmanı | `/obs` sayfası; yazı boyu, alt pay, zemin parametreleri | yok | 3 |
| Yayın penceresi | Şeffaflık tanımayan yayın programları için düz zeminli (yeşil/siyah/mor) pencere | yok | 3 |

## Ekranlar

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Kurulum sihirbazı | Hoş geldin → PSN girişi → PS5 eşleştirme → TV → deneme → (isteğe bağlı) daha iyi çeviri | yok | 1 |
| Ana ekran: salon sahnesi | TV, sehpa, konsol, priz; fiş takılınca çeviri başlar | yok | 2 |
| Ana ekran: cam anahtar | Ortada tek anahtar, açılınca üstte canlı TV | yok | 2 |
| Canlı altyazı ve ölçümler | Son satır, kökeni (paket/motor), süre | kısmi: `NinoEngine` olayları | 2 |
| Ayarlar | Kenar çubuklu bölümler: altyazı, alan, çeviri, TV, sağlık, sorun bildir, hakkında… | yok | 2 |
| Geçmiş | Son 200 satır, kopyalanabilir | yok | 2 |
| Sistem sağlığı | PS5 bağlantısı, görüntü akışı, çeviri sağlığı; kablo/Wi-Fi; sorun geçmişi; kayıtları dışa aktar | yok | 2 |
| Sorun bildirme | Açıklama, en çok 3 ekran görüntüsü, günlük sonları, cihaz bilgileri; sunucuya | yok | 2 |
| Otomatik sorun bildirimi | Kopmaları kullanıcı yazmadan bildirir (günde en çok 3, yalnız özet) | yok | 3 |
| Nino'ya Sor | Kurulum yardımcısı sohbeti (havuz sunucusu `/v1/assistant`), yüzen robot düğmesi | yok | 3 |
| Hakkında | Sürüm, lisans, kaynak bağlantısı | yok | 2 |
| Görünüm | Koyu/açık/sistem; tema renkleri | yok | 2 |

## Uygulama altyapısı

| Özellik | Ne yapar | NinoCore | Öncelik |
|---|---|---|---|
| Ayar kaydı ve okuma | UserDefaults `settings` blobu, hoşgörülü okuma, düzeltmeler | kısmi: `NC/Settings/NinoSettings.swift` (farklı biçim) | 1 |
| Anahtarlık | PS5 kaydı, hesap kimliği, TV anahtarları, çeviri anahtarları | kısmi: `NC/Settings/SecretStore.swift` (farklı hizmet ve hesap adları) | 1 |
| Veri klasörü ve eski klasör taşıma | `Nino` klasörü; eski addan taşıma ya da kopyalama | kısmi: `NC/Settings/NinoDirectories.swift` (taşıma yok) | 1 |
| Altyazı günlüğü | `altyazi.log`, 1 MB döner | yok | 2 |
| Güncelleme (Sparkle) | GitHub'daki appcast'ten güncelleme; çeviri sürerken bekler; yeniden açılınca çeviriyi sürdürür; ana ekranda bildirim | yok | 2 |
| İndirme sayacı | Ana ekranda toplam indirme sayısı (sunucu + son bilinen değer) | yok | 3 |
| Genel kısayol | ⌥⌘T ekranı çevir, ⌥⌘L tıklama geçirme; yalnız çeviri açıkken | yok | 3 |
| Admin modu | `ninoAdminMode`: açılışta kendiliğinden çeviri, debug kareleri, ayrıntılı kayıt | yok | 3 |
| Debug kareleri | 2 sn'de bir kare + bölge + kutu + çeviri; `KAYIT` ile video ve ses | yok | 3 |
| Tasarım denemesi bayrakları | `NinoFreeNav`, `NinoPreviewStep` (yalnız geliştirici derlemesi) | yok | 3 |
| Dağıtım kanalı | DMG (Sparkle, sandbox'sız) ile App Store sürümü farkları | yok | 3 |
| Dosya indirme | İlerlemeli tek dosya indirme (Greenlight, model) | yok | 3 |
| Elle adres | Kullanıcının yazdığı PS5/TV adresini temizler ("192.168.1.5:3000", tam genişlikli rakamlar) | kısmi: `NC/Link/NinoMessage.swift` (URL kurma, yerel adres denetimi) | 2 |

## Kaldırılmış (yeniden yapılmayacak)

| Özellik | Not |
|---|---|
| Dublaj (Türkçe seslendirme) | 22 Kasım 2026'da kaldırıldı. Eski ayar blobunda `dubbing`, veri klasöründe `dubbing/` kalabilir; yok sayılır |
