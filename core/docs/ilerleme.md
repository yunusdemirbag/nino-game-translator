# İlerleme

Kesilirse buradan devam edilir. Her parça bitince yerel commit atılır.

| # | Parça | Durum |
|---|---|---|
| 0 | Paket iskeleti, tarifler, okuma hattı | bitti |
| 1 | Çeviri: önbellek, terimler, Türkçe düzeltme, çevirmen zinciri | bitti |
| 2 | Oyun çeviri paketleri, bulanık eşleme | bitti |
| 3 | Nino Bağlantı Protokolü: sunucu, TV bulma, el sıkışma | bitti |
| 4 | Ayarlar, veri klasörü, Keychain | bitti |
| 5 | NinoEngine: uçtan uca akış | bitti |
| 6 | Remote Play: tüm bağımlılıklar kaynaktan; macOS + iOS; PS5 bulma çalışıyor | canlı eşleşme bekliyor |
| 7 | Son kontrol | bitti |

## Kurallar

- Eski uygulama klasörü açılmaz.
- Hiçbir şey dışarı gönderilmez (uzak depo yok).
- Her yerde yalnız Nino adı.
- Dış kütüphane eklenmez; indirme gerekirse önce kullanıcıya sorulur.

## Son kontrol (2026-11-22)

- `swift test`: 136 test, 0 hata. İsteğe bağlı 3 test (Keychain, Bonjour,
  cihaz içi çeviri) ortam değişkeniyle elle çalıştırıldı, geçti.
- Vision okuyucusu çizilmiş bir altyazı karesiyle denendi: yazı ve kutu doğru.
- `NinoSetup`: ayarlardan motor ve TV bağlantısı kurulumu; önbellek diske
  yazılıyor; canlı tutma ve yeniden bağlanma testli.
- iOS derlemesi (`generic/platform=iOS`): başarılı.
- Yasak ad taraması (`git grep`): boş.
- Tüm `.swift` dosyalarında AGPL başlığı var.
- Uzak depo yok, hiçbir şey dışarı gönderilmedi.

## Bekleyenler

- Remote Play: eşleşme için PS5 kodu ve PSN hesap kimliği gerekiyor; sonra
  `swift run nino-rp izle` ile canlı deneme.
- Vision okuyucusu gerçek oyun karesiyle denenmedi (çizilmiş kareyle denendi).
- Cihaz içi çeviri macOS 26+/iOS 26+ ister; daha eski sistemde ayarlara bir
  HTTP sağlayıcısı girilmeden çeviri olmaz.
- Uygulama arayüzleri (Mac, iPhone, TV) henüz yok.

## Değişiklik

- Dublaj çıkarıldı (kullanıcı istemedi). Ses motoru ve ayarları silindi.
