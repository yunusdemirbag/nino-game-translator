# Remote Play: kare alma

Bu adımda kod yok, yalnız tarif var. Çekirdeğin kare alma arayüzü hazır:
`FrameSource` (`Sources/NinoCore/Capture/FrameSource.swift`).

## Çekirdeğin beklediği

- `FrameSource.frames()` sırayla `Frame` (bir `CGImage`) verir.
- Tüketici yavaşsa eski kareler atılır, en yenisi tutulur (`bufferingNewest(1)`).
- Saniyede 5–10 kare yeter. Altyazı için 60 kare gerekmez; fazlası pil ve
  işlemci harcar.
- Akış bitince oturum kapanmış sayılır. `NinoEngine.run(_:)` döner.

## Kaynak: chiaki-ng

PS5 görüntüsünü almak için açık kaynak Remote Play istemcisi **chiaki-ng**
kullanılacak.

- **Kaynak:** yalnız resmî depo, `https://github.com/streetpea/chiaki-ng`.
  Eski uygulama klasöründen hiçbir dosya alınmaz.
- **İndirme (2026-11-22, kullanıcı izniyle):**
  - Sürüm: `v1.10.1`, commit `f30da0aaeb96fc0026cc03683153f682352e7d7c`.
  - `git archive HEAD | tar.gz` SHA-256:
    `067943110b413dbfd58b3998b808f0f3eb58d8105d8fcc1093afec3e8441bd53`.
  - Yer: `NinoRemotePlay/Vendor/chiaki-ng/` (209 MB, alt modüllerle).
    `.gitignore`'da; Nino deposuna girmez. Yeniden almak için:
    `git clone --depth 1 --branch v1.10.1 --recurse-submodules --shallow-submodules <resmî depo>`.
- **Lisans (okundu):** `AGPL-3.0-only` + OpenSSL ek izni (GNU AGPL bölüm 7).
  Nino da AGPL-3.0-only olduğu için birlikte dağıtılabilir; birleşik iş AGPL
  altında kalır.
  - OpenSSL ile bağlanırsa ek izin Nino kodu için de verilmeli (NOTICE'a bir
    paragraf). Bunun yerine **mbedtls** (Apache-2.0, AGPLv3 ile uyumlu)
    kullanılırsa bu gerekmez. Öneri: mbedtls.
  - Kendi telif ve lisans dosyaları olduğu gibi korunur. Bağlanınca `NOTICE`
    dosyasına "üçüncü taraf" bölümü eklenir.

## Bağımlılıklar (okundu)

Kütüphanenin C çekirdeği (`lib/`) şunlara bağlı:

| Bağımlılık | Lisans | Nereden | Durum |
|---|---|---|---|
| jerasure, gf-complete | BSD-3 | alt modül (indirildi) | hazır |
| nanopb | zlib | alt modül (indirildi) | hazır; üreteci için Python `protobuf` modülü gerekir (yok) |
| curl | curl (MIT benzeri) | alt modül (indirildi) | hazır |
| json-c | MIT | Homebrew'da 0.19 kurulu | macOS için hazır |
| OpenSSL **ya da** mbedtls | Apache-2.0 | OpenSSL 3.5 kurulu; mbedtls yok | seçim gerekli |
| libevent | BSD-3 | yok | indirilmeli |
| miniupnpc | BSD-3 | yok | indirilmeli |
| opus | BSD-3 | kurulu | gerekmez (`CHIAKI_LIB_ENABLE_OPUS=OFF`, ses alınmıyor) |

- Arayüz, oyun kumandası, FFmpeg çözücü, Steam ve Switch parçaları derlenmez
  (`CHIAKI_ENABLE_GUI/CLI/TESTS=OFF`, FFmpeg kapalı). Görüntü VideoToolbox ile
  çözülür.
- Homebrew kütüphaneleri yalnız macOS içindir. iOS için her bağımlılık
  kaynaktan iOS'a ayrıca derlenmelidir.
- Görüntü geri çağrısı (okundu): `chiaki_session_set_video_sample_cb`, imza
  `bool (*)(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)`.
  Gelen veri sıkıştırılmış video örneğidir; VideoToolbox'a verilir.

## Yerleşim

NinoCore bağımlılıksız kalır. Remote Play ayrı bir pakette durur:

```
NinoRemotePlay/          ayrı Swift paketi (NinoCore'a bağlı)
  Vendor/                indirilen kaynak, dokunulmadan
  Sources/CRemotePlay/   C kütüphanesi için modül haritası
  Sources/NinoRemotePlay/ Swift sarmalayıcı
```

- Kütüphanenin yalnız C çekirdeği derlenir (arayüz ve masaüstü kısmı derlenmez).
- macOS (arm64) ve iOS için statik kütüphane olarak derlenip XCFramework yapılır.
- Kütüphanenin kendi bağımlılıkları (şifreleme, ses çözücü, protobuf vb.)
  indirince listelenir; her biri için **ayrıca kullanıcıya sorulur**.

## Akış

1. **Bulma:** yerel ağda PS5 aranır (kütüphanenin keşif özelliği). Kullanıcı
   isterse IP'yi elle yazar.
2. **Kayıt (bir kez):** kullanıcı PS5'te "Uzaktan Oynatma → Cihaz bağla"
   menüsünden 8 haneli kodu alır. Ayrıca PSN hesap kimliği gerekir; kullanıcı
   bunu kendisi girer. Nino parola istemez, saklamaz.
3. **Kayıt bilgisi:** kayıttan dönen anahtarlar Keychain'e yazılır.
   Hesap adı: `remoteplay.<konsol kimliği>`. Ayar dosyasına yazılmaz.
4. **Oturum:** PS5 uykudaysa uyandırılır, oturum açılır.
5. **Görüntü:** kütüphane sıkıştırılmış video verir (H.264 ya da HEVC).
   Apple'ın **VideoToolbox**'u ile çözülür (`VTDecompressionSession`), çıkan
   `CVPixelBuffer` `CGImage`'a çevrilir.
6. **Seyreltme:** her N'inci kare alınır (hedef 5–10 kare/sn). İsteğe bağlı:
   kare önce küçültülür ya da yalnız altyazı bölgesi kırpılır.
7. **Kare:** `RemotePlayFrameSource: FrameSource` kareleri `AsyncStream`'e
   `bufferingNewest(1)` ile koyar.
8. **Kapanış:** oturum düşerse akış biter. Uygulama yeniden bağlanmayı önerir.

Oyun kumandası girdisi ve ses gerekmez (Nino yalnız görüntüyü izler).

## Doğrulanacaklar (indirmeden sonra)

- iOS'ta derlenebilirlik ve yerel ağ izni (`NSLocalNetworkUsageDescription`).
- Gecikme: kare yakalamadan TV'de altyazıya kadar hedef 1 saniyenin altı.

## Yapılanlar (2026-11-22)

- Bağımlılıklar kullanıcı izniyle kuruldu: libevent, miniupnpc (Homebrew),
  Python `protobuf` (yalnız `NinoRemotePlay/.tools/venv` içinde).
- **mbedtls yerine OpenSSL 3:** kütüphanenin mbedtls desteği yalnız eski 2.x
  sürümüyle derleniyor (3.x ve 4.x olmuyor). 2.x artık güncellenmiyor. Bu
  yüzden zaten kurulu olan OpenSSL 3.5 kullanıldı. OpenSSL 3 Apache-2.0
  lisanslıdır, AGPL-3.0 ile uyumludur; ek izin paragrafı gerekmez. Denenen
  mbedtls 4 ve 3 kaldırıldı.
- curl şifrelemesiz derlenir (yalnız internet üzerinden bağlantı ve PSN için
  gerekiyordu; ikisi de kapalı).
- `scripts/build-c-macos.sh`: C çekirdeğini derler, tüm statik kütüphaneleri
  `Frameworks/CRemotePlay.xcframework` içinde birleştirir.
- Swift paketi `NinoRemotePlay`:
  - `ConsoleDiscovery`: ağda PS5 bulma. **Gerçek ağda denendi, PS5 bulundu.**
  - `ConsoleRegistration`: 8 haneli kod + PSN hesap kimliğiyle eşleşme. Sonuç
    (`RegisteredConsole`) Keychain'e yazılır.
  - `RemotePlaySession: FrameSource`: oturum açar, sesi kapatır, H.264 720p
    30 kare/sn ister, her 4. kareyi okuma hattına verir.
  - `H264Decoder`: VideoToolbox ile çözme. VideoToolbox'la kodlanmış gerçek
    bir kareyle test edildi.
- `nino-rp` deneme aracı: `bul`, `kaydet`, `izle`.

## Bağımsız derleme (2026-11-22)

Kullanıcı isteğiyle tüm bağımlılıklar kaynaktan derleniyor; Homebrew
kütüphanesi kullanılmıyor.

| Kaynak | Etiket | Commit |
|---|---|---|
| chiaki-ng | v1.10.1 | f30da0aaeb96fc0026cc03683153f682352e7d7c |
| OpenSSL | openssl-3.5.9 | 45e844fa2a14ec92d146bd8f5778ac130b6625fb |
| json-c | json-c-0.19-20260627 | aa716cd8d663c976b99b0f30f102ee1d8ef63146 |
| libevent | release-2.1.13-stable | 79ddfb460847999b807cba76d04e73891f29c6ee |
| miniupnpc | miniupnpc_2_3_5 | e1db7c47295d38b2b416c892779dae9afa434016 |

- `scripts/fetch-deps.sh`: hepsini resmî depolarından bu etiketlerle indirir.
- `scripts/build-deps.sh`: OpenSSL (yalnız libcrypto; SSL, motorlar, modüller
  kapalı), json-c, libevent (şifrelemesiz), miniupnpc. Statik, macOS 14 /
  iOS 17 hedefli. Platformlar: `macos`, `ios`, `iossim` (hepsi arm64).
- `scripts/build-c.sh`: C çekirdeğini üç platform için derler, kütüphaneleri
  birleştirir, tek `CRemotePlay.xcframework` yapar. Homebrew kütüphanesi
  bulaşırsa durur.
- Derleme araçları (cmake, pkgconf, protoc) Homebrew'dan gelebilir; bunlar
  ürüne girmez. nanopb üreteci için Python `protobuf` `.tools/venv` içindedir.
- Homebrew'dan kurulan libevent ve miniupnpc artık gerekmiyor.
- **Sistem sürümü koruması:** bağımlılıklar `-Werror=unguarded-availability-new`
  ile derlenir. libevent, yalnız iOS/macOS 27'de olan `pipe2`'yi kullanıyordu;
  eski sistemde çökerdi. `EVENT__HAVE_PIPE2=OFF` ile kapatıldı.
- **Doğrulama:** NinoRemotePlay (8 test) ve NinoCore (136 test) hem macOS'ta
  hem iOS simülatöründe geçti. iOS cihaz derlemesi başarılı.

## Bilinen sınırlar

- Eşleşme ve canlı görüntü henüz denenmedi: PS5'in eşleştirme kodu ve PSN
  hesap kimliği gerekiyor.

## Sıradaki iş

1. ~~İndirme izni, indirme, özet, lisans.~~ Bitti.
2. ~~Bağımlılıklar, macOS derlemesi, paket, bulma.~~ Bitti.
3. Kullanıcıyla canlı eşleşme ve `nino-rp izle` denemesi.
4. ~~Bağımlılıkları kaynaktan derleme, iOS derlemesi.~~ Bitti.
