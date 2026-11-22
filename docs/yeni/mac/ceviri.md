# Mac: çeviri (tarif)

Bu belge eski Mac uygulamasının çeviriyi **nasıl yaptığını** anlatır: sıra, sağlayıcılar, istek biçimleri,
önbellek, terimler, Türkçe düzeltme, hedef diller. Kod yoktur; kurallar test yazılabilsin diye eşik değerleri ve
girdi→çıktı örnekleriyle verilir.

Yeni çekirdekte (NinoCore) neyin olduğu her bölümün sonunda "NinoCore'da eksik" listesinde yazılı. NinoCore'daki
dosyalar yoluyla anılır (ör. `Sources/NinoCore/Translation/ProviderChain.swift`).

> Marka adları (DeepL, Gemini, Groq…) bu belgede yalnız davranışı anlatmak için geçer. NinoCore kuralı gereği yeni
> kodda ve testlerde sağlayıcılar genel adlarla anılır.

## 0. Neyin birebir aynı kalması gerekir

Bunlar diskteki eski verilerle, sunucuyla ya da öbür platformlarla (Windows, Android, iPhone) ortaktır. Yeni kod
bunları **bayt bayt aynı** üretmelidir; yoksa eski önbellek, paketler ve havuz kullanılamaz:

- Paket ve havuz anahtarı (sadeleştirme + SHA-256'nın ilk 8 baytı): `havuz-paketler.md` §1.
- Bulanık paket imzası (Bloom): `havuz-paketler.md` §3.
- Önbellek dosya adı ve satır biçimi: aşağıda §6.
- Terim sözlüğünün izi (FNV-1a): §7.4.
- Paket ve havuz sunucularının istek/yanıt biçimleri: `havuz-paketler.md` §4 ve §6.

Geri kalan her şey (sıra kuralları, eşikler, istemler) davranıştır; aynı sonucu veren başka bir yolla yazılabilir.

## 1. Bir satırın yolu (zincir)

Okuma hattı ekrandan bir İngilizce satır verir. Sıra:

1. **Hazır çeviri araması** (satır sıraya alınırken; paket + havuz deposu; `havuz-paketler.md` §2 ve §6):
   - Oyun paketleri açıksa **ve** oyun "havuz öncelikli" değilse önce paketlere bakılır.
   - Bulunmazsa (ya da paketlere bakılmadıysa) ortak havuz açıksa veya oyun havuz öncelikliyse, cihaza inmiş havuz
     çevirilerine bakılır.
   - Önce satırın tamamı, bulunmazsa konuşmacı öneki atılmış gövde aranır.
   - Bulunursa hemen gösterilir; çevirmene gidilmez.
2. **Bulunmadıysa**: satır havuz gönderme kuyruğuna önerilir (`havuz-paketler.md` §6.1–6.2) ve aynı anda sunucuya
   "daha iyi çeviri" sorulur (gelirse ekrandaki çevirinin yerine konur, `havuz-paketler.md` §6.5).
3. **Zaten hedef dilde mi?** (§9.2; çeviri adımının başında) Evetse çevrilmez, gösterilmez.
4. **Çevirmen**: aşağıdaki karar ağacıyla seçilir. Konuşmacı öneki varsa çevirmene yalnız gövde gider.
5. **Çeviri dönünce** paket/havuz deposuna bir kez daha bakılır: arada havuzdan çeviri inmişse **o** gösterilir.

### 1.1 Çevirmen karar ağacı

```
oyun havuz öncelikli mi? (ve kaynak İngilizce)
├─ evet → sunucuya sor, en çok deadlineMs (varsayılan 1500 ms) bekle
│         ├─ çeviri geldi → onu göster
│         └─ gelmedi       → yalnız cihaz içi ücretsiz çeviri (kullanıcının anahtarlı motoru ÇAĞRILMAZ)
└─ hayır
   ├─ oyun kesin bilinmiyor (ve kaynak İngilizce) → yine sunucuya sor (aynı süre); gelirse göster
   └─ kullanıcının motoru:
        çevrimiçi çeviri etkin mi? (§2)
        ├─ hayır → cihaz içi ücretsiz çeviri
        └─ evet  → seçili motor (DeepL / Gemini / OpenAI / Claude / yerel model)
                   hata, kota, dakikalık sınır → o satır cihaz içi çeviriyle (yedek)
```

Önemli kurallar:

- Havuz öncelikli oyunda (varsayılan GTA 6) **ortak havuz ayarı kapalı olsa da** sunucuya sorulur. Bu, kullanıcının
  bilerek verdiği karardır.
- "Oyun kesin değilse sunucuya sor" kuralı, sunucunun satırdan GTA 6'yı tanıyıp sonraki satırları havuz öncelikli
  yapabilmesi içindir. Bu soruda oyun adı yalnız oyun kesin biliniyorsa **ya da** aday oyun havuz öncelikli
  listedeyse gönderilir; yoksa boş gider (sunucu satırdan ve bu kurulumun son oyunundan kendisi bulur).
- Sunucu süresinde cevap vermese de istek sürer; geç gelen çeviri havuz deposuna yazılır.
- Son satırı kim çevirdi bilgisi tutulur: `havuz`, `ücretsiz`, `motor` (günlük için).

### 1.2 Ücretsiz zincir (Gemini + Groq) nerede?

Mac istemcisinde Groq **yoktur**. "Ücretsiz zincir" sunucu tarafındadır (havuz sunucusu, `nino-pool/src/free.js`):
istemci yalnız `POST /v1/translate` atar, sunucu sırayla ücretsiz servisleri dener. Bugünkü sunucu yapılandırması
(`nino-pool/wrangler.toml`):

- Anında çeviri zinciri (`FREE_CHAIN`): Groq (3 model) → DeepL Free → OpenRouter ücretsiz modelleri → NVIDIA →
  OpenRouter (ücretli, günlük dolar sınırlı; sonuncusu OpenRouter üzerinden bir Gemini modeli).
- Google'ın kendi Gemini API'si yalnız **toplu çeviride** (`BATCH_CHAIN`; zamanlayıcı 30 dakikada bir, parti 50
  satır): havuzda çevrilmemiş bekleyen satırlar.
- Hakkı dolan servis (429) bir süre atlanır (varsayılan 120 sn ya da servisin söylediği bekleme). Servis başına
  cevap bekleme 2500 ms.
- Hepsi doluysa sunucu `text: null` döner; istemci cihaz içi çeviriyi gösterir.

İstemcinin bilmesi gereken tek şey: sunucuya sor, süre dolunca ya da `null` gelince cihaz içi çeviriye düş.

Ayrıca kullanıcı **kendi** ücretsiz Gemini anahtarını girerse (kurulumdaki "daha iyi çeviri" adımı) bu, istemcide
doğrudan Gemini'ye giden motordur (§4); sunucu zinciriyle ilgisi yoktur.

### NinoCore'da eksik
- Sıra farklı: NinoCore önbellek → paket → zincir yapıyor. Eski düzen: paket → havuz deposu → (zaten hedef dilde
  mi) → havuz önceliği/sunucu → motor (motorun **kendi** önbelleğiyle) → cihaz içi yedek → dönüşte depoya yeniden
  bakma.
- Havuz önceliği, sunucuya süreli soru (deadline), geç gelen çevirinin ekrandakinin yerine konması yok.
- "Oyun kesin değilse sunucuya da sor" kuralı yok.
- "Motor hata verince yalnız o satır cihaz içine düşsün, motor 60 sn denenmesin" davranışı NinoCore'daki dinlenme
  kuralıyla (3 hata → 60 sn) benzer ama aynı değil: eski kod **ilk** hatada 60 sn bekletir (§4.6).
- Son satırı kimin çevirdiği (`havuz/ücretsiz/motor`) bilgisi yok.

## 2. Hangi ayar neyi açar

| Ayar | Varsayılan | Etkisi |
|---|---|---|
| kaynak dil | `en` | İngilizce değilse paket, havuz, havuz önceliği, çevrimiçi motor kapanır; yalnız cihaz içi çeviri. |
| hedef dil | `tr` (ilk açılışta sistem dili listedeyse o) | §9. |
| çevrimiçi çeviri | kapalı | Açık **ve** motor hazırsa seçili motor kullanılır. |
| çevrimiçi motor | DeepL | DeepL, Gemini, OpenAI, Claude, yerel model. "Ücretsiz" hiçbir zaman bu alana yazılmaz. |
| model (motor başına) | listedeki ilk model | §4.2. |
| yerel model adresi / adı | `http://localhost:11434/v1`, `translategemma:4b` | §4.5. |
| oyun paketleri | açık | Yalnız `en`→`tr` iken paket araması. |
| ortak havuz | açık | Pakette olmayan satırları gönderir; havuz çevirilerini indirir/kullanır; oyunu ekrandan tanır. |

"Motor seçimi" tek bir değer gibi davranır: `ücretsiz` seçilince çevrimiçi çeviri kapanır; başka bir motor seçilince
açılır ve o motor yazılır. Eski kayıtta motor `ücretsiz` yazılıysa okurken DeepL'e çevrilir.

**Çevrimiçi çeviri etkin** = çevrimiçi çeviri açık **ve** kaynak `en` **ve** hedef seçilebilir dillerden biri
**ve** (motor DeepL ise hedef DeepL'in desteklediği dillerden) **ve** motor hazır. Motor hazır sayılır: bulut motorunda anahtar
kayıtlı; yerel modelde adres ve model adı geçerli (anahtar gerekmez).

### 2.1 Anahtarlar

- Anahtarlar Keychain'de durur, arayüze hiç geri dönmez (yalnız "kayıtlı mı" bilgisi).
- Hesap adları: `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey`, `localAIKey` (eski kurulumdan taşımak için).
- Anahtar kaydederken önce bir örnek satırla denenir. Kaydedilir: geçerli, kotası bitmiş ya da (yapay zekâda) model
  reddedilmiş. Kaydedilmez: geçersiz anahtar, ulaşılamadı.
- Kaydedilince o motor seçilir. Zaten seçiliyse çeviri hattı yeni anahtarla yeniden kurulur.
- Anahtar silinince o motor seçiliyse çevrimiçi çeviri kapanır. Yerel modelin anahtarı silinirse çeviri anahtarsız
  sürer.
- Anahtar baştan/sondan boşluk kırpılarak kullanılır.

### NinoCore'da eksik
- Motor seçimi, model listesi, "çevrimiçi etkin" koşulu, anahtar deneme-kaydetme akışı yok. NinoCore'da yalnız genel
  HTTP sağlayıcı listesi ve `useOnDevice` var.
- Eski Keychain hesap adlarından taşıma yok.

## 3. Cihaz içi (ücretsiz) çeviri

Apple'ın Translation çerçevesi (macOS 26+). Dil paketi yüklü değilse `indirme gerekli`, sistem eskiyse
`desteklenmiyor` durumu döner; arayüz bunu gösterir.

Hedef `tr` ve kaynak `en` ise satır şu metin hattından geçer (Windows'taki ücretsiz çeviriyle aynı adımlar):

1. Satır cümlelere bölünür; konuşmacı etiketi (`NADIA: `) ve diyalog tiresi çevrilmez (bölme kuralları:
   `okuma-hatti.md` §10.2). Etiketlerden karakter adları öğrenilir.
2. Her cümle için:
   1. Sözlükte hazır satır varsa (`lines`, §7.2) çevirmene gitmez.
   2. Tümü büyük harfli cümle cümle düzenine getirilir (öğrenilen adlar ve sözlükte büyük harfle yazılmış terimler
      büyük kalır). `THE BRIDGE IS ON FIRE.` → `The bridge is on fire.`
   3. Oyun argosu düz İngilizceye (§7.2).
   4. Terimler uydurma adlarla korunur (§7.1).
   5. Çeviri; yer tutucular geri konur, ekler kurulur (§7.1, §7.5).
   6. Türkçe düzeltme (§8).
3. **Kısa cümle bağlamı**: harf içeren sözcük sayısı 1–3 olan cümle (`Boy!`, `Do it.`, `Not you.`) önceki cümleyle
   birlikte çevrilir: `önceki *** kısa`. Önceki cümle = aynı satırdaki önceki cümle; yoksa bu satırdan önce
   gösterilen satırın son cümlesi (en çok 20 sn önce gösterildiyse). Aynı satır yeniden okunursa aynı bağlam döner.
4. Çıktıdan `***` sonrası alınır. Alınmaz (tek başına yeniden çevrilir) eğer:
   - `***` tam bir kez geçmiyor,
   - yıldızlar yapışık (`****`),
   - iki yandan biri harf içermiyor,
   - sonrası kaynak cümlenin UTF-16 uzunluğunun `3×+20`'sinden uzun.
5. Terim yer tutucusu kaybolursa: korumasız (terimsiz) yeniden çevrilir. "Terimsiz ama eksiksiz" tercih edilir.
6. Satırın bütününe hitap kuralı (§8.3) uygulanır.

Hedef `tr` değilse: yalnız cümle bölme + büyük harf düzeni + oyun deyimleri; sözlük, ekler, Türkçe düzeltme yok.

Oyun deyimleri (her hedefte, düz İngilizceye): `hit the deck`→`lie flat`, `haul tail`→`run fast`,
`we're toast`→`we are finished`, `waste 'em`→`kill them`, `go loud`→`start shooting`, `radio silence`→`no talking`,
`out of juice`→`out of power`, `hold the fort`→`defend this place`, `bought the farm`→`died`. Tam sözcük, büyük/küçük harf fark etmez, baş harf büyükse karşılığınki de büyük.

Örnek (kısa satır ayıklama, kaynak `Not you.`):

| Çıktı | Sonuç |
|---|---|
| `Dur orada. *** Sen değil.` | `Sen değil.` |
| `Dur orada. Sen değil.` | yok (tek başına çevrilir) |
| `A *** B *** C` | yok |
| `**** Sen değil.` | yok |

### NinoCore'da eksik
- Kısa cümleyi bağlamla çevirme (`***` ayracı) yok.
- Oyun deyimleri, argo düzleştirme, hazır satırlar yok.
- Tümü büyük harfli cümleyi düzeltme yok (okuma hattına aitse orada da kontrol edilmeli).
- Etiketten ad öğrenme yok.
- Yer tutucu kaybolunca "korumasız yeniden çevir" yok (NinoCore sonucu reddedip sıradaki sağlayıcıya geçiyor).
- Cihaz içi çeviride dil paketi durumu (`hazır / indirme gerekli / desteklenmiyor`) arayüze verilmiyor.

## 4. Yapay zekâ motorları (kullanıcının anahtarıyla)

Gemini, OpenAI, Claude ve bilgisayarda çalışan model (Ollama veya LM Studio) aynı çekirdekten geçer.

### 4.1 Satır akışı

1. Bağlam = bu satırdan **önce** gösterilen son 3 satır (ve biliniyorsa çevirileri). Aynı satır art arda gelirse
   bağlama iki kez girmez.
2. Satırın tamamı önbellekte varsa döner (§6).
3. Satır cümlelere bölünür; önbellekte olan cümleler gönderilmez.
4. Eksik cümleler **tek istekte**, JSON dizisi olarak gider; aynı sırada JSON dizisi beklenir.
5. Hizmet şu an dinlenmedeyse ya da dakikalık hak yoksa istek **gönderilmez**, satır cihaz içi çeviriyle çevrilir
   (kullanıcıya hata gösterilmez).
6. Gelen her cümle önbelleğe; bütün satır da önbelleğe yazılır.
7. **Yankı kontrolü**: model cümleyi çevirmeden geri verdiyse (sadeleştirilmiş kaynak ile çeviri benzerliği ≥ 0.90,
   Levenshtein oranı) cümle bir kez cihaz içi çeviriyle denenir. O da aynı kalmazsa cihaz içinin sonucu kullanılır
   ve **bu satır** motorun önbelleğine yazılmaz. Aynı kalırsa (ad, Türkçe menü) modelin cevabı kalır.
8. Gösterilen çeviri sonraki satırların bağlamına girer.

### 4.2 Model listesi

Liste bir JSON dosyasından gelir (`ai-models.json`, Windows ile ortak). Biçim: hizmet adı → model dizisi; ilk model
varsayılan. Dizi olmayan alanlar (`_comment`) atlanır. Kayıtlı model listede yoksa varsayılan model kullanılır.
Kullanıcı bulut modelinin adını yazamaz, listeden seçer.

| Alan | Anlamı |
|---|---|
| `id` | hizmetteki model adı |
| `label` | ayarlarda görünen ad (yerelleştirme anahtarı) |
| `effort` | OpenAI'da `reasoning_effort`, Claude'da `output_config.effort`; yoksa gönderilmez |
| `thinking` | Gemini'de `thinkingConfig.thinkingLevel`, Claude'da `thinking.type`; yoksa gönderilmez |
| `freeTier` | ücretsiz anahtarla kullanılabilir (bugün yalnız Gemini) |
| `requestsPerMinute` | uygulamanın dakikada gönderdiği en çok istek; yoksa sınır yok |

Bugünkü içerik: Gemini `gemini-3.5-flash-lite` (15/dk, ücretsiz), `gemini-3.6-flash` (`thinking: LOW`, 10/dk,
ücretsiz); OpenAI iki model (`effort: none`); Claude iki model (`effort: low`).

### 4.3 İstek biçimleri

Ortak kullanıcı iletisi İngilizce yazılır, bölümler aralarında boş satırla şu sırada gelir (cümleler kendi
sözümüzle kurulur, metin olarak kopyalanmaz):

1. Oyun satırı: oyunun adı (yalnız oyun kesin biliniyorsa).
2. Bağlam bölümü: önceki satırların yalnız bağlam için verildiğini ve yeniden çevrilmemesi gerektiğini söyleyen bir
   başlık; altında her önceki satır için `English: <önceki satır>` ve biliniyorsa `<Dil adı>: <çevirisi>`.
3. Görev cümlesi: aşağıdaki JSON dizisindeki her dizgenin `<Dil adı>`'na çevrilmesini ve yanıtın aynı sırada `<N>`
   dizgeden oluşan yalnız bir JSON dizisi olmasını ister.
4. Dizi: `["cümle 1","cümle 2"]`.

Sistem yönergesi hedef dile göre seçilir (metin olarak kopyalanmaz, kurallar şunlar):

- **Türkçe**: doğal, konuşma Türkçesi; karakterler birbirine "sen" der (açıkça resmî değilse); karakter, yer adları
  ve `NADIA:` gibi etiketler aynen; satır sonları korunur; anlam ve ton korunur, ekleme/eksiltme yok; doğru yazım;
  oyunun büyük harfle yazdığı terimler (Journal, Map, Camp…) Türkçede küçük harfli sıradan addır, ek bitişik
  (`günlüğüne`, `haritada`), kesme yalnız gerçek kişi/yer adlarında (`Arthur'a`), ünlü uyumu ve ünsüz değişimi;
  yalnız çeviri, açıklama yok.
- **Arapça**: kısa, ekranda kolay okunan Modern Standart Arapça; adlar ve etiketler Latin harfiyle aynen; Arapça
  noktalama (، ؟ ؛), Batı rakamları; kol tuşu simgeleri (✕ ○ △ □, L1, R2) aynen.
- **Öbür diller**: aynı kurallar dil adıyla (Arapça noktalama maddesi hariç).

Sağlayıcıya göre HTTP isteği (hepsi `POST`, `Content-Type: application/json`):

| Sağlayıcı | Adres | Anahtar | Gövde |
|---|---|---|---|
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` (model URL yolu için kaçışlanır) | `x-goog-api-key` başlığı | `systemInstruction.parts[0].text`, `contents[0] = {role: user, parts:[{text}]}`, `generationConfig.maxOutputTokens`, varsa `generationConfig.thinkingConfig.thinkingLevel` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | `model`, `messages = [{role: developer, …}, {role: user, …}]`, `max_completion_tokens`, varsa `reasoning_effort` |
| Claude | `https://api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `model`, `max_tokens`, `system`, `messages=[{role:user}]`, varsa `output_config.effort`, `thinking.type` |
| Yerel | `<adres>/chat/completions` | anahtar boş değilse `Authorization: Bearer` (boşsa başlık hiç yok) | `model`, `messages=[{role: system}, {role: user}]`, `temperature: 0.2`, `max_tokens`, `stream: false` |

- Çıktı sınırı: altyazıda 1024, "ekranı çevir"de 8192.
- Temperature yalnız yerel modelde gider.
- Gövde JSON anahtarları sıralı yazılır (önbellek/test kararlılığı için).

**Çeviri modelleri** (yerel modelin adı `translategemma` ya da `milmmt` içeriyorsa, büyük/küçük harf fark etmez):
yönerge ve JSON dizisi gönderilmez. Önceki satırlar (çevirisi olanlar) kullanıcı/asistan çifti olarak, sonra
cümleler satır satır (cümle içi satır sonları boşluk olur) tek kullanıcı iletisinde, modelin kendi kalıbıyla gider:

- TranslateGemma: "profesyonel İngilizce (en) → <Dil> (<kod>) çevirmen" kalıbı, metinden önce iki boş satır.
- MiLMMT: `Translate this from English to <Dil>:\nEnglish: <metin>\n<Dil>:`.

### 4.4 Yanıt okuma

Metin çıkarma:
- Gemini: `candidates[0].content.parts[].text`, `thought: true` olan parçalar atlanır, birleştirilir.
- OpenAI ve yerel: `choices[0].message.content`.
- Claude: `content[]` içinde `type == "text"` olanlar birleştirilir.
- Metin yok ya da boşsa: `ulaşılamadı`.

Metinden çeviri listesi (sırayla dene):
1. Son `</think>` varsa sonrası alınır.
2. Kontrol işaretleri silinir: `<s>`, `</s>`, `<|…|>` (1–32 harf/rakam/_), `<start_of_turn>`, `<end_of_turn>`,
   `<eos>`, `<bos>`, `<pad>` (açılış ve kapanış). Başka `<…>` yazıya dokunulmaz.
3. ```` ``` ```` çiti varsa çit satırları atılır.
4. İlk `[` ile son `]` arası JSON dizisi olarak okunur (sondaki `,]` düzeltilir). Eleman sayısı istenenle tutmazsa
   `ulaşılamadı`. Her eleman kırpılır.
5. Tırnaksız dizi (`[Fener sönmek üzere.]`, `[Bir., İki.]`): yalnız bütün yanıt `[`…`]` ise ve eleman sayısı tam
   tutuyorsa. Bölme sırası: satır sonu → cümle sonu işaretinden (`. ! ? … " ”`) hemen sonraki virgül → düz virgül.
   Boş eleman olmamalı.
6. Birden çok cümle istendiyse: boş olmayan satırlar, sayı tam tutmalı.
7. Tek cümlede: metnin kendisi (baş/son `"“”` atılır).

Örnekler:

| Yanıt | İstenen | Sonuç |
|---|---|---|
| `["Bir.", "İki.",]` | 2 | `["Bir.", "İki."]` |
| `<think>…</think>["Tamam."]` | 1 | `["Tamam."]` |
| `[Köprü yıkıldı., Karşıya yüzmeliyiz.]` | 2 | `["Köprü yıkıldı.", "Karşıya yüzmeliyiz."]` |
| `"Merhaba"` | 1 | `["Merhaba"]` |
| `["Bir."]` | 2 | hata (`ulaşılamadı`) |

### 4.5 Yerel model sunucusu

Adres düzeltme (kullanıcının yazdığından):
- Boş ya da boşluk içeren adres geçersiz.
- Şema yoksa `http://` eklenir; yalnız `http`/`https` kabul.
- Sondaki `/` ve `/chat/completions` atılır.
- Yol yoksa `/v1` eklenir; sorgu ve parça atılır.

| Girdi | Sonuç |
|---|---|
| `localhost:11434` | `http://localhost:11434/v1` |
| `http://localhost:1234/v1/chat/completions/` | `http://localhost:1234/v1` |
| `ftp://x` | geçersiz |

Kapıdan tür tahmini: 11434 Ollama, 1234 LM Studio, başka "diğer" (hata yönergesi için). Model adı boşsa
`translategemma:4b`. Eski kayıttaki `qwen2.5:7b` varsayılana çevrilir.

Önerilen modeller (ayarlardan tek tuşla indirilir): `translategemma:4b` (3,3 GB, önerilen), `translategemma:12b`
(8,1 GB, 16 GB bellek), MiLMMT 4B (3,1 GB). Kurulu model listesi `GET <kök>/api/tags` (3 sn), indirme
`POST <kök>/api/pull` `{"model":…, "stream":true}` (1 saat). Kök = adresin sonundaki `/v1` atılmış hâli.
"model" ile "model:latest" aynı sayılır, büyük/küçük harf fark etmez. İndirme ilerlemesi satır satır JSON:
parça (`digest`) başına `total`/`completed`, ilerleme = toplam tamamlanan / toplam (en çok 0.99), `status: success`
bitti, `error` hata.

### 4.6 Hata, bekleme, dakikalık hak

Zaman aşımı: bulut 5 sn, yerel 15 sn, "ekranı çevir" bulut 30 sn, yerel deneme 90 sn.

HTTP durumundan hata türü (yanıt gövdesi yalnız tanınan kodlar için okunur, hiçbir yere yazılmaz):

| Durum | Gövdede | Tür |
|---|---|---|
| 401, 403 | — | anahtar geçersiz |
| 402, 429 | — | kota bitti |
| 400 | `api_key_invalid` ya da `api key not valid` | anahtar geçersiz |
| 400 | `credit balance` ya da `insufficient_quota` | kota bitti |
| 400 (diğer), 404 | — | model reddedildi |
| diğer, ağ hatası | — | ulaşılamadı |

**Dakikalık sınır** (yalnız 429'da, gövdede `error.details[]`): `violations[].quotaId` içinde `PerMinute` geçiyor
ve hiçbirinde `PerDay` geçmiyorsa bu dakikalık sınırdır:
- `retryDelay` (`"37s"`) varsa bekleme o, yoksa 20 sn; en az 1, en çok 20 sn.
- `quotaId`'si `Requests` içeren ihlalin `quotaValue`'su (sayı ya da metin) dakikalık hakkı **düşürür** (yükseltmez).
- Kullanıcıya hata gösterilmez; o satır cihaz içine düşer.
- Günlük sınır (`PerDay`) ya da tanınmayan 429 → "kota bitti" olarak gösterilir.

Başka hata → hata durumu bildirilir (ana ekranda "şu an çevirmiyor" uyarısı), hizmet **60 sn** denenmez, satır
cihaz içine düşer. Başarılı istek uyarıyı kaldırır. Uyarı yalnız durum değişince bildirilir.

**Dakikalık hak** (kayan 60 sn pencere): penceredeki istek sayısı sınırın altındaysa hak alınır. Hak model başına
uygulama genelinde ortaktır (Google sınırı proje+model başına sayar; hat yeniden kurulsa da sıfırlanmaz). Deneme
isteği hak yemez. Örnek: sınır 2, t=0 ve t=10'da istek → t=20'de hak yok, t=60'ta var.

Anahtar denemesi örnek satırı: `BATMAN: I'm Batman.` (etiket çevrilmez, cümle çevrilir).

### 4.7 Ekran çevirisi (toplu)

Ekrandaki bağımsız yazılar tek istekte gider (en çok 40 parça/istek, çıktı 8192). Bağlam gönderilmez. Kullanıcı
tuşa bastığı için hak bitmiş olsa da gönderilir (hak sayılır). Hata ya da dakikalık sınırda kalan parçalar cihaz
içiyle çevrilir; o da yoksa hata ekranda gösterilir. DeepL ve cihaz içinde parçalar sırayla tek tek çevrilir.
Havuz öncelikli oyunda toplu istek yapılmaz, parçalar tek tek havuz kuralıyla çevrilir.

### NinoCore'da eksik
NinoCore'un genel HTTP sağlayıcısı (`Sources/NinoCore/Translation/HTTPTranslationProvider.swift`) şablonla tek
metin gönderir, cevaptan tek yol okur. Şunları anlatamıyor:
- Birden çok cümleyi tek istekte dizi olarak gönderip aynı sırada dizi bekleme.
- Bağlam satırları (önceki 3 satır ve çevirileri), oyun adı satırı.
- Hedef dile göre sistem yönergesi; çeviri modelleri için ayrı kalıp (yönergesiz, soru-cevap bağlamı).
- Dakikalık hak, 429 gövdesini okuma, hakkı düşürme, ilk hatada 60 sn bekleme.
- Yanıt temizliği (`</think>`, kontrol işaretleri, çit, tırnaksız dizi, satır satır).
- Yankı kontrolü (≥ 0.90) ve cihaz içiyle yeniden deneme.
- Hata türleri (anahtar/kota/model/ulaşılamadı) ve "şu an çevirmiyor" bildirimi.
- Anahtar deneme (örnek satır), model listesi dosyası, yerel model adres düzeltme, Ollama model listesi/indirme.
- Ekran çevirisinin toplu isteği.

## 5. DeepL motoru

- Adres: anahtar `:fx` ile bitiyorsa `https://api-free.deepl.com/v2/`, yoksa `https://api.deepl.com/v2/`.
- Çeviri: `POST …/translate`, başlık `Authorization: DeepL-Auth-Key <anahtar>`, gövde:
  `{"text":[…], "source_lang":"EN", "target_lang":"TR", "preserve_formatting":true}`;
  hedef `TR` ise `"formality":"prefer_less"`; bağlam varsa `"context": "<önceki 3 satır, satır sonuyla>"`.
- Yanıt `translations[].text`; sayı tutmazsa hata.
- Hata: 401/403 anahtar geçersiz, 456 kota bitti, diğer ulaşılamadı. Hata sonrası 60 sn denenmez, satır cihaz içine.
- Zaman aşımı 4 sn.
- **Terim etiketi** (yalnız hedef `tr`): sözlük terimi Türkçesiyle değiştirilip `<x>…</x>` içine alınır, metin XML
  için kaçışlanır (`& < >`); istekte `tag_handling: xml`, `ignore_tags: ["x"]`. Bir cümle etiketliyse istekteki
  bütün cümleler kaçışlanır. Dönüşte etiketler silinir, kaçışlar açılır.
  Örnek: `Ghost climbed the roof.` (sözlükte `keepExact: Ghost`) → giden `<x>Ghost</x> climbed the roof.`
- Kullanım denetimi: `GET …/usage` → `character_count`, `character_limit`; sayaç ≥ sınır ise "kota bitti".
- Önbellek anahtarı: satırda sözlük terimi varsa `<sözlük izi>` + U+001F + satır, yoksa satır.
- DeepL'in desteklediği hedefler: `tr ar id th vi nl` (Hintçe, Urduca, Bengalce, Malayca, Filipince yok).

### NinoCore'da eksik
- DeepL'e özgü XML terim etiketi ve `context` alanı genel sağlayıcıyla anlatılamıyor.
- Kullanım/kota denetimi yok.

## 6. Önbellek

Her motor ve dil çifti **ayrı dosya** kullanır: motor değişince eski motorun çevirisi gösterilmez.

- Klasör: `~/Library/Application Support/Nino/Translations/`.
- Motor adları: cihaz içi `apple-p3` (sondaki sayı metin hattı sürümü; kurallar değişince artar, eski çeviriler
  yeniden yapılır), DeepL `deepl`, yapay zekâ `<hizmet>:<model>` (ör. `gemini:gemini-3.5-flash-lite`), yerel
  `local:<makine>[:<kapı>]/<model>` (ör. `local:localhost:11434/translategemma:4b`).
- **Dosya adı**: motor, kaynak ve hedef yalnız `a-z 0-9 -` içeriyorsa `v1-<motor>-<kaynak>-<hedef>.jsonl`; yoksa
  `v1h-<sha256(motor + "\0" + kaynak + "\0" + hedef), küçük hex>.jsonl`.
  - `apple-p3`, `en`, `tr` → `v1-apple-p3-en-tr.jsonl`
  - `gemini:gemini-3.5-flash-lite`, `en`, `tr` →
    `v1h-1aa82a53a8896bbdf8841c6a44e31bc0ec2a382935938bda14071a3444e0ca98.jsonl`
- **Satır biçimi**: her satır bir JSON dizisi `["anahtar","çeviri"]`, sona eklenir. Boş anahtar/çeviri yazılmaz.
  Bozuk satır atlanır.
- Bellekte en çok 20 000 kayıt; aşılınca en uzun süredir kullanılmayanlardan (sınırın onda biri kadar fazlası) atılır.
- Dosya kayıt sınırının iki katı satıra ulaşınca bellektekilerle (eskiden yeniye) yeniden yazılır. Açılışta dosyadaki
  satır sayısı kayıt sayısını `sınır/2`'den fazla aşıyorsa da yeniden yazılır.
- Dosya ilk kullanımda okunur. Aynı dosya için uygulamada tek önbellek nesnesi vardır.
- Aynı çeviri yeniden yazılırsa dosyaya eklenmez (yalnız "kullanıldı" işareti tazelenir).
- Disk hatası çeviriyi durdurmaz: önbellek bellekte çalışır.

**Anahtarlar**:
- Cihaz içi: cümle; bağlamla çevrildiyse `bağlam` + U+001F + `cümle`; cümlede/bağlamda sözlük terimi, hazır satır ya
  da argo kuralı varsa başına `<sözlük izi>` + U+001F.
- Yapay zekâ: satır ve her cümle ayrı; oyun biliniyorsa `<oyun adı>` + U+001F + metin (oyun bilinmiyorsa eski düz
  kayıtlar geçerli; biliniyorsa yalnız o oyununki).
- DeepL: §5.

**Önbellek ölçümü** (günlük için): bir istekte kaç parça önbellekten geldi, hangi motor yeni çeviri yazdı.
Sonuç metni: `çeviri:<motor>` (yeni çevrildi), `önbellek` (hepsi önbellekten), bilinmiyorsa `çeviri:motor`.

### NinoCore'da eksik
- NinoCore tek dosya (`translations.json`, 50 000 kayıt, JSON listesi) ve tek anahtar (sadeleştirilmiş cümle)
  kullanıyor. Eski dosyaları okuyamaz: motor/dil başına dosya, `v1-…`/`v1h-…` adları, JSONL `[anahtar, çeviri]`
  biçimi, oyun ve sözlük izi ön ekleri yok.
- Motor değişince önbelleğin ayrılması yok (bir sağlayıcının çevirisi ötekine karışır).
- Metin hattı sürümü (kurallar değişince yeniden çevir) yok.
- Önbellek ölçümü (`çeviri:<motor>` / `önbellek`) yok.

## 7. Terimler

### 7.1 Uydurma adla koruma (cihaz içi çeviri)

Terim, çeviriden önce uydurma bir özel adla değiştirilir. Neden: çevirmenler özel adı olduğu gibi bırakıp Türkçe
ekini kesmeyle ekliyor (`Torvek'i al`); `[[1]]` gibi işaretleri ise düşürebiliyor.

- Ad listesi (sırayla): `Torvek, Mirdal, Haskor, Belmuk, Ravdin, Sorkel, Gundar, Vestar`. Kaynak metinde (bağlamda
  da) geçen ad kullanılmaz. Ad biterse kalan terimler korunmaz.
- Aynı terim aynı adı alır. Bağlamla birlikte çevrilen satırda bağlamın terimleri de aynı listeden ad alır.
- Geri koyma: ad + isteğe bağlı ek, kesmeyle (`Torvek'e`, `Torvek 'e`, `` ` ´ ' ’ ``) veya ek doğrudan ada yapışık (`Torveke`);
  büyük/küçük harf fark etmez; harf/rakamla bitişik değil.
- Ek terime göre yeniden kurulur (§7.5). Cümle başındaysa (önünde yalnız boşluk, tırnak, tire, `(`, `¡ ¿` ya da
  cümle sonu var) ilk harf Türkçe kurala göre büyütülür.
- Beklenen ad çıktıda yoksa **ya da** bu cümleye ait olmayan bir ad (bağlamınki) çıktıda kaldıysa sonuç geçersiz.
- Kaynakta `’` varsa eklerde de `’` kullanılır.

Örnekler (sözlük: `Ashford` ad, `stamina tonic` → `dayanıklılık iksiri`):

| Motor çıktısı | Sonuç |
|---|---|
| `Mirdal'a git.` (Mirdal=Ashford) | `Ashford'a git.` |
| `Torvek'i iç. Önce Torvek!` (Torvek=stamina tonic) | `Dayanıklılık iksirini iç. Önce dayanıklılık iksiri!` |
| `İki kez 'Torvek' diye fısıldadı.` (Torvek=Ashford) | `İki kez 'Ashford' diye fısıldadı.` |
| `Yola çıkıyoruz.` (ad bekleniyordu) | geçersiz → korumasız yeniden çeviri |

### 7.2 Sözlük dosyası

JSON (json5 izinli). Alanlar:

```json
{
  "game": "Ember Saga",
  "terms": { "Frost Lance": "Ayaz Mızrağı" },
  "keep": ["Orrin", "Nadia"],
  "keepExact": ["Echo"],
  "phrases": { "(?:pop|light) (?:a )?flares?(?! gun)": "fire a flare" },
  "lines": { "taking fire": "Ateş altındayım" }
}
```

- `terms`: İngilizce → Türkçe. `keep`: olduğu gibi kalır. `keepExact`: olduğu gibi kalır ama yalnız aynı büyük/küçük
  harfle geçince (`Echo` ad, `echo` yankı).
- Terim eklenmez: harf içermiyorsa, Türkçesi boşsa, İngilizcesi 80 UTF-16 birimden uzunsa. İç boşluklar teklenir.
- Eşleşme: tam sözcük (iki yanı harf/rakam değil), büyük/küçük harf fark etmez (`keepExact` hariç), **uzun terim
  önce**, çakışan kısa terim alınmaz. Aynı uzunlukta alfabetik.
- `phrases`: anahtar düzenli ifade, `\b(?: … )\b` içinde, büyük/küçük harf fark etmez, anahtar bayt sırasıyla
  uygulanır; bozuk ifade alınmaz. Eşleşmenin ilk harfi büyükse karşılığınki de büyür. `Aggro the guards` →
  `Provoke the guards` (kural `aggro` → `provoke`).
- `lines`: satır anahtarı = küçük harf, `’ ‘` → `'`, tek boşluk, baştaki/sondaki harf-rakam dışı atılmış. Birebir
  eşleşirse çevirmene gitmez. Türkçe son noktalamasızsa kaynağın sonundaki `. ! ? …` dizisi eklenir.
  `Taking fire!` → `Ateş altındayım!`
- Büyük harfle yazılmış terimlerin (≥ 2 harfli) sözcükleri "büyük kalacak ad" sayılır (`keepExact` hariç).

### 7.3 Sözlük kaynakları

- Uygulamayla gelen genel sözlük (NinoCore `BuiltinGlossary`, Nino'nun kendi seçtiği girişler): 10 terim, 2 `keep`
  (`NPC`, `DLC`), 1 `keepExact` (`Ghost`), 9 argo kuralı, 15 hazır satır (nişancı/aksiyon oyunu ünlemleri).
- Kullanıcı klasörü `~/Library/Application Support/Nino/Glossary/*.json`, ad sırasıyla üstüne eklenir; aynı terimde
  sonraki kazanır. Bozuk dosya atlanır.
- Klasöre en çok 5 sn'de bir bakılır; dosyaların yol/boyut/değişiklik zamanı değiştiyse yeniden okunur.
- Sözlük yalnız `en`→`tr`'de kullanılır.

### 7.4 Sözlük izi

Terim içeren satırın önbellek anahtarına girer; sözlük değişince o satırlar yeniden çevrilir. Hesap (Windows ile
aynı, birebir korunmalı): FNV-1a 32 bit, başlangıç `2166136261`, çarpan `16777619`, UTF-8 baytları üstünde.
1. Terimler küçük harfli İngilizcelerinin bayt sırasıyla: `ingilizce_küçük + U+0001 + türkçe + (exact ise U+0003) + U+0002`.
2. `phrases` anahtar bayt sırasıyla: `anahtar + U+0004 + karşılık + U+0005`.
3. `lines` anahtar bayt sırasıyla: `anahtar + U+0006 + türkçe + U+0007`.
Sonuç: `g` + 8 haneli küçük hex. Boş sözlük `g811c9dc5`.

### 7.5 Türkçe ekin kurulması

Motorun yer tutucuya koyduğu ek (kesmesiz) gerçek terime göre yeniden kurulur.

- Ek harf dışı karakter içeriyor ya da 12 harften uzunsa ek sayılmaz: `terim + kesme + ek` aynen.
- Baştaki kaynaştırma harfi yer tutucuya göreydi, atılır: `y` + ünlü/`l` (`ya` → `a`), `n` + dar ünlü + `n`
  (`nın` → `ın`).
- Son sözcüğün son harfi ve son ünlüsüne bakılır. Ünlüsüz kısaltma (`NPC`) ince ve ünlüyle biten sayılır.
- Tamlama: terim çok sözcüklü, dar ünlüyle bitiyor, son sözcük ≥ 3 harf → hâl ekinden önce `n`.
- Ünlüyle başlayan ek: tamlamada ya da ünlüyle biten terimde ilgi eki (`ın`) ise `n`; ünlüyle biten terimde `y`.
- `d`/`t` ile başlayan ek: tamlamada `n` + `d`; sert ünsüzle (`f s t k ç ş h p`) biten terimde `t`, değilse `d`.
- `la/le` (çoğul `lar` değil): ünlüyle biten ya da tamlamada `y`.
- Ünlü uyumu: `a/e` kalın/ince; dar ünlü kalın-düz `ı`, kalın-yuvarlak `u`, ince-düz `i`, ince-yuvarlak `ü`.
  Sondaki `-ki` değişmez.
- Özel ad (büyük harfle başlayan terim): kesmeyle. Cins ad: bitişik; ek ünlüyle başlıyor ve araya harf girmiyorsa
  son `p/ç/k` yumuşar (`b/c/ğ`), `nk` → `ng`; tek heceli sözcük yumuşamaz.

Örnekler (testlerden):

| Terim + ek | Sonuç |
|---|---|
| Orrin + da | Orrin'de |
| Orrin + nın | Orrin'in |
| Nadia + u / un / la | Nadia'yı / Nadia'nın / Nadia'yla |
| Westport + daki | Westport'taki |
| Elif + ya | Elif'e |
| Ejder Kılıcı + u / da | Ejder Kılıcı'nı / Ejder Kılıcı'nda |
| ateş oku + u | ateş okunu |
| ağaç / dolap / yaprak / çelenk / ip + u | ağacı / dolabı / yaprağı / çelengi / ipi |
| kapı + u, zırh + la | kapıyı, zırhla |
| NPC + u | NPC'yi |
| Westport + A | Westport'a |
| Orrin + un (kaynakta ’) | Orrin’in |

### NinoCore'da eksik
- NinoCore `⟦0⟧` yer tutucusu kullanıyor; uydurma ad yöntemi, ek yeniden kurma ve cümle başı büyütme yok. (Not:
  NinoCore'un `⟦n⟧` için cihaz içinde "korunuyor, denendi" notu var; ama ek, kesmeyle `⟦0⟧'a` gibi gelirse
  `Ashford'a` kurulmaz.)
- `keepExact`, `phrases`, `lines`, sözlük izi, kullanıcı sözlük klasörünü izleme, genel sözlük dosyası yok.
- "Bu cümleye ait olmayan ad çıktıda kaldı → geçersiz" kuralı yok.
- NinoCore'da paket terimleri var (paket biçimi farklı, `havuz-paketler.md`); eski paketlerde terim yok, terimler
  sözlükte.

## 8. Türkçe düzeltme (yalnız cihaz içi çeviride, hedef `tr`)

Yalnız anlamı değiştirmeyen biçim kuralları:

### 8.1 Cümle düzeltme
Çeviride harf yoksa dokunulmaz. Sırayla:
1. Tırnaklar: kaynakta `“ ”` varsa çevirideki düz `"` kıvrık olur (önü boş/boşluk/`( [ - – —` ise `“`, değilse `”`);
   yoksa çevirideki `“ ” „ ‟` düz `"` olur. Tek tırnak aynı mantıkla (`‘ ’` / `'`).
2. Noktalamadan (`, . ! ? ; : …`) önceki boşluk/sekme silinir.
3. Çoklu boşluk teklenir, baş/son kırpılır.
4. Son işaret: kaynağın sonu `!`, `?`, `…` ya da `...` içeriyorsa ve çevirinin sonu farklıysa (boş, `.` ya da başka
   ifadeli işaret) kaynağınki konur. Kaynakta son işaret tırnağın içindeyse ve çeviride değilse (ya da tersi)
   dokunulmaz. Kaynak `.` ile bitiyorsa çeviriye dokunulmaz.

| Kaynak | Çeviri | Sonuç |
|---|---|---|
| `Run!` | `Koş.` / `Koş` | `Koş!` |
| `What?!` | `Ne?` | `Ne?!` |
| `Wait…` | `Bekle.` | `Bekle…` |
| `Where is he?` | `O nerede.` | `O nerede?` |
| `He said "Run!"` | `"Koş." dedi.` | `"Koş." dedi.` |
| `"Run!"` | `"Koş."` | `"Koş!"` |
| `We go.` | `Gidiyoruz!` | `Gidiyoruz!` |
| `Okay. Go.` | `Dur , bekle !` | `Dur, bekle!` |
| `Fine. Move.` | `Pekâlâ ... yürüyelim .` | `Pekâlâ... yürüyelim.` |
| `She said "hide", Orrin's sister.` | `“Saklan” dedi, Orrin’in kız kardeşi.` | `"Saklan" dedi, Orrin'in kız kardeşi.` |

### 8.2 Sözlüğün hazır satırı
Hazır satır da 8.1'den geçer.

### 8.3 Hitap (satır bütünü)
Satırın cümlelerinden birinde `sen, seni, sana, senin, sende, senden, seninle, senle` geçiyorsa, `siz…` sözcüğü
(`siz, sizi, size, sizin, sizde, sizden, sizinle, sizler`) geçmeyen cümlelerdeki bilinen "siz"li emirler "sen"li
olur. Emir yalnız ardından noktalama (`! . , ? …`) ya da satır sonu geliyorsa değişir. Baş harf büyükse büyük kalır.
Liste: dikkat edin, acele edin, ateş edin, yardım edin, takip edin, sessiz olun, hazır olun, sakin olun, bekleyin,
durun, gelin, koşun, gidin, bakın, dinleyin, saklanın, kaçın, savaşın, dövüşün, durdurun, çekilin, eğilin,
atlayın, tutun, bırakın, söyleyin, gösterin, getirin, kalkın, odaklanın, yaklaşın, uzaklaşın. (`Alın` bilerek yok.)

| Cümleler | Sonuç |
|---|---|
| `Sana söyledim.` · `Bekleyin!` · `Dikkat edin, evlat.` | `Sana söyledim.` · `Bekle!` · `Dikkat et, evlat.` |
| `Seni buldum. Çabuk saklanın!` | `Seni buldum. Çabuk saklan!` |
| `Bekleyin!` (tek) | değişmez |
| `Siz saklanın, seni sonra ararım!` | değişmez |
| `Sen gelin misin?` | değişmez |

### NinoCore'da eksik
`Sources/NinoCore/Translation/TurkishPostProcessor.swift` farklı kurallar uyguluyor; eski davranışla çelişenler:
- NinoCore `…`'yı `...` yapıyor; eski kod `…`'yı korur ve kaynağın `…`'sını geri koyar.
- NinoCore kaynak `.` ile bitince çeviriye `.` ekliyor; eski kod yalnız ifadeli sonları (`! ? … ...`) düzeltir ve
  çevirinin `!`'ini `.` yapmaz.
- NinoCore ilk harfi büyütüyor; eski kodda bu yok (yalnız terim cümle başındaysa).
- NinoCore `..` → `.` yapıyor; eski kodda yok.
- Eski kodda olup NinoCore'da olmayan: tırnak türünü kaynağa uydurma, kapanış tırnağı/parantez içindeki son işaret
  kuralı, hitap (sen/siz) kuralı.
- Hangisinin kalacağına karar verilmeli; eski kurallar Windows ile ortak testlere sahip.

## 9. Hedef diller

### 9.1 Liste

Kodda **11** dil var (görev tanımında 12 yazıyor; kodda ve sunucuda 11):

| Kod | Ad | İstemdeki İngilizce ad | DeepL |
|---|---|---|---|
| tr | Türkçe | Turkish | var |
| ar | العربية | Arabic | var |
| hi | हिन्दी | Hindi | yok |
| id | Bahasa Indonesia | Indonesian | var |
| th | ไทย | Thai | var |
| vi | Tiếng Việt | Vietnamese | var |
| ur | اردو | Urdu | yok |
| bn | বাংলা | Bengali | yok |
| ms | Bahasa Melayu | Malay | yok |
| tl | Filipino | Filipino | yok |
| nl | Nederlands | Dutch | var |

- Dil kodu ilk iki harf, küçük harf. Filipince `tl` tutulur (`fi` Fince sanılmasın); arayüz dili `fil`.
- İlk açılışta: sistem dili listedeyse o (`fil…` → `tl`), değilse `tr`.
- Arayüz dili çeviri dilini izler.
- Sağdan sola: `ar fa he ur`. Arap harfi içeren gösterimde her paragrafın başına U+200F konur (zaten varsa
  eklenmez), böylece `NADIA: …` ile başlayan satır da sağdan sola dizilir.
- Sözlük, ekler, Türkçe düzeltme ve oyun paketleri **yalnız `tr`**'de. Çevrimiçi motorlar ve havuz hepsinde.
- Havuz önceliği yalnız sunucunun izin verdiği dillerde (varsayılan yalnız `tr`).
- Deneme ekranı için her dilde üç örnek satırın çevirisi uygulamada sabit (`tr` ve `ar` dışındaki dillerde).

### 9.2 "Zaten hedef dilde" denetimi

Satır çevirmene gitmeden önce (PS5'in Türkçe menüleri boşa çevrilmesin):
1. Hedefe özgü harf (`tr`: `ı İ ğ Ğ ş Ş`) varsa → hedef dilde. **İstisna**: bu harf yalnız tek bir sözcükte, geri
   kalan ≥ 3 sözcük (2+ harfli) dil tanıyıcıya göre ≥ 0.90 kaynak dilde ise kaynak dildedir (OCR tuş simgesini harf
   sanıp sözcüğe yapıştırmış: `Sure beats jailsır`).
2. Hedef `ar` ya da `ur` ve metinde Arap harfi var → hedef dilde.
3. Kendi yazısı olan dil (`th` U+0E00–0E7F, `hi` U+0900–097F, `bn` U+0980–09FF) ve o yazının harfi var → hedef dilde.
4. 2+ harfli sözcük sayısı ≥ 3 ise dil tanıyıcı (yalnız hedef ve kaynak arasında) hedefe ≥ 0.90 → hedef dilde.
5. Değilse çevrilir.

Çeviri sonrası: sadeleştirilmiş kaynak ile çeviri benzerliği ≥ 0.90 ise "zaten hedef dilde" sayılıp gösterilmez.
**İstisna**: paketten gelen satır, kaynakta Türkçe harf (`ğışçöüĞİŞÇÖÜ`) yoksa aynı olsa da gösterilir (isim, ünlem).

Bloğun herhangi bir satırı hedef dildeyse blok konsolun ekranıdır (okuma hattı kullanır).

### NinoCore'da eksik
- Hedef dil listesi, istem adları, DeepL desteği, sağdan sola gösterim, ilk açılış dili seçimi yok (NinoCore
  `targetLanguage` serbest metin).
- "Zaten hedef dilde" denetimi (önce ve sonra) yok.
- "Yalnız `tr`'de sözlük/paket/düzeltme" ayrımı yok; NinoCore Türkçe son düzeltmeyi her hedefte uyguluyor
  (`Sources/NinoCore/Translation/Translator.swift` hedefe bakmadan son düzeltmeyi çağırıyor).
