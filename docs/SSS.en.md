<!-- Üretilen dosya: nino-pool/scripts/build-sss.mjs (kaynak nino-pool/assistant/sss.json). Elle değiştirmeyin. -->
# Nino: Frequently Asked Questions

These are the answers to the questions people ask the in-app Ask Nino robot most often (most frequent first). Menu names are those of the current apps (V4.5); on screen they appear in your app's language. If your question isn't here, ask Nino in the app or use Report a problem in Settings.

Other languages: [Nino: Sık Sorulan Sorular](SSS.md) · [Nino: الأسئلة الشائعة](SSS.ar.md)

## Contents

- [TV types and the TV app](#tv-types-and-the-tv-app)
- [Connecting to the PS5](#connecting-to-the-ps5)
- [Subtitles](#subtitles)
- [Connecting to the Xbox](#connecting-to-the-xbox)
- [Translation, language packs and API keys](#translation-language-packs-and-api-keys)
- [App problems (Windows, Mac, iPhone, Android)](#app-problems-windows-mac-iphone-android)
- [Setup in general](#setup-in-general)
- [Supported games](#supported-games)
- [Privacy and accounts](#privacy-and-accounts)
- [Requests and things Nino doesn't do yet](#requests-and-things-nino-doesnt-do-yet)

## TV types and the TV app

### Nino TV won't install or connect on my Samsung TV. What should I do?

On Samsung, installation usually gets stuck at one of these points:

1. Host PC IP: in the Developer Mode window on the TV, type the address Nino shows into the Host PC IP box. It is the address of the phone or computer doing the install, not the TV. Do not add leading zeros (1, not 001). If the box does not change, press the 123 key first.

2. Nino shows the address here: on Mac in the Nino app for TV card, on Windows in the Nino on the TV card, on Android in big blue numbers, on iPhone in the box that puts the TV into developer mode.

3. Fully restart the TV: hold the power key until the Samsung logo appears, or unplug the TV for one minute. A short press is not enough.

4. The first time, the TV asks for permission; choose Allow with the remote. If you rejected it by mistake, approve Nino in Settings › General › External Device Manager › Device Connection Manager › Device List.

5. The first install asks you to sign in once with a free Samsung account. If the page does not open, press the button to open the page again.

6. If you see Tizen code 118, remove Nino if it is in the app list. If not, use Settings › Support › Device Care › Self Diagnosis › Reset Smart Hub (this also removes other apps you downloaded).

7. If you installed from a phone and its address changed, redo the Host PC IP step.

What exact warning do you see on the screen?

### I get an error installing Nino on my LG TV (passphrase, key, no answer). What should I do?

The most common sticking points with LG. Key Server is the TV setting that hands Nino the install key, and the passphrase is that key's password.

1. Keep the Developer Mode app open on the TV screen. Both Dev Mode Status and Key Server must be on.

2. Sign in to the Developer Mode app with the free LG developer account you created at webostv.developer.lge.com.

3. The passphrase is the 6-character code in the bottom-left corner of the app. Type it into Nino letter by letter and compare it with the TV; watch for look-alike characters such as the letter O and zero.

4. If it says Key Server is off, turn Key Server on and leave the app on screen.

5. If it says the TV rejected the key, turn Key Server on again and enter the code again.

6. If it says the TV did not answer, check that the TV is on, on the same Wi-Fi, and Dev Mode Status is on.

7. On the first connection the TV asks for permission; accept it with the remote within 60 seconds.

8. The button is Install on TV on Mac and Windows, Install and open on iPhone, and Install and open on Android.

9. If you see a different warning, send a screenshot with Report a Problem; the team will look at it.

Which warning do you see on the screen?

### Installation on my Android TV does not start or Nino cannot find the TV. What should I do?

If installation on Android TV does not start, check these:

1. USB debugging must be on. This setting lets Nino install the app on the TV over Wi-Fi. Find it on the TV under Settings › System (or Device Preferences) › Developer options › USB debugging. If the list has Network debugging, turn it on too.

2. The TV, the PS5 and the Nino device must be on the same Wi-Fi network. On Windows, if the firewall asks, tick Private networks and press Allow.

3. Start the install: on Mac, Settings › Connection › Television › Open TV setup; on Windows, the Connect TV button; on iPhone, Settings › Install the TV app with this phone › Install and open; on Android, Profile › Install Nino on TV › Install and open. A computer does not list an Android TV; it searches the network during the install.

4. Within a few seconds the TV asks for USB debugging permission. Tick Always allow and press Allow.

5. If the phone cannot connect, try the wireless way: on the TV, Developer options › Wireless debugging › Pair device with pairing code. Type the address, port and 6-digit code into the phone and press install before the window closes. On iPhone, Nino also needs Local Network permission (iPhone Settings › Nino).

6. If you see that the package is invalid or the app was not installed, go to Settings › Apps › Nino TV › Uninstall on the TV, then install again.

What does the screen say when you press install?

### Can I use Nino with a TV box (Xiaomi Mi Box, Android box)?

Nino TV installs on Google TV or Android TV boxes the same way as on an Android TV: you turn on developer options and USB debugging (the setting that lets Nino install onto the box over Wi-Fi) on the box, and Nino on your phone or computer installs it.

There is one limit: the box shows its own picture. If the PS5 is plugged straight into the TV's HDMI input and the TV is on that input, the box cannot put subtitles over the game. TV boxes have not been tested much yet.

1. If you want subtitles over the game, the TV itself must be Android TV, Samsung or LG.

2. Otherwise show the subtitles on your phone: choose the phone on the subtitle screen of the setup and place it next to the TV.

3. If you have a computer, you can also show the subtitles on the computer screen.

Are the PS5 and the box plugged into different inputs of the same TV?

### My Android TV shows the one-time permission screen, or the permission window never appears. What should I do?

The one-time permission screen asks for the overlay permission, the setting that lets Nino draw subtitles over the game picture. USB debugging is the setting that lets Nino install onto the TV over Wi-Fi.

1. Easiest: if USB debugging is on, start translation from the phone or computer; Nino grants the permission itself.

2. To grant it by hand, on the TV go to Settings › Apps › Special app access › Display over other apps › turn on Nino. The TV settings button on the permission screen also takes you there; the screen moves on by itself once Nino is on.

3. If the TV has no such setting, choose Continue without permission. The game then opens inside Nino; on some TVs the picture may stay black.

4. If the USB debugging permission window never appears during setup, turn USB debugging off and on, turn the TV off and on, and start the install again. If you rejected it by mistake, just start the install again.

5. The TV version installed from Google Play cannot draw the overlay; the version installed from the phone or computer can.

After these steps, does the game picture show on the TV?

### My TV has no build row, or tapping it 7 times does not open developer options. What should I do?

If you cannot find the build row, or tapping it 7 times does nothing:

1. Make sure you are on the right screen: on Google TV, Settings › System › About; on Android TV, Settings › Device Preferences › About; on TCL and iFFALCON, System › About.

2. The row may be called Android TV OS build or Build. With the row selected, press the middle OK key on the remote 7 times in a row; if no message appears, press a few more times.

3. If the row does not exist at all, the TV is most likely not an Android TV. Apps cannot be installed on Vidaa, TiVo OS, Titan OS or non-Android Vestel TVs.

4. If it is an Android TV but you cannot reach developer options, the last resort is a manual install: in the TV's browser type is.gd/ninotvapk in the address bar, then open and install the downloaded file. Then turn on Nino under Settings › Apps › Special app access › Display over other apps. An app installed this way does not update by itself.

5. If none of this works, show the subtitles on your phone or on the computer screen.

Which rows do you see on the TV's About screen?

### My TV runs Vidaa, TiVo or a non-LG webOS. Can Nino TV be installed?

The Nino TV app installs only on Android TV / Google TV, Samsung and LG TVs. Apps cannot be installed on Vidaa (most Hisense), TiVo OS, Titan OS (newer Philips), Axen or non-Android Vestel TVs. For the LG install, the TV's LG Content Store must offer the Developer Mode app.

On such a TV you can still use Nino like this:

1. Show the subtitles on your phone: choose the phone on the subtitle screen of the setup and place it next to the TV. On Android, turn the phone sideways for full-screen subtitles.

2. If you have a computer, show the subtitles on the computer screen.

3. You can plug an Android TV box into the TV, but for subtitles over the game the game picture must also be on that box's screen.

What operating system name does the TV show in its settings?

### Typing 1 2 3 4 5 on my Samsung TV does not open the Developer Mode window. What should I do?

If the Developer Mode window does not open:

1. On 2022 and newer models the numbers do nothing on the first page. On the Apps screen, scroll to the very bottom, choose App Settings and type the numbers there. On older models you type them directly on the Apps screen.

2. If the remote has no number keys, press the 123 key; numbers appear on screen and you pick 1 2 3 4 5 there.

3. If it still does not open, fully restart the TV (hold the power key until the Samsung logo appears) and try again; on some TVs it opens on the second or third try.

4. You can plug a USB keyboard into the TV and type 12345; some TVs also accept the number pad of the SmartThings app on your phone.

5. On Mac, while App Settings is on screen, press the button in Nino that types 1 2 3 4 5 on the TV; it does not work on every TV.

Did you find the App Settings screen?

### When Nino starts, the game picture disappears or the TV stays black. What should I do?

If the game picture does not show or the TV stays black, try in order. HDR and HDCP are PS5 picture settings; HDCP protects the picture from copying and can make it black on some devices.

1. Turn off HDR on the PS5: Settings › Screen and Video › Video Output.

2. If that does not help, turn off HDCP: Settings › System › HDMI › Enable HDCP.

3. On Android TV, grant the overlay permission: on the TV, Settings › Apps › Special app access › Display over other apps › Nino. In the subtitle appearance settings you can set the Android TV display mode to overlay.

4. On LG, do not switch to HDMI from the TV's source menu, because Nino closes. Pick the PS5 input inside Nino with the 1–4 keys on the remote.

5. If it still fails, press the button on the TV that closes Nino and switches to the TV input; follow the subtitles on your phone or computer.

Which TV brand does this happen on?

### Nino on the TV opens and closes right away, or jumps straight to HDMI. What should I do?

If Nino on the TV opens and closes, or jumps straight to HDMI, check this for your TV:

1. Samsung: on the TV, Settings › All Settings › Connection › External Device Manager, turn off Anynet+ (HDMI-CEC) and Auto Source Switching.

2. LG: do not switch to HDMI from the TV's source menu, because Nino closes. Pick the PS5 input inside Nino with the 1–4 keys on the remote.

3. Android TV: if the picture does not come into Nino, Nino switches to the overlay by itself and the TV's HDMI screen opens; subtitles are drawn on top of it. This needs the overlay permission (Settings › Apps › Special app access › Display over other apps).

4. If the TV app is old, reinstall it from Nino on your phone or computer.

Which TV brand does this happen on?

### My PS5 is connected to a plain (non-smart) monitor. How can I see the subtitles?

A plain monitor cannot run the TV app, but you can see the subtitles elsewhere:

1. On a phone: choose the phone on the subtitle screen of the setup (On the phone screen on Android, On this iPhone on iPhone) and place the phone next to the monitor.

2. On a computer: Nino can show the subtitles on the computer screen over the game picture. On Mac, choose Computer in Settings › Connection › where subtitles appear.

3. A capture card is a small device that passes the console's HDMI picture to a computer. With one, the picture goes from the card to the computer; Remote Play and a second account are not needed. Put the card between the PS5 and the monitor and set the picture source to Capture Card on Mac or Windows. Enable HDCP must be off on the PS5.

4. If the monitor is smart, like a Samsung Smart Monitor, Nino TV can be installed on it and subtitles appear over the game.

Which option suits you?

## Connecting to the PS5

### Nino stays on 'Connecting' to the PS5. What should I do?

If it stays on Connecting, Nino cannot reach the PS5 or the PS5 does not start the session. Try in order:

1. The PS5 must be on or in rest mode. In rest mode, Stay Connected to the Internet must be on.

2. The PS5 and the device running Nino must be on the same Wi-Fi network.

3. With the second account, turn on Settings › System › Remote Play on the PS5.

4. If PS Remote Play is open on another device, close it.

5. If your PS5 uses a sign-in passcode, enter it in the PS5 passcode section of Nino's settings.

6. If it still fails, close PS Remote Play, turn the PS5 off and on, and plug in the plug in Nino again.

7. If the screen says the PS5 rejected the pairing, pair again: with the second account on the PS5, Settings › System › Remote Play › Pair Device.

8. On iPhone, keep Nino open on screen and do not lock the phone.

Is there a reason written under the Connecting text?

### The PS5 connection keeps dropping while I play. What should I do?

If the connection drops during play, try these:

1. If PS Remote Play is open on another device, close it; the PS5 does not keep two Remote Play connections at once.

2. Play on your own (main) account on the PS5, not on the second account.

3. On iPhone, keep Nino open on screen. Do not lock the phone or switch apps, and keep it charging if you can. iOS stops apps that go to the background.

4. If the Wi-Fi is weak, keep the phone or computer close to the router.

5. If the PS5 is in rest mode, Stay Connected to the Internet must be on.

6. Nino keeps retrying by itself after a drop. If it happens often, report it from the app (Report a Problem); device details are added automatically.

On which device does the drop happen?

### The PS5 refuses the connection or rejects the pairing (I get an error code). What should I do?

If the PS5 refuses the connection or rejects the pairing, try in order:

1. Get a new code: with the second account on the PS5, Settings › System › Remote Play › Pair Device. The code has 8 digits and is valid for 5 minutes; type it into Nino right away, in the order shown.

2. If it says the console does not know this account, the second account has never signed in on the PS5. Sign in with it once using Add User on the PS5, then get the code.

3. The Sony account you signed in with in Nino must be the same second account you used to get the code.

4. Remote Play must be on for the second account.

5. If it says Remote Play is in use on another device, close Remote Play on that device.

6. If it still fails, close PS Remote Play, turn the PS5 off and on, and pair again.

What text appears next to the error code?

### The 'Remote Play connected' notice keeps showing on the PS5. How do I turn it off?

This notice is turned off in the settings of the second account Nino connects with:

1. On the PS5, switch to the second account: PS button › profile picture › Switch User.

2. While on the second account, open Settings › System › Remote Play and turn on Hide Remote Play Connection Status at the bottom.

3. Switch back to your own account and start the game.

Is the notice gone?

### While Nino runs, my controller does not work in the game. What should I do?

If the controller does not work in the game, the PS5 is most likely on Nino's second account:

1. When you turn on the controller, pick your own (main) account on the PS5. The second account is only for Nino; if you play on it, the controller will not work in the game.

2. To switch accounts: PS button › your profile picture › Switch User.

3. Start the game on your own account, then plug in the plug in Nino.

Does the controller work after switching to your account?

### I get an error at the Sony sign-in with the second account (for example CE-110032). What should I do?

This error code comes from Sony's sign-in page; I do not have confirmed information about what it means. Things you can try:

1. Sign in with the free second PSN account, not the one you play on. That account must have signed in on the PS5 once.

2. If the page inside the app does not open, use the browser way: on Android, Open in browser; on Windows, Sign in in the browser or type the ID by hand.

3. If it still fails, send a screenshot with Report a Problem; the team will look at it.

Which device are you signing in on?

### Nino cannot find my PS5 or says the PS5 is not responding. What should I do?

If Nino cannot reach the PS5, check these:

1. The PS5 must be on or in rest mode; in rest mode, Stay Connected to the Internet must be on.

2. The PS5 and the Nino device must be on the same Wi-Fi network.

3. On Mac, allow Nino in System Settings › Privacy & Security › Local Network.

4. If the PS5 is not listed, use Search again or Connect by IP address on Mac, Search again on Android, or the PS5 not showing button on iPhone.

5. Nino keeps trying by itself; if the PS5's network address changed, enter the new one.

Are the PS5 and the Nino device on the same network?

## Subtitles

### The translation shows on my phone or computer but not on the TV. What should I do?

If the translation shows on your phone or computer, reading works; the problem is sending it to the TV. Let's check in order:

1. Keep the Nino TV app open on the TV. The TV and the device running Nino must be on the same Wi-Fi network.

2. Make sure the subtitle target is the TV: on Mac, Settings › Connection › where subtitles appear (TV or Both); on iPhone, Settings › Where subtitles appear. On Android, choose TV on the home screen.

3. Send a test line: on iPhone, Settings › Send Test Subtitle; on Android, Settings › Try on TV. If the test line does not reach the TV, the problem is the TV connection.

4. If a Samsung TV jumps to HDMI by itself: on the TV go to Settings › All Settings › Connection › External Device Manager and turn off Anynet+ (HDMI-CEC) and Auto Source Switching.

5. On LG, do not switch to HDMI from the TV's source menu, because Nino closes. Pick the PS5 input inside Nino with the 1–4 keys on the remote.

6. On Android TV, the overlay permission is needed. It is the setting that lets Nino draw subtitles on top of the game picture. On the TV go to Settings › Apps › Special app access › Display over other apps › turn on Nino.

7. If the TV app is old, reinstall it from Nino on your phone or computer. On Android a button to refresh the TV app appears on the home screen.

Does the test line show up on the TV?

### The TV keeps saying it is waiting for Nino. What should I do?

This message means the TV is ready but has not found your phone or computer yet:

1. Open Nino on the phone or computer and plug the plug into the socket on the home screen so translation starts. A phone is enough even if the TV mentions a computer.

2. The TV and the Nino device must be on the same Wi-Fi network. Compare the network name in the TV's network settings and on the phone.

3. On a computer, only one copy of Nino may be open.

4. On Windows, if the firewall asked for permission, tick Private networks and press Allow; the network type should be Private.

5. If Mac says it is waiting for the TV app, or Windows says it is waiting for Nino to open on the TV, open Nino on the TV.

6. If it still does not work, set up the TV connection again: on Mac, Settings › Reset › Repeat setup from the TV step; on Windows, Settings › Reset › Set up again from the TV step. The PS5 pairing is kept.

Are the TV and the phone on the same network name?

### Everything looks connected but no subtitles come, or they come once and stop. What should I do?

If no subtitles come, or they come once and stop:

1. Turn on the game's own English subtitles; Nino reads this text on screen, not the voice.

2. The plug on Nino's home screen must be in the socket. This is the plug drawn in the app; do not touch the PS5's real power plug.

3. Nino learns where the game's subtitles are during the first few lines; wait a little in a scene with dialogue.

4. On a computer, only one copy of Nino may be open.

5. The phone or computer, the TV and the console must be on the same Wi-Fi network.

Does the game picture show inside Nino?

### How do I change the subtitle size, background or the Nino mark on the TV?

You change how subtitles look in Nino's settings: on Mac, Windows and Android, Settings › Subtitle appearance; on iPhone, Settings › Subtitle look.

1. Text size and color (white or yellow) are here.

2. The background goes from None to Opaque. Choosing None removes the black box.

3. Fonts: Action (GTA style), Modern, Rounded or Simple. iPhone calls Simple Standard, and Android calls Rounded Soft-cornered.

4. To turn off the small Nino mark on the TV, switch off the option to show the Nino mark on the TV (its name differs slightly per app). Subtitles keep working.

5. On Android, if the option to match the game's subtitle size on the TV is on, the TV text follows the size of the game's text.

6. If the text on the TV never changes, the TV app is old; reinstall it from Nino on your phone or computer.

Did you find the setting you wanted?

### Nino translates button hints or the whole screen instead of the subtitles. What should I do?

Nino learns where the game's subtitles are during the first few lines; after that it reads only that area. Directions and button hints are not treated as subtitles.

1. Keep the game's English subtitles on and wait a little in a dialogue scene; Nino learns the spot.

2. Keep the app up to date; older versions translated signs and button hints more often.

3. To narrow the reading area, look at Settings › Subtitle area on iPhone, or Settings › Subtitle area on Windows.

4. If a big black box bothers you, set the background to None in the subtitle appearance settings.

Did the subtitles start translating in a dialogue scene?

## Connecting to the Xbox

### Nino will not connect to my Xbox or the Xbox is not in the list. What should I do?

If Nino will not connect to the Xbox, check these:

1. On the Xbox, turn on Settings › Devices & connections › Remote features. The power mode should be Sleep so Nino can find the Xbox remotely.

2. When you sign in with Microsoft in Nino, use the same account that is signed in on the Xbox. The code is entered at microsoft.com/link.

3. The Xbox and the Nino device must be on the same Wi-Fi network.

4. On Mac, first open the Xbox in Greenlight or at xbox.com/play in a browser; on Windows, use Remote play in the Xbox app. Nino reads that window, so if the window does not connect, that has to be fixed first.

5. If it connects and then drops, set the resolution to 1080p on the Xbox in Settings › General › TV & display options.

Does the Xbox appear in Nino's list?

### Xbox remote play starts and stops right away, or keeps dropping. What should I do?

If Xbox remote play starts and stops, or keeps dropping:

1. On the Xbox, set the resolution to 1080p in Settings › General › TV & display options. This fixed it for some users.

2. The Xbox and the phone or computer must be on the same Wi-Fi network; if the Wi-Fi is weak, keep the phone close to the router.

3. On the Xbox, Remote features must be on and the power mode set to Sleep.

4. On iPhone, keep Nino open on screen and do not lock the phone.

Does it still drop after changing the resolution?

### With Xbox, the game sound comes from my phone. What should I do?

This is how the Xbox itself behaves: during remote play it sends the sound to the connected device. Ways around it:

1. Listen through the phone or computer; you can connect headphones or a soundbar.

2. Nino on Android has a separate setting for Xbox sound; look for the Xbox sound option in settings.

3. Use a capture card: the console's sound stays on the TV.

Which phone are you using?

## Translation, language packs and API keys

### On iPhone the language pack will not download, or it says translations could not be downloaded. What should I do?

I do not have confirmed steps for this screen yet, and I do not want to send you the wrong way. What we know:

1. GTA 6 gets its translation from Nino's shared translation pool; you do not need to download a pack for it.

2. For other games the iPhone uses Apple's free on-device translation, which needs iOS 26 or later. On older iOS, add a free Gemini key in Settings › Translation service; the app shows you how step by step.

3. Send the problem with a screenshot from Settings › Report a Problem; the team will look at it.

Can you send a screenshot?

## App problems (Windows, Mac, iPhone, Android)

### On Windows, Nino will not open, shows an error or does not update. What should I do?

Depending on what happens on Windows, check these:

1. If Windows says it protected your PC, press More info, then Run anyway.

2. If it says Nino could not start because files are missing, your antivirus has most likely quarantined them. Allow Nino in the antivirus and reinstall Nino.

3. If an unexpected error window appears, it shows where a log file is (%LOCALAPPDATA%\Nino\hata.log). Send that file from Settings › About Nino › Report a problem.

4. To update, press Update now on the home screen. Updates do not install while translation is running. A copy downloaded as a zip cannot update itself; install it with the setup file.

5. If the firewall asks, tick Private networks and press Allow; otherwise Nino cannot see the PS5 and the TV.

What exact warning do you see?

### On iPhone, translation stops when the screen turns off or after a while. What should I do?

iOS stops apps that are locked or moved to the background; this is Apple's rule and no app can get around it. While translating, Nino keeps the screen on by itself and dims the brightness.

1. Do not lock the phone or switch to another app.

2. Keep the phone on the charger.

3. If you do not want the screen to stay on, use Nino on a computer or an Android phone; on Android Nino also runs in the background.

Does it stop even without the phone locking?

## Setup in general

### How do I reset Nino or set it up from scratch?

On a computer you do not need to uninstall Nino to start over; use the Reset section:

1. On Mac: Settings › Reset from the menu. To redo only the TV, use Repeat setup from the TV step; to start everything over, use Reset everything.

2. On Windows: Settings at the top right › Reset. For the TV only, Set up again from the TV step; for everything, Reset everything.

3. Redoing the TV step keeps the PS5 pairing. Reset everything clears it all, and Nino then guides you step by step like on first launch.

4. If you want to reset on a phone, tell us where you are stuck with Report a Problem.

Which device do you want to reset?

### I finished the setup. What do I do now?

Once setup is done, each time you play you only do this:

1. When you turn on the controller, pick your own (main) account on the PS5 and start the game. Keep the game's English subtitles on.

2. Keep the Nino TV app open on the TV.

3. Drag the plug into the socket on Nino's home screen, or tap the plug. This is the plug drawn in the app; do not touch the PS5's real power plug.

4. When translation starts, the TV shows that Nino is translating subtitles, and the subtitles appear over the game. To stop, pull out the plug.

After plugging in, did subtitles appear on the TV?

## Supported games

### Which games does Nino work with? Does it translate games without subtitles or phone games?

Nino reads and translates the English text shown on screen in PS5 and Xbox Series X|S games. So what matters is the game's subtitles, not its name:

1. Turn on English subtitles in the game's settings. Nino cannot translate dialogue without subtitles, because it reads the text on screen, not the voice.

2. GTA 6 gets its translation from Nino's shared translation pool; no key is needed and it costs nothing.

3. Other games are translated by the translation engine you choose. For better quality you can add a free Gemini key.

4. Mobile games played on a phone or tablet, PS4, Nintendo Switch and Steam Deck are not supported.

Which game do you want to play?

### How does GTA 6 translation work, and why is there no GTA 6 pack in the list?

You do not need a separate pack for GTA 6:

1. The English lines in GTA 6 are translated once on Nino's server with high-quality AI, and go instantly to everyone who sees the same line. We call this the shared translation pool.

2. Your Gemini, DeepL, ChatGPT or other key is not used for this game, so it costs nothing.

3. Nino recognizes the game by itself from the screen and the subtitles; you do not need to pick it.

4. If the server cannot be reached, the device's free translation is shown.

Are the subtitles being translated in GTA 6?

## Privacy and accounts

### How do I sign out of the PSN or Xbox account in Nino?

Nino has no account of its own; settings stay only on your device. You sign in to PSN and Microsoft on Sony's and Microsoft's own pages, and your password never reaches Nino.

1. On Mac and Windows, Settings › Reset › Reset everything returns Nino to its first-launch state.

2. I do not have confirmed information about a separate sign-out button on phones. If you like, write to us with Report a Problem and the team will guide you.

Which device do you want to sign out on?

## Requests and things Nino doesn't do yet

### Does Nino work with PS4?

Right now Nino does not support PS4; it works with PS5 and Xbox Series X|S. We have noted your request.

If you have a PS5 or an Xbox, shall I help you set it up step by step?

### Can Nino do dubbing (spoken translation)?

I do not have current, confirmed information about dubbing, and I do not want to tell you something wrong. What Nino is known to do is read the English text in the game, translate it and show it as subtitles. To pass your request to the team, write to us with Report a Problem.

Shall I help you with the subtitle setup?

