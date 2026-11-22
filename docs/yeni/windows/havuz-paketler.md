# Windows: oyun paketleri, bulanık arama, paket güncelleme, içe aktarma ve ortak havuz (tarif)

Bu belge eski Windows uygulamasının (`windows/src/Nino.Core`, `windows/src/Nino.Translation`) oyun paketlerini, OCR'a
dayanıklı paket aramasını, sunucudan paket güncellemesini, kullanıcının çeviri dosyasını içe aktarmasını ve ortak
havuzu (satır gönderme kuyruğu + çeviri havuzu + ekrandan oyun tanıma) nasıl işlettiğini anlatır. Kod yoktur.
Çeviri zinciri, sözlük, önbellek, çevirmenler ve yerel modeller için bkz. `ceviri.md`.

Mac karşılığı: `git show claude/yeni-mac-c9961f:docs/yeni/mac/havuz-paketler.md`. Algoritmalar ortak olduğu için
burada **hepsi baştan sona** yazıldı (Windows yeni kodu da .NET; .NET'e özgü tuzaklar ayrıca işaretlendi). Mac'ten
farklar her bölümün sonunda "Mac'ten farkı" başlığında.

**Birebir aynı kalması gerekenler** (sunucu, paket betiği, öbür platformlar ve eski disk verisiyle ortak): §1 anahtar,
§3.2 bulanık imza, §2.1 ve §3.3 paket dosyası/dizin biçimi, §4 ve §6–§8 sunucu istek/yanıtları, §4.4, §7.1 ve §8.4
(disk dosyası) disk biçimleri. Gerisi davranıştır.

**Veri dosyaları:** uygulama **hiç oyun paketi gömmez**; paketler ortak havuzdan `/v1/packs` ile iner (§2.2, §4).
Testlerin ortak verileri (`golden-vectors.json`, `fuzzy-vectors.json`, `pack-matches.json`, `pack-wrapped.json.gz`,
`pack-bare.json.gz`, `pack-sample.json.gz`) bu tariften bağımsız yazılmış ikinci uygulama olan
`apps/windows/tools/gen-vectors.py` ile kendi kurgusal cümlelerimizden üretilir (çıktı bayt bayt aynı). Aşağıdaki
tablolar bu dosyalardan örnektir; esas olan fikstür dosyasıdır.

---

## 1. Satır anahtarı (16 hex)

Paketlerde ve havuzda İngilizce metin **yoktur**; satır yalnız bu anahtarla bulunur. Sunucu, Mac, Android, iPhone ve
paket hazırlayan Python betiği aynı anahtarı üretir; bir bayt farkı bütün paketleri kullanılmaz kılar.

### 1.1 Sadeleştirme ("canon"), adım adım

1. **Biçim etiketlerini sil:** metinde `<` yoksa bu adım atlanır. Varsa metin **kod noktası** (Unicode skaler) dizisi
   olarak taranır. `<` görülünce ileriye bakılır: `<`'dan sonra en çok **40** kod noktası boyunca ne `<` ne `>` gelmeli,
   ardından `>` gelmeli. Öyleyse `<` … `>` arası (iki uç dahil) **tek boşlukla** değiştirilir ve `>`'den sonra devam
   edilir. Değilse `<` olduğu gibi yazılır ve bir sonraki kod noktasına geçilir (iç içe `<<b>>` → `<` sonra `<b>` etiket
   sayılır → sonuç `< >`). Uzunluk UTF-16 birimiyle değil **kod noktasıyla** sayılır (Python'un
   "`<` + en çok 40 karakter + `>`" kuralıyla aynı). 40 karakterlik iç kabul, 41 karakterlik iç kabul edilmez.
2. **NFKC** normalleştirmesi (tam genişlik harfler, `ﬁ` bağları vb. açılır).
3. **.NET tuzağı — büyük noktalı İ:** küçük harfe çevirmeden **önce** her `İ` (U+0130), `i` + birleşen üst nokta
   (U+0069 U+0307) ile değiştirilir. Neden: .NET'in kültürden bağımsız küçük harf dönüşümü U+0130'u değiştirmez;
   Python ve Swift ise Unicode'un tam eşlemesiyle `i̇` yapar, nokta 5. adımda atılır. Bu adım olmadan `İstanbul`'un
   anahtarı tutmaz.
4. **Küçük harf** (kültürden bağımsız; Türkçe kültürü KULLANILMAZ, yoksa `I` → `ı` olur).
5. **NFD**'ye çevrilir ve kod noktası kod noktası yürünür. Her kod noktasının Unicode genel kategorisine bakılır:
   - **atılır** (yok sayılır): birleşen işaretler — boşluksuz işaret (Mn), boşluklu birleşen işaret (Mc), çevreleyen
     işaret (Me). (Aksanlar, `İ`'nin noktası.)
   - **tutulur**: büyük harf (Lu), küçük harf (Ll), başlık harfi (Lt), niteleyici harf (Lm), diğer harf (Lo), ondalık
     rakam (Nd), harf sayı (Nl), diğer sayı (No).
   - **ayraç**: geri kalan her şey (boşluk, noktalama, simge, denetim karakteri, kesme işareti…).
6. Tutulan kod noktaları yan yana yazılır; arada bir ya da daha çok ayraç geçtiyse ve çıktı boş değilse önce **tek
   boşluk** konur. Böylece baştaki ve sondaki ayraçlar hiç boşluk üretmez, ardışık ayraçlar tek boşluk olur.

**.NET tuzağı — bozuk UTF-16:** metinde eşi olmayan tek başına vekil (surrogate) varsa .NET'in normalleştirmesi hata
fırlatır. O durumda metin kod noktası kod noktası yeniden kurulur (bozuk vekil, .NET'in kod noktası çözücüsünün verdiği
yerine koyma karakteri U+FFFD olur) ve normalleştirme yeniden denenir. Anahtar hesabı hiçbir girdide hata vermemeli.

### 1.2 Anahtar

- canon boşsa anahtar **yok** (satır harf/rakam içermiyor: `...`, boş, `?!`).
- Değilse: canon'un **UTF-8** baytlarının SHA-256 özeti alınır, **ilk 8 bayt** küçük harf hex olarak yazılır (16 hane).
- Bellekte sayı olarak tutulabilir: 16 hex → işaretsiz 64 bit (büyük/küçük harf fark etmez). Sayıya çevirme yalnız
  tam 16 haneli ve geçerli hex için yapılır; değilse "geçersiz anahtar".

### 1.3 Örnekler (`golden-vectors.json`'dan)

| Girdi | canon | anahtar |
|---|---|---|
| `It’s a trap, run!` | `it s a trap run` | `f6e16244fdc9fa7c` |
| `<b><c>DARK LANTERN</c></b> UNLOCKED` | `dark lantern unlocked` | `489f15a9c3746361` |
| `Señor Álvarez… wait.` | `senor alvarez wait` | `48c4ffd6fbadd21c` |
| `␠␠Who␠␠␠left⏎the door open?␠␠` (baş/son 2 boşluk, arada 3 boşluk ve satır sonu) | `who left the door open` | `b3849f092374fe09` |
| `Ｓａｖｅ　ｐｏｉｎｔ ７` | `save point 7` | `df81addeb486990d` |
| `İzmir Harbor` | `izmir harbor` | `1560b05325bb96f4` |
| `Æther straße` | `æther straße` | `0ad660f27190f948` |
| `...` | boş | yok |
| boş metin | boş | yok |
| `MARISOL: Raise the sails!` | `marisol raise the sails` | `74ff0fce48e913a7` |
| `“Fire!” — Duck!` | `fire duck` | `02297fc35c47db47` |
| `ﬁnal boss ﬂoor` | `final boss floor` | `e8e1e8942b5bbc21` |
| `<` + 40 × `x` + `>Gate 3` | `gate 3` | `4b4329ddcf00c763` |
| `<` + 41 × `x` + `>` | 41 × `x` | `3164596df4fdd018` |
| `<<b>>Run` | `run` | `acba25512100f80b` |
| `Naïve café, 2nd floor?!` | `naive cafe 2nd floor` | `c625d0971a3c6821` |
| `Level 99 ★ unlocked` | `level 99 unlocked` | `ea7432b110271324` |

Etiket silme örnekleri (1. adım tek başına; çıktıda boşluklar teklenmemiştir):

| Girdi | Çıktı |
|---|---|
| `a <b> c` | `a   c` (a, boşluk, etiketin yerine boşluk, boşluk, c) |
| `<` + 41 × `x` + `>` | değişmez |
| `<` + 40 × `x` + `>` | tek boşluk |
| `a < b <i> c` | `a < b   c` |
| `<<b>>` | `< >` |

Testlerde sık kullanılan başka anahtarlar (§2.4.2 örnek paketi): `Bring me the map.` → `cdc64f627d78f71f`,
`Who left the lantern on?` → `eacfd20bcc1523a1`, `Captain Ruiz wants you.` → `71c9b3d148f14433`, `Stand back!` →
`c785e7bafcdfb411`.

---

## 2. Paketler

### 2.1 Paket dosyası

Dosya gzip'li ya da düz JSON'dur. **İlk iki bayt `1f 8b` ise** gzip sayılır ve açılır (açılamazsa "paket bozuk");
değilse bayt dizisi doğrudan JSON'dur. (Windows'ta boy denetimi yok; .NET'in gzip çözücüsü başlık bayraklarını
kendisi işler.)

İki biçim kabul edilir:

**Sarılı biçim** (kökte `entries` nesnesi var):
```json
{ "format": 2, "id": "lantern-coast", "title": "Lantern Coast",
  "entries":  { "cdc64f627d78f71f": "Haritayı bana getir." },
  "segments": { "<16 hex>": "<Türkçe>" },
  "fuzzy": { "version": 1, "count": 41234, "mask": "<base64>", "lengths": "<base64>", "blooms": "<base64>" } }
```
- `format` alanı **sayıysa** ve 1 ya da 2 değilse paket reddedilir ("desteklenmeyen biçim"). `format` yoksa ya da sayı
  değilse reddedilmez.
- `id` boş olmayan metinse kimlik odur; değilse dosya adından gelir. `title` boş olmayan metinse başlık odur; değilse
  kimlik.
- `segments` (biçim 2): oyunun ayrıca gösterdiği parçalar, birkaç cümleli satırların tek tek cümleleri ve çevirisi kaynağıyla aynı kalan satırlar. Nesne değilse yok sayılır.
- `fuzzy`: §3.3. Bozuksa paket yine yüklenir, yalnız bulanık imza araması olmaz.

**Düz biçim** (kökte `entries` nesnesi yok): kökün kendisi `{ "<16 hex>": "Türkçe", … }`. Kimlik ve başlık dosya
adından.

Dosya adından ad: dosya adının sonundan önce `.gz`, sonra `.json` (varsa) atılır. `kiyi.json.gz` → `kiyi`,
`x.json` → `x`.

Kayıt okuma (hem `entries` hem `segments` için):
- Değeri metin olmayan kayıt atlanır.
- Anahtar küçük harfe çevrilir; 16 haneli geçerli hex değilse atlanır.
- Geçerli her anahtar "paketin anahtar kümesine" eklenir (Türkçesi boş çıksa da; §3.3 sıralaması buna dayanır).
- Türkçe temizlenir: içinde `<` yoksa yalnız baştan/sondan kırpılır. Varsa §1.1'in etiket kuralıyla etiketler **hiçbir
  şeyle** değiştirilir (boşluk değil), sonra metin boşluklardan bölünüp boş parçalar atılarak tek boşlukla birleştirilir
  ve kırpılır. Örnek: `<b><c>KARANLIK FENER</c></b> AÇILDI` → `KARANLIK FENER AÇILDI`.
- Temiz Türkçe boşsa saklanmaz (ama anahtar kümesinde kalır).
- **`entries` sonunda boşsa paket reddedilir** ("pakette satır yok").
- JSON değilse, kök nesne değilse: reddedilir.

Paketin bellekteki hâli: kimlik, başlık, `entries` sözlüğü (64 bit → Türkçe), `segments` sözlüğü, **bütün geçerli
anahtarların küçükten büyüğe sıralı listesi** (entries ∪ segments, tekrar yok; ikili arama için) ve varsa bulanık dizin.

Test paketleri (`gen-vectors.py` üretir; içerik fikstürde):
- `pack-wrapped.json.gz`: sarılı biçim 1, kimlik `test-game`, başlık `Test Game`, 5 kayıt; biri etiketli Türkçe
  (`<b><c>KARANLIK FENER</c></b> AÇILDI`, okununca etiketsiz), biri anahtar `b3849f092374fe09` → `Kapıyı kim açık bıraktı?`.
- `pack-bare.json.gz`: düz biçim, 2 kayıt (`Light the beacon!` → `İşaret ateşini yak!` ve sarılı paketle **ortak bir
  anahtar**, farklı Türkçeyle); kimlik ve başlık `pack-bare`.
- `pack-sample.json.gz`: biçim 2, kimlik `lantern-coast`, başlık `Lantern Coast`; 56 `entries`, 4 `segments` ve bulanık
  dizin (§3.3); §3.7'deki `pack-matches.json` bununla çalışır.

Reddedilmesi gereken örnekler: `not json`; `1f 8b 08 00` + 30 × `07` (bozuk gzip);
`{"format":3,"entries":{"0123456789abcdef":"x"}}`; `{"bad":"x"}` (düz biçim ama geçerli anahtar yok → entries boş).

### 2.2 Kütüphane (paketlerin birleşimi)

Kaynaklar, okuma sırasıyla:
1. **Uygulamayla gelen paket yoktur** (eski uygulama dokuz paket gömüyordu; yeni uygulama gömmez, §2.6).
2. **Kullanıcı klasörü** `%LOCALAPPDATA%\Nino\packs` (sunucudan `/v1/packs` ile inenler ve içe aktarılanlar buraya):
   klasördeki dosyalar tam yol sırasıyla (sıralı karşılaştırma).

Klasörde yalnız adı `.json.gz` ya da `.json` ile biten dosyalar (büyük/küçük harf **duyarlı**) alınır. Okunamayan
ya da reddedilen dosya sessizce atlanır. Aynı kimlikli paket daha sonra gelirse öncekini listeden çıkarır ve sona
eklenir (sonra okunan dosya öncekini ezer, sırası da sona kayar).

Birleşik sözlük (tek bakışta Türkçe): önce **bütün paketlerin `segments`'i** paket sırasıyla, sonra **bütün paketlerin
`entries`'i** paket sırasıyla yazılır; aynı anahtarda sonraki kazanır. Böylece bir oyunun tam satırı, başka bir oyunun parçasının gerisinde kalmaz.

Bilgi listesi (ayarlarda gösterilir): her paket için kimlik, başlık, `entries` sayısı.

Yükleme tembeldir: ilk sorguda yapılır; uygulama açılışta arka planda bir kez "ısıtır" (ilk altyazı beklemesin).
"Yeniden yükle" her şeyi sıfırlar (kapsam, ayırt edici isabet ve elle seçilen oyunun paketi de unutulur). Paket
güncellemesi bir şey indirince ya da silince kütüphane yeniden yüklenir.

Paketler yalnız **kaynak `en`, hedef `tr` ve paket ayarı (`settings.packs.useGamePacks`) açıkken** kullanılır.

### 2.3 Tam arama ve kapsam

**Kapsam** = son tam eşleşmenin geldiği paket; bulanık arama (§3) yalnız bu pakette yapılır. Hiç tam eşleşme bulunmadıysa bulanık aramaya geçilmez.

Tam arama (bir metnin tamamı):
1. Birleşik sözlük boşsa ya da metnin anahtarı yoksa ya da sözlükte yoksa: sonuç yok.
2. Bulunduysa anahtarı içeren paketler bulunur (her paketin sıralı anahtar listesinde ikili arama).
   - Tek pakette varsa: o paket **ayırt edici isabet** olarak not edilir ve kapsam o paket olur.
   - Birden çok pakette varsa (her oyunda geçen kısa ortak satırlar): kapsam bu paketlerden biri değilse ilkine
     geçer; ayırt edici isabet not edilmez.
3. Türkçe, birleşik sözlükten döner.

**Ayırt edici isabet** okununca silinir; oyun tanıma (art arda aynı paketten gelen satırlar → oynanan oyun o paket) bunu
kullanır. Kapsamın kimliği havuza "oyun ipucu" olarak gider; kapsamın başlığı yapay zekâya **gitmez** (oyun adı oyun
tanımadan gelir; tek ortak satır adı başka oyuna kaydırmasın).

**Elle seçilen oyun:** kullanıcı oyunu seçtiyse arama **yalnız o oyunun paketinde** yapılır (tam ve bulanık), Türkçe de o
paketin kendisinden alınır (önce o paketin `entries`'i, yoksa `segments`'i). Paket = paket listesinde **sondan başa**
bakılarak, kimliği genel paket `pool-genel` olmayan ve başlığının ya da kimliğinin **oyun adı anahtarı** (§2.5) seçilen
adın anahtarıyla aynı olan ilk paket. Paketi yoksa **hiç aranmaz** (tam da bulanık da yok). Elle seçimle bulunan satırda
kapsam ve ayırt edici isabet o pakettir. Seçim değişince kapsam, ayırt edici isabet ve bulunan paket sıfırlanır; seçilen
ad boşsa ya da anahtarı boşsa seçim yok sayılır.

Örnek (kurgusal iki paket, sıra A, B): A = `ember-vale` / `Ember Vale`: `Over here!` → `Buraya!`, `The forge is cold.`
→ `Ocak soğuk.`; B = `iron-pass` / `Iron Pass`: `Over here!` → `Bu tarafa!`, `Steady, boy.` → `Sakin ol oğlum.`.
- Seçim yok: `Over here!` → `Bu tarafa!` (sonraki kazanır).
- Seçim paketi olmayan bir ad: `Over here!`, `The forge is cold.` → yok; bulanık `The forge is co1d.` → yok; kapsam yok;
  ayırt edici isabet yok.
- Seçim `EMBER VALE`: `Over here!` → `Buraya!`; `The forge is cold.` → `Ocak soğuk.`; `Steady, boy.` → yok; kapsam
  `ember-vale`; ayırt edici isabet `ember-vale`.
- Seçim kalkınca: `Steady, boy.` → `Sakin ol oğlum.`.

Kütüphane birleşim örneği: paket klasöründe `a.json.gz` (= pack-bare), `b.json.gz` (= pack-wrapped), `c.json.gz` (bozuk).
Paket başlıkları `a`, `Test Game`; satır sayıları 2, 5. İki paketin ortak anahtarı → sarılı paketin Türkçesi (sonraki
kazandı); `Light the beacon!` → `İşaret ateşini yak!`. Kullanıcı klasörüne `test.json` = `{"format":1,"id":"test-game",
"title":"Test Game 2","entries":{"<ortak anahtar>":"<yeni Türkçe>"}}` konup yeniden yüklenince: başlıklar `a`,
`Test Game 2` (`test.json` tam yol sırasında sonra gelir); ortak anahtar → yeni Türkçe; `b3849f092374fe09` (yalnız eski sarılı pakette) → yok (eski
test-game paketi tamamen ezildi).

### 2.4 Parçalı arama (paket bakışının tamamı)

Okuma hattı bir satır için "paket bakışı" ister. Sıra:

**Aşama** (bir "bulucu" ile çalışır; bulucu = tek metnin Türkçesini döndüren işlev):
1. **Tek satır** olarak dene (aşağıdaki "tek satır" kuralı). Bulunursa sonuç.
2. Metin satır sonlarından (`\r\n` önce `\n`'e çevrilir) bölünür, her satır kırpılır, boşlar atılır. **Birden çok
   satır** varsa her satır "tek satır" olarak aranır:
   - Bulunan satırlar arasına `\n` konarak birleştirilir.
   - Bulunmayan satır **köşe yazısıysa** (aşağıda) atlanır; değilse bu yol başarısız olur.
   - Hepsi bulundu (atlananlar hariç) ve en az bir satır bulunduysa sonuç.
3. **Cümle cümle:** satır cümle parçalarına bölünür (`ceviri.md` §3, altyazı bölücüsü: etiket, tire, ayraç parçaları
   "çevrilmez" işaretli). Çevrilecek parça sayısı **1 ya da daha azsa** bu yol yok. Her çevrilecek parça bulucuyla
   aranır; biri bile bulunmazsa yol yok. Sonuç: çevrilmeyen parçalar aynen, çevrilenler Türkçeleriyle, sırayla birleşir.
4. Hiçbiri: yok.

**Tek satır** kuralı:
1. Satır bölücüyle parçalanır. Baştaki "çevrilmez" parçalar (konuşmacı etiketi, diyalog tiresi) varsa, satır yalnız
   onlardan oluşmuyorsa ve parçalardan hiçbiri `\n` değilse: geri kalan parçaların metinleri birleşip **gövde** olur;
   gövde bulunursa sonuç = baştaki parçalar aynen + gövdenin Türkçesi.
2. Satırın **tamamı** bulunursa sonuç = Türkçesi.
3. **Bozuk etiket** (§2.4.1) çıkarılabiliyorsa gövdesi aranır; bulunursa sonuç = bozuk etiket aynen + Türkçe.
4. Yok.

**Bakışın tamamı:** metin kırpılır, boşsa yok. Aşama önce **yalnız tam aramayla** çalıştırılır. Sonuç yoksa aynı aşama
bir kez daha çalıştırılır; bu kez bulucu "önce tam ara, bulunmazsa en yakını ara (§3)" olur. Aynı metin bir bakışta
birden çok yoldan sorulabileceği için en yakın arama sonuçları o bakış boyunca metne göre hatırlanır (bir metin bir kez
bulanık hesaplanır).

**Köşe yazısı** (altyazıyla aynı bloğa düşen bölge adı, kamera ipucu): boşluklardan bölünmüş sözcük sayısı 1–4 **ve**
(satırda `•` var **ya da** her sözcük büyük harfle başlıyor ve yalnız harf/rakam içeriyor). 4 sözcükten uzun satır `•`
içerse de köşe yazısı değildir (OCR lekesi). Örnekler: `Port Selva`, `Third Person • zoom`, `Old Harbor`, `NRTHGT` →
köşe yazısı; `Wait for me,`, `Hey, Marisol!`, `I left the crates by the old dock with the others• Not that anyone ever
checks` → değil.

#### 2.4.1 Bozuk konuşmacı etiketi

Yalnız paket aramasında tekrar denemek için kullanılır. Satır kod noktası dizisi olarak işlenir.

1. **İşaretli:** 2. kod noktasından (sıra 1) başlayıp en çok 32. sıraya kadar (sıra < min(uzunluk, 33)) `:` ya da `•`
   aranır. Her aday için: o işarete kadarki metin boşluklardan bölünür; son sözcük "ad gibi" (en az **1** harf ve hiç
   küçük harf yok) değilse sıradaki adaya geçilir. Ad gibiyse: işaretten sonra ilk harf ya da sayıya kadar atlanır,
   oradan sona kadar gövde (kırpılmış). Gövdede harf yoksa sonuç **yok** (başka aday denenmez). Etiket = baştan işarete
   kadar (işaret dahil) kırpılmış + bir boşluk.
2. **İşaretsiz:** baştaki harf olmayanlar atlanır. En çok 3 kez: o konumdan boşluğa kadar sözcük alınır; sözcük metnin
   sonuna kadar gidiyorsa, büyük harfle başlamıyorsa ya da "ad gibi" değilse (en az **2** harf, küçük harf yok) durulur.
   Sözcükten sonraki boşluklar atlanır; şimdi bakılan yerde büyük harf ve hemen ardından küçük harf varsa: etiket =
   baştan buraya kadar kırpılmış + boşluk, gövde = buradan sona kırpılmış.
3. Hiçbiri: yok.

Ortak test vektörleri (`fuzzy-vectors.json` → `looseLabels`):

| Girdi | Etiket | Gövde |
|---|---|---|
| `-MARISOL: Raise the sails` | `-MARISOL: ` | `Raise the sails` |
| `K]: Is anyone on deck?` | `K]: ` | `Is anyone on deck?` |
| `ii TOMAS: easy now` | `ii TOMAS: ` | `easy now` |
| `· rq„.. ODALYS: As I said, no` | `· rq„.. ODALYS: ` | `As I said, no` |
| `BARTOLO Where is the cargo` | `BARTOLO ` | `Where is the cargo` |
| `O'HARA Leave it here.` | `O'HARA ` | `Leave it here.` |
| `He said: wait` | yok | yok |
| `İNA DOCKHAND• Any news?` | `İNA DOCKHAND• ` | `Any news?` |
| `-, • VERA: all hands` | `-, • VERA: ` | `all hands` |
| `Pull the rope!` | yok | yok |
| `OK Fine` | `OK ` | `Fine` |
| `CAPTAIN: ...` | yok | yok |

#### 2.4.2 Parçalı arama örnekleri (yalnız tam arama; örnek paket: `Bring me the map.`→`Haritayı bana getir.`, `Who left the lantern on?`→`Feneri kim açık bıraktı?`, `Captain Ruiz wants you.`→`Kaptan Ruiz seni istiyor.`, `Stand back!`→`Geri dur!`)

| Ekranda | Sonuç |
|---|---|
| `BRING ME THE MAP!!` | `Haritayı bana getir.` |
| `␠␠Who␠␠␠left⏎the lantern on?␠␠` | `Feneri kim açık bıraktı?` |
| `Hand me the rope!` / boş | yok |
| `RUIZ: Captain Ruiz wants you.` | `RUIZ: Kaptan Ruiz seni istiyor.` |
| `Tomas: Bring me the map!` | `Tomas: Haritayı bana getir.` |
| `TOMAS: Hand me the rope!` | yok |
| `TOMAS: Bring me the map!⏎VERA: Who left the lantern on?` | `TOMAS: Haritayı bana getir.⏎VERA: Feneri kim açık bıraktı?` |
| `- Bring me the map!⏎- Who left the lantern on?` | `- Haritayı bana getir.⏎- Feneri kim açık bıraktı?` |
| `Bring me the map!⏎Who sent you?` | yok (bir satır eksik) |
| `Port Selva⏎Who left the lantern on?` | `Feneri kim açık bıraktı?` |
| `Bring me the map!⏎Third Person • zoom` | `Haritayı bana getir.` |
| `Bring me the map!⏎Old Harbor⏎Who left the lantern on?` | `Haritayı bana getir.⏎Feneri kim açık bıraktı?` |
| `Port Selva⏎Old Harbor` | yok |
| `Bring me the map!⏎who are you` | yok |
| `I left the crates by the old dock with the others• Not that anyone ever checks⏎Who left the lantern on?` | yok |
| `TOMAS: Bring me the map! Who left the lantern on?` | `TOMAS: Haritayı bana getir. Feneri kim açık bıraktı?` |
| `Bring me the map! Stand back!` | `Haritayı bana getir. Geri dur!` |
| `Bring me the map! Who sent you?` | yok |
| `-MARISOL: Captain Ruiz wants you.` | `- MARISOL: Kaptan Ruiz seni istiyor.` (bölücü tireyi `- ` yapar) |
| `- MARISOL: Captain Ruiz wants you.` | `- MARISOL: Kaptan Ruiz seni istiyor.` |
| `K]: Bring me the map!` | `K]: Haritayı bana getir.` |
| `ii TOMAS: Who left the lantern on?` | `ii TOMAS: Feneri kim açık bıraktı?` |
| `BARTOLO Who left the lantern on?` | `BARTOLO Feneri kim açık bıraktı?` |
| `He said: hand me the rope!` | yok |

- Tam satır parçalardan önce gelir: pakette `Bring me the map! Stand back!` → `Haritayı getir ve geri dur!` de varsa,
  `Bring me the map! Stand back!` → `Haritayı getir ve geri dur!`.
- Bulanık yalnız tam parçalar tutmazsa: en yakın arayan işlev yalnız `Who left the lantem on?` için `Feneri kim açık
  bıraktı?` verirse, `TOMAS: Bring me the map! Who left the lantem on?` → `TOMAS: Haritayı bana getir. Feneri kim açık
  bıraktı?`, ve en yakın işlevine `Bring me the map!` hiç sorulmaz. `BRING ME THE MAP!!` için en yakın işlev her şeye
  `x` dese de sonuç `Haritayı bana getir.`.

### 2.5 Oyun adı anahtarı

Elle seçilen oyunu paketle eşlemek ve oyun adlarını karşılaştırmak için (sunucudaki oyun adı anahtarıyla aynı):
1. Boşsa boş.
2. `™ ® ©` boşluk olur (NFKD `™`'yi `TM` yapmasın diye önce).
3. NFKD, sonra kültürden bağımsız küçük harf.
4. Kod noktası kod noktası: birleşen işaretler (Mn, Mc, Me) atılır; `'` (U+0027), `’` (U+2019), `` ` `` (U+0060)
   atılır; `ı` → `i`; `&` → ` and ` (önceki "boşluk" sayılır); harf/rakam olmayan her şey boşluk; harf ile rakam
   bitişikse araya boşluk (`gta6` → `gta 6`, `6gta` → `6 gta`).
5. Boşluktan bölünür; Roma rakamı sözcükleri sayıya: `ii`→2 … `xvi`→16 (`v`→5, `x`→10).
6. Birden çok sözcük varsa ve ilki `the` ise atılır.
7. Kısaltmalar (sözcük sınırıyla, sırayla): `grand theft auto`→`gta`, `call of duty`→`cod`, `red dead redemption`→
   `rdr`, `ea sports fc`→`fc`, `ea sports`→(silinir).
8. Tek boşlukla birleştir, en çok 80 karakter, kırp.

`Grand Theft Auto VI` → `gta 6`; `GTA6` → `gta 6`; `ELDEN RING` → `elden ring`.

### 2.6 Uygulamayla gelen paket yok

Eski uygulama dokuz oyunun paketini uygulamanın içinde taşıyordu. Yeni uygulama **hiçbir paketi gömmez**; kütüphane
yalnız kullanıcı paket klasörünü okur. Bir oyunun paketi ortak havuzdaki çevirilerden sunucuda hazırlanır ve
`/v1/packs` ile iner (§4; adres `NINO_PACKS_URL` ya da derlemedeki `NinoPacksUrl` ile verilir, verilmezse indirme
kapalıdır); kullanıcı kendi dosyasını da içe aktarabilir (§5). Uygulama ilk açıldığında paket listesi
boştur; ayarlardaki paket listesi ve oyun tanıma bu durumda boş/tanınmamış davranır. Paket bulunmayınca satır çeviri
zincirine gider (ceviri.md).

### Mac'ten farkı (§1–§2)
- gzip'te "boy ≥ 18" ve son boy alanı denetimi yok; .NET çözücüsü yapar. Sonuç aynı.
- Mac'te uygulamayla gelen paketler vardı; Windows'ta yok (§2.6).
- Windows'ta üçüncü "içe aktarılanlar" klasörü yok; içe aktarılan paket de kullanıcı paket klasörüne yazılır (§5).
- Dosya uzantısı denetimi büyük/küçük harf duyarlı (`.JSON` paket olarak okunmaz).

---

## 3. Bulanık eşleme (OCR hatalarına dayanıklı arama)

"En yakını ara" isteği yalnız **kapsam paketinde** (ya da elle seçilen oyunun paketinde) çalışır; kapsam yoksa sonuç yok.
Türkçe: elle seçimde o paketin kendisinden (`entries`, yoksa `segments`), değilse birleşik sözlükten. İki yol sırayla:

1. **Tek düzeltme** (§3.1) sonuç verirse o.
2. Değilse paketin bulanık dizini varsa **Bloom benzerliği** (§3.2–§3.4); bulunan anahtarın Türkçesi.

### 3.1 Tek düzeltme

canon (§1.1) hesaplanır. Kod noktası sayısı **6–48** arası değilse bu yol yok. Aksi hâlde satırın tek bir OCR düzeltmesiyle elde edilebileceği bütün canon hâlleri üretilir (her konum i = 0 … n−1 için):
- **Karıştırılan dizi değişimi** (okunan → asıl), bu sırayla: `rn→m, m→rn, cl→d, d→cl, vv→w, ri→n, n→ri, li→h, l→i,
  i→l, 1→l, 1→i, 0→o, 5→s, j→i, c→e, e→c, a→o, o→a, h→b, b→h, f→t, t→f, u→v, v→u, y→v, v→y, q→g, g→q`. i'den başlayan
  kod noktaları okunan diziyle birebir aynıysa (diziler ASCII) o kısım asılla değiştirilmiş hâl eklenir.
- **Bir kod noktası düşer** (harf ya da boşluk).
- **Sözcük ikiye bölünür:** i > 0 ve i'deki de i−1'deki de boşluk değilse araya boşluk konmuş hâl (`cant` → `can t`).

Eklenmez: boş, boşlukla başlayan ya da biten, içinde çift boşluk olan. Kümeden canon'un kendisi çıkarılır (tekrar yok).
Hâller sıralı (bayt düzeni) dolaşılır. Her hâlin anahtarı **kapsam paketinin anahtar listesinde** varsa ve Türkçesi
bulunuyorsa aday olur. Adayların **hepsi aynı Türkçeye** çıkıyorsa o Türkçe; iki farklı Türkçe varsa sonuç yok.

### 3.2 Katlama ve imza

**Katlama:** canon'un kod noktalarından boşluklar atılır; şunlar değiştirilir: `l 1 ı j → i`, `0 → o`, `5 → s`,
`æ → a`, `ø → o`, `œ → o`, `ß → s`. Sonuç bir kod noktası dizisidir.

**Uzunluk:** L = min(katlanmış kod noktası sayısı, 255). Katlanmış dizi **16**'dan kısaysa imza yok, bulanık arama yok.

**Bit sayısı:** 64'ten başla; bit < 256 ve L × 3 > bit oldukça iki katına çıkar. Sonuç 64, 128 ya da 256.
(L ≤ 21 → 64; 22–42 → 128; ≥ 43 → 256.)

**Üçlü özetleri:** katlanmış dizinin her ardışık 3 kod noktası için FNV-1a 64 bit: başlangıç `0xcbf29ce484222325`, her
bayt için önce özet XOR bayt, sonra özet × `0x100000001b3` (64 bit taşmalı). Baytlar üç kod noktasının **UTF-8**
kodlaması art arda (ilk, ikinci, üçüncü). Aynı özet bir kez sayılır (küme).

**Bloom:** bit/64 adet 64 bitlik sözcük, hepsi 0. Her özet için b = özet & (bit − 1); `sözcük[b >> 6]`'nın `(b & 63)`.
biti 1 yapılır.

**Bayt dizisi (paket dizini ve test vektörü için):** sözcükler sırayla, her biri **küçük sonlu** (little-endian)
8 bayt. Uzunluk = L, bayt sayısı = bit/8.

Ortak test vektörleri (`fuzzy-vectors.json` → `signatures`; bloom küçük harf hex):

| Girdi | Katlanmış | Bozuk mu (§3.4) | L | Bit | Bloom (hex) |
|---|---|---|---|---|---|
| `The lighthouse keeper said the storm would pass before the morning tide.` | `theiighthousekeepersaidthestormwouidpassbeforethemorningtide` | hayır | 60 | 256 | `82240500402010400001008c8c02409580088514042400080880803072710800` |
| `MARISOL: The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.` | `marisoitheiighthousekeepersaidthestormwouidpassbeforethemorningtide` | evet | 67 | 256 | `82640d00402810400001008c8c02409580088514042400080880803472730800` |
| `Hand me the brass compass.` | `handmethebrasscompass` | hayır | 21 | 64 | `5102107c40200018` |
| `Ahoy, the n0rth pier is fIooded!` | `ahoythenorthpierisfiooded` | evet | 25 | 128 | `0200008328220e801021200020000114` |
| `We sail at first light.` | `wesaiiatfirstiight` | hayır | 18 | 64 | `4c0425050c400200` |
| `DOCKHAND: Ropes are•tight, captain.` | `dockhandropesaretightcaptain` | evet | 28 | 128 | `f9808a24004020281922100900100000` |
| `Café au lait for the whole crew.` | `cafeauiaitforthewhoiecrew` | evet | 25 | 128 | `2280018004c04b008000062004000910` |
| `Ｌｏｗ ｔｉｄｅ ａｔ １０ ｐｍ` | `iowtideatiopm` | evet | yok | yok | yok |
| `Keep the l1ght burning 0n the c1iffs tonight!` | `keeptheiightburningontheciiffstonight` | evet | 37 | 128 | `0000a58540a005480918806042110019` |
| 300 × `z` | 300 × `z` | evet | 255 | 256 | `0000000000000000000000000000000000000020000000000000000000000000` |
| `tiny line` | `tinyiine` | hayır | yok | yok | yok |
| `Check the u hold below deck.` | `checktheuhoidbeiowdeck` | evet | 22 | 128 | `2010402200884c006802000000000a30` |
| `The harbormastership is vacant again.` | `theharbormastershipisvacantagain` | evet | 32 | 128 | `8908010032405000204020480081089f` |
| `ægir øster straße œuvre jjjj` | `agirosterstraseouvreiiii` | evet | 24 | 128 | `010000086001006001008424a0100183` |
| `Short of rope.` | `shortofrope` | hayır | yok | yok | yok |
| `Down the stairs… then left — quickly!` | `downthestairsthenieftquickiy` | hayır | 28 | 128 | `c0046080088084620101140200008092` |

(300 × `z` satırının katlanmış hâli testte 300 kod noktasıdır, uzunluk 255'e kırpılır; tek bir farklı üçlü olduğu için
tek bit doludur.)

### 3.3 Paketteki bulanık dizin (`fuzzy`)

Paket betiği üretir; Windows yalnız okur.
- `version` 1 olmalı; `count` = paketin **bütün geçerli anahtarlarının** sayısı (entries ∪ segments, Türkçesi boş
  kalanlar dahil; §2.1) olmalı.
- `mask` (base64): bayt sayısı `(count + 7) / 8` (tam sayı bölme) olmalı. i. anahtar (anahtarlar küçükten büyüğe
  sıralı) imzalıysa `mask[i >> 3]`'ün `(i & 7)`. biti (düşük bitten başlayarak) 1'dir.
- `lengths` (base64): imzalı her anahtar için 1 bayt L, imzalı anahtarların sırasıyla.
- `blooms` (base64): imzalı anahtarların Bloom baytları art arda; her biri Bits(L)/8 bayt.
- Tutarsızlık (sayı, boy, toplam bayt tutmuyor, alan eksik, base64 bozuk) → dizin yok sayılır.

Okununca kayıtlar (L, anahtar, bayt konumu) **önce L'ye, eşitse anahtara göre** sıralanır; Bloom sözcükleri bu sırayla
ardışık bir diziye konur. Her kaydın 1 bit sayısı önceden hesaplanır. "L'si n olan ilk kayıt" tablosu (n = 0 … 256)
tutulur, böylece bir uzunluk aralığı hızla taranır.

### 3.4 Benzerlik, eşikler, OCR izi

**Kapsama** (iki Bloom aynı bit sayısında; ortak = AND'in 1 bit sayısı, s = sorgunun 1 bit sayısı, a = adayın):
- s = 0 ya da a = 0 → (0, 0). Doluluk ds = s/bit, da = a/bit; biri ≥ 1 ise (0, 0).
- sorgunun kapsanması = 100 × ((ortak/s − da) / (1 − da)); adayın kapsanması = 100 × ((ortak/a − ds) / (1 − ds)).
- **Benzerlik** = ikisinin küçüğü. (Rastlantıyla dolan bitler çıkarıldığı için 0'ın altına da inebilir.)

Ortak test vektörleri (`similarities`, 9 basamak hassasiyetle):

| Sorgu | Aday | Bit | Benzerlik |
|---|---|---|---|
| `The lighthouse keeper said the storm would pass before the morning tide.` | `MARISOL: The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.` | 256 | 88.38896952104498 |
| `The lighthouse keeper said the storm would pass before the morning tide.` | `Hand me the brass compass.` | 64 | -5.494505494505502 |
| `Hand me the brasscompass.` | `Hand me the brass compass.` | 64 | 100.0 |
| `DOCKHAND: Ropes are•tight, captain.` | `Ropes are tight, captain.` | 64 | 58.44155844155844 |
| `Who left the lantern on?` | `Who left the lanterns on?` | 64 | 84.31372549019608 |
| `We sail at first light.` | `We sail at last light.` | 64 | 52.662721893491124 |

**OCR izi ("bozuk satır")**, satırın ham metnine bakılır; şunlardan biri varsa bozuk:
- 127'den büyük bir kod noktası, şu tipografik işaretler hariç: `’ ‘ “ ” — – …`.
- Sözcükler (boşluktan bölünmüş, her birinin baş ve sonundaki şu işaretler atılmış: `. , ! ? ; : ' " ( ) [ ] - … “ ” ’ ‘`)
  içinde:
  - iki yanı harf olan, kendisi harf olmayan ve `'`, `’`, `-` olmayan bir karakter (`are•getting`);
  - harf ile rakam bitişik (`l1ght`, `0n`);
  - tek kod noktalı sözcük harfse ve `a A I o O` değilse (`u`);
  - 14 kod noktasından uzun sözcük.
- "Rakam": BMP'de ve ondalık değeri olan karakter.

**Kabul eşiği** (L'ye ve bozukluğa göre; "L < sınır" olan ilk satır):
- temiz: L < 24 → 90; L < 256 → 80.
- bozuk: L < 24 → 70; L < 40 → 60; değilse 55.
- Ayırma payı **5**. Taban = eşik − 5.

(Test verisindeki `thresholds`: `clean [[24,90],[256,80]]`, `damaged [[24,70],[40,60],[256,55]]`, `margin 5`,
`minLength 16`.)

### 3.5 Arama (dizinde en yakın anahtar)

1. Sorgu katlanır; 16'dan kısaysa ya da dizin boşsa yok. L, eşik (bozukluğa göre) hesaplanır. Sorgunun üçlü özetleri
   bir kez alınır; 64, 128 ve 256 bitlik üç Bloom'u ve 1 bit sayıları hazırlanır (aday hangi bit boyundaysa o kullanılır).
2. **Yakın boy taraması:** aday L'si `[L − L/4, min(255, L + L/4)]` (tam sayı bölme). Her aday için benzerlik ≥ taban
   ise listeye (puan = benzerlik).
3. **Seçim** (listeden): en yüksek puanlı; eşit puanda **anahtarı (64 bit sayı) büyük olan**. En iyinin puanı < eşik
   ise yok (belirsiz değil). En iyiden farklı anahtarlı başka bir aday puanı > (en iyi − 5) **ve Türkçesi farklıysa**
   → **belirsiz**, yok. (Türkçesi aynı adaylar birbirinin rakibi değil.)
4. Yakın boyda bir anahtar seçildiyse o. Belirsizse yok. L < **22** ise yok.
5. **Tek yönlü kapsama taraması** (yarım okunmuş ya da fazlalıklı okuma): aday L'si `[max(22, L×11/20),
   min(255, L×5/2)]`. Her aday için:
   - aday L'si < 22 ya da L'ye eşitse atla;
   - hızlı eleme: ortak × 10 < 9 × (kısa tarafın 1 bit sayısı) ise atla (aday uzunsa kısa taraf sorgu, kısaysa aday);
   - iki yönlü kapsamalar hesaplanır. Aday uzunsa: iç = sorgunun kapsanması, dış = adayın kapsanması, alt sınır **25**
     (satır yarım okunmuş). Aday kısaysa: iç = adayın kapsanması, dış = sorgunun kapsanması, alt sınır **55** (okumada
     fazlalık var: köşe yazısı, çöp).
   - iç < **90** ya da dış < alt sınır ya da (iç − **10**) < taban ise atla;
   - aday kısaysa **yan cümle denetimi** (§3.6); okuma birden çok yan cümleyse ve denetim geçmezse atla;
   - puan = iç − 10.
6. Tek yönlü aday yoksa yok. Varsa yakın boy listesine eklenir ve 3. adımdaki seçim birlikte yeniden yapılır.

### 3.6 Yan cümleler (fazlalıklı okumada)

**Bölme** (kod noktası dizisi; işaretler `. ! ? … , ; :`, kapanışlar `" ' ” ’ ) ]`):
- İşaret görülünce ardışık işaretler, sonra ardışık kapanışlar atlanır, sonra boşluklar.
- Bu işaret öbeğinde `, ; :` ya da `…` varsa "yumuşak"; nokta sayısı sayılır.
- Boşluk vardıysa, metin bitmediyse ve (yumuşak **ya da** nokta > 1 **ya da** sonraki kod noktası büyük harf) ise
  öbeğin sonunda kesilir, yeni parça boşluklardan sonra başlar. (Tek noktadan sonra küçük harf bölmez:
  `seriously. nis seriously` tek parça.)
- Parçalar kırpılır, boşlar atılır.
- **Birleştirme:** katlanmış hâli **6** harften kısa olan parça sonrakine eklenir (aradaki boşlukla); sonda kalan kısa
  parça öncekine eklenir (önceki yoksa kendi başına kalır).

Örnekler:
- `Old Harbor Ahem. Your late. Ring me later, okay? Bye, Mom.` → `Old Harbor Ahem.` · `Your late.` · `Ring me later,` ·
  `okay? Bye, Mom.`
- `to the docks... if we can. You said quickly. nis quickly.` → `to the docks...` · `if we can.` ·
  `You said quickly. nis quickly.`

**Denetlenecek yan cümleler:** parça sayısı < 2 ise denetim yok (geçer). Her parça için: köşe yazısına benziyorsa
(`•` içerir ya da 1–4 sözcük ve her sözcük büyük harfle başlayıp yalnız harf/rakam) atlanır. Seçenekler: parçanın
kendisi; ilk parçaysa ve ilk k sözcüğü (k = 1…3, k < sözcük sayısı) büyük harfli sözcükse onlarsız hâli; son parçaysa
ve son k sözcüğü öyleyse onlarsız hâli. Seçeneklerden **biri bile** katlanmışta 6'dan kısaysa bu parça denetlenmez.
Değilse her seçeneğin üçlü özetleri tutulur.

**Kapsanma:** adayın doluluğu d = a/bit (≥ 1 ise denetim başarısız). Her seçenek için seçeneğin Bloom'u (adayın bit
boyunda) kurulur; c = seçenekteki 1 bit; ortak = adayla AND. c = 0 ise seçenek geçer; değilse
100 × ((ortak/c − d) / (1 − d)) ≥ **30** ise geçer. Her denetlenen parçanın en az bir seçeneği geçmeli.

### 3.7 Bulanık arama örnekleri (`pack-sample.json.gz` + `pack-matches.json`)

- Hiç tam eşleşme yokken kapsam yok: bozuk bir okuma (`The lighthouse keeper sald the st0rm wouId pass beföre the
  mornlng tide.`) → yok. Isıtma satırı (`pack-matches.json` → `warmUp`, `Light the lantern, quickly.`) tam bulununca
  kapsam `lantern-coast` olur, kapsam başlığı `Lantern Coast`; artık aynı bozuk okuma düzgün satırın Türkçesine çıkar.
- `pack-matches.json` → `cases`: her `screen` okuması tam olarak `turkish` sonucunu (ya da `null` → yok) vermeli.
  Örnekler: `BRING ME THE MAP!!` → `Haritayı bana getir.`; `Bring rne the map.` (tek düzeltme) → `Haritayı bana
  getir.`; `Buon viaggio.` → `Buon viaggio.` (Türkçesi aynı satır, `segments`); `TOMAS: Run! Get to the boats!` →
  `TOMAS: Kaç! Teknelere koşun!`; `Every smugg1er on thls coast owes the harb0r master a fav0r.` → `Bu kıyıdaki her
  kaçakçının liman başkanına bir borcu var.`; `Get to the boatz!` → yok.
- Yalnız tek harfi farklı iki satır (`Take the north road to the old mill.` / `Take the south road …`) belirsizlik
  payına düşer: arada kalan bozuk okuma yok döner, Türkçeyi karıştırmaz.
- Köşe yazılı ve yarım okunmuş satırlar §3.5'in tek yönlü taramasıyla bulunur; iki ayrı altyazı yan yana okununca
  yalnız birinin çevirisi gösterilmez (yan cümle denetimi, §3.6). Bunların vakaları da `cases` içinde.
- Hız: deneme paketinde bozuk satır başına ortalama < 50 ms.

### Mac'ten farkı (§3)
Yok; aynı algoritma ve sabitler. Windows'a özgü tek ayrıntı .NET kod noktası işlemleri (her uzunluk kod noktasıyla).

---

## 4. Paket güncelleme (sunucudan)

### 4.1 Adres ve zamanlama
- Adres sırası: ortam değişkeni `NINO_PACKS_URL`, sonra çalıştırılabilir dosyanın derleme bilgisindeki `NinoPacksUrl`
  anahtarlı derleme meta verisi. Kırpılmış değer boşsa, mutlak adres değilse, şeması `http`/`https` değilse ya da makinesi
  yoksa atlanır. **Hiçbiri yoksa özellik kapalıdır** (bugünkü yayın durumu: değişken de meta veri de tanımlı değil).
  Kullanıcı ayarı yok (Mac'te `packsURL` ayarı vardı).
- Temel adresin sonuna `/` eklenir (tek).
- Açılışta hemen (ilk sefer **zorla**), sonra **24 saatte bir** zamanlayıcıyla. PS5'te yeni bir oyun tanınınca da
  "son bakış **10 dk**'dan eskiyse" bakılır.
- Aynı anda tek yenileme (ikinci çağrı birincinin bitmesini bekler).
- Bakma kararı: zorla değilse, durum dosyasında son bakış > 0 ve `şimdi − son bakış` < izin verilen yaş (varsayılan
  24 sa, ya da çağıranın verdiği 10 dk) **ve** kayıtlı her paketin sürümü −1'den farklıysa → atlanır ("süresi gelmedi").
- HTTP zaman aşımı 60 sn.

### 4.2 Uç noktalar
- `GET <adres>v1/packs` → `{"packs":[{"id":"gta-6","title":"…","version":2,"sha256":"<64 hex>","size":123,
  "entries":456}]}` (`size`, `entries` isteğe bağlı). Başarısız durum kodu, ağ hatası, JSON değil ya da `packs`
  eksik/`null` → **liste alınamadı**: hiçbir şey değişmez (indirilmiş paketler silinmez).
- `GET <adres>v1/packs/<id>` → paket dosyasının baytları.

### 4.3 Paket başına karar
Kimlik `^[a-z0-9][a-z0-9-]{0,63}$` değilse ya da sha256 64 hex değilse paket atlanır (ör. `../evil` hiç indirilmez).
İstenen özet küçük harfe çevrilir. Dosya `<paket klasörü>\<id>.json.gz`.
1. Kayıtlı paket var, sürümü ve özeti sunucununkiyle aynı **ve** diskteki dosyanın özeti de aynı → dokunulmaz, kayıt
   korunur.
2. Diskte dosya var ama özeti ne kayıtlıya ne yeniye eşit → **kullanıcının dosyası**: indirilmez, üstüne yazılmaz,
   kayda da alınmaz.
3. İndirilir. Veri yok, 64 MB'den büyük ya da SHA-256'sı tutmuyor → "yeniden denenecek" işareti konur; kayıtlı paket
   varsa ve diskte dosyası duruyorsa kayıt **sürüm −1** ile korunur. Devam.
4. Önce `<paket klasörü>\.<id>.download` geçici dosyasına yazılır, sonra asıl adına taşınır (üstüne yazarak). Yazma ya
   da taşıma hatasında geçici dosya silinir; kayıtlı paket varsa ve diskte duruyorsa sürüm −1 ile korunur (bu durumda
   "yeniden denenecek" işareti **konmaz**, ama sürüm −1 sonraki bakışı zaten zorlar).
5. Başarılıysa kayıt (id, title, version, sha256) yazılır; "indirilenler" listesine eklenir.

Sunucu listesinde olmayan kayıtlı paketler: diskteki dosyanın özeti kayıtlıyla aynıysa silinir; her durumda
"kaldırılanlar"a yazılır ve kayıttan çıkar.

Son bakış zamanı: "yeniden denenecek" işareti varsa **ilerletilmez** (eski değer kalır), yoksa şimdi (Unix saniye,
kesirli). Durum dosyası her yenilemede (listesi alınabildiyse) yazılır.

Sonuç: indirilenler, kaldırılanlar, "atlandı", "liste alınamadı". İndirilen ya da kaldırılan varsa kütüphane yeniden
yüklenir, ayarlardaki paket listesi tazelenir, günlüğe `paketler güncellendi: <kimlikler>` yazılır.

### 4.4 Durum dosyası
`%LOCALAPPDATA%\Nino\packs-remote.json` (paket klasörünün **dışında**, paket gibi okunmasın):
```json
{"checked": 1793000000.5, "packs": [{"id": "gta-6", "title": "gta-6", "version": 1, "sha256": "<64 hex>"}]}
```
Okunamazsa boş durum sayılır. Yazarken önce `.tmp`, sonra yerine taşıma.

İndirilen paketleri silme (ayarlar): kayıttaki her paketin dosyası, özeti kayıtlıyla aynıysa silinir; sonra durum
dosyası silinir. Kullanıcının dosyalarına dokunulmaz.

### 4.5 Test senaryoları (sahte sunucu, saat 1 793 000 000)
- `gta-6` sürüm 1 içerik `one` → indirilir, dosya `one`. Sunucu sürüm 2 `two` yapınca hemen bakış → atlandı. 24 sa + 1 sn
  sonra → indirilir, dosya `two`. Zorla bakışta sürüm ve özet aynı → indirme isteği gitmez.
- Kurulu `one` varken sunucu sürüm 2; dosya başka süreçte okumaya açık (taşıma başarısız) → indirilen yok, dosya `one`,
  kayıt sürüm −1. Kilit kalkınca zorlamasız bakış → `gta-6` indirilir, sürüm 2.
- Özeti tutmayan dosya (`good` ilan edilip `tampered` gönderilir) → hiç kurulmaz, kayıt yok.
- Kurulu `gta-6` varken yeni `rdr-2` 404 dönüyor (24 sa sonra) → indirilen yok, son bakış ilerlemedi; dosya gelince
  60 sn sonra, izin verilen yaş 10 dk ile → atlanmaz, `rdr-2` iner, `gta-6` değişmez.
- Liste 503 → "liste alınamadı", dosya duruyor. Liste boş gelince → `gta-6` kaldırıldı, dosya silindi.
- Liste `{}` ya da `{"packs":null}` → "liste alınamadı", kaldırılan yok, kayıt duruyor.
- Klasörde kullanıcının `gta-6.json.gz` = `mine`; sunucuda `gta-6` ve `../evil` → indirilen yok, dosya `mine`,
  `../evil` hiç istenmedi; "indirilenleri sil" sonrası dosya hâlâ `mine`.
- Adres: boş → yok; `ftp://x` → yok; `https://packs.example.test` → makine `packs.example.test`.
- Kimlik: `gta-6` geçerli; `-gta`, `../evil`, `GTA` geçersiz.

### Mac'ten farkı (§4)
- Kullanıcı ayarından adres yok; derleme bilgisi meta veriden okunur.
- Yazma/taşıma hatasında son bakış ilerletilir ama kayıt sürüm −1 ile kalır; sürüm −1 bir sonraki bakışı süresini
  beklemeden yaptırır (Windows davranışı; aynen korunmalı).

---

## 5. Paket içe aktarma (kullanıcının dosyası)

Ayarlardaki paket içe aktarma düğmesi: kullanıcı bir dosya seçer, önizleme (geçerli satır sayısı, geçersiz, yinelenen,
çelişen sayıları, önerilen başlık) gösterilir, başlığı onaylar, paket yazılır.

### 5.1 Okuma
- Dosya **64 MB**'den büyükse hata ("dosya çok büyük").
- Baştaki UTF-8 BOM (`EF BB BF`) atılır. Kalan baytlar **katı UTF-8** ile çözülür; geçersiz bayt → hata ("geçerli
  UTF-8 değil").
- Uzantı (büyük/küçük harf duyarsız): `.json`, `.txt`, `.srt`; başkası → hata ("desteklenmeyen dosya türü").

**JSON** (JSON belgesinde aynı ad birden çok kez geçebilir; **her geçiş sırasıyla** işlenir; tek değer gereken
yerlerde — `format`, `title`, `game`, `entries`, `subtitles` — **son geçiş** geçerlidir):
- Kök nesne değilse hata. JSON bozuksa ya da metinde geçersiz Unicode kaçışı (ör. `\uD800`) varsa hata.
- `format` **sayıysa**: 1 olmalı (1.0 da olur), değilse hata ("desteklenmeyen paket biçimi"). `entries` nesne olmalı,
  değilse hata. Her `entries` üyesi: ad 16 haneli hex (büyük harf de kabul) ise küçük harfe çevrilir ve anahtar odur
  (yeniden özetlenmez); değilse "geçersiz". Başlık: `title`, yoksa `game` (boş olmayan, kırpılmış metin).
- `format` sayı değil (yok, `true` vb.) ama `entries` nesneyse → hata ("biçim numarası gerekli").
- `subtitles` nesnesi varsa: üyeler İngilizce → Türkçe; anahtar §1 ile hesaplanır. Başlık: `game`, yoksa `title`.
  Kökteki öbür alanlar yok sayılır.
- Hiçbiri: kökün kendisi İngilizce → Türkçe nesnesi; başlık önerisi yok.

**TXT** (satır satır; satır sonu `\r\n` ya da `\n`):
- Kırpılınca boş ya da `#` ile başlayan satır atlanır.
- Satırda sekme varsa: tam **bir** sekme olmalı (birden çoksa "geçersiz"); sol İngilizce, sağ Türkçe.
- Sekme yoksa ilk ` = ` (boşluk-eşittir-boşluk) ayraçtır; yoksa "geçersiz".
- Ayraç seçimi sekme önceliklidir: `Who rang the bell?<TAB>Zili kim çaldı? = bilinmiyor` → Türkçe `Zili kim çaldı? = bilinmiyor`.

**SRT:** satırlar okunur; boş olmayan (kırpılmış) satırlar bir "blok"ta toplanır, boş (ya da yalnız boşluklu) satır
bloğu bitirir. Blok tam **4** satır olmalı: (1) yalnız ASCII rakam (tam genişlik `４` geçersiz), (2) zaman satırı: tam
29 karakter, `SS:DD:ss,mmm --> SS:DD:ss,mmm` (saat 2 rakam, dakika ve saniye 00–59, milisaniye 3 rakam, ayraç virgül),
başlangıç metni bitişten sözlük sırasıyla **küçük** (eşit olamaz), (3) İngilizce, (4) Türkçe. Başka blok "geçersiz".

**Sayaçlar** (her İngilizce/anahtar–Türkçe çifti için): anahtar yok ya da Türkçe (kırpılınca) boş → geçersiz. Aynı anahtar
aynı Türkçeyle yinelenirse → yinelenen. Farklı Türkçeyle gelirse → **çelişen**: anahtar sonuçtan **çıkarılır** ve bir
daha alınmaz; o anahtarın sonraki geçişlerinde, Türkçe çelişkili hedefler kümesinde zaten varsa yinelenen sayılır, yoksa
kümeye eklenir. Çelişen sayısı = çelişkili **anahtar** sayısı. Türkçe kırpılarak saklanır.

### 5.2 Kimlik ve yazma
- Kimlik: başlığın karakterlerinden yalnız ASCII harf/rakamlar küçük harfle alınır; aradaki (öncesinde en az bir alınmış
  karakter olan) her harf/rakam dışı öbek tek `-` olur; eklenmesi 80'i aşacak karakterde durulur; başına `community-`
  (hiçbir şey alınmadıysa `community-game`).
- Hedef: kullanıcı paket klasörü `%LOCALAPPDATA%\Nino\packs\<kimlik>.json`. Biçim 1:
  `{"format":1,"id":"<kimlik>","title":"<kırpılmış başlık>","entries":{"<16 hex>":"<Türkçe>",…}}` (tam bu 4 alan).
- Başlık (kırpılınca) boşsa hata; geçerli satır yoksa hata; ikisinde de hiçbir dosya yazılmaz/değişmez.
- Seçilen kaynak dosya hedefin kendisiyse hata (kaynak = hedef). Karşılaştırma: tam yol eşitse aynı; değilse Windows'ta
  iki dosya da açılıp birim seri numarası + dosya kimliği karşılaştırılır (büyük/küçük harf, bağlantı, kısayol aşamasın);
  birim dosya kimliği desteklemiyorsa bağlantıları çözülmüş yollar büyük/küçük harf duyarsız karşılaştırılır.
- Yazma: klasörde `.<rastgele 32 hex>.tmp` dosyasına yazılır, sonra hedefe taşınır. "Değiştir" onayı yoksa ve hedef
  varsa **hata** (dosya değişmez, geçici dosya silinir). Onay varsa üstüne yazılır.
- Arayüz akışı: başlık ya da satır yoksa düğme bir şey yapmaz; kaynak = hedef ise seçilen dosyanın zaten paketin kurulu
  yeri olduğunu söyleyip başka oyun adı isteyen hata; hedef varsa `pack.import.replaceMessage` Evet/Hayır sorusu
  (varsayılan Hayır). Bitince kütüphane yeniden yüklenir.
- Sunucu güncellemesi bu dosyalara dokunmaz (adları `.json`, sunucunun `<id>.json.gz` dosyalarıyla çakışmaz).

### 5.3 Test örnekleri
- `flat.JSON` (BOM'lu): `{"You sank my boat, sailor!":"  Teknemi batırdın, denizci!  ","...":"x","":"x","Blank":"  ",
  "Number":7}` → başlık yok; tek kayıt `9ef4f1d9908ecb47` → `Teknemi batırdın, denizci!`; geçersiz 4, yinelenen 0, çelişen 0.
- `{"game":"Old","game":"  Test Game  ","title":"Alternate","subtitles":{"Stand back!":"Geri dur!"},"other":"ignored"}` →
  başlık `Test Game`, kayıt `c785e7bafcdfb411` → `Geri dur!`, geçersiz 0. `game` yalnız boşluksa başlık `Alternate`.
- `{"format":2,"format":1.0,"id":"ignored","title":" Harbor Tales ","game":"Alternate","entries":{"0123456789ABCDEF":
  "Türkçe","0123456789abcdef":"Türkçe","+123456789abcdef":"bad","g123456789abcdef":"bad","fedcba9876543210":null,
  "9999999999999999":"  ","123":"bad"}}` → başlık `Harbor Tales`; tek kayıt `0123456789abcdef` → `Türkçe`;
  geçersiz 5, yinelenen 1, çelişen 0.
- Yinelenen/çelişen (düz, `subtitles` ya da biçim 1 aynı sonuç): `Stand back!`→`Geri dur!`, `Stand back!`→`Çekil!`,
  `Stand back!`→`Çekil!`, `Who rang the bell?`→`Zili kim çaldı?` ×2 → tek kayıt (`5fafbdf7bea9c4bd` ya da biçim 1'de
  `ffffffffffffffff`) → `Zili kim çaldı?`; geçersiz 0, yinelenen 2, çelişen 1.
- Hata vermesi gerekenler: `{"format":1,"title":"Harbor Tales","entries":[]}`, `…"entries":"text"}`,
  `…"entries":[true,"Stand back!","Geri dur!"]}`, `{"format":1,"title":"Harbor Tales","subtitles":{…}}` (entries yok),
  `{"format":2,"title":"Harbor Tales","entries":null}`, `{"format":2,"entries":{"0123456789abcdef":"Türkçe"}}`,
  `{"format":true,"entries":{…}}`, `{"oops",1}`, `{"Stand back!":"\uD800"}`, `[1,2]`; `file.csv`; tek bayt `FF`.
- TXT (BOM'lu, `\r\n`): `␠␠# ignored`, boş, `Stand back! = Geri dur! = hemen`, `Who rang the bell?<TAB>Zili kim çaldı? =
  bilinmiyor`, `You sank my boat, sailor!<TAB>Teknemi batırdın, denizci!`, `Extra = invalid<TAB>two<TAB>tabs`, `broken`,
  `Empty = `, `<TAB>Missing` → 3 kayıt (`c785e7bafcdfb411`→`Geri dur! = hemen`, `5fafbdf7bea9c4bd`→`Zili kim çaldı? =
  bilinmiyor`, `9ef4f1d9908ecb47`→`Teknemi batırdın, denizci!`), geçersiz 4.
- TXT çelişki: `Stand back! = Geri dur!`, `stand back = Geri dur!`, `<b>STAND BACK</b> = Çekil!`, `Stand back? = Geri dur!`,
  `Stand back = Uzak dur!`, `Who rang the bell? = Zili kim çaldı?` → tek kayıt `5fafbdf7bea9c4bd`→`Zili kim çaldı?`;
  yinelenen 2, çelişen 1, geçersiz 0.
- SRT (BOM'lu, `\r\n`, bloklar arası `␠<TAB>` satırı): 9 blok; geçerli olanlar 1 (`00:00:01,250 --> 00:00:03,999`,
  ` Stand back! `, ` Geri dur! `) ve 9 (`Who rang the bell?`/`Zili kim çaldı?`) → 2 kayıt; geçersiz 7 (tek satırlı metin,
  üç satırlı metin, `４`, `00:60:00,000`, nokta ayraçlı süre, ters süre, eşit süre).
- Kimlik: ` ../My GAME\a:a... ` → `community-my-game-a-a`; `../遊戲` → `community-game`; 300 × `a` →
  `community-` + 80 × `a`; 79 × `a` + ` b` → `community-` + 79 × `a`.
- Yazma: `Stand back! = Geri dur!` ve başlık ` Test Game ` → `<klasör>\community-test-game.json`, içinde tam 4 alan,
  `format` 1, `id` `community-test-game`, `title` `Test Game`, tek kayıt `c785e7bafcdfb411`. Kütüphane yeniden
  yüklenince paket başlığı `Test Game`, 1 satır, `Stand back!` → `Geri dur!`. Aynı başlıkla değiştirme onayı olmadan
  ikinci yazma → hata, dosya baytları aynı, klasörde tek dosya. Onayla → `Stand back!` → `Çekil!`, klasörde yine tek dosya.

### Mac'ten farkı (§5)
- Yazılan klasör kullanıcı paket klasörü (Mac ile aynı); "içe aktarılanlar" klasörü yok.
- Kaynak=hedef denetimi Windows dosya kimliğiyle (Mac/Linux'ta gerçek yol); Unix'te "değiştirme yok" yazımı sabit bağlantı
  ile atomik yapılır (yalnız testlerin Mac'te çalışması için gerekli).

---

## 6. Ortak havuz: genel

İki ayrı iş vardır:
- **Satır gönderme kuyruğu** (§7): pakette olmayan İngilizce satırlar sunucuya gider, yeni paketler bunlardan yapılır.
- **Çeviri havuzu** (§8): sunucunun yaptığı çeviriler indirilir ve anında sorulur; ekrandan oyun tanıma da buradadır.

Havuz sunucusunun adresi (ikisi için de aynı): sırayla ortam değişkeni `NINO_POOL_URL`, sonra `%LOCALAPPDATA%\Nino\pool\endpoint.txt`
dosyasının içeriği (kırpılmış), sonra canlı sunucu `https://nino-pool.y-demirbag2506.workers.dev`. Değer mutlak ve
şeması `http`/`https` olmalı; değilse sıradakine geçilir. Kullanıcı ayarı yok. Sorun bildirme de aynı adresi kullanır
(başka belge).

Ayar **"Ortak havuz"** (varsayılan **açık**): kapalıyken hiçbir şey gönderilmez ve indirilmez, indirilmiş çeviriler
kullanılmaz; kuyruk tamamen silinir. **İstisna:** havuz öncelikli oyunda (§8.2) çeviri sorusu ayar kapalıyken de gider
(kullanıcının bilerek verdiği karar; `ceviri.md` §1).

Bütün havuz isteklerinde başlık `User-Agent: nino-pool/1 (windows; <uygulama sürümü>)`. Kişisel veri gitmez: satır
metni, oyun ipucu, her açılışta yenilenen rastgele oturum kimliği, görülme sayısı ve zamanı, kuruluma ait rastgele kimlik, uygulama sürümü, platform `windows`, dil.

**İki ayrı kurulum kimliği** vardır (eski koddaki gibi korunmalı):
- Kuyruğun kimliği: `pool\state.json` içindeki `install` (§7.2).
- Çeviri havuzunun kimliği: `pool-translations\install` dosyası (§8.7). Arayüzdeki "kurulum kimliği" kuyruğunkidir.

### 6.1 Süzgeç (hangi satır havuza gider)

Önce **temizlik:** her kod noktası U+0000–001F, U+007F–009F, U+200B–200F, U+2028, U+2029, U+FEFF ise boşluk olur; sonra
metin boşluk karakterlerinden bölünüp boşlar atılarak tek boşlukla birleşir (baş/son kırpılmış olur).
`␠␠Ahoy<U+200B>⏎␠␠sailor.␠␠` → `Ahoy sailor.`

Kabul için hepsi:
1. Boş değil, **en çok 500 kod noktası**, en az bir harf.
2. **Gürültü değil:** (a) OCR çöp temizliğinden (okuma hattı belgesindeki çöp sözcük kuralları) geçirilmiş metnin canon'u
   (§1.1) metnin kendi canon'undan farklıysa çöp; (b) boşluk olmayan kod noktalarının yarısından azı harfse çöp
   (harf × 2 < görünür). `MP 40/80 XP 12%` → çöp.
3. **Yarım okuma değil** (metin kırpılır; "sözcük" = boşluktan bölünmüş, en az bir harf içeren parça):
   - "Cümle sonu var" = sondaki `" ' ” ’ » ) ]` atıldıktan sonra son karakter `. ! ? …`.
   - Cümle sonu yoksa ve (sözcük < **3** ya da metin < **15** metin öğesi [grafem]) → yarım.
   - İlk karakter küçük harfse → yarım (`ve left the harbor.`).
   - Cümle sonu varsa → yarım değil.
   - Son sözcüğün harfleri (küçük harfle) şunlardan biriyse → yarım: `the a an to of and or but with for from my your his
     her their our at in on by into than that if as is are was were`.
   - Harfleri olup hiçbiri küçük olmayan ve sözcük sayısı ≤ **6** → arayüz yazısı, yarım.
4. **Türkçe değil:**
   - `ğ Ğ ş Ş ı İ`'den biri varsa Türkçe.
   - `ü Ü ö Ö ç Ç`'den toplam en az 2 tane varsa Türkçe.
   - Katlanmış sözcüklerden en az 2'si aşağıdaki PS5 Türkçe arayüz sözcüklerinden birine "yakın"sa Türkçe. Yakın = eşit,
     ya da ikisi de ≥ 6 harfli, boyları en çok 1 farklı ve tek düzenleme (ekleme, silme, değiştirme) farkı. Liste
     (katlanmış): icin, lutfen, bekleyin, oyunu, oyun, oyunlar, kapat, ekran, ekranda, ekrani, sistemini, yeniden, baslat,
     ayarlar, ayarlari, kupalar, kupa, oturum, acti, kapatti, secenekleri, sifirlama, tut, kesfet, ilgili, takip, edin,
     ilerlemenizi, cikanlar, goruntusu, kaydedildi, bildirimler, arkadaslar, medya, galerisi, indiriliyor, guncelleme,
     kitaplik, denetleyici. (Listede listelendiği hâliyle de katlanır: `l` → `i` olduğu için ör. `ilgili` → `iigiii`.)
     `ile` bilerek yok (katlanınca İngilizce `lie` ile aynı).
5. **PS5 sistem yazısı değil:** katlanmış sözcükler tek boşlukla birleştirilip başına ve sonuna boşluk konur; şu öbeklerin
   (katlanmış hâlleriyle) ` öbek ` olarak geçmesi aranır: signed in, signed out, earned a trophy, trophy earned, trophy
   unlocked, screenshot saved, video clip saved, media gallery, is now online, joined the party, left the party, remote
   play, controller battery, controller is disconnected, controller disconnected, press the ps button, playstation
   network, download complete, installation complete, update available, turn off your console, cloud save, do not quit,
   photo mode, story mode, press any button, oturum acti, oturum kapatti, ekran ve video, oyunu kapat, ana ekranda tut,
   yeniden baslat, sifirlama secenekleri, lutfen bekleyin, ilerlemenizi takip.

**Katlama (süzgeç için):** kültürden bağımsız küçük harf; `ı` → `i`; NFD ve boşluksuz birleşen işaretler (Mn) atılır;
`q` → `c`; `l` ve `1` → `i`; harf/rakam olmayanlar ayraç; sözcük listesi.

Örnekler (canlı kuyruğun süzgeci; ortak kurallar sunucudaki süzgeçle aynıdır):

| Satır | Sonuç |
|---|---|
| `Run!` | kabul |
| `Where are you headed, Marisol?` | kabul |
| `Kayıt tamamlandı` | ret (Türkçe harf) |
| `Tomas_88 signed in` | ret (PS5 sistem yazısı) |
| `MP 40/80 XP 12%` | ret (gürültü) |
| 50 × `Wait here. ` | ret (500'den uzun) |

Kuralları tek tek sınayan ek örnekler (eski kuyruk ayrıca "en az 2 sözcük, en çok 300 karakter" ister, bkz. §9 —
aşağıdakiler ortak kurallarla da aynı sonucu verir):
- Ret: `Çözüm bulundu` (Türkçe harf), `Medya galerisi guncellendi.` (iki katlanmış sözcük PS5 Türkçe arayüz listesinde),
  `Mira signed in.`, `You earned a trophy!`, `Screenshot saved.` (PS5 sistem yazısı), `Pick up the` (son sözcük `the`),
  `ve left the harbor.` (küçük harfle başlıyor), `CHARTS AND MAPS` (büyük harfli kısa arayüz yazısı), `Go now`
  (2 sözcük, cümle sonu yok), `MP 40/80 XP 12%` (gürültü), `...` (harf yok).
- Kabul: `Frau Köhler will see you now.` (tek `ö`), `Bring the crates inside.`, `I owe you, you owe me.`,
  `CAPTAIN RUIZ WANTS YOU!` (cümle sonu var), `Who's at the door?`, `Room number 4 here`, `We have to go before the
  guards arrive`, `Pay me 30 coins, Tomas.`.
- `Okay.` canlı süzgeçte **kabul** (tek sözcük ama cümle sonu var); eski kuyrukta "2 sözcük" kuralıyla ret.

**Hangi satır önerilir** (okuma hattının "pakette yok" bildirimi): kaynak `en` olmalı. Paketler kapalıysa (ve oyun havuz öncelikli
değilse) yalnız **hiçbir pakette bulunmayan** satır önerilir (bulunursa önerilmez). Oyun ipucu: paket kapsamının kimliği
(§2.3), yoksa yok. Telefon, harita, görev gibi ek alanlar havuz kuyruğuna gitmez (kişisel olabilir).

---

## 7. Satır gönderme kuyruğu (kayıpsız)

Klasör `%LOCALAPPDATA%\Nino\pool\`:

| Dosya | İçerik |
|---|---|
| `pending.jsonl` | her görülme bir satır, görüldüğü an sona eklenir |
| `outbox\` | gönderilecek parçalar, her biri bir `.json` dosyası |
| `parked\` | sunucunun kabul etmediği parçalar |
| `state.json` | kuyruğun durumu |
| `rejected.jsonl` | sunucunun reddettiği satırlar ve nedeni |
| `endpoint.txt` | (isteğe bağlı) sunucu adresi, §6 |
| `state.broken-<unix sn>.json` | okunamayan eski durum dosyası (kenara konmuş) |

JSON yazımında ASCII dışı karakterler kaçışsız yazılır (`ş` olduğu gibi), `/` kaçışlanmaz; `null` alanlar **yazılır**.

### 7.1 Biçimler

`pending.jsonl` satırı (alan sırası sabit):
```json
{"s":12,"t":"Where did the caravan go?","g":"lantern-coast","e":"<oturum uuid>","a":1763300000.123}
```
`s` sıra numarası (artan tam sayı), `t` temizlenmiş metin, `g` oyun kimliği ya da `null`, `e` oturum kimliği ya da
`null`, `a` Unix saniye (kesirli).

Parça (outbox dosyası ve istek gövdesi aynı; alan sırası sabit):
```json
{"v":1,"batch":"<uuid>","install":"<uuid>","app":"0.2.1","platform":"windows",
 "lines":[{"text":"Stand back!","game":"lantern-coast","session":"<uuid>","count":3,"first":1763300000,"last":1763300100}],
 "upTo":1234}
```
`first`/`last` tam saniye (kesir atılır), `upTo` parçanın kapsadığı son sıra numarası.

`state.json`:
```json
{"install":"<uuid>","frozenThrough":1234,"failures":0,"nextAttempt":0,"serverRetryAt":0,"app":"0.2.1","dropped":0}
```
`nextAttempt`, `serverRetryAt` Unix saniye (kesirli). Kimlikler küçük harf, tireli UUID.

**Oyun kimliği** (sunucunun beklediği biçim): yoksa yok; küçük harf (kültürden bağımsız); ASCII harf/rakam ve `. _ -`
dışındaki her karakter `-`; ardışık `-`'ler teke iner; baştan/sondan `- . _` atılır; boşsa yok; en çok 64 karakter.
`GTA V` → `gta-v`; `Mafia: The Old Country` → `mafia-the-old-country`; `mafia--the-old-country` → aynı;
`Marvel's␠␠Spider-Man 2` → `marvel-s-spider-man-2`; `␠␠Lantern Coast: The Return!!␠` →
`lantern-coast-the-return`; `Ghost of Yōtei` → `ghost-of-y-tei`; `␠␠` → yok.

### 7.2 Açılış
1. `outbox\` ve `parked\` oluşturulur.
2. `state.json` okunur; okunamaz ya da `install` boşsa yeni durum (yeni rastgele `install`) kullanılır; dosya vardı ama
   okunamadıysa **silinmez**, `state.broken-<unix sn>.json` adıyla kenara konur.
3. `outbox\` parçalarının en büyük `upTo`'su `frozenThrough`'dan büyükse `frozenThrough` ona çekilir (parça yazılıp durum
   yazılamadan kapanmış olabilir).
4. Durumdaki `app` bu sürümden farklıysa `parked\` → `outbox\` taşınır (güncellemeden sonra yeniden dene), `app` yazılır.
5. `failures` = 0, `nextAttempt` = 0 (açılışta hemen dene; `serverRetryAt` korunur).
6. `pending.jsonl`'ın son baytı `\n` değilse son `\n`'den sonrası kesilir (yarım yazılmış satır).
7. Bekleyenler taranır (JSON olmayan satır atlanır); kuyruk etkinse ve eski kuyruk dosyası verildiyse bir kez içe aktarılır
   (§7.6). Sonraki sıra = max(en büyük sıra, `frozenThrough`) + 1.
8. Durum yazılır.

Ayrı bir "etkisiz" kip vardır (açılırken etkin değil): satır kabul etmez, göndermez ama kuyruğu **silmez**. Kullanıcı
ayarı kapatınca ise silinir (§7.5).

### 7.3 Satır ekleme
Süzgeçten (§6.1) geçmeyen satır alınmaz. Etkin değilse ya da kapanmışsa alınmaz. `pending.jsonl` boyu ≥ **64 MB** ise
yazılmaz, `dropped` bir artar ve durum yazılır. Aksi hâlde satır dosyaya eklenir (yazma hatasında alınmamış sayılır),
sıra numarası artar, bekleyen sayısı ve en eski bekleyen zamanı güncellenir.

### 7.4 Gönderim
Zamanlama: açılıştan **5 sn** sonra ve sonra **dakikada bir** denenir; işletim sistemi "ağ erişilebilir" dediğinde
artan bekleme sıfırlanır ve hemen denenir. Aynı anda tek gönderim (ikinci çağrı beklemeden döner).

Bir deneme:
1. Etkin değil, kapanmış ya da adres yoksa: hiçbir şey (satırlar bekler).
2. `şimdi < nextAttempt` ya da `şimdi < serverRetryAt` ise dur.
3. **Dondurma zamanı mı:** zorla, ya da bekleyen ≥ **200** satır, ya da en eski bekleyen ≥ **120 sn** önce. Öyleyse dondur:
   - bekleyen yoksa hiçbir şey; `outbox\` ≥ **2000** parça ise dondurma yok.
   - `frozenThrough`'dan büyük sıralı görülmeler sıra numarasıyla dolaşılır. (oyun, oturum, metin) aynıysa birleşir:
     `count` artar, `first` = en küçük, `last` = en büyük zaman. Yeni farklı satır eklenirken parça zaten **200 farklı
     satır**a ulaştıysa parça kapanır (`upTo` = o ana kadar görülen son sıra) ve yeni parça başlar; birleştirme parça
     sınırını aşmaz.
   - Parçalar `outbox\<ms zaman, 15 hane sıfır dolgulu>-<parça sırası, 4 hane>-<parça uuid>.json` adıyla atomik yazılır
     (önce `.tmp`, diske boşaltma, sonra taşıma). Her yazılan parçadan sonra `frozenThrough` = o parçanın `upTo`'su.
     Yazılamayan parçada durulur (kalan satırlar bekleyende kalır).
   - Durum yazılır; `pending.jsonl` yalnız `frozenThrough`'dan büyük sıralılarla atomik yeniden yazılır.
4. `outbox\` dosyaları **ada göre** sırayla gönderilir; bu turda denenen dosya yeniden denenmez. Okunamayan parça kenara
   (`parked\`) alınır.
5. `POST <sunucu>/v1/batches`, gövde parça JSON'u, 30 sn zaman aşımı.

Yanıta göre:

| Durum | Davranış |
|---|---|
| 2xx ve gövde `{"ok":true,"batch":"<aynı kimlik>"}` (kimlik büyük/küçük harf duyarsız) | `rejected[]` (`{i, reason}`) günlüğe yazılır; parça silinir; `failures`=0, `nextAttempt`=0; sıradaki parça |
| 2xx ama gövde tutmuyor (captive portal, yanlış sunucu) | hata sayılır (aşağı), tur biter, parça kalır |
| 413 | parça > 1 satırsa ikiye bölünür (ilk yarı = satır/2), iki yeni dosya `<eski adın ilk 20 karakteri>-<0/1>-<yeni uuid>.json`, aynı `upTo`; eski silinir. Tek satırsa kenara |
| 429, 503 | `serverRetryAt` = şimdi + `Retry-After` (saniye ya da HTTP tarihi; yoksa 60 sn; 1 sn – 1 gün arasına sıkıştırılır); tur biter |
| 400, 422 | kenara (`parked\`, aynı adla; orada varsa üstüne) |
| diğer (404, 401/403, 5xx…) ve ağ/zaman aşımı hatası | hata: tur biter, parça kalır |

**Hata beklemesi:** `failures` bir artar; bekleme = min(30 × 2^(min(failures−1, 16)), 3600) sn; buna ±%20 rastgele
eklenir; `nextAttempt` = şimdi + bekleme. Durum yazılır.

`rejected.jsonl`: her reddedilen satır için `{"reason":"…","text":"…"}` satırı; dosya ≥ **1 MB** ise yazılmaz. Geçersiz
`i` atlanır.

### 7.5 Kapatma ve kapanış
- Ayar kapatılınca: `pending.jsonl`, `rejected.jsonl`, `outbox\` ve `parked\` içindeki **bütün dosyalar** silinir; sayaçlar
  sıfırlanır; `failures`, `nextAttempt`, `serverRetryAt` = 0; durum yazılır. Sonra gelen satırlar alınmaz.
- Adres değişince `failures` ve `nextAttempt` sıfırlanır.
- Uygulama kapanırken durum yazılır; ağ beklenmez (satırlar zaten diskte).
- Durum özeti (ayarlar için): bekleyen satır, outbox parça, parked parça, `dropped`, adres var mı.

### 7.6 Eski kuyruk dosyasını içe aktarma
`%LOCALAPPDATA%\Nino\pool.json` (eski sürümlerin kuyruğu, §9 biçimi) varsa ve kuyruk etkinse: `queue[]` içindeki her
`text` temizlenir, süzgeçten geçmeyen atlanır; zaman `firstSeen` (ISO 8601, saat dilimi yoksa UTC sayılır) Unix saniyesi,
okunamazsa şimdi; oyun ve oturum `null`. Bekleyenlere sıra numarasıyla eklenir. Sonra dosya `pool.json.imported` adıyla
kenara konur (aynı adlı eski kopya silinerek). JSON bozuksa satır alınmaz ama dosya yine kenara konur.
Örnek: `{"install":"x","queue":[{"text":"Leave the oars by the door.","key":"k","firstSeen":"2026-11-11T03:17:00Z"},
{"text":"Kayıt tamamlandı","key":"k2","firstSeen":"2026-11-11T03:17:00Z"}],"sent":[]}` → 1 bekleyen satır
(`Leave the oars by the door.`, `first` = **1 794 367 020**); ikinci açılışta yeniden aktarılmaz.

### 7.7 Test senaryoları (sahte sunucu, saat 1 763 300 000)
- Eklenen satır hemen diskte; yeni nesne açınca 1 bekleyen; zorla gönderimde `Where did the caravan go?`, oyun `lantern-coast`.
- Adres yokken zorla gönderim → hiçbir istek, 1 bekleyen, "adres var" hayır; adres verilince gider.
- `pending.jsonl` sonuna yarım `{"s":3,"t":"Half writ` eklenip yeniden açılınca üç tam satır (eskiler + yeni) gider.
- Çevrimdışıyken zorla gönderim → 1 outbox parçası, 0 bekleyen; yeniden açılıp çevrimiçiyken (zorlamasız) gönderilir.
- Parça boyu 3 iken 7 farklı satır → 3 parça; ikinci ve üçüncü parça silinip `pending.jsonl` eski hâline,
  `frozenThrough` 0'a çekilip yeniden açılınca: toplam 7 satır, hepsi farklı, hepsinin `count`'u 1 (ilk parça
  `upTo`'su açılışta `frozenThrough`'u ilerlettiği için tekrar gönderilmez).
- Etkisiz kipte yeni satır alınmaz; mevcut 1 outbox ve 1 bekleyen durur.
- Parça boyu 3: aynı satır 4 kez (`Lantern Coast` ile), 10 sn sonra 1 kez daha, sonra 4 farklı satır → parçalar [3, 2] satır;
  tekrarlanan satırın `count` 5, oyun `lantern-coast`, `last − first` = 10; tek oturum; yol `/v1/batches`.
- Tek satır hemen gitmez; 120 sn sonra gider.
- 500 dönen sunucu: t=0 deneme; t=10 yok; t=50 ikinci deneme; t=90 yok; t=130 (sunucu düzeldi) gider, outbox boş.
- Yanıt kaybolursa (sunucu aldı ama yanıt yolda kayboldu) ağ gelince **aynı parça kimliğiyle** yeniden gider.
- `<html>otel ağı giriş sayfası</html>` 200 yanıtı → parça silinmez; ağ gelince gider, sunucu 1 satır görür.
- 429 + `Retry-After: 600` → 599 sn'de gitmez, 601 sn'de gider.
- 400 → parça kenara (outbox 0, parked 1); aynı sürümle yeniden açılınca gitmez; sürüm `0.1.7` ile açılınca 2 satır gider.
- 413 → 5 satırlık parça [2, 3] olarak gider, 5 farklı satır.
- 404 → parça outbox'ta kalır, kenara alınmaz.
- Kapatınca bekleyen + outbox + parked = 0; sonra satır alınmaz.
- Adres: hiçbir şey yokken canlı adres; `endpoint.txt` = `http://localhost:9000⏎` → `http://localhost:9000/`; ortam
  değişkeni `https://pool.example` → makine `pool.example`.

---

## 8. Çeviri havuzu

Klasör `%LOCALAPPDATA%\Nino\pool-translations\` (motorların önbelleği ayrı: `translations\`, `ceviri.md` §10). Bellekte
dil başına bir sözlük (anahtar → çeviri), eşzamanlı sorulara karşı kilitli.

### 8.1 Uzak ayar
`GET <sunucu>/v1/config` (30 sn zaman aşımı; zorla değilse son sorudan en az **600 sn** geçmiş olmalı; zaman soru
başlarken işaretlenir, başarısız olsa da). Yalnız 200 kabul.
```json
{"ok":true,
 "translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12},
 "poolFirst":{"games":["grand-theft-auto-vi","gta-vi","gta-6","gta6"],"langs":["tr"],"deadlineMs":1500},
 "downloads":3439}
```
- `downloads` (toplam indirme sayısı, ana ekranda gösterilir) aynı yanıttan okunur; çeviri bölümü okunamasa da alınır
  (başka belge: sayaç; dosyası `pool-translations\downloads.txt`).
- `translate` yoksa ya da JSON bozuksa ayar değişmez. Varsa olduğu gibi alınır; eksik alanlar varsayılanla dolar
  (varsayılanlar yukarıdaki değerler). `poolFirst` yoksa eski değer (varsayılan) kalır; varsa eksik alanları varsayılanla.
- Sunucuya hiç ulaşılamazsa bu varsayılanlar geçerlidir (GTA 6 havuz öncelikli).

### 8.2 Havuz önceliği
"Oyun havuz öncelikli mi" (oyun adı ya da kimlik verilir):
1. `translate.enabled` kapalı ya da adres yok → hayır.
2. Hedef dil kodu (küçük harf, `-`/`_` öncesi; `pt-BR` → `pt`) `poolFirst.langs` içinde değilse (`*` hepsi) → hayır.
3. Oyunun kimliği (§7.1) `poolFirst.games` öğelerinden birini (kırpılmış, küçük harf, boş olmayan) **içeriyorsa** → evet.
4. Değilse: sunucunun son çeviri yanıtında söylediği oyun (§8.4) son **600 sn** içinde geldiyse ve listede ise → evet.
5. Hayır.

"Ortak havuz" ayarı bu kararı etkilemez. Örnekler (varsayılan liste): `Grand Theft Auto VI`, `GTA VI`, `gta6` → evet;
`Grand Theft Auto V`, `Red Dead Redemption 2`, yok → hayır. Sunucu `{"translate":{"enabled":true},"poolFirst":{"games":
["mafia-the-old-country"],"deadlineMs":700}}` derse `Mafia: The Old Country` evet, `Grand Theft Auto VI` hayır, süre 700.
`{"translate":{"enabled":false}}` → GTA 6 de hayır.
Sunucunun tanıdığı oyun: soruda oyun `Call of Duty: Modern Warfare` iken yanıt `"game":"grand-theft-auto-vi"` →
artık oyun verilmese de ve CoD için de evet; sonraki yanıt `red-dead-redemption-2` derse hayır; oyunsuz soruda yanıt yine
GTA 6 derse evet; 601 sn sonra hayır.

**Hangi oyun adıyla sorulur:**
- Havuz öncelikli soru için: bilinen oyun (PS5'in bildirdiği / kullanıcının seçtiği / ekrandan tanınan) listedeyse o;
  değilse paket kapsamının kimliği listedeyse o; değilse kapsam, yoksa bilinen oyun. (Paketten tahmin edilen oyun GTA 6'yı
  gölgelemesin.)
- Öbür sorular ve indirme için: paket kapsamı, yoksa bilinen oyun.
- "Havuz öncelikli etkin" = kaynak `en` ve bu oyun havuz öncelikli.

### 8.3 Toplu indirme
Çeviri oturumu başlarken (kaynak `en`, ortak havuz açık): hemen **zorla** bir indirme, sonra döngü: "buradayım" (§8.5),
**60 sn** bekle, zorlamasız indirme. Döngü (öncekini durdurup) baştan başlar: okuma hattı kurulunca, bilinen oyun
değişince (PS5, kullanıcı, paket ya da ekrandan; hat kuruluysa) ve "Ortak havuz" ayarı değişince (hat kuruluysa).
Koşul sağlanmıyorsa döngü durur.

İndirme (`oyun` → kimlik, yoksa boş = bütün oyunlar):
1. Önce uzak ayar tazelenir (§8.1 kuralıyla).
2. Ortak havuz kapalı, sunucu kapalı ya da adres yok → 0.
3. Oyunun imleci alınır (yoksa `since` 0, `after` boş, `checked` 0). Zorla değilse ve `şimdi − checked` <
   max(30, `syncSeconds`) → 0. `checked` = şimdi.
4. En çok **50 sayfa**: `GET <sunucu>/v1/translations?lang=<kod>&since=<sayı>[&game=<kimlik>][&after=<metin>]`
   (değerler URL kaçışlı; `game` boşsa, `after` boşsa yazılmaz). 30 sn zaman aşımı, yalnız 200.
   ```json
   {"ok":true,"now":30,"items":[["00000000000000a1","Bir",10,"instant"],["00000000000000a2","İki",20,"instant"]],
    "next":{"since":20,"after":"k2"}}
   ```
   - İstek ya da JSON başarısızsa döngü biter.
   - Bu arada hedef dil değiştiyse yanıt atılır, döngü biter.
   - `items` dizi değilse döngü biter. Her öğe: dizi, en az 3 eleman, [0] metin, [1] metin, [2] 64 bit tam sayı olmalı;
     değilse atlanır. Anahtar → çeviri sözlüğe yazılır (aynı dil hâlâ geçerliyse); en büyük güncellenme izlenir.
   - `next` nesne ve `since` sayıysa: imleç `since` = o, `after` = `next.after` (metinse, değilse boş); sonraki sayfa.
   - Değilse: `since` = görülen en büyük güncellenme (en az eski `since`), `after` boş; döngü biter.
5. Dil hâlâ aynıysa imleç oyun için saklanır; değişiklik varsa disk dosyası yazılır. Gelen öğe sayısı döner.

Örnek (testten): ilk sayfa iki öğe + `next {since:20, after:"k2"}`; ikinci sayfa `["00000000000000a3","Üç",30,"review"]`,
`["bad"]`, `[1,2,3]` + `next:null` → 3 çeviri. İstekler: 1. `lang=tr&since=0&game=ghost-of-y-tei` (after yok),
2. `since=20&after=k2`. Dosya `translations-tr.json` oluşur. Hemen tekrar → istek yok. 181 sn sonra → `since=30`, after
yok. Yeniden açılışta diskten 3 çeviri, imleç korunur (`since=30`).

### 8.4 Anında soru
`POST <sunucu>/v1/translate`, 20 sn zaman aşımı, yalnız 200:
```json
{"v":1,"install":"<uuid>","app":"0.2.1","platform":"windows","lang":"tr","game":"red-dead-redemption-2",
 "lines":["Lower the bridge."],"context":["Halt!","State your name.","It's late.","Quickly!"]}
```
→ `{"ok":true,"translations":[{"text":"Köprüyü indir.","tier":"instant"}],"game":"grand-theft-auto-vi"}`
(`text` `null` olabilir: sınır doldu, `"limited":"daily_cap"` vb.; `game` isteğe bağlı.)

Tek satır sorusu:
1. Uzak ayar tazelenir. "Zorunlu" = bu oyun havuz öncelikli mi (§8.2).
2. Satır süzgeçten (§6.1, temizlenmiş hâliyle) geçmiyorsa ya da anahtarı yoksa → yok.
3. (Ortak havuz açık **ya da** zorunlu) **ve** sunucu açık **ve** adres var değilse → yok.
4. Bellekte varsa → hemen o (istek yok).
5. Aynı (dil, anahtar) için süren istek varsa onu bekler (aynı satır aynı anda iki kez sorulmaz).
6. Yoksa istek: `game` = oyun kimliği ya da boş metin; `context` = verilen bağlamın son `contextLines` (en az 0) öğesi.
7. Yanıt geldiğinde sunucunun söylediği oyun (kimliğe çevrilmiş, yoksa boş) ve zamanı not edilir (her başarılı yanıtta).
8. Boş olmayan çeviri belleğe yazılır (disk "değişti" işaretlenir) ve döner; değilse yok.
Ağ, zaman aşımı, 200 dışı, JSON hatası → yok.

**Bağlam listesi** (okuma hattının sorularına giden): son satırlar ve zamanları. Satır eklenince: 30 sn'den eski
olanlar ve aynı metin çıkarılır; bağlam = kalanların son 4'ü; satır eklenir; en çok 4 satır tutulur. "Satırdan öncekiler"
(eklemeden): 30 sn içindeki ve satırın kendisi olmayanların son 4'ü. Örnek: `One.` → bağlam boş; `Two.` → [`One.`];
31 sn sonra `Three.` → boş; `Four.` → [`Three.`].

**Süreli soru** (havuz öncelikli oyunun çevirisi, `ceviri.md` §1): tek satır sorusu başlatılır; en çok
`poolFirst.deadlineMs` (100–10 000 arasına sıkıştırılır) beklenir. Süre dolarsa yok döner ama **istek sürer**; geç gelen
çeviri belleğe yazılır ve aynı satırın sonraki sorusu süren isteği bekler. Örnek: süre 150 ms, sunucu bekletirken soru
100–3000 ms içinde yok döner; sonra aynı satır sorulup sunucu bırakılınca `Köprüyü indir.` gelir, toplam tek istek, bellekte
var. Sınır dolu yanıt (`text:null`) ya da 500 → yok.

**Çok satırlı soru** (telefon sohbeti, harita kartı; varsayılan süre 10 sn):
1. Uzak ayar tazelenir; zorunlu mu bakılır; (açık ya da zorunlu) ve sunucu açık ve adres var değilse hepsi yok.
2. Her satır: süzgeçten geçmiyor ya da anahtarı yoksa yok; bellekte varsa hemen; aynı satır için süren istek varsa
   o beklenir; aynı istekte zaten varsa (yinelenen) yalnız sonucun kopyalanacağı yer eklenir; değilse sorulacaklara.
3. Sorulacaklar en çok min(`maxLines`, 12) (en az 1) satırlık parçalara bölünür; her parça tek istek (`lines` dizisi),
   bağlam aynı kuralla. Her satırın sonucu yanıttaki **aynı sıradaki** öğedir (eksikse yok). Bu satırlar "süren istek"
   olarak kaydedilir (tek satırlık soru da bunları bekler).
4. Gelen boş olmayan çeviriler belleğe; sonuç dizisi istekteki sırayla.
Örnek: bellekte `Seen this one before` → `Bunu daha önce gördüm`; satırlar `Seen this one before`, `Bring the nets to
the pier`, `Dont forget the rope`, `Bring the nets to the pier`, bağlam [`Hey`], oyun `gta-vi` → tek istek `lines` =
[`Bring the nets to the pier`, `Dont forget the rope`], `context` = [`Hey`]; sonuç [`Bunu daha önce gördüm`,
`TR Bring…`, `TR Dont forget the rope`, `TR Bring…`]; sonra tek satırlık `Dont forget the rope` istek atmaz. `maxLines` 2 iken 3 satır → 2 istek.

**Sonradan iyileştirme:** okuma hattı pakette bulamadığı satırı havuza önerirken (§6.1) aynı anda (ortak havuz açık ya
da havuz öncelikli ise) arka planda tek satır sorusu atar; çeviri gelirse ve satır hâlâ ekrandaysa TV'deki çevirinin
yerine konur, günlükte kaynak "havuz" olur; paketten gelen satıra dokunulmaz; satır kalktıysa yalnız hatırlanır; aynısı
yeniden gelirse gönderilmez (okuma hattı belgesi). Çeviri sürerken havuza çeviri inerse motorun sonucu yerine o gösterilir.

**Disk dosyası** `pool-translations\translations-<dil>.json`:
```json
{"language":"tr","texts":{"<16 hex>":"<çeviri>"},"cursors":{"<oyun kimliği ya da boş>":{"since":30,"after":"","checked":1763300181.0}}}
```
- Yazılır: indirmeden sonra (değişiklik varsa), dil değişirken (eski dil), kapanışta. Değişiklik yoksa yazılmaz.
- Dil başına en çok **400 000** çeviri yazılır (fazlası atılır).
- Önce `.tmp`, sonra yerine taşıma. ASCII dışı karakterler kaçışsız.
- Açılışta ve dil değişince o dilin dosyası okunur; ortak havuz kapalıysa bellek **boş** tutulur (dosya silinmez). Açılınca
  dosya yeniden okunur; kapatılınca bellek boşalır.

**Dil değişince:** eski dil yazılır, yeni dilin dosyası ve imleçleri yüklenir; bu arada süren indirmenin yanıtı atılır.
Örnek: `tr` 2 çeviri, `ar-SA`'ya geçince 0, indirme `lang=ar` ile 1; arada sorulan çeviri `"lang":"ar"` ile gider;
`tr`'ye dönünce 2 ve o soru Türkçe bellekte yok; `ar`'a dönünce 2 (soru dahil).

### 8.5 "Buradayım"
`GET <sunucu>/v1/ping?install=<uuid>&platform=windows&app=<sürüm>&game=<kimlik ya da boş>&lang=<kod>` (değerler URL
kaçışlı; `game=` boş da yazılır). 15 sn zaman aşımı; yanıt okunmaz, hatalar yutulur. Ortak havuz kapalı ya da adres yoksa
gönderilmez. Son gönderimden **55 sn** geçmeden yenisi gönderilmez. Örnek: iki ardışık çağrı → tek istek; 60 sn sonra
oyunsuz → `game=&` içerir.

### 8.6 Oyunu ekrandan tanıma
Oyun bilinmiyorsa (PS5 söylemiyor, kullanıcı seçmedi, paketten tanınmadı) Remote Play karesinden tanınır.
- Koşul: çeviri çalışıyor, ortak havuz açık (ayar ve havuz), kaynak `en`, ve (paket kapsamı yok **ya da** havuz öncelikli
  değil).
- Zamanlama: yeni oturumda sayaçlar sıfırlanır. Oyun bilinmiyorsa ilk bakış oturumdan **8 sn** sonra, sonra **60 sn**
  arayla, en çok **6** deneme. Oyun **ekrandan** tanındıysa doğrulama: ilk **5 dk** sonra, sonra **20 dk**'da bir, en çok
  **12**. Oyun konsoldan, kullanıcıdan ya da paketten biliniyorsa bakılmaz. Aynı anda tek istek ("son bakıştan bu yana
  süre > bekleme" koşulu).
- Kare en çok **768 px** genişliğe küçültülüp JPEG kalite **60** ile kodlanır (Windows görüntü kodlayıcısı, başka belge);
  0 bayt ya da **450 KB**'tan (460 800 bayt) büyükse gönderilmez.
- `POST <sunucu>/v1/identify` (30 sn, yalnız 200), gövde **yalnız şu 5 alan**:
  `{"v":1,"install":"<uuid>","app":"0.2.1","platform":"windows","image":"<base64 jpeg>"}` →
  `{"ok":true,"game":"Grand Theft Auto VI","id":"grand-theft-auto-vi","confidence":0.92}`. Yalnız `game` okunur
  (kırpılır); boş ya da `null` → tanınamadı.
- Sonuç (günlüğe kısa Türkçe notlar; metni yeni yazılır): tanınamadıysa deneme numarasıyla "tanınamadı" ya da yeniden
  bakışta seçilemediği ve eski oyunun (X) kaldığı. Tanınan oyunun kimliği bilinenle aynıysa X'in doğrulandığı. Değilse
  X'in ekrandan tanındığı ya da oyunun A'dan B'ye değiştiği; oyun "ekrandan görüldü" kaynağıyla değişir, oyun sorusu
  (`reading.gamePicker.title`) kapanır.
- Ortak havuz kapalıysa istek atılmaz (sessiz).

### 8.7 Kurulum kimliği (çeviri havuzu)
`pool-translations\install` dosyası: içerik (kırpılmış) geçerli GUID ise o (küçük harf, tireli), değilse yeni üretilip
yazılır. Sunucu bu kimliği yalnız tuzlanmış özetiyle tutar (kaba hız sınırı için). Aynı klasörle açılan ikinci nesne aynı
kimliği okur.

### 8.8 Test senaryoları (sahte sunucu, adres `http://localhost:8787/`, sürüm `0.2.1`, saat 1 763 300 000)
- `Lower the bridge.`, bağlam [`a`, `Halt!`, `State your name.`, `It's late.`, `Quickly!`], oyun `Red Dead Redemption 2`:
  iki kez sorulur → ikisi de `Köprüyü indir.`, tek POST; `lower the BRIDGE` bellekte bulunur; gövdede `v` 1, `platform`
  `windows`, `lang` `tr`, `game` `red-dead-redemption-2`, `lines` [`Lower the bridge.`], `context` son 4.
- Sunucu bekletirken aynı satır iki kez → tek istek, iki sonuç da `Köprüyü indir.`.
- Gürültü gönderilmez: `%%% ### !!!`, `1234`, boş.
- Ortak havuz kapalı: bellek 0 (diskte 1 çeviri olsa da), soru yok, indirme 0, ping yok, "etkin" hayır; açınca 1,
  kapatınca 0. Ama GTA 6 için soru gider (`grand-theft-auto-vi` gövdede), RDR 2 için gitmez.
- Sunucu `translate.enabled:false` → soru yok, indirme 0, "etkin" hayır, `/v1/config` tek kez soruldu.
- Ping: `install=…`, `platform=windows`, `app=0.2.1`, `game=red-dead-redemption-2`, `lang=tr`.
- Tanıma: `FF D8 FF E0 01 02 03 FF D9` → `Grand Theft Auto VI`; gövde alanları sıralı: app, image, install, platform, v;
  `game:null` → yok; 500 → yok; 450 KB + 1 bayt → istek atılmaz; toplam 3 istek. Ortak havuz kapalı → istek yok.

### Mac'ten farkı (§6–§8)
- Adres sırası: ortam değişkeni → `pool\endpoint.txt` → canlı (Mac: ortam değişkeni → `ninoPoolURL` ayarı).
- "Buradayım" sınırı 55 sn (Mac "dakikada bir").
- Uzak ayar zamanı başarısız denemede de işaretlenir (10 dk boyunca yeniden sorulmaz).
- İki kurulum kimliği (kuyruk `state.json`, çeviri havuzu `install` dosyası).
- Windows'ta "oyun kesin bilinmiyorsa sunucuya süreli sor" diye ayrı bir çeviri dalı **yoktur**; sunucuya her bilinmeyen
  satır zaten §8.4 "sonradan iyileştirme" ile arka planda sorulur ve sunucunun söylediği oyun havuz önceliğini açar.

---

## 9. Eski satır kuyruğu (ölü kod, yeniden yazılmaz)

Eski kodda `POST <sunucu>/v1/lines` ile 5 dk'da bir 200'lük parçalar gönderen tek dosyalı bir kuyruk sınıfı ve testleri
duruyor, ama **uygulamada hiçbir yerde kurulmuyor**. Yeni kodda yazılmamalı. Yaşayan iki parçası:
- Gürültü denetimi (§6.1 madde 2) bu sınıftaydı; yeni kodda süzgecin parçası olarak yazılır.
- "Ortak havuz varsayılan açık" bilgisi bu sınıftaki sabitten okunuyordu; yeni kodda ayarın varsayılanı.
- Dosya biçimi yalnız içe aktarma (§7.6) için bilinmeli: `pool.json` =
  `{"install":"<uuid>","queue":[{"text":"…","key":"<16 hex>","firstSeen":"2026-11-11T03:17:00Z","titleId":"PPSA12345"?,
  "game":"…"?}],"sent":["<16 hex>",…],"retryAfter":<unix sn>|null}`. İçe aktarmada yalnız `queue[].text` ve
  `queue[].firstSeen` okunur.

Bu ölü sınıfın kendi süzgeci ortak kurallara ek olarak "en az 2 harfli sözcük, en çok 300 karakter" isterdi; test
vektörlerinin bir kısmı (ör. `Okay.` ret) yalnız ona aittir (§6.1'de ayrıldı).

---

## 10. Windows'a özgü kısımlar

| Yetenek | Ne için | Ayrıntı |
|---|---|---|
| `%LOCALAPPDATA%\Nino\` | bütün veri | `packs\`, `packs-remote.json`, `pool\`, `pool.json(.imported)`, `pool-translations\` |
| Ağ erişilebilirlik olayı (.NET ağ değişikliği bildirimi) | kuyruk ağ gelince hemen göndersin | "erişilebilir" olunca artan bekleme sıfır + deneme |
| Dosya kimliği sorgusu (birim seri no + 128 bit dosya kimliği) | içe aktarmada kaynak=hedef denetimi | desteklenmezse bağlantıları çözülmüş yol karşılaştırması |
| Atomik dosya değiştirme (aynı birimde üstüne yazarak taşıma) | kuyruk, durum, havuz dosyaları, paketler | önce `.tmp` / `.download`, sonra taşıma; kuyruk parçalarında diske boşaltma |
| Derleme meta verisi `NinoPacksUrl` | paket sunucusu adresi | uygulama projesinde MSBuild özelliği; bugün boş |
| Görüntü kodlayıcı (WPF JPEG) | oyun tanıma karesi | 768 px, kalite 60 (başka belge) |

---

## 11. Asıl oyun kimliği (sunucuya giden tek kimlik)

Sunucu aynı oyunu tek kimlikte toplar; uygulama da her gönderimde o kimliği kullanır: GTA 6 → `gta-6`, GTA 5 → `gta-v`
(`grand-theft-auto-vi`, `gta-vi`, `gta6`, `gtavi`, `pool-gta-6`, `grand-theft-auto-v`, `gta-5`… gitmez). Yazım:
`apps/windows/src/Nino.Core/Library/GameIds.cs`.

- **Çeviri:** kimlik küçük harfe çevrilir, art arda tireler teke iner, sonra takma ad tablosuna bakılır (tablo sunucunun
  tablosuyla aynı: 17 takma ad, 27 okunur ad). Addan kimlik: önce §7.1'deki kimlik üretimi, sonra bu çeviri
  (`Grand Theft Auto VI` → `grand-theft-auto-vi` → `gta-6`; `Ghost of Yōtei` → `ghost-of-yotei`).
- **Okunur ad:** tablodaki ad; yoksa kimlik `- _ .` yerlerinden bölünür, sözcüklerin ilk harfi büyük, yalnız i–x Romen
  rakamları tümüyle büyük (`final-fantasy-xvi` → "Final Fantasy Xvi").
- **Gönderim noktaları:** satır kuyruğu (`pending.jsonl` `g`, parça `game`), çeviri sorusu `game`, toplu indirme ve
  "buradayım" `game=`, ölçüm `session.game`, teşhis `diag.game`. Ölçüm ve teşhis gövdesi kimliği kendisi de çevirir.
  Sorun bildirimi ve Nino'ya Sor gövdesinde oyun kimliği alanı yoktur (oyun yalnız cihaz özetinde ad olarak geçer).
- **Eski veri:** eski sürümün bıraktığı bekleyen satırlar okunurken, dondurulmuş parçalar gönderilirken çevrilir (dosya
  değişmez; değişecek bir şey yoksa gövde bayt bayt aynı). `translations-<dil>.json` `cursors` anahtarları okunurken
  asıl kimliğe birleşir, dosya yeniden yazılır; iki imleç çakışırsa daha geride olanı (küçük `since`) kalır.
- **Havuz önceliği:** sunucunun `poolFirst.games` listesi ve oyun hem yazıldığı gibi hem asıl kimlikle karşılaştırılır.
- **Ekrandan tanıma:** sunucunun verdiği ad tablodaki bir oyunsa okunur adıyla tutulur ("GTA 6").
- **Paketler:** paket kimliği, dosya adı, `v1/packs/<id>` ve `packs-remote.json` değişmez. Paketin oyunu: kimlik
  (`community-` öneki atılarak) tabloda biliniyorsa o, yoksa başlıktan üretilen asıl kimlik. Ayarlar'daki liste ve oyun
  seçici aynı oyunu tek satır gösterir (ad tablodan ya da paketin başlığından, satır sayısı en büyüğü). Kapsam paketi
  havuza oyun ipucu olarak giderken de bu kimlik kullanılır.
- **Karşılaştırma:** iki oyun, ad anahtarları (§2.5) ya da asıl kimlikleri eşitse aynıdır; GTA 6'ya özgü kararlar
  (telefon, ekrandan GTA 6 sayma) bu yüzden takma adlarla da çalışır.
