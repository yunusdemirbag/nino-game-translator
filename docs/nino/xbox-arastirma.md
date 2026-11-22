# Xbox desteği: araştırma ve ilk sürüm

Tarih: 16 Kasım 2026. İlk kez 0.1.8 sürümüyle yayınlandı (deneysel).

**Durum:** Kod derleniyor ve birim testleri geçiyor. Gerçek bir Xbox ile **hiç denenmedi**.

## Kısa özet

- **Android telefon:** Xbox, PS5'in yanında ikinci bir konsol türü olarak eklendi. Kullanıcı Microsoft hesabıyla
  giriş yapar (şifre yazılmaz, microsoft.com/link'te kod girilir), Xbox'ını seçer, Nino da Xbox'ın ev yayınını
  (Xbox uygulamasındaki "Uzaktan oynat" ile aynı yayın) kendisi açıp altyazıyı okur.
- **Mac (geçici çözüm):** Pencere okuma yoluna "Xbox" seçeneği eklendi. Kullanıcı Xbox'ını Mac'te Greenlight ile ya
  da tarayıcıda xbox.com/play ile açar; Nino o pencereyi okur. Mac'te Nino henüz Xbox'a **kendisi** bağlanmıyor ve
  Microsoft girişi Nino'nun içinde değil. Kendi bağlantısı kalan işlerde.
- **Yakalama kartı:** Mac/Windows (commit 35ed631) ve Android'deki (commit 1e08fb4) HDMI kart yolu Xbox'ta da çalışır.
  Hesap gerekmez. Kart metinleri artık "PS5 ya da Xbox" diyor.

## 1. Araştırma bulguları

### Açık kaynak istemciler

| Proje | Ne yapıyor | Lisans | Durum |
|---|---|---|---|
| [Greenlight](https://github.com/unknownskl/greenlight) | Mac, Windows, Linux ve Steam Deck için Xbox ev yayını ve xCloud istemcisi (Electron) | MIT | Etkin (son commit 9 Kasım 2026) |
| [xbox-xcloud-player](https://github.com/unknownskl/xbox-xcloud-player) | Greenlight'ın WebRTC oynatıcı kitaplığı (TypeScript) | MIT | Son commit Kasım 2025 |
| [xal-node](https://github.com/unknownskl/xal-node) | Microsoft/Xbox giriş kitaplığı (XAL, TypeScript) | MIT | Etkin |
| xal-rs, OpenXbox | Aynı girişin Rust ve Python sürümleri | MIT | Başvuru için |
| xbplay | Kapalı kaynak, ücretli | — | Kullanılamaz |

Greenlight ve xal-node'un MIT lisansı AGPL-3.0 ile uyumludur. Nino'da bu projelerin kodu kopyalanmadı: akış ve sabitler
okunup Kotlin'de sıfırdan yazıldı. Yine de emek ve kaynak olarak `THIRD-PARTY-NOTICES.md`'de anıldılar.

**Temiz oda kuralı:** Nino'ın (`upstream`) Xbox kodu okunmadı. Yalnız commit başlıklarından (#139 Windows Xbox,
#142 metinler, #147 telefonlarda Xbox ev yayını) onların da aynı yolu (Microsoft hesabı eşleştirme ve Xbox görüntü
aktarımı) seçtiği anlaşıldı.

### Protokol (Xbox ev yayını, "xHome")

PS5'teki gibi yerel ağda doğrudan bir protokol yok. Her şey Microsoft'un bulut sunucuları üzerinden kurulur, görüntü
ise WebRTC ile gelir (ev ağındaysa doğrudan konsoldan).

1. **Microsoft girişi (cihaz kodu):** `login.microsoftonline.com/consumers/oauth2/v2.0/devicecode`. İstemci kimliği
   `1f907974-e22b-4810-a9de-d9647380c97e`, kapsam `xboxlive.signin openid profile offline_access`. Telefon bir kod
   gösterir, kullanıcı microsoft.com/link'te kodu girer, telefon `/token` adresini yoklar. Sonuçta uzun ömürlü bir
   yenileme jetonu (refresh token) gelir; yalnız bu saklanır.
2. **Xbox Live kullanıcı jetonu:** `user.auth.xboxlive.com/user/authenticate` (`RpsTicket = "d=" + erişim jetonu`).
3. **XSTS jetonu:** `xsts.auth.xboxlive.com/xsts/authorize`, `RelyingParty = http://gssv.xboxlive.com/`.
4. **Yayın jetonu:** `xhome.gssv-play-prod.xboxlive.com/v2/login/user`, `offeringId = xhome`. Yanıtta `gsToken` ve
   bölge sunucuları var (`isDefault` olan seçilir, ör. `https://uks.core.gssv-play-prodxhome.xboxlive.com`).
5. **Konsollar:** `GET /v6/servers/home`: ad, `serverId`, tür (XboxSeriesX…) ve güç durumu (`On`, `ConnectedStandby`, `Off`).
6. **Oturum:** `POST /v5/sessions/home/play` (`serverId`, `nanoVersion: V3;WebrtcTransport.dll`). Ardından `…/state`
   yoklanır: `Provisioning` → `ReadyToConnect` → `Provisioned` (ya da `Failed`). `ReadyToConnect`'te
   `login.live.com/oauth20_token.srf` adresinden aktarım jetonu (`PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN`) alınıp
   `…/connect`'e gönderilir.
7. **WebRTC:** Ses ve görüntü alıcısı (Nino'da ikisi de yalnız alır), dört veri kanalı (`chat`, `control`, `input`,
   `message`). Teklif SDP'si `…/sdp`'ye gönderilir, yanıt hazır olana kadar (204 gelmeyene kadar) yoklanır. ICE adayları
   `…/ice`'a gönderilir, konsolun adayları aynı yerden alınır. Konsolun Teredo (2001::/32) IPv6 adreslerinin içindeki
   gerçek IPv4 adresi ve portu çıkarılıp ayrıca eklenir. Görüntü yalnız H.264'tür (yüksek profil tercih edilir).
8. **Kanal el sıkışması:** `message` kanalı açılınca `Handshake` gönderilir; `HandshakeAck` gelince `control`
   kanalına yetki isteği (sabit erişim anahtarı) ve "kol takıldı/çıktı" çifti, `input` kanalına 15 baytlık istemci bilgisi
   paketi, `message` kanalına ekran ayarları (1920×1080) gider.
9. **Canlı tutma:** 30 saniyede bir `…/keepalive`. Kapanışta `DELETE` ile oturum bırakılır.

### Gecikme

Altyazı okumak için gecikme önemli değil: Nino saniyede birkaç kare okur ve çeviri zaten yarım saniye ile birkaç saniye
arası sürer. Topluluk ölçümlerine göre ev ağında ev yayını gecikmesi 30 ile 80 ms arasında. Bulut sunucuları yalnız
oturumu kurar, görüntü ev ağında doğrudan konsoldan gelir. Asıl yük görüntüyü çözmek: telefonda donanım H.264 çözücüsü
kullanılır, Nino her 100 ms'de bir kareyi işler.

### Yakalama kartı

Kart yolu konsoldan bağımsız: kart HDMI'dan ne gelirse okur. Xbox oyunlarda genellikle HDCP kullanmaz (PS5'teki gibi
HDCP'yi kapatmak gerekmez). Bu, gerçek kartla doğrulanmalı.

## 2. Seçilen yol

### Android (`nino-android`)

- **Görüntü kaynağı:** `VideoSource.XBOX` eklendi (PS5 Remote Play, Xbox, Yakalama Kartı). Kurulumun ilk adımında
  yeni "Hangi Konsolda Oynuyorsunuz?" ekranı (PS5 / Xbox) çıkıyor. Ayarlar › Görüntü Kaynağı'nda üç seçenek var.
- **Giriş:** `xbox/XboxAuth.kt` cihaz kodu girişini, yenilemeyi, XSTS'yi ve xHome jetonunu yapar. Yenileme jetonu
  `SecretStore`'da (Android Keystore, AES-GCM) şifreli duruyor. Seçilen Xbox ayarlarda kayıtlı.
- **Oturum:** `xbox/XboxApi.kt` (uç noktalar), `xbox/XboxSessionFlow.kt` (sıra, el sıkışma mesajları),
  `xbox/XboxStreamSession.kt` (Google'ın libwebrtc'si, `io.github.webrtc-sdk:android:125.6422.07`, BSD-3).
  `FrameSource` arayüzünü uyguluyor. Bağlantı koparsa PS5'teki gibi 2, 4, 8… en çok 30 sn arayla yeniden deneniyor.
- **Okuma hattı:** WebRTC kareleri `android.media.Image` değil. Bu yüzden `SubtitleReader.copyLuma(...)` eklendi: I420
  karenin parlaklık düzleminden altyazı bölgesini kopyalıyor. Eski `copyRegion(Image)` da artık bunu kullanıyor
  (davranışı aynı). `TranslationService` Xbox'ta PSN, PS5 eşlemesi ve chiaki kitaplığı aramıyor.
- **Arayüz:** `ui/XboxScreens.kt`: konsol seçimi ve Xbox kurulumu (üç adım satırı, büyük giriş kodu, "Kodu Kopyala ve
  Sayfayı Aç", konsol listesi, çıkış). Ana ekranda kısa yol "Xbox" yazıyor, eşlenmemişse başlık "Xbox'ınızı Bağlayın".
  Bütün metinler Türkçe (`values`) ve Arapça (`values-ar`).
- **Nino yalnız izler:** ses telefondan çalmaz, mikrofon açılmaz, kol girişi gönderilmez.
- **Boyut:** WebRTC APK'ya yaklaşık 11 MB (sıkıştırılmamış, yalnız arm64) ekliyor.

### Mac (`mac/`), geçici

- `GameConsole` ayarı (`ps5` / `xbox`, `core/.../AppSettings.swift`; eski kayıtlar PS5 açılır).
- Hoş geldin ekranına "Xbox'ta oynuyorum" kısa yolu eklendi: PS5 adımları atlanıyor, pencere okuma yolu Xbox için açılıyor.
- `GameWindowPicker.pick(_:target:)`: Xbox'ta Greenlight penceresini ya da başlığında "Xbox" geçen tarayıcı
  penceresini (Safari, Chrome, Edge, Arc, Firefox, Brave, Opera, Vivaldi) seçiyor.
- Ayarlardaki görüntü kaynağı kartında, pencere yolu seçiliyken PS5 / Xbox seçimi var.
- Metinler `Localizable.xcstrings`'de Türkçe ve Arapça.

Neden geçici: Mac'te kendi xHome istemcimizi yazmak için ya WebRTC.framework gömmek (büyük, imza işi) ya da WKWebView
içinde kendi JS oynatıcımızı çalıştırıp kareleri dışarı almak gerekiyor. İkisi de ayrı bir iş. Bu sürümde kullanıcının
zaten kullanabileceği iki ücretsiz yol (Greenlight ve xbox.com/play) okunuyor.

### Windows (`windows/`), pencere yolu

- Hoş geldin ekranına "Xbox'ta oynuyorum" düğmesi eklendi (`UseXboxWindowSetup`). PS5 adımları atlanıyor, TV adımı soruluyor.
- `GameConsole` ayarı (`Ps5` / `Xbox`, eski kayıtlarda PS5).
- `GameWindowRules.Pick(_, GameConsole.Xbox)` şu pencereleri seçiyor:
  - Microsoft'un Xbox uygulaması (`XboxPcApp`, "Uzaktan oynat"),
  - Greenlight,
  - başlığında "Xbox" geçen tarayıcı penceresi (Chrome, Edge, Firefox, Brave, Opera, Vivaldi, Arc).
- WPF projesi (`Nino.App`: XAML ve `GameWindowCapture.cs`) Mac'te derlenemedi. Değişiklik küçük, ama Windows'ta bir
  kez derlenmeli.

### Pencere yolunda altyazının yeri (Mac ve Windows)

PS5'te pencere yolu "oyun bu bilgisayarda" demekti, altyazı yalnız pencerenin üstünde çıkıyordu. Xbox'ta oyun çoğu zaman TV'de
oynanıyor; yayın penceresi yalnız görüntünün kaynağı. Bu yüzden Xbox penceresinde altyazı seçilen yere gidiyor: TV
(varsayılan) ya da "TV'm yok" seçilirse bilgisayarda, pencerenin üstünde (`usesXboxWindow` / `UsesXboxWindow`).

### Mac: Nino'nun kendi bağlantısı ertelendi

Kullanıcı kararı (16 Kasım): Mac ve Windows'ta önce pencere yolu kullanılacak. Kendi bağlantı, telefonun kendi bağlantısı
gerçek Xbox'ta doğrulanınca yazılacak. Yarım kalan Swift protokol taslağı (WebRTC.framework, stasel/WebRTC 140.0.0 için)
oturum notlarında saklı (`xbox-mac-yerel/XboxProtocol.swift`). Dalda değil.

## 3. Kalan işler

1. **Gerçek Xbox ile deneme** (en önemlisi, kullanıcıda): Android'de giriş, konsol listesi, oturum ve görüntü.
   Deneme listesi aşağıda.
2. **Mac'te Nino'nun kendi Xbox bağlantısı:** Android'deki protokol katmanının Swift'e aktarılması, Microsoft girişi
   ekranı, `StreamControlling` uygulayan bir `XboxStream` (WebRTC.framework ya da WKWebView + JS oynatıcı).
3. **iPhone (`nino-ios`) ve Windows:** Aynı protokol. Windows'ta .NET için WebRTC kitaplığı (ör. SIPSorcery,
   BSD-3) düşünülebilir. iPhone'da WebRTC.framework.
4. **Konsolu uyandırma:** Konsol `Off` ise yayın açılmaz. `ConnectedStandby` (Anında açılma) durumunda oturum konsolu
   uyandırmalı, bu denenmedi. Gerekirse SmartGlass "power on" çağrısı eklenebilir.
5. **Oturum yarışı:** Xbox'ta aynı anda tek ev yayını oturumu var. Kullanıcı telefonda Xbox uygulamasıyla oynuyorsa
   Nino'nun oturumu onu düşürebilir. Hata metni bunu söylemeli (şimdilik genel "Xbox yayını başlatmadı").
6. **`Failed` ayrıntıları:** Microsoft'un hata kodları (`errorDetails.code`) ayrı ayrı Türkçe anlatılabilir.
7. **Yeniden müzakere:** Konsol sohbet (chat) için ikinci bir SDP teklifi gönderebilir. Nino şimdilik bunu
   yanıtlamıyor. Görüntüyü etkilemiyorsa gerek yok.
8. **TV, iPhone ve web sitesi:** Kurulum rehberinde ve sitede Xbox anlatımı.

## 4. Riskler

- **Başkasının istemci kimliği:** Nino, Xbox uygulamalarının herkese açık istemci kimliğini kullanıyor (xal-node ve
  Greenlight de öyle). Microsoft bunu değiştirir ya da engellerse giriş durur. Kendi Azure uygulamamız Xbox Live
  kapsamlarına izin almadan çalışmaz.
- **Sabitler:** Kontrol kanalının erişim anahtarı, cihaz bilgisi (`X-MS-Device-Info`, "Microsoft.GamingApp" gibi
  davranıyor) ve el sıkışma mesajları Greenlight'tan alındı. Microsoft resmi bir belge yayınlamıyor, değişirse bozulur.
  Greenlight etkin olduğu için değişiklikler oradan izlenebilir.
- **Kullanım koşulları:** Resmi olmayan bir istemci Microsoft'un koşullarına aykırı sayılabilir. Bu yüzden Nino Xbox'ı
  yalnız okur, kol girişi göndermez. Mağaza incelemesinde sorun çıkabilir, Xbox adının ve logosunun kullanımına dikkat
  edilmeli. Uygulamada Xbox logosu yok, yalnız genel kol simgesi var.
- **Oyuncuya etkisi (denenmedi):** Ev yayını açılınca konsol TV'deki görüntüyü sürdürür mü, yoksa TV'de "uzaktan
  oynatılıyor" gibi bir durum mu olur? Nino'nun gönderdiği "kol takıldı/çıktı" çifti oyuncunun kolunu etkiler mi?
  Microsoft'un istemcisi bunu gönderdiği için yayının başlaması buna bağlı olabilir.
- **Aynı hesap mı, ikinci hesap mı:** PS5'te ikinci PSN hesabı gerekiyordu. Xbox'ta oyuncunun kendi Microsoft hesabıyla
  yayın açılabiliyor gibi görünüyor, ama oyun oynanırken açılan yayının oyuncunun oturumunu bozup bozmadığı bilinmiyor.
- **HDCP:** Xbox'ın oyunlarda HDCP kullanmadığı varsayıldı. Yakalama kartıyla doğrulanmalı.
- **Ağ:** Ev ağında IPv6 ya da UPnP yoksa bağlantı yalnız Teredo'dan çıkarılan IPv4 adaylarıyla kurulur. Bazı
  yönlendiricilerde başarısız olabilir.
- **Pil ve ısınma:** Telefonda sürekli 1080p H.264 çözmek PS5 yolundan farklı değil, ama uzun oturumda denenmeli.
- **xbox.com/play'de ev konsolu (Mac):** Microsoft'un tarayıcıdan ev konsoluna bağlanma özelliğinin her bölgede açık
  olduğu doğrulanmadı. Greenlight her durumda çalışır.

## 5. Denenemeyenler (kullanıcının yapacağı denemeler)

Android:

- [ ] Kurulumda konsol seçimi → Xbox → Microsoft girişi (kod, microsoft.com/link, onay) → konsol listesi.
- [ ] Listede Xbox'ın adı ve güç durumu doğru mu? "Uzak özellikler" kapalıyken liste boş mu?
- [ ] Çeviri başlatınca "Xbox'a bağlanılıyor…" → "Altyazılar okunuyor", TV'de Türkçe/Arapça altyazı.
- [ ] Bekleme modundaki (Anında açılma) Xbox uyanıyor mu?
- [ ] Oyuncu kendi koluyla oynarken bir sorun var mı (kol kopması, TV görüntüsünün değişmesi)?
- [ ] Telefonda ses çalmıyor ve mikrofon izni istenmiyor mu?
- [ ] Wi-Fi kopunca yeniden bağlanma; Microsoft girişinin süresi dolunca uyarı.
- [ ] Yakalama kartı + Xbox (USB-C), HDCP uyarısı çıkmadan görüntü.
- [ ] Arapça arayüzde yeni ekranlar (sağdan sola, taşma).
- [ ] Ayarlar › Görüntü Kaynağı'nda üç kutunun dar ekranda sığması.

Mac:

- [ ] Hoş geldin › "Xbox'ta oynuyorum" → Greenlight penceresi okunuyor mu?
- [ ] Safari/Chrome'da xbox.com/play ile ev konsolu yayını; sekme başlığında "Xbox" geçiyor mu, tam ekranda oyun alanı
      doğru kırpılıyor mu (tarayıcı araç çubuğu)?
- [ ] HDMI kart + Xbox.

## 6. Derleme ve test

- Android: `cd nino-android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=~/Library/Android/sdk gradle -Pnino.skipNative=true :app:testDebugUnitTest :app:assembleDebug`
  131 test geçti (12'si yeni: `xbox/XboxProtocolTest.kt`). Bu çalışma kopyasında `third-party/chiaki-ng` alt modülü
  boş olduğu için yerel (chiaki) derleme `skipNative` ile atlandı. Ana çalışma kopyasında tam derleme yapılmalı.
- Windows: `cd windows && dotnet test tests/Nino.Shell.Tests` → 262 test geçti (2 yeni Xbox testi);
  `tests/Nino.Core.Tests` → 625 test geçti.
- Mac: `cd mac && xcodegen generate && xcodebuild test -scheme Nino …`. Derleme başarılı. 175 testten 165'i geçti,
  2'si atlandı. Yeni Xbox testleri (`GameWindowTests.testPicksXboxStreamWindow`, `testXboxWindowSetup`) geçti. Başarısız
  10 doğrulama 8 eski testte: `ThemeTests` (3), `AppModelTests` metin testleri (2), `AppearanceTests`,
  `ComputerScreenTests`, `MainLayoutTests`. Bu testler Xbox değişikliğinden önceki commit'te (14a80b3) de aynı şekilde
  başarısız (Nino'ya geçişte değişen tema, metin ve varsayılanlar; testler güncellenmemiş). Xbox işiyle ilgileri yok.
- Çalışma kopyasında derleme için `third-party/build/CChiaki.xcframework` ve `dist/{tv-app,tv-helper,tts}` ana
  klasöre bağlandı (git'e girmeyen bağlantılar).
