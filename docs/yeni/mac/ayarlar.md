# Mac: Ayarlar penceresi (tarif)

Bu belge Mac uygulamasındaki Ayarlar penceresinin **görünüşünü ve davranışını** anlatır. Kod yoktur. Yeni yazan kişi
yalnız bu belgeyle aynı ekranı kurabilmelidir.

Ortak bileşenler (kart, ipucu yazısı, düğme türleri, cam zemin, renk ve ölçü adları) `tasarim-dili.md`'de anlatılıyor
(boşluk adları: xs, s, m/gap, l/tile, xl/screen, xxl; köşe adları: card, control, inner, tag). Burada yalnız hangisinin
kullanıldığı yazar: **Kart** (başlıklı ya da başlıksız yuvarlak köşeli yüzey), **İpucu** (küçük, ikincil
renkli açıklama), **Tamam etiketi** (yeşil onay işaretli kısa satır), **Hata yazısı** (kırmızı/uyarı renkli satır),
**Hap** (küçük yuvarlak etiket; tasarım dilinde "Etiket (pill)"), **Karo** (seçilebilir kutu; seçiliyken vurgulu), **Cam yüzey** (buzlu cam zemin +
ince kenar çizgisi), **Bölmeli seçici** (simgeli segment düğmeler), düğme türleri **birincil / ikincil / tehlikeli**.

## Metinler hakkında

- Bütün metinler yerelleştirme dosyalarından gelir. Anahtarlar noktalı kimliklerdir (ör. `settings.done`); her alanın
  kendi xcstrings dosyası vardır (Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport). Ayarlar
  metinlerinin çoğu `Settings.xcstrings`'te, tema adları `Home.xcstrings`'te durur. Tablolarda sütunlar
  "Anahtar | EN | TR"dir; kısa etiketlerde yeni metin yazılıdır, uzun metinlerde ise yalnız anahtar ve anlamı verilir.
- Çoğu satırda metin yerine kısa bir açıklama (köşeli ayraç içinde) yazılıdır; TR sütunundaki "[aynı anlam]" Türkçenin de
  aynı şeyi söylediğini gösterir. Metnin tam hâli xcstrings dosyasındadır.
- Yer tutucu içeren anahtarlar (ör. `settings.key.works %@`, `settings.area.percent %lld`) tam yazıldığı gibidir.
  `%@`, `%lld`, `%d`, `%1$@` yer tutuculardır (sayı ya da ad gelir).
- "verbatim" yazan metinler yerelleştirilmez, her dilde aynen görünür.

---

## 1. Pencere

- Ayarlar ana pencerenin üstünde **sayfa (sheet)** olarak açılır. Açma yolları:
  - Menü çubuğu › uygulama menüsü › `home.menu.settings` (Settings… / Ayarlar…) (kısayol ⌘,). Kurulum bitmeden
    (karşılama sihirbazı sürerken) bu menü öğesi soluk ve basılamaz.
  - Ana ekranın sağ üstündeki yuvarlak dişli düğmesi (ipucu: `home.settings`, Settings / Ayarlar).
  - Ana ekranın alt çubuğundaki çeviri motoru satırı: Ayarlar doğrudan **Çeviri** bölümünde açılır (liste atlanır).
- Pencere boyutu sabittir: ana pencerenin genişliği ve yüksekliğinden her yanda "screen" boşluğu kadar küçük.
  İç kenar boşluğu "xl".
- Üst satır (her zaman görünür):
  - Solda: liste görünümündeyken büyük başlık `settings.title` (Settings / Ayarlar) (28 pt, kalın, yuvarlak yazı
    tipi). Bir bölüm açıkken onun yerine geri düğmesi `settings.back` (Settings / Ayarlar): sola ok simgesi + metin,
    gövde boyu yarı kalın, vurgu yazı rengi, çerçevesiz. Kısayol ⌘[ . Basınca yaylı geçişle listeye dönülür.
  - Sağda: `settings.done` (Done / Bitti) birincil düğmesi (Return ile de çalışır); pencereyi kapatır.
- Altında kaydırılabilir alan (kaydırma çubuğu gizli). İçerik ortalanır, en çok **640 pt** genişliktedir; yalnız
  **Altyazı görünümü** bölümünde **900 pt**.
- Geçiş: listeden bölüme girerken bölüm sağdan kayarak + belirerek gelir, liste sola kayarak gider; geri dönüşte
  tersi. Yay animasyonu (tepki 0.4 sn, sönüm 0.86).

## 1a. Altyazı nereye gider? (birçok satırın görünme koşulu)

Aşağıda "altyazı TV'ye gidiyorsa" ve "altyazı bilgisayarda gösteriliyorsa" diye geçen iki koşul yalnız altyazı yeri
ayarı (`settings.connection.output`) değildir:

- **TV'ye gidiyor:** (görüntü kaynağı oyun penceresi değil **ya da** Xbox penceresi) **ve** altyazı yeri TV ya da İkisi de.
- **Bilgisayarda gösteriliyor:** (görüntü kaynağı oyun penceresi **ve** Xbox penceresi değil) **ya da** altyazı yeri
  Bilgisayar ya da İkisi de.

Yani okuma PS Remote Play'den veya chiaki-ng'den yapılırken altyazı her zaman bilgisayardaki pencerededir, TV'ye gitmez.
Tek istisna: Altyazı görünümü kartının **başlığı** bu kurala değil, doğrudan ayarın kendisine bakar (ayar "TV" ise
`settings.style.onTV`).

## 2. Liste görünümü (açılış)

iPhone Ayarları gibi: cam yüzeyli **gruplar**, grupların arasında "xl" boşluk. Her grupta satırlar, satırlar arasında
soldan 58 pt girintili ince çizgi.

**Satır:** solda 30×30 pt renkli simge kutusu (köşe 8 pt, bölüm renginin %85'inden %100'üne yukarıdan aşağı geçiş,
içinde beyaz 14 pt yarı kalın simge), yanında bölüm adı (gövde yazısı), sağda küçük gri ileri oku (12 pt, kalın, ikincil
renk %70). Yatay iç boşluk "l", en az yükseklik 52 pt. Fare üstüne gelince satır zemini açık vurgu renginin %60'ı olur
(0.15 sn).

**Gruplar ve sıra** (görünenler):

| Grup | Satırlar |
|---|---|
| 1 | Bağlantı · PS5 giriş şifresi |
| 2 | Altyazı görünümü · Çeviri |
| 3 | OBS katmanı |
| 4 | Sistem sağlığı · Güncellemeler · Nino'ya Sor · Sorun Bildir · Hakkında |
| 5 | Sıfırla |

**Bölümlerin simgesi ve rengi** (simge adları Apple SF Symbols adlarıdır; renk RGB 0–1). Bölüm adının anahtarı
`settings.section.<bölüm kimliği>` biçiminde kurulur:

| Bölüm | Anahtar | EN | TR | SF Symbol | Renk |
|---|---|---|---|---|---|
| Bağlantı | `settings.section.connection` | Connection | Bağlantı | cable.connector | 0.10, 0.45, 0.95 |
| PS5 giriş şifresi | `settings.section.passcode` | PS5 login passcode | PS5 giriş şifresi | lock | 0.30, 0.35, 0.45 |
| Altyazı görünümü | `settings.section.appearance` | Subtitle appearance | Altyazı görünümü | captions.bubble | 0.00, 0.44, 0.82 |
| Çeviri | `settings.section.translation` | Translation | Çeviri | globe | 0.00, 0.62, 0.75 |
| OBS katmanı | `settings.section.obs` | OBS overlay | OBS katmanı | dot.radiowaves.left.and.right | 0.92, 0.26, 0.30 |
| Sistem sağlığı | `settings.section.health` | System health | Sistem sağlığı | waveform.path.ecg | 0.95, 0.30, 0.45 |
| Güncellemeler | `settings.section.updates` | Updates | Güncellemeler | arrow.down.circle | 0.12, 0.62, 0.36 |
| Nino'ya Sor | `settings.section.askNino` | Ask Nino | Nino'ya Sor | bubble.left.and.text.bubble.right | 0.00, 0.44, 0.82 |
| Sorun Bildir | `settings.section.report` | Report a problem | Sorun Bildir | exclamationmark.bubble | 0.96, 0.62, 0.12 |
| Hakkında | `settings.section.about` | About Nino | [uygulamanın tam adı + "hakkında"] | info.circle | 0.45, 0.50, 0.60 |
| Sıfırla | `settings.section.reset` | Reset | Sıfırla | arrow.counterclockwise | 0.90, 0.30, 0.28 |
| (gizli) Arayüz | `settings.section.interface` | Interface | Arayüz | macwindow | 0.36, 0.30, 0.95 |
| (gizli) Dil | `settings.section.language` | Language | Dil | character.bubble | 0.20, 0.70, 0.40 |
| (gizli) Oyun paketleri | `settings.section.packs` | Game packs | Oyun paketleri | shippingbox | 0.98, 0.55, 0.10 |
| (gizli) Altyazı alanı | `settings.section.area` | Subtitle area | Altyazı alanı | rectangle.dashed | 0.35, 0.40, 0.95 |

**Gizli bölümler:** Arayüz, Dil, Oyun paketleri ve Altyazı alanı listede görünmez ama sayfaları hazır durur (geri açmak
için yalnız gizli listesinden çıkarmak yeter). Dil'in iki seçicisi Çeviri sayfasının en üstünde zaten gösterilir.
Sayfaları bu belgenin sonunda (bölüm 14) anlatılmıştır.

**Nino'ya Sor satırı özel:** basınca bölüm sayfası açılmaz. Ayarlar penceresi kapanır, ~0.35 sn sonra Nino'ya Sor
sohbet sayfası açılır.

## 3. Bölüm sayfasının ortak başı

Bir bölüm açıkken içeriğin en üstünde (Oyun paketleri hariç; o kendi başlığını çizer):

- 40×40 pt renkli kare (köşe 11 pt, düz bölüm rengi, bölüm renginin %45'iyle 10 pt yarıçaplı, 4 pt aşağı gölge), içinde
  beyaz 18 pt yarı kalın simge.
- Yanında bölüm adı, 28 pt kalın yuvarlak yazı tipi.
- Altında içerik, öğeler arası "gap" boşluk, sola yaslı.

---

## 4. Bağlantı

Tek kart. Ana ekranda da aynı kart kullanılır; Ayarlar'da **ayrıntılı** hâli (açıklamalar ve kart denetimi ek) çizilir.

1. Küçük ikincil başlık `settings.connection.console`, altında bölmeli seçici: PS5 (simge gamecontroller) | Xbox
   (gamecontroller.fill). İki konsol adı verbatim'dir.
   - Davranış: konsol değişince kaydedilir. Xbox'a geçilirken görüntü kaynağı "PS5" ise kendiliğinden "pencere" olur
     (Xbox'a doğrudan bağlanma yok). Aynı konsol tekrar seçilirse hiçbir şey olmaz.
2. Küçük başlık `settings.connection.picture`, altında bölmeli seçici:
   - Konsol PS5 ise: PS5 (gamecontroller) | `settings.connection.source.window` (macwindow) |
     `settings.connection.source.card` (cable.connector).
   - Konsol Xbox ise: `settings.connection.source.xboxWindow` (macwindow) | `settings.connection.source.card`
     (cable.connector). Pencere seçiliyken altında Xbox ipucu `settings.connection.xboxHint`.
3. Seçime göre alt kısım:
   - **Capture Card:** `settings.connection.output` başlığı + bölmeli seçici `settings.connection.output.tv` (tv) |
     `settings.connection.output.computer` (desktopcomputer) | `settings.connection.output.both` (rectangle.on.rectangle).
     Bilgisayar ekranında gösterim açıksa: açıklama ipucu `settings.connection.computerHint`, tıklama geçirme anahtarı
     `settings.connection.clickThrough` + pencere ayar düğmesi `settings.connection.adjustWindow` (yan yana; dar yerde
     alt alta) ve tıklama ipucu `settings.connection.clickHint`. Altında TV'ye mi bilgisayara mı gittiğine göre değişen
     ipucu (`settings.connection.cardTVHint` ya da `settings.connection.cardComputerHint`). Çeviri kapalıyken
     **kart denetimi** (kartın canlı önizlemesi, 170 pt yükseklik; bkz. `kurulum.md` › yakalama kartı rehberi). En altta
     ikincil düğme `settings.connection.guide` (simge list.bullet.rectangle; üstüne gelince ipucu
     `settings.connection.guideHelp`); çeviri sürerken basılamaz; basınca 720×700 pt'lik ayrı sayfada kart kurulum
     rehberi açılır (içeriği `kurulum.md` §10).
   - **Oyun penceresi:** PS5 ise Remote Play ipucu `settings.connection.remotePlayHint`; sonra tıklama geçirme anahtarı
     + pencere ayar düğmesi.
   - **PS5 (doğrudan):** yalnız ipucu `settings.connection.ps5Hint`.

Davranış:
- Görüntü kaynağı değişince altyazının nereye gideceği yeniden hesaplanır; çeviri sürüyorsa durdurulup yeni kaynakla
  hemen yeniden başlatılır. PS5'e dönülünce altyazı yeri zorla "TV" olur.
- Altyazı yeri (TV / Bilgisayar / İkisi) değişince: TV'ye gönderim açılır/kapanır; bilgisayar gösterimi kapandıysa
  bilgisayardaki saydam pencere gizlenir (yayın penceresi açıksa satırlar kalır, yalnız yer ayarı biter). Capture Card'la
  çeviri sürerken yer değişirse çeviri durdurulup yeniden başlar (oyunun bilgisayarda gösterilip gösterilmeyeceği değişir).
- Tıklama geçirme açıkken bilgisayardaki altyazı penceresi tıklamaları alttaki pencereye geçirir. ⌥⌘L ile ya da menü
  çubuğu simgesinden kapatılır.
- Pencere ayar düğmesine basılınca bilgisayardaki altyazı penceresi ayar kipine girer (örnek yazı görünür,
  tıklamalar geçmez, sürüklenip boyutlanır). Ayar kipindeyken düğme soluk.
- Yer seçimi kayıtlı ayarlardan okunurken eski "İkisi de" değeri "TV"ye çevrilir.

| Anahtar | EN | TR |
|---|---|---|
| `settings.connection.console` | Console | Konsol |
| `settings.connection.picture` | Game picture from | Oyun görüntüsü nereden |
| `settings.connection.source.xboxWindow` | Xbox window | Xbox penceresi |
| `settings.connection.source.window` | Remote Play window | [Remote Play'in pencere adı] |
| `settings.connection.source.card` | Capture card | Capture Card |
| `settings.connection.xboxHint` | [Xbox oynanacaksa Greenlight'ı veya tarayıcıdaki xbox.com/play adresindeki konsol listesini Microsoft hesabıyla açtırır; Nino bu pencereden okuyup çeviriyi üstüne bindirir] | [aynı anlam] |
| `settings.connection.output` | Show subtitles on | [altyazının hangi ekranda çıkacağını soran başlık] |
| `settings.connection.output.tv` · `.computer` · `.both` | TV · Computer · Both | TV · Bilgisayar · İkisi de |
| `settings.connection.computerHint` | [altyazının Mac'te, oyunun veya Remote Play penceresinin üzerinde duran ayrı bir pencerede çıktığını belirtir] | [aynı anlam] |
| `settings.connection.clickHint` | [bu kip açıkken fare tıklamasının arkadaki pencereye iletildiğini; kapatmanın ⌥⌘L kısayolu veya menü çubuğu simgesiyle olduğunu belirtir] | [aynı anlam] |
| `settings.connection.cardTVHint` | [TV seçiminde PS5 görüntüsü kartın HDMI çıkışıyla TV'ye varır; Nino kartı okuyup çeviriyi TV uygulamasına iletir] | [aynı anlam] |
| `settings.connection.cardComputerHint` | [Bilgisayar seçiminde oyun sesli ve tam ekran Nino'da oynar, çeviri üstüne bindirilir; Mac'i TV'ye veya monitöre takmayı önerir] | [aynı anlam] |
| `settings.connection.guide` | Connection guide | Bağlantı rehberi |
| `settings.connection.guideHelp` | [rehberin PS5, kart ve ekran bağlantısını ve HDCP kapatmayı anlattığını belirtir] | [aynı anlam] |
| `settings.connection.remotePlayHint` | [oyunun Mac üzerinde Remote Play'le (PS Remote Play veya chiaki-ng) oynandığını; Nino'nun bu pencereden okuyup çeviriyi üstüne koyduğunu; ikinci hesaba gerek olmadığını belirtir] | [aynı anlam] |
| `settings.connection.ps5Hint` | [altyazının televizyonda, Nino TV uygulaması içinde göründüğünü belirtir] | [aynı anlam] |
| `settings.connection.clickThrough` | Clicks pass through | Tıklamalar geçsin |
| `settings.connection.adjustWindow` | Adjust subtitle window | [bilgisayardaki altyazı penceresini ayar kipine alan düğme] |

Varsayılanlar: konsol PS5, görüntü kaynağı PS5, altyazı yeri TV, tıklama geçirme kapalı.

---

## 5. PS5 giriş şifresi

Tek kart. İkinci PSN hesabının PS5'teki 4 haneli giriş şifresi (isteğe bağlı).

- Üstte ipucu `settings.passcode.hint`.
- **Şifre kayıtlı değilse:** yan yana gizli giriş alanı (yer tutucu `settings.passcode.placeholder`) + ikincil
  `settings.passcode.save` düğmesi. Alan boşken (yalnız boşluk da boş sayılır) düğme soluk. Basınca: boşluklar atılır,
  tam 4 ASCII rakam değilse kaydedilmez ve altında ikincil renkli `settings.passcode.invalid` yazar. Geçerliyse Anahtar
  Zinciri'ne yazılır, alan boşalır, görünüm kayıtlı hâle geçer.
- **Şifre kayıtlıysa:** solda `settings.passcode.saved`, sağda ikincil `settings.passcode.remove`. Basınca Anahtar
  Zinciri'nden silinir.
- Etki: bir sonraki PS5 bağlantısında PS5 şifre isterse Nino bunu gönderir.

| Anahtar | EN | TR |
|---|---|---|
| `settings.passcode.hint` | [şifrenin yalnız ikinci hesapta PS5 girişi şifreliyse lazım olduğunu, PS5 isteyince Nino'nun yazdığını, Anahtar Zinciri'nde tutulduğunu belirtir] | [aynı anlam] |
| `settings.passcode.saved` | Passcode saved. | Şifre kaydedildi. |
| `settings.passcode.remove` | Remove passcode | Şifreyi kaldır |
| `settings.passcode.placeholder` | 4 digits | 4 hane |
| `settings.passcode.save` | Save | Kaydet |
| `settings.passcode.invalid` | [dört rakamlı şifrenin girilmesini ister] | [aynı anlam] |

---

## 6. Altyazı görünümü

Bu sayfa 900 pt genişliğinde ve **tek ekran, kaydırmasız** tasarlanmıştır.

### 6.1 Düzen

- Üst sıra yan yana (üstten hizalı, arada "gap"):
  - Solda **canlı önizleme** 470×264 pt. Sol üst köşesinde seçili temanın adı: beyaz, yarı kalın küçük yazı, %45 siyah
    yuvarlak hap zemin, yükseklik 26 pt, 10 pt iç boşluk.
  - Sağda **ayarlar kartı**.
- Altta tek sırada **6 tema kartı** (6 sütun).

### 6.2 Canlı önizleme

- Köşe 14 pt yuvarlatılmış, ince cam kenar çizgisi. Ekran okuyucudan gizli.
- Zemin: oyun sahnesi gibi koyu bir görüntü — sol üstten sağ alta üç renkli geçiş (lacivert 0.10/0.14/0.28 → mor-kahve
  0.24/0.14/0.22 → çok koyu 0.06/0.08/0.14); üstüne bulanık turuncu bir daire (%45, genişliğin %40'ı, sağ üstte) ve
  bulanık mavi bir daire (%40, genişliğin %45'i, solda).
- Yazı boyu: (otomatik boy açıksa 38, değilse seçili boy) / 1920 × önizleme genişliği × 1.6; en az 10 pt.
- Yazının alttan uzaklığı: sabit yerleşimde yüksekliğin "konum yüzdesi" kadar (en az 10 pt), diğerlerinde yüksekliğin %8'i.
- Demo döngüsü: önce oyunun İngilizce satırı (beyaza yakın, orta kalınlık, gölgeli) belirir; 0.9 sn sonra İngilizce
  kaybolup seçili temayla Türkçesi gelir (hafif büyüyerek + belirerek); 2.6 sn kalır; 0.5 sn boşluk; sonraki satır.
  Hareket azaltma açıksa yalnız Türkçe sabit görünür. Stil değişince önizleme yaylı animasyonla güncellenir.
- Demo satırları (verbatim, çevrilmez):
  1. Someone has to keep an eye on this town. → Bu kasabaya birinin göz kulak olması lazım.
  2. Here they come. Keep your head down. → Geliyorlar. Başını eğ, görünme.
  3. Is anyone there? → Orada biri mi var?
  4. The fog swallows every sound. → Sis bütün sesleri yutuyor.
  5. Up to the roof. Move! → Çatıya çıkın. Çabuk!
  6. We're not done here. → Burada işimiz bitmedi.

### 6.3 Ayarlar kartı (sırayla)

Kartın başlığı: altyazı yeri yalnız TV ise `settings.style.onTV`, değilse `settings.style.title`.

| # | Satır (anahtar) | Tür | Seçenekler / aralık | Varsayılan | Ne zaman görünür |
|---|---|---|---|---|---|
| 1 | `settings.style.autoSize` | anahtar | açık/kapalı | açık | her zaman |
| 2 | `settings.style.size` | kaydırıcı, uçlarda `settings.style.size.small`–`settings.style.size.large` | 20…80 (tam sayı; 1920 piksellik TV ekranında yazı yüksekliği) | 46 | her zaman; 1 açıkken soluk ve kilitli |
| 3 | `settings.style.placement` | açılır seçici | `settings.style.placement.cover` · `.above` · `.below` · `.fixed` | örtme (`cover`) | altyazı TV'ye gidiyorsa |
| 3a | `settings.style.position` | kaydırıcı, uçlarda `settings.style.position.bottom`–`settings.style.position.top` | 0…85 (% alttan) | 7 | TV'ye gidiyor ve sabit yer seçiliyse; altında kumanda ipucu `settings.style.remoteHint` |
| 3b | (ipucu) `settings.style.followHint` | ipucu | — | — | TV'ye gidiyor ve sabit yer seçili değilse |
| 4 | `settings.style.computerHint` + ikincil düğme `settings.connection.adjustWindow` | ipucu + düğme | — | — | altyazı bilgisayarda gösteriliyorsa |
| 5 | `settings.style.background` | kaydırıcı, uçlarda `settings.style.background.none`–`settings.style.background.solid` | 0…100 (%) | 100 | her zaman |
| 6 | `settings.style.shape` | açılır seçici | `settings.style.shape.fit` · `settings.style.shape.band` | `fit` | her zaman; altında ipucu `settings.style.shapeHint` |
| 7 | `settings.style.font` | açılır seçici | Aksiyon (GTA tarzı) · Modern · Yuvarlak · Sade (bu sırayla) | Aksiyon | her zaman |
| 8 | `settings.style.bold` | anahtar | | kapalı | her zaman |
| 9 | `settings.style.stack` | anahtar | | açık | her zaman; altında ipucu `settings.style.stackHint` |
| 10 | `settings.style.color` | açılır seçici | `settings.style.color.white` · `settings.style.color.yellow` | beyaz | her zaman |
| 11 | `settings.style.mode` | açılır seçici | `settings.style.mode.inApp` · `settings.style.mode.overlay` | `inApp` | TV'ye gidiyor **ve** kayıtlı TV Android TV ise; altında ipucu `settings.style.modeHint` |
| 12 | `settings.style.watermark` | anahtar | | açık | her zaman (en altta); altında ipucu `settings.style.watermarkHint` |

Yazı tipleri: Aksiyon = dar ve kalın (Barlow Condensed), Modern = Barlow, Yuvarlak = Nunito, Sade = cihazın kendi yazı
tipi. Bu yazı tiplerinde olmayan harfler (Arapça, Tayca, Hintçe) sistem yazı tipiyle çizilir.

Davranış:
- **Her değişiklik** anında kaydedilir ve görünüm bilgisi TV'ye (ve bilgisayardaki pencereye) hemen gönderilir.
- Kaydırıcılar (yazı boyutu, ekrandaki yer, arka plan) **sürüklenmeye başlanınca** TV'ye 8 saniyelik bir deneme
  altyazısı gönderilir: `settings.style.testSubtitle` (metin aşağıdaki tabloda). Oyunda henüz altyazı görülmediyse okuma
  bölgesinin altına yakın, ortada (yatayda %30–%70) tipik bir yere konur; görüldüyse son altyazının yerine.
- Kayıtlı ayar okunurken: yerleşim örtme (`cover`) ve arka plan %60'tan azsa arka plan %100'e çekilir (örtme kipinde
  saydam kutu İngilizceyi gizleyemez).
- Filigran ayarı sadece TV'de sol alt köşedeki ufak Nino rozetini saklar; telefondaki işaret yerinde durur.
- Satır yığma (`settings.style.stack`) kapalıyken gelen satır eskisini siler (TV uygulaması bunu 0.9.16+ sürümde tanır).
- Görüntü modu yalnız Android TV uygulamasını etkiler.

| Anahtar | EN | TR |
|---|---|---|
| `settings.style.onTV` | On the TV | TV'de |
| `settings.style.title` | Subtitle appearance | Altyazı görünümü |
| `settings.style.autoSize` | [yazı boyunu oyunun kendi altyazısına göre ayarlayan anahtar] | [aynı anlam] |
| `settings.style.size` · `.size.small` · `.size.large` | Text size · Small · Large | Yazı boyutu · Küçük · Büyük |
| `settings.style.placement` | Placement | Yerleşim |
| `settings.style.placement.cover` | [çeviri İngilizce altyazının üstüne biner, onu kapatır] | [aynı anlam] |
| `settings.style.placement.above` | [çeviri İngilizce altyazının yukarısında] | [aynı anlam] |
| `settings.style.placement.below` | [çeviri İngilizce altyazının aşağısında] | [aynı anlam] |
| `settings.style.placement.fixed` | Fixed position | Sabit yerde |
| `settings.style.position` · `.position.bottom` · `.position.top` | Position on screen · Bottom · Top | Ekrandaki yeri · Alt · Üst |
| `settings.style.remoteHint` | [sabit yer kipinde altyazının TV kumandasındaki ▲/▼ ile de kaydırılabildiğini belirtir] | [aynı anlam] |
| `settings.style.followHint` | [çevirinin, oyun altyazısını nereye koyuyorsa orada belirdiğini söyler] | [aynı anlam] |
| `settings.style.computerHint` | [Mac'teki altyazıyı yerinden oynatmak için pencerenin sürüklendiğini; önce pencere ayar düğmesine basılması gerektiğini söyler] | [aynı anlam] |
| `settings.style.background` · `.background.none` · `.background.solid` | Background · None · Solid | Arka plan · Yok · Opak |
| `settings.style.shape` | Background area | Arka plan alanı |
| `settings.style.shape.fit` · `.shape.band` | Fit the text · Full-width band | Yazı kadar · Tam genişlikte bant |
| `settings.style.shapeHint` | [arka plan kaydırıcısı en sona (Opak) gelince oyunun İngilizce altyazısının bütünüyle örtüldüğünü; tam genişlikte bandın kenarları da örttüğünü söyler] | [aynı anlam] |
| `settings.style.font` | Font | Yazı tipi |
| `settings.style.bold` | Bold text | Kalın yazı |
| `settings.style.stack` | [hızlı konuşmada bir önceki satırı yukarıda tutma seçeneği] | [aynı anlam] |
| `settings.style.stackHint` | [kapalıyken gelen her satırın eskisini sildiğini; en az 0.9.16 sürümlü TV uygulaması gerektiğini belirtir] | [aynı anlam] |
| `settings.style.color` · `.color.white` · `.color.yellow` | Text color · White · Yellow | Yazı rengi · Beyaz · Sarı |
| `settings.style.mode` | Picture mode | Görüntü modu |
| `settings.style.mode.inApp` | Inside the app | Uygulamanın içinde |
| `settings.style.mode.overlay` | [görüntü kararınca TV'nin kendi HDMI girişinin üstüne binen katman kipi] | [aynı anlam] |
| `settings.style.modeHint` | [Nino TV uygulamasında PS5 görüntüsü kararıyorsa Katman'ın seçilmesini; o kipte TV'nin PS5'i doğrudan HDMI girişinden gösterip altyazıyı üste koyduğunu; görüntü hiç ulaşmazsa TV uygulamasının Katman'a kendisi döndüğünü anlatır] | [aynı anlam] |
| `settings.style.watermark` | Show the Nino mark on the TV | TV'de Nino işaretini göster |
| `settings.style.watermarkHint` | [kapatmanın yalnız TV ekranının sol alt köşesindeki ufak Nino rozetini sakladığını söyler] | [aynı anlam] |
| `settings.style.testSubtitle` | [oyunun üstünde bu deneme yazısının seçilip seçilmediğini soran kısa iki cümle] | [aynı anlam] |

Yazı tipi seçeneklerinin adları (Aksiyon, Modern, Yuvarlak, Sade) ayrı bir xcstrings anahtarı olarak durmaz.

### 6.4 Tema kartları

Altı tema, tek sırada eşit genişlikte kartlar (aralık "m").

**Kart görünüşü:** 16:9 küçük önizleme (köşe 10 pt; aynı koyu oyun sahnesi zemini; ortada, üstten 26 pt aşağıda, 11 pt
boyunda "Kim var orada?" yazısı — verbatim — o temayla ve seçili yazı tipiyle çizilir). Altında tema adı (küçük, yarı
kalın, tek satır) ve tek satır tarif (11 pt, ikincil). Kartın iç boşluğu "s", köşe 14 pt.
Seçiliyken: zemin açık vurgu rengi, 2 pt vurgu renkli kenar, vurgu renginin %25'iyle hafif gölge, önizlemenin sağ
üstünde beyaz-üstüne-vurgu onay dairesi (18 pt; büyüyerek belirir). Seçili değilken: zemin yok, 1 pt cam kenar.
Fare üstüne gelince kart %3 büyür (yay animasyonu).

**Basınca:** tema seçilir (yay animasyonuyla) ve TV'ye bir deneme altyazısı yollanır. Tema seçmek yazı rengi, kalınlık ve
arka plan değerlerini de değiştirir; boyut ve yer kullanıcıda kalır. Tema adları ve tarifleri `Home.xcstrings`'tedir
(ana ekran da kullanır):

| Tema | Ad anahtarı (EN / TR) | Tarif anahtarı (EN / TR) | Renk | Kalın | Arka plan |
|---|---|---|---|---|---|
| Klasik | `home.theme.classic` (Classic / Klasik) | `home.theme.classic.detail` (See-through box / Yarı saydam kutu) | beyaz | hayır | 100 |
| Sinema | `home.theme.cinema` (Cinema / Sinema) | `home.theme.cinema.detail` (Yellow, like the movies / Film gibi sarı) | sarı | evet | 0 |
| Minimal | `home.theme.minimal` (Minimal / Minimal) | `home.theme.minimal.detail` (Keeps the picture clear / Görüntüyü kapatmaz) | beyaz | hayır | 0 |
| Nino Cam | `home.theme.glass` (Nino Glass / Nino Cam) | `home.theme.glass.detail` (Frosted glass with a blue edge / [buzlu cam ve mavi kenarı anlatan kısa tarif]) | beyaz | hayır | 62 |
| Yüksek Kontrast | `home.theme.contrast` (High Contrast / Yüksek Kontrast) | `home.theme.contrast.detail` (The easiest to read / En kolay okunan) | beyaz | evet | 100 |
| Kenarlıklı | `home.theme.outline` (Outline / Kenarlıklı) | `home.theme.outline.detail` (Like text in the game / Oyun yazısı gibi) | beyaz | evet | 0 |

Varsayılan tema: Klasik.

**Temaların çizimi** (önizlemede ve kartlarda; B = yazı boyu). Yazı ortalı, en çok 2 satır; sarı renk = RGB 1.0/0.88/0.21.
Yazı kalınlığı: Minimal orta; Kontrast, Kenarlıklı, Sinema kalın; diğerleri kalın yazı ayarı açıksa kalın, değilse yarı kalın.
- **Klasik:** yazıya hafif siyah gölge; yatay B×0.5, dikey B×0.2 iç boşluklu kutu; kutu siyah, opaklığı arka plan
  yüzdesi × 0.85; köşe B×0.3.
- **Sinema:** kutu yok; iki katlı koyu gölge (B×0.08 ve B×0.3 yarıçap).
- **Minimal:** kutu yok; iki hafif gölge (B×0.06 ve B×0.25).
- **Nino Cam:** yatay B×0.6, dikey B×0.25 boşluklu kutu; çok koyu lacivert (0.024/0.047/0.118) %86; mavi (0.18/0.55/1.0)
  %45 kenar çizgisi (kalınlık B×0.045, en az 1); aynı mavinin %25'iyle B×0.4 parıltı; köşe B×0.45.
- **Yüksek Kontrast:** tam siyah kutu, yatay B×0.45, dikey B×0.18 boşluk, köşe B×0.12.
- **Kenarlıklı:** yazının siyah kopyası 8 yöne B×0.07 (en az 1) kaydırılarak altına çizilir (kontur), üstte asıl yazı;
  bütününe hafif gölge.

---

## 7. Çeviri

Sayfa yukarıdan aşağı kartlardan oluşur.

### 7.1 Dil kartı (başlıksız)

| Satır | Tür | Seçenekler | Varsayılan |
|---|---|---|---|
| `settings.translation.gameLanguage` | açılır seçici | `settings.translation.lang.en` · `.lang.ja` · `.lang.de` · `.lang.fr` · `.lang.es` | İngilizce |
| `settings.translation.targetLanguage` | açılır seçici | her seçenek "bayrak + iki boşluk + dilin kendi adı" (verbatim): 🇹🇷 Türkçe, 🇸🇦 العربية, 🇮🇳 हिन्दी, 🇮🇩 Bahasa Indonesia, 🇹🇭 ไทย, 🇻🇳 Tiếng Việt, 🇵🇰 اردو, 🇧🇩 বাংলা, 🇲🇾 Bahasa Melayu, 🇵🇭 Filipino, 🇳🇱 Nederlands | Türkçe |

Çeviri dili Türkçe değilse altında ipucu `settings.translation.nonTurkishHint` (paketlerin yalnız Türkçede çalıştığını
anlatır).

Davranış: çeviri dili değişince çeviri hafızası yeni dile geçirilir, TV'deki "ekranı çevir" yazıları silinir, köşe
okumaları sıfırlanır, bilgisayardaki pencere gizlenir, son satır unutulur. Dil değişince çeviri sürüyorsa çeviri
hattı yeni dille yeniden kurulur (çeviri durmaz).

### 7.2 GTA 6 kartı

Sadece Türkçeye çevirirken görünür. Başlık **GTA 6** (verbatim). İçinde Tamam etiketi `settings.translation.gtaOK` ve
ipucu `settings.translation.gtaHint`. Seçilecek bir şey yok.

### 7.3 Motor kartı

Başlık: Türkçede `settings.translation.otherGames`, diğer dillerde `settings.translation.engine`.

- İki büyük seçenek satırı (karo görünümünde, seçili olan vurgulu):
  - Solda 18 pt daire: seçiliyse dolu iç daireli vurgu renkli, değilse boş ikincil renkli.
  - Ad (başlık yazısı) ve altında küçük ikincil açıklama.
  - **Ücretsiz** (`settings.translation.free`) — açıklama `settings.translation.freeDetail`.
  - **Gemini** (verbatim marka adı) — açıklama `settings.translation.geminiDetail`.
  - (Bir `settings.translation.recommended` hap etiketi yeri vardır ama ikisinde de kapalıdır: kullanıcı isteğiyle
    kaldırıldı.)
- Gemini seçiliyse altında: **anahtar bölümü** (7.5) ve iki ipucu: gizlilik (`settings.translation.geminiPrivacy`)
  ve sınır (`settings.translation.geminiLimit`).
- Motor ücretsiz değil ve oyunun dili İngilizce değilse ipucu `settings.translation.englishOnly`.
- **Diğer motorlar** açılır-kapanır grup (etiket `settings.translation.moreEngines`, küçük ikincil). Kapalı başlar;
  seçili motor bunlardan biriyse kendiliğinden açık durur. İçinde:
  - 2×2 karo: **DeepL** (`settings.translation.withFreeKey`), **OpenAI** (`settings.translation.withOwnKey`),
    **Claude** (`settings.translation.withOwnKey`), **Yerel model** (`settings.translation.localName`; açıklama
    `settings.translation.localDetail`). Karo: ad (başlık) + küçük açıklama, en az 64 pt yükseklik, seçili olan
    vurgulu. Marka adları (DeepL, OpenAI, Claude, Gemini) çevrilmez; yalnız yerel modelin adı çevrilir.
  - Seçili motor bunlardan biriyse altında o motorun açıklama ipucu (`settings.translation.about.<motor>`: `deepl`,
    `openai`, `claude`, `local`) ve kendi bölümü: DeepL → 7.6, OpenAI/Claude → 7.5, Yerel → 7.7.

Davranış: motor seçmek "çevrimiçi çeviri açık + seçili motor" ayarını yazar; Ücretsiz seçmek çevrimiçi çeviriyi kapatır
(son çevrimiçi motor hatırlanır). Motor, model, yerel sunucu adresi ya da model adı değişince çevirmen durumu yeniden
denetlenir; çeviri sürüyorsa çeviri hattı yeniden kurulur. Çevrimiçi motor yalnız şu hâllerin hepsinde gerçekten kullanılır: oyunun dili İngilizce,
çeviri dili listede, (DeepL için) çeviri dili DeepL'de var, ve motor hazır (bulut motorunda anahtar kayıtlı; yerel
modelde adres ve model adı geçerli). Bunlardan biri eksikse bedava çeviri kullanılır.

Varsayılan: Ücretsiz (çevrimiçi kapalı; hatırlanan çevrimiçi motor DeepL).

### 7.4 Gelişmiş kartı

Açılır-kapanır `settings.translation.advanced` (kapalı başlar). İçinde başlık-solda-anahtar-sağda satırı
`settings.translation.fastDetect` (varsayılan kapalı) ve ipucu `settings.translation.fastDetectHint`. Değişince çeviri
sürüyorsa çeviri hattı yeniden kurulur.

### 7.5 Yapay zekâ anahtar bölümü (Gemini, OpenAI, Claude)

- `settings.key.model` açılır seçici: yalnız ortak model listesindeki iki seçenek (elle yazılamaz). Etiketler:
  `settings.key.model.fast` (ilk, varsayılan) ve `settings.key.model.quality`. Listede olmayan kayıtlı model
  varsayılana döner.
- **Anahtar kayıtlıysa:** solda Tamam etiketi `settings.key.saved`, sağda ikincil `settings.key.test` (denerken
  `settings.key.testing` ve soluk) ve ikincil `settings.key.remove` (siler, sonucu temizler).
- **Kayıtlı değilse:** gizli alan (yer tutucu `settings.key.placeholder`) + ikincil `settings.key.saveAndTest` (alan
  boş ya da denerken soluk). Bu motor seçiliyse ipucu `settings.key.addToStart`. Altında bağlantı
  `settings.key.getKey %@` (motor adıyla; Gemini → aistudio.google.com/apikey, OpenAI → platform.openai.com/api-keys,
  Claude → platform.claude.com/settings/keys). Kayıt başarılıysa alan boşalır.
- Deneme düğmeleri örnek bir satırı çevirtir. Sonuç: başarılıysa ikincil renkli `settings.key.works %@`; değilse hata
  yazısı (7.8).

### 7.6 DeepL bölümü

- Kayıtlıysa: `settings.key.saved` + `settings.key.test` + `settings.key.remove`. Deneme bu ayki kullanımı okur.
- Değilse: gizli alan `settings.key.deeplPlaceholder` + `settings.key.saveAndTest`; altında bağlantı
  `settings.key.getDeepL` (deepl.com/pro-api).
- Sayfa açılınca anahtar kayıtlıysa kullanım kendiliğinden okunur. Sonuç satırı (ikincil renk):
  - geçerli: `settings.deepl.usage %@ %@` · sınır doldu `settings.deepl.limit` · anahtar reddedildi
    `settings.deepl.badKey` · ulaşılamadı `settings.deepl.unreachable` (tabloda).

### 7.7 Yerel model bölümü (Ollama / LM Studio)

Amaç: kullanıcı Terminal'e komut yazmasın.

- Sunucu adresi Ollama'yı gösteriyorsa:
  - **Durum satırı:** bakılırken küçük dönen gösterge + `settings.local.searching`; çalışıyorsa yeşil onay +
    `settings.local.running`; çalışmıyorsa uyarı ünlemi + `settings.local.notRunning` ve altında
    `settings.local.getOllama`. Çalışmıyorsa sağda ikincil bağlantı `settings.local.download` (ollama.com/download) ve
    ikincil `settings.local.checkAgain`.
  - **Önerilen modeller** (her biri bir satır, köşe "control", iç boşluk "m"): solda seçim dairesi; ad (başlık) +
    varsa `settings.translation.recommended` hapı (beyaz kalın 11 pt, mavi geçişli kapsül); altında açıklama. Sağda:
    indiriliyorsa 120 pt ilerleme çubuğu + yüzde; kuruluysa yeşil onay `settings.local.downloaded`; değilse ikincil
    `settings.local.downloadSize %@` (Ollama yoksa ya da başka indirme sürerken soluk). Seçili satır: vurgu renginin
    %8'i zemin + 1.5 pt vurgu kenar. Satıra basmak modeli seçer.
    - TranslateGemma 4B — `settings.local.model.gemma4b` — 3.3 GB — önerilen hapı var (varsayılan model)
    - TranslateGemma 12B — `settings.local.model.gemma12b` — 8.1 GB
    - MiLMMT 4B — `settings.local.model.milmmt` — 3.1 GB
  - İndir: model seçilir, Ollama'ya indirtilir, ilerleme gösterilir; bitince ya da hata olunca liste yenilenir. Hata:
    `settings.local.downloadFailed`.
- `settings.local.test` ikincil düğmesi (denerken / indirirken / adres geçersizken soluk). Sonuç 7.5'teki gibi; hata
  metni sunucu türüne göre (7.8).
- **Gelişmiş** açılır grup (`settings.translation.advanced`): iki satırlık ızgara `settings.local.address` (yer tutucu
  http://localhost:11434/v1) ve `settings.local.modelName` (yer tutucu translategemma:4b); `settings.local.useOllama` /
  `settings.local.useLMStudio` düğmeleri (adresi http://localhost:11434/v1 ya da http://localhost:1234/v1 yapar); adres
  geçersizse hata `settings.local.badAddress %@`; ipucu `settings.local.nameHint`; anahtar kayıtlıysa
  `settings.key.saved` + `settings.key.remove`, değilse gizli alan `settings.local.keyPlaceholder`.
  Alanlar odak değişince ya da Return'de ayara yazılır; değiştiyse eski deneme sonucu silinir. Anahtar test sırasında
  kaydedilir.

### 7.8 Çeviri metinleri

| Anahtar | EN | TR |
|---|---|---|
| `settings.translation.gameLanguage` | Game language | Oyunun dili |
| `settings.translation.lang.en` · `.ja` · `.de` · `.fr` · `.es` | English · Japanese · German · French · Spanish | İngilizce · Japonca · Almanca · Fransızca · İspanyolca |
| `settings.translation.targetLanguage` | [çevrilecek dilin seçicisi] | Çeviri dili |
| `settings.translation.nonTurkishHint` | [oyun paketiyle terim listesinin sadece Türkçeye özel olduğunu; öbür dillerde seçilen motorun (Apple'ın bedava çevirisi, yerel model, DeepL, Gemini, Claude ya da ChatGPT) çevirdiğini; Urduca, Bengalce, Filipince için yapay zekâlı motor şart olduğunu ve Gemini'nin parasız olduğunu anlatır] | [aynı anlam] |
| `settings.translation.gtaOK` | Nino translates it for you | Nino kendiliğinden çeviriyor |
| `settings.translation.gtaHint` | [GTA 6 Türkçesinin Nino'nun paylaşılan çevirisinden geldiğini: her satırı tek sefer, güçlü bir yapay zekâ çevirir, herkese aynısı gider; seçim de anahtar da gerekmez, bedavadır] | [aynı anlam] |
| `settings.translation.otherGames` | Other games | Diğer oyunlar |
| `settings.translation.engine` | Translation engine | Çeviri motoru |
| `settings.translation.free` | Free | Ücretsiz |
| `settings.translation.freeDetail` | [kurulum gerektirmediğini, çevirinin bu Mac'te yapıldığını söyler] | [aynı anlam] |
| `settings.translation.geminiDetail` | [çevirinin daha akıcı olduğunu ve bedava bir Google anahtarı istediğini söyler] | [aynı anlam] |
| `settings.translation.recommended` | Recommended | Önerilen |
| `settings.translation.geminiPrivacy` | [metnin Google'a gittiğini, ücretsiz anahtarda Google'ın onu ürün geliştirmede kullanıp çalışanlarına okutabileceğini, yalnız altyazının gönderildiğini anlatır] | [aynı anlam] |
| `settings.translation.geminiLimit` | [ücretsiz anahtarın dakikalık sınırını; sınır dolunca o satırın ücretsiz çeviriye düştüğünü anlatır] | [aynı anlam] |
| `settings.translation.englishOnly` | [internet motorlarının sadece İngilizce oyunlarda çalıştığını, öbür oyun dillerinde bedava çeviriye düşüldüğünü belirtir] | [aynı anlam] |
| `settings.translation.moreEngines` | [başka çeviri motorlarını açan grubun etiketi] | [aynı anlam] |
| `settings.translation.withFreeKey` | [ücretsiz anahtar gerektiğini gösteren etiket] | [aynı anlam] |
| `settings.translation.withOwnKey` | [kullanıcının kendi anahtarını gerektirdiğini gösteren etiket] | [aynı anlam] |
| `settings.translation.localDetail` | [yerel sunucu adları ve kota olmadığı] | [aynı anlam] |
| `settings.translation.localName` | Local model | Yerel model |
| `settings.translation.about.deepl` | [seçmeli olduğunu; kişisel bedava DeepL anahtarıyla daha akıcı çeviri; metnin DeepL'e yollandığını; DeepL yanıt vermezse Mac'teki çeviri modelinin işi aldığını anlatır] | [aynı anlam] |
| `settings.translation.about.openai` | [OpenAI yapay zekâsının oyunun tonunu tuttuğunu, isimleri bıraktığını; metnin kullanıcının anahtarıyla OpenAI'a gittiğini, masrafın kullanıcının OpenAI hesabına düştüğünü; OpenAI yanıt vermezse bedava çeviriye geçildiğini anlatır] | [aynı anlam] |
| `settings.translation.about.claude` | [Anthropic'in Claude'unun oyunun tonunu tuttuğunu, isimleri bıraktığını; metnin kullanıcının anahtarıyla Anthropic'e gittiğini, masrafın kullanıcının Anthropic hesabına düştüğünü; Claude yanıt vermezse bedava çeviriye geçildiğini anlatır] | [aynı anlam] |
| `settings.translation.about.local` | [parasız ve kota sınırı olmadığını; çeviriyi Mac'te koşan bir yapay zekâ modelinin (Ollama veya LM Studio) yaptığını, metnin dışarı gitmediğini; hızın makineye göre değiştiğini; model yanıt vermezse bedava çeviriye geçildiğini anlatır] | [aynı anlam] |
| `settings.translation.fastDetect` | [değişmemiş görünen altyazı alanının daha sık okunmasını açan anahtar] | [aynı anlam] |
| `settings.translation.fastDetectHint` | [altyazı alanı aynı görünse bile yeniden okumanın 20 kare yerine 2 karede bir yapıldığını, işlemciye daha çok yük bindirdiğini söyler] | [aynı anlam] |
| `settings.translation.advanced` | Advanced | Gelişmiş |
| `settings.key.model` | Model | Model |
| `settings.key.model.fast` | Quick and low-cost (suggested) | [hızlı ve ucuz modeli, önerilen olarak anlatan etiket] |
| `settings.key.model.quality` | Better quality, a bit slower | [daha kaliteli ama biraz yavaş model] |
| `settings.key.saved` | Key saved | Anahtar kayıtlı |
| `settings.key.test` · `settings.key.testing` | Test · Testing… | Dene · Deneniyor… |
| `settings.key.remove` | Remove key | Anahtarı Sil |
| `settings.key.placeholder` | [anahtar alanının yer tutucusu] | [aynı anlam] |
| `settings.key.saveAndTest` | Save and test | Kaydet ve Dene |
| `settings.key.addToStart` | [anahtar eklenene kadar ücretsiz çevirinin kullanıldığını söyler] | [aynı anlam] |
| `settings.key.getKey %@` | [%@ hizmetinden anahtar alma bağlantısı] | [aynı anlam] |
| `settings.key.works %@` | [denemenin başarılı olduğunu söyleyip örnek çeviriyi gösterir] | [aynı anlam] |
| `settings.key.deeplPlaceholder` | DeepL API key | DeepL API anahtarı |
| `settings.key.getDeepL` | [ücretsiz DeepL anahtarı alma sayfasına bağlantı] | [aynı anlam] |
| `settings.deepl.usage %@ %@` | [bu ay kaç karakterin kullanıldığını, toplam hakla birlikte verir] | Bu ay %2$@ karakterin %1$@ tanesi kullanıldı. |
| `settings.deepl.limit` | [aylık DeepL kotasının tükendiğini, yenilenene dek Mac'teki çeviri modelinin çevirdiğini söyler] | [aynı anlam] |
| `settings.deepl.badKey` | [DeepL'in anahtarı reddettiğini, DeepL hesap sayfasından tekrar kopyalanmasını ister] | [aynı anlam] |
| `settings.deepl.unreachable` | [DeepL'e erişilemediğini, internetin denetlenmesini ister] | [aynı anlam] |
| `settings.local.searching` | Looking for Ollama… | Ollama aranıyor… |
| `settings.local.running` | [Ollama'nın bu bilgisayarda çalıştığını söyler] | [aynı anlam] |
| `settings.local.notRunning` | Ollama isn't running. | Ollama çalışmıyor. |
| `settings.local.getOllama` | [Ollama'nın (bedava) indirilip açılmasını, ardından bu ekrana dönülmesini ister] | [aynı anlam] |
| `settings.local.download` | [Ollama indirme düğmesi] | [aynı anlam] |
| `settings.local.checkAgain` | Check again | Yeniden bak |
| `settings.local.downloaded` | Downloaded | İndirildi |
| `settings.local.downloadSize %@` | Download (%@ GB) | İndir (%@ GB) |
| `settings.local.model.gemma4b` | [Google'ın çoğu makinede koşabilen çeviri modeli] | [aynı anlam] |
| `settings.local.model.gemma12b` | [daha iyi çevirir, en az 16 GB bellek ister] | Daha iyi çevirir. En az 16 GB bellek ister. |
| `settings.local.model.milmmt` | [Xiaomi'nin hızlı ve doğal çeviri modeli] | [aynı anlam] |
| `settings.local.downloadFailed` | [indirmenin yarım kaldığını; internetin ve Ollama uygulamasının çalışıp çalışmadığının denetlenip tekrar denenmesini ister] | [aynı anlam] |
| `settings.local.test` | Test connection | Bağlantıyı dene |
| `settings.local.address` | Server address | Sunucu adresi |
| `settings.local.modelName` | Model name | Model adı |
| `settings.local.useOllama` | Use Ollama | Ollama'yı Kullan |
| `settings.local.useLMStudio` | [LM Studio'ya geçiren düğme] | [aynı anlam] |
| `settings.local.badAddress %@` | This address isn't valid. For example: %@ | [adresin geçersiz olduğunu söyleyip örnek adres verir] |
| `settings.local.nameHint` | [LM Studio veya başka bir modelde adın sunucudaki yazılışıyla birebir girilmesini; LM Studio'da modelin yüklenip yerel sunucunun açılmasını ister] | [aynı anlam] |
| `settings.local.keyPlaceholder` | API key (optional) | [isteğe bağlı API anahtarı alanının yer tutucusu] |

Eski düzende motor seçimi için üç ek açıklama metni daha vardı (internetsiz yerel çeviri, en iyi çeviri için ücretsiz
anahtar, Apple çevirisinin Mac'ten çıkmadığı); yeni uygulamada karşılıkları yoktur, yazılmaları gerekmez.

**Anahtar denemesi hata metinleri** (bulut motorlar; %@ = motor adı). Ana ekran da aynı metinleri kullanır.

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| geçerli | `settings.engine.works` | It works. | Çalışıyor. |
| anahtar reddedildi | `settings.engine.badKey %@` | [%@ hizmetinin anahtarı reddettiğini, hesap sayfasından tekrar kopyalanmasını ister] | [aynı anlam] |
| sınır doldu (Gemini) | `settings.engine.geminiQuota %@` | [Gemini'nin günlük bedava kotasının tükendiğini; bedava anahtardan para kesilmediğini; kotanın her gün tazelendiğini (bir sonraki: %@) söyler] | [aynı anlam] |
| sınır doldu (diğer) | `settings.engine.quota %@` | [%@ hesabında kredinin bittiğini veya limite dayandığını söyler] | [aynı anlam] |
| model reddetti | `settings.engine.model %@` | [%@ hizmetinin isteği reddettiğini; öbür modelin seçilmesini veya sonra tekrar denenmesini ister] | [aynı anlam] |
| ulaşılamadı | `settings.engine.unreachable %@` | [o hizmete erişilemediğini, internetin denetlenmesini ister] | [aynı anlam] |

Gemini'de "sıradaki" saat: bir sonraki **Pasifik saatiyle gece yarısı**, kullanıcının yerel saatine çevrilip yalnız saat
(kısa biçim) olarak yazılır.

**Yerel model hata metinleri:**

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| anahtar reddedildi | `settings.engine.local.badKey` | [yerel sunucunun API anahtarını reddettiğini; anahtarın denetlenmesini, sunucu anahtarsız çalışıyorsa silinmesini ister] | [aynı anlam] |
| meşgul | `settings.engine.local.busy` | [yerel sunucunun o an dolu olduğunu, az sonra tekrar denenmesini ister] | [aynı anlam] |
| model yok (LM Studio) | `settings.engine.local.missingLMStudio %@` | [LM Studio'da o modelin olmadığını; indirip yüklemeyi ya da adı denetlemeyi söyler] | [LM Studio'da o modelin olmadığını; indirip yüklemeyi ya da adı denetlemeyi söyler] |
| model yok (diğer) | `settings.engine.local.missing %@` | [yerel sunucuda %1$@ modelinin bulunmadığını ve `ollama pull %1$@` komutuyla indirileceğini söyler] | [aynı anlam] |
| ulaşılamadı (Ollama) | `settings.engine.local.ollamaDown %@ %@` | [Ollama'nın kapalı olduğunu (%1$@ yanıtsız ya da model geç kaldı); Ollama'yı açıp `ollama pull %2$@` ile modeli indirmeyi söyler] | [aynı anlam] |
| ulaşılamadı (LM Studio) | `settings.engine.local.lmStudioDown %@` | [LM Studio'nun kapalı olduğunu (%@ yanıtsız ya da model geç kaldı); LM Studio'yu açıp modeli yükleyerek sunucuyu başlatmayı söyler] | [aynı anlam] |
| ulaşılamadı (başka sunucu) | `settings.engine.local.otherDown %@` | [%@ üzerindeki yerel sunucuya erişilemediğini ya da modelin geç kaldığını; adresin ve sunucunun çalışırlığının denetlenmesini ister] | [aynı anlam] |

Sunucu türü adresten çıkarılır (Ollama / LM Studio / başka). Adres geçersizse Ollama varsayılanı kabul edilir.

---

## 8. OBS katmanı

İki kart.

**Kart 1 (başlıksız):**
- İpucu `settings.obs.hint`.
- Adres satırı: `http://localhost:<sunucu kapısı>/obs` (verbatim, eş aralıklı yazı, seçilebilir), ikincil yüzey
  zeminli, düğme yüksekliğinde kutuda; sağında ikincil `settings.obs.copy` düğmesi. Basınca adres panoya yazılır ve düğme
  `settings.obs.copied` olur.
- İpucu `settings.obs.otherComputer` (başka bilgisayarda OBS için).
- Mac'in ev ağındaki adresi bulunursa: ipucu `settings.obs.noLocalhost` + aynı biçimde ikinci adres
  satırı `http://<ağ adresi>:<kapı>/obs` + kendi kopyala düğmesi.

**Kart 2: `settings.obs.stream`**
- İpucu `settings.obs.streamHint`.
- `settings.obs.background` bölmeli seçici: `settings.obs.green` · `settings.obs.black` · `settings.obs.magenta`.
  Varsayılan yeşil. Seçim bu Mac'te ayrı bir tercih olarak saklanır (ana ayar kaydında değil).
- İkincil düğme: kapalıyken `settings.obs.open`, açıkken `settings.obs.close`. Pencerenin adı `home.stream.title`
  (Nino Stream / Nino Yayın).
- İpucu `settings.obs.keepOpen`.
- Davranış: yayın penceresi açıkken altyazı satırları (yalnız TV'de gösterilse bile) bu pencereye de gelir. Kapatılınca
  ve bilgisayarda gösterim yoksa bilgisayardaki saydam pencere de gizlenir.

| Anahtar | EN | TR |
|---|---|---|
| `settings.obs.hint` | [kartla yayın yapılıyorsa OBS'e bu adresle Tarayıcı kaynağı (1920 × 1080) eklenmesini; altyazının hem ekranda hem yayında oyunun üzerinde çıktığını anlatır] | [aynı anlam] |
| `settings.obs.copy` · `settings.obs.copied` | Copy · Copied | Kopyala · Kopyalandı |
| `settings.obs.otherComputer` | [OBS başka bir makinedeyse localhost yerine Mac'in ağ adresinin yazılmasını; katmanın altyazıyı sadece çeviri sırasında gösterdiğini anlatır] | [aynı anlam] |
| `settings.obs.noLocalhost` | [localhost'u kabul etmeyen yayın programları (örnek: TikTok LIVE Studio) için bu adresin bilgisayarın ağ adresiyle yazılmasını önerir; iki noktayla biter] | [aynı anlam] |
| `settings.obs.stream` | Stream window | Yayın penceresi |
| `settings.obs.streamHint` | [saydam tarayıcı kaynağı desteklemeyen programlarda (örneğin Streamlabs ya da TikTok LIVE Studio) yayın penceresinin açılıp Pencere yakalamayla eklenmesini (pencere adı Nino Stream / Nino Yayın) ve zeminin Chroma key süzgeciyle kaldırılmasını anlatır] | [aynı anlam] |
| `settings.obs.background` | Background | Arka plan |
| `settings.obs.green` · `.black` · `.magenta` | Green · Black · Magenta | Yeşil · Siyah · Mor |
| `settings.obs.open` · `settings.obs.close` | Open stream window · Close stream window | [yayın penceresini açan / kapatan düğme] |
| `settings.obs.keepOpen` | [yayın sürdükçe pencerenin açık ve üstü kapanmamış kalmasını ister; çeviri sırasında altyazı yalnız TV'ye ayarlı olsa da bu pencerede de çıkar] | [aynı anlam] |

---

## 9. Sistem sağlığı

Ayrı belgede: `gecmis-hakkinda-saglik.md` › Sistem sağlığı.

## 10. Güncellemeler

(Aynı kart `guncelleme-admin.md` › Ayarlar › Güncellemeler'de de anlatılır; ikisi aynıdır.)

Tek kart.
- Üst satır: solda 44 pt logo; yanında uygulamanın tam adı (verbatim, başlık yazısı) ve altında ikincil
  `settings.updates.version %@` (görünen sürüm). Sağda ikincil düğme `settings.updates.check`; denetlerken
  `settings.updates.checking` ve soluk. Basınca zorla (önbelleği atlayarak) denetler.
- Yeni sürüm varsa: parıltı simgesi (vurgu rengi) + kalın `settings.updates.ready %@` + ikincil
  `settings.updates.whatsNew` (sürüm notlarını tarayıcıda açar) + birincil `settings.updates.download` (güncellemeyi
  başlatır). Altında ipucu `settings.updates.installHint`.
- Yeni sürüm yoksa durum: güncelse Tamam etiketi `settings.updates.upToDate`; denetleme başarısızsa hata yazısı
  `settings.updates.failed`; hiç denetlenmediyse ya da denetleniyorsa boş.
- En altta her zaman ipucu `settings.updates.auto` (kendiliğinden denetlediğini anlatır).
- Arka planda: ana ekran açıkken yarım saatte bir kendiliğinden denetlenir (ağa en çok saatte bir çıkar).

| Anahtar | EN | TR |
|---|---|---|
| `settings.updates.version %@` | Version %@ | Sürüm %@ |
| `settings.updates.check` · `settings.updates.checking` | Check for updates · Checking… | [güncelleme denetleme düğmesi] · Denetleniyor… |
| `settings.updates.ready %@` | Nino %@ is ready. | Nino %@ hazır. |
| `settings.updates.whatsNew` | What's new | Yenilikler |
| `settings.updates.download` | Download | İndir |
| `settings.updates.installHint` | [Nino'nun güncellemeyi indirip kurduktan sonra kendini yeniden başlattığını, ayarların korunduğunu söyler] | [aynı anlam] |
| `settings.updates.upToDate` | You're on the latest version. | [en son sürümün kullanıldığını söyler] |
| `settings.updates.failed` | [denetlemenin yapılamadığını, internete bakmayı söyler] | [aynı anlam] |
| `settings.updates.auto` | [Nino'nun güncel sürümü kendiliğinden bulup arkada kurduğunu, yenisinin bir sonraki başlatmada açıldığını söyler] | [aynı anlam] |

## 11. Nino'ya Sor

Listeden basılınca sayfa açılmaz (bkz. 2). Sayfa bir yoldan doğrudan açılırsa içinde tek kart: ipucu
`settings.ask.hint` (Ask Nino anything about connecting, translation or settings. / Bağlantı, çeviri ya da ayarlarla
ilgili her şeyi Nino'ya sorabilirsiniz.) ve birincil `settings.section.askNino` (Ask Nino / Nino'ya Sor) düğmesi;
basınca sohbet sayfası açılır.

## 12. Sorun Bildir ve Hakkında

Ayrı belgede: `gecmis-hakkinda-saglik.md`. Sorun Bildir gönderildikten sonra Ayarlar listesine kendiliğinden döner.

## 13. Sıfırla

Başlıksız tek yüzey (karo, iç boşluk "l"):
- Gövde boyunda ikincil renkli açıklama `settings.reset.hint`.
- Yan yana: ikincil `settings.reset.fromTV` ve tehlikeli (kırmızı) `settings.reset.everything`.
- **TV'den yeniden kurma** (`settings.reset.fromTV`): onay sormaz. Çeviri durur; kayıtlı TV, TV anahtarları, TV
  uygulaması sürümü ve "kurulum bitti" işareti silinir; TV uygulaması durumu sıfırlanır. Daha önce "TV'm yok"
  seçildiyse altyazı yeri TV'ye döner. PS5 hesabına ve PS5 eşleşmesine dokunulmaz. Ayarlar kapanır, kurulum sihirbazı **TV
  adımından** açılır.
- **Her şeyi sıfırlama** (`settings.reset.everything`): onay penceresi açar. Başlık `settings.reset.confirmTitle`,
  mesaj `settings.reset.confirmMessage`, kırmızı `settings.reset.everything` ve vazgeç (`settings.cancel`). Onaylanınca:
  çeviri durur; PSN hesabı, PS5, TV, TV anahtarları, TV uygulaması sürümü, kurulum işareti ve PS5 giriş şifresi silinir;
  Ayarlar kapanır; sihirbaz **en baştan** (konsol seçiminden) başlar. Görünüm/çeviri ayarları, çeviri anahtarları ve
  geçmiş silinmez.

| Anahtar | EN | TR |
|---|---|---|
| `settings.reset.hint` | [iki düğmenin farkını anlatır: biri PS5 hesabıyla eşleşmeyi koruyup yalnız TV'yi yeniden kurar, öbürü kayıtlı PS5'i, hesabı ve TV'yi silip PSN girişini yeniden ister] | [aynı anlam] |
| `settings.reset.fromTV` | [kurulumu TV adımından yeniden başlatan düğme] | [aynı anlam] |
| `settings.reset.everything` | Reset everything | Her şeyi sıfırla |
| `settings.reset.confirmTitle` | Reset everything? | [her şeyin sıfırlanmasını onaylatan soru] |
| `settings.reset.confirmMessage` | [kayıtlı PS5'in, hesabın ve TV bağlantısının silineceğini, kurulumun sıfırdan başlayacağını söyler] | [aynı anlam] |
| `settings.cancel` | Cancel | Vazgeç |

---

## 14. Gizli bölümler (sayfaları hazır, listede yok)

### 14.1 Arayüz
- Kart `settings.interface.home`: iki seçenek kartı yan yana (eşit genişlik). Her birinde 130 pt yükseklikte önizleme
  (köşe 10 pt, koyu lacivert 0.04/0.08/0.20 zemin), altında seçim dairesi (seçiliyse vurgu renkli dolu onay dairesi) +
  kalın ad, en altta küçük açıklama. Seçili kartın kenarı 2 pt vurgu, diğeri 1 pt cam kenar; köşe 14 pt.
  - `settings.interface.livingRoom` (varsayılan): önizlemede salon görseli, mavi parıltılı. Açıklama
    `settings.interface.livingRoomHint`.
  - `settings.interface.toggle`: önizlemede 150×40 pt gri-mavi geçişli kapsül ve üstünde güç simgeli 50 pt daire.
    Açıklama `settings.interface.toggleHint`.
- Kart (başlıksız): `settings.interface.appearance` seçici: `settings.interface.dark` · `settings.interface.light` ·
  `settings.interface.system` (varsayılan sistemle aynı). Değişince bütün pencerelere anında uygulanır.

### 14.2 Dil
Çeviri sayfasındaki dil kartının aynısı (7.1).

### 14.3 Oyun paketleri
- Kendi başlığı: büyük `settings.section.packs` + sağda (paket varsa) yeşil hap `settings.packs.badge %lld`.
- Açıklama `settings.packs.hint`, çeviri dili Türkçe değilse uyarı kartı `settings.packs.turkishOnly`, büyük ikincil
  `settings.packs.import` (dosya seçici: JSON, düz metin, SRT; dosya en çok 64 MB), hata yazısı, paket yoksa
  `settings.packs.none` kartı, varsa 2 sütunlu paket karoları (48 pt kare içinde adın ilk üç kelimesinin baş harfleri
  büyük harfle, ad, `settings.packs.lines %@`).
- Altta bir karo içinde anahtar satırları (aralarında çizgi): `settings.packs.use` (açık) · `settings.packs.share`
  (açık) + ipucu `settings.packs.shareHint` · `settings.packs.ask` (açık) + ipucu `settings.packs.askHint` ·
  `settings.packs.speaker` (açık) + ipucu `settings.packs.speakerHint`.
- İçe aktarma sayfası (440 pt): başlık `settings.packs.importTitle`, `settings.packs.gameTitle` alanı (öneri dosyadan
  ya da dosya adından), sayılar ızgarası (`settings.packs.usable`, `settings.packs.invalid`, `settings.packs.duplicates`,
  `settings.packs.conflicts`), kullanılabilir satır yoksa uyarı `settings.packs.empty`; `settings.cancel` /
  `settings.packs.install`. Aynı kimlikte paket varsa `settings.packs.replaceTitle` uyarısı.
- Etkiler: paket kullanımı değişince çeviri hattına paketler yeniden bağlanır. Ortak havuz değişince havuz ve
  ortak çeviri açılır/kapanır, paketler yeniden bağlanır. Konuşan adı anında çeviri hattına iletilir.

### 14.4 Altyazı alanı
- Kart: hazır bölge bölmeli seçicisi (etiketsiz; erişilebilirlik adı `settings.area.preset`), son PS5 karesiyle canlı
  bölge önizlemesi (çerçeve sürüklenir/köşeden boyutlanır; elle değişince seçim `settings.area.custom` olur), özel
  bölgede `settings.area.vertical` ve `settings.area.height` kaydırıcıları (yüzde değerli) ve `settings.area.reset`
  (alt bölgeye döner), iki ipucu (`settings.area.fitHint`, `settings.area.dragHint`). Önizlemede henüz kare yokken
  `settings.area.noFrame`.
- Kart `settings.area.extra`: en çok üç ek alan (görev sağ üst, bildirim sol alt, telefon sağ alt); her biri ad alanı
  (`settings.area.name`), `settings.area.read` anahtarı, `settings.area.remove`, hazır yer seçicisi (+ özel), kendi
  önizlemesi (kapalıysa %50 soluk). `settings.area.add` menüsü. Kartın ipucu `settings.area.extraHint`.
- Kart `settings.area.translateScreen`: yalnız ipucu `settings.area.translateScreenHint`.

Hazır bölgeler: `settings.area.bottom` (varsayılan; tam alt okuma bölgesi), `settings.area.top` (üstten %3–%38, yatayda
%14–%86), `settings.area.full`, `settings.area.custom`. Kaydırıcıların yanındaki değer `settings.area.percent %lld`
ile yazılır; Türkçede yüzde işareti öndedir (yani "%40").

### 14.5 Gizli bölümlerin metinleri

| Anahtar | EN | TR |
|---|---|---|
| `settings.section.interface` | [arayüz bölümünün adı] | Arayüz |
| `settings.interface.home` | [ana ekran seçeneklerinin kart başlığı] | [aynı anlam] |
| `settings.interface.livingRoom` | [salon görünümünün adı] | [aynı anlam] |
| `settings.interface.livingRoomHint` | [fişi prize takınca altyazının açıldığını anlatır] | [aynı anlam] |
| `settings.interface.toggle` | [cam düğme görünümünün adı] | [aynı anlam] |
| `settings.interface.toggleHint` | [cam düğme kaydırılınca TV'nin canlı altyazıyla yukarıdan indiğini anlatır] | [aynı anlam] |
| `settings.interface.appearance` | [koyu/açık görünüm seçicisinin adı] | [aynı anlam] |
| `settings.interface.dark` · `.light` · `.system` | [koyu · açık · sistemle aynı] | [aynı anlam] |
| `settings.section.language` | Language | Dil |
| `settings.section.packs` | Game packs | Oyun paketleri |
| `settings.packs.badge %lld` | Free · %lld games | [ücretsiz olduğunu ve paketli oyun sayısını gösteren hap] |
| `settings.packs.hint` | [paketlerin bazı oyunlar için önceden hazırlanmış Türkçe çeviri olduğunu; paketteki satırın motora uğramadan anında çıktığını anlatır] | [aynı anlam] |
| `settings.packs.turkishOnly` | [paketlerin yalnız Türkçe çeviride kullanıldığını söyler] | [aynı anlam] |
| `settings.packs.import` | Import pack… | Paketi içe aktar… |
| `settings.packs.none` | [kurulu paket olmadığını söyler] | Kurulu oyun paketi yok. |
| `settings.packs.lines %@` | %@ lines | %@ satır |
| `settings.packs.use` | Use game packs | [paket kullanımını açıp kapatan anahtar] |
| `settings.packs.share` | [okunan İngilizce altyazıların ortak havuza gönderilmesini açan anahtar] | [aynı anlam] |
| `settings.packs.shareHint` | [yollananın yalnız oyunun İngilizce metninin olduğunu, kullanıcı adının gitmediğini; bunun herkesin Türkçe çevirisini iyileştirdiğini söyler] | [aynı anlam] |
| `settings.packs.ask` | [oynanan oyunun sorulmasını açan anahtar] | Oynadığım oyunu sor |
| `settings.packs.askHint` | [oyunu tanıyan paket yoksa Nino'nun çeviri başlamasından 2 dakika sonra tek sefer sorduğunu söyler] | [aynı anlam] |
| `settings.packs.speaker` | Show the speaker's name | Konuşanın adını göster |
| `settings.packs.speakerHint` | [karakter adının çevirinin önünde kaldığını, adın çevrilmediğini anlatır; örnek "ARTHUR: …"] | [aynı anlam] |
| `settings.packs.error.unreadable` | Couldn't read the translation file. | [çeviri dosyasının okunamadığını söyler] |
| `settings.packs.error.format` | [içe aktarmanın olmadığını, biçimi ve kodlamayı denetlemeyi söyler] | [aynı anlam] |
| `settings.packs.importTitle` | Import game pack | [içe aktarma sayfasının başlığı] |
| `settings.packs.gameTitle` | Game title | Oyunun adı |
| `settings.packs.usable` · `.invalid` · `.duplicates` · `.conflicts` | Usable entries · Invalid records · Duplicate pairs · Conflicting entries | [kullanılabilir satır sayısı] · Geçersiz kayıt · [yinelenen çift sayısı] · Çakışan satır |
| `settings.packs.empty` | The file has no usable translations. | [dosyada kullanılabilir çeviri olmadığını söyler] |
| `settings.cancel` | Cancel | Vazgeç |
| `settings.packs.install` | Install pack | Paketi kur |
| `settings.packs.replaceTitle` | Replace game pack? | [paketin değiştirilmesini onaylatan soru] |
| `settings.packs.replace` | Replace pack | Paketi değiştir |
| `settings.packs.replaceMessage` | [aynı kimlikte bir paketin zaten kurulu olduğunu ve değiştirmenin onu ezeceğini söyler] | [aynı anlam] |
| `settings.packs.error.sameFile` | [seçilen dosyanın halihazırda kurulum klasöründe olduğunu, başka oyun adının seçilmesini ister] | [aynı anlam] |
| `settings.packs.error.install` | Couldn't install the game pack. | Oyun paketi kurulamadı. |
| `settings.section.area` | Subtitle area | Altyazı alanı |
| `settings.area.preset` | Area preset | Hazır bölge |
| `settings.area.bottom` · `.top` · `.full` · `.custom` | Bottom area · Top area · Full screen · Custom | Alt bölge · Üst bölge · Tam ekran · Özel |
| `settings.area.vertical` · `settings.area.height` | Vertical position · Height | Dikey konum · Yükseklik |
| `settings.area.percent %lld` | %lld%% | %%%lld (yani "%40") |
| `settings.area.reset` | Reset area | Alanı Sıfırla |
| `settings.area.noFrame` | [çeviri başlayınca oyun görüntüsünün burada çıkacağını söyler] | [aynı anlam] |
| `settings.area.fitHint` | [çerçevenin oyun altyazısının çıktığı bölgeye oturtulmasını ister] | [aynı anlam] |
| `settings.area.dragHint` | [çerçeveyi sürükleyerek taşımayı, köşesinden boyutlamayı anlatır] | [aynı anlam] |
| `settings.area.extra` | Extra areas | Ek alanlar |
| `settings.area.extraHint` | [altyazıdan başka en fazla 3 küçük alanın (görev metni, oyun içi telefondaki mesaj, bildirim) okunabildiğini; her birinin yaklaşık saniyede bir okunup yalnız metni değişince yeniden çevrildiğini; çevirinin TV'de özgün metnin yanında çıktığını anlatır] | [aynı anlam] |
| `settings.area.add` | Add extra area | Ek alan ekle |
| `settings.area.name` | Area name | Alanın adı |
| `settings.area.read` | Read this area | Bu alanı oku |
| `settings.area.remove` | Remove | Kaldır |
| `settings.area.place.quest` · `.place.notification` · `.place.phone` | Quest (top right) · [bildirim, sol alt] · [telefon, sağ alt] | Görev (sağ üst) · Bildirim (sol alt) · Telefon (sağ alt) |
| `settings.area.default.quest` · `.default.notification` · `.default.phone` (yeni alanın varsayılan adı) | Quest · Notification · Phone | Görev · Bildirim · Telefon |
| `settings.area.translateScreen` | [ekranı çevirme kartının başlığı, kısayol ⌥⌘T ile] | Ekranı çevir (⌥⌘T) |
| `settings.area.translateScreenHint` | [oyun sırasında ⌥⌘T ile ekrandaki tüm metnin tek sefer çevrilip TV'de bulunduğu yerde gösterildiğini; ikinci basışın çevirileri sildiğini anlatır] | [aynı anlam] |

## 14a. Başka ekranların da kullandığı parçalar

Bu dosyada tarif edilen bazı parçalar Ayarlar dışında da kullanılır; yeni yazımda tek parça olarak yazılmalı:

- **Tema çizimi** (6.4'teki çizim kuralları): ana ekranın salon sahnesindeki ve cam düğmedeki TV'de (26–27 pt), ve
  bilgisayardaki altyazı penceresinde (o anki satır tam boy, önceki satırlar %80 boy, satır sınırı yok).
- **Canlı önizleme** (6.2): kurulumun deneme adımında (400×225) ve daha iyi çeviri adımında (300×169). Bu yerlerde demo
  satırları yerine çeviri sürerken **gerçek satır** (Türkçe + İngilizce) verilebilir: o zaman döngü durur, Türkçe
  boş değilse yalnız Türkçe görünür, İngilizce gösterilmez. Varsayılan boyut 452×254.
- **Tema seçici**: varsayılan 3 sütun (3×2); Ayarlar'da 6 sütun kullanılır.
- **Başlık-solda-anahtar-sağda satırı**: Sorun Bildir'de de kullanılır. Başlık "headline" yazı, anahtar etiketsiz, vurgu
  renkli.
- Eski bir **kenar çubuklu ayarlar düzeni** (solda bölüm listesi, sağda sayfa) kodda durur ama hiçbir yerde
  kullanılmaz; yeni yazımda yapılmasına gerek yok.
- **Çeviri motoru hata metinleri** (7.8): ana ekran da aynı metinleri gösterir.
- **Bağlantı kartı** (4): ana ekranda kısa hâliyle (açıklamasız, kart denetimsiz) kullanılır.

---

## 15. Admin (geliştirici) modu

Ayarlar penceresinde admin moduna özel **ek bir satır ya da bölüm yoktur**. Admin modu (geliştirici derlemesi ya da
bu Mac'te gizli bir tercih ile açılır) yalnız çeviri ve ana ekran davranışını değiştirir; bkz. `guncelleme-admin.md`.

## 16. Kayıt

- Bütün ayarlar tek bir kayıt olarak kullanıcı tercihlerine yazılır (Anahtar Zinciri değil); her değişiklikte.
- Eski kayıtta olmayan yeni ayarlar varsayılanla dolar; eski ayarlar kaybolmaz.
- Anahtar Zinciri'nde yalnız gizli bilgiler durur: çeviri anahtarları (DeepL, Gemini, OpenAI, Claude, yerel), PS5 giriş
  şifresi, hesap ve TV anahtarları.
- Yayın penceresinin zemin rengi ayrı bir küçük tercih olarak saklanır.
