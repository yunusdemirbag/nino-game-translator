# NinoCore

Nino'nun çekirdeği. PS5 oyunlarındaki İngilizce altyazıyı okur, Türkçeye
çevirir ve yerel ağdaki TV'ye gönderir.

Ücretsiz ve açık kaynak: **AGPL-3.0-only** (bkz. `LICENSE`, `NOTICE`).

```
kare → okuma hattı → çeviri → TV
```

## Parçalar

| Parça | Kod | Tarif |
|---|---|---|
| Okuma hattı (OCR, süzgeç, sabitleyici, cümle bölücü) | `Reading/` | [okuma-hatti.md](docs/tarif/okuma-hatti.md) |
| Zamanlı oyun okuma hattı (öğrenilen yer, konuşan adı, köşeler, kartlar) | `GameReading/` | [oyun-okuma.md](docs/tarif/oyun-okuma.md) |
| Çeviri (önbellek, terimler, Türkçe düzeltme, çevirmen zinciri) | `Translation/` | [ceviri.md](docs/tarif/ceviri.md) |
| Oyun çeviri paketleri | `Packs/` | [paket.md](docs/tarif/paket.md) |
| Telefon paneli, harita kartı, GTA 6 kuralları | `Phone/` | [telefon-harita.md](docs/tarif/telefon-harita.md) |
| Eski paketler, satır anahtarı, ortak havuz, paket güncelleme, geçmiş | `Library/` | [kutuphane.md](docs/tarif/kutuphane.md) |
| Nino Bağlantı Protokolü (TV sunucusu, gönderici, TV bulma) | `Link/` | [protokol.md](docs/tarif/protokol.md) |
| Ayarlar, veri klasörü, Keychain | `Settings/` | [ayarlar.md](docs/tarif/ayarlar.md) |
| NinoEngine (uçtan uca akış) | `Engine/` | [motor.md](docs/tarif/motor.md) |
| Kare alma / Remote Play | `Capture/` | [remote-play.md](docs/tarif/remote-play.md) |

Kod `Sources/NinoCore/` altında. İlerleme: [docs/ilerleme.md](docs/ilerleme.md).

## Çalıştırma

```bash
swift test
```

Ağa ya da cihaza dokunan testler isteğe bağlıdır:

```bash
NINO_KEYCHAIN_TESTS=1 NINO_BONJOUR_TESTS=1 NINO_DEVICE_TRANSLATION_TESTS=1 swift test
```

Uygulamalar `NinoSetup.makeEngine(...)` ve `NinoSetup.connectDisplay(...)` ile
başlar (bkz. [motor.md](docs/tarif/motor.md)).

Gereken: Swift 5.9+, macOS 14+ ya da iOS 17+. Dış kütüphane yok.

## Henüz yok

- Remote Play bağlantısı (tarif hazır, kütüphane indirme izni bekliyor).
- Uygulama arayüzü (Mac, iPhone, TV). Çekirdek bunlara hazır.
