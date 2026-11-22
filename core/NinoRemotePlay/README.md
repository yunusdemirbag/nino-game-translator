# NinoRemotePlay

PS5 görüntüsünü Remote Play ile alır ve NinoCore'a kare olarak verir.
AGPL-3.0-only. Üçüncü taraf bileşenler için kök klasördeki `NOTICE` dosyasına bakın.

## Kurulum

Tüm üçüncü taraf kaynaklar resmî depolarından, sabit sürümleriyle indirilir ve
kaynaktan statik olarak derlenir. Çalışırken Homebrew'a ya da başka bir kuruluma
bağlı kalınmaz. Derleme için yalnız Xcode, `cmake` ve `pkgconf` gerekir.

```bash
./scripts/fetch-deps.sh
```

```bash
./scripts/build-deps.sh
```

```bash
./scripts/build-c.sh
```

Çıktı: `Frameworks/CRemotePlay.xcframework`: macOS universal (arm64 + x86_64, Intel Mac'ler
dahil), iOS arm64, iOS simülatörü arm64. Betik her zaman dört dilimi birlikte üretir.

Başka uygulamalar aynı çerçeve yoluna bağlı. Yeni çerçeveyi önce ayrı klasörde üretip deneyin,
sonra yerine koyun:

```bash
OUT_DIR=$PWD/.build-c/out ./scripts/build-c.sh
NINO_CREMOTEPLAY_PATH=.build-c/out/CRemotePlay.xcframework swift test --scratch-path .build-c/spm-new
NINO_CREMOTEPLAY_PATH=.build-c/out/CRemotePlay.xcframework swift build --arch x86_64 --scratch-path .build-c/spm-x86
```

| Kaynak | Sürüm | Lisans |
|---|---|---|
| chiaki-ng | v1.10.1 | AGPL-3.0-only (+OpenSSL izni) |
| OpenSSL (yalnız libcrypto) | 3.5.9 | Apache-2.0 |
| json-c | 0.19 | MIT |
| libevent | 2.1.13 | BSD-3 |
| miniupnpc | 2.3.5 | BSD-3 |

## Kullanım (kütüphane)

- **Arama:** `ConsoleDiscovery().consoles()` ağın tamamına yayın yapar. `consoles(host: "192.168.0.20")`
  ya da `probe(host:timeout:)` yalnız o adrese sorar (yayın geçmeyen ağlar, elle girilen IP).
  `ConsoleInfo.macAddress`, keşifteki `hostID`'den (PS5'in MAC adresi) çıkarılır.
- **Eşleştirme:** `ConsoleRegistration.register(console:accountID:pin:)`. Elle IP için
  `ConsoleInfo(address:)` yeter; `hostID` boşsa sonuçtaki kimlik PS5'in MAC adresinden gelir.
  Hata olursa `RegistrationError` atılır: `reason` (yanlış kod, Cihaz Bağla ekranı kapalı,
  ulaşılamadı…), PS5'in kodu (`applicationReason`) ve günlük satırları (`log`).
- **Oturum:** `RemotePlaySession(address:console:options:)`. `Options.twentyPerSecond` okuma
  hattına saniyede ~20 kare verir (süreye göre seçer). PS5 giriş şifresi isterse
  `Event.loginPINRequested(incorrect:)` gelir; cevap `sendLoginPIN("1234")`. `stop()` her
  iş parçacığından, kütüphane geri çağrısının içinden de güvenle çağrılabilir.

## Deneme aracı

```bash
swift run nino-rp bul
```

```bash
swift run nino-rp kaydet 12345678 <PSN hesap kimliği>
```

```bash
swift run nino-rp izle
```

`izle`, altyazıyı okur, Türkçeye çevirir ve terminale yazar. `--tv <adres>` verilirse
TV uygulamasına da gönderir. `--ip <PS5 adresi>` aramayı tek adrese yapar.
