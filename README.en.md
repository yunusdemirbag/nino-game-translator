<p align="center">
  <img src="docs/img/nino-kapak-en.webp" width="100%" alt="Nino PS5 box">
</p>

<h1 align="center">Nino Game Translator</h1>

<p align="center"><b>The game speaks English. Your subtitles don't have to. Right on your TV, on top of the game.</b></p>

<p align="center">
  <a href="README.md">Türkçe</a> · <a href="README.ar.md">العربية</a> · <b>English</b>
</p>

<p align="center">Free · No ads · No account · Open source</p>

---

## What is Nino?

Nino translates the English text in PS5 and Xbox games into Turkish or Arabic, instantly.
It translates subtitles, in-game phone messages, and mission and map cards.
The translation shows up on your TV, on top of the game. You just play as usual.

## What it looks like

<p align="center">
  <img src="docs/img/oyunda-turkce-mesaj.webp" width="100%" alt="An in-game message with its Turkish translation right above it">
  <br><sub>A message arrives in the game, and its translation sits right above it.</sub>
</p>

<p align="center">
  <img src="docs/img/telefon-mesajlari-tr.webp" width="100%" alt="Translated chat panel next to the in-game phone">
  <br><sub><b>Phone messages</b><br>Next to the in-game phone, one bubble at a time.</sub>
</p>

<p align="center">
  <img src="docs/img/iphone-yatay-map-tr.webp" width="100%" alt="Translated map mission card">
  <br><sub><b>Map cards</b><br>The mission card on top, so you know what to do at a glance.</sub>
</p>

<p align="center">
  <img src="docs/img/iphone-yatay-phone-tr.webp" width="100%" alt="Subtitles on an iPhone held sideways">
  <br><sub><b>iPhone, sideways</b><br>No TV? Turn your phone sideways: messages on top, subtitles in the middle.</sub>
</p>

<p align="center">
  <img src="docs/img/mac-ve-iphone.webp" width="100%" alt="Nino's home screen on Mac and iPhone">
  <br><sub><b>Mac ↔ iPhone</b><br>The same Nino, just as easy on every device.</sub>
</p>

<p align="center">
  <img src="docs/img/rdr2-turkce-altyazi.webp" width="100%" alt="Subtitles on a real TV, on top of the game">
  <br><sub>From a real TV: Red Dead Redemption 2 · <a href="docs/img/rdr2-turkce-altyazi.mp4">▶️ Video with sound (30 s)</a></sub>
</p>

## Get started in 3 steps

1. **Download Nino:** pick your device in the table below.
2. **Connect your console:** PS5 or Xbox. Nino tells you what to do, step by step.
3. **Pick your TV:** Nino installs the TV app for you.

Then start your game and plug in Nino's plug. That's it.

## Download

| Device | Download | How to install |
|---|---|---|
| Mac | [Nino-Mac.zip](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Mac.zip) | [Setup ↓](#setup-mac) |
| Windows | [Nino-Windows-Setup.exe](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Windows-Setup.exe) | [Setup ↓](#setup-windows) |
| iPhone and iPad | [TestFlight](https://testflight.apple.com/join/1K3Q1KXp) | [Setup ↓](#setup-iphone) |
| Android phone | [Nino-Telefon.apk](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk) | [Setup ↓](#setup-android) |
| TV (Android TV, LG, Samsung) | Nino installs it | [Setup ↓](#setup-tv) |
| Linux | Docker | [Setup ↓](#setup-linux) |

## Setup

<a id="setup-mac"></a>
### Mac
1. Download **Nino-Mac.zip** and double-click it.
2. Drag **Nino** into **Applications** and open it.
3. If macOS says it can't be opened: **System Settings › Privacy & Security › Open Anyway**.

<a id="setup-windows"></a>
### Windows
1. Download **Nino-Windows-Setup.exe** and double-click it.
2. If you see "Windows protected your PC": **More info › Run anyway**.
3. Nino opens by itself.

<a id="setup-iphone"></a>
### iPhone and iPad
1. Install **TestFlight** from the App Store.
2. Tap [this link](https://testflight.apple.com/join/1K3Q1KXp), then **Accept › Install**.
3. Open Nino. (App Store version coming soon.)

<a id="setup-android"></a>
### Android phone
1. Download **Nino-Telefon.apk** on your phone and open it.
2. If it asks about unknown apps, tap **Allow**.
3. Tap **Install**, then open Nino.

<a id="setup-tv"></a>
### TV
Nothing to download: pick your TV in Nino and it installs the app on the TV for you.
To install by hand: [Android TV](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-TV.apk) · [LG](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-TV.ipk) · [Samsung](https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-TV.wgt)

<a id="setup-linux"></a>
### Linux
```bash
curl -fsSLO https://raw.githubusercontent.com/yunusdemirbag/nino-game-translator/main/apps/linux/docker-compose.yml
docker compose up -d
```
Then open `http://<computer address>:8788` in a browser.

All files: [Nino release page](https://github.com/yunusdemirbag/nino-game-translator/releases/latest)

## Which TVs work?

**Works on**
- Android TV and Google TV (including Android TV boxes)
- Samsung (Tizen)
- LG (webOS)
- A Mac or PC screen
- Any monitor (with an HDMI capture card or the computer screen)

**Does not work on**
- Vidaa (most Hisense TVs)
- TiVo
- Titan OS (newer Philips TVs)
- Axen
- Older Vestel TVs without Android
- TV boxes without Android

These TVs can't install other apps. The fix: plug an Android TV box into the TV, or show the subtitles on a computer screen.

## Questions people ask most

**Does it cost anything?**\
No. Nino is completely free. No ads, no subscription.

**Why do I need a second PSN account?**\
The PS5 won't allow remote play on the account you're playing with at the same time. A free second account is enough.

**Subtitles don't show on the TV. What now?**\
Make sure the console, Nino and the TV are on the same Wi-Fi. Then close Nino and the TV app and open them again.

**Which games does it work with?**\
Almost any game with English text on screen. GTA 6 has extra translation support.

**Does it work with Xbox?**\
Yes, in early testing. Your own Microsoft account is enough.

More answers: [FAQ](docs/SSS.en.md)

## Privacy

- You don't need an account.
- Your translation service key (API key) stays on your device. It is never sent to our server.
- The game picture is never saved or sent anywhere.

Details: [Privacy policy](PRIVACY.md)

## License and contact

Nino is open source under [AGPL-3.0](LICENSE). Build notes for developers: [docs/yeni](docs/yeni).
Questions and ideas: [GitHub › Issues](https://github.com/yunusdemirbag/nino-game-translator/issues)

Made by **Yunus Demirbağ** · Supported by **M. Akif Demirbağ**

Many thanks to **CouchSubs** and its developer **Sinan Yorulmaz**, who inspired our first versions.

<sub>Nino is not affiliated with Sony, Microsoft, LG or Samsung. PlayStation, PS5, Xbox, LG and Samsung are trademarks of their owners. Game images belong to their owners.</sub>
