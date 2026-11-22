# Kütüphane: eski paketler, ortak havuz, geçmiş

Eski uygulamalarla, sunucuyla ve öbür platformlarla ortak veri biçimleri. Kod:
`Sources/NinoCore/Library/`. Yeni `.ninopack.json` biçimi için bkz. `paket.md`.

Birebir korunması gerekenler: satır anahtarı, eski paket dosyası ve bulanık
dizini, sunucu istek/yanıtları, havuz disk dosyaları. Bunlar değişirse eski veri
ve sunucu okunamaz.

## 1. Satır anahtarı

Eski paketlerde ve havuzda İngilizce metin yoktur; satır 16 haneli özetle bulunur.

Sadeleştirme (`LineKey.canon`):
1. `<…>` biçim etiketi (içi `<`/`>` içermeyen, en çok 40 kod noktası) boşluk olur.
2. NFKC, küçük harf, NFD; aralıksız birleşen işaretler (Mn) atılır.
3. Harf (L*) ve sayı (Nd, Nl, No) dışındaki her kod noktası ayraçtır.
4. Ayraçlar tek boşluk, baş/son kırpılır.

Anahtar: sadeleşmiş metin boşsa yok; değilse UTF-8 SHA-256'nın ilk 8 baytı.
Bellekte `UInt64` (büyük sonlu), yazıda 16 haneli küçük hex.

| Girdi | Sade | Anahtar |
|---|---|---|
| `Move It!` | `move it` | `2a92733a6f2bf2c2` |
| `Don’t leave the convoy.` | `don t leave the convoy` | `411111ea3f2b7b24` |
| `<i><c>RUSTY LANTERN</></> FOUND` | `rusty lantern found` | `f8e7d3908b0714fb` |
| `Señor, más rápido.` | `senor mas rapido` | `558a6a04622a42bd` |
| `İzmir` | `izmir` | `f3698e3490018159` |
| `Ｇａｔｅ　７` | `gate 7` | `a4b972de42a56651` |
| `...` | boş | yok |

Bu anahtar `TranslationKey`'den farklıdır: noktalama atılır (`Run.` = `Run?`).

## 2. Eski paket dosyası

`.json.gz` ya da `.json`. İlk iki bayt `1f 8b` ve boy ≥ 18 ise gzip: başlık
(FEXTRA, FNAME, FCOMMENT, FHCRC) atlanır, gövde sistemin Compression
çerçevesiyle açılır, sondaki boy alanı tutmazsa dosya bozuktur.

İki düzen:
- `{"format": 1|2, "id", "title", "entries": {hex: tr}, "segments": {hex: tr},
  "fuzzy": {...}}`. `segments` yalnız biçim 2'de; çok cümleli satırların parçaları.
- Düz `{hex: tr}`; kimlik ve başlık dosya adından (`mafia.json.gz` → `mafia`).

Kurallar: başka `format` yüklenmez; `title` yoksa `id`, `id` yoksa dosya adı;
16 hex olmayan anahtar ya da metin olmayan değer atlanır; Türkçedeki `<…>`
silinir, boşluk teklenir; boş kalan çeviri saklanmaz ama dizinde sayılır;
`entries` boşsa paket yüklenmez; `fuzzy` bozuksa paket yüklenir, bulanık arama
kapanır. Bilinmeyen alanlar yok sayılır.

### Bulanık dizin (`fuzzy`)

- `version` 1. `count`: `entries ∪ segments` içindeki geçerli anahtarlar (boş
  çeviriler dahil), sayı değerine göre sıralı.
- `mask`: `count` bitlik dizi; i. anahtarın imzası varsa `bayt[i/8]`'in `i%8`.
  biti (düşük bitten) 1. Boyu `(count+7)/8` bayt.
- `lengths`: imzalı her anahtar için 1 bayt uzunluk.
- `blooms`: imzalı anahtarların Bloom baytları art arda.
- Sayılar tutmazsa dizin yok sayılır.

## 3. Bulanık eşleme

Yalnız tek bir pakette (kapsam ya da seçili oyun) yapılır.

### 3.1 Tek düzeltme

Sade metin 6–48 karakterse, tek bir OCR düzeltmesiyle oluşabilecek bütün
hâller üretilir ve tam anahtarla aranır: bilinen karışıklıklar (`rn↔m`, `cl↔d`,
`vv→w`, `ri↔n`, `li→h`, `l↔i`, `1→l`, `1→i`, `0→o`, `5→s`, `j→i`, `c↔e`, `a↔o`,
`h↔b`, `f↔t`, `u↔v`, `y↔v`, `q↔g`), bir harf ya da boşluk düşmesi, bir sözcüğün
ikiye bölünmesi. Baş/son ya da çift boşluklu hâller ve özgün hâl atılır. Bulunan
hâller farklı Türkçelere çıkıyorsa sonuç yok.

### 3.2 Bloom imzası

Katlama: sade metin boşluksuz; `l 1 ı j → i`, `0 → o`, `5 → s`, `æ → a`,
`ø œ → o`, `ß → s`. Katlanmış boy < 16 ise imza yok.

- Uzunluk = min(karakter sayısı, 255).
- Bit: 64'ten başla; `uzunluk×3 > bit` ve `bit < 256` iken ikiye katla.
- Her farklı ardışık üçlünün UTF-8 baytlarına FNV-1a 64; `özet & (bit−1)` bitini yak.
- Bayt dizisi: 64 bitlik sözcükler sırayla, her biri küçük sonlu.

Benzerlik (0–100): `ortak` = iki imzanın ortak bitleri; doluluk `d` = bir
imzanın yanan bit oranı. `qa = (ortak/sorgu_bit − d_aday)/(1 − d_aday)`, `aq`
simetriği; sonuç `100 × min(qa, aq)`. Biri boş ya da tam doluysa 0.
Bit sayıları farklıysa büyük imza küçüğün boyuna katlanır (sözcükler `i % n` ile
OR'lanır; aynı üçlülerin küçük boydaki imzası budur).

**Bozuk satır**: ASCII dışı karakter (tipografik tırnak, tire, `…` hariç), sözcük
içinde `' ’ -` dışında harf olmayan işaret, harf-rakam bitişik sözcük, `a A I o O`
dışında tek harfli sözcük ya da 14 karakteri aşan sözcük. Sözcük baş/sonundaki
noktalama atılarak bakılır.

**Eşik**: temiz satır L < 24 → 90, değilse 80; bozuk satır L < 24 → 70, < 40 → 60,
değilse 55. Ayırma payı 5.

Arama:
1. Yakın boy `[L − L/4, L + L/4]`: benzerliği `eşik − 5` ve üstü olanlar aday.
2. Tek yönlü kapsama (yakın boyda kabul yoksa ve L ≥ 22): aday boyu
   `[max(22, L·11/20), min(255, L·5/2)]` ve L'den farklı; ortak×10 ≥ 9 × kısa
   tarafın biti olmalı; kısa tarafın kapsanma oranı ≥ 90, uzun tarafın kısa
   taraftaki oranı ≥ 25 (aday uzun) ya da ≥ 55 (aday kısa). Puan = kapsanma − 10.
   Aday kısaysa okumanın her yan cümlesinin (≥ 6 harf, köşe yazısı değil)
   üçlülerinin en az %30'u adayda olmalı.
3. En iyi aday eşiğe ulaşmalı; Türkçesi farklı bir başka aday en iyiye 5 puandan
   yakınsa sonuç belirsiz, yok.

## 4. Kütüphane (`LegacyLibrary`)

- Klasörler sırayla okunur (uygulamayla gelen, sonra kullanıcı klasörü).
  Her klasörde ad sırasıyla `.json.gz`, `.json` ve `.ninopack.json` okunur; bozuk
  dosya atlanır, nedeni listelenir.
- Aynı kimlik sonra gelirse öncekinin yerine geçer (kullanıcınınki kazanır).
- Eski paketler tek sözlükte birleşir: önce bütün `segments`, sonra bütün
  `entries`; aynı anahtarda sonra gelen kazanır.
- Yeni biçim paketleri kendi eşlemesiyle (`paket.md`) bakılır.
- **Kapsam**: son tam eşleşmenin geldiği paket. Anahtar tek pakette varsa o
  paket "ayırt edici isabet" olur (bir kez okunur). Bulanık arama yalnız
  kapsamda.
- **Seçili oyun**: kimliği ya da başlığı oyun adı anahtarıyla seçilen ada eşit son
  paket (`pool-genel` hariç). Seçiliyse yalnız o pakete bakılır; paketi yoksa hiç
  bakılmaz. Seçim değişince kapsam sıfırlanır.

**Oyun adı anahtarı** (`GameName.key`): `™ ® ©` boşluk; NFKD, küçük harf,
işaretler atılır; kesmeler silinir; `ı→i`; `& → and`; harf/rakam dışı boşluk;
harf-rakam arasına boşluk; Roma rakamı sözcükleri (`ii`…`xvi`, `v`) sayı; baştaki
`the` (tek sözcük değilse) atılır; `grand theft auto→gta`, `call of duty→cod`,
`red dead redemption→rdr`, `ea sports fc→fc`, `ea sports→` sil; en çok 80.
`Grand Theft Auto VI` → `gta 6`, `GTA6` → `gta 6`.

**Oyun kimliği** (`GameName.id`): küçük harf; ASCII harf/rakam ve `. _ -` dışı
`-`; ardışık `-` teklenir; baş/son `- . _` atılır; en çok 64.
`Mafia: The Old Country` → `mafia-the-old-country`.

## 5. Ortak havuz istemcisi

Sunucu adresi yalnız yapılandırmayla gelir (`PoolConfiguration.baseURL`);
çekirdekte adres yoktur. Adres yoksa ya da havuz kapalıysa hiçbir şey gönderilmez,
indirilmez. Her istekte `User-Agent: nino-pool/1 (<platform>; <sürüm>)`. Ağ
`PoolTransport` arayüzünün arkasındadır (`URLSession` uyar; testler sahte).

### 5.1 Süzgeç (`PoolFilter`)

Denetim ve sıfır genişlikli karakterler boşluk, boşluk teklenir. Kabul için:
boş değil, ≤ 500 kod noktası, harf var; gürültü değil (görünür karakterlerin en az
yarısı harf; ek çöp denetimi dışarıdan verilir, okuma hattının işi); yarım değil
(cümle sonu yokken < 3 harfli sözcük ya da < 15 karakter; küçük harfle başlama;
cümle sonu yokken `the a to of …` ile bitme; cümle sonu yok, küçük harf yok ve
≤ 6 sözcük); Türkçe değil (`ğ ş ı İ`, ya da `ü ö ç`'den ≥ 2, ya da ≥ 2 PS5 Türkçe
arayüz sözcüğü); PS5 sistem yazısı değil (`signed in`, `trophy earned` …, tam
sözcük öbeği olarak).

### 5.2 Gönderme kuyruğu (`PoolQueue`)

Klasör `pool/`:
- `pending.jsonl`: görülen her satır `{"s":sıra,"t":metin,"g":oyun?,"e":oturum?,"a":unix}`.
- `outbox/<ms 15 hane>-<sıra 4 hane>-<parça>.json`: gönderilecek parçalar.
- `parked/`: sunucunun almadığı parçalar. `rejected.jsonl`: reddedilen satırlar (≤ 1 MB).
- `state.json`: `{"install","frozenThrough","failures","nextAttempt","serverRetryAt","app","dropped"}`.

Kurallar: `pending.jsonl` 64 MB'yi geçtiyse satır yazılmaz, `dropped` artar.
Gönderme zamanı: ≥ 200 bekleyen ya da en eskisi ≥ 120 sn. Dondurma: bekleyenler
parçalara (≤ 200 farklı satır) bölünür, aynı (oyun, oturum, metin) birleşir
(`count`, `first`, `last`); her parça yazıldıkça `frozenThrough` ilerler;
`outbox/` 2000 parçayı geçtiyse dondurulmaz. Açılışta yarım son satır kesilir,
`frozenThrough` parçaların en büyük `upTo`'suyla düzeltilir, sürüm değiştiyse
`parked/` geri `outbox/`'a alınır; okunamayan `state.json` `state.broken-<unix>.json`
olarak kenara konur. Havuz kapatılınca her şey silinir.

`POST /v1/batches` (30 sn), gövde parça dosyasının kendisi:
`{"v":1,"batch","install","app","platform","lines":[{"text","game"?,"session"?,"count","first","last"}],"upTo"}`.

| Yanıt | Davranış |
|---|---|
| 2xx, `ok` ve aynı `batch` | parça silinir, `rejected` günlüğe, bekleme sıfır |
| 2xx, başka `batch` | parça kalır, hata |
| 413 | birden çok satırsa ikiye bölünür, tek satırsa kenara |
| 429, 503 | `Retry-After` (sn ya da HTTP tarihi; yoksa 60; 1 sn–1 gün) |
| 400, 422 | kenara |
| diğer, ağ hatası | bekleme `30 × 2^(hata−1)`, en çok 3600, ±%20 |

Bozuk parça dosyası kenara konur. Bir turda bir dosya bir kez denenir. Eski
`pool.json` kuyruğu bir kez aktarılır, dosya `pool.json.imported` olur.

### 5.3 Uzak ayar ve havuz önceliği

`GET /v1/config` (en çok 10 dk'da bir): `translate` (`enabled`, `deadlineMs`,
`syncSeconds`, `contextLines`, `maxLines`) ve `poolFirst` (`games`, `langs`,
`deadlineMs`). Gelmeyen alan varsayılanda kalır.

Havuz öncelikli: çeviri açık, adres var, dil (`-`/`_` öncesi) `langs`'ta ya da
`*`, ve oyun kimliği `games` parçalarından birini içeriyor ya da sunucu son 600 sn
içinde bu oyunu söyledi. Varsayılan liste GTA 6 adlarıdır.

### 5.4 Havuz çevirileri (`PoolTranslations`)

`GET /v1/translations?lang&since[&game][&after]` →
`{"ok":true,"items":[[hex, metin, güncellenme, …]],"next":{"since","after"}|null}`.
`next` varsa sonraki sayfa (en çok 50); yoksa `since` en büyük güncellenme,
`after` boş. İmleç oyun başına; gerçek indirme oyun başına en erken
`max(30, syncSeconds)` sn'de bir. Dil değiştiyse cevap atılır.

Disk: `translations/translations-<dil>.json`
`{"language","texts":{hex:tr},"cursors":{oyun:{"since","after","checked"}}}`,
dil başına en çok 400 000 çeviri. Değişince ve kapanırken yazılır. Okurken
`Translations/` yazımı da aranır.

Kurulum kimliği: `install` dosyasında tek satır küçük harf UUID; UUID değilse
yeniden üretilir.

### 5.5 Anında soru

`POST /v1/translate` (20 sn):
`{"v":1,"install","app","platform","lang","game","lines":[…],"context":[…]}` →
`{"ok":true,"translations":[{"text"}],"game"?}`. Süzgeçten geçmeyen ya da depoda
olan satır sorulmaz; aynı (dil, anahtar) aynı anda bir kez sorulur. Bağlam: son
`contextLines` satır, en çok 30 sn önce görülmüş. Havuz öncelikli oyunda soru
`poolFirst.deadlineMs` (100–10 000) ile sınırlanır; geç gelen cevap yine depoya
yazılır. Boş olmayan çeviri depoya eklenir; yanıttaki `game` not edilir.

## 6. Paket güncelleyici (`PackUpdater`)

- `GET /v1/packs` → `{"packs":[{"id","title","version","sha256"}]}`;
  `GET /v1/packs/<id>` → dosya (≤ 64 MB, 60 sn). Kimlik `^[a-z0-9][a-z0-9-]{0,63}$`,
  sha256 64 hex değilse atlanır.
- Zaman: açılışta ve 24 saatte bir; yeni oyun tanınınca son bakış 10 dk'dan
  eskiyse. Önceki seferde inemeyen varsa taze olsa da bakılır.
- Dosya `<klasör>/<id>.json.gz`. Kayıtlı sürüm/sha ve diskteki sha aynıysa
  dokunulmaz. Diskteki sha ne kayıtlıya ne yeniye eşitse kullanıcının dosyasıdır,
  yazılmaz. İnen verinin sha'sı tutmazsa yazılmaz, sürüm −1 tutulur. Önce
  `.<id>.download`, sonra yerine konur.
- Sunucudan kalkan paket, diskteki sha kayıtlıyla aynıysa silinir.
- İnemeyen varsa "son bakış" ilerlemez.
- Durum dosyası paket klasörünün dışında: `{"checked":unix,"packs":[{"id","title","version","sha256"}]}`.

## 7. Geçmiş (`SubtitleHistory`)

`history.json`: `{"version":1,"entries":[{"id","date","source","translation","origin":"pack"|"engine"}]}`.
En yeni başta, en çok 200 kayıt, metin 500 karaktere kırpılır. Çeviri boşsa
eklenmez. Son kaydın kaynağı yenisine benziyorsa (sadeleşmiş Levenshtein oranı
≥ 0.85) son kayıt güncellenir, kimliği aynı kalır. Düz metin: `[HH:mm:ss] Türkçe\nİngilizce`,
kayıtlar arası boş satır. Bozuk dosya boş geçmiş sayılır; yazma yerine koyarak.

## 8. Altyazı günlüğü (`SubtitleLog`)

`altyazi.log`, satır `[yyyy-MM-dd HH:mm:ss.SSS] <ileti>`. 1 MB'yi geçince
`altyazi.log.1`'e taşınır. Alıntı: satırlar ` / ` ile birleşir, en çok 120
karakter (aşarsa 119 + `…`), çift tırnakta. Altyazı dışında kişisel bilgi yazılmaz;
yazılamazsa sessizce geçilir.

## 9. Çevirmen zincirine bağlama (`LibraryTranslator`)

```
paket (seçili oyun / kapsam) → havuz deposu → [havuz öncelikliyse süreli soru] → Translator (önbellek → sağlayıcılar)
```

`LibraryTranslator`, var olan `Translator`'ı değiştirmeden sarar. `Translator`
paketsiz (`pack: nil`) kurulmalı, yoksa paket iki kez sorulur. Sıra `ceviri.md`'den
farklıdır: eski paket ve havuz yerel ve kesin olduğu için önbellekten önce gelir
(eski uygulama böyle). Havuz öncelikli oyunda paketlere bakılmaz. Paketten ya da
havuzdan bulunmayan satır havuz kuyruğuna önerilir. İsteğe bağlı (`askInBackground`) bu satır
arka planda havuza da sorulur; cevap bir sonraki görülmede depodan gelir. Sonuç kendi kaynağını taşır:
`legacyPack(<kimlik>)`, `newPack(<kimlik>)`, `pool`, `translator(<Translation.origin>)`.

## Henüz yok

- Aşamalı paket araması (konuşmacı etiketi, satır satır, köşe yazısını atlama,
  cümle cümle) ve OCR'ın bozduğu etiket.
- Kullanıcı dosyasından paket içe aktarma (`.json`, `.txt`, `.srt`).
- Ekrandan oyun tanıma (`/v1/identify`).
- Çok satırlı anında soru ve ekrandaki çevirinin sonradan havuzdakiyle değişmesi.
- Süzgecin OCR çöp denetimi okuma hattından bağlanmalı (`PoolFilter.isGarbage`).
