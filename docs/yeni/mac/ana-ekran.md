# Mac uygulaması: ana ekran

Bu belge Mac uygulamasının penceresini, menülerini, ana ekranını (salon sahnesi ve cam anahtar), ekran dışındaki
altyazı penceresini ve yayın penceresini anlatır. Ortak renkler, yazılar ve bileşenler `tasarim-dili.md`'de; burada
yalnız adlarıyla anılır (ör. "birincil düğme", "karo", accent). Ölçüler nokta (pt) cinsinden. Renkler sRGB, (k, y, m)
0–1 aralığında. "Yay (t, s)" bir yay animasyonu demektir: t tepki süresi (saniye), s sönüm oranı.

Metinler: her metin noktalı bir anahtarla anılır (ör. `home.settings`). Anahtarlar alanlara göre ayrı metin
dosyalarında durur (Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport); ana ekranınkiler Home'da.
Anahtarın yanında ya yeni İngilizce ve Türkçe metin ya da, eskiyle örtüşebilecek yerlerde, metnin ne dediğine dair kısa bir açıklama bulunur. Bütün metinler §14'te (sona bakın) toplu olarak da listelenir.

---

## 1. Pencere yapısı

### 1.1 Ana pencere

- Tek ana pencere.
- Genişlik: en az 1040, ilk açılışta 1040, en çok 1300 (1040 × 1,25).
- Yükseklik: en az 720, ilk açılışta 720. En çok sınırı yok.
- Kullanıcı pencereyi bu en az / en çok sınırları içinde boyutlandırabilir; sınırlar içeriğin kendi sınırlarıdır.
- Başlık çubuğu ayrı renkte görünmez. Araç çubuğunun zemini gizlidir. macOS 15 ve sonrasında pencerenin kendi zemini
  `background` belirtecidir. Uygulama zemini (bkz. tasarım dili §7) başlık çubuğunun altına kadar uzanır.
- Pencerenin bütün içeriği:
  - Uygulama zemininin üstündedir.
  - Varsayılan yazısı body, rengi textPrimary.
- **Arayüz dili:**
  - Çeviri diliyle aynıdır (Türkçe, Arapça, Hintçe, Endonezce…).
  - Desteklenmeyen bir dilde arayüz İngilizce açılır. Filipince için "fil" kullanılır.
  - Kullanıcı çeviri dilini değiştirince arayüz hemen o dile geçer.
  - Seçilen dil sistemin uygulama dili tercihine de yazılır. Böylece sonraki açılışta sistemden okunan metinler de
    aynı dilde olur.
- **Yazı yönü:** çeviri dili Arapça, Farsça, İbranice ya da Urduca ise bütün arayüz sağdan sola dizilir (bkz. §9).

### 1.2 Açılış sırası

1. Uygulama açılır açılmaz pencerede açılış animasyonu oynar (§7). Testlerde oynamaz.
2. Kurulum bitmemişse açılışın arkasında kurulum ekranı, bitmişse ana ekran durur.
   - Ana ekran ancak açılış animasyonu bitince kurulur. Böylece salondaki fiş ve sayaç gösterisi açılışın arkasında
     oynayıp kaçmaz.
   - Kurulum ekranı açılış sırasında da kuruludur, yalnız görünmez (opaklık 0).
3. Açılış bitince açılış katmanı 0,35 sn ease-out ile söner. Altındaki ekran görünür hâle gelir.
4. Açılışla birlikte:
   - Ekran dışı altyazı penceresi (§11) ile yayın penceresi (§13) modele bağlanır.
   - Okuma motoru takılıp uygulamayı yeniden açtıysa çeviri kaldığı yerden sürer.
5. Kurulum bitmeden önce Ayarlar açılamaz.

### 1.3 Sayfalar (sheet)

Ana pencerenin üstünde açılan sayfalar. Hepsi uygulama zemini ve varsayılan yazıyla:

| Ne zaman | Sayfa |
|---|---|
| Uygulama menüsündeki Hakkında öğesi (`home.menu.about`) | Hakkında |
| Robot düğmesi | Nino'ya Sor (sohbet) |
| Başlıktaki dişli, ⌘, | Ayarlar (ilk bölüm) |
| Alt şeritteki Çeviri bağlantısı (`home.translation`) | Ayarlar, doğrudan Çeviri bölümü |
| Başlıktaki saat | Geçmiş |
| Xbox düğmesi | Xbox bağlantı yardımcısı |

### 1.4 Yüzen robot (`home.askNino`)

Pencerenin her yerinde, açılış animasyonu bitince görünür. Görünürken ölçek + opaklık geçişiyle gelir.

- **Yeri:**
  - Ana ekranda sol alt köşe: soldan 24, alttan 60. Sağ altta fiş ve kablo durduğu için sol tarafta.
  - Kurulumda sağ alt köşe: sağdan 24, alttan 96. Devam düğmesinin üstünde kalır.
- **Düğme:**
  - 60×60 daire, dolgusu beyaz %92, üstünde cam (etkileşimli), 1 pt cam kenarı.
  - Ortada robot yüzü 44 boyunda; hafifçe yukarı aşağı süzülür ve arada göz kırpar. Görseller tasarım dilinde.
    Yüzün kendi çizimi ve hareketi bu belgenin kapsamı dışında.
  - Gölge pro rengi %18, yarıçap 12, 6 aşağı. Üstüne gelince gölge %28 ve yarıçap 16 olur, düğme %105 büyür.
    Geçiş yay (0,3, 0,7).
  - Tıklayınca sohbet sayfası açılır. İpucu balonu ve ekran okuyucu etiketi `home.askNino` (Ask Nino / Nino'ya Sor).
- **Başlama balonu:**
  - Ana ekrandayken çeviri başlayınca robotun sağında (12 boşluk) belirir ve 7 sn kalır.
  - Metin: `home.startedBubble` (Nino ağzından çevirinin devreye girdiğini bildirip keyifli oyun dileyen kısa balon).
    17 pt kalın, beyaz.
  - Kutu: iç boşluk yatay 20, dikey 13. Kapsül, dolgu siyah %55, 1 pt beyaz %14 kenar. Kutu daralmaz.
  - Soldan kayarak ve belirerek gelir: yay (0,4, 0,8). 7 sn sonra 0,4 sn ease-out ile söner.
  - Çeviri durursa balon hemen 0,25 sn'de söner.

---

## 2. Menüler

### 2.1 Uygulama menüsü

- **Hakkında:** sistemin hazır Hakkında öğesinin yerine `home.menu.about` (About Nino / Türkçesi: uygulamanın tam adını taşıyan Hakkında öğesi) gelir.
  Hakkında sayfasını açar.
- **Ayarlar:** sistemin ayarlar öğesinin yerine `home.menu.settings` (Settings… / Ayarlar…) gelir. Kısayolu ⌘,. Kurulum bitmediyse
  devre dışıdır. Ayarlar sayfasını açar.

Başka menü değişikliği yok.

### 2.2 Menü çubuğu öğesi

- Simgesi `captions.bubble`, adı uygulamanın adıdır (Nino, çevrilmez).
- Menü çubuğunda yalnız iki koşul birlikteyse durur:
  - kurulum bitti,
  - altyazı bilgisayar ekranında da gösteriliyor.

  Böylece tıklamaların alttaki pencereye geçmesi ayarı açıkken uygulamaya geri dönülebilir.
- Menünün içi, sırasıyla:

1. Görüntü Capture Card'dan okunuyorsa:
   - Kartın durum metni, tıklanamaz satır olarak (bkz. §8.3).
   - Oyun bu bilgisayarda tüm ekranı kaplayarak oynanıyorsa (çeviri açık, kaynak Capture Card, altyazı bilgisayarda)
     `home.menu.gameFullScreen` (oyun görüntüsünü bu Mac'te ekranın tamamına yayan menü öğesi), kısayolu ⌃⌘F.
   - Ayırıcı çizgi.
2. Onay kutusu `home.menu.clickThrough` (Let clicks pass through / Tıklamalar geçsin). Ayardaki aynı değeri açar/kapatır.
3. `home.overlay.adjust` (İngilizcesi: altyazı penceresini düzenleme komutu / Altyazı penceresini ayarla). Ekran dışı altyazı penceresini ayar kipine sokar.
4. Ayırıcı.
5. `home.menu.openNino` (Open Nino / Nino'yu aç). Uygulamayı öne getirir.

---

## 3. Ana ekranın iskeleti

Ana ekranın iki arayüzü var. Seçim Ayarlar'da. Varsayılan **salon sahnesi** (§4). Diğeri **cam anahtar** (§5).
Her ikisinde de üstte başlık, altta ince şerit aynıdır.

Dikey yığın, aralıksız:

1. **Başlık** (§3.1): yatay iç boşluk 24, üstten 12.
2. **Geliştirici rozeti:** yalnız geliştiricinin kendi Mac'inde (yönetici kipi), kullanıcıda hiç görünmez.
   - Metin "Debug admin modu aktif", çevrilmez. Callout yarı kalın, beyaz.
   - Turuncu kapsül, iç boşluk yatay 10 dikey 3, üstten 6.
3. **Orta alan:** salon ya da cam anahtar. Kalan yüksekliğin tamamını kaplar.
4. **Alt şerit** (§6).

Ana ekran açık kaldıkça yarım saatte bir yeni sürüme bakılır. Denetimin kendisi en çok saatte bir ağa çıkar.

### 3.1 Başlık

Yatay sıra, aralık 8:

- **Logo**, 46 boyunda.
- **Ad ve sürüm**, dikey, sola yaslı, aralık 5:
  - Kelime işareti 24 boyunda, sola yaslı.
  - **Sürüm hapı:**
    - Metin uygulamanın kısa sürüm adı, ör. "V4.0", çevrilmez. 10 pt kalın yuvarlak, textSecondary.
    - İç boşluk yatay 7, dikey 2. Kapsül, dolgu textSecondary %12.
    - Üstüne gelince ipucu balonu tam sürümü gösterir, ör. "V4.0 (4.0.5)".
    - Ekran okuyucu `home.version %@` (Version %@ / Sürüm %@) okur, %@ tam sürümdür.
- Boşluk.
- **Geçmiş düğmesi:** yuvarlak simge düğmesi, `clock.arrow.circlepath`, adı `home.history` (History / Geçmiş). Geçmiş sayfasını
  açar.
- **Ayarlar düğmesi:** yuvarlak simge düğmesi, `gearshape.fill`, adı `home.settings` (Settings / Ayarlar). Ayarlar sayfasını açar.

---

## 4. Salon sahnesi (varsayılan arayüz)

### 4.1 Orta alanın düzeni

Dikey yığın, aralık 12. Yatay iç boşluk 24, dikey 12. Alanın tamamını kaplar. **Kaydırılmaz**: her şey pencereye
sığar, sahne kalan alana göre küçülür.

1. **Yeni sürüm şeridi:** yeni sürüm bulunduysa (§6.3).
2. **Sahne:** kalan bütün alanı alır (§4.2). Sahne içeride ortalanır ve her zaman soldan sağa çizilir.
3. **Fiş ipucu** sahnenin içinde, prizin üstünde (§4.9); ayrı satır yok.
4. **Xbox düğmesi:**
   - Koşul: Xbox penceresinden okunuyor ve Xbox bağlantısı tamamlanmamış.
   - Birincil düğme, büyük boy (44), en az 220 geniş, simgesi `gamecontroller.fill`.
   - Metin: yayın adımındaysa `home.xbox.start` (Start your Xbox / Xbox'ınızı açın), değilse `home.xbox.connect` (Connect your Xbox / Xbox'ı bağla).
   - Tıklayınca Xbox yardımcısı açılır.
5. **Altyazı penceresi ayar düğmesi** (`home.overlay.adjust`):
   - Koşul: altyazı bilgisayar ekranında da gösteriliyor.
   - Hayalet düğme. Ayar kipi zaten açıkken devre dışı.
6. **Uyarılar** (§8.2): en çok 640 geniş, aralık 12.

### 4.2 Sahnenin ölçeklenmesi

Sahne 1672×941'lik bir tuvalde, görselin piksel ölçüsüyle tasarlanır. Aşağıdaki bütün koordinatlar bu tuvalde, sol üst
köşe başlangıçtır.

- Ölçek = en küçüğü (1, ayrılan genişlik / 1672, ayrılan yükseklik / 941). Sahne küçülür ama hiç büyümez.
- Tuval bu ölçekle sol üstten küçültülür. Kapladığı alan 1672×ölçek, 941×ölçek olur. Bu alan ayrılan yere ortalanır.
- Sonra sehpanın ortası pencerenin ortasına gelsin diye yatayda kaydırılır. Görselde sağda priz ve konsol olduğu için
  sehpa biraz soldadır. Kayma miktarı (836 − sehpanın orta x'i) × ölçek:
  - PS5'te +36 × ölçek
  - Xbox'ta +3 × ölçek

### 4.3 İki düzen: PS5 ve Xbox

Ayarlardaki konsol seçimine göre sahne değişir. Görsel ve koordinatlar:

| | PS5 | Xbox |
|---|---|---|
| Görsel | `LivingRoom` | `LivingRoomXbox` (1671 geniş, 1672×941'e gerilir) |
| TV ekranı (içerik alanı) | x 149, y 40, 1151×595 | x 136, y 40, 1185×596 |
| TV çerçevesi (ışık için) | x 139, y 27, 1171×621 | x 121, y 26, 1214×630 |
| Sehpa | x 49, y 713, 1502×160 | x 43, y 733, 1580×167 |
| Priz merkezi | (1564, 378) | (1561, 381) |
| Kablonun başı | (1550, 734) | (1572, 722) |
| Görseldeki kablonun son parçası | (1490,706) → (1522,706) → (1535,709) → (1545,716) → (1552,727) | yok |
| Kablonun çıkış yönü (birim) | (0,5, 0,87) | (1, 0,1) |
| Fişin sarktığı yer (çıkıkken) | (1600, 885) | (1646, 912) |

Görselde sehpanın dışında kalan kablo ve fiş silinmiştir; onları uygulama çizer. Priz görselin parçasıdır.

> Not: konsol çizimi bir markanın tasarımına benzer; mağazaya gönderilmeden önce markasız bir çizimle değiştirilmelidir
> (bkz. CLAUDE.md, Marka).

### 4.4 Katmanlar (alttan üste)

1. **LED ışıkları** (§4.6): görselin arkasında, saydam kenarlarından taşar.
2. **Priz ışığı** (§4.7): görselin arkasında.
3. **Salon görseli:** tuvalin tamamı, 1672×941.
4. **Siyah zemin:** TV ekranı dikdörtgeninde düz siyah. Görseldeki ekran hiçbir anda, geçişlerde bile, görünmesin
   diye.
5. **TV ekranının içi** (§4.5):
   - İçerik 588 noktalık mantıksal bir TV'ye göre çizilir. Yüksekliği 588 × ekran yüksekliği / ekran genişliği: PS5'te
     ≈ 304, Xbox'ta ≈ 296.
   - Sonra ekran dikdörtgenine sol üstten büyütülür: PS5'te ×1,9575, Xbox'ta ×2,015. Böylece yazılar ekranla orantılı
     kalır.
   - Taşan kısım kesilir. Ekran dikdörtgeninin yerine oturtulur.
6. **Prizin tıklama alanı:** priz merkezinde 120×120 görünmez kare. Tıklayınca fiş takılır ya da çıkar.
7. **Kablo** (§4.8).
8. **Fiş** (§4.8).

**Sahnenin animasyonları:**

- Fişin takılıp çıkması, kablo ve fiş biçimi yay (0,5, 0,78) ile değişir.
- "Hareketi azalt" açıksa animasyon yok, hepsi hemen değişir.

**Ekran okuyucu:**

- Bütün sahne tek bir düğme olarak okunur.
- Etiketi fiş takılıyken `home.action.stop` (Stop translating / Çeviriyi durdur), değilken `home.action.start` (Start translating / Çeviriyi başlat).
- Eylemi fişi takıp çıkarmaktır.

### 4.5 Fiş durumu ve TV ekranının içi

**Fiş takılı mı:** çeviri açık ya da açılıyor ise takılıdır; değilse çıkıktır. Başlatma başarısız olursa fiş
kendiliğinden geri düşer.

**Açılış gösterisi:**

- Uygulama her açıldığında yalnız bir kez oynar. Ayarlardan dönünce yeniden oynamaz.
- Sahne ilk kez göründüğünde fiş, çeviri kendiliğinden başlamış olsa bile çıkık görünür.
- 0,9 sn sonra yay (0,55, 0,7) ile yaylanarak prize takılır. "Hareketi azalt" açıksa bekleme 0 ve animasyonsuz.
- Bu bekleme sırasında TV'deki indirme sayısı gizlidir. Fiş takılınca sayılarak çıkar.

**Her takışta** TV'de uygulamanın açılış animasyonu baştan oynar. İstisna: gösteri daha önce oynamışken ve çeviri
zaten açıkken sahneye geri dönülürse (ör. Ayarlar kapanınca) animasyon atlanır, doğrudan canlı ekran görünür.

TV ekranının içi üç hâlden biridir:

**a) Fiş çıkık: bekleme ekranı**

- Düz siyah.
- Ortada `home.tv.dragPlug` (fişi sürükleyip prize götürerek başlatmaya çağıran yazı):
  - 13 pt yarı kalın, tek aralıklı (monospaced), BÜYÜK HARF.
  - Harf aralığı 2. Metin Arap harfi içeriyorsa 0, çünkü aralık harflerin birleşmesini bozar.
  - Beyaz %40, ortalı, yatay iç boşluk 40.
- Sağ üst köşede, 18 iç boşlukla, indirme sayacı (§4.10). Yalnız sayı biliniyorsa ve açılış beklemesi bittiyse.

**b) Fiş yeni takıldı: açılış animasyonu**

- Uygulamanın açılış animasyonu (§7) 1040×586'lık bir pencere gibi çizilir. TV'nin mantıksal genişliğine küçültülür
  (588/1040 ≈ 0,565).
- TV'de hep **koyu tema** ile çizilir.
- Bitince 0,4 sn ease-out ile canlı ekrana geçer.

**c) Canlı ekran**

- **Zemin:** oyun fonu (§4.11).
- **İçerik:** 18 iç boşluklu dikey yığın.
  - **Üst satır:**
    - Solda CANLI rozeti: bayrak kırmızısı canlı nokta, 6 boşluk, `home.tv.live` (LIVE / CANLI). Yazı 11 pt kalın, harf aralığı
      1,2, beyaz. Rozet: yatay iç boşluk 10, yükseklik 24, kapsül, dolgu siyah %40.
    - Sağda indirme sayacı, sayma gösterisiyle (§4.10). Sayı biliniyorsa.
  - **Boşluk.**
  - **Alt satır** (alttan 8 boşluk), şu öncelikle:
    1. Görüntü akmıyorsa (bağlanıyor, bulunamadı, koptu): altyazı yerine PS5 durum metni (§8.3). 15 pt orta, beyaz %70,
       ortalı, alt satıra kayar.
    2. Görüntü akıyor ama henüz satır yoksa: `home.tv.waiting` (bir sonraki altyazı satırının beklendiğini söyleyen yazı). 15 pt
       orta, beyaz %55.
    3. Satır varsa: son Türkçe satır, seçili altyazı temasıyla (§12), yazı boyu 26, en çok 2 satır.
- **Geçiş:** gelen her satır bir öncekinin yerini belirerek alır, bu sırada 6 pt aşağıdan yukarı kayar. 0,3 sn ease-out.

### 4.6 LED ışıkları

TV'nin arkasından duvara vuran ışık ve sehpanın altındaki şerit. Dört katman, hepsi soldan sağa üç duraklı doğrusal
degrade ile boyanır. Katman ölçüleri TV çerçevesine ve sehpaya göre:

| Katman | Biçim | Ölçü ve yer | Bulanıklık | Renk |
|---|---|---|---|---|
| Geniş TV ışığı | yuvarlak dikdörtgen, köşe 30 | TV çerçevesinden her yana 20 büyük | 46 | geniş |
| Dar TV ışığı | yuvarlak dikdörtgen, köşe 10 | TV çerçevesinden her yana 5 büyük | 12 | dar |
| Sehpa ışığı | kapsül | genişlik sehpa − 60, yükseklik 40; sol kenar sehpa + 30, üst kenar sehpanın altı − 14 | 26 | geniş |
| Sehpa şeridi | kapsül | genişlik sehpa − 90, yükseklik 8; sol kenar sehpa + 45, üst kenar sehpanın altı − 4 | 4 | şerit |

Renkler:

| | Her zamanki (mavi) | Havuz öncelikli oyun tanınınca (GTA 6) |
|---|---|---|
| geniş | üç durak da (0.12, 0.36, 1.0) | pembe (1.0, 0.24, 0.62) → lila (0.74, 0.50, 0.96) → açık mavi (0.30, 0.78, 1.0) |
| dar | üç durak da (0.3, 0.55, 1.0) | (1.0, 0.52, 0.78) → (0.84, 0.70, 1.0) → (0.58, 0.88, 1.0) |
| şerit | üç durak da (0.45, 0.65, 1.0) | dar ile aynı |

Davranış:

- Işıklar yalnız fiş takılıyken yanar. Yanıp sönmeleri 0,8 sn ease-in-out.
- Mavi ile GTA renkleri arasındaki geçiş 1,2 sn ease-in-out. İki durumda da üç durak olduğu için renkler yumuşak akar.
- "Hareketi azalt" açıksa ikisi de anında değişir.
- Işıklar tıklamayı engellemez.

### 4.7 Priz ışığı

Fiş takılı değilken prizin kenarlarından taşan, yanıp sönen ışık. Fişin nereye takılacağı anlaşılsın diye. Görseldeki
prizin kenarı 86 pt.

- **Dış katman:** yuvarlak dikdörtgen, köşe 16 (sürekli), 112×112 (86 + 26). Renk (0.30, 0.66, 1.0), bulanıklık 18.
  Opaklık 0,3 ↔ 0,95.
- **İç katman:** yuvarlak dikdörtgen, köşe 12 (sürekli), 94×94 (86 + 8). Renk (0.62, 0.84, 1.0), bulanıklık 5.
  Opaklık 0,45 ↔ 1.
- İkisi de priz merkezinde.
- **Nabız:** 0,95 sn ease-in-out, gidip gelerek sonsuz. "Hareketi azalt" açıksa sabit olarak parlak hâlde (0,95 / 1)
  durur.
- Fiş takılınca 0,5 sn ease-in-out ile söner. Çıkınca aynı sürede geri gelir.
- Tıklamayı engellemez.

### 4.8 Kablo ve fiş

**Fişin yeri:**

- Fiş takılıysa priz merkezi, çıkıksa sarkma noktası.
- Sürüklenirken bu yere sürükleme miktarı eklenir.

**Fişin yönü (θ):**

- θ = 0'da metal uçlar aşağı bakar. Artı yön saat yönüdür.
- Dinlenirken fiş yerçekimiyle aşağı sarkar. Prize yaklaştıkça uçlar prize döner. Kural:
  - D0 = prizle sarkma noktası arası uzaklık. d = prizle fişin o anki yeri arası uzaklık.
  - D0 ≤ 120 ya da d ≤ 1 ise θ = 0.
  - t = (D0 − d) / (D0 − 120), 0–1 aralığına sıkıştırılır. Yumuşatılmış e = t² × (3 − 2t).
  - Prize bakan açı α: uçların θ kadar dönünce baktığı yön (−sin θ, cos θ) olduğuna göre, fişten prize giden vektörü
    gösteren açı. Yani α = atan2(−(priz.x − fiş.x), priz.y − fiş.y).
  - θ = e × α.
- Sonuç: prizden uzakta 0, prize 120 pt kalınca tam prize dönük.

**Kablo:**

- **Çizgi:** 8 kalın, uçları ve dönüşleri yuvarlak. Renk (0.06) gri, yani neredeyse siyah. Gölge siyah %25, yarıçap 3,
  2 aşağı.
- **Başlangıç:**
  - PS5'te görseldeki kablonun son parçasının ilk noktasından başlar ve o noktalardan düz çizgiyle geçer. Çizilen kablo
    görseldekinin üstüne biner, ek yeri görünmez.
  - Xbox'ta kablonun başından başlar. Orada küçük bir fiş başı çizilir: 14×12, köşe 3 (sürekli), renk (0.08) gri.
- S = son parçanın son noktası (Xbox'ta kablonun başı). Ç = çıkış yönü.
- **Fiş takılıyken (sürüklenmiyorsa):**
  - S'den, fişin 30 pt altına giden kübik eğri.
  - Birinci kontrol noktası S + 90 × Ç.
  - İkinci kontrol noktası bitişin 10 sağı, 170 altı.
  - Sonuç: kablo alttan prize kıvrılır.
- **Fiş çıkıkken ya da sürüklenirken:**
  - u = (−sin θ, cos θ), uçların yönü.
  - Kablo fişin arkasına girer: B = fişin yeri − 40 × u (gövdenin üstündeki kablo boğazı).
  - Sarkma = en büyüğü (0, 330 − |B − S|) × 0,45. Kablonun serbest boyu 330: fiş konsola yaklaştıkça artan boy kadar
    sarkar.
  - S'den B'ye kübik eğri.
  - Birinci kontrol noktası S + 70 × Ç, sarkma kadar aşağı.
  - İkinci kontrol noktası B − 80 × u, sarkma kadar aşağı.
- Kablo tıklamayı engellemez.

**Fişin görünüşü:**

- **Takılıyken (sürüklenmiyorsa):** prizin önünde yuvarlak kapak.
  - 58×58 daire. Dolgu sol üstten sağ alta (0.24) gri → (0.04) gri.
  - 1,5 pt beyaz %18 iç kenar.
  - Gölge siyah %45, yarıçap 6, 4 aşağı.
- **Çıkıkken / sürüklenirken:** dikey, aralıksız yığın; θ kadar kendi merkezi çevresinde döner.
  1. Boyun: 13×14, köşe 5 (sürekli), renk (0.06) gri.
  2. Gövde: 36×50, köşe 9 (sürekli). Dolgu soldan sağa (0.22) → (0.04) gri. 1 pt beyaz %14 iç kenar.
  3. Uçlar: yan yana iki kapsül, aralarında 14. Her biri 6×24, soldan sağa (0.92) → (0.60) gri, metal görünüm.
  4. Bütün fişin gölgesi siyah %30, yarıçap 4, 3 aşağı.
- Fiş boyu ne olursa olsun tıklama/sürükleme alanı fişin merkezinde 120×140'lık dikdörtgendir, kolay yakalansın diye.
- Sürüklenirken fiş %108 büyür.

**Etkileşim:**

- **Tıklama:** fişe tıklamak takar/çıkarır. Prize tıklamak da aynı işi yapar.
- **Sürükleme:**
  - En az 4 pt hareketle başlar. Fiş parmağı/fareyi izler.
  - Bırakınca bırakılan nokta (dinlenme yeri + sürükleme) prize 140 pt'den yakın mı diye bakılır.
  - Sürükleme yay (0,45, 0,75) ile sıfırlanır.
  - "Yakın mı" ile "takılı mı" farklıysa takma/çıkarma yapılır. Yani prize götürülen fiş takılır, prizden uzağa
    çekilen fiş çıkar.
- **İpucu balonu:** takılıyken `home.plug.unplugToStop` (Unplug to turn off subtitles / Altyazıyı kapatmak için fişi çıkarın),
  değilken `home.plug.plugInToStart` (Plug in to start / Başlatmak için fişi takın). Prizin üstündeki balon da aynı metinleri kullanır (§4.9).

**Takma/çıkarma kuralı** (cam anahtarda da aynısı):

1. Çeviri hâlâ hazırlanıyorsa (bir saniyeden kısa) tıklama kaybolmaz: hazırlık biter bitmez, çeviri açıldıysa
   durdurulur.
2. Çeviri açıksa durdurulur.
3. Çeviri başlatılabiliyorsa başlatılır.
4. Başlatılamıyorsa kurulum "konsol" adımından açılır.

### 4.9 Fiş ipucu (prizin üstünde)

Sahnenin içinde, prizin hemen üstünde küçük cam balon (callout, orta ağırlık, textPrimary, en çok 3 satır, ortalı;
iç boşluk yatay 12, dikey 7; köşe 12, sürekli) ve altında prizi gösteren ince aşağı ok (`arrow.down`, 14 pt yarı kalın,
accent). Ok ucu sahne ölçeğiyle prize bağlıdır
(`LivingRoomGeometry.plugHintPlacement`): prizin kapağının hemen üstü. Balonun yazısı ölçeklenmez; balon TV
çerçevesinin sağ kenarını ve pencereyi aşmaz, sağa yaslanır. Sahne soldan sağa çizildiği için Arapçada da sağdadır;
yalnız metin arayüz dilinin yönünde yazılır. Sürüklerken ve açılış gösterisinde gizlenir, tıklamayı engellemez.
Metin, ilk uyan:

1. Çeviri açık ve fiş takılıysa: `home.plug.unplugToStop` (Altyazıyı kapatmak için fişi çıkarın); ok takılı fişi gösterir.
2. Çeviri kapalı ve başlatılabiliyorsa: `home.plug.plugInToStart` (Başlatmak için fişi takın); ok parlayan prizi gösterir.
3. Konsol Xbox ise: `home.hint.connectTVFirst`; ok prizi gösterir.
4. Değilse: `home.hint.connectPS5First`; ok prizi gösterir.

Ekran okuyucu ipucunu sahnenin ipucu (hint) olarak okur.

### 4.10 İndirme sayacı

TV'nin sağ üst köşesindeki toplam indirme göstergesi. Oyunlardaki para göstergesine benzer: kalın, hafif eğik, siyah
çerçeveli.

**Görünüş:** dikey yığın, sağa yaslı, aralık 1.

- **Başlık:** `home.tv.totalDownloads` (Total downloads / Toplam indirme), BÜYÜK HARF.
  - "Impact" 11 pt, en kalın ağırlık. Yoksa sistemin en kalın yazısı.
  - Beyaz. Harf aralığı 0,8 (Arap harfinde 0).
- **Sayı:**
  - "Impact" 27 pt, rengi indirme yeşili (0.48, 0.91, 0.48).
  - Rakamlar sabit genişlikte, binlik ayırıcılı (dilin biçimiyle).
- **Siyah çerçeve:** yazının dört yanına (sağ, sol, alt, üst) w kadar kaydırılmış keskin (bulanıksız) siyah gölgeler,
  artı w + 1 aşağıda siyah %90 keskin bir derinlik gölgesi. Başlıkta w = 1, sayıda w = 1,5.
- **Eğim:** bütün gösterge yatayda eğilir. Her noktanın x'i, y × (−0,12) + 3 kadar kayar. Arap harfli metinde eğim yok.
- Gösterge daralmaz. Ekran okuyucu tek parça okur.

**Sayma gösterisi:** yalnız canlı ekranda; yani fiş takılıp TV'deki açılış animasyonu bitince, canlı ekran ilk göründüğünde başlar. Koşul: "hareketi azalt" kapalı ve sayı 3'ten büyük. Koşul
tutmazsa sayı doğrudan görünür.

1. 1, 2, 3 tek tek görünür, her biri 280 ms.
2. Sonra 1,55 sn boyunca saniyede ~60 kez güncellenir. İlerleme p (0→1) için gösterilen = en büyüğü (3, yuvarla(p^2,6
   × toplam)). Yavaş başlar, hızlanıp toplam sayıya fırlar.
3. Sonda toplam gösterilir ve "vuruş" yapılır:
   - Sayı sağ kenarından ×1,32 büyür. Yeşil %95 ışık yayar, yarıçap 14. Yay (0,22, 0,45).
   - 260 ms sonra yay (0,45, 0,6) ile yerine oturur, ışık söner.

**Sayının kaynağı:**

- Sunucudan okunur. Sahne açıkken en çok 10 dk'da bir yenilenir.
- Alınamazsa son bilinen sayı (kalıcı saklanır) gösterilir.
- Hiç alınamadıysa sayaç hiç görünmez.
- Sayı olduğu gibi gösterilir, üstüne ekleme yapılmaz.

### 4.11 Oyun fonu (canlı TV ekranının zemini)

1. Kullanıcı tanınan oyun için kendi görselini koyduysa o görsel kullanılır:
   - Görsel alanı doldurur, taşan kesilir.
   - 14 bulanıklık; bulanıklık kenarlarda saydamlaşmaz.
   - Üstünde siyah %36.
   - Görselin yeri: uygulama destek klasöründe "Covers" altında, `<oyun-kimliği>.png`. jpg, jpeg, heic, webp de olur.
     GTA 6 için `gta-6` adı da kabul edilir.
   - Görsel değişirse yeniden okunur. Görsel bu Mac'ten çıkmaz.
2. Yoksa ve oyun havuz öncelikliyse (GTA 6), Nino'nun gün batımı fonu:
   - Yukarıdan aşağı dört duraklı degrade, üstünde siyah %28. Güneş ya da ayrı katman yok.
   - Duraklar: 0'da (0.10, 0.08, 0.34), 0,40'ta (0.46, 0.16, 0.62), 0,74'te (0.93, 0.29, 0.60), 1'de (1.00, 0.55,
     0.48).
   - Oyunun logosu ya da görseli dağıtılmaz.
3. Hiçbiri değilse sol üstten sağ alta (0.09, 0.12, 0.24) → (0.15, 0.09, 0.18).

---

## 5. Cam anahtar (ikinci arayüz)

### 5.1 Orta alanın düzeni

- Kaydırılabilir alan; kaydırma çubuğu gizli. İçerik en az görünen alan kadar yüksek, yatay iç boşluk 24.
- Dikey yığın, aralık 16:
  1. Yeni sürüm şeridi (varsa).
  2. Esnek boşluk.
  3. **Anahtar bloğu**, tam genişlik, ortalı. Dikey yığın; aralık çeviri açıkken 20, kapalıyken 28.
     - Çeviri açıkken: **canlı TV** (§5.4). Yukarıdan kayarak, belirerek ve %94'ten büyüyerek gelir. Kalkarken tersi.
     - **Cam anahtar** (§5.2), her zaman soldan sağa çizilir.
     - Çeviri kapalıyken: açıklama `home.switch.description` (konsoldaki İngilizce altyazının okunup TV'de Türkçeye çevrilmiş hâlde gösterildiğini anlatan tek cümle).
       Callout, textSecondary, ortalı, en çok 420 geniş.
     - Dikey iç boşluk: açıkken 12, kapalıyken 40.
     - Çeviri açılıp kapanınca blok yay (0,6, 0,86) ile yeniden dizilir.
     - Arkasında **ışık halesi**:
       - 520×520 daire, 90 bulanık.
       - Açıkken bayrak kırmızısı %22, kapalıyken accent %10. Renk 0,6 sn ease-in-out ile değişir.
       - Tıklamayı engellemez.
  4. Xbox düğmesi (salondaki gibi).
  5. Altyazı penceresi ayar düğmesi (`home.overlay.adjust`), hayalet (salondaki gibi).
  6. Uyarılar, en çok 640 geniş.
  7. Esnek boşluk.

Böylece pencere ne boyda olursa olsun anahtar dikeyde ortada durur.

### 5.2 Cam anahtar

Hap biçimli iz ve üstünde kayan cam bir küre. Kapalıyken küre solda ve iz soğuk mavi-gri. Açınca küre sağa kayar, iz
bayrak kırmızısına döner, kürenin içinde ay yıldız belirir.

**Ölçüler:**

- İz 400×92 (tam kapsül).
- Küre 116×116. İzden büyüktür, iki uçta izin dışına 12'şer pt taşar (cam baloncuk görünümü).
- Yol = 400 − 92 = 308.

**Kürenin yeri:**

- Temel konum: açıksa 308, kapalıysa 0. Sürüklenirken buna yatay sürükleme eklenir, 0–308 aralığına sıkıştırılır.
- İlerleme p = konum / 308.
- Bütün renkler ve yazılar p'ye göre karışır.
- Küre izin sol kenarından konum − 12 kadar sağda, dikeyde ortalı.

**İz (alttan üste):**

1. Kapsül, yukarıdan aşağı (0.47, 0.55, 0.70) → (0.30, 0.36, 0.52).
2. Kapsül, yukarıdan aşağı bayrak kırmızısı → koyu bayrak kırmızısı, opaklık p.
3. Camın üst parlaklığı: her yandan 3 içeride kapsül. Yukarıdan ortaya kadar beyaz %35 → beyaz %0.
4. 1 pt beyaz %45 iç kenar.
5. Gölge:
   - Rengi p > 0,5 iken bayrak kırmızısı, değilse (0.30, 0.36, 0.52).
   - Opaklık 0,25 + 0,35 × p. Yarıçap 22, 10 aşağı.

**Yazılar** (beyaz, tıklamayı engellemez):

- **Kapalı yazı:** sağa yaslı, sağdan 30 içeride. Dikey, sağa yaslı, aralık 2. Opaklık 1 − p.
  - Başlık 22 pt yarı kalın yuvarlak, ilk uyan:
    1. hazırlanıyorsa `home.status.connecting` (Connecting… / Bağlanıyor…)
    2. başlatılamıyorsa `home.switch.connectPS5` (Connect your PS5 / PS5'inizi bağlayın)
    3. değilse `home.switch.turnOn` (Turn on / Aç)
  - Alt satır 12 pt orta, %80 opak: başlatılabiliyor ya da hazırlanıyorsa `home.switch.subtitles` (Turkish subtitles / Türkçe altyazı),
    değilse `home.switch.tapToSetUp` (Tap to start the setup / Türkçesi: dokununca kurulumun başlayacağını söyler).
- **Açık yazı:** sola yaslı, soldan 34 içeride. Dikey, sola yaslı, aralık 2. Opaklık p.
  - `home.switch.onTitle` (Turkish / Türkçe), 26 pt kalın yuvarlak.
  - `home.switch.onSubtitle` (Subtitles on / Altyazı açık), 12 pt orta, %85 opak.

**Küre (alttan üste),** k = 116, iç disk çapı i = 0,62 × k ≈ 72:

1. İç disk: i çaplı daire. Altta (0.36, 0.43, 0.60) gri-mavi, üstünde bayrak kırmızısı (opaklık p).
2. Hazırlanırken: ortada beyaz, normal boy dönen bekleme göstergesi. Simgeler çizilmez.
3. Hazırlanmıyorken iki simge:
   - `power` simgesi: i × 0,42 ≈ 30 pt kalın, beyaz, opaklık 1 − p.
   - Ay yıldız (aşağıda): i × 0,72 ≈ 52 kare, opaklık p, ölçek 0,7 + 0,3 × p.
4. Cam dolgu: k çaplı daire, en ince buzlu malzeme, %35 opak.
5. Cam kenarı: 2 pt iç kenar. Sol üstten sağ alta beyaz %95 → %15 → %60.
6. Parlama: elips, 0,55k × 0,28k (≈ 64 × 32,5).
   - Yukarıdan aşağı beyaz %65 → %0.
   - Merkezi küre merkezinden (−0,12k, −0,28k) ≈ (−14, −32,5) kayık. 2 bulanık.
7. Bütün küre tek katman olarak birleştirilir. Gölgesi siyah %18, yarıçap 14, 8 aşağı.

**Ay yıldız** (kenarı s olan kare içinde, r = 0,42 s):

- Beyaz daire, çapı 2r, merkezi (0,42 s, s/2).
- Oyuk: çapı 1,6 r, merkezi (0,42 s + 0,32 r, s/2). Bayrak kırmızısıyla boyanır, beyaz daireden hilal oyar.
- Yıldız: beyaz, beş köşeli, s × 0,34 kare içinde, merkezi (0,8 s, s/2).
  - İç yarıçap dış yarıçapın 0,382 katı.
  - İlk ucu sola, aya bakar (açı π). Uçlar ve iç köşeler π/5 aralıkla sırayla dizilir.

**Etkileşim:**

- Küreye üstüne gelince %104 büyür, yay (0,3, varsayılan sönüm).
- Küre en az 2 pt hareketle sürüklenir. Bırakınca:
  - Bitiş = temel konum + sürükleme.
  - Kapalıyken bitiş > yolun %60'ı ise açar. Açıkken bitiş < yolun %40'ı ise kapatır.
  - Sürükleme yay (0,45, 0,78) ile sıfırlanır.
- Küreye ya da ize (kapsül alanı) tıklamak takma/çıkarma kuralıyla aynı işi yapar (§4.8).
- Açılıp kapanma yay (0,55, 0,8).
- Bütün anahtar yalnız "başlatılabilir ama hazırlanıyor" durumunda %60 opak, diğer durumlarda %100.
- Ekran okuyucu tek düğme olarak okur: `home.action.stop` / `home.action.start` (§4.4).

### 5.3 Eski sol sütun (alınmaz)

Eski kodda bu arayüz için bir sol sütun (Başlat/Durdur düğmesi, durum karoları, canlı altyazı karosu, satır geçmişi,
oyun paketlerinin açık olduğunu bildiren karo) duruyordu. Hiçbir ekranda kullanılmıyor; yeni uygulamaya alınmaz.

### 5.4 Canlı TV (anahtarın üstünde)

Genişlik 580, ekran yüksekliği 580 × 9/16 = 326,25. Dikey yığın, aralıksız:

1. **TV:**
   - **Çerçeve:** 580×326,25, köşe 18 (sürekli), renk (0.05, 0.05, 0.07).
   - **Ekran:** çerçeveden 7 içeride, köşe 12 (sürekli).
     - Sol üstten sağ alta (0.10, 0.13, 0.24) → (0.16, 0.10, 0.20).
     - Üstünde sağ alttan yayılan dairesel degrade: bayrak kırmızısı %18 → saydam. Başlangıç yarıçapı 10, bitiş 348.
       Ekranın köşelerine kırpılır.
   - **İçerik:** 20 iç boşluk.
     - Sol üstte CANLI rozeti (salondaki gibi).
     - Altta, alttan 10 boşlukla, ya bekleme yazısı `home.tv.waiting` (15 pt orta, beyaz %55) ya da son satır, seçili
       temayla, yazı boyu 27.
     - Yeni satır geçişi salondaki gibi (belirerek, 6 pt kayarak, 0,3 sn).
   - Gölge siyah %28, yarıçap 24, 14 aşağı.
2. **Ayak boynu:** 34×14, köşe 2, renk (0.12, 0.12, 0.15).
3. **Ayak tabanı:** kapsül 150×6, aynı renk.
4. **İngilizce aslı:**
   - Callout, eğik, textSecondary. Tek satır, en çok 580 geniş, üstten 10.
   - Satır yoksa tek boşluk yazılır; yükseklik değişmesin.

Ekran okuyucu bütününü tek parça okur.

---

## 6. Alt şerit

Pencerenin en altında, iki arayüzde de aynı. Kutusuz, tek satır.

- Üstte tam genişlikte 1 pt cam kenarı renginde çizgi.
- Altında 44 yüksek satır, yatay iç boşluk 24. Üç bölge, aralık 16; hiçbir öge ötekinin üstüne binmez:
  1. **Sol bölge** (esnek, başa yaslı; aralık 22): görüntü kaynağı durumu (§6.1) ve, yalnız altyazı TV'ye
     gidiyorsa, TV durumu (§6.1).
  2. **Orta bölge** (en çok 300): güncelleme durumu (§6.3).
  3. **Sağ bölge** (esnek, sona yaslı): çeviri bağlantısı (§6.2).
- Sol ve sağ bölge eşit esner, orta bölge tam ortada kalır. Bütün metinler tek satır; sığmayan sondan kesilir.
- Şeritte yalnız **kısa durum** yazar (ör. PS5 Bulunamadı, PS5 Uykuda, TV Bekleniyor). Uzun açıklama fareyle
  gelince ipucu olarak çıkar ve TV sahnesinde yazar.

### 6.1 Durum öğeleri

Yatay sıra, aralık 7, yazı caption:

- 7×7 durum noktası (ton tasarım dili §8.8'deki kurallarla).
- Başlık: yarı kalın, textPrimary.
- Değer: textSecondary, tek satır.

**Görüntü kaynağı öğesi:**

- Başlık:
  - Oyun penceresinden okunuyorsa `home.source.gameWindow` (Game window / Oyun penceresi)
  - Capture Card'dansa `home.source.captureCard` (Capture card / Capture Card)
  - Değilse PS5, çevrilmez.
- Değer: PS5 yolunda, çeviri kapalıyken ve eşleşmiş bir PS5 varsa `home.source.ready %@` (%@ · ready / %@ · hazır), %@ PS5'in adıdır.
  Ad boşsa PS5. Diğer durumlarda kısa etiket (`HomeStatus.sourceShortKey`): bağlı, bağlanıyor, bağlı değil, eşli,
  ve her kopma nedeni için bir `home.short.*` (bulunamadı, yanıt yok, uykuda, başka cihazda, yeniden eşleyin, şifre
  gerekli/yanlış, Remote Play kapalı, görüntü yok, oturum açılmadı, ağ izni yok); pencere/kart için bekliyor, aranıyor,
  izin gerekli, Remote Play yok, kart yok, ekran karanlık, "%@ okunuyor".
- İpucu (fareyle): görüntü kaynağının uzun durum metni (§8.3).

**TV öğesi:**

- TV kuruluysa başlık TV (çevrilmez), değer:
  - en az bir TV uygulaması bağlıysa `home.status.connected` (Connected / Bağlı)
  - değilse kısa `home.short.tvWaiting` (Bekleniyor); ipucu `home.tv.waitingApp`
- TV kurulu değilse öğe düz (kenarsız) bir düğmedir:
  - Uyarı tonlu nokta, başlık TV, değer kısa `home.short.tvSetUp` (Bağlayın) ve ardından ` ›`; ipucu `home.tv.connect`.
  - Tıklayınca kurulum TV adımından açılır.

### 6.2 Çeviri bağlantısı

Düz düğme, yatay sıra, aralık 5, caption:

- `home.translation` (Translation / Çeviri), textSecondary.
- Değer, yarı kalın, textPrimary, tek satır:
  İlk uyan:
  1. Havuz öncelikli oyun tanındıysa ve Nino'nun kendi çevirisi o dilde geçerliyse (Türkçe) `home.translation.poolGame %@`
     (Nino · %@ active / Nino · %@ Aktif), %@ oyunun adıdır (ör. "Çeviri  Nino · GTA 6 Aktif"). Kullanıcının kendi motoru
     seçili olsa bile önce gelir. Oyun henüz tanınmadıysa son oynanan oyunun durumu kalır.
  2. Kullanıcı kendi çevrimiçi motorunu seçtiyse motorun adı (DeepL, Gemini, ChatGPT, Claude, Ollama).
  3. Nino'nun kendi çevirisi ve tanınan bir oyun varsa yine `home.translation.poolGame %@`.
  4. Değilse yalnız "Nino" (marka, çevrilmez).
  - "Ücretsiz/Free" ya da "Premium" gibi bir sıfat hiçbir dilde yazılmaz. Arapça ve Urducada metin sağdan sola işaretiyle
    başlar ve oyun adı yalıtılır; "Nino · GTA 6" doğru sırada okunur.
- `chevron.right`, 9 pt yarı kalın, textSecondary, önünde 1 boşluk.

Tıklayınca Ayarlar doğrudan Çeviri bölümünde açılır. Oyun değişince değer kendiliğinden güncellenir.

### 6.3 Güncelleme durumu ve yeni sürüm şeridi

**Ortadaki güncelleme durumu**, ilk uyan:

1. **İndirildi, kurulmaya hazır:** hap `home.update.readyRestart` (güncellemenin indiğini söyleyip yeniden başlatmayı öneren hap), simgesi
   `arrow.clockwise.circle.fill`. Tıklayınca kurulur ve Nino yeniden açılır. Çeviri sürüyorsa açılınca kendiliğinden
   sürer.
2. **Yeni sürüm iniyor:** mini dönen gösterge + 6 boşluk + `home.update.downloading %@` (Downloading %@… / %@ indiriliyor…). Caption,
   textSecondary, tek satır.
3. **Yeni sürüm var, inmiyor:** hap `home.update.newVersion %@` (yeni sürüm numarasını gösterip güncellemeye çağıran hap), simgesi
   `arrow.down.circle.fill`.
4. **Hiçbiri:** durum yazısı + yenile düğmesi, aralık 6.
   - Yazı: caption, textSecondary, tek satır.
     - Denetleniyorsa `home.update.checking` (Checking… / Denetleniyor…).
     - Güncelse `home.update.upToDate` (Up to date / Güncel), önünde `checkmark.circle` (10 pt kalın, aralık 5).
     - Değilse `home.update.check` (Check for updates / Türkçesi: güncelleme olup olmadığına bakma çağrısı).
   - Yenile düğmesi:
     - 22×22 daire, dolgu textSecondary %10 (üstüne gelince %18).
     - İçinde `arrow.clockwise` 10 pt kalın; rengi textSecondary, üstüne gelince textPrimary.
     - Denetlerken 0,9 sn'de bir doğrusal olarak sonsuz döner ve devre dışı kalır.
     - İpucu ve ekran okuyucu: `home.update.check`. Tıklayınca hemen yeniden denetler.

**Hap:**

- Simge 11 pt kalın + 5 boşluk + yazı. Caption yarı kalın, beyaz.
- İç boşluk yatay 12, dikey 5. Kapsül, dolgu accent.

Uygulama boştayken yeni sürüm sorulmadan iner ve kurulur.

**Yeni sürüm şeridi** (orta alanın en üstünde, yeni sürüm bulunduysa):

- Yatay sıra, aralık 12, iç boşluk 12, en çok 640 geniş.
- Cam zemin, köşe 22 (sürekli).
- İçerik:
  - `arrow.down.circle.fill`, 22 pt, accent.
  - Dikey, sola yaslı, aralık 2: `home.update.bannerTitle` (Nino'nun yeni sürümünün geldiğini duyurur) (callout yarı kalın) ve altında
    uygulamanın adı ile sürümü, ör. Nino 4.0.5 (caption, textSecondary; çevrilmez).
  - Boşluk.
  - Birincil düğme `home.update.download` (Download / İndir).

---

## 7. Açılış animasyonu

Uygulama açılırken pencerenin tamamında ve salondaki TV'de (fiş takılınca, küçültülmüş ve koyu temada) aynı animasyon
oynar.

**Katmanlar:**

- Zemin: uygulama zemini (tasarım dili §7).
- Ortada dikey yığın, aralık 28.

**Logo bloğu** (üst üste, ortalı):

1. **Dönen halka:**
   - 290×290 dairenin 3 pt iç kenarı.
   - Rengi açısal degrade: saydam → accent → accentHi → saydam → saydam. Yani halkanın yalnız bir parçası parlar.
   - 1,5 bulanık. Logo gelince görünür.
   - 2,4 sn'de bir doğrusal, sonsuz tam tur döner.
2. **Işık:** 220×220 daire, accent %25, 60 bulanık. Ölçek 0,4 → 1.
3. **Logo:** 200 boyunda.
   - Ölçek 0,72 → 1, bulanıklık 14 → 0, opaklık 0 → 1.
   - Üstünde bayrak parıltısı (aşağıda).

**Yazı bloğu,** dikey, aralık 6:

- Kelime işareti 34.
- `home.splash.tagline` (Your games, now in Turkish. / Türkçesi: oyunların artık Türkçe olduğunu söyleyen slogan), body, textSecondary.
- Opaklık 0 → 1, 12 pt aşağıdan yerine kayar.

**Zaman çizelgesi:**

1. 0 ms: logo yay (0,9, 0,72) ile gelir, halka dönmeye başlar.
2. 650 ms:
   - Yazı 0,6 sn ease-out ile gelir.
   - Bayrak ışığı 0,55 sn ease-in-out adımlarla yanar, söner, yeniden yanar (üç adım) ve sönüşe kadar yanık kalır.
   - 0,15 sn gecikmeyle 0,9 sn ease-in-out boyunca parıltı bayrağın üstünden geçer.
3. 2350 ms (önceki adımdan 1700 ms sonra): bütün yığın 0,45 sn ease-in ile %106'ya büyüyerek söner.
4. 2800 ms: animasyon biter.
- **"Hareketi azalt" açıksa:** logo ve yazı hemen görünür, 900 ms sonra biter.

**Bayrak parıltısı:**

Logodaki bayrağın üstünde durur. Bayrak 1254'lük görselde yaklaşık x 470–780, y 235–345. Logo 200 boyda ve görsel
1,21 kat çizildiği için ölçek ≈ 0,193. Buna göre:

- Bayrak alanı ≈ 59,8 × 21,2.
- Logo merkezinden ≈ 65 yukarıda.

İki katman:

- **Kırmızı ışık:**
  - Bayrak alanının 1,15 × 1,3 katı yuvarlak dikdörtgen, köşe 8 (sürekli).
  - Renk (0.95, 0.12, 0.16), 18 bulanık, ekran (screen) karışımıyla.
  - Opaklık 0 ↔ 0,85.
- **Parıltı:**
  - Bayrak alanı yüksekliğinde, genişliğinin %35'i kadar yuvarlak dikdörtgen, köşe 6.
  - Soldan sağa saydam → beyaz %75 → saydam, artı-aydınlatma (plus lighter) karışımıyla.
  - Bayrak genişliğinin −0,75 katından +0,75 katına kayar. Kayarken opaklığı 1 → 0.
  - Bayrak alanına kırpılır (köşe 6).
- Tıklamayı engellemez.

---

## 8. Ana ekranın okuduğu durumlar

Ana ekran kendi başına iş yapmaz. Uygulama modelinden şu durumları okur, şu eylemleri çağırır:

### 8.1 Okunan durumlar

| Durum | Ne için |
|---|---|
| Kurulum adımı (karşılama, ikinci hesap, PSN girişi, konsol, TV, deneme, daha iyi çeviri, bitti) | Kurulum mu ana ekran mı; "bitti" değilse Ayarlar kapalı; fiş/anahtar başlatamazsa "konsol" adımına, TV öğesi "TV" adımına gönderir |
| Çeviri açık mı | Fiş/anahtar, CANLI ekran, robot balonu, ışıklar, ton kuralları |
| Çeviri açılıyor mu (hazırlanıyor) | Fiş takılı sayılır; anahtarda `home.status.connecting` ve bekleme göstergesi |
| Başlatılabilir mi | Görüntü kaynağı hazır ve altyazının gideceği yer var mı (aşağıda) |
| Oturum durumu (akıyor / bağlanıyor / koptu + neden) | PS5 durum metni ve tonu; TV'de altyazı mı durum mu |
| Eşleşmiş PS5 (adıyla) | `home.source.ready %@` |
| Bağlı TV uygulaması sayısı | TV öğesi ve tonu |
| TV kurulu mu (eşleşmiş ve anahtarı saklı) | TV öğesi bağlı/bekleniyor değerini mi (`home.status.connected` / `home.tv.waitingApp`), `home.tv.connect` düğmesini mi gösterir |
| Konsol (PS5 / Xbox) | Sahne görseli ve koordinatları, ipucu metni |
| Görüntü kaynağı (PS5 / oyun penceresi / Capture Card) | Durum başlığı ve metni, menü çubuğu |
| Altyazının yeri (TV / Bilgisayar / İkisi de) | TV öğesi, altyazı penceresi ayar düğmesi (`home.overlay.adjust`), menü çubuğu |
| Son Türkçe satır, son İngilizce aslı | TV'deki satır, canlı TV'nin altındaki aslı |
| Seçili altyazı stili | TV'deki satırın teması ve yazı tipi |
| Tanınan oyun ve havuz öncelikli mi | Oyun fonu, ışık renkleri, `home.translation.poolGame %@` |
| Seçili çeviri motoru | Alt şeritteki değer |
| Çevirmen durumu (hazır / dil paketi eksik / desteklenmiyor) ve çevrimiçi çeviri açık mı | Uyarılar |
| Yerel ağ izni verilmemiş görünüyor mu (yalnız çeviri açıkken) | Uyarı ve PS5 durum metni |
| Çevrimiçi motorun sorunu | Uyarı |
| Yazı okunamadı + diskteki boş alan | Uyarı |
| Ekran dışı pencere ayar kipinde mi | Düğmenin devre dışı olması |
| Xbox bağlantı adımı | Xbox düğmesi |
| Uygulama görünümü, çeviri dili | Tema, arayüz dili ve yönü |
| Arayüz seçimi (salon / anahtar) | Orta alan |
| Güncelleme durumu | Şerit ve alt şeridin ortası |
| Toplam indirme sayısı | Sayaç |

**"Başlatılabilir" kuralı:**

- Görüntü PS Remote Play penceresinden (PS5) okunuyorsa her zaman evet.
- Değilse iki koşul birlikte aranır:
  - Görüntü kaynağı hazır olmalı: Xbox penceresi, Capture Card, ya da eşleşmiş PS5 ve hesap kimliği.
  - Altyazının gideceği bir yer olmalı: bilgisayar ekranı seçili ya da TV kurulu.

**"Altyazı bilgisayarda" kuralı:** PS oyun penceresinden okunuyorsa her zaman evet; değilse seçim Bilgisayar ya da
İkisi de ise evet.

**"Altyazı TV'de" kuralı:** PS oyun penceresinden okunuyorsa hayır, çünkü oyun bu bilgisayarda oynanır. Xbox penceresi
ve diğer kaynaklarda seçim TV ya da İkisi de ise evet.

### 8.2 Uyarılar

Kartlar, alt alta, aralık 12, en çok 640 geniş. Başlık satırları body yarı kalın, warning rengi, simgeli.

1. **Çevirmen hazır değil** ve şu iki durumdan biri değilse: dil desteklenmiyor ama çevrimiçi çeviri açık.
   - **Dil paketi eksikse:**
     - Simge `arrow.down.circle`. Başlık `home.warning.languagePack %@ %@` (The %1$@–%2$@ language pack hasn't been downloaded yet. / Türkçesi: iki dilin (kaynak–hedef) dil paketinin daha inmediğini söyleyen başlık);
       yer tutucular kaynak ve hedef dilin adları, arayüz dilinde.
     - İpucu: `home.warning.languagePackHint` (kaynak ve hedef dilin ikisinin de macOS'un Çeviri Dilleri ayarından indirilmesini isteyen ipucu).
     - İkincil düğme `home.warning.openLanguageRegion` (sistemin Dil ve Bölge ayarını açan düğme), sistemin Dil ve Bölge sayfasını açar.
   - **Dil desteklenmiyorsa:**
     - Simge `exclamationmark.triangle`. Başlık `home.warning.unsupported %@ %@` (This Mac can't translate from %1$@ to %2$@. / Bu Mac'te %1$@ dilinden %2$@ diline çeviri yapılamıyor.).
     - İpucu:
       - Sistemin çeviricisi hiç yoksa (macOS 26 öncesi): `home.warning.needsMacOS26` (Apple'ın bedava çevirisinin macOS 26 istediğini; oyun paketlerinin, DeepL'in ve Ayarlar › Çeviri'deki yapay zekâ çevirisinin bu Mac'te yine işlediğini anlatır).
       - Varsa: `home.warning.unsupportedHint` (Apple çevirisinin bu dili şimdilik desteklemediğini söyler; Ayarlar › Çeviri'de yapay zekâ çevirisini açmayı önerir ve Gemini'nin bedava olduğunu ekler).
2. **Çeviri açık ve yerel ağ izni verilmemiş görünüyor:**
   - Kartta `exclamationmark.triangle.fill` + metin (callout yarı kalın, warning). Metin:
     `home.warning.localNetwork` (Nino'nun yerel ağa erişemiyor olabileceğini söyler; macOS gizlilik ayarlarındaki Yerel Ağ bölümünden izni açıp Nino'yu kapatıp açmayı ister).
   - Altında ikincil düğme `home.warning.openSystemSettings` (Go to System Settings / Sistem Ayarları'na git), Yerel Ağ sayfasını açar. Aralık 8.
3. **Çeviri açık ve çevrimiçi motor çeviremiyor:**
   - Simge `exclamationmark.triangle`. Başlık `home.warning.engineDown %@` (%@ isn't translating right now / %@ şu an çevirmiyor), %@ motorun adıdır.
   - Altında sorunun açıklaması + bir boşluk + `home.warning.freeMeanwhile` (bu arada Nino'nun kendi çevirisinin devreye girdiğini söyler; "ücretsiz" demez) (callout, textSecondary). Açıklama
     metinleri Ayarlar › Çeviri belgesinde.
4. **macOS yazıyı okuyamadı:**
   - Simge `exclamationmark.triangle`. Başlık `home.warning.cantRead` (macOS'un ekrandaki yazıyı tanıyamadığını bildiren başlık).
   - İpucu:
     - Boş alan 10 GB'tan azsa: `home.warning.diskFull %.1f` (diskin dolmak üzere olduğunu, boş kalan GB'ı %.1f ile verir; macOS'un yazı okuyabilmek için yere gereksindiğini, birkaç GB boşaltıp çeviriye yeniden başlamayı söyler).
     - Değilse: `home.warning.restartMac` (bilgisayarı kapatıp açtıktan sonra çeviriye yeniden başlamayı söyler).

### 8.3 Görüntü kaynağının durum metni

**PS5'e doğrudan bağlanırken:**

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| Akıyor | `home.status.connected` | Connected | Bağlı |
| Bağlanıyor (yerel ağ izni kapalıysa ve çeviri açıksa yerine yerel ağ uyarısı `home.warning.localNetwork`) | `home.status.connecting` | Connecting… | Bağlanıyor… |
| Kapalı, çeviri kapalı, PS5 eşleşmemiş | `home.status.notConnected` | Not connected | Bağlı değil |
| Kapalı, çeviri kapalı, eşleşmiş (%@ = PS5'in adı) | `home.status.paired %@` | *%@ adlı PS5 ile eşleşildiğini, bağlantının çeviri başlayınca kurulacağını söyler* | *(Türkçesi aynı anlamda)* |
| Koptu, çeviri açık | Nedene göre (aşağıda). Bulunamadı / ağ / diğer nedenlerde yerel ağ izni kapalıysa yerel ağ uyarısı | | |

Kopma nedenleri:

| Neden | Anahtar | EN | TR |
|---|---|---|---|
| PS5 uykuda | `home.drop.asleep` | *PS5'in açılmasını ister* | *(Türkçesi aynı anlamda)* |
| Başka cihazda Remote Play | `home.drop.inUseElsewhere` | *Remote Play'i o anda başka bir aygıtın kullandığını söyler* | *(Türkçesi aynı anlamda)* |
| Reddetti | `home.drop.refused` | *PS5'in bağlantıyı geri çevirdiğini söyler, PS5 kurulumunun baştan yapılmasını ister* | *(Türkçesi aynı anlamda)* |
| Giriş şifresi isteniyor | `home.drop.passcodeRequired` | *PS5'in hesabın giriş şifresini beklediğini söyler; şifrenin Nino Ayarlar'ına yazılmasını veya konsolda o hesap için şifrenin kaldırılmasını önerir* | *(Türkçesi aynı anlamda)* |
| Giriş şifresi yanlış | `home.drop.passcodeWrong` | *Ayarlar'a kaydedilmiş giriş şifresinin PS5'çe geri çevrildiğini söyler; şifrenin orada düzeltilmesini veya konsolda o hesap için şifrenin kaldırılmasını önerir* | *(Türkçesi aynı anlamda)* |
| Eşleşme geçersiz | `home.drop.pairingInvalid` | *PS5'in bu eşleşmeyi tanımadığını söyler; Ayarlar'da ikinci hesap kullanılarak eşleşmenin tazelenmesini ister* | *(Türkçesi aynı anlamda)* |
| Remote Play kapalı | `home.drop.remotePlayDisabled` | *PS5'te Remote Play'in kapalı olduğunu söyler; konsolun kendi menüsünden (Settings › System › Remote Play, Türkçe arayüzde Ayarlar › Sistem › Uzaktan Oynama) Enable Remote Play / Uzaktan Oynamayı Etkinleştir seçeneğinin açılıp çevirinin baştan başlatılmasını ister* | *(Türkçesi aynı anlamda)* |
| Görüntü yok | `home.drop.noPicture` | *konsoldan hiç kare gelmediğini söyler; Remote Play'in kapalı ya da konsolun dinlenme modunda olup olmadığına bakıp yeniden başlatmayı ister* | *(Türkçesi aynı anlamda)* |
| Bulunamadı (%@ = adres) | `home.drop.notFound %@` | *%@ adresinde PS5'e rastlanmadığını söyler; konsolun açık olmasını ve bu bilgisayarla tek ağı paylaşmasını ister, bağlantının yeniden denendiğini ekler* | *(Türkçesi aynı anlamda)* |
| Ağ hatası | `home.drop.network` | The PS5 can't be reached. Reconnecting… | *PS5'e erişilemediğini ve yeniden bağlanmaya çalışıldığını söyler* |
| Kodla reddedildi (%@ = "0x" + 8 hane onaltılık) | `home.drop.rejectedCode %@` | *PS5'in bağlantıyı parantezde verilen kodla geri çevirdiğini söyler; bir diğer Remote Play programının veya ikinci bir oturumun açık kalmış olabileceğini belirtir, PS Remote Play'den çıkıp PS5'i yeniden başlatmayı ve tekrar denemeyi önerir* | *(Türkçesi aynı anlamda)* |
| Kodsuz reddedildi | `home.drop.rejected` | *PS5'in oturumu açmadığını söyler; PS Remote Play gibi bir diğer programın açık ya da konsolun başka bir oturumda olabileceğini belirtir, PS Remote Play kapatılıp PS5 yeniden başlatıldıktan sonra tekrar denenmesini önerir* | *(Türkçesi aynı anlamda)* |
| Ayrıntılı diğer | `home.drop.otherDetail %@` | Reconnecting… (%@) | *yeniden bağlanmaya çalışıldığını, ayrıntıyı parantez içinde vererek söyler* |
| Diğer / durdu | `home.drop.other` | Reconnecting… | Yeniden bağlanılıyor… |

Kurulum ve PS5 belgeleri de aynı tabloyu kullanır.

**Oyun penceresinden okunurken:**

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| Durdu, Xbox | `home.window.idleXbox` | *Xbox yayın penceresinin okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| Durdu, Remote Play bu bilgisayarda yok | `home.window.appMissing` | *bu bilgisayarda Remote Play programının bulunmadığını söyler, Nino'nun Ayarlar'daki Görüntü kaynağı kısmından edinilebileceğini belirtir* | *(Türkçesi aynı anlamda)* |
| Durdu | `home.window.idle` | *açık PS Remote Play penceresinin okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| Ekran Kaydı izni yok | `home.window.screenRecordingDenied` | *macOS gizlilik ayarlarındaki Ekran Kaydı bölümünden Nino'ya izin verilip uygulamanın kapatılıp açılmasını ister* | *(Türkçesi aynı anlamda)* |
| Pencere aranıyor, Xbox | `home.window.searchingXbox` | *Xbox'ın Greenlight içinden başlatılmasını ister; yardım için `home.xbox.connect` düğmesini gösterir* | *(Türkçesi aynı anlamda)* |
| Pencere aranıyor | `home.window.searching` | *PS Remote Play veya chiaki-ng açılıp bir oyunun başlatılmasını ister* | *(Türkçesi aynı anlamda)* |
| Okunuyor (%@ = uygulamanın adı) | `home.reading %@` | Reading %@ | %@ okunuyor |

**Capture Card'dan okunurken:**

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| Durdu | `home.card.idle` | *Capture Card'ın okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| Kamera izni yok | `home.card.cameraDenied` | *macOS gizlilik ayarlarındaki Kamera bölümünden Nino'ya izin verilip uygulamanın kapatılıp açılmasını ister* | *(Türkçesi aynı anlamda)* |
| Kart yok | `home.card.noCard` | *Capture Card'ın takılmasını ister* | *(Türkçesi aynı anlamda)* |
| Görüntü siyah | `home.card.black` | *gelen karenin simsiyah olduğunu söyler; PS5'i uyandırmayı ya da konsolun Settings › System › HDMI (Ayarlar › Sistem › HDMI) menüsündeki Enable HDCP / HDCP'yi Etkinleştir seçeneğini kapatmayı önerir* | *(Türkçesi aynı anlamda)* |
| Okunuyor (%@ = kartın adı) | `home.reading %@` | Reading %@ | %@ okunuyor |

### 8.4 Çağrılan eylemler

- çeviriyi başlat
- çeviriyi durdur
- kurulumu belli bir adımdan aç (konsol, TV)
- Ayarları aç (ilk ya da Çeviri bölümü)
- Geçmişi aç
- Hakkında'yı aç
- yardımcıyı aç
- ekran dışı pencereyi ayar kipine sok
- tıklamalar geçsin ayarını değiştir
- kartla tam ekranı aç/kapat
- güncellemeyi denetle / kur
- indirme sayısını yenile

---

## 9. Sağdan sola ve dil

- Çeviri dili Arapça, Farsça, İbranice ya da Urduca ise bütün arayüz sağdan sola dizilir. Başlıkta logo sağa, düğmeler
  sola geçer; alt şerit de aynalanır.
- **Aynalanmayanlar** (her zaman soldan sağa):
  - salon sahnesi (görsel, kablo, fiş)
  - cam anahtar
  - canlı TV
  - ekran dışı altyazı penceresi (kenar tutamakları dahil)
- **Altyazının yönü** arayüz dilinden değil, yazının kendisinden seçilir:
  - Metinde Arap harfi varsa satır sağdan sola dizilir.
  - Her paragrafın başına görünmez sağdan sola işareti (U+200F) konur. Böylece Latin harfli konuşmacı adıyla başlayan
    satır ("ARTHUR: …") da sağdan başlar.
  - Sola yaslı yerlerde Arapça satır kendi satırını kaplayıp sağa yaslanır.
- **Harf aralığı ve eğim:** TV'deki bekleme yazısında ve indirme sayacında, metin Arap harfi içeriyorsa harf aralığı 0
  olur; sayaçta eğim de kalkar. Harflerin birleşmesi bozulmasın diye.
- **Uzunluk:** Türkçe, Arapça gibi uzun dillerde metinler alt satıra kayar. Tek satırlık yerler (alt şerit, haplar)
  kısalmaz, sığmazsa kesilir.

## 10. Açık ve koyu tema

- Uygulamanın görünümü Ayarlar'da: Açık, Koyu ya da Sistem (varsayılan). Seçim bütün uygulamaya uygulanır.
- **Temaya göre değişenler:**
  - belirteç renkleri
  - cam kenarı ve cam dolgusu
  - pencere zemininin degradesi ve ışıkları
- **Temayla değişmeyenler:**
  - Salon görseli ve sahne renkleri, TV'nin içi. Açılış animasyonu TV'de hep koyu.
  - Cam anahtarın renkleri.
  - Canlı TV.
  - Altyazı temaları.
  - Robot düğmesinin beyaz dairesi.

---

## 11. Ekran dışı altyazı penceresi

Bilgisayar ekranında, oyunun veya PS Remote Play penceresinin üstünde duran saydam altyazı penceresi.

### 11.1 Ne zaman görünür

- Altyazı bilgisayar ekranında gösteriliyorsa görünür.
- Ve şu üçünden biri olmalı: ekranda satır var, ek alan çevirisi var ya da pencere ayar kipinde.
- Değilse gizlenir.

### 11.2 Pencere

- Kenarsız, odağı almayan, yüzen panel.
- Durum çubuğu seviyesinde: bütün pencerelerin, tam ekran uygulamaların da üstünde. Bütün masaüstlerinde görünür.
  Pencere geçişlerinde (⌘`) yer almaz, yerinden oynamaz.
- Zemini saydam, kendi gölgesi yok. Başka uygulama öne geçse de pencere görünür kalır. Kapatılınca silinmez.
- Klavyeyi yalnız ayar kipindeyken alabilir. Böylece oyun klavyeyi kaybetmez.
- Öndeki uygulama değişmeden ilk tıklama da çalışır (taşıma, `home.overlay.done` düğmesi).
- **Fare:** tıklamaların geçmesi ayarı (`home.menu.clickThrough`) açıksa ve ayar kipinde değilse fare alttaki pencereye geçer.
- **Yer ve genişlik:** macOS'un pencere kaydıyla hatırlanır, ekran da.
  - Kayıtlı yer artık bağlı olmayan bir ekrandaysa varsayılana döner.
  - Varsayılan: ana ekranın görünür alanının %70'i genişliğinde, ortada, alttan %4 yukarıda.
  - Eski kaydı korumak için kayıt adı aynen "NinoSubtitleWindow" kalmalı.
- **Ölçek ve yükseklik:**
  - Yazı boyu TV'deki gibi 1080 satırlık ekrana göredir. Ölçek = pencerenin bulunduğu ekranın yüksekliği / 1080.
  - Pencere yüksekliği = yuvarla(yazı boyu × ölçek × 8,1 + 140 × ölçek). En çok üç satıra ve satırların kaymasına
    yeter.
  - Yükseklik değişince alt kenar sabit kalır.
  - Pencere başka ekrana geçince yeniden ölçülür.
- **Oyun penceresinden okunurken** (ayar kipinde değilken):
  - Pencere oyun alanının alt kısmına oturur: oyun alanı genişliğinin %90'ı, ortalı, alt kenarı oyun alanının
    altından alan yüksekliğinin %3'ü kadar yukarıda.
  - Ölçek = oyun alanı yüksekliği / 1080. Pencere küçükse yazı da küçülür.
  - Bu sırada yer kaydı kapalıdır, kullanıcının kayıtlı yeri değişmez. Ayar kipine girilince kayıtlı yerine döner.
- **Taşıma:** fare imlecinin ekrandaki yeriyle, ekranlar arasında da.
- **Genişletme:** kenardan sürükleyince ortası yerinde kalır, iki yana eşit büyür. En az 320, en çok ekran genişliği.

### 11.3 İçerik

Alta yaslı katmanlar.

**Ayar kipinde:**

- **Çerçeve:** pencere boyunda yuvarlak dikdörtgen, köşe 22. Dolgu siyah %35. 2 pt kesik çizgili accent kenar (8 dolu,
  6 boş). Sürükleyince pencere taşınır.
- **Üst çubuk** (üstte, 12 iç boşluk), yatay sıra, aralık 12:
  - `home.overlay.instructions` (çerçeveyi sürükleyip taşımayı, kenarlarını çekip büyütüp küçültmeyi anlatan yönerge), callout yarı kalın, beyaz.
  - Birincil düğme `home.overlay.done` (Done / Bitti): ayar kipinden çıkar.
- **Kenar tutamakları:**
  - Sol ve sağ kenarda, dikeyde ortalı. Accent kapsül 6×48, yatayda 6 iç boşluk, tutma alanı pencere boyunda.
  - Üstüne gelince imleç "sola-sağa boyutlandır" olur.
  - Sürükleyince pencere genişler.

**Satır yığını**, dikey, aralık 14 × ölçek:

- Yatay iç boşluk 24 × ölçek (zemin biçimi bant (`settings.style.shape.band`) ise 0), alttan 8 × ölçek.
- Üstte ek alan kutuları. Altta esnek boşluk ve satırlar.
- Ayar kipinde satır yoksa örnek satır `home.overlay.sample` (Your subtitles will show up here. / Türkçesi: altyazının bu alanda çıkacağını gösteren örnek cümle), güncel satır olarak.
- Satırlar TV uygulamasıyla aynı yığından gelir:
  - En çok üç satır: güncel (en altta, tam boy), önceki (üstünde) ve iki önceki (en üstte).
  - Yeni satır öncekinden 1,5 sn içinde gelirse önceki üstte kalır. Üstteki satır 1,5 sn tam görünür, sonra 0,4 sn'de
    doğrusal söner.
  - Hiçbir satır, yerini yeni satır almadıkça, 1,2 sn'den kısa görünmez.
- **Satırın opaklığı:** güncel 1, önceki 0,6, iki önceki 0,45. Sönerken 0'a, 0,4 sn doğrusal.
- **Taşıma:** her satır, ek alan kutusu ve çerçeve sürüklenerek pencereyi taşır.

**Satırın çizimi:**

- **Tema Klasik (`home.theme.classic`) değilse ve satır paragraf değilse:**
  - Seçili temayla çizilir (§12).
  - Yazı boyu = stil boyu × ölçek, güncel değilse × 0,8. Satır sınırı yok.
- **Klasik ya da paragraf ise:**
  - **Bölme:** uzun satır en çok 3 satıra dengeli bölünür (satır başına 42 karakter hedefi). Konuşmacı adı ("ARTHUR:")
    sonraki sözcükle birlikte tutulur. 3 satıra sığmazsa yazı en çok %75'e küçülür. Zaten satır sonu içeren ya da 42
    karakterden kısa metin olduğu gibi kalır.
  - **Boy** = stil boyu × ölçek × (güncel 1, değilse 0,8) × bölme küçültmesi.
  - **Yazı:** seçili altyazı yazı tipi. Kalınsa kalın, değilse yarı kalın. Rengi beyaz ya da sarı (#FFE135).
  - **Hiza:** paragraf ise sola, değilse ortaya. Yazının yönü yazıya göre (§9). Satır arası boyun %30'u.
  - **Gölge:** siyah, yarıçap 2 × ölçek, 2 × ölçek aşağı.
  - **Kutu iç boşluğu:** güncelde dikey 10, yatay 26; diğerlerinde 6 ve 20 (× ölçek).
  - **Kutu zemini:** siyah. Opaklık stildeki zemin yüzdesi / 100, güncel değilse × 0,83.
  - **Bant:** zemin biçimi bant ise kutu pencerenin tüm genişliğini kaplar ve köşesizdir. Oyunun kendi İngilizce metni
    kenarlara uzansa bile görünmez kalır. Değilse köşe 10 × ölçek.
- **Ek alan kutusu** (görev, bildirim, telefon gibi sürekli okunan alanların çevirisi):
  - Yazı en az 12, stil boyu × ölçek × 0,55. Yarı kalın, altyazı rengi, sola yaslı.
  - İç boşluk dikey 6, yatay 14 (× ölçek). Siyah %85 zemin, köşe 8 × ölçek.
  - Oyundaki yazının bulunduğu yana yaslanır: sol, orta ya da sağ.

## 12. Altyazı temaları ve stil seçeneklerinin görünüşe etkisi

Stilin alanları:

- yazı boyu: 36, 46 (varsayılan), 58, 72; ya da otomatik
- zemin koyuluğu (yüzde)
- zemin biçimi: yazı kadar / bant
- kalın
- renk: beyaz / sarı
- tema
- yazı tipi
- yer, önceki satırı tutma, filigran

**Tema seçilince** renk, kalınlık ve zemin de ayarlanır. Boyut ve yer kullanıcıda kalır:

| Tema anahtarı | Ad (EN / TR) | Kısa tarif anahtarı | Kısa tarif (EN / TR) | Renk | Kalın | Zemin |
|---|---|---|---|---|---|---|
| `home.theme.classic` | Classic / Klasik | `home.theme.classic.detail` | See-through box / Yarı saydam kutu | beyaz | hayır | 100 |
| `home.theme.cinema` | Cinema / Sinema | `home.theme.cinema.detail` | Yellow, like the movies / Film gibi sarı | sarı | evet | 0 |
| `home.theme.minimal` | Minimal / Minimal | `home.theme.minimal.detail` | Keeps the picture clear / Görüntüyü kapatmaz | beyaz | hayır | 0 |
| `home.theme.glass` | Nino Glass / Nino Cam | `home.theme.glass.detail` | Frosted glass with a blue edge / *buzlu cam görünümünü ve mavi kenarı anlatan kısa tarif* | beyaz | hayır | 62 |
| `home.theme.contrast` | High Contrast / Yüksek Kontrast | `home.theme.contrast.detail` | The easiest to read / En kolay okunan | beyaz | evet | 100 |
| `home.theme.outline` | Outline / Kenarlıklı | `home.theme.outline.detail` | Like text in the game / Oyun yazısı gibi | beyaz | evet | 0 |

**Temalı satırın çizimi** (TV'deki satır, canlı TV, ekran dışı pencere, önizlemeler). B yazı boyudur:

- **Yazı:**
  - Seçili yazı tipi.
  - Kalınlık: Minimal'de orta; Kontrast, Kenarlıklı ve Sinema'da kalın; diğerlerinde stil kalınsa kalın, değilse
    yarı kalın.
  - Renk: sarı (1.0, 0.88, 0.21) ya da beyaz.
  - Ortalı. Varsayılan en çok 2 satır. Yönü yazıya göre.
- **Klasik:**
  - Gölge siyah %80, yarıçap 1, 1 aşağı.
  - İç boşluk yatay 0,5B, dikey 0,2B.
  - Zemin siyah, opaklık zemin yüzdesi / 100 × 0,85. Köşe 0,3B (sürekli).
- **Sinema:** kutu yok. Gölge siyah, yarıçap 0,08B, 0,04B aşağı; üstüne siyah %90, yarıçap 0,3B ikinci gölge.
- **Minimal:** kutu yok. Gölge siyah %90, yarıçap 0,06B, 1 aşağı; üstüne siyah %50, yarıçap 0,25B.
- **Nino Cam:**
  - Gölge siyah %60, yarıçap 1, 1 aşağı.
  - İç boşluk yatay 0,6B, dikey 0,25B.
  - Zemin (0.024, 0.047, 0.118) %86, köşe 0,45B (sürekli).
  - Kenar (0.18, 0.55, 1.0) %45; kalınlığı en az 1, 0,045B.
  - Dış ışık aynı mavi %25, yarıçap 0,4B.
- **Yüksek Kontrast:** iç boşluk yatay 0,45B, dikey 0,18B. Tam siyah zemin, köşe 0,12B (sürekli).
- **Kenarlıklı:**
  - Yazının siyah kopyası 8 yöne (her 45°) kaydırılarak arkaya çizilir. Kayma en az 1, 0,07B. Önde asıl yazı.
  - Bütününe siyah %60, yarıçap 0,15B gölge.

## 13. Yayın penceresi

Saydamlık tanımayan yayın programları (pencere yakalama) için düz zeminli sıradan bir pencere. Ayarlar › OBS'ten açılır.
Programda zemin chroma key ile silinir.

- **Pencere:** başlıklı, kapatılabilir, küçültülebilir, boyutlandırılabilir.
  - İlk boy 1280×720, ilk açılışta ortada.
  - İçerik oranı hep 16:9. En küçük boy 480×270.
  - Yer ve boy hatırlanır; eski kaydı korumak için kayıt adı aynen "NinoStreamWindow".
- **Başlık:** sabittir, yakalama listesinde bulunsun diye altyazıya göre değişmez. `home.stream.title` (Nino Stream / Nino Yayın).
- **Kapatınca** pencerenin açık durumu kapanır.
- **Zemin:** yeşil #00FF00 (varsayılan), siyah #000000 ya da mor #FF00FF.
- **İçerik:**
  - Ölçek = en büyüğü (0,2, pencere yüksekliği / 1080).
  - Dikey yığın, aralık 14 × ölçek. Yatay iç boşluk 24 × ölçek, alttan pencere yüksekliğinin %7'si.
  - **Üstte ek alan kutuları:** aralık 10 × ölçek, üstten 16 × ölçek. Saydam penceredeki gibi, ama zemin tam siyah,
    çünkü yarı saydamlık chroma key'i bozar.
  - **Esnek boşluk, sonra satırlar.**
- **Satırlar:** her zaman klasik biçim. Tema çizimi yok. Arapça için yön işareti eklenmez.
  - Ölçüler ekran dışı penceredeki klasik satırla aynı: bölme, boy, iç boşluk, köşe 10 × ölçek.
  - Kutu: zemin yüzdesi 0'dan büyükse tam koyu (opaklık 1), 0 ise hiç yok.
  - Önceki satırların solukluğu: kutu varsa yazının kendi rengi soldurulur (1 / 0,6 / 0,45); pencere zemininin
    saydamlığı kullanılmaz. Kutu yoksa yazı tam renk.
  - Gölge yalnız kutu yokken, yarıçap 2 × ölçek.
  - Sönen satır 0,4 sn doğrusal olarak kaybolur.

---

## 14. Metin tablosu

Ana ekranda ve bu belgede geçen metinler. Anahtarlar noktalı adlardır ve Home metin dosyasında durur; EN ve TR yeni
metinlerdir. Eski metinle örtüşebilecek satırlarda metnin yerine ne dediği *eğik* yazıyla anlatılır; metnin kendisi metin
dosyasındadır. Kopma nedenleri (`home.drop.*`) §8.3'te, motor sorunlarının açıklamaları
(`home.engineProblem.*`) Ayarlar › Çeviri belgesinde.

| Anahtar | EN | TR |
|---|---|---|
| `home.menu.about` | About Nino | *uygulamanın tam adını taşıyan Hakkında öğesi* |
| `home.menu.settings` | Settings… | Ayarlar… |
| `home.settings` | Settings | Ayarlar |
| `home.history` | History | Geçmiş |
| `home.version %@` | Version %@ | Sürüm %@ |
| `home.menu.gameFullScreen` | *oyun görüntüsünü ekranın tamamına yayan menü öğesi* | *(Türkçesi aynı anlamda)* |
| `home.menu.clickThrough` | Let clicks pass through | Tıklamalar geçsin |
| `home.overlay.adjust` | *altyazı penceresini düzenleme komutu* | Altyazı penceresini ayarla |
| `home.menu.openNino` | Open Nino | Nino'yu aç |
| `home.askNino` | Ask Nino | Nino'ya Sor |
| `home.startedBubble` | *Nino ağzından çevirinin devreye girdiğini bildiren, keyifli oyun dileyen balon* | *(Türkçesi aynı anlamda)* |
| `home.action.start` | Start translating | Çeviriyi başlat |
| `home.action.stop` | Stop translating | Çeviriyi durdur |
| `home.plug.unplugToStop` | Unplug to turn off subtitles | Altyazıyı kapatmak için fişi çıkarın |
| `home.plug.plugInToStart` | Plug in to start | Başlatmak için fişi takın |
| `home.hint.connectTVFirst` | *önce TV'yi bağlayıp ardından fişi takmayı söyleyen ipucu* | *(Türkçesi aynı anlamda)* |
| `home.hint.connectPS5First` | *PS5'in önce bağlanması gerektiğini hatırlatan ipucu* | *(Türkçesi aynı anlamda)* |
| `home.tv.dragPlug` | *fişi sürükleyip prize götürerek başlatmaya çağıran yazı* | *(Türkçesi aynı anlamda)* |
| `home.tv.totalDownloads` | Total downloads | Toplam indirme |
| `home.tv.live` | LIVE | CANLI |
| `home.tv.waiting` | *bir sonraki altyazı satırının beklendiğini söyleyen yazı* | *(Türkçesi aynı anlamda)* |
| `home.switch.turnOn` | Turn on | Aç |
| `home.status.connecting` | Connecting… | Bağlanıyor… |
| `home.switch.connectPS5` | Connect your PS5 | PS5'inizi bağlayın |
| `home.switch.subtitles` | Turkish subtitles | Türkçe altyazı |
| `home.switch.tapToSetUp` | Tap to start the setup | *dokununca kurulumun başlayacağını söyler* |
| `home.switch.onTitle` | Turkish | Türkçe |
| `home.switch.onSubtitle` | Subtitles on | Altyazı açık |
| `home.switch.description` | *konsoldaki İngilizce altyazının okunup TV'de Türkçeye çevrilmiş hâlde gösterildiğini anlatan tek cümle* | *(Türkçesi aynı anlamda)* |
| `home.xbox.start` | Start your Xbox | Xbox'ınızı açın |
| `home.xbox.connect` | Connect your Xbox | Xbox'ı bağla |
| `home.source.gameWindow` | Game window | Oyun penceresi |
| `home.source.captureCard` | Capture card | Capture Card |
| `home.status.connected` | Connected | Bağlı |
| `home.tv.waitingApp` | *TV uygulamasının açılmasının beklendiğini söyler* | *(Türkçesi aynı anlamda)* |
| `home.tv.connect` | Connect a TV | TV bağlayın |
| `home.source.ready %@` | %@ · ready | %@ · hazır |
| `home.translation` | Translation | Çeviri |
| `home.translation.poolGame %@` | Nino · %@ active | Nino · %@ Aktif |
| `home.update.readyRestart` | *güncellemenin indiğini söyleyip yeniden başlatmayı öneren hap* | *(Türkçesi aynı anlamda)* |
| `home.update.downloading %@` | Downloading %@… | %@ indiriliyor… |
| `home.update.newVersion %@` | *yeni sürüm numarasını gösterip güncellemeye çağıran hap* | *(Türkçesi aynı anlamda)* |
| `home.update.check` | Check for updates | *güncelleme olup olmadığına bakma çağrısı* |
| `home.update.checking` | Checking… | Denetleniyor… |
| `home.update.upToDate` | Up to date | Güncel |
| `home.update.bannerTitle` | *Nino'nun yeni sürümünün geldiğini duyurur* | *(Türkçesi aynı anlamda)* |
| `home.update.download` | Download | İndir |
| `home.splash.tagline` | Your games, now in Turkish. | *oyunların artık Türkçe olduğunu söyleyen slogan* |
| `home.warning.languagePack %@ %@` | The %1$@–%2$@ language pack hasn't been downloaded yet. | *iki dilin (kaynak–hedef) dil paketinin daha inmediğini söyleyen başlık* |
| `home.warning.languagePackHint` | *kaynak ve hedef dilin ikisinin de macOS'un Çeviri Dilleri ayarından indirilmesini isteyen ipucu* | *(Türkçesi aynı anlamda)* |
| `home.warning.openLanguageRegion` | *sistemin Dil ve Bölge ayarını açan düğme* | *(Türkçesi aynı anlamda)* |
| `home.warning.unsupported %@ %@` | This Mac can't translate from %1$@ to %2$@. | Bu Mac'te %1$@ dilinden %2$@ diline çeviri yapılamıyor. |
| `home.warning.needsMacOS26` | *Apple'ın bedava çevirisinin macOS 26 istediğini; oyun paketlerinin, DeepL'in ve Ayarlar › Çeviri'deki yapay zekâ çevirisinin bu Mac'te yine işlediğini anlatır* | *(Türkçesi aynı anlamda)* |
| `home.warning.unsupportedHint` | *Apple çevirisinin bu dili şimdilik desteklemediğini söyler; Ayarlar › Çeviri'de yapay zekâ çevirisini açmayı önerir, Gemini'nin bedava olduğunu ekler* | *(Türkçesi aynı anlamda)* |
| `home.warning.localNetwork` | *Nino'nun yerel ağa erişemiyor olabileceğini söyler; macOS gizlilik ayarlarındaki Yerel Ağ bölümünden izni açıp Nino'yu kapatıp açmayı ister* | *(Türkçesi aynı anlamda)* |
| `home.warning.openSystemSettings` | Go to System Settings | Sistem Ayarları'na git |
| `home.warning.engineDown %@` | %@ isn't translating right now | %@ şu an çevirmiyor |
| `home.warning.freeMeanwhile` | Meanwhile, Nino's built-in translation steps in. | Bu arada Nino'nun kendi çevirisi devreye girer. |
| `home.warning.cantRead` | *macOS'un ekrandaki yazıyı tanıyamadığını bildiren başlık* | *(Türkçesi aynı anlamda)* |
| `home.warning.diskFull %.1f` | *diskin dolmak üzere olduğunu, boş kalan GB'ı %.1f ile verir; macOS'un yazı okuyabilmek için yere gereksindiğini, birkaç GB boşaltıp çeviriye yeniden başlamayı söyler* | *(Türkçesi aynı anlamda)* |
| `home.warning.restartMac` | *bilgisayarı kapatıp açtıktan sonra çeviriye yeniden başlamayı söyler* | *(Türkçesi aynı anlamda)* |
| `home.status.notConnected` | Not connected | Bağlı değil |
| `home.status.paired %@` | *%@ adlı PS5 ile eşleşildiğini, bağlantının çeviri başlayınca kurulacağını söyler* | *(Türkçesi aynı anlamda)* |
| `home.drop.asleep` | *PS5'in açılmasını ister* | *(Türkçesi aynı anlamda)* |
| `home.window.idleXbox` | *Xbox yayın penceresinin okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| `home.window.idle` | *açık PS Remote Play penceresinin okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| `home.window.appMissing` | *bu bilgisayarda Remote Play programının bulunmadığını söyler, Nino'nun Ayarlar'daki Görüntü kaynağı kısmından edinilebileceğini belirtir* | *(Türkçesi aynı anlamda)* |
| `home.window.screenRecordingDenied` | *macOS gizlilik ayarlarındaki Ekran Kaydı bölümünden Nino'ya izin verilip uygulamanın kapatılıp açılmasını ister* | *(Türkçesi aynı anlamda)* |
| `home.window.searchingXbox` | *Xbox'ın Greenlight içinden başlatılmasını ister; yardım için `home.xbox.connect` düğmesini gösterir* | *(Türkçesi aynı anlamda)* |
| `home.window.searching` | *PS Remote Play veya chiaki-ng açılıp bir oyunun başlatılmasını ister* | *(Türkçesi aynı anlamda)* |
| `home.reading %@` | Reading %@ | %@ okunuyor |
| `home.card.idle` | *Capture Card'ın okunacağını söyler* | *(Türkçesi aynı anlamda)* |
| `home.card.noCard` | *Capture Card'ın takılmasını ister* | *(Türkçesi aynı anlamda)* |
| `home.card.cameraDenied` | *macOS gizlilik ayarlarındaki Kamera bölümünden Nino'ya izin verilip uygulamanın kapatılıp açılmasını ister* | *(Türkçesi aynı anlamda)* |
| `home.card.black` | *gelen karenin simsiyah olduğunu söyler; PS5'i uyandırmayı ya da konsolun Settings › System › HDMI (Ayarlar › Sistem › HDMI) menüsündeki Enable HDCP / HDCP'yi Etkinleştir seçeneğini kapatmayı önerir* | *(Türkçesi aynı anlamda)* |
| `home.overlay.instructions` | *çerçeveyi sürükleyip taşımayı, kenarlarını çekip büyütüp küçültmeyi anlatan yönerge* | *(Türkçesi aynı anlamda)* |
| `home.overlay.done` | Done | Bitti |
| `home.overlay.sample` | Your subtitles will show up here. | *altyazının bu alanda çıkacağını gösteren örnek cümle* |
| `home.stream.title` | Nino Stream | Nino Yayın |
| `home.theme.classic` | Classic | Klasik |
| `home.theme.cinema` | Cinema | Sinema |
| `home.theme.minimal` | Minimal | Minimal |
| `home.theme.glass` | Nino Glass | Nino Cam |
| `home.theme.contrast` | High Contrast | Yüksek Kontrast |
| `home.theme.outline` | Outline | Kenarlıklı |
| `home.theme.classic.detail` | See-through box | Yarı saydam kutu |
| `home.theme.cinema.detail` | Yellow, like the movies | Film gibi sarı |
| `home.theme.minimal.detail` | Keeps the picture clear | Görüntüyü kapatmaz |
| `home.theme.glass.detail` | Frosted glass with a blue edge | *buzlu cam görünümünü ve mavi kenarı anlatan kısa tarif* |
| `home.theme.contrast.detail` | The easiest to read | En kolay okunan |
| `home.theme.outline.detail` | Like text in the game | Oyun yazısı gibi |
| `home.font.condensed` | Action (GTA style) | Aksiyon (GTA tarzı) |
| `home.font.modern` | Modern | Modern |
| `home.font.rounded` | Rounded | Yuvarlak |
| `home.font.system` | System | Sade |

Çevrilmeyen metinler: Nino, GAME TRANSLATOR, PS5, TV, sürüm adı (ör. V4.0) ve geliştirici rozetindeki yazı (§3).

### Ana ekranda olmayanlar

- Konsol, görüntü kaynağı ve altyazının yeri karosu ana ekranda değil, Ayarlar › Bağlantı'dadır: `ayarlar.md`.
- Altyazı bölgesinin canlı önizlemesi (sürüklenen çerçeve, köşe tutamağı, hazır bölgeler) Ayarlar › Altyazı alanı'ndadır: `ayarlar.md` §14.4.

### Bölge önizlemesinin görünüşü (ayarlar.md §14.4'e ek)

`ayarlar.md` önizlemenin yerini anlatır; görünüşü şöyledir:

- **Kutu:** 16:9 oranında, köşe 10 (iç köşe) ile kırpılır.
- **Zemin:** son PS5 karesi, kutuya gerilerek çizilir. Kare yoksa:
  - background renginde yuvarlak dikdörtgen.
  - Ortasında yer tutucu yazı `settings.area.noFrame` (çeviri başlayınca oyun karesinin burada çıkacağını söyleyen yer tutucu).
    Caption, textSecondary, ortalı, 12 iç boşluk.
- **Bölge çerçevesi:**
  - Yeri ve boyu bölgenin yüzde değerlerinden (sol, üst, sağ, alt) hesaplanır.
  - Dolgu accent %14, 2 pt accent iç kenar. Köşesiz.
  - Sürükleyince bölge taşınır. Sürükleme en az 1 pt; hep sürüklemenin başındaki bölgeye göre hesaplanır.
  - Ekran okuyucu etiketi `settings.section.area` (Subtitle area / Altyazı alanı).
- **Boyut tutamağı:**
  - Çerçevenin sağ alt köşesinin içinde 14×14 dolu accent kare.
  - Sürükleyince sağ ve alt kenar değişir. Ekran okuyucudan gizli.
- **Hazır bölge adları:**
  - `settings.area.bottom` (Bottom area / Alt bölge)
  - `settings.area.top` (Top area / Üst bölge)
  - `settings.area.full` (Full screen / Tam ekran)
  - `settings.area.custom` (Custom / Özel)
- **Yüzde yazımı:** `settings.area.percent %lld` anahtarı (EN `%lld%%`, TR `%%%lld`). Türkçede %40, İngilizcede 40% görünür.
