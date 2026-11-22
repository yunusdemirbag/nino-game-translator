<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Nino için Windows: üçüncü taraf bileşenler

Nino AGPL-3.0'dır (`LICENSE`, `NOTICE`). Aşağıdakiler Nino'nun yazmadığı, kendi lisanslarıyla gelen parçalardır.
Uygulama paketinde yazı tipi lisansları `Fonts\OFL-*.txt` olarak uygulamanın yanında durur.

## Veri dosyaları

| Bileşen | Kaynak | Lisans / durum | Nerede |
|---|---|---|---|
| Samsung Tizen ara sertifikaları: `author_ca.pem` (Samsung Author CA Class), `public2.pem` ve `vd_tizen_dev_public2.pem` (VD DEVELOPER Public CA Class), `vd_tizen_dev_author_ca.pem` (Samsung VD Author CA) | Samsung Electronics; Tizen Studio'dan, **değiştirilmeden** | Samsung'un herkese açık sertifikaları (yalnız açık anahtar) | `src/Nino.TvInstall/Samsung/ca/`, gömülü kaynak `SamsungCa.<ad>.pem` |
| Barlow (Bold, SemiBold) | The Barlow Project Authors, github.com/jpt/barlow | SIL Open Font License 1.1 (`src/Nino.App/Fonts/OFL-Barlow.txt`) | `src/Nino.App/Fonts/Barlow-*.ttf` |
| Nino Action (Bold, SemiBold) | Barlow Condensed'in yeniden adlandırılmış yüzleri (Barlow türevi; WPF ailesini Barlow'dan ayırsın diye) | SIL Open Font License 1.1 (`OFL-Barlow.txt`) | `src/Nino.App/Fonts/NinoAction-*.ttf` |
| Nunito (Bold, SemiBold) | The Nunito Project Authors, github.com/googlefonts/nunito | SIL Open Font License 1.1 (`src/Nino.App/Fonts/OFL-Nunito.txt`) | `src/Nino.App/Fonts/Nunito-*.ttf` |

Oyun paketi dosyaları uygulamaya gömülmez; havuzun kendi çevirilerinden sunucudan iner (`/v1/packs`). Genel sözlük
(`src/Nino.Core/Resources/glossary-en-tr.json`) ve test vektörleri Nino'nundur (`tools/gen-vectors.py`).

## Yerel köprü (`native/`)

| Bileşen | Sürüm | Lisans | Not |
|---|---|---|---|
| chiaki-ng | v1.10.1 | AGPL-3.0 (OpenSSL istisnasıyla) | Remote Play oturumu; kaynağı değiştirilmeden derlenir (`NINO_CHIAKI_DIR`), alt modülleri nanopb, jerasure, gf-complete, curl kendi lisanslarıyla. Opus kapalı. |
| FFmpeg (libavcodec, libavutil, libswscale) | 7.1.2 | LGPL-2.1 veya sonrası | Yalnız H.264 çözücü ve ayrıştırıcı; `native/scripts/build-ffmpeg.sh` kaynaktan statik derler. |
| OpenSSL | MSYS2 mingw64 paketi (derleme anındaki sürüm) | Apache-2.0 | Statik bağlanır. |
| json-c | MSYS2 mingw64 paketi | MIT | Statik bağlanır. |
| libevent | MSYS2 mingw64 paketi | BSD-3-Clause | Statik bağlanır. |
| miniupnpc | MSYS2 mingw64 paketi | BSD-3-Clause | Statik bağlanır. |

## NuGet paketleri

| Paket | Sürüm | Lisans | Ne için |
|---|---|---|---|
| SSH.NET | 2026.0.0 | MIT | LG webOS geliştirici modu kurulumu (SSH) |
| TizenSdb.Core | 1.1.9 | MIT | Samsung TV'ye sdb ile kurulum |
| Microsoft.ML.OnnxRuntime | 1.31.1 | MIT | Ücretsiz Marian modelleri (ar, hi, id, vi, nl) |
| Microsoft.ML.Tokenizers | 2.0.1 | MIT | SentencePiece belirteçleme |
| System.Security.Cryptography.ProtectedData | 10.0.0 | MIT | `secure.dat` (DPAPI) |
| Microsoft.Web.WebView2 | 1.0.3537.50 | Microsoft WebView2 lisansı (dağıtıma izinli) | PSN giriş penceresi |
| Velopack | 1.2.161 | MIT | Kurulum ve güncelleme |
| xunit | 2.9.3 | Apache-2.0 | Yalnız testler (dağıtılmaz) |
| xunit.runner.visualstudio | 3.1.4 | Apache-2.0 | Yalnız testler (dağıtılmaz) |
| Microsoft.NET.Test.Sdk | 17.14.1 | MIT | Yalnız testler (dağıtılmaz) |

## Kullanıcının bilgisayarında kurulan çalışma zamanı

Türkçe ücretsiz çeviri işçisi (`ct2\worker.py`, Nino'nun) uygulama yanındaki gömülü Python 3.12 (PSF lisansı) ile
CTranslate2 (MIT) ve sentencepiece (Apache-2.0) paketlerini kullanır.
