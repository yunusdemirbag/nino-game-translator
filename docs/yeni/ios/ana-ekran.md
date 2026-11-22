# Eski uygulamadan çıkarılmış tarif: iPhone/iPad ana ekranı ve çeviri sırasında görünenler

Bu belge, yeni iOS uygulamasını yazacak kişinin eski kodu görmeden aynı ekranları ve davranışı kurabilmesi için
yazıldı. Kod değil, tarif: ölçüler nokta (pt), süreler saniye/milisaniye, renkler onaltılık. Ekrandaki metinler yeni
uygulamanın metin anahtarıyla anılır (`home.status.ready` gibi); metinlerin kendisi
`apps/ios/Nino/Resources/Localizable.xcstrings` içindedir. Yeni katalogda karşılığı olmayan metinler yalnız
anlamıyla, kısaca anlatılır.

Not: `docs/screenshots/telefon/07..09` görüntüleri **eski, koyu temalı bir tasarıma** ait (sarı başlatma düğmesi,
"şu an oynanan" kartı, hazır çeviri sayacı, gecikme karoları). Bugünkü uygulamada bunlar yok; ana ekran açık
temalı ve ortasında salon sahnesi var. Kaynak olarak bu belgeyi esas alın. Görüntülerden yalnız şu fikirler bugün de
geçerli: üst satırda logo solda, simge düğmeleri sağda; yatay altyazı ekranı siyah zemin, sol üstte yeşil noktalı
durum etiketi, ortada büyük beyaz son satır ve üstünde gri önceki satır, altında soluk ekran-açık-kalır notu
(`phone.keepon.note`).

---

## 0. Ortak tasarım ölçüleri (bu ekranların kullandığı)

### Boşluklar, köşeler, yükseklikler

| Ad | Değer |
|---|---|
| Ekran kenar boşluğu (screen) | 20 |
| Öğeler arası (gap) | 12 |
| Karo iç boşluğu (tile) | 16 |
| Satır içi (inline) | 8 |
| İnce (hair) | 4 |
| Köşe: karo | 22 (sürekli/"continuous" köşe) |
| Köşe: kontrol | 16 |
| Köşe: iç | 8 |
| Köşe: etiket | 6 |
| Simge düğmesi | 44 × 44 |
| Etiket (tag) yüksekliği | 24 |
| iPad okunaklı sütun genişliği | en çok 680, ortalanır |

### Renkler

| Ad | Değer |
|---|---|
| Ana yazı (ink / text) | #0A1430 |
| İkincil yazı (inkSoft / secondary) | #55607A |
| Üçüncül yazı (tertiary) | #8A93A8 |
| Vurgu mavisi (accent) | #0070D1 |
| Açık vurgu (accentHi) | #1A86E8 |
| Lacivert (navy) | #003085 |
| Paket rengi (pro) | #00205B, açığı (proSoft) #E2E8F5 |
| Uyarı (warning) | #9A4A08 |
| Tehlike (danger) | #B3261E, açığı #FBE4E2 |
| Başarı (success) | #1E6B45 |
| Canlı yeşili (ana ekran durum noktası) | #30C578 |
| Yüzey 2 (surface2) | #E6EDF8 |
| Güçlü kenar (borderStrong) | #D3DEEF |
| Cam karo zemini (surface) | beyaz %85 |
| Cam kenarı (border) | beyaz %75 |
| Altyazı beyazı / sarısı | #FFFFFF / #FFD54A |
| Önceki altyazı satırı grisi | #7C7A76 |

### Yazı boyları

| Ad | Boy / kalınlık |
|---|---|
| display | 28 yarı kalın |
| title | 22 yarı kalın, rakamlar eş genişlikte |
| headline | 17 yarı kalın |
| body | 15 normal |
| caption | 13 orta |
| Altyazı (yatay ekran) | iPhone 36, iPad 60; kullanıcının boy ayarıyla ×0,8…×1,6; yarı kalın; kullanıcının seçtiği altyazı yazı tipi |

### Ekran iskeleti ("MobileScreen")

- Zemin: sol üstten sağ alta #F7FAFF → #E3ECFA doğrusal geçiş; üstüne iki yumuşak ışık: (x %10, y %8) merkezli vurgu
  mavisi %22 saydamlıkta, yarıçapı genişliğin %90'ı; (x %95, y %95) merkezli paket laciverdi %16, yarıçapı
  max(genişlik, yükseklik×0,5). Zemin güvenli alanı da kaplar.
- Üstte başlık satırı: yatay 20 boşluk; üstten iPhone'da 8, iPad'de 20.
- Ortada kayan içerik: dikey yığın, öğeler arası 12, sola yaslı; üstte 12, altta 20, yanlarda 20 boşluk; kaydırma
  çubuğu gizli.
- Altta sabit düğme bölgesi: öğeler arası 12; alttan iPhone'da 20, iPad'de 40.
- iPad'de üst satır, içerik ve alt bölge en çok 680 genişlikte ortalanır; iPhone'da tam genişlik.
- Gezinti çubuğu gizli; varsayılan yazı rengi ana yazı.

### Ortak parçalar

- **Simge düğmesi:** 44×44, köşe 16, cam zemin (beyaz %85), beyaz %75 kenar, gölge paket laciverdi %8 yarıçap 8 aşağı 3.
  Simge 17 yarı kalın, ana yazı renginde.
- **Profil düğmesi:** simge düğmesiyle aynı; içinde "person" simgesi (baş harf verilirse baş harf). Erişilebilirlik
  adı `settings.profile`.
- **Karo (Tile):** dikey yığın (varsayılan aralık 8), sola yaslı, tam genişlik, iç boşluk 16, cam zemin, köşe 22,
  kenar 1 pt beyaz %75 (seçili vurguda 1,5 pt vurgu mavisi), gölge paket laciverdi %10 yarıçap 14 aşağı 6.
- **Bilgi karosu (InfoTile):** karo; ilk satırda küçük simge (15 pt, ikincil renk, 18×18 kutu) + headline başlık;
  altında caption açıklama ikincil renkte.
- **Not satırı (MobileNote):** "exclamationmark.triangle.fill" simgeli etiket, caption, varsayılan renk uyarı
  (#9A4A08); renk verilebilir. Çok satıra sarılır.
- **Düğme biçimleri:** hepsi tam hap (kapsül), yazı headline, simge + başlık.
  - Birincil: #1B2747 → #0A1430 yukarıdan aşağı geçiş, beyaz yazı, beyaz %14 ince kenar, gölge #0A1430 %28
    yarıçap 14 aşağı 8; tam genişlik, en az 58 yükseklik, yanlarda 20 boşluk.
  - İkincil: beyaz %90 zemin, güçlü kenar (#D3DEEF), ana yazı rengi; tam genişlik, en az 58.
  - Hayalet (ghost): zeminsiz, yazı #0058A8, kendi genişliğinde, en az 44 yükseklik, yanlarda 12.
  - Yıkıcı: #FBE4E2 zemin, #B3261E yazı; tam genişlik, en az 58.
  - Basılıyken %97'ye küçülür (0,12 sn yumuşak); devre dışıyken %40 saydam.
- **Logo:** 36 pt uygulama logosu.

---

## 1. Ana ekran (HomeScreen)

Uygulama kurulumu bitince açılan tek ana ekran. Çeviri sürerken de aynı ekran kalır, yalnız durum değişir. Ana ekran
iPhone'da **yalnız dikey** kullanılır (yön kilidi); iPad'de her yön serbesttir.

### 1.1 Durum (HomeState)

Ekranın dört durumu vardır; sırayla bakılır:

1. Demo sürüyorsa → **canlı (live)**.
2. Çeviri çalışıyorsa → PS5 görüntüsü geliyorsa (oturum "akıyor") **canlı**, gelmiyorsa **bağlanıyor**.
3. Çeviri hazırlanıyorsa (başlatma sürüyor) → **bağlanıyor**.
4. Başlatılabiliyorsa → **hazır**; değilse → **eşlenmemiş (notPaired)**.

"Başlatılabilir" demek: konsol eşlenmiş (PS5 için konsol kaydı ve PSN hesabının kimliği; Xbox için seçili Xbox ve
Microsoft girişi) **ve** altyazının gideceği yer hazır (çıkış "telefonda göster"i içeriyor ya da TV eşlenmiş ve
anahtarı kayıtlı).

"Sorun metni": durum bağlanıyor iken modelin bağlantı sorunu metni (bkz. §8.4); yoksa boş.

"Telefonda mı": demo sürüyorsa ya da çıkış ayarı telefonda göstermeyi içeriyorsa evet.

Durum değiştikçe ekranın tamamı 0,25 sn "ease-out" ile canlandırılır.

### 1.2 Düzen (yukarıdan aşağıya)

**Üst satır** (yükseklik 44):
- Normalde **HomeHeader** (§2): solda logo, sağda Geçmiş, Ayarlar, Profil.
- Kurulumdan açılan "PS5'siz önizleme" kipinde (demoOnly): solda 36'lık logo, sağda hayalet düğme
  `common.close`; dokununca demo durur ve önizleme kapanır. Bu kipte kısa yollar ve TV kartları yoktur.

**Kayan içerik** (öğeler arası 12):

1. **Durum satırı** (üstten ek 8 boşluk): solda 8×8 nokta (§1.5 PulsingDot), 8 boşluk, metin 14 orta, ikincil renk,
   tek satır. Nokta rengi ve metin:

   | Durum | Nokta rengi | Metin |
   |---|---|---|
   | eşlenmemiş | ikincil (#55607A) | `home.status.notpaired` (konsol adı eklenmez) |
   | hazır | vurgu mavisi | "‹konsol adı›  ·  " + `home.status.ready` |
   | bağlanıyor | sorun yoksa vurgu mavisi, sorun varsa uyarı rengi | "‹konsol adı›  ·  " + `home.status.connecting` |
   | canlı, altyazı telefonda | #30C578 | "‹konsol adı›  ·  " + `home.status.live` |
   | canlı, altyazı TV'de | #30C578 | "‹konsol adı›  ·  " + `home.status.tv` |
   | demo (hangi durumda olursa) | durumun rengi (canlı yeşili) | `demo.status` |

   Konsol adı: PS5'in adı, boşsa "PS5"; Xbox seçiliyse Xbox'ın adı, boşsa "Xbox". Ayırıcı iki boşluk, orta nokta,
   iki boşluk. Nokta yalnız canlı ve bağlanıyor durumlarında yanıp söner.

2. **Büyük başlık:** 34 pt kalın, harf aralığı −0,6, ana yazı rengi, en çok 2 satır, sığmazsa %70'e kadar küçülür,
   sola yaslı tam genişlik. Durum değişince 0,25 sn ease-out.

   | Durum | Metin |
   |---|---|
   | eşlenmemiş | `home.title.pair` |
   | canlı | `home.title.live` |
   | hazır / bağlanıyor | `home.title.ready` (%@ = dil adı) |

   Dil adı: hedef Türkçe ise `lang.tr`; Arapça ise `lang.ar`; öbür dillerde dilin kendi adı (ör. "हिन्दी"). Örnek:
   Türkçe hedefte `home.title.ready` içine `lang.tr` yerleşir.

3. **Salon sahnesi** (PhoneLivingRoom, §3), üstten ek 8 boşluk. Parametreleri:
   - etkin: demo ya da çalışıyor ya da hazırlanıyor
   - akıyor: durum canlı
   - satır: §1.6'daki "şu anki satır"
   - kaynak (İngilizcesi): yalnız demoda, demo satırının İngilizcesi
   - sorun: §1.1'deki sorun metni
   - rozet: demoda `demo.badge`, değilse `home.live.badge`
   - GTA kipi: (çalışıyor ya da hazırlanıyor) ve demo değil ve şu anki oyun "havuz öncelikli" (GTA 6) ise
   - fişe/prize dokunma → §1.7 aç/kapa; TV'ye dokunma → tam ekran altyazıyı aç.
   Kullanım turunda "start" adımı bu sahneyi vurgular.

4. **Sahne altı satırı** (yatay, aralık 10):
   - Solda ipucu: footnote boyu, orta kalınlık, ikincil renk, gerektiği kadar satıra sarılır.

     | Durum | Metin |
     |---|---|
     | eşlenmemiş (demo değil) | `slide.pair` |
     | eşlenmemiş ama demo | `scene.unplug` |
     | hazır | `scene.plug` |
     | bağlanıyor / canlı | `scene.unplug` |

   - Sağda, yalnız canlıyken: **tam ekran düğmesi**. "arrow.up.left.and.arrow.down.right" simgesi +
     `home.fullscreen`; footnote yarı kalın, vurgu mavisi; yanlarda 12, dikeyde 7 boşluk; beyaz %72 kapsül zemin, 1 pt
     beyaz kapsül kenar. Belirip kaybolması saydamlıkla. Dokununca tam ekran altyazı açılır (altyazı TV'ye gitse
     bile).

5. **Demo düğmesi:** yalnız eşlenmemiş ve demo kapalıyken. Hayalet düğme, "sparkles" simgesi,
   `demo.try` (tek satır, %75'e kadar küçülür), yatayda ortalı. Dokununca demo başlar (§8.2).

6. **Döndürme ipucu:** yalnız canlı ve altyazı telefondayken. Yatayda ortalı satır: "rotate.right" simgesi 15 orta +
   8 boşluk + `home.rotate.hint` (14 pt), ikincil renk; üstten 2 boşluk.
   Saydamlıkla belirir.

7. **Kısa yollar** (demoOnly değilse): üç eşit karo yan yana, aralık 10, üstten ek 16 boşluk (§1.4).

8. **TV uygulaması kartı** (demoOnly değilse, en çok biri):
   - TV'deki uygulama telefondaki paketten eskiyse **güncelleme karosu**: seçili vurgulu karo; ilk satır
     "arrow.triangle.2.circlepath" simgesi (vurgu mavisi) + TV uygulamasının yeni sürümü olduğunu söyleyen başlık
     (headline); altında caption ikincil, TV'deki kurulu sürümle bu telefondaki paketin sürümünü ok ile yan yana
     gösteren satır (iki %@); altında güncellemeyi başlatan ikincil düğme. (Yeni katalogda bu üç metnin
     anahtarı yok.) Dokununca TV kurulum
     sayfası açılır ve güncelleme kendiliğinden başlar.
   - Değilse ve TV uygulaması eksikse (TV eşlenirken uygulama açılamadıysa) **bilgi karosu**: "arrow.down.app"
     simgesi, başlık `tv.install.fromphone`, açıklama
     üç TV markasının adı, aralarında orta nokta (marka adları çevrilmez). Tüm karo düğmedir; TV kurulum sayfasını açar.

9. **Dil paketi karosu** (§2.2): Apple çevirisinin dil paketi indirilmemişse ve iOS 26 ya da sonrasıysa.

10. **Çeviri uyarıları** (en çok biri):
    - iOS 26'dan eskiyse ve çevrimiçi motor açık değilse: **Eski iOS kartı** (§3.13); kartın `oldios.add` düğmesi Ayarlar'ı açar.
    - Değilse, Apple çevirisi var ama bu dili desteklemiyorsa ve çevrimiçi motor kapalıysa: uyarı notu
      `translate.error.unsupportedlang`.

11. **Çalışırken (demo değil):**
    - Henüz hiç satır çevrilmediyse ve Xbox değilse, ikincil renkli not
      `psn.controller.warning` (kolu açınca PS5'te ana hesabı seçme uyarısı).
    - **Oyun bölümü** (§6): soru kartı ya da oynanan oyun satırı.
    - PS5 görüntüsü akıyorsa **ekran çevirisi düğmesi** (§2.6).

12. **Çalışırken (demo dahil değil; yalnız gerçek çalışma)**: caption, üçüncül renk, üstten 4:
    `home.foreground.note`.

**Alt bölge:** boş.

### 1.3 Ekrandaki olaylar

- Ekran açılınca: ekran adı "home" olarak (yerel, kişisel veri taşımayan) istatistiğe yazılır; çeviri durumu
  (dil paketi var mı) yenilenir; TV uygulamasının sürümü denetlenir (en çok dakikada bir; §8.8).
- Çeviri **başlayınca** ve altyazı telefondaysa tam ekran altyazı kendiliğinden açılır.
- "Yan çevirme gözcüsü" (§1.8): (çalışıyor ya da demo) ve altyazı telefondaysa çalışır, değilse durur. Çalışma
  durumu, çıkış ayarı ve demo değiştikçe yeniden karar verilir. Ekran kaybolunca durur.
- Tam ekran altyazı ekranı tüm ekranı kaplayan bir örtü olarak açılır (fullScreenCover); kapanınca gözcü yeniden
  "silahsızlanır" (telefon önce dik gelmelidir).

### 1.4 Kısa yollar (Shortcut)

Her biri düğme olan karo:
- İçerik dikey, sola yaslı, aralıksız: simge (20 yarı kalın, vurgu mavisi) → 12 boşluk → başlık (12 pt, ikincil
  renk, tek satır) → değer (14 yarı kalın, ana yazı, tek satır, %80'e kadar küçülür).
- Tam genişlik (üçü eşit bölüşür), yanlarda 12, dikeyde 14 iç boşluk, beyaz %72 zemin, köşe 20 (sürekli), 1 pt
  beyaz kenar. Basılı görünümü yok (düz düğme).

| Karo | Simge | Başlık | Değer | Dokununca |
|---|---|---|---|---|
| Konsol (PS5) | gamecontroller.fill | "PS5" (çevrilmez) | PS5'in adı (boşsa "PS5"); eşlenmemişse `home.status.notpaired` | PS5 sayfası (girişi yoksa önce PSN girişi, sonra eşleme) |
| Konsol (Xbox Beta seçiliyse) | gamecontroller.fill | "Xbox · Beta" | Xbox'ın adı (boşsa "Xbox"); seçili değilse `xbox.choose.title` | aynı PS5/konsol sayfası |
| Çıkış | telefondaysa "iphone", değilse "tv" | `home.output` | telefondaysa `home.output.phone`, değilse TV'nin adı (yoksa "TV") | altyazı hedefi seçimi (`target.title`) |
| Paketler | shippingbox.fill | `home.packs` | `home.packs.free` | Paketler sayfası |

Kullanım turu "target" adımında Çıkış karosunu, "packs" adımında Paketler karosunu vurgular.

### 1.5 Yanıp sönen nokta (PulsingDot)

8×8 daire, verilen renkte. Yanıp sönmesi açıksa saydamlığı 1 ile 0,3 arasında gider gelir: 0,9 sn "ease-in-out",
sonsuz tekrar, ileri-geri. Kapalıyken tam opak durur. (Not: canlandırma görünür olunca bir kez kurulur.)

### 1.6 Şu anki satır (sahnedeki TV'de görünen)

- Demoda: demo satırının çevirisi (satır arası boşlukta boş).
- Değilse: telefon yığınının son satırının metni (boş değilse);
- o da yoksa bu oturumda çevrilen en yeni satırın çevirisi.

### 1.7 Fiş/priz aç-kapa kuralı (toggle)

Sahnedeki fişe ya da prize dokunulunca veya fiş sürüklenip bırakılınca:
1. Demo sürüyorsa demo durur.
2. Hazırlık sürüyorsa (genelde 1 sn'den kısa): dokunuş kaybolmaz; hazırlık bitene kadar 50 ms aralıkla beklenir,
   bitince çalışıyorsa durdurulur.
3. Çalışıyorsa durdurulur.
4. Başlatılabiliyorsa: orta şiddette dokunsal geri bildirim, sonra çeviri başlatılır.
5. Hiçbiri değilse: PS5 sayfası açılır (kurulum).

### 1.8 Yan çevirme gözcüsü (SidewaysWatcher)

Ana ekran dikey kilitli olduğu için telefonun yan çevrildiği ivmeölçerden anlaşılır (sistemin yön kilidi açık olsa da
çalışır).
- Ölçüm aralığı 0,1 sn.
- "Dik": y < −0,75 ve |x| < 0,45. Dik görülünce gözcü "kurulur" ve yan sayaç sıfırlanır.
- "Yan": |x| > 0,75 ve |y| < 0,45.
- Yan durum, gözcü kuruluyken ve uygulama öndeyken **en az 0,7 sn** sürerse: gözcü silahsızlanır ve tam ekran açılır
  (zaten açık değilse). Sonra telefon yeniden dik gelmeden tekrar tetiklenmez.
- Tam ekran açılırken ve kapanırken gözcü silahsızlanır.

### 1.9 Yön kuralı

- iPhone: ana ekran yalnız dikey; tam ekran altyazı açılınca yalnız yatay istenir (ekran döndürülür); kapanınca
  yeniden dikey istenir.
- iPad: hiçbir zaman zorla döndürülmez; her yön serbest, altyazı ekranı dikeyde de yatayda da çalışır.

### 1.10 iPhone / iPad farkı (ana ekran)

Ana ekran `horizontalSizeClass` kullanmaz; yalnız "iPad mi" bakılır. iPad'de içerik 680 genişlikte ortalı sütun, üst
ve alt boşluklar daha geniş (§0), yön serbest. Yatayda ayrı bir düzen yok; aynı sütun kayar.

### 1.11 Arayüz dili

Arayüz dili çeviri dilini izler (Türkçe hedef → Türkçe arayüz). Arapça ve Urduca'da düzen sağdan soladır; ancak salon
sahnesi ve oyun karesi koordinatlı katmanlar aynalanmaz. Ana ekran metinleri yeni metin kataloğundan, arayüz
dilinin karşılığıyla okunur; o dilde yoksa İngilizcesi kullanılır.

---

## 2. Ana ekranın parçaları (Home.swift)

### 2.1 Üst satır (HomeHeader)

Yükseklik 44, öğeler arası 12: solda 36'lık logo, esnek boşluk, sonra üç simge düğmesi:

| Simge | Erişilebilirlik adı | Dokununca |
|---|---|---|
| clock.arrow.circlepath | `settings.history` | Geçmiş ekranı (§5) |
| gearshape | `settings.title` | Ayarlar |
| person (profil düğmesi) | `settings.profile` | Profil; kullanım turunun "profile" adımı burayı vurgular |

### 2.2 Dil paketi karosu (LanguagePackTile) — yalnız iOS 26+

Koşul: çeviri durumu "indirme gerekiyor". Karo içinde:
- headline metin: İngilizce–hedef dil paketinin henüz indirilmediğini söyleyen tek cümle. Türkçe ve Arapça hedef için
  dil adları yazılı ayrı biçimler, öbür diller için iki %@ yer tutuculu genel biçim (ilki telefonun dilinde
  İngilizce'nin adı, ikincisi hedef dilin kendi adı). Yeni katalogda bu metinlerin anahtarı yok.
- İndirme anlamında ikincil düğme: kaynak→hedef dil çifti için Apple'ın sistem indirme penceresini açar; indirme
  hazırlanınca çeviri durumu yeniden okunur (karo kendiliğinden kaybolur).

### 2.3 Tam ekran altyazı ekranı (SubtitleScreen)

Ana ekranın üstüne tüm ekranı kaplayarak açılır. Durum çubuğu ve sistem örtüleri (ana sayfa çizgisi) gizli.

**Açılınca:** iPhone'da yatay yön istenir; ekran parlaklığı kaydedilir ve en çok 0,4'e indirilir.
**Kapanınca:** iPhone'da dikey istenir; parlaklık eski değerine döner.

**Katmanlar (alttan üste):**

1. Simsiyah zemin, güvenli alanı da kaplar.
2. **Altyazı yığını**, alta yaslı, ortalı, satırlar arası 8:
   - Demoda: demo satırının çevirisi (varsa), altyazı yazı boyunda (yatay), kullanıcının altyazı rengiyle
     (beyaz ya da sarı), ortalı, %50'ye kadar küçülür, metin yönü içeriğe göre (Arapça sağdan sola).
   - Telefon yığınındaki her satır: metin "dengeli sarılmış" hâliyle (§8.6), yazı boyu altyazı boyu × kullanıcı
     ölçeği × sarma ölçeği. Son satır kullanıcının altyazı renginde; ondan önceki satırlar sabit **#7C7A76 gri**
     (soldurulmaz, gri olur). Satır "soluyor" ise %40 saydam. Ortalı, %50'ye kadar küçülür.
   - Yanlarda iPhone'da 20, iPad'de 60; altta iPhone'da 40, iPad'de 80 boşluk.
   - Yığının (alt boşluğuyla) yüksekliği ölçülür (satır yokken 0); köşe çevirileri bunun üstünde kalsın diye.
3. **Ek alan kutuları** (görev, telefon, bildirim): her biri caption, ana yazı rengi (#0A1430), 6 iç boşluk, siyah
   %80 zemin, köşe 6. Kutunun yeri oyun karesindeki oranlı kutudan: genişliği en az 120 ya da ekran genişliği ×
   (sağ − sol); merkezi x = genişlik × (sol+sağ)/2, y = yükseklik × üst + 24. Kutusu bilinmiyorsa varsayılan
   sol 0,6 – üst 0,05 – sağ 0,95 – alt 0,2. Dokunulamaz.
4. **Ekran çevirisi sonuçları**: her çeviri kendi yazısının yerinde. Genişlik en az 60 ya da ekran × (sağ−sol);
   yazı boyu 10 ile 28 arasında, ekran yüksekliği × satır yüksekliği × 0,8; yarı kalın, ana yazı rengi, sola yaslı,
   4 iç boşluk, siyah %85 zemin köşe 4; konumu sol kenar = genişlik × sol, dikey merkez = yükseklik × (üst+alt)/2.
5. **Köşe çevirileri katmanı (HintLayer, §2.4):** yalnız ekran çevirisi boştayken ve sonucu yokken; alt boşluk olarak
   altyazı yığınının yüksekliği verilir.
6. En altta ortalı bilgi: `phone.keepon.note`; caption, beyaz %50, alttan 8.

**Örtüler:**
- **Bağlantı sorunu** (model sorun metni varsa): ekranın ortasında dikey yığın (aralık 8): turuncu
  "exclamationmark.triangle.fill" (22 yarı kalın) + sorun metni (17 orta, beyaz %90, ortalı, sarılır). En çok 520
  genişlik, 20 iç boşluk; dokunulamaz; okuyucu için tek öğe.
- **Sol üst durum etiketi** (20 boşlukla): metin aşağıdaki gibi. Canlıysa (akıyor ya da demo) koyu zemin için açık
  renkli yazı (beyaz %75) ve önünde 2 sn'de bir genişleyip sönen halkalı 8 pt yeşil (#1E6B45) nokta. Canlı değilken
  aynı bileşen "etiket" görünümüne düşer (24 yükseklik, #E6EDF8 zemin, köşe 6, ikincil renk yazı).

  | Durum | Metin |
  |---|---|
  | demo | `demo.status` |
  | akmıyor, sorun yok | PS5 durum metni (§8.4) |
  | akmıyor, sorun var | `status.connecting` (uzun neden ortada yazar) |
  | akıyor, paketler etkin | `status.ps5.packs` |
  | akıyor | `status.ps5.connected` |

- **Sağ üst düğmeler** (20 boşlukla, aralarında 8), simge düğmesi biçiminde:
  - Akıyorsa: ekran çevirisi boştaysa "text.viewfinder" simgesi, erişilebilirlik adı ekranı çevirme anlamında;
    değilse "xmark.circle", adı çevirileri kaldırma anlamında (§2.6'daki etiketlerin aynısı). Dokununca §8.7.
  - Her zaman: "xmark" / `common.close`; ekranı kapatır.

**iPad farkı:** altyazı 60 pt taban, yanlarda/altta daha geniş boşluk, yön zorlanmaz, köşe çevirileri daha büyük
(§2.4).

### 2.4 Köşe çevirileri katmanı (HintLayer)

Oyunda kendiliğinden çevrilen köşe yazıları (sol üstteki ipucu kutusu, görev kartı) ve telefon mesajı/araması. Her
çeviri oyundaki yazının yerinde durur; simsiyah kutu yok.

- Katman oyun karesinin koordinatındadır, **Arapça arayüzde de aynalanmaz** (içindeki Arapça yazı yine sağdan sola).
- Öğeler değişince ve alt boşluk değişince 0,25 sn ease-out; her öğe saydamlıkla girip çıkar. Dokunulamaz.
- Her öğe:
  - Yazı: medium kalınlık; boyu oyundaki satır yüksekliği × ekran yüksekliği, iPhone'da 15–20 arasına, iPad'de
    20–30 arasına sıkıştırılır. Öğe eğikse italik.
  - Renk beyaz; "düz" öğede %82, kutulu öğede %92. Satır aralığı 2. Sola yaslı. Gölge siyah %70, yarıçap 2, aşağı 1.
  - Kutulu öğe (ör. görev şeridi): 8 iç boşluk, beyaz %10 zemin, köşe 8. Düz öğe: boşluk ve zemin yok.
  - Metin yönü içeriğe göre.
  - En çok genişlik: max(120, ekran genişliği − sol kenar − 8); metin kendi doğal boyunda.
  - Konum: sol kenar = ekran genişliği × kutunun solu.
    - Kutunun dikey ortası ekranın alt yarısındaysa (mesaj) **alt kenarından** tutturulur ve yukarı doğru uzar;
      alt boşluk = max(yükseklik × (1 − kutunun altı), altyazı yığını varsa yığın yüksekliği + 6, yoksa 0).
    - Üst yarıdaysa (ipucu) **üst kenarından** tutturulur ve aşağı uzar; üst boşluk = yükseklik × kutunun üstü.
  - Okuyucu için etiketi çevirinin metni.

### 2.5 Yön isteği (Orientation)

iPad'de hiçbir şey yapmaz. iPhone'da izin verilen yön maskesini değiştirir, kök görünüme "desteklenen yönler değişti"
der ve sahneden o yöne geçmesini ister.

### 2.6 Ekran çevirisi düğmesi (ScreenTranslateButton)

İkincil düğme (tam genişlik). Dokununca hafif dokunsal geri bildirim, sonra §8.7.

| Ekran çevirisi durumu | Simge | Metin |
|---|---|---|
| boşta | text.viewfinder | ekranı çevirme anlamında kısa etiket |
| sürüyor | hourglass | ekranın çevrilmekte olduğunu söyleyen kısa etiket |
| sonuçlar ekranda | xmark.circle | ekran çevirilerini kaldırma anlamında kısa etiket |

Ekran çevirisi yeni katalogda yok; bu etiketlerin anahtarı da yok.

---

## 3. Salon sahnesi (PhoneLivingRoom)

Bütün uygulamalarda ana ekranın ortasındaki aynı sahne: duvarda TV, sehpada konsol, sağda duvar prizi, konsoldan
prize giden kablo ve fiş. Fiş prize takılınca çeviri başlar, çekilince durur.

### 3.1 Görsel ve ölçek

- Arka planı saydam bir salon görseli: **1672 × 941 piksel**. PS5 seçiliyse "LivingRoom", Xbox seçiliyse
  "LivingRoomXbox". Görselde metal sehpa, duvara asılı ince çerçeveli büyük TV (ekranında mavi ışık dalgası), sehpanın
  sağ ucunda dik duran beyaz konsol, konsolun sağ üstünde gri çerçeveli Avrupa tipi (Schuko) priz var.
  (Marka uyarısı: konsol çizimi Sony'nin tasarımına benzer; yayımlamadan önce markasız bir çizimle değiştirilmeli.)
- Sahnenin kutusu 1672 × **965** oranındadır (görselden 24 piksel uzun: Xbox'ta sarkan fiş görselin altına taşar,
  iki sahne aynı yükseklikte kalsın diye). Kutu ekran genişliğini doldurur, yüksekliği orandan gelir.
- Ölçek s = sahne genişliği / 1672 (iPhone'da ≈ 0,21–0,23). Bütün sahne ölçüleri pikselde verilir ve s ile çarpılır
  (sahneyi bir bütün olarak küçültmek yerine; bulanık katmanlar gereksiz bellek yemesin).
- Sahne bir resimdir: sağdan sola arayüzde aynalanmaz.

### 3.2 Öğelerin konumları (görsel pikseli ve görsele oranı)

Oranlar: x / 1672, y / 941.

**PS5'li salon**

| Öğe | Piksel | Oran |
|---|---|---|
| TV ekranının içi | x 149, y 40, g 1151, y 595 | sol %8,9, üst %4,3, genişlik %68,8, yükseklik %63,2 |
| TV çerçevesi (ışıklar için) | x 139, y 27, g 1171, y 621 | sol %8,3, üst %2,9, g %70,0, y %66,0 |
| Sehpa (ışıklar için) | x 49, y 713, g 1502, y 160 | sol %2,9, üst %75,8, g %89,8, y %17,0 |
| Priz merkezi | (1564, 378) | x %93,5, y %40,2 |
| Kablonun konsoldan çıktığı yol | (1490,706) → (1522,706) → (1535,709) → (1545,716) → (1552,727) | ilk nokta x %89,1, y %75,0 |
| Kablo başlangıcı (yedek) | (1550, 734) | x %92,7, y %78,0 |
| Kablonun çıkış yönü | (0,5 ; 0,87) birim vektör (aşağı-sağa) | |
| Fişin çekikken asılı durduğu yer | (1600, 885) | x %95,7, y %94,0 |

**Xbox'lı salon**

| Öğe | Piksel | Oran |
|---|---|---|
| TV ekranının içi | x 136, y 40, g 1185, y 596 | sol %8,1, üst %4,3, g %70,9, y %63,3 |
| TV çerçevesi | x 121, y 26, g 1214, y 630 | sol %7,2, üst %2,8, g %72,6, y %67,0 |
| Sehpa | x 43, y 733, g 1580, y 167 | sol %2,6, üst %77,9, g %94,5, y %17,7 |
| Priz merkezi | (1561, 381) | x %93,4, y %40,5 |
| Kablo başlangıcı | (1572, 722) | x %94,0, y %76,7 |
| Kablonun konsoldan çıkan yolu | yok (kablo konsolun arkasındaki girişten küçük bir fiş başıyla çıkar) | |
| Kablonun çıkış yönü | (1 ; 0,1) | |
| Fişin asılı durduğu yer | (1646, 912) | x %98,4, y %96,9 |

### 3.3 Katman sırası (alttan üste)

1. LED ışıkları (§3.5)
2. Priz parıltısı (§3.6)
3. Salon görseli
4. TV ekranının içi (§3.4)
5. Kablo (§3.7)
6. Fiş (§3.7)
7. Prizin dokunma alanı: 60×60 saydam kare, priz merkezinde; dokununca hafif dokunsal geri bildirim + aç/kapa.
8. Fişin dokunma/sürükleme alanı: 60×60 saydam kare, fişin o anki yerinde (§3.8).

"Takılı" = etkin **ve** açılış gösterisi beklemiyor.

### 3.4 TV ekranının içi

- TV ekranı dikdörtgeninin tam içine çizilir, taşanlar kırpılır; en altta siyah zemin (geçişlerde görseldeki ekran
  görünmesin).
- İçerik 300 nokta genişliğinde "mantıksal bir TV" için tasarlanır (yükseklik = 300 × ekran oranı, PS5'te ≈ 155) ve
  sol üstten ölçeklenerek ekran dikdörtgenine sığdırılır. Yazı boyları bu 300'lük TV'ye göredir.
- Takılıyken ve akarken TV'ye dokunmak tam ekran altyazıyı açar.

Üç hâli var:

**a) Fiş takılı değil — Bekleme ekranı (TVStandby)**
- Simsiyah. Ortada `scene.plug` metni, **büyük harfle**, 11 pt yarı kalın
  eş aralıklı (monospaced) yazı, harf aralığı 1,5 (metinde Arapça harf varsa 0), beyaz %45, ortalı, yanlarda 28.
- Sağ üstte (12 boşlukla) toplam indirme göstergesi (§3.10), sayı varsa. Açılış gösterisi sürerken sayı gösterilmez.

**b) Fiş yeni takıldı — Açılış animasyonu**
- Uygulamanın kendi açılış animasyonu (§3.11), 1040 × 586'lık pencere için çizilip TV genişliğine küçültülür; koyu
  tema. Bitince 0,4 sn ease-out ile canlı ekrana geçilir. Her takışta baştan oynar.
- Ekran ilk göründüğünde açılış gösterisi daha önce oynadıysa ve zaten etkinse bu animasyon atlanır.

**c) Canlı ekran**
- Zemin: GTA kipinde gün batımı fonu (§3.12, saydamlıkla gelir); değilse sol üstten sağ alta koyu lacivertten
  (r 0,09 g 0,12 b 0,24) koyu morumsuya (r 0,15 g 0,09 b 0,18) geçiş.
- İçerik 12 iç boşlukla:
  - Üst satır: solda **rozet** kapsülü: 6×6 kırmızı nokta (#E5162B) + 5 boşluk + rozet metni (`home.live.badge` ya da
    `demo.badge`), 9 pt kalın, beyaz, harf aralığı 1 (Arapçada 0); yanlarda 8, yükseklik 18, siyah %40 kapsül zemin.
    Sağda toplam indirme göstergesi (sayıyor kipte, §3.10).
  - Altta (alttan 4) duruma göre:
    - Sorun varsa: turuncu üçgen ünlem + 6 boşluk + sorun metni (beyaz %90), 11 orta, sola yaslı, en çok 5 satır,
      %60'a kadar küçülür.
    - Akmıyorsa: `home.stage.connecting`, 13 orta, beyaz %70.
    - Satır varsa: dikey (aralık 3): demoda İngilizcesi (9 pt, beyaz %55, tek satır), altında çeviri 17 yarı kalın
      beyaz, ortalı, en çok 3 satır, %60'a kadar küçülür; yanlarda 12, dikeyde 6 boşluk; siyah %62 zemin köşe 9
      (sürekli); metin yönü içeriğe göre. Her yeni satır saydamlık + 5 nokta aşağıdan kayarak gelir.
    - Satır yoksa: `home.stage.waiting`, 13 orta, beyaz %55.
- Satır değişimi ve GTA kipi değişimi 0,3 sn ease-out.

### 3.5 LED ışıkları

Görselin arkasında; takılınca yanar (saydamlık 0→1, 0,8 sn ease-in-out; hareketi azalt açıksa anında). GTA kipi
değişince renkler 1,2 sn'de geçer. Dört katman, hepsi soldan sağa renk geçişli:

| Katman | Biçim / yer | Bulanıklık |
|---|---|---|
| Geniş TV ışığı | köşe 30; TV çerçevesinin her yanından 20 taşan dikdörtgen | 46 |
| Dar TV ışığı | köşe 10; çerçeveden 5 taşan | 12 |
| Sehpa altı geniş | kapsül; genişlik sehpa−60, yükseklik 40; sol = sehpa solu+30, üst = sehpa altı−14 | 26 |
| Sehpa şeridi | kapsül; genişlik sehpa−90, yükseklik max(1,5 nokta, 8 piksel); sol = sehpa solu+45, üst = sehpa altı−4 | 4 |

(Ölçüler piksel; s ile çarpılır.)

Renkler (r, g, b 0–1):
- Normal: geniş = mavi (0,12 ; 0,36 ; 1,0) üç kez; dar = (0,3 ; 0,55 ; 1,0); şerit = (0,45 ; 0,65 ; 1,0).
- GTA kipi: geniş = pembe (1,0 ; 0,24 ; 0,62) → lila (0,74 ; 0,50 ; 0,96) → açık mavi (0,30 ; 0,78 ; 1,0);
  dar ve şerit = (1,0 ; 0,52 ; 0,78) → (0,84 ; 0,70 ; 1,0) → (0,58 ; 0,88 ; 1,0).

### 3.6 Priz parıltısı

Fiş takılı değilken prizin kenarından taşan, yanıp sönen ışık (fişin nereye takılacağı anlaşılsın). Priz merkezinde,
taban ölçü 86 piksel:
- Dış: köşe 16, renk (0,30 ; 0,66 ; 1,0), kenar 86+26 piksel, bulanıklık 18; saydamlık 0,3 ↔ 0,95.
- İç: köşe 12, renk (0,62 ; 0,84 ; 1,0), kenar 86+8, bulanıklık 5; saydamlık 0,45 ↔ 1.
- Yanıp sönme 0,95 sn ease-in-out, sonsuz, ileri-geri. Hareketi azalt açıksa sabit parlak.
- Takılınca 0,5 sn'de kaybolur. Dokunulamaz.

### 3.7 Fiş ve kablo

**Büyütme:** fiş görselde çok küçük kaldığı için çizimi k = s × büyütme ile ölçeklenir; büyütme = 0,3 / s, 1 ile 1,6
arasına sıkıştırılır.

**Fişin yeri:** takılıysa priz merkezi, değilse asılı durduğu yer; sürüklenirken parmağın kaydığı kadar (sahne
pikseline çevrilerek) eklenir.

**Fişin dönüşü (çekikken):** uzakta dümdüz aşağı sarkar; prize yaklaştıkça uçları prize döner. Kural: asılı yerin
prize uzaklığı D, fişin prize uzaklığı d; dönüş 120 piksel kala tamamlanır. t = (D − d)/(D − 120), 0–1 arası;
yumuşatma t²(3−2t); açı = yumuşatılmış t × (fişten prize olan yönün dikeyden açısı). D ≤ 120 ya da d ≤ 1 ise 0.

**Fiş çizimi:**
- Takılı ve sürüklenmiyorken: prizin önünde yuvarlak siyah kapak: çap 58k, sol üstten sağ alta gri (0,24) → siyah
  (0,04) geçiş, 1 pt beyaz %18 kenar, gölge siyah %45 yarıçap 3 aşağı 2.
- Değilse, yukarıdan aşağı aralıksız: boyun (13k × 14k, köşe 5k, çok koyu 0,06) → gövde (36k × 50k, köşe 9k, soldan
  sağa 0,22 → 0,04 geçiş, 0,5 pt beyaz %14 kenar) → iki metal uç (her biri 6k × 24k kapsül, aralarında 14k, soldan
  sağa açık gri 0,92 → 0,6). Bütünü yukarıdaki açıyla döner; gölge siyah %30 yarıçap 2 aşağı 1,5.
- Sürüklenirken %110 büyük.

**Kablo:** konsoldan fişe; çizgi kalınlığı max(1,8 nokta, 8 piksel), çok koyu gri (0,06), yuvarlak uç ve köşe, gölge
siyah %25 yarıçap 1,5 aşağı 1. Dokunulamaz.
- Konsoldan çıkış yolundaki noktalar düz çizgiyle birleştirilir (yol yoksa kablo başlangıcından başlar).
- Fiş takılı ve sürüklenmiyorsa: son noktadan, prizin 30 piksel altına kübik eğri; 1. kontrol = başlangıç + çıkış
  yönü × 90; 2. kontrol = bitiş + (10, 170). (Kablo alttan prize kıvrılır.)
- Değilse: fişin arkası = fişin yeri − uç yönü × (40 × büyütme). Sarkma = max(0, 330 − başlangıçla fiş arkası arası
  uzaklık) × 0,45. Eğri fiş arkasına: 1. kontrol = başlangıç + çıkış yönü × 70 + aşağı sarkma; 2. kontrol = fiş
  arkası − uç yönü × 80 + aşağı sarkma. (Uç yönü: dönüş açısına göre aşağıyı gösteren birim vektör.)
- Xbox'ta (yol yoksa) kablo başlangıcında küçük bir fiş başı: 14 × 12 piksel, köşe 3, çok koyu gri (0,08).

### 3.8 Dokunma ve sürükleme

- Prize dokunma: aç/kapa.
- Fişe dokunma: aç/kapa.
- Fişi sürükleme (en az 4 nokta hareketle başlar): fiş parmağı izler. Bırakınca bitiş noktası prize **160 pikselden**
  yakınsa "prizde" sayılır. Fiş 0,45 sn yaylı (sönüm 0,75) yerine döner; "prizde" sonucu şu anki takılı durumdan
  farklıysa aç/kapa çalışır (hafif dokunsal geri bildirimle). Hareketi azalt açıksa anında.
- Takılı durum değişince sahne 0,5 sn yay (sönüm 0,78) ile canlanır.
- Erişilebilirlik: sahne tek düğmedir. Adı takılıysa `scene.stop`, değilse `scene.start`; değeri (takılı ve akıyorsa) TV'deki satır; eylemi aç/kapa.

### 3.9 Açılış gösterisi

Uygulama her açıldığında yalnız **bir kez** (ayarlardan dönünce yeniden oynamaz): ilk görünüşte fiş bir an çekik
durur (çeviri kendiliğinden başlamış olsa bile), **0,9 sn** sonra 0,55 sn yay (sönüm 0,7) ile prize takılır. Ardından
toplam indirme sayacı sayarak çıkar. Hareketi azalt açıksa bekleme ve canlandırma yok.

Toplam indirme sayısı sahne görünürken başta ve sonra her 600 sn'de bir yenilenir.

### 3.10 Toplam indirme göstergesi (DownloadHUD)

Oyunlardaki para göstergesi gibi: sağa yaslı dikey yığın (aralık 1):
- Üstte başlık `scene.downloads`, **büyük harf**, 7,5 pt, beyaz, harf aralığı 0,6 (Arapçada 0).
- Altta sayı, binlik ayraçlı, 18 pt, yeşil (0,48 ; 0,91 ; 0,48), rakamlar eş genişlikte.
- Yazı tipi "Impact", en kalın (yoksa sistemin en kalını). Her yazının dört yönde keskin siyah çerçevesi (başlıkta 0,6,
  sayıda 1 nokta kaydırılmış bulanıksız gölgeler) ve altta derinlik gölgesi (siyah %90, çerçeve + 0,5 aşağı).
- Bütün gösterge hafif sağa eğik (yatay eğim −0,12, 2 nokta sağa kaydırma); Arapçada eğim yok.
- **Sayarak çıkma** (yalnız canlı TV ekranında; hareketi azalt kapalı ve sayı 3'ten büyükse): 0 → 1, 2, 3 (her adım
  280 ms) → sonra 1,55 sn içinde ilerleme p'nin 2,6'ncı kuvvetiyle hızlanarak toplam sayıya fırlar (en az 3; ~16 ms'de
  bir güncellenir) → toplam sayıda "vuruş": sayı sağ kenarından %132'ye büyür ve yeşil parlar (yarıçap 9), 0,22 sn yay
  (sönüm 0,45); 260 ms sonra 0,45 sn yay (sönüm 0,6) ile geri döner.
- Sayı kaynağı: Nino sunucusunun yapılandırma cevabındaki "downloads" alanı; kişisel bilgi gönderilmez; en son bilinen
  sayı cihazda saklanır; hiç alınamadıysa gösterge görünmez; sayıya ekleme yapılmaz.

### 3.11 Açılış animasyonu (TV'nin içinde oynayan)

Uygulamanın açılış ekranı: arka planda Nino zemini; ortada 200'lük logo bulanıklıktan (14) netleşerek %72'den %100'e
büyür (0,9 sn yay, sönüm 0,72); arkasında 290'lık, açısal geçişli (vurgu mavileri) 3 pt halka 2,4 sn'de bir döner ve
220'lik mavi %25 bulanık (60) bir parıltı büyür. 650 ms sonra altında kelime logosu (34) ve slogan saydamlıkla ve
12 nokta aşağıdan gelir (0,6 sn). Logodaki bayrak kırmızı ışıkla üç kez nabız gibi atar (0,55 sn) ve üstünden beyaz
bir parıltı geçer (0,9 sn, 0,15 gecikme). 1,7 sn sonra her şey %106'ya büyüyüp kaybolur (0,45 sn), sonra bitti
bildirilir. Hareketi azalt açıksa her şey hemen görünür, 0,9 sn sonra biter.

### 3.12 Gün batımı fonu (SunsetBackdrop) — GTA 6 kipi

Yalnız renk geçişi (oyunun logosu ya da görseli yok), yukarıdan aşağıya:
- 0 → (0,10 ; 0,08 ; 0,34) lacivert
- 0,40 → (0,46 ; 0,16 ; 0,62) mor
- 0,74 → (0,93 ; 0,29 ; 0,60) pembe
- 1 → (1,00 ; 0,55 ; 0,48) şeftali
Üstüne siyah %28 karartma. Dokunulamaz, okuyucudan gizli.

### 3.13 Eski iOS kartı (OldIOSTranslationNotice)

Koşul: cihazda Apple'ın ücretsiz çevirisi yok (iOS 26'dan eski) ve çevrimiçi bir motor anahtarıyla açık değil.

- Dikey yığın (aralık 10), sola yaslı, tam genişlik, 16 iç boşluk; zemin uyarı rengi %8, kenar uyarı rengi %35 (1 pt),
  köşe 22 (sürekli).
- Başlık satırı: uyarı renkli "info.circle.fill" + `oldios.title` (headline, ana yazı).
- Gövde (subheadline, ikincil, sarılır): `oldios.body` (%@ = sistem sürümü).
- Düğmeler: sığarsa yan yana (aralık 10), sığmazsa alt alta (aralık 8):
  - "key.fill" + `oldios.add`: subheadline yarı kalın beyaz, yanlarda 14 dikeyde 9,
    vurgu mavisi kapsül. Ana ekranda Ayarlar'ı açar.
  - Bağlantı: "arrow.up.right.square" + `oldios.get`: subheadline yarı kalın vurgu mavisi,
    dikeyde 9. Gemini'nin anahtar sayfasını tarayıcıda açar.

---

## 4. Demo örnek satırları (SampleLines)

Oyun metni değil, Nino'nun kendi örnekleri. Türkçe ve Arapça için altı satır:

| # | İngilizce | Türkçe | Arapça |
|---|---|---|---|
| 1 | Are you listening to me? | Beni dinliyor musun? | هل تستمع إليّ؟ |
| 2 | The bridge is out. Find another way. | Köprü yıkılmış. Başka bir yol bul. | الجسر مهدوم. ابحث عن طريق آخر. |
| 3 | Stay close and watch your step. | Yakınımda kal, adımına dikkat et. | ابقَ قريبًا مني وانتبه لخطواتك. |
| 4 | Wait for my signal at the old station. | Eski istasyonda işaretimi bekle. | انتظر إشارتي عند المحطة القديمة. |
| 5 | No one moves until I say so. | Ben söyleyene kadar kimse kımıldamıyor. | لا أحد يتحرك حتى أقول ذلك. |
| 6 | Relax, I know exactly what I'm doing. | Rahat ol, ne yaptığımı çok iyi biliyorum. | اهدأ، أعرف تمامًا ما أفعله. |

Öbür diller için üç satır (İngilizcesi hep aynı: "Who's there?", "Footsteps. Get behind the wall.", "Run for the
boat. Go!"):

| Dil | 1 | 2 | 3 |
|---|---|---|---|
| hi | वहाँ कौन है? | कदमों की आहट। दीवार के पीछे छिपो। | नाव की ओर भागो। चलो! |
| id | Siapa di sana? | Ada langkah kaki. Sembunyi di balik tembok. | Lari ke perahu. Cepat! |
| th | ใครอยู่ตรงนั้น? | มีเสียงฝีเท้า หลบหลังกำแพง | วิ่งไปที่เรือ ไปเลย! |
| vi | Ai ở đó? | Có tiếng bước chân. Nấp sau bức tường. | Chạy ra thuyền. Đi! |
| ur | وہاں کون ہے؟ | قدموں کی آہٹ۔ دیوار کے پیچھے چھپ جاؤ۔ | کشتی کی طرف بھاگو۔ چلو! |
| bn | ওখানে কে? | পায়ের শব্দ। দেয়ালের পেছনে লুকাও। | নৌকার দিকে দৌড়াও। যাও! |
| ms | Siapa di sana? | Ada bunyi tapak kaki. Sembunyi di sebalik dinding. | Lari ke bot. Pergi! |
| tl | Sino'ng nandiyan? | May yabag. Magtago ka sa likod ng pader. | Tumakbo ka sa bangka. Bilis! |
| nl | Wie is daar? | Voetstappen. Ga achter de muur. | Ren naar de boot. Nu! |

Seçim kuralı: hedef dilin üç satırlık listesi varsa sıradaki satır (sıra mod 3); yoksa altılı listeden sıradaki
satır, çeviri hedef Türkçe ise Türkçe, değilse Arapça.

---

## 5. Geçmiş ekranı (HistoryScreen)

Bu ve önceki oturumlarda çevrilen son satırlar, en yenisi üstte. Uygulama açılışta cihazdaki geçmiş dosyasını okur;
her yeni satır eklenince arka planda dosyaya yazılır. Saklanan en çok satır: **200**.

- **Üst satır (geri başlığı):** 44 yükseklik, aralık 12: "chevron.left" simge düğmesi (`common.back`; bir önceki
  sayfaya döner) + başlık `settings.history` (title boyu).
- **İçerik:**
  - caption ikincil: `history.limit` (%lld = 200)
  - Boşsa body ikincil, sarılır: `history.empty`
  - Doluysa tek karo (iç aralık 0), satırlar arasında 1 pt ayraç (#D3DEEF %70). Her satır (dikey yığın, aralık 4,
    dikeyde 12 boşluk, tam genişlik, tamamı dokunma alanı):
    - "saat · kaynak": saat yalnız saat (saniyeli, cihazın biçimi), caption eş genişlikli rakam. Kaynak paketse
      `packs.pack` ve renk paket laciverdi (#00205B); değilse `settings.engine`, üçüncül renk.
    - Çeviri (body, sarılır, metin yönü içeriğe göre ve tam genişliğe yaslı).
    - İngilizcesi (caption ikincil, sarılır).
    - Basılı tutunca bağlam menüsü: "doc.on.doc" + `common.copy`: "çeviri + yeni satır + İngilizcesi" panoya.
- **Alt bölge** (yalnız satır varsa), yan yana aralık 12:
  - İkincil düğme: "doc.on.doc" + `common.copyall`; dokununca tüm geçmiş düz metin olarak panoya, düğme
    "checkmark" + `common.copied` olur (ekrandan çıkana kadar öyle kalır).
  - Yıkıcı düğme: "trash" + `common.clear`; onay penceresi açar.
- **Onay penceresi** (alttan eylem listesi, başlık görünür): başlık `history.clear.confirm`; mesaj
  `history.clear.note`; yıkıcı düğme `common.clear` → geçmiş boşaltılır ve dosya yazılır. (Vazgeç düğmesi
  `common.cancel`.)

## 6. Oyun bölümü (GameAsk)

Çeviri sürerken ana ekranda: kart açıksa **soru kartı**, değilse **oynanan oyun satırı**.

Bu bölümün metinleri yeni katalogda yok; aşağıda yalnız anlamları verilir.

**Ne zaman sorulur:** çeviri başlayınca 15 sn'de bir bakılır; ayarda "oyunu sor" ve "ortak havuz" açıksa, bu oturumda
henüz sorulmadıysa ve oyun hiçbir yoldan (konsolun bildirdiği, paket, kullanıcı seçimi, ekrandan tanıma) bilinmiyorsa
**başlangıçtan 120 sn sonra** kart bir kez açılır. Çeviri durunca kart kapanır. Oyun sonradan tanınırsa kart kendiliğinden
kapanır.

**Soru kartı (GameAskTile)** — karo:
- Üst satır (ilk satır taban çizgisine göre hizalı): hangi oyunun oynandığını soran başlık (headline) + esnek boşluk
  (en az 8) + bir daha sorma anlamında caption ikincil düz düğme (bu oturumda bir daha sorulmaz, kart kapanır).
- Açıklama (caption ikincil, sarılır): pakette olmayan satırların oyunun adıyla ortak havuza gittiğini, böylece o
  oyunun hazır çevirisinin daha çabuk çıkacağını anlatan bir cümle.
- Arama alanı: yer tutucusu oyun arama anlamında; 52 yükseklik, beyaz %90 zemin, güçlü kenar, köşe 16, yanlarda 16, yazı
  headline normal; kelime başı büyük harf, otomatik düzeltme kapalı, klavyenin dönüş tuşu "bitti" türünde. Bu tuşa basılınca yazılan
  (baştaki/sondaki boşluk atılmış) boş değilse seçilir.
- Öneriler: en çok 5 satır, aralarında ayraç. Her satır düz düğme: oyun adı (body, ana yazı) + esnek boşluk + bu PS5'te
  son seçilen oyunsa son oynanan anlamında kısa etiket (caption ikincil); dikeyde 12 boşluk. Dokununca seçilir.
- Yazılan boş değilse ve önerilerde aynı ad (büyük-küçük/işaret farkı gözetmeden) yoksa ikincil düğme: oyunun listede
  olmadığını söyleyip yazılan adla kaydetmeyi öneren etiket (%@ = yazılan ad) → yazılanı seçer.
- Seçim bu oturumda ve aynı PS5'te bir sonraki oturumda (ilk öneri olarak) hatırlanır.

**Oynanan oyun satırı (PlayedGameRow)** — karo, yatay (aralık 12): küçük "gamecontroller" simgesi + dikey (aralık
4): oynanan oyun anlamında üst etiket (caption ikincil; en yakın yeni anahtar `home.nowplaying`) ve oyunun adı ya da
bilinmiyor anlamında kısa yazı (headline, tek satır) + esnek boşluk + düğme: oyun bilinmiyorsa seçme, biliniyorsa
değiştirme anlamında kısa etiket (caption yarı kalın, vurgu mavisi); dokununca kart açılır.

## 7. Ayarlar'daki alan karoları (History.swift içinde)

Bunlar ana ekranda değil, Ayarlar'da görünür; burada yer aldıkları için tarif ediliyor.

### 7.1 Altyazı alanı (AreaTile)

Karo:
- Başlık `settings.region` (headline).
- Dört bölmeli seçici: `region.bottom`, `region.top`, tam ekran bölmesi (yeni katalogda bu bölmenin ayrı anahtarı
  yok), `common.custom`. Seçici: #E6EDF8 zemin, köşe 16, 4 iç boşluk, bölmeler arası 4; seçili bölme beyaz zemin köşe 8 hafif
  gölgeli, yazı body yarı kalın ana renk; diğerleri orta kalınlık ikincil; en az 36 yükseklik; seçimde dokunsal geri
  bildirim. Seçim hazır bölgeyi uygular.
- Canlı önizleme (PhoneRegionPreview): son PS5 karesi üstünde altyazı bölgesinin çerçevesi; çerçeve sürüklenerek
  taşınır, köşesinden boyutlandırılır (sürüklemek bölgeyi özel bölmeye geçirir). Arapça arayüzde aynalanmaz. Yalnız son kare
  değişince yeniden çizilir.
- Yalnız özel bölmede iki kaydırıcı (vurgu mavisi), her biri üstte başlık (caption ikincil) ve sağda yüzde değeri (eş
  genişlikli rakam):
  - `subtitle.position.vertical`: 0 … max(1, 100 − yükseklik).
  - `subtitle.height`: en küçük bölge boyu×100 … 100.
- Alt not (caption ikincil): `region.edit.hint`

### 7.2 Ek alanlar (ExtraAreasTile, ExtraAreaEditor)

Bu karonun metinleri yeni katalogda yok; anlamları verilir.

Karo:
- Ek alanlar başlığı (headline).
- Açıklama (caption ikincil): Nino'nun altyazının yanında görev yazısı, telefon mesajı, bildirim gibi en çok üç küçük
  alanı da okuyabildiğini; her alanın yaklaşık saniyede bir okunduğunu ve yazı değişmedikçe yeniden çevrilmediğini;
  çevirinin TV'de asıl yazının yanında çıktığını anlatan kısa metin.
- Her alan için düzenleyici: #E6EDF8 zemin, köşe 16, 12 iç boşluk, dikey aralık 8:
  - Satır (aralık 8): ad alanı (yer tutucusu alanın adı anlamında, headline normal) + aç/kapa anahtarı (etiketsiz,
    vurgu mavisi; erişilebilirlik adı bu alanı okuma anlamında) + çöp kutusu düğmesi (ikincil renk; adı
    `common.clear`).
  - Üç bölmeli seçici: görev, bildirim, telefon; bölgesi bunlardan birine uymuyorsa görev bölmesi seçili görünür. Seçmek hazır bölgeyi uygular.
  - Bölge önizlemesi (son kare + çerçeve, sürüklenir); alan kapalıysa %50 saydam.
- Üçten azsa menü düğmesi (ikincil): "plus" + ek alan ekleme anlamında etiket; menüde üç seçenek: görev (sağ üst),
  bildirim (sol alt), telefon (sağ alt). Seçilen bölgeyle ve o seçeneğin adını varsayılan ad alarak yeni alan
  eklenir.

---

## 8. Modelin durumları ve eylemleri (ana ekranın kullandıkları)

### 8.1 Durum alanları

| Alan | Anlamı |
|---|---|
| çalışıyor (isRunning) | Gerçek çeviri oturumu açık. |
| başlatılıyor (isStarting) | "Başlat" sürüyor (genelde < 1 sn). |
| demo (isDemo) | PS5'siz önizleme sürüyor. |
| demo satırı | Demoda o an görünen örnek (İngilizce + çeviri) ya da boş. |
| oturum durumu | akıyor / bağlanıyor / koptu(neden). Başta "koptu: durduruldu". |
| son hata (lastFailure) | Çeviri sürerken en son neden bağlanılamadığı (§8.4). |
| telefon satırları (phoneLines) | Telefon ekranında o an görünen altyazı satırları (§8.6). |
| telefon ek alanları | Görev/telefon/bildirim kutuları (metin + oranlı kutu). |
| son satırlar (recentLines) | Bu oturumda çevrilen satırlar, en yenisi başta, en çok 30; her biri: sıra no, İngilizce, çeviri, paketten mi. |
| oturum satır sayısı / paketten gelen | Bu oturumdaki toplam ve paketten gelen satır sayısı. |
| başlama anı (runningSince) | Çevirinin başladığı an; durunca boş. |
| son oturum süresi | Son durdurulan oturumun saniyesi (cihazda saklanır; 0 ise yok). |
| ekran çevirisi durumu | boşta / sürüyor / gösteriliyor. |
| ekran çevirisi öğeleri | Ekran çevirisi sonuçları (yalnız altyazı telefondaysa doldurulur). |
| köşe öğeleri (hintItems) | Kendiliğinden çevrilen köşe yazıları ve telefon mesajı; altyazı TV'deyken boş. |
| TV istemci sayısı | Altyazı sunucusuna bağlı TV uygulaması sayısı. |
| TV uygulaması eksik | TV eşlenirken uygulama açılamadıysa evet. |
| TV güncellemesi | TV'deki sürüm telefondaki paketten eskiyse (marka, adres, kurulu ve paketteki sürüm). |
| geçmiş | Son 200 satır (§5). |
| çeviri durumu | hazır / indirme gerekiyor / desteklenmiyor. |
| paketler etkin | Paket ayarı açık ve kaynak İngilizce ve hedef Türkçe. |

### 8.2 Demo

- **Başlat:** gerçek oturum açık ya da açılıyorsa veya zaten demodaysa hiçbir şey yapmaz. Demo açılır, satır boşalır,
  ekran açık tutulur (§8.9). Döngü: 0,7 sn bekle → sıradaki örnek satırı göster → 2,8 sn bekle → satırı boşalt →
  0,6 sn bekle → tekrar. Ağa ve PS5'e dokunmaz.
- **Durdur:** döngü iptal, demo kapanır, satır boşalır, ekranı açık tutma isteği kalkar.

### 8.3 Başlat / Durdur

**Başlat:** önce demo durur. Zaten çalışıyor, başlatılıyor ya da başlatılamıyorsa çıkılır. "Başlatılıyor" açılır
(bitince kapanır). Sırasıyla: çeviri durumu yenilenir; altyazı sunucusu başlatılır (yerel ağda; olmazsa rastgele
portta) ve altyazı biçimi TV'ye gönderilir; okuma hattı kurulur; konsola (PS5 ya da Xbox) bağlanan oturum açılır ve
durum değişiklikleri, konsolun adres değiştirmesi, gelen kareler dinlenir; son hata silinir; altyazı TV'ye gidecekse
TV'yi 5 sn'de bir yoklayan "TV tutucu" başlar; oyun sorusu sayacı başlar (§6); "çalışıyor" açılır; başlama anı
yazılır; son satırlar, sayaçlar ve kullanılan paket sıfırlanır; ekran açık tutulur; bağlantı kopma bildirimi açıksa
bildirim izni (ilk seferde) istenir.

**Durdur:** oturum süresi saniye olarak saklanır ("son oturum"); başlama anı ve paket silinir; oyun sorusu kapanır;
konsol oturumu, TV tutucu, okuma hattı, ek alan/köşe/telefon/harita okuyucuları durur; "çalışıyor" kapanır; çevrimiçi
sorun ve son hata silinir; oturum durumu "koptu: durduruldu" olur; telefon ekranındaki altyazı, ek alanlar ve ekran
çevirisi kalkar; ekranı açık tutma isteği kalkar.

**Uygulama öne dönünce:** çalışıyorsa, arka plandan dönüldüyse ya da oturum kopmuşsa konsola hemen yeniden bağlanılır;
TV tutucu yeniden bağlanır. (Yalnız Denetim Merkezi/bildirim gibi kısa kesintide çalışan oturum kapatılıp açılmaz.)

**Oturum durumu değişince:** akarken kendiliğinden koptuysa (kullanıcı durdurmadı) ve tercih açıksa yerel bildirim
(`notify.ps5.lost`; uygulama öndeyken gösterilmez). Koptu durumunda okuyucular sıfırlanır ve TV'deki altyazı
temizlenir. Son hata şu kurala göre güncellenir: akıyorsa silinir; bağlanıyorsa korunur; koptu(durduruldu) eskisini
değiştirmez; koptu(ayrıntısız "diğer") PS5'te eskisini değiştirmez, Xbox'ta yazılır; öbür nedenler yazılır.

### 8.4 Durum ve neden metinleri

**PS5 durum metni** (tam ekranın sol üst etiketi):
- akıyor → `status.connected`
- bağlanıyor → `status.connecting`
- koptu ve çalışmıyor → `status.disconnected`
- koptu ve çalışıyor → nedenin metni, yoksa `status.reconnecting`

**Bağlantı sorunu metni:** çalışıyor, demo değil, akmıyor ve son hata varsa o nedenin metni; yoksa boş.

**Neden metinleri:**

| Neden | Metin |
|---|---|
| PS5 uykuda | `ps5.turnon` |
| başka cihazda kullanımda | `session.error.inuse` |
| reddedildi (kayıt) | `session.error.refused` |
| giriş şifresi isteniyor | `ps5.reason.passcode` |
| giriş şifresi yanlış | `ps5.reason.passcodeWrong` |
| eşleme geçersiz | anahtar yok; anlamı: PS5 bu eşlemeyi tanımadı, Ayarlar'dan ikinci hesapla yeniden eşleyin |
| Uzaktan Oynama kapalı | anahtar yok; anlamı: PS5'te Remote Play kapalı, PS5'te Ayarlar › Sistem › Remote Play'den açıp yeniden başlatın |
| görüntü yok | `session.error.nopicture` |
| bulunamadı (adres) | `session.error.notatip` (%@ = adres) |
| ağ | `session.error.unreachable` |
| reddedildi (kodlu) | `session.error.rejected` (%@ = kod) |
| reddedildi (kodsuz) | `session.error.notstarted` |
| diğer | Xbox'ta ayrıntı metninin kendisi; PS5'te metin yok |
| durduruldu | metin yok |

Kod "0x" + 8 haneli küçük harf onaltılık (ör. 0x80108bff).

**TV durum metni:** TV bağlıysa `status.connected`, değilse TV uygulamasının beklendiğini söyleyen kısa metin
(yeni katalogda anahtarı yok).

### 8.5 Telefon ekranına altyazı gelmesi

Altyazı sunucusunun TV'ye gönderdiği olayların aynısı telefona da gelir (TV kurulu olmasa da), ama yalnız çıkış
"telefonda göster"i içeriyorsa işlenir:
- Altyazı: satır yığınına eklenir (§8.6); "yerine geçer" işaretliyse önceki satırın düzelmiş okuması sayılır.
- Temizle: yığına "temizle" denir.
- Ekran çevirisi olayları yığına girmez.
- Ek alan: aynı kimlikli kutu değiştirilir; metin boşsa kutu kalkar. Ek alanları temizle: hepsi kalkar.
Her değişiklikte görünen satırlar hesaplanır ve bir sonraki değişim anına zamanlayıcı kurulur.

### 8.6 Satır yığını kuralları (telefon ve TV aynı)

- Yeni satır geldiğinde: önceki satır **1,5 sn'den kısa** süre önce gösterildiyse, "önceki satırı üstte tut" ayarı
  açıksa, ikisi de paragraf değilse ve aynı cümlenin başka okunuşu değilse önceki satır üste çıkar (en çok iki eski
  satır). Değilse eskiler silinir.
- Üstteki eski satır **1,5 sn** görünür, sonra **0,4 sn** "soluyor" (yatay ekranda %40 saydam) ve kalkar.
- Görünme süresi: bildirilen süre varsa max(1,2 sn, süre); yoksa min(8 sn, 2 + uzunluk × 0,06 sn). "Temizle" gelince
  satır okunacak kadar (min(5 sn, 2 + uzunluk × 0,06)) görünmediyse o süre dolunca kalkar.
- Dengeli sarma: 42 karakterden uzun (ve içinde satır sonu olmayan) satır en çok 3 satıra dengeli bölünür; sığmazsa
  yazı en çok %75'e kadar küçülür. Konuşan adı ("ARTHUR: …") bölünmez, hep ilk satırdadır. Paragraf satırları
  sarılmaz.

### 8.7 Ekranı çevir

- Çalışmıyorsa hiçbir şey yapmaz.
- Durum boşta değilse (sürüyor ya da gösteriliyor): **kaldır** (aşağıda).
Bu bölümdeki bilgi altyazılarının yeni katalogda anahtarı yok; anlamları verilir.

- Son PS5 karesi yoksa TV'ye/telefona 4 sn'lik altyazı: PS5'ten henüz görüntü gelmediği için ekranın
  yakalanamadığını söyleyen cümle.
- Değilse durum "sürüyor"; 2,5 sn'lik altyazı: ekranın çevrilmekte olduğunu söyleyen kısa metin. Karenin tamamı bir
  kez okunur, yazı grupları tek istekte çevrilir; her parti geldikçe TV'ye ve (altyazı telefondaysa) telefona
  gönderilir, durum "gösteriliyor" olur ve gösterim süresi dolunca kendiliğinden kaldırılır. Bitince altyazı temizlenir;
  hiç yazı yoksa durum boşa döner ve 2,5 sn'lik altyazı ekranda yazı bulunmadığını söyler.
- Hata: durum boşa döner, 6 sn'lik altyazı ekranın çevrilemediğini söyler ve nedeni ekler (%@); neden:
  - çevrimiçi motor dakikalık sınıra takıldıysa: motorun (%@ = motor adı) dakikalık sınırı doldu, bir dakika sonra
    yeniden denensin
  - indirme gerekiyorsa: ücretsiz çeviri henüz indirilmedi
  - desteklenmiyorsa: ücretsiz çeviri bu telefonda çalışmıyor
  - diğer: genel bir "bir sorun çıktı, yeniden deneyin" anlamı
- **Kaldır:** süren iş ve süre sayacı iptal, sonuçlar boşalır, durum boşta, TV'deki ekran çevirisi ve altyazı
  temizlenir; kendiliğinden çevrilen köşe yazıları hâlâ varsa geri gelir.

### 8.8 TV uygulaması sürüm denetimi

Uygulama açılınca (ana ekran) ve TV uygulaması her yeniden bağlandığında (bağlı TV sayısı 0'dan yukarı çıkınca)
sessizce çalışır; aynı anda birden çok çalışmaz; zorlanmadıkça 60 sn içinde tekrarlanmaz. Daha önce kurulan TV
uygulaması biliniyorsa onun markası/adresi, değilse eşlenmiş TV kullanılır. Telefondaki paketin sürümü TV'dekinden
yeniyse "TV güncellemesi" dolar, değilse boşalır; okunan sürüm cihazda saklanır.

### 8.9 Ekranı açık tutma (ScreenAwake)

iOS, kilitlenen ya da arka plana geçen uygulamayı askıya alır ve PS5/TV bağlantıları kopar; bu yüzden çeviri (ve
TV'ye kurulum) sürerken ekran kararmamalı.
- Birden çok neden aynı anda isteyebilir: **çeviri** ve **TV kurulumu**. Nedenler bir kümede tutulur; biri bitince
  öbürününki kapanmaz.
- Bir neden açılınca ya da kapanınca bayrak hemen uygulanır. Açarken iOS'un "unuttuğu" bayrağı yeniden
  etkinleştirmek için önce kapatılıp sonra açılır.
- Küme boş değilken **20 sn'de bir** bayrak yeniden uygulanır; küme boşalınca bu sayaç durur.
- Uygulama her öne geldiğinde bayrak yeniden uygulanır.
- Model, çeviri ve demo başlayınca "çeviri" nedenini açar, durunca kapatır.

---

## 9. Durum özeti (ekranda ne görünür)

| Durum | Durum satırı | Başlık | Sahne | Sahne altı | Ek |
|---|---|---|---|---|---|
| Eşlenmemiş | gri nokta, `home.status.notpaired` | `home.title.pair` | fiş çekik, priz yanıp söner, TV'de büyük harfle `scene.plug` | `slide.pair`; fiş/priz kurulumu açar | `demo.try` düğmesi |
| Hazır | mavi nokta, "PS5 · " + `home.status.ready` | `home.title.ready` | fiş çekik, priz yanıp söner | `scene.plug` | — |
| Bağlanıyor | mavi yanıp sönen nokta, "PS5 · " + `home.status.connecting` | `home.title.ready` | fiş takılı, LED'ler yanık, açılış animasyonu sonra `home.stage.connecting` | `scene.unplug` | `psn.controller.warning`, oyun satırı, `home.foreground.note` |
| Bağlanamıyor | turuncu yanıp sönen nokta | `home.title.ready` | TV'de turuncu ünlem + neden | aynı | aynı; tam ekranda neden ortada |
| Canlı (telefon) | yeşil, "PS5 · " + `home.status.live` | `home.title.live` | TV'de `home.live.badge` rozeti, sayaç, satır | + `home.fullscreen` | `home.rotate.hint`, ekran çevirisi düğmesi; yan çevirince tam ekran |
| Canlı (TV) | yeşil, "PS5 · " + `home.status.tv` | `home.title.live` | aynı | + `home.fullscreen` | ekran çevirisi düğmesi |
| Demo | yeşil, `demo.status` | `home.title.live` | TV'de `demo.badge` rozeti, İngilizce + çeviri | `scene.unplug` + `home.fullscreen` | `home.rotate.hint` |
| TV uygulaması eski | — | — | — | — | TV güncelleme karosu (§1.2 madde 8) |
| TV uygulaması eksik | — | — | — | — | `tv.install.fromphone` karosu |
| TV yok (çıkış TV, TV eşlenmemiş) | `home.status.notpaired` | `home.title.pair` | fiş çekik | `slide.pair` | başlatılamaz; fiş/priz PS5 sayfasını açar; Çıkış karosundan telefon seçilebilir |
