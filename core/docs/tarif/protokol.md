# Nino Bağlantı Protokolü (sürüm 1)

Çeviriyi telefondan ya da Mac'ten (gönderici) yerel ağdaki TV uygulamasına
(gösterici) taşıyan protokol. Kod: `Sources/NinoCore/Link/`.

| Parça | Ne |
|---|---|
| `NinoMessage` | Mesajların JSON biçimi |
| `DisplaySession`, `DisplayBoard` | TV tarafı durum makinesi (ağdan bağımsız) |
| `NinoDisplayServer` | TV tarafı sunucu (HTTP + WebSocket, Bonjour yayını) |
| `NinoSender` | Gönderici: el sıkışma, gönderme, ping, yeniden bağlanma |
| `NinoHTTPClient` | Tek seferlik HTTP çağrıları |
| `NinoBrowser` | Bonjour ile TV bulma ve adres çözme |
| `NinoExtensions` (`NinoStyle`, `NinoBox`, `ScreenItem`, `NinoEvent`, `NinoInfo`) | Uzantı mesajları (aşağıda) |
| `NinoSenderIngress` | Gönderici girişi: web TV'ler göndericiye bağlanır (ters yön) |
| `DisplayHub` | Bütün çıkışlara (giden, gelen, eski 8787) tek yerden gönderme |
| `Legacy/LegacyEventServer` | Eski TV uygulamaları için 8787 HTTP + SSE sunucusu ve OBS sayfası |

## Roller

- **TV (gösterici)** dinler. Bir HTTP sunucusu açar; WebSocket da aynı
  sunucudadır.
- **Gönderici** (Mac/telefon) bağlanır.
- Varsayılan bağlantı noktası: **47800** (TCP). Ayarlanabilir.

## TV'yi bulma

1. **Bonjour (mDNS):** TV, `_nino._tcp` hizmetini yayınlar. Hizmet adı TV'nin
   görünen adıdır. TXT kayıtları: `v=1` (protokol sürümü), `id=<TV kimliği>`.
2. **Elle:** Kullanıcı IP adresini yazar. Gönderici `GET /nino/info` ile
   doğrular.

## Genel kurallar

- Tüm mesajlar UTF-8 JSON'dur. Her mesajda `"app": "nino"` ve `"type"` vardır.
- Bilinmeyen alanlar **yok sayılır**. Bilinmeyen `type` gelirse mesaj yok
  sayılır, bağlantı kapanmaz.
- Tek mesaj en fazla **512 KB**'tır (buzlu zemin görseli `cover` için). Büyüğü
  gelirse `too_large` yollanır ve bağlantı kapanır. Göndericiler `cover`
  taşımayan mesajları yine 16 KB altında tutar (`NinoLink.compactMessageBytes`).
  `cover` eklenince mesaj 512 KB'ı aşacaksa gönderici `cover`'ı atar, gerisini
  yollar.
- `version` bir tam sayıdır. Yalnız uyumsuz değişiklikte artar. Yeni isteğe
  bağlı alan eklemek sürümü artırmaz.

## HTTP

| Yol | Ne yapar |
|---|---|
| `GET /nino/info` | TV bilgisi döner (aşağıda) |
| `GET /nino/ws` | WebSocket'e yükseltilir |
| `POST /nino/show` | Tek seferlik gösterme (WebSocket kullanamayanlar için) |
| `POST /nino/clear` | Tek seferlik temizleme |

`GET /nino/info` cevabı:

```json
{ "app": "nino", "type": "info", "version": 1, "versions": [1],
  "name": "Salon TV", "id": "b1f2…" }
```

İsteğe bağlı alanlar (uzantı): `model` (TV markası ve modeli), `appVersion`
(karşı tarafın uygulama sürümü), `role` (`"sender"`: cevap veren bir
göndericidir, TV değil; TV'ler bu alanı yollamaz). `app` adı zarf alanıyla
(`"app":"nino"`) çakıştığı için uygulama sürümü `appVersion` adını taşır.
TV bulan göndericiler `role:"sender"` olan cevabı TV saymaz.

`POST` gövdeleri aşağıdaki `show` / `clear` mesajlarıyla aynıdır. Cevap `200`
ve `{"app":"nino","type":"ok"}`; hata durumunda `4xx` ve `error` mesajı.

## El sıkışma (WebSocket)

Bağlantı açılınca gönderici **ilk** mesaj olarak `hello` yollar:

```json
{ "app": "nino", "type": "hello", "version": 1,
  "device": "Mac", "client": "nino-mac/0.1.0" }
```

TV, sürümü destekliyorsa:

```json
{ "app": "nino", "type": "welcome", "version": 1, "name": "Salon TV" }
```

Desteklemiyorsa hata yollar ve bağlantıyı kapatır:

```json
{ "app": "nino", "type": "error", "code": "version_unsupported",
  "versions": [1] }
```

Gönderici `versions` listesindeki en büyük ortak sürümle yeniden dener; yoksa
kullanıcıya "TV uygulamasını güncelle" der.

- `hello`'dan önce başka mesaj gelirse ya da `app` alanı `nino` değilse TV
  `error` (`code: "bad_handshake"`) yollar ve kapatır.
- 5 saniye içinde `hello` gelmezse TV bağlantıyı kapatır.
- TV aynı anda tek göndericiyi kabul eder. Yeni gönderici gelirse eskisine
  `error` (`code: "replaced"`) yollar ve onu kapatır.

## Mesajlar

### `show` — altyazıyı göster

```json
{ "app": "nino", "type": "show", "id": 42,
  "text": "Buraya gel.", "source": "Come here.",
  "position": "bottom", "durationMs": 0 }
```

- `id`: altyazının numarası (zorunlu).
- `text`: gösterilecek Türkçe metin (zorunlu).
- `source`: İngilizce metin (isteğe bağlı).
- `position`: `bottom` (varsayılan) ya da `top`.
- `durationMs`: `0` ya da yoksa `clear` gelene kadar kalır. Değilse bu süre
  sonra kendiliğinden kalkar.
- Yeni `show` eskisinin yerine geçer.

### `clear` — altyazıyı kaldır

```json
{ "app": "nino", "type": "clear", "id": 42 }
```

- `id` verilirse yalnız ekrandaki altyazı o ise kaldırılır (geç gelen
  `clear` yeni altyazıyı silmesin diye).
- `id` yoksa ekran temizlenir.

### `ping` / `pong` — bağlantı canlı mı

```json
{ "app": "nino", "type": "ping", "t": 1732233600000 }
{ "app": "nino", "type": "pong", "t": 1732233600000 }
```

- Gönderici 5 sn'de bir `ping` yollar. TV aynı `t` ile `pong` döner.
- 15 sn cevap yoksa gönderici bağlantıyı kopmuş sayar, yeniden bağlanır
  (1, 2, 4, 8 sn bekleyerek, en fazla 8 sn).
- TV 20 sn hiç mesaj almazsa ekranı temizler.

### `error`

```json
{ "app": "nino", "type": "error", "code": "bad_message", "message": "…" }
```

Kodlar: `version_unsupported`, `bad_handshake`, `bad_message`, `too_large`,
`replaced`.

## Uzantılar (isteğe bağlı, sürüm 1)

Hepsi isteğe bağlıdır; bilmeyen taraf yok sayar (sürüm artmaz). Adlar ve
değerler eski 8787 olaylarıyla aynıdır. Ondalıklar en çok 4 basamağa
yuvarlanır (`light` 2), kutular 0–1 arasına kırpılır. Kod:
`Link/NinoExtensions.swift`.

**Kutu** (`box`): `{"left", "top", "right", "bottom"}`, karenin oranı (0–1,
üstten/soldan).

### `show` ek alanları

| Alan | Ne |
|---|---|
| `box` | İngilizce altyazının ekrandaki yeri (örtme kipi için) |
| `paragraphs` | `true`: çok parçalı metin (satır sonları korunur) |
| `replace` | `true`: önceki satırın düzelmiş okuması; yığma, yerine koy |
| `light` | Sahne aydınlığı 0–1 (zemin koyuluğu buna göre) |
| `cover` | base64 JPEG: altyazının arkasının bulanık hali (buzlu zemin) |
| `speaker` | Konuşan adı (en çok 60 karakter; uzunu kırpılır). Varsa `text` **adsız** çeviridir |
| `icons` | Metindeki `⟦T1⟧` yer tutucularının tuş simgeleri (aşağıda "Tuş simgeleri") |

**Konuşan adı (`speaker`).** Ad kaynak (İngilizce) satırdan ayrılır ve çevrilmez; böylece büyük
harfi olmayan hedef dillerde (Arapça) de ayrı (sarı) çizilebilir. Gönderici yalnız tek bir baştaki
etiket (`AD: …`) varsa ve "konuşan adlarını göster" açıksa yollar; çok konuşanlı satırda adlar
`text` içinde kalır, `speaker` yok. Gösterici: `text` adla (`Ad:`) başlamıyorsa adı kendisi başa
koyar. Alanı bilmeyen eski gösterici yalnız `text`'i (adsız) gösterir. Eski 8787 yolunda ad
`"Ad: text"` olarak tek metne katılır (`ShowPayload.textWithSpeaker`), ayrı alan gitmez.

### Tuş simgeleri (`icons`; `show`, `screen` öğesi, `region`)

Oyunun satır içindeki kumanda tuşu simgesi (`Hold [D-pad] to interact with your partner`) çeviride
kaybolmasın diye metinde **yer tutucu** `⟦T1⟧` … `⟦T99⟧` durur, simgenin kendisi aynı mesajda ayrı gelir:

```json
{ "app": "nino", "type": "show", "id": 12,
  "text": "Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut",
  "icons": [ { "id": "T1", "name": "dpad-right" } ] }
```

- Geçerli yerler: `show.icons`, `screen` mesajında `items[].icons`, `region.icons`.
- Öğe: `id` (`^T\d{1,2}$`, metindeki yer tutucunun içi) ve **ya** `name` (bilinen tuş, en çok 24 karakter;
  TV temiz vektör çizer) **ya** `png` (oyundan kesilmiş simge, base64 PNG, en çok 200 000 karakter; gönderici
  ≤ 8 KB tutar). İkisi de varsa `name` önce gelir. En çok 8 simge; kurala uymayan öğe atılır.
- Bilinen adlar (büyük/küçük harf farksız): `cross`, `circle`, `square`, `triangle`, `dpad-up`, `dpad-down`,
  `dpad-left`, `dpad-right`, `dpad`, `L1`, `L2`, `L3`, `R1`, `R2`, `R3`, `options`, `create`, `touchpad`.
- Simgesi bulunamayan yer tutucuyu TV hiç göstermez. `⟦sözcük⟧` vurgusu ayrıdır; yer tutucu yalnız `⟦T+sayı⟧`.
- Simge yoksa alan **yazılmaz**; JSON eskisiyle bayt bayt aynıdır.
- **Eski 8787 yolu:** `icons` gitmez; yer tutucu okunur metne döner (`[→]`, `[✕]`, `[L2]`, görüntülüde `[■]`;
  `IconPlaceholders.readable`). Aynı okunur biçim Mac'in kendi pencerelerinde ve günlükte kullanılır.

Kod: `Link/LinkIcons.swift` (`LinkIcon`, `IconPlaceholders`). Simgenin bulunması ve çeviri: oyun-okuma.md §4.4.

### `style` — görünüm

```json
{ "app": "nino", "type": "style", "fontSize": 46, "bottomPercent": 7,
  "placement": "cover", "background": 100, "backgroundShape": "fit",
  "bold": false, "textColor": "white", "displayMode": "inApp",
  "stackPrevious": true, "theme": "classic", "autoSize": true,
  "font": "condensed", "watermark": true }
```

Bütün alanlar isteğe bağlı. `placement`: `cover|above|below|fixed`;
`backgroundShape`: `fit|band` (TV yalnız `band`'ı tanır, gerisi "yazı kadar");
`theme`: `classic|cinema|minimal|glass|contrast|outline`; `font`:
`system|modern|condensed|rounded`; `textColor`: `white|yellow`;
`displayMode`: `inApp|overlay` (yalnız Android TV). Gönderici bağlanınca bir
kez ve değişince yollar; TV son `style`'ı saklar.

### `started` / `stopped`

`{"app":"nino","type":"started"}`: çeviri başladı (balon + rozet).
`stopped`: rozet, altyazı, ekran ve bölge kutuları hemen kalkar.

### `screen` / `screen-clear` — ekran örtüleri

```json
{ "app": "nino", "type": "screen", "durationMs": 120000, "overlay": true,
  "items": [ { "box": {"left":0.1,"top":0.1,"right":0.4,"bottom":0.2},
               "line": 0.03, "text": "Görev", "plain": true } ] }
```

Öğe: `box`, `text`, `line` (satır yüksekliği) ve isteğe bağlı bayraklar
`paragraphs`, `plain`, `italic`, `fill` (`#rrggbb`), `ink` (`#rrggbb`),
`angle` (derece, 1 basamak), `alpha` (0–1, 2 basamak), `side`, `frost`,
`backdrop`, `card`, `icons` (tuş simgeleri, yukarıda). `overlay: true` iken TV görünen altyazıyı silmez.
`screen-clear` örtüleri kaldırır (altyazıya dokunmaz).

`text` içinde `⟦…⟧` arası **vurgu** rengiyle (TV'de pembe `#ff5fb2`) çizilir; tek kalan işaretler atılır.
Oyunun renkli vurguladığı sözcüğün çevirideki karşılığı böyle gelir (GTA 6 görev şeridi:
`"text": "⟦Limanlara⟧ git"`). Yeni alan yok; eski TV sayfaları da aynı işareti tanır.

`card: true` (harita kartı) kutusu kartın oyundaki çerçevesidir: TV öğeyi kutuya tam oturtur ve opak çizer
(orijinal kart altında görünmesin). Görev şeridi (`plain` olmayan düz öğe) orijinal satırın kutusunu tam örter.

### `region` / `region-clear` — ek alanlar

```json
{ "app": "nino", "type": "region", "id": "map", "text": "Köprü",
  "box": {"left":0.7,"top":0.05,"right":0.95,"bottom":0.1}, "line": 0.02 }
```

`text` boşsa o kutu kalkar. `region-clear` bütün kutuları kaldırır.
`id` dizgedir (sayı gelirse dizge olarak okunur).

## Gönderici girişi (ters yön: web TV'ler)

LG webOS ve Samsung Tizen dinleyemez. Bu yüzden gönderici de **47800**'de
dinler (`NinoSenderIngress`), TV ona bağlanır. Mesajlar aynıdır; yalnız
bağlantıyı açan değişir.

| Yol | Ne yapar |
|---|---|
| `GET /nino/info` | `info` + `role:"sender"`; `Access-Control-Allow-Origin: *` |
| `OPTIONS *` | 204, CORS başlıkları |
| `GET /nino/ws` | WebSocket |

1. TV `ws://<gönderici>:47800/nino/ws` açar.
2. **Gönderici** ilk mesaj olarak `hello` yollar; TV `welcome` (ya da `error`)
   döner. 5 sn içinde `welcome` yoksa gönderici kapatır.
3. Hazır olunca gönderici son `style`'ı, çeviri son 20 sn içinde başladıysa
   `started`'ı (TV her `started`'da balon gösterir) ve hâlâ ekranda olması
   gereken son `show`'u yollar. Aynısı giden bağlantı yeniden kurulunca da
   yapılır.
4. Gönderici 5 sn'de bir `ping` yollar; 15 sn TV'den hiçbir şey gelmezse
   bağlantıyı kapatır (TV kendisi yeniden bağlanır: 1, 2, 4, 8 sn).
5. Birden çok TV aynı anda bağlanabilir; her mesaj hepsine gider.
6. Bonjour yayını yoktur (web TV Bonjour arayamaz; göndericiyi açılış
   parametresiyle ya da `/nino/info` taramasıyla bulur). `_nino._tcp` yalnız
   TV'lerindir; gönderici onu yayınlamaz.
7. `welcome` içinde isteğe bağlı `model` ve `appVersion` gelirse gönderici
   bunları TV bilgisi olarak saklar. İsteğe bağlı `id` TV'nin kalıcı kimliğidir.
8. Aynı TV yeniden bağlanırsa (aynı `welcome.id`; `id` yoksa aynı uzak adres)
   yeni bağlantı el sıkışınca gönderici eskisine `error` (`code: "replaced"`)
   yollar ve onu kapatır; `replaced` bu yönde de kullanılır. TV kopma nedenini
   bu koddan okur; mesaj gelmezse neden `closed` kalır.

## Bütün çıkışlar: `DisplayHub`

Uygulama tek bir `DisplayHub`'a gönderir; o da her çıkışa iletir:
giden bağlantılar (`NinoSender`, TV dinler), gelen TV'ler
(`NinoSenderIngress`) ve eski 8787 sunucusu (`LegacyEventServer`). Her çıkış
`DisplayOutput`'tur: `show`, `clear`, `send(NinoEvent)`. Bir çıkış hata verirse
ötekiler yine alır; hepsi hata verirse hub hata döner. Yeni eklenen çıkışa son
durum (style, yakın zamandaki started, ekrandaki altyazı) yollanır.

"Altyazı yalnız bilgisayarda" (`setSubtitlesOnTV(false)`): altyazı olayları
(`show`, `clear`, `style`, `screen*`, `region*`) yalnız eski sunucuya gider, o da
yalnız OBS'ye verir; `started`/`stopped` herkese gider. Kapatınca TV'ler
temizlenir, açınca son style ve altyazı yollanır.

## Eski uyumluluk: 8787 HTTP + SSE (kalıcı)

Eski TV uygulamaları için `LegacyEventServer` (`Link/Legacy/`). Ayrıntılı eski
biçim Mac tarifindedir (veri uyumu §5). Özet:

- `GET /hello` → `{"app":"nino"}`; `GET /events` → SSE (`model`, `app`,
  `viewer=obs` sorguları); `GET /obs` → OBS tarayıcı kaynağı sayfası;
  `OPTIONS` → 204; diğerleri 404. Her cevapta `Access-Control-Allow-Origin: *`.
- SSE `retry: 2000` ile başlar; bağlanınca son `style` ve (son 20 sn içinde
  başladıysa, OBS değilse) `started`. 15 sn'de bir `: ping` + `event: ping`.
- Çeviri: `show` → `subtitle` (`text` — `speaker` varsa `"Ad: text"`, `⟦T1⟧` okunur `[→]` —, `duration` ms, `at`, `box`, `replace`,
  `light`, `cover`); `durationMs: 0` → `duration` = 15000 (eski varsayılan;
  ayarlanabilir). `clear` → `clear` (kimlik verilmişse yalnız son altyazı
  oysa). `screen.durationMs` → `duration`. Diğer türler aynı adla.
- "Altyazı yalnız bilgisayarda" iken altyazı olayları TV'lere gitmez, OBS'ye
  gider; `started`/`stopped`/`ping` herkese gider. OBS TV sayılmaz.
- Port doluysa birkaç kez yeniden dener, sonra rastgele port. Port başka bir
  süreçle paylaşılmaz. Adres süzgeci varsayılan kapalıdır (eskide yoktu).
- Ölü izleyici: SSE istemcisi hiç veri göndermediği için canlılık yazmadan
  anlaşılır. Yazma hata verirse, bir çerçeve `writeTimeout` (20 sn) içinde
  çekirdeğe geçmezse (15 sn'lik ping turunda bakılır; okumayı bırakmış TV) ya da
  bekleyen bayt `maxPendingBytes`'ı (4 MB) aşarsa izleyici hemen düşürülür.
  Ağdan kaybolan TV'de küçük çerçeveler tampona sığar; onu çekirdek yakalar:
  `connectionDropTime` 25 sn (onaylanmayan veri), sonuç `write-stalled`. Ping
  15 sn'de bir gittiği için en kötü durumda kopma ~40 sn'de görülür. Aynı adresten yeni
  bir TV akışı (OBS değil) gelince eskisi "değiştirildi" sayılıp kapatılır; OBS
  izleyicileri birbirini düşürmez.

## Bağlantı olayları (`DisplayLinkEvent`)

Üç yol da her TV bağlantısı için tipli olay verir: `LegacyEventServer.onLinkEvent`,
`NinoSenderIngress.onLinkEvent` (el sıkışmadan sonra), `NinoSender.setLinkEventHandler`.
Tür: `connected` · `disconnected` · `timedOut`. Alanlar: yol (`sse-8787`, `ws-47800`,
`outgoing`), uzak adres, bağlantı kimliği, model, TV uygulama sürümü, an, bağlı kalma
süresi, neden (`peer-closed`, `read-failed`, `write-failed`, `write-stalled`,
`heartbeat-timeout`, `replaced`, `protocol-error`, `server-stopped`, `local-close`).
Her bağlantıya bir "bağlandı" ve bir kopma düşer, ilk neden geçerlidir. OBS olay
üretmez. Adres yalnız günlük içindir; ölçüme gitmez.

## Güvenlik

- Sürüm 1 yalnız yerel ağ içindir, şifreleme ve kimlik doğrulama yoktur.
- TV yalnız özel IP aralıklarından (`10/8`, `172.16/12`, `192.168/16`,
  `169.254/16`, `127/8`, IPv6 `::1`, `fe80::/10`, `fc00::/7`) bağlantı kabul
  eder.
- Adres çözülürken IPv4 tercih edilir. IPv4 adresindeki kapsam (`%en0`) atılır,
  IPv6'da URL içinde `%25en0` olarak kodlanır.
- Gelen metin yalnız düz yazı olarak gösterilir; HTML ya da biçim olarak
  yorumlanmaz.
- Eşleştirme kodu (TV'de görünen 4 haneli kod) sonraki sürüm için düşünülür.
