# Windows: oyun telefonu (GTA 6 mesajları), harita görev kartı ve ekran örtüleri — tarif

Bu belge, GTA 6'da oyunun içindeki telefonun ve harita ekranındaki seçili görev kartının nasıl
bulunduğunu, okunduğunu, çevrildiğini ve TV'ye "katman öğeleri" olarak nasıl gittiğini **davranış
olarak** anlatır. Kod yoktur. Bütün sayılar eski Windows uygulamasından birebir alınmıştır;
Mac'ten farklı olduğu yerler §14'teki tabloda toplanmıştır. Mac tarifi
(`docs/yeni/mac/telefon-harita.md`, `claude/yeni-mac-c9961f` dalında) yalnız karşılaştırma içindir;
sayısal bir kural için ona yaslanma, buradaki değerleri kullan.

## 0. Ortak kavramlar

- **Koordinatlar.** Bütün kutular kareye oranlıdır (0–1): sol, üst, sağ, alt. "Kare" PS5 görüntüsünün
  tamamıdır (16:9). Bir okumanın satır kutuları, okunan bölgeye göre gelir; "bölgeye yerleştirme"
  ile kareye çevrilir (`x_kare = bölge_sol + x × bölge_genişliği`, y için aynı).
- **Kutu birleşimi:** iki kutuyu birlikte çevreleyen en küçük kutu.
- **Sadeleştirme** (bütün anahtarların temeli): metin küçük harfe çevrilir (kültürden bağımsız; Türkçe
  Windows'ta `I` → `i` olmalı, `ı` değil), harf/rakam olmayan her karakter boşluk olur, art arda
  boşluklar teke iner, baş/son boşluk atılır. "Harf/rakam" Unicode'a göredir: her tür harf (büyük,
  küçük, başlık, değiştirici, diğer), birleşen işaretler ve her tür sayı karakteri. Yani `Señora` →
  `señora`, `$3,250 to next goal` → `3 250 to next goal`, `Body & Nutrition` → `body nutrition`.
- **Benzerlik oranı:** iki metin arasındaki Levenshtein uzaklığı `u` ise oran `1 − u / max(uzunluk)`.
  Aynı metinler (boş değilse) benzerdir; boş metin hiçbir metne benzemez.
- **Saat:** milisaniye cinsinden tekdüze saat (sistem açılışından beri geçen ms). Bütün bileşenler
  dışarıdan saat alabilmeli (testler sahte saat verir).
- **Renk:** her nokta (R, G, B) 0–255. **Parlaklık ×1000** = `R×299 + G×587 + B×114`; "parlaklık"
  dendiğinde bunun 1000'e tam bölümü kastedilir. `en_büyük` / `en_küçük` = üç kanalın en büyüğü /
  en küçüğü. Renk yazısı `#rrggbb`, küçük harfli onaltılık, her kanal 0–255'e kırpılmış.
- **Kare biçimi:** 32 bit BGRA (bayt sırası mavi, yeşil, kırmızı, alfa), satır adımı ayrı.
- **Okuma:** yazı tanımanın çıktısı; her satırın metni, kutusu (olmayabilir) ve güveni.
- **Sözcük:** metin boşluklarla bölünür, boş parçalar atılır. "Kırpma" yalnız boşluk karakterini
  atar (sekme vb. değil).

---

## 1. Ne zaman çalışır

### 1.1 "Telefon oyunu" kararı
Telefon ve harita okuyucuları yalnız **telefon oyunu** açıkken vardır. Telefon oyunu =
altyazı çevirisi duraklatılmamış **ve** şunlardan biri:

1. Kaynak dil `en` ve havuza sorulacak oyun **havuz öncelikli** (bugün yalnız GTA 6). Havuza sorulacak
   oyun: bilinen oyun havuz öncelikli listesindeyse o; değilse altyazı paketinin oyunu listedeyse o;
   değilse paketin oyunu, o da yoksa bilinen oyun.
2. Ya da kaynak dil `en`, oyun **hiç bilinmiyor** ya da yalnız **altyazı paketinden tahmin edilmiş**,
   ve havuz öncelikli ayarı **çeviri diline** izin veriyor (bugün Türkçe). (PS5 oyunu çoğu zaman
   söylemiyor; yeni kurulumda telefon hiç aranmıyordu. GTA 6 satırları başka oyunun paketinde de
   eşleşebildiği için paket tahmini kesin sayılmaz.)

Havuz öncelikli listesi ve oyun kaynağı (PS5 / kullanıcı / ekran / paket) `havuz-paketler.md` ve `denetleyici.md` §12.3’ün
konusudur; burada yalnız bu karar kullanılır.

Windows'ta Mac'teki "Köşeleri çevir" ayarı gibi ayrı bir anahtar **yoktur**; karar yalnız yukarıdakidir.

### 1.2 Okuyucuların kurulması ve kaldırılması
- Telefon oyunu açıkken gelen ilk karede iki okuyucu (telefon, harita) yoksa kurulmaları arayüz
  iş parçacığına bir kez gönderilir (aynı istek her karede yeniden gönderilmez; "kuyrukta" bayrağı).
- Her okuyucunun **kendi yazı tanıyıcısı** vardır (aynı tanıyıcı iki okumayı birden yapamaz; altyazı
  okumasını bekletmez). Tanıyıcı kaynak dilde kurulur; kurulamazsa (OCR dili yok) "kullanılamıyor"
  bayrağı konur ve okuma hattı yeniden kurulana kadar yeniden denenmez.
- Kurulurken bağlanan şeyler (§11.1): depodan birebir çeviri (havuz/paket), toplu
  havuz sorgusu, ortak yedek çevirmen, telefon sözlüğü (yalnız hedef dil `tr` iken açık), harita
  kartı için hedef dil, günlük, oyun tanıma geri çağrıları.
- Telefon oyunu kapanınca, okuma hattı (dil/motor değişti) yeniden kurulunca okuyucular sıfırlanıp
  bırakılır ve TV'deki örtüler kaldırılır. PS5 bağlantısı kopunca ikisi de sıfırlanır.

### 1.3 Her karede
Telefon oyunu açıkken, her gelen karede sırayla:
1. Harita okuyucusuna kare verilir (§9.1).
2. Telefon okuyucusuna kare verilir (§4.1).
3. Örtüler TV'de gösteriliyorsa ve son gönderimden **60 000 ms** geçtiyse aynı örtüler yeniden
   gönderilir (TV yan çevirileri 120 sn sonra kendisi kaldırır; uzun açık kalan sohbet kaybolmasın).

Her iki "kare ver" çağrısı hemen döner; okuma arka planda yapılır.

---

## 2. Oyunu ekrandan tanıma

Harita okuyucusu her okumasında (harita olsun olmasın) okunan satırları oyun tanıyıcısına verir.
Telefon okuyucusu sohbet ya da uygulama okuduğunda doğrudan "GTA 6 görüldü" der.

Okumada GTA 6'ya özgü yazı varsa oyun **`GTA 6`** olur:
- Harita ekranı (§8.1).
- Her satır önce menü temizliğinden (§8.2) sonra sadeleştirmeden geçer. Bir satırda hem `jason` hem
  `lucia` geçiyor (alt dizi olarak).
- Satırlar arasında tam olarak `brief` ve `progress` var **ve** (bütün satırların sözcükleri arasında
  `jason` ya da `lucia` var, ya da bir satır tam olarak `map`).
- Bir satır tam olarak `whatup` (telefonun mesaj uygulaması).

Tanınınca:
- Uygulama çalışmıyorsa bir şey yapılmaz.
- Bilinen oyunla aynı oyunsa (ad anahtarı: `GTA 6` ile `Grand Theft Auto VI` aynı anahtardır) bir şey
  yapılmaz.
- Oyun PS5'ten ya da kullanıcıdan biliniyorsa **ezilmez**.
- Değilse günlüğe oyunun ekrandaki yazılardan tanındığı (adıyla) yazılır, oyun "ekranda görüldü" kaynağıyla
  kaydedilir, "hangi oyunu oynuyorsunuz" sorusu kapanır, oyun yayınlanır ve çeviri eşitlemesi başlar.

| Okuma (satırlar) | Sonuç |
|---|---|
| ek A'daki `gta6-harita-buckme` | GTA 6 |
| `JASON & LUCIA`, `MAP`, `BRIEF`, `PROGRESS` | GTA 6 |
| `MAP`, `BRIEF`, `PROGRESS` | GTA 6 |
| `Reminders`, `WhatUp` | GTA 6 |
| `Options`, `Map`, `Progress`, `Quit Game` | yok |
| `Wait for me at the pier!` | yok |
| ek A'daki `gta6-altyazi-beyaz` | yok |
| ek A'daki `gta6-telefon-brian-parlama` | yok |

Oyun listesinde `GTA 6` kısa adı gösterilir; `grand theft` aramasında çıkar; boş aramada ilk sıradadır.

---

## 3. Telefonu karede bulma

Telefonun ekranı dikey, açık renkli, büyük bir dörtgendir; iki yanında koyu çerçeve vardır. Yaya
hâlde eğik tutulur: ekran bir **paralelkenardır** (aşağı indikçe sol kenar yana kayar).

### 3.1 Bulunan telefon
Şunları taşır: çevreleyen kutu; üst kenardaki sol x (`üst_sol`); **eğim** (sol kenarın, kare yüksekliği
kadar aşağıda, kare genişliği biriminde ne kadar kaydığı; dik telefonda 0); ekran genişliği (her satırda aynı).
- `y` yüksekliğinde sol kenar = `üst_sol + eğim × (y − kutu_üst)`; orta = sol + genişlik / 2.
- Dönme açısı (derece, saat yönü artı) = `atan(−eğim × 16 / 9)` derece. Örnek: eğim −0,1 → yaklaşık
  10,08° (9'dan büyük); eğim 0 → 0. (Windows bu açıyı TV'ye **göndermez**, bkz. §10.)

### 3.2 Küçültme
Kare **240 × 135** noktaya **alan ortalamasıyla** küçültülür: hedef noktanın (tx, ty) kaynak alanı
x'te `⌊tx × G / 240⌋` ile `max(başlangıç + 1, ⌊(tx+1) × G / 240⌋)` arası (G kare genişliği), y için
aynı; alandaki bütün noktaların kanal ortalaması (tam bölme). Kare boşsa telefon yoktur.

Bir nokta için `düşük = en_küçük`, `yayılma = en_büyük − en_küçük`.

### 3.3 Üç arama, sırayla
1. **Açık ekran:** beyaz nokta = düşük ≥ **118** ve yayılma ≤ **45**; koyu nokta = düşük < **90**.
   Şekil araması (§3.4) bulursa telefon odur.
2. **Kararmış ekran** (telefon dokunulmadan durunca ekran kararır): karenin ortasından örnek alınır —
   y `135/10 = 13`'ten `135×9/10 = 121`'e (hariç) 2'şer, x `240×15/100 = 36`'dan `240×85/100 = 204`'e
   (hariç) 2'şer; düşük değerleri sıralanır; `dilim = değerler[⌊adet × 95 / 100⌋]`. Dilim **40 ile
   117** arasındaysa (40 ≤ dilim < 118) `kazanç = 225 / dilim`; her noktanın düşük ve yayılması
   kazançla çarpılıp tam kısmı alınır ve açık ekran kuralları bu değerlerle yeniden denenir.
3. **Koyu temalı uygulama** (ör. araç çağırma): ekran noktası = `en_büyük ≤ 75` ve yayılma ≤ **40**;
   gövde noktası (koyu yerine) = `en_büyük ≥ 85`. Şekil araması bulursa:
   - Kutunun altı > **0,96** ise telefon yok.
   - **Yazı sınaması** (koyu kıyafet/gölge de koyu dikdörtgen verir): `üst = ⌊kutu_üst × 135⌋`,
     `alt = ⌊kutu_alt × 135⌋`; üstten alta (alt hariç, en az bir satır) her satırda
     `baş = ⌊sol(y/135) × 240⌋ + 2`, `son = baş + ⌊genişlik × 240⌋ − 4` (son ≤ baş ise satır atlanır);
     baş..son arasında (kare içine kırpılarak) `en_büyük ≥ 110` olan nokta sayılır. Sayı ≥ 2 ve
     ≤ `(son − baş + 1) × 0,6` ise satır "yazılı"dır. Yazılı satır sayısı ≥ `max(1, alt − üst) × 0,15`
     ise telefon budur, değilse yok.

Windows'ta "yalnız şekliyle bulma" (dikdörtgen bulucu) yolu **yoktur**.

### 3.4 Şekil araması (beyaz/koyu nokta haritasında)
Girdi: genişlik W (240), yükseklik H (135), "beyaz mı" ve "koyu mu" sınamaları.

**a) Şeritler.** En kısa şerit `⌊W × 0,12⌋` = 28, en uzun `⌊W × 0,30⌋` = 72 nokta. Her satırda soldan:
- Beyaz olmayan nokta atlanır. Beyaz noktada şerit başlar; `son` = bu nokta. İleriye bakılır: bakılan
  nokta `son`'dan en çok 4 ileride olduğu sürece (yani arada en çok 3 beyaz olmayan nokta) beyazsa
  `son` oraya taşınır.
- **Kırıntı atma** (gümüş çerçevenin 1–2 noktalık parlak çizgisi): şerit (bitiş − başlangıç) 6'dan
  uzun olduğu sürece başta art arda beyaz noktalar sayılır; sayı ≤ 2 ve hemen ardından gelen iki
  nokta beyaz değilse başlangıç o kadar ilerletilir ve beyaz olmayanlar da atlanır; değilse durulur.
  Sonda aynısı geriye doğru.
- Uzunluk (bitiş − başlangıç + 1) 28–72 ise şerit (başlangıç, bitiş) kaydedilir. Tarama `son + 1`'den sürer.

**b) Oylama.** Eğimler (nokta/satır) şu sırayla: 0, +0,02, −0,02, +0,04, −0,04, … , +0,30, −0,30
(31 eğim). Her eğim için her satırın her şeridi oy verir:
`kesişim = yuvarla(başlangıç − eğim × satır)` (yarımlar sıfırdan uzağa), kova anahtarı =
`⌊(kesişim + 400) / 2⌋ × 1000 + ⌊(bitiş − başlangıç) / 2⌋`. Her eğimde oya göre azalan, eşitlikte
anahtara göre artan ilk **3** kova, en az **8** oy aldıysa aday listesine (oy, eğim, anahtar) eklenir.
Liste oya göre azalan, eşitlikte **eklenme sırasıyla** (dik telefon önce) sıralanır. İlk **32** aday
sırayla sınanır; geçen ilk aday telefondur.

**c) Aday sınaması.**
1. Kovadan tahmini kesişim `= ⌊anahtar / 1000⌋ × 2 − 400`, tahmini genişlik `= (anahtar mod 1000) × 2`.
2. Her satırda, sol kenarı `tahmini_kesişim + eğim × satır`'a **3,5**'ten, genişliği (bitiş−başlangıç)
   tahmini genişliğe **4**'ten yakın ilk şerit "uyar".
3. Uyan satırlar, ardışık iki satır arası en çok **10** olacak şekilde parçalara ayrılır. Birden çok parça
   varsa ve iç parça (ilk satırı > 1 ve son satırı < H − 2) varsa yalnız iç parçalar kalır (telefonun
   üstündeki aydınlık pencere atılır).
4. En az **8** satır kalmalı.
5. Kesişim = kalan satırlarda `başlangıç − eğim × satır` değerlerinin ortancası (sıralı listede
   `[adet/2]`). Şerit genişliği = `bitiş − başlangıç` değerlerinin ortancası. Bir satırın sol kenarı
   `yuvarla(kesişim + eğim × satır)`.
6. **Çerçeve:** bir satırda "solu koyu" = sol kenardan 1–4 nokta solda (0'a kırpılarak) koyu nokta var;
   "sağı koyu" = `sol + şerit_genişliği + 1..4` (W−1'e kırpılarak) noktalarından biri koyu. "Solu açık
   değil" / "sağı açık değil" aynı yerlerde beyaz olmayan nokta. Çerçeveli = iki yanı koyu satır sayısı;
   kenarlı = iki yanı beyaz olmayan satır sayısı. Şart: çerçeveli ≥ satır × **0,7**, ya da (kenarlı
   ≥ satır × **0,85** ve çerçeveli ≥ satır × **0,35**). (Gündüz sahnelerinde telefonun bir kenarı açık renkli bir zemine değebilir.)
7. **Üst/alt kenar:** bir satır "parlak" = `max(0, sol)` ile `min(W−1, sol + şerit_genişliği)` arasında
   beyaz nokta sayısı ≥ o aralığın yarısı (aralık boşsa parlak değil). İlk satırdan yukarı, son satırdan
   aşağı parlak oldukça uzatılır; satır listesi bu aralıkla sınırlanır.
8. `boy = (son − ilk + 1) / H`. Şart: **0,38 ≤ boy ≤ 0,86** ve kalan satır sayısı ≥ `(son − ilk + 1) × 0,25`.
9. **Biçim** = `boy × 9 / ((şerit_genişliği + 1) / W × 16)`; **1,2–2,6** arası olmalı.
10. Üst sol = `kesişim + eğim × ilk`, alt sol = `kesişim + eğim × son` (yuvarlanmamış). Kutu:
    sol `max(0, min(üst_sol, alt_sol)) / W`, üst `ilk / H`, sağ `min(W, max(üst_sol, alt_sol) +
    şerit_genişliği + 1) / W`, alt `(son + 1) / H`.
11. Kutunun ortası (x) **0,30–0,80** arası, üstü ≥ **0,04**, ve (altı ≤ **0,96** ya da üstü ≥ **0,2**)
    (eğik indirilen telefon alttan taşabilir).
12. Sonuç: kutu, `üst_sol / W`, eğim `= eğim × H / W`, genişlik `(şerit_genişliği + 1) / W`.

### 3.5 Takip
Telefon bulucu bir "takipçi" içinde kullanılır (okuma hattında bir tane, telefon okuyucusunda bir
tane; ikisi ayrıdır). Takipçi: son yer, son yerin koyu ekran olup olmadığı, son görülme anı.

- **Ekran payı** (bir yerdeki ekran türü): kare 480 × 270 örnekleyiciyle (§3.6) okunur; satır 1..14
  için `y = üst + boy × satır / 15`, sütun 1..7 için `x = sol(y) + genişlik × sütun / 8`. Okunabilen
  noktalardan "koyu" isteniyorsa `en_büyük ≤ 85`, "beyaz" isteniyorsa `en_küçük ≥ 118` ve yayılma ≤ 45
  olanların oranı (nokta yoksa 0).
- **Yerini bul:** Telefon bulunursa: koyu mu = koyu payı ≥ **0,5**; yer, koyuluk ve an saklanır; döner.
  Bulunamazsa: son yer yoksa ya da son görülmeden bu yana ≥ **3 000 ms** geçtiyse yok. (Ayarlanabilir
  bir "en çok yaş" 20 000 ms vardır ama kullanılan süre `min(o, 3 000)`'dir; fiilen 3 sn. Hayalet
  telefon altyazıları kesik okutuyordu.) Değilse son yerde aynı tür ekranın payı (koyu idiyse koyu,
  değilse beyaz) **< 0,45** ise takip bırakılır ve yok; değilse son yer döner (son görülme anı
  **güncellenmez**).
- **Yazılardan benimseme:** Telefon uygulamasına özgü yazılar (§7.3) görüldü ama telefon bulunamadıysa
  yazıların kutuları verilir. Kutu yoksa bir şey olmaz. Son yer varsa ve son görülme 2 000 ms'den yeni
  ise bir şey olmaz. Değilse tahmini yer (aşağıda) alınır, koyu mu = koyu payı ≥ **0,45**, yer/koyuluk
  ve şimdiki an saklanır.
- **Tahmini yer:** `en_sol` (kutu yoksa 0,6), `en_sağ` (yoksa 0,78), `en_üst` (yoksa 0,3), `en_alt`
  (yoksa 0,8). Sol `max(0,02, en_sol − 0,015)`; sağ `min(0,98, max(en_sağ + 0,015, sol + 0,21))`;
  üst `max(0,04, min(0,2, en_üst − 0,02))`; alt `min(0,95, max(0,82, en_alt + 0,03))`; eğim 0,
  üst_sol = sol, genişlik = sağ − sol.
- **Sıfırla:** son yer unutulur.

Örnek (sahte saat): siyah 960×540 karede iki yazı kutusu `(0,60 0,40 0,75 0,42)` ve
`(0,60 0,60 0,72 0,62)` benimsenir (saat 0). Saat 2 000'de yerini bul → var (koyu ekran duruyor).
Saat 3 500'de → yok.

### 3.6 Renk örnekleyici
- Kare bir kez istenen boyuta (varsayılan **960 × 540**) §3.2'deki gibi küçültülür. `(x, y)` kesirleri
  için `cx = yuvarla(x × G)`, `cy = yuvarla(y × Y)` (yarımlar sıfırdan uzağa); `cx < 1`, `cy < 1`,
  `cx ≥ G − 1` ya da `cy ≥ Y − 1` ise renk yoktur. Renk, çevresindeki 3 × 3 noktanın kanal ortalaması
  (tam bölme). Kare boşsa hiçbir noktanın rengi yoktur.
- **Aydınlatılmış örnekleyici** (kararmış açık ekran için; telefon yerleşiminde hep bu kullanılır):
  `y` telefon üstü + 0,03'ten başlayıp alt − 0,02'nin altında kaldıkça 0,02 artarak, her y'de oran
  0,05, 0,15, …, 0,95 için `(sol(y) + genişlik × oran, y)` okunur. Renkler en_büyük'e göre sıralanır.
  `ekran = en_büyükler[⌊adet × 8/10⌋]`, `orta = en_büyükler[⌊adet/2⌋]`, `bölge = renkler[⌊adet × 8/10⌋]`,
  `gri = bölge.en_küçük / max(1, bölge.en_büyük)`, `en_parlak` = son. Şart: 40 ≤ ekran < 232,
  orta ≥ ekran × 0,8, gri ≥ 0,8, en_parlak ≤ ekran × 1,3. Sağlanırsa her renk kanalı `238 / ekran`
  ile çarpılıp tam kısmı alınır (en çok 255); sağlanmazsa (ya da hiç renk yoksa) düz örnekleyici.
  Koyu temalı uygulama bu şartı sağlamaz, olduğu gibi kalır.

---

## 4. Telefonun okunması

### 4.1 Zamanlama ("kare ver")
- Son okumanın başlangıcından bu yana geçen süre ≤ **600 ms** (ekranda telefon örtüsü yokken) ya da
  ≤ **1 000 ms** (örtü varken) ise bir şey yapılmaz.
- Bir okuma sürüyorsa (meşgul bayrağı) bir şey yapılmaz.
- Değilse okuma arka planda başlar, çağrı hemen döner. Okumada hata çıkarsa günlüğe
  telefon okumasının başarısız olduğu (hata türüyle) yazılır; meşgul bayrağı her durumda kalkar.

### 4.2 Okuma turu
1. Okuma anı kaydedilir, o anki oturum numarası alınır.
2. **Duraklatma:** harita okuyucusu "yakında açıktı" diyorsa (harita son görülmesinden itibaren
   5 000 ms tutma + **8 000 ms**, ya da harita kartı örtüsü ekrandaysa; §9) örtü temizlenir (§5.6) ve tur biter.
   (Sebep: harita ekranının açık renkli bölgesi telefon gibi görünebilir; o zaman harita tuşları çevrilirdi.)
3. Takipçiden yer istenir. Yoksa: örtü varsa ve telefon **1 200 ms**'dir görülmediyse (son
   "mesaj okundu" anına göre) örtü temizlenir; tur biter.
4. Telefon kutusu kareden kesilir. Kesilen görüntünün yüksekliği < 900 ve iki katı genişlik ve
   yükseklikte ≤ 2 600 ise iki kat büyütülür (720p karede yazı birkaç piksel boyunda).
5. Telefon tanıyıcısı **derin olmayan tek geçişle** okur; satırlar telefon kutusuna göre kareye yerleştirilir.
6. Okuma işlenir (§5).

---

## 5. Ekran türü ve telefon okuyucusunun durum makinesi

### 5.0 Okuyucunun tuttuğu durum
- Ekrandaki öğeler (TV'ye giden liste; boş = örtü yok).
- Son anahtar (ekrandaki okumanın anahtarı).
- Bir önceki okumanın mesaj metinleri (sadeleştirilmiş küme).
- Ekrandaki panelin mesaj metinleri (sadeleştirilmiş küme), başlığı, "sohbet mi" bayrağı.
- Son "mesaj okundu" anı, son okuma anı, meşgul bayrağı, oturum numarası.
- Yerleşim tabanı: yerleşimin kurulduğu telefon kutusu ve o anki öğeler.
- Çapalar: her mesajın (sadeleştirilmiş) telefon üstüne göre üst kenarı.
- Son mesajlar ve anı (altyazı hattına verilir, §7.4).
- Hafıza: sadeleştirilmiş İngilizce → çeviri (§6.5).

### 5.1 Harita tuşu
Okumada bir satır harita tuşu ise (§8.1 dar liste: `recenter`, `2d view`, `3d view`, `add marker`,
`remove marker`, `set destination`, `remove destination`, `close menu`; menü temizliğinden ve küçük
harften sonra tam eşleşme) örtü temizlenir; tur biter. (`markers`, `view on map`, `cinematic` burada
**sayılmaz**: işaretçi görünümünün tuşları yalnız harita ekranını tanır.)

### 5.2 Hangi satırlar
1. **Sohbet listesi** mi (§5.3.4)? Liste ise sohbet aranmaz.
2. Liste değilse ve **sohbet başlığı** (§5.3.1) varsa sohbet mesajları (§5.3.2) çıkarılır.
3. Mesajlardan **gönderen adları** (1–2 sözcük, hepsi büyük harfle başlar, `. , ! ? …` yok) atılır
   (grup sohbetinde balon üstündeki ad).
4. **Sohbet** = kalan mesajlardan en az biri **cümle** (§5.3.5).
5. Sohbetse mesajlar bunlardır. Değilse: okuma **mesaj listesi** (§5.3.4) ise hiçbir şey; değilse
   **uygulama satırları** (§5.3.6).
6. Liste boşsa: örtü varsa ve telefon 1 200 ms'dir görülmediyse temizlenir; tur biter.
7. Boş değilse: "mesaj okundu" anı şimdi olur; "telefon ekranı görüldü" bildirilir (oyun GTA 6, §2).

### 5.3 Ekran kuralları

#### 5.3.1 Sohbet başlığı
Telefon ekranının yüksekliği `E`. Okumanın satırları okuma sırasıyla denenir; başlık, şartları
sağlayan **ilk** satırdır:
- Kutusu var; üstü `telefon_üstü + E × 0,07`'nin altında **ya da** en üstteki satırın üstünden en çok
  0,002 aşağıda.
- Metin (kırpılmış) **ad gibi**: ya kişi adı kuralı (aşağıda) ya da (uzunluk ≥ 2, ≤ 5 sözcük, yalnız
  harf ve `, . ' ’ & -` ve boşluk, en az bir harf).
- Gezinme düğmesi değil: küçük harfli ve baştan/sondan `<`, `‹`, boşluk atılmış hâli `back`, `geri`,
  `done`, `close`, `cancel`, `edit` değil.
- Ortası (x), ekranın satırın ortası yüksekliğindeki ortasına `ekran_genişliği × 0,12`'den yakın.
- Hemen altında aynı girintide satır **yok**: üstü bu satırın üstünden 0,008'den fazla ve 0,05'ten az
  aşağıda olan ve girintisi (sol − ekranın o yükseklikteki solu) bu satırınkine 0,015'ten yakın başka
  kutu yoksa. (Listede adın altında önizleme olur.)

Başlık varsa ekran "sohbet adayıdır"; başlık metni kırpılmış satır metnidir.

**Kişi adı kuralı:** uzunluk 2–30; 1–4 sözcük; her sözcük büyük harfle ya da `&` ile başlar; her
sözcükte ilk harften sonra en çok 1 büyük harf; metinde küçük harf var; `. , ! ? : ; … "` yok.

#### 5.3.2 Sohbet mesajları
1. Başlık şeridinin altı = `max(telefon_üstü + E × 0,07, başlık_altı)` (başlık yoksa 0).
2. **Aynı satırdaki parçaları birleştir** (emoji satırı böler): satırlar sol kenara göre sıralanır
   (kutusuz satır 0 sayılır, olduğu gibi eklenir). Her satır için, eklenmiş satırlar arasında şu şartı
   sağlayan ilki aranır: küçük boy > 0, dikey örtüşme ≥ küçük boyun **%75**'i, `bu.sol − o.sağ ≤ 0,03`
   ve `bu.sol > o.sağ − 0,005`. Bulunursa metinler boşlukla birleşir, kutular birleşir (güven ilkinin);
   bulunamazsa satır yeni eklenir.
3. Satır alınır: kutusu var, kırpılmış metinde en az 2 harf, üstü > `başlık_şeridi_altı + 0,012`,
   altı < `telefon_altı − 0,01`. Üstten sıralanır.
4. **Satır aralığı:** ardışık üst farklarından 0,012–0,04 arasındakilerin en küçüğü; yoksa en küçük
   satır boyu × 1,2 (satır yoksa 0,025 × 1,2).
5. **Paragraf:** sonraki satırın üstü önceki satırın üstünden aralık × **1,6**'dan az aşağıda ve
   girintisi (sol − ekranın o yükseklikteki solu) paragrafın ilk satırının girintisine **0,02**'den
   yakınsa aynı mesajdır.
6. Metin = satırlar boşlukla. **Etiket** ise atılır (aşağıda). Kutu = satır kutularının birleşimi.
   Mesajın satır boyu = aralık × **0,85**.

**Etiket (mesaj değil):**
- Küçük harfli ve baştan/sondan `.`, `…`, `•`, boşluk atılmış hâli tam olarak: `new message`,
  `new messages`, `typing`, `delivered`, `read`, `today`, `yesterday`, `messages encrypted`.
- `messages encrypted` ya da `message encrypted` ile bitiyor (kilit simgesi harf sanılıyor: etiketin
  başına tek bir büyük harf eklenmiş okunur).
- Sadeleştirilmiş hâli uygulama adı: `ryde`, `rydeme`, `buckme` (mesaja eklenen bağlantı kartı).
- En az 2 sözcük, `. , ! ? …` yok ve her sözcük büyük harfle başlıyor ya da küçük hâli `del`, `de`,
  `la`, `of`, `the`, `&` (ek olarak gönderilen yer/eşya adı).

#### 5.3.3 Sohbet başlığı örnekleri (telefon kutusu verildi, eğim 0)
- Telefon `(0,575 0,215 0,783 0,859)`: `Kenton (0,653 0,233 0,690 0,248)`, `Yo! Thanks for the ride today
  (0,595 0,351 0,750 0,377)` → sohbet.
- Telefon `(0,583 0,207 0,792 0,852)`: `Suggested (0,608 0,230 0,661 0,249)`, `Donnie (0,635 0,272 0,669
  0,285)`, `Go get em (0,635 0,297 0,685 0,313)`, `Marla's Boat Rental (0,634 0,347 0,725 0,367)`, `Hey.
  U free later? I got (0,634 0,371 0,772 0,391)` → sohbet **değil**.
- Telefon `(0,59 0,2 0,79 0,81)`: `Harbor Bank, Pier Road (0,64 0,21 0,74 0,23)`, `Dear customer, please
  review the (0,61 0,55 0,76 0,57)` → sohbet, başlık `Harbor Bank, Pier Road`.

#### 5.3.4 Listeler (çevrilmez)
- **Sohbet listesi:** kutulu satırlar okuma sırasıyla; ardışık her (satır, sonraki) çiftinde satır ad
  gibiyse (1–3 sözcük, hepsi büyük harfle başlar, `. , ! ? : …` yok) ve sonraki satırın üstü bu satırın
  altından `boy × 1,2`'den az aşağıda ve sol kenarları 0,03'ten yakınsa bir çift sayılır. **≥ 3** çift → liste.
- **Mesaj kartı listesi:** en az 3 satır ve (kişi adı kuralına uyan ≥ 2 satır ya da `...`/`…` ile biten
  ≥ 2 satır).
- **Mesaj listesi** = (mesaj kartı listesi **ve** en az bir satır `...`/`…` ile bitiyor) ya da sohbet listesi.

Örnekler:
- `Seaside Bait & Tackle`, `Economy Ride`, `Pick A Ride`, `Edit Pickup Spot` (kutusuz) → mesaj listesi değil.
- `Donnie`, `You got my plane?! You be...`, `Brian`, `Remember, you get your h...` → mesaj listesi.
- `Messages (0,64 0,22 0,72 0,24)`, `Andy (0,62 0,30 0,65 0,32)`, `drive safe ok (0,62 0,325 0,74
  0,345)`, `Cal (0,62 0,38 0,64 0,40)`, `Bring snacks for the trip (0,62 0,405 0,77 0,425)`, `Lucia
  (0,62 0,46 0,65 0,48)`, `running late? (0,62 0,485 0,72 0,505)` → sohbet listesi; iki okumada da
  hiçbir şey gösterilmez, çevirmen çağrılmaz.
- Ek A'daki `brian-parlama`, `lucia-foto`, `egik-mavi`, `yakin-alt` okumaları sohbet listesi **değildir**.

#### 5.3.5 Cümle
Harf içeren sözcükler sayılır.
- ≥ 2 sözcük ve kırpılmış metin `.`, `!` ya da `?` ile bitiyor; ya da
- `!` ya da `?` içeriyor ve ≥ 2 sözcük; ya da
- ≥ 3 sözcük ve ilkinden sonraki sözcüklerden biri küçük harfle başlıyor.

| Girdi | Cümle mi |
|---|---|
| `Book Ride ($64)` | hayır |
| `Seaside Bait & Tackle` | hayır |
| `1.74 mi` | hayır |
| `Nice one! U see the boat yet` | evet |
| `Are you high right now?` | evet |
| `Left the keys under yuh mat bro` | evet |

#### 5.3.6 Uygulama satırları (sohbet olmayan ekran)
1. Her kutulu satır: kırpılır; baştaki harf, rakam, `$`, `€`, `£` olmayan karakterler atılır, yeniden kırpılır.
2. Küçük hâli `messages encrypted` / `message encrypted` ile bitiyorsa alınmaz.
3. En az 3 harf; üstü > `telefon_üstü + E × 0,07`; altı < `telefon_altı − 0,01`. Satır boyu =
   kutu yüksekliği × 0,85.
4. Üstten sıralanır. **Birleştirme:** sonraki satır öncekinin devamıdır, eğer
   `boşluk = yeni.üst − önceki.alt < yeni_boy × 0,6`, sol kenarlar 0,02'den yakın ve devam şartı
   sağlanıyorsa. Devam şartı: önceki satır yazar satırı değil (küçük hâli `by ` ile başlıyor ve harfli
   sözcük sayısı ≤ 4 ise yazar satırıdır) **ve** (yeni satır küçük harfle başlıyor **ya da** (önceki satır
   `. ! ? :` ile bitmiyor ve önceki satırda harf içeren en az 3 sözcük var)). Birleşince metin boşlukla, kutu birleşimle.
5. **Büyük harfli etiket ekranı:** her satırın harfleri büyük harfli hâline eşit ve ≤ 3 sözcükse ekran
   telefon değildir, boş liste döner. (Açık mavi kapının `△ CLOSE` ipucu "yakın" diye çevriliyordu.)

| Girdi (telefon `(0,59 0,2 0,79 0,81)`) | Satırlar |
|---|---|
| `$500 (0,70 0,33 0,77 0,36)`, `◆ Checking Account (0,61 0,38 0,72 0,40)`, `$3,250 to next goal (0,64 0,65 0,74 0,67)` | `Checking Account`, `$3,250 to next goal` |
| `△ CLOSE (0,62 0,5 0,70 0,52)` | boş |
| `◆ Checking Account (0,61 0,38 0,72 0,40)` | tek satır |

#### 5.3.7 Sohbet mesajı örnekleri (telefon `(0,58 0,197 0,793 0,854)`, eğim 0)
Okuma:
```
Kenton                              0,66  0,22  0,70  0,24
Club Marea del Sol                  0,63  0,295 0,755 0,315
Left the keys under yuh mat         0,60  0,372 0,752 0,394
bro. Good luck out there!           0,60  0,398 0,70  0,42
New message                         0,648 0,503 0,718 0,522
Can't believe u caught that         0,60  0,558 0,753 0,58
marlin. U got the magic touch.      0,60  0,582 0,754 0,604
Need u back out on the              0,60  0,607 0,731 0,629
reef tomorrow.                      0,60  0,632 0,662 0,652
Sure thing, see ya.                 0,667 0,689 0,766 0,712
```
Mesajlar: `Left the keys under yuh mat bro. Good luck out there!`; `Can't believe u caught that
marlin. U got the magic touch. Need u back out on the reef tomorrow.`; `Sure thing, see ya.`

Telefon `(0,575 0,215 0,783 0,859)`:
```
Kenton                              0,653 0,233 0,690 0,248
Message encrypted                   0,620 0,296 0,734 0,322
Shared Pin Ended                    0,624 0,478 0,707 0,496
Here r the coords bro. The          0,595 0,557 0,736 0,576
reef there is a good spot           0,595 0,581 0,747 0,602
Bahía de la                         0,626 0,646 0,734 0,665
Luna Roja                           0,625 0,668 0,681 0,694
```
Tek mesaj: `Here r the coords bro. The reef there is a good spot`.

Gerçek karede (`brian-parlama`, görüntüden bulunan telefonla): sohbettir; `Brian` mesaj değildir;
`Remember, you get your hands` ile başlayan bir mesaj vardır. `lucia-foto`: sohbet, başlık `Lucia`.

### 5.4 Okuma anahtarı, kaydırma ve "önceki okuma"
1. **Okuma anahtarı** = her mesaj için `sadeleştirilmiş_metin@⌊(mesaj_üstü − telefon_üstü) × 60⌋`,
   `|` ile birleşik. (Konumlar telefon kutusuna göredir: telefon elde oynasa anahtar aynı kalır; sohbet kaydırılırsa anahtar da değişir.)
2. Kilit altında: oturum değiştiyse ya da anahtar son anahtarla aynıysa tur biter.
3. **Kaydırma temizliği:** yerleşim tabanı ve örtü varsa: okunan mesajların (sadeleştirilmiş → ilk
   görülen üst farkı) haritası çıkarılır; tabandaki zemin olmayan öğelerin kaynakları sadeleştirilir;
   ortak olanlar bulunur. `kaydı` = ortaklardan birinin çapası varsa ve okunan yeri çapasından
   **0,02**'den fazla farklıysa. `sabit_okuma` = okunan **her** mesaj bir önceki okumanın metinlerinden
   birine benziyor (§6.1). `bayat = (kaydı ya da ortak × 2 < taban_öğe_sayısı) ve sabit_okuma`. Bayatsa
   öğeler, taban ve son anahtar silinir (gösterilen metinler, başlık, sohbet bayrağı **unutulmaz**) ve
   kilit dışında "örtü boş" bildirilir.
4. "Önceki" = bir önceki okumanın metinleri; bir önceki okumanın metinleri artık bu okumanın
   (sadeleştirilmiş) mesajlarıdır. Hafızanın bir kopyası alınır.

**Dikkat (sıra):** okuma anahtarı ve "önceki okuma" metinleri, aşağıdaki yarım mesaj atmadan **önce**
hesaplanır.

### 5.5 Yarım mesajlar (yalnız sohbette)
Hafızadan bulma (§6.5) burada da kullanılır.
- **Altta kesik son mesaj:** hafızada yok, altı > `telefon_altı − 0,06`, kutu boyu > satır boyu × 1,8 ve
  kırpılmış metin `. ! ? … " )` ile bitmiyor → atılır. Liste boş kaldıysa tur biter.
- **Üstte kesik ilk mesaj:** birden çok mesaj var, ilki hafızada yok, küçük harfle başlıyor **ve** üstü
  < `telefon_üstü + 0,095` → atılır.

Örnek (Kenton sohbeti, telefon `(0,58 0,197 0,793 0,854)`): `lol that was a wild night` üstü 0,372 iken
çeviriye gider; üstü 0,26 iken gitmez.

### 5.6 Örtü temizleme
Örtü yoksa bir şey yapılmaz. Varsa öğeler, taban, son anahtar ve gösterilen metin/başlık/sohbet
bayrağı silinir; "örtü boş" bildirilir.

### 5.7 Türkçenin kaynağı (her mesaj, sırayla)
1. Telefon sözlüğü (§6.6), yalnız sözlük açıksa (hedef `tr`).
2. Depodan birebir çeviri (havuz/paket).
3. Hafıza (§6.5).
4. Yoksa boş = "bilinmeyen".

### 5.8 Panel kararları
1. Ham başlık = sohbetse başlık metni, değilse boş. Kullanılan başlık = ham başlık ≤ 3 sözcük ve
   `. , ! ? …` içermiyorsa o, değilse boş.
2. Kilit altında (oturum değiştiyse tur biter):
   - **Sohbet değişti:** örtü varsa, başlık ve gösterilen başlık boş değilse ve sadeleştirilmiş hâlleri
     farklıysa: öğeler, taban, anahtar silinir ve gösterilen bilgiler unutulur; kilit dışında günlüğe
     sohbetin değiştiği (eski ve yeni başlıkla) ve eski panelin kaldırıldığı yazılır; "örtü boş" bildirilir.
   - `örtü_var` = öğeler boş değil.
   - **Aynı mesajlar:** örtü var, sohbet bayrağı gösterilenle aynı ve okunan metinler gösterilenlerle
     aynı (§6.1) → son anahtar = okuma anahtarı; tur biter (panel yeniden kurulmaz; TV'de yanıp sönmesin).
   - **Yeni mesajlar:** örtü varsa: gösterilenlerden hiçbirine benzemeyen mesajlar "taze"dir. Taze yoksa
     son anahtar = okuma anahtarı; tur biter. Tazelerden **herhangi biri** bir önceki okumanın metinlerine
     benzemiyorsa tur biter (panel korunur; tek bozuk okuma paneli değiştirmez). Hepsi benziyorsa devam edilir.
3. **Onay:** bilinmeyen mesajların her biri bir önceki okumanın metinlerinde **birebir** (sadeleştirilmiş)
   var mı? Yoksa ve bilinmeyen varsa: bilinmeyen sayısı < mesaj sayısı ve örtü yoksa **ara gösterim**
   (yalnız bilinenler; §5.9 "kesin değil"); tur biter. Bilinenler ilk okumada gösterilir, bilinmeyenler
   ikinci okumayı bekler.
4. Bilinmeyen yoksa: yerleştir (kesin; not: hepsinin hazır olduğu); tur biter.
5. Bilinmeyen varsa: bilinmeyen < mesaj sayısı ve örtü yoksa önce bilinenlerle **kesin** yerleştirme
   yapılır (not: hazır ve beklenen sayıları; bu yerleştirme anahtarı ve gösterilenleri yazar). Sonra çeviri (§6.4),
   sonra yeniden kesin yerleştirme (not: çeviri süresi ve havuzdan / tek tek çevrilen sayıları).

### 5.9 Yerleştirme
1. Renk = aydınlatılmış örnekleyici (§3.6).
2. Sohbetse **sohbet paneli** (§6.7, başlık = başlık metni), değilse **uygulama balonları** (§6.8).
3. Kilit altında (oturum değiştiyse çıkılır):
   - Son mesajlar = mesaj metinleri, an = şimdi. Çapalar yeniden yazılır (sadeleştirilmiş → üst − telefon_üstü; ilk görülen).
   - **Elde sallanma:** taban varsa `dx = (yeni_sol + yeni_sağ − eski_sol − eski_sağ) / 2`,
     `dy` aynı şekilde; `|dx| < 0,05` ve `|dy| < 0,05` ise bütün yeni öğeler `(−dx, −dy)` kaydırılır ve
     taban kutusu eski telefon kutusu kalır.
   - **Aynı kutuyu koru:** sohbet değilse ve eski öğe sayısı yeniyle aynı ve sırayla her çiftin çevirisi
     aynı ve üstleri 0,06'dan yakınsa bütün eski öğeler kalır. Değilse her yeni öğe için, kaynağı ve
     çevirisi aynı ve solu (sohbette 0,012 / uygulamada 0,04) ve üstü (0,015 / 0,06) yakın eski öğe
     varsa eskisi kullanılır.
   - Taban = (taban kutusu, öğeler); ekrandaki öğeler = bunlar.
   - **Kesin** ise: son anahtar = okuma anahtarı, gösterilen metinler = mesajların sadeleştirilmişi,
     gösterilen sohbet bayrağı, gösterilen başlık = sohbetse başlık metni (ham, süzülmemiş) değilse boş.
     **Ara gösterimde** bunların hiçbiri yazılmaz (sonraki okuma her şeyi yeni sayar).
4. Günlük: yazı sayısı, ilk kaynağın kısaltması → ilk çeviri, uygulama işareti ve not (zemin sayılmaz;
   uygulama işareti yalnız sohbet değilse). "Örtü değişti" bildirilir.

### 5.10 Sıfırlama
Oturum numarası artar (süren okumanın sonucu gösterilmez); öğeler, taban, anahtar, gösterilenler,
önceki okuma ve son mesajlar silinir; takipçi sıfırlanır; örtü vardıysa "örtü boş" bildirilir.
Hafıza **silinmez**.

---

## 6. Benzerlik, çeviri, hafıza ve telefonun yanındaki yerleşim

### 6.1 Benzer mesaj ve "aynı mesajlar"
- **Benzer** (iki sadeleştirilmiş metin): aynı; ya da biri ötekinin başı; ya da biri ötekinin sonu;
  ya da benzerlik oranı ≥ **0,75**. Bir metin bir kümeye benzer = sadeleştirilmiş hâli kümedeki bir öğeye benzer.
- **Aynı mesajlar** (okunan metinler, gösterilen küme): okunanlar sadeleştirilir, boşlar atılır. Okunan
  boşsa, gösterilen boşsa, `okunan × 2 < gösterilen` ya da `okunan > gösterilen + 1` ise hayır. Değilse
  her okunan gösterilenlerden birine benzer mi.

Örnekler (gösterilen = {`did you get my text`, `ok`}):
- `Did you get my text?' U OK` kümeye benzer (biri ötekinin başı).
- `Did you get my text??`, `OK` → aynı mesajlar.
- `The bait shop closes at nine.` → aynı değil. Boş liste → aynı değil.

### 6.2 Çevrilmeye değer mi
`a` = kaynağın, `b` = çevirinin sadeleştirilmişi. Değer: `b` boş değil, `a ≠ b`, ve (`b` `a`'yı içeriyor
**ve** `a` tek sözcük) değil. Örnek: `buckme` → `BuckMe mi?` değmez (marka adı çevrilmez);
`Checking Account` → `Ana Hesap` değer.

### 6.3 Çeviri sonucunun temizlenmesi
1. **HTML varlıkları:** metinde `&` varsa sırayla `&amp;`→`&`, `&#39;`→`'`, `&quot;`→`"`, `&lt;`→`<`,
   `&gt;`→`>`, `&apos;`→`'`.
2. **Simgeler:** Unicode karakter (vekil çiftler tek karakter sayılarak) "diğer simge", "matematik simgesi"
   ya da "özel kullanım" türündeyse atılır; boşluklar (her tür beyaz boşluk) teke iner, baş/son atılır.
3. **Tekrar:** sözcük, bir öncekiyle büyük/küçük harf farkı gözetmeden aynıysa ve harf içeriyorsa atılır.

| Girdi | Çıktı |
|---|---|
| `Geliyorum 👍` | `Geliyorum` |
| `Balık &amp; Yem` | `Balık & Yem` |
| `HEMEN GEL GEL GEL` | `HEMEN GEL` |
| `Şu şu tekne $9 $9` | `Şu tekne $9 $9` (harfsiz tutar tekrar edebilir) |

Telefonda sıra: simge temizliği (varlıklar dahil), kırpma, tekrar temizliği.

### 6.4 Bilinmeyenlerin çevirisi
- Kaynaklar = bilinmeyen mesajların metinleri (sırayla).
- **Toplu havuz sorgusu** bağlıysa (her zaman bağlıdır; §11.1): bağlam = sohbetse mesaj listesinde ilk
  bilinmeyenden önceki en çok **4** mesajın metni (`max(0, ilk − 4)`'ten ilk bilinmeyene kadar), sohbet
  değilse boş. Sorgu hata verirse sonuç boş sayılır. Dönen her boş olmayan sonuç o kaynağın çevirisidir.
  Kalanlar **yedek çevirmenle** (bağlıysa) çevrilir.
- Toplu sorgu bağlı değilse kalanlar okuyucunun kendi çevirmeniyle tek tek çevrilir.
- Tek tek çeviriler **aynı anda en çok 2**; hata veren boş sayılır.
- Her sonuç §6.3'ten geçer.
- Kilit altında (oturum değiştiyse çıkılır): boş olmayan **her** sonuç (havuzdan ya da yedekten) hafızaya
  yazılır; hafıza **5 000** kaydı aşarsa tamamen silinir.

### 6.5 Hafıza (Windows: yalnız bellekte)
- Anahtar: mesajın sadeleştirilmiş İngilizcesi; değer: temizlenmiş çeviri.
- **Bulma:** anahtar 5 sözcükten azsa yalnız birebir. 5 ve üstüyse birebir ya da `anahtar + " "` ile
  başlayan ya da `" " + anahtar` ile biten kayıtlardan **en uzun anahtarlı** olanın değeri (kesik okunan
  mesaj tam hâlinin çevirisini alır).
- Eski Windows'ta hafıza **dosyaya yazılmaz**; okuyucu nesnesiyle yaşar. Sıfırlama silmez; okuyucu yeniden
  kurulunca (dil/motor değişti, telefon oyunu kapandı, program kapandı) boş başlar. Test bunu bekler: "başka bir
  okuyucunun hafızası boştur, havuza yeniden sorulur".
- **Uyumluluk notu (Mac biçimi, eski Windows'ta yok):** Mac aynı hafızayı uygulama veri klasöründe
  `phone-memory-<hedef dil>.json` dosyasında tutar: **düz JSON nesnesi**, anahtar = sadeleştirilmiş
  İngilizce mesaj, değer = çeviri dizgesi; örnek `{"sure thing see ya": "Tamam, görüşürüz."}`. Dil
  başına ayrı dosya (`phone-memory-tr.json`); hedef dil değişince o dilin dosyası okunur; her çeviri
  turundan sonra bütünüyle (atomik) yazılır; 5 000'i aşınca boşaltılır. Yeni Windows bunu yazacaksa bu
  biçimi kullanmalı. **Varsayılan:** eski Windows gibi yalnız bellekte; dosya ancak ana oturum öyle karar verirse (klasörü de o belirler) yazılır.

### 6.6 Telefon sözlüğü (yalnız hedef `tr`)
Önce sadeleştirilmiş tam eşleşme. Sözlüğün kendisi kodda durur (`apps/windows/src/Nino.Core/Phone/PhoneGlossary.cs`,
tam eşleşme tablosu); anahtarları GTA 6 telefon uygulamalarının İngilizce yazılarının sadeleştirilmiş hâlidir.
Gruplar: gazete adları (Türkçesi İngilizcesiyle aynı; §6.2 yüzünden gösterilmez), spor/beslenme uygulaması
(beden tipi, antrenman, kalori, kilo cümleleri, aç/tok), yolculuk uygulaması (yolculuk bilgisi, ücret, araç seçimi,
varış değiştirme, çağırma/iptal), banka uygulaması (hesap türleri, birikim, bakiye, para yatırma/çekme, hareketler,
hedef), mesaj uygulaması etiketleri (şifreli mesaj notu, yeni mesaj, kişiler, öneriler, mesajlar, süresi dolan konum).
`body & nutrition` gibi `&` içeren bir anahtar yazılmaz: sadeleştirme `&`'yi sildiği için yalnız `body nutrition`
eşleşir.

Sonra kalıplar, sırayla:
1. **Parantezli tutar:** metinde `(` var, metin `)` ile bitiyor ve ilk `(`'den önceki kısmın
   sadeleştirilmişi sözlükte → `değer + " " + parantezden itibaren asıl metin`.
2. **`Ad - Seviye`:** metin tam olarak ` - ` ile iki parçaya bölünüyor; sol parçanın sadeleştirilmişi
   ad, sağınki seviye tablosunda → `ad + " - " + seviye`.
   Ad tablosu 5 (`muscle`, `body fat`, `stamina`, `strength`, `fat`), seviye tablosu 6 girişlidir (`high`, `low`,
   `medium`, `average`, `very high`, `very low`); Türkçeleri `PhoneGlossary.cs`'te.
3. **Tire düşmüş:** sadeleştirilmiş metnin ≥ 2 sözcüğü var, **son sözcük** seviye ve öncekiler (boşlukla)
   ad → `ad - seviye`. (İki sözcüklü seviye bu yolla tutmaz.)
4. **Seviye:** sadeleştirilmiş metin `level ` ile başlıyor ve asıl metnin 2. sözcüğünde `/` var →
   `Seviye ` + o sözcük.
5. **Hedef:** sadeleştirilmiş metin ` to next goal` ile bitiyor ve asıl metnin ilk sözcüğünde rakam var →
   hedef kalıbının Türkçe öneki (`PhoneGlossary.cs`) + boşluksuz ilk sözcük (virgüller noktaya).
6. Hiçbiri değilse yok.

Örnekler (Türkçe çıktılar `PhoneGlossary.cs`'teki karşılıklardır):

| Girdi | Sonuç |
|---|---|
| `Savings Account` | tam eşleşme |
| `$3,250 to next goal` | hedef kalıbı; tutar `$3.250` olarak kalır |
| `Are you high right now?` | yok |
| `Cancel Ryde ($64)` | parantezli tutar: sözlük karşılığı + ` ($64)` |
| `Recent Transactions` | tam eşleşme |
| `Level 2/5` | `Seviye 2/5` kalıbı |
| `Strength Workout` | tam eşleşme |
| `Stamina - Medium` | `Ad - Seviye` |
| `Fat - Very Low` | `Ad - Seviye` (iki sözcüklü seviye) |
| `Toned` | tam eşleşme |
| `Stamina Medium` | tire düşmüş → `Ad - Seviye` |

Uygulama ekranı sözlükle örneği: telefon `(0,59 0,2 0,79 0,81)`, okuma `$500`, `◆ Checking Account`,
`$3,250 to next goal` (kutular §5.3.6 tablosundaki gibi), iki okuma → tek gönderim, iki öğe: hesap adının sözlük
karşılığı ve hedef kalıbının sonucu (zemin yok), çevirmen hiç çağrılmaz.

### 6.7 Sohbet paneli (telefonun yanında)

**a) Balon rengi (her mesaj; "kaplama").** Mesaj ve çevirisi çiftlenir (az olanın sayısı kadar).
Çeviri kırpılır; boşsa ya da değmezse (§6.2) mesaj atılır. Kalanlar için:
- Kenar noktaları: yükseklik oranları 0,15, 0,35, 0,5, 0,65, 0,85 ve her birinde iç pay **0,0045** ve
  0,0027 (0,0045 × 0,6) için `(kutu_sol − pay, kutu_üst + boy × oran)`.
- İç noktalar: y oranı 0,15'ten 0,85'e 0,1 adım (8), x oranı 0,1'den 0,9'a 0,1 adım (9). Okunanlar
  parlaklığa göre sıralanır; en az 10 renk varsa en parlak `⌊adet × 4 / 10⌋` tanesi **zemin** adayıdır.
- Kenar = okunan kenar renklerinin en parlağı; hiç yoksa `(233, 233, 236)`.
- Dolgu = zemin adayı yoksa ya da `zemin_orta.parlaklık×1000 × 4 < kenar.parlaklık×1000 × 3` ise kenar;
  değilse zemin adaylarının ortadaki (`[adet/2]`) rengi.
- Yazı rengi: dolgunun parlaklığı (tam bölüm) > 140 ise `#2c2c2e`, değilse `#f5f5f7`.
- Kutu: mesaj kutusu x'te **0,0035**, y'de **0,004** genişletilmiş; satır boyu = mesajın satır boyu.

Örnek: mesajlar `On my way (0,61 0,5 0,7 0,53)` ve `Casa De Donnie (0,61 0,6 0,7 0,63)`, çeviriler
`Geliyorum`, `Casa De Donnie`; renk: x < 0,6075 ise `(233,233,236)`, değilse `(40,40,40)` → tek öğe,
dolgu `#e9e9ec`, yazı `#2c2c2e`, kutu mesajı kapsar.

**b) Sütun.** Telefonun ortası > 0,5 ise **solunda**: sağ = telefon_sol − **0,035**, sol =
`max(0,02, sağ − genişlik)`. Değilse **sağında**: sol = telefon_sağ + 0,035, sağ = `min(0,98, sol + genişlik)`.
Panelde genişlik **0,27**'dir (sütun hesabının varsayılanı 0,30; yalnız testte kullanılır).
Örnek: telefon `(0,58 0,197 0,793 0,854)` → sütun telefonun sol yanında (sağı < 0,58). Telefon
`(0,39 0,2 0,61 0,85)` → sütun solu > 0,61, sağı ≤ 0,98.

**c) Ölçüler.** İç = sütun ± **0,012**; balonun en çok genişliği = iç genişlik × **0,82**; balon iç
payı 0,012. Her mesaj için satır boyu `min(max(mesaj_satır_boyu, 0,018), 0,028) × 0,97`; çeviri
`en_çok − 0,012` genişlikte sarılır (§6.9) → satır sayısı ve en uzun satırın harf sayısı.

**d) Balon kutuları (üst üste binmesin).** `taban = 0`; her mesaj için yükseklik
`boy × max(1, satır) × 1,3`; üst `min(max(mesaj_üstü, taban), max(0, 0,98 − yükseklik))`; kutu
`(iç_sol, üst, iç_sağ, üst + yükseklik)`; yeni taban `üst + yükseklik + boy × 0,6`.
Örnek: mesajlar üstleri 0,40 ve 0,43, satırlar 3 ve 1, boylar 0,02 → ikinci kutunun üstü ≥ birincinin altı.

**e) Logo payı.** Sınır = `telefon_altı − 0,012 − 0,03`. Son kutunun altı sınırı aşarsa bütün kutular
aşan kadar yukarı kayar.

**f) Giden mesaj** (yalnız sohbette). Maviliği = `B − ⌊(R + G) / 2⌋` (dolgu renginden; okunamazsa 0);
en gri = en küçük mavilik. Girinti = mesaj_sol − ekranın o yükseklikteki solu; sağ girinti = mesaj_sağ −
aynı sol; en_sol_girinti ve en_sağ_girinti tüm mesajlar üstünden. Giden = şunlardan biri:
- Girinti > ekran_genişliği × **0,2**.
- `girinti − en_sol_girinti > genişlik × 0,1` ve `en_sağ_girinti − sağ_girinti < genişlik × 0,08`.
- `mavilik − en_gri ≥ 14`.

**g) Zemin.** Giden olmayan (yalnız birinci kurala göre) mesajlar için orta yükseklikte
`(ekran_solu(y) + ekran_genişliği − 0,012, y)` okunur; renkler R+G+B'ye göre sıralanıp ilk yarı
atılır, kalanın ilki zemin (yoksa `(226, 228, 233)`). **Açık sohbet** = zemin parlaklığı > 150; açık
sohbette zemin her kanalda beyaza %60 yaklaştırılır (`v + (255 − v) × 0,6`, tam kısım).
Zemin öğesi: kaynak boş, çeviri boş, kutu `(sütun_sol, telefon_üstü, sütun_sağ, telefon_altı)`,
satır boyu 0,02, dolgu zemin, saydamlık **0,6**, "zemin" bayrağı. Başlık verilmişse çevirisi başlık
(çevrilmez), satır boyu `min(max(en_büyük_mesaj_satır_boyu, 0,02), 0,028)`.

**h) Balonlar.** Genişlik `min(en_çok, en_uzun_harf × boy × 0,5 × 9/16 + 0,012 + 0,012)`. Giden:
`(iç_sağ − genişlik, iç_sağ)`; gelen: `(iç_sol, iç_sol + genişlik)`. Alt `+ boy × 0,3` uzar. Açık
sohbette dolgu: giden `(R × 0,86, G × 0,93, min(255, B × 1,04))`, gelen her kanal beyaza %70
(`c + (255 − c) × 0,7`), tam kısım. Öğe: kaplamanın kaynağı/çevirisi/yazı rengi, yeni kutu, satır boyu
= boy, açı **yok**, saydamlık **0,95**, "yan balon".
Öğe sırası: önce zemin, sonra balonlar (mesaj sırasıyla).
Not: her kaplama, kaynağı aynı metin olan **ilk** mesaja eşlenir; aynı metinli iki mesaj aynı yeri (ve satır boyunu) paylaşır (eski davranış).

Örnek (telefon `(0,59 0,2 0,79 0,81)`, eğim 0, ölçü = (1, harf sayısı)): `On my way (0,61 0,5 0,7 0,53)`
→ `Geliyorum`, `Where at? (0,72 0,6 0,77 0,62)` → `Nerede?`; renk x < 0,7 ise `(233,233,236)` değilse
`(200,220,245)`. Sonuç 3 öğe: zemin (telefonla aynı üst/alt, sağı ≤ 0,59, saydamlık 0,6); gelen balonun
üstü 0,5 (±0,001), dolgu `#f8f8f9`; giden balon gelenin sağında, dolgu `#acccfe`; balonlarda açı yok,
"yan balon", zemin içinde. Başlık `Lucia` verilirse zemin öğesinin çevirisi `Lucia`.
Mavimsi ışık örneği: `Honestly if they didn't let us (0,61 0,4 0,77 0,43)` ve `Not today. Rex keeps dodging the boss (0,61 0,5 0,77 0,53)`; renk y < 0,45 ise `(137,154,183)` değilse `(120,150,215)` → birinci
balonun solu = zemin solu + 0,012 (gelen), ikincinin sağı = zemin sağı − 0,012 (giden).
Gerçek kare (`egik-mavi`): `Shit went sideways…` ve `Will do` sağa (en soldakinden 0,02'den fazla
içeride), `Ah crap…` ve `Remember…` solda.

**i) Yalnız testte kullanılan yol.** Panel kurucusu "sohbet değil" kipinde de çağrılabilir (canlıda
uygulama ekranı §6.8'i kullanır): giden yoktur, her satır ekrandaki yatay yerine göre ölçeklenir
(`ölçek = iç_genişlik / ekran_genişliği`; sol = `iç_sol + max(0, girinti) × ölçek − 0,006`; sağ =
`min(iç_sağ, sol + max(genişlik, mesaj_genişliği × ölçek + 0,012))`), zemin yine eklenir, açık sohbet
düzeltmesi yapılmaz. Test: `$500`, `◆ Checking Account`, `$3,250 to next goal` satırları, renk y < 0,5 ise
`(155,80,187)` değilse `(233,233,236)` → 3 öğe; ikinci satırın balonu birincinin sağında başlar; birincinin
yazı rengi `#f5f5f7`. Yeni yazımda bu kip zorunlu değildir; yazılırsa bu testi geçmeli.

### 6.8 Uygulama balonları (sohbet olmayan ekran, canlı yol)
1. Satır–çeviri çiftlerinden değmeyenler (§6.2) atılır; kalmazsa boş.
2. **Uygulama rengi:** "en canlı" = okunan noktalardan doygunluğu (en_büyük − en_küçük) **60'tan büyük**
   ve en_büyük ≥ **120** olanlar arasında doygunluğu en büyük olan (eşitlikte ilk); yoksa yok. Önce başlık şeridi: `y`
   telefon üstü − 0,04'ten telefon üstü + 0,06'ya (hariç) 0,01 adım, her y'de oran 0,1..0,9 (9 nokta),
   `(ekran_solu(y) + genişlik × oran, y)`. Bulunmazsa her satırın dört yanı: `(sol − 0,006, orta)`,
   `(sağ + 0,006, orta)`, `(x_orta, üst − 0,006)`, `(x_orta, alt + 0,006)`. Bulunursa dolgu odur, yazı `#ffffff`.
3. **Renk yoksa** (beyaz haber uygulaması): `y` telefon üstü + 0,02'den alt − 0,01'e (hariç) 0,01 adım,
   oran 0,05..0,95 (19 nokta). Renkler 16'lık kovalara ayrılır (her kanal `⌊c/16⌋`); en kalabalık kova
   (eşitlikte küçük anahtar; anahtar = R kovası × 256 + G × 16 + B) ortalaması arka plandır. Satırların
   içinden (y üstten alta `max(boy/8, 0,002)` adım, x oranı 0,02..0,98 adım 0,02) renkler toplanır; arka
   plana toplam kanal farkı en büyük olan "yazı"dır. Arka plan açık (parlaklık×1000 > 128 000) mı:
   yazı farkı ≥ **90** ise açık zeminde yazı × 0,6, koyu zeminde her kanal `255 − (255 − c)/2`; değilse
   açıkta `#1c1c1e`, koyuda `#ffffff`. Dolgu = arka plan. Hiç renk okunamazsa dolgu `(58, 58, 60)`, yazı beyaz.
4. **Yazı boyu:** satır boylarının (× 1/0,85) ortancası, `min(max(…, 0,018), 0,028) × 0,95` — bütün balonlarda aynı.
5. Sütun (§6.7 b, 0,27). Sütun telefonun sol yanındaysa (sütun_sağ ≤ telefon_sol) balonlar **sağa** (telefona) yaslı,
   değilse sola.
6. Her satır: çeviri kırpılır; harf genişliği `boy × 0,5 × 9/16`; satır başı harf
   `max(8, ⌊(sütun − 0,03) / (harf × 0,85)⌋)`; satır sayısı `max(1, ⌈uzunluk / satır_başı⌉)`.
   Çok satırsa genişlik = sütun, yükseklik `boy × (1,22 × satır + 0,45)`; tek satırsa genişlik
   `min(sütun, uzunluk × harf + 0,03)`, yükseklik `boy × 1,55`. Üst: çok satırda satırın üstü, tek
   satırda `satır_ortası − yükseklik/2`; `max(…, taban)`, en çok `max(0, 0,98 − yükseklik)`. Taban
   `üst + yükseklik + boy × 0,4`. Öğe: kaynak satır metni, çeviri, kutu, satır boyu = boy, dolgu, yazı
   rengi, saydamlık **0,95**, "yan balon". Zemin paneli **yok**.

Örnek: telefon `(0,59 0,2 0,79 0,81)`; satırlar `Checking Account (0,61 0,38 0,72 0,40)` ve
`buckme (0,61 0,28 0,66 0,30)`, satır boyu 0,02; çeviriler `Ana Hesap`, `BuckMe mi?`; renk y < 0,45
ise `(155,80,187)` değilse `(233,233,236)` → tek öğe `Ana Hesap`, dolgu `#9b50bb`, yazı `#ffffff`,
telefonla aynı dikey hizada sol tarafta, dikey ortası 0,39 (±0,002).

### 6.9 Sarma (satır sayısı ölçümü)
Satır başı harf `max(12, ⌊genişlik / max(0,004, boy × 0,5 × 9/16)⌋)`. Sözcükler sırayla; mevcut satır
boş değilse ve `uzunluk + 1 + sözcük` sınırı aşarsa yeni satır. Hiç satır çıkmazsa metnin kendisi tek satır.
Ölçü = (satır sayısı, en uzun satırın uzunluğu).

---

## 7. Telefon ve altyazı hattı

Telefon oyununda altyazı hattı telefonun yazılarını altyazı saymaz. Hattın kendi takipçisi vardır (§3.5).

### 7.1 Okumadan önce (kare iş parçacığında)
- "Telefon aransın mı" = telefon oyunu.
- Son bulunan telefon (hattın kendi kaydı) son **5 000 ms** içindeyse "yakın telefon" odur.
- Aranıyorsa takipçiden yer istenir; bulunursa (takiple dahil) "bulundu" ve kayıt (kutu, an) güncellenir.
- Bulunan ya da yakın telefon varsa **maske kutusu** = o kutu, altı `max(alt, min(alt + 0,15, 0,84))`
  (ekranın gerçek alt kenarına kadar, ama altyazının başladığı 0,84'e inmeden). Bölgeye giren kısmı
  okunmadan **siyaha** boyanır: kutu her yanda 0,01 genişletilip bölge koordinatlarına çevrilir, bölge
  dışında kalan kısım kırpılır, içindeki noktalar (0,0,0, alfa 255) olur.
  Örnek: 200×100 beyaz bölge (kare y 0,5–1), telefon `(0,5 0,2 0,8 0,75)`, pay 0 → bölgede (130,10)
  siyah; (130,80) ve (20,10) beyaz.

### 7.2 Okumadan sonra (sıra önemli)
1. Maske kutusu (§7.1; altı uzatılmış kutu) varsa: ortası (kareye göre) bu kutunun 0,02 genişletilmiş hâlinin içinde kalan satırlar atılır.
2. Telefon aranıyorsa ve bölgenin görüntüsü varsa: **açık zeminde koyu yazı** (§7.3) olan satırlar atılır
   (telefon bulunamasa da). Örnekleyici bölgenin kesilmiş görüntüsüyle kurulur (960×540), satır kutuları
   bölgeye göredir.
3. Telefon aranıyorsa: **telefon uygulaması yazısı** (§7.3) olan satırlar bulunur; varsa kutuları kareye
   çevrilir; telefon bu karede bulunmadıysa hattın takipçisi bu kutuları benimser; telefon okuyucusuna da
   bildirilir (onun takipçisi benimser); bu satırlar atılır.
4. Telefon okuyucusunun son mesajları (son **30 000 ms**) sadeleştirilir.
5. Maske kutusu varsa ya da son mesaj varsa: ortası (kareye göre) **0,8**'in üstünde kalan satırlar atılır.
6. Son mesaj varsa: sadeleştirilmiş hâli ≥ 3 sözcüklü ve bir mesajın içinde geçen satırlar atılır.
7. Sonra (hattın olağan sırası): dev yazılar, **ortadan uzak satırlar** (telefon aranıyorsa; ortası
   karede 0,5'ten 0,12'den uzak satır atılır), düğme ipuçları vb., altyazı bloğu.
8. Harita ekranı açıksa (§9) okuma boş sayılır (altyazı yok).

Örnekler:
- Kare 960×540 karanlık (20), ortada beyaz (240) telefon x 0,58–0,79 y 0,2–0,85; bölge üst 0,62 alt 0,97
  sol 0,14 sağ 0,86. Okuma (bölgeye göre): `Can't believe u caught that` (kare 0,60 0,66 0,75 0,68),
  `marlin. U got the magic touch.` (kare 0,60 0,69 0,75 0,71). Telefon araması açıkken 6 kare → hiçbir şey
  gönderilmez, çevirmen çağrılmaz. Kapalıyken çevirmen çağrılır.
- Okuma `You got my plane?! You better (0,3 0,7 0,7 0,8)`, son mesaj `Donnie: You got my plane?! You better
  be good to her` → altyazı yok.
- Harita açıkken `Meet me behind the bait shop.` → altyazı yok.
- Ortadan uzak: alan `(0,14 0,62 0,86 0,97)`, `The tide is coming in fast. (0,35 0,5 0,65 0,6)` ve `Dock Fees Due
  (0,80 0,1 0,95 0,2)` (alana göre) → yalnız `The tide is coming in fast.`.

### 7.3 Yardımcı sınamalar
**Açık zeminde koyu yazı:** kutunun içinde y üstten alta `max(boy/6, 0,001)` adım (alt dahil), x oranı
0,02'den 0,98'e 0,03 adım (33 nokta); okunan renklerin parlaklıkları (tam bölüm) toplanır. 20'den azsa
hayır. Sıralanır: `koyu = [n/20]`, `orta = [n/2]`, `parlak = [n×19/20]`. Evet = `orta − koyu ≥ 25` ve
`orta − koyu > (parlak − orta) × 2`.
Örnek: kutu `(0,2 0,4 0,6 0,5)`; renk `⌊x×200⌋ mod 4 = 0` ise `(250,250,250)` değilse `(30,30,30)` → hayır
(beyaz altyazı); tersi (`(30,30,30)` / `(235,235,238)`) → evet. Gerçek karelerde (`altyazi-beyaz`, bölge
0,66–0,97 / 0,14–0,86): `…gonna love it…` hayır; `finder…` ve `lockups…` evet. `yakin-alt`: `plane` ve
`good to her` geçen satırlar evet.

**Telefon uygulaması yazısı:**
- `" " + sadeleştirilmiş`'te `" " + kök` geçiyor; kökler: `trip detail`, `change destinat`, `destinatio`,
  `messages encrypt`, `map pin expir`, `checking accoun`, `family saving`, `workout window`,
  `strength workout`, `cardio workout`, `calorie balanc`, `maintain weight`, `gain weight`, `lose weight`
  (OCR bir harf kaçırsa da tutsun).
- Ya da sözcüklerden biri tam olarak `ryde`, `rydeme`, `buckme`.
- Ya da parantezli kısımları (ilk `(`'den son `)`'ye kadar) silinmiş metnin sadeleştirilmişi sözlükte tam var.
- Ya da metin ≥ 2 sözcük ve sözlük kalıbıyla (§6.6) çevriliyor.

| Telefon yazısı | Değil |
|---|---|
| `Stamina High`, `Strength Workout`, `Calorie Balanc`, `You will gain weight`, `I Change Destinatlon`, `Cancel Ryde ($64)`, `Choose Ryde`, `Trip Detail`, `rydeme`, `Savings Account` | `Nice catch!`, `Back to the boat`, `Plans changed, see you at the marina`, `Ryder left his bike outside`, `My workout can wait till Monday` |

Türkçe kültürde de: `RECENT TRANSACTIONS` telefon yazısıdır; `RECENTER` + `SET DESTINATION` harita ekranıdır.

### 7.4 Telefon okuyucusunun altyazıya verdikleri
- Son mesajlar: son yerleştirmedeki mesaj metinleri, yalnız yerleştirmeden sonraki 30 000 ms içinde
  (sonra boş). Sıfırlama siler.
- Telefon oyunu açık mı (§1.1) ve harita açık mı (§9) da hatta verilir.
- Windows'ta görev şeridi çizgisi (0,935) **kapalıdır** (hatta "çizgi yok" verilir); şerit kuralı var
  ama kullanılmaz. Kural (yazılacaksa): alan içinde üstü kareye göre ≥ çizgi olan satırlar atılır;
  konuşan adıyla başlayan satır ve onun hemen altındaki (üstü konuşan satırın altından `max(0,02, boy × 1,5)`'ten
  az aşağıda) devamı kalır. Örnek: alan `(0,14 0,62 0,86 0,97)`, `Give me two minutes. (0,3 0,70 0,7 0,76)`
  ve `Go to the marina office (0,35 0,905 0,65 0,96)` → yalnız ilki; `CAL: Grab the cooler, (0,3 0,86 0,7 0,90)`
  ve `the fish won't wait. (0,35 0,905 0,65 0,945)` → ikisi de kalır.
- Windows'ta mesaj kartı ve köşe okuması **yoktur**; Mac'teki "telefon son 3/10 sn'de görüldüyse" kuralları yok.

---

## 8. Harita ekranı ve görev kartını bulma

Harita ekranında yalnız **seçili görevin kartı** çevrilir; menünün kalanı çevrilmez.

### 8.1 Harita ekranı ve harita tuşu
- **Harita tuşları (dar liste):** `recenter`, `2d view`, `3d view`, `add marker`, `remove marker`,
  `set destination`, `remove destination`, `close menu`.
- **Ekran tuşları:** dar liste + `view on map`, `markers`, `cinematic` (işaretçi görünümü: dünya bulanıklaşır, işaretçinin yanında görev kartı çıkar).
- **Harita ekranı** = satırların menü temizliğinden geçmiş, kültürden bağımsız küçük harfli hâllerinden
  ekran tuşlarına tam eşit olanların **farklı** değerlerinden en az **2** tane.
- **Harita tuşu mu** (telefon okuyucusu için, §5.1) = temizlenmiş küçük hâli dar listede.

### 8.2 Menü temizliği (simge kırıntıları)
Metin beyaz boşluklarla sözcüklere bölünür.
1. Baştaki sözcük harf içermiyorsa ya da (≤ 2 karakter ve tamamı harf değil) ise atılır; tekrar.
2. En az 2 sözcük varken: ilk sözcük ≤ 2 karakter, (hiç büyük harf içermiyor ya da tam olarak `Il` ya da
   `II`) ve ikinci sözcük büyük harfle başlıyorsa ilk sözcük atılır; tekrar. (Simge küçük harf sanılır:
   `i Settings`, `ii Map`, `Il Game`.)
3. Sondaki sözcük harf ya da rakam içermiyorsa atılır; tekrar.
4. Boşlukla birleştirilir.

Örnekler: `◇ SHOW ROUTE` → `SHOW ROUTE`; `ADD MARKER •` → `ADD MARKER`; `i Settings` → `Settings`;
`SET DESTINATION X` → değişmez (`X` harf); `2D VIEW` → `VIEW` (ilk kural `2D`'yi atar: 2 karakter ve
tamamı harf değil; dolayısıyla `2d view` tuşu pratikte hiç eşleşmez — eski davranış budur, koru).

Örnekler: ek A'daki `buckme` ve `balik` okumaları harita ekranıdır (`RECENTER`, `ADD MARKER`, …);
`brian-parlama` değildir; tek satır `You trying to kill me?` değildir; `◇ CINEMATIC` + `MARKERS`
harita ekranıdır; `MARKERS` harita tuşu değildir, `RECENTER` harita tuşudur.

### 8.3 Kartı bulma
1. **Satır adayları.** Kutulu her satır: kutunun sağı ≤ **0,30** ise atılır (sol menü). Metin kırpılır.
   - **Uzaklık etiketi:** metinde "(isteğe bağlı boşluk) sözcük sınırı, rakamlar, isteğe bağlı nokta ya
     da virgülle ondalık kısım, isteğe bağlı tek boşluk, `km`/`mi`/`ft`/`m`, sözcük sınırı (isteğe bağlı
     boşluk)" kalıbı varsa her geçtiği yer tek boşlukla değiştirilip kırpılır; ayrıca kutunun solu 0,5'ten
     küçükse 0,5 yapılır. (`1.53 km` kartın satırıyla birlikte okunabiliyor. `0.9 kg` bu kalıba girmez.)
   - **Baştaki simgeler:** metnin başında, bir ya da daha çok "ASCII harf ve boşluk olmayan karakterlerden
     oluşan parça + en az bir boşluk" dizisi varsa ve ardından bir ASCII harf geliyorsa bu baş silinir;
     kutunun solu `(silinen uzunluk / metin uzunluğu) × kutu genişliği` kadar sağa kayar.
     Örnekler: `(43) Cal challenged…` → `Cal challenged…`; `• • Find the Lost Drugs` → `Find the Lost
     Drugs`; `◆ amenities and cheap rates…` → `amenities and cheap rates…` (rota çizgisi kartın üstünden
     geçince düşen simge); `i Use the index…` değişmez (`i` harf).
   - Sol ≤ 0,30 ya da 3'ten az harf → atılır. Kalanlar üstten sıralanır.
2. **Cümle satırı:** ≥ 3 sözcük ve ≥ **6** küçük harf.
3. Cümle satırı yoksa kart yok. İlk cümle satırı kartın başıdır. Üstü ondan aşağıda olan satırlar
   sırayla, her biri kartın **son** satırına göre:
   - Cümle satırı, `boşluk = yeni.üst − son.alt < son_boy × 2,6`, yatayda örtüşüyor
     (`yeni.sol < son.sağ` ve `son.sol < yeni.sağ`) ve sol kenarı **ilk** satırınkine **0,06**'dan yakın → kartta.
   - Değilse: boşluk < son_boy × **1,2**, sol kenarı **son** satırınkine **0,03**'ten yakın, küçük harf
     içeriyor ve son satır `. ! ?` ile bitmiyor → kartta (cümlenin kısa son satırı).
4. **Cümlelere ayırma.** `uç` = kart satırlarının en büyük sağı. Her kart satırı:
   - "Devam" = satır küçük harfle başlıyor ve (bir önceki cümle var ve son satırı `. ! ?` ile bitmiyor).
   - Bir önceki cümle varsa ve (devamsa **ya da** (sol kenarı o cümlenin ilk satırına 0,03'ten yakın,
     o cümlenin son satırının altından son satırın boyundan az aşağıda, ve **değil** (son satırın sağı
     `uç − 0,04`'ten küçük **ve** yeni satır büyük harfle başlıyor))) → o cümleye katılır. Değilse yeni cümle.
5. **Başlık:** bütün aday satırlar arasında: altı ≤ ilk_cümle_satırı.üst + 0,01, `ilk.üst − alt < 0,06`,
   yatayda örtüşüyor (`satır.sol < ilk.sağ` ve `ilk.sol < satır.sağ + 0,05`), metni büyük harfli hâline
   eşit (kültürden bağımsız) ve ≥ 3 harf. Sağlayanların **sonuncusu** (en alttaki) başlıktır.
6. **Kutu:** kart satırlarının birleşimi; başlık varsa o da katılır. Sonra üstü ≥ `kutu_altı − 0,005` olan
   her satır (sırayla, kutu büyüdükçe): üstü kutu altından 0,05'ten az aşağıda, solu > `kutu_sol − 0,03`,
   sağı < `kutu_sağ + 0,08` ise kutuya katılır (ör. kart gövdesinin hemen altındaki `GOAL $100 / $5,000` hedef satırı).
7. **Satır boyu** = kart satırlarının yüksekliklerinin ortancası (`[n/2]`; başlık hariç).
8. **Cümle metinleri:** satırlar boşlukla birleşir; her `"- "` dizisi `"-"` olur (satır sonu tireli
   sözcük birleşik kalır: `burned-` + `out` → `burned-out`); sonra baştaki **simge kırıntıları** silinir:
   metnin başında bir ya da daha çok "tek karakter `i`, `I`, `•`, `●`, `◆`, `△`, `▲`, ya da içinde rakam
   geçen boşluksuz parça, ya da `ml`" parçası boşluklarla ayrılmış duruyor ve ardından boşluk + ASCII
   büyük harf geliyorsa bu baş silinir (`i Use the index` → `Use the index`; `4 ml △ Make…` → `Make…`).
9. **Başlık metni:** sonunda bir ya da daha çok "boşluk + 1–3 tane ASCII harf ve boşluk olmayan karakter"
   grubu varsa silinir (`CATCH A BIGGER FISH •` → `CATCH A BIGGER FISH`). Başlık yoksa boş.
10. Sonuç: başlık, cümleler, kutu, satır boyu.

| Okuma | Başlık / cümleler |
|---|---|
| `BUY FLOWERS` / `Lucia will appreciate this` / `Have some flowers delivered to the` / `house for Lucia.` | `BUY FLOWERS` / `Lucia will appreciate this`, `Have some flowers delivered to the house for Lucia.` (Mac örneği; aynı kural) |
| ek A `gta6-harita-buckme` | `DEPOSIT CASH INTO BUCKME` / 2 cümle: ilki `Use the index` ile başlar, `nearby ATMs` ile biter; sonuncusu `checking account at an ATM` içerir; kutunun altı > 0,58 |
| ek A `gta6-harita-balik` | `CATCH A BIGGER FISH` / tek cümle (`.lines.txt`'deki görev cümlesi, `0.9 kg.` ile biter) |
| `RECENTER (0,85 0,85 0,93 0,87)`, `SET DESTINATION (0,85 0,88 0,95 0,90)`, `PELICAN INN (0,60 0,40 0,72 0,425)`, `A quiet beach hotel with small (0,60 0,44 0,78 0,46)`, `◆ rooms and a sea view. Clean and cheap. (0,59 0,465 0,80 0,485)` | cümleler birlikte `rooms and a sea view. Clean and cheap.` içerir, `◆` içermez |

### 8.4 Kartın çerçevesi (görüntüden)
Kart koyu, harita açık zeminlidir. Kare 640 × 360 örnekleyiciyle (§3.6) okunur; **koyu** = renk var ve
parlaklık (tam bölüm) < **130**.
- Satırlar: `y` = yazı kutusu üstü + 0,01'den, alttan küçük kaldıkça 0,02 adım. Sütunlar: `x` = sol + 0,01'den,
  sağdan küçük kaldıkça 0,03 adım. Biri boşsa çerçeve yok.
- **Kenar yürüyüşü** (başlangıç, adım, sınır, sayaç, toplam): konum = başlangıç; `|konum − başlangıç| < sınır`
  oldukça: bir adım ötede sayaç × 2 ≥ toplam ise bir adım ilerle. Değilse 2, 3, 4 adım ötesine bak (ilk
  tutan); hiçbiri tutmazsa ya da tutan sınırı aşıyorsa dur; tutarsa o kadar adım atla (ince açık rota şeridi).
  - Sol: x yönünde −0,003, sınır 0,04, sayaç = o x'te koyu satır sayısı.
  - Sağ: +0,003, sınır 0,09, aynı sayaç.
  - Alt: y yönünde +0,004, sınır 0,08, sayaç = o y'de koyu sütun sayısı.
  - Üst: −0,004, sınır 0,06.
- **Sınıra dayandıysa** (`|bulunan − başlangıç| ≥ sınır − 0,004`; gece haritası da koyu) o yanda yazı kutusu
  paylı kullanılır: sol −0,015, sağ +0,02, alt +0,02, üst −0,02.
- Çerçevenin genişliği yazı kutusununkinden büyük değilse çerçeve yok.

Örnek: 640×360 görüntü; kart x 0,60–0,90, y 0,30–0,61 koyu (30), geri kalan ve y 0,570–0,578 arası şerit
açık (200) (nokta ortası `(x+0,5)/640` ile ölçülür). Yazı kutusu `(0,65 0,35 0,85 0,55)` → çerçevenin altı > 0,6.

---

## 9. Harita okuyucusu

### 9.1 Zamanlama ve okuma
- "Kare ver": son turun başlangıcından bu yana < **2 000 ms** ise bir şey yapılmaz; değilse tur anı şimdi olur
  (okuma sürse bile). Okuma sürüyorsa (meşgul) bir şey yapılmaz. Değilse arka planda okunur; hata olursa
  günlüğe harita okumasının başarısız olduğu (hata türüyle).
- Okuma: karenin `üst 0,03 – alt 0,95`, `sol 0 – sağ 1` bölgesi kesilir (sekme şeridi ve alt kenar hariç);
  genişlik ya da yükseklik **2 600**'ü aştıkça yarıya küçültülür (2×2 noktanın ortalaması, `(toplam + 2) / 4`;
  4K yakalama kartı). Harita tanıyıcısıyla **tek geçiş, derin değil** okunur; OCR çöp süzgecinden geçer
  (okuma hattı tarifindeki süzgeç); satırlar bölgeye yerleştirilir.

### 9.2 Tur
1. Okuma oyun tanıyıcısına verilir (§2).
2. Harita ekranı değilse: **kaçırma** sayılır (§9.2.1); biter.
3. Harita ekranıysa: "harita açık" süresi = şimdi + **5 000 ms**; son kare saklanır (çerçeve için).
4. Kart bulunursa gösterme (§9.3) **beklenmeden** başlatılır (çeviri okumayı bekletmez; harita okunmaya devam
   eder). Kart gösterme kurallarının ilk dördünden (§9.3 1–4) geçiyorsa kaçırma sayacı sıfırlanır ve kart
   gösteriliyorsa kutusunun izi bu kareden tazelenir. Kart yoksa **kaçırma** sayılır (§9.2.1).

### 9.2.1 Kartın kalkması (gecikmeli, canlı denemeden)
Tek bir kaçırılan okuma kartı TV'den silmez (kanıt: GTA 6 harita kartı ekrandayken okuma bir kez kaçırdı,
kart 8 sn sonra "kalktı" sayıldı).
- Kart yerleştirilince (§9.3 12) kart kutusunun **izi** saklanır: son karenin kart kutusu (0–1'e kırpılmış)
  bölgesi kesilip bölge izi alınır (`RegionSignature`, 64 × 12 gri örnek). Kart yeniden okundukça iz tazelenir.
- **Kaçırma:** örtü yoksa yalnız anahtar unutulur. Örtü varsa sayaç bir artar, ilk kaçırmanın anı tutulur.
  Kart ancak üçü birden doğruysa kalkar (örtü temizlenir, anahtar unutulur, günlüğe kartın kalktığı):
  1. art arda en az **3** kaçırma,
  2. ilk kaçırmadan beri en az **4 000 ms**,
  3. kart kutusunun bu karedeki izi saklanandan **belirgin** farklı: örneklerin en az **%10**'u
     **16**'dan çok değişmiş (tek tük kıpırtı sayılmaz). Kare yoksa ya da iz alınamıyorsa "farklı" sayılır.
- Aksi hâlde kart TV'de kalır ve §1.3'teki 60 sn yenileme sürer (TV süresi 120 sn).
- Kart geri okunursa sayaç sıfırlanır; anahtar unutulmadığı için yeniden çeviri istenmez. Kart kalktıktan
  sonra yeniden okunursa çeviri hafızadan gelir.
- Sıfırlama ve örtü temizliği sayacı ve izi de siler.
- Telefon okuyucusunun paneli bu kurala girmez (kendi takibi ve 1 200 ms görülmeme kuralı var, §5.6);
  Windows'ta ayrı bir "mesaj kartı" öğesi yoktur.

- **Harita açık mı** = şimdi < harita açık süresi.
- **Yakında açıktı mı (ek süre)** = şimdi < harita açık süresi + ek süre, **ya da** kart örtüsü ekranda.
  Telefon okuyucusu ek süre **8 000 ms** ile sorar.
- **Sıfırla:** oturum artar; örtü, anahtar, bekleyen kart, harita açık süresi silinir; örtü vardıysa "boş"
  bildirilir. Hafıza, "çeviri sürüyor" bayrağı ve gösterilen kart bilgisi silinmez.

### 9.3 Gösterme kuralları
`tümü` = başlık + cümleler, boşlukla.
1. `tümü`'nde `ğ ı ş Ğ İ Ş` harflerinden biri varsa ya da cümle yoksa gösterilmez (PS5'in kendi Türkçe bildirimi).
2. Başlık boş ve `tümü` < **6** sözcükse gösterilmez (kartın kırığı: `Pick up the of`).
3. Başlık boş, kutu solu > 0,6 ve üstü < 0,32 → PS5'in sağ üst bildirimi, gösterilmez.
4. Kutu üstü < 0,1 → sekme şeridi, gösterilmez.
5. `tam_metin` = `tümü`'nün sadeleştirilmişi. **Kart anahtarı** = `tam_metin@⌊kutu_üst × 50⌋`.
6. Kilit altında:
   - **Yarım okuma:** başlık boş değil, sadeleştirilmiş başlık gösterilen kartın başlığıyla aynı, gösterilen
     tam metin bu tam metinle başlıyor ve ondan farklı → gösterilmez (ekrandaki tam okumanın yerine geçmez).
   - Anahtar son anahtarla aynıysa gösterilmez. Değilse son anahtar = bu anahtar; oturum alınır.
7. **Aynı kart** = başlık boş değil, sadeleştirilmiş başlık gösterilenle aynı ve kutu üstü gösterilenin
   üstünden 0,04'ten yakın. Aynı kart değilse eski Türkçe hemen kalkar (anahtar korunur). Aynı kartsa
   (`0.26 ml` / `0.26 mi` gibi biraz farklı okuma) eski Türkçe yenisi gelene kadar kalır.
8. Kilit altında: hafızada bu anahtar varsa hemen yerleştirilir (harita açık mı bakılmaz). Yoksa ve bir
   çeviri sürüyorsa bu kart **bekleyen** olur (yalnız en sonuncusu) ve çıkılır. Yoksa "çeviri sürüyor"
   açılır, bekleyen silinir.
9. **Çeviri:** parçalar = başlık varsa başlığın "Baş Harfleri Büyük" hâli (küçük harfe çevrilip kültürden
   bağımsız sözcük başları büyütülür: `DEPOSIT CASH INTO BUCKME` → `Deposit Cash Into Buckme`) + cümleler.
   - Her parça için depodan birebir çeviri (havuz/paket).
   - Toplu havuz sorgusu bağlıysa ve hazırı olmayan varsa onlar **tek istekte** sorulur (bağlam yok); hata →
     boş; dönen boş olmayanlar alınır; yedek çevirmen bağlıysa kalanlar onunla.
   - Kalanların **hepsi aynı anda** çevrilir (sınır yok); hata → boş.
   - Her sonuç: simge ve varlık temizliği (§6.3, tekrar temizliği **yok**), kırpma; boşsa atlanır. İlk parça
     başlıksa büyük harfe çevrilir — hedef `tr` ise **Türkçe kurallarıyla** (`i` → `İ`), değilse kültürden
     bağımsız. Diğerleri: varlıklar çözülür ve **terim düzeltmesi** (aşağıda) yapılır. Satırlara bölünmez
     (TV böler).
   - Günlük: harita kartı çevirisinin süresi (ms) ve parantez içinde hazırdan ya da havuzdan gelen parça sayısı / parça sayısı.
   - Her durumda "çeviri sürüyor" kapanır.
10. Kilit altında (oturum değiştiyse çıkılır): satır varsa hafızaya yazılır (anahtar → satırlar); hafıza
    **200**'ü aşarsa silinir. Bekleyen kart varsa alınır, silinir, son anahtar boşaltılır ve **bekleyen**
    gösterilir (bu sonuç gösterilmez); çıkılır.
11. Kilit altında: son anahtar artık bu kartınki değilse ya da satır yoksa çıkılır. Harita kapandıysa
    (şimdi ≥ harita açık süresi) son anahtar boşaltılır, gösterilmez (yeniden açılınca hafızadan gelir).
12. **Yerleştir:** son kareden çerçeve bulunur (§8.4; kare yoksa çerçevesiz), yerleşim (§9.4). Kilit altında
    son anahtar hâlâ buysa: örtü = bu tek öğe, gösterilen kart = (sadeleştirilmiş başlık, kutu üstü),
    gösterilen tam metin. Günlüğe kart (başlık ya da ilk cümle kısaltması → ilk satır kısaltması);
    "örtü değişti".

Kenar durumu (eski davranış): başlığın çevirisi boş gelirse atlanır; o zaman ilk satır bir cümle olur ve
yerleşimdeki mekân kuralı (§9.4) onu başlıkla değiştirebilir. Bunu koruman gerekmez ama bil.

**Terim düzeltmesi** (sırayla, büyük/küçük harf duyarlı, her geçtiği yer): makine çevirisinin GTA 6 kartlarında
sık yanlış seçtiği birkaç Türkçe sözcüğün düzeltmesi. Tablo kodda durur (`apps/windows/src/Nino.Core/Phone/MapCardLayout.cs`):
dört grup, her biri yanlış biçimin büyük harfli / baş harfi büyük / küçük harfli (ya da tekil / çoğul / iyelikli)
biçimlerini doğrusuyla değiştirir; uzun biçim kısa biçimden önce denenir (çoğul ekli sözcük tekilden önce). Gruplar:
"depo" anlamına gelen sözcüğün yanlış çevirisi, banknot yerine "fatura", uyuşturucu yerine teknik terim, balık türü
adının sözcük sözcük çevirisi (İngilizce tür adı kalır).

Örnek: düzeltme tablosundaki çoğul yanlış biçimi içeren bir cümlede yalnız o sözcük değişir, cümlenin geri kalanı
aynı kalır.

**Mekân adı** (başlık çevrilmez, İngilizcesi kalır):
- Açıklamanın (cümleler boşlukla) küçük hâlinin **ilk 4 sözcüğü**, başına bir boşluk eklenerek, şu
  dizgelerden birini içeriyor: `distributor`, `shop`, `store`, `dive bar`, ` bar` (baştaki boşlukla),
  `restaurant`, `dealer`, `club`, `diner`, `garage`, `convenience`, `wholesaler`, `boutique`, `salon`,
  `motel`, `hotel`, `bodega`.
- Ya da başlığın (büyük hâli) sözcüklerinden biri: `CUSTOMS AUTO SHOP BAR CLUB MOTORS GARAGE SPEEDWAY DINER
  CAFE GRILL MOTEL HOTEL STORE MART LOUNGE SALOON TACKLE ANCHOR MARINA AMMU-NATION BARBER TATTOO PAWN`.
- Ya da başlık `THE ` ile başlıyor ve ≤ 4 sözcük.

| Başlık / açıklama | Mekân mı |
|---|---|
| `HARBOR CUSTOMS` | evet |
| `MAMA ROSA'S KITCHEN` / `A dive bar by the docks.` | evet |
| `JASON'S MAILBOX` | hayır |
| `REEL DEAL` / `Bait shop and boat repairs.` | evet |
| `NEW IN TOWN` / `Grab a coffee at the diner on the corner of Main Street.` | hayır |
| `CHECK ON CAL` / `See how Cal is doing at the hotel.` | hayır |
| `RENT IS DUE` / `Pay Andy for the hotel room before Friday.` | hayır |

### 9.4 Yerleşim
1. Satırlara bir kez daha varlık çözümü ve terim düzeltmesi uygulanır. Başlık varsa, satır varsa ve başlık
   mekân adıysa ilk satır **başlığın İngilizcesi** olur.
2. Satır boyu `min(max(kart_satır_boyu, 0,024), 0,034) × 0,9`.
3. Yazı alanı = kart kutusu x'te ±0,015, y'de ±0,02. Çerçeve = bulunan çerçeve **∪** yazı alanı (bulunmadıysa
   yazı alanı). (İşaretçi görünümünde bulunan çerçeve kartın bir parçası çıkıyordu.)
4. Harf genişliği `boy × 0,42 × 9/16` (dar yazı tipi). En uzun = en uzun satırın harf sayısı (satır yoksa 10).
   Genişlik `min(çerçeve_genişliği, en_uzun × harf + 0,035)`.
5. Satır sayısı: **ilk** satır 1 (başlık olsun olmasın); diğerleri `max(1, ⌈uzunluk × harf / (genişlik − 0,03)⌉)`.
   Yükseklik `boy × satır × 1,32 + 0,022`.
6. `alttaki_yer = 0,97 − (çerçeve_alt + 0,012)`, `üstteki_yer = çerçeve_üst − 0,012 − 0,02`. Üst varsayılanı
   `çerçeve_alt + 0,012`. Yükseklik alttaki yerden büyükse: üstteki yere sığıyorsa ya da üstteki yer
   daha büyükse üste konur (sığmıyorsa `boy ×= (üstteki − 0,022) / (yükseklik − 0,022)`, yükseklik = üstteki);
   üst = `çerçeve_üst − 0,012 − yükseklik`. Değilse altta kalır: `boy ×= (alttaki − 0,022)/(yükseklik − 0,022)`,
   yükseklik = alttaki.
7. Sol `max(çerçeve_sol, kart_sol − 0,014)`.
8. Öğe: kaynak = başlık + cümleler (boşlukla; başlık boşsa başta bir boşluk kalır), çeviri = satırlar `\n`
   ile, kutu `(sol, üst, sol + genişlik, üst + yükseklik)`, satır boyu = boy, **"kart"** bayrağı (TV oyunun
   kartı gibi çizer). Birden çok satır olduğu için TV'ye "paragraflar" olarak gider.

Örnekler (ek A `buckme` kartı, satırlar `BUCKME'YE NAKİT YATIR`, `Dizinden en yakın ATM'yi bul`,
`Nakit yatır`):
- Çerçevesiz: kart bayrağı var; üst > kart kutusunun altı; çeviri 3 satır; sol ≤ kart solu.
- Çerçeve kartın küçük bir parçası `(kart_sol+0,02, kart_üst+0,01, kart_sol+0,08, kart_üst+0,05)`: yine
  üst > kart altı, sol ≤ kart solu.

### 9.5 Okuyucu örnekleri (sahte çevirmen metnin başına `TR: ` ekler)
- Boş 64×36 kare, ek A `buckme` okuması: önce harita kapalı; turdan sonra açık; tek öğe, kart bayrağı,
  çeviri `TR: ` + başlığın Türkçe kurallarıyla büyük harfe çevrilmiş hâliyle başlar (başlık `Deposit Cash Into Buckme`
  olarak gitti, `TR: ` önekiyle döndü, sonra büyütüldü; `i` → `İ`), kartın cümlelerinin `TR: ` önekli çevirilerini içerir.
  Ardından boş okuma → örtü kalkar, son bildirim boş.
- Toplu sorgu yalnız ilk parçaya `BuckMe'ye nakit yatır` döndürür, yedek çevirmen `Cihaz ` + metin döndürür:
  tek toplu istek, 3 parça, ilki `Deposit Cash Into Buckme`; yedeğe giden parçalar = cümleler; kendi
  çevirmeni hiç çağrılmaz; çeviri `BUCKME'YE NAKİT YATIR` ile başlar, `Cihaz ` içerir; günlükte harita kartı
  çevirisinin süresini ve 3 parçadan 1'inin havuzdan geldiğini söyleyen satır.
- `RECENTER`, `SET DESTINATION` ve tek satır `Pick up the of (0,50 0,50 0,72 0,52)` → çevirmen çağrılmaz,
  örtü yok. Aynı satır `Pick up the bait before the shop closes.` → tek öğe.

---

## 10. TV'ye giden örtüler

Telefon okuyucusunun öğeleri ve harita okuyucusunun öğesi **tek listede** (önce telefon, sonra harita)
TV'ye `screen` olayıyla gider; her olay öncekinin yerine geçer. Liste değişince (bir okuyucu "örtü değişti"
dediğinde) yeniden gönderilir. Liste boşsa ve önceden gösteriliyordu ise `screen-clear` olayı (boş nesne)
gider. Olay biçimi `tv-baglanti.md` §4.6–4.7’deki SSE olayıdır (`event: <ad>`, `data: <JSON>`, boş satır).

`screen` verisi: `{"duration": 120000, "items": [...], "overlay": true}`. `overlay` = TV o an görünen altyazıyı
silmez; ayrıca bu olay bilgisayardaki altyazı penceresine **gitmez** (orada telefonun yanı yoktur).
Anahtarlar her nesnede **alfabetik sıradadır** (test sırayı bekler: `"alpha":0.6,"backdrop":true,` ve
`"alpha":0.95,"angle":5.7,`). Türkçe harfler kaçışsız yazılır.

| Alan | Ne | Biçim / yuvarlama | Windows'ta kim koyar |
|---|---|---|---|
| `box` | `{"bottom","left","right","top"}` | 0–1'e kırpılır, 4 basamak, sondaki sıfırlar atılır (`0.8`) | hepsi |
| `line` | satır boyu | aynı | hepsi |
| `text` | Türkçe (zeminde başlık ya da boş) | dizge | hepsi |
| `paragraphs` | çeviride `\n` var | yalnız `true` ise yazılır | harita kartı |
| `fill` | zemin rengi `#rrggbb` | varsa | balonlar, zemin, uygulama balonları |
| `ink` | yazı rengi | varsa | balonlar, uygulama balonları |
| `alpha` | zemin saydamlığı | 0–1'e kırpılır, 2 basamak | zemin 0,6; balonlar 0,95 |
| `angle` | dönme açısı (derece) | açının mutlak değeri ≥ 0,3 ise, 1 basamak | biçim var ama canlı yolda hep yok (balonlarda açı silinir) |
| `side` | yan balon (TV daha yuvarlak, gölgeli çizer) | `true` ise | balonlar, uygulama balonları |
| `backdrop` | yazısız zemin paneli | `true` ise | sohbet zemini |
| `card` | harita kartı (koyu zemin, üstte vurgu çizgisi, ilk satır başlık) | `true` ise | harita kartı |
| `plain` | kutusuz gölgeli yazı | `true` ise | bu bölümde kimse |
| `italic` | eğik yazı | `true` ise | bu bölümde kimse |
| `frost` | buzlu kart (Mac mesaj kartı) | — | Windows'ta **yok** (öğede de, yazıcıda da) |

Örnek (test): zemin `("" → "Lucia", kutu 0,3 0,2 0,57 0,85, satır 0,022, fill #f5f5f6, alpha 0,6, backdrop)`,
balon `("Did you fix the engine?" → "Motoru tamir ettin mi?", 0,31 0,5 0,45 0,53, 0,02, fill #acccfe, ink #2c2c2e, alpha 0,95,
side, angle 5,71)`, kart `("BUY FLOWERS" → "ÇİÇEK AL", 0,55 0,6 0,8 0,7, 0,02, card)`, süre 120 000, overlay.
Veride `"overlay":true`, `"alpha":0.6,"backdrop":true,`, `"fill":"#f5f5f6"`, `"alpha":0.95,"angle":5.7,`,
`"ink":"#2c2c2e"`, `"side":true`, `"card":true` geçer. Ardından `screen-clear` gelir.
Overlay işaretli gönderim yerel altyazı olayı üretmez; işaretsiz gönderim bir tane üretir.

Gönderim sonrası "gösteriliyor" bayrağı ve gönderim anı tutulur (§1.3'teki 60 sn yenileme için).

---

## 11. Uygulama denetleyicisine bağlantılar

### 11.1 Okuyuculara verilenler
- **Depodan birebir çeviri:** çeviri deposunda (havuz + paket) metnin birebir eşleşmesi; yoksa yok.
- **Toplu havuz sorgusu** (telefon: satırlar + bağlam; harita: parçalar, bağlam boş): ortak havuz ayarı açıksa
  ya da oyun havuz öncelikliyse çeviri deposunun toplu çevirisine sorulur (oyun = havuz öncelikliyse
  §1.1'deki "havuza sorulacak oyun", değilse olağan havuz oyunu). Havuz kullanılamıyorsa hepsi boş döner.
- **Yedek çevirmen** (telefon ve harita **aynı** nesneyi paylaşır; motor iki kez kurulmasın): havuz öncelikli
  oyunda yalnız ücretsiz cihaz içi çevirmen (kullanıcının anahtarı harcanmaz), değilse kullanıcının motoru; ikisi
  de hedef yazı sistemi bekçisiyle sarılı (hedef dilin yazısında olmayan sonucu reddeder). Havuza ikinci kez sorulmaz.
- **Okuyucunun kendi çevirmeni:** olağan çevirmen; toplu sorgu bağlı olduğu için pratikte kullanılmaz.
- Telefon: sözlük açık = hedef `tr`; duraklatma = harita "yakında açıktı" (8 000 ms); telefon ekranı görülünce
  oyun = `GTA 6` (§2); örtü değişince örtüleri gönder (§10); günlük.
- Harita: hedef dil; her okumada oyun tanıma (§2); örtü değişince gönder; günlük.
- Depodan birebir çeviri ve sözlük ayarı okuyucular her güncellendiğinde yeniden verilir.

### 11.2 Okuma hattına verilenler
"Telefon aransın mı" = telefon oyunu; "son telefon mesajları" = telefon okuyucusunun son mesajları (okuyucu
yoksa boş); "telefon yazısı görüldü" = telefon okuyucusunun takipçisine benimset; "harita açık mı" = harita
okuyucusu açık diyor mu; "görev şeridi çizgisi" = yok (§7.4).

### 11.3 Günlük satırları (anlam)
- telefon: okunamadı (hata türü); sohbet değişti (eski ve yeni başlık) ve eski panel kaldırıldı; N yazı (kaynak →
  çeviri) · uygulama · not.
- Notlar: hepsinin hazır olduğu; N'sinin hazırdan gösterildiği ve M yeni mesajın ikinci okumayı beklediği (ara
  gösterim); N hazır ve M beklenen; çevirinin süresi (ms) ve kaçının havuzdan, kaçının tek tek çevrildiği.
- harita: okunamadı / kart çevrilemedi (hata türü); kart çevirisinin süresi (ms) ve havuzdan gelen parça oranı (a/b);
  kartın kaynağı → çevirisi.
- oyunun ekrandaki yazılardan tanındığı (adıyla).

Bu metinler yalnız günlüğe gider; kullanıcıya gösterilmez.

---

## 12. Windows'a özgü kısımlar

- **Yazı tanıma:** Windows'un yerleşik OCR motoru (Windows.Media.Ocr), kaynak dilin dil etiketiyle; o dil
  yüklü değilse kullanıcı profili dilleriyle; ikisi de yoksa okuyucu kurulamaz (§1.2). Telefon ve harita için
  her biri **ayrı** motor örneği, **tek geçiş** kipinde: kare olduğu gibi okunur (ön işleme, otomatik seviye,
  beyaz yazı süzgeci, paket/sözlük adayları, büyütme denemesi yok). Altyazı okuyucusunun çok adaylı kipleri
  burada kullanılmaz.
- **Boyut sınırı:** Windows OCR 2 600 pikselden büyük görüntüyü okumaz. Telefon kesiti yalnız iki katı bu
  sınıra sığıyorsa büyütülür; harita bölgesi sınıra inene kadar yarıya küçültülür.
- **Saat:** sistemin tekdüze ms sayacı (açılıştan beri).
- **İş parçacıkları:** okumalar iş parçacığı havuzunda; "kare ver" kare iş parçacığından çağrılır ve hemen
  döner; okuyucu durumu kilitle korunur; "örtü değişti" bildirimi **kilit dışında** çağrılır (dinleyici başka
  kilit alıp öğeleri okur; kilit sırası ters dönmesin). Okuyucuların kurulması arayüz iş parçacığında.
  Meşgul bayrakları atomik karşılaştır-değiştir ile.
- **Kare:** yakalama kartından ya da yayından gelen BGRA kare; renk kanallarını karıştırmamak önemli (test:
  kararmış karede mavi balon mavi okunmalı).
- **Kültür:** Türkçe Windows'ta küçük/büyük harf çevirileri kültürden bağımsız yapılmalı (`I` → `i`). Yalnız
  harita başlığının Türkçe büyük harfi Türkçe kültürle (`tr-TR`).
- TV'ye gönderim yerel HTTP sunucusunun SSE akışıyla (`tv-baglanti.md`).

---

## 13. Gerçek karelerle sınamalar

Görüntüler `core/Tests/NinoAppCoreTests/Fixtures/` altında JPG'dir (Mac'in deneme verisi). Eski testler bunları
macOS'ta `sips` ile BMP'ye çevirip okuyordu; JPG çözülemiyorsa (başka sistem, dosya yok) sınama **atlanır**.
Yeni testler aynı kareleri veri olarak kopyalayabilir (kod değildir). Her beklenti eski Windows bulucusuyla
geçiyordu:

| Kare | Beklenti |
|---|---|
| `gta6-telefon-donnie`, `-kenton`, `-shirley`, `-liste` | telefon bulunur; sol 0,59 (±0,02), sağ 0,79 (±0,02), üst 0,20 (±0,03), alt 0,82 (±0,03) |
| `gta6-telefon-egik-alt` | bulunur; üst 0,58 (±0,03), alt > 0,96, orta 0,52 (±0,03) |
| `gta6-telefon-koyu-rydeme` | bulunur (koyu tema), orta 0,69 (±0,03) |
| `gta6-menu-kapusonlu` | telefon **yok** (koyu kıyafet) |
| `gta6-telefon-koyu-altpencere` | doğrudan bulunamaz; ama takipçi önce `koyu-rydeme`'yi bulduysa aynı kutuyu döndürür; arada `menu-kapusonlu` gelirse yok, ondan sonra `koyu-altpencere` de yok |
| `gta6-telefon-karanlik` | bulunur; sol 0,36 (±0,03), sağ 0,60 (±0,03); aydınlatılmış örnekleyicide (0,44, 0,46) noktası mavi: B > R + 15 ve B > 150 |
| `gta6-telefon-koyu-rydeme` | aydınlatılmış örnekleyici ekranın ortasında düz örnekleyiciyle aynı R değerini verir (aydınlatılmaz) |
| `gta6-telefon-lucia-foto` | bulunur, orta 0,47 (±0,04); ek A okumasıyla sohbet, başlık `Lucia` |
| `gta6-telefon-brian-parlama`, `gta6-telefon-egik-mavi` | bulunur; ek A okumalarıyla §5.3.7 ve §6.7 h'deki beklentiler |
| `gta6-altyazi-beyaz`, `gta6-telefon-yakin-alt` | §7.3 açık zeminde koyu yazı beklentileri (bölge 0,66–0,97 / 0,14–0,86 kesilip örneklenir; satırlar bölgeye göre yerleştirilir; 4'ten az harfli satırlar alınmaz) |

Diğer sentetik bulucu sınamaları (240×135 harita; "beyaz değil" = koyu, aksi belirtilmedikçe):
- Telefon x 139–190, y 27–115 beyaz → kutu sol 139/240, sağ 191/240, üst 27/135, alt 116/135 (±0,01).
- Aynı telefonun içinde y 40–75 × x 144–185 (fotoğraf) ve y 95–108 × x 160–186 (balon) beyaz değil → yine bulunur.
- Eğik: y 24–105 arası, sol `99 − yuvarla((y − 24) × 0,16)`, genişlik 45 beyaz, her yer koyu → bulunur;
  `eğim × 240/135 ≈ −0,16` (±0,03), üst 24/135, alt 106/135 (±0,01), üstte orta `(99+23)/240`, altta
  `(86+23)/240` (±0,012).
- Bulunmaz: aynı telefon ama hiçbir nokta koyu değil; x 12–65 y 7–88 (kenardaki duvar); x 100–150 y 0–68
  (üst kenara dayanan kapı); hiç beyaz yok; y < 70 hepsi beyaz (gökyüzü); x 150–220 y 110–134 (yatay kutu);
  y 20–120 ve x `100 + (y×7 mod 23)` ile `150 + (y×11 mod 29)` arası (kenarları oynayan leke).

Telefon okuyucusu sınamaları (sahte çevirmen `TR: ` ekler; telefon `Kenton` = kutu `(0,58 0,197 0,793 0,854)`,
eğim 0, genişlik 0,213; okuma `Kenton (0,66 0,22 0,70 0,24)`, `Left the keys under yuh mat (0,60 0,372
0,752 0,394)`, `bro. Good luck out there! (0,60 0,398 0,70 0,42)`, `Sure thing, see ya. (0,667 0,689 0,766 0,712)`;
kare boş 960×540; okuma doğrudan işlenir):
1. İlk okuma → bildirim yok. İkinci → tek bildirim: zemin (çevirisi `Kenton`) + `TR: Left the keys under yuh
   mat bro. Good luck out there!`, `TR: Sure thing, see ya.`; balonlar yan balon ve telefonun sol yanında; son
   mesajlarda `Sure thing, see ya.`. Üçüncü aynı okuma → yeni bildirim yok; çevirmen 2 kez çağrıldı. Sıfırla → öğe
   yok, son mesaj yok.
2. Toplu sorgu `Havuz ` + metin döndürür, yedek `Cihaz ` + metin: ilk okuma yok; ikincide tek toplu istek,
   satırlar iki mesaj, bağlam boş; kendi çevirmeni çağrılmaz; öğeler `Havuz …`. Yeni okuyucu, depodan birebir çeviri
   `Bilinen 1` / `Bilinen 2` → **ilk okumada** öğeler `Bilinen 1`, `Bilinen 2`; toplu istek sayısı değişmez.
3. Depodan birebir çeviri yalnız ilk mesaja `Bilinen`, toplu sorgu hep boş, yedek `Cihaz `: ilk okumada bir bildirim
   (`Bilinen`); ikincide ikinci bildirim (`Bilinen` ve `Cihaz ` önekli ikinci mesaj); kendi çevirmeni çağrılmaz.
4. Toplu sorgu boş, yedek `Cihaz `: iki okuma → (toplu 1, yedek 2), tek bildirim. Sıfırla, oturum 1 ile yeniden
   oku → ilk okumada `Cihaz …` öğeleri, yeni çeviri yok. **Yeni** okuyucu (hafıza boş) iki okuma → (toplu 2, yedek 4).
5. İkinci okumada mesajlar 0,03 aşağı kaymış → yine gösterilir (onay metinle; çevirmen 2).
6. Gösterilen panelden sonra son mesaj sonuna kırıntı eklenmiş (`Sure thing, see ya.' U`, 0,01 kaymış) ve
   noktalaması düşmüş (`Sure thing see ya`, 0,005) okunur → yeni bildirim yok, çevirmen 2, öğeler duruyor.
7. Panelden sonra ek satır `Bring the big net. (0,60 0,76 0,72 0,78)`: ilk okumada bildirim yok; ikincide yeni
   bildirim, `TR: Bring the big net.` içerir.
8. Panelden sonra `Linda (0,665 0,22 0,70 0,24)` + `Rent is late again. (0,60 0,40 0,75 0,42)` → öğeler
   hemen boş, son bildirim boş.
9. Grup sohbeti `Boat Crew (0,655 0,22 0,715 0,24)`, `Cal (0,60 0,30 0,62 0,315)`, `Who took my hat? (0,60 0,35
   0,70 0,37)`, `It's in the cabin, next (0,667 0,50 0,766 0,52)`, `to the map. (0,667 0,525 0,72 0,545)` → toplu
   istekte `Cal` yok, `Who took my hat?` var.
10. §5.5 küçük harfli ilk mesaj; §5.3.4 sohbet listesi; §6.6 uygulama ekranı sözlükle.

---

## 14. Mac'ten farklar (Windows esas)

| Konu | Windows | Mac |
|---|---|---|
| Sınanan telefon adayı | 32 | 16 |
| Yalnız şekille (dikdörtgen bulucu) telefon | yok | var |
| Panel varken 100 ms'de bir telefon yeri takibi | yok (yalnız yerleşimde elde sallanma düzeltmesi) | var |
| Harita okuması | kendi tanıyıcısıyla karenin 0,03–0,95'i, 2 sn'de bir | köşe okumasının menü araması (0,6 sn) |
| Harita ekranı menü bayrağı | harita son görülmeden 5 sn (altyazı boş) | 5 sn |
| Haritadan sonra telefon duraklatması | 5 sn tutma + 8 sn, ya da kart ekrandayken | menü bayrağından 8 sn, ya da kart ekrandayken |
| Telefon varken altyazı tabanı | sabit 0,8 | `max(taban, 0,8)` |
| Görev şeridi çizgisi 0,935 | kapalı | açık |
| Mesaj kartı, köşe ipucu, köşedeki telefon kuralları | yok | var |
| "Köşeleri çevir" ayarı | yok | telefon için şart |
| Telefon hafızası | yalnız bellekte | `phone-memory-<dil>.json` |
| Balon açısı TV'ye | gönderilmez | gönderilebilir |
| `frost` alanı | yok | var (mesaj kartı) |
| Yarım okuma, onay, aynı mesajlar, sohbet değişti, kart kuralları | Mac ile aynı mantık | — |

---

## Ek A. Yazı tanıma okumaları (test verisi, aynen)

Her satır: `sol üst sağ alt<SEKME>metin`, kareye göre 0–1 (macOS Vision ile gerçek karelerden bir kez
okunmuş). Yeni testler bu dosyaları aynen kullanabilir (`<ad>.lines.txt`).

`gta6-altyazi-beyaz`
```
0.8342 0.6704 0.8594 0.6891	Will
0.6874 0.7045 0.8605 0.7617	Remember, you get your hands
0.6866 0.7315 0.8080 0.7751	on anything I might be
0.6850 0.7550 0.8565 0.8139	interested in you bring it to my
0.6832 0.7790 0.8259 0.8333	lockups. I'll cut you a little
0.6838 0.8035 0.8612 0.8707	finder's fee. Door code is 7700.
0.2295 0.8630 0.7705 0.9280	Yeah, okay. Just wait, you're gonna love it, we're gonna have fun.
```

`gta6-harita-balik`
```
0.0159 0.0409 0.1076 0.0753	ACTIVITIES
0.9244 0.1163 0.9826 0.1500	$500 •
0.0798 0.1208 0.2066 0.1520	Catch a Bigger Fish
0.9242 0.1536 0.9842 0.1852	$502 G
0.0509 0.1809 0.0959 0.2067	RACING
0.0855 0.2419 0.1616 0.2643	• Raceways
0.0509 0.2997 0.1642 0.3259	HUNTING & FISHING
0.0625 0.3592 0.1672 0.3880	* Fishing Spots
0.0508 0.4156 0.1134 0.4423	NIGHTLIFE
0.5756 0.4519 0.7137 0.4833	CATCH A BIGGER FISH
0.0610 0.4753 0.1192 0.5015	@ Clubs
0.2456 0.4780 0.2544 0.4961	>
0.4817 0.4877 0.5166 0.5185	(43)
0.5465 0.4987 0.8009 0.5271	Cal challenged you to catch a stoplight
0.4811 0.5245 0.5174 0.5504	1.53 km
0.5451 0.5370 0.7326 0.5633	parrotfish larger than 0.9 kg.
0.9055 0.7571 0.9622 0.7804	RECENTER
0.9651 0.7571 0.9797 0.7804	L3)
0.9171 0.8031 0.9797 0.8326	2D VIEW R3
0.8909 0.8465 0.9827 0.8847	ADD MARKER •
0.8706 0.8958 0.9797 0.9310	SET DESTINATION X
0.8938 0.9398 0.9827 0.9801	CLOSE MENU O
```

`gta6-harita-buckme`
```
0.0160 0.0388 0.0727 0.0749	STORY
0.9244 0.1189 0.9666 0.1499	$500
0.0768 0.1233 0.1557 0.1476	Earn Money
0.9244 0.1549 0.9681 0.1862	$502
0.0798 0.1762 0.2502 0.2102	Deposit Cash Into BuckMe
0.0814 0.2403 0.2064 0.2611	Save for the Future
0.0523 0.2992 0.1091 0.3236	OPTIONAL
0.0858 0.3592 0.2602 0.3798	• Recover Stashed Cocaine
0.5756 0.4083 0.7587 0.4393	DEPOSIT CASH INTO BUCKME
0.0594 0.4138 0.2255 0.4477	• • Find the Lost Drugs
0.2427 0.4186 0.2544 0.4419	>
0.0203 0.4289 0.0378 0.4574	P
0.5480 0.4625 0.7747 0.4884	i Use the index or BuckMe to find
0.5668 0.5010 0.6497 0.5300	nearby ATMs
0.5451 0.5426 0.7922 0.5713	Make a cash deposit into your BuckMe
0.5464 0.5783 0.7327 0.6082	checking account at an ATM.
0.9055 0.7569 0.9622 0.7805	RECENTER
0.4666 0.7933 0.4811 0.8165	11)
0.9171 0.8058 0.9797 0.8299	2D VIEW R3)
0.8910 0.8527 0.9797 0.8787	ADD MARKER •
0.8706 0.9018 0.9651 0.9251	SET DESTINATION
0.8939 0.9509 0.9637 0.9742	CLOSE MENU
```

`gta6-telefon-brian-parlama`
```
0.6728 0.2113 0.6991 0.2295	Brian
0.6123 0.2398 0.7220 0.2604	got some calls to make.
0.6167 0.3472 0.7531 0.3657	Shit went sideways with your
0.6167 0.3713 0.7510 0.3898	supplier. Might wanna talk to
0.6167 0.3935 0.7677 0.4139	that new broker. Still got one of
0.6156 0.4157 0.7656 0.4343	the drops stashed at the house
0.6155 0.4392 0.6532 0.4589	though.
0.6104 0.4935 0.7365 0.5139	Ah crap. Ok, I guess I need
0.6102 0.5147 0.7564 0.5399	another new broker. Drop that
0.6082 0.5384 0.7377 0.5629	last package at my lockup.
0.7363 0.6008 0.7711 0.6172	Will do
0.6090 0.6498 0.7607 0.6822	Remember, you get your hands
0.6091 0.6740 0.7160 0.7016	on anything I might be
0.6080 0.6987 0.7587 0.7287	interested in you bring it to my
0.6079 0.7216 0.7327 0.7511	lockups. I'll cut you a little
0.6089 0.7423 0.7652 0.7791	finder's fee. Door code is 7700.
```

`gta6-telefon-egik-mavi`
```
0.4853 0.1967 0.5117 0.2185	Brian
0.4240 0.2228 0.5302 0.2495	got some calls to make.
0.4196 0.3271 0.5502 0.3693	Shit went sideways with your
0.4175 0.3525 0.5460 0.3922	supplier. Might wanna talk to
0.4154 0.3770 0.5585 0.4163	that new broker. Still got one of
0.4133 0.4011 0.5544 0.4384	the drops stashed at the house
0.4111 0.4231 0.4473 0.4493	though.
0.4005 0.4772 0.5200 0.5195	Ah crap. Ok, I guess I need
0.3986 0.5018 0.5358 0.5458	another new broker. Drop that
0.3952 0.5242 0.5160 0.5678	last package at my lockup.
0.5094 0.6073 0.5416 0.6255	will do
0.3857 0.6387 0.5275 0.6902	Remember, you get your hands
0.3829 0.6623 0.4839 0.7043	on anything I might be
0.3805 0.6868 0.5215 0.7372	interested in you bring it to my
0.3775 0.7109 0.4954 0.7563	lockups. I'll cut you a little
0.3765 0.7307 0.5228 0.7885	finder's fee. Door code is 7700.
```

`gta6-telefon-lucia-foto`
```
0.4870 0.1958 0.5130 0.2153	Lucia
0.4347 0.4070 0.5579 0.4443	One man's trash is another
0.4318 0.4319 0.5007 0.4602	man's treasure
0.4011 0.4840 0.5080 0.5228	Are you high right now?
0.3959 0.5414 0.5228 0.5831	Honestly if they didn't let us
0.3936 0.5650 0.5290 0.6109	keep our phones, I don't know
0.3916 0.5875 0.5278 0.6357	how I'd get through this. Seen
0.3897 0.6105 0.4708 0.6459	this? Hahahahaha
0.4126 0.6695 0.4749 0.6994	@247Heaven
0.4696 0.7612 0.5302 0.7954	You slackin?
```

`gta6-telefon-yakin-alt`
```
0.3803 0.6812 0.5188 0.7340	You got my plane?! You better
0.3782 0.7066 0.5210 0.7570	be good to her! Brian wants me
0.3754 0.7296 0.4887 0.7761	to pick her up in the AM.
```
