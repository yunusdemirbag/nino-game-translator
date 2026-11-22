# Mac ↔ havuz sunucusu (nino-pool) uyumu

22 Kasım 2026. Yeni Mac uygulamasının (NinoMacKit + NinoCore) havuz sunucusuna gönderdiği isteklerin sunucu
kodundaki doğrulamayla karşılaştırılması. Sunucu kaynağı: `nino-pool/src/` (yönlendirme `worker.js`). Sunucuya
dokunulmadı; uyuşmazlıklar istemcide düzeltildi. Sözleşme testleri:
`apps/mac/NinoMacKit/Tests/NinoMacKitTests/ServerContractTests.swift` ve
`~/Desktop/NinoCore/Tests/NinoCoreTests/PoolServerContractTests.swift`.

Sunucu adresi: `https://nino-pool.y-demirbag2506.workers.dev` (`PoolServer.liveURL`); `NINO_POOL_URL` / `ninoPoolURL`
ile değişir. İndirme sayacı (`DownloadCounterService`) bu ayara bakmaz, her zaman canlı adrese gider.

## Özet

| Uç nokta | İstemci | Durum |
|---|---|---|
| `POST /v1/batches` | NinoCore `PoolQueue` | uyuyordu |
| `GET /v1/config` | NinoCore `PoolClient.refreshConfig`, Mac `DownloadCounterService` | uyuyordu |
| `GET /v1/translations` | NinoCore `PoolClient.sync` | uyuyordu |
| `POST /v1/translate` | NinoCore `PoolClient.ask`, `NinoPoolProvider` | **düzeltildi** (oyun kimliği, 300 karakter) |
| `GET /v1/ping` | NinoCore `PoolClient.ping` | uyuyordu |
| `POST /v1/reports` | Mac `ReportClient` | **düzeltildi** (`logs` → `log`, sınırlar) |
| `POST /v1/assistant` | Mac `AssistantClient` | uyuyordu |
| `POST /v1/identify` | Mac `GameIdentifyClient` | **düzeltildi** (gövde boyu) |
| Satır anahtarı (`key.js`) | NinoCore `LineKey` | **düzeltildi** (işaret harfleri) |
| `POST /v1/events` | NinoCore `Telemetry` | **sunucuda yok** (404; istemci saklayıp bekliyor) |
| `GET /v1/packs`, `/v1/packs/<id>` | NinoCore `PackUpdater` | **nino-pool'da yok** (404; paketler hiç inmiyor) |
| Güncelleme | Mac `GitHubUpdateChecker` | havuz sunucusuna gitmez (GitHub Releases API); karşılaştırılacak sözleşme yok |

## Açık konular (sunucu tarafı, istemciyle çözülmez)

1. **Paketler.** `LiveEngineEnvironment.live` paket adresini (`NINO_PACKS_URL` / `ninoPacksURL` yoksa) havuz
   adresine eşitliyor ("paketler havuzdan iner" kararı), ama nino-pool'da `/v1/packs` yok: her bakış 404, paket hiç
   inmez (uygulama paketsiz çalışır, bozulmaz). İstemcinin beklediği biçim ayrı paket Worker'ının (`server/packs`,
   `nino-packs`) biçimiyle aynı (`{"packs":[{id,title,version,sha256,…}]}`, kimlik `^[a-z0-9][a-z0-9-]{0,63}$`).
   Çözüm: ya nino-pool'a `/v1/packs` eklenir ya da Mac'e `nino-packs` adresi varsayılan olarak verilir (adres burada
   doğrulanamadı; tahmin edilmedi).
2. **Ölçüm.** `POST /v1/events` nino-pool'da yok. İstemci 404'ü "sunucu henüz yayında değil" sayar: parçayı saklar,
   1 dk → 1 sa artan aralıkla yeniden dener, silmez. Uç nokta yayına alınınca kendiliğinden gönderir.
3. **Tanıma ve yardımcı canlıda kapalı olabilir.** Canlı `wrangler.toml`'da `CLAUDE_ENABLED = "0"`: `/v1/identify`
   503 `disabled` döner; istemci bunu "tanınmadı" sayar. Yardımcı anahtarı (Gemini) yoksa `/v1/assistant` 503
   `assistant_disabled` → "kapalı" balonu.
4. `/v1/config` → `minVersion.mac` Mac'te okunmuyor (alan zararsız).
5. Hedef dil diskteki ayardan denetimsiz okunuyor (`MacSettings+Coding`); yeni uygulama yalnız 11 sunucu dilini
   yazar. Eski bir ayar dosyasında listede olmayan bir kod varsa havuz istekleri 400 `bad_lang` alır (zararsız:
   çeviri havuzdan gelmez, uygulama kendi motoruyla sürer).

## Uç noktalar

### POST /v1/batches (satır gönderme)

| | İstemci (`PoolQueue`) | Sunucu (`validate.js` checkBatch/checkLine, `pool.js`) |
|---|---|---|
| Başlıklar | `Content-Type: application/json`, `User-Agent: nino-pool/1 (mac; <sürüm>)` | içerik türüne bakmaz |
| Gövde sınırı | ≤ 200 satır (≤ 500 × 4 bayt) | ≤ 512 KB, ≤ 500 satır (fazlası 413 `too_many_lines`) |
| `v` | 1 | 1 değilse 400 `unknown_version` |
| `batch` | küçük harf UUID | UUID değilse 400 `bad_batch_id` |
| `install` | UUID (`pool/state.json`) | UUID değilse 400 `bad_install` |
| `app`, `platform` | sürüm, `"mac"` | `app` 40'a kırpılır; bilinmeyen platform `other` |
| `lines[].text` | `PoolFilter.prepare`: temizlenmiş, ≤ 500 kod noktası, harfli | ≤ 500 kod noktası, harf şart; değilse satır `rejected` |
| `lines[].game` | `GameName.id` (yoksa alan hiç yok) | `^[a-z0-9][a-z0-9._-]*$`, ≤ 64; değilse satır `bad_game` |
| `lines[].session` | küçük harf UUID | UUID değilse satır `bad_session` |
| `lines[].count/first/last` | tam sayı ≥ 1 / unix sn | tam sayı 1…100 000 / 2024'ten şimdi+1 güne kıstırılır |
| `upTo` | istemci için | yok sayılır |
| 200 | `ok == true` ve `batch` aynıysa parça silinir; `rejected[{i,reason}]` `rejected.jsonl`'a | `{ok, batch, accepted, rejected}`; yinelenende `duplicate: true` |
| 413 | parça ikiye bölünür (tek satırsa kenara) | `too_many_lines`, gövde `too_large` |
| 429 / 503 | `Retry-After` kadar bekler | `install_rate` (900 sn), `daily_budget` (ertesi gün), 503 `server` (60 sn) |
| 400 / 422 | parça kenara (`parked/`) | gövde bozuk |

### GET /v1/config

| | İstemci | Sunucu (`remoteConfig`) |
|---|---|---|
| Sorgu | yok | yok; `cache-control: public, max-age=300` |
| `PoolClient` | `ok == true` şart; `translate.{enabled, deadlineMs, syncSeconds, contextLines, maxLines}`, `poolFirst.{games, langs, deadlineMs}` | aynı adlar |
| `DownloadCounterService` | `downloads` (sayı > 0), en çok 10 dk'da bir | `downloads` yalnız saklanan değer varsa gelir |
| Not | `translate.enabled: false` iken `PoolClient.ask` hiç sormaz | `enabled` = ücretsiz zincir ya da Claude açık |

### GET /v1/translations

| | İstemci (`PoolClient.sync`) | Sunucu (`listTranslations`) |
|---|---|---|
| Sorgu | `lang` (11 dilden biri), `since` (tam sayı), `game` (`GameName.id`, yoksa alan yok), `after` (16 hex, varsa) | `lang` değilse 400 `bad_lang`; `game` `^[a-z0-9][a-z0-9._-]{0,63}$` değilse 400 `bad_game`; `since` parseInt; `after` 16 hex değilse yok sayılır |
| 200 | `ok == true`; `items[[key, text, updated, tier?]]`; `next {since, after}` ya da null | aynı; sayfa 4000 satır |
| Hata | 200 dışı: tur biter, imleç ilerlemez | — |

### POST /v1/translate

| | İstemci | Sunucu (`handleTranslate`) |
|---|---|---|
| Başlıklar | `Content-Type: application/json`, `User-Agent` | gövde ≤ 64 KB |
| `v`, `install` | 1, UUID | değilse 400 `bad_request` / `bad_install` |
| `lang` | `PoolClient`: hedef dil kodu; `NinoPoolProvider`: `TargetLanguage.normalize` | ilk parça, 11 dilden biri; değilse 400 `bad_lang` |
| `game` | `GameName.id` ya da `""` | `^[a-z0-9][a-z0-9._-]{0,63}$` değilse sessizce `""` |
| `lines` | `PoolClient`: tek satır, ≤ 300 kod noktası | 1…12 (fazlası 413); > 300 kod noktası çevrilmez (`text: null`) |
| `context` | ≤ `contextLines` (4), son 30 sn | son 4, ≤ 300 kod noktası olanlar |
| `app`, `platform` | sürüm, `"mac"` | kurulum kaydı |
| 200 | `translations[0].text` (boş/null: çeviri yok), `game` (havuz önceliği için hatırlanır) | `{ok, translations:[{text, tier}], game?, limited?}` |
| Hata | 200 dışı: `nil` (sağlayıcıda `ProviderFailure.server`) | 400/413 |

**Düzeltilen:** `NinoPoolProvider` oyun adını olduğu gibi gönderiyordu ("Grand Theft Auto VI"); sunucu bunu biçime
uymadığı için sessizce `""` yapıyordu. Artık `GameName.id` ile kimlik gider. `PoolClient.ask` 300 kod noktasından uzun
satırı artık hiç sormuyor (sunucu zaten çevirmiyordu).

### GET /v1/ping

| | İstemci | Sunucu (`handlePing` → `touchInstall`) |
|---|---|---|
| Sorgu | `install`, `platform=mac`, `app`, `game` (kimlik ya da boş), `lang` | `install` UUID değilse sessizce hiçbir şey yazılmaz; `game` biçime uymazsa boş |
| Cevap | okunmaz | 204 |

### POST /v1/reports (Sorun Bildir, otomatik bildirim)

| | İstemci (`ReportContract`) | Sunucu (`receiveReport`) |
|---|---|---|
| Başlıklar | `Content-Type: application/json`, `User-Agent: nino-report/1 (mac; <sürüm>)` | — |
| Gövde sınırı | **4 MB** (aşarsa gönderilmez, `tooLarge`) | 4 MB (413 `too_large`) |
| `v` | 1 | 1 değilse 400 `bad_report` |
| `install` | kurulum UUID'i | 8–64 karakter, değilse 400 `bad_report` |
| `platform` | `"mac"` | 6 platformdan biri, değilse 400 `bad_platform` |
| `text` | açıklama + boş satır + tespitler; **≤ 4000 UTF-16, tespitler kesilmez** (açıklama kısaltılır) | ilk 4000 tutulur; boşsa 400 |
| `log` | **`log`** (eskiden `logs`), günlüğün **son** 60 000 UTF-16 birimi | `log`, ilk 60 000 tutulur |
| `app`, `language` | her zaman | 40 / 16'ya kırpılır |
| `contact`, `device` | boşsa alan yok | 200 / 600'e kırpılır |
| `images` | ≤ 3 × `{mime: "image/jpeg", data: base64}` (≈ 900 KB) | ≤ 3 (400 `too_many_images`); jpeg/png/webp/heic; ≤ 1500 KB (413 `image_too_large`) |
| `kind` | `user` / `auto` | yok sayılır |
| 2xx | `ok == false` değilse başarı | `{ok: true, id}` |
| 429 | `dailyLimit` | `rate_limited` (kurulum başına günde 10) |
| 413 | `tooLarge` | `too_large`, `image_too_large` |
| diğer | `server` | 400, 503 |

**Düzeltilen:** sunucu `log` alanını okuyor, istemci `logs` gönderiyordu: günlük hiç kaydedilmiyordu. Gövde sınırı
12 MB'tan 4 MB'a, günlük 120 000 karakterden 60 000 UTF-16 birimine indi (sunucu başı tuttuğu için istemci sonunu
gönderir; en yeni satırlar kalır). `text` 4000'i aşınca sunucu sonunu (tespitleri) kesiyordu; artık açıklama kısaltılır.

### POST /v1/assistant (Nino'ya Sor)

| | İstemci (`AssistantContract`) | Sunucu (`validateConversation`, `handleAssistant`) |
|---|---|---|
| Başlıklar | `Content-Type: application/json`, `User-Agent: nino-assistant/1 (mac; <sürüm>)` | gövde ≤ 6 MB (413) |
| Alanlar | `v` 1, `install`, `app`, `platform` mac, `language`, `device` (varsa), `messages` | aynı adlar; `install` 8–64 |
| `messages` | ≤ 24; ilk mesaj kullanıcınınsa başlar, son mesaj kullanıcının | son 24 alınır; son mesaj `user` olmalı |
| `text` | ≤ 2000 UTF-16 | 2000'e kırpılır |
| `images` | yalnız kullanıcı mesajında, mesaj başına ≤ 3, yalnız son 2 fotoğraflı mesajda (≤ 6) | jpeg/png/webp, ≤ 1500 KB; toplam ≤ 6 (400 `too_many_images`) |
| 200 | `reply` (boş değil), `report` (bildirim kimliği ya da null) | `{ok, reply, report}` |
| 400 | `rejected` | `bad_request`, `bad_platform`, `bad_image`, `too_many_images` |
| 413 | `tooLarge` | `too_large`, `image_too_large` |
| 429 | `error == "busy"` → `busy`, değilse `dailyLimit` | `rate_limited` (kurulum başına günde 60), `busy` (günlük bütçe/harcama) |
| 503 | `assistant_disabled` → `disabled`, değilse `busy` | `assistant_disabled`; yakalanmayan hata 503 `server` |
| 502 | `serverError` | `model_failed`, `refused` |

`GET /v1/assistant` (`{ok, enabled}`) Mac'te kullanılmıyor; kapalılık POST cevabından anlaşılıyor.

### POST /v1/identify (ekrandan oyun tanıma)

| | İstemci (`GameIdentifyClient`) | Sunucu (`handleIdentify`) |
|---|---|---|
| Başlıklar | `Content-Type: application/json` | gövde ≤ 600 KB (413 `too_large`) |
| Alanlar | `v` 1, `install` (UUID), `app`, `platform` mac, `image` (base64 JPEG) | `install` UUID değilse 400; `image.length × 0,75` ≤ 450 KB (413) |
| Resim | ≤ 768 px genişlik, JPEG 0,6 / 0,45 / 0,3; **≤ 440 KB**, gövde ≤ 600 KB değilse gönderilmez | `iVBOR` ile başlıyorsa PNG, değilse JPEG |
| 200 | `game` (boş değilse temizlenmiş ad) | `{ok, game \| null, id, confidence}` (güven ≥ 0,7) |
| diğer | `nil` | 429 `rate` (günde 30), 503 `disabled` |

**Düzeltilen:** 450 KB'lık JPEG base64 ile tam 600 KB eder; JSON zarfıyla gövde 600 KB'ı geçip 413 alırdı. Üst sınır
440 KB'a indi ve gövde boyu gönderimden önce denetleniyor.

### Satır anahtarı (`key.js` ↔ `LineKey`)

Sunucu satır anahtarını metinden kendisi hesaplar; istemci aynı anahtarla havuz çevirisini bulur. Sunucu bütün
birleşen işaretleri (`\p{M}`: Mn, Mc, Me) atıyordu; istemci yalnız Mn'yi atıyor, Mc/Me'yi ayraç sayıyordu
(`काम` sunucuda `कम`, istemcide `क म`). İngilizce satırlarda fark doğmaz; yine de istemci sunucuya uyduruldu ve
sunucunun çıktısı (node ile alındı) teste kondu.

### Ölçüm (`POST /v1/events`) ve paketler (`/v1/packs`)

Bkz. "Açık konular" 1–2. İstemcinin istek biçimleri değişmedi.

## Yerel deneme (22 Kasım)

Sunucu kodunun kopyasıyla (`wrangler dev --local --port 8799`; yapay zekâ bağlaması, zamanlayıcı ve çeviri motoru
yok, model anahtarı yok; yerel D1'e bir çeviri ve indirme sayısı konarak) iki istemci testi çalıştırıldı. Canlı
sunucuya hiç istek gitmedi: testlerin taşıyıcısı yalnız 127.0.0.1/localhost/::1'e izin veriyor, canlı adresi
yerel adrese çeviriyor.

```sh
NINO_LOCAL_POOL_URL=http://127.0.0.1:8799 NINO_LOCAL_POOL_SEEDED=1 swift test --filter PoolServerContractTests   # NinoCore
NINO_LOCAL_POOL_URL=http://127.0.0.1:8799 NINO_LOCAL_POOL_SEEDED=1 swift test --filter ServerContractTests       # NinoMacKit
```

Sonuç: `POST /v1/batches` 200, `GET /v1/config` 200 (sayaç 4321'i okudu), `GET /v1/translations` 200 (konan çeviri
indi), `POST /v1/translate` 200 (havuzdaki satır döndü; HTTP üstünden yalnız `NinoPoolProvider` ile, çünkü yerel
ayar `translate.enabled: false` verdiği için `PoolClient.ask` doğru olarak hiç sormadı; Mac'in kullandığı
`PoolClient.ask` gövdesi yalnız birim testinde denetlendi), `GET /v1/ping` 204, `POST /v1/reports` 200 (kayıtta `log`
ve fotoğraf var), `POST /v1/assistant` 503 → "kapalı", `POST /v1/identify` 503 → tanınmadı. Model anahtarı olmadığı
için yardımcı ve tanıma gövdeleri ayrıca sunucunun `handle()` işlevinden (taklit modelle, ağsız) geçirildi: üçü de
200 (`assistant`: 3 mesaj, ilkinde 1 fotoğraf; `identify`: Grand Theft Auto VI; `reports`: id).
