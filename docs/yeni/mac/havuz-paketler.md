# Mac: havuz ve oyun paketleri (tarif)

Bu belge eski Mac uygulamasının oyun paketlerini, paket güncellemesini, ortak havuzu (satır gönderme ve çeviri
havuzu), altyazı geçmişini ve günlüğünü nasıl işlettiğini anlatır. Kod yoktur.
Çeviri zinciri için bkz. `ceviri.md`.

**Birebir aynı kalması gerekenler** (sunucu, öbür platformlar ve eski veriyle ortak): §1 anahtar, §3.3 bulanık
imza ve dizin biçimi, §2.1 paket dosyası, §4 ve §6 sunucu istek/yanıtları, §6.6 disk dosyası. Gerisi davranıştır.

## 1. Satır anahtarı

Paketlerde ve havuzda İngilizce metin **yoktur**; satır bu anahtarla bulunur.

Sadeleştirme (canon), sırayla:
1. `<…>` biçim etiketleri (içinde `<` `>` olmayan, en çok 40 kod noktası) boşluk olur.
2. NFKC.
3. Küçük harf.
4. NFD; birleşen işaretler (aksanlar) atılır.
5. Harf ve rakam (Unicode genel kategorisi: harf türleri, ondalık/harf/diğer sayı) dışındaki her şey ayraçtır.
6. Ayraçlar tek boşluk; baş ve son boşluksuz.

Anahtar: canon boşsa yok; değilse `SHA-256(canon, UTF-8)`'in ilk 8 baytı, 16 haneli küçük hex. Sözlükte sayı
olarak da tutulabilir (16 hex → 64 bit; büyük/küçük harf fark etmez).

| Girdi | canon | anahtar |
|---|---|---|
| `Duck behind the crates, rookie!` | `duck behind the crates rookie` | `0885d31ab6df7d0a` |
| `Don’t leave the convoy.` | `don t leave the convoy` | `411111ea3f2b7b24` |
| `<i><c>RUSTY LANTERN</></> FOUND` | `rusty lantern found` | `f8e7d3908b0714fb` |
| `Move It!` | `move it` | `2a92733a6f2bf2c2` |
| `  Where   did\nthey go?  ` | `where did they go` | `b0da4da3c1d33090` |
| `Señor, más rápido.` | `senor mas rapido` | `558a6a04622a42bd` |
| `İzmir` | `izmir` | `f3698e3490018159` |
| `Ｇａｔｅ　７` | `gate 7` | `a4b972de42a56651` |
| `Øresund œuvre` | `øresund œuvre` | `0c867223ed23da1b` |
| `...` / boş | boş | yok |

(Anahtarlar havuz sunucusunun `nino-pool/src/key.js` koduyla hesaplandı; aynı örnekler NinoCore `LineKeyTests`'te.)

### NinoCore'da eksik
- Bu anahtar yok. NinoCore'un anahtarı (`Sources/NinoCore/Translation/Translation.swift`: küçük harf, kıvrık
  tırnak düzleştirme, noktalama korunur) farklı; `Run.` ile `Run?` ayrı sayılıyor, eski anahtarda aynı.
  Eski paketler, havuz indirmeleri ve sunucu bu anahtarla çalışır.

## 2. Oyun paketleri

### 2.1 Dosya

gzip'li ya da düz JSON (`.json.gz` ya da `.json`). İlk iki bayt `1f 8b` ve boy ≥ 18 ise gzip sayılır; gzip
başlığı (RFC 1952: FEXTRA, FNAME, FCOMMENT, FHCRC) atlanıp gövde açılır, sondaki boy alanı tutmazsa bozuk.

İki biçim:

```json
{ "format": 2, "id": "mafia-the-old-country", "title": "Mafia: The Old Country",
  "entries":  { "c1aee1ba1957aeae": "Başını eğik tut, çaylak!" },
  "segments": { "…16 hex…": "…" },
  "fuzzy": { "version": 1, "count": N, "mask": "<base64>", "lengths": "<base64>", "blooms": "<base64>" } }
```

ya da yalnız `{ "<16 hex>": "Türkçe", … }` (kimlik ve başlık dosya adından: `mafia.json.gz` → `mafia`).

- `format` 1 ya da 2 değilse yüklenmez. `title` yoksa `id`, `id` yoksa dosya adı.
- `entries`: tam satırlar. `segments` (biçim 2): oyunun ayrı gösterdiği parçalar, çok cümleli satırların cümleleri.
- Geçersiz anahtar (16 hex değil) ya da metin olmayan değer atlanır. Türkçedeki biçim etiketleri silinir
  (`<…>` → hiç), boşluklar teklenir, kırpılır; boş kalan çeviri saklanmaz ama anahtar sırasında sayılır (§3.3).
- `entries` boşsa paket yüklenmez.
- `fuzzy` bozuksa paket yine yüklenir, yalnız bulanık arama olmaz.

### 2.2 Kütüphane

Klasörler (okuma sırası): uygulamayla gelen paketler (bugün 9 oyun: Assassin's Creed Shadows, CoD MW 2019,
Death Stranding 2, Death Stranding DC, Elden Ring, GTA V, Mafia The Old Country, Spider-Man 2, RDR2), kullanıcı
klasörü `~/Library/Application Support/Nino/packs/` (sunucudan inenler ve Mac'te içe aktarılanlar da buraya).
  Kütüphane üçüncü bir "içe aktarılanlar" klasörünü de destekler (telefonda kullanılır, en son okunur); Mac
  bunu bağlamaz.

- Klasörde ad sırasıyla `.json.gz` ve `.json` okunur. Bozuk dosya sessizce atlanır.
- Aynı `id` sonra gelirse öncekinin yerine geçer (kullanıcınınki uygulamanınkini ezer).
- Tek sözlükte birleşir: önce **bütün paketlerin `segments`'i**, sonra **bütün `entries`**; aynı anahtarda sonraki
  kazanır. Bir oyunun tam satırı başka oyunun parçasına yenilmez.
- İlk kullanımda (açılışta arka planda) yüklenir; `yeniden yükle` hepsini sıfırlar.
- Bilgi listesi: kimlik, başlık, satır sayısı (`entries`), uygulamayla mı geldi.
- Paketler yalnız `en`→`tr` ve "oyun paketleri" açıkken kullanılır.

### 2.3 Hangi oyun? (kapsam)

- **Kapsam** = son tam eşleşmenin geldiği paket. Bulanık arama yalnız bu pakette yapılır. Hiç tam eşleşme yoksa
  bulanık arama yok.
- Tam eşleşen anahtar yalnız bir pakette varsa: kapsam o paket ve "ayırt edici isabet" o paket. Birden çok pakette
  varsa (ortak satırlar: `Okay.`, `Let's go.`): kapsam bu paketlerden biri değilse ilkine geçer, ayırt edici isabet
  sayılmaz.
- Ayırt edici isabet okununca silinir; oyun tanıma (art arda aynı paketten gelen satırlar) bunu kullanır.
- Kapsamın kimliği havuza oyun ipucu olarak gider; başlığı yapay zekâya **gitmez** (oyun adı oyun tanımadan gelir).
- **Elle seçilen oyun**: kullanıcı oyunu seçtiyse satırlar **yalnız o oyunun paketinde** aranır (tam ve bulanık),
  Türkçe de o paketin kendisinden. Paket = başlığı ya da kimliği seçilen adla aynı anahtara inen son paket (genel
  paket `pool-genel` hariç; ad anahtarı aşağıda). Paketi yoksa **hiç aranmaz**
  (paketi olmayan oyunda kısa genel satırlar başka oyunun çevirisini getiriyordu). Seçim değişince kapsam sıfırlanır.
- Havuz öncelikli oyunda (GTA 6) paketlere hiç bakılmaz.

**Oyun adı anahtarı** (adları karşılaştırmak için): `™ ® ©` boşluk; NFKD, küçük harf, işaretler atılır; kesme işaretleri (`'`, `’`, ters tırnak)
silinir; `ı`→`i`; `&` → ` and `; harf/rakam dışı boşluk; harf ile rakam arasına boşluk (`gta6` → `gta 6`); Roma
rakamı sözcükleri sayı (`ii`…`xvi` → 2…16, `v` → 5); baştaki `the` atılır (tek sözcük değilse); kısaltmalar:
`grand theft auto`→`gta`, `call of duty`→`cod`, `red dead redemption`→`rdr`, `ea sports fc`→`fc`, `ea sports`→(sil);
tek boşluk, en çok 80 karakter. `Grand Theft Auto VI` → `gta 6`; `GTA6` → `gta 6`.

### 2.4 Arama sırası

Önce yalnız **tam anahtarla** aşağıdaki aşama; hiçbir yol tutmazsa aynı aşama bir kez daha, bu kez her parça önce
tam, sonra bulanık (§3) aranır. Aynı parça bir aramada bir kez bulanık hesaplanır.

Aşama:
1. **Tek satır** olarak:
   1. Başında konuşmacı etiketi/tire varsa (`- TOMAS: `) etiketsiz gövde; bulunursa etiket + Türkçe.
   2. Satırın tamamı.
   3. OCR'ın bozduğu etiket (§2.5): gövde aranır, bozuk etiket ekranda kalır.
2. **Birden çok satırsa** her satır tek satır olarak. Hepsi bulunmalı; bulunmayan satır **köşe yazısıysa** atlanır.
   Köşe yazısı: ≤ 4 sözcük ve (`•` içeriyor ya da her sözcük büyük harfle başlayıp yalnız harf/rakam). Çeviriler
   satır sonuyla birleşir.
3. **Cümle cümle** (çevrilecek parça > 1): etiket, tire ve ayraçlar aynen, her cümle bulunmalı.
4. Hiçbiri: yok.

Okuma hattı ayrıca: satır bulunamazsa konuşmacı öneki atılmış gövdeyle bir kez daha sorar; altyazının yerinde
olmayan ve 3 sözcükten kısa yazının paket sonucu gösterilmez.

### 2.5 Bozuk etiket

İlk 32 karakter içinde `:` ya da `•` var ve önündeki son sözcükte küçük harf yok (en az 1 harf) → etiket = başlangıçtan
işarete kadar + boşluk; gövde = işaretten sonra ilk harf/rakamdan itibaren. Gövdede harf yoksa yok.
İşaretsiz: baştan en çok 3 büyük harfli sözcük (her biri ≥ 2 harf, küçük harfsiz), ardından büyük harfle başlayıp
küçük harfle süren sözcük.

| Girdi | Etiket | Gövde |
|---|---|---|
| `-BRUNO: Keep moving` | `-BRUNO: ` | `Keep moving` |
| `K]: Did anyone see the truck?` | `K]: ` | `Did anyone see the truck?` |
| `ri MARTA: over here` | `ri MARTA: ` | `over here` |
| `HARLAN Keep your voice down` | `HARLAN ` | `Keep your voice down` |
| `MCKAY Not a chance.` | `MCKAY ` | `Not a chance.` |
| `I said: wait` | yok | yok |

### NinoCore'da eksik
- Paket biçimi tamamen farklı: NinoCore `.ninopack.json` (açık İngilizce `source`, `terms`, `speaker`) kullanıyor.
  Uygulamayla gelen 9 paket, sunucudaki paketler ve havuz indirmeleri bu biçimle okunamaz. Ya eski biçim okunmalı
  ya da paketler dönüştürülmeli (İngilizce metin olmadığı için dönüştürme ancak anahtarı koruyarak olur).
- gzip açma yok.
- `segments`, birleştirme önceliği (parça < tam satır), birden çok klasör, `id` ezme kuralı (NinoCore sürüm
  büyüğünü tutuyor) farklı.
- Kapsam, ayırt edici isabet, elle seçilen oyunla sınırlama yok (NinoCore'da yalnız "seçili oyunun paketi").
- Aşamalı arama (etiketsiz gövde, satır satır, köşe yazısını atlama, cümle cümle, bozuk etiket) yok.

## 3. Bulanık eşleme (OCR hataları)

İki yol var; ikisi de yalnız **kapsam paketinde** (ya da elle seçilen oyunun paketinde) çalışır.

### 3.1 Tek düzeltme

canon uzunluğu 6–48 ise satırın tek bir OCR düzeltmesiyle olabileceği hâller üretilir ve pakette **tam anahtarla**
aranır:
- karıştırılan dizi değişimi (okunan → asıl): `rn→m, m→rn, cl→d, d→cl, vv→w, ri→n, n→ri, li→h, l→i, i→l, 1→l, 1→i,
  0→o, 5→s, j→i, c→e, e→c, a→o, o→a, h→b, b→h, f→t, t→f, u→v, v→u, y→v, v→y, q→g, g→q`;
- bir harf ya da bir boşluk düşer;
- sözcük ikiye bölünür (`cant` → `can t`).
Başta/sonda boşluk ya da çift boşluk olan hâller atılır; özgün hâl atılır. Bulunan hâllerin **hepsi aynı Türkçeye**
çıkmıyorsa sonuç yok.

### 3.2 Bloom benzerliği

Katlama: canon, boşluksuz; `l 1 ı j → i`, `0 → o`, `5 → s`, `æ → a`, `ø œ → o`, `ß → s`.

| Girdi | Katlanmış | Bozuk mu | Uzunluk | Bit |
|---|---|---|---|---|
| `Stay cIose to me, kid.` | `stayciosetomekid` | hayır | 16 | 64 |
| `Where's the old mill?` | `wherestheoidmiii` | hayır | 16 | 64 |
| `We rnust reach the 5outh gate.` | `wernustreachthesouthgate` | evet | 24 | 128 |
| `CAPTAİN: The engine room is f1ooding•fast.` | `captaintheengineroomisfioodingfast` | evet | 34 | 128 |

İmza:
- Katlanmış uzunluk < 16 → imza yok, bulanık arama yok.
- Uzunluk = min(harf sayısı, 255).
- Bit sayısı: 64'ten başla, `uzunluk × 3 > bit` ve bit < 256 iken iki katına çıkar (64/128/256).
- Her **farklı** ardışık üçlü için FNV-1a 64 (başlangıç `0xcbf29ce484222325`, çarpan `0x100000001b3`) üçlünün
  UTF-8 baytları üstünde; bit = `özet & (bit − 1)`; o bit 1 yapılır.
- Bayt dizisi: 64 bitlik sözcükler sırayla, her sözcük küçük sonlu (little-endian) 8 bayt.

Benzerlik (0–100, rastlantı arındırılmış): ortak = `sorgu & aday` bit sayısı; `qa = ortak/sorgu_bit − aday_dolu`,
`/(1 − aday_dolu)`; `aq` simetrik; `benzerlik = 100 × min(qa, aq)`. Doluluk = 1 bit sayısı / bit. Biri boş ya da
tamamen doluysa 0. Örnek: `The engine room is flooding fast, captain.` ile bozuk okuması
`The engine roorn is f1ooding fast, captaín.` (128 bit) → **82.34**; ilgisiz `Where's the old mill?` ile → 10.36
(tarif kurallarından bağımsız hesap; testler eşleşir/eşleşmez olarak sınar).

**Bozuk satır** (OCR izi): şunlardan biri:
- ASCII dışı karakter (tipografik `’ ‘ “ ” — – …` hariç);
- sözcük içinde (iki yanı harf) harf olmayan işaret (`' ’ -` hariç);
- sözcükte harf ile rakam bitişik;
- tek harfli sözcük ve `a A I o O` değil;
- 14 karakterden uzun sözcük.
(Sözcüğün baş/sonundaki `.,!?;:'"()[]-…“”’‘` atılarak bakılır.)

**Kabul eşiği**: temiz satır uzunluk < 24 → 90, < 256 → 80; bozuk satır < 24 → 70, < 40 → 60, değilse 55.
Ayırma payı 5.

Arama:
1. **Yakın boy**: aday uzunluğu `[L − L/4, L + L/4]` (tam sayı bölme, üst sınır 255). Benzerlik
   `≥ eşik − 5` olanlar aday.
2. En iyi aday `≥ eşik` değilse yok. Türkçesi farklı başka bir aday `> en iyi − 5` ise **belirsiz**, yok.
3. Yakın boyda kabul yoksa, belirsiz değilse ve `L ≥ 22` ise **tek yönlü kapsama**:
   - Aday aralığı `[max(22, L×11/20), min(255, L×5/2)]`, aday uzunluğu ≥ 22 ve L'den farklı.
   - Hızlı eleme: ortak bit × 10 ≥ 9 × (kısa tarafın bit sayısı).
   - Kısa tarafın kapsanma oranı ≥ 90; uzun tarafın kısa tarafta olan oranı ≥ 25 (aday uzun: satır yarım okunmuş)
     ya da ≥ 55 (aday kısa: okumada fazlalık var).
   - Puan = kısa tarafın kapsanma − 10, `≥ eşik − 5` olmalı.
   - Aday kısa ise **yan cümle denetimi**: okuma birden çok yan cümleyse, köşe yazısına benzemeyen her yan cümlenin
     (katlanmış ≥ 6 harf) üçlülerinin en az %30'u (arındırılmış) adayda olmalı. İlk yan cümlenin başındaki ve
     sonuncunun sonundaki en çok 3 büyük harfli sözcük atılmış hâli de seçenektir.
   - Sonra yakın ve tek yönlü adaylar birlikte 2. adımdaki gibi seçilir.

Yan cümle bölme: `. ! ? … , ; :` dizisi (+ kapanış tırnak/ayraç) ardından boşluk ve (büyük harf **ya da** dizide
`, ; : …` veya birden çok nokta var). Tek noktadan sonra küçük harf bölmez. 6 harften kısa yan cümle sonrakine
(sonuncuysa öncekine) eklenir.

### 3.3 Paketteki dizin biçimi

`fuzzy` nesnesi (paket betiği üretir):
- `version: 1`, `count` = paketteki bütün geçerli anahtar sayısı (`entries` ∪ `segments`, Türkçesi boş kalanlar
  dahil), sayı sırasıyla.
- `mask` (base64): `count` bit; i. anahtarın imzası varsa `bayt[i>>3]`'ün `(i & 7)`. biti 1 (düşük bitten başlar).
  Bayt sayısı `(count + 7) / 8` olmalı.
- `lengths` (base64): imzalı her anahtar için 1 bayt uzunluk.
- `blooms` (base64): imzalı anahtarların Bloom baytları art arda (her biri `bit / 8` bayt).
- Tutarsızlıkta (sayı/boy tutmuyor) dizin yok sayılır.

### NinoCore'da eksik
- NinoCore'un bulanık eşlemesi (`Sources/NinoCore/Packs/TranslationPack.swift`: harf/rakam anahtarı ≥ 12, ortak
  sözcük, boy %80–125, son işaret türü, benzerlik ≥ 0.90) açık İngilizce metin istiyor; eski paketlerde metin yok.
- Tek düzeltme yolu, Bloom imzası, bozuk satır eşikleri, belirsizlik payı, tek yönlü kapsama, yan cümle denetimi yok.
- Ortak test verisi (`fuzzy-vectors.json`) NinoCore testlerine alınmalı.

## 4. Paket güncelleme (sunucudan)

- Adres sırası: ortam değişkeni (`NINO_PACKS_URL`), kullanıcı ayarı (`packsURL`), uygulama yapılandırmasındaki
  paket adresi. `http`/`https` ve makine olmalı; `$(` ile başlayan (doldurulmamış derleme değişkeni) atlanır.
  Hiçbiri yoksa özellik kapalı (bugünkü durum). Yeni uygulama yapılandırma anahtarına yeni bir ad vermeli.
- Ne zaman: açılışta ve 24 saatte bir; PS5'te yeni oyun tanınınca son bakış 10 dk'dan eskiyse. Son bakış taze ise
  atlanır, **ancak** önceki seferde inemeyen paket varsa yine bakılır.
- `GET <adres>/v1/packs` → `{"packs":[{"id","title","version","sha256","size"?,"entries"?}]}`.
- `GET <adres>/v1/packs/<id>` → paket dosyası; en çok 64 MB. Zaman aşımı 60 sn.
- Kimlik `^[a-z0-9][a-z0-9-]{0,63}$`, sha256 64 hex değilse paket atlanır.
- Her paket için (dosya `<klasör>/<id>.json.gz`):
  - Kayıtlı sürüm ve sha aynı, diskteki dosyanın sha'sı da aynı → dokunulmaz.
  - Diskte dosya var ama sha'sı ne kayıtlıya ne yeniye eşit → **kullanıcının dosyası**, üstüne yazılmaz.
  - İndirilen verinin sha'sı tutmazsa yazılmaz; eski sürüm "inemedi" (sürüm −1) olarak tutulur, sonra yeniden denenir.
  - Önce `.<id>.download` geçici dosyasına, sonra yerine konur (yarım dosya hiç yüklenmez).
- Sunucudan kalkan paket silinir (yalnız diskteki sha kayıtlıyla aynıysa).
- Bir paket inemediyse "son bakış" zamanı ilerletilmez.
- Durum dosyası paket klasörünün **dışında** (`~/Library/Application Support/Nino/packs-remote.json`):
  `{"checked": <unix sn>, "packs": [{"id","title","version","sha256"}]}`.
- Paket inince ya da silinince kütüphane yeniden okunur.
- İndirilenleri silme düğmesi: kullanıcının değiştirmediği, sunucudan gelmiş paket dosyalarını ve durum dosyasını kaldırır.
- Sunucu her gece havuzdan otomatik paket üretir (`pool-<oyun kimliği>`, genel paket `pool-genel`).

### NinoCore'da eksik
- Paket güncelleme hiç yok.

## 5. Paket içe aktarma (kullanıcının dosyası)

Desteklenen: `.json`, `.txt`, `.srt` (en çok 64 MB, UTF-8, baştaki BOM atılır).

- **JSON**:
  - `format` sayısı varsa 1 olmalı, `entries` nesnesi 16 hex anahtar → Türkçe; başlık `title` ya da `game`.
  - `format` yok ama `entries` var → desteklenmiyor.
  - `subtitles` nesnesi: İngilizce → Türkçe (anahtar §1 ile hesaplanır); başlık `game` ya da `title`.
  - Düz nesne: İngilizce → Türkçe.
  - Aynı anahtar birden çok kez geçebilir; sırası korunarak okunur.
- **TXT**: `#` ile başlayan ve boş satırlar atlanır; `İngilizce<TAB>Türkçe` (tam bir sekme) ya da sekmesiz
  `İngilizce = Türkçe`; başkası geçersiz sayılır.
- **SRT**: tam 4 satırlık bloklar: sıra numarası (yalnız rakam), `HH:MM:SS,mmm --> HH:MM:SS,mmm` (başlangıç <
  bitiş), İngilizce, Türkçe. Başka blok geçersiz.
- Sayılar: geçersiz (anahtar yok ya da Türkçe boş), yinelenen (aynı anahtar aynı Türkçe), çelişen (aynı anahtar
  farklı Türkçe: anahtar **hiç alınmaz**).
- Kimlik: başlıktaki ASCII harf/rakamlar küçük harf, aradakiler tek `-`, en çok 80 karakter, başına `community-`
  (boşsa `community-game`). `Mafia: The Old Country` → `community-mafia-the-old-country`.
- Yazma: `<klasör>/<kimlik>.json` biçim 1 (`{"format":1,"id","title","entries"}`). Başlık boş ya da satır yoksa hata.
  Değiştirme izni yoksa ve dosya varsa "zaten var" hatası. Kaynak dosya hedefle aynıysa hata.
- Mac'te hedef klasör kullanıcı paket klasörüdür (sunucudan inenlerle aynı). Sunucu güncellemesi bu dosyaya
  dokunmaz: sha'sı durum dosyasındakiyle tutmadığı için "kullanıcının dosyası" sayılır (§4). Telefonda ayrı klasöre
  yazılır ve en son okunur.

### NinoCore'da eksik
- İçe aktarma yok.

## 6. Ortak havuz

İki ayrı iş var: **satır gönderme** (pakette olmayan İngilizce satırlar sunucuya gider, yeni paketler bunlardan
yapılır) ve **çeviri havuzu** (sunucunun yaptığı çeviriler indirilir ve anında sorulur).

Sunucu: `https://nino-pool.y-demirbag2506.workers.dev`. Değiştirme: `NINO_POOL_URL` ortam değişkeni, sonra
`ninoPoolURL` ayarı. Ayar "ortak havuz" (varsayılan açık) kapalıysa hiçbir şey gönderilmez ve indirilmez (havuz
öncelikli oyunda anında soru hariç, `ceviri.md` §1.1). Bütün isteklerde
`User-Agent: nino-pool/1 (<platform>; <sürüm>)`, platform `mac`.

> Daha eski bir satır kuyruğu (tek JSON dosyası, `POST /v1/lines`, 5 dk'da bir) artık kullanılmıyor. Yalnız
> süzgeci (§6.1) ve gürültü denetimi yaşıyor; açılışta eski `pool.json` dosyasındaki gönderilmemiş satırlar bir kez
> yeni kuyruğa aktarılır ve dosya `pool.json.imported` adıyla kenara konur.

### 6.1 Süzgeç (hangi satır havuza gider)

Önce temizlik: denetim karakterleri (U+0000–001F, 007F–009F), sıfır genişlikli (U+200B–200F), U+2028/2029, U+FEFF
boşluk olur; boşluklar teklenir.

Kabul için hepsi:
1. Boş değil, en çok 500 kod noktası, harf içeriyor.
2. **Gürültü değil**: OCR çöp temizliğinden sonra canon değişiyorsa çöp (çöp kuralları `okuma-hatti.md` §5.4); görünür
   karakterlerin yarısından azı harfse çöp (`100/100 HP 25%`).
3. **Yarım okuma değil**:
   - Cümle sonu (`. ! ? …`, kapanış tırnak/ayraç atılarak) yoksa ve (harfli sözcük < 3 ya da karakter < 15) → yarım.
   - Küçük harfle başlıyor → yarım (`and the boat sank slowly.`).
   - Cümle sonu yoksa ve son sözcük şunlardan biri → yarım: `the a an to of and or but with for from my your his
     her their our at in on by into than that if as is are was were` (`Take out the`).
   - Cümle sonu yok, harflerin hiçbiri küçük değil ve ≤ 6 sözcük → arayüz yazısı (`PHOTO MODE SELECT`).
4. **Türkçe değil**: `ğ Ğ ş Ş ı İ` var; ya da `ü Ü ö Ö ç Ç`'den ≥ 2 tane; ya da katlanmış sözcüklerden ≥ 2'si
   PS5 Türkçe arayüz sözcüklerine yakın (6+ harfte bir harf farkı serbest; liste: icin, lutfen, bekleyin, oyunu,
   oyun, oyunlar, kapat, ekran, ekranda, ekrani, sistemini, yeniden, baslat, ayarlar, ayarlari, kupalar, kupa,
   oturum, acti, kapatti, secenekleri, sifirlama, tut, kesfet, ilgili, takip, edin, ilerlemenizi, cikanlar,
   goruntusu, kaydedildi, bildirimler, arkadaslar, medya, galerisi, indiriliyor, guncelleme, kitaplik, denetleyici).
5. **PS5 sistem yazısı değil**: katlanmış satırda tam sözcük öbeği olarak: signed in, signed out, earned a trophy,
   trophy earned, trophy unlocked, screenshot saved, video clip saved, media gallery, is now online, joined the
   party, left the party, remote play, controller battery, controller is disconnected, controller disconnected,
   press the ps button, playstation network, download complete, installation complete, update available, turn off
   your console, cloud save, do not quit, photo mode, story mode, press any button, oturum acti, oturum kapatti,
   ekran ve video, oyunu kapat, ana ekranda tut, yeniden baslat, sifirlama secenekleri, lutfen bekleyin,
   ilerlemenizi takip.

Katlama: küçük harf, `ı`→`i`, aksansız, `q`→`c`, `l` ve `1`→`i`, harf/rakam dışı ayraç.

| Satır | Sonuç |
|---|---|
| `Stay low!` | kabul |
| `Take out the` | ret (yarım) |
| `PHOTO MODE SELECT` | ret (arayüz) |
| `Lutfen Bekleyin, Oyun Yukleniyor.` | ret (Türkçe sözcükler) |
| `Your friend signed in to the network.` | ret (sistem yazısı) |
| `Designed in the city.` | kabul (`signed in` tam öbek olarak geçmiyor) |

(Bu kurallar sunucudaki süzgeçle ve Windows ile aynıdır.)

Havuza önerilen satır: okuma hattı paket/havuz deposunda bulamadığı satırı verir. Paketler kapalıysa yalnız hiçbir
pakette olmayanlar önerilir. Altyazının yerinde olmayan yazı yalnız temiz okunmuşsa önerilir. Ek alanlar (görev,
bildirim, telefon) havuza **gitmez** (kişisel olabilir). Oyun ipucu: paket kapsamının kimliği, yoksa bilinen oyun.

### 6.2 Gönderme kuyruğu (kayıpsız)

Klasör `~/Library/Application Support/Nino/pool/`:
- `pending.jsonl`: her görülme bir satır `{"s":<sıra>,"t":"metin","g":"oyun"?,"e":"oturum"?,"a":<unix sn>}`,
  görüldüğü an sona eklenir.
- `outbox/`: gönderilecek parçalar; ad `<ms zaman 15 hane>-<sıra 4 hane>-<parça kimliği>.json`, ada göre sırayla.
- `parked/`: sunucunun kabul etmediği parçalar.
- `state.json`: `{"install","frozenThrough","failures","nextAttempt","serverRetryAt","app","dropped"}`.
- `rejected.jsonl`: sunucunun reddettiği satırlar ve nedeni (en çok 1 MB).

Kurallar:
- Kurulum kimliği: rastgele UUID, küçük harf. Oturum kimliği: her açılışta yeni UUID.
- Oyun kimliği: küçük harf; ASCII harf/rakam, `. _ -` dışı `-`; ardışık `-` teklenir; baş/son `- . _` atılır;
  en çok 64. `Mafia: The Old Country` → `mafia-the-old-country`. Boşsa yok.
- `pending.jsonl` 64 MB'yi aştıysa yeni satır yazılmaz, `dropped` artar.
- Gönderim zamanı: bekleyen ≥ 200 satır ya da en eski bekleyen ≥ 120 sn. Uygulama dakikada bir dener; ağ geri
  gelince hemen (artan bekleme sıfırlanır).
- Dondurma: bekleyenler sıra numarasıyla dilimlere (her parça en çok 200 **farklı** satır) bölünür; aynı
  (oyun, oturum, metin) birleşir: `count` artar, `first/last` en küçük/en büyük zaman. Parça diske yazıldıkça
  `frozenThrough` o parçanın son sırasına ilerler; sonra dondurulanlar `pending.jsonl`'dan atılır.
  `outbox/` 2000 parçayı geçtiyse dondurulmaz.
- Açılışta: yarım kalmış son satır kesilir; `frozenThrough` = durum ile parçaların en büyük `upTo`'su; uygulama
  sürümü değiştiyse `parked/` → `outbox/`; bekleme sıfırlanır. Okunamayan `state.json` silinmez,
  `state.broken-<zaman>.json` olarak kenara konur.
- Ortak havuz kapatılınca bekleyen, gönderilecek, kenara alınmış her şey silinir.

İstek: `POST <sunucu>/v1/batches`, 30 sn:
```json
{"v":1,"batch":"<uuid>","install":"<uuid>","app":"<sürüm>","platform":"mac",
 "lines":[{"text":"Stay low!","game":"gta-v","session":"<uuid>","count":3,"first":1763300000,"last":1763300100}],
 "upTo": 1234}
```
(Gövde parça dosyasının aynısı; anahtarlar sıralı, `/` kaçışlanmaz.)

Yanıta göre:

| Durum | Davranış |
|---|---|
| 2xx ve `{"ok":true,"batch":"<aynı kimlik>"}` | parça silinir, `rejected[]` (`{i, reason}`) günlüğe yazılır, bekleme sıfırlanır |
| 2xx ama kimlik tutmuyor | parça kalır, hata sayılır (yanlış sunucu) |
| 413 | satır > 1 ise ikiye bölünür (yeni kimliklerle), tek satırsa kenara |
| 429, 503 | `Retry-After` kadar beklenir (saniye ya da HTTP tarihi; yoksa 60 sn; 1 sn–1 gün) |
| 400, 422 | kenara (`parked/`) |
| diğer, ağ hatası | hata: bekleme `30 × 2^(hata−1)` sn, en çok 3600, ±%20 rastgele |

Bozuk parça dosyası silinmez, kenara konur. Aynı turda bir dosya iki kez denenmez.

### 6.3 Çeviri havuzu: uzak ayar

`GET <sunucu>/v1/config` (en çok 10 dk'da bir; 30 sn zaman aşımı):
```json
{"ok":true,
 "translate":{"enabled":true,"deadlineMs":900,"syncSeconds":180,"contextLines":4,"maxLines":12},
 "poolFirst":{"games":["grand-theft-auto-vi","gta-vi","gta-6","gta6"],"langs":["tr"],"deadlineMs":1500},
 "minVersion":{"mac":"","windows":"","android":"","ios":""}}
```
- Ulaşılamazsa bu varsayılanlar. `poolFirst` gelmezse ya da eksik alan varsa varsayılan kalır (eski sunucu).
- **Havuz öncelikli mi**: sunucu açık **ve** adres var **ve** hedef dil `langs` içinde (`*` hepsi; dil kodu `-`/`_`
  öncesi küçük harf) **ve** (oyun kimliği `games` parçalarından birini **içeriyor** ya da sunucunun son 600 sn
  içinde bir çeviri yanıtında söylediği oyun listede).
- Adaylardan oyun seçimi: listede olan ilk aday, yoksa ilk aday (paketten tahmin edilen oyun GTA 6'yı gölgelemesin).

| Oyun | Liste | Sonuç |
|---|---|---|
| `Grand Theft Auto VI` → `grand-theft-auto-vi` | varsayılan | evet |
| `gta-vi-enhanced` | varsayılan | evet (içeriyor) |
| `gta-v` | varsayılan | hayır |

### 6.4 Çeviri havuzu: toplu indirme

Oyun başlarken hemen, sonra dakikada bir denenir; gerçek indirme en erken `max(30, syncSeconds)` sn'de bir (oyun
başına). Ayrıca dakikada bir "buradayım":
`GET /v1/ping?install=…&platform=mac&app=…&game=…&lang=…` (15 sn, cevap okunmaz).

`GET /v1/translations?lang=<kod>&since=<sayı>[&game=<kimlik>][&after=<anahtar>]` → 
`{"ok":true,"now":…,"items":[["<anahtar>","<çeviri>",<güncellenme>,<aşama>]],"next":{"since":…,"after":"…"}|null}`
- Satırın ilk üç öğesi (anahtar, metin, sayı) okunur; eksik satır atlanır.
- `next` varsa imleç ona ilerler ve sonraki sayfa istenir (en çok 50 sayfa); yoksa `since` = görülen en büyük
  güncellenme, `after` boş.
- Dil değiştiyse gelen cevap atılır.
- İmleç oyun başına (`game` boşsa bütün oyunlar) tutulur.

### 6.5 Çeviri havuzu: anında soru

`POST /v1/translate`:
```json
{"v":1,"install":"<uuid>","app":"<sürüm>","platform":"mac","lang":"tr","game":"<kimlik ya da boş>",
 "lines":["satır"],"context":["önceki satır", "…"]}
```
→ `{"ok":true,"translations":[{"text":"çeviri"|null,"tier":…}],"game":"<sunucunun tanıdığı oyun>"?}`

- Sorulmaz: havuz kapalı (havuz öncelikli değilse), sunucu kapalı, adres yok, satır §6.1 süzgecinden geçmiyor ya da
  anahtarı yok.
- Satır depoda varsa istek atılmaz.
- Aynı (dil, anahtar) aynı anda iki kez sorulmaz: ikinci soran ilkinin sonucunu bekler.
- Bağlam: son `contextLines` (4) satır, en çok 30 sn önce görülmüş ve satırın kendisi değil. Satır eklenince listeye
  girer (en çok 4 tutulur, aynı metin yinelenmez).
- Zaman aşımı 20 sn. Yalnız 200 kabul. Yanıttaki `game` not edilir (§6.3).
- Boş olmayan çeviri depoya eklenir.
- **Süreli soru** (havuz öncelikli oyun): `poolFirst.deadlineMs` (100–10 000 arasına sıkıştırılır) dolunca yok
  döner; istek sürer, geç gelen depoya yazılır.
- **Çok satırlı soru** (telefon sohbeti, harita kartı): bilinenler hemen; aynı anda sorulanlar beklenir; kalanlar
  en çok `min(maxLines, 12)` satırlık isteklerle; varsayılan 10 sn. Yanıt sırası istekle aynı, eksik olan yok.
- **Sonradan iyileştirme**: pakette bulunmayan satır sorulduktan sonra sunucudan çeviri gelirse ve satır hâlâ
  ekrandaysa TV'deki çevirinin yerine konur (paketten gelen satıra dokunulmaz). Kalktıysa yalnız hatırlanır.

### 6.6 Çeviri havuzu: disk ve kimlik

- Klasör `~/Library/Application Support/Nino/translations/`; dosya `translations-<dil>.json`:
  `{"language":"tr","texts":{"<anahtar>":"<çeviri>"},"cursors":{"<oyun>":{"since":0,"after":"","checked":0}}}`.
- Dil başına en çok 400 000 çeviri yazılır.
- İndirmeden sonra (değişiklik varsa) ve kapanırken yazılır. Havuz kapalıyken yazılmaz (diskteki boş listeyle ezilmez);
  kapatmadan hemen önce bir kez yazılır.
- Hedef dil değişince o dilin dosyası yüklenir.
- Kurulum kimliği `install` dosyasında (UUID değilse yeniden üretilir). Bu kimlik sunucuda yalnız tuzlanmış özetiyle
  tutulur.

### 6.7 Oyunu ekrandan tanıma

Oyun bilinmiyorsa (PS5 söylemiyor, paketten de tanınmadı) Remote Play karesi gönderilir:
- Koşul: ortak havuz açık, kaynak `en`, ve (paket kapsamı yok **ya da** oyun havuz öncelikli değil).
- Zaman: oyun bilinmiyorsa çeviri başladıktan 8 sn sonra, sonra 60 sn arayla, en çok 6 kez. Ekrandan tanındıysa
  5 dk sonra bir kez doğrulama, sonra 20 dk'da bir (en çok 12). Oyun konsoldan, kullanıcıdan ya da paketten
  biliniyorsa hiç bakılmaz.
- Kare en çok 768 px genişliğe küçültülür, JPEG kalite 0.6; en çok 450 KB.
- `POST /v1/identify` `{"v":1,"install","app","platform","image":"<base64 jpeg>"}` (30 sn) →
  `{"game":"<ad>"}`; tanınamazsa yok.
- Tanınan oyun bilinenle aynı kimlikteyse "doğrulandı"; değilse oyun değişir ve havuz indirmesi yeniden başlar.

### NinoCore'da eksik
- Ortak havuzun hiçbir parçası yok: süzgeç, kayıpsız gönderme kuyruğu, eski kuyruğu taşıma, uzak ayar, havuz
  önceliği, toplu indirme, anında/süreli/çok satırlı soru, sonradan iyileştirme, buradayım, ekrandan oyun tanıma,
  kurulum kimliği.
- Ayarlarda "ortak havuz" seçeneği yok.

## 7. Altyazı geçmişi

- Dosya `~/Library/Application Support/Nino/history.json` (Windows ile aynı biçim):
  `{"version":1,"entries":[{"id":0,"date":"<ISO 8601>","source":"…","translation":"…","origin":"pack"|"engine"}]}`.
- En yeni başta, en çok 200 kayıt (dosya ~200 KB). Metinler en çok 500 karakter.
- Ekleme: çeviri kırpılır, boşsa eklenmez. En son kaydın kaynağı yenisine benziyorsa (sadeleştirilmiş, Levenshtein
  oranı ≥ 0.85) yeni kayıt açılmaz, son kayıt güncellenir (kimlik aynı kalır).
- Bir andan sonraki kayıtlar (ör. oturum başı) süzülebilir.
- Düz metin kopyası: her kayıt `[HH:mm:ss] Türkçe\nİngilizce`, kayıtlar arası boş satır.
- Dosya eksik ya da okunamazsa geçmiş boş başlar; kayıt önce geçici dosyaya yazılıp sonra asıl dosyanın yerine taşınır.

Sadeleştirme: küçük harf, harf/rakam dışı boşluk, tek boşluk. Benzerlik: `1 − düzenleme_uzaklığı / uzun_olanın_boyu`;
iki metin eşitse ve boş değilse benzer; biri boşsa benzer değil.

| A | B | Benzer mi (0.85) |
|---|---|---|
| `Who goes there?` | `who goes there` | evet (sadeleşince eşit) |
| `Where is the boy` | `Where is the ship` | hayır |

Yeniden okuma, uzama, daha kötü okuma ve anlam işareti (olumsuzluk/sayı) kuralları okuma hattına aittir:
`okuma-hatti.md` §7.3–7.4.

### NinoCore'da eksik
- Geçmiş yok (dosya, 200 kayıt sınırı, benzer satırı güncelleme, düz metin kopyası).

## 8. Altyazı günlüğü

- Dosya `~/Library/Logs/Nino/altyazi.log`. Uygulama açılışta açar; açılmazsa (testler) hiçbir şey yazılmaz.
- Satır biçimi: `[yyyy-MM-dd HH:mm:ss.SSS] <ileti>`; arka planda yazılır.
- 1 MB'yi geçince `altyazi.log.1`'e taşınır (en çok ~2 MB).
- Alıntı: satırlar ` / ` ile birleşir, en çok 120 karakter (aşarsa 119 + `…`), çift tırnak içinde.
  `"Who goes\nthere?"` → `"Who goes / there?"`.
- Yazılan akıbetler (örnekler): `"…" → paket:<kimlik>`, `→ çeviriye`, `→ sırada (çeviri sürüyor: #n)`,
  `çeviri:<motor> 412 ms, gösterildi`, `önbellek …`, `zaten hedef dilde`, `geç: satır … ms önce kalktı`,
  `atıldı: <neden>`, `havuzdan daha iyi çevirisi geldi, yerine kondu`, `havuz öncelikli oyun: sunucudan çeviri
  gelmedi, ücretsiz çeviri kullanıldı`, oyun tanıma sonuçları, görüntü duraklamaları.
- Altyazı metni dışında kişisel bilgi yazılmaz. Günlük yazılamasa da altyazı sürer.

### NinoCore'da eksik
- Altyazı günlüğü yok (NinoCore'da günlük klasörü tanımlı, içeriği değil).
- Sadeleştirme ve benzerlik (Levenshtein oranı) çeviri tarafında da gerekli (yankı ve "zaten hedef dilde"
  denetimleri, `ceviri.md` §4.1 ve §9.2).
