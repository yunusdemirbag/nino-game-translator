# Çevirmenler (Providers)

Kod: `Sources/NinoCore/Providers/`. Kullanıcının kendi anahtarıyla çalışan
çevirmenler, ücretsiz havuz sorusu ve bunların çevresindeki yardımcılar.
`Translation/` klasöründeki hiçbir dosyanın davranışı değişmez; buradakiler
yanına eklenir.

## Ağ

Bütün istekler `ProviderTransport` arayüzünden geçer (`URLSession` buna uyar).
Testler sahte taşıyıcı kullanır; gerçek ağa çıkılmaz. Kodda anahtar yoktur.

## Sağlayıcılar

Her biri NinoCore'un `TranslationProvider` arayüzüne uyar (tek cümle). Asıl iş
çok cümleli yöntemdedir: cümle listesi + bağlam + oyun adı → aynı sırada liste.

| Sağlayıcı | Adres | Anahtar | Zaman aşımı |
|---|---|---|---|
| bulut A (Gemini) | `…/v1beta/models/<model>:generateContent` | `x-goog-api-key` | 5 sn |
| bulut B (OpenAI) | `…/v1/chat/completions` | `Authorization: Bearer` | 5 sn |
| bulut C (Claude) | `…/v1/messages` + `anthropic-version: 2023-06-01` | `x-api-key` | 5 sn |
| yerel model | `<adres>/chat/completions` | boş değilse Bearer, boşsa başlık yok | 15 sn |
| DeepL | anahtar `:fx` ile bitiyorsa ücretsiz adres | `DeepL-Auth-Key` | 4 sn |
| Nino havuzu | `<sunucu>/v1/translate` (adres ayardan) | yok | 20 sn |

- Gövdeler sıralı anahtarlı JSON. Çıktı sınırı altyazıda 1024.
- Sıcaklık (`temperature: 0.2`) yalnız yerel modelde.
- İstem: sistem yönergesi hedef dile göre (Türkçe, Arapça, diğerleri), kullanıcı
  iletisi: varsa `Game:` satırı, varsa önceki satırlar (yalnız bağlam), sonra
  "şu JSON dizisini çevir, N öğelik dizi döndür" ve dizi.
- Adında `translategemma` ya da `milmmt` geçen yerel model "çeviri modeli"dir:
  yönerge ve JSON gönderilmez, modelin kendi kalıbı kullanılır.
- Yanıt temizliği: son `</think>` sonrası, kontrol işaretleri, kod çiti, ilk `[`
  ile son `]` arası (sondaki `,]` düzelir), tırnaksız dizi, satır satır, tek
  cümlede düz metin. Sayı tutmazsa hata.
- DeepL'de hedef `tr` ise sözlük terimleri `<x>…</x>` içinde gider
  (`tag_handling: xml`, `ignore_tags: [x]`); bağlam `context` alanında;
  `formality: prefer_less`. Kullanım denetimi `GET …/usage`.
- Havuz: `{"v":1,"install","app","platform","lang","game","lines","context"}`
  gönderilir; `translations[].text` (null olabilir) ve `game` okunur. Süreli
  soru: süre dolunca `nil` döner, istek sürer, geç gelen yanıt geri çağrıyla
  verilir.

## Hata türleri

`ProviderFailure`: `invalidKey`, `quotaExhausted`, `minuteLimit(retryAfter:)`,
`modelRejected`, `network`, `server(durum)`, `badResponse`, `notReady`
(dinlenmede ya da dakikalık hak yok: istek hiç gitmedi).

| Durum | Gövde | Tür |
|---|---|---|
| 401, 403 | — | geçersiz anahtar |
| 402 | — | kota |
| 429 | `PerMinute` var, `PerDay` yok | dakikalık sınır (bekleme `retryDelay`, yoksa 20 sn; 1–20 sn) |
| 429 | diğer | kota |
| 400 | `api_key_invalid` / `api key not valid` | geçersiz anahtar |
| 400 | `credit balance` / `insufficient_quota` | kota |
| 400 (diğer), 404 | — | model reddedildi |
| 5xx, diğer | — | sunucu |
| bağlantı hatası | — | ağ |

DeepL'de 456 kotadır. Ana ekran uyarısı `ProviderAlert`'tir (anahtar, kota, ağ,
sunucu, model). Dakikalık sınır ve `notReady` uyarı değildir; satır cihaz içine
düşer. `ProviderHealth` ilk hatada hizmeti 60 sn dinlendirir (dakikalık sınırda
söylenen süre kadar), uyarıyı yalnız değişince bildirir, başarı uyarıyı siler.

## Dakikalık bütçe

`RequestBudget`: model başına kayan 60 sn pencere, uygulama genelinde tek
(`shared`). Sınır 2, istekler t=0 ve t=10 → t=20'de hak yok, t=60'ta var. 429
gövdesindeki `quotaValue` sınırı yalnız düşürür. Anahtar denemesi hak yemez.

## Anahtar deneme

`KeyCheck.run` örnek satırla (`BATMAN: I'm Batman.`, etiket gitmez) bir istek
atar. Sonuç: `valid`, `quotaExhausted`, `modelRejected`, `invalidKey`,
`unreachable`. İlk üçünde anahtar kaydedilir. Anahtar kırpılarak kullanılır.

## Model listesi

`ModelCatalog` yerleşik JSON'dan okunur (Swift dosyasına gömülü metin; paket
tanımına kaynak eklemeden). Biçim: `{"nino-models":1,"services":{"<hizmet>":[…]}}`.
Model alanları: `id`, `label`, `effort`, `thinking`, `freeTier`,
`requestsPerMinute`. İlk model varsayılan; kayıtlı model listede yoksa
varsayılan. Uygulama dışarıdan JSON da verebilir.

## Yerel model sunucusu

Adres düzeltme: boş/boşluklu geçersiz; şema yoksa `http://`; yalnız
http/https; sondaki `/` ve `/chat/completions` atılır; yol yoksa `/v1`; sorgu
ve parça atılır. Kapı 11434 Ollama, 1234 LM Studio. Model adı boşsa ya da eski
`qwen2.5:7b` ise `translategemma:4b`. Kurulu modeller `GET <kök>/api/tags`;
`x` ile `x:latest` aynı. İndirme ilerlemesi satır satır JSON'dan hesaplanır.

## Sözlük (yalnız en→tr)

`Glossary`: `terms`, `keep`, `keepExact`, `phrases`, `lines`. JSON'da yorum ve
sondaki virgül kabul. Terim eklenmez: harfsiz, Türkçesi boş, İngilizcesi 80
UTF-16 birimden uzun. Eşleşme tam sözcük, uzun terim önce, çakışan kısa alınmaz;
`keepExact` yalnız aynı yazılışla. `phrases` düzenli ifade, anahtar bayt
sırasıyla, ilk harf büyükse karşılık da büyür. `lines` birebir hazır satır;
çeviri noktalamasızsa kaynağın son `. ! ? …` dizisi eklenir. Kullanıcı
klasöründeki dosyalar ad sırasıyla üstüne yazılır (`GlossaryFolder`, 5 sn'de
bir yol/boyut/tarih değişti mi diye bakar).

Sözlük izi: FNV-1a 32 bit (terimler `en+\u1+tr[+\u3]+\u2`, sonra phrases
`k+\u4+v+\u5`, sonra lines `k+\u6+v+\u7`, hepsi bayt sırasıyla), `g` + 8 hex.
Boş sözlük `g811c9dc5`.

Yerleşik en-tr sözlüğü (`BuiltinGlossary`) Nino'nun kendi seçtiği girişlerdir:
10 terim, `keep` NPC/DLC, `keepExact` Ghost, 9 argo kuralı, 15 hazır satır.
Eski dosyanın hiçbir girişi yoktur; izi de farklıdır.

## Oyun deyimleri (her hedefte)

Çeviriden önce kalıp düz İngilizceye: `hit the deck→lie flat`, `haul tail→
run fast`, `we're toast→we are finished`, `waste 'em→kill them`,
`go loud→start shooting`, `radio silence→no talking`, `out of juice→out of power`,
`hold the fort→defend this place`, `bought the farm→died`.
Tam sözcük, büyük/küçük fark etmez, baş harf büyükse karşılık da büyük.

## Uydurma adla terim koruma (cihaz içi)

Terim `Torvek, Mirdal, Haskor, Belmuk, Ravdin, Sorkel, Gundar, Vestar`
listesinden kaynakta geçmeyen bir adla değiştirilir. Dönüşte ad + ek
(kesmeli, boşluk+kesmeli ya da bitişik) bulunur, ek gerçek terime göre yeniden
kurulur (`TurkishSuffix`), cümle başındaysa ilk harf büyür. Beklenen ad yoksa
ya da bağlama ait ad çıktıda kaldıysa sonuç geçersizdir (çağıran korumasız
yeniden çevirir).

`TurkishSuffix` kuralları: kaynaştırma harfi atılır, ünlü uyumu, tamlamada `n`,
ünlüyle biten terimde `y`, sert ünsüzden sonra `t`, özel adda kesme, cins adda
yumuşama (`p ç k → b c ğ`, `nk → ng`; tek heceli sözcük yumuşamaz ama `nk`
yumuşar: `renk → rengi`).

## Kısa satır bağlamı

Harfli sözcük sayısı 1–3 olan cümle önceki cümleyle `önceki *** kısa` olarak
çevrilir. Önceki = aynı satırdaki önceki cümle, yoksa en çok 20 sn önce
gösterilen satırın son cümlesi. Çıktıdan `***` sonrası alınır; `***` tam bir
kez değilse, `****` varsa, bir yan harfsizse ya da sonrası `3×kaynak+20`
UTF-16 biriminden uzunsa alınmaz.

## "Zaten hedef dilde" denetimi

Önce: hedefe özgü harf (`tr`: `ı İ ğ Ğ ş Ş`; tek sözcükteyse ve geri kalan ≥3
sözcük ≥0.90 kaynak dildeyse istisna), Arap harfi (`ar`, `ur`), kendi yazısı
(`th`, `hi`, `bn`), ≥3 sözcükte dil tanıyıcı hedefe ≥0.90. Dil tanıyıcı
arayüz arkasında (`LanguageGuesser`; varsayılanı NaturalLanguage). Sonra:
kaynak ile çeviri benzerliği ≥0.90 ise gösterilmez; paketten gelen ve kaynakta
Türkçe harf olmayan satır istisna. Aynı ölçü yankı denetiminde de kullanılır.

## Hedef diller

`tr ar hi id th vi ur bn ms tl nl` (11). Kod ilk iki harf; Filipince `tl`
tutulur, arayüz dili `fil`. DeepL: `tr ar id th vi nl`. Sağdan sola: `ar fa he
ur`; Arap harfli paragrafa U+200F konur. İlk açılışta sistem dili listedeyse o,
değilse `tr`.

## Motor başına önbellek

`EngineCacheStore` her (motor, kaynak, hedef) için ayrı `EngineCache` açar;
mevcut `TranslationCache`'e dokunmaz. Dosya adı `v1-<motor>-<kaynak>-<hedef>.jsonl`
(yalnız `a-z 0-9 -` varsa), yoksa `v1h-<sha256(motor\0kaynak\0hedef)>.jsonl`.
Satır `["anahtar","çeviri"]`. Bellekte 20 000; aşılınca en eskiler (fazlası +
onda biri) atılır. Dosya 2×sınır satıra ulaşınca ya da açılışta fazlalık
sınır/2'yi geçince yeniden yazılır. Aynı çeviri yeniden eklenmez. Disk hatası
çeviriyi durdurmaz. Motor adları: `apple-p3`, `deepl`, `<hizmet>:<model>`,
`local:<makine>[:<kapı>]/<model>`. Anahtar ekleri (oyun, sözlük izi, bağlam)
U+001F ile.

## Eski Türkçe kuralları ve NinoCore farkları

`ClassicTurkishRules` eski davranışı verir (yalnız cihaz içi, hedef `tr`):
tırnak türü kaynağa uyar; noktalamadan önceki boşluk silinir; boşluk teklenir;
son işaret yalnız kaynak `! ? … ...` ile bitiyorsa kaynağınkiyle değişir,
tırnak içi/dışı uyuşmazsa dokunulmaz; hitap kuralı (satırda "sen" varsa "siz"
emirleri tekile iner).

`Translation/TurkishPostProcessor.swift` (değiştirilmedi) ile farklar:

| Konu | TurkishPostProcessor | ClassicTurkishRules |
|---|---|---|
| `…` | `...` yapar | korur; kaynağın `…`'sını geri koyar |
| kaynak `.` ile bitiyor | çeviri noktasızsa `.` ekler | dokunmaz |
| çeviri `!`, kaynak `.` | dokunmaz | dokunmaz |
| çeviri `.`, kaynak `!`/`?` | dokunmaz (son harf işaret) | kaynağınkini koyar (`Koş.` → `Koş!`) |
| baş harf | kaynak büyükse büyütür | dokunmaz |
| `..` | `.` yapar | dokunmaz |
| virgülden sonra boşluk | ekler | eklemez |
| tırnak türü | dokunmaz | kaynağa uydurur |
| hitap (sen/siz) | yok | var |
| hedef dil | her hedefte (Translator) | yalnız `tr` |

Hangisinin kullanılacağına uygulama karar verir.
