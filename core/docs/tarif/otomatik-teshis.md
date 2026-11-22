# Otomatik teşhis: uygulamanın kendi sorununu fark edip bildirmesi

Her Nino uygulamasında küçük bir **bekçi** çalışır. Bekçi aşağıdaki kurallardan biri tetiklenince o anın teknik
özetini çıkarır, muhtemel sebebi koddan seçer ve ölçüm kanalıyla (`/v1/events`, `k: "diag"`) gönderir. Sunucu aynı
sorunları gruplar; panelde en sık sorunlar, yeni çıkan sorunlar ve sürüm sonrası artışlar görünür. Kullanıcı hiçbir
şey yapmadan ürün iyileşir.

- Taşıma, kuyruk, sıkıştırma, yeniden deneme, `ctx`: ölçüm tarifiyle aynı (`docs/tarif/olcum.md`).
- Sunucu: `nino-pool/src/diag.js`, tablo `0019_diag.sql`; panel "Otomatik teşhis" ve günlük özet sayfası `/teshis`.
- Örnek senaryolar ve beklenen bildirimler: `nino-pool/test/fixtures/diag-scenarios.json`.
- Ölçümün parçasıdır: ayrı bir kapatma düğmesi yoktur (kullanıcı kararı); sunucu `telemetry.diag` ile kural kural
  kapatabilir ya da eşikleri değiştirebilir.

## Gizlilik (ölçümle aynı, pazarlıksız)

- **Serbest metin yok.** Günlük satırı, hata mesajı, istisna metni, dosya yolu, ağ adresi, cihaz/TV/PS5 adı, altyazı
  metni gitmez. "Günlüğün son kısmı" yerine **iz** gider: tetikten önceki son adımlar, her biri yalnız
  `[kaç saniye önce, kod, sayı?]`.
- Uygulama günlüğü yalnız kullanıcı **kendisi** Sorun Bildir'e basıp "günlüğü ekle"yi açık bıraktığında gider
  (`/v1/reports`). Otomatik teşhis hiçbir zaman günlük göndermez (ana oturum kararı, 22 Kasım).
- Teşhis cümlesi uygulamada yazılmaz: uygulama `cause` **kodu** gönderir, cümle bu tariften (aşağıdaki tablo) panelde
  ve uygulamanın kendi ekranında üretilir.
- `state` yalnız sayı, doğru/yanlış ve kod içerir (ör. `"net": "wifi"`, `"memMB": 410`).
- Kurulum kimliği sunucuda yalnız tuzlu özetle, sınırlar ve "kaç farklı kurulum" sayımı için 3 gün tutulur.

## Olay biçimi

```json
{ "k": "diag", "t": 1763303600, "rule": "ps5.no_return", "cause": "network_lost", "sev": "warn",
  "state": { "ps5": "down", "tv": "up", "net": "wifi", "sessionMin": 42, "lines": 310, "fps": 0, "memMB": 410 },
  "trail": [[-240, "net.change", 1], [-236, "ps5.drop"], [-200, "ps5.retry", 1], [-120, "ps5.retry", 2], [-30, "net.down"]],
  "tv": { "brand": "androidtv", "model": "TCL 98U95A", "app": "4.0.0" },
  "game": "gta-vi",
  "ver": { "core": "1.0.0", "remoteplay": "2.1.0" } }
```

| Alan | Kural |
|---|---|
| `rule` | aşağıdaki kural kodlarından biri (yeni kural eklenebilir, biçim `[a-z0-9_.]`, en çok 40) |
| `cause` | o kuralın sebep kodlarından biri; bilinmiyorsa `unknown` |
| `sev` | `info` · `warn` · `error` |
| `state` | en çok 30 anahtar; anahtar `[A-Za-z0-9_]{1,24}`; değer tam sayı, ondalık, `true/false` ya da kod kuralına uyan kısa dizgi (≤ 40) |
| `trail` | en çok 40 adım, eskiden yeniye; `[saniye (−3600…0), kod, sayı?]`. Kod, ölçümdeki hata kodu kuralıyla aynı |
| `tv` | biliniyorsa marka, **model** (ad değil) ve TV'deki Nino sürümü |
| `game` | oyun kimliği (havuz biçimi), bilinmiyorsa yok |
| `ver` | bileşen sürümleri (en çok 6): `core`, `remoteplay`, `ocr`, `tvApp`… |

Kurala uymayan alan atılır; `rule` geçersizse olay atılır.

### İz (`trail`) kodları

Uygulama, bekçinin baktığı olayları bellekte son 10 dakikalık bir halka tamponda tutar (en çok 200 adım); bildirimde
son 40'ı gider. Önerilen kodlar: `session.start` `session.stop` `ps5.connect` `ps5.drop` `ps5.retry` `ps5.frame`
(sayı: fps) `tv.connect` `tv.drop` `net.up` `net.down` `net.change` `ocr.slow` (sayı: ms) `ocr.empty` `tr.slow` (ms)
`tr.error` (HTTP durumu) `tr.ok` `ocr.text` (yazı okundu) `pack.fail` `app.background` `app.foreground` `sys.sleep` `sys.wake` `mem.high` (MB)
`cpu.high` (%) ve ölçümdeki bütün hata kodları.

## Genel kurallar (her bekçi)

- **Susturma:** Aşağıdakilerden biri son 2 dakikada olduysa kural tetiklenmez (ya da sayaç sıfırlanır):
  bilgisayar uyudu/uyandı, uygulama arka plana geçti (telefon/TV), kullanıcı çeviriyi kendisi durdurdu, uygulama
  yeni açıldı (ilk 60 sn). Ağ tamamen gittiyse ağ dışı kurallar susar; ağ kuralı ağ gelince gönderilir (kuyruk zaten
  bekletir).
- **Tek kök, tek bildirim:** Aynı 5 dakika içinde birden çok kural tetiklenirse yalnız önceliği en yüksek olan gider
  (öncelik: `app.hang` > `ps5.no_return` > `tv.flapping` > `ocr.stalled` > `tr.errors` > `tr.slow` > `ocr.silent` >
  `app.resources` > `pack.download`); öbürleri iz adımı olarak eklenir.
- **Sınırlar:** aynı kural bir oturumda en çok 1 kez; kurulum başına günde en çok 5 bildirim, aynı kural günde en
  çok 2. Sunucu da günde 10 / kural başına 3 üstünü sessizce atar. `diag`, ölçümün günlük olay sınırından (`maxPerDay`)
  muaftır (çökme gibi).
- **Uzaktan ayar:** `/v1/config` → `telemetry.diag`: `{ "off": ["ocr.silent"], "limits": { "tr.slow.p90Ms": 4000 } }`.
  Bilinmeyen anahtarlar yok sayılır; yoksa aşağıdaki varsayılanlar.

## Kurallar

Her kural: tetik (varsayılan eşikler), bağlam (`state` anahtarları), sebep seçimi, önem.

### `ps5.no_return`: PS5 koptu, geri gelmedi
- **Tetik:** çeviri oturumu sürerken PS5 bağlantısı koptu ve `ps5NoReturnSec` (180 sn) içinde yeniden kurulamadı.
- **Bağlam:** `ps5` `net` (`wifi`/`ethernet`/`cellular`/`none`) `sessionMin` `retries` `lastFps` `lostPackets`.
- **Sebep:** cihazın ağı gitti → `network_lost`; PS5 dinlenmeye geçti → `ps5_standby`; PS5 oturumu kapattı →
  `ps5_closed`; başka cihaz bağlandı → `kicked`; görüntü durdu → `stalled`; bunların hiçbirine işaret yoksa (PS5'ten
  veri gelmedi) → `timeout`. Tetik anı: kopma + 180 sn.
- **Önem:** `error`.

### `tv.flapping`: TV bağlantısı tekrar tekrar kopuyor
- **Tetik:** `tvFlapWindowMin` (10 dk) içinde `tvFlapCount` (3) kopma; tetik anı 3. kopma.
- **Susturma istisnası:** bu kurala **arka plan susturması uygulanmaz**: arka plana gidip gelme (`resume`) kopmanın
  kendisi sayılır. Yalnız açılışın ilk 60 sn'si, uyku/uyanma ve kullanıcının durdurması susturur.
- **`resume` sayılan kopma:** uygulamanın öne gelişinden (`app.foreground`) sonraki 10 sn içindeki kopma (bağlantı
  katmanı sebebi kendisi biliyorsa o geçerli). `replaced`: bağlantının yerini başka bir bağlantı aldı (aynı TV yeniden bağlandı ya da TV başka göndericiye
  geçti); karşı taraf `{"app":"nino","type":"error","code":"replaced"}` bildirdiyse. TV uygulaması da kendi tarafında aynı kuralı
  çalıştırır (`platform` TV olur).
- **Bağlam:** `drops` `net` `tvCount` (bağlı TV sayısı) `proto` (`nino`/`legacy`) `avgUpSec`.
- **Sebep:** kopmaların çoğunun nedeni: `write_error` · `timeout` · `closed` · `resume` · `network_change` · `replaced`; karışıksa
  `mixed`.
- **Önem:** `warn`.

### `ocr.silent`: görüntü geliyor ama hiç yazı okunmuyor
- **Tetik:** oturum sürerken görüntü kareleri geliyor (≥ 1 kare/sn), ama `ocrSilentMin` (15 dk) boyunca yazı tanıma
  **hiç** metin döndürmedi. (Diyalogsuz oynanış çok olur: tek bir satır bile okunduysa sayaç sıfırlanır.)
- **Bağlam:** `fps` `frameLuma` (0–255 ortalama parlaklık) `frameSame` (kareler aynı mı) `region` (`auto`/`manual`)
  `ocrMs`.
- **Sebep:** kareler kararık (`frameLuma` ≤ 16) ya da hep aynı (`frameSame`) → `video_black`; okuma alanı elle seçilmiş → `region_wrong`; aksi →
  `no_text`.
- **Önem:** `info`.

### `ocr.stalled`: yazı tanıma ya da görüntü akışı takıldı
- **Tetik:** yazı tanıma isteği `ocrStallSec` (10 sn) içinde dönmedi (5 dk'da 3 kez) ya da PS5 bağlıyken 30 sn hiç
  kare gelmedi.
- **Bağlam:** `ocrMs` (son), `queue` (bekleyen kare), `fps` `memMB` `cpu`.
- **Sebep:** `ocr_hang` · `frames_stopped` · `decoder`.
- **Önem:** `error`.

### `tr.slow`: çeviri gecikmesi yüksek
- **Tetik:** son 50 satırda (en az 20) `tr.total` p90 > `trSlowP90Ms` (3000 ms).
- **Bağlam:** `p50` `p90` `provider` (en çok kullanılan çevirmen) `poolShare` `providerShare` `ocrP90`.
- **Sebep:** çevirmen payı yüksek ve yavaş → `provider_slow`; havuz yavaş → `pool_slow`; yazı tanıma da yavaş →
  `device_busy`; aksi → `network_slow`.
- **Önem:** `warn`.

### `tr.errors`: çeviri hizmeti ya da havuz sık hata veriyor
- **Tetik:** son 40 istekte (en az 10) hata oranı > `trErrorRate` (%30). Her istek sonucundan (`tr.ok` / `tr.error`)
  sonra bakılır; koşulun ilk sağlandığı an tetiklenir (ör. 8 hata + 2 başarı: 10. istekte).
- **Bağlam:** `errors` `requests` `provider` `http` (en sık durum).
- **Sebep:** 429 → `quota`; 401/403 → `auth`; ağ yok → `offline`; 5xx → `server`; zaman aşımı → `timeout`.
- **Önem:** `warn`.

### `app.hang`: uygulama askıda kaldı
- **Tetik:** ana iş parçacığı `hangSec` (5 sn) boyunca yanıt vermedi (izleyici iş parçacığıyla ölçülür), ya da önceki
  çalışma, çalışma işaretinin "hâlâ çalışıyorum" damgası 60 sn'den eskiyken ve kapanış olmadan bitti (bir sonraki
  açılışta gönderilir; `crash` olayından ayrı). Web TV'lerde (webOS, Tizen) kapanış anı bilinemediği için yalnız canlı
  ölçüm yapılır (sayfa görünürken donma).
  Android'de önceki çalışmanın askıda bitmesi sistemin ANR kaydıyla zaten `crash` (`code: anr`) olarak gider; ayrıca
  `app.hang` gönderilmez (çift sayılmasın).
- **Bağlam:** `blockedSec` `memMB` `cpu` `sessionMin`.
- **Sebep:** `main_thread` · `unknown`.
- **Önem:** `error`.

### `app.resources`: bellek ya da işlemci aşırı
- **Tetik:** bellek > `memHighMB` (masaüstü 1500, telefon 800, TV 400) ya da işlemci > %90, 2 dk boyunca. Telefon /
  TV'de işletim sisteminin bellek uyarısı da sayılır.
- **Bağlam:** `memMB` `cpu` `thermal` (`nominal`/`fair`/`serious`/`critical`) `sessionMin`.
- **Sebep:** `memory_high` · `cpu_high` · `thermal`.
- **Önem:** `warn`.

### `pack.download`: oyun paketi indirilemedi
- **Tetik:** aynı paket art arda 3 kez ya da 24 saattir indirilemedi.
- **Bağlam:** `attempts` `http` `sizeKB`.
- **Sebep:** `offline` · `http_4xx` · `http_5xx` · `corrupt` · `storage_full`.
- **Önem:** `warn`.

## Teşhis cümleleri (`rule` + `cause`)

Uygulamanın kendi ekranında ve panelde aynı anlamla gösterilir (her dil kendi çevirisini yazar).

| Kural | Sebep | Cümle |
|---|---|---|
| ps5.no_return | network_lost | Cihazın ağ bağlantısı gitti; PS5'e yeniden ulaşılamadı. |
| ps5.no_return | ps5_standby | PS5 dinlenme moduna geçti. |
| ps5.no_return | ps5_closed | PS5 Remote Play oturumunu kapattı. |
| ps5.no_return | kicked | Başka bir cihaz PS5'e bağlandı. |
| ps5.no_return | timeout | PS5'ten veri gelmedi; ağ yavaş ya da PS5 yanıt vermiyor. |
| ps5.no_return | stalled | Görüntü durdu ve toparlanmadı. |
| tv.flapping | write_error | TV'ye gönderim tekrar tekrar başarısız oldu. |
| tv.flapping | timeout | TV bir süre yanıt vermedi; Wi-Fi zayıf olabilir. |
| tv.flapping | closed | TV bağlantıyı kapatıyor. |
| tv.flapping | resume | TV uygulaması arka plana gidip geri geliyor. |
| tv.flapping | network_change | Ağ değişiyor (Wi-Fi ↔ kablo ya da adres değişti). |
| tv.flapping | replaced | TV bağlantısının yerini tekrar tekrar yeni bir bağlantı alıyor (TV yeniden bağlanıyor ya da başka cihaza geçiyor). |
| tv.flapping | mixed | TV bağlantısı farklı sebeplerle kopuyor. |
| ocr.silent | video_black | Görüntü kararık ya da donuk; altyazı okunamıyor. |
| ocr.silent | region_wrong | Elle seçilen okuma alanında yazı yok. |
| ocr.silent | no_text | Uzun süredir ekranda okunacak yazı bulunamadı. |
| ocr.stalled | ocr_hang | Yazı tanıma yanıt vermiyor. |
| ocr.stalled | frames_stopped | PS5'ten görüntü karesi gelmiyor. |
| ocr.stalled | decoder | Görüntü çözücü takıldı. |
| tr.slow | provider_slow | Seçilen çeviri hizmeti yavaş yanıt veriyor. |
| tr.slow | pool_slow | Nino çeviri havuzu yavaş yanıt veriyor. |
| tr.slow | device_busy | Cihaz yoğun; yazı tanıma da yavaşladı. |
| tr.slow | network_slow | İnternet bağlantısı yavaş. |
| tr.errors | quota | Çeviri hizmetinin kullanım hakkı doldu. |
| tr.errors | auth | Çeviri anahtarı kabul edilmiyor. |
| tr.errors | offline | İnternet yok; çeviri hizmetine ulaşılamıyor. |
| tr.errors | server | Çeviri hizmeti hata veriyor. |
| tr.errors | timeout | Çeviri hizmeti zamanında yanıt vermiyor. |
| app.hang | main_thread | Uygulama birkaç saniye donup kaldı. |
| app.resources | memory_high | Uygulama çok bellek kullanıyor. |
| app.resources | cpu_high | Uygulama işlemciyi uzun süre yoğun kullanıyor. |
| app.resources | thermal | Cihaz ısındı, sistem yavaşlatıyor. |
| pack.download | offline | Oyun paketi internet olmadığı için inmedi. |
| pack.download | http_4xx | Oyun paketi sunucuda bulunamadı. |
| pack.download | http_5xx | Paket sunucusu hata veriyor. |
| pack.download | corrupt | İnen oyun paketi bozuk. |
| pack.download | storage_full | Cihazda yer kalmadı. |
| (her kural) | unknown | Sebep belirlenemedi. |

## Sunucu ve panel

- Her bildirim bir **imzaya** düşer: `rule + platform + uygulama sürümü + model` (TV kurallarında TV modeli, öbürlerinde
  `ctx.device`). Sürümden bağımsız **grup** (`rule + platform + model`) "yeni çıkan sorun" için kullanılır.
- Panel "Otomatik teşhis": en sık sorunlar (adet, kaç farklı kurulum, sebep dağılımı, sürümler), **yeni çıkan
  sorunlar** (grubun ilk görüldüğü an son 48 saat), **sürüm sonrası artış** (aynı platformda en yeni sürümün açılış
  başına bildirim oranı bir önceki sürümün 2 katından fazla; iki tarafta da en az 20 açılış, yenide en az 3 bildirim).
- `/teshis`: günlük özet sayfası. Günün grupları, sebepleri, örnek bildirimlerin `state` ve `trail`'i; Nino
  yardımcısının modeliyle (şu an Gemini) her grup için kısa Türkçe özet ("ne oluyor, muhtemel sebep, ne yapılmalı").
  Özet gece bakımında yalnız değişen gruplar için, günde en çok 10 grup yazılır; elle `POST /v1/diagnoses/summarize`.
- Saklama: örnek bildirimler (imza başına günde en çok 3) 30 gün, günlük toplamlar 400 gün, kurulum özeti 3 gün.

## Uygulama başına yapılacaklar

1. Halka tampon iz (son 10 dk, 200 adım) ve bekçi: yukarıdaki kurallar, varsayılan eşikler, susturma ve öncelik.
2. Eşikleri ve kapatılan kuralları `telemetry.diag`'dan oku.
3. Tetiklenince `diag` olayını ölçüm kuyruğuna ekle (günlük sınırdan muaf; kendi sınırları geçerli).
4. Uygulamanın "Sistem sağlığı" ekranında son teşhisleri cümle tablosuyla göster (isteğe bağlı).
5. `diag-scenarios.json` senaryolarını birim testi olarak çalıştır: her zaman çizelgesi için beklenen kural, sebep ve
   tetik anı (`at`). Senaryo ile tarif çelişirse **tarif esastır**; çelişkiyi olcum oturumuna bildirin.
