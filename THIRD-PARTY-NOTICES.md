# Third-party notices

Nino is licensed under the GNU AGPL-3.0 only (`LICENSE`, `NOTICE`). The components below were not written for Nino.
Each keeps its own copyright and license; where a license asks for its text to travel with the program, the text is
shipped next to the component (for example the font licenses `OFL-*.txt`).

## Remote Play library (Mac, iPhone, Android, Windows, Linux)

Built from unmodified upstream sources fetched by `core/NinoRemotePlay/scripts/fetch-deps.sh` (pinned versions).

| Component | Version | License | Source |
|---|---|---|---|
| chiaki-ng | 1.10.1 | AGPL-3.0 with OpenSSL linking exception | https://github.com/streetpea/chiaki-ng |
| nanopb (bundled with chiaki-ng) | as pinned by chiaki-ng | zlib | https://github.com/nanopb/nanopb |
| Jerasure, GF-Complete (bundled with chiaki-ng) | as pinned by chiaki-ng | BSD-3-Clause | https://github.com/ceph/jerasure |
| curl (bundled with chiaki-ng) | as pinned by chiaki-ng | curl license | https://curl.se |
| OpenSSL | 3.5.9 | Apache-2.0 | https://www.openssl.org |
| json-c | 0.19 | MIT | https://github.com/json-c/json-c |
| libevent | 2.1.13 | BSD-3-Clause | https://libevent.org |
| miniupnpc | 2.3.5 | BSD-3-Clause | https://github.com/miniupnp/miniupnp |

## Mac

| Component | Version | License | Source |
|---|---|---|---|
| Sparkle (automatic updates, direct-download build only) | 2.10.1 | MIT | https://github.com/sparkle-project/Sparkle |

Text recognition and on-device translation use Apple's own frameworks.

## iPhone and iPad

| Component | Version | License | Source |
|---|---|---|---|
| WebRTC for iOS (Google libwebrtc build; Xbox home streaming) | 150.0.0 | BSD-3-Clause | https://github.com/stasel/WebRTC |

## Android phone

| Component | Version | License | Source |
|---|---|---|---|
| AndroidX, Jetpack Compose, Kotlin coroutines | see `apps/android/app/build.gradle` | Apache-2.0 | https://developer.android.com/jetpack |
| Google ML Kit text recognition and translation | 16.0.1 / 17.0.3 | ML Kit Terms of Service | https://developers.google.com/ml-kit |
| WebRTC (`io.github.webrtc-sdk:android`; Xbox home streaming) | 144.7559.15 | BSD-3-Clause | https://github.com/webrtc-sdk/webrtc |
| Bouncy Castle (`bctls`, `bcpkix`, `bcprov`, `bcutil`) | 1.79 | MIT | https://www.bouncycastle.org |
| JSch (mwiede fork; LG developer-mode SSH) | 0.2.25 | BSD-3-Clause | https://github.com/mwiede/jsch |

## Windows and Linux

| Component | Version | License | Source |
|---|---|---|---|
| .NET runtime | 10 | MIT | https://github.com/dotnet/runtime |
| FFmpeg (H.264 decoder only, statically linked into `nino_native`) | 7.1.2 | LGPL-2.1-or-later | https://ffmpeg.org |
| SSH.NET | 2026.0.0 | MIT | https://github.com/sshnet/SSH.NET |
| TizenSdb.Core | 1.1.9 | MIT | https://github.com/PatrickSt1991/tizen-sdb |
| ONNX Runtime | 1.31.1 | MIT | https://github.com/microsoft/onnxruntime |
| Microsoft.ML.Tokenizers | 2.0.1 | MIT | https://github.com/dotnet/machinelearning |
| System.Security.Cryptography.ProtectedData | 10.0.0 | MIT | https://github.com/dotnet/runtime |
| Microsoft WebView2 SDK (Windows) | 1.0.3537.50 | Microsoft WebView2 license (redistributable) | https://www.nuget.org/packages/Microsoft.Web.WebView2 |
| Velopack (Windows installer and updates) | 1.2.161 | MIT | https://github.com/velopack/velopack |
| CTranslate2, sentencepiece (free Turkish translation worker) | 4.9.0 | MIT / Apache-2.0 | https://github.com/OpenNMT/CTranslate2 |
| Python embedded runtime (Windows translation worker) | 3.12 | PSF License | https://www.python.org |
| Tesseract OCR (Linux) | 5 | Apache-2.0 | https://github.com/tesseract-ocr/tesseract |
| BouncyCastle.Cryptography (used by SSH.NET) | as resolved by NuGet | MIT | https://github.com/bcgit/bc-csharp |
| Google.Protobuf | as resolved by NuGet | BSD-3-Clause | https://github.com/protocolbuffers/protobuf |
| Microsoft.Extensions.Logging/DependencyInjection.Abstractions | as resolved by NuGet | MIT | https://github.com/dotnet/runtime |
| System.Numerics.Tensors (used by ONNX Runtime) | as resolved by NuGet | MIT | https://github.com/dotnet/runtime |
| Windows SDK projection (`Microsoft.Windows.SDK.NET`, `WinRT.Runtime`) | as resolved by the .NET SDK | MIT | https://github.com/microsoft/CsWinRT |

FFmpeg is compiled from the unmodified upstream release by `apps/windows/native/scripts/build-ffmpeg.sh`; anyone can
rebuild `nino_native` with their own FFmpeg using `apps/windows/native/CMakeLists.txt`.

### Translation models downloaded on first use

| Model | License | Source |
|---|---|---|
| OPUS-MT English→Turkish (`opus-mt-tc-big-en-tr`) | CC BY 4.0, University of Helsinki | https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-tr |
| OPUS-MT English→Arabic | CC BY 4.0, University of Helsinki | https://huggingface.co/Helsinki-NLP/opus-mt-en-ar |
| OPUS-MT English→Hindi, Indonesian, Vietnamese, Dutch | Apache-2.0, University of Helsinki | https://huggingface.co/Helsinki-NLP |

## Fonts (all apps)

| Font | License | Source |
|---|---|---|
| Barlow, Barlow Condensed | SIL Open Font License 1.1, Copyright 2017 The Barlow Project Authors | https://github.com/jpt/barlow |
| Nunito | SIL Open Font License 1.1, Copyright 2014 The Nunito Project Authors | https://github.com/googlefonts/nunito |

The Windows app embeds Barlow Condensed renamed to the family "Nino Action" and static Nunito instances,
made under the same license.

## Samsung certificates

The Samsung Tizen developer CA certificates (`author_ca`, `public2`, `vd_tizen_dev_author_ca`, `vd_tizen_dev_public2`)
are Samsung Electronics' public certificates, shipped unmodified so the TV app can be signed for the user's own
Samsung TV. They are not covered by Nino's license.

## Protocol references

The Xbox home-streaming code in the Android and iPhone apps is written for Nino; the sign-in flow and streaming
messages follow the public behaviour documented by Greenlight (MIT, https://github.com/unknownskl/greenlight).
The Samsung TV install flow follows the protocol implemented by TizenSdb.Core (MIT).

## Trademarks

Nino is not affiliated with Sony Interactive Entertainment, Microsoft, LG Electronics or Samsung Electronics.
The PlayStation and PS5 marks belong to Sony Interactive Entertainment Inc. The Xbox mark belongs to the Microsoft
group of companies. The LG and webOS marks belong to LG Electronics Inc. The Samsung and Tizen marks belong to
Samsung Electronics Co., Ltd.
