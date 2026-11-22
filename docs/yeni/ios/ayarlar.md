Eski uygulamadan çıkarılmış tarif

# Nino iPhone/iPad: ana ekrandan açılan alt sayfalar

Bu belge eski iOS uygulamasındaki Profil, Ayarlar, Hakkında, Oyun paketleri, Sorun Bildir, Nino'ya Sor, TV uygulaması
kurulumu ve konsol/Xbox ekranlarını anlatır. Kod yoktur; yapı, ölçü, renk, metin ve davranış vardır. Yeni kodu yazan
kişi bu tarife bakarak aynı ekranları kendi kodunu yazarak kurar.

Ortak bileşenlerin (Tile, ListRow, SegmentedTabs, MobilePill, MobileNote, IconButton, BackHeader, MobileScreen,
BentoGrid, düğme stilleri, robot yüzü, renk ve yazı jetonları) ölçüleri **`docs/yeni/ios/tasarim.md`** içinde. Burada
yalnız adlarıyla anılırlar. Kısaca hatırlatma:

| Jeton | Değer |
|---|---|
| Boşluk | screen 20, gap 12, tile 16, inline 8, hair 4 |
| Köşe | tile 22, control 16, inner 8, tag 6 |
| Yükseklik | button 52 (birincil/ikincil düğme en az 58), buttonSmall 44, icon 44, field 52, row 52, tag 24 |
| Yazı | display 28 yarı kalın, title 22 yarı kalın, headline 17 yarı kalın, body 15 normal, caption 13 orta |
| Renk | text #0A1430, secondary #55607A, tertiary #8A93A8, accent #0070D1, pro #00205B, success #1E6B45, warning #9A4A08, danger #B3261E, surface beyaz @%85, surface2 #E6EDF8, borderStrong #D3DEEF, bg #EEF3FB |

Metinler: ekrandaki her yazı, yeni uygulamanın metin tablosundaki **anahtarıyla** anılır (ör. `settings.title`). Anahtarın
İngilizce ve Türkçe değerleri `apps/ios/Nino/Resources/Localizable.xcstrings` içindedir; bu belgede metnin kendisi
yazılmaz. Katalogda karşılığı olmayan yazılar kısa bir düz anlatımla, "(katalogda yok)" notuyla geçer; marka ve ürün
adları (PlayStation 5, DeepL, Gemini…) çevrilmez ve olduğu gibi yazılır.

---

## 0. Genel kurallar ve ekran görüntüleri

- **Yalnız açık tema.** Kök görünüm açık renk şemasına sabittir; bütün alt sayfalar açık zemin (MobileBackground degradesi)
  üstünde beyaz cam karolardır.
- **Arayüz dili çeviri dilini izler.** Kökte ortam dili `UILanguage.locale(çeviri dili)` yapılır; Arapça/Urduca seçilince
  arayüz o dile ve sağdan sola düzene anında geçer. Türkçe seçiliyken bütün metinler Türkçe görünür.
- **iPad farkı (bütün alt sayfalarda aynı):** cihaz iPad ise içerik, üst satır ve alt düğme bölgesi en çok 680 pt genişlikte
  ortalanmış sütundur; üst satırın üstündeki boşluk 8 yerine 20, en alttaki boşluk 20 yerine 40 pt. Bunun dışında
  ekranların düzeni iPhone ile aynıdır (iki sütunlu bento ızgara iPad'de de iki sütundur). Ek farklar: Ayarlar'daki
  altyazı önizlemesinin yazı boyu iPhone'da 28, iPad'de 36 pt tabanlıdır (bkz. 2.5). Sorun Bildir sayfası aynı ekran
  iskeletini kullandığı için iPad'de de 680 pt sütundadır; Nino'ya Sor sohbet sayfası ve paket içe aktarma
  önizleme sayfası bu iskeleti kullanmaz, sistem sayfasının tüm genişliğini doldurur (iPad'deki sayfa genişliği ve
  sayfa davranışları için tasarim.md §13 ve §15).
- **Gezinme:** ana ekran bir NavigationStack'tir; alt sayfalar sağdan itilerek açılır (sistem gezinme çubuğu gizli, her
  sayfanın kendi geri başlığı var). Sorun Bildir, Nino'ya Sor ve paket içe aktarma ise **alttan açılan sayfa** (sheet).
- **Yol listesi (Route):** settings, profile, packs, target, ps5, psn, about, history, platform, tvInstall, tvUpdate.
  - `settings` → Ayarlar, `profile` → Profil, `packs` → Oyun paketleri, `about` → Hakkında, `target` → Altyazı hedefi
    ekranı (kurulum dışı kipte; bitince bir geri), `psn` → PSN giriş ekranı, `history` → Geçmiş (bu belgenin dışında).
  - `platform` → Konsol seçimi. İleri düğmesine (`common.next`) basınca bir geri gidilir; Xbox seçildiyse ve Microsoft
    girişi ya da Xbox seçimi eksikse ardından `ps5` yoluna gidilir.
  - `ps5` duruma göre farklı ekran açar: Xbox ve giriş yok → Xbox girişi (bitince kendini kapatıp `ps5`'i yeniden açar);
    Xbox ve giriş var → Xbox seçimi (oradaki Microsoft giriş düğmesi `xbox.signin.button` Microsoft oturumunu kapatır);
    PS5 ve PSN hesabı yok → PSN girişi (bitince kendini kapatıp `ps5`'i açar); PS5 ve hesap var → PS5 eşleme ekranı.
  - `tvInstall` → TV uygulaması kurulumu; `tvUpdate` → aynı ekran, ana ekrandaki güncelleme kartından, kurulum
    kendiliğinden başlar. Kurulum bitince ana ekran düğmesi (`tvi.home`) bütün yığını boşaltır (ana ekrana döner).
- **Robot düğmesi** (Nino'ya Sor, 6.1) alt sayfalarda **görünmez**: ana ekranda yalnız yığın boşken ve tanıtım turu
  bittiyse çıkar. Alt sayfalarda sohbete Profil/Ayarlar listesindeki `ask.title` satırından gidilir.
- **Ölçüm:** Profil açılınca `screen("profile")`, Ayarlar `screen("settings")`, Paketler `screen("packs")` ölçüm olayı
  gönderilir (ölçüm katmanı başka belgenin konusu).

### Ekran görüntülerinden farklar (docs/screenshots/telefon/10–12)

Bu üç görüntü eski bir tasarım taslağından kalmadır; **kaynak doğrusu koddur**. Yeni uygulama koddaki hâli kurar.

| Görüntü | Görüntüde | Kodda (doğrusu) |
|---|---|---|
| 10 Paketler | Koyu zemin; başlığın sağında ücretsiz olduğunu ve oyun sayısını söyleyen etiket; karolarda kısaltma kutusu ve yeşil "şu an" noktası; son karo kesik çizgili, yeni paketlerin güncellemeyle geleceğini anlatan bir karo | Açık zemin; sağdaki etiket yalnız `engine.price.free`; üstte açıklama, ardından paketleri açıp kapatan anahtar karosu; karolar dokununca açılıp kapanır, `home.nowplaying` / `common.off` etiketi; içe aktarma bölümü; en altta düz `packs.comingsoon` karosu; altta `packs.updateNow` düğmesi |
| 11 Cihazlarım | Koyu, amber vurgu, cihazları listeleyen bir başlık, sağ üstte dişli; cihaz listesi (PS5 satırı adres + eşlendi bilgisi, TV satırlarında hazır/kurulu/uygulama yok etiketleri), ikinci PSN hesabını değiştirme satırı, iki anahtar, yardım ve hakkında satırları, altta cihaz ekleme düğmesi | Başlık `settings.profile`; logo karosu; iki değer karosu (`settings.devices`, `settings.psn`); `devices.console` / `settings.ps5` / `settings.target` listesi; altı (Xbox'ta yedi) anahtar; gizlilik / yardım / Nino'ya Sor / Sorun Bildir / Hakkında listesi; telif satırı; alt düğme yok |
| 12 Ayarlar | Koyu; çeviri motoru segmenti ve kayıtlı DeepL anahtarı alanı; yüzdeli altyazı boyu kaydırıcısı ve iki renk dairesi; altta paketler (ücretsiz etiketiyle) / altyazı hedefi / PS5 bağlantısı / hakkında satırları | Bunların hepsi var ama açık temada; ek olarak çeviri dili, GTA 6 kartı, yazı tipi, arka plan, yer, görüntü modu, filigran, altyazı alanı, ek alanlar, PS5 oturum şifresi, cihaz bilgisi ve altta `tv.test.send` düğmesi var |

Görüntüdeki amber vurgu, koyu karolar ve renkli simge kutuları **kullanılmaz**. Görüntü 11'deki TV satırında eski
projenin adı geçiyor; bu ad hiçbir ekranda yazılmaz.

---

## 1. Profil ekranı (Route.profile)

Ana ekrandaki profil düğmesinden (AvatarButton) açılır. Hesap yoktur; ekran cihazları, bildirim ve paylaşım
tercihlerini ve yardım bağlantılarını toplar.

### 1.1 Düzen (yukarıdan aşağı, içerik aralığı 12)

1. **Geri başlığı:** `settings.profile`. Sağ tarafı boş.
2. **Kimlik karosu** (Tile, iç aralık 8): yatay sıra, aralık 12: logo (56 pt), yanında dikey yığın (aralık 4):
   - Ürün adı "Nino Game Translator" (title, çevrilmez, sabit yazı).
   - `engine.apple.detail` (caption, secondary): ücretsiz ve hesapsız olduğunu söyleyen kısa satır.
3. **İki değer karosu** (BentoGrid, iki sütun, aralık 12; ikisi de düğme):
   - Sol: simge `tv`, simge rengi accent ("ok" tonu), etiket `settings.devices`, değer `devices.counts` (PS5 sayısı:
     eşlenmiş konsol varsa 1, yoksa 0; TV sayısı: TV eşlenmiş ve anahtarı kayıtlıysa 1, yoksa 0). Dokununca **Altyazı
     hedefi** (Route.target) açılır.
   - Sağ: simge `person.2.fill` (nötr), etiket `settings.psn`, değer PSN hesabının kimliği yoksa `devices.status.notsetup`,
     varsa `signin.status.done`. Dokununca PSN giriş ekranı (Route.psn).
4. **Cihaz listesi karosu** (Tile, satırlar arası 0, satırlar arasında 1 px ayraç):
   - Satır `devices.console`, simge `gamecontroller.fill`, sağda ayrıntı: Xbox seçiliyse "Xbox (Beta)" (çevrilmez),
     değilse "PlayStation 5". Sağda ok. → Konsol seçimi (Route.platform).
   - Satır: Xbox seçiliyse `settings.xbox` (ayrıntı: seçilen Xbox'ın adı), değilse `settings.ps5` (ayrıntı: eşlenen
     PS5'in adı; yoksa ayrıntı yok). Simge `gamecontroller`. → Route.ps5.
   - Yalnız Xbox seçili **ve** Microsoft girişi varsa: Microsoft oturumunu kapatan satır (katalogda yok),
     simge `person.crop.circle.badge.xmark`, sağda ok. Dokununca Microsoft oturumu kapanır (onay sorulmaz), satır kaybolur.
   - Satır `settings.target`, simge `tv`, ayrıntı: çıkış "yalnız bu cihaz" ise `devices.thisphone`; TV varsa TV'nin adı
     (ad yoksa "TV"); hiçbiri yoksa `devices.status.notsetup`. → Route.target.
5. **Tercihler karosu** (Tile, aralık 0, satır arası ayraç). Her satır bir Toggle: solda başlık (headline) ve altında
   açıklama (caption, secondary, dikey aralık 4); anahtar rengi accent; satırın üst/alt iç boşluğu 12.

   | # | Başlık | Açıklama | Sakladığı yer |
   |---|---|---|---|
   | a | `settings.notifications` | `packs.updates` | UserDefaults `notifyPackUpdates` (varsayılan açık). Kodda başka bir yerde okunmuyor; yalnız tercih olarak duruyor. |
   | b | `settings.ps5.connection` | `settings.notify.drop` | UserDefaults `notifyDisconnect` (varsayılan açık). **Açılınca hemen** bildirim izni istenir. |
   | c | `settings.pool.contribute` | `settings.pool.detail` | `UserSettings.sharePool` (varsayılan açık) |
   | d | `ask.suggest.whichgame` | `settings.gameask.detail` | `UserSettings.askGame` (açık) |
   | e | `settings.speaker` | `settings.speaker.detail` | `UserSettings.showSpeakerNames` (açık) |
   | f | `settings.read.fastcheck` | `settings.read.fastcheck.detail` | `UserSettings.fastSubtitleDetection` (kapalı) |
   | g | (yalnız Xbox seçiliyken) `xbox.audio.toggle` | `xbox.audio.detail` | `UserSettings.xboxAudioOnDevice` (açık) |

   Ayar değişince hemen etkisi: `sharePool` değişince havuz gönderimi ve çeviri havuzu açılır/kapanır; çeviri sürüyorsa
   paket eşleştirmesi yeniden kurulur. `showSpeakerNames` çalışan okuma hattına anında geçer.
6. **Yardım karosu** (Tile, aralık 0, satır arası ayraç; satırlar sağda oklu):
   - `settings.privacy`, simge `hand.raised`. Dışarıda tarayıcıda açılır:
     `https://github.com/yunusdemirbag/nino-game-translator#gizlilik`.
   - `settings.help`, simge `questionmark.circle`. Tarayıcıda: `https://github.com/yunusdemirbag/nino-game-translator/issues`.
   - `ask.title`, simge `bubble.left.and.text.bubble.right`. Sohbet sayfasını alttan açar (bölüm 6).
   - `report.title`, simge `exclamationmark.bubble`. Sorun Bildir sayfasını alttan açar (bölüm 5).
   - `settings.about`, simge `info.circle`, ayrıntı: uygulama sürümü (CFBundleShortVersionString, ör. "4.0.0").
     → Route.about.
7. **Telif satırı:** ortalanmış, caption, secondary: "Nino Game Translator <sürüm> · © 2026 Yunus Demirbağ · AGPL-3.0"
   (çevrilmez, sabit).
8. Alt düğme bölgesi boş.

### 1.2 Durumlar

- Xbox seçimi Profil'in üç yerini değiştirir: konsol satırının metni/ayrıntısı, çıkış satırı ve (g) anahtarı.
- PSN değer karosu canlıdır: giriş yapılınca geri dönüldüğünde `signin.status.done` olur.

---

## 2. Ayarlar ekranı (Route.settings)

Ana ekrandaki dişli düğmesinden açılır. Uzun, kayan tek sütun; içerik aralığı 12. En altta sabit duran bir düğme var.

### 2.1 Sıra

1. Geri başlığı `settings.title`.
2. Çeviri dili karosu (2.2)
3. (koşullu) GTA 6 karosu (2.3)
4. Çeviri motoru karosu (2.4)
5. Görünüm karosu (2.5)
6. Altyazı alanı karosu (2.6)
7. Ek alanlar karosu (2.7)
8. PS5 şifresi karosu (2.8)
9. Gezinme listesi karosu (2.9)
10. Cihaz bilgisi karosu (2.10)
11. Alt bölge: ikincil düğme `tv.test.send` (2.11)

### 2.2 Çeviri dili

- Başlık `settings.language` (headline).
- Altında dil seçici (LanguageFlags, adı gösteren biçimde; bkz. tasarim.md 6.4): hap biçimli düğme, içinde seçili dilin
  bayrağı (20 pt), dilin kendi adı (headline yarı kalın) ve aşağı ok. Basınca menü açılır; her satır "bayrak  ad".
  Seçim `UserSettings.targetLanguage`'i değiştirir (varsayılan "tr"; geçiş 0.2 sn yumuşak).
- Diller, sırayla: tr Türkçe 🇹🇷, ar العربية 🇸🇦, hi हिन्दी 🇮🇳, id Bahasa Indonesia 🇮🇩, th ไทย 🇹🇭, vi Tiếng Việt 🇻🇳,
  ur اردو 🇵🇰, bn বাংলা 🇧🇩, ms Bahasa Melayu 🇲🇾, tl Filipino 🇵🇭, nl Nederlands 🇳🇱.
- Seçili dil Türkçe **değilse** altında açıklama (caption, secondary): `settings.language.note`. Anlamı: paketler ve
  terim listesi yalnız Türkçe içindir; öbür dillerde altyazı seçilen motordan gelir; Urduca, Bengalce ve Filipince yapay
  zekâ motoru ister.
- Dil değişince: arayüz dili de o dile geçer, çeviri havuzunun dili güncellenir.

### 2.3 GTA 6 karosu (koşullu)

Görünme koşulu ("Nino havuzu etkin"): çeviri dili havuzun çevirdiği dillerden (şimdilik yalnız Türkçe) **ve** ya henüz
hiç oyun tanınmadı ya da tanınan oyun "havuz öncelikli" (şimdilik GTA 6). Başka bir oyun tanınınca karo kalkar.

- Başlık "GTA 6" (headline, çevrilmez).
- Durum etiketi (MobilePill, noktalı): Nino'nun GTA 6 için etkin olduğunu söyleyen kısa etiket (katalogda yok).
- Açıklama (caption, secondary; katalogda yok): GTA 6 altyazısının Nino'nun ortak çevirisinden geldiğini, her satırın
  bir kez çevrilip herkese aynı gittiğini, kullanıcının bir şey seçmesine ya da anahtar girmesine gerek olmadığını ve
  ücretsiz olduğunu anlatır.

### 2.4 Çeviri motoru

- Başlık: GTA 6 karosu görünüyorsa "diğer oyunlar" anlamında bir başlık (katalogda yok), değilse `settings.engine`.
- **Dört bölmeli segment** (SegmentedTabs): `engine.price.free`, "DeepL", "Gemini" (çevrilmez), `common.other`.
- `common.other` seçiliyken altında **ikinci segment**: "OpenAI" | "Claude" (çevrilmez).
- Motorun saklandığı yer: `UserSettings.translationEngine` doğrudan bir alan değildir, iki alandan hesaplanır:
  `onlineTranslation` (bool, varsayılan kapalı) ve `onlineEngine` (DeepL/Gemini/OpenAI/Claude, varsayılan DeepL).
  free (ücretsiz) seçimi = `onlineTranslation` kapalı. Başka bir seçim = `onlineTranslation` açık + `onlineEngine` o motor.
- Segmentin gösterdiği seçim: free → `engine.price.free`; deepL → DeepL; gemini → Gemini; openAI, claude ve yerel model → `common.other`
  (yerel model telefonda seçilemez, yalnız masaüstünde; telefonda `common.other` sayılır).
- Segment değişince: yazılmış anahtar alanı ve hata metni temizlenir. `common.other` seçilince motor, önceki Claude ise Claude,
  değilse OpenAI olur. Segment seçimi anahtar olmasa da hemen kaydedilir.
- **Eski iOS kartı** (koşullu): free seçiliyken **ve** cihazda Apple'ın cihaz içi çevirisi yoksa (iOS 26'dan eski)
  **ve** anahtarı kayıtlı bir çevrimiçi motor etkin değilse görünür. Turuncu çerçeveli kart: zemin warning @%8, kenar
  warning @%35 (1 pt), köşe 22, iç boşluk 16, öğe aralığı 10.
  - Başlık: `info.circle.fill` simgesi (warning rengi) + `oldios.title` (sistem headline).
  - Gövde (subheadline, secondary; %@ yerine sistem sürümü): `oldios.body`.
  - İki düğme, yan yana sığmazsa alt alta (aralık 10 / 8): (1) dolu mavi hap, `key.fill` simgesi, beyaz yazı
    `oldios.add` (subheadline yarı kalın, iç boşluk yatay 14 dikey 9). Ayarlar'da basınca motor Gemini'ye geçer
    (anahtar alanı açılır). (2) bağlantı, `arrow.up.right.square`, accent yazı `oldios.get`; Gemini anahtar sayfasını
    tarayıcıda açar.
- **Anahtar alanı** (motor free değilse): yükseklik en az 52, yatay iç boşluk 16, zemin surface2, köşe 16, ince
  kenar (border). İçinde yatay sıra, aralık 8, yazı headline normal kalınlık:
  - **Anahtar kaydedilmemişse:** gizli giriş alanı, yer tutucu `settings.engine.key` (%@ = motorun adı: "DeepL",
    "Gemini", "OpenAI", "Claude"); otomatik büyük harf ve düzeltme kapalı. Sağında accent renkli `common.save`
    düğmesi; alan boşken ya da denetim sürerken kapalı.
  - **Kayıtlıysa:** solda `settings.engine.key` yazısı, sağda yeşil (success) onay simgeli `settings.engine.saved`
    (caption) ve gri `xmark.circle.fill` düğmesi (erişilebilirlik adı `settings.engine.removekey`). Silme onay sormaz.
  - Denetim sürerken alanın altında accent renkli dönen gösterge.
  - Anahtar kabul edilmezse altında uyarı notu (MobileNote, warning): `settings.engine.badkey`.
- Kaydet davranışı: anahtar kırpılır; DeepL için hizmetin kullanım uç noktasına sorulur ("geçerli" ya da "kota dolu"
  kabul); yapay zekâ motorları için o motorla tek bir kısa deneme çevirisi yapılır (başarı, "kota dolu" ve "model
  reddedildi" kabul; diğer hatalar ret). Kabul edilirse anahtar **Anahtar Zinciri'ne** yazılır, alan boşalır, motor o
  motora geçer (zaten oysa ve çeviri sürüyorsa okuma hattı yeniden kurulur). Silince Anahtar Zinciri'nden kalkar; silinen
  motor seçiliyse `onlineTranslation` kapanır (free seçimine döner).
- Karonun en altında açıklama (caption, secondary): `settings.engine.packnote`.

### 2.5 Altyazının görünüşü

Tek karo, öğe aralığı 8. Bütün alanlar `UserSettings.style` (SubtitleStyle) içindedir; her değişiklik hemen kaydedilir
ve bağlı TV'ye yeni görünüm olarak gönderilir.

1. Başlık satırı: solda `settings.appearance` (headline), sağda "%120" gibi yüzde (caption, secondary; "%" işareti
   sayının **önünde**, Türkçe yazımla).
2. **Boyut kaydırıcısı:** %40–%160, adım 10, accent rengi. Saklanan alan `style.fontSize` (TV piksel boyu, varsayılan
   46). Gösterilen yüzde = fontSize/46 × 100, en yakın 10'a yuvarlanmış. Kaydırınca fontSize = 46 × yüzde/100
   (yuvarlanmış). Ör. %40 → 18, %100 → 46, %160 → 74.
3. **Önizleme şeridi:** örnek altyazı; tek satır, sığmazsa yarıya kadar küçülür. Yazı: seçili altyazı yazı tipi, yarı
   kalın, boyu 28 pt (iPad'de 36 pt) × ölçek (ölçek = yüzde/100, ama 0.8–1.6 arasına kıstırılır). Renk: beyaz ya da
   sarı #FFD54A. Zemin siyah @%85, köşe 8, yatay iç boşluk 12, dikey 8. Örnek metin: demo örnek satırlarının ilki
   (ana-ekran.md §4; Türkçede 1. satırın Türkçesi, başka dillerde o dilin listesinin ilki, yoksa Arapçası). Metin Arapça
   yazı içeriyorsa her satırın başına sağdan-sola işareti (U+200F) eklenir (zaten varsa eklenmez).
4. `subtitle.font` (caption, secondary) ve altında 2×2 yazı tipi ızgarası (bkz. tasarim.md 6.3). Sıra ve adlar:
   `pack.style.action` (Barlow Condensed, varsayılan), `subtitle.font.modern` (Barlow), `subtitle.font.rounded`
   (Nunito), `subtitle.font.system` (sistem yazısı). Her ad kendi yazı tipiyle 16 pt yarı kalın.
   Alan: `style.font` (condensed / modern / rounded / system).
5. Renk satırı: solda `subtitle.textcolor`; sağda iki daire (28×28), aralarında 8: beyaz ve sarı #FFD54A, ikisinin de
   ince borderStrong kenarı. Seçili olanın 4 pt dışında 2 pt accent halka. Erişilebilirlik adları
   `subtitle.color.white`, `subtitle.color.yellow`. Alan: `style.textColor` (white varsayılan / yellow).
6. Arka plan satırı: solda `subtitle.background`, sağda "%100" gibi değer. Altında kaydırıcı 0–100, adım 5. Alan:
   `style.background` (opaklık yüzdesi, varsayılan 100).
7. `subtitle.background.area` ve iki bölmeli segment: `subtitle.width.fit` (varsayılan), `subtitle.band.full`. Alan:
   `style.backgroundShape` (fit / band).
8. Açıklama: `subtitle.background.solidhint` (kaydırıcı sonuna çekilince zemin tam opak olur, İngilizce yazı kapanır;
   bant yanları da örter).
9. **Yalnız altyazı TV'de gösteriliyorsa** (çıkış TV ya da TV+telefon):
   - `settings.tvposition` ve dört bölmeli segment: `subtitle.layout.cover` (varsayılan), `subtitle.layout.above`,
     `subtitle.layout.below`, `subtitle.position.fixed`. Alan: `style.placement`.
   - `subtitle.position.fixed` seçiliyse: satır `subtitle.height.screen` + sağda "%7" gibi değer; kaydırıcı 0–85 (adımsız, tam sayıya
     yuvarlanır). Alan: `style.bottomPercent` (varsayılan 7). **Kaydırıcı bırakılınca** TV'ye deneme altyazısı
     gönderilir (2.11 ile aynı). Altında: `subtitle.position.hint` (bırakınca TV'de örnek çıkar; sabit yerde kumandanın
     ▲/▼ tuşları da taşır).
   - Diğer üç seçenekte: `subtitle.layout.hint` (örtme kipinde çeviri İngilizceyi kapatır; üstte/altta kipinde ikisi de
     görünür).
10. Anahtar: `settings.stack.lines` (headline); açıklama `settings.stack.detail` (kapalıysa yeni satır eskisini
    siler; TV tarafında 0.9.16 ya da daha yeni sürüm ister). Alan: `style.stackPrevious` (açık).
11. **Yalnız TV'de gösteriliyorsa:** `settings.picturemode`, iki bölmeli segment `target.inapp` (varsayılan),
    `settings.picturemode.overlay`. Alan: `style.displayMode` (inApp / overlay). Açıklama: `settings.picturemode.hint`.
    Anlamı: PS5 görüntüsü TV uygulamasında siyah kalıyorsa katman seçilir, TV PS5'i kendi HDMI girişinde gösterir ve
    altyazıyı üstüne koyar; görüntü gelmezse TV uygulaması önce HDMI girişlerini listeler; Google Play sürümünde katman
    yoktur ve TV bunu ekranda söyler.
12. Anahtar (en altta): `settings.watermark`; açıklama `settings.watermark.detail` (kapatınca yalnız sol alttaki küçük
    işaret gizlenir). Alan: `style.watermark` (açık).

SubtitleStyle'ın burada gösterilmeyen alanları (bold=false, theme=classic, autoSize=true) bu ekranda değişmez.

### 2.6 Altyazı alanı (kısa)

Ayrıntısı bölge önizlemesi tarifinde (tasarim.md 12). Karo:
- `settings.region`; dört bölmeli segment `region.bottom` (varsayılan), `region.top`, `subtitle.width.full`,
  `common.custom`. Alan: `UserSettings.areaPreset` (seçim aynı anda `region`'ı da o hazır bölgeye ayarlar).
- Altında son PS5 karesiyle canlı önizleme; çerçeve sürüklenir (sürükleme bölgeyi `common.custom` seçimine çevirir). Önizleme sağdan sola
  dillerde aynalanmaz. Kare yokken önizlemede `home.preview.empty`.
- `common.custom` seçiliyken iki kaydırıcı: `subtitle.position.vertical` (0 … 100−yükseklik) ve `subtitle.height` (en küçük bölge boyu …
  100); sağlarında yüzde.
- Altta: `region.edit.hint`.

### 2.7 Ek alanlar (kısa)

Bu karonun metinleri yeni katalogda henüz yok; anlamları:
- Başlık: ek alanlar. Açıklama: altyazıya ek olarak üç küçük bölge (ör. görev satırı, telefon mesajı, bildirim)
  tanımlanabildiğini, bunlara saniyede bir bakıldığını ve yalnız yazıları değişince yeniden çevrildiğini anlatır;
  Türkçesi TV'de oyundaki yazının hemen yanına konur.
- Her alan için surface2 zeminli (köşe 16, iç boşluk 12) bir düzenleyici: üst sırada ad alanı (yer tutucu: alanın adı),
  açma/kapama anahtarı (erişilebilirlik: bu alanı oku), çöp kutusu (erişilebilirlik `common.clear`); altında üç
  bölmeli segment: görev / bildirim / telefon; altında o alanın canlı önizlemesi (kapalıysa %50 soluk).
- Üçten az alan varsa ikincil düğme (+ simgesi, "ek alan ekle" anlamında); menüde üç hazır yer: görev (sağ üst),
  bildirim (sol alt), telefon (sağ alt). Yeni alanın adı seçilen türün adıdır.
- Alan: `UserSettings.extraAreas` (dizi; her öğe kimlik, ad, açık/kapalı, bölge). Varsayılan boş.

### 2.8 PS5 oturum şifresi

- Başlık `passcode.title`.
- Alan kutusu anahtar alanıyla aynı görünüm (52 yükseklik, surface2, köşe 16):
  - Şifre yoksa: gizli alan, yer tutucu `passcode.placeholder`, sayı klavyesi; yazılan rakam dışı karakterler atılır ve
    en çok 4 haneye kesilir. Sağda accent `common.save` (alan boşken kapalı).
  - Şifre kayıtlıysa: `passcode.saved` ve sağda gri çarpı (erişilebilirlik `passcode.remove`); onay sormadan siler.
- 4 haneden az kaydedilmeye çalışılırsa uyarı notu: `passcode.prompt`.
- Açıklama: `passcode.note` (yalnız ikinci hesabın PS5'te giriş şifresi varsa gerekir; Nino PS5 isteyince girer;
  Anahtar Zinciri'nde durur).
- Saklama: Anahtar Zinciri (UserSettings değil). Sonraki PS5 bağlantısında PS5 isterse gönderilir.

### 2.9 Gezinme listesi

Tek karo, aralık 0, satır arası ayraç, satırlar sağda oklu:

| Satır | Simge | Ayrıntı | Gittiği yer |
|---|---|---|---|
| `settings.packs` | `bolt.fill`, pro (lacivert) rengi | `gamePacks` açıksa `common.on`, değilse `common.off` | Route.packs |
| `settings.target` | `tv` | Profil'deki ile aynı kural (`devices.thisphone` / TV adı / `devices.status.notsetup`) | Route.target |
| `tv.install.fromphone` | `arrow.down.app` | Bu telefonun kurduğu ya da sürümünü okuduğu TV uygulamasının sürümü; yoksa boş | Route.tvInstall |
| `settings.ps5` | `gamecontroller` | PS5'in adı | Route.ps5 (Xbox seçiliyse de bu metin; yönlendirme Xbox ekranına) |
| `ask.title` | (bkz. 1.1) | — | sohbet sayfası |
| `report.title` | (bkz. 1.1) | — | Sorun Bildir sayfası |
| `settings.about` | `info.circle` | sürüm | Route.about |

### 2.10 Cihaz bilgisi

- Başlık `diag.deviceinfo`.
- Satırlar (aralık 8; her satır solda etiket secondary, sağda değer text, sağa hizalı, caption; uzun değer alt satıra
  kayar). Boş değerli satır gösterilmez. Sıra ve etiketler:

  | Kimlik | Etiket | Değer |
  |---|---|---|
  | app | `diag.appversion` | "4.0.0 (19)" (kısa sürüm + yapı numarası; yapı yoksa yalnız sürüm) |
  | device | `diag.devicemodel` | donanım model kodu, ör. "iPhone17,1" (simülatörde simüle edilen model) |
  | system | `diag.os` | "iOS 27.0.1" (yama 0 ise "iOS 27.0") |
  | tv | "TV" | Marka (LG / Samsung / Android TV); TV uygulaması modelini bildirdiyse model (marka adıyla başlamıyorsa "Samsung QE65Q80C" gibi önüne marka eklenir); TV uygulamasının sürümü biliniyorsa sonuna " · TV uygulaması 4.0.0". TV'nin kullanıcı verdiği **adı kullanılmaz**. |
  | console | `devices.console` | PS5 eşliyse "PS5 · Remote Play"; Xbox seçiliyse "Xbox · <model>" (model yoksa "Xbox"); konsol adı kullanılmaz |
  | status | `diag.status.current` | Yalnız çeviri sürerken: `status.connected` / `status.connecting` / PS5 reddi onaltılık kodla "0x80108b12" / adres ya da ağ yoksa `session.error.unreachable` / diğer kopmalar `status.reconnecting` / uyku, kullanımda, şifre, kayıt geçersiz, Remote Play kapalı, görüntü yok gibi nedenlerde PS5 durum metni. Oyun biliniyorsa virgülle "oyun: <ad>" eklenir. |

  Değerlerden satır sonları atılır, "|" işareti "/" olur, IP adresleri (port dahil) "(adres)" ile değiştirilir.
- Açıklama: `diag.deviceinfo.note` (sorun bildirimine eklenir; ad, seri numarası ya da adres içermez).
- İkincil düğme `diag.deviceinfo.copy`. Basınca panoya tek satırlık özet yazılır ve düğme 2 saniye `common.copied`
  olur. Özet biçimi: `app: 4.0.0 (19) | device: iPhone17,1 | system: iOS 27.0 | tv: … | console: … | status: …`
  (kimlikler çevrilmez; en çok 600 karakter). Aynı özet Sorun Bildir ve Nino'ya Sor isteklerinde `device` alanı olarak
  gider.

### 2.11 Alt düğme: deneme altyazısı

İkincil düğme `tv.test.send` (beyaz cam hap). Basınca altyazı sunucusu çalışmıyorsa başlatılır, güncel görünüm
gönderilir ve `tv.test.text` metni 8 saniyeliğine TV'ye (ve telefon ekranına) gönderilir.

---

## 3. Hakkında ekranı (Route.about)

- Geri başlığı `settings.about`.
- Tek karo, öğe aralığı 8, sola hizalı:
  1. Logo, 56 pt.
  2. "Nino Game Translator <sürüm>" (title, çevrilmez).
  3. "Nino © 2026 Yunus Demirbağ" (caption, secondary, çevrilmez).
  4. `about.license` (body, secondary).
  5. Türetme bildirimi satırı (caption, secondary, çevrilmez): depodaki `NOTICE` dosyasındaki türetme bildirimi aynen
     gösterilir; metin o dosyadan alınır (bu belgede yazılmaz). Lisansın istediği tek yer burasıdır.
  6. Bağlantı `about.source` (headline, accent): `https://github.com/yunusdemirbag/nino-game-translator`.
- Alt bölge boş.

---

## 4. Oyun paketleri ekranı (Route.packs)

Paketler herkese ücretsizdir: bir kısmı uygulamayla gelir, yenileri ve güncellemeleri herkese açık paket sunucusundan
iner. Kullanıcı ayrıca kendi topluluk çeviri dosyasını içe aktarabilir.

### 4.1 Düzen

1. Geri başlığı `settings.packs`; sağında nötr etiket (MobilePill) `engine.price.free`.
2. Açıklama (body, secondary): `packs.auto.note` (paket oyun açılınca kendiliğinden seçilir; pakette olmayan satırlar
   seçilen motorla çevrilir).
3. **Ana anahtar karosu:**
   - Çeviri dili Türkçe değilse en üstte not (caption, secondary): `packs.turkishonly`.
   - Toggle: başlık `settings.packs.toggle` (headline); altında özet (caption, secondary): "<N> oyun · <M> bin satır ·
     internetsiz" biçiminde. Parçalar: `packs.count.games`; satır sayısı ≥1000 ise `packs.count.klines` (binlere bölünüp
     aşağı yuvarlanır), değilse `packs.count.lines`; `packs.offline`; ayraç " · ". Toplam satır = kurulu bütün paketlerin
     satır sayısı toplamı.
   - Alan: `UserSettings.gamePacks` (varsayılan açık). Paketler yalnız kaynak İngilizce + hedef Türkçe ve bu açıkken
     kullanılır. Değişince çalışan okuma hattı yeni ayarla yeniden eşleşir.
4. **Güncelleme durumu** (yalnız durum varsa; metinleri katalogda yok):
   - İniyorken: pro renkli küçük dönen gösterge + paketlerin güncellendiğini söyleyen kısa satır (caption).
   - Başarısızsa: secondary tonlu uyarı notu (MobileNote) ve neden: ağ yok → internet olmadığı ve telefondaki paketlerin
     kullanıldığı; sunucu hatası, bozuk yanıt ya da SHA-256 tutmazlığı → paketlerin güncellenemediği ve telefondakilerin
     kullanıldığı; başka hata → sistemin hata metni.
5. Kurulu paket varsa ipucu (caption, secondary): `packs.toggle.hint`.
6. **Paket ızgarası** (BentoGrid, iki sütun, aralık 12; bir satırdaki iki karo eşit yükseklik). Sıra: paket
   kütüphanesinin verdiği sıra: klasörler sırayla okunur (uygulamayla gelenler, indirilenler, içe aktarılanlar), her
   klasörde dosya adına göre alfabetik; aynı kimlikli paket sonradan okunursa öncekini listeden çıkarır ve listenin sonuna
   eklenir. Bozuk dosya sessizce atlanır. Satır sayısı = paketin `entries` sayısı. Her karo bir düğme:
   - Karo içinde üst sıra: solda oyun rozeti (GameMonogram, 44×44, surface2, köşe 8, kısaltma caption yarı kalın);
     sağda etiket: paket şu an satır veriyorsa noktalı yeşil `home.nowplaying` (sıkı biçim); paket kapalıysa nötr
     `common.off`.
   - Esnek boşluk (en az 8), sonra oyunun adı (headline, en çok 2 satır), altında satır sayısı (`packs.count.klines` /
     `packs.count.lines`).
   - **Kısaltma kuralı:** başlık harf/rakam dışı karakterlerden bölünür; tek sözcükse ilk 3 harf büyük harfle
     ("Minecraft" → "MIN"); birden çok sözcükse ilk üç sözcüğün baş harfleri büyük harfle ("Grand Theft Auto V" → "GTA",
     "Mafia: The Old Country" → "MTO").
   - **Oynanıyor koşulu:** çeviri sürüyor ve son satırı veren paketin başlığı bu paketin başlığı. Bu durumda karo seçili
     vurguyla (1.5 pt accent kenar) çizilir.
   - **Soluk:** paket kapalıysa ya da ana anahtar kapalıysa karo %50 opak.
   - **Dokununca:** paket açılır ya da kapanır (onay yok). Kapatılan paket kimlikleri UserDefaults `disabledPacks`
     (sıralı metin dizisi) içinde saklanır. Okuma hattı hemen yeni listeyle eşleşir. Erişilebilirlik değeri `common.on` /
     `common.off`.
7. **İçe aktarılmış paketler bölümü** (4.3).
8. **Bilgi karosu:** yatay sıra (aralık 12): `arrow.down.circle` simgesi; başlık `packs.comingsoon` (headline), altında
   `packs.updates.detail` (caption, secondary).
9. Alt bölge: ikincil düğme `packs.updateNow`. Basınca zorla yenileme (4.4). İnerken ya da sunucu adresi tanımlı
   değilken kapalı (%40 opak).

### 4.2 Paket kütüphanesi ve dosya yerleri

- **Uygulamayla gelen paketler:** uygulama paketinin içindeki `packs` klasörü (`<kimlik>.json.gz`).
- **İndirilen paketler:** `Application Support/Nino/Packs/files/<kimlik>.json.gz`. Aynı klasörde `manifest.json` (son
  liste) ve boş `refreshed` dosyası (değişiklik tarihi = son yenileme zamanı) durur.
- **İçe aktarılmış paketler:** `Application Support/Nino/Packs/imported/<kimlik>.json`; kimlik her zaman `community-` ile
  başlar. Sunucu yenilemesi yalnız `files` klasörünü temizlediği için bunlar silinmez.
- Okuma sırası: uygulamayla gelenler → indirilenler → içe aktarılanlar. Aynı kimlik sonradan okunan kazanır (indirilen
  paket gelenin, içe aktarılan da öncekilerin yerini alır).
- **Paket dosyası biçimi** (gzip'li ya da düz JSON): `{"format":1,"id":"…","title":"…","entries":{"<anahtar>":"Türkçe"}}`.
  Biçim 2 ayrıca `segments` (aynı anahtar→Türkçe düzeni) ve `fuzzy` (bozuk OCR satırını bulma imzaları) taşır. Yalnız
  `{anahtar: Türkçe}` nesnesi de kabul edilir (kimlik ve başlık dosya adından). İngilizce metin dosyada **yoktur**.
- **Anahtar:** İngilizce satırın kanonik biçiminin SHA-256'sının ilk 8 baytı, 16 haneli küçük harf onaltılık. Kanonik
  biçim: en çok 40 karakterlik `<…>` biçim etiketleri boşluk olur → NFKC → küçük harf → NFD ile aksan/işaretler atılır →
  harf ve rakam dışı her şey boşluk → boşluklar teklenir, baş-son kırpılır. Harf/rakam yoksa anahtar yok. (Bu kural
  Mac, Windows ve Android ile birebir aynıdır; ortak deneme verisi çekirdekteki "golden vectors" dosyasında.)

### 4.3 İçe aktarılmış paketler bölümü

Bu bölümün metinleri yeni katalogda henüz yok; aşağıda anlamlarıyla anılır.

1. Başlık bloğu (aralık 8): içe aktarılmış paketler başlığı (headline); açıklama: topluluk çeviri dosyasının (JSON, TXT
   ya da iki dilli SRT) oyun paketi olarak eklenebildiğini, dosyanın telefonda kaldığını ve hiçbir yere gitmediğini
   söyler.
2. İçe aktarılmış paket varsa liste karosu: başlığa göre (büyük/küçük harf duyarsız) sıralı; satırlar arası ayraç; her
   satır en az 52 yüksek: solda ad (headline, en çok 2 satır) ve satır sayısı (caption, secondary), sağda kırmızı (danger)
   silme düğmesi `common.clear` (headline).
   - Silmeye basınca alttan çıkan onay menüsü (başlığı görünür): paketin silinip silinmeyeceğini soran başlık; mesajda
     paket adı (%@) ile birlikte paketin bu telefondan silineceği ve yeniden kullanmak için dosyanın yeniden içe
     aktarılması gerektiği; yıkıcı silme düğmesi (ve sistemin vazgeç düğmesi `common.cancel`). Onaylanınca dosya silinir,
     kütüphane yeniden okunur, liste yenilenir.
3. Hata varsa uyarı notu (warning).
4. İkincil düğme: paket içe aktarma ("…" ile biten); dosya okunurken kapalı. Basınca hata temizlenir ve sistemin
   dosya seçicisi açılır. Kabul edilen türler: JSON, düz metin, `.srt`.
5. **Okuma:** dosya güvenlik kapsamlı erişimle okunur; 64 MB'den büyükse ret. Hatalar:
   - Seçici hata verirse ya da dosya okunamazsa: çeviri dosyasının okunamadığını söyleyen not.
   - Biçim hatası (desteklenmeyen uzantı, UTF-8 değil, bozuk JSON, desteklenmeyen paket biçimi, çok büyük): dosyanın içe
     aktarılamadığını, biçimine ve karakter kodlamasına bakılmasını söyleyen not.
6. **Desteklenen dosyalar** (başta UTF-8 BOM varsa atılır; satır sonları CRLF/CR → LF):
   - **JSON, Nino paket biçimi:** `format` sayısı varsa 1 olmalı (değilse "desteklenmeyen biçim"), `entries` nesnesinin
     anahtarları zaten 16 haneli onaltılık anahtardır (büyük harf de olur, küçültülür; değilse kayıt geçersiz sayılır).
     Başlık önerisi: `title`, yoksa `game`.
   - **JSON, altyazı sözlüğü:** `{"game": "…", "subtitles": {"İngilizce": "Türkçe", …}}`; başlık önerisi `game`, yoksa
     `title`. `format` olmayıp `entries` varsa reddedilir.
   - **JSON, düz sözlük:** `{"İngilizce": "Türkçe", …}`; başlık önerisi yok.
   - JSON kökü nesne olmalı. Aynı İngilizce satır dosyada birden çok kez geçebilir; JSON çözülürken tekrarlar kaybolmamalı,
     her geçiş sırasıyla ayrı sayılır (bkz. sayım kuralları). `title`/`game`/`entries` gibi alanlar birden çok kez varsa
     sonuncusu geçerlidir.
   - **TXT:** her satır ya "İngilizce<SEKME>Türkçe" (tam iki sütun) ya da "İngilizce = Türkçe". Boş satırlar ve `#` ile
     başlayanlar atlanır; diğer her satır geçersiz kayıt.
   - **SRT (iki dilli):** boş satırla ayrılan her blok tam 4 satır olmalı: sıra numarası (yalnız rakam), zaman satırı
     ("SS:DD:ss,mmm --> SS:DD:ss,mmm", başlangıç bitişten önce), İngilizce satır, Türkçe satır. Uymayan blok geçersiz.
   - İngilizce metinler 4.2'deki kurala göre anahtara çevrilir.
   - **Sayım kuralları:** anahtar çıkmazsa ya da Türkçe boşsa → geçersiz kayıt. Aynı anahtar aynı Türkçeyle tekrar →
     yinelenen çift. Aynı anahtar farklı Türkçeyle → çakışma: o anahtar paketten tamamen çıkar; sonraki tekrarları da
     yineleme ya da çakışma olarak sayılır.
7. **Önizleme sayfası** (alttan açılan, içerik kadar yükseklikte, tutamaçlı; zemin surface; iç boşluk 20; aralık 12;
   kurulum sürerken aşağı kaydırıp kapatılamaz):
   - Başlık: oyun paketini içe aktarma (title).
   - Oyunun adı etiketi (caption, secondary) ve altında 52'lik giriş alanı (yer tutucu aynı etiket).
     Başlangıç değeri: dosyadan gelen başlık önerisi, yoksa uzantısız dosya adı.
   - Dört sayı satırı (body; solda etiket secondary, sağda eşit genişlikli rakamla sayı): kullanılabilir satır,
     geçersiz kayıt, yinelenen çeviri çifti, çakışan satır.
   - Kullanılabilir sayı 0 ise uyarı: dosyada kullanılabilir çeviri olmadığı.
   - Kurulum hatası (danger tonlu not): paketin kurulamadığı.
   - Birincil düğme: paketi kur (kurulurken solunda dönen gösterge). Ad boşsa, satır yoksa ya da kurulum sürerken kapalı.
   - Hayalet düğme `common.cancel` (kurulurken kapalı).
   - **Kurulum:** kimlik = `community-` + başlıktan üretilen kısa ad (ASCII harfler küçültülür, rakamlar kalır, aradaki
     her harf/rakam dışı dizi tek "-" olur, en çok 80 karakter; hiç harf yoksa "game"). Dosya
     `{"format":1,"id","title","entries"}` olarak `imported/<kimlik>.json`'a önce geçici dosyaya yazılıp tek adımda
     yerine konur. Aynı kimlik varsa uyarı penceresi: paketin değiştirilip değiştirilmeyeceğini soran başlık; mesajda bu
     kimlikle kurulu bir paket olduğu ve değiştirilirse üstüne yazılacağı; düğmeler `common.cancel` ve yıkıcı "paketi
     değiştir" (üstüne yazarak kurar). Başarıda kütüphane yeniden okunur, liste yenilenir, sayfa kapanır.

### 4.4 Paket sunucusu API'si

- **Adres:** derleme ayarındaki `PACKS_API_BASE_URL` değeri uygulama bilgi dosyasına bir anahtar olarak girer (yeni
  uygulamada anlamlı bir ad seçin, ör. `NinoPacksBaseURL`). Değer boşsa ya da `$(` ile başlıyorsa sunucu yok sayılır:
  yalnız uygulamayla gelen paketler kullanılır, `packs.updateNow` düğmesi kapalı kalır. Yayındaki adres
  `https://nino-packs.<hesap>.workers.dev` biçimindedir (Cloudflare Worker, kimlik/anahtar istemez).
- **`GET <kök>/v1/packs`** → `{"packs":[{"id","title","version","sha256","size","entries"}, …]}`.
  `title` yoksa kimlik kullanılır; `version` sayı ya da metin olabilir (yalnız bilgi); `sha256` indirilen dosyanın
  (gövdenin, sıkıştırılmış hâliyle) küçük harf onaltılık SHA-256'sı; `size`, `entries` isteğe bağlı. Sunucu otomatik
  paketlerde ayrıca `auto`, `titleId` verebilir; uygulama bunları yok sayar.
- **`GET <kök>/v1/packs/<id>`** → `<id>.json.gz` gövdesi.
- Her istekte zaman aşımı 30 sn. 2xx dışı yanıt "sunucu hatası", ağ hatası "internet yok" sayılır. Sunucu IP başına
  saatte 60 indirmeye izin verir (aşınca 429).
- **Yenileme algoritması:** (zorla değilse son yenilemeden bu yana süre dolmadıysa hiçbir şey yapma) → listeyi al →
  `files` klasörünü oluştur → listedeki her paket için: önceki `manifest.json`'daki SHA-256 aynıysa ve dosya varsa atla;
  değilse indir, SHA-256'yı denetle (tutmazsa hata ver, dosyayı yazma), dosya adını kimlikten yalnız harf/rakam/-/_
  bırakarak üret, tek adımda yaz → listede olmayan dosyaları `files` klasöründen sil → yeni listeyi `manifest.json`'a
  yaz → `refreshed` dosyasının tarihini şimdi yap. Dönen değer: indirilen paket sayısı. Sayı > 0 ise kütüphane yeniden
  okunur, ölçüm olayı "packsUpdated(count)" gönderilir, okuma hattı ve ekrandaki liste yenilenir.
- **Ne zaman:** uygulama açılınca hemen (zorla); sonra uygulama açık kaldıkça 24 saatte bir (zorla değil, 24 saat
  sınırıyla); PS5'te yeni oyun tanınınca son bakış 10 dakikadan eskiyse; `packs.updateNow` ile hemen (zorla).

---

## 5. Sorun Bildir (alttan açılan sayfa)

Profil ve Ayarlar listesindeki `report.title` satırından, ayrıca Nino'ya Sor sohbetindeki bildirim düğmesinden açılır.
Taslak **uygulama açık kaldıkça bellekte** durur: sayfa aşağı kaydırılıp kapatılsa da yazılanlar, fotoğraflar ve seçimler
kaybolmaz. Gönderildikten sonra sıfırlanır.

### 5.1 Düzen

Sayfa zemini bg (#EEF3FB) üstünde MobileScreen yapısı (aynı boşluklar, kayan içerik, alt düğme bölgesi).

1. **Üst satır** (44 yükseklik): solda `report.title` (title), sağda kapat düğmesi (IconButton `xmark`, erişilebilirlik
   `common.close.alt`).
2. **Nino'nun gördükleri karosu:**
   - Başlık `report.noticed` (headline).
   - Son 3 gündeki olay kaydı boşsa **ve** sağlık özetinde muhtemel sebep yoksa: `report.noissue` (caption, secondary).
   - Değilse: muhtemel sebep cümlesi (body yarı kalın; sağlık ekranındaki birinci sebebin başlığı) ve son 3 günün en yeni
     6 olayı, en yenisi üstte: "• 14:05  <olayın başlığı>" (caption, secondary; saat kısa biçim, ardından iki boşluk).
   - İkincil düğme `settings.sendproblems`: açıklama yazılmadan hemen gönderir (5.3). Gönderilemezken kapalı.
3. **Açıklama karosu:** başlık `report.more.title`; altında çok satırlı metin alanı: en az 130 yüksek, body, zemin
   surface2, köşe 16, ince kenar, yatay iç boşluk 8. Boşken yer tutucu (tertiary renk, 5/8 iç boşluk):
   `report.description.placeholder`. Metin değişince önceki hata kalkar.
4. **Fotoğraf karosu** (metinleri katalogda yok): başlık satırı "fotoğraf ya da ekran görüntüsü" anlamında bir başlık +
   sağda "1/3" sayacı (caption, secondary). Altında yatay sıra (aralık 12):
   - Her ekli fotoğraf 88×88 küçük resim (doldurarak kırpılmış, köşe 12 sürekli); sağ üstünde 4 pt içeride 20 pt
     `xmark.circle.fill` (beyaz çarpı, siyah @%60 daire), erişilebilirlik adı "fotoğrafı kaldır" anlamında.
   - 3'ten az ise "ekle" kutusu: 88×88, 1 pt kesik çizgili (5/4) borderStrong kenar, köşe 12; içinde 22 pt simge
     (`photo.badge.plus`, hazırlanırken `hourglass`) ve kısa "ekle" etiketi (caption); renk accent. Basınca sistemin
     foto seçicisi, yalnız görseller, en çok kalan sayı kadar seçim.
   - Okunamayan dosya seçildiyse uyarı: dosyanın fotoğraf olarak okunamadığını söyleyen not.
5. **İletişim karosu:** başlık `report.contact.title`; 52'lik giriş alanı, yer tutucu `report.contact.placeholder`
   (e-posta klavyesi, otomatik büyük harf ve düzeltme kapalı). Ayraç. Toggle `report.log.include`, açıklama
   `report.log.note` (varsayılan açık; formun kendi alanı, UserSettings değil).
6. **Otomatik bildirim karosu:** Toggle `settings.autoreport`; açıklama `settings.autoreport.detail` (kopmada ne
   olduğu, ne zaman, ağ türü, cihaz ve TV modeli gider; günlük, altyazı, ad, adres gitmez). Alan:
   `UserSettings.autoReport` (varsayılan açık).
7. Gönderim hatası varsa uyarı notu (5.4).
8. Alt açıklama (caption, secondary): `report.privacy.note`.
9. **Alt bölge:** birincil düğme `common.send`; gönderirken solunda beyaz dönen gösterge ve `report.status.sending`.
   Kapalı olduğu durumlar: gönderiliyor, fotoğraf hazırlanıyor, gönderildi. (Açıklama boşken de gönderilebilir.)
   Gönderme sırasında alanlar ve anahtarlar kapalı.
10. **Gönderildi durumu:** yukarıdaki her şeyin yerine tek karo: yeşil 28 pt `checkmark.circle.fill` + `report.thanks`
    (headline). Alt düğme gizlenir. 1.6 sn sonra form sıfırlanır ve sayfa kendiliğinden kapanır.

### 5.2 Fotoğraf hazırlama

Seçilen her görsel (JPEG, PNG, HEIC…) arka planda: döndürme bilgisi uygulanır, en uzun kenar en çok 1600 piksele
küçültülür, saydam alanlar beyaz zemine basılır (sRGB), JPEG kalite 0,7 ile kodlanır. 900 000 baytı geçerse sırayla
kalite 0,55 ve 0,4 denenir; yine sığmazsa kenar 3/4'üne indirilip tekrarlanır (200 pikselin altına inmez). Hiç
olmazsa "okunamadı" sayılır. En çok 3 fotoğraf.

### 5.3 Ne gönderilir, nereye

- **Uç nokta:** `POST <havuz sunucusu>/v1/reports`. Havuz sunucusunun kökü sırayla: `NINO_POOL_URL` ortam değişkeni →
  UserDefaults `ninoPoolURL` → yayın adresi `https://nino-pool.y-demirbag2506.workers.dev`. Yalnız http/https kabul.
- Başlıklar: `Content-Type: application/json`, `User-Agent: nino-report/1 (ios; <sürüm>)`. Zaman aşımı 120 sn.
- **Gövde** (JSON, anahtarlar alfabetik sıralı, "/" kaçırılmadan):

  | Alan | İçerik |
  |---|---|
  | `v` | 1 |
  | `install` | Kuruluş kimliği: ortak havuzun kullandığı rastgele kimlikle aynı (sunucu tuzlayıp özetler, IP tutmaz) |
  | `app` | uygulama kısa sürümü |
  | `platform` | "ios" |
  | `language` | çeviri dili kodu (ör. "tr") |
  | `text` | 5.5'teki tanı metni (en çok 4000 UTF-16 birimi) |
  | `contact` | iletişim; boşsa alan hiç yazılmaz; en çok 200 karakter |
  | `log` | günlük açıksa ve günlük varsa (5.6); yoksa alan yok |
  | `images` | `[{"mime":"image/jpeg","data":"<base64>"}]`, en çok 3; yoksa alan yok |
  | `device` | Cihaz bilgisi özeti (2.10), en çok 600; boşsa yok |
  | `kind` | yalnız otomatik bildirimde "auto" (elle gönderimde yok) |

- Gövde 4 MB'yi geçerse gönderilmeden "çok büyük" hatası.
- Yanıt: 2xx ve `{"ok":true,"id":"…"}` → gönderildi (`ok:false` gelirse sunucu hatası). 400 → reddedildi, 413 → çok
  büyük, 429 → bugün çok bildirim, diğerleri → sunucu hatası; ağ hatası → çevrimdışı.

### 5.4 Hata metinleri

| Hata | Metin anahtarı |
|---|---|
| 429 | `report.error.dailylimit` |
| ağ yok / sunucu adresi yok | `report.error.network` |
| çok büyük | `report.error.toolarge` |
| reddedildi / sunucu hatası | `report.error.generic` |

Hata sonrası form korunur; kullanıcı metni değiştirince hata kalkar.

### 5.5 Tanı metni (`text` alanı)

Parçalar boş satırla birleşir:
1. Kullanıcı bir şey yazdıysa onun kırpılmış metni. Yazmadıysa (elle gönderim): "elle gönderildi,
   kullanıcı açıklama yazmadı" anlamında sabit bir giriş satırı (değeri `ReportProblemSheet.swift` içinde). Otomatik bildirimde de buna benzer, otomatik
   olduğunu belirten bir giriş satırı.
2. bulgular başlığı satırı; muhtemel sebep varsa onun başlığı; son 3 günde olay varsa son sorunlar
   başlığı ve en çok son 12 olay madde olarak; en sonda sağlık özeti (ağ türü dahil).
Bu sabit Türkçe parçalar sunucu tarafı içindir, çevrilmez. Tamamı en çok 4000 UTF-16 birimi: ilk 4000 birim tutulur,
sonu atılır (bölünen karakter bırakılmaz).

### 5.6 Günlük

Günlük açıksa gönderimden önce açık günlükler diske yazdırılır, sonra üç dosyanın sonları birleştirilir: Remote Play
günlüğü, altyazı günlüğü, TV kurulum günlüğü. En başa başlık satırı: "Nino iOS <sürüm>, <sistem adı> <sistem sürümü>,
<cihaz türü>". Her dosya "=== <dosya adı> ===" başlığıyla; toplam en çok 60 000 UTF-16 birimi, pay dosyalara bölünür
(kısa dosyanın artan payı ötekilere kalır), her dosyadan **en yeni** satırlar alınır (ortadan başlıyorsa yarım ilk satır
atılır).

**Gizli bilgi temizliği** (günlük ve başlıkta): "Bearer/Basic <jeton>" → "Bearer [gizli]"; adı key, token, secret,
password, passwd, passcode, auth, credential, cookie, session_id ile biten alanların `=` ya da `:` sonrası değeri →
"[gizli]"; Google anahtarları (AIza…), "sk-…" anahtarları ve DeepL'in ":fx" ile biten anahtarları → "[gizli]"; ayrıca
32+ karakterlik base64/onaltılık diziler, içinde en az 4 harf ve 4 rakam varsa ve yol gibi görünmüyorsa (eğik çizgi
sayısı uzunluğun 1/16'sından azsa) → "[gizli]".

### 5.7 Otomatik bildirim

`autoReport` açıksa ve bu çeviri oturumunda henüz gönderilmediyse, kullanıcıya bir şey göstermeden aynı uç noktaya
gönderilir: `text` = otomatik tanı metni, `device` = cihaz özeti, `contact`/`log`/`images` yok, `kind` = "auto".
Tetikleyiciler: (a) çeviri oturumu biterken oturumda olay kaydedildiyse ya da bağlantı/çeviri sağlığı "sorun"
düzeyindeyse; (b) çeviri sürerken ve uygulama öndeyken PS5'e bir süre ulaşılamazsa. Sınırlar: oturum başına en çok bir,
günde en çok 3. Ağ yoksa bildirim saklanır, sonra yeniden gönderilir.

---

## 6. Nino'ya Sor (kurulum yardımcısı)

### 6.1 Robot düğmesi (yüzen)

- Yer: kök görünümün sağ altı, sağdan 20 pt. Ana ekranda alttan 12 pt; karşılama ve kurulum ekranlarında alttaki büyük
  düğmenin ve üstündeki ikinci satırın üstünde durur (alttan 52 + 44 + 20 + 3×12 = 152 pt).
- Görünme: karşılama ve kurulumda hep; ana ekranda yalnız gezinme yığını boşken ve tanıtım turu bittiyse. Alt sayfalarda
  yok. Çıkış/giriş: ölçek + saydamlık geçişi.
- Görünüm: 62×62 beyaz @%95 daire, ince border kenar, gölge pro @%22 yarıçap 14 y 6; içinde 46 pt robot yüzü (süzülme
  açık, göz kırpma açık; bkz. tasarim.md 11.1). Basılınca 0.92'ye küçülür (yay, tepki 0.25, sönüm 0.7).
- Erişilebilirlik adı `ask.title`. Basınca sohbet sayfası alttan açılır.
- **"Çeviri başladı" balonu:** çeviri başlayınca robotun solunda (aralık 10) 7 saniye kapsül balon çıkar: siyah @%70
  zemin, beyaz 15 pt kalın yazı, iç boşluk yatay 16 dikey 11; sağdan kayarak + saydamlıkla gelir (yay 0.4/0.8), 0.4 sn
  sönerek gider. Çeviri durursa hemen (0.25 sn) gider. Metin: "Nino:" ile başlayan, altyazı çevirisinin başladığını
  söyleyip iyi oyunlar dileyen tek cümle. Arayüz diline göre seçilir (tr, ar, bn, fil, hi, id, ms, nl, th, ur, vi; diğer
  dillerde İngilizcesi). Yeni katalogda henüz anahtarı yok; eklenirken her dil için bir değer yazılmalı.

### 6.2 Sohbet sayfası

Alttan açılan sayfa, zemin MobileBackground (sayfa zemini bg). Üç parça, aralıksız dikey: başlık, mesajlar, yazma alanı.
Sohbet **uygulama açık kaldıkça bellekte** tutulur (sayfa kapanıp açılınca kalır; uygulama yeniden açılınca boş).

**Robot metinlerinin dili:** robotun metinleri (selamlama, öneriler, hata bildirimleri, `settings.setuphelper` vb.)
sistem dilinden değil **arayüz dilinin** (= çeviri dili) metin tablosundan okunur; bulunamazsa İngilizcesi. Öneri
çiplerine basınca **o dildeki metin** sunucuya gider.

1. **Başlık** (yatay 20, üst 20, alt 8; aralık 12): 50×50 beyaz @%95 daire içinde 42 pt robot yüzü (bekleme sürerken
   "düşünüyor": baş sallar); yanında "Nino" (sistem headline) ve altında `settings.setuphelper` (subheadline,
   secondary). Sağda: sohbet boş değilse "yeni sohbet" simge düğmesi (`square.and.pencil`, erişilebilirlik
   `ask.newchat`; basınca bekleyen istek iptal edilir, her şey silinir); en sağda kapat (`xmark`, `common.close.alt`).
2. **Mesajlar** (kayan, tembel dikey yığın, aralık 12, yatay 20, dikey 12; kaydırınca klavye etkileşimli kapanır):
   - Her zaman en üstte robotun selamlama balonu: `ask.greeting` (kendini tanıtır, kurulumla ilgili her şeyin
     sorulabileceğini söyler ve hangi cihazların olduğunu sorar).
   - Sohbet boşken altında öneri çipleri (soldan 36 pt içeride, sığmayan alt satıra geçer, aralık 8):
     `setup.combo.tvphone`, `setup.combo.monitor`, `setup.combo.xbox`, `ask.suggest.tvinstall`. Çip: kapsül, beyaz @%90
     zemin, accent @%30 kenar, accent yazı subheadline orta kalın, iç boşluk 14/9. Basınca metin doğrudan gönderilir.
   - **Robot balonu:** solda 28 pt robot yüzü (alta hizalı), yanında balon: body, text rengi, iç boşluk 14/10, beyaz @%92
     zemin, köşe 18 sürekli, ince border kenar; sağda en az 32 pt boşluk. Cevap metni bloklara ayrılır (paragraf,
     numaralı adım rozetli, madde; bağlantılar tıklanır, metin seçilebilir; bkz. tasarim.md 11.3).
   - Robot cevabı bir bildirim açtıysa balonun altında (soldan 36 pt) yeşil kapsül: `checkmark.circle.fill` +
     `report.status.sent` (caption yarı kalın, success yazı, success @%12 zemin, iç boşluk 10/4).
   - **Kullanıcı balonu:** sağa yaslı, solda en az 56 pt boşluk; accent zemin, köşe 18, iç boşluk 14/10; içinde varsa
     fotoğraflar (76×76, köşe 10, aralık 6) ve beyaz body metin (seçilebilir). Gönderilemeyen (yeniden denenebilir)
     mesaj %60 opak.
   - Son kullanıcı mesajı yeniden denenebilir bir hatayla gönderilemediyse altında sağa yaslı: kırmızı
     `exclamationmark.circle.fill` + `report.status.failed` (caption) ve `common.retry` (caption yarı kalın; beklerken
     kapalı).
   - **Hata bildirimi** robot balonu olarak (6.4). "Hazır değil" ve "çok soru" durumlarında balonda ayrıca dolu accent
     kapsül düğme: `exclamationmark.bubble` + `report.title` (subheadline yarı kalın, beyaz yazı, iç boşluk 14/9);
     basınca Sorun Bildir sayfası bu sayfanın üstüne açılır.
   - Cevap beklenirken robot balonu içinde üç "yazıyor" noktası (düşünen robot yüzüyle); erişilebilirlik `ask.typing`.
   - Yeni mesaj, bekleme değişimi ve klavye odağında en alta 0.25 sn yumuşak kaydırılır; açılışta en altta başlar.
3. **Yazma alanı** (yatay 20, üst 8, alt 12; zemin bg @%90, alttaki güvenli alana taşar):
   - Ek fotoğraf varsa ya da hazırlanıyorsa üstte küçük resimler (60×60, köşe 10, sağ üstte 18 pt çarpı, 2 pt içeride;
     erişilebilirlik adı Sorun Bildir'deki fotoğraf kaldırma adıyla aynı) ve hazırlanırken dönen gösterge.
   - Okunamayan dosyada Sorun Bildir'deki "fotoğraf okunamadı" notu.
   - Alt sıra (alta hizalı, aralık 8): 40×40 foto düğmesi (`photo.badge.plus` 19 pt orta kalın; ekleyebiliyorsa accent,
     değilse tertiary; erişilebilirlik adı "ekran görüntüsü ekle" anlamında, katalogda yok; mesaj başına en çok 3); çok
     satırlı metin alanı (1–5 satır, body, iç boşluk 14/9, en az 40 yüksek, beyaz @%95 zemin, köşe 20 sürekli,
     borderStrong kenar, yer tutucu `ask.input.placeholder`); 40×40 gönder dairesi (`arrow.up` 17 pt kalın beyaz; zemin
     gönderilebiliyorsa accent, değilse tertiary @%50; erişilebilirlik `common.send`).
   - Gönderilebilir: metin boş değil ya da fotoğraf var, cevap beklenmiyor, fotoğraf hazırlanmıyor.

### 6.3 Ne gönderilir, nereye

- **Uç nokta:** `POST <havuz sunucusu>/v1/assistant` (kök Sorun Bildir'deki gibi). Başlıklar `Content-Type:
  application/json`, `User-Agent: nino-assistant/1 (ios; <sürüm>)`. Zaman aşımı 90 sn. Sunucu kendi bilgi tabanıyla
  bir dil modeline sorar; telefon hangi model olduğunu bilmez.
- **Gövde:** `{"v":1,"install","app","platform":"ios","language","messages":[…],"device"}`. `language` = arayüz dili
  kodu; `install` Sorun Bildir'dekiyle aynı kuruluş kimliği; `device` cihaz özeti (her mesajda yeniden okunur; sunucu
  modele göndermez, yalnız robot bildirim açarsa ekler).
- **messages:** `{"role":"user"|"assistant","text","images"?:[{mime,data}]}`. Kurallar: boş metinli mesajlar atılır
  (fotoğraflı kullanıcı mesajı hariç); en çok son 24 mesaj; her metin en çok 2000 UTF-16 birimi; mesaj başına en çok 3
  fotoğraf; fotoğraflar yalnız **fotoğraflı son iki kullanıcı mesajında** gider, daha öncekilerde fotoğraf atılıp metnin
  başına "[screenshot]" yazılır. Yerel hata bildirimleri ve gönderilemeyen mesajlar isteğe katılmaz. Gövde 6 MB'yi
  geçerse yalnız son fotoğraflı mesajın fotoğrafları bırakılır; yine geçerse "çok büyük".
- Fotoğraflar Sorun Bildir'deki gibi hazırlanır (5.2).
- **Yanıt:** 2xx ve `{"ok":true,"reply":"…","report":"<id>"?}` → robot balonu (boş cevap sunucu hatası sayılır);
  `report` doluysa `report.status.sent` kapsülü. 400 → reddedildi; 413 → çok büyük; 429 + `error:"busy"` → yoğun, başka
  429 → çok soru; 503 + `error:"assistant_disabled"` → hazır değil, başka 503 → yoğun; diğerleri sunucu hatası; ağ
  hatası → çevrimdışı.
- Yeni mesaj gönderilince önceki yerel hata balonları silinir. `common.retry` son kullanıcı mesajını yeniden gönderir.

### 6.4 Robotun hata balonları

| Durum | Metin anahtarı | Yeniden denenebilir |
|---|---|---|
| hazır değil (503 assistant_disabled) | `ask.error.notready` (+ Sorun Bildir düğmesi) | hayır |
| çok soru (429) | `ask.error.dailylimit` (+ Sorun Bildir düğmesi) | hayır |
| yoğun | `ask.error.busy` | evet |
| çok büyük | `ask.error.toolarge` | hayır |
| reddedildi | `ask.error.unreadable` | hayır |
| ağ / sunucu / adres yok | `ask.error.network` | evet |

---

## 7. TV uygulamasının telefondan kurulumu (Route.tvInstall / tvUpdate)

Ayarlar listesinden, altyazı hedefi ekranından ve ana ekrandaki güncelleme kartından (7.6) açılır. Bilgisayar
olmadan Samsung, LG ya da Android TV'ye Nino'nun TV uygulamasının kurulumunu ve güncellemesini yapar. Burada yalnız **ekranlar ve kullanıcının
gördüğü adımlar** var; bağlantı, imzalama ve kurulum protokolleri bu belgenin konusu değil. TV paketleri uygulamanın
içinde gelir.

### 7.1 Ortak iskelet

- Geri başlığı `tv.install.title`. Alt bölge boş (düğmeler içerikte).
- Açılışta marka belirlenene kadar: accent dönen gösterge + `tv.searching` (body, secondary).
- Marka seçimi sırası: güncellenen TV'nin markası → bu telefonun daha önce kurduğu TV → eşlenmiş TV → ağda ilk bulunan
  TV → hiçbiri yoksa Samsung.
- Kurulum sürmüyorsa en üstte üç bölmeli segment: "Samsung" | "LG" | "Android TV" (çevrilmez). Kurulum sürerken segment
  gizlenir (marka değiştirilemez).
- Kurulum sürerken ekran kararmaz (ekranı uyanık tutma açılır, bitince kapanır).
- **Ortak parçalar:**
  - *Tanıtım:* açıklama (body, secondary) + not (caption, tertiary).
  - *Aday TV satırı:* karo (seçiliyse accent kenarlı), içinde `tv` simgesi, ad (headline), ayrıntı (caption, secondary;
    model · adres), varsa durum satırı (caption; olumluysa success yeşili, değilse warning turuncusu), seçiliyse sağda
    accent `checkmark.circle.fill`. Kurulum sürmüyorsa dokununca seçilir.
  - *Adımlar karosu:* başlık (headline), numaralı adım cümleleri (body, secondary), isteğe bağlı vurgulu değer (title,
    accent, seçilebilir) ve ardından gelen adımlar.
  - *Sonuç:* sürerken karo içinde dönen gösterge + adım metni (7.5); bitince seçili vurgulu karo: yeşil onay simgeli
    `tvi.done` ya da zaten güncelse `tvi.uptodate` (headline) ve altında `tvi.next`; hata olursa uyarı notu ve altında
    accent paylaşma bağlantısı `tvi.sharelog` (kurulum günlüğü dosyasını sistem paylaşım sayfasıyla paylaşır).
  - *Ana düğme* (birincil): bittiyse `tvi.home` (bütün yığını kapatıp ana ekrana döner); bitmediyse boşta/sürerken
    `tv.install.button`, hatadan sonra `common.retry`.
- Kurulum başarıyla bitince TV hatırlanır (marka, adres, port, sürüm) ve TV altyazı hedefi olarak eşlenir (eşlenmemişse
  "Android TV" / "LG TV" / "Samsung TV" adıyla). Kurulum ilk kurulumun altyazı hedefi adımında yapıldıysa kurulum
  tamamlanmış sayılır.
- `tvUpdate` ile açıldıysa: güncellenen TV'nin adresi önceden seçilir ve kurulum kendiliğinden başlar (LG'de yalnız
  kayıtlı anahtar varsa).

### 7.2 Samsung

1. Tanıtım: `tv.install.samsung.body` / not: `tvi.samsung.note` (2016 ve sonrası; 2016–2018 deneme aşamasında).
2. `tvi.samsung.list` (caption). Arama sürerken dönen gösterge. Bulunamazsa secondary not `tvi.samsung.none` ve elle
   giriş alanı kendiliğinden açılır.
3. Aday satırları: ad (TV'nin bildirdiği ad, yoksa keşif adı), ayrıntı "model · adres". Durum: geliştirici modu kapalı →
   turuncu `tvi.dev.off`; açık ama TV'deki "Host PC IP" bu telefon değil → turuncu `tvi.dev.otherip`; açık ve doğru →
   yeşil `tvi.dev.on`. Eşlenmiş Samsung TV listede yoksa en başa eklenir. İlk aday kendiliğinden seçilir.
4. Elle giriş açık değilse ve kurulum sürmüyorsa hayalet düğme `tv.notlisted`; basınca 52'lik alan açılır, yer tutucu
   `tvi.address` (ondalık klavye).
5. Adımlar karosu `tvi.dev.title`:
   1. `tvi.samsung.step1` (TV'de uygulamaları açmak).
   2. `tvi.samsung.step2` (kumandada 12345 ile geliştirici modu penceresi).
   3. `tvi.samsung.step3` (Developer mode açık, Host PC IP = bu telefonun adresi).
   - Vurgulu değer: bu telefonun TV ile aynı ağdaki IP adresi; bulunamazsa `tvi.samsung.nophoneip`.
   4. `tvi.samsung.step4` (güç tuşuna ~2 sn basılı tutarak tam yeniden başlatma).
6. Not (caption): `tvi.samsung.signin.note` (ilk kurulumda bir kez Samsung girişi; adres değişirse Host PC IP adımı
   yinelenir).
7. Sonuç ve ana düğme (adres boşken kapalı).
8. **Samsung giriş sayfası:** kurulum sırasında gerekirse alttan sayfa açılır: üst satırda solda kapat (`xmark`,
   `common.close`), başlık `tvi.samsung.signin.title` (title), sağda `safari` simge düğmesi (aynı sayfayı uygulama içi
   Safari görünümünde açar). Altında Samsung'un giriş sayfasını gösteren web görünümü (zemin bg). Giriş tamamlanınca
   sayfa kendiliğinden kapanır; kullanıcı kapatırsa giriş iptal olur. En çok 10 dakika beklenir.
9. Hata metinleri (hata notuna, varsa sonuna boş satır + `tvi.details` eklenir; "kurulamadı" ve "sertifika reddi"
   hatalarına ayrıca bakım paragrafı eklenir):

   | Neden | Metin anahtarı |
   |---|---|
   | TV telefonu kabul etmedi | `tvi.samsung.err.unreachable` (%@ = telefonun adresi) |
   | TV çok eski | `tvi.samsung.err.tooold` |
   | giriş bitmedi | `tvi.samsung.err.login` |
   | sertifika alınamadı | `tvi.samsung.err.certificate` |
   | yer yok | `tvi.err.space` |
   | başka cihazda imzalı kopya | `tvi.samsung.err.mismatch` |
   | sertifika reddi | `tvi.samsung.err.rejected` |
   | TV saati geride | `tvi.samsung.err.clock` |
   | eski kayıt engeli (Tizen 118, -22) | `tvi.samsung.err.blocked` |
   | bağlantı koptu | `tvi.err.connection` |
   | paket eksik | `tvi.err.package` |
   | kurulamadı / beklenmeyen | `tvi.err.failed` |
   | bakım paragrafı | `tvi.samsung.maintenance` |

### 7.3 LG (webOS)

1. Tanıtım: `tv.install.lg.body` / not: `tvi.lg.note`.
2. `tvi.lg.list`; bulunamazsa `tvi.lg.none` (elle alan açılır).
3. Aday satırları: ad, ayrıntı adres, durum `tvi.dev.on` (yeşil) / `tvi.dev.off` (turuncu). İlk geliştirici modu açık
   aday (yoksa ilk aday) seçilir; daha önce kurulan LG TV varsa o.
4. Adres geçersizse uyarı: `tvi.lg.badip`.
5. `tv.notlisted` düğmesi / elle adres alanı `tvi.address` (Samsung'daki gibi; sayı-noktalama klavyesi, düzeltme
   kapalı). Yazılan adres temizlenir: Arapça/Farsça rakamlar Latin rakama çevrilir; "http://", port ve virgüllü yazım
   düzeltilir.
6. **Passphrase alanı** (52'lik): yer tutucu, bu TV için anahtar kaydedilmemişse `tvi.lg.pass`, kayıtlıysa
   `tvi.lg.pass.saved`. Yazılan boşluklardan arındırılıp büyük harfe çevrilir.
7. Adımlar karosu `tvi.dev.title`: `tvi.lg.step1` (ücretsiz LG geliştirici hesabı), `tvi.lg.step2` (Developer Mode
   uygulaması, Dev Mode Status açık, TV yeniden başlar), `tvi.lg.step3` (Key Server açık, uygulama ekranda, passphrase
   sol altta), `tvi.lg.step4` (passphrase'i yazıp kurma; yalnız ilk kurulumda).
8. Not: `tvi.lg.session` (geliştirici modu en çok 1000 saat; Nino günde bir uzatır).
9. Sonuç; ardından (kurulum sürmüyorsa) "ipucu" uyarısı: düğmeye basılıp kurulum başlayamadıysa neden **düğmenin hemen
   üstünde** yazar: TV seçilmemiş → `tvi.lg.needtv`; adres geçersiz → `tvi.lg.badip`; parola yok ve kayıtlı anahtar
   yok → `tvi.lg.needpass`.
10. Ana düğme yalnız kurulum sürerken kapalıdır (eksik bir şey varsa basınca ipucu çıkar).
11. Hata metinleri (sonuna gerekirse `tvi.lg.tvsays`; yanlış parola hatasında eklenmez): TV yanıt vermedi →
    `tvi.lg.err.unreachable`; Key Server kapalı → `tvi.lg.err.keyserver`; yanlış parola → `tvi.lg.err.passphrase`;
    anahtar reddi → `tvi.lg.err.keyrefused`; yer yok, bağlantı koptu, paket eksik, kurulamadı → ortak `tvi.err.space`,
    `tvi.err.connection`, `tvi.err.package`, `tvi.err.failed`.
12. Davranış notu (kullanıcıya görünen): kayıtlı anahtar TV tarafından reddedilirse (geliştirici modu yeniden açılmış)
    anahtar unutulur; parola yazıldıysa yenisi alınıp bir kez daha denenir.

### 7.4 Android TV ve Google TV

1. Tanıtım: `tvi.android.body` / not: `tvi.android.note`.
2. `tvi.android.list`; bulunamazsa `tvi.android.none`.
3. Aday satırları: ad hep "Android TV", ayrıntı adres; durum: ağ hata ayıklama portu açık → yeşil `tvi.android.debug.on`,
   bilinen ama portu kapalı TV → turuncu `tvi.android.debug.off`. Bilinen TV'ler (güncellenen, daha önce kurulan,
   eşlenen) en başa eklenir. Portu açık ilk aday (yoksa ilk) seçilir.
4. `tvi.android.mode` ve iki bölmeli segment: `tvi.android.mode.network` (varsayılan) | `tvi.android.mode.wireless`.
5. Adres alanı (her zaman görünür, 52'lik): ağ kipinde yer tutucu `tvi.address`; kablosuz kipte
   `tvi.android.address.wireless`. Kablosuz kipte ayrıca iki alan: `tvi.android.pair.address` ve `tvi.android.pair.code`
   (sayı klavyesi), altında `tvi.android.localnet` notu (caption, tertiary).
6. Adımlar karosu `tvi.android.steps.title`:
   - Ağ kipi: `tvi.android.step1` (geliştirici seçeneklerini açma: derleme satırına 7 kez), `tvi.android.step2` (USB ve
     varsa ağ hata ayıklamasını açma), `tvi.android.step3` (kurmaya basıp TV'deki izin sorusunda "her zaman izin ver";
     olmazsa kablosuz yol).
   - Kablosuz kip: `tvi.android.step1`, `tvi.android.wstep2` (kablosuz hata ayıklamayı açıp üstteki adres ve portu
     yazma), `tvi.android.wstep3` (ilk seferde eşleme koduyla eşleme; pencere açıkken kurma).
7. Sonuç. Hata "TV'deki kopya değiştirilmeli" ise ve kurulum sürmüyorsa yıkıcı düğme `tvi.android.replace` (TV'deki
   kopyayı kaldırmaya izin vererek yeniden dener).
8. Ana düğme (adres boşken kapalı).
9. Başlamadan denetimler: kablosuz kipte port yoksa → `tvi.android.needport`; eşleme kodu yazılıp eşleme adresinde port
   yoksa → `tvi.android.needpairport`. Ağ kipinde port yazılmazsa 5555 kullanılır.
10. Hata metinleri (gerekirse sonuna `tvi.details`):

    | Neden | Metin anahtarı |
    |---|---|
    | TV yanıt vermedi | `tvi.android.err.unreachable` |
    | izin verilmedi | `tvi.android.err.notapproved` |
    | eşlenmemiş | `tvi.android.err.notpaired` |
    | eşleme olmadı | `tvi.android.err.pairing` |
    | değiştirilmeli (Play'den kurulmuş) | `tvi.android.err.playcopy` |
    | değiştirilmeli (başka anahtar ya da daha yeni) | `tvi.android.err.othercopy` |
    | kaldırıp kurma da imza yüzünden olmadı | `tvi.android.err.removemanually` |
    | yer yok / bağlantı koptu / paket eksik / kurulamadı | ortak `tvi.err.*` anahtarları |

    Son üç "değiştirilmeli / elle kaldır" durumunda ayrıntı eklenmez.

### 7.5 Adım metinleri (kurulum sürerken)

| Adım | Metin anahtarı |
|---|---|
| eşleme | `tvi.step.pairing` |
| TV'de onay | `tvi.step.approve` |
| anahtar | `tvi.step.key` |
| Play açıldı | `tvi.step.play` |
| bağlanma | `tvi.step.connecting` |
| okuma | `tvi.step.reading` |
| giriş | `tvi.step.signin` |
| sertifika | `tvi.step.certificate` |
| imzalama | `tvi.step.signing` |
| kurma | `tvi.step.installing` |
| kaldırma | `tvi.step.uninstalling` |
| açma | `tvi.step.launching` |

Bittikten sonraki açıklama: `tvi.next` (TV'de Nino'nun bekleme ekranı açılır; bilgisayardan söz etse de telefonu
beklediğini, ana ekrandan çeviriyi başlatınca TV'nin telefonu kendisi bulacağını anlatır).

### 7.6 Ana ekrandaki güncelleme kartı (bilgi için)

TV'deki uygulama telefondaki paketten eskiyse ana ekranda seçili vurgulu karo: `arrow.triangle.2.circlepath` (accent) +
TV uygulamasının yeni sürümü olduğunu söyleyen başlık; altında "TV: <TV'deki sürüm> → bu telefon: <paketteki sürüm>"
satırı; ikincil güncelleme düğmesi → Route.tvUpdate. (Bu kartın metinleri katalogda yok.)

---

## 8. Konsol seçimi ve Xbox ekranları

### 8.1 Konsol seçimi (PlatformScreen; kurulumda ve Profil › Konsol'dan)

- Üst satır: geri işlevi verilmişse yalnız sol geri simge düğmesi (`chevron.left`, `common.back`); başlık satırı yok.
- Başlık bloğu (ScreenTitle): `console.title`; açıklama `console.choose.body`.
- İki seçenek karosu (dokununca seçilir; seçili olan accent kenarlı ve simgesi accent, diğerinin simgesi nötr):
  `gamecontroller.fill` + başlık + açıklama:
  - "PlayStation 5" / `console.ps5.detail`.
  - "Xbox" + yanında accent tonlu "Beta" etiketi / `console.xbox.detail`.
- Xbox seçiliyse secondary not: `xbox.beta.note`.
- Alt bölge: birincil `common.next`: seçim kaydedilir (UserDefaults'ta platform anahtarı; "platform seçildi"
  bayrağı açılır) ve bir sonraki adıma geçilir. Açılışta kayıtlı platform seçili gelir.

### 8.2 Xbox girişi (XboxLoginScreen)

- Üst satır: kurulum başlığı (adım 1; geri ve `common.skipfornow` verilmişse onlar). Ayarlar'dan açıldığında yalnız geri.
- Başlık bloğu: üst satır `setup.step` (adım 1; accent), başlık `xbox.signin.button`, açıklama `xbox.signin.body`.
- "Beta" etiketi (accent tonlu). Zaten giriş yapılmışsa ve kod gösterilmiyorsa yeşil noktalı `signin.status.done`.
- Kod yokken ve beklenmiyorken açıklama: `xbox.signin.hint`.
- Kod alındıysa karo: `xbox.code.label` (caption); kodun kendisi (display 28, accent; dokununca panoya kopyalanır;
  ipucu `xbox.code.copy`); doğrulama adresi "https://" atılarak (headline, accent, altı çizili; dokununca kodu kopyalar
  ve adresi tarayıcıda açar; ipucu `xbox.code.open`); üç adımlı açıklama `xbox.code.steps` (satır sonlarıyla);
  kopyalandıysa yeşil `xbox.code.copied`.
- Beklerken: dönen gösterge + `xbox.signin.waiting`.
- Hata: uyarı `xbox.signin.failed` (%@ = 8.4'teki neden ya da sistem hata metni); hata olunca kod kaybolur.
- Alt bölge: kod varsa hayalet `xbox.code.open`; birincil `xbox.signin.button` (beklerken kapalı).
- Akış: birincile basınca Microsoft "cihaz kodu" girişi başlar → kod gelince hemen kopyalanır ve doğrulama sayfası
  tarayıcıda açılır → uygulama girişin bitmesini yoklar → bitince bir sonraki adım. Ekrandan çıkılırsa yoklama iptal.
  Jeton Anahtar Zinciri'nde saklanır.

### 8.3 Xbox seçimi (XboxConsoleScreen)

- Başlık bloğu: `setup.step` (adım 2), `xbox.choose.title`, açıklama `xbox.choose.body`.
- Yüklenirken karo içinde `xbox.choose.searching` (body, secondary).
- Liste boş ve hata yoksa secondary not: `xbox.choose.none`.
- Her Xbox bir karo (seçiliyse accent kenarlı): uzaktan oynatma açıksa accent `checkmark.circle.fill`, değilse kırmızı
  `exclamationmark.triangle.fill`; ad (boşsa model) headline; altında `xbox.choose.ready` ya da `xbox.choose.off`.
  Yalnız uzaktan oynatması açık olan seçilebilir. Başta kayıtlı Xbox, yoksa ilk uygun Xbox seçili.
- Hata varsa uyarı notu.
- Alt bölge: hayalet `common.searchagain`; giriş süresi dolduysa birincil `xbox.signin.button` (girişe döner), değilse
  birincil `xbox.choose.use` (uygun seçim yoksa kapalı; seçim kaydedilir).

### 8.4 Xbox hata metinleri

| Neden | Metin anahtarı |
|---|---|
| giriş gerekli / reddedildi | `xbox.error.signin` |
| kodun süresi doldu | `xbox.error.code` |
| Xbox profili yok | `xbox.error.noprofile` |
| ağ | `xbox.error.offline` |
| diğer | `xbox.error.unexpected` (%@ = sorun kodu ya da ayrıntının ilk 120 karakteri) |

Çeviri sürerken Xbox oturum hataları ayrıca `xbox.session.*` anahtarlarıyla gösterilir (meşgul, zaman aşımı, ulaşılamıyor,
bağlantı koptu, beklenmeyen yanıt, vazgeçildi).

---

## 9. Ayar → saklama yeri (toplu)

| Ekrandaki ayar | Saklandığı yer | Varsayılan |
|---|---|---|
| Bildirimler (paket) | UserDefaults `notifyPackUpdates` | açık |
| PS5 bağlantısı bildirimi | UserDefaults `notifyDisconnect` | açık |
| Havuza katkı | UserSettings `sharePool` | açık |
| Oyun sorusu | UserSettings `askGame` | açık |
| Konuşanın adı | UserSettings `showSpeakerNames` | açık |
| Değişmeyen alanı sık oku | UserSettings `fastSubtitleDetection` | kapalı |
| Xbox sesi bu cihazda | UserSettings `xboxAudioOnDevice` | açık |
| Otomatik bildirim | UserSettings `autoReport` | açık |
| Çeviri dili | UserSettings `targetLanguage` | "tr" |
| Çeviri motoru | UserSettings `onlineTranslation` + `onlineEngine` | kapalı + DeepL (= Ücretsiz) |
| Motor anahtarları | Anahtar Zinciri (motor başına) | yok |
| Yazı boyu | `style.fontSize` | 46 (%100) |
| Yazı tipi | `style.font` | condensed (Aksiyon) |
| Yazı rengi | `style.textColor` | white |
| Arka plan opaklığı | `style.background` | 100 |
| Zemin biçimi | `style.backgroundShape` | fit |
| TV'de yer | `style.placement` | cover |
| Sabit yükseklik | `style.bottomPercent` | 7 |
| Önceki satırları tut | `style.stackPrevious` | açık |
| Görüntü modu | `style.displayMode` | inApp |
| Filigran | `style.watermark` | açık |
| Altyazı alanı | UserSettings `areaPreset` + `region` | bottom |
| Ek alanlar | UserSettings `extraAreas` | boş |
| Oyun paketleri | UserSettings `gamePacks` | açık |
| Kapatılan paketler | UserDefaults `disabledPacks` | boş |
| PS5 şifresi | Anahtar Zinciri | yok |
| Konsol türü | UserDefaults (platform anahtarı) + "seçildi" bayrağı | PlayStation |
| Seçilen Xbox, Microsoft jetonu | Anahtar Zinciri | yok |
| Tanıtım turu bitti | UserDefaults `coachTourDone` | hayır |
| Havuz sunucusu adresi (gizli ayar) | UserDefaults `ninoPoolURL` | yayın adresi |

UserSettings tek bir JSON olarak UserDefaults'ta tutulur; her değişiklikte yeniden yazılır ve TV'ye görünüm gönderilir.
Eski kayıtlarda olmayan alanlar varsayılanla dolar.

---

## 10. Çevrilmeyen ya da katalogda henüz olmayan metinler

- **Bilerek çevrilmez:** ürün ve marka adları (Nino Game Translator, Nino, GTA 6, DeepL, Gemini, OpenAI, Claude,
  PlayStation 5, Xbox, Xbox (Beta), Beta, Samsung, LG, Android TV, TV, Safari), telif satırları, NOTICE satırı, tanı
  metnindeki sunucuya giden sabit Türkçe parçalar (5.5), cihaz bilgisi özetindeki kimlikler (app, device, system, tv,
  console, status) ve "TV uygulaması" / "oyun:" ekleri.
- **Yeni katalogda karşılığı olmayanlar** (yeni uygulamada bu özellik ya yok ya da metni henüz eklenmedi; eklenirken
  yeni anahtar açılmalı):
  - Profil kimlik karosundaki "ücretsiz, hesapsız" alt satırı yeni uygulamada `engine.apple.detail` ile karşılanıyor;
    ayrı bir anahtar istenirse açılmalı.
  - Profil'deki Microsoft oturumunu kapatma satırı (1.1).
  - GTA 6 karosunun etiketi ve açıklaması, GTA 6 görünürken çeviri motoru başlığının "diğer oyunlar" biçimi (2.3, 2.4).
  - Ek alanlar karosunun bütün metinleri (2.7).
  - Paket güncelleme durumu ve hataları (4.1/4), içe aktarılan paketler bölümü ve önizleme sayfasının bütün metinleri
    (4.3).
  - Sorun Bildir'deki fotoğraf karosu metinleri (5.1/4) ve Nino'ya Sor'daki ekran görüntüsü ekleme adı (6.2).
  - Robotun "çeviri başladı" balonu (6.1; her arayüz dili için ayrı değer gerekir).
  - Ana ekrandaki TV uygulaması güncelleme kartı (7.6).
- Eski uygulamada İngilizce kalan bazı metinlerin (Xbox sesi anahtarı, Samsung "çok eski" ve "desteklenen modeller"
  notları, kurulum sonrası açıklama) yeni katalogda Türkçesi var: `xbox.audio.toggle`, `xbox.audio.detail`,
  `tvi.samsung.err.tooold`, `tvi.samsung.note`, `tvi.next`.

---

## 11. Belirsiz kalanlar

- `notifyPackUpdates` (Profil'deki `settings.notifications` / `packs.updates` anahtarı) kodda yalnız saklanıyor; paket
  bildirimi gönderen bir yer bulunamadı. Yeni uygulamada ya işlev eklenmeli ya da anahtar kaldırılmalı.
- Ayarlar'daki `settings.ps5` satırı Xbox seçiliyken de bu adla kalıyor (Profil'de ise `settings.xbox`). Yeni
  uygulamada Profil'deki gibi duruma göre ad vermek daha tutarlı olur.
- Görüntü 10–12 eski taslak; koddaki hâl esas alındı.
- Eski iOS kartındaki `oldios.add` düğmesi Ayarlar'da yalnız motoru Gemini'ye çevirir; ana ekrandaki aynı kartın
  davranışı ana ekran tarifinde.

---

## Ek A: Metin anahtarlarının bölümlere göre öbekleri

Metinlerin kendisi `apps/ios/Nino/Resources/Localizable.xcstrings` içindedir; bu belgede yalnız anahtarlar anılır.

| Ekran / bölüm | Anahtar öbekleri |
|---|---|
| Profil (1) | `settings.*`, `devices.*`, `signin.status.done`, `xbox.audio.*`, `ask.suggest.whichgame` |
| Ayarlar (2) | `settings.*`, `engine.*`, `oldios.*`, `subtitle.*`, `region.*`, `passcode.*`, `diag.*`, `tv.test.*` |
| Hakkında (3) | `about.*` |
| Oyun paketleri (4) | `packs.*`, `settings.packs*`, `home.nowplaying` |
| Sorun Bildir (5) | `report.*`, `settings.autoreport*`, `settings.sendproblems` |
| Nino'ya Sor (6) | `ask.*`, `setup.combo.*`, `settings.setuphelper` |
| TV kurulumu (7) | `tv.install.*`, `tv.searching`, `tv.notlisted`, `tvi.*` |
| Konsol ve Xbox (8) | `console.*`, `setup.step`, `xbox.*` |
| Ortak düğmeler | `common.*` |
