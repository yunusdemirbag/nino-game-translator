<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Linux yeniden yazımı: ilerleme

Dal `claude/yeni-linux-236454`, klasör `apps/linux/`. Tarif: `tarif.md`.

## Bitti (22 Kasım 2026)

- Davranış tarifi (`tarif.md`).
- Linux'a özgü katman, eski koddan bağımsız yazıldı; Mac'te derleniyor, **69 test** geçiyor
  (`~/.dotnet/dotnet test apps/linux/Nino.Linux.slnx`):
  - Panel sunucusu (bütün uçlar, 400/500 ayrımı, seri sıra) ve yeni panel sayfası (sihirbazın 8 adımı +
    ana ekran; eski panelde boş kalan "Daha iyi çeviri" adımı artık çevrimiçi anahtar kartını gösteriyor).
  - Seri iş sırası (`SerialWorker`), günlük (`Journal`), veri klasörü.
  - Gizli değer deposu (`secure.json`, 0600, atomik yazma, eski dosyalar okunur) ve ayar dosyası.
  - Tesseract okuyucusu: kütüphane bağlama, motor havuzu, sözcük süzgeci, satır kutuları, beyaz/ham/çevre/şerit
    okuma sırası, renkli kip, döküm, süre günlüğü. (Gerçek libtesseract ile denenmedi: Mac'te kurulu değil.)
  - PS5 günlük dosyası (`remoteplay.log`, 1 MB'de yarıya inme), `--read-raw` tanı komutu, önizleme PNG'si.
  - Dockerfile, compose.yml, build.sh, README.
  - Denetim (`apps/linux/check-headers.sh`): her dosyada SPDX + telif satırı, eski `linux/`/`windows/` bağımlılığı yok,
    eski projenin adı yok ve `copy-audit.py` ile eski Linux kodundan aynen kalan satır/metin yok (yalnız C arayüzü
    adları, rotalar, ortam değişkenleri, dosya ve adım adları gibi sözleşme gereği aynı kalanlar hariç).
- Panel Mac'te tarayıcıda açılıp bütün adım/durum birleşimleri hatasız çizildi.

## Bekleyen: ortak C# çekirdeği (yeni-windows)

Çekirdek Windows oturumunda yazılıyor (dal `claude/yeni-windows-ece87c`, `apps/windows/src/...`, düz net10.0).
Anlaşma ortak not klasöründe `linux-cekirdek-ihtiyaclari.md`. Çekirdek gelince yapılacaklar:

1. `apps/linux/src/Nino.Linux` → çekirdek projelerine `ProjectReference`.
2. `Engine/CoreBackend.cs`: `INinoBackend`'i çekirdeğin arayüzsüz denetleyicisiyle uygulamak (durum alanları
   `Ports/PanelState.cs`). `WaitingBackend` silinir.
3. Çekirdeğin bağlantılarını doldurmak: okuyucu (`TesseractReader` + `IOcrRules` uyarlayıcısı), gizli depo
   (`SecretVault`), ayar deposu (`SettingsFile<UserSettings>`), boş uyku koruyucu, TV kurulum araçları.
4. `IRawFrameServices` uyarlayıcısı (`--read-raw`), `RemotePlayJournal`'ı çekirdeğin PS5 günlük olayına bağlamak,
   `nino_native` yüklenebilirliği, `NINO_AUTOSTART`, açılış günlüğündeki "kütüphane/okuma/LG paketi" satırı.
5. Docker imajını gerçekten derlemek; şimdiye dek denenmedi. Gerekenler: çekirdek (`apps/windows/src`), yeni
   `apps/windows/native` (chiaki-ng alt modülleri `build.sh`'ta `--recursive` ile iniyor; yeni yerel kaynağın
   hangilerini istediği belli olunca kontrol edilmeli), `apps/tv-web` (başka dalda). Kök `.dockerignore` `dist` ve
   `docs`'u dışlıyor; imaj bunlara dayanmıyor.
6. Gerçek libtesseract ile deneme (Linux makinede ya da Docker'da); Mac'te Tesseract kurulu değil.

Çevrimiçi çeviri (Claude/DeepL), TV arama/eşleme/kurulum, 8787 ve 47800 sunucuları çekirdeğin işi; Linux yalnız
bağlar. Eski `linux/` klasörü silinmedi.

## Nasıl denenir

Bugünkü hâliyle (çekirdek bağlı değil) yalnız panel ve testler denenebilir:

```bash
~/.dotnet/dotnet test apps/linux/Nino.Linux.slnx
apps/linux/check-headers.sh
NINO_DATA=/tmp/nino-deneme NINO_PANEL_PORT=18788 ~/.dotnet/dotnet run --project apps/linux/src/Nino.Linux
```

Sonra tarayıcıda `http://localhost:18788`: sihirbazın ilk sayfası ve "çekirdek henüz bağlı değil" uyarısı görünür.
Çekirdek bağlandıktan sonra asıl deneme bir Linux makinesinde Docker ile yapılır (README): panelden sihirbaz → PS5
eşleme → TV → model → deneme altyazısı → çeviriyi başlat; "Bu alanı şimdi oku" ile Tesseract'ın okuduğu görülür.

Ölçüm istemcisi (olcum.md) çekirdekten bekleniyor; istek linux-cekirdek-ihtiyaclari.md'de.

## 22 Kasım sabah: çekirdeğe bağlandı

- Windows dalı (`claude/yeni-windows-ece87c`, 6567c496) bu dala birleştirildi; `apps/linux` çekirdeğin dört projesine
  (`Nino.Core`, `Nino.RemotePlay`, `Nino.Translation`, `Nino.TvInstall`) bağlı, 67 test geçiyor.
- Çekirdeğe geçenler (Linux'un kendi kopyaları silindi): gizli kasa (`FileSecretStore.ForLinux`, eski secure.json
  okunuyor), ayar dosyası (`JsonFileSettingsStore`, eski settings.json okunuyor), PS5 günlüğü
  (`RemotePlayLog`, bilgi dışı satırlar panele), ölçüm (`TelemetryClient`, platform `linux`, `/etc/os-release`).
- Okuyucu çekirdeğin kurallarını kullanıyor (`Core/CoreOcrRules.cs`): beyaz yazı süzgeci, bilineer büyütme, gürültü
  puanı, boşluk kuralı. `Core/TesseractTextReader.cs` çekirdeğin `ITextReader`'ı.
- `--read-raw` ve panelin okuma/çeviri denemeleri gerçek parçalarla (`Core/LinuxTools.cs`).
- Eski `deepLKey` içindeki Claude anahtarı açılışta `claudeKey`'e taşınır, motor ayarı Claude olur.
- Dockerfile yerel köprüyü `apps/windows/native/scripts/build-linux.sh` ile derliyor (FFmpeg statik).

### Hâlâ bekleyen
- **Denetleyici:** Windows `Nino.Shell`'de arayüzsüz denetleyiciyi yazıyor (API: `docs/yeni/windows/denetleyici-api.md`).
  Gelince `Engine/CoreBackend.cs` panel arayüzünü (`INinoBackend`) ona bağlayacak; `WaitingBackend` silinecek.
- **Türkçe ücretsiz model (çözüldü):** eski kurulumların `models/en-tr` ONNX modeli korunup kullanılıyor
  (`keepLegacyTurkish`, testli). Yeni kurulumlar CT2 modelini indirir; imaja python3 + ctranslate2 4.6.0 eklendi
  (`/app/ct2/python3` → sanal ortam). İmaj derlenmediği için bu sürüm denenmedi.
- Docker imajı ve gerçek Tesseract hâlâ denenmedi.

## 22 Kasım öğleden sonra: sağlamlaştırma

- Kapanış: denetleyici seri sırada beklenmeden kapatılır; kapanmış sıraya geç gelen işler süreci çökertmez (bu
  hata testte bulundu: test süreci çöküyordu). Denetleyici gerçek seri sırada da sınandı.
- Eski birim: test verisi `tests/Nino.Linux.Tests/Fixtures/old-linux/` eski sunucunun **kendi koduyla** üretildi
  (FileAppStore, FileSettingsStore). Yeni sunucu bunu kurulum bitmiş olarak açıyor; PS5, TV (Android TV), bölge,
  görünüm ve Claude anahtarı korunuyor.
- Docker kaynak kümesi Docker'sız denendi: Dockerfile'ın kopyaladığı yollar geçici klasöre alınıp aynı
  `dotnet publish` çalıştırıldı; `ct2/worker.py`, `tv-app/` ve linux-x64/arm64 ONNX kütüphaneleri çıktıda.
  Eksik olan `apps/windows/Directory.Build.props` Dockerfile'a eklendi.
- tv-web'in `package.py`'si (kendi dalından, geçici klasörde) `com.ninotranslator.tv_4.0.3_all.ipk` ve
  `nino-samsung_4.0.3.wgt` üretti; çekirdek bu adlardan sürümü okuyor (testli).
- 89 test geçiyor.

### Docker için bilinmesi gerekenler
- `apps/tv-web` bu dalda yok (tv-web dalında). İmajı derlemeden önce o dal birleşmeli; yoksa Dockerfile'ın
  `COPY apps/tv-web` satırı hata verir.
- Bu Mac'te Docker yok; imaj hiç derlenmedi. Yerel köprü betiği (`build-linux.sh`) Windows tarafında da denenmemiş.

## 22 Kasım akşamüstü: gerçek Tesseract ile okuma

- `apps/tv-web` dalı birleştirildi (Docker imajının TV paketi aşaması artık kaynak buluyor).
- Ana oturumun kararıyla Docker/colima kurulmadı (sanal makine kuran araç; sabah kullanıcıya sorulacak). Yerine
  `brew install tesseract` (Apache-2.0, 5.x + eng) ile Mac'te Linux kod yolu gerçek libtesseract'la denendi.
- Depodaki 22 GTA 6 karesi (`core/Tests/NinoAppCoreTests/Fixtures/gta6-*.jpg`) hem eski sunucuyla hem yenisiyle
  `--read-raw` ile okundu: **22/22 birebir aynı** (okunan satırlar ve seçilen altyazı). Örnek: beyaz altyazı karesi
  "Yeah, okay. Just wait, you're gonna lo[v]e it, we're gonna have fun." (~145 ms, 1384×379 bölge).
- Bu karşılaştırmada bir hata bulundu ve düzeltildi: tanı aracı satır kutularını bölgeye iki kez yerleştiriyordu;
  2 telefon menüsü karesinde yanlış blok seçiliyordu. Gerçek kutu değerleriyle birim testi eklendi (eski hâlde
  kırmızı, düzeltilmiş hâlde yeşil).
- Tekrar etmek için: `apps/linux/tools/gta6-karsilastir.sh` (beklenen çıktı `tools/gta6-beklenen.txt`, eski
  sunucudan). Yeni ortam değişkeni `NINO_TESSERACT_LIBRARY` (libtesseract tam yolu).
- 90 test geçiyor.

### Sabah kullanıcıya sorulacak
- Docker imajı için bu Mac'e Docker (ya da colima) kurulsun mu, yoksa imaj doğrudan Linux makinesinde mi derlensin?
  `brew install tesseract` bu Mac'e kuruldu (kaldırmak için `brew uninstall tesseract`).

## 22 Kasım akşam: temiz oda (veri-dosyalari-karari.md)

- Tarif belgelerinin önceki hâli depo dışına arşivlendi: `~/NinoYedek/tarif-arsiv/linux/` (git'te değil).
- `tarif.md`'deki eski panel/günlük metni alıntıları davranış tarifine çevrildi.
- Kopya denetimi (`copy-audit.py`) HTML şablonlarındaki iç içe tırnakları kaçırıyordu; düzeltildi. Panelde kalan
  birkaç kısa eski yazı (giriş düğmesi, kurulum hatası, kare açıklaması, iki uyarı) yeniden yazıldı.
- Mac dalının `temiz-oda-tarama.py`'si Linux ağacına uyarlanarak çalıştırıldı: yalnız "genel" (paket kimliği,
  adresler, dosya adı) eşleşmeler kaldı; bir test cümlesi değiştirildi.
- Linux ağacında eski veri dosyası (sözlük, test vektörü, gömülü paket) yok. Test verileri: eski sunucunun kendi
  koduyla üretilen secure.json/settings.json (veri biçimi, metin değil) ve kullanıcının GTA 6 karelerinin okunuşu.

## 22 Kasım gece: kullanıcı metni karşılaştırması

- `apps/linux/text-audit.py`: yeni kullanıcı metinleri (panel, komut satırı ve hata iletileri, README) eski metinlerle
  (eski Linux paneli ve kodu, eski Windows kodu + `Windows.xcstrings`, eski Mac `Localizable.xcstrings`, tüm diller)
  karşılaştırılır: birebir (12+ karakter) ve dört sözcüklük örtüşme. İlk taramada 214 örtüşme vardı; panelin bütün
  metinleri ve birkaç hata iletisi yeniden yazıldı, şimdi **0**. `check-headers.sh` bunu da çalıştırıyor.
- Karşılaştırma dışı tutulan olgular (başkasının koyduğu adlar): PS5 menü yolu (Ayarlar › Sistem › Uzaktan Oynatma ›
  Cihaz Bağla ve İngilizcesi), LG Content Store, Developer Mode, Dev Mode Status, Key Server, Host PC IP, Claude Haiku,
  "API anahtarı/API key", "TV uygulaması"; dosya, ortam değişkeni, kütüphane ve HTTP adları.
- Panel bütün adım/durum birleşimleriyle tarayıcıda hatasız çizildi. 90 test geçiyor.
