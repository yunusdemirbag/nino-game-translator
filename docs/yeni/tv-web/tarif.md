<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# LG ve Samsung TV uygulaması: davranış tarifi

Bu belge, `tv-webos/` ve `tv-tizen/` altındaki şimdiki TV uygulamasının (sürüm 4.0.3) **ne yaptığını** anlatır.
Yeni uygulama (`apps/tv-web/`) bu tarife göre kendi yapısıyla baştan yazıldı; ekran metinleri üç dilde aynı
anlamla yeniden yazıldı. Tarif eski kod okunarak çıkarıldı;
yeni kodda eski satır kalmaması için ayrıca satır karşılaştırması yapıldı (bkz. `ilerleme.md`). Sayılar (renk, boy, süre) tasarımın
parçasıdır ve aynen korunur. Ekran metinleri burada alıntılanmaz; anahtar adıyla anılır (`src/js/strings.js`).

## 1. Genel

- Tek web uygulaması, iki paket: LG webOS (`com.ninotranslator.tv`, .ipk) ve Samsung Tizen (`NinoTVApps.Nino`, .wgt).
- Ekran 1920×1080 düzenlenir (`<meta name="viewport" content="width=1920">`). Sayfa zemini **saydamdır**: HDMI
  görüntüsü sayfanın altında ayrı bir katmanda çizilir.
- Eski TV tarayıcıları (Tizen 2.4, webOS 3) için yalnız ES5 JavaScript; derleme aracı yok.
- Dil TV'nin dilinden: `tr…` → Türkçe, `ar…` → Arapça (yazılar sağdan sola), değilse İngilizce.
- Yazı tipi: TV'nin kendi yazı tipi (`LG Smart UI`, `Museo Sans`, `SamsungOne`, `Tizen Sans`, Roboto, Arial), sonra
  Arapça yazı tipleri. Ayrıca pakette OFL yazı tipleri: Nino Modern (Barlow), Nino Condensed (Barlow Condensed),
  Nino Rounded (Nunito).

## 2. Katmanlar (alttan üste, z-index)

| z | Öğe | Ne |
|---|---|---|
| — | `video-host` | HDMI görüntüsü (LG: `<video>` + `ext://hdmi:N`; Samsung: TVWindow arkada) |
| 5 | bekleme sahnesi (attract) | bağlı değilken tam ekran sinematik demo |
| 7 | ek alanlar (regions), filigran | köşe yazılarının çevirisi; sol altta Nino rozeti |
| 8 | ekran çevirisi (screen) | telefon balonları, harita kartı, görev yazısı |
| 9 | altyazı örtüsü, oyunun sahte İngilizce altyazısı (demo) | |
| 10 | altyazı | Türkçe çeviri, en çok 3 satır yığın |
| 12 | bekleme kartı, ok, tanıtım rozeti | |
| 20 | bilgi paneli, demo notu | |
| 21 | Samsung kaynak ipucu | |
| 22 | HDMI görüntüsü yok uyarısı (`signalTitle`) | |
| 50 | çeviri başladı bildirimi (`startedNote`) | |

Köşedeki kutular TV'nin güvenli alanında: üstte 54 px, yanlarda 96 px.

## 3. Altyazı kutusu

- Yer: varsayılan `left: 8%; right: 8%; bottom: 7%`, ortalı.
- Yazı: 46 px, satır yüksekliği 1.3, kalınlık 600, beyaz, üç katmanlı siyah gölge
  (`0 0 3px #000, 0 0 3px #000, 0 2px 4px #000`).
- Kutu: `padding 10px 26px`, köşe 18 px, zemin `rgba(6,12,30,0.74)`, 18 px arka bulanıklık,
  gölge `0 10px 40px rgba(0,0,0,0.35)`.
- Görünmezken `visibility: hidden` (yerini korur).
- Bekleme demosunda Türkçe kutuya ince mavi kenar eklenir: `0 0 0 2px rgba(45,140,255,0.35)`.

### 3.1 Uzun çeviriyi bölme
- 56 karakterden uzunsa ve içinde satır sonu yoksa sözcük sınırından **en çok 2 satıra**, en uzun satırı en kısa
  olacak, eşitlikte satır uzunluklarının kareleri toplamı en küçük olacak şekilde bölünür.
- Yazı küçültme oranı: `min(1, max(0.75, 56·2 / uzunluk))`. Yazı boyu `taban × oran`.
- İlk 3 sözcükten biri `:` (ya da `：`) ile bitiyorsa (konuşan adı, ör. `KAPTAN:`) o sözcük sonrakiyle birleşik kalır.
- Satırlar `white-space: pre-line` ile gösterilir.

### 3.2 Gösterme ve kaldırma süreleri
- Süre verilmişse `max(1200, süre)` ms, verilmemişse `min(8000, 2000 + 60 × uzunluk)` ms sonra kalkar.
- "Okuma payı": satır gösterildikten sonra `min(5000, 2000 + 60 × uzunluk)` ms içinde gelen **temizle** isteği yazıyı
  hemen silmez, pay dolunca siler.
- Bağlantı koparsa yazı hemen silinmez; 6 sn içinde geri gelmezse altyazı, ekran çevirisi, ek alanlar ve rozet
  kaldırılır.

### 3.3 Hızlı konuşma yığını
- Yeni satır öncekinden 1,5 sn içinde gelirse önceki satır yeni satırın **üstünde**, %80 boyda, %75 opaklıkta kalır;
  1,5 sn sonra 0,4 sn'de solarak kalkar. Orada zaten bir satır varsa o da bir üste (iki önceki, %60 opaklık) kayar.
  En çok 3 satır.
- Üste çıkmaz: yeni satır "yerine geçer" (`replace`) işaretliyse; paragraf yazısıysa; önceki ile "aynı satır"sa;
  göndericinin `stackPrevious` ayarı kapalıysa (ayar TV'de saklanır, hiç gelmediyse açık).
- **Aynı satır**: küçük harfe çevrilip noktalama (`. , ! ? ; : … " ' “ ” ‘ ’ « » ( ) [ ] - – — ، ؟ ؛`) ve boşluklar
  atılınca eşitse ya da biri ötekini içeriyorsa aynıdır; ancak içerilen tek sözcükse öteki satırda tam sözcük olarak
  geçmelidir (ör. `Hayır!` ile `Hayır, şimdi değil!` farklı sayılır; `şimdi değil` ise `Hayır, şimdi değil` ile aynı).
- Üstteki satırların kutusu: `padding 6px 20px`, 37 px, alt boşluk 14 px, zemin `rgba(0,0,0,0.6)`.

### 3.4 Yerleşim (bilgisayardan gelen `placement`)
- `fixed` (varsayılan): alttan `bottomPercent` (varsayılan %7, en az %3, en çok %85).
- `cover` / `above` / `below`: oyundaki İngilizce satırın kutusu (0–1 oranlarla `left, top, right, bottom`)
  biliniyorsa ona göre:
  - Yatayda İngilizce satırın ortasına hizalanır; yarı genişlik `max(0.3, min(merkez, 1−merkez))`; kenarlarda en az %5.
  - `below` ve kutunun altı > 0.88 ise `above`a; `above` ve üstü < 0.12 ise `below`a geçer. Ara boşluk ekran
    yüksekliğinin %1,2'si.
  - `cover`: çeviri kutunun dikey ortasına; İngilizce koyu bir örtüyle kapanır. Örtü kutuyu her yandan 0.012 paylı
    kaplar, çeviri daha büyükse onu da içine alır; köşe 6 px. Bu sırada çevirinin kendi zemini, kenarı, gölgesi kalkar
    (oyunun altyazısı gibi düz beyaz yazı).
- Yerleştirilen altyazı ekran dışına düşerse sabit yere döner.
- **Otomatik boy** (`autoSize`): son 24 kutu yüksekliğinin %30'luk değeri "tek satır" sayılır; satır sayısı buna göre
  bulunur; ölçülen boy `kutu yüksekliği / satır × 1.022`; son 7 ölçümün ortancası, 27 px ile ekran yüksekliğinin
  %5,08'i arasında.
- Kumandanın ▲▼ tuşları yalnız `fixed`te altyazıyı %3 taşır, yeri saklanır; yazı yoksa yer önizleme yazısı
  2,5 sn gösterilir. Bilgisayardan gelen yeni `bottomPercent`, kumandanın kaydını siler.

### 3.5 Biçim (bilgisayardan gelen `style`)
- `fontSize`: taban boy (üstteki satırlar %80'i). `bold`: 700/600. `textColor`: `white` #FFFFFF, `yellow` #FFE135.
- `background` (0–100): zemin `rgba(0,0,0,a)`; a < 0.3 ise yazıya 1 px sert kontur; 100'de örtü tam siyah.
  ≥ 90 ise **cam görünüm** (`glass`): zemin ortası koyu, kenarları eriyen oval; yazı Nino Rounded, ince kontur,
  %70 ölçekli; örtü `rgb(10,10,10)`, köşe 30 px, dışa taşan gölge.
- `backgroundShape: band`: zemin ve örtü ekranın iki kenarına uzanan bant, köşesiz.
- `theme`: `cinema`, `minimal`, `glass` (Nino Cam: koyu lacivert zemin, mavi kenar), `contrast` (tam siyah),
  `outline` (zeminsiz, 2 px kontur).
- `font`: `modern`, `condensed`, `rounded`.
- `watermark: false`: sol alttaki rozet hiç görünmez.
- `stackPrevious`, `autoSize`, `placement`, `bottomPercent`: yukarıda.
- Sahne ışığı (`light`, 0–1, cam görünümde): zemin opaklığı `0.3 + 0.55 × ışık`; örtünün gölgesi buna göre.
- Buzlu örtü (`cover`, base64 JPEG, cam görünümde): örtünün zemini sahnenin bulanık hali; kenarları maskeyle erir.

### 3.6 Düğme simgeleri ve vurgu
- Yazıdaki `✕ ○ △ □` kendi SVG çizimimiz olan cam gibi koyu yuvarlak tuşlar; `●`, `L1–R3`, `OPTIONS`, `TOUCHPAD`/`▦`,
  yön okları `↑↓←→✜`, harita işaretleri `Ⓐ–Ⓩ` (sarı daire içinde harf) rozet olarak çizilir.
- `⟦…⟧` arasındaki sözcükler vurgu renginde (#ff5fb2).
- Arap harfi içeren satır `dir="rtl"`.

## 4. Ekran çevirisi (`screen`) ve ek alanlar (`region`)

- `screen`: öğe listesi. Her öğe kendi kutusunda (0–1 oranlar):
  - Düz öğe: koyu kutu (`#000`, 6 px gölge), yazı boyu satır yüksekliğinin %95'i (14–96 px), Türkçe uzunsa kutu en çok
    1,5 kat uzar sonra yazı küçülür; sağ yarıdaki öğe sağa yaslı. Pay: solda/dikeyde geniş, sağda dar.
  - `paragraphs` sola yaslı satır satır; `plain` hafif gölgeli sade yazı; `card` harita kartı (koyu zemin, üstte
    kırmızı-beyaz şerit, ilk satır kalın); `italic`.
  - Balon (`fill` renkli): telefon mesaj balonu, aynı zemin/yazı rengiyle kutunun içine sığdırılır (en küçük 11 px),
    `alpha`, `angle` (eğik telefon), `frost` (buzlu kart), `side` (sırayla kayarak gelir).
  - Zemin (`backdrop`): telefonun yanındaki mesaj paneli; sağ altta saydam Nino rozeti, üstte gönderenin adı.
  - Aynı balonlar yeniden gelirse silinip çizilmez, yalnız yerleri yumuşakça kayar.
  - `overlay: true` değilse altyazıyı kaldırır. Süre (varsayılan 20 sn) dolunca kalkar; balonlu panel 0,3 sn'de solar.
- `region`: `{id, text, box, line}`; köşe yazısının çevirisi kendi kutusunda (`rgba(0,0,0,0.9)`, 18–44 px). Alt yarıdaki
  kısa (yükseklik ≤ 0.16) yazının çevirisi yazının **üstünde**, yarı saydam ve bulanık zeminle durur. Boş `text` o
  alanı, `region-clear` hepsini kaldırır.

## 5. Bekleme ekranı (bağlı değilken)

Göründüğü durum: bilinen bir gönderici adresi yok, demo oynamıyor, panel ve "görüntü yok" kutusu kapalı.

- Tam ekran yağmurlu gece şehri: degrade gökyüzü, ay, kayan bulutlar, iki dönen projektör ışığı, uzak/yakın şehir
  siluetleri (pencere ışıkları), çatıda pelerini dalgalanan kahraman silueti, kenar kararması; sahne 40 sn'de yavaşça
  yaklaşır.
- Sol üstte cam kart: logo + "Nino" (beyazdan maviye degrade), üç numaralı adım, ayraç, üç zıplayan nokta +
  bekleme yazısı, altında TV'nin adresi ve aramanın sürdüğü.
- Sağ üstte tanıtım rozeti; sol altta altyazıyı gösteren ok ve etiketi.
- Döngü: 1,2 sn sonra oyunun İngilizce satırı (44 px, kırık beyaz) belirir, 0,9 sn sonra Türkçesi 3 sn üstüne biner,
  sonra İngilizce kalkar, 0,9 sn ara. Yedi satırlık örnek konuşma.

## 6. Bilgi paneli (OK ya da Yeşil)

Sağ üstte 480 px kart, köşe 36 px, koyu zemin. Solda salıncak çizimi: "N" harfinden sarkan iplerde robot. Bağlantı
durumuna göre: bekliyor (kehribar nokta yanıp söner, salıncak hafif sallanır), bağlı (yeşil, daha çok sallanır),
koptu (kırmızı, durur, robot soluk). Sağda "Nino", büyük durum başlığı, "HDMI N · durum". Altyazı geldiyse altında
son gelen altyazı (60 karakter). Açılınca 8 sn sonra kendiliğinden kapanır (HDMI değişimi gibi durumlarda).

## 7. HDMI

- Açılışta kayıtlı port, yoksa TV'nin giriş listesinden konsol aranır (LG: `GAME` türü ya da "PlayStation/PS5"
  etiketi, etkin olan öncelikli; Samsung: tek bağlı HDMI ya da o anki giriş). Bulunamazsa HDMI 1.
- 10 sn içinde görüntü gelmezse ya da giriş açılamazsa ortada kutu: neden, HDMI 1–4 düğmeleri, çıkış ve kapatma
  düğmeleri ve HDR/HDCP açıklaması. Açık olandan sonraki giriş seçili gelir. ◀▶ sırayla, ▲▼ satırlar arası, Tamam seçer;
  LG işaretçisinin üstündeki düğme seçili olur. Kapatılırsa başka giriş seçilene kadar açılmaz.
- Kumanda: 1–4 HDMI, 0 konsolu yeniden ara, panel açıkken ◀▶ HDMI değiştirir, Kırmızı deneme altyazısı, Mavi demo
  (tanıtım notu sağ üstte), Yeşil/OK panel, Geri: ipucu → kutu → demo → panel → uygulamadan çık.

## 8. Bağlantı (şimdiki)

- Gönderici bilgisayarda 8787'de HTTP sunucu; TV **istemcidir**: `GET /hello` (cevapta "nino" geçer) ile yoklar,
  `EventSource(<adres>/events?model=…)` ile olayları alır: `subtitle`, `clear`, `screen`, `screen-clear`, `region`,
  `region-clear`, `style`, `started`, `stopped`, `ping` (15 sn'de bir).
- Adres: açılış parametresi `{server, hdmi}` (LG `PalmSystem.launchParams`, yeniden açılışta `webOSRelaunch`; Samsung
  AppControl `PAYLOAD`), yoksa kayıtlı adres.
- Ağ tarama: TV'nin kendi ağı ve kayıtlı adresin ağı, `.1–.254`, aynı anda 24 istek, 1,2 sn zaman aşımı; bulunamazsa
  30 sn sonra yeniden. Kayıtlı adres art arda 3 kez cevap vermezse 3 sn sonra taranır.
- Bekçi: 5 sn'de bir; bağlantı kapandıysa ya da ping görülmüş ve 31 sn ses yoksa yeniden bağlanır.
- `started`: sol üstte robot + `startedNote` balonu 7 sn; rozet açılır. Rozet her altyazı/ekran olayında açılır,
  `stopped`, kopma ya da 90 sn sessizlikte kapanır. Rozet: sol alt, mini haritanın altı, %5 opak.

## 9. Platforma özgü

- **LG:** Geri tuşu 461. Ekran koruyucu isteği `tvpower`'a her açılışta yeni adla kaydolup `ack:false` ile ertelenir
  (en çok 4 deneme); `appinfo.json`'da `screenSaverProperties.preferredType: 2`. Ağ adresi `connectionmanager`'dan
  (kablolu öncelikli). Çıkış `platformBack`.
- **Samsung:** Geri tuşu 10009. `0–4` ve renkli tuşlar kaydedilir; ekran koruyucu `appcommon` ile kapatılır,
  `tizen.power` ekranı açık tutar. HDMI `tvwindow.setSource` + `show(..., 'BEHIND')`. Uygulama açıldıktan sonraki
  10 sn içinde ya da 5 dk'da 3 kez arka plana düşerse (Anynet+ kaynağa geçti) bir dahaki görünüşte 30 sn ipucu.
- **İkisi de:** günde bir kez anonim kurulum bildirimi (rastgele kimlik, marka, model, sürüm) Nino havuzuna; TV
  modeli göndericiye de bildirilir.
