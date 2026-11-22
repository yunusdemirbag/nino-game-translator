# Windows: çeviri (tarif)

Bu belge eski Windows uygulamasının çeviriyi nasıl yaptığını anlatır: çevirmen zinciri, havuz önceliği, altyazı bölücüsü,
ücretsiz (cihaz üstü) çeviri metin hattı, sözlük, terim koruma, Türkçe ek kurma, Türkçe düzeltme, yerel modeller (ONNX
Marian, CTranslate2 işçisi, model indirme), DeepL, yapay zekâ motorları, dakikalık bütçe, kalıcı önbellek ve hedef
diller. Kod yoktur. Paketler ve ortak havuz için `havuz-paketler.md`.

Mac karşılığı: `git show claude/yeni-mac-c9961f:docs/yeni/mac/ceviri.md`. Windows'ta cihaz üstü çeviri Apple Translation
değil **OPUS-MT** (Marian) modelleridir; metin hattı (sözlük, kısa satır bağlamı, Türkçe düzeltme) ortaktır. Bu belgede
istenen bütün algoritmalar baştan sona yazıldı; Mac'ten farklar her bölümün sonunda.

> Marka adları (DeepL, Gemini, OpenAI, Claude, Ollama…) davranışı anlatmak için geçer. Yapay zekâ istemlerinin
> **anlamı** madde madde verildi; metin kelimesi kelimesine kopyalanmadı. Yalnız üçüncü taraf çeviri modellerinin kendi
> istem kalıpları (TranslateGemma, MiLMMT) ve bizim istek gövdemizin iskeleti biçim olduğu için birebir verildi.

## 0. Birebir aynı kalması gerekenler

Eski diskteki veriyle, öbür platformlarla ya da sunucularla ortak; bayt bayt aynı üretilmeli:
- Paket/havuz anahtarı: `havuz-paketler.md` §1.
- Kalıcı önbellek dosya adı ve satır biçimi, motor adları, önbellek anahtarları: §10.
- Sözlük izi (FNV-1a 32) ve sözlük dosya biçimi: §5.
- Model dosyalarının adresleri, adları, boyları, SHA-256'ları: §8.
- CTranslate2 işçisinin satır protokolü: §8.6.
- DeepL ve yapay zekâ isteklerinin adres/başlık/gövde biçimleri, yanıt okuma: §11, §12.
- Model listesi dosyası (`ai-models.json`) biçimi: §12.2.

**Veri dosyaları** (kod değil; yeni kodun kaynak klasörüne aynen taşınır, gömülü kaynak olur): `ai-models.json` (§12.2,
içeriği tam verildi), genel sözlük `glossary-en-tr.json` (§5.6, içeriği tam verildi), CTranslate2 işçi betiği ve paket
listesi (§8.6, davranışı tam verildi; betik yeniden yazılabilir).

---

## 1. Bir altyazı satırının yolu

Okuma hattı (başka belge) ekrandan bir İngilizce satır okur. Çeviriyle ilgili sıra:

1. **Paket + havuz bakışı** (satır kuyruğa girerken). Kaynak `en` değilse yapılmaz.
   - "Paketler etkin" = paket ayarı (`settings.packs.useGamePacks`) açık **ve** kaynak `en` **ve** hedef `tr`.
   - Paketler etkinse **ve** oyun havuz öncelikli değilse: parçalı paket bakışı (`havuz-paketler.md` §2.4). Bulunursa bu.
   - Bulunmadıysa (ya da bakılmadıysa): (ortak havuz açık **ya da** oyun havuz öncelikli) ise indirilmiş havuz
     çevirileri sözlüğünde **satırın tamamı** anahtarla aranır; bulunursa bu. Havuz çevirisine Türkçe düzeltme
     uygulanmaz (sunucuda yapıldı).
   - Bulunan çeviri hemen gösterilir, çevirmene gidilmez; günlükte kaynak "paket".
2. **Bulunmadıysa** okuma hattı satırı "pakette yok" diye bildirir (`havuz-paketler.md` §6.1): satır gönderme kuyruğuna
   önerilir ve (ortak havuz açık ya da havuz öncelikli ise) arka planda havuza tek satır sorusu atılır; çeviri gelirse
   ekrandakinin yerine konur (`havuz-paketler.md` §8.4 "sonradan iyileştirme").
3. **Çevirmen** (bu belge): aşağıdaki zincir. Çeviri dönünce okuma hattı paket/havuz bakışını bir kez daha yapar; arada
   havuza çeviri indiyse **o** gösterilir.
4. **"Zaten hedef dilde mi"** (okuma hattı): kaynak ile çevirinin sadeleştirilmiş hâlleri (küçük harf, yalnız harf/rakam,
   tek boşluk) Levenshtein oranıyla ≥ **0.90** benzerse çeviri gösterilmez (PS5'in Türkçe menüsü boşa gösterilmesin).

### 1.1 Zincir (dıştan içe)

```
yazı denetimi (hedefin yazısıyla yazılmış satırı çevirmeden geri ver)   §13.3
└─ havuz önceliği (oyun havuz öncelikliyse sunucuya süreli sor)       §1.2
   └─ temel çevirmen                                                   §1.3
        ├─ çevrimiçi etkin ve motor hazır → DeepL / Gemini / OpenAI / Claude / yerel model
        │     (yedeği: ücretsiz çevirmen; açılamadıysa yedek yok)
        └─ değilse → ücretsiz çevirmen (OPUS-MT) ya da "kullanılamaz" çevirmeni
```

Zincir çeviri oturumu başlarken ve dil/motor/anahtar/ayar değişince yeniden kurulur. Okuma hattı zinciri kurulurken bir
kez "ön çeviri destekliyor mu" diye sorar (temel motorunkini yansıtır).

### 1.2 Havuz önceliği katmanı

Her satırda "oyun havuz öncelikli mi" (kaynak `en` **ve** `havuz-paketler.md` §8.2'nin kararı, o anki oyun adıyla) diye
bakılır (oyun satır satır değişebilir):
- **Hayır:** satır temel çevirmene gider; son kaynak `motor`.
- **Evet:** satır havuza **süreli soru** ile sorulur (`havuz-paketler.md` §8.4; bağlam = bağlam listesinden "satırdan
  öncekiler", oyun = havuz öncelikli soru adı). Sorunun kendisi hata fırlatırsa (iptal dışında) yok sayılır.
  - Boş olmayan çeviri geldiyse o; son kaynak `havuz`.
  - Gelmediyse (süre doldu, sınır doldu, hata): günlüğe havuz öncelikli oyunda sunucudan çeviri gelmediği ve ücretsiz çevirmene geçildiği yazılır, satır **yalnız ücretsiz çevirmenle** çevrilir (kullanıcının anahtarlı motoru **çağrılmaz**);
    son kaynak `ücretsiz`.
- Ön çeviri: havuz öncelikli oyunda motorun ön çevirisi başlatılmaz (anahtar harcanmasın).
- Toplu çeviri ("ekranı çevir"): havuz öncelikli değilse ve temel motor toplu çevirebiliyorsa onunki; havuz öncelikliyse
  parçalar tek tek bu kuralla.
- Ortak havuz ayarı kapalı olsa da bu katman çalışır.

Test: motor `gemini`, ücretsiz `ücretsiz`, havuz `havuz` döndüren sahteler.
- Havuz öncelikli: `Untie the boat!` → `havuz`; ön çeviri motora gitmez; toplu çeviri yok sayılır ("toplu çevirebilir"
  hayır); `a line`, `a second line` → [`havuz`, `havuz`]; motor ve ücretsiz hiç çağrılmadı; havuza 3 soru; son kaynak
  `havuz`.
- Havuz `null` döner ya da hata fırlatır → `ücretsiz` (iki kez); motor çağrılmaz; son kaynak `ücretsiz`.
- Havuz öncelikli değil → `gemini`; ön çeviri motora gider; "toplu çevirebilir" motorunki (evet); havuza soru yok.
- Oyun satır arasında değişir: `one` → `gemini`, sonra `two` → `havuz`; motor tek çağrı.

### 1.3 Temel çevirmen seçimi

- **Ücretsiz çevirmen** (§7): kaynak/hedef çifti desteklenmiyorsa "desteklenmiyor", model kurulu değilse "indirme
  gerekli", motor daha önce açılamadıysa "motor açılamadı" durumuyla her çeviride hata fırlatan "kullanılamaz" çevirmen
  döner. Kurulamazsa da (önbellek/sözlük okunamadı) "motor açılamadı" ve çevrimiçi etkin değilse ana ekrana uyarı.
- **Yedek** = ücretsiz çevirmen; ama "kullanılamaz" çevirmense ya da motor açılamadıysa yedek **yoktur** (çevrimiçi motor
  çeviremeyince hata yukarı çıkar, okuma hattı satırı sonra yeniden dener).
- **Çevrimiçi etkin** = "çevrimiçi çeviri" açık **ve** kaynak `en` **ve** hedef seçilebilir dillerden (§13) **ve** (motor
  DeepL ise hedef DeepL'in dillerinden) **ve** motor hazır. Hazır: bulut motorunda şifreli depoda anahtar var; yerel
  modelde ayardaki adres ve model geçerli (anahtar gerekmez).
- Etkin değilse ücretsiz çevirmen. Etkinse:
  - Yerel model: ayardaki sunucu (§12.7), depodaki anahtar (yoksa boş).
  - Bulut: anahtar yoksa ücretsiz çevirmen; Gemini/OpenAI/Claude ise ayardaki model (listede yoksa varsayılan); DeepL ise
    DeepL.
  - Oyun adı (yapay zekâ için): her istekte o anki "kararlı oyun" adı (PS5'in bildirdiği, kullanıcının elle seçtiği ya da en son satırların paketinden tanınan; **son eşleşen paketin başlığı değil**).
  - Çevrimiçi motorun hata durumu değişince ana ekranın "şu an çevirmiyor" uyarısı güncellenir (§11.2, §12.6).

### 1.4 Telefon ve harita kartı yazıları
(Başka belge; çeviri ile ilgili kısım.) Bilinmeyen yazılar önce havuza çok satırlı soru ile sorulur; gelmeyenler: havuz
öncelikli oyunda **yalnız ücretsiz** çevirmen, değilse temel çevirmen (ikisi de yazı denetimiyle sarılı). Havuza ikinci
kez sorulmaz.

### 1.5 Ekran çevirisi (`translation.screen.translate`)
Zincir (yazı denetimi + havuz önceliği + temel) ile çevrilir. Amaç: yapay zekâ motorunda ekranın bütün parçalarının tek
istekte gitmesi (§12.8). **Eski kodda bir boşluk var:** en dıştaki yazı denetimi katmanı "toplu çevirebilir" bilgisini
ve toplu çeviri işlemini iç katmana geçirmiyor; bu yüzden uygulamada "ekranı çevir" fiilen parçaları **tek tek** çeviriyor
(yapay zekâda 20 parçalık ekran dakikalık hakkı bitirebiliyor). Yeni kodda yazı denetimi de bu ikisini içe geçirmeli
(hedefin yazısıyla yazılmış parçaları kendisi ayırıp kalanları toplu göndermeli). Davranış hedefi §12.8'deki testlerdir.

### 1.6 Ücretsiz çeviri zinciri (sunucu tarafı)
"Ücretsiz zincir" (Gemini + Groq + öbür ücretsiz servisler) **sunucudadır** (havuz sunucusu); Windows istemcisinde Groq,
OpenRouter ya da başka ücretsiz servis kodu **yoktur**. İstemcinin bildiği tek şey:
- Havuza `POST /v1/translate` atar (`havuz-paketler.md` §8.4); sunucu kendi zincirini dener.
- Yanıtta `text: null` (hepsinin hakkı dolu, günlük sınır) ya da süre dolması/hata → istemci cihaz içi ücretsiz çeviriye
  (OPUS-MT) düşer (havuz öncelikli oyunda) ya da kendi motorunun sonucunu gösterir (öbür oyunlarda).
- Kullanıcının **kendi** ücretsiz Gemini anahtarı ayrı bir motordur (§12; istemciden doğrudan Gemini'ye); sunucu
  zinciriyle ilgisi yoktur. (Ücretsiz Gemini kullanıldığı bilgisi = motor Gemini ve anahtar kayıtlı.)
- Sunucunun hangi servisleri hangi sırayla denediği, bekleme süreleri, toplu çeviri zamanlayıcısı: Mac `ceviri.md` §1.2
  ile aynı (istemciyi etkilemez).

### Mac'ten farkı (§1)
- Windows'ta "oyun kesin bilinmiyorsa sunucuya süreli sor" dalı yok (Mac §1.1). Sunucu sorusu her bilinmeyen satırda
  arka planda yapılır; sunucu oyunu tanırsa havuz önceliği sonraki satırlarda açılır.
- Havuz çevirisi sözlüğü yalnız satırın tamamıyla aranır (konuşmacı öneki atılmış gövdeyle ikinci bakış okuma hattının
  işidir).

---

## 2. Motor ve anahtar ayarları (çeviri tarafı)

| Ayar | Varsayılan | Not |
|---|---|---|
| kaynak dil | `en` | `en` değilse paket, havuz, havuz önceliği, çevrimiçi motor kapalı |
| hedef dil | `tr`; ilk açılışta Windows arayüz dili listedeyse o (§13) | |
| çevrimiçi çeviri | kapalı | |
| çevrimiçi motor | DeepL | DeepL, Gemini, OpenAI, Claude, yerel model; "ücretsiz" seçilince çevrimiçi kapanır |
| model (her bulut motoru) | listedeki ilk | kayıtlı model listede yoksa varsayılan |
| yerel adres / model | `http://localhost:11434/v1` / `translategemma:4b` | |
| çeviri aygıtı | CPU | GPU (NVIDIA CUDA) seçilebilir, §8.5 |
| CPU iş parçacığı | 2 | seçenekler 2, 4, 8, 12 (mantıksal işlemciden büyük olmayanlar; < 2 işlemcide yalnız 1) |
| oyun paketleri | açık | |
| ortak havuz | açık | |

CPU iş parçacığı düzeltme: istenen değerden küçük ya da eşit en büyük seçenek; yoksa en küçük seçenek. "Kapasiteye
yakın" uyarısı: seçilen × 4 ≥ mantıksal işlemci × 3.

**Anahtarlar** şifreli depoda (Windows DPAPI, başka belge) şu adlarla: `deepLKey`, `geminiKey`, `openAIKey`,
`claudeKey`, `localAIKey`. Anahtar arayüze hiç geri dönmez (yalnız "kayıtlı mı"). Kullanırken baştan/sondan kırpılır.
- DeepL anahtarı kaydı: önce kullanım denetimi (§11.5); **geçerli ya da kota bitmiş** ise kaydedilir ve DeepL seçilir.
- Yapay zekâ anahtarı kaydı: örnek satırla deneme (§12.9); **geçerli, kota bitmiş ya da model reddedildi** ise kaydedilir
  ve o motor seçilir. Geçersiz ya da ulaşılamadı → kaydedilmez.
- Yerel modelde bağlantı deneme düğmesi: yazılan anahtar (yoksa kayıtlı) ile deneme; sunucu kabul ettiyse yazılan anahtar kaydedilir.

**Hata metinleri** (ayarlar ve ana ekran aynı anahtarları kullanır; `%@` motorun marka adı):
- geçerli: `status.online.working` (denemede örnekle `settings.translation.result.aiValid`).
- anahtar geçersiz: `settings.translation.result.aiKeyRejected` (DeepL'de `settings.translation.result.deeplRejected`).
- kota: `settings.translation.result.aiQuota` (DeepL'de `settings.translation.result.deeplQuota`).
- model reddedildi: `translation.error.modelRejected`.
- ulaşılamadı: `translation.error.unreachable`.
- Yerel model: anahtar geçersiz → `translation.error.local.invalidKey`; kota → `translation.error.local.busy`; model
  reddedildi → LM Studio'da `translation.error.local.lmStudioModelMissing`, öbürlerinde
  `translation.error.local.modelMissing` (`ollama pull <model>` komutunu verir); ulaşılamadı → Ollama'da
  `translation.error.local.ollamaNotRunning`, LM Studio'da `translation.error.local.lmStudioNotRunning`, diğerinde
  `translation.error.local.serverUnreachable` (adres ve model değerleriyle).
- Yerel modelin arayüz adı çevrilir (`status.online.localModelName`); marka adları çevrilmez.
- Anahtar sayfaları: Gemini `https://aistudio.google.com/apikey`, OpenAI `https://platform.openai.com/api-keys`,
  Claude `https://platform.claude.com/settings/keys`, yerel model `https://ollama.com/download`.

### Mac'ten farkı (§2)
- Windows'ta Ollama'nın kurulu model listesi (`/api/tags`) ve tek tuşla model indirme (`/api/pull`) **yok**; kullanıcı
  model adını yazar. Eski `qwen2.5:7b` kaydını varsayılana çevirme de yok.
- CPU iş parçacığı ve GPU seçenekleri yalnız Windows'ta.

---

## 3. Altyazı bölücüsü (cümle parçaları)

Ücretsiz çeviri, DeepL, yapay zekâ ve parçalı paket araması satırı aynı kurallarla parçalar. Her parça ya
**çevrilecek** metin ya da olduğu gibi kalacak **ayraç/etiket**tir; parçalar art arda birleşince satırın (boşlukları
sadeleşmiş) hâli çıkar.

### 3.1 Konuşmacı etiketi
Satır ya da cümle başında, ardından en az bir boşluk gelen `ad:` biçimi. Ad iki kalıptan biri:
- **Tümü büyük harf:** ilk sözcük büyük harfle başlar ve en az bir karakter daha içerir; sözcük karakterleri büyük harf,
  rakam, `'`, `’`, `.`, `-`. Sonra en çok 2 sözcük daha (tek boşlukla; büyük harfle başlayıp aynı karakterlerden sıfır ya
  da daha çok). `VERA:`, `OLD SAILOR:`, `RUIZ JR.:`.
- **Baş harfi büyük:** ilk sözcük büyük harf + küçük harf ile başlar, sonra harf, `'`, `’`, `.`, `-`; en çok 2 sözcük
  daha (tek boşlukla, büyük harfle başlayan, sonra harf/`'’.-`). `Tomas:`, `Ship Doctor:`, `Old Sailor:`.
- Tek sözcüklü ad şu listedeyse (büyük/küçük harf duyarsız) etiket **değildir** (çevrilir): note, warning, tip, hint,
  objective, objectives, quest, goal, new, reward, rewards, location, chapter, mission, task, tutorial, update, info,
  status, level, controls, press, hold, tap, remember, example, question, answer, result, results, time, listen, look,
  wait, okay, ok, well, so, yes, no, now, then, and, but.
- Etiket parçası = `ad:` + tek boşluk. Etiketin adı ("etiket parçası `: ` ile bitiyorsa son iki karakter atılmış hâli")
  ad öğrenmede kullanılır.

### 3.2 Bölme
1. `\r\n` → `\n`; satırlardan bölünür; her satır kırpılır, boş satırlar atlanır.
2. Satırlar **bloklara** toplanır: etiketle ya da diyalog tiresiyle (`-`, `–`, `—`, bir ya da daha çok) başlayan satır yeni
   blok başlatır; öbür satırlar öncekine boşlukla eklenir (sarılmış satır).
3. Bloklar arasında `\n` ayraç parçası.
4. Her blokta boşluklar teklenir. Blok tireyle başlıyorsa tire(ler) + tek boşluk ayraç parçası olur, tire ve ardındaki
   boşluklar atılır.
5. Blok **cümlelere** bölünür: bir ya da daha çok `. ! ? …`'dan sonra (isteğe bağlı kapanış `" ' ” ’ ) ]` dizisiyle) gelen
   boşluk adaydır. Aday **atlanır** (bölünmez) eğer: boşluktan sonraki karakter küçük harfse (`easy... what`), ya da
   adaya kadarki metin noktayla bitiyor ve son sözcüğü (noktasız) tek büyük harf (ad baş harfi) ya da kısaltmaysa: mr,
   mrs, ms, dr, st, jr, sr, prof, mt, vs, etc, e.g, i.e, lt, sgt, capt, gen, col (büyük/küçük harf duyarsız).
6. Cümleler arasında tek boşluk ayraç parçası. Cümle etiketle başlıyorsa etiket ayrı (çevrilmez) parça olur. Kalan gövde
   boş değilse parça olur: içinde harf varsa çevrilecek, yoksa (`...`, `?!`, `3`) çevrilmez.

Örnekler (çevrilecekler köşeli parantezde):

| Girdi | Parçalar |
|---|---|
| `Wait!` | `[Wait!]` |
| `Tomas! Focus. The raiders are still coming.` | `[Tomas!] [Focus.] [The raiders are still coming.]` |
| `What is that?! It looks like a sail.` | `[What is that?!] [It looks like a sail.]` |
| `"Row!" she said. Then silence.` | `["Row!" she said.] [Then silence.]` |
| `I know… but we must sail.` | `[I know… but we must sail.]` |
| `Easy... what was that?` | `[Easy... what was that?]` |
| `Mr. Ruiz is here. Dr. Vale too.` | `[Mr. Ruiz is here.] [Dr. Vale too.]` |
| `No. We sail now.` | `[No.] [We sail now.]` |
| `Vera.` | `[Vera.]` |
| `VERA: Captain, look over there!` | `VERA: [Captain, look over there!]` |
| `VERA: Look! RUIZ: Stay behind me.` | `VERA: [Look!] RUIZ: [Stay behind me.]` |
| `RUIZ JR.: Ahoy there.` | `RUIZ JR.: [Ahoy there.]` |
| `Tip: this is not a label.` | `[Tip: this is not a label.]` |
| `Tomas: Keep low.` | `Tomas: [Keep low.]` |
| `Old Sailor: Who rang the bell?` | `Old Sailor: [Who rang the bell?]` |
| `Objective: Find the key.` | `[Objective: Find the key.]` |
| `If we do not reach the island before nightfall,⏎we will have to drop anchor.` | `[If we do not reach the island before nightfall, we will have to drop anchor.]` |
| `VERA: Captain, look!\r\nRUIZ: Stay behind me.` | `VERA: [Captain, look!]⏎RUIZ: [Stay behind me.]` |
| `- Who sent you?⏎- The captain.` | `- [Who sent you?]⏎- [The captain.]` |
| `...` / `?!` | `...` / `?!` (çevrilmez) |
| boş / `␠␠␠` | hiç parça |

### 3.3 Büyük harf düzeni (tümü büyük harfli cümle)
Model büyük harfli sözcükleri ad sanıp çevirmiyordu. Cümlede küçük harf varsa ya da harf sayısı < 2 ya da (kırpılınca)
boşluk yoksa dokunulmaz. Değilse sözcük sözcük (sözcük = harfler ve `'`, `’`): küçük harfe çevrilir; cümle başındaysa,
sözcük `i` ise ya da "bilinen adlar" kümesinde (küçük harfle) ise ilk harfi büyütülür (kültürden bağımsız). Sözcük
olmayan karakter aynen yazılır; `. ! ? …` sonraki sözcüğü cümle başı yapar.
- `THE HULL WILL NOT HOLD MUCH LONGER.` → `The hull will not hold much longer.`
- `YES, BUT I WON'T.` → `Yes, but I won't.`
- `RUN!`, `VERA.` → değişmez (tek sözcük); `Who sent you?`, `NATO is here.` → değişmez (küçük harf var).
- Bilinen `vera`: `THE HULL WILL NOT HOLD, VERA.` → `The hull will not hold, Vera.`

**Bilinen adlar:** çevirmen konuşmacı etiketlerinden öğrenir (etiket adının boşlukla ayrılmış, ≥ 2 karakterli her
sözcüğü, küçük harfle; `OLD SAILOR:` → `old`, `sailor`), Türkçe hedefte sözlüğün "büyük kalacak sözcükleri" (§5.3) eklenir.
Öğrenilen adlar çevirmen nesnesi yaşadıkça kalır.

---

## 4. Ücretsiz çevirinin metin hattı (hedef `tr`)

Tek **cümle** için (bölücünün bir çevrilecek parçası), "bağlam" verilmiş ya da verilmemiş olabilir:

1. Sözlükte bu cümlenin **hazır satırı** varsa (§5.4) modele gitmez: hazır Türkçe §6.4'teki Türkçe düzeltmeden geçirilip
   döner.
2. Kesme işareti türü: cümlede `’` varsa eklerde `’`, yoksa `'` kullanılır.
3. **Hazırlama** (bir metne uygulanan): büyük harf düzeni (§3.3, bilinen adlarla) → sözlüğün argo kuralları (§5.4,
   `phrases`) → oyun deyimleri (§4.2).
4. **Bağlamla deneme** (bağlam varsa): bir terim koruyucu (§6.1) cümle ve bağlam metinleriyle kurulur (ikisinde geçen
   uydurma adlar kullanılmaz). Bağlam hazırlanıp korunur, cümle hazırlanıp korunur (aynı koruyucu: bağlamın terimleri de
   aynı ad listesinden ad alır). Modele `<korunmuş bağlam> *** <korunmuş cümle>` (ayraç: boşluk, üç yıldız, boşluk) gider.
   Çıktıdan ayraç sonrası alınır (§4.1); alınabildiyse ve terimler geri konabildiyse (§6.2; beklenen = cümlenin adları,
   "hepsi" = koruyucunun bütün adları) → Türkçe düzeltme (§6.4) → sonuç.
5. **Tek başına:** yeni koruyucu yalnız cümleyle kurulur; cümle hazırlanıp korunur; modele gider.
   - Hiç terim korunmadıysa: çıktı → Türkçe düzeltme → sonuç.
   - Terimler geri konabildiyse → Türkçe düzeltme → sonuç.
   - Konamadıysa (model bir uydurma adı düşürdü ya da yanlış ad kaldı): cümle **korumasız** hazırlanıp yeniden modele
     gider; çıktı → Türkçe düzeltme → sonuç. "Terimsiz ama eksiksiz" çeviri, eksik terimli çeviriden iyidir.

### 4.1 Kısa cümle ve bağlam
- **Kısa:** harf içeren sözcük sayısı 1, 2 ya da 3 (`Run!`, `Do it.`, `Not now, Tomas.`). 0 ya da ≥ 4 kısa değil
  (`We sail to the island.`, `...`).
- Satır çevrilirken: önce "bu satırdan önce gösterilen satır" alınır (aşağıdaki son satır kaydı). Satır parçalanır,
  etiketlerden adlar öğrenilir. "Önceki cümle" = önceki satırın son çevrilecek parçası (önceki satır yoksa yok). Parçalar
  sırayla: çevrilecek parça kısa ise bağlamı "önceki cümle"dir, değilse bağlam yok. Parça çevrildikten sonra "önceki
  cümle" bu parça olur.
- **Son satır kaydı:** tek kayıt (metin, bağlamı, görüldüğü an). Gelen satır kayıttakiyle **aynıysa** kayıtlı bağlamı
  döner ve zaman tazelenir (yeniden okunan satır aynı bağlamla çevrilir, önbellekten aynı sonuç gelir). Değilse bağlam =
  kayıttaki metin, eğer en çok **20 sn** önce görüldüyse; kayıt yeni satırla değişir.
  Örnek: `Who took the map?` → bağlam yok; `Not me.` → `Who took the map?`; 5 dk sonra aynı `Not me.` → yine
  `Who took the map?`; `Go.` → `Not me.`. 25 sn arayla → bağlam yok.
- **Ayraç sonrası** (`***` çıktısından kısa cümlenin çevirisi): `***` tam **bir** kez geçmeli; sonrası kırpılır; sonrası
  `*` ile başlıyor ya da öncesi `*` ile bitiyorsa (yapışık yıldızlar) yok; iki yanından biri harf içermiyorsa yok;
  sonrası kaynak cümlenin UTF-16 uzunluğunun 3 katı + 20'den uzunsa yok. Kaynak `Not me.` (7 birim; sınır 41) için:

| Çıktı | Sonuç |
|---|---|
| `Haritayı kim aldı? *** Ben değil.` | `Ben değil.` |
| `Haritayı kim aldı?***Ben değil.` | `Ben değil.` |
| `HARİTAYI KİM ALDI? *** BEN DEĞİL.` | `BEN DEĞİL.` |
| `Haritayı kim aldı? Ben değil.` | yok |
| `Haritayı *** kim aldı? *** Ben değil.` | yok |
| `Haritayı kim aldı? **** Ben değil.` | yok |
| `*** Ben değil.` | yok |
| `Haritayı kim aldı? ***` | yok |
| `Haritayı kim aldı? *** Ben değil, ben değil, ben değil, ben değil, ben değil, ben değil, ben değil.` | yok (çok uzun) |

`***` seçimi: OPUS-MT sözlüğünde `▁***` tek parça (altyazılarda sahne ayracı); `|`, `||`, `[[` bilinmeyen parçaya düşer.

### 4.2 Oyun deyimleri (her hedefte, çeviriden önce)
Tam sözcük sınırıyla, büyük/küçük harf duyarsız, bu sırayla; eşleşmenin ilk harfi büyükse karşılığınki de büyütülür:
`friendlies`→`allies`; `I've got your six` ya da `I got your six`→`I've got your back`; `check your six`→`watch behind
you`; `heads up`→`watch out`; `took you long enough`→`you're late`; `we've got company`→`enemies are coming`;
`lock and load`→`get ready`; `sitting ducks`→`easy targets`; `moving in`→`going in`.

### 4.3 Satırın birleştirilmesi
Her çevrilecek parçanın çevirisi alınır; Türkçe hedefte bütün parça çevirilerine **hitap kuralı** (§6.5) uygulanır
(önbellekteki cümle çevirileri değişmez); çevrilmeyen parçalar aynen. Parçalar art arda birleşir.

### 4.4 Önbellek anahtarı (ücretsiz çeviri, cümle başına)
- Temel = cümle; bağlam varsa `bağlam` + U+001F + `cümle`.
- Temelde bir sözlük terimi geçiyorsa **ya da** cümle bir `lines`/`phrases` kuralına giriyorsa **ya da** bağlam bir
  `lines`/`phrases` kuralına giriyorsa: `<sözlük izi>` + U+001F + temel. Değilse temel.
- Örnekler (sözlük `terms: Storm Lantern`, `keep: Doros, Belus`): `We go.` → `We go.`; bağlam `Where?` → `Where?`
  U+001F `We go.`; `Doros, go.` → `<iz>` U+001F `Doros, go.`; `Go.` bağlam `Doros!` → `<iz>` ile başlar.
  Genel sözlükle: `Level up!` (hazır satır) ve `Chug a pot and go.` (`phrases`) → iz ile başlar; `I hear it.` → aynen.

### 4.5 Hedef `tr` değilse
Sözlük, terim koruma, kısa satır bağlamı, hazır satır, Türkçe düzeltme ve hitap **yok**. Her çevrilecek parça: büyük harf
düzeni (yalnız öğrenilen adlarla) → oyun deyimleri → model. Önbellek anahtarı = cümle (boş sözlükle).
Örnek (sahte model `ترجمة`): `DOROS: LIGHT THE STORM LANTERN, BOY!` → `DOROS: ترجمة`; modele giden (küçük harfle
karşılaştırıldığında) `light the storm lantern, boy!`.

### 4.6 Test örnekleri (sahte model; `Same` = hazırlama değiştirmez)
Örnek kullanıcı sözlüğü "Lantern Coast": `terms` `Storm Lantern` → `Fırtına Feneri`, `Selvard` → `Selvard`; `keep`
`Doros`, `Belus`.
- `Doros, light the Storm Lantern!` → modele `Zarmon, light the Velkor!`; model `Zarmon, Velkor'u yak.` → sonuç
  `Doros, Fırtına Feneri'ni yak!`.
- `Light the Storm Lantern!` → modele `Light the Zarmon!` (model adı düşürür: `Feneri yak!`), sonra korumasız
  `Light the Storm Lantern!` → `Fırtına Fenerini yak!`.
- `Not me.` bağlam `Who took the map?` → modele `Who took the map? *** Not me.` → `Ben değil.`.
- Belirsiz çıktı (`Haritayı kim aldı, ben değil.`) → ikinci çağrı `Not me.` → `Ben değil.`.
- `Wait, Belus!` bağlam `Doros has the map.`: modele `Zarmon has the map. *** Wait, Velkor!`; çıktı
  `Haritayı Zarmon aldı. *** Bekle, Velkor!` → `Bekle, Belus!`. Çıktı `Aldı. *** Bekle, Zarmon Velkor!` (bağlamın adı
  satıra kaydı) → tek başına çeviri `Bekle, Zarmon!` → `Bekle, Belus!`.
- Hazırlama sırası: `WE'VE GOT COMPANY, DOROS!` önce büyük harf düzeninden (`We've got company, Doros!`), sonra oyun
  deyiminden geçer; modele `Enemies are coming, Zarmon!` gider.
- Genel sözlükle hazır satırlar (model hiç çağrılmaz): `Level up!` → `Seviye atladın!`; `Watch out!` ve `WATCH OUT!` →
  `Dikkat et!`; `Behind you!` → `Arkanda!`; `Thanks for the help!` → `Yardımın için sağ ol!`; `Game over.` →
  `Oyun bitti.`; `It’s a trap!` → `Bu bir tuzak!`.
- Genel sözlükle modele gidenler (giden metin, model çıktısı, sonuç):
  `Chug a pot and keep moving.` → `Drink a Zarmon and keep moving.`, `Bir Zarmon iç ve devam et.` → `Bir şifa iksiri iç
  ve devam et.`; `GET THE ROCKET LAUNCHER!` → `Get the Zarmon!`, `Zarmon'u al!` → `Roket atarı al!`;
  `Use the grappling hook!` → `Use the Zarmon!`, `Zarmon'u kullan!` → `Kancalı halatı kullan!`; `The mobs are back.` →
  `The monsters are back.`, `Canavarlar geri döndü.` → aynı; `Grab the loot before you go.` → `Collect the items before
  you go.`, `Gitmeden eşyaları topla.` → aynı.
- Hiç değiştirilmeden modele gidenler: `Where is the rocket?`, `Open your map.`, `I'm saving you a seat.`.

### Mac'ten farkı (§3–§4)
Kurallar aynı; Mac'te model Apple Translation, Windows'ta OPUS-MT. Windows'ta "dil paketi indirme gerekli" yerine
model dosyaları indirilir (§8).

---

## 5. Terim sözlüğü (yalnız hedef `tr`)

### 5.1 Dosya biçimi
JSON; sondaki virgüllere ve yorumlara (`//`, `/* */`) izin verilir. Kök nesne olmalı (değilse dosya bozuk sayılır).
```json
{ "game": "Lantern Coast",
  "terms": { "Storm Lantern": "Fırtına Feneri", "Lantern": "Fener" },
  "keep": ["Doros", "Belus"],
  "keepExact": ["Raven"],
  "phrases": { "(?:light|fire) (?:a |the )?flares?(?! gun)": "fire a signal flare" },
  "lines": { "anchors up": "Demir alındı" } }
```
- `game` bilgi amaçlıdır, kullanılmaz.
- `terms`: İngilizce → Türkçe; değeri metin olmayan atlanır.
- `keep`: olduğu gibi kalacak adlar (Türkçesi kendisi); metin olmayan öğe atlanır.
- `keepExact`: olduğu gibi kalır ama **yalnız aynı büyük/küçük harfle** geçince eşleşir (`Raven` ad, `raven` kuzgun).
- **Terim ekleme kuralı** (üçü için): İngilizce ve Türkçenin iç boşlukları teklenir, kırpılır. İngilizcede harf yoksa,
  Türkçe boşsa ya da İngilizce **80** UTF-16 biriminden uzunsa alınmaz. Anahtar = İngilizcenin küçük hâli; aynı anahtar
  sonra gelirse ezer (bir dosyada `terms`, sonra `keep`, sonra `keepExact` sırasıyla işlenir).
- `phrases`: anahtar bir düzenli ifade, değer düz İngilizce. Anahtar ve değer boş değilse ve anahtar geçerli bir düzenli
  ifadeyse alınır (bozuk ifade atlanır).
- `lines`: anahtar "satır anahtarı"na çevrilir (§5.4), değerin boşlukları teklenir; ikisi de boş değilse alınır.

Örnek: `{ "terms": { "...": "x", "Selvard": "Selvard", "": "y" }, "keep": [false] }` → 1 terim.

### 5.2 Birleştirme ve kaynaklar
- Uygulamayla gelen genel sözlük (§5.6) + kullanıcı klasörü `%LOCALAPPDATA%\Nino\glossary\*.json` (yalnız `.json`;
  tam yol sırasıyla). Okunamayan ya da bozuk dosya atlanır.
- Birleşim sırası: genel, sonra kullanıcı dosyaları; terimlerde, `phrases`'te ve `lines`'ta aynı anahtarda **sonraki
  kazanır**.
- **İzleme:** sözlük istendiğinde son bakıştan **5 sn** geçmediyse eldeki döner. Geçtiyse klasördeki dosyaların
  "tam yol | boy | son yazma zamanı (UTC tik)" listesi çıkarılır; öncekinden farklıysa sözlük yeniden okunur. Klasör
  yoksa yalnız genel sözlük.
- Sözlük yalnız kaynak `en` → hedef `tr`'de kullanılır (ücretsiz çeviri ve DeepL).

Test: klasörde Lantern Coast dosyası, `broken.json` = `{ not json`, `notes.txt` (`keep: Ignored`) → `Storm Lantern` →
`Fırtına Feneri`, `healing potion` → `şifa iksiri`, `Ignored` yok. Olmayan klasör → genel sözlüğün terim sayısı.
Saat 0'da istendi (Doros yok), dosya yazıldı, aynı anda yine yok, 6 sn sonra `Doros` → `Doros`.

### 5.3 Eşleşme ve "büyük kalacak sözcükler"
- **Terimin Türkçesi:** soru boşlukları teklenip küçük harfe çevrilerek aranır (`storm  lantern` → `Fırtına Feneri`,
  `DOROS` → `Doros`).
- **Metindeki terimler:** terimler **uzundan kısaya**, eşit uzunlukta İngilizcenin sıralı (bayt) düzeniyle dolaşılır.
  Her terim için metinde soldan sağa aranır: `keepExact` ise tam harf eşleşmesi, değilse büyük/küçük harf duyarsız
  (sıralı karşılaştırmayla). Eşleşmenin iki yanı "sınır" olmalı (metnin başı/sonu ya da harf/rakam olmayan karakter) ve
  daha önce bulunmuş bir eşleşmeyle çakışmamalı. Bulunanlar metindeki konuma göre sıralanır. Her eşleşme: konum, uzunluk,
  sözlükteki İngilizce, Türkçe.
  - Lantern Coast sözlüğü (`Storm Lantern`, `Lantern`, `Selvard`, `Iron Reef` + keep `Doros`, `Belus`; 6 terim):
    `LIGHT THE STORM LANTERN, then the lantern. Doros's lanterns. Selvardian.` → `Storm Lantern` (konum 10), `Lantern`,
    `Doros`.
  - Genel sözlük: `Raven, you saw a raven. RAVEN!` → yalnız `Raven` (konum 0).
- **Büyük kalacak sözcükler:** `keepExact` olmayan ve İngilizcesinde en az bir büyük harf olan terimlerin boşlukla ayrılmış,
  ≥ 2 karakterli sözcükleri (küçük harfle). Lantern Coast → `belus, doros, iron, lantern, reef, selvard, storm`.
  Genel sözlükte `healing` yok (terimleri küçük harfli), `raven` yok (`keepExact`).

### 5.4 `lines` ve `phrases`
- **Satır anahtarı:** küçük harf (kültürden bağımsız), `’` ve `‘` → `'`, boşluklar teklenir, baştan ve sondan harf/rakam
  olmayan karakterler atılır.
- **Hazır satır:** cümlenin satır anahtarı `lines`'ta varsa Türkçesi; Türkçe `. ! ? …` ile bitiyorsa olduğu gibi, değilse
  kaynağın (kırpılmış) sonundaki `. ! ? …` dizisi eklenir. `Level up!` → `Seviye atladın!`; `anchors up` (kullanıcı
  `lines: {"Anchors up!": "Demir alındı"}`) → anahtar `anchors up` → `Demir alındı` (kaynağın sonunda işaret yok).
- **Argo düzleştirme:** `phrases` anahtarları sıralı (bayt) düzenle; her biri `\b(?: <anahtar> )\b` (boşluksuz) kalıbı
  olarak, büyük/küçük harf duyarsız ve kültürden bağımsız, en çok 100 ms zaman aşımıyla uygulanır. Eşleşmenin ilk harfi
  büyükse karşılığın ilk harfi büyütülür. `Kite the boss` → `Lure the boss` (kural `kite` → `lure`).
  Bozuk kural (`(`) alınmaz: `( a` değişmez.
- **"Yeniden yazıyor mu":** metnin satır anahtarı `lines`'ta varsa ya da bir `phrases` kalıbı metinde eşleşiyorsa evet.
  `They kite it.` → evet; `Kited.` → hayır.

### 5.5 Sözlük izi (önbellek anahtarına girer)
FNV-1a 32 bit: başlangıç `2166136261`, her UTF-8 bayt için `iz = (iz XOR bayt) × 16777619` (32 bit taşmalı).
Sırayla karıştırılır:
1. Terimler, **küçük harfli İngilizcelerine göre** sıralı (bayt) düzende: `ingilizce_küçük` + U+0001 + `türkçe` +
   (keepExact ise U+0003) + U+0002.
2. `phrases` anahtar sıralı: `anahtar` + U+0004 + `karşılık` + U+0005.
3. `lines` anahtar sıralı: `anahtar` + U+0006 + `türkçe` + U+0007.

Sonuç `g` + 8 haneli küçük hex. Boş sözlük `g811c9dc5`. **Genel sözlüğün izi `gcf7f6091`** (yeniden üretilen sözlük;
eski uygulamalarınkinden farklıdır, bu yüzden eski önbellek kayıtları sözlüklü satırlarda kullanılmaz; içerik bir harf
değişse iz değişir; `tools/gen-vectors.py` aynı izi bağımsız hesaplar). `keep: ["Raven"]` ile `keepExact: ["Raven"]`
farklı iz verir (genel sözlükte `Raven`'ı `keep`'e almak izi `g793e7afa` yapar). Sözlük + kullanıcı dosyası
(`storm lantern` → `fırtına feneri`) birleşince iz değişir; aynı birleşim aynı izi verir.

### 5.6 Genel sözlük (`glossary-en-tr.json`, 3674 bayt; `tools/gen-vectors.py` üretir)
Eski sözlük kopyalanmaz; içerik oyun türünün genel sözcüklerinden ve kısa kalıp satırlardan kendimiz yazdık.
- `game`: `Genel`.
- `terms` (26): save point → kayıt noktası; fast travel → hızlı yolculuk; side quest → yan görev; skill tree → beceri ağacı; skill point → beceri puanı; skill points → beceri puanları; healing potion → şifa iksiri; healing potions → şifa iksirleri; mana potion → mana iksiri; boss fight → boss savaşı; hit points → can puanı; stamina bar → dayanıklılık çubuğu; crafting table → üretim tezgâhı; loot chest → ganimet sandığı; respawn point → yeniden doğma noktası; difficulty level → zorluk seviyesi; new game plus → yeni oyun artı; mini map → mini harita; waypoint → yol işareti; quick save → hızlı kayıt; auto save → otomatik kayıt; dodge roll → kaçış yuvarlanması; stealth kill → sessiz infaz; rocket launcher → roket atar; supply drop → ikmal paketi; grappling hook → kancalı halat.
- `keep`: yok. `keepExact`: `Raven` (ad olarak büyük harfle; küçük `raven` kuzgun).
- `phrases` (10):
  - `(?:drink|chug|pop|use) (?:a |some |the |your )?pots?(?! of)` → `drink a healing potion`
  - `(?:grab|snag) (?:the |all the )?loot` → `collect the items`
  - `rez me` → `revive me`
  - `mobs` → `monsters`
  - `aggro` → `attention`
  - `noobs` → `beginners`
  - `noob` → `beginner`
  - `brb` → `be right back`
  - `afk` → `away from keyboard`
  - `gg` → `good game`
- `lines` (62, anahtar → Türkçe): checkpoint reached → Kontrol noktasına ulaşıldı; game saved → Oyun kaydedildi; saving → Kaydediliyor; loading → Yükleniyor; mission complete → Görev tamamlandı; mission failed → Görev başarısız; quest updated → Görev güncellendi; objective updated → Hedef güncellendi; new objective → Yeni hedef; level up → Seviye atladın; you died → Öldün; try again → Yeniden dene; game over → Oyun bitti; victory → Zafer; defeat → Yenilgi; inventory full → Envanter dolu; item acquired → Eşya alındı; not enough gold → Yeterli altın yok; not enough mana → Yeterli mana yok; i'm out of potions → İksirim kalmadı; heal me → Beni iyileştir; i need healing → İyileşmem lazım; i need a medic → Sıhhiye lazım; watch out → Dikkat et; behind you → Arkanda; look out → Dikkat; over here → Buraya; this way → Bu taraftan; follow me → Beni takip et; let's go → Hadi gidelim; let's move → Hadi ilerleyelim; hurry up → Acele et; keep moving → Durma, devam et; hold on → Bekle; run for it → Kaçın; retreat → Geri çekilin; charge → Saldırın; they're coming → Geliyorlar; here they come → İşte geliyorlar; more enemies → Daha fazla düşman; enemy ahead → Önde düşman; ambush → Pusu; it's a trap → Bu bir tuzak; boss incoming → Boss geliyor; the boss is down → Boss yenildi; nice shot → Güzel atış; good job → Aferin; well done → Aferin; thanks for the help → Yardımın için sağ ol; i'm on it → Hallediyorum; on my way → Geliyorum; wait for me → Beni bekle; we did it → Başardık; area secured → Bölge güvende; all quiet → Ortalık sakin; out of arrows → Ok kalmadı; need arrows → Ok lazım; low health → Can az; shield's down → Kalkan düştü; open the gate → Kapıyı aç; close the gate → Kapıyı kapat; find the key → Anahtarı bul.

Üretici dosyayı her çalıştırmada bayt bayt aynı yazar; iz `gcf7f6091` bunu doğrular (JSON'daki anahtar sırası izi
etkilemez ama metinlerin her karakteri etkiler). Genel sözlükte en az 10 terim; `Healing Potion` → `şifa iksiri`;
`skill tree` → `beceri ağacı`.

---

## 6. Terim koruma, Türkçe ek kurma, Türkçe düzeltme

### 6.1 Uydurma adla koruma
Çeviriden önce sözlük terimi uydurma bir özel adla değiştirilir. Neden: OPUS-MT özel adı değiştirmeden bırakıp Türkçe eki kesme işaretiyle ekliyor (`Zarmon'u al`); `[[1]]`, `__T1__` gibi işaretler model sözlüğünde olmadığı için düşüyor/bozuluyor.

- Ad listesi (sırayla): `Zarmon, Velkor, Dorvan, Kelmar, Tolvar, Brandur, Halvor, Feldor` (Türkçe/İngilizce sözcük değil,
  birbirinin başı değil, `i/I` içermez, ünsüzle biter, kalın ünlülü). Koruyucu kurulurken verilen kaynak metinlerden
  birinde (büyük/küçük harf duyarsız) geçen ad kullanılmaz.
- Koruma: metindeki terimler (§5.3) sırayla; aynı terim (küçük harfli İngilizcesi) aynı adı alır; yeni terim sıradaki boş
  adı alır; ad kalmadıysa o terim korunmaz (yerinde kalır). Terim metinde adla değiştirilir. Bu metinde kullanılan adlar
  (tekrarsız, ilk geçiş sırasıyla) döner. Koruyucu, bütün metinlerde verdiği adları da bilir ("hepsi").
- Örnek (Lantern Coast: Storm Lantern, Selvard, healing potion + keep Doros, Belus): `Doros! The Storm Lantern stays in
  Selvard, Doros.` → `Zarmon! The Velkor stays in Dorvan, Zarmon.`, adlar sırası `Doros, Storm Lantern, Selvard`.
- Kaynakta zaten geçen ad atlanır: kaynak `Zarmon waved at Doros.` → `Zarmon waved at Velkor.`.
- Terimsiz metin değişmez, ad yok.

### 6.2 Geri koyma
Girdi: model çıktısı, beklenen adlar (bu metnin), isteğe bağlı "hepsi", kesme türü. Beklenen de "hepsi" de boşsa çıktı
aynen döner.
1. "Hepsi" içinde olup beklenenlerde olmayan bir ad çıktıda geçiyorsa → **geçersiz** (bağlamın adı satıra kaymış).
2. Her beklenen ad için kalıp: önünde harf/rakam yok; ad (büyük/küçük harf duyarsız); isteğe bağlı ek: ya (isteğe bağlı
   tek boşluk + `'`, `’`, `` ` ``, `´` kesmelerinden biri + bir ya da daha çok harf) ya da (doğrudan bitişik bir ya da
   daha çok harf); ardında harf/rakam yok. Ad çıktıda hiç geçmiyorsa → **geçersiz**.
3. Her eşleşme: ek (kesmeli ya da bitişik kısım) alınır; terimin Türkçesi + ek §6.3 ile kurulur. Eşleşme **cümle
   başındaysa** (önünde, geriye doğru, yalnız boşluk, `"`, `“`, `'`, `‘`, `(`, `-`, `–`, `—`, `¡`, `¿` var ve ondan önce
   metnin başı ya da `. ! ? …`) kurulmuş terimin ilk harfi küçükse **Türkçe kültürüyle** büyütülür. Cümle başı denetimi
   değiştirilmemiş çıktıya göre yapılır.

Örnekler (yukarıdaki koruma):

| Model çıktısı | Sonuç |
|---|---|
| `Zarmon! Velkor Dorvan'da kalıyor, Zarmon.` | `Doros! Fırtına Feneri Selvard'da kalıyor, Doros.` |
| `ZARMON! VELKOR DORVAN'DA KALIYOR, ZARMON.` | `Doros! Fırtına Feneri Selvard'da KALIYOR, Doros.` |
| `Zarmon! Velkor Dorvan ’da kalıyor, Zarmon.` | `Doros! Fırtına Feneri Selvard'da kalıyor, Doros.` |
| (yalnız `The Storm Lantern stays in Selvard.`: Zarmon, Velkor) `Fener Velkor'da kalıyor.` | geçersiz (Zarmon yok) |
| (`Doros!` sonra `Sail to Selvard.` korundu) `Zarmon, Velkor'a yelken aç.` | geçersiz (Zarmon başka metnin) |
| aynı, `Velkor'a yelken aç.` | `Selvard'a yelken aç.` |
| (`Healing potion now! Drink the healing potion.`) `Hemen Zarmon! Zarmon'u iç.` | `Hemen şifa iksiri! Şifa iksirini iç.` |
| (`She whispered 'Selvard' twice.`) `İki kez 'Zarmon' diye fısıldadı.` | `İki kez 'Selvard' diye fısıldadı.` (tırnak ek sayılmaz) |
| (terimsiz) `Hemen çıkıyoruz.` | aynen |

### 6.3 Türkçe ekin yeniden kurulması
Girdi: terim (Türkçe), ek (modelin uydurma ada koyduğu, kesmesiz), kesme türü (varsayılan `'`). Ünlüler `aeıioöuü`;
kalın `aıou`; yuvarlak `ouöü`; dar `ıiuü`; sert ünsüzler `fstkçşhp`. Küçük harf dönüşümleri Türkçe kültürüyle.
1. Terim ya da ek boşsa terim döner.
2. ek' = ekin küçük hâli. 12'den uzunsa ya da harf olmayan karakter içeriyorsa: `terim + kesme + ek` (özgün ek) döner.
3. Özel ad = terimin ilk harfi büyük. Son sözcük = son boşluktan sonrası (küçük harfle). Son harf = son sözcüğün son
   harfi; son ünlü = son sözcüğün son ünlüsü.
4. Ünlüyle biter = son ünlü yok (ünlüsüz kısaltma, `XP`) **ya da** son harf ünlü. Son ünlü yoksa `e` sayılır.
5. Tamlama = terimde boşluk var **ve** son harf dar ünlü **ve** son sözcük ≥ 3 harf.
6. Sert = ünlüyle bitmiyor **ve** son harf sert ünsüz.
7. Baştaki kaynaştırma harfi (uydurma ada göreydi) atılır: ek' ≥ 2 harf, `y` ile başlıyor ve ikinci harf ünlü ya da `l`
   ise ilk harf atılır (`ya` → `a`, `yla` → `la`); değilse ek' ≥ 3 harf, `n` + dar ünlü + `n` ile başlıyorsa ilk harf
   atılır (`nın` → `ın`).
8. İlgi eki = ek' ≥ 2, ilk harf dar ünlü, ikinci `n`, ve (2 harfli ya da üçüncü harf ünlü değil). Vasıta eki = ek' ≥ 2,
   `l` + (`a` ya da `e`), ve 3. harf `r` değil (çoğul `lar/ler` değil).
9. Araya giren harf:
   - ek' ünlüyle başlıyorsa: tamlama ya da (ünlüyle biter ve ilgi eki) → `n`; değilse ünlüyle biter → `y`.
   - `d` ya da `t` ile başlıyorsa: tamlama → `n`; ilk harf (tamlama ya da sert değilse) `d`, sert ise `t` olur.
   - değilse vasıta eki ve (ünlüyle biter ya da tamlama) → `y`.
10. **Ünlü uyumu:** ek'in her harfi soldan sağa; "önceki ünlü" son ünlüden başlar. Sondaki `-ki` (son harf `i`, öncesi
    `k`) değişmez. `a/e` → önceki kalınsa `a`, değilse `e`. Dar ünlü → kalın+yuvarlak `u`, kalın+düz `ı`, ince+yuvarlak
    `ü`, ince+düz `i`. Her ünlü (değişmiş hâliyle) "önceki ünlü" olur.
11. Özel ad: `terim + kesme + araya giren + uyumlu ek`.
12. Cins ad: araya giren yok ve uyumlu ek ünlüyle başlıyorsa terim **yumuşatılır**; `terim + araya giren + uyumlu ek`
    (bitişik). Yumuşama: terim < 2 karakterse yok; son sözcük `nk` ile bitiyorsa son harf `g` olur (`renk` → `reng`);
    son sözcükte 2'den az ünlü varsa yok (tek heceli: `top`); son harf `p`→`b`, `ç`→`c`, `k`→`ğ`; `t` dokunulmaz.

Test tablosu:

| Terim | Ek | Sonuç |
|---|---|---|
| Doros | u / un / a / da / dan / la / dur | Doros'u / Doros'un / Doros'a / Doros'ta / Doros'tan / Doros'la / Doros'tur |
| Belus | un / a | Belus'un / Belus'a |
| Selvard | a / da / u / un / daki | Selvard'a / Selvard'da / Selvard'ı / Selvard'ın / Selvard'daki |
| Mirna | u / a / un / la / da / nın | Mirna'yı / Mirna'ya / Mirna'nın / Mirna'yla / Mirna'da / Mirna'nın |
| Telir | a / u / un / dan | Telir'e / Telir'i / Telir'in / Telir'den |
| Drok | da / u | Drok'ta / Drok'u |
| Velheim | a / da | Velheim'e / Velheim'de |
| Vor | un | Vor'un |
| Ardur | u | Ardur'u |
| Kendri | un / u | Kendri'nin / Kendri'yi |
| Varin | a / ya | Varin'e / Varin'e |
| Doros | nın / (boş) | Doros'un / Doros |
| Fırtına Feneri | u / a / da / dan / un / la | Fırtına Feneri'ni / 'ne / 'nde / 'nden / 'nin / 'yle |
| Liman Kulesi | a | Liman Kulesi'ne |
| Gece Kılıçları | u | Gece Kılıçları'nı |
| şifa iksiri | u | şifa iksirini |
| yeniden doğma noktası | a | yeniden doğma noktasına |
| zorluk seviyesi | da | zorluk seviyesinde |
| fener | a / da | fenere / fenerde |
| ağaç / dolap / kayak / denk / ip | u | ağacı / dolabı / kayağı / dengi / ipi |
| çapa | u / lar | çapayı / çapalar |
| kapan | lar / dan / la | kapanlar / kapandan / kapanla |
| Doros (kesme `’`) | un | Doros’un |
| HP | u | HP'yi |
| Selvard | A | Selvard'a |

### 6.4 Türkçe düzeltme (tek cümle; yalnız ücretsiz çeviri ve hazır satırlar, hedef `tr`)
Çeviride harf yoksa dokunulmaz. Sırayla:
1. **Tırnaklar:** kaynakta `“` ya da `”` varsa çevirideki düz `"` kıvrık olur (önündeki karakter yok, boşluk ya da
   `( [ - – —` ise `“`, değilse `”`); yoksa çevirideki `“ ” „ ‟` düz `"` olur. Tek tırnak aynı mantıkla: kaynakta `’`
   ya da `‘` varsa `'` → `‘`/`’`; yoksa `’ ‘` → `'`.
2. Noktalamadan (`, . ! ? ; : …`) önceki boşluk/sekme/bölünmez boşluk silinir.
3. İki ve daha çok boşluk/sekme/bölünmez boşluk teke iner; baş ve son kırpılır.
4. **Son işaret:** metin = gövde + son işaret dizisi (`. ! ? …`) + kapanış dizisi (`" ' ” ’ ) ] »`), sondaki boşluklar
   atılarak ayrılır. Kaynağın son işareti "ifadeli" değilse (ifadeli: boş değil ve `!`, `?` ya da `…` içeriyor ya da tam
   `...`) dokunulmaz. Kaynakta kapanış var ama çeviride yok (ya da tersi) ise dokunulmaz. Çevirinin son işareti kaynağınkiyle
   aynıysa ya da (boş, `.` ya da ifadeli) değilse dokunulmaz. Gövdede harf yoksa dokunulmaz. Değilse gövde + kaynağın son
   işareti + çevirinin kapanışı.

| Kaynak | Çeviri | Sonuç |
|---|---|---|
| `Run!` | `Koş.` / `Koş` | `Koş!` |
| `What?!` | `Ne?` | `Ne?!` |
| `Wait…` | `Bekle.` | `Bekle…` |
| `Wait...` | `Bekle.` | `Bekle...` |
| `Where is she?` | `Kız nerede.` | `Kız nerede?` |
| `She yelled "Row!"` | `"Kürek çek." diye bağırdı.` | aynen |
| `She yelled "Row!"` | `"Kürek çek" diye bağırdı` | aynen |
| `"Run!"` | `"Koş."` | `"Koş!"` |
| `We go.` | `Gidiyoruz!` / `Gidiyoruz` | aynen |
| `Boy!` | `Evlat!` | aynen |
| `Okay. Go.` | `Gel , çabuk !` | `Gel, çabuk!` |
| `Okay. Go.` | `Kim  geldi ?` | `Kim geldi?` |
| `Okay. Go.` | `Tamam ... çıkalım .` | `Tamam... çıkalım.` |
| `She said "row", Doros's daughter.` | `“Kürek çek” dedi, Doros’un kızı.` | `"Kürek çek" dedi, Doros'un kızı.` |
| `She said “row”, Doros’s daughter.` | `"Kürek çek" dedi, Doros'un kızı.` | `“Kürek çek” dedi, Doros’un kızı.` |

### 6.5 Hitap (satırın bütün cümleleri)
Cümle çevirilerinden (boş olanlar atlanır) birinde, Türkçe kültürüyle küçük harfe çevrilip harf olmayanlardan bölünmüş
sözcükler arasında `sen, seni, sana, senin, sende, senden, seninle, senle` varsa: aynı biçimde `siz, sizi, size, sizin,
sizde, sizden, sizinle, sizler` sözcüğü **geçmeyen** her cümlede bilinen "siz"li emirler "sen"e çevrilir; geri kalan metin değişmez. Emir değişimi: önünde harf yok; emir (büyük/küçük harf duyarsız); ardından (isteğe bağlı boşluklar +
`! . , ? …`) ya da (isteğe bağlı boşluklar + satır sonu). Eşleşmenin ilk harfi büyükse karşılığın ilk harfi Türkçe kültürüyle
büyütülür. Liste (bu sırayla): dikkat edin→dikkat et, acele edin→acele et, ateş edin→ateş et, yardım edin→yardım et,
takip edin→takip et, sessiz olun→sessiz ol, hazır olun→hazır ol, sakin olun→sakin ol, bekleyin→bekle, durun→dur,
gelin→gel, koşun→koş, gidin→git, bakın→bak, dinleyin→dinle, saklanın→saklan, kaçın→kaç, savaşın→savaş, dövüşün→dövüş,
durdurun→durdur, çekilin→çekil, eğilin→eğil, atlayın→atla, tutun→tut, bırakın→bırak, söyleyin→söyle, gösterin→göster,
getirin→getir, kalkın→kalk, odaklanın→odaklan, yaklaşın→yaklaş, uzaklaşın→uzaklaş. (`alın` bilerek yok.)

| Cümleler | Sonuç |
|---|---|
| `Seni uyardım.` · `Bekleyin!` · `Dikkat edin, denizci.` | `Seni uyardım.` · `Bekle!` · `Dikkat et, denizci.` |
| `Sana inanıyorum. Hemen koşun!` | `Sana inanıyorum. Hemen koş!` |
| `Bekleyin!` | değişmez |
| `Siz durun, sana sonra yetişirim!` | değişmez |
| `Sen de gelin mi oldun?` | değişmez (`gelin` ardından işaret ya da satır sonu yok) |
| boş · `Seni uyardım.` · boş · `Durun!` | boş · `Seni uyardım.` · boş · `Dur!` |

Ücretsiz çevirmenle: `I told you to stay on the ship. Wait here!` (model `Sana gemide kalmanı söyledim.` ve bağlamlı
`Sana gemide kalmanı söyledim. *** Burada bekleyin!`) → `Sana gemide kalmanı söyledim. Burada bekle!`.

### Mac'ten farkı (§5–§6)
Aynı kurallar; genel sözlük yeniden üretildiği için içeriği ve izi (`gcf7f6091`) Mac'inkinden farklı. Windows'ta sözlük klasörü `%LOCALAPPDATA%\Nino\glossary`.

---

## 7. Ücretsiz çevirmen (OPUS-MT) nesnesi

Hedef dil başına **bir** nesne (dil değişse de aynı dil için yeniden kullanılır; aygıt ya da iş parçacığı sayısı değişince
hepsi kapatılıp sonraki çeviride yeniden kurulur). Kurulur kurulmaz arka planda **ısıtılır**: kısa bir İngilizce selamlama cümlesi çevrilir
(hata fırlatmaz, gözlenmemiş hata bırakmaz; motor açılamazsa "motor açılamadı" olayı bir kez gelir).

- **Model dizini** hedefe göre (§8.1). Dizinde `model.bin` varsa CTranslate2 işçisi (§8.6), yoksa ONNX motoru (§8.8).
- **Kurulu mu:** CTranslate2 deposu kurulu (§8.4) **ya da** ONNX'in 4 dosyası (`encoder_model_int8.onnx`,
  `decoder_model_merged_int8.onnx`, `source.spm`, `vocab.json`) dizinde.
- **Durum:** motor daha önce açılamadıysa "motor açılamadı"; motor açıksa ya da kuruluysa "hazır"; değilse "indirme
  gerekli".
- **Cümle çevirisi:**
  1. Önbellekte (§4.4 anahtarıyla) varsa döner (motor açılamamış olsa da).
  2. Tek seferde tek cümle: bir kilit beklenir (paralel çeviri çekirdekleri bölüştürüp her satırı geciktiriyordu).
     Beklerken iptal edilirse iptal hatası.
  3. Kilit alınınca: kapatıldıysa "kapatıldı" hatası; önbelleğe yeniden bakılır (beklerken başkası çevirmiş olabilir).
  4. Motor daha önce açılamadıysa "motor açılamadı" hatası. Motor yoksa kurulur: kurulu değilse "indirme gerekli" hatası
     (motor kurulmaya çalışılmaz); kurulurken hata olursa (iptal dışında) bu çevirmen kalıcı "motor açılamadı" olur, olay
     **bir kez** bildirilir.
  5. Metin hattı (§4) arka plan iş parçacığında çalışır; model çağrısı motorun "cümle çevir" işlemidir.
  6. Motor bir **giriş/çıkış hatası** verirse (işçi süreci kapandı): kalıcı "motor açılamadı", olay bir kez, hata. Tek
     satırın başka hatası (işçi ayakta, satır çevrilemedi) yalnız o satırı düşürür.
  7. Sonuç kilit bırakılmadan önbelleğe yazılır.
- Satır çevirisi §4.1–§4.3.
- Kapatma: kilit alınır, motor kapatılır; sonra önbellekte olmayan çeviri "kapatıldı" hatası verir, önbellektekiler döner.

Testler (sahte motor; çıktı = cümlenin büyük harfi):
- `Wait!` iki kez → `WAIT!`, tek çağrı; `wait!` yeni çağrı (önbellek tam metne bakar).
- `We sail to the island now. Stay behind me, Tomas.` sonra `… Watch the rocks.` → çağrılar `We sail to the island now.`,
  `Stay behind me, Tomas.`, `Watch the rocks.`.
- `VERA: Captain, look!⏎RUIZ: Stay.` → `VERA: CAPTAIN, LOOK!⏎RUIZ: STAY.`; `...` → `...`; çağrılar
  `Captain, look!`, `Captain, look! *** Stay.` (kısa `Stay.` önceki cümleyle).
- `VERA: Captain, look!` sonra `THE HULL WILL NOT HOLD, VERA.` → son çağrı `The hull will not hold, Vera.`.
- `OLD SAILOR: Ahoy.` sonra `RUN, OLD SAILOR!` → son çağrı `Ahoy. *** Run, Old Sailor!`.
- Konuşmacı adları: `VERA: Captain!` → `VERA: CAPTAIN!` (çağrı `Captain!`); `OLD SAILOR: Who rang the bell?`;
  `Ship Doctor: Sister, wait.` → `Ship Doctor: SISTER, WAIT.`; `Tip: Press Y.` → `TIP: PRESS Y.` (çağrı
  `Tip: Press Y.`, etiket değil).
- Kalıcı önbellek: 1. oturum `RUIZ: We leave now. Keep low.`; 2. oturum aynı satır modelsiz `RUIZ: WE LEAVE NOW. KEEP
  LOW.`; sonra `We leave now. Row to the boat, Tomas!` → çağrılar `Keep low. *** We leave now.` (kısa `We leave now.`
  önceki satırın son cümlesiyle) ve `Row to the boat, Tomas!`.
- Model kurulu değil → durum "indirme gerekli", çeviri bu hatayı verir, motor hiç kurulmaz. Boş dizinle gerçek kurucu da
  aynı.
- Motor kurulamıyor (çalışma zamanı eksik) → "motor açılamadı" (iç hata dosya bulunamadı); ikinci satır da aynı; kurulum
  1 kez denendi; olay 1 kez. Isıtma hata bırakmadan biter, olay 1 kez. Önbellekteki satır yine döner, yenisi hata.
- İşçi kapanması (giriş/çıkış hatası) → iki satır da "motor açılamadı", olay 1 kez, motor 1 kez çağrıldı.
- 40 eşzamanlı satır (`Rope number 0..9 is ready.`, dört kez) → sonuçlar doğru, hiç eşzamanlı çağrı yok, 10 çağrı.
- İptal: biri kilitteyken bekleyen ikinci iptal edilince iptal hatası; birincisi tamamlanır.
- Kapatınca motor kapanır; yeni satır "kapatıldı"; önbellekteki satır döner.
- Motor adı `opus-mt-ct2-p3`.
- Kısa satır: `Who took the map?` → `Haritayı kim aldı?`; `Not me.` → (`Who took the map? *** Not me.` →
  `Haritayı kim aldı? *** Ben değil.`) `Ben değil.`; yeniden okunan `Not me.` önbellekten; toplam 2 çağrı. 1 dk aradan
  sonra `Not me.` tek başına çevrilir.
- Sözlük klasöründe Lantern Coast (`Storm Lantern`, keep `Doros`): `DOROS, LIGHT THE STORM LANTERN!` → (çağrı `Zarmon,
  light the Velkor!`) `Doros, Fırtına Feneri'ni yak!`.

Gerçek modelle (kurulu ise; `NINO_TEST_MODELS`) test kendi seçtiği birkaç cümlenin Türkçesinde beklenen bir parça arar:
ünlem korunur, konuşmacı etiketi aynen kalıp gövde çevrilir, tümü büyük harfli cümle küçük harfli hâliyle aynı anlamı
verir, iki satırlı blok tek cümle gibi çevrilir, oyun deyimi (§4.2) açılmış anlamla çevrilir, bilinen ad olduğu gibi
kalır.

---

## 8. Yerel modeller

### 8.1 Diller ve klasörler
| Hedef | Model | Klasör (`%LOCALAPPDATA%\Nino\models\…`) | Motor |
|---|---|---|---|
| `tr` | OPUS-MT tc-big en-tr, CTranslate2 dönüşümü | `en-tr-ct2` | CTranslate2 işçisi |
| `ar` | opus-mt-en-ar (Xenova int8 ONNX) | `en-ar` | ONNX |
| `hi` | opus-mt-en-hi | `en-hi` | ONNX |
| `id` | opus-mt-en-id | `en-id` | ONNX |
| `vi` | opus-mt-en-vi | `en-vi` | ONNX |
| `nl` | opus-mt-en-nl | `en-nl` | ONNX |

`th`, `ur`, `bn`, `ms`, `tl` için ücretsiz model **yok**: o dillerde ücretsiz çeviri "desteklenmiyor"; yalnız yapay zekâ
motorları çevirir. Ücretsiz çeviri yalnız kaynak `en`'de. Dil kodu hedefin ilk iki harfi, küçük harf.

**Hedef belirteci** (çok hedefli modellerde girdinin başına): `ar` → `>>ara<<`, `vi` → `>>vie<<`; öbürlerinde yok.
Belirteç modelin `vocab.json`'unda yoksa model açılmaz (hata).

Türkçe model kurulunca eski sürümlerin ONNX Türkçe modeli (`models\en-tr`, ~530 MB) silinir (silinemezse günlüğe).

### 8.2 İndirme (her dosya: ad, adres, boy, SHA-256)
- HTTP istemcisi toplam süre sınırsız; **60 sn** hiç veri gelmezse "indirme takıldı" hatası.
- Aynı depoda aynı anda tek indirme.
- Dosya "kurulu" = asıl adıyla duruyor **ve** boyu beklenen boy (özet yeniden hesaplanmaz; özet indirmede denetlenir).
- Kurulu dosyalar atlanır (ilerlemeye boyları eklenir). Eksik her dosya:
  1. `<ad>.part` varsa boyu alınır; beklenenden büyükse silinir.
  2. Boyu 0 < boy < beklenen: `Range: bytes=<boy>-` ile istenir. Yanıt **206** ise önce mevcut parçanın baytları özete
     katılır, sonra gövde sona eklenir. Değilse (sunucu aralığı yok saydı) başarı kodu olmalı ve dosya baştan yazılır.
  3. Boy = beklenen: mevcut parça özetlenir (yeniden indirilmez).
  4. Parça yok: baştan indirilir (başarı kodu olmalı).
  5. Sonunda boy ve SHA-256 (büyük/küçük harf duyarsız) tutmazsa parça **silinir** ve "boy/özet tutmadı" hatası.
     Tutarsa asıl adına taşınır (üstüne yazarak). Asıl adla duran her dosya doğrulanmıştır.
- İptalde asıl dosya oluşmaz (parça kalabilir; sonraki indirme kaldığı yerden sürer).
- İlerleme 0–1 (toplam bayt oranı), yalnız en az binde bir arttığında bildirilir; sonunda 1 bildirilmemişse 1.
- Test (sahte, aralık destekli sunucu): iki dosya iner, `.part` kalmaz, son ilerleme 1, ilerleme azalmaz; özet tutmazsa
  hata, dosya da parça da yok; boy tutmazsa hata; asıl adla ama kısa dosya kurulu sayılmaz; 120 000 baytlık parçadan
  `bytes=120000-` ile sürer; aralık desteklenmezse baştan; bozuk parça (sıfırlar) önce hata, ikinci denemede başarı;
  kurulu dosyalarda istek yok ama ilerleme 1; 100 000 bayttan sonra iptal → kurulu değil, sonra tamamlanır. Türkçe
  belirteç dosyaları 2 adet, adresleri `/resolve/ce128ea834a090aca240e4e113e7756e06cc78e0/` içerir, toplam 2–3 MB.

### 8.3 Dosya listesi

**Türkçe belirteç dosyaları** (`https://huggingface.co/onnx-community/opus-mt-tc-big-en-tr/resolve/ce128ea834a090aca240e4e113e7756e06cc78e0/<ad>`):

| Ad | Boy | SHA-256 |
|---|---|---|
| `source.spm` | 796 953 | `180d3f94ddfee5585d78b702290ded0f4f9bd40f299349c8383b32a579fefad4` |
| `vocab.json` | 1 501 287 | `01ef522455d2bf22b0716416ee34688cc2b3f5fa257f742665d21b6acc450ac1` |

(Türkçe kurulumda bu listeden yalnız `vocab.json` indirilir; `source.spm` arşivden gelir, §8.4.)

**ONNX dilleri** — adres `https://huggingface.co/Xenova/opus-mt-<çift>/resolve/<sürüm>/<yol>`; kodlayıcı ve kod
çözücünün yolu `onnx/<ad>`, öbürleri kökte. Dosya adları her dilde aynı: `encoder_model_int8.onnx`,
`decoder_model_merged_int8.onnx`, `source.spm`, `vocab.json`.

| Çift | Sürüm (revizyon) |
|---|---|
| `en-ar` | `034a684356c19021a187cda4d7f823298b913921` |
| `en-hi` | `7aad72006a1588a9c3485ed6203aed99eebbc872` |
| `en-id` | `b3b41f654c2fb3286d007dee1da7b0f47fd27d82` |
| `en-vi` | `30bcd461c0d7338ad106b36314d3eedc2d4e998c` |
| `en-nl` | `c3a0541231a7329b4492809fc2bd7ab7d2ceb0bc` |

| Çift | Dosya | Boy | SHA-256 |
|---|---|---|---|
| en-ar | encoder_model_int8.onnx | 51 600 664 | `045dce89bd4b5bd5d8f546b9e3f9b506a9dbae70c551e8744eac67564050ddfd` |
| en-ar | decoder_model_merged_int8.onnx | 58 878 333 | `f2cd3894f105e5859d60cd66ad5f83356a3343e68f60c1997627a6e2d156f549` |
| en-ar | source.spm | 801 074 | `81ac8f4d4ee271f4109eac67560a31f9c2d555463ba5eb95c32c6deee8ae819d` |
| en-ar | vocab.json | 2 243 581 | `8b74af9e4c1ec122b8d06362db6c38795e10ca2b0156b2110cf08d4716744b76` |
| en-hi | encoder_model_int8.onnx | 51 164 441 | `8b53ce50ba917cf4b77d6713a01cb767d16a6a92fe4a56bec4d3576fb9d1e4e2` |
| en-hi | decoder_model_merged_int8.onnx | 58 438 702 | `7c21712321e7a02aa1f0f676b4beeef8cdccd0c295cdc642eea97991ce59b180` |
| en-hi | source.spm | 812 240 | `fd4e951487aed00bae6a6c2ee4ef5d8d1db05fd098b19b608046c9334b58d24d` |
| en-hi | vocab.json | 2 221 738 | `be02f5dfb85054d4f25089f6b347b69d32e98ed4c3d181ed0c789904eb1e3d3b` |
| en-id | encoder_model_int8.onnx | 47 501 593 | `577591fb62f86b82b9cddd799bae274b8e9b489a7439bb13ea2d5c4510f34f08` |
| en-id | decoder_model_merged_int8.onnx | 54 747 238 | `c36b784308b4983be64f076e237332709af48f7e575a9a535fd138d9fbdd468c` |
| en-id | source.spm | 795 925 | `e88300911c2c573ec5526777a1e84bae698d20925b82dcef9c7248bb0e537ed0` |
| en-id | vocab.json | 1 366 984 | `cda834905a5d478c54a73abc98cc9155dc58217baa130cdf165411265b760d6b` |
| en-vi | encoder_model_int8.onnx | 46 932 760 | `0aa4c958dc2171312b15d70e2fb1a036feca9ff5e098609ee0ea31ebd21b3c98` |
| en-vi | decoder_model_merged_int8.onnx | 54 173 961 | `c1ec8c85d68119cb419518d30a504ebf625f8e36d62f588c4e0a1466cd6d6e28` |
| en-vi | source.spm | 808 612 | `fdd9ab486ca8ea060967105e30db7d8928729c78a67448711d2dd7c3153b37cd` |
| en-vi | vocab.json | 1 299 764 | `bcc8bbafeb0b6b58fecf244f8da996da9aa45dbea7871164f9c8ce480507f9fe` |
| en-nl | encoder_model_int8.onnx | 53 764 376 | `3857b90ec2dd0d5f2f4bb637dbe6f6f9e80d9cbed55391d1aa943cffa0cc628f` |
| en-nl | decoder_model_merged_int8.onnx | 61 058 949 | `3c6bf76b6711dfc3e73d7bf85b3964bd40f425b35d6b721118233b71b9a1ccd4` |
| en-nl | source.spm | 789 525 | `d05781fde84b8793191528a7a176e1b17f96265388f602379ee6ae3139f59141` |
| en-nl | vocab.json | 1 794 274 | `b1fba91c620564d90848c5f77b03f13d17949790f8e7c7741e4a8ea13b8b0d91` |

Lisanslar (eski koddaki notlara göre): en-ar CC BY 4.0, en-hi/id/vi/nl Apache-2.0; en-tr arşivi kendi `LICENCE.txt`'ini
taşır (§8.4). Hakkında ekranı başka belgede.

### 8.4 Türkçe CTranslate2 modeli
- Arşiv `opus-mt-en-tr.zip`, adres
  `https://huggingface.co/Unbakedcookie/live-translator-models/resolve/50473df5681764ebdef107dd78f7d21da66c28a7/opus-mt-en-tr.zip`,
  boy **474 595 937**, SHA-256 `acabcdc3becfbf4d740c3012d6dc4e8a1ba6ed41a62a125c37f6c228667ff9b9`.
- **Kurulu mu:** klasörde `model.bin`, `config.json`, `source.spm`, `vocab.json` var **ve** (`shared_vocabulary.json`
  **ya da** hem `source_vocabulary.json` hem `target_vocabulary.json`) var.
- İndirme (aynı anda tek): kuruluysa ilerleme 1, bitti. Değilse arşiv §8.2 ile indirilir (ilerleme yalnız arşive
  göre); sonra `vocab.json` (§8.3 tablosu) indirilir. Arşivden **dosya adı** şunlardan biri olan girdiler (klasör yolu
  yok sayılarak) çıkarılır: `model.bin`, `config.json`, `shared_vocabulary.json`, `source_vocabulary.json`,
  `target_vocabulary.json`, `source.spm`, `target.spm`, `opus_mt.json`, `LICENCE.txt`; her biri `.part`'a yazılıp asıl
  adına taşınır. Sonra kurulu değilse "arşivde model ya da sözlük dosyası eksik" hatası; kuruluysa arşiv silinir,
  ilerleme 1.

### 8.5 GPU (NVIDIA CUDA) ve iş parçacığı
- Ayar "GPU" seçilince: `%WINDIR%\System32\nvcuda.dll` (NVIDIA sürücüsü) varsa CUDA çalışma zamanı indirmesi arka planda
  başlar (yoksa indirme boşa ~565 MB olurdu, CPU'da kalınır). İndirme hatası günlüğe yazılır. Açık çevirmenler kapanır.
- CUDA çalışma zamanı klasörü `%LOCALAPPDATA%\Nino\cuda-12.8`. Arşivler (taban `https://developer.download.nvidia.com/compute/cuda/redist/`):

| Arşiv | Yol | Boy | SHA-256 |
|---|---|---|---|
| `libcublas-windows-x86_64-12.8.4.1-archive.zip` | `libcublas/windows-x86_64/` | 563 660 944 | `57a470112cec7e112c95253dde8b3c7184d795dbd92b0bde77a4cb7f8c94c8aa` |
| `cuda_cudart-windows-x86_64-12.8.90-archive.zip` | `cuda_cudart/windows-x86_64/` | 3 037 735 | `4a39058fd8519444a81cfc7ae055d136f48d1a31ffa41ae255b35b2edd61e13b` |

- Gerekli DLL'ler ve boyları: `cublas64_12.dll` 113 716 224; `cublasLt64_12.dll` 674 667 520; `cudart64_12.dll`
  573 952. **Kurulu** = üçü de tam bu boyda duruyor.
- İndirme: tek ortak görev (aynı anda iki kez başlamaz; başarısız olduysa sonraki seçimde yeniden başlar; kuruluysa hemen
  biter). İki arşiv §8.2 ile iner; sonra ikisinin SHA-256'sı yeniden hesaplanır (tutmazsa arşiv silinir, hata). Her
  arşivde, adı `/bin/<dll>` ile biten girdi (varsa) boyu tutmalı (tutmazsa hata), `.part` üzerinden çıkarılır. cuBLAS
  arşivinde `/LICENSE` ile biten tek girdi `CUDA-LICENSE.txt` olarak yazılır. Sonra kurulu değilse hata; kuruluysa iki
  arşiv silinir.
- Çevirmen GPU ile kurulurken: CUDA görevi yoksa ya da başarıyla bittiyse hemen CUDA işçisi denenir; açılamazsa "GPU'dan
  CPU'ya düşüldü" bildirilir ve CPU işçisi açılır. Görev sürüyorsa CPU işçisiyle başlanır; görev bittikten sonraki ilk
  çeviride (bir kez) başarılıysa CUDA işçisi açılıp CPU işçisi kapatılır, başarısızsa "düşüldü" bildirilir.
- CUDA işçisiyle çeviri hata verirse (iptal dışında): işçi kapatılır, "düşüldü" bildirilir, CPU işçisi açılıp aynı cümle
  yeniden çevrilir.
- İş parçacığı: CPU işçisi ayardaki sayı (1 ile mantıksal işlemci sayısı arasına sıkıştırılır); CUDA işçisi 2.

### 8.6 CTranslate2 işçisi (süreç protokolü)
**Çalışma zamanı:** uygulama klasöründe `ct2\` (ortam değişkeni `NINO_CT2_RUNTIME` başka klasör verebilir). İçinde gömülü
CPython 3.12 (`python.exe`), `worker.py` ve `Lib\site-packages`. `python.exe` ya da `worker.py` yoksa "çalışma zamanı
eksik" (dosya bulunamadı) hatası → motor açılamadı.

**Paketleme** (yayın betiği): `https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip`
(SHA-256 `4acbed6dd1c744b0376e3b1cf57ce906f9dc9e95e68824584c8099a63025a3c3`) `ct2\` içine açılır; `python312._pth`
dosyası şu dört satırla yazılır: `python312.zip`, `.`, `Lib\site-packages`, `import site`. Paketler PyPI'den yalnız
ikili tekerlek, sabit sürüm ve SHA-256 ile (`--require-hashes`, Python 3.12, `win_amd64`, cp) `Lib\site-packages`'a
kurulur:
- `ctranslate2==4.9.0` — `sha256:ee930e984679ad16c5fb7bc8da2eaca8c269f86d02cb9eeec087baa1837b5bd2`
- `numpy==2.5.4` — `sha256:a7b1b6353e36a7e50de2973a38d705c88ee93adcf120673cee7f45a4a3fa223a`
- `pyyaml==6.0.3` — `sha256:5fcd34e47f6e0b794d17de1b4ff496c00986e1c83f7ab2fb8fcfe9616ff7477b`

Visual C++ çalışma zamanı DLL'leri (`vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll`, `msvcp140_1.dll`…)
hem uygulama klasörüne hem `ct2\`'ye konur (yönetici izni gerekmesin). Yayın denetimi: `ct2/python.exe`,
`ct2/python312.dll`, `ct2/worker.py`, `onnxruntime.dll`, `onnxruntime_providers_shared.dll`, ONNX Runtime .NET DLL'i ve
VC++ DLL'leri yerinde; `ct2/Lib/site-packages/ctranslate2` içinde `.pyd` var.

**Süreç başlatma:** `python.exe -u <ct2>\worker.py <model klasörü> <aygıt> <iş parçacığı>`; aygıt `cpu` ya da `cuda`.
Pencere açılmaz; stdin/stdout/stderr yönlendirilir; stdin UTF-8 (BOM'suz), stdout/stderr UTF-8; çalışma klasörü `ct2\`;
ortam `PYTHONIOENCODING=utf-8`. CUDA'da ayrıca `NINO_CUDA_DIR=<cuda klasörü>` ve `PATH` başına cuda klasörü. stderr satırları
yalnız hata ayıklama çıktısına gider.

**İşçinin yaptığı:**
1. `NINO_CUDA_DIR` varsa o klasörü hem Python'un DLL arama yoluna hem Win32 DLL arama klasörüne ekler (cuBLAS dinamik
   yüklenir).
2. CTranslate2 çevirmeni açar: model klasörü, aygıt, hesaplama türü CUDA'da `float16`, CPU'da `int8`, iç işler arası 1
   iş parçacığı, iş içi iş parçacığı = 3. bağımsız değişken.
3. Isınma: `["▁Hello", ".", "</s>"]` belirteçlerini ışın 1 ile çevirir (CUDA bağımlılığı ilk çıkarımda patlayabilir).
4. İlk stdout satırı: başarıda `{"ready": true}`; hatada `{"ready": false, "error": "<ileti>"}` ve çıkış kodu 1.
5. Sonra stdin'den her satır bir istek, her istek için stdout'a tek satır yanıt (her yanıttan sonra boşaltma; JSON ASCII
   kaçışsız):
   - İstek: `{"tokens":["▁We","▁go",".","</s>"],"beams":4,"max_output":24}`
   - Yanıt: `{"tokens":["▁Gidiyoruz","."]}` (ilk hipotez; `translate_batch` tek cümleyle, `beam_size` = `beams`,
     `max_decoding_length` = `max_output`).
   - Satır hatası: `{"error":"<ileti>"}` (süreç ayakta kalır).

**Uygulama tarafı:** ilk satır okunur; yoksa ("açılışta kapandı") ya da `ready` true değilse `error` iletisiyle hata, süreç
(ağacıyla) öldürülür. Çeviri: cümle §8.7 ile belirteç **dizgilerine** çevrilir; 256'dan fazlaysa ilk 255 + `</s>`.
`max_output` = min(128, 2 × belirteç sayısı + 16). İstek tek satır olarak yazılır, boşaltılır, tek satır yanıt okunur.
Yanıt yoksa "çeviri sırasında kapandı" giriş/çıkış hatası (kalıcı motor hatası, §7). `error` varsa yalnız o satırın hatası.
Değilse `tokens` dizgileri §8.7 ile metne çevrilir. Kapatma: süreç ağacıyla öldürülür, en çok 2 sn beklenir. Işın sayısı 4.

### 8.7 Belirteçleme (Marian / OPUS-MT)
SentencePiece yalnız metni parçalara ayırır; **kimlikler modelin `vocab.json`'undan** gelir (Hugging Face Marian
belirteçleyicisiyle aynı). Kitaplık: Microsoft.ML.Tokenizers 2.0.1 (SentencePiece), ONNX Runtime 1.31.1 (.NET paketi).
- `source.spm` başlangıç/bitiş belirteci eklemeden açılır; normalleştirme modelin kendi kuralıyla (`nmt_nfkc`) ve ön
  bölmeyle yapılır.
- `vocab.json`: parça → kimlik nesnesi (boşsa hata). Özel kimlikler sözlükten: `</s>`, `<unk>`, `<pad>`; sözlükte yoksa
  tc-big en-tr'nin değerleri: bitiş **43741**, bilinmeyen **52508**, dolgu **57059**. Sözlük boyu = en büyük kimlik + 1
  (en-tr: **57060**). Ters tablo kimlik → parça.
- **Kodlama:** hedef belirteci varsa önce onun kimliği. Sonra her parça: SentencePiece "bilinmeyen" dediyse, art arda gelen
  bilinmeyen parçaların metinleri birleştirilir (özgün SentencePiece böyle yapar; `Óð` tek parça); birleşik ya da normal
  parça metni `vocab.json`'da aranır, yoksa bilinmeyen kimliği. Sonda bitiş kimliği.
- **Dizgi kodlama** (CTranslate2 için): kodlanan kimliklerin ters tablodaki parçaları.
- **Çözme:** bitiş, bilinmeyen, dolgu ve aralık dışı kimlikler atlanır; parçalar birleşir; `▁` (U+2581) boşluk olur;
  kırpılır. Dizgi çözmede dizgi önce `vocab.json`'dan kimliğe çevrilir (yoksa bilinmeyen).

Başvuru kimlikleri (en-tr `source.spm` + `vocab.json`): belirteçleyicinin çıktısı Hugging Face'in aynı modelle verdiği
kimliklerle **birebir** aynı olmalı. Testin başvuru dizileri kurulu modelle (`NINO_TEST_MODELS`) Hugging Face
belirteçleyicisinden kendi cümlelerimiz için üretilir; model yoksa test atlanır. Kapsanması gerekenler: düz cümle (bitiş
kimliği 43741 ile biter), boş metin (yalnız 43741), tek sözcük + noktalama, `…` (normalleştirme üç noktayı açar),
baştaki/sondaki ve ardışık boşluklar + sekme (tek boşluk gibi), satır sonu (boşluk gibi), tam genişlik harfler ve `½`
(NFKC), aksanlı Latin, kıvrık tırnak ve tire, sayı + `%` + birim, sözlükte olmayan yazı (bilinmeyen kimlik 1 ya da tek
tek parçalar), emoji (bilinmeyen) ve tümü büyük harfli cümle.

Gidiş-dönüş: düz bir cümle aynen; fazla boşluklu cümle tek boşluklu hâline; `…` → `...`. [dolgu, 54162, 21, bilinmeyen,
bitiş] → `Wait!`. `<bağlam> *** <cümle>` biçimli metinler ve uydurma ad listesindeki adların (§6.1) hepsi bilinmeyen
kimlik içermez ve aynen geri çözülür (`***` ve adlar sözlükte); `|` içeren metin bilinmeyen içerir.
en-ar (`>>ara<<` ile): bitiş 0, bilinmeyen 1, dolgu 62801; herhangi bir cümlede ilk kimlik 4 (`>>ara<<`), son 0.

### 8.8 ONNX kod çözme (Türkçe dışındaki ücretsiz diller)
- Oturum ayarları: tam grafik iyileştirme, sıralı yürütme, iş içi iş parçacığı = mantıksal işlemci / 2 (en az 1, en çok
  **2**), işler arası 1. (Bellek havuzunu kapatmak denendi, kötüleşti; varsayılanlar.) Kodlayıcı açılır, sonra kod
  çözücü (açılamazsa kodlayıcı kapatılır).
- Kod çözücü (birleşik) girdileri: `input_ids`, `encoder_attention_mask`, `encoder_hidden_states`, `use_cache_branch`,
  ardından modelin girdileri arasında adı `past_key_values.` ile başlayanlar (modeldeki sırayla). Çıktıları: `logits`,
  her `past_key_values.<x>` için `present.<x>`. Öz dikkat önbellekleri = adı `.decoder.key` ya da `.decoder.value` ile
  bitenler; öbürleri çapraz dikkat (kodlayıcı). Baş sayısı ve baş boyu ilk önbellek girdisinin [ışın, baş, uzunluk, boy]
  biçiminden (pozitifse; yoksa 16 ve 64).
- **Çeviri:** cümle kodlanır (§8.7); 256'dan uzunsa ilk 256 alınıp sonuncusu bitiş yapılır. Kodlayıcı `input_ids` ve
  `attention_mask` (64 bit tam sayı, [1, n], hepsi 1) ile çalışır, `last_hidden_state` alınır. Gizli durum ışın sayısı
  (B = 4) kadar çoğaltılır ([B, n, boy]); maske [B, n] hepsi 1. Önbellekler boş ([B, baş, 0, baş boyu]).
- Işın puanları: ilk ışın 0, öbürleri −∞ (başta hepsi aynı olduğu için yalnız ilki aday üretir). Başlangıç belirteci
  **dolgu** kimliği. Adım sınırı = min(128, 2n + 16).
- Her adım: `use_cache_branch` = adım > 0; girdi belirteçleri [B, 1]. Çıkan `logits`'ten adaylar: puanı −∞ olmayan her
  ışın için, dolgu hariç log-softmax (en büyük değer çıkarılarak, `log Σ exp`), aday puanı = ışın puanı + log-olasılık;
  bütün ışınlardan en iyi **2B** aday (puana göre azalan; eşit puanda önce eklenen önde). Dolgu hiç üretilmez.
- Adaylar sırayla, yeni ışın sayısı B'ye ulaşana kadar: puan −∞ ise dur. Belirteç **bitiş** ise ve adayın sırası < B ise
  "biten" olarak eklenir (puan / (ışının belirteç sayısı + 1), bitenler puana göre azalan, en çok B tane); bitiş yeni ışın
  olmaz. Değilse yeni ışın: kaynağı, belirteçleri (kaynağınkiler + yeni), puanı, sonraki girdi belirteci. Dolmayan ışınlar
  ilk yeni ışının kopyası, puanı −∞.
- Öz dikkat önbellekleri yeni ışınların kaynak sırasına göre yeniden dizilir (kaynaklar 0,1,2,… ise kopyalanmaz); çapraz
  dikkat önbellekleri yalnız ilk adımda alınır, sonra atılır.
- Hiç yeni ışın yoksa dur. Biten sayısı ≥ B ve (en iyi süren ışının puanı / (adım + 1)) ≤ en kötü bitenin puanı ise dur.
- Sonuç: biten varsa en iyi bitenin belirteçleri, yoksa ilk süren ışın. §8.7 ile çözülür.

### Mac'ten farkı (§7–§8)
Mac'te cihaz içi çeviri Apple Translation (dil paketi sistemden). Bütün bu bölüm Windows'a özgüdür.

---

## 9. Dakikalık istek hakkı (bütçe)

Kayan **60 sn**'lik pencere. Hak alınırken: pencereden çıkmış (şimdi − zaman ≥ 60 sn) istekler atılır; penceredeki istek
sayısı ≥ sınırsa hak **yok** (istek gönderilmez); değilse şimdiki zaman eklenir, hak var. Sınır en az 1.
"Sınırı düşür": yeni sınır = max(1, min(eski, bildirilen)); hiçbir zaman yükseltmez.

**Ortak hak:** modelin listede `requestsPerMinute` değeri varsa, uygulama genelinde motor adı (§10.2: `gemini:<model>`)
başına **tek** bir hak nesnesi vardır (çeviri hattı yeniden kurulsa da sıfırlanmaz; Google sınırı proje + model başına
sayar). Değer yoksa hak yok (sınırsız). Yerel modelde ve ücretli hizmetlerde (OpenAI, Claude) bugün yok.

Test: sınır 3, 12:00:00'da 1 hak; 20 sn sonra 2 hak daha; 4. yok; 39 sn sonra yok; 1 sn daha (ilk istek 60 sn önce) var;
hemen sonra yok. Düşür 1 → 1; düşür 50 → 1 kalır; düşür 0 → 1.

Gerçek kayıttan zaman çizelgesi (sınır 15/dk, ms; B = bulut, Y = yerel): 21734 B, 30010 B, 35159 B, 36602 B, 37585 B,
38121 B, 40015 B, 43233 B, 45500 B, 49720 B, 51248 B, 54432 B, 56567 B, 60607 B, 63772 B, 68160 Y, 76612 Y, 77354 Y,
80223 Y, 81879 B, 82560 Y, 87568 Y, 88425 Y, 88661 Y, 93364 B, 98714 B → toplam 18 bulut isteği, 8 yerel çeviri; her
yerel satırda "son satır dakikalık sınırdaydı" evet, bulutta hayır; hiç hata bildirilmez.

---

## 10. Kalıcı çeviri önbelleği

Her motor ve dil çifti **ayrı dosya**: motor değiştiyse önceki motorun sonucu gösterilmez. Klasör
`%LOCALAPPDATA%\Nino\translations\` (havuz çevirileri ayrı: `pool-translations\`).

### 10.1 Dosya adı
Girdi: motor adı, kaynak (`en`), hedef (hedef dil kodu).
- Üçü de **yalnız** `a-z`, `0-9`, `-` içeriyor ve boş değilse ("eski güvenli ad"): `v1-<motor'>-<kaynak'>-<hedef'>.jsonl`;
  burada her parçada harf, rakam ve `_` dışındaki karakterler (yani **`-` de**) `_` olur. Ayraçlar `-`.
  - `opus-mt` → `v1-opus_mt-en-tr.jsonl`
  - ücretsiz çevirmen `opus-mt-ct2-p3` → `v1-opus_mt_ct2_p3-en-tr.jsonl` (Arapça: `v1-opus_mt_ct2_p3-en-ar.jsonl`)
  - DeepL `deepl` → `v1-deepl-en-tr.jsonl`
- Değilse: `v1h-<SHA-256(motor + U+0000 + kaynak + U+0000 + hedef), UTF-8, küçük hex>.jsonl`.
  - `local:model.a` → `v1h-6b5f11ab62999719865a030d1fb7f93bbcf1184290b58d4d603d1bee6c03249c.jsonl`
  - `gemini:gemini-3.5-flash-lite` → `v1h-1aa82a53a8896bbdf8841c6a44e31bc0ec2a382935938bda14071a3444e0ca98.jsonl`
  - `openai:gpt-6-luna` → `v1h-c55ee774e0046635db77c49627a703b46524fac9e8ac34cc676b9932601841cc.jsonl`
  - `claude:claude-haiku-5-5` → `v1h-ac2a88fa400ef49a64c68710bbc687325388e306a6e625d64ace07741110a525.jsonl`
  - `local:localhost:11434/translategemma:4b` →
    `v1h-a809c3f4a9cb728f049af7017f3a2e62dc067d2bbc44d8744ae68cfdca0abefb.jsonl`
- Farklı motor adları asla aynı dosyayı paylaşmaz: `local:qwen2.5:7b` ≠ `local:qwen2-5:7b`; `local:model.a` ≠
  `local:model_a`; `opus-mt` ≠ `opus_mt`.

### 10.2 Motor adları
- Ücretsiz çevirmen: `opus-mt-ct2-p` + metin hattı sürümü (bugün **3**) → `opus-mt-ct2-p3`. Metin hattının kuralları
  (bölücü, sözlük, terim koruma, ek kurma, Türkçe düzeltme, oyun deyimleri) değişince sürüm bir artırılır; önceki kurallarla çevrilen satırlar baştan çevrilir. (ONNX dilleri de aynı adı kullanır; dosya hedef dile göre ayrılır.)
- DeepL: `deepl`.
- Bulut yapay zekâ: `<hizmet>:<model>`, hizmet `gemini`, `openai`, `claude` (ör. `gemini:gemini-3.5-flash-lite`).
- Yerel model: `local:<makine küçük harf>[:<kapı>]/<model>`; kapı yalnız şemanın varsayılanı değilse
  (`local:localhost:11434/qwen2.5:7b`; `http://LOCALHOST:11434/v1/` aynı ad verir).

### 10.3 Satır biçimi ve sınırlar
- Her satır bir JSON dizisi `["anahtar","çeviri"]` + `\n`, dosyanın sonuna eklenir, BOM'suz UTF-8. **Windows ASCII dışı
  karakterleri `\uXXXX` kaçışıyla yazar** (`"Koş!"`); okurken kaçışlı ve kaçışsız (Mac'in yazdığı) ikisi de okunur.
- Boş anahtar ya da boş çeviri yazılmaz. Okurken JSON olmayan, 2 öğeli dizi olmayan ya da boş öğeli satır atlanır (ama
  "dosyadaki satır" sayısına girer).
- Bellekte en çok **20 000** kayıt (her kayıt "son kullanım" sayacıyla). Aşılınca en uzun süredir kullanılmayanlardan
  (fazla + sınırın onda biri) kadarı atılır.
- Dosya ilk kullanımda okunur (sonra satırlar sırayla belleğe; aynı anahtarda sonraki kazanır). Okuduktan sonra dosyadaki
  satır sayısı kayıt sayısını sınırın yarısından fazla aşıyorsa dosya yeniden yazılır.
- Yeni kayıtta dosyadaki satır sayısı sınırın iki katına ulaştıysa ekleme yerine bellekteki kayıtlarla, en eski
  kullanılandan yeniye **yeniden yazılır** (`.tmp` + taşıma); değilse sona eklenir.
- Aynı anahtara aynı çeviri yeniden yazılırsa dosyaya eklenmez (yalnız "kullanıldı" tazelenir).
- Okuma da "kullanıldı" sayacını tazeler.
- Disk hatası çeviriyi durdurmaz (önbellek bellekte çalışır; yeniden yazma başarısızsa eski dosya kalır).
- Dosyasız (yalnız bellek) önbellek de vardır (testler, deneme çevirmenleri).
- Aynı dosya için uygulamada **tek** önbellek nesnesi (yol büyük/küçük harf duyarsız karşılaştırılır).

Testler: iki kayıt yeniden açılışta okunur; motorlar ayrı dosya; tırnak ve satır sonu içeren anahtar/çeviri gidip gelir
(`RUIZ: "Tomas."⏎VERA: Yes?` → `RUIZ: "Tomas."⏎VERA: Evet?`); sınır 10'da `s0`…`s9` sonra `s0` okunup `s10`
yazılınca `s0` ve `s10` var, `s1` yok, kayıt ≤ 10; sınır 5'te 6 tur × 5 kayıt yazılınca dosya ≤ 10 satır ve yeniden
açılışta `s3` → `t3-5`; `["Row!","Kürek çek!"]⏎not json⏎["lonely"]` → 1 kayıt; Mac biçimi `["Who sent you?","Seni kim gönderdi?"]`
okunur; boş çeviri yazılmaz, dosya oluşmaz; ortak nesne aynı dosyada aynı, başka motorda farklı.

### 10.4 Önbellek ölçümü (altyazı günlüğü için)
Bir çeviri isteği boyunca (eşzamansız akışa bağlı bir ölçüm nesnesiyle): önbellekten gelen parça sayısı ve önbelleğe yeni
yazan motor adları sayılır. Sonuç: yeni yazan varsa `çeviri:<son yazan motor>` (adı boşsa `çeviri:<yedek ad>`); yoksa ve
önbellekten parça geldiyse `önbellek`; hiçbiri yoksa `çeviri:<yedek ad>` (varsayılan yedek ad `motor`). Çevrimiçi motor
yedeğe düşerse yeni parçayı yedek motorun önbelleği saklar; günlükte çeviriyi asıl yapan motor yazar.

### Mac'ten farkı (§9–§10)
- **Dosya adı:** Windows "eski güvenli" adlarda `-`'yi `_` yapar (`v1-opus_mt_ct2_p3-en-tr.jsonl`); Mac belgesi
  `v1-apple-p3-en-tr.jsonl` diyor (Mac `-`'yi koruyor). Yeni Windows kodu **Windows'un** adlarını üretmeli, yoksa eski
  kullanıcıların önbelleği kaybolur. `v1h-` adları iki platformda aynı.
- Windows ASCII dışını kaçışla yazar; Mac kaçışsız. İkisi de okunmalı.

---

## 11. DeepL motoru

### 11.1 Adres ve istek
- Taban: anahtar (kırpılmış) `:fx` ile bitiyorsa `https://api-free.deepl.com/v2/`, değilse `https://api.deepl.com/v2/`.
- `POST <taban>translate`, başlık `Authorization: DeepL-Auth-Key <anahtar>`, gövde JSON (alan sırası sabit; `null` olanlar
  yazılmaz):
```json
{"text":["We sail on."],"source_lang":"EN","target_lang":"TR","context":"RUIZ: We sail on.",
 "formality":"prefer_less","preserve_formatting":true,"tag_handling":"xml","ignore_tags":["x"]}
```
  - `target_lang`: hedef dil kodu büyük harf (`TR`, `AR`, `ID`, `TH`, `VI`, `NL`).
  - `context`: son gösterilen **3** satır, eskiden yeniye, `\n` ile; hiç yoksa alan yok. (DeepL bağlamı çevirmez ve
    ücretlendirmez.)
  - `formality`: yalnız hedef `TR`'de `prefer_less` ("sen"); başka hedefte yok.
  - `tag_handling`, `ignore_tags`: yalnız etiketli istekte (§11.3).
- Yanıt `{"translations":[{"text":"…"}]}`; liste yoksa ya da sayısı gönderilen metin sayısından farklıysa "ulaşılamadı".
- Zaman aşımı **4 sn** (paylaşılan istemci).

### 11.2 Satır akışı
1. Bağlam = şu ana kadar gösterilen son 3 satır (bu satır hariç). Sonra bu satır "gösterildi" kaydına eklenir: son kayıtla
   aynıysa eklenmez; 3'ü aşarsa en eski atılır. Önbellekten dönen satır da gösterilmiş sayılır.
2. Sözlük = hedef `TR` ise kullanıcının sözlüğü (§5.2), değilse boş.
3. Satırın önbellek anahtarı (§11.4) varsa döner.
4. Hata beklemesindeyse (son hatadan beri 60 sn geçmedi) yedekle çevrilir.
5. Satır parçalanır (§3); etiketlerden adlar öğrenilir; bilinen adlar = öğrenilenler + sözlüğün büyük kalacak sözcükleri.
6. Önbellekteki parçalar gönderilmez. Eksik parçalar büyük harf düzeniyle (§3.3) hazırlanır.
7. Etiketleme (§11.3); hiç eksik yoksa istek yok.
8. İstek. Başarıda hata durumu temizlenir (bildirim yalnız değişince). Hata (ağ, zaman aşımı, DeepL hatası; iptal değil):
   hata durumu bildirilir (anahtar geçersiz / kota bitti / ulaşılamadı), **60 sn** DeepL denenmez, satır yedekle çevrilir
   (yedeğin sonucu DeepL önbelleğine **yazılmaz**).
9. Her yeni parça çevirisi önbelleğe (parçanın anahtarıyla); parçalar birleşir; satır da önbelleğe; döner.
- Yedek yoksa yedek gereken her yerde "indirme gerekli" hatası.
- Hata eşlemesi: 401/403 → anahtar geçersiz; 456 → kota bitti; diğer başarısız kodlar → ulaşılamadı; ağ/zaman aşımı →
  ulaşılamadı.

### 11.3 Terim etiketi (yalnız hedef `TR`)
Sözlük terimleri DeepL'e "çevirme" etiketiyle gider (etiketsiz gönderilince DeepL `Soul began…`'da adı sıradan sözcük
sanıp sonraki sözcüğü de bozuyordu). Bir parçada terim varsa: terimler arası metin XML için kaçışlanır (`&`→`&amp;`,
`<`→`&lt;`, `>`→`&gt;`), terimin yerine `<x>` + kaçışlanmış Türkçesi (keep adlarında kendisi) + `</x>`. İstekteki herhangi
bir parça etiketliyse istek etiketli gider: etiketsiz parçalar da kaçışlanır; `tag_handling: xml`, `ignore_tags: ["x"]`.
Dönüşte `<x>`, `</x>` silinir, `&lt;`, `&gt;`, `&amp;` açılır.
Örnek: `Raven began to sing. Feed your raven & run.` (genel sözlük, `keepExact: Raven`) → giden metinler
`<x>Raven</x> began to sing.` ve `Feed your raven &amp; run.`; sonuçta `<x>` yok, `& run.` var. Terim yoksa istek düz:
`Keep low & quiet.` aynen, `tag_handling` yok. Hedef `ar`'da sözlük yok: `Raven began to sing.` düz gider, `formality`
ve `tag_handling` yok, `target_lang` `AR`.

### 11.4 Önbellek anahtarı
Metinde sözlük terimi varsa `<sözlük izi>` + U+001F + metin, yoksa metin (satır da parça da). Bağlam anahtara girmez
(önbellekteki çeviri bağlamsız eski hâliyle döner).

### 11.5 Kullanım denetimi (ayarlardaki "Dene" ve anahtar kaydı)
Anahtar kırpılır; boşsa "geçersiz". `GET <taban>usage`, aynı başlık. Başarısızsa §11.2 eşlemesi. Yanıt
`{"character_count":1200,"character_limit":500000}`; boşsa "ulaşılamadı". Sınır > 0 ve sayaç ≥ sınır → "kota bitti",
değilse "geçerli"; ikisinde de kullanılan ve sınır döner. Ağ/zaman aşımı → ulaşılamadı.

### 11.6 Testler
- `RUIZ: We sail on.` (anahtar sonu `:fx`) → `RUIZ: [tr] We sail on.`; adres `https://api-free.deepl.com/v2/translate`;
  başlık `DeepL-Auth-Key <anahtar>`; `text[0]` `We sail on.`; `target_lang` `TR`; ilk istekte `context` yok; sonraki
  `Keep low.` isteğinde `context` = `RUIZ: We sail on.`.
- `Who sent you?` iki kez (`:fx`'siz anahtar) → tek istek, adres `https://api.deepl.com/…`.
- Satırlar `First.`, `Second.`, `Second.`, `Third.`, `Fourth.`, `Fifth.` → 5 istek; bağlamlar: yok, `First.`,
  `First.⏎Second.`, …, 5.'de `Second.⏎Third.⏎Fourth.`.
- `Where is she?`, `On deck.`, `Where is she?` (önbellekten), `Bring her here.` → 3 istek; 3.'nün bağlamı
  `Where is she?⏎On deck.⏎Where is she?`.
- Kalıcı önbellek: 1. oturum `RUIZ: We leave now. Keep low.`; 2. oturumda aynı satır istek atmaz; `Keep low. Run!` →
  yalnız `Run!` gider.
- 502 → yedek `yerel: Run!`, önbellekte yok; DeepL düzelince yeni nesne `[tr] Run!`.
- 456 → `yerel: Run!`, hata "kota bitti"; `Duck!` → istek gitmeden `yerel: Duck!`.
- Kullanım: `{"character_count":1200,"character_limit":500000}` → geçerli (1200, 500000), yol `/v2/usage`; 403 →
  geçersiz; 500000/500000 → kota; boş anahtar → geçersiz.

### Mac'ten farkı (§11)
Aynı. (Windows'ta "zaten hedef dilde" denetimi okuma hattında.)

---

## 12. Yapay zekâ motorları (Gemini, OpenAI, Claude, yerel model)

### 12.1 Satır akışı
1. Oyun adı **bir kez** alınır ve kırpılır (arama, istek ve kayıt aynı oyunla yapılır; istek sırasında değişse de).
2. Bağlam = son gösterilen **3** satır ve (biliniyorsa) gösterilen çevirileri; bu satır hariç. Bu satır "gösterildi"ye
   eklenir (son kayıtla aynı kaynaksa eklenmez; 3'ü aşarsa en eski atılır).
3. **Önbellek anahtarı:** oyun boş değilse `oyun` + U+001F + metin, boşsa metin (oyun bilinmiyorsa eski oyunsuz kayıtlar
   geçerli; biliniyorsa yalnız o oyunun kayıtları). Satırın tamamı önbellekteyse döner.
4. Satır parçalanır; etiket adları öğrenilir (büyük kalacak sözcükler yalnız öğrenilenler; sözlük yok). Önbellekteki
   parçalar (aynı anahtar kuralıyla) gönderilmez; eksikler büyük harf düzeniyle hazırlanır.
5. Eksik varsa ve hata beklemesindeyse → yedek. (Bütün parçalar önbellekteyse yedek gerekmez, istek de yok.)
6. Eksik varsa ve dakikalık hak (§9) alınamazsa → "son satır dakikalık sınırdaydı" işaretlenir, yedek (hata
   bildirilmez).
7. İstek (§12.3) — eksik cümleler **tek istekte** JSON dizisi olarak. Başarıda (eksik varsa) hata durumu temizlenir.
8. **Dakikalık sınır yanıtı** (§12.5): bildirilen istek sınırı varsa ortak hak ona düşürülür; bekleme = önerilen
   bekleme < 20 sn ise o, değilse 20 sn; en az 1 sn; "sınırdaydı" işaretlenir; bekleme süresince istek yok; yedek. Hata
   bildirilmez.
9. **Başka hata** (ağ, zaman aşımı, hizmet hatası; iptal değil): hata türü bildirilir, **60 sn** denenmez, yedek.
   İptal: hiçbir şey bildirilmez, önbelleğe yazılmaz, bekleme konmaz; iptal edilen satır bağlamda kalır ama çevirisi yok.
10. **Yankı denetimi:** her yeni cümle için kaynak ile çeviri sadeleştirilmiş hâlleri (küçük harf, harf/rakam dışı boşluk,
    tek boşluk) Levenshtein oranıyla ≥ **0.90** benzerse cümle yedekle bir kez denenir (yedek yoksa ya da hata verirse
    denenmemiş sayılır). Yedeğin sonucu yankı değilse o kullanılır ve **önbelleğe yazılmaz**, satırın tamamı da yazılmaz.
    Değilse (ad, konsolun Türkçe menüsü) modelin cevabı kalır ve yazılır.
11. Parçalar birleşir; yankı yedeği kullanılmadıysa satır önbelleğe yazılır.
12. Dönen (gösterilen) çeviri bağlam kaydında bu satırın çevirisi olur (yedeğinki de).
- Yedek yoksa yedek gereken her yerde "indirme gerekli" hatası.

### 12.2 Model listesi (`ai-models.json`, veri)
Biçim: hizmet adı → model dizisi; ilk model varsayılan; dizi olmayan alanlar (`_about`) atlanır; boş dizi atlanır.
Model alanları: `id`, `text` (ayarlarda görünen adın metin kataloğu anahtarı; eski dosyadaki `label`'ın yerini alır), isteğe bağlı `effort`, `thinking`, `freeTier`
(yalnız JSON `true` ise evet), `requestsPerMinute` (tam sayıysa). Kayıtlı model listede yoksa varsayılan model; kullanıcı
bulut modeli adı yazamaz. Bugünkü içerik:
```json
{
  "gemini": [
    { "id": "gemini-3.5-flash-lite", "text": "ai.model.fast", "freeTier": true, "requestsPerMinute": 15 },
    { "id": "gemini-3.6-flash", "text": "ai.model.better", "thinking": "LOW", "freeTier": true, "requestsPerMinute": 10 }
  ],
  "openai": [
    { "id": "gpt-6-luna", "text": "ai.model.fast", "effort": "none" },
    { "id": "gpt-6.1-terra", "text": "ai.model.better", "effort": "none" }
  ],
  "claude": [
    { "id": "claude-haiku-5-5", "text": "ai.model.fast", "effort": "low", "thinking": "disabled" },
    { "id": "claude-sonnet-5-5", "text": "ai.model.better", "effort": "low", "thinking": "between_tools" }
  ]
}
```
(Dosyada ayrıca açıklama amaçlı bir `_about` metni vardır; okunmaz.) Bulut hizmetleri = listedeki üç ad. Yerel modelin
listesi yok; model adı kullanıcının yazdığı (kırpılmış; boşsa `translategemma:4b`). "Ücretsiz katmanı var" = modellerinden
biri `freeTier` (bugün yalnız Gemini; metin anahtarı `aiModel.freeTier`). `ai.model.fast` (hızlı ve ucuz, önerilen)
ve `ai.model.better` (daha iyi, biraz yavaş) 12 dilin kataloğunda olmalı.

### 12.3 İstek gövdeleri
Bütün istekler `POST`, `Content-Type: application/json; charset=utf-8`; gövde ASCII dışı karakterleri kaçışsız yazar.
Anahtar kırpılır.

| Hizmet | Adres | Anahtar başlığı | Gövde (alan sırası) |
|---|---|---|---|
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/<model, URL kaçışlı>:generateContent` | `x-goog-api-key: <anahtar>` (Authorization yok) | `systemInstruction.parts[0].text` = yönerge; `contents[0]` = `{role:"user", parts:[{text: ileti}]}`; `generationConfig.maxOutputTokens`; modelde `thinking` varsa `generationConfig.thinkingConfig.thinkingLevel` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer <anahtar>` | `model`; `messages` = [`{role:"developer", content: yönerge}`, `{role:"user", content: ileti}`]; `max_completion_tokens`; `effort` varsa `reasoning_effort` |
| Claude | `https://api.anthropic.com/v1/messages` | `x-api-key: <anahtar>` ve `anthropic-version: 2023-06-01` | `model`; `max_tokens`; `system` = yönerge; `messages` = [`{role:"user", content: ileti}`]; `effort` varsa `output_config.effort`; `thinking` varsa `thinking.type`. Temperature yok |
| Yerel | `<temel adres>/chat/completions` | anahtar boş değilse `Authorization: Bearer <anahtar>`, boşsa başlık yok | `model`; `messages` (çeviri modeli kalıbı ya da [`{role:"system"}`, `{role:"user"}`]); `temperature: 0.2`; `max_tokens`; `stream: false` (tam bu 5 alan) |

- Çıktı sınırı: altyazıda **1024**, "ekranı çevir"de **8192**.
- Yerel sunucu verilmediyse Ollama'nın varsayılan adresi ve modelin adı.

**Kullanıcı iletisi** (biçim; testler bunu sabitler). Parçalar arasında **boş satır** (`\n\n`):
1. Oyun adı boş değilse: `Game: <oyun adı>`
2. Bağlam varsa: bir başlık satırı (İngilizce, metni yeni yazılır; anlamı: "önceki altyazılar, yalnız bağlam için;
   bunları yeniden çevirme"), sonra her bağlam satırı için `English: <kaynak>` ve çevirisi biliniyorsa
   `<Dil adı>: <çeviri>` (satırlar `\n` ile).
3. Her zaman: tek bir İngilizce yönerge cümlesi (anlamı: "bu JSON dizisindeki her dizgiyi **`into <Dil adı>`**
   çevir; yalnız aynı sırada N tane <Dil adı> dizgisinden oluşan bir JSON dizisiyle yanıt ver"; N sayıyla yazılır) + `\n`
   + cümlelerin sıkışık JSON dizisi (ASCII dışı kaçışsız, ör. `["We leave now.","Keep low."]`). Dizi iletinin **son
   satırıdır**.
<Dil adı> = hedefin İngilizce adı (§13.1), N = cümle sayısı. Testlerin dayandığı sabitler: `Game: ` öneki, parçalar arası
boş satır, bağlam başlık satırının varlığı (metni kodda tek sabit), `English: ` / `<Dil adı>: ` önekleri, `into <Dil adı>`
ifadesi, son satırın JSON dizisi olması.

**Yönerge (sistem iletisi) — anlamı.** Hedefe göre üç çeşit:
- **Türkçe:** İngilizce oyun altyazısını doğal, insanların gerçekten konuştuğu gibi konuşma Türkçesine çevir; karakterler
  birbirine açıkça resmî olmadıkça "sen" der ("siz" değil); karakter adları, yer adları ve `VERA:` gibi konuşmacı
  etiketleri olduğu gibi kalır; satır sonları korunur; anlam ve ton korunur, ekleme ya da eksiltme yok; yalnız çeviri
  döner, açıklama, not ya da tırnak yok.
- **Arapça:** açık, doğal Modern Standart Arapçaya, iyi Arapça oyun altyazıları gibi; ekranda kısa ve kolay okunur;
  diyalogda doğal konuşma tonu; adlar, yer adları ve konuşmacı etiketleri olduğu gibi, **Latin harfleriyle**; satır sonları;
  anlam ve ton; Arapça noktalama (`، ؟ ؛`) ve Batı rakamları; kol tuşu simgeleri (`✕ ○ △ □`, `L1`, `R2`) değişmez; yalnız
  çeviri.
- **Öbür diller:** Arapçanınkiyle aynı maddeler, dil adı hedefin İngilizce adı; Arapça noktalama
  maddesi yok; adlar Latin harfleriyle; kol tuşu simgeleri değişmez.
(Testler: Tayca yönergesi `Thai` adını içerir; Vietnamca yönergesinde `Arabic` geçmez; Arapça istekte `Modern Standard
Arabic` ve `into Arabic` geçer, `Turkish` geçmez, bağlam satırı `Arabic: <bilinen çeviri>` biçiminde.)

**Çeviri modelleri** (yerel model adı `translategemma` ya da `milmmt` içeriyorsa, büyük/küçük harf duyarsız): yönerge ve
JSON dizisi **gönderilmez**. `messages`: bağlamdaki çevirisi bilinen her satır için `{role:"user", content: kalıp(kaynak)}`
ve `{role:"assistant", content: çeviri}`; sonra `{role:"user", content: kalıp(metin)}`; metin = cümleler (her cümlenin
içindeki `\n` boşluk olur) `\n` ile birleşik. Kalıplar üçüncü taraf model biçimidir (modellerin kendi belgelerindeki
kullanıcı iletisi kalıbı; metni oradan alınır, burada tekrarlanmaz):
- TranslateGemma: Google'ın model kartında belgelediği tek paragraflık İngilizce yönerge; kaynak `English (en)`, hedef
  `<Dil> (<kod>)` yazılır (<Dil> İngilizce ad, <kod> hedefin iki harfli kodu), son cümlesi `into <Dil>:` ile biter; ardından
  `\n\n\n` + metin.
- MiLMMT: üç satır: kaynağı İngilizce, hedefi <Dil> olarak söyleyen kısa yönerge satırı (`:` ile biter), `English: <metin>`,
  `<Dil>:`.
Örnek: model `translategemma:12b`, cümleler `We leave now.`, `Keep low.`, bağlam [`Vera?`/`Vera?`, `Hm.`/çevirisiz] →
roller user, assistant, user; ilk içerik kalıp(`Vera?`); son içerik `…into Turkish:\n\n\nWe leave now.\nKeep low.` ile
biter. MiLMMT `Hi` → son iki satır `English: Hi` ve `Turkish:`; Arapçada son satır `Arabic:`. TranslateGemma Arapça
kalıbında hedef `Arabic (ar)` diye yazılır.

### 12.4 Yanıt okuma
**Metin çıkarma** (JSON değilse "ulaşılamadı"):
- Gemini: `candidates[0].content.parts[]`; `thought` değeri JSON `true` olan parçalar atlanır; kalanların `text`'leri
  birleşir.
- OpenAI ve yerel: `choices[0].message.content`.
- Claude: `content[]` içinde `type == "text"` olanların `text`'i birleşir.
- Beklenmeyen tür (alan beklenenden başka tipte) ya da metin yok/boş/yalnız boşluk → "ulaşılamadı".
  `{"promptFeedback":{"blockReason":"OTHER"}}` → ulaşılamadı.

**Metinden çeviri listesi** (N = istenen sayı):
1. Kırp. Son `</think>` varsa sonrası alınır, kırpılır.
2. Kontrol işaretleri silinir, kırpılır: `<s>`, `</s>`; `<|` + 1–32 harf/rakam/`_` + `|>`; `<start_of_turn>`,
   `</start_of_turn>`, `<end_of_turn>`, `</end_of_turn>`; `<eos>`, `</eos>`, `<bos>`, `</bos>`, `<pad>`, `</pad>`.
   Başka `<…>` yazıya dokunulmaz.
3. ```` ``` ```` ile başlıyorsa: ilk satır atılır, ```` ``` ```` ile başlayan satırlar atılır, kalan birleşir, kırpılır.
4. İlk `[` ile son `]` arası (varsa ve sıralıysa): sondaki `,` + boşluk + `]` → `]` düzeltilip JSON olarak okunur.
   Bütün öğeleri metin olan bir diziyse: öğe sayısı N değilse **ulaşılamadı**; değilse her öğe kırpılıp döner. JSON
   değilse (ya da öğeler metin değilse) devam.
5. **Tırnaksız dizi:** metin `[` ile başlayıp `]` ile bitiyorsa ve uzunluk ≥ 2: iç kısım. N = 1 ise tek seçenek iç kısmın
   tamamı. N > 1 ise sırayla: (a) satır sonlarından bölme (boş satırlar atılır), (b) cümle sonu işaretinden (`. ! ? … " ”`;
   aradaki boşluklar sayılmaz) hemen sonra gelen virgülden bölme, (c) düz virgülden bölme. Her seçenekte öğeler temizlenir
   (kırp, sondaki `,` at, kırp, baş/son `" “ ”` at, kırp); öğe sayısı N ve hiçbiri boş değilse o seçenek döner.
6. N > 1 ise: boş olmayan (kırpılmış) satırlar; sayı N değilse ulaşılamadı.
7. N = 1 ise: metin, baş/son `" “ ”` atılmış.

| Yanıt | N | Sonuç |
|---|---|---|
| ```` ```json⏎["Hadi çıkalım.", "Alçak dur."]⏎``` ```` | 2 | `Hadi çıkalım.`, `Alçak dur.` |
| `“Hadi çıkalım.”` | 1 | `Hadi çıkalım.` |
| `["Tek"]` | 2 | hata |
| `Hadi çıkalım. Alçak dur.` | 2 | hata |
| `<think>…</think>Hadi çıkalım.` | 1 | `Hadi çıkalım.` |
| `[Demiri kaldırmamız lazım.]` | 1 | `Demiri kaldırmamız lazım.` |
| `[Gel, otur, dinle.]` | 1 | `Gel, otur, dinle.` |
| `<think>⏎Önce düşüneyim.⏎</think>⏎[Çekil oradan be!]` | 1 | `Çekil oradan be!` |
| ```` ```json⏎[Olduğun yerde kal.]⏎``` ```` | 1 | `Olduğun yerde kal.` |
| `["Ona "kal" dedim."]` | 1 | `Ona "kal" dedim.` |
| `[iç çekiyor] Hadi çıkalım.` | 1 | `[iç çekiyor] Hadi çıkalım.` |
| `["Kapağı kapat!"]</s>` / `[Kapağı kapat!]</s>` | 1 | `Kapağı kapat!` |
| `Çık dışarı!<|im_end|>` | 1 | `Çık dışarı!` |
| `<s>["Sol.", "Sağ.",]<|eot_id|>` | 2 | `Sol.`, `Sağ.` |
| `["<i> etiketi kalır"]` | 1 | `<i> etiketi kalır` |
| `[İlk cümle., İkinci cümle.]` | 2 | `İlk cümle.`, `İkinci cümle.` |
| `[⏎␠␠Hadi çıkalım.,⏎␠␠Alçak dur.⏎]` | 2 | `Hadi çıkalım.`, `Alçak dur.` |
| `<think>…</think>[Kaç!, Çabuk!]` | 2 | `Kaç!`, `Çabuk!` |
| `[Tek cümle.]` / `[Kuzey., Güney., Batı.]` | 2 | hata |
| `[Tamam, kaptan., Hayır, kalıyorum.]` | 2 | `Tamam, kaptan.`, `Hayır, kalıyorum.` |
| `[Gel, otur, dinle!, Peki.]` | 2 | `Gel, otur, dinle!`, `Peki.` |
| `[Rahat ol, denizci.⏎Ben bakarım, dert etme.]` | 2 | iki satır |
| `[Gel, otur, dinle.]` | 2 | hata |
| `[Ah, Vera]` | 2 | `Ah`, `Vera` |
| `Hemen çıkıyoruz.⏎Alçak dur.` | 2 | iki satır |
| `<think>⏎Output must be ["x"] only…⏎</think>⏎⏎["Kaç!"]` | 1 | `Kaç!` |

### 12.5 Hata eşlemesi ve dakikalık sınır
Başarısız HTTP yanıtında gövde okunur (yalnız eşleme için; hiçbir yere yazılmaz, anahtar hiçbir hata metninde görünmez):

| Durum | Gövdede (küçük harfle) | Tür |
|---|---|---|
| 401, 403 | — | anahtar geçersiz |
| 402, 429 | — | kota bitti |
| 400 | `api_key_invalid` ya da `api key not valid` | anahtar geçersiz |
| 400 | `credit balance` ya da `insufficient_quota` | kota bitti |
| 400 (diğer), 404 | — | model reddedildi |
| diğer (529, 500…), ağ, zaman aşımı | — | ulaşılamadı |

**Dakikalık sınır** (önce bakılır; yalnız 429): gövde JSON ve `error.details` dizisi olmalı. Bütün `details[].violations[]`
toplanır; metin olan `quotaId`'ler alınır. Birinde `PerDay` geçiyorsa ya da hiçbirinde `PerMinute` geçmiyorsa → dakikalık
değil (kota hatası olarak gösterilir). Dakikalıksa: `details[]` içinde metin olan ilk `retryDelay` (`"37.5s"` → sondaki
`s` atılıp kültürden bağımsız ondalık) bekleme önerisidir; `quotaId`'si `Requests` içeren ilk ihlalin `quotaValue`'su
(pozitif sayı ya da sayıya çevrilebilen metin) istek sınırıdır. Örnekler:
- `GenerateRequestsPerMinutePerProjectPerModel-FreeTier`, değer `10`, bekleme `37.5s` → (37.5 sn, 10).
- `GenerateContentInputTokensPerModelPerMinute-FreeTier`, `250000`, `3s` → (3 sn, sınır yok).
- `GenerateRequestsPerDayPerProjectPerModel-FreeTier` → dakikalık değil.
- `{"error":{"message":"quota"}}` → dakikalık değil; 400 + dakikalık gövde → değil; boş gövde → değil; boş gövdeli 429 →
  kota bitti.

Hata eşleme örnekleri: 400 + `{"error":{"message":"API key not valid. …","details":[{"reason":"API_KEY_INVALID"}]}}` →
geçersiz; 429 + `insufficient_quota` → kota; 400 + `Your credit balance is too low` → kota; 404 → model; 400 + `unknown
model` → model; 529, 500 → ulaşılamadı. Ollama'nın indirilmemiş model yanıtı (404) → model reddedildi.

### 12.6 Zaman aşımları ve hata bildirimi
- Bulut **5 sn**; yerel **15 sn**; "ekranı çevir" bulut **30 sn**, yerel **90 sn**; yerel "bağlantıyı dene" **90 sn**.
- Hata durumu yalnız değişince bildirilir (başla: tür; düzel: yok). Ana ekran "şu an çevirmiyor" uyarısını buna göre
  gösterir/kaldırır. Dakikalık sınır hata sayılmaz.

### 12.7 Yerel model sunucusu
Adres düzeltme (kullanıcının yazdığından):
1. Kırp; boşsa ya da boşluk içeriyorsa geçersiz.
2. `://` yoksa başına `http://`.
3. Sondaki `/`'lar atılır; `/chat/completions` (büyük/küçük harf duyarsız) ile bitiyorsa atılır ve yine sondaki `/`'lar.
4. Mutlak adres, şema `http`/`https`, makine boş değil olmalı; değilse geçersiz.
5. Sorgu ve parça atılır; yol boş ya da `/` ise `/v1`. Sonuç sondaki `/` olmadan.

| Girdi | Sonuç |
|---|---|
| `http://localhost:11434/v1` | `http://localhost:11434/v1` |
| `␠␠http://localhost:11434/v1/␠␠` | `http://localhost:11434/v1` |
| `localhost:11434` | `http://localhost:11434/v1` |
| `http://127.0.0.1:1234` | `http://127.0.0.1:1234/v1` |
| `http://localhost:1234/v1/chat/completions` | `http://localhost:1234/v1` |
| `https://ai.example.com/openai/v1` | aynı |
| boş / `ftp://localhost:11434` / `http://` / `local host` | geçersiz |

- Sunucu = (düzeltilmiş adres, kırpılmış model adı); model boşsa ya da adres geçersizse sunucu yok (yerel motor hazır
  değil).
- İstek adresi = temel + `/chat/completions`. Gösterilen kısa adres = şema + makine + kapı (`http://localhost:11434`).
- Tür (hata iletisi için): kapı 11434 Ollama, 1234 LM Studio, diğer "başka". Ollama adresi `http://localhost:11434/v1`,
  LM Studio `http://localhost:1234/v1`, varsayılan model `translategemma:4b`.
- Yerel motorda dakikalık hak yok. Test: LM Studio adresi, model `qwen2.5-7b-instruct`, anahtar ` yerel-anahtar ` → adres
  `http://localhost:1234/v1/chat/completions`, `Authorization: Bearer yerel-anahtar`.

### 12.8 Ekran çevirisi (toplu)
Ekrandaki bağımsız yazılar (menü satırı, görev yazısı) birlikte çevrilir:
1. Oyun adı bir kez alınır. Her metin önbellekte (oyunlu anahtarla) aranır.
2. Eksikler **40'lık** parçalar hâlinde, her parça tek istek: bağlam **yok**, çıktı sınırı 8192, ekran zaman aşımı.
   Hata beklemesindeyse hiç istek atılmaz. Her istekte ortak hak **sayılır ama beklenmez** (kullanıcı tuşa bastı; hak
   bitmiş olsa da gider). "Sınırdaydı" işareti istek başında temizlenir.
3. Başarıda hata durumu temizlenir, her çeviri önbelleğe yazılır. Sayı tutmazsa (§12.4) hata → kalanlar yedeğe.
4. Dakikalık sınır: hak düşürülür, bekleme (≤ 20 sn, ≥ 1 sn), "sınırdaydı"; kalan parçalar istek atmadan yedeğe.
5. Başka hata: bildirilir, 60 sn bekleme; kalanlar yedeğe.
6. Hâlâ çevrilmemiş her metin sırayla yedekle; yedek yoksa "indirme gerekli" hatası yukarı çıkar (ekranda hata).
- DeepL ve ücretsiz çevirmende toplu yok: metinler sırayla tek tek.
- Havuz öncelikli oyunda toplu yok (§1.2).
- **Uygulamada eksik:** §1.5'teki yazı denetimi boşluğu yüzünden eski uygulamada bu yol hiç devreye girmiyor. Yeni kodda
  devreye girmeli.

Testler:
- Eski hata: Gemini'de yedeksiz, hak 15, 20 farklı ekran yazısı tek tek çevrilince 15 istek, 15 gösterim, sonra
  "indirme gerekli" hatası.
- Düzeltme: hak önceden 15 kez harcanmış olsa da 20 yazı **tek istekte** gider, hepsi `[tr] …` olur, ekrana bir kez 20
  öğe gösterilir, `maxOutputTokens` 8192; yeniden basınca istek yok.
- 45 metin → 2 istek, sıra korunur.
- 500 → `yerel: Check the hold`, `yerel: Lower the sails`, hata "ulaşılamadı" bir kez; yedeksiz Claude'da ekran çevirisi
  "indirme gerekli" hatası, son hata "ulaşılamadı".
- Yanıt dizisi eksik (`["[tr] tek"]` iki yazı için) → ikisi de yedekten.
- Oyunlu önbellek ekranda da: `The shop is open.` oyun `Harbor game` → `Dükkân açık.` (istek başı `Game: Harbor game⏎`),
  tekrar istek yok; oyun `Forest game` → yeni istek `Mağaza açık.`; `Harbor game`'e dönünce önbellekten.
- 41 metin ekranda: oyun bir kez okunur (istek sırasında `Two` olsa da iki istek de `Game: One` ile başlar); sonra
  `One` ile istek yok, `Two` ile 2 yeni istek.

### 12.9 Anahtar deneme
Örnek satır: kodda sabit, konuşmacı etiketli kısa bir İngilizce cümle (etiket çevrilmez, cümle çevrilir; sonuç
`translation.key.sample` ile gösterilir). Anahtar kırpılır; bulut motorunda boşsa "geçersiz".
İstemci: yerel modelde 90 sn'lik, bulutta 5 sn'lik. Deneme çevirmeni sınırsız kendi hakkıyla kurulur (ortak hakkı
**yemez**) ve yedeği "her zaman başarısız" bir çevirmendir. Çeviri dönerse (geçerli, örnek çeviri). Yedeğe düşerse: son
hata varsa o; yoksa ve "sınırdaydı" ise **kota bitti**; değilse ulaşılamadı.
Testler: geçerli → (geçerli, `<etiket>: [tr] <cümle>`); dört hizmette 401 (gövdede anahtar geçse de) → (geçersiz,
örneksiz) ve sonuç metninde anahtar yok; zaman aşımı → ulaşılamadı; boşluklu anahtar (Claude) → geçersiz; dakikalık
429 → kota bitti; yerel anahtarsız → geçerli, Authorization yok.

### 12.10 Diğer testler
- Gemini `RUIZ: We leave now.` → `RUIZ: [tr] We leave now.`; adres `…/models/gemini-3.5-flash-lite:generateContent`;
  `x-goog-api-key` = anahtar; Authorization yok; yönerge Türkçe; `maxOutputTokens` 1024; `thinkingConfig` yok; ileti
  `["We leave now."]` ile biter, `RUIZ` içermez.
- OpenAI `Run!`: model `gpt-6-luna`, `reasoning_effort` `none`, `max_completion_tokens` 1024, roller developer + user.
- Claude `Run!`: model `claude-haiku-5-5`, `max_tokens` 1024, `system` yönerge, temperature yok, `output_config.effort`
  `low`, `thinking.type` `disabled`. `claude-sonnet-5-5` → `between_tools`; `gpt-6.1-terra` → `none`; `gemini-3.6-flash`
  → `thinkingLevel` `LOW`. `gpt-4o` → varsayılan `gpt-6-luna`. Gemini boş model → `gemini-3.5-flash-lite`; Claude yok →
  `claude-haiku-5-5`. Motor adları `gemini:gemini-3.5-flash-lite`, `openai:gpt-6-luna`.
- Yerel `RUIZ: We leave now.`: `http://localhost:11434/v1/chat/completions`, içerik türü JSON, Authorization yok, alanlar
  sıralı `max_tokens, messages, model, stream, temperature`; model `qwen2.5:7b`; roller system + user.
- Düşünen yerel model yanıtı (`<think>…</think>⏎⏎["Koş!"]`) → `Koş!`.
- Yerel sunucu kapalı → `yerel: Run!`, hata ulaşılamadı; Ollama 404 `model "qwen2.5:7b" not found…` → `yerel: Run!`,
  hata model reddedildi.
- Bağlam: `First.`, `Second.`, `Second.`, `Third.`, `Fourth.`, `Fifth.` (Claude) → 5 istek; ilkinde bağlam başlığı yok;
  2.'de `English: First.⏎Turkish: [tr] First.`; 5.'de `English: Second.⏎Turkish: [tr] Second.⏎English: Third.⏎…Fourth.`
  var, `First.` ve `Fifth.` yok.
- `We leave now. Keep low.⏎VERA: Yes, captain.` → `[tr] We leave now. [tr] Keep low.⏎VERA: [tr] Yes, captain.`, tek
  istek, dizi `["We leave now.","Keep low.","Yes, captain."]`.
- Tırnaksız yanıt `[Hadi çıkalım., Alçak dur.]` (yerel) → `Hadi çıkalım. Alçak dur.`; ekran isteği
  `[Ambarı kontrol et., Yelkenleri indir.]` → iki çeviri, ileti `Game: Lantern Coast⏎⏎` ile başlar.
- Oyun adı yokken `Game:` yok; `Harbor Tales` olunca ileti `Game: Harbor Tales⏎⏎` ile başlar.
- Yankı: model kaynağı geri verirse (`Vera: You think I'm hiding something?` → yerel yedek `yerel: You think I'm hiding
  something?` kullanılır; tekrar sorulunca yine istek gider (önbelleğe yazılmadı); yedek de aynı kalırsa (`Vera Ruiz.`)
  modelin cevabı yazılır, tekrar istek yok.
- Düz metin yanıt `Koş!` → `Koş!`.
- Kota (429 düz gövde) → `yerel: Run!`, `yerel: Duck!`, tek istek, hata kota bir kez, önbellekte `Run!` yok.
- Önbellek + bekleme: hizmet (503 / zaman aşımı / `{}` yanıtı / günlük kota / dakikalık kota) hatasından sonra
  önbellekteki `Run!`, `Hide!` ile `RUIZ: Run! Hide!` → `RUIZ: Koş! Saklan!` istek ve yedek olmadan; son hata
  değişmez; `Run! Duck!` (bir parça eksik) → `yerel: Run! Duck!`, yeni istek yok, önbellekte yok.
- İptal edilen yerel istek: yedek çağrılmaz, önbelleğe yazılmaz, hata bildirilmez, bekleme konmaz; sonraki `Run!` →
  `[tr] Run!`; ikinci isteğin iletisi `English: Lower the bridge.` içerir, `Turkish:` içermez.
- Oyunlu önbellek: oyun `One` iken `Keep low.`; `Two` iken `Keep low. Run!` → 2 istek, 2.'nin dizisi
  `["Keep low.","Run!"]`; sonra `Run!` istek atmaz. Eski kayıt `Keep low.`→`Önceki çeviri.`: oyun yok ya da `␠␠␠` →
  eski; `␠␠One␠␠` → yeni istek (`Game: One⏎` ile), `One` → önbellekten; oyun yok → yine eski.
- Bütçe 1: `Run!` buluttan, `Hide!` yerelden (sınırdaydı, hata yok), `Run!` önbellekten. Bütçe 1 ile `We leave now. Keep
  low. Run!` tek istek. Dakikalık 429 (değer 5) → iki satır yerel, tek istek, hata yok, sınırdaydı, hak 5'e düştü.
  Günlük 429 → kota bitti bildirilir.

### Mac'ten farkı (§12)
- **Türkçe yönerge daha kısa:** Windows'ta "oyunun büyük harfle yazdığı terimler küçük harfli sıradan ad, ek bitişik,
  kesme yalnız gerçek adlarda, doğru yazım/ünlü uyumu" maddeleri yok. Yeni Windows kodu eski Windows yönergesinin anlamını
  korumalı (istenirse Mac'inkine yükseltmek ayrı karar).
- Gövde anahtarları sıralı değil, yukarıdaki sırayla (Mac sıralı yazıyor); hizmetler sıradan etkilenmez.
- Ollama model listesi/indirme yok (§2).

---

## 13. Hedef diller

### 13.1 Liste (11 dil; Türkçe hep ilk)
| Kod | Kendi adı | İstemdeki İngilizce ad | DeepL | Ücretsiz model |
|---|---|---|---|---|
| tr | Türkçe | Turkish | var | var (CTranslate2) |
| ar | العربية | Arabic | var | var |
| hi | हिन्दी | Hindi | yok | var |
| id | Bahasa Indonesia | Indonesian | var | var |
| th | ไทย | Thai | var | yok |
| vi | Tiếng Việt | Vietnamese | var | var |
| ur | اردو | Urdu | yok | yok |
| bn | বাংলা | Bengali | yok | yok |
| ms | Bahasa Melayu | Malay | yok | yok |
| tl | Filipino | Filipino | yok | yok |
| nl | Nederlands | Dutch | var | var |

- Kod = ilk iki harf, küçük harf. Listede olmayan kodun İngilizce adı `Turkish` döner (yalnız güvenlik için); kendi adı
  kodu. `fi` desteklenmez (Filipince `tl` tutulur).
- İlk açılış (ayar dosyası yokken): Windows arayüz dili `fil` ile başlıyorsa `tl`; değilse ilk iki harfi listedeyse o;
  değilse `tr`. `ar` → `ar`; `tr` → `tr`; `en` → `tr`; boş → `tr`; `vi` → `vi`; `fil` → `tl`; `fi` → `tr`.
- Sözlük, ek kurma, Türkçe düzeltme, hitap, kısa satır bağlamı ve oyun paketleri **yalnız `tr`**'de. Çevrimiçi motorlar
  ve havuz bütün dillerde. Havuz önceliği sunucunun izin verdiği dillerde (varsayılan yalnız `tr`).

### 13.2 Sağdan sola gösterim
Sağdan sola hedef: **`ar`, `ur`**. Arap harfi = şu aralıklardan biri: U+0620–064A, U+066E–06D3, U+06FA–06FF,
U+0750–077F, U+08A0–08FF, U+FB50–FDFF, U+FE70–FEFF. Gösterilecek metinde Arap harfi varsa `\n`'den bölünen her paragrafın
başına (zaten yoksa) U+200F konur; yoksa metin aynen. `VERA: أين القبطان؟⏎انتظر هنا` → her iki satırın başında U+200F;
`Daha bitmedi.` aynen; iki kez uygulamak tek işaret verir.

### 13.3 Hedefin yazısıyla yazılmış satır (yazı denetimi)
Hedef `ar`/`ur` ve metinde Arap harfi varsa, ya da hedef `th` (U+0E00–0E7F), `hi` (U+0900–097F), `bn` (U+0980–09FF) ve
metinde o yazının karakteri varsa: satır **zaten hedef dilde**; çevirmene gönderilmeden **olduğu gibi** döner (okuma hattı
bunu "zaten hedef dilde" sayıp göstermez). Hedef Türkçeyse satırlar doğrudan çevirmene verilir. Ön çeviri de aynı kuralla
atlanır. Örnekler: `الإعدادات` (ar) → evet; `Settings` (ar) → hayır; `الإعدادات` (tr) → hayır; `ตั้งค่า` (th), `सेटिंग्स`
(hi), `সেটিংস` (bn), `ترتیبات` (ur) → evet; `Where is the harbor?` (th) → hayır. Sarmalayıcı testi: Arapça hedefte
`الألعاب` → aynen, `Keep low.` → içteki çevirmen; Türkçe hedefte `الألعاب` → içteki çevirmen.

### Mac'ten farkı (§13)
- Sağdan sola Windows'ta yalnız `ar`, `ur` (Mac: `ar fa he ur`).
- Windows'ta "hedefe özgü harf (ı İ ğ Ğ ş Ş) varsa hedef dilde" ve dil tanıyıcıyla (≥ 0.90) denetim **çevirmen
  katmanında yok**; yalnız yazı denetimi (§13.3) ve okuma hattının çeviri sonrası benzerlik denetimi (§1, madde 4) var.

---

## 14. Windows'a özgü kısımlar

| Yetenek | Ne için | Ayrıntı |
|---|---|---|
| `%LOCALAPPDATA%\Nino\` | veri | `translations\` (önbellek), `glossary\` (kullanıcı sözlükleri), `models\en-tr-ct2`, `models\en-<dil>`, `cuda-12.8\` |
| DPAPI şifreli depo | çevrimiçi anahtarlar | `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey`, `localAIKey` (başka belge) |
| Alt süreç (gizli pencere, yönlendirilmiş akışlar, süreç ağacını öldürme) | CTranslate2 işçisi | §8.6 |
| Gömülü CPython 3.12 + VC++ çalışma zamanı DLL'leri uygulama yanında | işçi ve ONNX | yönetici izni gerekmez |
| `nvcuda.dll` varlığı (`System32`) | GPU seçilebilir mi | yoksa CUDA indirilmez |
| DLL arama klasörü (işçide) | cuBLAS'ı bulmak | `NINO_CUDA_DIR` + `PATH` |
| ONNX Runtime (CPU, .NET 1.31.1) | Türkçe dışı ücretsiz diller | §8.8 |
| Microsoft.ML.Tokenizers 2.0.1 | SentencePiece | §8.7 |
| Mantıksal işlemci sayısı | iş parçacığı seçenekleri | §2, §8.5, §8.8 |
| Windows arayüz dili (iki harfli ISO) | ilk açılış hedef dili | §13.1 |
| Gömülü kaynaklar | `ai-models.json`, `glossary-en-tr.json` | §12.2, §5.6 |
| Ortam değişkenleri (geliştirici) | `NINO_CT2_RUNTIME` (işçi klasörü); testlerde `NINO_TEST_MODELS`, `NINO_DOWNLOAD_TEST_MODELS=1`, `NINO_TEST_MODELS_AR` | gerçek model testleri yalnız dosyalar varsa |
