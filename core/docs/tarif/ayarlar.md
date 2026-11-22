# Ayarlar, veri klasörü, gizli anahtarlar

Kod: `Sources/NinoCore/Settings/`.

## Veri klasörü

`Application Support/Nino/` (iOS'ta uygulamanın kendi kabının içinde).

```
Nino/
  settings.json          ayarlar
  cache/translations.json çeviri önbelleği
  packs/                 oyun paketleri (*.ninopack.json)
  logs/                  günlükler
```

`prepare()` eksik klasörleri oluşturur, var olana dokunmaz.

## Ayar dosyası

- JSON. Bölümler: `reading`, `translation`, `display`.
- Dosyada olmayan her alan varsayılanını alır. Bilinmeyen alanlar yok sayılır.
  Böylece eski dosya yeni sürümde de açılır.
- Sınırlar: `stableFrames` ve `missingFrames` en az 1.
- Dosya bozuksa `settings.bad.json` adıyla kenara alınır ve varsayılanlarla
  devam edilir. Uygulama çökmez.
- Yazma işlemi atomiktir (yarım dosya kalmaz).
- `translation.useOnDevice` (varsayılan açık): Apple'ın cihaz içi çevirisi
  zincirin başına konur.

## Gizli anahtarlar

- Çevirmen anahtarları **ayar dosyasına yazılmaz**, Keychain'de durur.
- Servis: `com.ninotranslator.secrets`. Hesap: `provider.<sağlayıcı adı>.key`.
- Erişim: `AfterFirstUnlockThisDeviceOnly`, iCloud eşitlemesi kapalı.
- Testlerde `MemorySecretStore` kullanılır. Gerçek Keychain testi yalnız
  `NINO_KEYCHAIN_TESTS=1` ile çalışır.
