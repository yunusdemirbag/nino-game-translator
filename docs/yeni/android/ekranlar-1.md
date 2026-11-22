# Nino Android: ekranlar ve görünüş, bölüm 1

Bu belge eski Android telefon uygulamasının **kullanıcının gördüğü ve yaşadığı** hâlini tarif eder. Kod, sınıf ya da
dosya yapısı anlatılmaz. Metinler yalnız anahtar adıyla anılır; metnin kendisi yeni uygulamanın `apps/android/app/src/main/res/values/strings.xml` dosyasındadır (o dosyada yoksa yanında anlamı yazılır) (varsayılan dil Türkçedir; başka 12 dilde
çevirisi var). `%1$s` / `%1$d` yazan yerlere ne geldiği yanında belirtildi.

Kapsam: genel tasarım dili, ortak parçalar, gezinme kuralları, açılış animasyonu, yüzen robot düğmesi, karşılama, PS5
eşleme, "Altyazılar nerede", görüntü kaynağı, iki ana ekran (Salon ve kaydırmalı), tanıtım turu, oyun paketleri,
telefonda tam ekran altyazı, altyazı alanı karoları, dil menüsü, güncelleme kartları, görseller.

---

## 1. Genel tasarım dili

**Tema:** Yalnız **açık** tema vardır (sistem karanlık modda olsa da). Beyaz cam görünüm, PlayStation mavisi vurgu,
lacivert derinlik. Koyu renk yalnız "sahne" kartlarında (oyun ekranı gibi duran kartlar) ve tam ekran altyazıda kullanılır.

**Pencere:** Kenardan kenara çizilir; durum çubuğu ve gezinme çubuğu saydamdır, simgeleri **koyu** renktedir. Pencerenin
çizilmeden önceki zemin rengi `#EEF3FB`. Klavye açılınca içerik yeniden boyutlanır (ekran küçülür, kaymaz).

**Arayüz dili:** Uygulamanın kendi arayüz dili ayarı vardır; sistem dilinden bağımsız olarak o dille açılır. Arapça ve
Urduca arayüzde düzen sağdan sola döner (aşağıda yer yer istisnalar var).

### 1.1 Renkler

| Ad | Değer | Kullanım |
|---|---|---|
| Zemin | `#EEF3FB` | pencere zemini |
| Yüzey | `#FFFFFF` %85 opak | karolar |
| Yüzey 2 | `#E6EDF8` | segment rayı, kod kutuları, tur kartı, açılır dil satırı, iletişim kutusu |
| Yükseltilmiş | `#FFFFFF` | ikincil düğme, simge düğmesi, metin alanı |
| Çerçeve | `#FFFFFF` %75 | karo kenarı, ayraçlar |
| Güçlü çerçeve | `#D3DEEF` | düğme ve alan kenarları |
| Yazı | `#0A1430` | ana yazı ("mürekkep") |
| İkincil yazı | `#55607A` | açıklamalar |
| Vurgu | `#0070D1` | seçili karo kenarı, odak, simgeler |
| Vurgu açık | `#1A86E8` | degradelerin üst ucu |
| Vurgu yazısı | `#0058A8` | metin düğmeleri, adım satırı |
| Lacivert | `#003085` | degradelerin alt ucu |
| Vurgu yumuşak | `#DDEBFA` | karo simgelerinin daire zemini |
| Paket (koyu) | `#00205B` | paket etiketi yazısı, gölge tonu |
| Paket yumuşak | `#E2E8F5` | paket etiketi zemini |
| Başarı | `#1E6B45` | bağlı nokta, onay |
| Uyarı | `#9A4A08` | uyarı karosu yazısı ve simgesi |
| Tehlike | `#B3261E` / zemin `#FBE4E2` | tehlikeli düğme |
| Sahne üst / alt | `#151E36` → `#06080F` | koyu sahne kartları |
| Canlı yeşili | `#30C578` | "Canlı" durum noktası, "Ücretsiz" etiketi |
| Bayrak kırmızısı | `#E30A17` (koyu ucu `#A80514`) | CANLI noktası, kaydırma çubuğunun açık rengi |

**Ekran zemini (her ekran):** sol üstten sağ alta `#F7FAFF` → `#E3ECFA` doğrusal degrade. Üstüne iki yumuşak ışık:
- sol üstte (genişliğin %10'u, yüksekliğin %8'i) merkezli, yarıçapı genişliğin 0,9 katı, `#0070D1` %22'den saydama
  radyal ışık;
- sağ altta (%95, %95) merkezli, yarıçapı genişlik kadar, `#00205B` %16'dan saydama radyal ışık.

### 1.2 Yazı

Uygulama yazısı sistemin yazı tipidir (Roboto). Ölçek:

| Rol | Boy / satır | Kalınlık |
|---|---|---|
| Büyük başlık | 28/34 sp | yarı kalın (600) |
| Başlık | 22/28 sp | 600 |
| Alt başlık / düğme yazısı | 17/22 sp | 600 |
| Önceki altyazı satırı | 17/22 sp | normal |
| Gövde | 15/20 sp | normal |
| Küçük yazı | 13/16 sp | orta (500) |
| Telefondaki altyazı (dikey) | 28/36 sp | 600 |
| Telefondaki altyazı (yatay tam ekran) | 36/44 sp | 600 |

Ekran başlıkları (kurulum ekranları) bundan daha büyüktür: bkz. 2.6. Ana ekran başlığı 34 sp'dir (bkz. 7).

**Altyazı yazı tipleri** (kullanıcı Ayarlar'dan seçer; sıra bu): "Aksiyon (GTA tarzı)" = Barlow Condensed (SemiBold/Bold,
varsayılan), "Modern" = Barlow (SemiBold/Bold), "Yuvarlak" = Nunito değişken yazı tipi 650 kalınlıkta, "Sade" = cihazın
yazı tipi. Dosyalar uygulamaya gömülüdür (OFL lisanslı, TV uygulamasıyla aynı). Bu yazı tiplerinde olmayan harfler
(Arapça, Tayca, Hintçe…) sistemin yedek yazı tipinden çizilir. Ad anahtarları: `settings_font_condensed`, `settings_font_modern`, `settings_font_rounded`, `settings_font_system`.

### 1.3 Ölçüler

- Ekran kenar boşluğu 20 dp; karolar arası 12 dp; karo içi boşluk 16 dp; satır içi 8 dp; en küçük boşluk 4 dp.
- Köşe yarıçapları: karo **22 dp**, denetim (alan, segment rayı) **16 dp**, karo içi kutu 8 dp, etiket 6 dp. Düğmeler hap
  biçimlidir (tam yuvarlak uç).
- Simge düğmesi 44 dp; satır en az 52 dp; etiket 24 dp yüksek; durum noktası 8 dp.

### 1.4 Hareket

- Sistemde "animasyonları kapat" açıksa (animasyon süresi ölçeği 0) sürekli dönen/yanıp sönen animasyonlar durur ya da
  anında biter; her animasyon notunda ayrıca belirtildi.
- Basılabilir karolar ve birincil düğme basılıyken %97'ye küçülür (dalga efekti yoktur).

---

## 2. Ortak parçalar

### 2.1 Ekran iskeleti
Yukarıdan aşağı: güvenli alan + 20 dp kenar → (varsa) üst çubuk → 12 dp → **kaydırılan içerik** (öğeler arası 12 dp) →
12 dp → **alta sabit düğme bölgesi** (öğeler arası 12 dp, yatayda ortalı; birincil düğme en altta). Zemin: 1.1'deki
ekran zemini.

### 2.2 Üst çubuk
44 dp yüksek, öğeler arası 12 dp.
- Solda: geri gidilebiliyorsa **geri** simge düğmesi (sağdan sola dillerde ayna ok), değilse **uygulama simgesi** 36 dp
  (`icon.png`).
- Ortada: varsa başlık (22 sp, 600, tek satır), yoksa boşluk.
- Sağda: ekrana özel düğmeler, varsa en sağda **kapat** (X).
- Erişilebilirlik adları: `back`, `close`, `settings`, `profile`,
  `history`.

### 2.3 Simge düğmesi
44 dp daire, beyaz zemin, 1 dp `#D3DEEF` kenar, ortada 20 dp `#0A1430` simge. Basma ışığı da daire içinde kalır.

### 2.4 Düğmeler
- **Birincil:** tam genişlik, 58 dp yüksek, hap. Dikey degrade `#1B2747` → `#0A1430`, 1 dp beyaz %14 kenar, 18 dp koyu
  gölge (mürekkep rengi %50–60). Yazı 17 sp, 600, beyaz. Basılıyken %97. Pasifken: `#E6EDF8` zemin, `#D3DEEF` kenar,
  `#55607A` yazı, gölgesiz.
- **İkincil:** tam genişlik, 58 dp, hap, beyaz zemin, 1 dp `#D3DEEF` kenar, `#0A1430` 17 sp 600 yazı, gölgesiz.
- **Metin (hayalet) düğme:** 44 dp yükseklik, yalnız yazı: 17 sp 600, `#0058A8` (ya da verilen renk).
- **Tehlikeli:** 52 dp, 16 dp köşe, `#FBE4E2` zemin, `#B3261E` yazı. (Ulaşılabilir ekranlarda kullanılmıyor.)

### 2.5 Karo
22 dp köşe, beyaz %85 zemin, 1 dp beyaz %75 kenar, 14 dp yumuşak gölge (`#00205B` %10). İç boşluk 16 dp, içindeki
öğeler arası 8 dp. **Seçili/etkin** karo: kenar 1,5 dp `#0070D1`. Basılabilir karo basılıyken %97.
- **Karo etiketi:** 13 sp, 500, `#55607A`.
- **Karo simgesi:** 28 dp `#DDEBFA` daire içinde 16 dp `#0058A8` simge.
- **Not/uyarı karosu:** karo; solda uyarı (Warning) karo simgesi (uyarı renginde), yanında 15 sp metin `#9A4A08`.
  Bilgi notunda renk `#55607A` olur ve simge çıkmaz.
- **Satır listesi:** tek karo, içinde satırlar, aralarında 1 dp ayraç (çerçeve rengi); iç boşluk yatay 16, dikey 4 dp.
- **Satır:** en az 52 dp; solda başlık (17 sp 600) ve altında değer (13 sp ikincil); sağda isteğe bağlı öğe (anahtar vb.).
  Basılabiliyorsa tüm satır basılır.

### 2.6 Ekran başlığı (kurulum ekranları)
Yukarıdan aşağı, aralar 6 dp:
1. İsteğe bağlı adım satırı: 13 sp, 600, `#0058A8`, harf aralığı 0,2 sp. Metin: `setup_step`
   (adım numarası).
2. Başlık: 32/38 sp, kalın (700), harf aralığı −0,5 sp, `#0A1430`.
3. İsteğe bağlı açıklama: 16/23 sp, `#55607A`.

### 2.7 Etiket (hap)
24 dp yüksek, 6 dp köşe, yatay 8 dp iç boşluk, 13 sp 500 yazı tek satır. Nötr: `#E6EDF8` zemin, `#55607A` yazı.
Paket etiketi: `#E2E8F5` zemin, `#00205B` yazı.

### 2.8 Durum noktası ve durum yazısı
8 dp dolu daire (16 dp alan içinde). "Canlı" durumda çevresinde 2 sn'de bir büyüyüp sönen 2 dp halka (opaklık %70 → 0,
yarıçap yarıdan tama). Animasyon kapalıysa halka yok. Durum yazısı: nokta + 4 dp + 13 sp `#0A1430` yazı, tek satır,
zeminsiz. Nokta rengi: iyi durumda `#1E6B45`, değilse `#55607A`.

### 2.9 Metin alanı
Çerçeveli alan, 16 dp köşe, beyaz zemin. Kenar `#D3DEEF`, odakta `#0070D1`; imleç `#0070D1`; etiket 13 sp `#55607A`.
Tek satırlıkta yazı 17 sp 600; çok satırlıkta 15 sp. Gizli alanlarda karakterler noktalanır.

### 2.10 Segmentli seçim
Tam genişlik ray: `#E6EDF8`, 16 dp köşe, 4 dp iç boşluk, parçalar arası 4 dp. Her parça eşit genişlik, 36 dp yüksek,
8 dp köşe. Seçili parça beyaz zemin, 15 sp 600 `#0A1430`; diğerleri saydam, 15 sp 500 `#55607A`. Çerçeve yok.

### 2.11 Kod kutuları (8 hane)
Tam genişlikte 8 eşit kutu, aralar 6 dp, 48 dp yüksek, 8 dp köşe, `#E6EDF8` zemin, 1,5 dp `#55607A` %40 kenar.
Sıradaki (yazılacak) kutu 2 dp `#0070D1` kenarlı. Rakam 22 sp 600 `#0A1430`. Görünmez bir alan rakamları alır
(yalnız rakam, en çok 8; sayısal gizli klavye); kutulara dokununca klavye açılır.

### 2.12 Paket karosu
Karo: üst satırda solda 44 dp kısaltma kutusu (8 dp köşe, `#E6EDF8`, kısaltma 13 sp 600 `#0A1430`), sağda isteğe bağlı
durum. Altında ad (17 sp 600, tek satır) ve satır sayısı (13 sp ikincil), aralar 4 dp. Kapalı/sönük hâlde tüm karo %40
opak.

### 2.13 Bilgi iletişim kutusu
Standart uyarı kutusu, zemin `#E6EDF8`; başlık 17 sp 600, gövde 15 sp ikincil; tek düğme `ok` (17 sp 600
`#0058A8`).

### 2.14 Koyu sahne kartı ve cam öğeler (kurulum ekranlarının görseli)
- **Sahne kartı:** tam genişlik, verilen yükseklik (varsayılan 380 dp), 28 dp köşe, 28 dp koyu gölge (mürekkep %50),
  dikey degrade `#151E36` → `#06080F`, 1 dp kenar: dikey degrade beyaz %22 → beyaz %3. İç boşluk 16 dp, içerik dikeyde
  ortalı, aralar 10 dp.
- **Cam satır:** beyaz %8 zemin, 18 dp köşe, 1 dp beyaz %12 kenar, iç boşluk yatay 14 / dikey 12, aralar 12 dp.
  Solda isteğe bağlı kısaltma rozeti (40 dp, beyaz %12, 12 dp köşe, 12 sp kalın beyaz yazı). Ortada başlık 15 sp 600
  beyaz tek satır ve açıklama 12 sp beyaz %60 tek satır. Sağda isteğe bağlı etiket: 12 sp 600 beyaz yazı, `#30C578` %25
  hap zemin, iç boşluk 10×4.
- **Cam seçenek kutusu:** beyaz %8 zemin, 20 dp köşe, 1 dp beyaz %12 kenar, iç boşluk 16, aralar 8. Üstte 40 dp beyaz
  %12 daire içinde 22 dp beyaz simge, altında ad 20 sp kalın beyaz, altında açıklama 12 sp beyaz %60.
- **Seçilebilir cam kutu:** cam seçenek kutusu gibi, ama 190 dp sabit yükseklik; seçiliyken zemin beyaz %16 ve kenar 2 dp
  beyaz %85, değilken beyaz %6 ve 1 dp beyaz %12. Seçiliyken sağ üst köşede 24 dp beyaz daire içinde 16 dp `#0A1430`
  onay işareti. Açıklama en çok 3 satır. Dokununca seçilir.
- **Simgeli cam satır:** cam satır gibi; rozet yerine 40 dp beyaz %12 daire içinde 20 dp beyaz simge; açıklama tek satıra
  sınırlı değil, etiket yok (PSN ekranındaki güvence satırları).

### 2.15 Diğer ortak parçalar (başka ekranlar da kullanır)
- **Durum karosu:** karo; üst satırda karo simgesi (isteğe bağlı) + ad (13 sp ikincil, tek satır, kalan genişlik) + sağda
  isteğe bağlı durum öğesi; altında değer (22 sp 600, en çok 2 satır); altında isteğe bağlı not (13 sp ikincil). Etkin
  hâli mavi kenarlı; sönük hâli %40 opak; basılabilir olabilir.
- **Seçili işareti:** 20 dp `#0070D1` daire içinde 14 dp beyaz onay (erişilebilirlik adı `selected`).
- **Ortası yazılı ayraç:** iki yanda `#D3DEEF` ince çizgi, ortada 13 sp ikincil yazı (ör. iki giriş yolu arasındaki "ya da" ayracı), aralar 12 dp.
- **İki sütun:** iki eşit genişlikte karo yan yana, 12 dp ara, ikisi aynı yükseklikte (uzun olana uyar).

---

## 3. Gezinme kuralları

### 3.1 İlk açılan ekran
Uygulama her açılışta kurulumun **ilk eksik adımına** gider; sıra:
1. Karşılama hiç görülmediyse → **Karşılama**.
2. Konsol türü (PS5 / Xbox) hiç seçilmediyse ve kurulum bitmemişse, PSN hesabı ve eşli PS5 yoksa ve kurulum "Şimdilik
   Atla" ile atlanmadıysa → **Konsol türü** ekranı (bu belgenin kapsamı dışında).
3. Konsol Xbox ise: Microsoft girişi yoksa (atlanmadıysa) → **Microsoft girişi**; Xbox seçilmemişse (atlanmadıysa) →
   **Xbox seçimi**; sonra kurulum bitmemişse → **Altyazılar nerede**, bitmişse → **Ana ekran**. (Bu iki Xbox ekranı
   kapsam dışı.)
4. PSN hesabı yoksa, kurulum atlanmadıysa ve görüntü kaynağı yakalama kartı değilse → **PSN girişi** (kapsam dışı).
5. Eşli PS5 yoksa (aynı koşullarla) → **PS5 eşleme**.
6. Kurulum bitmemişse → **Altyazılar nerede** (Adım 3).
7. Hepsi tamamsa → **Ana ekran**.

### 3.2 "Bitti" ile ilerleme
Bir kurulum adımı bitince yukarıdaki sıraya göre sonraki eksik adım hesaplanır:
- Adım **ana ekrandan açılmışsa** (geride bir ekran varsa) ve sonraki eksik adım Microsoft girişi, Xbox seçimi, PSN
  girişi ya da PS5 eşleme ise, o adım **şimdiki ekranın yerine** açılır.
- Ana ekrandan açılmışsa ve her şey tamamsa → bir geri gidilir (ana ekrana döner).
- İlk kurulumda (geride ekran yoksa) → sonraki adım açılır ve geçmiş tümüyle silinir (geri tuşu eski adıma dönmez).

Özel durumlar:
- **PSN girişi bitti:** PS5 eşli değilse ve ana ekrandan gelindiyse → PS5 eşleme, PSN ekranının yerine açılır; değilse
  normal ilerleme. (Microsoft girişi de aynı şekilde Xbox seçimine geçer.)
- **Altyazılar nerede bitti:** seçim kaydedilir, kurulum "bitti" sayılır, normal ilerleme. İlk kurulumda biterse kurulum
  bitti olayı (seçilen hedefle) ölçüme gider.
- **TV'ye kurulum bitti** ("Ana ekrana geç"): her şey tamamsa ana ekran açılır ve geçmiş silinir; değilse bir geri.
- **Görüntü kaynağı kaydedildi:** bir geri gidilir; sonra Xbox seçildiyse ve Microsoft girişi yoksa → Microsoft girişi
  açılır, giriş var ama Xbox seçilmemişse → Xbox seçimi açılır.

### 3.3 Geri ve "Şimdilik Atla"
- Üst çubuktaki **geri** düğmesi yalnız geride bir ekran varken görünür; ilk kurulum adımlarında görünmez.
- **"Şimdilik Atla"** (`skip_for_now`) yalnız ilk kurulumda (geride ekran yokken) PSN, PS5 eşleme ve Xbox
  adımlarının sağ üstünde görünür. Basınca kurulum "atlandı" olarak işaretlenir ve ilerlenir; PSN, PS5 ve Xbox adımları
  atlanır. Kurulum bitmemişse sonraki ekran **Altyazılar nerede** olur, ardından konsolsuz ana ekrana varılır (eşleme
  sonradan Ayarlar/Profil'den yapılır).
- Sistem geri tuşu bir önceki ekrana döner; ilk ekranda uygulamadan çıkar.

### 3.4 Ana ekrandan gidilen yerler
| Dokunulan | Açılan |
|---|---|
| Geçmiş simgesi | Geçmiş ekranı |
| Ayarlar simgesi | Ayarlar |
| Profil simgesi | Profil |
| Konsol kısa yolu (ya da eşlenmemişken başlat denetimi) | Kaynak yakalama kartıysa → Görüntü kaynağı; değilse eşleme akışı |
| Çıkış kısa yolu | Altyazılar nerede |
| Paketler kısa yolu | Oyun paketleri |
| TV güncelleme kartındaki düğme | TV'ye kurulum ekranı (o TV seçili gelir) |
| Tam ekran düğmesi/hapı, telefonu yan çevirme | Telefonda tam ekran altyazı (ayrı, yatay pencere) |

**Eşleme akışı:** konsol Xbox ise Microsoft girişi yoksa Microsoft girişi, varsa Xbox seçimi; PS5 ise PSN hesabı yoksa
PSN girişi, varsa PS5 eşleme.

Profil ve Ayarlar'dan da Altyazılar nerede, eşleme akışı, PSN girişi, TV'ye kurulum, Sorun Bildir, Nino'ya Sor, Paketler,
Sistem sağlığı ve Görüntü kaynağı açılır (o ekranlar kapsam dışı).

### 3.5 Çeviriyi başlatma (her iki ana ekran)
1. Kaynak yakalama kartıysa ve kamera izni yoksa önce kamera izni sorulur. Verilirse çeviri başlar; verilmezse ana
   ekranda uyarı karosu çıkar: `capture_no_permission`
2. Android 13 ve üstünde bildirim izni yoksa istenir (cevap beklenmeden çeviri başlar).
3. Çeviri arka planda başlar. Altyazı hedefi "telefon" ise tam ekran altyazı penceresi hemen açılır.

Durdurma: örnek (demo) oturum açıksa o durur, değilse çeviri hizmeti durur.

### 3.6 Diğer genel davranışlar
- Çeviri sürerken ve Ayarlar'da "ekranı açık tut" açıksa ekran kararmaz; çeviri durunca bu kalkar.
- Uygulama her öne geldiğinde telefon uygulamasının yeni sürümüne bakılır (ağa en çok 3 saatte bir çıkılır).
- Uygulama açılınca ve her TV bağlandığında TV'deki Nino'nun sürümüne bakılır; eskiyse ana ekranda güncelleme kartı çıkar.
- Her ekran değişimi anonim ölçüme ekran adı olarak gider.
- Ana pencere **hep dikeydir** (tablette de). Yalnız tam ekran altyazı penceresi yataydır (sensöre göre iki yatay yön).
  Ana pencere tek örnek çalışır (bildirimden ya da başlatıcıdan açılınca aynı pencere öne gelir).

---

## 4. Açılış animasyonu

Uygulama her açıldığında (ekran döndürülünce yeniden oynamaz) gezinme ekranlarının **üstünü kaplar**; bitince kaybolur ve
altındaki ilk ekran görünür.

**Düzen (ekranın tam ortasında, dikey):**
1. Logo grubu (üst üste, ortalı):
   - 300 dp daire: `#0070D1` %35'ten saydama radyal ışık.
   - 270 dp dönen halka: 3 dp çizgi, açısal degrade (saydam → `#0070D1` → `#1A86E8` → saydam → saydam); 2,4 sn'de bir tam
     tur, doğrusal, sonsuz.
   - Logo `nino_logo.png`, 230 dp.
   - Logonun üst ortasındaki bayrağın üstünde, 62 dp yukarıda 120×70 dp kırmızı parıltı: `#F21F29` %75'ten saydama radyal.
2. 28 dp boşluk.
3. "Nino" (gömülü metin) 34 sp kalın `#0A1430`.
4. 6 dp boşluk.
5. `nino_games_now_in` (seçili çeviri dilinin adı, ör. "Türkçe"), 15 sp `#55607A`.

Zemin: ekran zemini (1.1).

**Zaman çizelgesi:**
- 0 ms: logo, halka ve ışık 0'dan 1'e yaylanarak gelir (yay sönümü 0,62, sertlik 120, yani hafif sekerek). Logo %72
  boydan %100'e büyür, opaklığı artar; başta 14 dp bulanıktır, netleşir (%95'ten sonra bulanıklık tümüyle kalkar).
- 650 ms: yazılar 600 ms'de (hızlı başlayıp yavaş biten eğri) belirir ve 12 dp aşağıdan yerine kayar. Aynı anda bayrak
  parıltısı iki kez yanıp söner: 500 ms'de 1'e, 500 ms'de 0,15'e (×2; parıltı opaklığı bunun %85'i).
- Ardından 250 ms bekleme.
- Çıkış: 420 ms'de tüm grup saydamlaşır ve %106'ya büyür. Toplam yaklaşık **3,3 sn**.

**Animasyon kapalıysa:** her şey hemen tam görünür, 900 ms sonra biter.

Aynı animasyon, Salon ana ekranındaki çizili TV'nin içinde, fiş takılınca küçültülmüş olarak da oynar (bkz. 7.2).

---

## 5. Yüzen robot düğmesi ("Nino'ya Sor") ve "Çeviri başladı" balonu

### 5.1 Robot düğmesi
- **Görünür olduğu ekranlar:** Ana ekran, Karşılama, Konsol türü, PSN girişi, PS5 eşleme, Altyazılar nerede, Microsoft
  girişi, Xbox seçimi, TV'ye kurulum, Görüntü kaynağı. Açılış animasyonu sürerken görünmez.
- **Yer:** sağ alt köşe; sağdan 20 dp, gezinme çubuğunun üstünden ana ekranda 96 dp, diğerlerinde 92 dp yukarıda (alttaki
  birincil düğmenin üstünde durur). Sağdan sola arayüzde sol alta geçer.
- **Görünüş:** 60 dp daire, beyaz %94 zemin, 1 dp `#D3DEEF` kenar, 14 dp gölge (`#00205B` %25–30). İçinde 46 dp robot
  görseli `nino_bot.png`.
- **Canlanma:** robot 1,6 sn'de 3 dp yukarı çıkıp iner (gidip gelir, sonsuz). Her 4,5 sn'de 150 ms göz kırpar (görsel
  `nino_bot_blink.png` ile değişir). Animasyon kapalıysa ikisi de durur.
- **Dokununca:** "Nino'ya Sor" yardımcı ekranı açılır (zaten açıksa ikinci kopya açılmaz). Erişilebilirlik adı
  `assistant_title`.

### 5.2 "Çeviri başladı" balonu
- Çeviri başladığı an ölçülür; **7 sn** boyunca görünür. Ekran dönse ya da ekrana geri gelinse 7 sn geçtiyse yeniden çıkmaz.
- Metin `translation_started_notice`; 14/18 sp kalın beyaz, siyah
  %55 hap zemin, iç boşluk 14×8. Ekran okuyucuya kibarca duyurulur.
- **Robot görünüyorsa:** robotun solunda; sağdan 90 dp (20 + 60 + 10), robotla aynı alt hizada, en az 60 dp yükseklikte
  dikey ortalı, en çok 250 dp genişlik, sola 20 dp pay.
- **Robot yoksa:** ekranın üst ortasında, durum çubuğunun 12 dp altında, yanlardan 20 dp.
- Giriş: genişliğinin üçte biri kadar sağdan kayarak + belirerek; çıkış: 600 ms'de solarak.
- Açılış animasyonu sürerken görünmez.

---

## 6. Kurulum ekranları

### 6.1 Karşılama (3 sayfa)

**Üst çubuk** (Arapça arayüzde de soldan sağa dizilir): solda uygulama simgesi 36 dp; sağda **çeviri dili seçici** (küçük
hap, bkz. 10) ve son sayfa dışında `skip` metin düğmesi. "Atla" = son sayfadaki "Başlayalım" ile aynı iş.

**Orta:** yatay kaydırmalı üç sayfa; kendiliğinden geçiş yok. Her sayfada içerik **aşağıya yaslıdır**: üstte esnek boşluk,
sonra görsel, 12 dp, sonra ekran başlığı (2.6, adım satırı yok).

- **Sayfa 1:** 380 dp yüksekliğinde **örnek altyazı sahnesi** (6.1.1). Başlık `welcome1_title`; açıklama `welcome1_body`
- **Sayfa 2:** 380 dp koyu sahne kartı, içinde üç cam satır (alt alta, 10 dp ara):
  1. rozet "GTA", başlık "Grand Theft Auto V", açıklama `welcome2_gta`, etiket `packs_free`
  2. rozet "RDR", başlık "Red Dead Redemption 2", açıklama `welcome2_rdr_lines`, etiket "Ücretsiz"
  3. rozet "MAF", başlık "Mafia", açıklama `welcome2_maf_lines`, etiket "Ücretsiz"

  (Rozet ve oyun adları gömülü metindir.) Başlık `welcome2_title`; açıklama `welcome2_body`
- **Sayfa 3:** 380 dp koyu sahne kartı: üstte yan yana iki cam seçenek kutusu (10 dp ara, eşit genişlik):
  TV simgesi + `welcome3_tv` + `welcome3_tv_label`; telefon simgesi + `welcome3_phone` + `welcome3_phone_label`. Altında rozetsiz cam satır: `welcome3_wifi` / `welcome3_wifi_body`. Başlık `welcome3_title`; açıklama `welcome3_body`

**Alt bölge:** sayfa noktaları (yatayda ortalı, aralar 8 dp): etkin sayfa 24×8 dp `#0A1430` hap, diğerleri 8×8 dp
`#0A1430` %18 daire. Altında birincil düğme: ilk iki sayfada `next` (sonraki sayfaya animasyonla kayar), son
sayfada `welcome_start`.

**Bitince:** karşılama "görüldü" olarak kaydedilir, kullanıcının ölçüm tercihi uygulanır, 3.2'ye göre ilerlenir.

#### 6.1.1 Örnek altyazı sahnesi
- 28 dp köşeli koyu sahne kartı (2.14'teki gibi degrade, kenar ve gölge). İçinde iki yumuşak ışık: sağ üstte (%75, %30)
  `#FF9A4A` %16, yarıçap genişliğin %35'i; solda (%20, %45) `#0070D1` %22, yarıçap %40.
- Sol üstte 12 dp içeride rozet: `nino_sample`; 11 sp kalın beyaz, harf aralığı 1,5 sp (Arapça yazıda 0),
  siyah %40 hap, 1 dp beyaz %20 kenar, iç boşluk 10×4.
- Alt ortada (20 dp yukarıda) sonsuz döngü:
  1. İngilizce satır 300 ms'de belirir (15 sp, `#F4F1E8`).
  2. 900 ms bekler.
  3. Çeviri satırı yaylanarak gelir (sönüm 0,8, sertlik 300): 17 sp 600 beyaz, siyah %72 zemin, 10 dp köşe, iç boşluk
     14×6; %96'dan %100'e büyür. Çeviri belirdikçe İngilizce satır aynı oranda kaybolur (ikisi aynı yerde üst üste).
  4. 2,6 sn bekler; ikisi 250 ms'de söner; 450 ms bekler; sıradaki satıra geçer.
- Satırlar seçili çeviri diline göredir. Türkçe ve Arapçada beş İngilizce örnek satır (`SampleLines`: fener, ayak
  sesleri, dışarıda biri var mı, sis, harita ve iskele) ve o dildeki çevirileri; diğer dillerde bunlardan üçü (dışarıda
  biri var mı, ayak sesleri, harita ve iskele). Satırlar ve çeviriler yeni uygulamanın kendi metnidir
  (`SampleSubtitleScene.kt`). Arapça/Urduca metin sağdan sola işaretlenir.

### 6.2 PS5 eşleme

**Üst çubuk:** geri (varsa) ve sağda "Şimdilik Atla" (yalnız ilk kurulumda).

**İçerik (yukarıdan aşağı):**
1. Ekran başlığı: adım `setup_step` (2), `pair_title`, `pair_body`
2. **Bulunan PS5'ler:**
   - Henüz arama sonucu yok: karo, içinde `pair_searching` (15 sp ikincil).
   - Arandı, bulunamadı: karo; `pair_searching` (17 sp 600), altında `pair_still_searching` (13 sp
     ikincil), altında metin düğmesi `pair_search_again` (listeyi "aranıyor" hâline döndürür, aramayı
     baştan başlatır).
   - Bulundu: her PS5 için bir karo; seçili olan etkin kenarlı. Solda onay simgesi (karo simgesi, `#1E6B45`), yanında
     `pair_found` (PS5 adı; 17 sp 600) ve `pair_same_wifi` (IP adresi; 13 sp).
     Karoya dokununca o PS5 seçilir.
3. (Elle giriş açıksa) metin alanı `pair_address`, adres klavyesi.
4. (Adres geçersizse) uyarı karosu `address_invalid`
5. Kod karosu: etiket `pair_code`, 8 kod kutusu (2.11), not `pair_code_note`
6. (Hata varsa) uyarı karosu `pair_failed` (neden; varsa ayrıntı parantez içinde eklenir).
7. (Bağlanırken) `pair_working` (15 sp ikincil).

**Alt bölge (yukarıdan aşağı):**
- Elle giriş kapalıyken metin düğmesi `pair_not_found` → elle adres alanını açar.
- İlk kurulumda metin düğmesi `demo_try` → örnek altyazılı deneme oturumunu başlatır ve "Şimdilik
  Atla" ile aynı yoldan ilerler (kurulum bitmemişse Altyazılar nerede, sonra ana ekran).
- Birincil `pair_button`. Etkin olması için: bağlanma sürmüyor, 8 hane girilmiş ve adres boş değil.

**Arama davranışı:** Ekran açık kaldıkça ağda PS5 aranır (her arama 2,5 sn). Bulunamazsa 1,5 sn, bulunursa 6 sn sonra
yeniden aranır; PS5 sonradan açılır ya da uyanırsa kendiliğinden listeye düşer. Henüz adres seçilmemişse ilk bulunan
kendiliğinden seçilir ve elle giriş kapanır. Hiç PS5 bulunamazsa elle adres alanı kendiliğinden açılır. Eski eşlemeden
kalma adres varsa alan onunla dolu gelir.

**Bağlan'a basınca:** Elle yazılan adres temizlenir (port, "http://", virgüllü yazım düzeltilir); adres değilse 4. madde
çıkar ve durur. Sonra eşleme denenir; başarılıysa PS5 kaydedilir ve ilerlenir (3.2). Hata nedenleri:

| Durum | Anahtar = metin |
|---|---|
| Hesap tanınmadı | `regist_wrong_account` |
| Kod yanlış | `regist_wrong_code` |
| Başka oturum | `regist_in_use` |
| Sürüm uyumsuz | `regist_version` |
| Remote Play çöktü | `regist_crashed` |
| Adres çözülemedi | `regist_bad_address` |
| Yanıt yok | `regist_no_answer` |
| Kod alındı, yanıt yok | `regist_no_reply` |
| Diğer | `regist_failed` |

Beklenmeyen bir hatada hatanın kendi iletisi yazılır.

### 6.3 Altyazılar nerede görünsün?

**Üst çubuk:** geri (varsa).

**İçerik:**
1. Ekran başlığı: `target_title`, `target_body`; adım satırı (3) yalnız ilk kurulumda.
2. 250 dp koyu sahne kartı, içinde yan yana iki **seçilebilir cam kutu** (10 dp ara):
   - TV simgesi, `target_tv_short`; açıklama: ağda TV aranırken `target_searching`,
     hiç bulunamazsa `target_tv_over_game`, bulunduysa TV adları virgülle.
   - Telefon simgesi, `target_phone`; açıklama `target_phone_note`.
3. Seçime göre açıklama (15/21 sp ikincil): TV → `target_tv_body`; telefon →
   `target_phone_body`
4. TV seçiliyse ikincil düğme `tv_install_button` → TV'ye kurulum ekranı.
5. Metin düğmesi `target_unlisted` → tarayıcıda `url_tvs` adresini açar (kurulum belgesinin TV
   bölümü).

**Alt bölge:** birincil `next_continue`: seçim kaydedilir; TV bulunduysa ilk bulunan TV'nin adı saklanır; kurulum
bitti işaretlenir; ilerlenir. Açılışta seçili olan, kayıtlı tercihtir. TV araması ekran açılınca bir kez yapılır.

### 6.4 Görüntü kaynağı (Ayarlar › Görüntü Kaynağı)

**Üst çubuk:** geri (varsa).

**İçerik:**
1. Ekran başlığı: `settings_video_source`, `source_body`
2. Koyu sahne kartı (yakalama kartı seçiliyken 316 dp, değilken 250 dp); içinde yan yana üç seçilebilir cam kutu:
   - oyun kolu simgesi, "PS5" (gömülü), `source_ps5_detail`
   - gamepad simgesi, "Xbox" (gömülü), `source_xbox_detail`
   - USB simgesi, `capture_card`, `source_card_detail`

   Yakalama kartı seçiliyse altında cam satır, rozet "USB": kart takılıysa `capture_found_title`,
   `capture_found_detail` (kartın çözünürlüğü, bilinmiyorsa "—"), etiket `capture_ready`; takılı değilse `capture_missing_title`, `capture_missing_detail`, etiketsiz.
3. Seçime göre açıklama (15/21 sp ikincil): `source_ps5_body` / `source_xbox_body` / `source_card_body`
4. Yalnız yakalama kartında: kart bir kez arandıktan sonra hâlâ yoksa uyarı karosu `capture_not_found`; ardından not
   `source_hdcp` (13/18 sp ikincil).

Takılı kart ekran açıkken her 1,5 sn'de yeniden aranır (sonradan takılan kart kendiliğinden görünür).

**Alt bölge:** birincil `save`. Yakalama kartı seçili ve kamera izni yoksa önce izin istenir; cevap ne olursa
olsun seçim kaydedilir. Kaydederken, kaynak artık kart değilse ya da izin varsa önceki "kamera izni yok" uyarısı
silinir. Sonra 3.2'deki "Görüntü kaynağı kaydedildi" kuralı.

Ayarlar satırında görünen kısa adlar: `capture_card`, `source_xbox`,
`source_remote_play`.

---

## 7. Ana ekran

İki görünümü vardır; kullanıcı Ayarlar › `nino_interface` bölümünden seçer: `nino_home_living_room`
(**varsayılan**; bu sürüme geçen herkes bir kez Salon'a alınır) ve `nino_home_toggle` (aşağıda
"kaydırmalı ana ekran" diye anılır). İki görünümün ortak kabuğu:

**Üst çubuk:** solda uygulama simgesi; sağda (12 dp ara) Geçmiş (saat-geri simgesi), Ayarlar (dişli), Profil (kişi)
simge düğmeleri.

**Kaydırılan içerik, yukarıdan aşağı:**
1. Çeviri kapalıyken ve TV'deki uygulama eskiyse: **TV güncelleme kartı** (11.2).
2. Çeviri kapalıyken ve telefon uygulamasının yeni sürümü varsa: **Uygulama güncelleme kartı** (11.1).
3. Seçili görünüm (7.2 ya da 7.3).
4. Hata varsa uyarı karosu (ör. kamera izni yok, yakalama kartı sorunu).

Üstüne, ilk ziyarette **tanıtım turu** biner (7.5). Sağ altta robot düğmesi durur (5).

**Kavramlar (ikisinde ortak):**
- **Eşli:** kaynak yakalama kartıysa her zaman eşli; Xbox'ta Microsoft girişi yapılmış ve Xbox seçilmişse; PS5'te eşli
  PS5 varsa.
- **Kaynak adı:** kartta "Capture Card", Xbox'ta Xbox'ın adı, PS5'te PS5'in adı. Konsol etiketi: "Xbox" ya da "PS5".
- **Durum:** çeviri açık ve görüntü geliyorsa **Canlı**; çeviri açık ama görüntü henüz yoksa **Bağlanıyor**; kapalı ve
  eşliyse **Hazır**; değilse **Bağlı Değil**.
- **Kilitli dokunuş:** eşli değilken başlatma denetimine dokunmak, kaynak kartsa Görüntü kaynağını, değilse eşleme akışını
  açar.

### 7.1 Ortak başlık: durum satırı + büyük başlık
Üstten 8 dp boşlukla:
- **Durum satırı:** 8 dp renkli nokta + 8 dp + 14 sp 500 `#55607A` yazı, tek satır, sığmazsa "…". Yazı "‹ad›  ·  ‹durum›"
  (iki yanında çift boşluklu orta nokta); Bağlı Değil durumunda yalnız durum. Örnek oturumda ad yerine `demo_name`.

  | Durum | Nokta rengi | Yazı |
  |---|---|---|
  | Bağlı Değil | `#55607A` | `home_not_paired` |
  | Hazır | `#0070D1` | `home_ready` |
  | Bağlanıyor | `#0070D1` (bağlanamama nedeni varsa `#9A4A08`) | `home_connecting` |
  | Canlı | `#30C578` | altyazı TV'deyse `home_status_tv`, değilse `home_live` |

  Bağlanıyor ve Canlı'da nokta 900 ms'de %100 ↔ %30 opaklık arasında gidip gelir.
- 6 dp.
- **Başlık:** 34/40 sp kalın, harf aralığı −0,6 sp, `#0A1430`. Durum değişince eskisi 200 ms'de söner, yenisi 300 ms'de
  belirir.
  - Bağlı Değil: `home_title_pair` (Xbox'ta `xbox_home_title_pair`)
  - Canlı: `home_title_live`
  - Hazır / Bağlanıyor: `home_title_ready` (çeviri dilinin adı: `nino_lang_tr`,
    `nino_lang_ar`, diğer diller kendi dillerindeki adla)

### 7.2 Salon görünümü (varsayılan)

Yukarıdan aşağı:
1. Ortak başlık (7.1).
2. 14 dp.
3. **Salon sahnesi** (7.2.1). Arapça arayüzde de aynalanmaz.
4. 10 dp.
5. Satır (en az 36 dp, dikey ortalı, 10 dp ara): solda **ipucu** (13/18 sp 500 `#55607A`, kalan genişlik):
   - çeviri açıkken `nino_unplug_to_stop`
   - eşliyken `nino_plug_to_start` (dil adı)
   - değilse `nino_pair_first`

   Sağda, çeviri açıkken belirip kaybolan **Tam Ekran hapı**: beyaz %72 hap, 1 dp beyaz kenar, en az 36 dp, iç boşluk
   12×7, 16 dp genişlet (OpenInFull) simgesi `#0070D1` + 6 dp + `home_full_screen` 13 sp 600 `#0070D1`.
   Altyazı TV'ye gitse de görünür; telefonda tam ekran altyazıyı açar.
6. Eşli değilken ve çeviri kapalıyken, 14 dp üstte **"PS5'siz Deneyin" düğmesi** (7.4.2).
7. Çeviri açıkken ve altyazı telefondaysa (ya da örnek oturumdaysa), 14 dp üstte **döndürme ipucu** (7.4.3).
8. Boşluk: eşli değil ve kapalıysa 18 dp, değilse 22 dp.
9. **Üç kısa yol** (7.4.1). Çıkış kısa yolunun değeri: TV'deyse ve en az bir TV bağlıysa `nino_tv_connected`,
   bağlı TV yoksa "TV"; telefondaysa `nino_phone`.

#### 7.2.1 Salon sahnesi
Duvara asılı bir TV, altında uzun metal sehpa, sehpanın sağında konsol, sağda duvarda priz. Konsoldan çıkan kablonun
ucundaki **fiş** prize takılınca çeviri başlar, çekilince durur.

**Görsel:** konsol PS5 ise `living_room.png`, Xbox ise `living_room_xbox.png` (ikisi de 1672×941 piksel, saydam zemin;
aynı TV, sehpa ve priz). Aşağıdaki koordinatlar **görsel pikseli** cinsindendir; sahne ekran genişliğine sığacak gibi
ölçeklenir: ölçek = genişlik / (1672 + 40) (sağda fişe 40 piksel pay). Görsel sol üste yaslı, 1672×941 × ölçek boyda.

| Ölçü | PS5'li salon | Xbox'lı salon |
|---|---|---|
| TV'nin ekran alanı (sol, üst, en × boy) | 149, 40, 1151 × 595 | 136, 40, 1185 × 596 |
| TV çerçevesi | 139, 27, 1171 × 621 | 121, 26, 1214 × 630 |
| Sehpa | 49, 713, 1502 × 160 | 43, 733, 1580 × 167 |
| Prizin ortası (fişin takıldığı yer) | 1564, 378 | 1561, 381 |
| Kablonun başladığı yer | 1550, 734 | 1572, 722 |
| Çıkık fişin sarktığı yer | 1600, 885 | 1646, 912 |

- PS5 görselinde kablonun ilk parçası resimde vardır; çizilen kablo onun üstünden geçer ki ek yeri görünmesin: kırık çizgi
  (1490,706) → (1522,706) → (1535,709) → (1545,716) → (1552,727); oradan çıkış yönü (0,5 ; 0,87). Xbox görselinde kablo
  yoktur: kablo konsolun arkasındaki girişte 14×12 piksel, 3 piksel köşeli `#141414` küçük bir fiş başından çıkar;
  çıkış yönü (1 ; 0,1).
- **Fiş büyütme:** fiş görselde çok küçük kalır; telefonda büyütülür: oran = 0,3 ÷ (bir görsel pikselinin dp karşılığı),
  1 ile 1,6 arasında sınırlı.
- **Sahne yüksekliği:** en büyüğü (941, sarkma noktasının y'si + 46 × büyütme) × ölçek, artı 6 dp (sarkan fiş alttaki
  yazının üstüne binmesin).

**Katmanlar (arkadan öne):**
1. **LED ışıkları** (görselin arkasında, saydam kenarlardan taşar); yalnız fiş takılıyken, 800 ms'de yanar/söner.
   - TV'nin arkasında duvara vuran ışık: TV çerçevesinden 10, 22, 34 … 82 piksel taşan 7 yuvarlak dikdörtgen (köşe
     30 + taşma), içten dışa opaklık %11'den %6'ya; üstüne çerçeveden 5 piksel taşan ince parlak kenar (%55, köşe 12).
   - Sehpanın alt kenarında şerit: 6 katman (yükseklik 10–50 piksel, opaklık %14'ten %8'e) ve 6 piksel yüksek parlak çizgi.
   - Renk: geniş ışık `#1F5CFF`, ince ışık `#738CFF`. Oynanan oyun "öncelikli havuz oyunu" (GTA 6) olarak tanınınca 1,2
     sn'de soldan sağa degradeye döner: geniş `#FF3D9E` → `#BD80F5` → `#4DC7FF`, ince `#FF85C7` → `#D6B3FF` → `#94E0FF`.
2. **Priz ışığı** (yalnız fiş takılı değilken; fiş takılınca 500 ms'de söner): prizin çevresinde kenarları yumuşak iki
   kare. Geniş: `#4DA8FF`, kenarı priz (86 piksel) + 26, köşe 16, 18 piksel yumuşaklık, opaklık %30 ↔ %95. Dar:
   `#9ED6FF`, kenar + 8, köşe 12, 5 piksel yumuşaklık, opaklık %45 ↔ %100. 950 ms'de gidip gelen yumuşak nabız
   (yavaş başlayıp yavaş biten). Animasyon kapalıysa sabit, parlak yanar.
3. **Salon görseli.**
4. **TV ekranının içi:** ekran alanında siyah zemin, kırpılır. İçerik 420 dp genişlikte (yükseklik orantılı) bir "sanal
   TV" olarak çizilip ekran alanına küçültülür. Duruma göre:
   - fiş takılı değil → **bekleme ekranı** (7.2.2);
   - fiş takıldı, görüntü henüz gelmedi → **TV açılış animasyonu**: uygulamanın açılış animasyonu (4) 820×424 dp sanal
     alanda oynatılıp TV'ye sığdırılır; bitince sıradakine geçilir;
   - sonra → **canlı TV ekranı** (7.4.4), sağ üstte sayarak çıkan toplam indirme göstergesiyle.
5. **Kablo:** `#0F0F0F`, 8 piksel kalın, yuvarlak uçlu. Kablonun başından fişe tek eğri:
   - fiş çıkıkken: fişin arkasına, fişin ekseni boyunca girer (fiş gövdesinin 40 × büyütme kadar gerisi). Kablonun
     serbest boyu 330 pikseldir; fiş kablo başına yaklaştıkça artan boy × 0,45 kadar aşağı sarkar.
   - fiş takılıyken: fişin 30 piksel altından, aşağıdan kıvrılarak prize çıkar.
6. **Fiş** (ölçüler görsel pikseli × büyütme):
   - Çıkıkken: üstte 16×14 kablo boğazı (`#0F0F0F`, köşe 6), altında 36×50 gövde (soldan sağa `#383838` → `#0A0A0A`,
     köşe 9), altında iki metal uç 6×24 (köşe 3, `#EBEBEB` → `#999999`), merkezden ±10 yanda. Fiş kendi ortası çevresinde
     döner: dinlenirken uçlar aşağı bakar; prize yaklaştıkça yumuşakça prize döner, prize 120 piksel kala tam dönmüştür.
     Sürüklenirken %8 büyük çizilir.
   - Takılıyken: prizin önünde 29 yarıçaplı yuvarlak kapak: altında 4 piksel aşağıda siyah %35 gölge, köşeden köşeye
     `#3D3D3D` → `#0A0A0A` dolgu, 1,5 piksel beyaz %18 kenar.

**Hareket:**
- Fiş, takılı ve çıkık yerleri arasında yayla gider (sönüm 0,78, sertlik 158: prize hafif taşıp oturur).
- **Açılış gösterisi:** uygulama her açıldığında ana ekran ilk göründüğünde bir kez: fiş 0,9 sn çıkık görünür (çeviri zaten
  açık olsa da), sonra daha yumuşak bir yayla (sönüm 0,7, sertlik 130) prize takılır; bu yumuşak yay 1,2 sn geçerlidir.
  Bu sürede toplam indirme sayısı görünmez. Ayarlardan dönünce yeniden oynamaz. Animasyon kapalıysa bekleme yok, fiş
  anında yerine geçer.

**Dokunma:**
- Prizin ve fişin üstünde 64 dp'lik dokunma alanları vardır (sahne dışına taşmaz). Fişin alanı fişin dinlendiği yerde
  durur (prizde ya da sarkma noktasında).
- Prize ya da fişe **dokunmak**: çeviri açıksa durdurur; kapalıysa eşliyse başlatır, değilse kilitli dokunuş.
- Fişi **sürüklemek**: parmakla gider; bırakınca fişin dinlendiği yere göre son konum prize 160 pikselden yakınsa
  "takılı", değilse "çıkık" sayılır; bu, şimdiki durumdan farklıysa aynı aç/kapa işi yapılır. Fiş yayla (sönüm 0,75)
  yerine döner.
- Tüm sahne ekran okuyucuya tek düğme olarak görünür; adı çeviri açıksa `nino_unplug_to_stop`, değilse `nino_plug_to_start`.

**Toplam indirme sayısı:** ana ekran açıkken açılışta ve sonra en çok 10 dakikada bir sunucudan alınır; alınamazsa son
bilinen sayı kalır, hiç alınamadıysa gösterge hiç çıkmaz.

#### 7.2.2 TV bekleme ekranı (fiş takılı değilken)
Siyah. Ortada `nino_plug_drag_hint`: 16/23 sp, 600, eş aralıklı (monospace) yazı
tipi, harf aralığı 2,5 sp (Arapça yazıda 0), beyaz %45, ortalı, yanlardan 56 dp boşluk (sanal TV ölçüsünde; iki satıra
kırılır). Sağ üstte 18 dp içeride toplam indirme göstergesi (7.4.5), sayma animasyonsuz.

### 7.3 Kaydırmalı ana ekran ("Cam düğme")

Yukarıdan aşağı:
1. Ortak başlık (7.1).
2. 20 dp.
3. **Sahne kartı** (7.3.1).
4. 22 dp.
5. **Kaydırma çubuğu** (7.3.2).
6. Bağlı Değil durumunda, 12 dp üstte "PS5'siz Deneyin" düğmesi (7.4.2).
7. Canlıyken ve altyazı TV'de değilken, 14 dp üstte döndürme ipucu (belirip kaybolarak).
8. 28 dp.
9. Üç kısa yol (7.4.1). Çıkış değeri: TV'deyse "TV", telefondaysa "Telefon".

#### 7.3.1 Sahne kartı
Tam genişlik, en az 196 dp, 28 dp köşe, 28 dp koyu gölge, `#151E36` → `#06080F` dikey degrade, 1 dp degrade kenar
(beyaz %22 → %3). İçerik geçişi: yeni 400 ms'de belirir, eski 250 ms'de söner.
- **Canlı:** canlı TV ekranı (7.4.4), 196 dp yükseklikte, soldan sağa. Altyazı TV'de değilse karta dokunmak tam ekran
  altyazıyı açar ve sağ üstte **Tam Ekran düğmesi** belirir (300 ms'de belirir, 200 ms'de söner): 12 dp içeride hap,
  dikey degrade beyaz %26 → %10, 1 dp degrade kenar beyaz %55 → %12, 12 dp siyah gölge, iç boşluk sol 12 / sağ 14 /
  dikey 8; 20 dp tam ekran simgesi beyaz + 6 dp + "Tam Ekran" 14 sp 600 beyaz.
- **Canlı değil:** ortalı tek yazı, yanlardan 22 dp, dikeyde 24 dp (neden yazısında 18 dp):
  - Bağlanırken bir neden biliniyorsa (ör. `phase_in_use`; uyarı karosunda zaten yazan metin
    tekrarlanmaz): 14/20 sp 500 beyaz %85, çok satırlı, ortalı; uzunsa kart aşağı doğru uzar.
  - Değilse: Bağlanıyor'da `home_connecting`, diğerlerinde `home_stage_idle`; 15 sp 500 beyaz %42.

#### 7.3.2 Kaydırma çubuğu
68 dp yüksek tam genişlik hap; içinde 56 dp beyaz yuvarlak tutamaç, kenarlardan 6 dp.
- **İz:** `#0A1430` zemin; üstüne çeviri diline göre renkli dikey degrade, opaklığı tutamacın ilerlemesi kadar; üst yarıda
  beyaz %22 × ilerleme parlaklık; 1 dp beyaz %10 kenar; ilerledikçe artan renkli gölge (16 dp).
  Dil renkleri (üst → alt): Arapça, Urduca, Bengalce `#0B8A4A` → `#056236`; Hintçe, Felemenkçe `#F08A1C` → `#B85F00`;
  Tayca, Malayca, Filipince `#2D4FB3` → `#1A3380`; diğerleri (Türkçe dahil) `#E30A17` → `#A80514`.
- **Yazı:** tutamaçtan sonraki alanda ortalı, 17 sp 600; üzerinden soldan sağa geçen bir ışıltı (2,2 sn'de bir, doğrusal,
  sonsuz; yazı beyaz %55'ten beyaza parlar; sağdan sola arayüzde sağdan sola geçer). Kapalıyken tutamaç ilerledikçe yazı
  kaybolur.
  - Bağlı Değil: `slide_pair`
  - Hazır: `slide_start`
  - Bağlanıyor / Canlı: `slide_stop`
- **Tutamaç:** beyaz daire, 10 dp gölge. İçinde 24 dp sağ ok `#0A1430` (ilerledikçe kaybolur); Bağlanıyor'da ok yerine
  22 dp dönen halka (`#0070D1`, 2,5 dp). İlerledikçe tutamaç **camlı bayrak küresine** döner: Türkçede `#E30A17` dolgu
  üzerinde 34 dp beyaz ay yıldız; diğer dillerde o dilin bayrak emojisi daireyi dolduracak kadar büyük, kırpılmış; üstünde
  çapraz beyaz degrade 2 dp kenar ışığı ve üst solda beyaz %60 parlama oval.
- Açık (Bağlanıyor/Canlı) durumda tutamaç sağ uçtadır; konum değişimi yayla (sönüm 0,82, sertlik 320).
- **Sürükleme bırakılınca:** Bağlı Değil'de yarıdan ötedeyse kilitli dokunuş; kapalıyken %85'ten ötedeyse başlat; açıkken
  %15'ten berideyse durdur. Tutamaç yayla (0,8) yerine döner. **Tutamaca dokunmak** da aynı işi yapar (Bağlı Değil →
  kilitli dokunuş, Hazır → başlat, diğer → durdur).
- Sağdan sola arayüzde tutamaç sağda başlar, sola kaydırılır.
- Ekran okuyucuda düğme; adı yazıyla aynı.

**Ay yıldız çizimi** (kare alan, kenar s): beyaz ay = (0,42s ; 0,5s) merkezli 0,42s yarıçaplı daire, içinden zemin
renginde 0,8 kat yarıçaplı, 0,32 × yarıçap sağa kaymış daire oyulur. Beyaz beş köşeli yıldız (0,8s ; 0,5s) merkezli, dış
yarıçap 0,17s, iç yarıçap dışın 0,382 katı, bir ucu aya bakar.

### 7.4 Ana ekran parçaları

#### 7.4.1 Üç kısa yol
Yan yana üç eşit, aynı yükseklikte kutu (10 dp ara). Her biri: beyaz %72 zemin, 20 dp köşe, 1 dp beyaz kenar, iç boşluk
yatay 12 / dikey 14; üstte 22 dp `#0070D1` simge, 10 dp, ad 12 sp `#55607A`, değer 14 sp 600 `#0A1430` tek satır "…".

| Simge | Ad | Değer | Dokununca |
|---|---|---|---|
| Oyun kolu (SportsEsports) | "PS5" / "Xbox" | kaynak adı, yoksa `profile_not_paired` | eşleme akışı / Görüntü kaynağı |
| TV ya da telefon | `nino_output` | bkz. 7.2 / 7.3 | Altyazılar nerede |
| Kutu (Inventory2) | `nino_packs` | paketler açıksa "Ücretsiz", kapalıysa "—" | Oyun paketleri |

#### 7.4.2 "PS5'siz Deneyin" düğmesi
Yatayda ortalı hap biçimli dokunma alanı (en az 48 dp, iç boşluk 16×10): 20 dp ışıltı (AutoAwesome) simgesi `#0058A8` +
8 dp + `demo_try` 17 sp 600 `#0058A8`. Dokununca örnek altyazılarla deneme oturumu başlar (konsol
gerekmez).

#### 7.4.3 Döndürme ipucu
Ortalı satır: 18 dp ekran döndürme simgesi `#55607A` + 8 dp + `home_rotate_hint` 14 sp `#55607A`.

**Yan çevirince tam ekran:** Yalnız çeviri açıkken ve altyazı telefondayken (ya da örnek oturumda) çalışır; ekran dönmez,
telefonun yönü algılayıcıdan okunur. Dik = 0–25° ya da 335–360°; yan = 65–115° ya da 245–295°. Telefon bir kez dik
tutulduktan sonra ("kurulu") yan duruma geçip orada **0,7 sn** kalırsa ve uygulama öndeyse tam ekran altyazı açılır.
Açılınca kurulum düşer: tam ekrandan dönünce telefon önce yeniden dik gelmeden tekrar açılmaz (masadaki titreme
yanlışlıkla açmasın).

#### 7.4.4 Canlı TV ekranı
Hem Salon'daki TV'nin içinde hem kaydırmalı ekranın sahne kartında kullanılır. Hep soldan sağa.
- **Zemin:** köşeden köşeye `#171F3D` → `#26172E`. Oynanan oyun öncelikli havuz oyunuysa (GTA 6) bunun yerine gün batımı
  fonu: yukarıdan aşağı `#1A1457` (0) → `#75299E` (%40) → `#ED4A99` (%74) → `#FF8C7A` (%100), üstüne siyah %28. Güneş,
  bulanıklık ya da oyun görseli yoktur.
- İç boşluk 18 dp.
- **Sol üst CANLI rozeti:** siyah %40 hap, iç boşluk 10×4, 8 dp `#E30A17` nokta + 6 dp + `nino_live` 11 sp kalın
  beyaz, harf aralığı 1,2 sp (Arapça yazıda 0).
- **Sağ üst:** (yalnız Salon'da) toplam indirme göstergesi, sayarak çıkar.
- **Alt orta** (8 dp yukarıda):
  - görüntü henüz gelmiyorsa bağlantı durumu (hizmetin o anki aşama yazısı, yoksa `nino_connecting_ps5`); 15 sp 500 beyaz %70, ortalı;
  - gösterilecek satır yoksa `nino_waiting_next` 15 sp 500 beyaz %55;
  - satır varsa: şu an görünen çeviri, yoksa son çeviri. 600 kalın beyaz, ortalı, en çok 3 satır "…"; boy uzunluğa göre:
    60 karaktere kadar 24 sp, 61–90 arası 20 sp, 90'dan uzun 17 sp. Siyah %72 zemin, 10 dp köşe, iç boşluk 16×8.

#### 7.4.5 Toplam indirme göstergesi
Sağa yaslı iki satır, aralar 1 dp. Oyunlardaki para göstergesi gibi: sistemin dar ve kalın yazı tipi (sans-serif
condensed, en kalın), hafif sağa eğik (−0,12; Arapçada eğimsiz), siyah çerçeveli.
- Üst: `nino_total_downloads`, 11 sp, harf aralığı 0,8 sp (Arapçada 0), beyaz, 1 dp siyah çerçeve.
- Alt: sayı, 27 sp, `#7BE87B`, 1,5 dp siyah çerçeve. Her ikisinin altında çerçeve kalınlığı + 1 dp aşağıda siyah %90 derinlik
  gölgesi. Sayı arayüz dilinin binlik ayırıcısıyla yazılır.
- **Sayarak çıkış** (yalnız canlı TV'de): sayı 1, 2, 3 diye 280 ms arayla başlar, sonra 1,55 sn'de hızlanarak (ilerleme
  üssü 2,6) toplama çıkar; sonda sayı arka kenarından (sağdan sola dillerde sol kenarından) %132'ye yaylanarak büyür (sönüm
  0,45, hızlı), 260 ms sonra yavaşça (sönüm 0,6) yerine döner; büyürken 14 dp yeşil ışıma (%95) yapar. Toplam 3 ya da
  daha azsa, ya da animasyon kapalıysa sayı doğrudan yazılır. Sayım sırasında sayı yenilenirse sayım yeni toplama sürer.
- Ekran okuyucu tek parça okur: `nino_total_downloads` + sayı.

### 7.5 Tanıtım turu

Ana ekran ilk açıldığında (tur bitirilmediyse/atlanmadıysa) dört adımlık bir tur gösterilir.
- **Karartma:** tüm ekran siyah %70. Vurgulanan öğenin çevresinde 6 dp payla 16 dp köşeli **delik**, kenarında 2 dp
  `#0070D1` çizgi.
- **Kart:** `#E6EDF8`, 22 dp köşe, iç boşluk 16 dp, ekran kenarından 20 dp + güvenli alan. Vurgulanan öğe ekranın aşağı
  kısmındaysa (üst kenarı 900 pikselden aşağıdaysa) kart üstte, değilse altta durur. İçerik (aralar 8 dp):
  1. Satır: solda "1 / 4" biçiminde sayaç (13 sp ikincil), sağda `skip` metin düğmesi.
  2. Başlık 17 sp 600.
  3. Açıklama 15 sp ikincil.
  4. Birincil düğme: `next`, son adımda `tour_done`.
- **Adımlar:**
  1. Başlatma denetimi (Salon sahnesi ya da kaydırma çubuğu): `tour1_title`. Metin ana
     ekran düzenine göre: kaydırmalı düzende `tour1_body`; Salon düzeninde (yeni uygulama)
     `tour1_body_plug`
  2. Çıkış kısa yolu: `tour2_title`, `tour2_body`
  3. Paketler kısa yolu: `tour3_title`, `tour3_body`
  4. Profil düğmesi: `tour4_title`, `tour4_body`
- "Atla" ya da son adımda "Tamam" → tur bir daha gösterilmez.

---

## 8. Oyun paketleri

**Üst çubuk:** geri, başlık `packs_title`, sağda etiket: liste boşken `packs_free`, doluyken
`packs_free_count` (paket sayısı).

**İçerik:**
1. `packs_auto` (15 sp ikincil)
2. Tek satırlık satır listesi: `settings_packs`, değer `packs_switch_note`, sağda anahtar (tüm paketleri açar/kapatır).
3. Yüklenirken `packs_loading`; yüklendi ve boşsa bilgi karosu `packs_none_yet`
4. İki sütunlu paket ızgarası (12 dp ara, satırdaki iki karo aynı yükseklikte; tek kalan karo yarım genişlikte). Her paket
   bir paket karosu (2.12):
   - Kısaltma / kısa ad: GTA V → "GTA" / "GTA V"; Red Dead Redemption 2 → "RDR" / "Red Dead 2"; Mafia: The Old Country →
     "MAF" / "Mafia: TOC"; Assassin's Creed Shadows → "ACS" / "AC Shadows"; Death Stranding 2 → "DS2" / "Death Str. 2";
     Call of Duty Modern Warfare 2019 → "MW" / "CoD MW 2019"; diğerleri: başlığın ilk üç harf/rakamı büyük harfle /
     başlığın tamamı.
   - Satır sayısı: 1000 ve üstü `lines_thousands` (en yakın bine yuvarlanır), altı `lines_count`.
   - Şu an oynanan paket: etkin kenar ve sağ üstte durum yazısı `packs_now`.
   - Paket kapalıysa (ve paketler açıkken) sağ üstte etiket `packs_off`.
   - Tüm paketler kapalıyken ya da bu paket kapalıyken karo %40 opak.
   - Karoya dokunmak o paketi açar/kapatır.
5. İçe aktarılmış paketler bölümü (kapsam dışı).
6. Bilgi karosu: yenile simgesi (karo simgesi), `packs_next` (17 sp 600), `packs_next_note` (13 sp).

**Alt bölge:** ikincil düğme `packs_refresh` → zorla yeniden indirir; liste yenilenir.

---

## 9. Telefonda tam ekran altyazı

Ayrı bir pencere. **Yatay** (sensöre göre iki yön), zemin her zaman **siyah**. Saat ve bildirim çubukları gizlidir
(kenardan kaydırınca bir an görünür); sistem çubuklarının simgeleri açık renk. Ekran açık kalır; açıldıktan 10 sn sonra
parlaklık %35'e (sistem parlaklığı zaten daha düşükse ona) kısılır.

Güvenli alan + 20 dp kenar içinde:

**Üst satır** (12 dp ara, dikey ortalı):
- Durum noktası + 4 dp + 13 sp 500 beyaz %75 yazı (tek satır "…"). Çeviri açık ve hizmetin aşaması
  `phase_streaming` ise "bağlı" sayılır. Bağlıysa nokta `#1E6B45` ve "canlı" halkası
  atar, yazı `subtitle_connected`; değilse nokta beyaz %40 ve yazı sırayla: hata varsa hata metni, çeviri
  açık ve bir aşama yazısı varsa o, yoksa `subtitle_waiting`.
- Kullanılan paket varsa paket etiketi `running_pack` (oyun adı).
- Boşluk.
- Bağlıyken simge düğmesi: henüz ekran çevirisi yoksa büyüteç (`screen_translate`), varsa çöp kutusu
  (`screen_remove`). Dokununca oyun ekranının tamamı çevrilir ya da çeviriler kaldırılır.
- Kapat (X) → pencere kapanır, ana ekrana dönülür.

**Orta** (dikeyde 40 dp pay bırakılmış alanda, ortada; satırlar arası 12 dp):
- **Önceki satır** (Ayarlar'da `settings_stack_previous` açıksa; önceki ve şimdiki satır boş değilse, önceki
  şimdikinden farklıysa ve şimdiki satır 90 karakterden kısaysa): asıl boyun 0,8 katı, renk %40 opak, en çok 2 satır "…".
- **Şimdiki satır:** 36/44 sp 600, kullanıcının seçtiği altyazı yazı tipiyle; boy × kullanıcının yazı boyu ayarı (%) ×
  bölme oranı. Renk Ayarlar'a göre beyaz `#FFFFFF` ya da sarı `#FFD54A`. Ortalı. Çeviri kapalıyken ve satır yoksa "Nino"
  (gömülü) yazar.
  - **Bölme:** 42 karakterden uzun satır (zaten satır sonu yoksa ve en az iki sözcükse) en dengeli biçimde 2–3 satıra
    bölünür; boy = (42 × 3) ÷ uzunluk, en az 0,75. Konuşan adı ("ARTHUR:") sonraki sözcükle aynı satırda tutulur.
  - **Sığdırma:** yine sığmazsa yazı her denemede %10 küçülür, en çok yarı boya kadar.
  - Arapça/Urduca satırlar sağdan sola işaretlenir.

**Alt orta:** `subtitle_screen_note` (13 sp beyaz %45).

**Ekran çevirisi sonuçları:** her çeviri oyundaki yazının yerinde (görüntüye oranla), genişliği yazının kutusu kadar (en
az 60 dp); yazı boyu kutu yüksekliğine göre 10–28 sp; siyah %85 zemin, 4 dp köşe, 4 dp iç boşluk, sola yaslı.

**Ek alanların çevirisi** (görev, telefon, bildirim): her biri oyundaki yerinde (konumu bilinmiyorsa sağ üst: yatay
%60–95, dikey %5–20), genişlik 120 dp ile alan genişliği arası, siyah %80 zemin, 6 dp köşe, 6 dp iç boşluk, 13 sp yazı.

---

## 10. Çeviri dili seçici

Seçili dilin bayrağı ve kendi dilindeki adı; basınca bütün diller açılır.

- **Küçük hap** (Karşılama'nın sağ üstü): 36 dp yüksek hap, beyaz %10 zemin, 1 dp beyaz %18 kenar, yatay 12 dp iç boşluk,
  aralar 8 dp: bayrak emojisi 18 sp, ad 15 sp 600 `#0A1430` tek satır, 20 dp aşağı ok `#55607A`.
- **Tam satır** (Ayarlar): tam genişlik, 44 dp, `#E6EDF8` zemin, 12 dp köşe, kenarsız, yatay 14 dp iç boşluk: bayrak 20
  sp, ad, esnek boşluk, aşağı ok.
- **Açılır liste** (standart açılır menü), sıra: 🇹🇷 Türkçe, 🇸🇦 العربية, 🇮🇳 हिन्दी, 🇮🇩 Bahasa Indonesia, 🇹🇭 ไทย,
  🇻🇳 Tiếng Việt, 🇵🇰 اردو, 🇧🇩 বাংলা, 🇲🇾 Bahasa Melayu, 🇵🇭 Filipino, 🇳🇱 Nederlands. Her satır: bayrak 20 sp + 12 dp +
  ad 15 sp; seçili olanın sağında `#0070D1` onay. Bilinmeyen dilde bayrak 🌐.
- Seçince liste kapanır ve dil hemen kaydedilir (açılış yazısı, örnek satırlar, ana ekran başlığı, kaydırma çubuğu rengi ve
  bayrak küresi buna göre değişir). Ekran okuyucu dil adını okur.

---

## 11. Güncelleme kartları (ana ekranın üstü)

### 11.1 Telefon uygulaması güncellemesi
Yalnız GitHub'dan kurulan kopyada (mağaza kopyasında çıkmaz), yeni sürüm bulunduğunda ve çeviri kapalıyken. Etkin (mavi
kenarlı) karo:
1. Satır: `app_update_title` (sürüm no; 17 sp 600, kalan genişlik) ve sağda 32 dp kapat
   düğmesi (18 dp X, `#55607A`) → bu sürüm bir daha önerilmez.
2. `app_update_body` (15 sp ikincil)
3. Birincil `app_update_button` → yükleme dosyasının indirme adresi tarayıcıda açılır.

### 11.2 TV uygulaması güncellemesi
TV'deki Nino telefondakiyle gelen sürümden eskiyse ve çeviri kapalıyken. Etkin karo:
1. `tvapp_update_title` (17 sp 600)
2. `tvapp_update_body` (marka: "LG", "Samsung" ya da "Android TV"; TV'deki sürüm; telefondaki sürüm)
3. Birincil `tvapp_update_button` → TV'ye kurulum ekranı, bu TV seçili.

---

## 12. Altyazı alanı karoları (Ayarlar içinde)

### 12.1 Altyazı alanı
Karo, yukarıdan aşağı:
1. Etiket `area_title`.
2. Segmentli seçim: `area_bottom`, `area_top`, `area_full`, `area_custom`. Hazır seçim seçilince alan ona göre ayarlanır.
3. **Önizleme** (12.3).
4. Yalnız "Özel"de iki kaydırıcı: `area_position` ve `area_height`; başlığın sağında değer
   "%‹sayı›" (gömülü biçim). Konum 0 ile (100 − yükseklik) arası; yükseklik en küçük alan boyu ile 100 arası. Kaydırıcı
   tutamacı `#0A1430`, dolu iz `#0070D1`, boş iz `#D3DEEF`.
5. Not `area_drag_note` (13 sp ikincil).

Önizlemede çerçeveyi sürüklemek ya da kaydırıcıyı oynatmak seçimi kendiliğinden "Özel"e geçirir ve kaydeder.

### 12.2 Ek alanlar
Karo:
1. Etiket `extra_title`.
2. Not `extra_note` (13 sp ikincil)
3. Her ek alan için `#E6EDF8` zeminli, 22 dp köşeli, 12 dp iç boşluklu kutu (aralar 8 dp):
   - Satır: ad alanı `extra_name` (genişliğin kalanı), açık/kapalı anahtarı, çöp kutusu simge düğmesi
     (`extra_remove`).
   - Segmentli seçim: `extra_quest`, `extra_notification`, `extra_phone` (alanın
     konumu hazır yerlerden birine eşitse o seçili görünür).
   - Önizleme (12.3); alan kapalıysa %50 opak.
4. Üç alandan azsa ikincil düğme `extra_add` → açılır menü: `extra_quest_title`,
   `extra_notification_title`, `extra_phone_title`. Seçilen, o adla ve
   konumla eklenir.

Her değişiklik anında kaydedilir.

### 12.3 Bölge önizlemesi
Tam genişlik, 16:9 oranlı, 16 dp köşeli, siyah kutu. Çeviri sürüyorsa içinde son oyun karesi (kutuya gerilerek), yoksa
ortada `area_preview_empty` (13 sp ikincil). Üstünde bölge çerçevesi:
`#0070D1` %15 dolgu, 2 dp `#0070D1` kenar, sağ alt köşede 7 dp yarıçaplı `#0070D1` tutamaç. Sürükleme sağ alt köşenin
32 dp yakınından başlarsa boyutlandırır, değilse çerçeveyi taşır. Önizleme açıkken kareler canlı gelir.

---

## 13. Görseller ve simgeler

| Dosya | Boyut | Ne | Nerede |
|---|---|---|---|
| `icon.png` (uygulama simgesi klasörü) | 512×512 | Uygulama simgesi: koyu mavi yuvarlak kare, mavi ışıklı kenar; ortada kırmızı Türk bayraklı DualSense benzeri oyun kolu, önünde oyun kolu ve "文A" çeviri balonları, altta "NINO" ve "GAME TRANSLATOR" | Başlatıcı simgesi, tüm üst çubukların solundaki 36 dp logo |
| `nino_logo.png` | 512×512 | Simgenin aynısı | Açılış animasyonu (230 dp) |
| `nino_bot.png` | 256×256 | Beyaz yuvarlak robot: kırmızı Türk bayraklı şapka, mavi gözler, gülümseme, başında "文A" balonu, çevresinde mavi halka | Yüzen robot düğmesi (46 dp) |
| `nino_bot_blink.png` | 256×256 | Aynı robot, gözleri kapalı | Göz kırpma karesi (150 ms) |
| `living_room.png` | 1672×941 | Saydam zemin: duvara asılı TV (ekranında mavi dalga), uzun metal sehpa, sağda dikey PS5 benzeri konsol, sağda duvar prizi | Salon sahnesi (PS5) ve Ayarlar › Arayüz önizlemesi |
| `living_room_xbox.png` | 1671×941 | Aynı salon, konsol yatay beyaz Xbox benzeri; resimde kablo yok | Salon sahnesi (Xbox) ve önizleme |
| `ic_notification` (vektör) | 24 dp | Beyaz: üstte 18×7 dolu dikdörtgen, altında 16×2,5 ve 10×2,5 iki altyazı çizgisi | Çeviri sürerken bildirim simgesi |

Uygulama adı (başlatıcıda): "Nino Game Translator" (gömülü).

Kullanılan Material simgeleri: geri oku, kapat (X), dişli, kişi, geçmiş (saat), onay, uyarı, TV, akıllı telefon, oyun kolu
(SportsEsports), gamepad, USB, kutu (Inventory2), yenile, ışıltı (AutoAwesome), ekran döndürme, genişlet (OpenInFull),
tam ekran, sağ ok, aşağı ok, büyüteç, çöp kutusu.

---

## 14. Telefon ve tablet düzeni

Eski uygulamada **tablet/geniş ekran için ayrı düzen yoktur**; genişlik eşiği tanımlanmamıştır.
- Ana pencere tablette de **dikeye kilitlidir**; yalnız tam ekran altyazı yataydır.
- Bütün ekranlar tam genişliğe yayılır (20 dp kenar boşluğuyla); en fazla genişlik sınırı yoktur. Karolar, düğmeler, sahne
  kartları ve kısa yollar ekran genişledikçe uzar.
- Salon sahnesi genişliğe göre ölçeklenir (yüksekliği de oranla büyür); fiş büyütme oranı ölçek büyüdükçe 1'e iner.
- Sahne kartlarının ve karşılama görsellerinin yükseklikleri sabittir (196 / 380 / 250 / 316 dp), genişlikle değişmez.
- Bilinen en fazla genişlikler yalnız şunlardır: "Çeviri başladı" balonu 250 dp, Ayarlar › Arayüz'deki cam düğme
  önizlemesi 130 dp.

---

## 15. Belirsizlikler

1. **Kodda var, ekranda çıkmayan parçalar.** Aşağıdakiler eski kodda çizilmiş ama hiçbir ekrandan çağrılmıyor; yeni
   uygulamaya alınıp alınmayacağına karar verilmeli:
   - Çeviri sürerken açılan ayrı ekran: süre sayacı (`running_pill` (çalışırken üstteki hap: çeviri sürüyor + oyun adı)), paket etiketi, `running_now` (şu an çalışan oyun satırı) karosunda büyük çeviri ve altında özgün metin ile ölçüm satırı (`metrics_ocr` (okuma süresi, ms),
     `metrics_translation` (çeviri süresi, ms), `metrics_pack` (satır hazır paketten geldi etiketi), `metrics_delay` (toplam gecikme, ms)),
     önceki 4 satır, `running_from_pack` (satırın hazır çeviriden geldiğini söyleyen not) ve `main_tvs_label` (bağlı TV bölüm etiketi) karoları, `psn_main_account`
     uyarısı, `main_phone_view` (altyazıyı telefonda gösterme düğmesi), `stop` (çeviriyi durdurma düğmesi) ve ekranı çevirme düğmeleri.
   - Bu ekrana bağlı oyun sorma kartı (`game_ask_title`, `game_ask_body`, `game_ask_search`,
     `game_ask_dont_ask`, `game_ask_not_listed`, `game_last_played`) ve oynanan oyun satırı (`game_played`,
     `game_unknown`, `game_choose`, `game_change`).
   - Eski pano tarzı sahne kartı (`home_idle_hint`, `home_pair_hint`) ve dönen telefon simgeli tam ekran altyazı şeridi
     (`home_rotate_title`, `home_rotate_body`).
   - Büyük cam küreli aç/kapa düğmesi (`nino_subtitles_in`, `nino_slide_to_start`, `nino_tap_to_setup`,
     `nino_subtitles_on`, `nino_toggle_connecting`, `nino_toggle_pair`, `nino_start_translation`,
     `nino_stop_translation`). Yalnız küçük, etkileşimsiz önizlemesi Ayarlar › Arayüz'de görünür.
   - Eski ince kaydırarak başlatma çubuğu ve koyu küçük durum çipi.
   - Bu parçalardaki diğer metinler: `running_waiting` (altyazı bekleniyor durumu), `running_ready` (kısa hazır durum sözcüğü),
     `running_ready_translation` (hazır çeviri durum etiketi), `main_target_phone`, `screen_working` (ekran çevirisi sürerken düğme yazısı).
   - Süre ve motor biçimleri (yalnız kapsam dışı ekranlarda kullanılıyor): `duration_hours` (saat ve dakika süre biçimi),
     `duration_minutes` (dakika süre biçimi), `engine_free_short`; diğer motorlar adıyla: "DeepL", "Gemini", "OpenAI",
     "Claude".
2. **"Cam düğme" adı yanıltıcı:** Ayarlar'da "Cam düğme" seçilince açılan ana ekran 7.3'teki kaydırma çubuklu ekrandır;
   oysa ayar önizlemesi büyük cam küreli düğmeyi gösterir. Yeni sürümde adın ya da önizlemenin düzeltilmesi gerekebilir.
3. **Karşılama'daki dil hapı okunmuyor olabilir:** beyaz %10 zemin ve beyaz %18 kenar, açık ekran zemininde neredeyse
   görünmez (koyu zemine göre tasarlanmış gibi).
4. **Tam ekran altyazıdaki kutucuklar:** ekran çevirisi ve ek alan kutularında yazı rengi koyu lacivert (`#0A1430`), zemin
   siyah %80–85; okunmuyor olabilir. Beyaz yazı amaçlanmış olabilir.
5. **Açılış süresi:** koddaki not "yaklaşık 2,3 sn" diyor; zaman çizelgesi toplamda yaklaşık 3,3 sn çıkıyor.
6. **Döndürme ipucunun koşulu iki görünümde farklı:** Salon'da "altyazı telefonda ya da örnek oturum", kaydırmalı ekranda
   yalnız "altyazı TV'de değil" (örnek oturum ayrıca sayılmaz). Tam Ekran hapı Salon'da TV çıkışında da görünür, kaydırmalı
   ekranda TV çıkışında görünmez. Bilinçli mi belirsiz.
7. **Tur kartının yeri** vurgulanan öğenin konumuna **piksel** cinsinden (900 px) bakarak seçiliyor; ekran yoğunluğuna göre
   farklı davranır.
8. **Marka:** uygulama simgesi ve açılış logosu DualSense benzeri bir kol ve PlayStation tarzı simgeler içeriyor; salon
   görselindeki konsol PS5'e, Xbox görselindeki konsol Xbox'a benziyor. Proje notlarına göre yayından önce markasız
   çizimlerle değiştirilmeli.
9. **Tablet:** eski uygulamada tablet düzeni yok (bkz. 14); yeni uygulamada genişlik eşiği ve en fazla içerik genişliği
   ayrıca kararlaştırılmalı.
10. **Kapsam dışı ekranlar** (Konsol türü, PSN girişi, Microsoft girişi, Xbox seçimi, TV'ye kurulum, Profil, Ayarlar,
    Geçmiş, Sorun Bildir, Nino'ya Sor, Sistem sağlığı, içe aktarılmış paketler) bu belgede yalnız gezinme açısından anıldı.
11. **"Öncelikli havuz oyunu"** (gün batımı fonu ve renkli LED'ler) şu an yalnız GTA 6 için; hangi oyunların bu sınıfa
    girdiği sunucudan mı geliyor, belge kapsamında görülmedi.
12. **Kaydırma çubuğu dokunuşu:** `slide_pair` yazsa da eski uygulamada yalnız beyaz tutamaç dokunmaya yanıt
    veriyor; iz ve yazı vermiyor (ekran okuyucuda tümü düğme). Yenide tüm çubuğun dokunulabilir olması düşünülebilir.
13. **Tur 1. adımı** "bu çubuğu sonuna dek çekin" diyor; varsayılan Salon görünümünde başlatma denetimi fiş/prizdir.
14. **Konsola göre metin:** "PS5 bağlı", "PS5'siz Deneyin", "PS5'e bağlanılıyor…", "Kurulum · Adım 2/3" gibi metinler Xbox
    ya da yakalama kartı kullanılırken de aynen çıkıyor; PS5 eşleme ekranındaki adım satırı ana ekrandan açılınca da
    görünüyor.
