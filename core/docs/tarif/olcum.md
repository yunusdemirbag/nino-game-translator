# Ölçüm: hata ve performans istatistikleri

Bütün yeni Nino uygulamaları (Mac, iPhone/iPad, Android telefon, Windows, Linux, Android TV, LG webOS, Samsung Tizen)
aynı biçimde ölçer ve aynı yere gönderir. Amaç: hangi uygulamada, hangi sürümde, hangi hatanın ne sıklıkla olduğunu
ve çevirinin aşama aşama ne kadar sürdüğünü görüp ürünü sürekli iyileştirmek.

- Sunucu: `nino-pool` Worker, `POST /v1/events` (kod: `nino-pool/src/events.js`).
- Panel: `/panel` → "Sağlık" bölümü (veri `GET /v1/events/stats`, yönetici anahtarıyla).
- Swift istemcisi: `Sources/NinoCore/Telemetry/` (bu depoda). Öbür diller bu tarife göre kendi istemcisini yazar.
- Örnek gövde: `nino-pool/test/fixtures/events-v1.json`. Her istemcinin testi bu biçimde gövde üretmeli.

## Gizlilik (değişmez kurallar)

- **Gönderilmez:** altyazı metni (okunan ya da çevrilen), ekran görüntüsü, ses, PSN/Xbox kimliği, PS5'in ya da TV'nin
  adı, IP/MAC adresi, ağ adı, dosya yolu, kullanıcı adı, e-posta, serbest yazılı hata mesajı.
- Hatalar yalnız **kod** olarak gider (`ps5.auth.expired`). İstisna metni, yığın izi, `localizedDescription` gitmez:
  içinde dosya yolu, kullanıcı adı, IP olabilir. Sunucu da kodları sıkı karakter kuralıyla süzer (aşağıda).
- Kurulum kimliği: uygulamanın zaten tuttuğu rastgele UUID (havuzdakiyle aynı). Sunucu onu yalnız tuzlu özetiyle,
  yalnız hız sınırı ve "kısa sürede çok kopan TV bağlantısı" uyarısı için 3 gün tutar. Özet tablolarında kurulum
  kimliği yoktur.
- Sunucu IP adresini okumaz, yazmaz.
- Kurulum kimliği ev ağına (TV protokolüne) **gitmez**. TV'nin bağlantıda gönderdiği `id` ayrı, kalıcı bir rastgele
  kimliktir; gönderici onu yalnız aynı TV'yi tanımak için kullanır, sunucuya giden hiçbir şeye yazmaz.
- **Kapatma düğmesi yok** (kullanıcı kararı, 22 Kasım 2026): ölçüm her zaman açıktır, ayarlarda anahtar konmaz.
  Bunun karşılığı yukarıdaki kurallar pazarlıksızdır: yalnız teknik veri, kişisel veri hiç yok. Gizlilik metninde ve
  mağaza etiketlerinde açıkça yazılır (aşağıda). Sunucu `telemetry.enabled = false` ile bütün uygulamalarda ölçümü
  uzaktan durdurabilir; o zaman kuyruklar silinir.

## Gönderim

```
POST https://nino-pool.<hesap>.workers.dev/v1/events     (havuzla aynı kök adres)
content-type: application/json
content-encoding: gzip            (isteğe bağlı; önerilir)
```

### Gövde

```json
{
  "v": 1,
  "batch": "2f6c1c8e-8a43-4b9b-9a3e-1e5f0c7d9a10",
  "install": "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f",
  "ctx": {
    "platform": "mac",
    "app": "4.0.0",
    "os": "macOS 27.0",
    "device": "Mac16,1",
    "tv": "androidtv",
    "channel": "release"
  },
  "events": [
    { "k": "launch", "t": 1763300000 },
    { "k": "ps5_connect", "t": 1763300012, "r": "ok", "ms": 2840, "via": "lan" },
    { "k": "tv_connect", "t": 1763300015, "r": "ok", "ms": 420, "brand": "androidtv", "proto": "nino" },
    { "k": "error", "t": 1763300300, "code": "tr.provider.http", "http": 429, "n": 3 },
    { "k": "session", "t": 1763303600, "dur": 3580, "game": "gta-vi", "src": "remoteplay", "lines": 412,
      "h": { "ocr": { "n": 6, "sum": 410, "max": 140, "h": [0,0,0,1,2,2,0,1] },
             "tr.total": { "n": 4, "sum": 2100, "max": 900, "h": [0,0,0,0,0,0,0,0,1,0,1,1,1] } } }
  ]
}
```

- `batch`: her gönderim parçasının rastgele UUID'si. **Yeniden denemede aynı kalır**; sunucu aynı parçayı iki kez
  saymaz.
- `t`: olay zamanı (Unix saniye). Yalnız sıralama ve 7 günden eski olayları atmak için kullanılır. Günlere bölme
  sunucunun alış zamanına göre yapılır (TV saatleri yanlış olabiliyor).
- Bir parçada en çok **300 olay**. Gövde sıkıştırılmış en çok **64 KB**, açılmış en çok **512 KB**.

### Ortak alanlar (`ctx`)

| Alan | Kural | Örnek |
|---|---|---|
| `platform` | `mac` `windows` `linux` `android` `ios` `androidtv` `webos` `tizen` | `ios` (iPad de `ios`) |
| `app` | uygulama sürümü, `[0-9A-Za-z.+-]`, en çok 24 | `4.0.0`, `4.1.0-beta.2` |
| `os` | işletim sistemi adı + sürümü, `[A-Za-z][A-Za-z0-9 ._()-]`, en çok 40 | `macOS 27.0`, `Android 14`, `Windows 11 26100`, `webOS 23`, `Tizen 8.0` |
| `device` | cihaz **modeli** (kullanıcının verdiği ad değil), `[A-Za-z0-9][A-Za-z0-9 ,._()+-]`, en çok 60 | `Mac16,1`, `iPhone17,2`, `SM-S918B`, `TCL 98U95A` |
| `tv` | gönderen uygulamanın bağlı olduğu TV'nin markası; yoksa boş (panelde açılışlara göre sayılır) | `androidtv` `samsung` `lg` `` |
| `channel` | `release` `beta` `dev` | `release` |

Bilinmeyen platformlu parça reddedilir (400). Öbür alanlar kurala uymuyorsa boş sayılır (ör. "Yunus'un MacBook'u"
saklanmaz). Windows'ta `device` için bilgisayarın adı (`MachineName`) değil, üretici modeli kullanılır.

`channel: "dev"` (Xcode / Android Studio / `dotnet run` ile çalışan geliştirici yapıları, otomatik testler) sunucuya
gidebilir ama **sayılmaz** (cevap `dev: true`): hata ayıklayıcıda durdurmak çökme gibi görünür, istatistikleri bozmasın.

### Cevaplar ve istemcinin davranışı

| Durum | Anlamı | İstemci |
|---|---|---|
| 200 `{ok, accepted, dropped, config}` | alındı (`duplicate: true` olabilir) | gönderilenleri kuyruktan siler, `config`'i uygular |
| 400 | gövde bozuk | parçayı siler (tekrar göndermek işe yaramaz). **Silen tek durum budur.** |
| 413 | çok büyük | parçayı ikiye böler; tek olay bile büyükse siler |
| 429 | hız sınırı | saklar, `retry-after` kadar bekler |
| 404, öbür 4xx, 5xx, ağ yok | sunucu hazır değil (ör. henüz yayınlanmadı) | saklar; `retry-after` varsa o kadar, yoksa 1 dk, 2 dk, 4 dk… en çok 1 saat arayla dener |

Bilinmeyen olay türleri ve alanlar hata değildir: sunucu onları atlar ve `dropped` sayısına ekler.

### Uzaktan ayar

`GET /v1/config` cevabında ve her `/v1/events` cevabında:

```json
"telemetry": { "enabled": true, "sample": 1, "maxPerDay": 1000, "flushSeconds": 600, "diag": { "off": [], "limits": {} } }
```

- `enabled: false` → istemci göndermeyi bırakır ve kuyruğu siler (yeniden açılınca yeniden başlar).
- `sample` (0–1): **süre ölçümleri** (`session.h`) için örnekleme. Kurulum başına sabittir: `fnv1a32(install) % 10000
  < sample × 10000` ise bu kurulum süre gönderir. Hata, bağlantı, çökme ve oturum sayıları **hiç örneklenmez** (oranlar
  bozulmasın).
- `maxPerDay`: istemcinin günde göndereceği en çok olay. Aşılırsa o gün yalnız `crash` ve `diag` gider, öbürleri atılır.
- `diag`: otomatik teşhis kurallarından kapatılanlar ve eşikler (`{ "off": [...], "limits": {...} }`).
- `flushSeconds`: toplu gönderim aralığı.

## Toplu gönderim (istemci)

- Olaylar diskte bir kuyrukta durur (uygulama kapanınca kaybolmaz). Kuyruk en çok **2000 olay**; dolunca en eski
  (çökme olmayan) olay atılır.
- Gönderim: `flushSeconds`'ta bir (varsayılan 10 dk), kuyrukta 100 olay birikince ya da uygulama arka plana geçince /
  kapanırken (kısa zaman aşımıyla). Gönderim sırasında yeni olaylar kuyruğa eklenmeye devam eder.
- Aynı hata kodu art arda geliyorsa birleştirilir: `n` alanı tekrarı sayar (gönderim aralığı içinde).
- Ağ yoksa ya da ölçüm kapalıysa hiçbir şey denenmez.

## Olay türleri (`k`)

| `k` | Ne zaman | Alanlar |
|---|---|---|
| `launch` | uygulama açıldı | `ms`? (soğuk açılış süresi) |
| `session` | çeviri oturumu bitti (durdur, kopma, kapanış) | `dur` sn, `game`, `src`, `lines`, `h` |
| `crash` | önceki çalışma çöktü (bir sonraki açılışta gönderilir) | `code`, `where`?, `ver`, `up`? sn |
| `error` | yakalanan hata | `code`, `http`?, `n`? |
| `ps5_connect` | PS5 bağlantı denemesi bitti | `r`, `ms`, `via` |
| `ps5_drop` | bağlıyken PS5 bağlantısı koptu | `code`, `after` sn |
| `tv_connect` | TV bağlantı denemesi bitti | `r`, `ms`, `brand`, `proto`, `model`?, `tvApp`? |
| `diag` | bekçi bir sorun fark etti (otomatik teşhis) | `rule`, `cause`, `sev`, `state`, `trail`, `tv`, `game`, `ver`: **docs/tarif/otomatik-teshis.md** |
| `tv_drop` | bağlıyken TV koptu | `code`, `brand`, `after` sn, `model`?, `tvApp`? |

- `r`: `"ok"` ya da hata kodu. `ms`: denemenin başından sonuca kadar.
- `via`: `lan` (ev ağı) · `remote` (internet üzerinden) · `xbox`.
- `proto`: `nino` (yeni protokol) · `legacy` (eski 8787).
- `model`: TV'nin modeli (ör. `TCL 98U95A`, `QE65Q80C`, `OLED55C3`; `ctx.device` ile aynı kural, kullanıcının
  verdiği TV adı değil). `tvApp`: TV'deki Nino uygulamasının sürümü. Gönderen (Mac, telefon, Windows) TV'den
  öğrendiyse ekler. **TV'nin kendisi** gönderiyorsa (`androidtv`, `webos`, `tizen`) gerek yok: sunucu modeli
  `ctx.device`'tan, sürümü `ctx.app`'ten, markayı platformdan alır.
- `src`: `remoteplay` · `capture` (görüntü yakalama kartı) · `xbox` · `screen` (ekrandan).
- `game`: oyun kimliği (havuzdaki biçim: `[a-z0-9][a-z0-9._-]{0,63}`), bilinmiyorsa boş.
- `lines`: oturumda ekranda gösterilen çeviri satırı sayısı.
- Kullanıcının kendi isteğiyle durdurması kopma değildir; `ps5_drop` gönderilmez, yalnız `session` gider.

### Süre ölçümleri (`session.h`)

Uygulama her satırın süresini bellekte sabit kovalı bir histograma ekler, oturum bitince tek olayda gönderir.
Her satır için ayrı olay **gönderilmez**.

Kova üst sınırları (ms), herkes için aynı (19 kova; sonuncusu 10 000 ms'den uzun):

```
5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000, ∞
```

Değer `v`, `v ≤ sınır` olan ilk kovaya girer. Histogram: `{ "n": adet, "sum": toplam ms, "max": en büyük ms,
"h": [kova adetleri] }`. Sondaki sıfırlar atılabilir; `h`'nin toplamı `n`'e eşit olmalı (değilse sunucu o ölçümü atar).

| Ölçüm | Başlangıç → bitiş |
|---|---|
| `ocr` | karenin yazı tanımaya verilmesi → yazının dönmesi (kare başına) |
| `tr.cache` | çeviri önbellekten bulundu: arama süresi |
| `tr.pack` | oyun paketinden bulundu: arama süresi |
| `tr.pool` | Nino çeviri havuzundan (sunucudan) geldi: istek süresi |
| `tr.provider` | çevirmenden geldi (DeepL, Gemini, cihaz içi…): istek süresi |
| `tr.provider:<ad>` | aynı, çevirmen adıyla: `deepl` `gemini` `openai` `claude` `groq` `apple` `mlkit` `windows` `free` |
| `tr.total` | satırın ekranda kararlı okunması → çevirisinin ekranda görünmesi (**gecikme**) |
| `first_frame` | PS5 bağlantısının başlaması → ilk görüntü karesi |
| `first_subtitle` | oturumun başlaması → ilk çeviri satırının ekranda görünmesi |

`n` değerleri aynı zamanda satırların nereden geldiğini gösterir (önbellek / paket / havuz / çevirmen). Başarısız
çeviri süre olarak eklenmez, `error` olarak sayılır. Yeni ölçüm adı eklenebilir (`[a-z0-9_.]{1,32}(:[a-z0-9_-]{1,24})?`,
oturum başına en çok 24 ölçüm); sunucu bilmediği adları da saklar.

Sunucu, PS5 ve TV bağlantı sürelerini (`ps5_connect.ms`, `tv_connect.ms`) ve oturum süresini kendisi histograma ekler;
uygulamalar bunları ayrıca `h` içine koymaz.

### Yüzdelikler

p50 / p90 / p99 sunucuda kova toplamlarından hesaplanır: istenen sıradaki değerin düştüğü kova bulunur, kovanın alt ve
üst sınırı arasında doğrusal ara değer alınır (son kova için üst sınır `max`). Uygulamaların yüzdelik göndermesine gerek
yoktur.

## Hata kodları

Biçim: `[A-Za-z0-9_.$-]`, en çok 64 karakter, küçük harf ve noktalı alanlar (`alan.konu.sebep`). Liste kapalı değildir:
yeni kod eklemek serbest, ama önce burada aynı anlamda bir kod var mı bak.

**PS5** (`ps5_connect.r`, `error.code`)

| Kod | Anlamı |
|---|---|
| `ps5.discover.none` | ağda PS5 bulunamadı |
| `ps5.discover.timeout` | arama zaman aşımı |
| `ps5.register.failed` | ilk eşleme (PIN) başarısız |
| `ps5.auth.expired` | PSN girişi/jetonu süresi dolmuş |
| `ps5.auth.rejected` | PS5 kimliği kabul etmedi |
| `ps5.session.timeout` | oturum kurulamadı (zaman aşımı) |
| `ps5.session.busy` | başka bir Remote Play bağlı |
| `ps5.session.standby` | PS5 dinlenme modunda, uyandırılamadı |
| `ps5.remote.blocked` | internet üzerinden bağlantı (NAT) kurulamadı |
| `ps5.stream.decoder` | görüntü çözücü başlatılamadı |
| `ps5.other` | sınıflanmamış |

**PS5 kopma sebebi** (`ps5_drop.code`): `network_lost` (bilgisayarın ağı gitti) · `ps5_closed` (PS5 oturumu
kapattı) · `timeout` (PS5'ten veri gelmedi) · `stalled` (görüntü durdu, toparlanmadı) · `standby` (PS5 uyudu) ·
`kicked` (başka cihaz bağlandı) · `other`.

**TV**: `tv.discover.none` · `tv.connect.refused` · `tv.connect.timeout` · `tv.protocol.mismatch` ·
`tv.overlay.denied` (Android TV katman izni yok) · `tv.other`. Kopma (`tv_drop.code`):

| Kod | Anlamı |
|---|---|
| `timeout` | karşı taraftan bir süre ses yok / bağlantı asılı kaldı |
| `write_error` | gönderilemedi (soket yazma hatası) |
| `closed` | karşı taraf bağlantıyı kapattı (`close`, `tv_closed` da kabul edilir, `closed` sayılır) |
| `resume` | uygulama arka plandan öne geldi, bağlantı yenilendi |
| `network_change` | cihazın ağı değişti (Wi-Fi ↔ kablo, IP değişti) |
| `network_lost` | ağ tamamen gitti |
| `replaced` | bu bağlantının yerini başka bir bağlantı aldı: aynı TV yeniden bağlandı ya da TV başka bir göndericiye geçti. Gönderici kapatmadan önce TV'ye `{"app":"nino","type":"error","code":"replaced"}` yollar |
| `other` | sınıflanmamış |

**Okuma ve çeviri**: `ocr.failed` · `ocr.timeout` · `tr.provider.http` (`http` alanıyla) · `tr.provider.timeout` ·
`tr.provider.quota` · `tr.provider.auth` · `tr.provider.offline` · `tr.pool.unreachable` · `tr.pack.corrupt` ·
`tr.ondevice.missing` (cihaz içi dil modeli yok).

**Uygulama**: `app.settings.corrupt` · `app.storage.full` · `app.update.failed` · `app.capture.denied` (ekran /
kamera izni yok) · `app.network.offline`.

### Çökmeler

- Çökme, panelde **çöken sürümün** (`ver`) altına sayılır; yeniden açılan sürümün değil.
- Bilinen sınır: güncellemeden önce kuyrukta kalan öbür olaylar yeni sürümün `ctx`'iyle gider (az sayıda, önemsiz).
- Her platform aynı yolu izler: **çalışma işareti.** Uygulama açılınca `telemetry/running.json` yazar (sürüm,
  açılış zamanı); düzgün kapanınca siler. Bir sonraki açılışta işaret duruyorsa önceki çalışma çökmüştür → `crash`
  olayı (`ver`: çöken sürüm, `up`: çalışma süresi).
- `code`: biliniyorsa sinyal ya da istisna sınıfı (`SIGSEGV`, `SIGABRT`, `NSInvalidArgumentException`,
  `java.lang.IllegalStateException`, `System.NullReferenceException`, `anr`, `oom`), bilinmiyorsa `unclean_exit`.
  Çökme anında yalnız sınıf adı işarete yazılır (mesajı değil).
- `where`: biliniyorsa uygulamanın kendi kodundaki en üst çerçeve, yalnız sembol adı (`ReadingPipeline.process`).
  Karakterler `[A-Za-z0-9_.:$<>+-]`, en çok 120; boşluk, `/` ve `\` olmaz (dosya yolu gitmesin).
- Apple'da isteğe bağlı: MetricKit'in çökme özetinden yalnız sinyal adı ve uygulama içi sembol alınabilir.
- Android'de: `Thread.setDefaultUncaughtExceptionHandler` sınıf adını işarete yazar; ANR için
  `ApplicationExitInfo.REASON_ANR` → `anr`, `REASON_LOW_MEMORY` → `oom`.
- İşletim sistemi uygulamayı arka planda kapattıysa (iOS bellek, Android süreç ölümü) çökme sayılmaz: işaret arka
  plana geçerken de silinir, öne gelince yeniden yazılır.

## Sunucu tarafı (özet)

- Alım: doğrulama → aynı `batch` daha önce geldiyse sayılmaz → hız sınırı → günlük özet tablolarına eklenir.
- Hız sınırı: kurulum başına günde 1500 olay ve 60 parça; bütün kurulumlar için günde `EVENTS_DAILY_BATCHES`
  (100 000) parça. Aşılınca 429 + `retry-after` (ertesi güne kadar).
- Tablolar (`migrations/0016_events.sql`): `ev_daily` (gün × platform × sürüm × tür × kod × ek boyut: adet),
  `ev_timing` + `ev_hist` (gün × platform × sürüm × ölçüm: adet, toplam, en büyük, kova adetleri), `ev_games`
  (gün × oyun: oturum, süre), `ev_recent` (son 30 günün çökme ve hataları: sürüm, işletim sistemi, cihaz modeli,
  kod; kurulum kimliği yok), `ev_batches` (7 gün), `ev_quota` (3 gün), `ev_tv_daily` (gün × gönderen × TV markası ×
  model × TV uygulama sürümü × sonuç/neden: adet, bağlı kalma süresi), `ev_tv_raw` (TV olayları tek tek, kurulum
  özetiyle, 3 gün: "son 24 saat" ve uyarı için).
- Panel "TV bağlantıları": kopma oranı (kopma / başarılı bağlantı), ortalama bağlı kalma, modele / TV uygulama
  sürümüne / gönderen platforma / nedene göre tablolar, son 24 saatte en çok kopan modeller ve **uyarı listesi**:
  bir kurulum son 1 saatte 3+ ya da son 6 saatte 6+ kez koptuysa (kurulum kimliği gösterilmez).
- Günler Türkiye saatiyle (UTC+3) sayılır, panelin öbür bölümleriyle aynı.
- Özetler 400 gün tutulur; günlük bakımda eskiler silinir.
- Web TV'ler için `/v1/events` ve `/v1/config` CORS'a açıktır (`OPTIONS` ön isteği dahil).

## Mağaza gizlilik etiketleri (ölçüm için)

Ölçüm kapatılamadığı için etiketlerde "zorunlu" olarak işaretlenir. Hiçbiri "izleme" ya da "kimliğe bağlı" değildir.

**App Store (App Privacy) ve `PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes`):**

| Veri türü | Kimliğe bağlı | İzleme | Amaç |
|---|---|---|---|
| Diagnostics › Crash Data (`NSPrivacyCollectedDataTypeCrashData`) | Hayır | Hayır | App Functionality, Analytics |
| Diagnostics › Performance Data (`…PerformanceData`) | Hayır | Hayır | App Functionality, Analytics |
| Diagnostics › Other Diagnostic Data (`…OtherDiagnosticData`) | Hayır | Hayır | App Functionality, Analytics |
| Usage Data › Product Interaction (`…ProductInteraction`): oturum süresi, oyun | Hayır | Hayır | Analytics |
| Identifiers › Device ID (`…DeviceID`): rastgele kurulum kimliği | Hayır | Hayır | App Functionality |

`NSPrivacyTracking = false`, `NSPrivacyTrackingDomains` boş. Kurulum kimliği Apple'ın reklam kimliği değildir, ama
sunucuya gittiği ve 3 gün tutulduğu için dürüst olmak adına "Device ID" olarak beyan edilir.

**Google Play (Veri güvenliği):**

| Play veri türü | Toplanıyor mu | Başkasına veriliyor mu | Kullanıcı kapatabilir mi | Ne için |
|---|---|---|---|---|
| Uygulama bilgileri ve performans › Kilitlenme günlükleri | Evet | Hayır | Hayır (zorunlu) | Uygulama işlevselliği, Analiz |
| Uygulama bilgileri ve performans › Teşhis | Evet | Hayır | Hayır (zorunlu) | Uygulama işlevselliği, Analiz |
| Uygulama etkinliği › Uygulama etkileşimleri (oturum süresi, oyun) | Evet | Hayır | Hayır (zorunlu) | Analiz |
| Cihaz veya diğer kimlikler (rastgele kurulum kimliği) | Evet | Hayır | Hayır (zorunlu) | Uygulama işlevselliği |

Otomatik teşhis (`diag`) aynı satırlara girer (Teşhis / Kilitlenme günlükleri); ek tür gerekmez.
Sunucudaki özetleme için verinin Gemini'ye gitmesi "paylaşım" değil, hizmet sağlayıcı (işleyen) kullanımıdır.

Aktarımda şifrelenir: Evet. Silme isteği: istatistikler kurulumla ilişkilendirilmeden günlük toplamlara dönüştüğü
için tek tek silinecek kayıt yoktur (gizlilik metninde yazar). Windows/Linux/TV mağazalarında da aynı içerik.

## AB (ve KVKK) için risk notu

Kapatma düğmesi olmaması AB kullanıcıları için hukuki bir risk taşır; karar kullanıcınındır, burada yalnız kayda
geçirilir. Avukat görüşü değildir.

- **ePrivacy Direktifi m. 5(3):** cihazda bilgi saklamak ya da cihazdan bilgi okuyup göndermek, kullanıcının istediği
  hizmet için *kesinlikle gerekli* değilse rıza ister. EDPB 2/2023 rehberi telemetri ve çökme raporu gönderimini
  açıkça bu maddenin kapsamında sayıyor; hata istatistikleri genelde "kesinlikle gerekli" kabul edilmez.
- **GDPR:** rastgele kurulum kimliği (tuzlu özetiyle bile) + cihaz modeli takma adlı kişisel veri sayılabilir. Hukuki
  dayanak meşru menfaat (m. 6/1-f) olur; o zaman kullanıcının **itiraz hakkı** (m. 21) vardır, kapatma düğmesi
  olmaması bununla çelişebilir. Gizlilik metninde dayanak, saklama süreleri ve itiraz yolu (e-posta) yazmalı.
- **KVKK (Türkiye):** benzer; açık rıza ya da meşru menfaat ve aydınlatma metni.
- **Risk azaltan şeyler (yapıldı):** IP yok, metin yok, serbest yazı yok, kodlar sunucuda süzülür, kurulum kimliği
  3 gün sonra silinir, kalan her şey kurulumsuz günlük toplam, üçüncü taraf yok.
- **Teşhis özeti ve Gemini:** gruplar Gemini'nin **ücretsiz** katmanıyla özetleniyor. Google ücretsiz katmanda
  girdileri ürün geliştirmek için kullanabildiğini söylüyor; gönderilen yalnız teknik veri (kod, sayı, model) olsa da
  AB açısından işleyen sözleşmesi zayıf kalır. Gerekirse özet kapatılır ya da ücretli katmana geçilir.
- **İleride düşünülebilecekler:** (a) yalnız AB/TR'de ilk açılışta tek ekranlık bilgi + Ayarlar'da gizli "itiraz"
  düğmesi; (b) kurulum kimliği yerine günlük değişen ayrı bir ölçüm kimliği (hız sınırı yine çalışır, günler arası
  bağ kurulamaz; o zaman veri büyük olasılıkla anonim sayılır ve 5(3) dışında kalan kısmı daralır).

## Uygulama başına yapılacaklar

1. Kurulum kimliğini (havuzla aynı UUID) ve `ctx` alanlarını doldur.
2. Ayarlara kapatma anahtarı **koyma** (kullanıcı kararı). Gizlilik ekranında / Hakkında'da "Nino anonim hata ve hız
   istatistikleri gönderir" satırı ve gizlilik metnine bağlantı olsun. Mağaza etiketlerini yukarıdaki tabloyla doldur.
3. Açılışta `launch` + çalışma işareti kontrolü; düzgün kapanışta işareti sil.
4. PS5 ve TV bağlantı noktalarına `*_connect` / `*_drop`; yakalanan hataları koduyla `error`.
5. Okuma hattında ve çeviri zincirinde süreleri oturum histogramına ekle; oturum bitince `session`.
6. Testte üretilen gövdeyi `events-v1.json` biçimiyle karşılaştır.
