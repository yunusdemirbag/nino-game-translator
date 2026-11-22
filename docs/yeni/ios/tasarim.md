Eski uygulamadan çıkarılmış tarif

# Nino iPhone/iPad: tasarım sistemi tarifi

Bu belge eski iOS uygulamasının nasıl göründüğünü anlatır. Kod yoktur; yalnız değerler ve yapı vardır. Yeni kodu
yazan kişi bu tarife bakarak aynı görünümü kendi kodunu yazarak kurar.

Kısaltmalar: **pt** = SwiftUI noktası. **Renk @%x** = o rengin x yüzde opaklığı. "Yarı kalın" = semibold,
"kalın" = bold, "orta" = medium. "Sürekli köşe" = Apple'ın yumuşak (continuous, squircle) köşesi; aksi yazmıyorsa düz
dairesel köşe.

---

## 0. Genel kurallar

- **Yalnız açık tema.** Uygulama bilgi dosyasında arayüz biçimi "Light" olarak sabit. Koyu mod hiç görünmez. Aşağıdaki
  koyu değerler yalnız ortak jeton dosyasında durur, iPhone'da kullanılmaz.
- **Ekranlar sabit değer kullanmaz.** Bütün renk, boşluk, köşe ve yazı boyu tek bir "Mobile" ad alanından gelir
  (Space, Radius, Control, Palette, TypeScale). Yeni kodda da tek bir tasarım ad alanı olmalı.
- **Arayüz yazı tipi: sistem yazı tipi (SF Pro).** Arayüz boyları sabittir: Dinamik Yazı ile büyümez (sistem yazısı
  sabit punto ile çağrılıyor). Altyazının yazı tipi ayrıdır (bölüm 6).
- **iPad algılaması:** cihaz türüne bakılır (iPad mi?). Boyut sınıfına (horizontalSizeClass) bakılmaz. Yani iPad'de
  bölünmüş ekranda dar pencere de "iPad" sayılır. iPad'de farklılaşan her değer aşağıda **iPad:** diye ayrıca yazılı.
- **iPad okunaklı sütun:** iPad'de ekran içeriği en çok **680 pt** genişlikte, yatayda ortalanmış bir sütundur.
  iPhone'da tam genişlik.
- **Hareketi azalt:** sistemde "Hareketi Azalt" açıksa bütün sürekli animasyonlar (nabız, süzülme, göz kırpma, dönen
  halka, sallanma) kapanır. Her bileşende ayrıca belirtildi.
- **Desteklenen yönler:** iPhone dikey + yatay sol + yatay sağ (baş aşağı yok). iPad dört yön.
- Uygulama adı (ana ekranda): "Nino Game Translator". Desteklenen arayüz dilleri: en, tr, ar, hi, id, th, vi, ur, bn,
  ms, fil, nl.

---

## 1. Jetonlar (değerler)

### 1.1 Boşluk (Space)

| Ad | Değer | Kullanım |
|---|---|---|
| screen | 20 | ekran kenar boşluğu, alt boşluk |
| gap | 12 | karolar ve bölümler arası |
| tile | 16 | karonun iç boşluğu, giriş alanı yatay iç boşluğu |
| inline | 8 | simge ile yazı arası, satır içi |
| hair | 4 | başlık satırları arası, segment iç boşluğu |

### 1.2 Köşe yarıçapı (Radius)

| Ad | Değer |
|---|---|
| tile | 22 (sürekli) |
| control | 16 (simge düğmesi, giriş alanı, segment kutusu) |
| inner | 8 (segment içindeki seçili parça, oyun rozeti) |
| tag | 6 (etiket) |
| pill | 999 (tam hap) |

### 1.3 Kontrol yükseklikleri (Control)

| Ad | Değer |
|---|---|
| button | 52 (tanımlı ama birincil/ikincil düğme gerçekte en az **58**) |
| buttonSmall | 44 (hayalet düğme en az yüksekliği) |
| icon | 44 (simge düğmesi 44×44) |
| field | 52 (giriş alanı en az yüksekliği) |
| row | 52 (liste satırı en az yüksekliği) |
| tag | 24 (etiket yüksekliği) |

### 1.4 Renk paleti (Palette, açık tema)

| Ad | Değer | Ne için |
|---|---|---|
| deep | #E3ECFA | koyu buz mavisi zemin tonu |
| bg | #EEF3FB | zemin |
| surface | beyaz @%85 | cam karo zemini |
| surface2 | #E6EDF8 | etiket, segment kutusu, oyun rozeti zemini |
| border | beyaz @%75 | camın ince kenarı |
| borderStrong | #D3DEEF | ikincil düğme kenarı, giriş alanı kenarı, ayraç |
| text | #0A1430 | ana yazı (koyu lacivert) |
| secondary | #55607A | ikincil yazı |
| tertiary | #8A93A8 | liste oku |
| accent | #0070D1 | vurgu mavisi |
| accentHi | #1A86E8 | açık vurgu mavisi |
| navy | #003085 | lacivert |
| onAccent | beyaz | koyu zemin üstü yazı |
| pro | #00205B | koyu lacivert (gölge rengi, paket etiketi) |
| proSoft | #E2E8F5 | paket etiketi zemini |
| success | #1E6B45 | yeşil durum |
| warning | #9A4A08 | turuncu-kahve uyarı |
| danger | #B3261E | kırmızı |
| dangerSoft | #FBE4E2 | tehlikeli düğme zemini |
| subtitleWhite | beyaz | altyazı yazısı |
| subtitleYellow | #FFD54A | sarı altyazı seçeneği |
| gradient | accentHi → navy, yukarıdan aşağı | simge kutuları için tanımlı degrade |

Hayalet düğme yazı rengi ayrıca sabit: **#0058A8**.

"Kimlik" renkleri (NinoInk):

| Ad | Değer |
|---|---|
| ink | #0A1430 |
| soft | #55607A |
| stageTop | #151E36 |
| stageBottom | #06080F |
| freeGreen | #6EE7A8 |

### 1.5 Ortak jeton dosyası (design/tokens.json, Mac ile ortak)

iPhone paketi bu dosyayı da taşır; Mac'ten gelen ortak parçalar (logo, robot, bölge önizlemesi, arka zemin, robot
mesajı) renklerini buradan alır. Ad: "Nino", sürüm 4. Renkler açık/koyu çift olarak verilir:

| Ad | Açık | Koyu |
|---|---|---|
| background | #EEF3FB | #050A1A |
| surface | #FFFFFF | #0E1733 |
| surface2 | #E6EDF8 | #16224A |
| tileBorder | #DCE5F3 | #22305A |
| border | #D3DEEF | #2A3A68 |
| textPrimary | #0A1430 | #F2F5FB |
| textSecondary | #55607A | #9DA9C6 |
| accent | #0070D1 | #2D8CFF |
| accentHi | #1A86E8 | #5AA6FF |
| onAccent | #FFFFFF | #FFFFFF |
| accentText | #0058A8 | #7DB8FF |
| accentSoft | #DDEBFA | #132A55 |
| pro | #00205B | #9FC2FF |
| proSoft | #E2E8F5 | #1A2A50 |
| success | #1E6B45 | #5FD39A |
| successSoft | #DDF1E6 | #123527 |
| warning | #9A4A08 | #F5AE62 |
| danger | #B3261E | #FF8A80 |
| dangerSoft | #FBE4E2 | #3A1E24 |
| dangerBorder | #EDB6B0 | #6B3A40 |
| onDanger | #FFFFFF | #17181B |

Yazı jetonları (hepsi sistem yazı tipi): display 28 yarı kalın, title 22 yarı kalın, headline 17 yarı kalın, body 15
normal, callout 13 orta, caption 13 orta, button 15 yarı kalın, code 22 yarı kalın (rakamlar eş genişlikte).

Boşluk jetonları: xs 4, s 8, m 12, l 16, xl 24, xxl 32, hair 4, inline 8, gap 12, tile 16, screen **24** (dikkat:
mobildeki screen 20; ortak dosyadaki 24 yalnız Mac'ten gelen parçalarda geçer).

Köşe jetonları: card 22, control 14, inner 10, tag 6, pill 999.

Boy jetonları: buttonHeight 40, buttonLarge 44, primaryActionHeight 52, rowHeight 40, keycap 24, statusDot 8,
sidebarWidth 240, mainColumn 380, windowWidth 1040, windowHeight 720 (son dördü Mac penceresi için).

Ayrıca iki cam rengi (iOS'ta ortak parçalarda): **cam kenarı** açıkta beyaz @%75 (koyuda beyaz @%12); **cam dolgusu**
açıkta beyaz @%55 (koyuda yaklaşık #0F1A38 @%55).

### 1.6 Yazı ölçeği (TypeScale, mobil)

Arayüzde yalnız bu beş boy kullanılır (altyazı içeriği hariç):

| Ad | Boy | Kalınlık | Not |
|---|---|---|---|
| display | 28 | yarı kalın | |
| title | 22 | yarı kalın | rakamlar eş genişlikte (tabular) |
| headline | 17 | yarı kalın | |
| body | 15 | normal | |
| caption | 13 | orta | |

Bunların dışında "kimlik" başlıkları: 32 kalın (harf aralığı −0.5), 16 normal açıklama, 13 yarı kalın adım satırı
(bölüm 4.1).

**Altyazı içeriği boyu** (taban × kullanıcı ölçeği; ölçek %80 ile %160 arasına sıkıştırılır, yarı kalın):

| Durum | iPhone | iPad |
|---|---|---|
| Dikey (canlı satır) | 28 | 36 |
| Yatay (altyazı ekranı) | 36 | 60 |

Yazı tipi kullanıcının seçtiği altyazı yazı tipidir (bölüm 6), varsayılan Aksiyon (`pack.style.action`).

---

## 2. Görseller ve dosyalar

### 2.1 Görsel kataloğu (Assets)

| Ad | Dosya | Boyut | Ne |
|---|---|---|---|
| AppIcon | icon-1024.png | 1024×1024, saydamsız | uygulama simgesi (tek evrensel boy) |
| Logo | logo.png | 512×512, saydam | uygulama içi logo |
| LivingRoom | living-room.png | 1672×941, saydam | salon sahnesi (PS5 düzeni) |
| LivingRoomXbox | living-room-xbox.png | 1671×941, saydam | salon sahnesi (Xbox düzeni) |

Not (proje notlarından): logoda "TRANSLATER" yazım hatası ve Sony'nin PlayStation logosu ile DualSense kolu var; yeni
uygulamada genel bir oyun kolu çizimi ve "TRANSLATOR" kullanılmalı.

### 2.2 Katalog dışı paket dosyaları

- Robot: `nino-bot-256.png` (gözler açık) ve `nino-bot-blink-256.png` (gözler kapalı), 256×256 saydam. Kaynak
  `design/bot-png/` (128 ve 512 sürümleri de var). Paket kökünde düz dosya olarak durur, katalogda değil.
- Altyazı yazı tipleri: paketin içinde **"fonts" adlı klasör** (kaynak `tv-webos/fonts`):

| Dosya | PostScript adı |
|---|---|
| Barlow-SemiBold.ttf | Barlow-SemiBold |
| Barlow-Bold.ttf | Barlow-Bold |
| BarlowCondensed-SemiBold.ttf | BarlowCondensed-SemiBold |
| BarlowCondensed-Bold.ttf | BarlowCondensed-Bold |
| Nunito-Variable.ttf | Nunito-SemiBold / Nunito-Bold (değişken dosyanın örnekleri) |

  Lisansları aynı klasörde: OFL-Barlow.txt, OFL-Nunito.txt (SIL Open Font License; pakete lisansla birlikte konmalı).
  Yazı tipleri açılışta yalnız bu uygulama için (süreç kapsamında) bir kez kaydedilir, sisteme kurulmaz.
- `tokens.json` paketin kökünde.

---

## 3. Ekran iskeleti

### 3.1 Uygulama zemini (en dış katman)

Bütün uygulamanın kökünde: temel yazı body (15), yazı rengi textPrimary, sistem vurgu rengi (tint) accentText
(#0058A8), arkada kenardan kenara (güvenli alanı yok sayarak) **Nino arka zemini** (3.2). Ekranların çoğu bunun
üstüne kendi mobil zeminini (3.3) çizer, yani kullanıcı çoğunlukla 3.3'ü görür.

### 3.2 Nino arka zemini (NinoBackdrop, Mac ile ortak)

Ne işe yarar: canlı, hafifçe süzülen zemin. Açılış animasyonunda da kullanılır.

Katmanlar (alttan üste):
1. Doğrusal degrade, sol üstten sağ alta: **#F7FAFF → #E3EDFC** (koyu modda #050A1A → #0A1738; iOS'ta görünmez).
2. Daire, 520×520, renk #0070D1 @%22 (koyuda @%35), 120 bulanıklık. Ortadan kaydırma: x −200, y −170.
3. Daire, 600×600, renk #00215C @%16 (koyuda @%55), 140 bulanıklık. Kaydırma: x +240, y +210.

Animasyon: göründüğünde 9 sn süren, yumuşak girişli-çıkışlı, ileri-geri sonsuz tekrar. Birinci daire (−200,−170) ↔
(−260,−220), ikinci daire (240,210) ↔ (300,260) arasında gider gelir. Hareketi azalt açıksa durur. Erişilebilirlikte
gizli.

### 3.3 Mobil ekran zemini (MobileBackground)

Kenardan kenara (güvenli alanı yok sayar). Katmanlar:
1. Doğrusal degrade, sol üstten sağ alta: **#F7FAFF → #E3ECFA**.
2. Radyal degrade: merkez ekranın (x %10, y %8) noktası; accent (#0070D1) @%22'den saydama; yarıçap 0'dan
   **ekran genişliği × 0.9**'a.
3. Radyal degrade: merkez (x %95, y %95); pro (#00205B) @%16'dan saydama; yarıçap 0'dan
   **en büyüğü(genişlik, yükseklik × 0.5)**'e.

Hareketsizdir.

### 3.4 Ekran yapısı (MobileScreen)

Üç bölmeli dikey yığın, bölmeler arası boşluk 0:

1. **Üst satır (header):** yatay 20 iç boşluk; üstte güvenli alanın altından **8** (iPad: **20**). iPad'de 680'lik
   ortalanmış sütun.
2. **İçerik:** dikey kaydırılır, kaydırma çubuğu gizli. İçinde sola yaslı dikey yığın, öğeler arası 12. İç boşluk:
   yatay 20, üst 12, alt 20. iPad'de 680'lik sütun.
3. **Alt düğme bölgesi:** dikey yığın, aralık 12; yatay 20; altta güvenli alanın üstünden **20** (iPad: **40**).
   iPad'de 680'lik sütun. Kaymaz, hep altta durur.

Bütün ekranın yazı rengi text (#0A1430), zemini 3.3. Sistem gezinme çubuğu gizli (her ekran kendi üst satırını çizer).

### 3.5 Okunaklı genişlik (readableWidth)

iPad'de: içerik en çok 680 genişlikte, sonra tam genişlikte bir çerçeveye ortalanır. iPhone'da hiçbir şey yapmaz.

### 3.6 Bento ızgara (BentoGrid)

İki sütunlu karo ızgarası. Sütunlar arası ve satırlar arası **12**. Sütun genişliği = (toplam genişlik − 12) / 2.
Karolar sırayla ikişer ikişer satıra dizilir. Bir karo "geniş" işaretliyse kendi başına tam satır kaplar (yarım kalan
satır önce kapatılır). Tek kalan son karo yarım genişlikte, solda kalır. **Bir satırdaki karoların yüksekliği eşittir**
(satırdaki en uzun karonun yüksekliği; kısa olan uzatılır). Genişlik bilinmiyorsa 350 varsayılır. iPad'de ayrıca
değişen bir şey yok (yalnız dıştaki 680 sütun).

---

## 4. Başlıklar

### 4.1 Kimlik başlığı (NinoTitle) ve ekran başlığı (ScreenTitle)

İkisi de aynı görünür; tek fark üst-alt aralık. Sola yaslı, tam genişlik dikey yığın.

| Katman | Yazı | Renk |
|---|---|---|
| Adım satırı (isteğe bağlı, ör. `setup.step`) | 13 yarı kalın | accent #0070D1 |
| Başlık | 32 kalın, harf aralığı −0.5 | #0A1430 |
| Açıklama (isteğe bağlı) | 16 normal | #55607A |

Satırlar arası: NinoTitle'da **6**; ScreenTitle'da **4** ve açıklamanın üstüne ek **2**. Başlık ve açıklama dikeyde
kısaltılmaz, satır kırarak tam görünür.

### 4.2 Geri başlığı (BackHeader)

Alt sayfaların üst satırı. Yükseklik 44. Yatay yığın, aralık 12: solda geri simge düğmesi (4.3, simge
`chevron.left`, erişilebilirlik adı `common.back`; basınca sayfayı kapatır/geri gider), yanında başlık **title (22 yarı kalın)**,
sonra boşluk, sağda isteğe bağlı öğe.

### 4.3 Simge düğmesi (IconButton)

Girdiler: SF Symbol adı, erişilebilirlik etiketi, renk (varsayılan text), eylem.

Katmanlar: 44×44 kutu; zemin surface (beyaz @%85), köşe 16 sürekli; kenar border (beyaz @%75, 1 pt, içeriden);
gölge pro @%8, yarıçap 8, y +3. Ortada simge 17 yarı kalın.

Durumlar: sistemin "düz" (plain) düğme stili kullanılır; basılıyken yalnız sistemin kendi hafif solması görünür,
ölçek ya da renk değişimi yok. Erişilebilirlikte yalnız etiket okunur.

### 4.4 Profil düğmesi (AvatarButton)

Simge düğmesiyle birebir aynı kutu. İçerik: baş harf boşsa `person` simgesi (17 yarı kalın); değilse baş harfler,
13 yarı kalın, text rengi. Erişilebilirlik adı `settings.profile`.

---

## 5. Düğmeler

### 5.1 Mobil düğme stili (MobileButtonStyle)

Dört tür: birincil, ikincil, hayalet, tehlikeli. Hepsi **tam hap (kapsül)**. Etiket yazı + simge birlikte (ikisi de
varsa ikisi görünür), yazı headline 17 yarı kalın.

| | Birincil | İkincil | Hayalet | Tehlikeli |
|---|---|---|---|---|
| Genişlik | tam genişlik | tam genişlik | içerik kadar | tam genişlik |
| En az yükseklik | 58 | 58 | 44 | 58 |
| Yatay iç boşluk | 20 | 20 | 12 | 20 |
| Yazı rengi | beyaz | text #0A1430 | #0058A8 | danger #B3261E |
| Zemin | degrade #1B2747 → #0A1430 (yukarıdan aşağı) | beyaz @%90 | yok | dangerSoft #FBE4E2 |
| Kenar | beyaz @%14, 1 pt | borderStrong #D3DEEF, 1 pt | yok | yok |
| Gölge | #0A1430 @%28, yarıçap 14, y +8 | yok | yok | yok |

Dikkat: birincil düğme **mavi değil, koyu lacivert-siyah** degradedir (kimlik yenilendi).

Durumlar:
- **Basılı:** tüm düğme %97 ölçek; birincilde zemin (gölgesiyle birlikte) %85 opaklık. Geçiş 0.12 sn, yumuşak çıkış
  (easeOut).
- **Devre dışı:** tüm düğme %40 opaklık.
- Dokunma alanı kapsül biçiminde.

### 5.2 PS5'siz deneme bağlantısı (TryWithoutPS5Button)

Hayalet düğme; simge `sparkles` + yazı (`demo.try`). Yazı tek satır, sığmazsa %75'e kadar küçülür. Yerleşimde önceliği yüksek
(yanındakiler önce daralır). Test kimliği "tryWithoutPS5". Basınca PS5 olmadan demo ana ekranı açılır.

---

## 6. Altyazı yazı tipi ve seçicileri

### 6.1 Altyazı yazı tipleri

| Seçenek | Seçicideki ad (metin anahtarı) | Normal/yarı kalın | Kalın | Harf aralığı |
|---|---|---|---|---|
| Aksiyon (varsayılan) | `pack.style.action` | BarlowCondensed-SemiBold | BarlowCondensed-Bold | boyun %1'i |
| Modern | `subtitle.font.modern` | Barlow-SemiBold | Barlow-Bold | 0 |
| Yuvarlak | `subtitle.font.rounded` | Nunito-SemiBold | Nunito-Bold | 0 |
| Sistem | `subtitle.font.system` | sistem yazı tipi | sistem | 0 |

Kurallar: kalın, çok kalın ve siyah ağırlıklar "kalın" dosyayı; diğer her şey (orta dahil) yarı kalın dosyayı
kullanır (Barlow'da orta yok). Özel yazı tipleri **sabit boyla** çağrılır, Dinamik Yazı ile büyümez. Bu yazı
tiplerinde olmayan harfler (Arapça, Tayca, Hintçe...) sistemce otomatik başka yazı tipiyle çizilir. Seçici sırası:
Aksiyon, Modern, Yuvarlak, Sistem.

### 6.2 Segmentli seçim (SegmentedTabs)

Ne işe yarar: 2–4 seçenekten biri (ör. çeviri motoru).

Dış kutu: yatay yığın, parçalar arası 4; iç boşluk 4; zemin surface2 #E6EDF8, köşe 16 (düz dairesel).

Her parça: eşit genişlik, en az yükseklik 36; yazı body 15, seçiliyse yarı kalın, değilse orta; renk seçiliyse text,
değilse secondary; tek satır, %70'e kadar küçülür. Seçili parçanın arkasında: beyaz, köşe 8 dikdörtgen, gölge pro @%10,
yarıçap 4, y +2. Seçili olmayanın zemini yok. Tüm parça dokunulabilir.

Durum geçişi: animasyon yok (seçim anında değişir). Seçim değişince hafif **seçim dokunsal geri bildirimi**
(iOS 17+ sistem "selection" geri bildirimi; iOS 16'da seçim üreteci, yalnız yeni seçilen parçada bir kez).

### 6.3 Altyazı yazı tipi ızgarası (SubtitleFontGrid)

2×2 ızgara; sütunlar ve satırlar arası 4; dış iç boşluk 4; zemin surface2, köşe 16. Her hücre: en az yükseklik 40,
yatay iç boşluk 8, tam genişlik. Seçeneğin adı **kendi yazı tipiyle**, 16 yarı kalın; seçili text, değilse secondary;
tek satır, %70'e kadar küçülür. Seçili hücrenin arkası 6.2'deki gibi (beyaz, köşe 8, aynı gölge). Seçim dokunsal geri
bildirimi aynı. Erişilebilirlikte seçili hücre "seçili" niteliği taşır.

### 6.4 Çeviri dili seçici (LanguageFlags)

Ne işe yarar: hedef dili seçmek. Bir açılır menü düğmesi.

Düğme görünümü (kapsül): yatay yığın, aralık 6: seçili dilin bayrak emojisi (20 pt); isteğe bağlı (Ayarlar'da) dilin
kendi adı, 17 yarı kalın; `chevron.down` simgesi 12 yarı kalın, @%70. Yatay iç boşluk 14, en az yükseklik 40. Zemin
accent @%10 kapsül; kenar accent @%80, **1.5 pt**. Erişilebilirlik adı: dilin kendi adı.

Menü: sistem açılır menüsü, içinde tek seçimli liste. Her satır "bayrak + iki boşluk + dilin kendi adı". Sıra
(Türkçe en üstte): Türkçe 🇹🇷, العربية 🇸🇦, हिन्दी 🇮🇳, Bahasa Indonesia 🇮🇩, ไทย 🇹🇭, Tiếng Việt 🇻🇳, اردو 🇵🇰,
বাংলা 🇧🇩, Bahasa Melayu 🇲🇾, Filipino 🇵🇭, Nederlands 🇳🇱. Bilinmeyen dilde bayrak 🌐. Seçim 0.2 sn yumuşak çıkış
animasyonuyla değişir.

---

## 7. Karolar

### 7.1 Karo (Tile)

Girdiler: vurgu (yok / seçili), içerik aralığı (varsayılan 8), içerik.

Katmanlar: sola yaslı dikey yığın (aralık girdiye göre), tam genişlik; iç boşluk 16; zemin surface (beyaz @%85),
köşe 22 sürekli; kenar: normalde border (beyaz @%75) 1 pt, **seçiliyken accent #0070D1, 1.5 pt**; gölge pro @%10,
yarıçap 14, y +6. Seçim geçişinde animasyon yok.

### 7.2 Değer karosu (StatTile)

Girdiler: simge, simge tonu, etiket, değer metni, canlı mı.

Karonun içinde:
1. Üst satır (yatay, aralık 8): karo simgesi (7.4), etiket caption 13 orta secondary, boşluk, canlıysa sağda
   **atmayan** yeşil nokta (8.2, nabızsız).
2. Değer: title (22 yarı kalın, rakamlar eş genişlik), tek satır, sığmazsa %60'a kadar küçülür.

Kare olmaya zorlanmaz.

### 7.3 Bilgi karosu (InfoTile)

Girdiler: simge, başlık, açıklama, vurgu.

Karonun içinde: üst satır (aralık 8) karo simgesi + başlık headline 17 yarı kalın (satır kırar); altında açıklama
caption 13 secondary (satır kırar); en altta esnek boşluk (bento satırında eşit boy için aşağı doğru uzar). Seçili
vurguda mavi kenar (7.1).

### 7.4 Karo simgesi (MobileTileIcon)

Kutusuz SF Symbol, 15 yarı kalın, 18×18 çerçevede. Erişilebilirlikte gizli. Ton → renk: nötr → secondary #55607A;
tamam ve vurgu → accent #0070D1; paket (pro) → #00205B; hata → danger #B3261E.

### 7.5 Oyun rozeti (GameMonogram)

Oyunun kısaltması ("GTA"). Varsayılan 44×44 kare; zemin surface2, köşe 8 (düz); yazı 13 yarı kalın, text, ortada.

### 7.6 Liste satırı (ListRow)

Geniş karonun içinde. Yatay yığın, aralık 12: karo simgesi; başlık headline 17 yarı kalın text; en az 8'lik esnek
boşluk; isteğe bağlı ayrıntı yazısı caption 13 secondary; sağ öğe. En az yükseklik 52, tüm satır dokunulabilir.
Gidilecek ekranı olan satırın sağ öğesi: `chevron.right`, 13 yarı kalın, tertiary #8A93A8.

### 7.7 Satır ayracı (RowDivider)

1 pt yüksekliğinde tam genişlik çizgi, borderStrong #D3DEEF @%70.

### 7.8 Giriş alanı (MobileFieldStyle)

Yazı 17 normal (headline boyu, normal kalınlık), text rengi. Yatay iç boşluk 16, en az yükseklik 52. Zemin beyaz
@%90, köşe 16 sürekli; kenar borderStrong 1 pt. Odaklanınca ayrıca bir görünüm değişikliği yok.

---

## 8. Etiketler ve durum

### 8.1 Etiket / durum (MobilePill)

Girdiler: metin, tür (nötr, tamam, vurgu, pro), nokta, canlı, sıkışık (kullanılmıyor), koyu zemin.

İki biçimi var:
- **Durum biçimi** (nokta ya da canlı açıksa): zeminsiz yatay yığın, aralık 8: durum noktası (8.2; canlıysa atar,
  değilse atmaz) + metin caption 13 orta, rakamlar eş genişlikte, tek satır. Renk text; **koyu zemin** açıksa
  (tam ekran altyazı üstünde) beyaz @%75.
- **Etiket biçimi:** metin caption 13 orta, eş genişlikte rakam, tek satır; yatay iç boşluk 8, yükseklik 24; zemin
  surface2 (pro türünde proSoft #E2E8F5), köşe 6 (düz). Yazı rengi secondary (pro türünde #00205B). "Tamam" ve "vurgu"
  türleri etiket biçiminde nötrle aynı görünür.

### 8.2 Durum noktası (MobileLiveDot)

8×8 daire, varsayılan renk success #1E6B45. **Nabız** açıksa ve hareketi azalt kapalıysa: üstünde 16×16, 2 pt
kalınlıkta aynı renkte halka; ölçeği 0.5'ten 1.2'ye büyürken opaklığı 0.7'den 0'a iner; 2 sn, yumuşak çıkış,
geri dönmeden sonsuz tekrar. Nabız yalnız canlı çeviri sürerken kullanılır. Erişilebilirlikte gizli.

### 8.3 Sayfa noktaları (PageDots)

Karşılama ve tur için. Yatay yığın, aralık 8. Her nokta 8 yükseklikte kapsül: geçerli sayfa **22 genişlik, #0A1430**;
diğerleri 8 genişlik, #0A1430 @%18. Sayfa değişince 0.2 sn yumuşak çıkış animasyonu (genişlik ve renk kayar).
Erişilebilirlikte gizli.

### 8.4 Not satırı (MobileNote)

Hata ya da uyarı. Simge `exclamationmark.triangle.fill` + metin; caption 13 orta; varsayılan renk warning #9A4A08
(simge de aynı renk); satır kırar.

### 8.5 Ücretsiz etiketi (FreeTag, `home.packs.free`)

Koyu sahne üstünde. Metin 12 kalın, #6EE7A8. Yatay iç boşluk 10, dikey 5. Zemin #6EE7A8 @%14 kapsül, kenar #6EE7A8
@%35, 1 pt.

---

## 9. Koyu sahne parçaları

### 9.1 Sahne kartı (NinoStage)

Girdiler: isteğe bağlı sabit yükseklik, içerik (üst üste yığılı, ortalı).

Katmanlar: tam genişlik; köşe **28** sürekli; zemin degrade #151E36 → #06080F (yukarıdan aşağı); kenar degrade beyaz
@%22 → beyaz @%3 (yukarıdan aşağı), 1 pt; içerik köşeden kırpılır; gölge #0A1430 @%35, yarıçap 18, y +10.

### 9.2 Camsı satır (GlassRow)

Sahnenin içinde. Yatay yığın, aralık 12:
1. Simge: SF Symbol 18 yarı kalın beyaz, 40×40 daire içinde, daire zemini beyaz @%10.
2. Dikey yığın (sola yaslı, aralık 2): başlık 16 yarı kalın beyaz, tek satır, %70'e kadar küçülür; isteğe bağlı
   açıklama 13 normal beyaz @%60, en çok 2 satır.
3. En az 4'lük esnek boşluk, sonra isteğe bağlı sağ öğe.

İç boşluk yatay 14, dikey 12. Zemin beyaz @%7, köşe 18 sürekli; kenar beyaz @%12, 1 pt.

---

## 10. Logo ve açılış

### 10.1 Logo (LogoView)

Girdi: boy (varsayılan 40; uygulamada 36 ana ekran/karşılama üst satırında, 56 profilde, 200 açılışta).

Görünüm: "Logo" görseli, yüksek kaliteli ölçekleme, en-boy korunarak sığdırılır, **boy × 1.21** karelik çerçevede çizilir
ve sonra boy × boy çerçeveye konur (kırpılmaz; görselin kenarında parıltı için saydam pay var, opak kısım görüntünün
~%83'ü olduğundan logo tam istenen boya oturur, saydam pay dışarı taşar). Erişilebilirlikte gizli.

### 10.2 Açılış animasyonu (SplashView)

iOS'ta salon sahnesinde, TV ekranının içinde (1040×586'lık sanal pencere, TV ekranına sığacak kadar küçültülmüş)
oynatılır. Bitince sahne 0.4 sn yumuşak çıkışla sonraki duruma geçer.

Katmanlar (merkezde):
- Zemin: Nino arka zemini (3.2).
- Dikey yığın, aralık 28:
  1. Üst üste:
     - **Dönen ışık halkası:** 290×290 daire kenarı, 3 pt; açısal degrade (saydam → accent → accentHi → saydam →
       saydam); 1.5 bulanıklık.
     - **Parıltı:** 220×220 daire, accent @%25, 60 bulanıklık.
     - **Logo** boy 200; üstünde bayrak vurgusu (10.3).
  2. Yazı bloğu (aralık 6): marka yazısı (10.4) boy 34; altında kısa marka sloganı (`home.tagline`), body 15, secondary.

Zaman çizelgesi (hareketi azalt kapalı):
- 0 ms: logo girer: yay animasyonu (tepki 0.9 sn, sönüm 0.72). Logo ölçek 0.72 → 1, bulanıklık 14 → 0, opaklık
  0 → 1. Parıltı ölçek 0.4 → 1. Halka opaklık 0 → 1.
- 0 ms: halka sürekli döner: 2.4 sn'de 360°, doğrusal, sonsuz.
- 650 ms: yazı bloğu belirir: 0.6 sn yumuşak çıkış; opaklık 0 → 1, y +12 → 0.
- 650 ms: bayrak kırmızı parıltısı 0.55 sn yumuşak giriş-çıkışla 3 kez ileri-geri atar; beyaz parlama 0.15 sn
  gecikmeyle 0.9 sn'de soldan sağa geçer.
- 2350 ms: çıkış: 0.45 sn yumuşak giriş; tüm yığın ölçek 1 → 1.06, opaklık 1 → 0.
- 2800 ms: bitti bildirimi.

Hareketi azalt açıksa: logo ve yazı hemen görünür, hiçbir hareket yok, 900 ms sonra bitti.

### 10.3 Bayrak vurgusu (logodaki Türk bayrağı üstünde, yalnız boy 200 için)

Logo görselinde bayrak yaklaşık x 470–780, y 235–345 (1254'lük kaynakta). Ölçek = 200 × 1.21 / 1254 ≈ 0.193.
Bayrak kutusu ≈ 59.8 × 21.2 pt, merkezden yukarı ≈ 65 pt kaydırılmış.
- **Kırmızı parıltı:** ≈ 68.8 × 27.6 pt (kutunun 1.15 × 1.3 katı), köşe 8 sürekli, renk ≈ #F21F29, 18 bulanıklık,
  "ekran" karışım kipi; opaklık 0 ↔ 0.85.
- **Beyaz parlama:** kutunun %35'i genişliğinde, kutu yüksekliğinde, köşe 6; yatay degrade saydam → beyaz @%75 →
  saydam; "artı açıklık" (plus lighter) karışımı; x −0.75×genişlik'ten +0.75×genişlik'e kayarken opaklık 1 → 0;
  bayrak kutusuna (köşe 6) kırpılır.
- Dokunmaya kapalı.

Not: yeni logoda bayrak yeri farklı olacaksa bu koordinatlar yeniden ölçülmeli.

### 10.4 Marka yazısı (NinoWordmark)

Girdi: boy (varsayılan 24), hizalama (varsayılan orta). Dikey yığın, aralık boy × 0.02:
1. "Nino": boy, kalın, **yuvarlak sistem yazı tipi** (SF Pro Rounded).
2. "GAME TRANSLATOR": en küçük 8 olmak üzere boy × 0.32, yarı kalın, yuvarlak; harf aralığı boy × 0.09; renk
   textSecondary.

Erişilebilirlikte tek öğe: "Nino Game Translator".

---

## 11. "Nino'ya Sor" robotu

### 11.1 Robot yüzü (NinoBotFace)

Girdiler: boy, canlı mı (göz kırpma, varsayılan açık), süzülme, düşünme.

Görünüm: robot görseli (gözler açık karesi), en-boy korunarak boy × boy çerçeveye sığar. Görsel yoksa yedek: SF
Symbol `face.smiling`, sistem vurgu rengi. Erişilebilirlikte gizli.

Animasyonlar (hepsi hareketi azalt açıkken kapalı):
- **Göz kırpma:** 4–5 sn arasında rastgele bekler, kapalı göz karesini **150 ms** gösterir, açığa döner; sürekli.
  Animasyonsuz kare değişimi.
- **Süzülme:** y ekseninde −boy×0.05 ile +boy×0.05 arası; 1.6 sn yumuşak giriş-çıkış, ileri-geri sonsuz.
- **Düşünme:** −6° ile +6° arası dönme; 0.5 sn yumuşak giriş-çıkış, ileri-geri sonsuz. Düşünme bitince 0.2 sn
  yumuşak çıkışla düz duruma döner.

### 11.2 Yazıyor noktaları (NinoTypingDots)

Girdiler: renk, nokta çapı (varsayılan 7). Yatay yığın, aralık çap × 0.6; yükseklik çap × 1.6. Üç daire. Saniyede
30 kare güncellenir. Her nokta için evre = (sin(2π·t/1.2 − i·0.9) + 1) / 2 (t saniye, i = 0,1,2; yani 1.2 sn'lik
dalga, her nokta 0.9 radyan geride). Opaklık = 0.35 + 0.65·evre; ölçek = 0.75 + 0.35·evre. Hareketi azalt açıksa
duraklar, evre sabit 0.5.

### 11.3 Robot mesajı (NinoMessageText)

Robotun cevabı bloklara ayrılır (ayırma kuralı çekirdek kitaplıkta): paragraf, numaralı adım, madde. Bloklar dikey
dizilir; ilk bloğun üstünde boşluk yok; iki liste öğesi arasında 8, diğer her geçişte 10. Metin seçilebilir;
bağlantılar tıklanabilir (zengin metin).

- **Paragraf:** satır kıran metin (yazı tipi ve rengi dış ortamdan).
- **Numaralı adım:** yatay yığın, ilk satır taban çizgisine hizalı, aralık 8. Rozet: numara 12 kalın yuvarlak, eş
  genişlik rakam, beyaz; en az 21×21; tek haneli ise yatay iç boşluk 0, çok haneliyse 4; zemin accent kapsül
  (21×21'de daire). Erişilebilirlikte "3." gibi okunur. Yanında paragraf; **asılı girinti** (kayan satırlar yazının
  hizasında).
- **Madde:** aynı düzen; rozet yerine "•", kalın, accent renk, 21 genişliğinde çerçevede ortada; erişilebilirlikte
  gizli.

### 11.4 Öneri düzeni (ChipFlow)

Öneri çiplerini soldan sağa dizer, sığmayanı alt satıra geçirir. Yatay ve dikey aralık 8 (varsayılan). Her öğe kendi
doğal boyunda. Sağdan sola dillerde sıra sağdan başlar. Robotun öneri metinleri: `setup.combo.tvphone`,
`setup.combo.monitor`, `setup.combo.xbox`, `ask.suggest.tvinstall`.

---

## 12. Altyazı bölgesi önizlemesi (RegionPreview)

Ne işe yarar: PS5 görüntüsü üstünde altyazının okunacağı bölgeyi gösterip sürükleyerek ayarlamak.

Girdiler: bölge (sol, üst, sağ, alt; 0–1 oranları), son kare (görsel ya da yok), yer tutucu yazı (varsayılan
`home.preview.empty`), değişiklik bildirimi.

Görünüm: **16:9** oranında sığar; köşe 10 ile kırpılır.
1. Kare varsa: görsel, çerçeveyi doldurur (oranı zaten 16:9 sayılır). Yoksa: background #EEF3FB dolgulu, köşe 10
   dikdörtgen; ortada yer tutucu yazı caption 13 orta, textSecondary, ortalı, 12 iç boşluk.
2. Bölge kutusu: accent #0070D1 @%14 dolgu, accent 2 pt iç kenar. Konum/boy oransal. Erişilebilirlik adı
   `settings.region`.
3. Boyutlandırma tutamacı: 14×14 dolu accent kare, bölge kutusunun **sağ alt köşesinin içinde**. Erişilebilirlikte
   gizli.

Hareket: kutuyu sürükleyince (en az 1 pt) bölge taşınır; tutamacı sürükleyince sağ ve alt kenar değişir (sol-üst sabit).
Hesap hep sürükleme başlangıcındaki bölgeye göre yapılır; sınırlara sıkıştırma çekirdek kitaplıkta. Her değişiklik anında
bildirilir. Animasyon yok.

Hazır bölge adları: `region.bottom`, `region.top`, tam ekran (anahtarı yok), `common.custom`. Yüzde metni yerel biçimle ("40%", Türkçede "%40").

Bu görünüm sağdan sola dillerde **aynalanmamalı** (bölüm 14).

---

## 13. Sayfa (sheet) davranışları

- **Sayfa zemini:** alttan açılan sayfanın zemini verilen renkle boyanır (iOS 16.4+ sistemin sayfa zemini; öncesinde
  içerik zemini kenara kadar boyanır, görünüm aynı).
- **Sığan sayfa (fittedSheet):** küçük bilgi sayfası içeriği kadar açılır (orta/büyük yükseklikteki boşluk olmaz).
  İçerik doğal yüksekliğinde ölçülür; yükseklik yukarı yuvarlanır ve sayfanın tek yükseklik durağı olur. İçerik
  değişince (ör. bir alan gizlenince) sayfa da uyar. Ölçülmeden önceki başlangıç yüksekliği 320. Üstte sistem tutamacı
  görünür. Özel yükseklik alttaki güvenli alanı içermez.

---

## 14. Sağdan sola (Arapça, Urduca) davranışı

İki ayrı şey var:

1. **Arayüz dili sağdan sola ise** (ar, ur): sistemin olağan aynalaması geçerli. Yatay yığınlar ters dizilir (simge
   sağa, ok sola), "baştaki/sondaki" hizalamalar yer değiştirir, yönlü SF Symbol'ler (`chevron.left/right`) sistemce
   aynalanır. Bileşenlerde ayrıca bir işlem yok. Robot mesajındaki rozet ve madde noktası kendiliğinden sağa geçer;
   öneri çipleri sağdan dizilir.
2. **Altyazı metninin yönü yazının kendisinden seçilir, arayüz dilinden değil.** Metinde en az bir Arap harfi varsa
   (Unicode aralıkları: 0620–064A, 066E–06D3, 06FA–06FF, 0750–077F, 08A0–08FF, FB50–FDFF, FE70–FEFF) o metnin
   görünümü sağdan sola dizilir; yoksa çevrenin yönü korunur. "Doldur" seçeneği açıksa ve metin Arapçaysa metin tam
   genişlik alır ki sola yaslı bir yerde bile sağa yaslansın. Ek olarak gösterilecek metnin her satırının başına
   sağdan sola işareti (U+200F) konur; böylece "ARTHUR: …" gibi Latin harfli konuşmacı adıyla başlayan satır da
   sağdan başlar.
3. **Hep soldan sağa kalanlar** (Arapça arayüzde de aynalanmaz): PS5 görüntüsü ve çerçevesi, altyazı bölgesi
   önizlemesi, sürüklenen düğme, salon sahnesi, altyazı penceresinin kenar tutamakları. Bunların içindeki Arapça
   altyazı yine 2. kurala göre sağdan sola dizilir.

---

## 15. iPad farkları (toplu liste)

| Ne | iPhone | iPad |
|---|---|---|
| Ekran içeriği genişliği | tam genişlik | en çok 680, ortalı |
| Üst satırın üst boşluğu | 8 | 20 |
| Alt düğme bölgesinin alt boşluğu | 20 | 40 |
| Dikey canlı altyazı taban boyu | 28 | 36 |
| Yatay altyazı ekranı taban boyu | 36 | 60 |
| Yönler | dikey, yatay sol/sağ | dört yön |

Bu dosyalardaki diğer bütün ölçüler iPad'de aynıdır. (Ana ekranın kendi dosyasında ek iPad değerleri var; o ekranın
tarifinde ele alınmalı: yatay kenar 20 yerine 60, alt boşluk 40 yerine 80, oyuna göre altyazı boyu iPhone'da 15–20,
iPad'de 20–30 arası.)

---

## 16. Mac ile ortak olup iPhone'da görünmeyen parçalar

Eski iPhone projesi Mac'in ortak bileşen dosyalarını da derler, ama aşağıdakiler iPhone ekranlarında hiç kullanılmıyor;
yeni uygulamada yazılmalarına gerek yok: Mac düğme stili (eski adlı; sarı/mavi degrade düğme), Mac metin alanı stili,
Mac karo düzenleyicisi ve başlıklı kart, yuvarlak zeminli küçük karo simgesi, Mac etiketi ve canlı noktası, durum
noktası, sihirbaz adım düzeni, degrade simge kutusu, numaralı talimat satırı, durum satırı/karosu, tamam etiketi,
ipucu ve hata metni, cam yüzey düzenleyicisi (iOS 26 "Liquid Glass"), cam zeminli kayan kapsüllü seçici, seçenek
kartı. Marka yazısı (10.4) ve Nino arka zemini (3.2) yalnız açılış animasyonu ve uygulama kökü üzerinden görünür.

---

## 17. Belirsiz kalanlar

- **Simge düğmesinin basılı hâli:** yalnız sistemin düz düğme solması var, mobil düğmelerdeki %97 küçülme yok;
  bilerek mi yapıldığı belli değil.
- **Segment ve ızgaradaki seçim geçişi** animasyonsuz; Mac'teki kayan kapsül iPhone'da yok. Bilinçli mi belli değil.
- **"button" jetonu 52** tanımlı ama düğmeler gerçekte en az 58 yüksekliğinde; hangisinin doğru olduğu belirsiz (görünen
  58).
- **Mobil "screen" boşluğu 20**, ortak jeton dosyasında 24; iki değer yan yana yaşıyor.
- **Birincil düğme rengi:** yorumlarda "mavi-lacivert degrade, mavi gölge" yazıyor, kod koyu lacivert-siyah degrade
  ve lacivert gölge çiziyor. Tarif kodu esas aldı.
- **Etiketin "tamam" ve "vurgu" türleri** ve "sıkışık" seçeneği görünümü değiştirmiyor (tanımlı ama etkisiz).
- **Özel yerleşimlerin (bento ızgara, çip düzeni) sağdan solda aynalanması** sistemin özel yerleşimleri otomatik
  aynalamasına dayanıyor; eski kodda ayrıca sınanmış bir işlem görmedim.
- **Bayrak vurgusu koordinatları** eski logoya göre; yeni logo (PlayStation ve DualSense'siz) gelince yeniden ölçülmeli.
- **Uygulama simgesi** saydamsız 1024×1024 tek dosya; mağaza sorunları (Sony markaları) için yenisi gerekiyor.
