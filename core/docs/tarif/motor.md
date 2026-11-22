# NinoEngine: uçtan uca akış

Kod: `Sources/NinoCore/Engine/NinoEngine.swift`.

```
FrameSource → ReadingPipeline → Translator → SubtitleOutput (TV)
```

## Kurallar

1. Kareler sırayla okunur. Çeviri **ayrı görevde** yürür; okuma çeviriyi
   beklemez.
2. Altyazı başlayınca tüm cümleleri çevrilir. Daha önce çevrilmiş cümleler
   önbellekten gelir, yani uzayan yazıda yalnız yeni cümle çevirmene gider.
3. Çeviri geldiğinde altyazı bitmişse ya da yenisi başlamışsa sonuç **atılır**
   (`dropped`).
4. TV'ye `show(id, text, source)` gider. Altyazı bitince `clear(id)` gider.
   Gönderme sürerken altyazı biterse hemen `clear` yollanır.
5. Hiçbir cümle çevrilemezse İngilizce metin gösterilir
   (`showUntranslated = false` ise hiçbir şey gösterilmez).
6. TV'ye gönderme hatası motoru durdurmaz, `outputFailed` olayı çıkar.

## Kurulum: `NinoSetup`

Uygulamaların tek giriş noktası.

- `makeEngine(settings:directories:secrets:...)`: veri klasörünü hazırlar,
  önbelleği diskten açar, seçili oyunun paketini yükler, çevirmen zincirini
  kurar (cihaz içi + HTTP, anahtarlar Keychain'den), okuma hattını ayarlarla
  ve Vision okuyucusuyla kurar.
- `connectDisplay(settings:)`: ayarda adres varsa ona, yoksa ağda arar. Önce
  son bağlanılan TV (`lastDisplayID`) seçilir; arama süresi dolarsa görülen ilk
  uyumlu TV seçilir. Bağlanınca canlı tutma (ping + yeniden bağlanma) başlar.

## Olaylar

`subtitleStarted`, `translated`, `translationFailed`, `dropped`, `shown`,
`cleared`, `outputFailed`. Arayüz bunları `events()` akışından dinler.
