# Mac uygulaması: tasarım dili

Bu belge yeni Mac uygulamasının ortak görünüşünü anlatır: renkler, yazılar, boşluklar, köşeler ve her ekranda
kullanılan bileşenler. Ana ekranın kendisi `ana-ekran.md`'de. Burada geçen her ölçü nokta (pt) cinsindendir. Renkler
sRGB'dir.

Genel his: Apple uygulaması gibi sade, saydam "cam" yüzeyler, mavi vurgu, lacivert koyu tema. Parlak neon, ağır
degrade ya da kalabalık süs yok. Yalnız birincil düğme, seçili bölme ve simge kutularında hafif mavi-lacivert degrade
ve mavi gölge var.

---

## 1. Renk belirteçleri

Her belirtecin açık ve koyu temada bir değeri var. Uygulama görünümü (Ayarlar'da Açık / Koyu / Sistem) bütün
uygulamaya uygulanır, renkler kendiliğinden ona göre seçilir. Belirteç dosyası yeni yapıyla yeniden yazılacak; değerler
aynı kalır:

| Belirteç | Açık | Koyu | Nerede |
|---|---|---|---|
| background | #EEF3FB | #050A1A | Pencere başlık çubuğunun zemini (macOS 15+), boş önizleme kutusu |
| surface | #FFFFFF | #0E1733 | (yedek yüzey) |
| surface2 | #E6EDF8 | #16224A | Etiket (pill) zemini |
| tileBorder | #DCE5F3 | #22305A | (yedek kenar) |
| border | #D3DEEF | #2A3A68 | Liste ayırıcıları |
| textPrimary | #0A1430 | #F2F5FB | Ana yazı rengi |
| textSecondary | #55607A | #9DA9C6 | İkincil yazı, açıklama, boşta durum noktası |
| accent | #0070D1 | #2D8CFF | Vurgu: birincil düğme, seçili kenar, güncelleme hapı |
| accentHi | #1A86E8 | #5AA6FF | Vurgunun açık tonu (basılı düğme, degrade başı) |
| onAccent | #FFFFFF | #FFFFFF | Vurgu üstündeki yazı |
| accentText | #0058A8 | #7DB8FF | Vurgu renginde yazı, hayalet düğme, imleç üstündeki simge |
| accentSoft | #DDEBFA | #132A55 | Karo simgesinin dairesi, seçili tema kartı zemini |
| pro | #00205B | #9FC2FF | Paket rengi, karo gölgesinin tonu |
| proSoft | #E2E8F5 | #1A2A50 | Paket etiketinin zemini |
| success | #1E6B45 | #5FD39A | "Bağlı", tamam |
| successSoft | #DDF1E6 | #123527 | (yedek) |
| warning | #9A4A08 | #F5AE62 | Uyarı yazıları, "bekliyor" noktası |
| danger | #B3261E | #FF8A80 | Tehlikeli düğmenin yazısı |
| dangerSoft | #FBE4E2 | #3A1E24 | Tehlikeli düğmenin zemini |
| dangerBorder | #EDB6B0 | #6B3A40 | (yedek) |
| onDanger | #FFFFFF | #17181B | (yedek) |

### Belirteç dışındaki sabit renkler

Bunlar belirteç dosyasında yok, ama birçok yerde aynı değerle kullanılıyor; yeni yapıda da ortak bir yerde tanımlanmalı.

| Ad (öneri) | Değer | Nerede |
|---|---|---|
| Cam kenarı | açık: beyaz %75; koyu: beyaz %12 | Cam yüzeylerin 1 pt kenarı, alt şeridin üst çizgisi |
| Cam dolgusu | açık: beyaz %55; koyu: (0.06, 0.10, 0.22) %55 | Cam yüzeyin altına serilen renk |
| Derin lacivert | (0.0, 0.19, 0.52) | Birincil düğme, seçili bölme, simge kutusu, numara dairesinin degrade sonu |
| Bayrak kırmızısı | (0.89, 0.04, 0.09) | Açık çeviri anahtarı, CANLI noktası, canlı ışık |
| Koyu bayrak kırmızısı | (0.66, 0.02, 0.08) | Anahtar izinin alt tonu |
| Altyazı sarısı | #FFE135 (≈ 1.0, 0.88, 0.21) | Sarı altyazı yazısı |
| İndirme yeşili | (0.48, 0.91, 0.48) | TV'deki toplam indirme sayısı |

Salon sahnesinin ışık renkleri, anahtarın gri-mavisi ve TV içi degradeler `ana-ekran.md`'de, kullanıldıkları yerde.

### Görseller

`Assets.xcassets` içinde renk seti yok; renklerin hepsi yukarıdaki değerlerden gelir. Görseller aynen kullanılır (tek
ölçek, 1 piksel = 1 nokta):

| Görsel adı | Piksel | Nerede |
|---|---|---|
| `AppIcon` | 16…1024 | Uygulama simgesi |
| `Logo` | 512×512 | Başlıktaki ve açılıştaki logo |
| `LivingRoom` | 1672×941 | Salon sahnesi, PS5'li |
| `LivingRoomXbox` | 1671×941 | Salon sahnesi, Xbox'lı (1672×941'e gerilerek çizilir) |
| `ConsolePS5` | 500×870 | Kurulum (konsol seçimi) |
| `ConsoleXbox` | 970×270 | Kurulum (konsol seçimi) |
| `TVOptionAndroid` | 360×296 | Kurulum (TV seçimi) |
| `TVOptionLGSamsung` | 351×360 | Kurulum (TV seçimi) |
| `TVOptionMac` | 360×330 | Kurulum (TV seçimi) |

Robot ("Nino'ya Sor") görselleri `design/bot-png/` klasöründen pakete doğrudan kopyalanır: `nino-bot-256.png`
(gözler açık) ve `nino-bot-blink-256.png` (göz kırpma).

---

## 2. Yazı tipleri

Arayüzün yazı tipi sistemin yazı tipi (SF Pro). Yazı boyları sabittir.

| Belirteç | Boy | Kalınlık | Nerede |
|---|---|---|---|
| display | 28 | yarı kalın | Ekran başlığı (ekranda en çok bir tane) |
| title | 22 | yarı kalın | Bölüm başlığı |
| headline | 17 | yarı kalın | Karo başlığı, durum karosunun değeri |
| body | 15 | normal | Uygulamanın varsayılan yazısı |
| callout | 13 | orta | Açıklama, ipucu, alt satır |
| caption | 13 | orta | Küçük etiket, alt şerit |
| button | 15 | yarı kalın | Düğme yazısı |
| code | 22 | yarı kalın, sabit genişlikte rakamlar | Kod / sayı gösterimi |

Belirteç dışında sık geçen boylar:

- Kelime işareti ("Nino"): sistemin yuvarlak (rounded) yazısı, kalın; alt satır "GAME TRANSLATOR" yuvarlak, yarı kalın.
- Sürüm hapı: 10 pt, kalın, yuvarlak.
- Kurulum başlığı: 26 pt kalın yuvarlak; kurulum açıklaması 14 pt normal.
- TV içi yazılar: 11 pt kalın (CANLI), 13 pt yarı kalın tek aralıklı (monospaced) bekleme yazısı, 15 pt orta.
- İndirme sayacı: "Impact" yazı tipi (yoksa sistemin en kalını), en kalın ağırlık.

### Altyazı yazı tipleri

Altyazı için dört seçenek var. Dosyalar `tv-webos/fonts/` klasöründen pakete "fonts" klasörü olarak kopyalanır (OFL
lisans dosyaları da: `OFL-Barlow.txt`, `OFL-Nunito.txt`). Uygulama açılınca yalnız bu uygulama için kaydedilir,
sisteme kurulmaz.

| Seçenek | Ekranda (TR / EN) | Normal | Kalın | Harf aralığı |
|---|---|---|---|---|
| Aksiyon (varsayılan) | Aksiyon (GTA tarzı) / Action (GTA style) | BarlowCondensed-SemiBold | BarlowCondensed-Bold | boyun %1'i |
| Modern | Modern / Modern | Barlow-SemiBold | Barlow-Bold | 0 |
| Yuvarlak | Yuvarlak / Rounded | Nunito (değişken), yarı kalın | Nunito, kalın | 0 |
| Sistem | Sade / System | sistem yazısı | sistem yazısı, kalın | 0 |

Seçicide sıra: Aksiyon, Modern, Yuvarlak, Sistem. "Kalın" sayılan ağırlıklar: kalın ve üstü. Orta kalınlık Barlow'da
yoktur; kalın olmayan her şey yarı kalın çizilir. Altyazı yazısı sabit boydadır (sistemin yazı büyütme ayarıyla
değişmez). Arapça, Tayca, Hintçe gibi bu yazı tiplerinde olmayan harfler sistemin yazı tipiyle kendiliğinden çizilir.

---

## 3. Boşluk ölçeği

| Ad | Değer | Kullanım |
|---|---|---|
| xs / hair | 4 | Yazı ile alt satırı arası |
| s / inline | 8 | Simge ile yazı arası, sıkı yığınlar |
| m / gap | 12 | Karo içi satırlar, karolar arası |
| l / tile | 16 | Karonun iç boşluğu, düğmenin yatay iç boşluğu |
| xl / screen | 24 | Ekran kenar boşluğu |
| xxl | 32 | Büyük ayrım |

## 4. Köşe yarıçapları

Bütün yuvarlak dikdörtgenler "sürekli" (Apple'ın yumuşak, squircle benzeri) köşe biçimiyle çizilir.

| Ad | Değer | Nerede |
|---|---|---|
| card | 22 | Karo, kart, güncelleme şeridi, altyazı penceresinin ayar çerçevesi |
| control | 14 | Düğme, metin alanı |
| inner | 10 | İç kutu, bölge önizlemesi |
| tag | 6 | Etiket (pill) |
| pill | 999 | Tam kapsül |

## 5. Ölçüler

| Ad | Değer |
|---|---|
| Düğme yüksekliği (normal) | 40 |
| Düğme yüksekliği (büyük) | 44 |
| Ana eylem düğmesi | 52 |
| Satır yüksekliği | 40 |
| Tuş simgesi | 24 |
| Durum noktası | 8 |
| Kenar çubuğu genişliği | 240 |
| Ana sütun | 380 |
| Pencere genişliği | 1040 |
| Pencere yüksekliği | 720 |

---

## 6. Cam yüzey

Düğmelerin, karoların ve yuvarlak simge düğmelerinin zemini "cam"dır:

- **macOS 26 ve sonrası:** önce cam dolgusu rengi şeklin içine serilir, üstüne sistemin "Liquid Glass" etkisi aynı
  şekille uygulanır. Tıklanabilir yüzeylerde (ikincil düğme, yuvarlak simge düğmesi, robot) etkinin "etkileşimli"
  türü kullanılır (basınca sistemin kendi tepkisi).
- **Daha eski macOS:** şeklin içine en ince buzlu malzeme (ultra thin material) ve onun altına cam dolgusu.
- Cam yüzeylerin çoğunda üstte 1 pt cam kenarı çizgisi bulunur (aşağıda her bileşende belirtilir).

## 7. Pencere zemini

Bütün pencereler ve sayfalar aynı zemini kullanır; zemin pencerenin kenarlarına kadar (başlık çubuğunun altı dahil)
uzanır:

1. Sol üstten sağ alta doğrusal degrade. Açık: (0.97, 0.98, 1.00) → (0.89, 0.93, 0.99). Koyu: (0.02, 0.04, 0.10) →
   (0.04, 0.09, 0.22).
2. Mavi ışık: 520×520 daire, renk (0.00, 0.44, 0.82), açıkta %22 koyuda %35 opak, 120 bulanık. Merkezi pencere
   ortasından (−200, −170) kayık.
3. Lacivert ışık: 600×600 daire, renk (0.00, 0.13, 0.36), açıkta %16 koyuda %55, 140 bulanık. Merkezi (240, 210) kayık.
4. Hareket: iki ışık 9 sn'de bir yumuşak (ease-in-out) gidip gelir: mavi (−260, −220)'ye, lacivert (300, 260)'a
   kayar, sonra geri döner. "Hareketi azalt" açıksa ışıklar durur.

Zeminin üstünde varsayılan yazı body (15), rengi textPrimary; seçim/işaret rengi accentText.

---

## 8. Ortak bileşenler

### 8.1 Logo

`Logo` görseli kare bir alana yerleştirilir. Görselin kenarında parıltı için saydam pay olduğundan, görsel istenen
boyun 1,21 katı büyüklükte çizilir ve istenen boydaki kareye ortalanır (taşan saydam pay kesilmez, yalnız yerleşim
istenen boydadır). Yüksek kaliteli küçültme. Ekran okuyucuya gösterilmez.

### 8.2 Kelime işareti

Üstte "Nino" (boy S, kalın, yuvarlak), altında "GAME TRANSLATOR" (boy en az 8, en çok S×0,32; yarı kalın, yuvarlak;
harf aralığı S×0,09; textSecondary). İki satır arası S×0,02. Hizası çağırana göre sola ya da ortaya. Ekran okuyucu tek
parça okur: "Nino Game Translator". Bu iki metin çevrilmez.

### 8.3 Düğmeler

Dört tür. Ortak: köşe 14 (sürekli), yazı button (15 yarı kalın), en az yükseklik normalde 40 (büyükte 44, ana eylemde
52), yatay iç boşluk 16 (hayalette 12). Basılıyken %97 ölçek; basma geçişi 0,12 sn ease-out. Tıklama alanı şeklin
kendisi. İsteğe bağlı tam genişlik.

| Tür | Zemin | Yazı | Kenar | Gölge |
|---|---|---|---|---|
| Birincil | Yukarıdan aşağı degrade: accent (basılıyken accentHi) → derin lacivert. Üstünde 1 pt iç kenar: yukarıdan aşağı beyaz %45 → beyaz %5 | onAccent | (degrade kenar) | accent rengi %35 (basılıyken %15), 14 yarıçap, 6 aşağı |
| İkincil | Cam (etkileşimli) | textPrimary | 1 pt cam kenarı | yok |
| Tehlikeli | dangerSoft | danger | yok | yok |
| Hayalet | yok | accentText | yok | yok |

Devre dışı:

- Birincil: zemin cama döner (degrade ve gölge kalkar), yazı textSecondary olur, bütün düğme %75 opak.
- Diğerleri: görünüş aynı kalır, bütün düğme %45 opak.

### 8.4 Metin alanı

Düz metin alanı; yazı body. Yatay iç boşluk 16, en az yükseklik 44. Zemin cam, köşe 14, 1 pt cam kenarı.

### 8.5 Karo ve kart

**Karo** bir zemin biçimidir: içerik 16 iç boşlukla sarılır, zemin cam, köşe 22. Kenar 1 pt cam kenarı; "etkin"
karoda (seçili seçenek, üstüne gelinen seçenek kartı) 1,5 pt accent. Gölge: pro rengi %8, 18 yarıçap, 8 aşağı.

**Kart**: dikey yığın (sola yaslı, aralık 12), tam genişlik, karo zemininde. İsteğe bağlı başlık satırı headline
(17 yarı kalın).

### 8.6 Karo simgesi

24×24 daire, dolgusu accentSoft. Ortasında sistem simgesi 12 pt yarı kalın, rengi accentText (paket için pro).

### 8.7 Etiket (pill)

- Normal: yazı caption (13 orta), rakamlar sabit genişlikte, tek satır. Yatay iç boşluk 8, yükseklik 24, köşe 6.
  Zemin surface2, yazı textSecondary. Paket türünde zemin proSoft, yazı pro.
- Canlı türü: kutu yok. Canlı nokta + 8 boşluk + yazı (caption, textPrimary).

### 8.8 Durum noktası ve durum tonu

8×8 daire. Üç ton var:

- iyi: success
- uyarı: warning
- boşta: textSecondary

Ton kuralları:

- **PS5 / görüntü kaynağı:** görüntü akıyorsa iyi. Akmıyor ve çeviri açıksa uyarı. Çeviri kapalıysa boşta.
- **TV:** en az bir TV bağlıysa iyi. Bağlı TV yok ve çeviri açıksa uyarı. Çeviri kapalıysa boşta.

Ekran okuyucuya gösterilmez.

### 8.9 Canlı nokta

8×8 dolu daire (varsayılan success; TV içinde bayrak kırmızısı). Arkasında aynı renkte 2 pt çizgili, 16×16 bir halka
2 sn'de bir büyür ve kaybolur: ölçek 0,5 → 1,2, opaklık 0,7 → 0. Geçiş ease-out, başa sararak sonsuz döner. "Hareketi
azalt" açıksa halka hiç çizilmez. Yalnız çeviri canlıyken kullanılır.

### 8.10 Durum satırı

Yatay sıra, aralık 12:

- solda durum noktası
- başlık (body yarı kalın)
- boşluk
- değer (body, tek satır; ton iyiyse textPrimary, değilse textSecondary)

### 8.11 Durum karosu

Karo zemininde dikey yığın (aralık 8):

- Üst satır, aralık 8: karo simgesi, başlık (caption, textSecondary), boşluk. Ton boşta değilse en sağda durum noktası.
- Altında değer: headline, gerekirse alt satıra kayar.
- Varsa altında ek düğme.

Karo, sırasındaki en uzun karonun boyunu alır. Ekran okuyucu karoyu tek parça okur.

### 8.12 Degrade simge kutusu

Kare kutu, köşesi kenarın %30'u. Dolgu sol üstten sağ alta accentHi → derin lacivert. 1 pt kenar: yukarıdan aşağı
beyaz %50 → %5. Ortada beyaz simge, kenarın %42'si boyunda, yarı kalın. Gölge: accent %45, yarıçap kenarın %25'i,
kenarın %10'u kadar aşağı.

### 8.13 Numaralı satır

Karo zemininde (iç boşluk 16) yatay sıra, aralık 16:

- 32×32 daire içinde numara: 15 pt kalın yuvarlak, sabit genişlikte rakam, beyaz. Daire dolgusu degrade kutudakiyle
  aynı; gölgesi accent %35, 6 yarıçap, 2 aşağı.
- Yazı: body, satır arası +3.

### 8.14 Küçük metinler

- **İpucu:** callout, textSecondary, satır arası +2, alt satıra kayar.
- **Hata:** "exclamationmark.triangle.fill" simgesi + metin, callout, warning rengi.
- **Tamam:** "checkmark.circle.fill" simgesi + metin, body yarı kalın, success rengi.

### 8.15 Bölmeli seçici

Apple'ın segment denetimine benzer:

- Kapsül biçimli cam zemin, 4 iç boşluk, 1 pt cam kenarı. Bölmeler arası 4.
- Her bölme eşit genişlikte, en az 34 yükseklik. İçinde simge (12 pt yarı kalın) + 6 boşluk + yazı. Yazı callout yarı
  kalın, tek satır, sığmazsa %80'e kadar küçülür.
- Seçili bölme: yazı beyaz. Altında kapsül: yukarıdan aşağı accent → derin lacivert, gölgesi accent %40, 8 yarıçap,
  3 aşağı.
- Seçim değişince kapsül eski bölmeden yenisine kayar: yay, tepki 0,35 sn, sönüm 0,8.
- Seçili olmayan bölmenin yazısı textSecondary.
- Ekran okuyucuya seçili bölme "seçili" diye bildirilir.

### 8.16 Seçenek kartı

Tıklanabilir satır karo (iç boşluk 16):

- Solda görsel (88×60, sığdırılarak) ya da görsel yoksa 44'lük degrade simge kutusu.
- 16 boşluk, sonra başlık (headline, textPrimary) ve altında açıklama (callout, textSecondary). İkisi arası 3.
- Boşluk, en sağda "chevron.right" (13 pt kalın).
- Üstüne gelince:
  - karo "etkin" olur (accent kenar), %101 büyür
  - ok accentText rengine döner ve 3 pt sağa kayar
  - geçiş yay, tepki 0,3 sn, sönüm 0,8
- Devre dışıyken %50 opak.

### 8.17 Yuvarlak simge düğmesi (ana ekran başlığı)

- 36×36 cam daire (etkileşimli), 1 pt cam kenarı.
- Ortada simge 14 pt yarı kalın, rengi textPrimary.
- Üstüne gelince simge accentText olur, düğme %108 büyür. Geçiş yay, tepki 0,3 sn, sönüm 0,7.
- İpucu balonu ve ekran okuyucu etiketi düğmenin adıdır.

### 8.18 Kurulum adımı düzeni (bilgi için)

Kurulum ekranlarının ortak düzeni (ayrı belgede ayrıntılı). Dikey, ortalı, aralık 12:

- Üstte simge: 56'lık degrade kutu ya da logo (84, accent %45 ışıkla). Yay ile belirir: tepki 0,55, sönüm 0,7, ölçek
  0,7→1, opaklık 0→1.
- Başlık 26 kalın yuvarlak.
- Açıklama 14 pt textSecondary, satır arası +2, en çok 540 geniş.
- Altında içerik, üstte 8 boşlukla.

---

## 9. Simgeler

Bütün simgeler sistem simgeleridir (SF Symbols). Ana ekranda ve ortak bileşenlerde geçenler:

| Simge | Nerede |
|---|---|
| `clock.arrow.circlepath` | Geçmiş düğmesi |
| `gearshape.fill` | Ayarlar düğmesi |
| `captions.bubble` | Menü çubuğu öğesi |
| `power` | Cam anahtarın küresi (kapalı) |
| `arrow.down.circle.fill` | Yeni sürüm şeridi ve hapı |
| `arrow.clockwise.circle.fill` | "Güncelleme hazır" hapı |
| `arrow.clockwise` | Güncellemeyi yeniden denetle |
| `checkmark.circle` | "Güncel" |
| `chevron.right` | Alt şerit bağlantısı, seçenek kartı |
| `arrow.down.circle` | Dil paketi uyarısı |
| `exclamationmark.triangle` | Çeviri / okuma uyarıları |
| `exclamationmark.triangle.fill` | Hata metni, yerel ağ uyarısı |
| `checkmark.circle.fill` | Tamam etiketi, seçili tema kartı |
| `gamecontroller`, `gamecontroller.fill` | PS5 / Xbox seçimi, Xbox düğmesi |
| `macwindow` | Oyun penceresi seçeneği |
| `cable.connector` | Capture Card seçeneği |
| `tv`, `desktopcomputer`, `rectangle.on.rectangle` | Altyazının yeri: TV / Bilgisayar / İkisi de |
| `list.bullet.rectangle` | Bağlantı rehberi |

Ayın ve yıldızın çizimi simge değildir, şekil olarak çizilir (bkz. `ana-ekran.md`, cam anahtar).
