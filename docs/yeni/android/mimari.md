# Yeni Android uygulaması: mimari ve yazım kuralları

Bütün yeni kod `apps/android/` altında. Eski `nino-android/` yalnız davranışı anlamak için okunabilir; **oradan satır,
yapı, sınıf ya da fonksiyon adı kopyalanmaz.** Davranışın kaynağı bu klasördeki tarifler ve
`~/Desktop/NinoCore/docs/tarif/`.

## Modüller

| Modül | Ne | Bağımlılık |
|---|---|---|
| `:core` (`apps/android/core`) | Saf Kotlin/JVM: okuma, çeviri, paketler, havuz istemcisi, bağlantı protokolü, motor | yalnız kotlinx-coroutines |
| `:app` (`apps/android/app`) | Android uygulaması: veri, Remote Play (JNI), ML Kit, hizmet, arayüz (Compose) | `:core`, AndroidX, Compose, ML Kit |

## Paketler

- `com.ninotranslator.core.json`: küçük JSON okuyucu/yazıcı (`Json.parse`, `Json.write`).
- `com.ninotranslator.core.reading`: tarif okuma hattı (NinoCore ile aynı) **ve** eski Android hattının canlı kuralları
  (`okuma.md`). Zaman ms ile verilir; saat dışarıdan enjekte edilir (testler elle ilerletir).
- `com.ninotranslator.core.translation`: çeviri sırası, önbellekler, terimler, Türkçe düzeltme, çevrimiçi
  sağlayıcıların istek biçimleri (HTTP, kendi `HttpURLConnection` sarmalayıcısı).
- `com.ninotranslator.core.packs`: `.ninopack.json` (NinoCore) ve eski gömülü `.json.gz` paket biçimi.
- `com.ninotranslator.core.pool`: ortak havuz istemcisi.
- `com.ninotranslator.core.link`: Nino Bağlantı Protokolü (gönderici, WebSocket, HTTP).
- `com.ninotranslator.core.engine`: uçtan uca akış.
- `com.ninotranslator.mobile.data`: SharedPreferences, Keystore, dosyalar (`veri-ve-ayarlar.md`, eski veriyle uyumlu).
- `com.ninotranslator.mobile.remoteplay`: chiaki-ng JNI sarmalayıcısı, MediaCodec çözücü, PS5 bulma/eşleme/oturum.
- `com.ninotranslator.mobile.ocr`, `...translation`: ML Kit yazı tanıma ve cihaz içi çeviri.
- `com.ninotranslator.mobile.service`: ön plan çeviri hizmeti ve canlı durum.
- `com.ninotranslator.mobile.tv`: TV bulma (mDNS `_nino._tcp`, elle adres), ileride TV'ye kurulum.
- `com.ninotranslator.mobile.ui`: Compose tema, ortak parçalar, ekranlar, gezinme.

## Kurallar

- Her dosyanın başı (Kotlin, C, CMake, Gradle, XML):
  ```
  // SPDX-License-Identifier: AGPL-3.0-only
  // Copyright (C) 2026 Nino contributors
  ```
  XML'de `<!-- ... -->`, CMake/sh/properties'te `#` ile.
- Yalnız Nino adı. Eski projenin ya da yazarının adı hiçbir yerde geçmez. Eski kimlik adları yalnız
  `com.ninotranslator.mobile.data.LegacyNames` içinde, base64 kodlu durur.
- Yorumlar ve günlük iletileri Türkçe, kısa.
- Yeni üçüncü taraf kütüphane eklenmez (izin gerekir). Var olanlar: Compose BOM 2024.12.01, material3, icons-extended,
  activity-compose, core-ktx, navigation-compose, coroutines, ML Kit text-recognition 16.0.1 ve translate 17.0.3.
  Gradle çevrimdışı çalışır: `--offline`.
- Derleme: `cd apps/android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 gradle --offline <görev>`.
  Çekirdek testi: `:core:test`. Uygulama: `:app:assembleDebug` (PS5 kütüphanesi olmadan `-Pnino.skipNative=true`),
  birim testi `:app:testDebugUnitTest`.
- PS5 kütüphanesi: `scripts/build-remoteplay.sh` → `apps/android/.remoteplay/<abi>/{include,lib}` (git dışı).
- Push, uzak depo, indirme yok. Kullanıcının telefonunda `adb uninstall` yapılmaz (veri silinir).
