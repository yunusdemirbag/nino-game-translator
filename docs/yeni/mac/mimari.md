# Yeni Mac uygulaması: mimari ve iş bölümü

## Katmanlar

```
apps/mac/App/                 ince Xcode hedefi (yalnız NinoScenes'i açar)
apps/mac/NinoMacKit/          Swift paketi: bütün Mac mantığı ve ekranları
  Settings/                   MacSettings (eski `settings` kaydı), SettingsStore      [bitti]
  Model/                      AppState (ekranların tek kaynağı), AppEngine, PreviewEngine [bitti]
  Storage/                    Anahtarlık kasası, kayıtlar, veri klasörü, eski klasör taşıma
  Console/                    PS5: bulma, PSN girişi, eşleşme, Remote Play oturumu, kopma nedenleri
  Session/                    LiveEngine: kaynak → okuma → çeviri → çıkışlar
  Output/                     TV gönderimi, bilgisayardaki altyazı penceresi, yayın penceresi, OBS
  TVSetup/                    LG / Samsung / Android TV kurulumu
  UI/Design/                  renkler, yazı tipleri, ölçüler, ortak bileşenler
  UI/Home/                    ana pencere, salon sahnesi, cam anahtar, alt şerit, açılış
  UI/Settings/ UI/Setup/ UI/Sheets/ ...
  Resources/                  Assets.xcassets (kullanıcının görselleri), Fonts/ (OFL), *.xcstrings
~/Desktop/NinoCore            ortak çekirdek (iPhone da kullanır); yeni özellikler YENİ klasörlerde:
  Sources/NinoCore/Library/   eski biçimli paketler, özet anahtarı, bulanık eşleme, havuz, paket güncelleme
  Sources/NinoCore/Providers/ yapay zekâ / DeepL / yerel model çevirmenleri, istek bütçesi, sözlük, Türkçe ekler
  Sources/NinoCore/GameReading/ zengin okuma hattı (zamanlı eşikler, öğrenilen altyazı yeri, konuşan adı, menü, köşeler, kartlar)
```

## Kurallar (her ajan için)

- **Temiz oda:** yalnız `docs/yeni/mac/*.md`, görseller ve NinoCore okunur. Eski `mac/`, `core/`, `remoteplay/`,
  `nino-ios/` vb. klasörlerin kodu AÇILMAZ. Tarif yetmezse tarifin eksiğini rapora yaz.
- Her dosyanın başı:
  ```
  // SPDX-License-Identifier: AGPL-3.0-only
  // Copyright (C) 2026 Nino contributors
  ```
- Eski projenin ya da eski yazarın adı hiçbir yerde geçmez. Eski adlar gerekirse yalnız `LegacyNames` dosyasında
  base64 kodlu durur.
- **Metinler:** tarif tablolarındaki Türkçe/İngilizce metinler yalnız ANLAM içindir. Kendi anahtarını (anlamlı,
  noktalı: `home.status.connected`) ve kendi cümleni yaz. Her alan kendi tablosunu kullanır
  (`Resources/Home.xcstrings` gibi; `String(localized:table:bundle: .module)` ya da
  `Text(LocalizedStringKey, tableName:, bundle: .module)`). İlk aşamada `en` + `tr` yeterli; diğer 10 dil
  (ar, bn, fil, hi, id, ms, nl, th, ur, vi) sonda tek geçişte eklenir.
- Ekranlar yalnız `AppState` okur ve onun eylemlerini çağırır. Eksik durum/eylem gerekirse `AppStateTypes.swift`'e
  EKLE (silme, yeniden adlandırma yok) ve rapora yaz.
- Testler: kullanıcının gerçek verisine (UserDefaults `com.ninotranslator.mac*`, `Application Support/Nino*`,
  gerçek Anahtarlık) DOKUNMAZ. Geçici klasör / geçici suite / bellek kasası kullan. Ağ yok.
- Uygulamayı açma, `xcodebuild test` çalıştırma (kullanıcı oyun oynuyor olabilir). `swift build` / `swift test` serbest.
- Commit: yalnız kendi dosyaların, **açık yol** ile (`git add <yol>`; `-a`, `add -A`, `add .` YOK).
  NinoCore'da da aynı; NinoCore'u başka oturumlar da kullanıyor: var olan dosyaların davranışını değiştirme,
  gerekirse rapora öneri yaz. Push yok, uzak depo yok.
- Commit iletisi Türkçe; sonuna:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Paket yolu

`apps/mac/NinoMacKit/Package.swift`, NinoCore'u `~/Desktop/NinoCore`'dan alır (`NINOCORE_DIR` ile değişir).
