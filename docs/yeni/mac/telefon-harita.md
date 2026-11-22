# Mac telefon paneli ve harita kartı: tarif

Bu belge, oyunun içindeki telefonun (GTA 6) ve harita ekranındaki görev kartının nasıl
tanındığını, okunduğunu, çevrildiğini ve TV'de nasıl gösterildiğini **davranış olarak**
anlatır. Kod yoktur. Koordinat, saat ve benzerlik kuralları `okuma-hatti.md` §0'daki gibidir.

Bu belgede **Mac uygulamasının** sayıları esastır. Çekirdekteki ortak kopya bazı yerlerde
farklıdır; farklar tek satırla not edilmiştir.

---

## 1. Ne zaman çalışır

### 1.1 Telefon oyunu mu
Telefon araması yalnız şu durumda yapılır:

- "Köşeleri çevir" ayarı açık, kaynak dil `en`.
- Oyun **havuz öncelikli** (bugün yalnız GTA 6).
  - Oyun kesin biliniyorsa (PS5, kullanıcı ya da ekran söyledi): o oyunun durumu.
    Bu değer "son oyun havuz öncelikliydi" olarak saklanır (sonraki açılış için).
  - Oyun yalnız altyazı paketinden tahmin edildiyse: oyun havuz öncelikli **ya da** çeviri
    dili havuz öncelikliyse (Türkçe) aranır. (GTA 6 satırları başka oyunların paketinde de
    eşleşip telefonu kapatıyordu.)
  - Oyun hiç bilinmiyorsa: son oturumdaki oyun havuz öncelikliyse ya da çeviri dili havuz
    öncelikliyse aranır.
- Altyazı hattı da aynı kuralla "telefon oyunu" bilgisini alır (§7).

### 1.2 Okuma aralığı
- Türkçe panel ekranda yokken **0,6 sn**'de bir, ekrandayken **1,0 sn**'de bir.
  (Ortak kopyada 1,5 sn.) Bir okuma sürerken yenisi başlamaz.
- **Duraklatma:** menü/harita bayrağı son **8 sn** içinde açıktıysa ya da harita kartı
  ekrandaysa telefon aranmaz; ekrandaki panel kalkar. (Haritanın aydınlık kısmı telefon
  sanılıyordu.) (Ortak kopyada yalnız bayrak açıkken.)
- Telefon okuması **yalnız işlemcide** yapılır (Neural Engine altyazıya kalsın).


### NinoCore'da eksik

- Oyun bilgisi, havuz önceliği ve "telefon oyunu" kararı yok.

---

## 2. Oyunu ekrandan tanıma

PS5 çalışan oyunu çoğu zaman söylemiyor. Ekranın büyük kısmının okumasında (köşe
okumasının menü araması, `okuma-hatti.md` §12.1) GTA 6'ya özgü yazı varsa oyun **GTA 6** olur:

- Harita ekranı (§9.1).
- Bir satırda hem `jason` hem `lucia` (sadeleştirilmiş, simge kırıntıları atılmış).
- Satırlar arasında `brief` ve `progress` ve (sözcüklerde `jason` ya da `lucia`, ya da
  satır olarak `map`).
- Satır olarak `whatup` (telefonun mesaj uygulaması).

Ayrıca telefonda sohbet ya da uygulama okunursa oyun GTA 6 sayılır.

- Ekrandan tanıma, PS5'in ya da kullanıcının söylediği oyunu **ezmez**. Aynı oyunsa bir şey
  yapmaz. Tanınınca görev çizgisi hemen yeniden hesaplanır.
- "GTA 6" adı "Grand Theft Auto VI" ile aynı anahtardır; oyun listesinde aramada ilk sıradadır.

| Okuma (satırlar) | Oyun |
|---|---|
| harita tuşları | GTA 6 |
| `JASON & LUCIA`, `MAP`, `BRIEF`, `PROGRESS` | GTA 6 |
| `MAP`, `BRIEF`, `PROGRESS` | GTA 6 |
| `Reminders`, `7 Notifications`, `WhatUp` | GTA 6 |
| `Options`, `Map`, `Progress`, `Quit Game` | yok |
| `Jason, wait for me!` | yok |


### NinoCore'da eksik

- Ekrandan oyun tanıma yok.

---

## 3. Telefonu karede bulma

Telefonun ekranı dikey, açık renkli, büyük bir dörtgendir; iki yanında koyu çerçeve vardır.
Yaya hâlde eğik tutulur: ekran bir **paralelkenardır** (aşağı indikçe sol kenar kayar).

**Bulunan ekran:** çevreleyen kutu, üst kenardaki sol x, **eğim** (bir kare yüksekliği aşağı
inince sol kenarın x kayması), ekran genişliği, "yalnız şekliyle bulundu" bayrağı.
- `y` yüksekliğinde sol kenar = `üst_sol + eğim × (y − kutu_üst)`; orta = sol + genişlik/2.
- Dönme açısı (derece, saat yönü artı) = `atan(−eğim × 16/9)`.

### 3.1 Açık ekran (ana yol)
Kare **240 × 135**'e küçültülür. Bir nokta için `düşük = min(R,G,B)`, `yayılma = max − min`.

- **Beyaz nokta:** düşük ≥ **118** ve yayılma ≤ **45**.
- **Koyu nokta (çerçeve):** düşük < **90**.

Sınırlar (kare oranı): genişlik **0,12–0,30**, ortası **0,30–0,80**, yükseklik **0,38–0,86**.

1. **Şeritler:** her satırda beyaz şeritler bulunur; aradaki en çok 3 noktalık beyaz olmayan
   boşluk şeridi bölmez (yazı çizgileri). Şeridin başında/sonunda, ardından en az 2 beyaz
   olmayan nokta gelen ≤ 2 noktalık parlak kırıntı atılır (gümüş çerçeve çizgisi).
   Uzunluğu genişlik sınırları içindeki şeritler tutulur.
2. **Oylama:** eğimler 0, ±0,02, ±0,04 … ±0,30 (nokta/satır). Her eğim için her şeridin
   `(başlangıç − eğim × satır)` kesişimi ve genişliği (ikişer nokta kovalarla) oy alır.
   Her eğimin en çok oy alan **3** adayı (en az **8** oy) listeye girer. Liste oya göre,
   eşitlikte eklenme sırasına göre (dik telefon önce) sıralanır. İlk **16** aday sırayla
   denenir; geçen ilk aday telefondur.
3. **Aday sınaması:**
   - Her satırda sol kenarı aday doğrusuna **3,5**, genişliği **4** noktadan yakın şerit uyar.
   - Uyan satırlar en çok **10** satırlık boşluklarla parçalara ayrılır. Birden çok parça
     varsa karenin üst/alt kenarına değen parçalar atılır (telefonun üstündeki pencere).
   - En az **8** satır kalmalı. Sol kenar ve genişlik ortancadır.
   - **Çerçeve:** satırların ≥ **%70**'inde ekranın hem solunda hem sağında 1–4 nokta
     içinde koyu nokta var; ya da satırların ≥ **%85**'inde iki yanında 1–4 nokta içinde
     beyaz olmayan nokta var **ve** ≥ **%35**'inde koyu çerçeve var.
   - **Üst/alt kenar:** şeridin yarısından çoğu beyaz kaldıkça yukarı/aşağı uzatılır.
   - Yükseklik sınır içinde ve uyan satırlar bu aralığın en az **%25**'i.
   - **Biçim:** `(yükseklik × 9) / (genişlik × 16)` **1,2–2,6** arası.
   - Ortası sınır içinde, üstü ≥ **0,04**, ve (altı ≤ **0,96** ya da üstü ≥ **0,2**).
     (Eğik indirilen telefon alttan taşabilir.)

### 3.2 Şekille bulma (yalnız telefon paneli; altyazı hattı kullanmaz)
Koyu çerçeve bulunamazsa (altın/gümüş gövde, açık kapı önü):
- Vision dikdörtgen bulucusu: en/boy 0,35–0,75, en küçük boy 0,25, en çok 4 sonuç,
  köşe toleransı 25°, güven ≥ 0,6.
- Üst kenar genişliği sınır içinde; boy (piksel) ≥ en × **1,4**.
- İçi (kenarlardan %10 / %12 içeride, kare içinde kırpılarak): renksiz orta-açık nokta
  (düşük ≥ 80, yayılma ≤ 35) ≥ **%40**; koyu nokta (max < 70) en az bir ve ≤ **%35**.
- Bu yolla bulunan telefon **ancak içinde sohbet varsa** telefondur (§5.4).

### 3.3 Kararmış ekran
Telefon dokunulmadan durunca ekran kararır. Karenin ortasındaki (x %15–85, y %10–90, iki
noktada bir) düşük değerlerin **%95**'lik dilimi 40–117 arasındaysa bütün değerler
`225 / dilim` ile çarpılıp açık ekran yeniden aranır.

### 3.4 Koyu temalı uygulama
Ekran koyu, gövde açık (ör. araç çağırma uygulaması):
- Ekran noktası: `düşük + yayılma ≤ 75` ve yayılma ≤ 40. Gövde noktası: `düşük + yayılma ≥ 85`.
- Aynı şekil sınamaları; altı ≤ **0,96** olmalı.
- Koyu kıyafet de koyu dikdörtgen verir: ekran satırlarının en az **%15**'inde, kenarlardan
  2 nokta içeride, parlak (`düşük + yayılma ≥ 110`) en az 2 ve en çok **%60** nokta olmalı.

### 3.5 Takip
- Bulunursa yer, koyu mu (ekran noktalarının ≥ %50'si koyu) ve an saklanır.
- Bulunamazsa: son bulunuştan **3 sn** geçmediyse ve son yerde aynı tür ekran duruyorsa
  (ekranın 14 × 7 noktasının ≥ **%45**'i koyu ya da beyaz ekran rengi) telefon orada sayılır;
  değilse takip bırakılır. (Hayalet telefon altyazıları kesik okutuyordu.)
- **Yazılardan tahmin:** Telefon uygulamasına özgü yazı görüldüyse ve telefon yoksa (ya da
  son bulunuş 2 sn'den eski) yer tahmin edilir: sol `max(0,02, en_sol − 0,015)`, sağ
  `min(0,98, max(en_sağ + 0,015, sol + 0,21))`, üst `max(0,04, min(0,2, en_üst − 0,02))`,
  alt `min(0,95, max(0,82, en_alt + 0,03))`, eğim 0. Koyu mu: ≥ %45.

### 3.6 Renk örnekleme
- Kare bir kez **960 × 540**'a küçültülür; bir noktanın rengi çevresindeki 3 × 3'ün ortalamasıdır.
  Kenardaki noktalar yoktur.
- **Aydınlatılmış örnekleme** (kararmış açık ekran): ekranın içinden (y adım 0,02,
  x %5–95 adım 0,1) renkler en parlak kanala göre sıralanır. Ekran = %80'lik dilim.
  Ekran 40–231, ortanca ≥ ekran × 0,8, %80'lik rengin gri oranı (min/max) ≥ 0,8 ve en
  parlak ≤ ekran × 1,3 ise bütün renkler `238 / ekran` ile çarpılır (en çok 255).
  Değilse olduğu gibi (koyu tema zaten koyudur).


### NinoCore'da eksik

- Telefon bulma (dört yol), takip, yazılardan tahmin, renk örnekleme yok.

---

## 4. Telefonun okunması

- Telefon bulunur (takip dahil), kutusu kesilir, OCR yapılır (derin değil), satırlar kareye taşınır.
- Telefon yoksa: ekranda panel varsa ve telefon **1,2 sn**'dir görülmediyse panel kalkar.
- Okumada harita tuşlarından biri (`recenter`, `2d view`, `3d view`, `add marker`,
  `set destination`, `close menu`; satır temizlenip küçük harfle) varsa bu haritadır: panel kalkar.


### NinoCore'da eksik

- Telefon okuması (ayrı okuyucu, yalnız işlemci) yok.

---

## 5. Ekran türü

### 5.1 Sohbet listesi (çevrilmez)
Alt alta en az **3** kez "kişi adı + hemen altında önizleme": ad 1–3 sözcük, her biri büyük
harfle başlar, `. , ! ? : …` yok; sonraki satır adın altından ad boyunun **1,2 katından** az
aşağıda ve sol kenarı **0,03**'ten yakın.

**Mesaj listesi** da çevrilmez: mesaj kartı listesi kuralı (`okuma-hatti.md` §14.1) ve en
az bir satır `...`/`…` ile bitiyor; ya da sohbet listesi.

### 5.2 Sohbet başlığı
Başlık, en üst şeritte (ekran yüksekliğinin **%7**'si) ya da en üstteki satır (0,002 payla)
olan ve şu şartları sağlayan satırdır:
- Kişi/yer adı: mesaj kartı ad kuralı ya da (≥ 2 karakter, ≤ 5 sözcük, yalnız harf ve
  `, . ' ’ & -` ve boşluk, harf var).
- Gezinme düğmesi değil: `back geri done close cancel edit` (baştaki `<`/`‹` atılarak).
- Ortası ekranın o yükseklikteki ortasına ekran genişliğinin **%12**'sinden yakın.
- Hemen altında (0,008–0,05 aşağıda) ve ekran kenarına göre aynı girintide (0,015) başka
  satır **yok** (listede adın altında önizleme olur).

Başlık varsa ekran **sohbettir**.

### 5.3 Sohbet mesajları
- Başlık şeridinin altı = `max(ekran_üstü + yükseklik × 0,07, başlık_altı)`.
- Önce aynı satırdaki parçalar birleşir (emoji satırı böler): dikeyde küçük boyun ≥ **%75**'i
  örtüşüyor, aradaki boşluk ≤ **0,03** ve sağdaki parça soldakinin sağından en çok 0,005 içeride.
- Satır alınır: en az 2 harf; üstü başlık şeridinin altından **0,012**'den fazla aşağıda
  (yarısı kesik ilk satır atılır); altı ekranın altından **0,01**'den fazla yukarıda.
- **Satır aralığı:** art arda üst kenar farklarından 0,012–0,04 arasındaki en küçüğü;
  yoksa en küçük satır boyu × 1,2.
- **Paragraf:** sonraki satır önceki satırın üstünden aralığın **1,6 katından** az aşağıda ve
  girintisi (ekran kenarına göre) paragrafın ilk satırınınkine **0,02**'den yakınsa aynı mesajdır.
- Mesaj olmayanlar atılır: `new message`, `new messages`, `typing`, `delivered`, `read`,
  `today`, `yesterday`, `messages encrypted` (ve bunlarla biten); uygulama bağlantı kartı
  adları (`ryde`, `rydeme`, `buckme`); en az 2 sözcüklü, noktalamasız ve her sözcüğü büyük
  harfle başlayan (ya da `del de la of the &`) satır (ek olarak gönderilen yer/eşya adı).
- Mesajın satır boyu = aralık × 0,85.
- **Mac ek kuralı:** grup sohbetinde balonun üstündeki gönderen adı (1–2 büyük harfle
  başlayan sözcük, noktalamasız) mesaj değildir.

Örnek: `Here r the coords bro. Those` + `reefs look like a solid spot` (aynı paragraf) →
tek mesaj `Here r the coords bro. Those reefs look like a solid spot`.

### 5.4 Sohbet mi uygulama mı
- Sohbet = başlık var **ve** mesajlardan en az biri **cümle**.
- **Cümle:** en az 2 harfli sözcükte son karakter `. ! ?`; ya da `!`/`?` içeriyor ve ≥ 2 sözcük;
  ya da ≥ 3 sözcük ve ilk sözcükten sonra küçük harfle başlayan sözcük var.

| Girdi | Cümle mi |
|---|---|
| `Book Ryde ($82)` | hayır |
| `Righto Cash & Carry` | hayır |
| `1.74 mi` | hayır |
| `Thx amigo! U find anything else` | evet |
| `Are you high right now?` | evet |
| `Dropped off scuba to yuh boat man` | evet |

- Yalnız şekille bulunan telefon (§3.2) sohbet değilse **telefon sayılmaz**.
- Sohbet değilse ve mesaj listesi değilse → **uygulama satırları** (§5.5).
- Hiç satır yoksa: panel varsa ve 1,2 sn'dir telefon görülmediyse kalkar.
- Satır bulununca "telefon görüldü" anı güncellenir ve oyun GTA 6 sayılır (§2).

### 5.5 Uygulama satırları (sohbet olmayan ekran)
- Satırın başındaki simgeler atılır (harf, rakam, `$ € £` gelene kadar).
- `messages encrypted` / `message encrypted` ile biten satır alınmaz.
- En az 3 harf; üstü başlık şeridinin altında; altı ekranın altından 0,01 yukarıda.
- Satır boyu = satır yüksekliği × 0,85.
- **Birleştirme:** sonraki satır öncekinin altından kendi boyunun **0,6 katından** az aşağıda,
  sol kenarı **0,02**'den yakın ve (küçük harfle başlıyor ya da önceki satır cümle bitirmiyor
  ve en az 3 sözcük) ise devamdır. `By …` ile başlayan ≤ 4 sözcüklü yazar satırı paragrafa katılmaz.
- Bütün satırlar "BÜYÜK HARFLİ kısa etiket" ise (harfler büyük, ≤ 3 sözcük) ekran telefon
  değildir (kapının `△ CLOSE` ipucu). Hiçbir şey dönmez.

Örnek: `◆ Checking Account`, `$1,250 to next goal` → `Checking Account`, `$1,250 to next goal`.


### NinoCore'da eksik

- Telefon ekranı türleri (liste, başlık, mesaj, uygulama satırı, cümle kuralı) yok.

---

## 6. Kararlılık, hafıza ve çeviri

### 6.1 Okuma anahtarı ve kaydırma
- Okuma anahtarı = her mesajın anahtarı + `@` + `⌊(mesaj_üstü − ekran_üstü) × 60⌋`
  (telefon elde sallanınca değişmez, sohbet kaydırılınca değişir). Anahtar öncekiyle aynıysa
  bir şey yapılmaz.
- **Kaydırma:** Panel ekrandayken, gösterilen mesajlardan ortak olanlardan biri ekrana göre
  **0,02**'den fazla yer değiştirdiyse ya da gösterilenlerin yarısından azı yeniden okunduysa
  — **ve** (Mac) yeni okumanın bütün mesajları bir önceki okumadakilere benziyorsa —
  panel hemen kalkar.
- **Benzer mesaj:** sadeleştirilmiş metinler aynı, ya da biri ötekinin başı/sonu, ya da
  ≥ 0,75 benzer.

### 6.2 Yarım mesajlar
- **Altta kesik son mesaj:** sohbette, hafızada yok, altı ekranın altından 0,06'dan yakın,
  boyu mesaj satır boyunun 1,8 katından büyük (çok satırlı) ve `. ! ? … " )` ile bitmiyorsa
  atılır (tamamı görünene kadar).
- **Üstte kesik ilk mesaj:** sohbette, birden çok mesaj var, hafızada yok, küçük harfle
  başlıyor **ve** üstü ekran üstünden **0,095**'ten yakınsa atılır. (Küçük harfle yazılan
  gerçek mesajlar kalsın.)
- **Hafızadan bulma:** mesaj ≥ 5 sözcükse hafızada aynısı ya da onunla başlayan/biten en
  uzun kayıt kullanılır; daha kısaysa yalnız aynısı.

### 6.3 Türkçenin kaynağı (sırayla)
1. Telefon sözlüğü (§6.6; yalnız Türkçe hedefte).
2. Havuzda bilinen çeviri.
3. Kalıcı hafıza (çeviri diline özel dosya; dil değişince o dilin dosyası yüklenir).
4. Bu oturumun cihaz çevirileri.

### 6.4 Panel ne zaman yeniden kurulur (Mac)
- **Sohbet değişti:** yeni başlık (≤ 3 sözcük, noktalamasız) ekrandakinden farklıysa panel
  hemen kalkar.
- **Aynı mesajlar:** panel varsa, ekran türü aynıysa ve okunanlar gösterilenlerle aynıysa
  panel yeniden kurulmaz. Aynı sayılması için: okunan sayısı × 2 ≥ gösterilen sayısı,
  okunan ≤ gösterilen + 1 ve her okunan gösterilenlerden birine benziyor.
- **Yeni mesajlar:** panel varken, gösterilenlere benzemeyen mesajlar ancak **bir önceki
  okumada da** (benzer biçimde) görüldüyse panel güncellenir; yoksa panel korunur.
- **Onay:** bilinmeyen (Türkçesi olmayan) mesajlar bir önceki okumada aynı metinle
  görülmediyse çeviriye gitmez. Bu arada panel boşsa bilinenler hemen gösterilir
  (ara gösterim; anahtar yazılmaz). Bütün mesajlar biliniyorsa ikinci okuma beklenmez.
- (Ortak kopyada onay yer dahil anahtarla yapılır; Mac yalnız metne bakar, çünkü elde sallanan
  telefonda yer anahtarı hiç tutmuyordu.)

### 6.5 Çeviri
- Bilinmeyen mesajlar havuza bildirilir (havuz açıksa ya da oyun havuz öncelikliyse).
- Havuz soruluyorsa bilinmeyenler **tek istekte** sorulur; bağlam = sohbette ilk bilinmeyenden
  önceki en çok **4** mesaj.
- Havuzdan gelmeyenler cihazda çevrilir, aynı anda en çok **2**.
- Sonuç: simgeler ve HTML varlıkları (`&amp; &#39; &quot; &lt; &gt; &apos;`) temizlenir,
  boşluklar sadeleşir, art arda aynı sözcük teke iner.
- Boş olmayan her çeviri kalıcı hafızaya yazılır (en çok 5 000 kayıt, aşılırsa silinir);
  cihaz çevirisi ayrıca oturum hafızasına yazılır.
  (Ortak kopyada cihaz çevirisi kalıcı hafızaya yazılmaz; sınır 600.)

| Girdi | Çıktı |
|---|---|
| `Rosa &amp; Marco` | `Rosa & Marco` |
| `Don&#39;t` | `Don't` |
| `TAMAMEN YENİDEN YENİDEN YENİDEN` | `TAMAMEN YENİDEN` |

### 6.6 Telefon sözlüğü
Sadeleştirilmiş tam eşleşme (Türkçe hedef):

| İngilizce | Türkçe |
|---|---|
| Vice City Horn / The Leonida Journal / Leonida Journal | aynı kalır (gösterilmez) |
| Ripped | Kaslı |
| Toned | Sıkı |
| Average | Ortalama |
| Body & Nutrition | Vücut ve Beslenme |
| Strength Workout | Güç Antrenmanı |
| Cardio Workout | Kardiyo Antrenmanı |
| Workout Window | Antrenman zamanı |
| Focus | Odak |
| Fitness | Fitness |
| Calorie Balance | Kalori Dengesi |
| You will maintain / gain / lose weight | Kilonu koruyacaksın / Kilo alacaksın / Kilo vereceksin |
| Hungry / Full | Aç / Tok |
| Trip Details | Yolculuk Bilgileri |
| Cost | Ücret |
| Choose Ryde / Standard Ryde | Ryde Seç / Standart Ryde |
| Change Destination | Varış Noktasını Değiştir |
| Book Ryde / Cancel Ryde | Ryde Çağır / Ryde'ı İptal Et |
| Checking Account / Savings Account | Vadesiz Hesap / Birikim Hesabı |
| Family Savings / Family Savings Video | Aile Birikimi / Aile Birikimi Videosu |
| ATM Finder / FAQs | ATM Bulucu / SSS |
| Savings / Balance | Birikim / Bakiye |
| Deposit / Withdraw / Transfer | Para Yatır / Para Çek / Transfer |
| Transactions / Recent Transactions | Hesap Hareketleri / Son Hareketler |
| Set a Goal | Hedef Belirle |
| Messages encrypted / New message | Mesajlar şifreli / Yeni mesaj |
| All Contacts / Suggested / Messages | Tüm Kişiler / Önerilenler / Mesajlar |
| Map pin expired | Konum süresi doldu |

Kalıplar:
- Sonda parantezli tutar korunur: `Book Ryde ($82)` → `Ryde Çağır ($82)`.
- `Ad - Seviye`: adlar `muscle Kas`, `body fat Vücut Yağı`, `stamina Dayanıklılık`,
  `strength Güç`, `fat Yağ`; seviyeler `high Yüksek`, `low Düşük`, `medium Orta`,
  `average Ortalama`, `very high Çok Yüksek`, `very low Çok Düşük`. Tire düşmüşse de olur.
- `Level 3/4` → `Seviye 3/4`.
- `$1,250 to next goal` → `Sonraki hedefe $1.250`.

| Girdi | Çıktı |
|---|---|
| `Checking Account` | `Vadesiz Hesap` |
| `Family Savings` | `Aile Birikimi` |
| `$1,250 to next goal` | `Sonraki hedefe $1.250` |
| `Are you high right now?` | yok |
| `Book Ryde ($82)` | `Ryde Çağır ($82)` |
| `Trip Details` | `Yolculuk Bilgileri` |
| `Level 3/4` | `Seviye 3/4` |
| `Cardio Workout` | `Kardiyo Antrenmanı` |
| `Muscle - High` | `Kas - Yüksek` |
| `Stamina - Medium` | `Dayanıklılık - Orta` |
| `Ripped` | `Kaslı` |
| `Muscle High` | `Kas - Yüksek` |


### NinoCore'da eksik

- Kaydırma, yarım mesaj, onay, hafıza (dosya, oturum), toplu havuz isteği, sözlük yok.

---

## 7. Telefon ve altyazı hattı

Telefon oyununda altyazı hattı telefon yazılarını altyazı saymaz (ayrıntılı sıra
`okuma-hatti.md` §6):

- Telefon kutusu okumadan önce siyaha boyanır (alt kenar `max(alt, min(alt + 0,15, 0,84))`).
  Telefon son **5 sn**'de görüldüyse aynı yerde sayılır. Altyazı hattının telefon araması
  şekil yolunu kullanmaz.
- Telefon kutusu içindeki satırlar, açık zeminde koyu yazılar ve telefon uygulaması
  yazıları atılır.
- Telefon varken ya da son **30 sn**'de telefonda yazı okunduysa ortası `max(taban, 0,8)`'in
  üstündeki satırlar atılır; en az 3 sözcüklü ve telefondaki bir yazının içinde geçen satır atılır.
- **Telefon uygulaması yazısı** (telefon bulunamasa da):
  - Sadeleştirilmiş yazıda şu köklerden biri sözcük başında geçiyor: `trip detail`,
    `change destinat`, `destinatio`, `messages encrypt`, `map pin expir`, `checking accoun`,
    `family saving`, `workout window`, `strength workout`, `cardio workout`, `calorie balanc`,
    `maintain weight`, `gain weight`, `lose weight` (OCR bir harf kaçırsa da tutsun).
  - Ya da tam sözcük olarak `ryde`, `rydeme`, `buckme`.
  - Ya da parantezsiz hâli sözlükte tam var.
  - Ya da en az 2 sözcüklü ve sözlük kalıbıyla çevriliyor. (Tek sözcükler `Focus`, `Cost`
    diyalogda da geçer, sayılmaz.)
  - Örnek: `Body Fat Low` → telefon yazısı.
- Telefon uygulaması yazısı görülüp telefon bulunamadıysa telefonun yeri bu yazılardan
  tahmin edilir (§3.5).
- Köşe okumasında telefon son 3 sn'de görüldüyse telefon kutusundaki satırlar ipucu sayılmaz.
- Mesaj kartı, telefon son **10 sn**'de görüldüyse gösterilmez.


### NinoCore'da eksik

- Altyazı hattındaki telefon süzgeçleri ve telefon uygulaması yazısı tanıma yok.

---

## 8. Telefonun yanındaki Türkçe

### 8.1 Balon rengi (her mesaj)
- Çeviri boşsa ya da gösterilmeye değmezse (sadeleştirilmiş çeviri boş, kaynağın aynısı,
  ya da tek sözcüklü kaynağı olduğu gibi içeriyor: `BuckMe` → `BuckMe mi?`) balon yok.
- Renk: yazının solunda, balonun iç payında (**0,0045** ve 0,0027 içeride) beş yükseklikte
  (%15 %35 %50 %65 %85) okunan en parlak renk = kenar. Kutunun içinden (x %10–90, y %15–85,
  0,1 adım) en parlak %40'ın ortancası = zemin. Zemin yoksa ya da kenardan çok koyuysa
  (`zemin_parlaklığı × 4 < kenar × 3`) kenar kullanılır. Hiçbiri yoksa `(233, 233, 236)`.
- Yazı rengi: zemin parlaklığı > 140 ise `#2c2c2e`, değilse `#f5f5f7`.
- Kutu yazıdan x'te **0,0035**, y'de **0,004** taşar; açı telefonun açısıdır.

Örnek: gelen balon zemini `#e9e9ec`, yazı `#2c2c2e`. Çevirisi aslıyla aynı (ad) olan mesaj örtülmez.

### 8.2 Sohbet paneli
- **Sütun:** telefonun ortası ekranın sağ yarısındaysa solunda, değilse sağında; telefondan
  **0,035** uzakta, genişlik **0,27** (kare içinde 0,02–0,98).
- İç pay **0,012**; balonun en çok genişliği iç genişliğin **%82**'si; balon iç payı 0,012.
- Satır boyu `min(max(mesaj_boyu, 0,018), 0,028) × 0,97`. Satır sayısı ve en uzun satır
  sarma kuralıyla (harf genişliği boy × 0,5 × 9/16, satırda en az 12 harf).
- **Balon kutuları:** her mesajın hizasında; yükseklik `boy × satır × 1,3`; üst
  `min(max(mesaj_üstü, önceki_taban), 0,98 − yükseklik)`; sonraki taban `üst + yükseklik + boy × 0,6`.
- Panel telefon boyundadır. En alttaki balon `telefon_altı − 0,012 − 0,03` (sağ alttaki logo
  payı) çizgisini aşarsa bütün balonlar o kadar yukarı kayar.
- **Giden mesaj:** sohbette ve şunlardan biri:
  - Telefonda sağa yaslı: ekran kenarına göre girinti > ekran genişliği × **0,2**.
  - En soldakine göre girinti > genişlik × **0,1** ve sağ kenarı en sağdakine × **0,08**'den yakın.
  - Maviliği (`B − (R+G)/2`) sohbetteki en gri balondan en az **14** fazla.
- Balon genişliği `min(en_çok, en_uzun_satır × boy × 0,5 × 9/16 + 0,012 + 0,012)`.
  Giden sağa, gelen sola yaslı. Kutu altı `boy × 0,3` uzatılır.
- **Zemin:** gelen balonların ortasının yüksekliğinde, ekranın sağ kenarından 0,012 içeride
  okunan renkler; parlaklığa göre sıralanıp ortadaki. Yoksa `(226, 228, 233)`.
- **Açık sohbet** (zemin parlaklığı > 150): zemin beyaza %60 yaklaştırılır; giden balon
  `R × 0,86, G × 0,93, B × 1,04`; gelen balon beyaza %70 yaklaştırılır.
- Zemin saydamlığı **0,6**, balon saydamlığı **0,95**; balonlar "yan balon", açısız.
- Panelin en üstünde ortada sohbet başlığı (çevrilmez), boy `min(max(en_büyük_mesaj_boyu, 0,02), 0,028)`.
- Öğe sırası: önce zemin, sonra balonlar.

Örnekler (sahte renklerle):
- Zemin telefonun boyunda (üstü telefonun üstü) ve telefonun sol yanındaki alanda.
- Gelen balonun üstü mesajın hizasında (0,5), gelen solda giden sağda.
- Gelen balon `#f8f8f9`, giden mavi balon `#acccfe`.
- Mavimsi ışıkta gelen balon sola, belirgin mavi sağa yaslı.

### 8.3 Uygulama balonları (sohbet olmayan)
- Uygulamanın rengi: önce başlık şeridi (ekran üstünün 0,04 üstünden 0,06 altına, 0,01 adım;
  ekran genişliğinin %10–90'ı), yoksa her satırın dört yanı (0,006 dışarıda). En doygun renk
  (doygunluk > 60 ve en parlak kanal ≥ 120). Bulunursa balon zemini odur, yazı beyaz.
- Bulunamazsa (beyaz haber uygulaması): ekrandaki renkler 16'lık kovalara ayrılır, en
  kalabalık kovanın ortalaması arka plandır. Satırların içinde arka plandan en uzak renk
  (toplam kanal farkı ≥ 90) yazı rengidir: açık zeminde × 0,6 koyulaştırılır, koyu zeminde
  beyaza yarı yarıya açılır. Uzak renk yoksa açık zeminde `#1c1c1e`, koyuda beyaz.
  Hiç renk okunamazsa zemin `(58, 58, 60)`.
- Bütün balonlarda aynı yazı boyu: satır boylarının (× 1/0,85) ortancası,
  `min(max(…, 0,018), 0,028) × 0,95`.
- Harf genişliği `boy × 0,5 × 9/16`; satır başı harf `max(8, (sütun − 0,03) / (harf × 0,85))`.
  Birden çok satırsa genişlik sütun kadar, yükseklik `boy × (1,22 × satır + 0,45)`;
  tek satırsa genişlik `min(sütun, harf_sayısı × harf + 0,03)`, yükseklik `boy × 1,55`.
- Üst: çok satırda satırın üstü, tek satırda satırın ortasına göre; `önceki_taban`'ın altında,
  en çok `0,98 − yükseklik`. Sonraki taban `üst + yükseklik + boy × 0,4`.
- Telefonun solundaysa sağa (telefona) yaslı, sağındaysa sola yaslı. Saydamlık 0,95, yan balon.
- Zemin paneli yoktur.

### 8.4 Kıpırdamama
- **Elde sallanma:** yeni yerleşimde telefonun ortası eskisinden x ve y'de **0,05**'ten az
  kaydıysa yerleşim eski telefon yerine göre kurulur (panel yerinde kalır).
- **Aynı yazının kutusu:** aynı kaynak ve çeviri eski kutusuna (sohbette 0,012 / 0,015,
  uygulamada 0,04 / 0,06) yakınsa eski kutu aynen kalır. Uygulamada bütün çeviriler aynı
  ve yerleri 0,06'dan yakınsa bütün yerleşim eskisi gibi kalır.
- **Takip:** Panel ekrandayken en sık **100 ms**'de bir yalnız telefonun yeri bulunur (yazı
  okunmaz). Ortası kayma değeri öncekinden x'te > **0,009** ya da y'de > **0,012** farklı ve
  her iki eksende < **0,08** ise: tek ölçüm gürültüdür; aynı yönde ikinci ölçüm (x 0,008,
  y 0,011 içinde) gelince iki ölçümün ortalaması kadar bütün balonlar kaydırılır.
- Panel TV'ye köşe/ipucu/mesaj/harita öğeleriyle aynı listede gider (`okuma-hatti.md` §12.7).


### NinoCore'da eksik

- Panel ve balon yerleşimi yok; TV mesajında renk, saydamlık, açı, zemin paneli alanları yok.

---

## 9. Harita kartı

Harita ekranında yalnız **seçili görevin kartı** çevrilir; menünün kalanı çevrilmez.

### 9.1 Harita ekranı
Satırların (simge kırıntıları temizlenip küçük harfle) tam olarak şunlardan en az **ikisi**:
`recenter`, `2d view`, `3d view`, `add marker`, `remove marker`, `set destination`,
`remove destination`, `close menu`, `view on map`, `markers`, `cinematic`.

- Harita ekranı menü sayılır: 5 sn menü bayrağı (altyazı okunmaz), telefon aranmaz.
- Köşe okumasının menü araması harita açıkken her turda (0,6 sn) yapılır, kapandıktan sonra
  10 sn daha.

Örnek: tek satır `Keep the engine running.` → harita değil.

### 9.2 Kartı bulma
1. Satır adayları: sağ kenarı > 0,30.
   - Satırdaki uzaklık etiketi (sayı + `km mi ft m`) silinir; silindiyse ve sol kenar < 0,5
     ise sol kenar 0,5 sayılır.
   - Baştaki harfsiz parçalar (simge, `(43)`) silinir, sol kenar silinen harf oranında sağa kayar.
   - Sol kenar > 0,30 ve en az 3 harf olmalı. Üstten sıralanır.
2. **Cümle satırı:** en az 3 sözcük ve en az 6 küçük harf.
3. İlk cümle satırı kartın başıdır. Altındaki satırlar sırayla:
   - Cümle satırı, önceki satırın altından boyunun **2,6 katından** az aşağıda, yatayda örtüşüyor
     ve sol kenarı ilk satırınkine **0,06**'dan yakın → kartta.
   - Değilse: önceki satırın altından boyunun **1,2 katından** az aşağıda, sol kenarı öncekine
     **0,03**'ten yakın, küçük harf içeriyor ve önceki satır `. ! ?` ile bitmiyor → kartta
     (cümlenin kısa son satırı).
4. **Cümleleri ayırma:** satır öncekinin cümlesine katılır: küçük harfle başlıyor ve önceki
   cümle bitmemiş; ya da sol kenarı cümlenin ilk satırına 0,03'ten yakın, öncekinin altından
   boyundan az aşağıda ve (önceki satır sağ uca 0,04'ten fazla erken bitip yeni satır büyük
   harfle başlamıyor). Değilse yeni cümle.
5. **Başlık:** ilk cümlenin hemen üstünde (altı ilk satırın üstünden 0,01'den fazla aşağıda
   değil ve 0,06'dan yakın), yatayda örtüşen (0,05 payla), tamamı büyük harf ve en az 3 harfli
   en son satır. Sondaki 1–3 karakterlik harfsiz kırıntılar atılır.
6. **Kutu:** kart satırları ve başlık; altındaki hedef satırı (`GOAL $100 / $5,000`: üstü kutunun
   altından en çok 0,05 aşağıda, sol 0,03 / sağ 0,08 payla) da kutuya katılır.
7. Satır boyu ortanca. Cümle metinleri: satırlar boşlukla birleşir, satır sonu tireli sözcük
   birleşik kalır (`burned-` + `out` → `burned-out`), baştaki simge kırıntıları (`i`, `•`, `●`,
   `◆`, `△`, `▲`, rakamlı parçalar, `ml`) büyük harften önce atılır.

| Okuma | Başlık / cümleler |
|---|---|
| `BUY FLOWERS` / `Lucia will appreciate this` / `Have some flowers delivered to the` / `house for Lucia.` | `BUY FLOWERS` / `Lucia will appreciate this`, `Have some flowers delivered to the house for Lucia.` |
| (gerçek kare) para yatırma kartı | `DEPOSIT CASH INTO BUCKME` / 2 cümle; ilki `nearby ATMs` ile biter, ikincisi `checking account at an ATM` içerir |
| (gerçek kare) balık kartı, simge `(43)` ve `1.53 km` karışmış | cümle: `Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg.` |

### 9.3 Kartın çerçevesi (görüntüden)
Kart koyu, harita açık zeminlidir. Kare 640 × 360 örneklenir; koyu = parlaklık < **130**.
- Satırlar: yazı kutusunun içinde y 0,02 adım; sütunlar x 0,03 adım.
- Her yönde koyu satır/sütunların en az yarısı koyu kaldıkça ilerlenir: sol (adım 0,003,
  en çok 0,04), sağ (0,003, 0,09), alt (0,004, 0,08), üst (0,004, 0,06). Açık ince şerit
  (rota çizgisi) için 2–4 adım ileri bakılır; ötesi koyuysa devam.
- Sınıra kadar gidildiyse (koyu harita) o yanda yazı kutusu paylı kullanılır: sol −0,015,
  sağ +0,02, alt +0,02, üst −0,02.
- Çerçeve yazı kutusundan dar çıkarsa yok.

### 9.4 Mac'te gösterme kuralları
- Kartta Türkçe harf (`ğışĞİŞ`) varsa ya da cümle yoksa gösterilmez (PS5 bildirimi).
- **Başlıksız ve 6 sözcükten az** kart gösterilmez (kartın kırığı). (Ortak kopyada bu kural yok.)
- Başlıksız ve sol > 0,6 ve üst < 0,32 → PS5'in sağ üst bildirimi, gösterilmez.
- Üst < 0,1 → sekme şeridi, gösterilmez.
- Aynı başlıklı kartın yarım okuması (ekrandaki tam metin onunla başlıyor) ekrandakinin
  yerine geçmez.
- Kart anahtarı = sadeleştirilmiş tam metin + `@` + `⌊üst × 50⌋`. Aynıysa bir şey yapılmaz.
- **Aynı kart** (aynı başlık ve üstü 0,04'ten yakın) biraz farklı okunduysa (`0.26 ml` /
  `0.26 mi`) eski Türkçe yenisi gelene kadar kalır; değilse eski Türkçe hemen kalkar.
- Hafızada varsa (en çok 200 kart; aşılınca silinir) hemen gösterilir.
- Çeviri sürüyorsa yeni kart beklemeye alınır (yalnız en sonuncusu); süren bitince onun
  sonucu gösterilmez, bekleyen çevrilir.
- **Çeviri:** parçalar = başlık (Baş Harfleri Büyük hâliyle) + cümleler. Havuzda bilinenler
  alınır; havuz açıksa kalanlar tek istekte havuza sorulur; gelmeyenler cihazda **aynı anda**
  çevrilir. Simgeler temizlenir. Başlık Türkçe büyük harfle yazılır; cümlelerde HTML varlıkları
  çözülür ve terim düzeltmesi yapılır. Satırlara bölünmez (TV böler).
- Sonuç ancak kart anahtarı hâlâ aynıysa ve menü bayrağı hâlâ açıksa gösterilir.
- Harita kapanınca (menü bayrağı sona erince) Türkçe kalkar. Menü okumasında kart yoksa da kalkar.

**Terim düzeltmesi:**

| Yanlış | Doğru |
|---|---|
| `KAPALI TUTULMASI` / `Kapalı Tutulması` / `kapalı tutulması` | `DEPOSU` / `Deposu` / `deposu` |
| `işaretli faturaların` / `işaretli faturalar` / `işaretli fatura` | `işaretli banknotların` / `işaretli banknotlar` / `işaretli banknot` |
| `narkotik` / `NARKOTİK` | `uyuşturucu` / `UYUŞTURUCU` |
| `trafik ışığı papağan balığı` / `kırmızı ışık papağan balığı` | `stoplight papağan balığı` |

**Mekân adı** (başlık çevrilmez, İngilizcesi kalır):
- Açıklamanın **ilk 4 sözcüğünde** işletme sözcüğü: `distributor shop store dive bar
  _bar restaurant dealer club diner garage convenience wholesaler boutique salon motel hotel bodega`.
- Ya da başlıkta `CUSTOMS AUTO SHOP BAR CLUB MOTORS GARAGE SPEEDWAY DINER CAFE GRILL MOTEL
  HOTEL STORE MART LOUNGE SALOON TACKLE ANCHOR MARINA AMMU-NATION BARBER TATTOO PAWN` sözcüğü.
- Ya da `THE ` ile başlıyor ve ≤ 4 sözcük.

| Başlık / açıklama | Mekân mı |
|---|---|
| `RIDEOUT CUSTOMS` | evet |
| `JASON'S MAILBOX` | hayır |
| `REEL DEAL` / `Bait shop for anglers and divers.` | evet |
| `JUST MOVED IN` / `Pick up some supplies from the Alpha convenience store near the motel.` | hayır |
| `TAKE CARE OF JASON` / `Keep checking in on Jason at the motel.` | hayır |

### 9.5 Yerleşim (Mac)
- Satır boyu `min(max(kart_boyu, 0,024), 0,034) × 0,9`. (Ortak kopyada 0,02–0,032 × 0,85.)
- Çerçeve = (görüntüden çerçeve ya da yazı alanı) **∪** yazı alanı; yazı alanı = kart kutusu
  x'te ±0,015, y'de ±0,02. (Ortak kopyada birleşim yok.)
- Harf genişliği `boy × 0,42 × 9/16` (dar yazı tipi). Genişlik
  `min(çerçeve_genişliği, en_uzun_satır × harf + 0,035)`.
- Satır sayısı: başlık 1; her cümle `⌈harf × harf_genişliği / (genişlik − 0,03)⌉` (en az 1).
- Yükseklik `boy × satır × 1,32 + 0,022`.
- Alttaki yer `0,97 − (çerçeve_alt + 0,012)`, üstteki yer `çerçeve_üst − 0,012 − 0,02`.
  Varsayılan: çerçevenin hemen altı (`çerçeve_alt + 0,012`). Altta yer yetmezse: üstte
  yetiyorsa ya da üstteki yer daha büyükse üste konur (yetmezse boy küçülür); değilse altta
  kalır ve boy küçülür.
- Sol `max(çerçeve_sol, kart_sol − 0,014)`. Öğe "kart" biçimindedir (TV oyunun kartı gibi
  çizer: koyu zemin, üstte vurgu çizgisi, ilk satır başlık).

Örnek (sahte çeviri): Türkçe kartın altında; satır sayısı `1 + cümle sayısı`; aynı kart
yeniden seçilince çevirmen yeniden çağrılmaz (hafızadan).


### NinoCore'da eksik

- Harita ekranı tanıma, kart bulma, çerçeve, gösterme kuralları, terim ve mekân kuralları, yerleşim yok.

---

## 10. GTA 6'ya özel kuralların tam listesi

Bu kurallar yalnız "telefon oyunu" (§1.1) açıkken çalışır; başka oyunlarda kapalıdır.

1. Telefon paneli ve uygulama balonları (§3–§8).
2. Altyazı hattında telefon maskesi, açık zeminde koyu yazı süzgeci, telefon yazısı süzgeçleri (§7).
3. Mesaj köşesi (kare sol ≥ 0,66, üst ≥ 0,74) altyazı sayılmaz; kart olarak işlenir
   (`okuma-hatti.md` §6, §14).
4. Altyazı ortadan **0,12**'den uzaksa altyazı değildir.
5. Küçük harfle başlayan blok altyazı değildir.
6. Mesaj listesi ve arama kartı altyazı değildir.
7. Altyazı yeri `gta-6` anahtarıyla öğrenilir; görev çizgisi en çok **0,935**; taban çizgisi
   şartı (yalnız pakette/havuzda bilinen yazı gösterilir) açık.
8. Görev şeridinde pembe vurgu (`okuma-hatti.md` §12.6).
9. Etkileşim ipucu kalıbı `A e DRINKS` ve balık tutma ipuçları (`Slowly rotate ○ to …`).
10. Menü sekme şeridi, harita ekranı ve harita kartı (§9); harita/görev menüsünün sol
    listesi ipucu kutusu sayılmaz.
11. Oyun ekrandan tanınır (§2).
12. Telefon uygulamaları: mesajlar (WhatUp), araç çağırma (Ryde/Rydeme), banka (BuckMe),
    haber (Vice City Horn, Leonida Journal), fitness.

### NinoCore'da eksik

- GTA 6'ya özel kuralların hiçbiri yok.

---

## NinoCore'da eksik: genel tasarım çakışmaları

Bölüme özel eksikler her bölümün sonundadır.

Yeni çekirdekte telefon, harita, mesaj kartı ve oyuna özel kurallardan **hiçbiri yok**.
Okuma hattı yalnız tek bölgeyi okuyup altyazı olayı üretir.

### Tasarım çakışmaları
- **Tek bölge, tek okuyucu.** Telefon, köşeler ve harita aynı kareyi ayrı bölgelerde, ayrı
  aralıklarla ve ana okumayı beklemeden okur. Yeni çekirdekte çoklu okuyucu ve paylaşılan
  "okuma kapısı" (`okuma-hatti.md` §4.6) olmalı; yoksa Vision takılması yeniden çıkar.
- **Kare sayısı / saat.** Bütün telefon ve harita süreleri ms'dir (0,6/1,0 sn aralık, 1,2 sn
  kalkma, 3 sn takip, 5 sn tutma, 8/10 sn duraklatma, 30 sn telefon yazıları, 100 ms takip).
  Çekirdeğe saat girmeli.
- **TV mesajı yetersiz.** Telefon paneli ve harita kartı TV'ye "katman öğeleri" olarak gider:
  kutu, satır boyu, zemin rengi, yazı rengi, saydamlık, açı, yan balon, zemin paneli, kart
  biçimi, buzlu, eğik, vurgu işareti `⟦ ⟧`. Yeni protokolde yalnız metin + konum (alt/üst)
  var; 16 KB sınırı kalabalık panelde dolabilir.
- **Oyun bilgisi.** Kurallar "havuz öncelikli oyun" bilgisine bağlı; yeni çekirdekte oyun
  tanıma ve havuz önceliği yok. Ekrandan tanıma PS5/kullanıcı bilgisini ezmemeli.
- **Görüntü işleme.** Telefon bulma, renk örnekleme, çerçeve bulma, vurgu rengi ham piksel
  ister. Çekirdekte ortak bir "küçültülmüş kare ve renk örnekleyici" olmalı (kare başına bir kez).

