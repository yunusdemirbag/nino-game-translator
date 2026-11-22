# LG Content Store: inceleme soruları için hazır cevaplar

Seller Lounge'daki 1:1 soru ya da inceleme notları için. Önce Türkçe (proje sahibi için), sonra LG'ye gönderilecek İngilizce.

## Türkçe özet

1. **Mağazadan kurulunca geliştirici modu neden gerekmez?** Bugün Nino, TV uygulamasını LG'nin geliştirici modu
   üzerinden bilgisayardan ya da telefondan kurabiliyor; bu yalnız mağaza sürümü olmadığı için var. Uygulama LG Content
   Store'dan kurulursa TV'de geliştirici modu, Developer Mode uygulaması, LG geliştirici hesabı ya da 1000 saatlik süre
   uzatma gerekmez. Mağaza sürümü olağan bir uygulama gibi açılır ve ev ağında Nino'yu bekler.
2. **Altyazı TV'ye nasıl gelir?** TV uygulaması kullanıcının kendi Nino uygulamasına (aynı Wi-Fi'daki Mac, Windows,
   Android telefon ya da iPhone) yerel ağ üzerinden bağlanır: göndericiyi ağda arar
   (`http://<ip>:47800/nino/info`), sonra WebSocket ile çeviri satırlarını alır. Eski Nino sürümleri için 8787
   portundaki olay akışı da desteklenir. TV uygulaması altyazıyı yalnız ev ağından alır; altyazı için internete bağlanmaz.
3. **Hesap, reklam, satın alma?** Yok. Giriş ekranı, reklam, ödeme yok.
4. **TV'den internete ne gider?** Gizlilik sayfasında yazanlar: günde bir kez TV'nin marka ve modeli, uygulama sürümü
   ve rastgele bir kimlik; ayrıca anonim hata ve bağlantı ölçümleri (açılış, çökme türü, hata kodu, bağlanma süresi,
   kopma nedeni). Altyazı metni, görüntü, ses, TV'nin adı ya da ağ adresi gönderilmez.
5. **HDMI'ye neden erişiyor?** Konsol görüntüsünü TV'nin kendi HDMI girişinden göstermek ve altyazıyı onun üstüne
   çizmek için. Görüntü okunmaz, kaydedilmez, gönderilmez.

## English (to send to LG)

**What does the app do?**
Nino Game Translator shows translated subtitles over a game console's HDMI picture. The console picture is shown
through the TV's own HDMI input; the app only draws subtitle text on top of it.

**Where do the subtitles come from?**
From the user's own Nino app (free and open source) running on a Mac, Windows PC, Android phone or iPhone on the
same home network. That app reads and translates the game text. The TV app finds it on the local network
(`GET http://<ip>:47800/nino/info`) and receives subtitle lines over a WebSocket connection; older Nino versions are
reached through an event stream on port 8787. The TV app receives subtitles only over the local network; it does not fetch them from the internet.

**Why is Developer Mode not needed?**
Developer Mode was only used to sideload the TV app while it was not in the LG Content Store. When installed from the
store, the app runs like any other app: no Developer Mode, no LG developer account, no key server and no session
extension. It simply waits for the user's Nino app on the local network.

**How can the reviewer test it without a console?**
Open the app: a waiting screen with a short built-in preview plays. Press **Blue** to start demo subtitles,
**Green** or **OK** to open the info panel, **Back** to close them. Keys **1–4** switch the HDMI input.
If a reviewer wants live subtitles, install Nino on a Mac, Windows PC or Android phone from
https://github.com/yunusdemirbag/nino-game-translator/releases/latest, connect it to the same Wi-Fi network and
choose this TV in Nino; Nino's Android phone app also has a "Try without PS5" demo that needs no console.

**Accounts, ads, payments?**
None. There is no sign-in, no advertising and no in-app purchase.

**Data sent to the internet**
Once a day the app reports the TV's brand and model, the app version and a random ID generated on the TV. It also
sends anonymous technical measurements (launches, crash type, error codes, connection time and disconnect reason) to
Nino's own server. No subtitle text, picture, audio, TV name, network address or personal data is sent. Full policy:
`<site>/gizlilik`.

**Permissions and services used**
TV input (HDMI) to show the console picture, network status to find the user's Nino app on the local network, and a
screen saver request so the screen saver does not cover the game while subtitles are shown.

**Source code**
https://github.com/yunusdemirbag/nino-game-translator (AGPL-3.0). Support: GitHub Issues.
