# LG Content Store: Nino Game Translator (webOS TV)

Seller Lounge'daki başvuru alanları için metinler. `<site>` yerine sitenin adresi yazılacak (karar bekliyor).

## Uygulama bilgileri

| Alan | Değer |
|---|---|
| Uygulama adı | Nino Game Translator |
| Uygulama kimliği | `com.ninotranslator.tv` (`apps/tv-web/packaging/webos/appinfo.json`) |
| Sürüm | 4.5.0 |
| Paket | `com.ninotranslator.tv_4.5.0_all.ipk` (`python3 apps/tv-web/tools/package.py`) |
| Satıcı | Yunus Demirbağ |
| Fiyat | Ücretsiz (uygulama içi satın alma ve reklam yok) |
| Kategori (öneri) | Entertainment / Eğlence (panelde yoksa Lifestyle) |
| Yaş sınırı (öneri) | Herkes (uygulamada kullanıcı içeriği, sohbet, satın alma yok) |
| Arayüz dilleri | Türkçe, İngilizce, Arapça (TV uygulaması); çeviri Türkçe başta olmak üzere Nino'nun dillerinde |
| Gizlilik politikası | `<site>/gizlilik` |
| Destek | https://github.com/yunusdemirbag/nino-game-translator/issues |
| Kaynak kod | https://github.com/yunusdemirbag/nino-game-translator (AGPL-3.0) |
| Simge | `icon-400.png` (400×400) |
| Ekran görüntüleri | `screenshots/tr/` ve `screenshots/en/`: `1-waiting.png` (ana görsel), `2-demo.png`, `3-panel.png` (1920×1080) |
| Eksik | Açılış arka planı (1920×1080, LG isterse), UX senaryo belgesi, Self-Checklist (Seller Lounge şablonu) |

## Kısa açıklama

**TR:** PS5 ve Xbox oyunlarının İngilizce altyazısını TV'de, oyunun üstünde Türkçe gösterir.

**EN:** Shows translated subtitles for PS5 and Xbox games on your TV, right over the game.

## Açıklama (TR)

Nino Game Translator, Türkçe desteği olmayan oyunları Türkçe oynamanızı sağlar.

Oyunu her zamanki gibi TV'de, kendi kolunuzla oynarsınız. Mac'inizde, Windows bilgisayarınızda ya da telefonunuzda çalışan ücretsiz Nino uygulaması oyundaki İngilizce yazıyı okur ve çevirir. Bu TV uygulaması da çeviriyi ev ağınız üzerinden alır ve oyunun tam üstünde, okunaklı bir altyazı olarak gösterir.

- Konsol TV'nin HDMI girişinden gelir; Nino görüntünün üstüne yalnız altyazıyı çizer.
- PS5'in bağlı olduğu HDMI girişini kendisi bulur; kumandanın 1–4 tuşlarıyla değiştirebilirsiniz.
- Altyazının yüksekliğini kumandanın ok tuşlarıyla ayarlayabilirsiniz.
- Bağlı değilken kısa bir tanıtım sahnesi altyazının nasıl görüneceğini gösterir; Mavi tuş tanıtımı açar, Yeşil ya da OK bilgi panelini gösterir.
- Hesap, reklam ve uygulama içi satın alma yoktur. Ücretsiz ve açık kaynaktır (AGPL-3.0).

Gerekenler: aynı Wi-Fi ağında açık bir Nino uygulaması (Mac, Windows, Android telefon ya da iPhone) ve PS5 için ikinci, ücretsiz bir PSN hesabı. Kurulum anlatımı ve indirme bağlantıları proje sayfasındadır.

Nino; Sony Interactive Entertainment, Microsoft ya da LG Electronics ile bağlantılı değildir. PlayStation, PS5 ve Xbox sahiplerinin ticari markalarıdır.

## Description (EN)

Nino Game Translator lets you play games that have no subtitles in your language.

You keep playing on your TV with your own controller. The free Nino app on your Mac, Windows PC or phone reads the English text in the game and translates it. This TV app receives the translation over your home network and shows it as a clear subtitle right on top of the game.

- The console picture comes straight from the TV's HDMI input; Nino only draws the subtitle on top.
- Finds the HDMI input your PS5 is on; switch with the 1–4 keys on the remote.
- Move the subtitle up or down with the remote's arrow keys.
- While nothing is connected, a short preview scene shows what subtitles will look like. The Blue key starts a demo; Green or OK opens the info panel.
- No account, no ads, no in-app purchases. Open source under AGPL-3.0, and free.

You need: the Nino app running on the same Wi-Fi network (Mac, Windows, Android phone or iPhone) and, for PS5, a second free PSN account. Setup guide and downloads are on the project page.

Nino has no affiliation with Sony Interactive Entertainment, Microsoft or LG Electronics. PlayStation, PS5 and Xbox are trademarks of their owners.

## Anahtar sözcükler

**TR:** altyazı, çeviri, Türkçe altyazı, oyun çevirisi, PS5, Xbox, Remote Play, oyun, çevirmen, Nino

**EN:** subtitles, translation, translator, game translation, Turkish, PS5, Xbox, Remote Play, captions, Nino

## Bu sürümde yeni (4.5.0)

**TR:**
- TV uygulaması baştan yazıldı; LG ve Samsung'da tek, ortak uygulama.
- Nino'nun yeni Mac, Windows, Android ve iPhone uygulamalarıyla yeni bağlantı yolu; eski Nino sürümleriyle de çalışır.
- Türkçe, İngilizce ve Arapça ekran metinleri yeniden yazıldı.

(Proje sahibi denetlemeli: mağazadaki ilk sürüm olduğu için bu bölüm boş da bırakılabilir.)

**EN:**
- The TV app was rewritten; one shared app for LG and Samsung.
- New connection to the new Nino apps for Mac, Windows, Android and iPhone; older Nino versions still work.
- Turkish, English and Arabic screen texts rewritten.

## İnceleyici notu (EN)

The app is a subtitle overlay for the HDMI picture. It needs a companion app (Nino for Mac, Windows, Android or iPhone, free, open source) on the same local network to receive subtitles. Without it, the app shows a waiting screen with a built-in preview; press the **Blue** key for the demo subtitles and **Green/OK** for the info panel. Details: `question.md`.
