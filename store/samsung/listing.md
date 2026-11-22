# Samsung Seller Office: Nino Game Translator (Tizen TV)

Samsung TV Seller Office başvuru alanları için metinler. `<site>` yerine sitenin adresi yazılacak (karar bekliyor).

## Uygulama bilgileri

| Alan | Değer |
|---|---|
| Uygulama adı | Nino Game Translator |
| Tizen uygulama kimliği | `NinoTVApps.Nino` (paket `NinoTVApps`), widget kimliği `https://github.com/yunusdemirbag/nino-game-translator` (`apps/tv-web/packaging/tizen/config.xml`) |
| Sürüm | 4.5.0 |
| Paket | `nino-samsung_4.5.0.wgt` (`python3 apps/tv-web/tools/package.py`); mağazaya göndermeden önce Samsung dağıtıcı sertifikasıyla imzalanmalı |
| En düşük Tizen | 2.4 (2016 ve sonrası Samsung TV'ler) |
| Çözünürlük | 1920×1080 |
| Satıcı | Yunus Demirbağ |
| Fiyat | Ücretsiz (uygulama içi satın alma ve reklam yok) |
| Kategori (öneri) | Entertainment / Eğlence (panelde yoksa Lifestyle) |
| Yaş sınırı (öneri) | Herkes |
| Arayüz dilleri | Türkçe, İngilizce, Arapça |
| İzinler | `tv.window` (HDMI görüntüsü), `tv.inputdevice` (renkli ve rakam tuşları), `application.launch`, `internet`, `network.get` (ev ağında Nino'yu bulmak), `power` (ekranın kararmaması) |
| Gizlilik politikası | `<site>/gizlilik` |
| Destek | https://github.com/yunusdemirbag/nino-game-translator/issues |
| Kaynak kod | https://github.com/yunusdemirbag/nino-game-translator (AGPL-3.0) |
| Simge / tanıtım görseli | `icon-1920x1080.png` (logo #0B0B0F zemin ortasında, 1920×1080) |
| Ekran görüntüleri | `screenshots/tr/` ve `screenshots/en/`: `1-waiting.png`, `2-demo.png`, `3-panel.png` (1920×1080) |
| Eksik | Samsung'un istediği boylarda ayrı simge(ler) (Seller Office'te listelenen ölçüler), UX senaryo belgesi |

## Kısa açıklama

**TR:** PS5 ve Xbox oyunlarının İngilizce altyazısını TV'de, oyunun üstünde Türkçe gösterir.

**EN:** Translated subtitles for PS5 and Xbox games, shown on your TV over the game.

## Açıklama (TR)

Türkçe desteği olmayan oyunları Türkçe oynayın.

Nino Game Translator, oyunun İngilizce yazısının Türkçesini TV'de, oyunun tam üstünde gösterir. Oyunu her zamanki gibi TV'de, kendi kolunuzla oynarsınız. Çeviriyi Mac'inizde, Windows bilgisayarınızda ya da telefonunuzda çalışan ücretsiz Nino uygulaması yapar; bu TV uygulaması çeviriyi ev ağınız üzerinden alır ve okunaklı bir altyazı olarak çizer.

- Konsol görüntüsü TV'nin HDMI girişinden gelir; Nino yalnız altyazıyı ekler.
- PS5'in hangi HDMI girişinde olduğunu kendisi bulur; 1–4 tuşlarıyla değiştirilebilir.
- Altyazının yüksekliği kumandanın ok tuşlarıyla ayarlanır.
- Nino'yu beklerken kısa bir tanıtım sahnesi oynar. Mavi tuş tanıtımı, Yeşil ya da OK bilgi panelini açar.
- Hesap, reklam ve uygulama içi satın alma yoktur. Ücretsiz ve açık kaynaktır (AGPL-3.0).

Gerekenler: aynı Wi-Fi ağında açık bir Nino uygulaması (Mac, Windows, Android telefon ya da iPhone) ve PS5 için ikinci, ücretsiz bir PSN hesabı.

Nino; Sony Interactive Entertainment, Microsoft ya da Samsung Electronics ile bağlantılı değildir. PlayStation, PS5 ve Xbox sahiplerinin ticari markalarıdır.

## Description (EN)

Play games in your own language.

Nino Game Translator shows a translation of a game's English text on your TV, right on top of the game. You keep playing on your TV with your own controller. The free Nino app on your Mac, Windows PC or phone does the translation; this TV app receives it over your home network and draws it as a clear subtitle.

- The console picture comes from the TV's HDMI input; Nino only adds the subtitle.
- Finds the HDMI input your PS5 is on; switch with the 1–4 keys.
- Move the subtitle with the arrow keys on the remote.
- A short preview scene plays while waiting for Nino. Blue starts the demo; Green or OK opens the info panel.
- No account, no ads, no in-app purchases. Open source under AGPL-3.0, and free.

You need: the Nino app running on the same Wi-Fi network (Mac, Windows, Android phone or iPhone) and, for PS5, a second free PSN account.

Nino has no affiliation with Sony Interactive Entertainment, Microsoft or Samsung Electronics. PlayStation, PS5 and Xbox are trademarks of their owners.

## Anahtar sözcükler

**TR:** altyazı, çeviri, Türkçe altyazı, oyun çevirisi, PS5, Xbox, Remote Play, oyun, Nino

**EN:** subtitles, translation, translator, game translation, Turkish, PS5, Xbox, Remote Play, captions, Nino

## Bu sürümde yeni (4.5.0)

**TR:**
- TV uygulaması baştan yazıldı; Samsung ve LG'de tek, ortak uygulama.
- Nino'nun yeni uygulamalarıyla yeni bağlantı yolu; eski Nino sürümleriyle de çalışır.
- Türkçe, İngilizce ve Arapça ekran metinleri yeniden yazıldı.

(Proje sahibi denetlemeli: mağazadaki ilk sürüm olduğu için bu bölüm boş da bırakılabilir.)

**EN:**
- The TV app was rewritten; one shared app for Samsung and LG.
- New connection to the new Nino apps; older Nino versions still work.
- Turkish, English and Arabic screen texts rewritten.

## İnceleyici notu (EN)

This app is a subtitle overlay for the TV's HDMI picture. Subtitles come from the user's own Nino app (Mac, Windows,
Android or iPhone; free, open source) over the local network: the TV app finds it at `http://<ip>:47800/nino/info` and
receives lines over a WebSocket (older Nino versions: event stream on port 8787). Without it the app shows a waiting
screen with a built-in preview. Press **Blue** for demo subtitles, **Green/OK** for the info panel, **Back** to close,
**1–4** to change the HDMI input. No account, no ads, no payments. Once a day the app reports the TV's brand and model,
the app version and a random ID, plus anonymous technical measurements (launch, crash type, error codes, connection
time); no subtitle text, picture, audio or personal data is sent. Privacy policy: `<site>/gizlilik`.
