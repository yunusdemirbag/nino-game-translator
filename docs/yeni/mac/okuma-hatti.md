# Mac okuma hattı: tarif

Bu belge, Mac uygulamasının PS5 karesinden TV'deki altyazıya kadar yaptığı her şeyi
**davranış olarak** anlatır: sıra, eşik, sayı, kural. Kod yoktur. Amaç, yeni Mac
uygulamasını yazan birinin bu belgeden test yazabilmesidir.

Telefon paneli, harita kartı ve oyuna özel işaretler ayrı belgededir:
`telefon-harita.md`. Bu belge yalnız onlarla kesiştiği yerleri anlatır.

## 0. Ortak kurallar

- **Koordinat:** Her kutu karenin (ya da okunan alanın) oranıdır, 0–1. Başlangıç sol
  üst köşedir. Kutu dört sayıdır: sol, üst, sağ, alt.
- **Alan içi → kare:** Okunan alanın içindeki kutu kareye şöyle taşınır:
  `kare_sol = alan_sol + kutu_sol × alan_genişliği` (üst, sağ, alt da aynı yolla).
- **Saat:** Eski Mac hattı **milisaniye saatiyle** çalışır (açılıştan beri geçen ms).
  Bütün süreler bu saatledir. Testlerde saat dışarıdan verilir ve elle ilerletilir.
- **Sadeleştirme (anahtar):** Küçük harf, harf ve rakam dışındaki her şey boşluk,
  boşluklar teke iner. Örnek: `Brenna: We can NOT stay long, kid.` →
  `brenna we can not stay long kid`.
- **Benzerlik oranı:** `1 − düzenleme_uzaklığı / uzun_olanın_boyu`. Boş yazı hiçbir
  yazıya benzemez. Varsayılan eşik 0,85.
  - `the boat will sink soon` ~ `the boal will sink soon` → benzer
  - `we can not stay long` ~ `the boat will sink soon` → benzer değil
- **Cümle sonu:** Sondaki kapanan tırnak ve parantezler (`" ' ” ’ » ) ]`) atıldıktan
  sonra son karakter `. ! ? …` ise satır cümle bitirir.


### NinoCore'da eksik

- Koordinat ve sadeleştirme anahtarı var; benzerlik oranı var. Milisaniye saati yok (kare sayılır).

---

## 1. Kare girişi ve tek kare kapısı

Her yeni karede sırayla:

1. Son kare saklanır (kare dökümü, buzlu zemin ve telefon takibi için).
2. Çeviri açıksa yan işler başlatılır, hiçbiri ana okumayı beklemez:
   köşe okuması (§12), oyun tanıma, mesaj kartının süresi (§14), telefon (ayrı belge).
3. Ek alanlar okunur (§11). Ana okumayı beklemez.
4. **Tek kare kapısı:** Okuma hattına aynı anda yalnız bir kare girer.
   - Önceki kare hâlâ işleniyorsa yeni kare **atlanır** (kareler birikmez).
   - Her giriş artan bir numara alır. Çıkışta yalnız o numara kapıyı açar. Kapı
     sıfırlandıysa (durdurma, yeni hat) eski okumanın geç çıkışı bir şey değiştirmez.
   - Bir okuma **45 000 ms**'den uzun sürerse "takıldı" sayılır: kapı sıfırlanır,
     hat yeniden kurulur.
   - Yedek okuyucu devredeyken (bkz. §4.6) kapıyı tutan okuma **9 000 ms**'yi
     geçerse 45 sn beklenmeden hat yeniden kurulur.

Örnek (kapı):
- `t=0: giriş → içeri (1)`, `t=100: giriş → atlandı`, `t=10 000: giriş → atlandı`
- `t=45 000: giriş → takıldı (45 000 ms)`, sonra `giriş → içeri (2)`
- Sıfırlamadan sonra 1 numaranın çıkışı kapıyı **açmaz**.


### NinoCore'da eksik

- Tek kare kapısı, 45 sn takılma ve hattı yeniden kurma yok (motor yalnız sırayla okuyor).

---

## 2. Okunan bölge

### 2.1 Altyazı bölgesi

- Varsayılan: üst **0,62**, alt **0,97**, sol **0,14**, sağ **0,86**.
- Hazır seçimler:

| Seçim | Üst | Alt | Sol | Sağ |
|---|---|---|---|---|
| Alt (varsayılan) | 0,62 | 0,97 | 0,14 | 0,86 |
| Üst | 0,03 | 0,38 | 0,14 | 0,86 |
| Tam kare | 0 | 1 | 0 | 1 |
| Özel | kullanıcının kaydı | | | |

- Kayıtlı bölge bir hazır seçimle 0,001 payla aynıysa o seçim sayılır, değilse "Özel".
- Bölgenin en küçük yüksekliği ve genişliği **0,05**. Kaydırma ve boyutlandırma
  bölgeyi karenin dışına taşırmaz (gerekirse yukarı/sola kayar).
- Dikey kaydırıcılar yüzdedir: konum = üst × 100, yükseklik = (alt − üst) × 100.

### 2.2 Öğrenilen şerit bölgeyi daraltır

Altyazının yeri öğrenildiyse (§9) yalnız o şerit okunur:
`okuma_üstü = şerit_üstü − 0,05`. Bu değer ancak bölgenin üstünden büyükse ve
bölgenin altından en az 0,06 yukarıdaysa kullanılır.

Örnek: aynı oyunda 10 altyazı `üst 0,84 / alt 0,92` → okuma üstü **0,79**.

### 2.3 Kesme

Bölge kareden piksel olarak kesilir (kenarlar tam piksele yuvarlanır). Telefon açıksa
kesilen alandaki telefon kısmı okumadan önce **siyaha boyanır** (bkz. §6 adım 2).


### NinoCore'da eksik

- Tek dikdörtgen var; hazır seçimler, en küçük boy, kaydırma kuralları yok.
- Varsayılan bölge farklı (yenisi 0,10–0,90 / 0,62–0,98).
- Öğrenilen şeritle daraltma ve telefon maskesi yok.

---

## 3. Okuma planı (ne zaman OCR yapılır)

Oyunun çoğunda bölge boştur ya da değişmez. Her kare okunmaz.

- **Bölge izi:** Kesilen alanın **64 × 12** gri küçük kopyası (düşük kaliteli küçültme).
- **Değişti mi:** İki izde herhangi bir noktanın farkı **16**'dan büyükse değişmiştir.
  İz uzunlukları farklıysa değişmiş sayılır. İstenirse yalnız bir kutunun örttüğü
  noktalara bakılır (kutu ızgaraya aşağı/yukarı yuvarlanır, en az bir hücre).
- **Plan:**
  - İz değişmediyse ve üst üste yeniden kullanım sınırı dolmadıysa: **son okuma
    kullanılır**, OCR yapılmaz. Sınır: normalde **20** kare, "hızlı altyazı algılama"
    açıkken **2** kare.
  - Değiştiyse ya da sınır dolduysa: OCR yapılır, sayaç sıfırlanır.
  - **Derin okuma** (§4.3) yalnız boş okuma sayacı 3'e tam bölündüğünde istenir.
- **Kayıt:** Her OCR'dan sonra okunan yazı saklanır. Yazı boşsa boş sayacı bir artar;
  doluysa sayaç **1** olur (yazı yeni kalktığında derin okuma sırası hemen gelmesin).
- Hat sıfırlanınca plan da sıfırlanır.
- Testlerdeki "her zaman" planı: eşik −1, yeniden kullanım 0, her boş karede derin.

Örnek: `iz aynı, son yazı "Hello there"` → son okuma kullanılır, `"Hello there"`.


### NinoCore'da eksik

- Okuma planı (64×12 iz, eşik 16, 20/2 yeniden kullanım, 3'te bir derin okuma) yok; her kare okunuyor.

---

## 4. OCR (yazı tanıma)

### 4.1 Ayarlar

- Apple Vision, **doğru (accurate)** düzey, dil: kaynak dil (çoğunlukla `en`),
  dil düzeltmesi **açık**.
- Satırın ilk adayı alınır; **güveni 0,5'in altındaki satır atılır**.
- Vision kutusu sol alttan ölçer; Nino'nun sol üst düzenine çevrilir
  (`üst = 1 − vision_üst_kenar`).
- Satırlar üst kenara göre yukarıdan aşağı sıralanır.
- Her satırın metni baştan ve sondan kırpılır, ardından simge düzeltmesi (§4.5) yapılır.

### 4.2 Satır parçalarını birleştirme

Vision aynı satırı simgenin olduğu yerde bölebilir (`Hold` ve `to continue`).
Parçalar soldan sağa dolaşılır; bir parça daha önceki bir sıraya şu şartlarla katılır:

- İki parçanın boyları birbirinin en az **yarısı** (dev tabela harfi katılmaz).
- Dikey ortaları arasındaki fark büyük boyun **%45**'inden az.
- Yatay boşluk (görüntünün en/boy oranıyla çarpılarak) **−0,01**'den büyük ve büyük
  boyun **4 katından** küçük.
- Boşluk büyük boyun **0,9 katından** genişse o boşluk görüntüden tanınır (§4.4); simge
  bulunursa araya o konur, bulunmazsa yalnız boşluk. (Tanıyıcı verilmeyen testlerde araya `●` konur.)
- Birleşen satırın güveni parçaların en küçüğü, kutusu birleşimidir.
- Birleşmeden sonra simge düzeltmesi yeniden yapılır.

Örnekler:
- `Hold` (0,30–0,36 / 0,80–0,85) + `to continue` (0,42–0,60 / 0,805–0,85) →
  tek satır, `Hold` ile başlar, `to continue` ile biter.
- Altyazı `The tide is coming in fast.` (boy 0,05) + yanında `BAIT`
  (boy 0,20) → **iki ayrı satır**, altyazının kutusu büyümez.

### 4.3 Derin okuma (boş bölgede kısa satır)

Vision geniş bölgede `Go!` gibi kısa satırları sık kaçırır. Derin okuma istenmişse ve
ilk okuma **hiç satır bulmadıysa**:

1. Ortadaki şerit (bölge genişliğinin **%40**'ı, tam yükseklik) **2 kat** büyütülüp okunur.
   Bulunan kutular şeridin değil bölgenin oranına çevrilir.
2. O da boşsa bölgenin tamamı 2 kat büyütülüp okunur.

Denemeler **sırayla** yapılır, ilk yazı bulunan kullanılır (aynı anda iki istek Vision'ı
kilitleyebiliyordu). İkisi de yazı bulursa şeridinki seçilir.

Örnekler:
- İlk okuma boş, yalnız şerit (genişlik = 2 × %40) `Go!` görüyor → `Go!`
- İlk okuma boş, tam büyütme `G0!`, şerit `Go!` → `Go!`
- İlk okuma `Hold the rope.` → yedek okuma hiç yapılmaz (tek çağrı).

Not: eski testlerden biri yedeklerin "aynı anda" çalışmasını bekler; güncel davranış
sıralıdır. Yeni testler sıralı davranışa göre yazılmalı.

### 4.4 Kumanda simgesini görüntüden tanıma

Oyunlar düğmeyi yazının içine resim olarak koyar. Vision ya hiç okumaz (sözcükler
arasında simge genişliğinde boşluk kalır) ya da `•`, `(x)`, `L`, `O` sanır.

**Şüpheli boşluk:** İki sözcük arası boşluk satır yüksekliğinin **0,9 katından**
genişse o boşluk tanınır; simge bulunursa araya eklenir, bulunmazsa hiçbir şey eklenmez.

**Şüpheli sözcük:**
- `L`/`R`/`C` + rakam ya da `D I l Z |` biçimleri (`LD`, `(C1`, `Ll`, `RZ`).
- 3 karakterden kısa, parantez içinde parça (`(x)`).
- Harf ve rakamsız en çok 2 karakterlik parça (`•`, `&`).
- `I` ve `A` dışındaki tek büyük harf.
- 2 karakterlik bilinen simge (L1–R3 hariç).
- Tamamı büyük harfli satırın sonundaki tek harf ya da `11 12 13 21 22 23`
  (`MOUNT HORSE A` → sondaki `A` △ olabilir).
- `press hold tap push use release mash` fiilinden sonra gelen tek büyük harf.
- Şüpheli sözcük tanınırsa yerine simge konur. Tanınmaz ve harf/rakam içermezse
  **atılır** (ıslık, işaret simgesi düğme değildir).

**Kenar simgeleri** (yalnız köşe ve ipucu okuyucusunda açık): satırın hemen solunda ve
sağında, satır yüksekliğinin **1,8 katı** genişliğinde bir alan "sıkı" kuralla tanınır;
simge varsa satırın başına/sonuna eklenir. Satır zaten simgeyle başlıyor/bitiyorsa bakılmaz.
Satır yüksekliği 4 pikselden azsa bakılmaz.

**Tanıma adımları** (kesit: boşluk, dar ise satır yüksekliğinin 1,4 katına genişletilir;
yükseklik satırın 2 katı; 6 pikselden küçükse vazgeçilir):

1. Kesit 48 piksel yüksekliğe gri ve renk doygunluğu olarak küçültülür.
2. Otsu eşiğiyle parlak noktalar ayrılır. En iyi leke: yüksekliği kesitin en az üçte biri
   (ama tamamı değil), en/boy 0,4–2,2, puanı `alan × (0,5 + kareye yakınlık) × (1,2 − ortadan uzaklık)`.
3. Sıkı kuralda leke: kesit yüksekliğinin %27–65'i, en/boy 0,78–1,28, kenara değmiyor.
4. **Renkli leke** (ortalama doygunluk > 0,28): harita işaretidir. İçinde tek büyük harf
   okunursa daire içinde harf (`B` → `Ⓑ`), yoksa `◆`.
5. En/boy < 0,62 → simge değil.
6. **Yön tuşu:** 3×3 hücrede köşeler %20'den az, dört kol %35'ten fazla doluysa artı
   biçimidir. Bir kol ötekilerden **1,12 kat** parlaksa o yön (`↑ ← → ↓`), değilse `✜`.
7. **Yazılı simge:** Lekenin sıkı kesiti (%15 pay) okunur; olmazsa renkleri ters çevrilmişi,
   olmazsa geniş kesit. Kesit 120/140 piksel yüksekliğe büyütülür, kenar rengiyle dolu
   geniş zemine konur; önce doğru, sonra hızlı düzey; dil düzeltmesi kapalı.
   - `OPTION…` → `OPTIONS`
   - 3 harfli ve `C`/`I` ile başlıyorsa ilk harf atılır.
   - 3–5 harfin içinde `L`/`R` + `1 2 3 I Z 7` aranır.
   - İkinci karakter: `I→1`, `Z→2`, `7→1`, `B→3`. Sonuç `L1 L2 L3 R1 R2 R3` değilse yok.
8. **Dokunmatik yüzey:** en/boy > 1,45 ve lekenin orta satırında en az 4 açık-koyu çizgi → `▦`.
9. En/boy > 1,15 (yazılı kutu ama okunamadı) → simge değil.
10. **Sembol:** İç dairede (yarıçap çarpanı 0,74 / 0,6 / 0,48 denenir) azınlıktaki renk
    16×16 ızgaraya oranlanır, `✕ ○ □ △` şablonlarıyla karşılaştırılır (bir hücre büyütmeli
    iki yönlü örtüşme çarpımı). Kare için köşelerde en az 3 dolu hücre gerekir.
    En iyi puan **0,3**'ü (sıkı kuralda **0,5**'i) geçmezse simge yok.

### 4.5 Simge metni düzeltme

Okunan her satırda (ve birleşmiş satırda yeniden):

- Yuvarlak L3/R3 simgesinin okunuşları düğme adına çevrilir. Yalnız parantezli ya da
  harfli biçimler; düz sayı olduğu gibi kalır.
- `(C1` biçimi L1'dir.
- Yan yana aynı simge teke iner (simgeler ve `L1–R3 OPTIONS TOUCHPAD`).

| Girdi | Çıktı |
|---|---|
| `13) Stand up` | `L3 Stand up` |
| `L3] Stand up` | `L3 Stand up` |
| `(R3 Focus` | `R3 Focus` |
| `We counted 13 crates today.` | `We counted 13 crates today.` |
| `Hold ✕ ✕ to keep the lantern lit` | `Hold ✕ to keep the lantern lit` |
| `Press □ □ □ to climb` | `Press □ to climb` |
| `Use ← → to pick a path` | `Use ← → to pick a path` |
| `Hold L2 L2 to talk to the ferryman` | `Hold L2 to talk to the ferryman` |
| `Tap ✕ ✕ ✕ to row faster` | `Tap ✕ to row faster` |
| `Hold L1 R1 to brace` | `Hold L1 R1 to brace` |

### 4.6 Vision takılması

Vision uzun oyunda arada bir sonsuza dek takılır ve kilit bütün süreci etkiler.

- Okumalar **sırayla** yapılır (altyazı, köşe, telefon, harita aynı kapıdan geçer).
- Kapı en çok **4 sn** beklenir.
  - Kapıyı tutan okuma **8 sn**'den kısa sürüyorsa takılma yoktur, sıra kalabalıktır:
    **bu kare atlanır** ("meşgul" hatası).
  - Daha uzunsa: süren istekler iptal edilir ve okumalar **yedek okuyucuya** geçer.
- **Yedek okuyucu:** Uygulamanın kendisi, pencere açmadan ayrı süreç olarak çalışır.
  Kareyi girişten alır, satırları çıkışa yazar.
  - Oturumun ilk başarılı okumasında o kareyle ısıtılır (yeni süreçte ilk okuma 45 sn'yi
    bulabilir). Isınma en çok **240 sn** beklenir.
  - Her okuma en çok **12 sn** beklenir; dönmezse süreç öldürülür, yenisi ısıtılır.
  - Isınmadan gelen okuma atlanır.
  - Art arda **3** düşüşte yedek bırakılır; son çare uygulama yeniden açılır.
  - Asıl okuma sonunda bitince okumalar asıl okuyucuya döner, yedek ısınmış bekler.
- Yedek yoksa: bundan sonraki okumalar **yalnız işlemcide** yapılır. Kapı 1 sn daha
  beklenir; okuma **45 sn**'den kısa sürüyorsa yalnız kare atlanır, daha uzunsa kapı
  yenilenir ve "takıldı" bildirilir (uygulama hattı yeniden kurar).
- Köşe okuması takılmayı 4–5 sn'de fark eder; takılma bayrağı görülünce hat hemen
  yeniden kurulur.
- Okumalar başlamadan önce okuyucu boş küçük bir görüntüyle ısıtılır (ilk okuma
  saniyelerce sürmesin). Isıtma hiçbir zaman çeviriye gitmez.

### 4.7 Sahne aydınlığı

Her OCR'dan sonra okunan alanın aydınlığı ölçülür: alan 160 × 40'a küçültülür,
y = 0,1…0,9 (0,1 adım) ve x = 0,05…0,95 (0,05 adım) noktalarının parlaklığı
(`0,299 R + 0,587 G + 0,114 B`) alınır, **ortanca / 255** TV'ye "sahne aydınlığı"
olarak gönderilir (akıllı koyuluk için).


### NinoCore'da eksik

- Güven alt sınırı 0,40 (eskisi 0,5).
- Derin okuma, satır parçası birleştirme, simge boşluğu, simge tanıma ve simge metni düzeltme yok.
- Vision takılma yönetimi (sıralı kapı, 4/8/45 sn, işlemciye geçiş, yedek süreç) yok.
- Sahne aydınlığı ölçümü yok.

---

## 5. Satır süzgeçleri (kurallar)

Bu bölüm tek tek kuralları verir. **Hangi sırayla** uygulandıkları §6'dadır.

### 5.1 Harfsiz satır
İçinde **2'den az harf** olan satır atılır (`91 / 200`, saat).

### 5.2 Tuş ipucu
Satır şu kurallardan birine uyarsa ipucudur (altyazı değildir). Satır boşluk, `+` ve
`/` ile parçalara ayrılır, parçaların parantezleri atılır.

- **Düğmeler:** `R1 R2 R3 L1 L2 L3 OPTIONS TOUCHPAD`, `✕ × ⨯ ✖ ○ ◯ ● □ ▢ ◻ ■ △ ▲ ⨂`,
  OCR'ın simge okuyuşları `& ® © @ ⊗ Ⓧ ⓧ`, `L R LZ RZ LI RI L7 R7`, `*`, ve görüntüden
  tanınan `↑ ↓ ← → ✜ ▦ ◆`. Tek başına `X` ve `O` yalnız ipucu kalıbında düğmedir.
- Tamamı büyük harf ve içinde `PHOTO MODE` geçiyor.
- Başta 1–3 tane 1–2 karakterlik kırıntı, ardından noktalamasız BÜYÜK HARFLİ 1–3 sözcük
  (ilki en az 3 harf).
- İlk parça düğme ve düğme olmayan harfli sözcük sayısı ≤ 5.
- Son parça düğme, ≤ 4 sözcük, cümle bitmiyor.
- İlk parça `X`/`O`, 2–4 parça, ikinci parça büyük harfle başlıyor, cümle bitmiyor.
- Fiil (`press hold tap push use mash release double pull click`) ile başlıyor, 2–10
  parça ve ikinci parça düğme / `X` / `O`; ya da ikinci parça `to` ve en az 4 parça.
- Fiil ile başlıyor, en çok 14 parça, içinde düğme var, cümle bitmiyor.
- Zarf (`slowly quickly ouickly gently carefully rapidly repeatedly continuously briefly`)
  ile başlıyor, 3–16 parça, üçüncü parçadan sonra `to` var, cümle bitmiyor.
- En çok 16 parça, güçlü düğme (`R1–R3 L1–L3 TOUCHPAD ✕ ○ ◯ □ △ ▲`) ve `to` var,
  cümle bitmiyor.

| Girdi | İpucu mu |
|---|---|
| `PHOTO MODE L2 + R2` | evet |
| `PHOTO MODE [R1] + [L3]` | evet |
| `PHOTO MODE ■ FILTER` | evet |
| `A e SNACKS` | evet |
| `B : LIE DOWN` | evet |
| `L3 Stand up` (düzeltilmiş `13) Stand up`) | evet |
| `Pass me the R2.` | hayır |
| `FIND SHELTER!` | hayır |
| `I am FREEZING` | hayır |
| `Hey, you found Mira's map.` | hayır |

### 5.3 Yol tarifi
Yalnız yön + mesafeden oluşan satır altyazı değildir (ne çevrilir ne gösterilir).

- Baştaki noktalama/tire/tırnak atlanır. İsteğe bağlı `make a`/`make an`, sonra
  `u-turn`/`uturn`/`turn`/`keep`/`bear`, isteğe bağlı `left`/`right`, isteğe bağlı
  mesafeler (sayı ya da OCR'ın `O`/`o` okuduğu sıfır + `ft mi yd km m`), sonda isteğe
  bağlı `.` ya da `!` → tarif.
- Ya da: yön + `left/right` ile başlıyor, arkasında en az bir mesafe var ve mesafeler
  silinince geriye en çok 2 harf/rakam kalıyor → tarif.

| Girdi | Tarif mi |
|---|---|
| `Turn left`, `Turn Right`, `Keep left`, `Make a U-turn`, `U-Turn Left`, `Turn left 250 ft`, `Keep Right.` | evet |
| `Turn Right 310 ft 355 ft`, `Keep Left 7 ft 12 ft`, `U-Turn Right 8 ft 31 ft` | evet |
| `Turn left past the mill, then stop.`, `Keep walking, the camp is close.`, `Turn it down!` | hayır |

### 5.4 OCR çöpü temizleme (satır içi)
Her sözcük baş noktalama, çekirdek ve son noktalama olarak ayrılır.

- Tek başına `l` ya da `|` (ya da `l'm`, `|'ll`, `l've`, `l'd`) çoğu zaman `I`'dır.
  Yalnız `I` olacaksa ancak sonraki sözcük küçük harfle başlıyorsa ya da kendisi `?`/`!`
  ile bitiyorsa kalır; yoksa kutu kenarı sayılıp atılır. Kesmeli biçimler hep `I'm`, `I'll`… olur.
- Yalnız `? ! . , ; :` işaretlerinden oluşan parça (üç nokta hariç): önceki sözcük
  cümle bitirmiyorsa ona yapışır, yoksa atılır.
- Çekirdekte harf yoksa korunur (`24`, `$500`, `…`).
- Simge (`$ @ # % ^ * _ = | \ ~ < > { } ¢ £ ¥ § © ® ° ± µ ¶ ¤`) ve rakam yoksa korunur.
- Simge yok ve olağan harf-rakam karışımıysa korunur: 1–4 harf + 1–4 rakam (`PS5`, `R2`,
  `MK2`), sayı + ek (`2nd`, `100m`, `4K`, `60fps`, `1980s`, `9.5kg` vb.), `x2`, ondalık,
  saat (`3:00pm`). Tireli adlarda her parça ayrı bakılır (`R2-D2`).
- Değilse: baştaki harf/kesme/tire dizisinde en az 3 harf varsa o kısım kalır
  (`waters2aljd` → `waters`), yoksa sözcük atılır; atılan sözcüğün son noktalaması
  önceki sözcüğe eklenir.
- Satır en az 3 sözcükse ve ilk sözcük tek başına sayı (isteğe bağlı `m km ft yd`
  ve tek noktalama) ve ikinci sözcük büyük harfle başlıyorsa ilk sözcük atılır.

| Girdi | Çıktı |
|---|---|
| `Beyond the frozen pass, Mira ok$7e rode, praying the bridge would still stand.` | `Beyond the frozen pass, Mira rode, praying the bridge would still stand.` |
| `Beyond the frozen pass4xqz O rode, Praying the bridge.` | `Beyond the frozen pass O rode, Praying the bridge.` |
| `She came 7q, at noon.` | `She came, at noon.` |
| `?! Who told you to follow me?` | `Who told you to follow me?` |
| `Who told you to follow me ?!` | `Who told you to follow me?!` |
| `Grab the rope, Tomas. ?!` | `Grab the rope, Tomas.` |
| `Hurry, ?! the captain is waiting.` | `Hurry, the captain is waiting.` |
| `. Grab the rope.` | `Grab the rope.` |
| `\| Grab the rope, Tomas.` | `Grab the rope, Tomas.` |
| `Grab the rope, Tomas. \|` | `Grab the rope, Tomas.` |
| `Drop it. l` | `Drop it.` |
| `l can't see them, Captain Vey.` | `I can't see them, Captain Vey.` |
| `\| can't swim.` | `I can't swim.` |
| `l'm sure, l heard it.` | `I'm sure, I heard it.` |
| `\|'ll wait here.` | `I'll wait here.` |
| `Mara and l've met once.` | `Mara and I've met once.` |
| `What did l do?` | `What did I do?` |
| `Is that you, \|?` | `Is that you, I?` |
| `Not now, l!` | `Not now, I!` |
| `Drop it. l.` | `Drop it.` |
| `7? The trail goes cold here.` | `The trail goes cold here.` |
| `200. Nora and Felix...` | `Nora and Felix...` |
| `41m VESNA: Over there! Find shelter!` | `VESNA: Over there! Find shelter!` |
| `300 riders came` | `300 riders came` |

Değişmeden kalanlar: `Plug in the PS5 cable.`, `Move the R2-D2 toy.`, `That costs $750.`,
`Meet me at 4:30pm.`, `The 3rd tower is 250m away.`, `Runs at 120fps, 8K.`, `Combo x3!`,
`Back in 1999.`, `I won't — hold on…`, `"Mira!" he shouted.`, `Mk3 pistol, 1.2kg.`,
`L2 + R2 Iron Stance`, `Huh?! The lights went out alone!`, `- Now? - Later.`,
`Hold on... what?`, `We... we can't stay.`, `"Go!" she yelled.`, `So, you're Tomas?`,
`... and then it rained.`, `Hold on ... what?`, `You said no!`, `Drop it, you said.`, `Press R to reload.`

### 5.5 Okuma puanı ve "çöp gibi"
- **Puan:** Her sözcüğün harfleri sayılır. Temiz sözcük (çöp temizliğinde değişmiyor,
  büyük/küçük harf düzeni olağan, içinde `[ ] ( )` yok, ünlüsüz değil) harf sayısı kadar
  **artı**, değilse **iki katı eksi** puan.
  - Olağan büyük harf: hepsi büyük, ya da yalnız baştaki büyük, ya da tek iç büyük harf
    ve en az 2 küçük harf (`MacGregor`, `iPhone`).
  - Ünlüsüz: en az 3 harf, hepsi büyük değil, ünlü yok, ve ünlem değil
    (`hm m sh br gr pst pft tsk hrm z pht`; art arda tekrar tek harf sayılır: `Hmm`, `Shh`).
- **Çöp gibi:** kötü harfler × 6 > tüm harfler.

| Karşılaştırma | Sonuç |
|---|---|
| `VESNA: Hold this ridge!` vs `- VESNAiQwürr'k!` | ilki yüksek |
| `We drink at MacGregor's tonight.` | > 0 |
| `S tay the[rnl Behind the wall.` vs `Stay behind the wall.` | ilki düşük |
| `Run to the tower now.` vs `Rnn to the tower now.` | ilki yüksek |
| `Hmm!`, `Shh!`, `Brr!`, `Psst!`, `Mmm!` | > 0 |

### 5.6 Eşya / tabela etiketi
Satır şu durumlarda etikettir:

- `(1/5)` gibi parantezli sayaç taşıyor.
- En az 2 simge sözcüğü var (tuş şeridi).
- 1–6 sözcük, küçük harf yok, harf var ve "1–2 sözcüklü ve `!`/`?` ile biten bağırış"
  değil (`FRESH FISH, BEST PRICE`, `GET YOURS TODAY ONLY!` etiket; `FIND SHELTER!`, `WHY?` değil).
- 1–4 sözcük olmalı (değilse etiket değil), ve:
  - Tek sözcük, tek parça, yalnız harf ve kesme → etiket (`WhatUp`, `Contacts`).
  - En çok 3 sözcük, küçük harf yok, `!`/`?` ile bitmiyor → etiket.
  - Cümle noktalaması (`. , ! ? : ; … "`) varsa etiket değil.
  - Küçük harf yoksa etiket.

| Girdi | Etiket mi |
|---|---|
| `PingMe`, `Gallery`, `LEATHER BOOTS`, `BREAD` | evet |
| `STORE IN CHEST (2/8) □ EQUIP ✕ CLOSE ○` | evet |
| `Fine.`, `FIND SHELTER!`, `TOMAS: ...` | hayır |

### 5.7 İki kenara değen satır
Okunan alanın hem sol hem sağ kenarına (pay **0,015**) değen satır kesiktir, atılır
(açılış yasal uyarısı, kayan yazı). Yalnız bir kenara değen kalır.

### 5.8 Aynı sıradaki parçaları birleştirme (blok öncesi)
Bütün satırların kutusu biliniyorsa, soldan sağa: dikeyde küçük boyun en az **%60**'ı
örtüşen ve yatay boşluğu **0,05**'ten az olan parça aynı satırdır; metinler boşlukla
birleşir, güven en küçüğü olur. Sonuç üstten sıralanır. (Renkli konuşan adı `Brenna:`
cümleden ayrı okunuyordu.)

### 5.9 Dev yazı
Ölçü **karenin tamamına** göredir (satır yüksekliği × alan yüksekliği).

- Satır > **0,13** → atılır.
- Satır > **0,075** ve etiket gibi (≤ 4 sözcük, `. , ! ? …` yok) → atılır.
- Blok > **5** satır ya da blok yüksekliği > **0,26** → bütün blok atılır.
- Yeri bilinmeyen satıra dokunulmaz.
- Atılan dev yazı günlüğe bir kez yazılır (son 32 farklı yazı hatırlanır).

Örnekler. Kutular alan içi orandır; "alt yarı" alanı = sol 0,06, üst 0,56, sağ 0,98, alt 1
(yükseklik 0,44):

| Alan | Satır (üst–alt) | Sonuç |
|---|---|---|
| alt yarı | `You shouldn't have followed me.` (0,60–0,69) + `Nobody ever listens.` (0,70–0,79) | ikisi kalır; blok dev değil |
| alt yarı | `Welcome to Ravenmoor` (0,05–0,35) + `Where are we headed?` (0,80–0,88) | yalnız `Where are we headed?` kalır |
| alt yarı | `We did it! KO` (0,30–0,50) + `What now? 00071000` (0,60–0,80) | **ikisi de kalır** (cümle gibi, 0,13'ü aşmıyor) |
| alt yarı | `Ferry Tickets` (0,60–0,80) | atılır (etiket gibi) |
| alt yarı | `Welcome to the Ashfall Isles, traveler.` (0,10–0,45) | atılır (0,13'ü aşıyor) |
| dar (0,2–0,8 / 0,85–0,95) | `Stay behind me.` (0,2–0,7) | kalır (karede 0,05) |
| tam kare | `Stay behind me.` (0,2–0,7) | atılır |
| alt yarı | kutusuz `No signal here.` | kalır; blok dev değil |
| alt yarı | 7 satır, her biri 0,09 yüksek, 0,12 arayla | blok dev |
| alt yarı | aynı satırların ilk 3'ü | blok dev değil |
| alt yarı | `Top of a poster` (0,05–0,15) + `bottom of a poster` (0,65–0,75) | blok dev |

Etiket gibi: `BAIT AND TACKLE`, `Open 24 Hours`, `CAR WASH`, `COLD DRINKS INSIDE`.
Etiket gibi değil: `What?`, `We made it!`, `Hold on, listen.`, `The tide is coming in fast`.

### 5.10 Altyazı bloğu seçimi
Bütün satırların yeri biliniyorsa:

1. Satırlar üstten sıralanır. Bir satır, son bloğun son satırının hemen altındaysa
   (arada büyük boyun **0,8 katından** az boşluk, üst kenarı ondan aşağıda) ve yatayda
   dar olanın en az **yarısı** kadar örtüşüyorsa o bloğa girer; yoksa yeni blok.
2. Menü bloğu elenir: en az 3 satır ve her satır ≤ 3 sözcük ve cümle bitirmiyor
   (`MAP / HELP / SOCIAL CLUB`).
3. Ortası karenin ortasına **0,12**'den yakın bloklar arasından **en alttaki** seçilir.
4. Ortalanmış blok yoksa en az 3 sözcüklü, menü olmayan en alttaki blok; o da yoksa boş.

Örnekler. Alan = sol 0, üst 0,6, sağ 1, alt 1. Satırlar `metin (sol, üst, sağ)`, boy 0,07:

| Satırlar | Seçilen blok |
|---|---|
| `MAP`, `HELP`, `PROGRESS`, `PLAYER`, `STORY`, `ONLINE`, `SOCIAL CLUB`, `SETTINGS` alt alta solda (sol 0,05, üst 0,05 + 0,1·sıra) + `PHOTO MODE` (0,85, 0,9, 0,97) | boş |
| `The bridge will fall if we wait too long.` (0,25, 0,7, 0,75) + `9` (0,02, 0,7, 0,04) + `PHOTO MODE` (0,85, 0,9, 0,97) | ilk satır; kutu 0,25–0,75 / 0,7–0,77 |
| `Ivo and Sela... neither came back.` (0,3, 0,6, 0,7) + `We have to go.` (0,4, 0,68, 0,6) | iki satır, alt alta |
| `Smuggler: I don't trust this one.` (0,05, 0,8, 0,5) | o satır (ortalı değil ama ≥ 3 sözcük) |
| kutusuz `MAP` + `HELP` | okuma olduğu gibi |

İki kenar (§5.7), aynı alanda: `vex trail and copper is lanterned a morrow fiel gate shun orbit plenk`
(0,0–1,0) → boş; `Brenna, we have to reach the ferry before the tide rolls over the causeway!`
(0,06–0,94) → kalır; `before the tide rolls over the causeway` (0,0–0,7) → kalır.

Okuma hattı içinden (§6): ortada `Let's head back now.` (0,2–0,8 / 0,6–0,7) + sağ altta
`R2 Swing` (0,85–0,98 / 0,9–0,95) → çevrilen yalnız `Let's head back now.`

### 5.11 Kutunun ortalanması
Ortası 0,3–0,7 arasındaki kutu ekranın ortasına göre simetrik genişletilir:
`sol = min(sol, 1 − sağ)`, `sağ = max(sağ, 1 − sol)`. Köşedeki yazıya dokunulmaz.
(Açık zeminde satırın bir ucu okunamayınca çeviri yanda kalıyordu.)


### NinoCore'da eksik

- Var: güven, en az 2 harf (eskisiyle aynı), bölge süzgeci. Fazladan: harf oranı ve arayüz sözcüğü listesi (eskisinde yok).
- Yok: tuş ipucu, yol tarifi, OCR çöpü temizliği, okuma puanı, eşya etiketi, iki kenar, aynı sıra birleştirme, dev yazı/blok, blok seçimi, kutu ortalama.

---

## 6. Her karede süzgeç sırası

Sıra davranıştır; değiştirmeyin. "Telefon oyunu" = havuz öncelikli oyun (GTA 6) ya da
oyun bilinmiyorsa son oturumdaki oyun / çeviri dili havuz öncelikli (ayrıntı ayrı belgede).
"Mesaj kartı açık" = telefon oyununda kart işleyicisi bağlı.

1. **Telefon yeri** (yalnız telefon oyununda): karede telefon aranır (takip dahil).
   Bulunamazsa son **5 000 ms** içinde bulunan yer geçerlidir.
2. **Telefon maskesi:** Telefon kutusunun altı `max(alt, min(alt + 0,15, 0,84))` yapılır
   (çerçeveli son mesajın olduğu karede ekran kısa bulunuyordu; maske altyazının başladığı
   0,84'e inmez). Kutu **0,01** payla, bölgeye giren kısmıyla siyaha boyanır. Sonra iz alınır.
3. **Plan ve OCR** (§3, §4). Okuma hatası boş okuma sayılır ve bildirilir.
4. Harfsiz satırlar atılır (§5.1).
5. **Telefon üstündeki satırlar:** Telefon varsa ortası telefon kutusunun **0,02** payla
   içinde kalan satır atılır.
6. **Mesaj köşesi** (telefon oyununda, kart açık): Kare koordinatında sol ≥ **0,66** ve
   üst ≥ **0,74** olan satırlar altyazıdan çıkarılır. Bunlardan alıcı satırı atılır
   (§14); kart kuralına uyuyorsa kart olarak işlenir ve "son kart" (metin, an) saklanır.
7. **Açık zeminde koyu yazı** (telefon oyununda): satırın kutusunda 6 sıra × %2–98
   (0,03 adım) nokta örneklenir (en az 20 nokta). En koyu %5, ortanca, en parlak %95
   alınır. `ortanca − koyu ≥ 25` ve `ortanca − koyu > 2 × (parlak − ortanca)` ise satır
   telefon balonudur, atılır. (Altyazı koyu sahnede beyaz yazıdır.)
8. **Telefon uygulaması yazıları** atılır (ayrı belge). Görülürlerse ve telefon
   bulunamadıysa telefonun yeri bu yazılardan tahmin edilir.
9. **Telefon açıkken yukarıdaki yazı:** Telefon varsa ya da son 30 sn'de telefonda
   okunan yazı varsa, ortası `max(taban_çizgisi, 0,8)`'in üstünde kalan satır atılır.
10. **Telefonda görülen yazı:** En az 3 sözcüklü satırın anahtarı telefondaki son
    yazılardan birinin içinde geçiyorsa atılır.
11. **Görev çizgisi** (§9): Konuşan adıyla başlayan satır hep kalır. Onun hemen altındaki
    devam satırı da kalır (üstü konuşan satırın üstünden aşağıda ve aradaki boşluk
    `max(0,02, kendi_boyu × 1,5)`'ten az). Ötekiler ancak üst kenarı çizginin üstündeyse kalır.
12. **Eski duran yazı:** Her satırın (anahtarına göre) ilk görüldüğü an tutulur. **9 000 ms**'den
    uzun duran satır, yanında yeni satır varken atılır. Tek başınaysa ya da hepsi eskiyse dokunulmaz.
13. **Dev satırlar** atılır (§5.9).
14. **Orta şart** (telefon oyununda): ortası karenin ortasından **0,12**'den uzak satır atılır
    (tezgâhtaki tabela konuşmaya karışıyordu).
15. **Zincir:** ipucu → yol tarifi → çöp temizliği → eşya etiketi → iki kenar → aynı sıra
    birleştirme → blok seçimi.
16. **Kart için ikinci bakış** (kart açıksa): adım 14 olmadan ve **eşya etiketi süzgeci
    olmadan** aynı zincir kurulur. Sonuç kart ya da arama kartıysa o kullanılır
    (tek sözcüklük gönderen adı `Brian` etiket süzgecinde siliniyordu).
17. **Menü/harita bayrağı** açıksa (köşe okuması kurar, §12) okuma boşaltılır.
18. **Küçük harfle başlayan blok** (kart açıksa): ilk karakter küçük harfse okuma boşalır
    (uygulama açıklaması, solu kesik menü). Altyazı büyük harfle ya da `…` ile başlar.
19. **Mesaj listesi** (kart açıksa) boşaltılır (§14).
20. **Arama kartı** → kart işleyicisine; adı ve an saklanır; okuma boşalır.
    Ya da son arama **6 000 ms** içindeyse ve okuma yalnız arananın adıysa → boşalır.
    Ya da **mesaj kartı** → işleyiciye; okuma boşalır.
    Ya da son kart **6 000 ms** içindeyse ve okuma kartın metnini tekrarlıyorsa → boşalır.
21. **Dev blok** → boşalır (§5.9).
22. **İpuçları çıkışı:** adım 14'ten önceki okumanın çöp temizliğinden geçmiş, ipucu olan
    satırları kare koordinatında ipucu işleyicisine verilir (§13). Her karede.
23. Okuma bilgisi saklanır (kare anı, OCR süresi, ortalama güven).
24. **Kutu:** blok kutusu kareye taşınır ve ortalanır (§5.11).
25. **Sabitleyiciye** verilir (§7): metin satırlar alt alta, iz ve alan içi kutu ile.


### NinoCore'da eksik

- Süzgeç sırası yok; yenisinde yalnız bölge → gürültü → birleştir.
- Telefonla ilgili adımlar (1–2, 5–10, 14, 16–20), görev çizgisi, eski duran yazı (9 sn), menü bayrağı yok.

---

## 7. Sabitleme

Sabitleyici her karede bir okuma alır ve şu tepkilerden birini verir:
**yok**, **çevir(metin)**, **temizle**, **geri getir(ilk metin)**.

### 7.1 Sayılar

| Ad | Değer | Anlamı |
|---|---|---|
| Kararlılık | 2 okuma | Cümle bitirmeyen satır için |
| Benzerlik | 0,85 | Aday sayacı için |
| Temizleme | 800 ms | Bölge bu kadar boş kalırsa (yeri değiştiyse) |
| Yer değişmeden tutma | 4 000 ms | Okuma boş ama yer aynıysa en çok bu kadar |
| Geri gelme | 1 500 ms | Kalkan satır bu sürede dönerse yeniden çevrilmez |
| Yeniden deneme | 1 000 ms | Çevirisi başarısız satır en erken |
| Çöp kararlılığı | 700 ms | Çöp gibi okuma ancak bu kadar aynı kalınca |
| Geçmiş | 5 satır | Geri getirme için |
| Zaten hedef dilde | 0,90 | Çeviri kaynağa bu kadar benziyorsa |

### 7.2 Kurallar (sırayla)

1. Okuma sadeleştirilir. **3 karakterden kısa** okuma boş sayılır: aday silinir.
   - Ekranda satır yoksa → yok.
   - Satırın yeri (son okunduğu karenin izi, satırın kutusunda) değiştiyse "gitti" anı
     not edilir. Gitti anından **800 ms** geçtiyse ya da boşluk **4 000 ms**'yi bulduysa
     → satır geçmişe yazılır, **temizle**. Değilse → yok.
   - İz ya da kutu bilinmiyorsa yer hep "değişti" sayılır.
2. Okuma adaya benziyorsa (0,85) sayaç artar; değilse yeni aday, sayaç 1, an not edilir.
3. **Hazır mı:** Çöp gibiyse sayaç ≥ 2 **ve** aday ≥ 700 ms'dir aynı. Değilse sayaç ≥ 2
   **ya da** satır cümle bitiriyor (ilk karede gider).
4. Okuma ekrandaki satırın **aynısıysa** (§7.3) ya da başına önceki satırdan çöp eklenmiş
   hâliyse (ekrandaki anahtar ≥ 12 karakter, okuma daha uzun ve ekrandakiyle bitiyor)
   → yer güncellenir, yok.
5. Hazır değilse → yok.
6. Ekrandakinin **daha kötü yeniden okumasıysa** (§7.3) → yok (günlüğe bir kez yazılır).
7. Son 1 500 ms içinde kalkan bir satırın aynısıysa → o geçmişten çıkar, ekranda sayılır,
   **geri getir(ilk gönderilen metin)**.
8. Çevirisi az önce başarısız olan satırın aynısıysa ve yeniden deneme anı gelmediyse → yok.
9. Ekrandaki satır geçmişe yazılır; okuma ekrana alınır → **çevir(okuma)**.

Ek: Çeviri başarısız olursa satır "unutulur": yeniden deneme anı = şimdi + 1 000 ms.
Sıfırlamada ekranda satır varsa **temizle**, yoksa **yok**.
Çöp aday gönderilmeden kalkarsa (boş ya da başka okuma geldiyse) günlüğe bir kez yazılır.

### 7.3 Aynı satır mı, yeniden okuma mı

**Aynı altyazı** (`okuma` / `gönderilen`; gönderilen satırları alt alta verilebilir):

1. Okuma gönderilende olmayan bir **anlam işareti** taşıyorsa (§7.4) → farklı.
2. "Temiz sözcükler" = 1 harften uzun, rakamsız sözcükler.
3. Okuma gönderilenden uzun ve gönderilenle başlıyor ya da bitiyorsa → farklı (uzayan yazı).
4. Karakter benzerliği ≥ 0,85 → aynı.
5. Okuma daha kısa ve gönderilenin başı ya da sonu ise → ancak **tam satırları** okunduysa aynı.
6. Okumanın en az 4 sözcüğü varsa ve sözcüklerinin ≥ %85'i gönderilende varsa → aynı.
7. Kısa olan ≥ 6 sözcük ve kısa/uzun ≥ 0,75 ve ortak/uzun ≥ 0,75 → aynı.

**Daha kötü yeniden okuma:** okuma ≥ 5 temiz sözcük, ikisi birbirinin uzaması değil,
anlam işareti eklemiyor; sözcük dizisi benzerliği ≥ 0,65 ya da karakter benzerliği ≥ 0,75;
ve okumanın puanı < gönderilenin puanı + 4.

**Düzeltme / uzama** (TV'nin "yerine koy" bayrağı için): biri ötekinin uzaması, ya da
karakter benzerliği ≥ 0,8, ya da (kısa olan ≥ 5 temiz sözcük ve) sözcük dizisi
benzerliği ≥ 0,65 ya da ortak/uzun ≥ 0,7.

**Uzama:** yeni sözcük dizisi eskiden uzun ve eskiyle başlıyor; ya da eski en az 2 sözcük
ve yeni onunla bitiyor.

| Girdi | Sonuç |
|---|---|
| uzama `We can not stay long.` / `We can not` | evet |
| uzama `We can not` / `We can not stay long.` | hayır |
| uzama aynı yazı | hayır |
| uzama `Then we sail east.` / `Then` | evet |
| uzama `Then we sail east.` / `east` | hayır |
| uzama `Then we sail east.` / `sail east` | evet |
| aynı `we need to climb the ridge` / tek satır `We need to climb the ridge before the snow comes in` | hayır |
| aynı `we need to climb the ridge` / iki satır `We need to climb the ridge` + `before the snow comes in` | evet |

### 7.4 Anlam işareti
Okuma şunlardan birini **eklerse** başka cümledir (düşürmesi OCR kaybıdır, sayılmaz):

- Daha çok olumsuzluk: `not no never nothing nobody none nowhere neither nor cannot`
  ve kesmesiz biçimler (`dont doesnt didnt cant wont isnt arent wasnt werent aint
  couldnt shouldnt wouldnt havent hasnt hadnt mustnt neednt`). Rakam karışmış sözcük
  harfe çevrilip sayılır (`0→o 1→i 3→e 4→a 5→s 7→t 8→b`: `n0t` → `not`). Tek kalan `t`,
  önceki sözcükle bilinen kısaltma oluyorsa olumsuzluktur (`can t`).
- Gönderilende olmayan bir sayı. Aynı konumdaki (ya da eşleşen baş/son kısımdaki) sözcük
  yalnız rakam-harf karışıklığıysa sayılmaz.

### 7.5 Sabitleyici örnekleri

Saat yazılmayan örneklerde saat ilerlemez.

| Akış | Tepkiler |
|---|---|
| `The tide is rising` ×3 | yok, **çevir**, yok |
| `We can not stay long.` / `Wait!` / `Who are you?` / `I know…` / `"Run."` (her biri ×2) | **çevir**, yok |
| `Gtt solkolfege.`, `Go to college.` | yok, **çevir(Go to college.)** |
| `- Vrk) so, we hqve. dmn, I r` ×5 (her biri +100 ms), +700 ms, aynısı | yok ×5, **çevir** |
| `The boat will sink soon` ×2, `The boal will sink soon` ×2 | …, yok, yok |
| `Beyond the frozen pass, Mira ok$7e rode, praying the bridge would still stand.` | **çevir** |
| ardından `Beyond the frozen pass%xqz O rode, Praying the bridge would still stand.` ×2 | yok, yok |
| ardından `Beyond the frozen pass, she rode.` | **çevir** |
| `Look, I only stopped by to ask if there's anythin' you need from me.` → `Look, I stopped by to ask if there anythinl you need, ya.` → ilki → ikincisi | **çevir**, yok, yok, yok |
| ikincisi önce, sonra ilki, sonra ikincisi | **çevir**, **çevir**, yok |
| `24 / 120` ve boş, 20 kez sırayla | hiç çevir yok |
| `We can`, `We can not stay`, `We can not stay long in this cold.` ×2 | …, **çevir**, yok |
| `Hello there` ×2; boş; +799 ms boş; +1 ms boş; boş | yok, yok, **temizle**, yok |
| `Hold the rope` ×2; sonra 3 tur: (10 × [+50 ms boş]), (4 × [+50 ms aynı]) | **çevir**; sonra hep yok |
| `Hold the rope.`; boş; +800 ms boş; +1 500 ms `Hold the rope` ×2; `Hold the rope.` | **çevir**, yok, **temizle**, yok, **geri getir(Hold the rope.)**, yok |
| `Hold the rope.`; boş; +800 ms boş; +1 501 ms `Hold the rope.` | …, **temizle**, **çevir** |
| `Hold the rope.`; +100 `Run!`; +100 `Hold the rope.`; +100 `Run!` | **çevir**, **çevir**, **geri getir**, **geri getir** |
| `Who sent you here?` → +50 ms `Who sent you here, kid?` (ve tersi) | ikisi de **çevir** |
| `I could find the key for you today.` → `I couldn't find the key for you today.` | ikisi de **çevir** |
| `She told me she would leave the village.` → `…would never leave…` | ikisi de **çevir** |
| `Wait for me by the mill at 8.` → `…at 9.` | ikisi de **çevir** |
| `Hold the rope` ×2, unut; 19 × [+50 ms aynı]; +50 ms aynı | yok ×19, **çevir** |
| `Hold the rope` ×2, unut; `Run!` | **çevir(Run!)** hemen |
| sıfırla (boş) / `Hello there` ×2 sonra sıfırla / tekrar sıfırla | yok / **temizle** / yok |
| zaten hedef dilde: `Kullanıcı Değiştir Bildirimler Açık` → aynısı | gönderilmez |
| zaten hedef dilde: `Add user` → `Kullanıcı ekle` | gönderilir |

**Yer değişmeden tutma** (satır kutusu 0,3–0,7 / 0,6–0,85; iz her yerde 120):
- `Hold the rope.` (iz aynı) → **çevir**. Sonra 3 000 ms boyunca her 50 ms'de boş, ama iz
  yalnız satırın dışında değişiyor → hep yok. Sonra satır yeniden okunur → yok.
- Satırın kutusundaki bir noktası +60 değişti: boş → yok; +799 ms → yok; +1 ms → **temizle**.
- İz aynı, boş: +3 999 ms yok, +1 ms **temizle** (en çok 4 sn tutulur).
- İz ya da kutu verilmezse: boş, +800 ms boş → **temizle**.

Ön ek çöpü:
- `VESMA. TRl VESNA: Said you wanted to earn your keep.` /
  `VESNA: Said you wanted to earn your keep.` → ön ek çöpü (ekran değişmez).


### NinoCore'da eksik

- Var: aday sayacı, benzerlik 0,85, uzama ayrımı, bitti olayı, tekrar bayrağı.
- Farklı: 3 kare (eskisi 2 okuma ve cümle sonunda ilk karede); boş kare süresi kare ile.
- Yok: çöp gibi okuma ve 700 ms, sözcük tabanlı aynı altyazı, tam satır kuralı, kötü yeniden okuma, ön ek çöpü, anlam işareti, yer değişmeden tutma, 1,5 sn geri getirme, 1 sn yeniden deneme.

---

## 8. Çeviriye gönderme: bekletme, sıra, geç sonuç

### 8.1 Sayılar

| Ad | Değer |
|---|---|
| Bozuk okuma beklemesi | 800 ms |
| Yarım olabilecek temiz okuma beklemesi | 300 ms |
| Az önce çevrilenin yeniden okuması penceresi | 4 000 ms |
| Sırada bekleyen en çok satır | 2 |
| Geç sonuç sınırı | 2 500 ms |
| Hatırlanan çeviri çifti | 8 |
| Ekrandaki satırın TV süresi | 15 000 ms |
| Kalkmış satırın TV süresi | `min(8 000, 2 000 + 60 × karakter)` |

### 8.2 Okuma türleri
- **Bozuk okuma:** ASCII dışı ve tipografik olmayan karakter var; ya da bir sözcüğün
  içinde iki harf arasında harf olmayan (kesme/tire dışı) karakter; ya da harf-rakam
  bitişik; ya da `a A I o O` dışında tek harflik sözcük; ya da 14 karakterden uzun sözcük.
- **Tam:** Her satır (ilk harfi) büyük harfle başlıyor ve cümle bitiriyor.
- **İlgili:** ortak sözcükler; kısa olan ≤ 1 sözcükse en az 1 ortak; değilse en az 2 ortak
  ve ortak × 2 ≥ kısa.
- **Yeniden okuma (yeni → eski):** anlam işareti eklemiyor ve şunlardan biri:
  aynı sözcük sayısı ve ≥ 4 karakter ve benzerlik ≥ 0,75; ya da aynı sayıda ≥ 2 sözcük,
  farklı sözcükler yarıdan az ve hepsi bozuk; ya da biri bozuksa "ilgili"; ya da yeni
  ≥ 2 sözcük ve eskinin aralıklı alt dizisi; ya da yeni eskinin bitişik bir parçası ve
  (cümle bitirmiyor ya da küçük harfle başlayan daha kısa parça).
- Daha iyi okuma bekleyenin yerine geçerken bekleyende olup yenisinde olmayan **temiz
  satırlar korunur** (alt satıra eklenir).

| Girdi | Sonuç |
|---|---|
| yeniden okuma `Lead the mule back to the` / `Lead the mule back to the stable.` | evet |
| yeniden okuma `You scared me!` / `Oh my word, you scared me!` | hayır |
| yeniden okuma `Head to Harbor` / `Head to Old Harbor.` | evet |
| tam `Hold the rope.` | evet |
| tam `hold the rope` / `Lead the mule back to the` | hayır |
| satır koruma `You did it.` (eski `You did it.` + `I don't care!`) | `You did it.` + `I don't care!` |
| ilgili `Lead the mule` / `Lead the mule back to the stable.` | evet |
| ilgili `And you mind your manners!` / `r ners! fair!` | hayır |

### 8.3 Çevir tepkisi gelince
1. Sırada aynı metinli tam okuma varsa ve aradaki kısalmış kayıtlar onun parçasıysa
   (son temizlemeden sonra kalkmış): parçalar sıradan atılır, tam okuma ekranda sayılır. Bitti.
2. Bekletme kapalıysa → hemen sıraya.
3. Pakette var mı bakılır (önce adlı satır, yoksa konuşan adsız cümle).
4. **Az önce çevrilenin yeniden okuması:** son gönderim 4 000 ms içinde, her satırı
   son gönderilenin bir satırının aynısı/yeniden okuması ve puanı daha iyi değil → yok
   sayılır (paketteki parçaysa da: son temizlemeden sonra gönderildiyse).
5. Paketteyse → hemen sıraya.
6. Bekleme: bozuksa 800 ms, tam değilse 300 ms, tamsa 0 (hemen sıraya).
7. Bekleyen okuma (metin, kutu, başlangıç, süre, puan) saklanır.

### 8.4 Bekleyen varken her kare
- **Yeni çevir geldi:** bekleme = ikisinin büyüğü.
  - Yeni okuma pakette → bekleyen atılır, yeni okuma normal yoldan.
  - Yeni okuma anlam işareti ekliyor ve benziyorsa → bekleyenin yerini alır (eksik satırlar
    korunur), başlangıç aynı kalır; süre dolduysa gönderilir.
  - Biri ötekinin yeniden okumasıysa ve süre dolmadıysa → puanı yüksekse yerine geçer;
    süre baştan başlamaz.
  - Bekleyen bozuktu → atılır.
  - Yeni okuma bozuk ve ilgisiz, süre dolmadı → yok sayılır.
  - Değilse → bekleyen gönderilir, yeni okuma da normal işlenir.
- **Temizle / geri getir:** bekleyen bozuksa atılır, değilse gönderilir.
- **Yok:** okuma ≥ 3 karakter, ilgili ve puanı yüksekse bekleyenin yerine geçer;
  süre dolduysa gönderilir.

### 8.5 Sıraya alma
1. Buzlu zemin hazırlanır (§15).
2. İstek numara alır, ekranda sayılır, "son gönderim" güncellenir.
3. **Taban çizgisi şartı** (§9): kutunun altı çizginin üstündeyse "yerinde değil".
   - Pakette varsa: harf içeren sözcük sayısı **3'ten azsa** gösterilmez; değilse gösterilir.
   - Pakette yoksa: gösterilmez; bozuk değilse havuza önerilir.
4. Pakette varsa **hemen gösterilir** (§8.7).
5. Havuza önerilir.
6. Çeviri sürmüyorsa → çevrilir. Sürüyorsa → sıraya: bu okumanın düzeltmesi olan
   (ve ondan kısa olmayan) eski kayıtlar atılır; sıra 2'yi aşarsa **en eski** atılır.
   Süren çeviri bu okumanın yarımıysa (uzama) süren bırakılır.

### 8.6 Gösterim kuralları
- Aynı anda tek çeviri. Biten çeviriden sonra: oturumu bitmiş ya da 2 500 ms'den uzun
  önce kalkmış bekleyenler atılır, sıradaki başlar.
- Satır zaten hedef dildeyse çevirmene gitmez; ekrandaki eski çeviri (bu satır hâlâ
  ekrandaysa ve ondan yenisi gösterilmediyse) **silinir**. Köşe okuması 15 sn durur.
- Çeviri gelince: oturum değiştiyse ya da istek bırakıldıysa atılır. Kaynağa ≥ 0,90
  benziyorsa gösterilmez (zaten hedef dilde) ve eski çeviri silinir. Daha yeni satır
  gösterildiyse ya da yerine uzamış okuma geldiyse atılır.
- Satır ekranda değil ve 2 500 ms'den uzun önce kalktıysa → gösterilmez.
- Gösterilir: ekrandaysa 15 000 ms, kalktıysa okuma süresi. "Yerine koy" bayrağı:
  son gösterilenin düzeltmesiyse açık.
- **Bırakma:** Süren çeviri, daha yeni satır gösterildiyse; ya da satır 2 500 ms'den uzun
  önce kalktı, ekranda değil ve sırada gösterilebilir yeni satır varsa iptal edilir.
  Ekrandaki satırın çevirisi ne kadar sürerse sürsün iptal edilmez.
- **Hata:** satır ekrandaysa sabitleyici satırı unutur (en erken 1 sn sonra yeniden denenir).
- **Geri getir:** hatırlanan çifti varsa çevirmene gitmeden yeniden gösterilir;
  çevirisi sürüyorsa yeniden ekranda sayılır; hiç yoksa normal yoldan çevrilir.
- **Havuzdan daha iyi çeviri** sonradan gelirse: hatırlanan çift güncellenir; satır hâlâ
  ekrandaysa ve son gösterilen oysa (paketten değilse) TV'de yerine konur.
- Konuşan adı (§10) çeviriye gitmez; gösterirken ayara göre eklenir ya da atılır.

### 8.7 Paket satırı
- Paket sonucu hemen gösterilir; sıradaki bütün bekleyenler atılır.
- Gizlenme kuralı: paketteki çeviri kaynağa **≥ 0,90 benziyor VE kaynakta Türkçe harf
  (`ğışçöüĞİŞÇÖÜ`) varsa** gösterilmez (PS5'in kendi Türkçe ekranı). Aksi hâlde
  (Türkçesi aynı olsa da: `Hey, Lu...`, isim, ünlem) **gösterilir**.

### 8.8 Sıra örnekleri

Saat her karede +50 ms (aksi yazılmadıkça). "TR: x" sahte çeviridir.

| Senaryo | Sonuç |
|---|---|
| Okuma `Hold the rope.` ×2, `Run!` ×2; ilk çeviri beklerken | istenen: `Hold the rope.`, `Run!` |
| `Hold the rope.`, `Run!`; çeviriler sırayla bırakılır | gösterilen: `TR: Hold the rope.`, `TR: Run!` |
| `Hold the rope.`, `Run!`, `Stay low!` | üçü de sırayla gösterilir |
| `Hold the rope.`, `Run!`, `Stay low!`, `Now!` (ilk çeviri sürerken) | istenen: `Hold the rope.`, `Stay low!`, `Now!` (en eski bekleyen atlandı) |
| Üç satır, +2 000 ms sonra çeviriler gelir | üçü gösterilir; süreler: okuma süresi, okuma süresi, 15 000 |
| `Climb up` ×8 kare, `Climb up the wall!` ×2; çeviriler sonra | istenen ikisi; gösterilen yalnız `TR: Climb up the wall!` |
| `Climb up` ×8, `Climb up the wall!` ×2, `Stay low now!` ×2 (çeviri hemen) | gösterilen üçü; yerine koy: hayır, **evet**, hayır |
| `Climb up` ×2, `Climb up the wall!` ×8 | istenen yalnız `Climb up the wall!` |
| `Climb up` ×4 kare → gösterilen yok; +6 kare → `TR: Climb up` | |
| `Hold the rope.`, `Run!`; +2 600 ms sonra çeviriler | gösterilen yalnız `TR: Run!` |
| `Hold the rope.` ×1, boş ×17; çeviri sonra | 1 temizle; gösterilen `TR: Hold the rope.`, süre `2000 + 18×60` |
| aynısı, +2 600 ms sonra çeviri | hiçbir şey gösterilmez |
| 2 kare okunur, hat sıfırlanır, çeviri gelir | gösterilmez |
| `Hold the rope.` ×1, `Run!` ×60 (iptali dinleyen çevirmen) | eski iptal edilir; gösterilen `TR: Run!`, hata yok |
| `Hold the rope.` ×1, `Run!` ×40 ya da ×50 | iptal yok; ikisi de gösterilir |
| `Hold the rope.` ×200 | iptal yok |

Önde bir engel satırı (`Hold the rope.`) çevrilirken sıra davranışı (kare başına +100 ms,
beklemeler 0):

| Sıradaki okumalar | Sonunda istenen |
|---|---|
| `Wait, you crossed the desert on foot? Alone? That's insane.`, sonra kısa hâli `Wait, you crossed the desert on foot? Alone?` | engel, tam, kısa |
| tam, kısa, tam | engel, tam |
| tam, kısa ×18, tam | engel, tam |
| tam, kısa, boş ×12, tam | engel, tam, kısa |
| `Run! Wait here.` → `Run!` | engel, ikisi |
| `Oh my word, you scared me!` → `You scared me!` | engel, ikisi |
| `Stay put until I signal.` → `Stay low!` | engel, ikisi |
| `The ferry leaves in 5 hours.` → `The ferry leaves in 2 hours.` | engel, yalnız düzeltilmiş |
| `The train leaves at 07:15.` → `The train leaves at 07:25.` | engel, yalnız düzeltilmiş |
| `I could find the key for you today.` → `I couldn't …` | engel, yalnız düzeltilmiş |
| `There is a way across.` → `There is no way across.` | engel, yalnız düzeltilmiş |
| `We can not stay...` → `We can not stay long.` | engel, yalnız düzeltilmiş |

Paket parçası (pakette yalnız parça var; tam satır ×4, parça ×4, çeviri yavaş):

| Tam / parça | Sonuç |
|---|---|
| `The lighthouse is ours.` / `ours.` | yalnız tam satır çevrilir ve gösterilir |
| `So he just fell asleep.` / `asleep` | aynı |
| `Hey Ivo, come on, come on!` / `come on!` | aynı |
| `the lighthouse is ours` ×2, `ours` ×6 (çeviri hemen) | istenen yalnız tam; gösterilen `TR: the lighthouse is ours` |
| `Oh my word, you scared me!` → `You scared me!` (pakette) | `Yeni replik` paketten, çevirmene gitmez |
| `The lighthouse is ours.` → boş ×12 → `ours.` (pakette) | paketten |
| `So he just fell asleep.` → `Stay low!` (pakette) | paketten |
| `I have three arrows.` → `I have one arrow.` (pakette) | paketten |
| Paket satırı yavaş çeviriyi beklemez: `Hold the rope.` ×2 (çeviri asılı), `Stay low!` ×2 (pakette `Alçakta kal!`) | gösterilen yalnız `Alçakta kal!`; çeviri sonra gelse de gösterilmez |

Gösterilmeyen yeni satır eski çeviriyi siler (her okuma 3 kare):
- `You doing okay?` → `Uzaktan Oynatma ile oturum açıldı` → olaylar: `İyi misin?`, **temizle**.
- `You doing okay?` → `Okay, sure. Better than waiting herı` → olaylar: `İyi misin?`, `Çeviri`
  (tek bulaşık harf satırı Türkçe yapmaz).

Taban çizgisi (alan tam kare, çizgi 0,845, kare başına +150 ms, 6 kare):

| Satır (üst–alt) | Pakette | Sonuç |
|---|---|---|
| `Choose a base color and pick two patterns.` (0,62–0,655) | yok | gösterilmez, çevrilmez, havuza önerilir |
| `Keep the engine running.` (0,881–0,916) | yok | çevrilir |
| `How bright the compass looks on screen.` (0,62–0,655) | var | paketten gösterilir |
| `Chest.` (0,62–0,655) | var | gösterilmez |
| `Chest.` (0,881–0,916) | var | paketten gösterilir |
| çizgi yok, `Pick a focal flower…` | yok | çevrilir |


### NinoCore'da eksik

- Tamamı yok: bekletme (300/800 ms), en iyi okuma, eksik satır koruma, sıra (2), geç sonuç (2 500 ms), bırakma, okuma süresi, havuzdan sonradan gelen çeviri, paket kısa yolu ve Türkçe harf kuralı, taban çizgisi şartı.

---

## 9. Altyazı yerinin öğrenilmesi

Oyun başına, gösterilen her altyazının kare kutusu (üst, alt) kaydedilir.

- Kayıt şartı: alt > üst, üst ≥ 0, alt ≤ 1, **alt ≥ 0,80** (menü açıklamaları sayılmasın).
- Oyun başına en çok **60** örnek (eskiler düşer). Disk dosyasında saklanır.
- **Şerit:** en az **8** örnek; üst = üstlerin %10'luk dilimi, alt = altların %90'lık dilimi
  (dilim: sıralı listede `round((n−1) × q)` sırası).
- **Görev çizgisi:** şerit yoksa **0,895**. Varsa
  `çizgi = şerit_alt + max(0,012, ortanca_satır_boyu)`; çizgi ≥ 0,97 ise **yok**
  (altyazı en dipte); değilse `max(çizgi, şerit_üst + 0,03, 0,895)` (öğrenilen çizgi
  sınırı yalnız aşağı indirir).
- **Taban çizgisi:** en az **12** örnek; altların ortancası; altların ≥ %70'i ortancaya
  0,03'ten yakın değilse yok; varsa `ortanca − 0,07`.
- **Okuma üstü:** şerit varsa `şerit_üst − 0,05` (§2.2).
- Mac'te oyun anahtarı: havuz öncelikli oyun ise sabit `gta-6`, değilse paketin oyunu,
  yoksa `genel`. Havuz öncelikli oyunda görev çizgisi `min(öğrenilen ?? 0,935, 0,935)`.
  Taban çizgisi yalnız havuz öncelikli oyunda kullanılır.
- Her yeni altyazıda çizgiler yeniden hesaplanıp hatta verilir; şerit ilk öğrenildiğinde
  günlüğe yazılır.

Örnekler: 7 örnek → şerit yok, çizgi 0,895. Hiç örnek → 0,895. 12'den az örnek → taban yok.
Altları dağınık oyun → taban yok.


### NinoCore'da eksik

- Altyazı yerinin oyun başına öğrenilmesi ve diskte saklanması yok.

---

## 10. Konuşan adı ve cümle bölme

### 10.1 Konuşan adı
- Satırın başında en çok 3 sözcük, her biri büyük harfle başlar (harf, kesme, nokta, tire
  içerebilir, rakam yok), ardından isteğe bağlı bir boşluk ve `:` ya da `：`.
- Ad en çok **24** karakter; tek sözcüklü ad başlık listesinde değil (§10.2); gövdede
  harf var; gövde `/` ile başlamıyor.

| Girdi | Ad / gövde |
|---|---|
| `BRENNA: Hold the door.` | `BRENNA` / `Hold the door.` |
| `Ivo: I know a shortcut.` | `Ivo` / `I know a shortcut.` |
| `Mr. Kade：Go away.` | `Mr. Kade` / `Go away.` |
| `OLD MAN : Hm.` | ad `OLD MAN` |
| `BRENNA:We go.` | gövde `We go.` |
| `Brenna:` + yeni satır + `Hold the door.` | gövde `Hold the door.` |
| `08:15 by the old pier.`, `Wait for me at 08:15.`, `HTTPS://example.com`, `Ratio 16:9`, `Tip: the well is dry.`, `Listen to me: stay back!`, `Some Other Name Too: words`, `Maximilianus Wolfensteinberg: Hi.`, `BRENNA:` | ad yok |

**Gösterim:** çeviri kaynağın adıyla başlamıyorsa başa `AD: ` eklenir. Ayar kapalıysa
kaynakta ad olan satır başlarındaki ad atılır (Türkçe başlık kalır).

| Çeviri / kaynak / ayar | Sonuç |
|---|---|
| `Kapıyı tut.` / `BRENNA: Hold the door.` / açık | `BRENNA: Kapıyı tut.` |
| aynı / kapalı | `Gitmeliyiz.` |
| `BRENNA: Kapıyı tut.` / aynı / açık | `BRENNA: Kapıyı tut.` |
| `BRENNA: Evet.` + `IVO: Hayır.` / `BRENNA: Yes.` + `IVO: No.` / kapalı | `Evet.` + `Hayır.` |
| `Hedef: Deniz fenerine ulaş.` / `Objective: Reach the lighthouse.` / kapalı | `Hedef: Deniz fenerine ulaş.` |

Paket önce adlı satırla, bulunmazsa adsız gövdeyle aranır. Çevirmene yalnız gövde gider.

### 10.2 Cümle parçaları (çevirmene giden)
- Satırlar kırpılır; konuşan etiketi ya da tire (`- – —`) ile başlayan satır yeni
  konuşmadır, ötekiler önceki konuşmanın sarmasıdır (boşlukla birleşir).
- Etiket: satır başında, en çok üç sözcüklü ad + `:` + boşluk. Ya tümü büyük harf
  (rakam olabilir) ya da her sözcüğü büyük harfle başlayan. Tek sözcüklü başlıklar ad
  değildir: `note warning tip hint objective objectives quest goal new reward rewards
  location chapter mission task tutorial update info status level controls press hold tap
  remember example question answer result results time listen look wait okay ok well so
  yes no now then and but`.
- Etiket ve tire **çevrilmez**, olduğu gibi kalır.
- Cümle sonu: boşluktan önce (kapanan tırnak/parantez atlanarak) `. ! ? …` ve sonraki
  karakter küçük harf değil ve kısaltma değil. Kısaltmalar: `mr mrs ms dr st jr sr prof mt
  vs etc e.g i.e lt sgt capt gen col` ve tek büyük harf (`J.`).

Örnekler (`+` çevrilir, `=` olduğu gibi):

| Girdi | Parçalar |
|---|---|
| `Let's head` + `home, kid.` | `+Let's head home, kid.` |
| `SELA: Brother, look!` | `=SELA: `, `+Brother, look!` |
| `Brenna: Stay low.` + `Ivo: Right, sister.` | `=Brenna: `, `+Stay low.`, `=\n`, `=Ivo: `, `+Right, sister.` |
| `Old Woman: Who's there?` | `=Old Woman: `, `+Who's there?` |
| `Objective: Find the well.` | `+Objective: Find the well.` |
| `Kid! What was that? Ask Mr. Vale.` | `+Kid!`, `= `, `+What was that?`, `= `, `+Ask Mr. Vale.` |
| `Hold on... who was that?` | `+Hold on... who was that?` |
| `- Run!` + `- Where?` | `=- `, `+Run!`, `=\n`, `=- `, `+Where?` |

**Büyük harf düzeltme:** küçük harfi olmayan, en az 2 harfli, boşluklu cümle cümle
düzenine çevrilir; `I`, cümle başı ve bilinen adlar büyük harfle başlar.
Adlar etiketlerden öğrenilir (çok sözcüklü adın her ≥ 2 harfli sözcüğü ayrı).

| Girdi | Çıktı |
|---|---|
| `THE BRIDGE IS FALLING, SELA. I SEE IT.` | `The bridge is falling, sela. I see it.` |
| aynısı, ad `SELA` biliniyor | `The bridge is falling, Sela.` |
| `RUN, OLD MAN!` (etiketten `OLD MAN` öğrenilmiş) | `Run, Old Man!` |
| `BOY!` | `BOY!` |
| `Already fine.` | `Already fine.` |

### 10.3 Oyun deyimleri (çeviriden önce)
Sözcük sınırlı, büyük/küçük harf duyarsız; cümle başındaki büyük harf korunur.

| Girdi | Çıktı |
|---|---|
| `Haul tail, the roof is sagging!` | `Run fast, the roof is sagging!` |
| `Quick, hit the deck!` | `Quick, lie flat!` |
| `If they spot us, we're toast.` | `If they spot us, we are finished.` |
| `When I nod, waste 'em.` | `When I nod, kill them.` |
| `We stay quiet until I say go loud.` | `We stay quiet until I say start shooting.` |
| `Out of juice again, need a charger!` | `Out of power again, need a charger!` |
| `Radio silences everywhere` | değişmez |
| `Hold your fire!` | değişmez |

Diğer kalıplar: `radio silence` → `no talking`, `hold the fort` → `defend this place`,
`bought the farm` → `died`.


### NinoCore'da eksik

- Cümle bölücü var ama kısaltma listesi eksik (`mt lt sgt capt gen col`, tek harf baş harfi yok); etiket ve tire çevrilmeyen parça olarak ayrılmıyor.
- Konuşan adı ayırma/gösterme, büyük harf düzeltme, ad öğrenme, oyun deyimleri yok.

---

## 11. Ek alanlar

Altyazının yanında sürekli okunan en çok **3** alan (görev metni, oyun içi telefondaki mesaj, bildirim).

- Hazır seçimler:

| Seçim | Üst | Alt | Sol | Sağ |
|---|---|---|---|---|
| Görev (sağ üst) | 0,03 | 0,30 | 0,66 | 0,98 |
| Bildirim (sol alt) | 0,58 | 0,88 | 0,02 | 0,30 |
| Telefon (sağ alt) | 0,50 | 0,95 | 0,72 | 0,98 |

- Her alanın kalıcı kimliği, adı, bölgesi ve açık/kapalı durumu vardır. Okunamayan eski
  kayıtta bölge yoksa görev bölgesi verilir. Kapalı alan okunmaz.
- **Tur:** en çok **1 000 ms**'de bir; önceki tur bitmediyse kare atlanır; ana okumayı
  beklemez. Hiç alan yoksa ve ekranda kutu yoksa tur atılmaz.
- Kaldırılan alanın kutusu TV'den kalkar.
- Her alan: kesilir, iz alınır. İz değişmediyse ve bekleyen aday varsa → aday kararlıdır,
  işlenir. İz değiştiyse OCR (derin değil).
  - OCR hatası boş alan değildir: eski kutu korunur, iz ve aday unutulur.
  - Okumadan aday: ipucu ve çöp temizliği yapılır, "yazı" olmayan satır (en az 2 harf ve
    en az bir sözcükte 2 harf) atılır, satırlar parçalara toplanır (§12.4 parçalama kuralı).
    Kutu kareye taşınır, satır boyu ortanca.
  - Aday anahtarı son okumanınkiyle aynıysa kararlıdır; değilse bekler.
- **İşleme:** anahtar ekrandakiyle aynıysa yalnız yer değiştiyse eski çeviri yeni yere
  gönderilir. Boşsa kutu kalkar. Değilse parçalar önce **yalnız pakette** aranır (havuza
  gitmez, havuza önerilmez), kalanı çevirmene (birlikte çevirebiliyorsa tek istekte).
  Boş çeviri yerine kaynak kullanılır. Her parça kaynağına ≥ 0,90 benziyorsa kutu gösterilmez.
  Çeviri hatası: ekrandaki eski hâline döner, aday yeniden denenir.
- Sıfırlamada her şey unutulur, ekranda kutu varsa hepsi kalkar.

Tur örnekleri (görev alanı; "kare N" aynı N ise iz aynıdır, sahte çeviri `TR: …`):

| Turlar | Sonuç |
|---|---|
| `Find the healer` kare 10; kare 10 | 1. tur gönderim yok; 2. tur `TR: Find the healer`, kutu görev alanının içinde |
| ardından kare 10 iki tur daha | okuma 1 kez, çeviri 1 kez, gönderim 1 kez |
| `Talk to Brenna`, kareler 10, 60, 110, 160, 210 (arka plan kıpırdıyor) | 5 okuma, 1 çeviri, 1 gönderim |
| `Talk to Brenna` ×2 (kare 10), `Meet Brenna at the pier` ×2 (kare 90), boş ×2 (kare 200) | gönderimler: `TR: Talk to Brenna`, `TR: Meet Brenna at the pier`, boş (kutu kalkar) |
| `R2 Swing` ve `23m` ×2 | hiçbir şey gönderilmez |
| `New message` (pakette `Yeni mesaj`) + `Ring me back when you can.` ×2 | `Yeni mesaj` + `TR: Ring me back when you can.`; çevirmene yalnız ikincisi gider |
| aynı yazı yeni yerde | yeniden çevrilmeden yeni yere gönderilir |


### NinoCore'da eksik

- Ek alanlar yok.

---

## 12. Köşeler (Mac)

Ana okumadan ayrı, kendi okuyucusuyla. Bu bölüm Mac uygulamasının kendi kurallarıdır;
çekirdekteki ortak kopya bazı sayılarda farklıdır (not edildi).

### 12.1 Zamanlama ve okunan yerler
- Açık olması için "köşeleri çevir" ayarı açık olmalı ve "ekranı çevir" işi sürmemeli.
- Aralık: menü/harita açıkken **0,6 sn**, değilse **1,5 sn**. Önceki tur 10 sn'den uzun
  sürdüyse bırakılır.
- Yerler:
  1. **Sol üst:** üst 0, alt **0,48**, sol 0, sağ **0,40** (yardım kutusu ekranın ortasına iner).
  2. **Görev şeridi:** görev çizgisi biliniyorsa çizgi – **0,995**, sol **0,08**, sağ **0,92**.
  3. **Menü araması:** üst 0,03, alt 0,95, tam genişlik; **üç turda bir** (~4,5 sn),
     menü/harita son 10 sn'de açıktıysa her turda; kare en çok **1 280** piksel genişliğe
     küçültülür.
- Sol üst ve görev okuyucusunda kenar simgeleri açık; menü okuyucusunda kapalı.
- Her okuma çöp temizliğinden geçer ve kareye taşınır.

### 12.2 Ekran türü
- **Menü ekranı:** satırların tek başına şunlardan en az ikisi: `map brief progress settings
  stats gallery online inventory store help photo studio game journal options wardrobe
  outfits missions show text hide text flip put back rotate inspect examine read`
  (satır başı simge kırıntıları temizlenerek, küçük harfe çevrilerek); ya da satırların
  sözcüklerinde dükkân sözcükleri `speed acceleration handling rating upgrade performance
  respray purchase owned braking armor armour`; ya da tek satırdaki `map`, `brief`, `progress`.

| Okuma | Menü mü |
|---|---|
| `SELA & IVO MAP BRIEF PROGRESS` (tek satır) | evet |
| `ii Map`, `Game`, `Store` | evet |
| `We need a better map.`, `Game on.` | hayır |
| `SPEED`, `ACCELERATION`, `ASPHALT HANDLING` | evet |

- **Harita ekranı** da menüdür (ayrı belge).
- Menü/harita görülünce: **5 sn** "menü açık" bayrağı kurulur (ana okuma altyazı okumaz),
  ipucu çevirileri kalkar.
- Oyun ekrandaki yazılardan tanınır (ayrı belge).

**Menü satırı temizliği:** baştaki harfsiz ya da ≤ 2 karakterlik harf olmayan içerikli
parçalar atılır; ardından büyük harfli sözcük gelen 1–2 harflik küçük harfli parça (ya da
`Il`, `II`) atılır; sondaki harf/rakamsız parçalar atılır.

| Girdi | Çıktı |
|---|---|
| `⊙ Store` | `Store` |
| `0] Photo Studio` | `Photo Studio` |
| `1 Help` | `Help` |
| `i Settings` | `Settings` |
| `ii Map` | `Map` |
| `Go Home` | `Go Home` |
| `i Ayarlar` | `Ayarlar` |
| `Chapter 1` | `Chapter 1` |

**Menü grupları** (bilgi için; Mac'te menüler şu an **çevrilmez**, yalnız tanınır):
kısa satırlar (yükseklik < 0,07, 1–4 harfli sözcük, ≤ 30 karakter, `.`/`?` ile bitmiyor);
önce sola, sonra sağa hizalı olanlar; kenar farkı ≤ **0,012**; en az **3** satır; satırlar
arası boşluk ≤ **0,13**.
- `Map`, `Game`, `Store`, `Help` sola hizalı → bir grup; `GONE FISHING`, `Retry Checkpoint`,
  `Restart Mission` → bir grup.
- Menü satırlarının bilinen Türkçesi (yalnız Türkçe hedefte): `Settings` → `Ayarlar`,
  `CHAPTER 1` → `Bölüm 1`, `Open the hatch` → yok. Liste: map Harita, game Oyun, store
  Mağaza, help Yardım, photo studio Fotoğraf Stüdyosu, settings Ayarlar, options Seçenekler,
  resume/continue Devam Et, quit/exit Çık, quit game Oyundan Çık, back Geri, select Seç,
  save Kaydet, load Yükle, load game Oyun Yükle, new game Yeni Oyun, save game Oyunu Kaydet,
  inventory Envanter, stats İstatistikler, brief Özet, journal Günlük, gallery Galeri,
  online Çevrim İçi, story mode Hikâye Modu, retry checkpoint Son Kayıttan
  Dene, restart mission Görevi Baştan Başlat, restart Yeniden Başlat, skip Atla, replay
  mission Görevi Tekrar Oyna, audio Ses, display Ekran, controls Kontroller, graphics Grafik,
  accessibility Erişilebilirlik, language Dil, credits Jenerik, friends Arkadaşlar,
  messages Mesajlar, contacts Kişiler, phone Telefon, camera Kamera, missions Görevler,
  objectives Hedefler, weapons Silahlar, vehicles Araçlar, apparel Kıyafet, gone fishing
  Balığa Gitti.
- Yerleşim: sola hizalıda en uzun satırın sağına, sağa hizalıda en soldakinin soluna,
  0,03 boşlukla sütun; genişlik `min(0,42, max(0,05, harf × boy × 0,55 × 9/16 + 0,02))`.

### 12.3 Sol üst ipucu kutusu
**Kutu seçimi:**
- Yatay satırlar (gerçek en/boy ile `genişlik × 16/9 > yükseklik × 1,2`), en az 3 harfli.
- Üstten dolaşılır; satır son bloğa ancak aradaki boşluk ortanca boyun **1,8 katından** az
  ve yatayda bloğun genişliğiyle örtüşüyorsa girer.
- En çok sözcüklü blok (sözcük: harf/kesme dizisi, ≥ 2 karakter) seçilir. En az **4** sözcük
  ya da (en az 2 sözcük ve ilk satır harf/rakam/tırnak/parantez olmayan bir işaretle
  başlıyor: `◆ Find the lighthouse`). Yoksa boş.

Örnekler: `BROTHER HALLOWAY` + `WHO KEEPS THE LANTERN` → ikisi; tek `grizzlies` → boş.

**Ek süzgeçler (Mac):**
- Telefon son 3 sn'de görüldüyse telefon kutusuyla (0,02 payla) çakışan satırlar atılır.
- Satırlar arasında BÜYÜK HARFLE `OPTIONAL STORY SIDE COMPLETED ACTIVITIES` başlığı ya da
  `◆`/`♦` ile başlayan en az 2 satır varsa kutu yok sayılır (harita listesi).
- Menü/harita bayrağı açıksa kutu yok sayılır.
- Son 6 sn'de görülen menü satırlarıyla dikeyde (0,02 payla) çakışan satırlar atılır.

### 12.4 Görev şeridi
- Konuşan adıyla başlamayan ve ortası **0,32–0,68** arasındaki satırlar.
- Ekrandaki altyazının yerinde (0,01 payla çakışan) ya da altyazıyla aynı olan satır
  atılır: anahtarı ≥ 6 karakter ve biri ötekini içeriyor ya da sözcüklerinin ≥ %50'si
  altyazıda.

### 12.5 Kararlılık ve çeviri (her yer için)
1. Yazı öncekiyle aynıysa boş sayacı sıfırlanır (görev şeridinde vurgu henüz eklenmediyse
   yeniden denenir, §12.6).
2. Yazı boş ve ekranda çeviri var: boş sayacı artar; **4** okuma (menüde 1) üst üste boş
   olmadan çeviri kalkmaz.
3. Yazı dolu: bir önceki okumayla aynı ya da (≥ 30 karakter ve ≥ 0,8 benzer) değilse
   beklenir (menüde beklenmez).
4. Satırlarından biri zaten hedef dildeyse PS5'in kendi ekranıdır: **15 sn** köşeler
   çevrilmez. Hedef dilde olmayan ama bekleme sırasında görülen yazı unutulur (dönünce yeniden).
5. Sol üst: **küçük harf yoksa** çevrilmez (tabela, afiş); **en az 3** sözcük (≥ 2 harf) yoksa
   çevrilmez.
6. Hafıza: son **40** çeviri; aynı anahtar ya da (≥ 30 karakter ve ≥ 0,8 benzer) varsa
   çevirmene gitmez.
7. Çeviri sırası: sol üst için havuz (biliniyorsa hemen; değilse sunucu süre sınırıyla
   beklenir), sonra cihaz. Görev şeridi yalnız cihazla.
8. Sol üstte ilk satır etiketse ve en az 2 satır varsa: başlık ayrı çevrilir, hedef dilin
   büyük harfiyle başa konur.
9. Gövde ekranı çevir kuralıyla gruplanıp çevrilir (§16).
10. Çeviri sürerken menü açıldıysa sol üst sonucu atılır.

### 12.6 Vurgu rengi (görev şeridi)
Oyun hedefi pembe yazar (`Go to Mira's cabin`). Türkçede aynı sözcük `⟦ ⟧` ile işaretlenir.

- Satırın kutusu en çok 400 × 24'e küçültülür. Bir sütunda **pembe** nokta:
  `R ≥ 90`, `R > B`, `R − G ≥ 40`, `B − G ≥ 15`.
- Pembe sütunların ilki ve sonu (en az 3 sütun) oran olarak alınır. Sözcüklerin yeri harf
  sayısından kestirilir; ortası pembe aralığa (0,03 payla) düşen harfli sözcükler seçilir.
- Bütün satır pembeyse vurgu yok.
- İşaretleme: pembe İngilizce sözcükler önce Türkçe cümlede aranır (isimler aynı kalır);
  bulunmazsa pembenin Türkçesiyle. Kök: her parçanın ilk `min(4, max(2, uzunluk−1))` harfi.
  Kök tutmazsa: Türkçede hedef sondaki fiilden önce gelir; İngilizcedeki pembe sözcük
  sayısı kadar, son sözcükten önceki sözcükler işaretlenir. Yan yana işaretliler tek vurgu.
- Yazı ilk görüldüğünde pembe soluk olabilir; yazı durdukça her turda yeniden aranır.

| Türkçe / pembe Türkçesi / pembe İngilizce | Sonuç |
|---|---|
| `Mira'nın kulübesine git` / `kulübe` | `Mira'nın ⟦kulübesine⟧ git` |
| `Üst kata çık` / `üst kat` | `⟦Üst kata⟧ çık` |
| `Ivo'nun teknesine bin` / `sandal` | `Ivo'nun ⟦teknesine⟧ bin` |
| `Kapıyı kilitle` / `pencere` | `⟦Kapıyı⟧ kilitle` |
| `L2 Brenna ile konuşmak için tuşu basılı tut` / `Brenna` / `Brenna` | `L2 ⟦Brenna⟧ ile konuşmak için tuşu basılı tut` |
| (görüntüde yalnız `cabin` pembe) | pembe sözcükler: `cabin` |

### 12.7 Yerleşim
- **Sol üst (Mac):** koyu buzlu kutu, oyunun kutusunun hemen altında. Satır boyu
  `min(max(boy, 0,026), 0,04) × 0,95`; sağ kenar `max(sağ + 0,01, sol + 0,22)`; başlık varsa
  `BAŞLIK · metin` (baştaki simgeler ve tüm simgeler atılır); satır sayısı sarma kuralıyla
  (harf genişliği boy × 0,5 × 9/16, satırda en az 12 harf); yükseklik `boy × satır × 1,25 + 0,02`;
  üst `min(1 − yükseklik − 0,01, kutu_alt + 0,012)`; sol `sol − 0,006`.
  Zemin `#1c1c24`, yazı `#f2f2f5`, saydamlık 0,62, buzlu, yan balon.
  (Ortak kopyada bu yazı kutusuz ve daha küçüktür: boy ≤ 0,032 × 0,8.)
- **Görev şeridi:** her grubun Türkçesi kendi yerine (ekranı çevir gibi). Görev çevirisi
  ekrandayken ana altyazı TV'de **0,03** yukarı kaldırılır.
- Bütün köşe, ipucu, mesaj, telefon ve harita öğeleri TV'ye tek liste olarak, 120 000 ms
  süreyle, "katman" olarak gönderilir; liste boşsa TV'deki katman temizlenir.


### NinoCore'da eksik

- Köşe okuması, sol üst ipucu kutusu, görev şeridi, menü/harita ekranı tanıma, 5 sn menü bayrağı, PS5 sistem ekranı, köşe hafızası, vurgu rengi yok.

---

## 13. Tuş ipuçları (Mac)

Ana okumanın ipucu çıkışı (§6 adım 22) her karede gelir.

- Görev çizgisinin altındaki ipuçları atılır (o şerit köşe okuyucusunundur).
- **Gezinme sözcükleri çevrilmez:** simgeler atıldıktan sonra yazı tam olarak `back select
  exit close confirm cancel ok accept continue skip zoom rotate scroll navigate change toggle
  view rev buy equip` ise; ya da tuş adı olmayan harfli sözcük sayısı ≤ 2 ise; ya da eşya
  etiketiyse. Yalnız cümle hâlindeki ipuçları çevrilir (`Hold L1 to open the crafting wheel`).
- **Karşılaştırma anahtarı:** küçük harf, harf/rakam dizileri, 1 karakterlikler ve `l1–r3`
  atılmış. Anahtar değişmediyse yeniden çevrilmez (simgenin halkası okumayı oynatır).
- Menü bayrağı açıkken çevrilmez. Bir çeviri sürerken yenisi başlamaz.
- Çeviri: havuz açıksa önce havuz (bilinen ya da süre sınırlı sunucu), sonra cihaz;
  simgeler korunarak (§16).
- **Simgede bölme:** Türkçe ve İngilizce simgelerle aynı sayıda (≥ 2) parçaya ayrılıyorsa
  her parça ayrı öğe olur; parçanın yeri harf sayısından kestirilir (simge ≈ 2 harf).
  Kutu `max(İngilizce_genişlik, Türkçe_harf × boy × 0,42 × 9/16 + 0,01)`; tek sözcüklük
  tuş adının bilinen Türkçesi kullanılır (Türkçe hedefte).
- Simgeler Türkçeden atılır, boş ya da gezinme sözcüğü olanlar düşer.
- **Ortalı sade yazı:** genişlik `min(0,6, harf × boy × 0,5 × 9/16 + 0,02)`, eski ortaya.
- **Üste koyma:** alttan yukarı; TV payı 0,008, boşluk 0,006; Türkçe uzunsa yana en çok
  %60 genişler (sağ yarıda sola, sol yarıda sağa); üstteki öğe çakışmada daha yukarı itilir
  (aynı satırdan bölünen parçalar birbirini itmez); üstte altyazı varsa Türkçe ipucunun
  **altına** konur.
- **Titrememe:** aynı çeviri 0,06'dan yakın yerde yeniden gelirse eski kutu aynen kalır;
  aynı kaynak ya da çeviri 0,04 / 0,06 / 0,06 yakınsa eski sol-üst kalır, sağ büyüyebilir.


### NinoCore'da eksik

- Tuş ipuçlarının çevirisi ve yerleşimi yok.

---

## 14. Mesaj kartı ve arama kartı

Telefon oyununda telefona gelen mesaj kartı (üstte gönderen, altında mesaj) altyazı değildir.

### 14.1 Tanıma
- **Ad:** 2–30 karakter, 1–4 sözcük, her sözcük büyük harf ya da `&` ile başlar, sözcük
  içinde en çok 1 büyük harf (tabela değil), küçük harf var, `. , ! ? : ; … "` yok.
- **Kart:** liste değil; en az 2 satır; ilk satır ad; adın altı ilk gövde satırının üstünden
  0,01'den fazla aşağıda değil. Gövde ≥ 3 sözcükse küçük harf içermeli. Gövde 1–2 sözcükse:
  harf var ve adın da gövdenin de sol kenarı alan içinde ≥ **0,55** (kısa mesaj sağ yarıda).
- **Liste:** en az 3 satır ve (en az 2 ad ya da `...`/`…` ile biten en az 2 satır).
- **Arama:** tam 2 satır, ilki ad; ikinci satır (sondaki `.` `…` boşluk atılarak):

| İkinci satır | Durum (Türkçe, çeviriye gitmez) |
|---|---|
| `calling`, `dialing`, `dialling`, `connecting`, `ringing` | `aranıyor…` |
| `incoming call`, `incoming` | `seni arıyor…` |
| `call ended`, `ended`, `call failed`, `busy`, `no answer`, `unavailable` | `arama bitti` |
| `00:05` gibi süre | boş (konuşma sürüyor, gösterilmez) |
| `We should split the reward now.` | arama değil |

- **Alıcı satırı:** Kartın son satırı (≥ 3 satır varsa) 1–3 büyük harfle başlayan sözcük
  ve (ok `→`/`->` içeriyor ya da tek sözcük) ise atılır (`→ Cal`). İlk satırdan harfsiz
  parçalar (okundu tikleri) atılır.
- **Tekrar:** okumanın (1 harften uzun) sözcüklerinin ≥ %50'si kartta geçiyorsa; kart
  ≤ 2 sözcükse okumanın bütün sözcükleri kartta olmalı.

| Okuma | Sonuç |
|---|---|
| `Donnie` + mesaj | kart, ad `Donnie` |
| `TOMAS: Move.` + `Quick, before the guards turn.` | kart değil |
| `Okay.` + `Let's grab a drink later.` | kart değil |
| tek `Lucia` | kart değil |
| `Chuck's Gun Shop` + mesaj | kart |

### 14.2 Mac'te gösterme
- Telefon son **10 sn**'de görüldüyse, ya da kartın sol kenarı < **0,55** ya da üstü
  < **0,72** ise kart gösterilmez (telefon uygulamasının satırlarıdır); ekrandaki kart
  çevirisi kalkar.
- Gövdenin başındaki tek karakterlik simge kırıntısı (`b Bucked You $50`) atılır.
- Gösterilen mesaja ≥ 0,85 benzeyen okuma kartı değiştirmez.
- Aynı metin iki okumada görülünce çevrilir; havuzda biliniyorsa beklemez.
- Çeviri: havuzda bilinen, sonra süre sınırlı sunucu, sonra cihaz. Simgeler atılır.
- Yerleşim: kartın hemen üstünde açık buzlu kart. Satır boyu `min(ilk_gövde_boyu ?? 0,03,
  0,032) × 0,85`; sol `sol − 0,012`, sağ `min(0,995, max(sağ + 0,012, sol + 0,18))`; metin
  `Ad: Türkçe`; yükseklik `boy × satır × 1,25 + 0,02`; üst `max(0, üst − 0,018 − yükseklik − 0,012)`.
  Zemin `#eef0f5`, yazı `#1c1c1e`, saydamlık 0,72, buzlu, yan balon.
- Kart **3 sn** görülmezse çevirisi kalkar.
- **Arama:** `Ad durum` (ör. `Harbor Cabs aranıyor…`) kartın hemen üstünde, sade, eğik.
  Satır boyu `min(ilk_satır_boyu, 0,032) × 0,8`, yükseklik × 1,3, üst `üst − yükseklik − 0,035`,
  genişlik en az 0,2. Durum boşsa gösterilmez.
- (Ortak kopyada kart çevirisi buzlu değil sade yazıdır; ad ayrı satırdadır.)


### NinoCore'da eksik

- Mesaj kartı, arama kartı, mesaj listesi, alıcı satırı yok.

---

## 15. Buzlu zemin

Her satır sıraya alınırken (kutusu varsa) son kareden üretilir ve TV'ye verilir:

- Kutu x'te **0,04**, y'de **0,035** genişletilir (kare dışına taşmaz).
- En çok **360** piksel genişliğe küçültülür.
- Gauss bulanıklığı, yarıçap `max(8, kutu_yüksekliği_piksel × ölçek × 0,55)`; kenarlar
  uzatılarak bulanıklaştırılır (kararmasın).
- Parlaklık −0,12, doygunluk 1,15, karşıtlık 0,9.
- JPEG kalite **0,55**, base64.


### NinoCore'da eksik

- Buzlu zemin yok; 16 KB mesaj sınırı base64 JPEG'e dar.

---

## 16. Ekranı çevir (köşelerin ve ipuçlarının kullandığı gruplama)

- Satırlar çöp temizliğinden geçer; "yazı" olmayanlar atılır (§11). Üstten sıralanır.
- Bir satır bir gruba katılır: boylar en çok **1,6 kat** farklı, üstteki satırın altından
  büyük boyun **0,8 katından** az aşağıda, yatayda dar olanın en az yarısı örtüşüyor; ve
  iki ayrı sütunu birbirine bağlamıyor (geniş başlık, aynı sıradaki iki sütunun ikisinin de
  üstündeyse). İpucu satırları sütun sınırı sayılmaz.
- En çok **30** grup. Grup kutusu birleşim, satır boyu ortanca.
- **Parçalar:** önceki parça cümle bitirdiyse ya da (≤ 3 sözcük, virgülle bitmiyor ve yeni
  satır büyük harfle başlıyor) yeni parça; değilse devam.
- **Simge koruma:** simgeli parça çevrilirken simgeler `[1]`, `[2]` yer tutucularıyla gider
  ve geri konur; düşen simge başa eklenir. Yalnız simgeden oluşan parça çevrilmez.
  Menü açıklaması (simge + çöp ≥ 2, ya da büyük harfli ≤ 5 parçalı satırın kenarında simge)
  ve fiil ile başlamıyorsa: her yazı parçası ayrı çevrilir, simgeler yerinde kalır, Türkçe
  her sözcüğü büyük harfle başlar. Büyük harfli satırda `GO UP ON TO OF IN MY OK NO BY AT IT`
  dışındaki 2 harflik parçalar simge artığıdır.
- Çevirisi kaynağa (her parça) ≥ 0,90 benzeyen grup gösterilmez.
- Birlikte çevirebilen çevirmende simgesiz parçalar tek istekte gider.
- Ekranı çevir sonucu TV'de `min(60 000, max(12 000, 8 000 + 50 × toplam_harf))` ms kalır.


### NinoCore'da eksik

- Ekranı çevir gruplaması ve simge koruma yok.

---

## 17. TV yığını ve sarma (bilgisayardaki altyazı penceresi)

### 17.1 Yığın
| Ad | Değer |
|---|---|
| Üste çıkma penceresi | 1,5 sn |
| Üstteki satırın tam görünmesi | 1,5 sn |
| Solma | 0,4 sn |
| En kısa görünme | 1,2 sn |
| "Temizle"nin en çok bekletmesi | 5 sn |

- Yeni satır: süre verilmişse `max(1,2, süre)`, yoksa `min(8, 2 + harf × 0,06)`.
  Tutma = `şimdi + min(5, 2 + harf × 0,06)`.
- "Yerine koy" ise ve ekranda satır varsa (paragraf değilse) üsttekiler olduğu gibi kalır.
- Değilse: üst üste açık, ekrandaki satır 1,5 sn'den yeni, ikisi de paragraf değil ve
  aynı satır değilse → ekrandaki **önceki** olur; önceki hâlâ tam görünüyorsa ve farklıysa
  o da **iki önceki** olur. Yoksa üsttekiler silinir.
- **Temizle:** satır okunacak kadar görünmediyse tutma anında kalkar, yoksa hemen.
- Ekrandaki satır kalkınca üsttekiler de kalkar. Görünüm yukarıdan aşağı: iki önceki,
  önceki, şimdiki.
- **Aynı satır:** büyük/küçük harf, noktalama (Arapça işaretler dahil) ve boşluklar yok
  sayılınca aynı; ya da biri ötekini içeriyor (tek sözcüklük satır ancak öteki satırda tam
  sözcük olarak geçerse).

| Karşılaştırma | Aynı mı |
|---|---|
| `Kapıyı aç!` / `kapıyı aç.` | evet |
| `Kapı` / `Kapı daha fazla…` | evet |
| `Evet` / `Hayır` | hayır |
| `أين المخيم؟` / `أين المخيم` | evet |
| `آرثر، انتظر` / `آرثر انتظر` | evet |
| `Kapıyı aç!` / `Kapıyıaç` | evet |
| `Kapıyı a` / `Kapıyı aç!` | evet |
| `No!` / `Not now!` | hayır |

- Ayarlardaki `settings.style.stack` anahtarı (hızlı konuşmada bir önceki satırı yukarıda tutma seçeneği) kapalıysa yeni satır hep eskisinin yerine geçer.

Zamanlı örnekler (saniye; `göster(metin, süre_ms, an)`):

| Adımlar | Sonuç |
|---|---|
| `Kapıyı aç.` 4 000 ms, t=0 | t=3,9: `Kapıyı aç.`; t=4: boş |
| `Evet.` 100 ms, t=0 | t=1,1: dolu; t=1,2: boş (en kısa 1,2 sn) |
| `Evet.` 0 ms, t=0 | t=2,29: dolu; t=2,31: boş (2 + 5 × 0,06) |
| `Birinci` t=0, `İkinci` t=0,5, `Üçüncü` t=1 (8 000 ms) | t=1: `Birinci` (iki önceki), `İkinci` (önceki), `Üçüncü` (şimdiki) |
| ardından `Dördüncü` t=1,5 | t=1,5: `İkinci`, `Üçüncü`, `Dördüncü` |
| üste tutma kapalı: `Birinci` t=0, `İkinci` t=0,5 | t=0,5: `İkinci` |
| `Birinci` t=0, `İkinci` t=2 | t=2: `İkinci` |
| `Birinci` t=0, `İkinci` t=1 | t=2,4 önceki solmuyor; t=2,6 soluyor; t=2,9: yalnız `İkinci`; sonraki değişimler 1 → 2,5 → 2,9 → 9 |
| `Kapı` t=0, `Kapı artık kıpırdamıyor.` t=0,5 | t=0,5: yalnız ikincisi |
| `Birinci` t=0, `Vaktimiz yok` t=0,5, `Buna ayıracak vaktimiz yok, ufaklık.` (yerine koy) t=0,8 | t=0,8: `Birinci` (önceki), son satır (şimdiki) |
| `Birinci` t=0, paragraf `GÖREV` + `• Feneri bul` t=0,5 | t=0,5: yalnız paragraf |
| `Kapıyı aç.` 15 000 ms t=0, temizle t=1 | t=2,5 dolu; t=2,61 boş (2 + 10 × 0,06) |
| `Birinci` t=0, `İkinci` t=1 (15 000 ms), temizle t=4 | t=4 boş, sonraki değişim yok |
| `Birinci` t=0, `İkinci` t=0,5, hepsini kaldır | t=0,5 boş |

### 17.2 Sarma
- Satırda en çok **42** harf, en çok **3** satır, en küçük ölçek **0,75**.
- 42'den kısa ya da zaten satır sonu içeren metin olduğu gibi (ölçek 1).
- Ölçek `max(0,75, 126 / uzunluk)` (en çok 1). Satır başı sığa `⌊42 / ölçek⌋`.
  Satır sayısı `min(3, max(2, ⌈uzunluk / sığa⌉))`.
- Konuşan adı (`BRENNA:` ilk üç sözcükte) sonraki sözcükle birleşik tutulur; ad hep ilk
  satırdadır, satır sonunda tek kalmaz.
- Bölme: en uzun satırı en kısa yapan; eşitlikte uzunluk kareleri toplamı küçük olan.
- Paragraflı (görev paneli) satırlar sarılmaz.

Örnek: `Gitmeliyiz, hemen.` → olduğu gibi, ölçek 1.


### NinoCore'da eksik

- Yığın ve sarma yok (TV ile ortak kural olarak çekirdekte durmalı).

---

## 18. Ölçümler ve görünüm yardımcıları

- **Satır ölçümü:** OCR süresi, çeviri süresi (paketse yok), karenin geldiği andan TV'ye
  gidene kadar geçen süre, güven (yüzde, 0–100 yuvarlanmış). Eksi süreler 0 olur.
  Ekranda dört değer tek satırda, aralarında ` · ` ile: OCR süresi (ms), çeviri süresi (ms), gecikme (ms), güven
  (%). Paketse çeviri süresinin yerinde, çevirinin hazır paketten geldiğini söyleyen kısa bir etiket durur (yeni
  uygulamada bu satırın metin anahtarı henüz yok). Bilinmeyen değer yazılmaz.
- **Yayın penceresi zemini:** yeşil `#00FF00` (varsayılan, okunamayan kayıtta da), siyah,
  mor `#FF00FF`. Düz zeminde altyazı kutusu ya tam koyu ya hiç yok (yüzde > 0 → 1, değilse 0).
- **Yazı tipleri:** Sistem, Modern (Barlow SemiBold/Bold), Dar (Barlow Condensed
  SemiBold/Bold, harf aralığı 0,01 em), Yuvarlak (Nunito SemiBold/Bold). TV sayfasıyla aynı
  OFL dosyaları uygulama paketinin `fonts` klasöründen yalnız bu uygulama için kaydedilir.
- **Günlük:** ilk kare ve ilk yazının oturum başından kaç ms sonra geldiği, her satırın
  akıbeti (paket, çeviri, sırada, atıldı, geç, gösterilmedi). Kararları değiştirmez.

---

### NinoCore'da eksik

- Satır ölçümleri kısmen motor olaylarında; yayın zemini ve yazı tipi kaydı yok.


## NinoCore'da eksik: genel tasarım çakışmaları

Bölüme özel eksikler her bölümün sonundadır.

Yeni çekirdeğin okuma hattı (`Sources/NinoCore/Reading`, `docs/tarif/okuma-hatti.md`) ile
karşılaştırma. **Var olan:** tek OCR çağrısı (doğru düzey, dil düzeltmesi, bölge ilgi alanı),
bölge süzgeci (satır ortası bölgede), basit gürültü süzgeci, satırları boşlukla birleştirme,
kare sayılı sabitleyici, cümle bölücü, başladı/bitti olayı, tekrar ve devam bayrağı.

### Tasarım çakışmaları (önce bunlara karar verilmeli)
- **Saat yok, kare sayısı var.** Eski eşiklerin neredeyse hepsi ms'dir (800, 1 500, 4 000,
  700, 300/800, 2 500, 9 000, 5 000, 6 000…). Ya çekirdeğe dışarıdan verilen bir saat
  eklenmeli ya da her eşik kare hızına göre çevrilmeli. Kare hızı okuma planıyla değiştiği
  için ikincisi kırılgandır.
- **Satırlar tek yazıya boşlukla birleşiyor.** Eski kuralların çoğu satır sınırına ihtiyaç
  duyar: tam satır kuralı (§7.3 adım 5), eksik satırları koruma (§8.2), görev çizgisi
  altındaki devam satırı, konuşan etiketli ikinci satır (§10.2). Olay metni satırları
  korumalı (alt alta).
- **Varsayılanlar farklı:** güven alt sınırı 0,40 (eski 0,5); kararlılık 3 kare (eski 2
  okuma ve cümle sonunda **ilk karede** gönderme); benzerlik anahtarı aynı ama uzama
  kuralı eski hatta "aynı değil"in yalnız bir parçası. Varsayılan bölge 0,10–0,90 / 0,62–0,98
  (eski 0,14–0,86 / 0,62–0,97).
- **Gürültü süzgeci eski hatta yok gibi:** yeni çekirdeğin "harf < boşluk dışı karakterin
  yarısı" ve "bilinen arayüz sözcüğü" (`map`, `options`…) kuralları eskisinde böyle değildir;
  eski hat sözcük çöpünü temizler, satırı atmaz. `I.` gibi tek harflik satırın atılması
  bilinen kayıp olarak kalır.
- **TV mesajında yer yok:** yeni gösterme mesajında kutu, "yerine koy", katman listesi
  (köşe/ipucu/mesaj/telefon/harita öğeleri: zemin, yazı rengi, saydamlık, buzlu, eğik,
  açı, kart, yan balon), buzlu zemin görüntüsü, sahne aydınlığı, altyazıyı yukarı kaldırma
  ve ek alan kutuları yok. **16 KB mesaj sınırı** buzlu zemin JPEG'ine (base64) yetmeyebilir;
  ya sınır büyümeli ya da görüntü ayrı yoldan gitmeli.
- **Olaylar çeviriden bağımsız.** Eski hatta bekletme, sıra, geç sonuç, bırakma, geri getirme
  ve paket kısa yolu okuma hattının içindedir. Yeni çekirdekte bunlar ya motorda ya ayrı bir
  "gönderim" katmanında yeniden kurulmalı.

