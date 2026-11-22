# Windows uygulaması: tasarım dili

Bu belge yeni Windows uygulamasının ortak görünüşünü anlatır: renkler, yazılar, boşluklar, köşeler, ortak bileşenler,
temalar, sağdan sola düzen ve hareket kuralları. Ana pencere ve ana ekran `ana-ekran.md`'de, kurulum sihirbazı
`kurulum.md`'de. Ölçüler WPF'in aygıttan bağımsız pikseli (px, 1/96 inç) cinsindendir. Renkler sRGB; `#AARRGGBB`
yazımında ilk iki hane opaklıktır (ör. `#66FFFFFF` = beyaz %40).

**Genel his (Windows'a özgü, Mac'ten farklı):** düz yüzeyler. Bileşenlerde cam, buzlu malzeme, degrade, parıltı,
hale ve gölge YOKTUR. Pencere zemini düz renktir (Mac'teki hareketli mavi/lacivert ışıklar yok). Birincil düğme düz
accent renginde, kart düz `surface` renginde, ince 1 px çerçeveyle. Degrade, gölge ve bulanıklık yalnız ana ekranın
iki çiziminde (salon sahnesi, cam anahtar), TV ekranının içinde ve "Nino'ya Sor" robotunda vardır; bunlar
`ana-ekran.md`'de.

---

## 1. Renk belirteçleri

Değerler eski uygulamanın belirteç dosyasıyla birebir aynı kalır (Mac de aynı değerleri kullanır). Yeni yapıda bu
dosya `apps/windows/src/Nino.Core/Resources/` altında yeniden yazılır (eski `design/tokens.json`'a bağlantı yok).
Dosyanın adı/biçimi serbest; içerik aşağıdaki gibi olmalı. Belirteç dosyası ayrıca şu bilgileri taşıyordu (uyum için
korunabilir): ad "Nino", sürüm 4, yazı ailesi Mac'te "SF Pro (sistem)", Windows'ta "Segoe UI Variable".

| Belirteç | Açık | Koyu | Windows'ta nerede |
|---|---|---|---|
| background | #EEF3FB | #050A1A | Bütün pencerelerin zemini (düz) |
| surface | #FFFFFF | #0E1733 | Kart zemini, açılır listenin açılan kutusu |
| surface2 | #E6EDF8 | #16224A | İkincil düğme, metin alanı, açılır liste, bölmeli seçim rayı, etiket, numara dairesi, seçili adım satırı, liste satırının üstüne gelme/seçili zemini |
| tileBorder | #DCE5F3 | #22305A | Kart çerçevesi |
| border | #D3DEEF | #2A3A68 | İkincil düğme ve metin alanı çerçevesi, ayırıcı, anahtar izi (kapalı), kaydırıcının boş kısmı, ilerleme çubuğunun izi, kaydırma çubuğu tutamacı, seçili bölme zemini, sıradaki adımın dairesi, logonun 1 px kenarı |
| textPrimary | #0A1430 | #F2F5FB | Ana yazı (pencere düzeyinde verilir), anahtar düğmesi (kapalı), kaydırıcı tutamacı |
| textSecondary | #55607A | #9DA9C6 | İkincil yazı, ipucu, alt yazı, boşta durum noktası, simge düğmesi |
| accent | #0070D1 | #2D8CFF | Birincil düğme, açık anahtar izi, kaydırıcının dolu kısmı, ilerleme çubuğu, etkin kart çerçevesi, şimdiki adımın dairesi, seçim zemini (metin seçimi) |
| accentHi | #1A86E8 | #5AA6FF | Birincil düğme basılıyken |
| onAccent | #FFFFFF | #FFFFFF | Accent üstündeki yazı, açık anahtarın düğmesi, adım dairesindeki işaret |
| accentText | #0058A8 | #7DB8FF | Klavye odak halkası, odaklı metin alanının çerçevesi, hayalet düğme yazısı, bağlantı (hyperlink), güncelleme başlığı |
| accentSoft | #DDEBFA | #132A55 | Kart rehberindeki kablo şeması kutuları |
| pro | #00205B | #9FC2FF | Paket simgesi ve paket etiketi yazısı |
| proSoft | #E2E8F5 | #1A2A50 | Paket etiketi zemini |
| success | #1E6B45 | #5FD39A | "Tamam" yazısı, iyi durum noktası, tamamlanmış adımın dairesi |
| successSoft | #DDF1E6 | #123527 | (yedek) |
| warning | #9A4A08 | #F5AE62 | Hata/uyarı yazısı, uyarı kartı başlıkları, uyarı durum noktası |
| danger | #B3261E | #FF8A80 | Tehlikeli düğme yazısı, güncelleme hata yazısı |
| dangerSoft | #FBE4E2 | #3A1E24 | Tehlikeli düğme zemini |
| dangerBorder | #EDB6B0 | #6B3A40 | (yedek) |
| onDanger | #FFFFFF | #17181B | (yedek) |

**Pencere zemini** = `background` belirteci, düz renk. Her pencere zeminini ve ana yazı rengini (textPrimary)
kendisi verir. Ana yazı rengi genel "yazı" stiline KONMAZ; pencere düzeyinde kalıtılır (genel stile konursa düğmelerin
içindeki yazının rengini ezer).

Her renk belirtecinden uygulama kaynaklarına bir "renk" ve bir dondurulmuş (değişmez) "fırça" türetilir; arayüz
bunlara dinamik kaynak olarak bağlanır, böylece tema değişince her şey anında yeniden boyanır.

### 1.1 Belirteç testleri (yeni testlere aynen alınabilir)

Kontrast WCAG 2 formülüyle: göreli parlaklık L = 0,2126·R + 0,7152·G + 0,0722·B, kanal c ≤ 0,03928 ise c/12,92,
değilse ((c + 0,055)/1,055)^2,4; oran = (büyük + 0,05)/(küçük + 0,05). "#RRGGBB" dışındaki yazım (uzunluk ≠ 7, '#' yok,
onaltılık değil) geçersizdir.

- Siyah/beyaz oranı 21 (2 hane); `#777777`/beyaz 4,48 (2 hane).
- Her renk çiftinin iki değeri de geçerli "#RRGGBB"; adı "Nino".
- Her iki temada: textPrimary / background ≥ 7; textPrimary / surface ≥ 7.
- textSecondary, accentText, success, warning, danger → background ve surface üstünde ≥ 4,5. accentText / accentSoft ≥ 4,5.
- pro → background, surface, proSoft üstünde ≥ 4,5; danger/dangerSoft ≥ 4,5; success/successSoft ≥ 4,5;
  textPrimary/surface2 ≥ 7; textSecondary/surface2 ≥ 4,5.
- onAccent/accent ≥ 3 (iki tema), açık temada ayrıca ≥ 4,5; onDanger/danger ≥ 4,5.
- Köşe değerleri kümesi tam olarak {6, 10, 14, 22, 999}. Yazı boyları yalnız {13, 15, 17, 22, 28}; kalınlıklar yalnız
  regular / medium / semibold. Dosyada "glow" (parıltı) alanı yok.
- body ≥ 15, caption ≥ 12.

### 1.2 Belirteç dışındaki sabit renkler

Temaya göre DEĞİŞMEYEN renkler (açıkta da koyuda da aynı):

| Ad (öneri) | Değer | Nerede |
|---|---|---|
| Bayrak kırmızısı | #E30A17 | Cam anahtar açık izi ve küresi, CANLI noktası, Türk bayrağı |
| Koyu bayrak kırmızısı | #A80514 | Cam anahtar izinin alt tonu |
| LED mavisi | #1F5CFF | Salon LED'leri, TV açılışındaki ışık |
| İndirme yeşili | #7BE87B | TV'deki toplam indirme sayısı |
| Robot dairesi | #F5FFFFFF, kenar #1F0B1633 | "Nino'ya Sor" düğmesi |
| Balon | zemin #8C000000, kenar #24FFFFFF | çeviri başladı balonu (`home.toast.translationStarted`) |

Salonun, anahtarın ve TV içinin diğer renkleri `ana-ekran.md`'de kullanıldıkları yerde.

---

## 2. Yazı tipleri

- **Metin yazısı:** "Segoe UI Variable Text", yoksa "Segoe UI".
- **Başlık yazısı:** "Segoe UI Variable Display", yoksa "Segoe UI" (yalnız ekran başlığı ve bölüm başlığında).
- **Simge yazısı:** "Segoe Fluent Icons", yoksa "Segoe MDL2 Assets" (§9).

Kalınlık eşlemesi: bold → kalın (700), semibold → yarı kalın (600), medium → orta (500), diğerleri normal (400).

Varsayılan yazı (her yazı bloğu): metin yazısı, body boyu (15), alt satıra kayar, satır yüksekliği "blok" usulü
(belirtilen satır yüksekliği tam uygulanır).

| Stil | Boy | Kalınlık | Satır yüksekliği | Renk | Yazı |
|---|---|---|---|---|---|
| Ekran başlığı (display) | 28 | yarı kalın | 34 | kalıtılan | başlık yazısı |
| Bölüm başlığı (title) | 22 | yarı kalın | 28 | kalıtılan | başlık yazısı |
| Karo başlığı (headline) | 17 | yarı kalın | 22 | kalıtılan | metin |
| Gövde (body) | 15 | normal | 20 | kalıtılan | metin |
| İkincil | 15 | normal | 20 | textSecondary | metin |
| İpucu (callout) | 13 | orta | 17 | textSecondary | metin |
| Küçük etiket (caption) | 13 | orta | 16 | textSecondary | metin |
| Hata | 13 | orta | 17 | warning | metin |
| Tamam | 15 | yarı kalın | 20 | success | metin |
| Canlı satır | 28 | yarı kalın | 36 | kalıtılan | metin (arayüz ölçeğinin dışında, sabit) |
| Simge | — | — | — | — | simge yazısı, tek satır, dikeyde ortalı |

Belirteç dosyasındaki yazı boyları: display 28 semibold, title 22 semibold, headline 17 semibold, body 15 regular,
callout 13 medium, caption 13 medium, button 15 semibold, code 22 semibold.

Not: Mac'teki gibi "hata" ve "tamam" metinlerinin önünde simge yoktur; düz renkli yazıdır. (Eşleşme başarısında yazının
başına "✓ " karakteri konur, bkz. `kurulum.md`.)

### 2.1 Altyazı yazı tipleri (uygulamaya gömülü)

Dosyalar uygulamanın kaynaklarına gömülür (pakete yazı tipi kaynağı olarak), sisteme kurulmaz. OFL lisans metinleri
(`OFL-Barlow.txt`, `OFL-Nunito.txt`) uygulamanın yanına `Fonts\` klasörüne düz dosya olarak kopyalanır. Eski
`windows/src/Nino.App/Fonts/` klasöründeki dosyalar aynen yeniden kullanılabilir (OFL):

| Dosya | İç aile adı | Yüz |
|---|---|---|
| `NinoAction-SemiBold.ttf` | "Nino Action" (tipografik aile; eski ad alanında "Nino Action SemiBold") | SemiBold |
| `NinoAction-Bold.ttf` | "Nino Action" | Bold |
| `Barlow-SemiBold.ttf` | "Barlow" (tipografik aile) | SemiBold |
| `Barlow-Bold.ttf` | "Barlow" | Bold |
| `Nunito-SemiBold.ttf` | "Nunito" (tipografik aile) | SemiBold |
| `Nunito-Bold.ttf` | "Nunito" | Bold |

- "Nino Action", Barlow Condensed'in yeniden adlandırılmış kopyasıdır. Sebep: WPF aile adındaki "Condensed" sözcüğünü
  genişlik bilgisi sayıp aileyi Barlow'a bağlar; ayrı adla gömülünce ayrı aile olarak kalır.
- Nunito'nun değişken dosyası WPF'te en ince ağırlığıyla çizildiği için yarı kalın ve kalın olarak iki sabit dosyaya
  ayrılmıştır.
- Seçenekler: Aksiyon (varsayılan) → "Nino Action"; Modern → "Barlow"; Yuvarlak → "Nunito"; Sade/Sistem → hiçbir şey
  atanmaz, yazı bloğu kendi yazı tipiyle kalır.
- Her gömülü ailenin arkasına yedek zincir eklenir: "Segoe UI, Segoe UI Historic, Nirmala UI, Leelawadee UI". Gömülü
  ailelerde bulunmayan yazı sistemleri (Arapça, Tayca, Hintçe, Bengalce) bu zincirdeki sistem yazılarıyla çizilir.
- Seçeneklerin ekrandaki adları ve sırası Mac `tasarim-dili.md` §2'deki tabloyla aynı.

---

## 3. Boşluk ölçeği

| Ad | Değer | Kullanım |
|---|---|---|
| xs / hair | 4 | |
| s / inline | 8 | Simge ile yazı arası |
| m / gap | 12 | Karo içi satırlar, başlık altı |
| l / tile | 16 | Kartın iç boşluğu |
| xl / screen | 24 | Pencere kenar boşluğu (ana ekran, sihirbaz, rehber penceresi) |
| xxl | 32 | Sihirbaz adım karosunun iç boşluğu |

Her boşluk değerinden hem sayı hem dört yana eşit kalınlık (kenar boşluğu) kaynağı türetilir.

## 4. Köşe yarıçapları

Windows'ta köşeler düz daire yayıdır (Mac'teki "sürekli" köşe yok).

| Ad | Değer | Nerede |
|---|---|---|
| card | 22 | Kart |
| control | 14 | Düğme, metin alanı, açılır liste, bölmeli seçim rayı, kenar çubuğu satırı, sihirbaz adım satırı, kart önizlemesi |
| inner | 10 | Bölme, açılır liste satırı, oyun monogramı |
| tag | 6 | Etiket |
| pill | 999 | (tam kapsül; doğrudan kullanılmaz) |

Eski kodun yorumlarında "16/12/8" yazar; bu eskidir, geçerli değerler yukarıdakilerdir.

## 5. Ölçüler

| Ad | Değer |
|---|---|
| Düğme yüksekliği (en az) | 40 |
| Büyük düğme (sihirbaz Geri/Devam, rehber) | 44 |
| Ana eylem yüksekliği | 52 (PIN alanı) |
| Satır yüksekliği | 40 |
| Tuş simgesi | 24 |
| Durum noktası | 8 (ana ekran şeridinde 7 kullanılır) |
| Kenar çubuğu genişliği | 240 |
| Ana sütun | 380 |
| Pencere genişliği | 1040 |
| Pencere yüksekliği | 720 |

---

## 6. Görünüm (tema)

- Ayarlardaki görünüm üç değerlidir: Sistem, Açık, Koyu. **Varsayılan: Sistem** (yeni ayarda da, alanı olmayan eski
  ayar dosyasında da). Ayar dosyasında metin olarak saklanır: `"Appearance":"System" | "Light" | "Dark"`. (Eski kodda
  bu varsayılanla çelişen bir yorum vardı; geçerli olan Sistem'dir.)
- Açık → açık renkler, Koyu → koyu renkler, Sistem → Windows'un uygulama teması.
- Windows'un teması: kullanıcı kayıt defterinde `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`
  altındaki `AppsUseLightTheme` değeri tamsayı 0 ise koyu; değer yoksa ya da 0 değilse açık.
- Görünüm, ilk pencere açılmadan uygulanır. Aynı görünüm ikinci kez uygulanmaz (yalnız değiştiğinde yeniden kurulur).
- Ayarlar değişince (görünüm alanı) kaynaklar anında yeniden kurulur; arka iş parçacığından gelirse arayüz iş
  parçacığına aktarılarak.
- Windows'un kullanıcı tercihi "Genel" kategorisinde değişince: görünüm henüz uygulanmadıysa ya da "Sistem" ise renkler
  yeniden okunur.
- Açık/koyu farkı yalnız §1 tablosundaki renklerdir; ölçüler, yazılar, bileşen biçimleri aynı kalır. §1.2'deki sabit
  renkler ve ana ekranın çizimleri temadan bağımsızdır.

## 7. Hareket ve "hareketi azalt"

- "Hareketi azalt" = Windows'ta "Animasyonları göster" kapalı (istemci alanı animasyonu sistem parametresi yanlış).
- Uyanlar (hareketi azaltınca durur ya da anında biter): robotun göz kırpması ve süzülmesi, robot düğmesinin büyüme
  geçişi, "çeviri başladı" balonu, salondaki priz ışığının nabzı (sabit yanar), priz ışığının sönme geçişi, açılışta
  fişin bekleyip yaylanması (bekleme 1 ms'ye iner, yay yok), indirme sayısının sayılması.
- Uymayanlar (her zaman oynar): TV'deki Nino açılışı, LED'lerin 0,8 sn'lik solup yanması, cam anahtarın 0,55 sn'lik
  kayması, CANLI noktasının yanıp sönmesi, TV satırının 0,3 sn'lik belirmesi, kart rehberinin sayfa geçişi, sihirbazdaki
  rehber/adım değişiminin 0,25 sn'lik belirmesi. (Bu, eskisinin davranışıdır; aynen korunur.)
- Ortak bileşenlerin (düğme, anahtar, kart, bölmeli seçim) durum değişimleri animasyonsuzdur: renk/opaklık anında
  değişir. Mac'teki %97 basma ölçeği, yay geçişleri, bölmeli seçimde kayan kapsül Windows'ta yoktur.

## 8. Ortak bileşenler

### 8.1 Düğmeler

Ortak şablon: dış çerçeve (zemin, çerçeve rengi/kalınlığı, iç boşluk, köşe 14, piksele oturtulmuş) ve içinde ortalı
içerik; içeriğin yazı rengi düğmenin yazı rengidir. Çerçevenin üstünde aynı köşeli, 2 px, accentText renkli bir odak
halkası durur; yalnız klavye odağındayken görünür. Sistemin kesik çizgili odak işareti kapalı.

Ortak değerler: metin yazısı, 15 px, yarı kalın; en az yükseklik 40; yatay iç boşluk 20 (dikey 0); el imleci; varsayılan
yatay hiza SOLA (tam genişlik değil).

Durumlar (hepsinde aynı, animasyonsuz):

| Durum | Etki |
|---|---|
| Üzerine gelince | Çerçevenin opaklığı 0,92 |
| Basılıyken | Çerçevenin opaklığı 0,8 (birincilde ayrıca zemin accentHi) |
| Klavye odağı | 2 px accentText halka |
| Devre dışı | Bütün düğme opaklığı 0,4 (görünüş değişmez) |

| Tür | Zemin | Yazı | Çerçeve | Not |
|---|---|---|---|---|
| Birincil | accent (basılıyken accentHi) | onAccent | yok | |
| İkincil | surface2 | textPrimary | 1 px border | **Her düğmenin varsayılanı** (tür verilmeyen düğme ikincildir) |
| Tehlikeli | dangerSoft | danger | yok | |
| Hayalet | saydam | accentText | yok | yatay iç boşluk 12 |
| Simge düğmesi | surface2 | textSecondary | 1 px border | 40 × 40, iç boşluk 0 |

Mac'ten farklar: birincil düğmede degrade, iç parıltı kenarı ve gölge yok; ikincil düğme cam değil, düz surface2.

### 8.2 Metin alanı ve parola alanı

İkisi aynı görünür: metin yazısı 15 px, yazı textPrimary, zemin surface2, 1 px border çerçeve, köşe 14, imleç
textPrimary, seçim zemini accent, yatay iç boşluk 14, en az yükseklik 40, içerik dikeyde ortalı. Klavye odağındayken
çerçeve accentText olur. (Mac'te 44 yükseklik ve cam; Windows'ta 40 ve düz.)

### 8.3 Bölmeli seçim (Mac'teki segment denetiminin karşılığı)

- Ray: zemin surface2, köşe 14, iç boşluk 2, sola yaslı.
- Her bölme bir seçenek düğmesidir: 2 px dış boşluk, en az yükseklik 36; içinde köşe 10, iç boşluk yatay 12 dikey 6,
  1 px saydam çerçeveli bir kutu; içerik ortalı. Yazı 15 px, orta kalınlık, textSecondary; ortalı ve gerekirse iki
  satıra iner (dar sütunda `settings.connection.output.computer` gibi iki sözcüklü bir seçenek kesilmez).
- Seçili bölme: kutunun zemini border rengi, yazı textPrimary, yarı kalın. Kayan kapsül, gölge, degrade yok.
- Klavye odağında kutunun çerçevesi accentText.

### 8.4 Seçenek düğmesi (radyo)

Sistemin kendi radyo düğmesi görünüşü; yalnız yazı 15 px, rengi textPrimary, üst/alt dış boşluk 4.

### 8.5 Anahtar (aç/kapat)

Onay kutusu anahtar olarak çizilir:

- 52 × 32 iz, köşe 16, zemin border, 2 px saydam çerçeve.
- 24 × 24 daire düğme, izin solunda 4 px boşlukla, dolgusu textPrimary.
- Açıkken iz accent, düğme sağa yaslanır (sağda 4 px), dolgusu onAccent. Geçiş animasyonsuz (düğme atlar).
- Etiket izin sağında, 12 px boşlukla, dikeyde ortalı; etiket yoksa boşluk 0.
- Klavye odağında izin çerçevesi accentText. Devre dışıyken bütün anahtar opaklığı 0,4. Yazı 15 px, textPrimary, el
  imleci.

### 8.6 Açılır liste

- En az yükseklik 40, en az genişlik 220, sola yaslı, el imleci, yazı 15 px textPrimary.
- Kutu: surface2 zemin, 1 px border çerçeve, köşe 14. Sağda aşağı ok simgesi (U+E70D), 12 px, textSecondary, sağdan
  14 px içeride. Üzerine gelince çerçeve textSecondary.
- Seçili öğe kutunun içinde: sol 14, sağ 38 boşlukla, dikeyde ortalı, sola yaslı; tıklamaları kutuya bırakır.
- Odak liste içindeyken 2 px accentText halka (köşe 14).
- Açılan kutu: listenin altında, solarak açılır; zemin surface, 1 px border çerçeve, köşe 14, iç boşluk 4, üstten 4 px
  aralık; en az genişlik listenin genişliği, en çok yükseklik listenin en çok açılır yüksekliği; içi kaydırılır,
  klavye oklarıyla içeride gezilir.
- Satır: köşe 10, iç boşluk yatay 12 dikey 8. Üstüne gelince ya da klavyeyle vurgulanınca zemin surface2; seçili
  satırın zemini surface2 ve yazısı yarı kalın.
- Devre dışıyken opaklık 0,4.

### 8.7 Kaydırıcı

28 px yüksek iz. Tutamacın solu (dolu kısım) 8 px yüksek, köşe 4, accent; sağı aynı ölçüde border. Tutamaç 24 × 24
daire, textPrimary. Boş kısma tıklamak büyük adımla ilerletir.

### 8.8 Bağlantı, ayırıcı, kaydırma çubuğu, ilerleme çubuğu

- **Bağlantı (hyperlink):** accentText, altı çizgisiz.
- **Ayırıcı:** border rengi, üst/alt 12 boşluk.
- **Kaydırma çubuğu:** 8 px geniş, dış boşluk üst 4, sağ 4, alt 4; oksuz; tutamaç border renkli, köşe 4; boş kısmı
  saydam (tıklayınca sayfa kaydırır). Yatayda 8 px yüksek.
- **İlerleme çubuğu:** 6 px yüksek; iz border, dolgu accent, ikisi de köşe 3; dolgu soldan büyür. Değer 0–1.

### 8.9 Kart (karo)

- Zemin surface, 1 px tileBorder çerçeve, köşe 22, iç boşluk 16 (dört yana). **Gölge yok.**
- İsteğe bağlı başlık: en üstte karo başlığı stili (17 yarı kalın), altında 12 boşluk. Başlık verilmezse yer kaplamaz.
- "Etkin" kart (seçili seçenek): çerçeve accent (kalınlık yine 1 px).
- Mac'ten farklar: cam yok, gölge yok, etkin çerçeve 1,5 değil 1 px, iç boşluk aynı (16).

### 8.10 Sihirbaz adım düzeni

Dikey yığın, **sola yaslı** (Mac'te ortalı ve simgeli):

1. Başlık: ekran başlığı stili (28 yarı kalın, başlık yazısı).
2. Açıklama: ikincil stil (15, textSecondary), üstte 12 boşluk, en çok 620 geniş, sola yaslı, alt satıra kayar.
3. İçerik: üstte 20 boşluk.

Simge rozeti, logo, belirme animasyonu yok.

### 8.11 Numaralı satır

Altta 16 boşluk. Solda 28 × 28 daire (köşe 14), zemin surface2, yukarıya yaslı; içinde numara 13 px yarı kalın,
textPrimary, ortalı. Sağda metin: gövde stili (15, satır 20), soldan 12, üstten 4 boşluk, alt satıra kayar. (Mac'teki
degrade daire, gölge, karo zemini yok.)

### 8.12 Durum karosunun içi (ayarlar ve sağlık sayfalarında kullanılır)

Dikey: üstte etiket satırı (altında 8 boşluk) ve altında değer.

- Etiket satırı: solda simge (kutusuz, textSecondary, simge yazısı 18 px, sağında 8 boşluk), sonra başlık (küçük etiket
  stili), en sağda 8 × 8 durum noktası (dikeyde ortalı).
- Değer: karo başlığı stili (17 yarı kalın), alt satıra kayar.
- Ton iyi: nokta success, değer textPrimary. Ton uyarı: nokta warning, değer textSecondary. Ton boşta: nokta
  textSecondary, değer textSecondary. Nokta her tonda görünür.

### 8.13 Durum tonu

Üç ton: iyi → success, uyarı → warning, boşta → textSecondary. Hangi durumun hangi tonu aldığını denetleyici söyler.

### 8.14 Karo simgesi, oyun monogramı, etiket

- **Karo simgesi:** kutusuz, sola yaslı, yalnız simge; rengi textSecondary (paket simgesinde pro). (Mac'teki
  accentSoft daire yok.)
- **Oyun monogramı:** 52 × 52, zemin surface2, köşe 10, yazı textPrimary.
- **Etiket (pill):** 24 yüksek, yatay iç boşluk 8, köşe 6, zemin surface2, yazı küçük etiket boyunda (13 orta)
  textSecondary, dikeyde ortalı, sola yaslı. Paket türü: zemin proSoft, yazı pro. Durum bilgisi etiketle değil, nokta +
  kelimeyle verilir.

### 8.15 Ayarların kenar çubuğu (bilgi için; ayrıntı ayarlar belgesinde)

Solda 240 genişliğinde kart (iç boşluk yatay 12, dikey 20), üstte bölüm başlığı stilinde pencere başlığı (yanlardan 12,
altta 12), altında kaydırılabilir bölüm listesi; sağda 16 boşlukla seçili bölüm (kaydırılabilir, sağda 12 boşluk).
Satır: en az 40 yükseklik, yatay iç boşluk 12, altta 4 boşluk, köşe 14, 1 px saydam çerçeve; yazı 15, textSecondary.
Üzerine gelince zemin surface2; seçiliyken zemin surface2, yazı textPrimary yarı kalın; klavye odağında çerçeve
accentText. Sekme/ok tuşlarıyla liste içinde döngülü gezilir. Kenar çubuğunun yazı rengi açıkça textPrimary verilir
(sistemin varsayılan siyahı koyu temada okunmuyordu).

### 8.16 Logo kutusu

`logo.png` (512 × 512) kare alana yüksek kaliteli küçültmeyle sığdırılır; üstünde 1 px border renkli çerçeve, köşe
kenarın 0,225 katı (36'da 8,1; 32'de 7,2), koyu temada logonun kenarı zeminden ayrılsın diye. Mac'teki 1,21 kat büyütme
kuralı Windows'ta yok.

### 8.17 Dil bayrakları (çeviri dili seçicileri)

Windows'ta bayrak emojisi bayrak yerine iki harf olarak görünür; bu yüzden bayraklar şekillerle çizilir. Her bayrak 22 × 15, köşesi
2,5 yuvarlatılarak kırpılır, her zaman soldan sağa çizilir. Koordinatlar bayrağın sol üstünden (x, y); "dikdörtgen
g×y @ (x, y)".

| Kod | Çizim |
|---|---|
| tr (ve listede olmayan her kod) | Zemin #E30A17. Hilal: (4,2; 3,7)'de 7,6'lık beyaz daire, üstünden 7,6 × 0,8 = 6,08'lik zemin renkli daire, sol üstü (4,2 + 7,6×0,22; 3,7 + (7,6 − 6,08)/2). Yıldız: merkez (13,4; 7,5), dış yarıçap 2,1, beyaz |
| ar | Zemin #006C35. Beyaz dikdörtgenler: 12×1,2 @ (5; 4,2), 9×1,2 @ (6,5; 6,6), 13×1 @ (4,5; 10,2), 1×2,4 @ (15,5; 9,5) |
| hi | Üç eşit yatay şerit: #FF9933, beyaz, #138808. Ortada 4 × 4 daire @ (9; 5,5), çizgi #000080, kalınlık 0,9 |
| id | İki şerit: #CE1126, beyaz |
| th | Zemin #A51931; beyaz 22×2,5 @ (0; 2,5); #2D2A4A 22×5 @ (0; 5); beyaz 22×2,5 @ (0; 10) |
| vi | Zemin #DA251D; sarı (#FFFF00) yıldız, merkez (11; 7,8), yarıçap 4,2 |
| ur | Zemin #01411C; beyaz 5,5×15 @ (0; 0); hilal (9,2; 3,6) boy 7,4 (oyuk zemin rengi); beyaz yıldız merkez (16,4; 5,6) yarıçap 1,6 |
| bn | Zemin #006A4E; #F42A41 daire 8,4 @ (5,6; 3,3) |
| ms | Zemin beyaz; 0, 2, 4 … 12. on dörtte birlik dilimlerde #CC0001 şeritler (yükseklik 15/14 + 0,1, y = i × 15/14); #010066 11×8,6 @ (0; 0); hilal (1,6; 1,6) boy 5,4, rengi #FFCC00, oyuğu #010066; #FFCC00 yıldız merkez (7,8; 4,3) yarıçap 1,5 |
| tl | İki şerit #0038A8, #CE1126; beyaz üçgen (0,0)-(11; 7,5)-(0,15); #FCD116 daire 3 @ (2,6; 6) |
| nl | Üç şerit #AE1C28, beyaz, #21468B |

- Şerit: yükseklik 15/n (+0,2 taşma payı, ek yeri görünmesin), yukarıdan aşağı.
- Hilal (genel): (x, y)'de boy b dolu daire (renk verilmezse beyaz), üstüne b×0,8 boyunda zemin renkli daire, sol üstü
  (x + b×0,22, y + (b − b×0,8)/2).
- Yıldız: beş köşeli, 10 nokta; i. nokta açısı 90° + i × 36°, yarıçap çift i'de r, tek i'de r × 0,42; nokta
  (r·cos a, −r·sin a) merkeze göre (ilk köşe yukarı bakar).
- Liste satırı: bayrak + 10 boşluk + dilin kendi adı (dikeyde ortalı), satır her zaman soldan sağa.
- Dil listesi ve sırası: Türkçe (tr), العربية (ar), हिन्दी (hi), Bahasa Indonesia (id), ไทย (th), Tiếng Việt (vi),
  اردو (ur), বাংলা (bn), Bahasa Melayu (ms), Filipino (tl), Nederlands (nl). Kodun ilk iki harfi küçük harfle
  karşılaştırılır.

### 8.18 Kısayol metinleri (ekran metinlerinde)

Bir işin tuşları ekranda şöyle yazılır: hiç kısayolu yoksa yok; bir tuş varsa tuşun etiketi; iki tuş varsa metin
anahtarı `shortcut.keysTwo` (iki tuş, "ya da" bağlacıyla), ilk iki tuşla. Başlık biçiminde tuş yoksa parantez içinde
`shortcut.none` yazılır. Cümle biçiminde tuş yoksa `shortcut.noneSentence` (kısayol atanmadığını ve Kısayollar
bölümünden atanabileceğini söyleyen cümle) gösterilir. İşlerin metin anahtarları ve Ayarlar › Kısayollar'daki sırası
(en çok kullanılandan aza): `shortcut.action.translateScreen`, `shortcut.action.freeArea`,
`shortcut.action.translateArea1` / `…Area2` / `…Area3`, `shortcut.action.pauseResume`,
`shortcut.action.clickThrough`, `shortcut.action.refreshPicture`. Tuş tablosunun kendisi ayarlar belgesinde.

---

## 9. Simgeler (Segoe Fluent Icons kod noktaları)

| Kod noktası | Sistem adı | Nerede |
|---|---|---|
| U+E81C | History | Geçmiş düğmesi |
| U+E713 | Settings | Ayarlar düğmesi |
| U+E73E | CheckMark | Tamamlanan adım, "iyi" bilgi satırı |
| U+E7BA | Warning | Uyarı bilgi satırı |
| U+E7E8 | PowerButton | Cam anahtarın küresi (kapalı) |
| U+E70D | ChevronDown | Açılır liste oku |
| U+E703 | Connect | `setup.welcome.shortcutCaptureCard` kısayolu, kablo şeması, kart önizlemesi |
| U+E7FC | Game | Kablo şemasında PS5/kol |
| U+E7F4 | TVMonitor | TV / monitör |
| U+E7F8 | DeviceLaptopNoPic | Bilgisayar |
| U+E72E | Lock | Kamera izni yok |
| U+E785 | Unlock | |
| U+E946 | Info | Bilgi satırı |
| U+E7F6 | Headphone | Kulaklık uyarısı |
| U+EA3A | CircleRing | Seçilmemiş seçenek halkası |
| U+EC61 | CompletedSolid | Seçili seçenek halkası |
| U+E8C1 | Characters | daha iyi çeviri adımı (`setup.better.title`) |
| U+E8BD | (altyazı) | |
| U+E716 | People | |
| U+E77B | Contact | |
| U+E930 | Completed | |
| U+E896 | Download | |
| U+E768 | Play | |
| U+E71A | Stop | |
| U+E774 | Globe | çeviri motoru karosu (`translation.engine.title`) |
| U+E765 | KeyboardClassic | Kısayol karosu |
| U+E7B8 | Package | Oyun paketi karosu |
| U+E723 | Attach | Nino'ya Sor: görüntü ekle |
| U+E724 | Send | Nino'ya Sor: gönder |
| U+E710 | Add | Nino'ya Sor: yeni sohbet |

Ay-yıldız, fiş, priz ışığı gibi çizimler simge değil şekildir (`ana-ekran.md`).

## 10. Görseller

Görseller uygulamaya kaynak olarak gömülür; 1 piksel = 1 px, tek ölçek. Hepsi yeniden kullanılabilir (yeni ağaca
kopyalanır; eski yollara bağlantı kurulmaz):

| Görsel | Piksel | Eski yer | Nerede |
|---|---|---|---|
| `Nino.ico` | çok boy | `windows/src/Nino.App/Assets/` | Pencere ve görev çubuğu simgesi, exe simgesi |
| `logo.png` | 512 × 512 | `windows/src/Nino.App/Assets/` | Başlık logosu, TV açılışı |
| `living-room.png` | 1672 × 941 | `windows/src/Nino.App/Assets/` | PS5'li salon |
| `living-room-xbox.png` | 1671 × 941 | `mac/Nino/Resources/Assets.xcassets/LivingRoomXbox.imageset/` (Windows kopya tutmuyordu, Mac'inkini bağlıyordu) | Xbox'lı salon (1672 × 941'e gerilerek) |
| `nino-bot-256.png` | 256 × 256 | `design/bot-png/` | Robot, gözler açık |
| `nino-bot-blink-256.png` | 256 × 256 | `design/bot-png/` | Robot, göz kırpma karesi |

Mac'teki konsol/TV seçim görselleri (ConsolePS5, TVOption…) Windows'ta kullanılmaz.

## 11. Sağdan sola

- Arayüz yalnız Arapça (ar) ya da Urduca (ur) arayüz dilinde sağdan sola açılır.
- **Windows'ta arayüz dili = Windows'un kendi arayüz dili** (iki harfli kodu), çeviri dili değil. Desteklenen arayüz
  dilleri: tr, ar, hi, id, th, vi, ur, bn, ms, fil (kod "fil" ile başlıyor ya da "tl" ise), nl; diğer her dilde
  İngilizce. Uygulama açıkken değişmez. (Mac'te arayüz dili çeviri diliyle birlikte değişir; Windows'ta değişmez.)
  Bir metnin o dilde çevirisi yoksa İngilizcesi gösterilir. İlk açılışta varsayılan çeviri dili de Windows arayüz dilinden
  önerilir (listede varsa o dil; ayrıntı ayarlar belgesinde).
- Uygulama açılırken, ilk pencereden önce: her pencere yüklenirken, kendi yönü açıkça verilmemişse sağdan sola yapılır;
  ana pencere ilk çizimden önce ayrıca aynı kurala göre yön alır. (Bütün pencerelerin varsayılan yönünü genel olarak
  değiştirmek, Arapça Windows'ta görüntü denetiminin ilk kullanımında açılışta çöküyordu; bu yüzden pencere pencere
  uygulanır.)
- Aynalanmayan (her zaman soldan sağa kalan) parçalar: salon sahnesinin tamamı, cam anahtarın tamamı (canlı TV dahil),
  robot görseli (şapkadaki bayrak ters dönmesin), dil bayrakları ve bayraklı liste satırları, karşılama adımındaki dil
  seçicisi, kart önizlemesinin çerçevesi, PS5 görüntüsü / çerçeve / sürüklenen düğmeler.
- Altyazı ve TV satırı: yön yazının kendisinden seçilir. Metinde Arap harfi varsa satır sağdan sola akar ve her
  paragrafın başına (yoksa) sağdan sola işareti U+200F konur (konuşmacı adıyla "MARA: …" başlasa da sağdan dizilsin);
  yoksa soldan sağa, metin olduğu gibi.
- Kart rehberinde sayfa geçişi Arapçada öteki yandan gelir; kablo şemasındaki ok "→" yerine "←" olur.

## 12. Windows'a özgü (platform) kısımlar

| Yetenek | Ne için | Ayar |
|---|---|---|
| Kayıt defteri, kullanıcı anahtarı | Windows teması | `...\Themes\Personalize\AppsUseLightTheme` (0 = koyu) |
| Sistem olayları: kullanıcı tercihi değişti | Tema "Sistem"ken anında izleme | yalnız "Genel" kategori |
| Sistem parametresi: istemci alanı animasyonu | "Hareketi azalt" | yanlışsa hareket azaltılır |
| Gömülü yazı tipi kaynakları | Altyazı yazıları | §2.1, aile adı "#Nino Action", "#Barlow", "#Nunito" |
| Segoe Fluent Icons / Segoe MDL2 Assets | Simgeler | §9 |
| Sistem yazı tipi listesi | "Impact" var mı (TV indirme sayacı) | okunamazsa yok sayılır |

## 13. Mac'te olup Windows'ta olmayanlar (bilerek)

Cam yüzeyler ve Liquid Glass; hareketli zemin ışıkları; birincil düğmede degrade/gölge; %97 basma ölçeği ve yay
geçişleri; kayan segment kapsülü; seçenek kartı (görselli satır karo, üstüne gelince büyüme); 36'lık yuvarlak cam simge
düğmeleri (Windows'ta yazılı ikincil düğmeler); degrade simge kutusu; numara dairesindeki degrade; hata/tamam
simgeleri; kurulum adımının simgesi ve ortalı düzeni; arayüz dilinin çeviri diliyle değişmesi.
