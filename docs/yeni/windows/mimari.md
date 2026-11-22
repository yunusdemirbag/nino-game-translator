# Yeni Windows uygulaması: mimari ve çalışma kuralları

Amaç: `windows/` altındaki uygulamanın **aynı tasarım ve davranışla**, eski koddan tek satır almadan baştan
yazılmış hali. Yeni kod `apps/windows/` altında. Eski `windows/` klasörü yerinde kalır (silinmez), yeni koda
hiçbir bağı yoktur.

## İki aşama (temiz oda)

1. **Tarif** (`docs/yeni/windows/*.md`): eski kodu okuyan ajanlar davranışı, biçimleri, sabitleri, durumları,
   metinlerin anlamını **kod olmadan** yazar. Kod parçası, eski tanımlayıcı adı listesi, eski yorum kopyası yok;
   sayı, biçim, sıra, eşik, dosya adı, JSON alan adı (uyumluluk için zorunlu olanlar) serbest.
2. **Yazım** (`apps/windows/`): yazan ajanlar yalnız tarifleri, `~/Desktop/NinoCore/docs/tarif/*.md`,
   diğer oturumların `docs/yeni/*` belgelerini ve görselleri okur. Eski `windows/`, `linux/`, `core/`, `mac/`
   kodu **açılmaz**. Tarif yetmiyorsa eksik rapora yazılır, tarif tamamlanır.

## Katmanlar (`apps/windows/`)

```
Nino.Windows.slnx
Directory.Build.props            ortak ayarlar, sürüm, AGPL bilgisi
src/Nino.Core/                   net10.0, platformdan bağımsız (Linux da kullanır): veri, ayarlar, okuma hattı,
                                 çeviri/havuz/paket, telefon/harita, TV bağlantısı (8787 + 47800), sağlık, bildirim
src/Nino.Translation/            net10.0: yerel modeller (ONNX Marian, CT2 işçisi), DeepL/yapay zekâ çevirmenleri
src/Nino.RemotePlay/             net10.0: PS5 bulma, PSN girişi, eşleşme, yayın oturumu (yerel kütüphaneye P/Invoke)
src/Nino.Shell/                  net10.0: uygulama denetleyicisi (ekranların tek kaynağı), platform arayüzleri
src/Nino.TvInstall/              net10.0: Samsung ve Android TV'ye kurulum
src/Nino.TvHelper/               Mac'e gömülen tek dosyalık kurulum yardımcısı (AOT)
src/Nino.App/                    net10.0-windows WPF: pencereler, Windows hizmetleri (OCR, yakalama, DPAPI…)
native/                          chiaki-ng v1.10.1 üstüne ince C köprüsü (nino_native)
tests/                           xUnit; Mac'te çalışır (WPF hariç)
tools/check-headers.sh           başlık / eski ad / eski kodla aynı satır denetimi
tools/clean-room-scan.py         eski metin/veri/test dizgeleriyle ortak değer taraması (tarifler dahil)
tools/gen-vectors.py             test vektörleri, deneme paketleri ve genel sözlük üreticisi
```

Kimlikler eskisiyle aynı: çıktı `Nino.exe`, Velopack paket kimliği, veri klasörü `%LOCALAPPDATA%\Nino`,
`secure.dat` (DPAPI) — ayrıntı `kimlikler-veri.md`.

## Kurallar

- Her dosyanın başı (yorum alabilen her dosya):
  ```
  // SPDX-License-Identifier: AGPL-3.0-only
  // Copyright (C) 2026 Nino contributors
  ```
  XAML/XML/csproj'da `<!-- … -->` ile aynı iki satır.
- Eski projenin ya da eski yazarın adı hiçbir yerde geçmez. Eski adlar yalnız `LegacyNames.cs` içinde base64.
- Eski kaynak dosyalarına bağlantı (`..\..\..\mac\…`, `core/Sources/…`, `design/tokens.json`) yok. Metinler ve
  tasarım değerleri yeni dosyalarda yeniden yazılır (`apps/windows/src/Nino.Core/Resources/`).
- Metinler: tarifteki cümleler yalnız anlam içindir; kendi anahtarını ve cümleni yaz. 12 dil: tr, en, ar, bn,
  fil(tl), hi, id, ms, nl, th, ur, vi.
- Yeni NuGet paketi yok; eskinin kullandığı sürümler (yerel önbellekte var) kullanılabilir.
- Testler kullanıcının gerçek verisine dokunmaz (geçici klasör). Ağ yok.
- Commit'i ana oturum atar; ajanlar `git` ile commit atmaz.
