# App Store incelemesi: Nino Game Translator (iOS)

**Ret nedeni (0.1.4, 15 Kasım 2026):** Guideline 2.1 – Information Needed. Apple bir hata bulmadı; uygulamayı PS5
olmadan deneyemediği için bilgi ve gerçek iPhone'da çekilmiş bir ekran kaydı istedi. 0.1.5'te **PS5'siz demo modu**
eklendi (0.1.4, **yapı 2**, 16 Kasım gece yüklendi ve TestFlight'ta "Ekip" grubunda); inceleme ekibi uygulamanın ana akışını PS5 olmadan görebilir.

## Yeniden göndermeden önce (sabah, 5 dakika)

1. **Ekran kaydı çek (gerçek iPhone'da, iOS güncel):** Denetim Merkezi › Ekran Kaydı.
   1. Nino'yu kapalıyken aç (kayıt uygulamanın açılışıyla başlamalı).
   2. Karşılama sayfalarını "Devam" ile geç, sağ üstteki bayraklardan Türkçe ve Arapça'yı bir kez göster.
   3. PSN adımında "Sony İle Giriş Yapın"a dokunup Sony'nin giriş sayfasının açıldığını göster, sonra geri dön ve
      "Şimdilik Atla".
   4. Ana ekranda "PS5'siz Deneyin"e dokun. Altyazıların akışını 10 saniye göster, kaydırma çubuğunu göster,
      telefonu yan çevir (tam ekran açılır), geri dön, çubuğu geri kaydırıp demoyu durdur.
   5. Ayarlar'ı açıp çeviri dilini ve çeviri motoru seçeneklerini göster.
   6. Mümkünse gerçek PS5 ile 20–30 saniyelik canlı çeviri de ekle (PS5 eşli telefonda).
0. iPhone'a **TestFlight** uygulamasını kur, Apple hesabının e-postasına gelen daveti kabul et ve Nino 0.1.4 (2)'yi indir.
2. App Store Connect › Nino Game Translator › 0.1.4 sürümü › **Build** bölümünde yapı **2**'yi seç; **App Review Information › Notes** alanına aşağıdaki
   İngilizce metni yapıştır ve videoyu **Attachment** olarak ekle.
3. **Resubmit to App Review**'a bas.

## Notes alanına yapıştırılacak metin

```
Thank you for reviewing Nino Game Translator. Answers to the requested information:

1) SCREEN RECORDING
Attached: recorded on a physical iPhone running the latest iOS, starting from app launch and showing the full
flow (welcome, language choice, Sony sign-in page, demo session, full-screen subtitles, settings).

2) PURPOSE AND AUDIENCE
Many PlayStation 5 games have no Turkish or Arabic subtitles. Nino is a free, open-source (AGPL-3.0) accessibility
tool for Turkish- and Arabic-speaking players: the iPhone reads the English subtitles of the game the user is playing
on their own PS5 and shows them translated into Turkish or Arabic, either on the iPhone screen next to the TV or on
the user's smart TV. There are no ads, no purchases, no subscriptions and no Nino accounts.

3) HOW TO ACCESS THE MAIN FEATURES
- No PS5 is needed to review the app: on the welcome screen tap "Atla" (Skip), on the PSN step tap "Şimdilik Atla"
  (Skip for now), then on the home screen tap "PS5'siz Deneyin" (Try without PS5). A demo session starts: sample
  English game subtitles are translated and shown live; rotate the phone for full-screen subtitles; slide the bar
  back to stop. Arabic interface: tap the Saudi flag on the welcome screen (or Settings > Translation language).
- With a PS5: the user signs in with a second, free PlayStation Network account on Sony's own sign-in page, pairs the
  iPhone with their PS5 once (PS5 Settings > System > Remote Play > Pair Device, 8-digit code), and slides to start.
  The iPhone receives the PS5 picture over the home Wi-Fi using the Remote Play protocol, reads the subtitles on
  device and translates them. The user keeps playing on their TV with their own account and controller.
- No login credentials are needed for review (demo mode). Nino has no account system, so there is no account
  registration or deletion; PSN sign-in happens on Sony's page and Nino never sees or stores the password.

4) EXTERNAL SERVICES
- Sony PlayStation Network sign-in page (Sony's own web page) to obtain the user's Remote Play credentials.
- The user's own PS5 on the local network (open-source Remote Play implementation, chiaki-ng, AGPL-3.0).
- Apple's on-device Translation framework (free translation) and Apple Vision (on-device text recognition).
- Optional, only if the user enters their own API key: DeepL, Google Gemini, OpenAI or Anthropic translation.
- Nino's own server (Cloudflare Workers) to download free game translation packs, and an optional anonymous pool of
  untranslated subtitle lines (text only, no personal data; can be turned off in Settings).
- No analytics, tracking or advertising SDKs.

5) REGIONAL DIFFERENCES
The app works the same in all regions. The interface is available in Turkish and Arabic.

6) THIRD-PARTY MATERIAL
Nino is not affiliated with or endorsed by Sony Interactive Entertainment. It does not include, stream or
redistribute any game content: it only reads the subtitles of games the user already owns and plays on their own
PS5, and shows a translation privately to that user, like a reading aid. "PS5" and "PlayStation" are used only to
describe compatibility.

Source code: https://github.com/yunusdemirbag/nino-game-translator
Contact: via the support URL on the App Store page.
```

## Aynı hataya bir daha düşmemek için

- Her yeni sürümde demo modu çalışır kalmalı ve notlarda nasıl açılacağı yazmalı (inceleme ekibinde PS5 yok).
- Gerçek iPhone'da çekilmiş kısa video her gönderimde ek olarak hazır tutulsun.
- Logoda ve ekran görüntülerinde Sony'nin tescilli öğeleri (DualSense kolu, PlayStation tuş simgeleri △ ○ ✕ □,
  PlayStation logosu) kullanılmamalı; aksi halde 5.2.1 (fikri mülkiyet) reddi gelebilir. **Şu anki logoda DualSense
  kolu ve tuş simgeleri var; yayından önce markasız bir kol çizimiyle değiştirilmeli.**
- Ekran görüntüleri uygulamanın gerçek kullanımını göstermeli (yalnız açılış/giriş ekranı değil).

## Yükleme nasıl yapıldı (bir dahaki sefere)

Uygulama kişisel ekipte (2D65S2R5LX), eski kuruluş ekibinde değil; `scripts/release-appstore.sh` eski kuruluşu varsaydığı için
bu uygulamada çalışmaz. Çalışan yol (API anahtarı ve `asc.json` bu Mac'te, depoda değil):

```bash
# imzasız arşiv (otomatik imza cihaz kaydı istediği için)
xcodebuild -project nino-ios/Nino.xcodeproj -scheme Nino -configuration Release \
  -destination 'generic/platform=iOS' -archivePath dist/appstore/Nino-ios-<sürüm>-<yapı>.xcarchive \
  DEVELOPMENT_TEAM=2D65S2R5LX CODE_SIGNING_ALLOWED=NO MARKETING_VERSION=<sürüm> CURRENT_PROJECT_VERSION=<yapı> archive
# imzala ve yükle (dist/appstore/ExportOptions-upload.plist: app-store-connect, upload, 2D65S2R5LX, automatic)
xcodebuild -exportArchive -archivePath dist/appstore/Nino-ios-<sürüm>-<yapı>.xcarchive \
  -exportOptionsPlist dist/appstore/ExportOptions-upload.plist -exportPath dist/appstore/upload-ios \
  -allowProvisioningUpdates -authenticationKeyPath <AuthKey .p8> -authenticationKeyID <keyId> -authenticationKeyIssuerID <issuerId>
```
`nino-ios/Config/Secrets.xcconfig` içinde `PACKS_API_BASE_URL` boş bırakılır (paketler uygulamanın içinde).
