# Yeni Android uygulaması: ilerleme

Yer: `apps/android/` (Gradle; modüller `:core` saf Kotlin, `:app` Android). Eski `nino-android/` dokunulmadan duruyor.
Paket kimliği `com.ninotranslator.mobile`, veri yerleri eskisiyle aynı (bkz. `veri-ve-ayarlar.md`); yeni uygulama
eskisinin üstüne kurulunca ayarlar, PSN hesabı ve PS5 eşlemesi korunur (emülatörde denendi).

## Tarifler (bu klasörde)

`ekranlar-1.md`, `ekranlar-2.md`, `veri-ve-ayarlar.md`, `remote-play.md`, `okuma.md`, `ceviri.md`, `tv.md`,
`servis.md`, `mimari.md`, `karsilastirma.md` (eski/yeni ekran karşılaştırması).

## Özellik listesi

Durum: ✅ yazıldı ve testli · 🟡 yazıldı, gerçek cihazda denenmedi · ⬜ yapılmadı

| Özellik | Durum | Not |
|---|---|---|
| Çekirdek: okuma hattı + eski canlı kurallar | ✅ | `core/reading`, `core/reading/live` |
| Çekirdek: çeviri sırası, önbellek, sözlük, çevrimiçi sağlayıcılar | ✅ | eski önbellek dosyaları okunur |
| Paketler (havuzdan iner, eski indirilenler okunur) | ✅ | gömülü paket yok (veri kararı) |
| Ortak havuz istemcisi | ✅ | |
| TV'ye gönderim: Android TV istemcisi, web TV için 47800, eski TV'ler için 8787 | ✅ | gerçek soket testli; gerçek TV'de denenmedi |
| Veri katmanı (eski SharedPreferences/Keystore uyumlu) | ✅ | Keystore gerçek cihazda denenmedi |
| PS5 Remote Play (chiaki-ng JNI + MediaCodec) | 🟡 | emülatörde yükleniyor ve arıyor; eşleme ve görüntü gerçek PS5'le denenmedi |
| Çeviri hizmeti (ML Kit OCR + çeviri) | ✅ | emülatörde uçtan uca çalıştı |
| Arayüz: tüm ekranlar (telefon + tablet) | ✅ | eskisiyle karşılaştırma: `karsilastirma.md` |
| Yakalama kartı | 🟡 | kart yok |
| Ek alanlar, ekranı çevir | 🟡 | |
| GTA 6 telefon/harita kartı | ✅ | 22 gerçek kareyle test; emülatörde TV'ye `screen` gidiyor; 2 kare sorunlu (okuma.md sonu) |
| Xbox ev yayını | 🟡 | giriş emülatörde açıldı; yayın denenmedi |
| Telefondan TV kurulumu (Android TV, LG, Samsung) | 🟡 | sahte TV'lerle uçtan uca test; gerçek TV'ye kurulmadı (yasak) |
| Ölçüm istemcisi (olcum.md) | ✅ | gövde örnekle birebir; canlı sunucu yok |
| Nino'ya Sor, Sorun Bildir, Sistem sağlığı | 🟡 | |
| Türkçe ve İngilizce metinler | ✅ | yeniden yazıldı |
| Diğer 10 dil | ✅ | yeniden yazıldı; menü yolları bazı dillerde tahmini |

## Kullanıcı hata listesinden (22 Kasım) ve ana oturum kuralları
- TV uygulaması eskiyse kartta "Yeni Sürümü Kur": kayıtlı TV'ye tek dokunuşla kurulum; bağlanan her Nino TV'nin sürümüne bakılır.
- Eskiyen satır kuralı NinoCore adım 12 ile aynı (sabit görev yazısı altyazıyı engellemez).
- Xbox: Ayarlar'da 1080p/720p (`xboxQuality`); oturum başlatılamazsa adım adım çözüm notu.
- Oyun kimliği: sunucuya hep asıl kimlik (`gta-6`, `gta-v`); aynı oyunun eski ve havuz paketi tek kart.
- Ekran öğeleri 60 sn'de bir yeniden gönderilir (120 sn), harita kartı kalkma histerezisi.
- Ortak kalkma histerezisi (`ScreenItemBoard`): telefon paneli ve harita kartı aynı kuralla (3 okuma + 4 sn + bölge
  değişimi); telefonun eski 1,2 sn kuralı kalktı. Ölçüm/teşhis olaylarında oyun NinoCore `GameIDs.id` ile birebir aynı `GameIds.id` kimliğiyle
  (bilinen ad → asıl kimlik, yeni oyun → slug, kimliğe dönmeyen metin → alan yok); kuyruk ve havuz istekleri de aynı.
- TV ölü bağlantı: 5 sn ping, 8787'de 10 sn kalp atışı, kopma nedeni ölçüme.
- Otomatik teşhis (9 kural, `diag`). Sürüm 4.5.0 (kod 61).

## Nasıl denenir (sabah, kullanıcıyla)

Derleme (Mac'te):

```
cd apps/android
./scripts/build-remoteplay.sh            # PS5 kütüphanesi (bir kez; ~/Desktop/NinoCore/NinoRemotePlay/Vendor gerekir)
JAVA_HOME=/opt/homebrew/opt/openjdk@17 gradle :core:test :app:testDebugUnitTest :app:assembleRelease
```

**Dikkat:** sürüm imzası `~/.config/nino/android-signing.properties` ile eskisinin anahtarıyla atılmalı; bu dosya
şu an bu Mac'te YOK (klasörde yalnız `upload-mobile.keystore` ve `play-upload.env` var), dosya yoksa APK hata ayıklama
anahtarıyla imzalanır ve telefondaki Nino'nun üstüne kurulmaz. Doğru anahtar sabah kullanıcıyla belirlenecek. bu sayede yeni sürüm
telefondaki eski Nino'nun **üstüne** kurulur ve veriler kalır (eskisini kaldırmayın, veri silinir). `versionCode`
telefondakinden büyük olmalı: `-Pnino.versionCode=<sayı> -Pnino.versionName=<ad>`.

Telefonda sırayla:
1. Kurulunca uygulama doğrudan ana ekrana gelmeli (eski kurulum bitmişse); PS5 "bağlı" görünmeli.
2. Fişi tak / çeviriyi başlat → bildirim "Çeviri sürüyor"; PS5 görüntüsü gelmeli (Ayarlar › Sistem sağlığı'nda kare sayısı).
3. Oyunda altyazı çıkınca TV'de Türkçesi görünmeli. TV için:
   - **Android TV:** TV'deki **yeni** Nino TV (4.1.x, Android TV oturumu) telefonu kendisi bulur; ya da Ayarlar'dan
     TV kurulumu ile telefondan kurulur.
   - **LG/Samsung:** yeni web TV uygulaması telefona 47800'den bağlanır.
   - **Eski TV uygulamaları:** telefon 8787'de eski düzeni de sunar; eskisi gibi çalışmalı.
4. Telefon hedefi: "Altyazılar nerede" › Telefonda; telefonu yan çevirince tam ekran altyazı.
5. GTA 6: oyun içi telefon açılınca TV'de yanında Türkçe panel; haritada kart çevirisi.

Emülatörde PS5'siz uçtan uca (yalnız debug):

```
adb push <kare>.jpg /sdcard/Android/data/com.ninotranslator.mobile/files/demo-frames/
adb shell am start -n com.ninotranslator.mobile/.service.DebugDemoActivity --el holdMs 6000 --el gapMs 1500
adb forward tcp:18787 tcp:8787 && curl -sN http://127.0.0.1:18787/events     # TV'ye gidenleri izle
adb shell am start -n com.ninotranslator.mobile/.service.DebugDemoActivity --ez demo false   # durdur
```

## Denetim araçları
- `scripts/metin-benzerlik.py <depo> --min 8`: yeni metinleri eski uygulamanınkilerle 13 dilde karşılaştırır (birebir 0).
- `scripts/api-tarama.py`: derlenmiş kodu API 26 listesiyle karşılaştırır (lint saf Kotlin modülü denetlemiyor).
- `gradle :app:lintDebug` (core dahil) 0 hata.
- Debug: `adb shell am start -n com.ninotranslator.mobile/.service.DebugDemoActivity --ez rpcheck true` → günlükte
  `NinoRpCheck` (PS5 kütüphanesi yüklendi mi, arama).

## Kararlar ve farklar

- (Ana oturum, 22 Kasım) Metinler eski `strings.xml`'den alınmaz; 14 dilde aynı anlamla yeniden yazılır. Hitap: "siz".
- (Kullanıcı) Firebase ve Meta kullanılmaz. Ölçüm kendi istemcimizle (olcum.md), kapatma düğmesi yok.
- (Ana oturum) Eski yazara ait veri dosyaları kullanılmaz: paketler havuzdan iner, sözlük ve model listesi Nino'nun.
  Eski paket sunucusundan inmiş (`pool-` olmayan) paketler silinmez, okunmaya devam eder; aynı oyunun havuz paketi
  (`pool-…`) inince havuzunki kullanılır, eskisi kendiliğinden devre dışı kalır (ana oturum kararı).
- **Eskisinden farklı (bilinçli iyileştirme):** karşılamadaki "hazır paketler" sayfası yalnız çeviri hedef dili
  Türkçeyken görünür (paketler yalnız Türkçe); diğer dillerde karşılama iki sayfadır. Arayüz diline değil hedef dile bakılır.
- (Ana oturum, TV protokol kararı; `protokol-karari-tv.md`) Telefon üç yolla gönderir: Android TV'ye istemci
  (47800), web TV'ler için 47800'de sunucu (`/nino/info` role sender, `/nino/ws`), eski TV'ler için 8787.
- Tablet: eskisi gibi dikey ve tam genişlik.
- Gradle betikleri Groovy (Gradle 9.9.1'in Kotlin DSL'i çevrimdışı önbellekte olmayan Kotlin 2.4 istiyor).
- `:core` dış kütüphanesiz; kendi JSON okuyucusu, WebSocket istemci/sunucusu, HTTP sunucusu var.
- chiaki-ng ve bağımlılıkları indirilmez; NinoCore'un resmî depodan aldığı kaynaklar NDK ile derlenir; eski yamalar yok.
- Kütüphaneler ortak klasördeki `kutuphaneler.md`'de (ML Kit, webrtc-sdk, BouncyCastle, jsch, AndroidX/Compose).
