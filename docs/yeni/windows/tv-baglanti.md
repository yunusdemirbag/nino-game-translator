<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Windows: TV bağlantısı (altyazı sunucusu 8787, OBS sayfası, yeni protokol)

Bu belge bir **tarif**tir: eski Windows uygulamasının altyazıyı TV'ye (ve OBS'e) taşıyan parçasının davranışını,
biçimlerini ve sabitlerini kod olmadan anlatır. Yeni kod `apps/windows/src/Nino.Core/` altında yazılır; platformdan
bağımsızdır (Linux da kullanır). TV'yi bulma, eşleştirme, TV uygulamasını açık tutma ve kurma `tv-kurulum.md`'dedir.

Mac karşılığı: `git show claude/yeni-mac-c9961f:docs/yeni/mac/veri-uyumu.md` §5. Windows birçok noktada **Mac'ten
geride**dir (aşağıda §9); yeni Windows ESKİ 8787'yi Windows'taki haliyle birebir korur, Mac'in fazlalarını yalnız yeni
protokol (§11) üzerinden ekler.

Terimler:
- **Altyazı sunucusu**: bilgisayarda TCP 8787'de dinleyen küçük HTTP + SSE sunucusu. TV uygulaması ona bağlanır.
- **TV istemcisi**: `/events` akışını açan TV uygulaması.
- **İzleyici (OBS)**: `/events?viewer=obs` ile bağlanan OBS sayfası; olayları alır ama "TV bağlı" sayılmaz.
- **Yerel dinleyici**: uygulamanın kendi içindeki bilgisayar ekranı altyazı penceresi; sunucudan geçen olayların bir
  özetini, ağdan bağımsız olarak alır.

---

## 1. Altyazı sunucusunun açılışı

### 1.1 Port seçimi
- Varsayılan port **8787**. Sunucu uygulama açılışında **açılmaz**; yalnız üç yerde açılır: TV eşleştirme (açılamazsa
  hata eşleştirmeye gider), "test altyazısı gönder" (port hatası yutulur) ve çeviri başlatma (her hata yutulur; TV
  durumu "bekleniyor" kalır). Bir kez açıldıktan sonra uygulama kapanana kadar açık kalır. Sonuç: TV'si olmayan
  kullanıcıda OBS sayfası (`/obs`) ancak ilk çeviri başlatıldıktan (ya da test altyazısından) sonra erişilebilir olur.
- 8787 alınamazsa (port dolu hatası) **6 deneme** yapılır, aralarında **1 sn** beklenir: Nino yeniden açıldığında eski
  sürecin portu birkaç saniye bırakmamış olabilir; hemen başka porta geçilirse TV (yalnız 8787'yi tarar) beklemede kalır.
  Her başarısız denemede sunucu nesnesi atılıp yenisi kurulur (olay abonelikleri yeniden bağlanır). İkinci ya da
  sonraki denemede açılırsa altyazı günlüğüne "altyazı sunucusu 8787'de N. denemede açıldı" anlamında bir satır yazılır.
- 6 deneme de başarısızsa günlüğe 8787'nin açılamadığı (sebebiyle) ve boş bir porta geçildiği yazılır ve işletim sisteminin
  verdiği **rastgele boş port**la açılır. TV'ye adres her açılışta parametreyle bildirildiği için LG/Samsung'da bu da
  çalışır; Android TV ve tarayan eski TV'ler pratikte bulamaz.
- Aynı anda iki açılış yapılmaz: süren açılış varsa ikinci çağrı onu bekler.
- Uygulama "gerçekten dinlenen port"u tutar; TV'ye verilen adres, OBS adresi ve ayarlarda gösterilen adres bu portu
  kullanır.

### 1.2 Dinleme
- **Bütün IPv4 adreslerinde** (0.0.0.0) TCP dinlenir. IPv6 dinlenmez.
- Kabul edilen her bağlantıda:
  - TCP canlılık denetimi açılır: **10 sn** boşta kalınca başla, **5 sn** arayla yokla, **3** yanıtsız denemede kopar
    (fişten çekilen ya da Wi-Fi'ı kopan TV böyle fark edilir). Ayar verilemezse sessizce geçilir.
  - Nagle kapatılır (küçük altyazı çerçeveleri beklemeden gitsin).
- Ping zamanlayıcısı sunucu açılınca kurulur: ilk ping **15 sn** sonra, sonra her 15 sn'de bir (§3.3).

### 1.3 Durdurma
Ping zamanlayıcısı ve dinleyici kapatılır; bütün bağlı istemciler listeden çıkarılıp bağlantıları kapatılır.
Durdururken "bağlı TV sayısı değişti" bildirimi gönderilmez.

---

## 2. HTTP istekleri

### 2.1 İsteği okuma
- Bağlantıdan 8 KB'lık parçalarla, başlıkların sonu (`\r\n\r\n`) görülene kadar okunur; toplam **64 KB**'ı geçerse ya da
  bağlantı erken kapanırsa istek boş sayılır. Metin ASCII olarak çözülür, yalnız **ilk satır** kullanılır (başlıklar
  ve gövde yok sayılır).
- İlk satır boşluktan bölünür: yöntem, hedef. Yol = hedefin `?` öncesi. Karşılaştırmalar harf duyarlı.
- Herhangi bir aşamada hata olursa bağlantı sessizce kapatılır.

### 2.2 Yollar

| İstek | Cevap |
|---|---|
| `OPTIONS` (her yol) | `204 No Content` |
| `GET /events` | SSE akışı (§3). Hedefte herhangi bir yerde `viewer=obs` geçiyorsa izleyici (OBS) sayılır. |
| `GET /obs` | OBS sayfası (§8), `text/html; charset=utf-8` |
| `GET /hello` | `200 OK`, gövde tam olarak `{"app":"nino"}` |
| `GET <yayımlanmış dosya yolu>` | O dosya (§2.4) |
| diğer her şey (başka yöntemler dahil) | `404 Not Found` |

### 2.3 Cevap biçimleri (birebir)
- **Durum cevabı** (204, `/hello`, 404): `HTTP/1.1 <durum>`, `Access-Control-Allow-Origin: *`,
  `Content-Length: <gövde uzunluğu>`, `Connection: close`, boş satır, gövde. `Content-Type` başlığı **yoktur**
  (`/hello` dahil). Gövde ASCII yazılır; 204 ve 404'te gövde boştur. Yazıldıktan sonra bağlantı kapatılır.
  CORS için başka başlık (`Allow-Methods`/`Allow-Headers`) gönderilmez.
- **Dosya cevabı** (`/obs` ve yayımlanmış dosyalar): `HTTP/1.1 200 OK`, `Access-Control-Allow-Origin: *`,
  `Content-Type: <tür>`, `Cache-Control: no-cache`, `Content-Length: <bayt>`, `Connection: close`, boş satır, baytlar;
  sonra kapatılır.

### 2.4 Yayımlanmış dosyalar
Sunucu, uygulamanın verdiği bir bayt dizisini bir yol altında ("/voices/male_1.wav" gibi; tür varsayılanı `audio/wav`)
verebilir. Eskiden dublaj sesleri için kullanılıyordu; dublaj kaldırıldı, bugün hiçbir şey yayımlanmaz. Yeni kodda bu
yetenek **yazılmayabilir** (yazılırsa: tam yol eşleşmesi, harf duyarlı).

### 2.5 TV modeli bildirimi
- TV istemcisi (izleyici değilse) `/events?model=<marka model>` ile modelini söyleyebilir. Sorgu `&` ile bölünür,
  adı tam `model` olan ilk çift alınır; değer `+` → boşluk yapılıp yüzde kodlaması çözülür (çözülemezse model yok).
  Yalnız harf, rakam, boşluk ve `.` `-` `_` `(` `)` bırakılır, baştan/sondan boşluk kırpılır; boşsa yok, **60**
  karakterden uzunsa ilk 60.
- Model, akış açılmadan **önce** uygulamaya bildirilir (uygulama `settings.section.systemHealth` raporunda gösterir). Dinleyicinin
  hatası yutulur.
- `app=<TV uygulaması sürümü>` sorgusu Windows'ta **okunmaz** (Mac okur).

Örnekler (hesaplanmış, testten değil): `/events?model=Samsung%20QE65Q80C` → "Samsung QE65Q80C";
`/events?model=LG+OLED55<C1>` → "LG OLED55C1"; `/events?model=%20%20` → yok; `/events?viewer=obs&model=X` → izleyici
olduğu için bildirilmez. (.NET'in yüzde çözücüsü bozuk diziyi hata vermeden olduğu gibi bırakır; `%E0` → "E0" olur.
Çözücü hata verirse model yok sayılır.)

---

## 3. SSE akışı (`GET /events`)

### 3.1 Açılış (tek yazmada)
İlk yazma şu parçaları **tek seferde** gönderir:
1. `HTTP/1.1 200 OK\r\n`
2. `Content-Type: text/event-stream; charset=utf-8\r\n`
3. `Cache-Control: no-cache\r\n`
4. `Connection: keep-alive\r\n`
5. `Access-Control-Allow-Origin: *\r\n\r\n`
6. `retry: 2000\n\n`
7. Son gönderilmiş `style` çerçevesi (varsa; izleyiciye de).
8. İstemci TV ise (izleyici değil) ve çeviri son **20 sn** içinde başladıysa (`started` gönderilme anı; saat
   değiştirilebilir olmalı, testler ileri alır) `started` çerçevesi. "20 sn içinde" kesin küçüktür: tam 20 sn ya da
   sonrasında gönderilmez.

İstemci bu yazmadan önce listeye eklenir; yazmadan sonra "bağlı TV sayısı" (izleyiciler hariç) bildirilir (izleyici
bağlandığında da bildirim çıkar, sayı değişmemiş olsa bile).

### 3.2 Bağlantının sürmesi ve kopması
- Sunucu, istemciden gelen her şeyi okuyup atar; okuma 0 bayt döner ya da hata verirse istemci listeden çıkarılır,
  bağlantısı kapatılır ve yeni TV sayısı bildirilir.
- Bir çerçeveyi yazarken hata alınan istemci de kopmuş sayılır, aynı biçimde çıkarılır (bir istemci iki kez
  çıkarılmaz; ikinci çıkarma bildirim üretmez).
- Her istemcinin kendi yazma kilidi vardır: iki çerçeve aynı bağlantıya iç içe yazılmaz. Çerçeveler gönderildikleri
  sırayla gitmelidir. Her yazmadan sonra akış boşaltılır (flush). Metin UTF-8.
- "Bağlı TV sayısı" = listedeki izleyici olmayan istemciler.

### 3.3 Ping
Her 15 sn'de bir **bütün** istemcilere (TV'ye gitmeme kapısına bakılmaz) şu metin gider:
`: ping\n\nevent: ping\ndata: {}\n\n` — önce bir yorum satırı (EventSource görmez, ara cihazlar için), sonra adlı
`ping` olayı (TV bunu görür; bir süre gelmezse yarı açık bağlantıyı kapatıp yeniden bağlanır).

### 3.4 "TV'ye gönderme" kapısı
Sunucunun bir anahtarı vardır: **altyazı TV'ye gitsin mi**. Kapalıyken (altyazı yalnız bilgisayar ekranında)
"altyazı olayları" yalnız izleyicilere (OBS) gider, TV istemcilerine gitmez. Altyazı olayları: `subtitle`, `clear`,
`screen`, `screen-clear`, `region`, `region-clear`, `style`. `started` ve `ping` her zaman herkese gider.
**İstisna**: bağlanma anındaki açılışta (§3.1) son `style` kapı kapalıyken de yeni TV istemcisine verilir (kapı yalnız
canlı yayını keser).
Test: kapı kapalı; bir TV ve bir OBS bağlı; `subtitle` "Merhaba", `clear`, `started` gönderilir → OBS `subtitle` ve
`clear`'ı alır; TV akışında `started`'a kadar `subtitle` yoktur.
Uygulama bu anahtarı "altyazı TV'de gösteriliyor mu" bilgisine bağlar ve çıktı seçimi her değiştiğinde günceller.

---

## 4. Olaylar

### 4.1 Çerçeve biçimi
`event: <ad>\ndata: <JSON>\n\n`. JSON tek satırdır; **anahtarlar alfabetik (ASCII) sıralıdır**; Türkçe ve başka
dillerin harfleri kaçışsız (olduğu gibi) yazılır (`ı` değil `ı`). Tırnak, ters bölü ve denetim karakterleri
JSON kuralıyla kaçışlanır (satır sonu `\n`).

**Uyum doğrulamasıyla kesinleşen kaçış kuralı (eski sunucunun baytları, 22 Kasım):** eski uygulama dizgeleri .NET JSON
yazıcısının "gevşek" kaçışıyla (`UnsafeRelaxedJsonEscaping`) yazıyordu; birebir aynı bayt için yeni 8787 de öyle yazar:
`"` → `\"`, `\` → `\\`, `\n \r \t \b \f` kısa biçimde; öbür denetim karakterleri **büyük harfli** onaltılıkla
(`\u001B`); ayrıca `U+007F`, `U+00A0` (bölünmez boşluk), `U+2028`/`U+2029` gibi denetim/biçim/ayraç karakterleri ve
**BMP dışı karakterler (emoji) vekil çiftiyle** (`😀` → `\uD83D\uDE00`) kaçışlanır. Türkçe, Arapça harfler ve
`< > & ' +` kaçışsız kalır. (Yeni protokol 47800 bu kuraldan etkilenmez; orada yalnız tırnak, ters bölü ve denetim
karakterleri kaçışlanır.) Test: `Fixtures/Compat/old/sse/tv-all-events.bin`.

### 4.2 Sayı yuvarlama
- **Kutu ve satır yüksekliği** değerleri: önce 0–1 arasına kırpılır, sonra **4 ondalığa** yuvarlanır (ondalık sayı
  aritmetiğiyle, eşit yarıda çift sayıya), sondaki sıfırlar atılır. JSON'da `0.8` yazar (`0.8000` değil), `0.87499` →
  `0.875`, `1.2` → `1`, `-0.1` → `0`.
- **Kutu** = `{"bottom":…, "left":…, "right":…, "top":…}` (alfabetik sırada; değerler karenin oranı, üstten ve soldan).
- `angle`: derece; mutlak değeri **0.3'ten küçükse hiç yazılmaz**; değilse 1 ondalığa, yarıda sıfırdan uzağa
  yuvarlanır (`5.71` → `5.7`, `-0.35` → `-0.4`). Kırpılmaz.
- `alpha`: 0–1'e kırpılır, 2 ondalığa, yarıda sıfırdan uzağa yuvarlanır (`0.6` → `0.6`, `0.955` → `0.96`).
- **Uyum doğrulamasıyla kesinleşen:** `angle` ve `alpha` eski uygulamada **kayan noktalı** aritmetikle yuvarlanır
  (`round(a × 10) / 10`, `round(a × 100) / 100`, yarıda sıfırdan uzağa), ondalık sayıyla değil. Fark eden değer
  örneği: `alpha` 0.285 → **0.28** (0.285 × 100 = 28.4999…); ondalık aritmetik 0.29 verirdi. Sonuç en kısa geri
  dönüşlü yazımla yazılır (`0.28`, `1`, `-0.4`). Kutu ve satır yüksekliği ise ondalık aritmetikle kalır (yukarıda).
- **Uyum doğrulamasıyla kesinleşen:** ekran öğesinde `line` eski uygulamada **her öğede** vardır (satır yüksekliği
  zorunluydu); yeni uygulama da her öğe için verir. `fill`/`ink` verildiyse — boş dizge de — yazılır (`"fill":""`).

### 4.3 `subtitle`
Gönderen bilgiler: metin, süre (ms; verilmezse **15000**), isteğe bağlı kutu (İngilizce altyazının yeri), "paragraflı"
bayrağı, "yerine koy" bayrağı.

Gövde alanları:
- `at`: gönderme anı, Unix milisaniye (UTC).
- `duration`: süre, ms (tam sayı).
- `text`: çeviri (konuşan adı ve satır sonları metnin içinde).
- `paragraphs`: yalnız doğruysa gönderilir, `true` (her satır ayrı ve sola dayalı çizilir; görev listesi gibi bloklar için).
- `replace`: yalnız doğruysa, `true` (satır az önce gösterilenin uzamış/düzelmiş okumasıdır; TV öncekinin üstüne
  yığmaz, yerine koyar; eski TV uygulamaları yok sayar).
- `box`: yalnız kutu verildiyse.

Örnek (test): metin "Merhaba", 4000 ms, kutu sol 0.25, üst 0.8, sağ 0.75, alt 0.87499 →
`data: {"at":<ms>,"box":{"bottom":0.875,"left":0.25,"right":0.75,"top":0.8},"duration":4000,"text":"Merhaba"}`
(içinde `replace` geçmez). Ardından "Merhaba yolcu", 4000, yerine koy → `…"replace":true,"text":"Merhaba yolcu"}`.

Yerel dinleyiciye: (tür altyazı, metin, süre, paragraflı, yerine koy). Kutu yerel dinleyiciye **verilmez**.

### 4.4 `clear`
Gövde `{}`. Yerel dinleyiciye "temizle". Kimlik yoktur: TV ekrandaki altyazıyı kaldırır.

### 4.5 `started`
Çeviri başladığında: başlama anı saklanır (§3.1 tekrar için) ve `event: started\ndata: {}\n\n` herkese gider
(kapıdan bağımsız). TV çevirinin başladığını söyleyen kısa bir balon gösterir; eski TV'ler yok sayar. Yerel dinleyiciye gitmez.
**Windows'ta `stopped` olayı yoktur** (Mac'te var).

### 4.6 `screen` ("ekranı çevir" sonuçları ve sürekli örtüler)
Gönderen: öğe listesi, süre (ms), "örtü" (overlay) bayrağı.

Gövde: `{"duration": <ms>, "items": [<öğe>…], "overlay": true?}` (`overlay` yalnız doğruysa).

Öğe alanları (alfabetik sırada yazılır):
- `box` (zorunlu), `line` (satır yüksekliği, ekran yüksekliğine oranla; §4.2 kuralı), `text` (çeviri; birden çok parça
  satır sonuyla ayrılmış).
- `paragraphs: true` — çeviride satır sonu varsa kendiliğinden.
- `plain: true` — kutusuz, gölgeli sade yazı.
- `italic: true` — eğik yazı (telefon araması).
- `fill: "#rrggbb"` ve `ink: "#rrggbb"` — oyunun kutusunun zemin ve yazı rengi (verildiyse).
- `angle` (§4.2), `alpha` (§4.2).
- `side: true` — balon oyunun kutusunun yanında.
- `backdrop: true` — yazısız zemin (telefonun yanındaki panel).
- `card: true` — harita görev kartının çevirisi.
- Windows **`frost` göndermez** (Mac gönderir).

`overlay: true` iken TV o an görünen altyazıyı silmez; bu olay yerel dinleyiciye **gitmez** (bilgisayar penceresinde
telefonun yanı bulunmaz, altyazının yerini örterdi). Örtü değilse yerel dinleyiciye: (tür ekran, metin = öğelerin
çevirileri sırayla `\n` ile birleşik, süre, paragraflı = doğru).

Örnek (test): öğeler ("Map\nSettings" → "Harita\nAyarlar", kutu 0.05/0.3/0.2/0.4, satır 0.03) ve ("Light the torch." →
"Meşaleyi yak.", kutu 0.4/0.8/0.6/0.84, satır 0.04), süre 12000 → gövde `duration":12000` ve şu iki öğeyi içerir:
`{"box":{"bottom":0.4,"left":0.05,"right":0.2,"top":0.3},"line":0.03,"paragraphs":true,"text":"Harita\nAyarlar"}` ve
`{"box":{"bottom":0.84,"left":0.4,"right":0.6,"top":0.8},"line":0.04,"text":"Meşaleyi yak."}`.

Örnek (test, telefon/harita): öğeler (çeviri "Lucia", dolgu `#f5f5f6`, alpha 0.6, zemin), ("Bu gece çok sessiz.", dolgu
`#acccfe`, mürekkep `#2c2c2e`, alpha 0.95, yan, açı 5.71), ("ÇİÇEK AL", kart); süre 120000, örtü → gövdede
`"overlay":true`, `"alpha":0.6,"backdrop":true,`, `"fill":"#f5f5f6"`, `"alpha":0.95,"angle":5.7,`, `"ink":"#2c2c2e"`,
`"side":true`, `"card":true` geçer.

Uygulamadaki kullanım (bilgi için): sürekli örtüler `overlay: true`, süre **120000** ile tek liste halinde gönderilir;
liste boşalınca `screen-clear`. `shortcut.action.translateScreen` sonuçları örtüsüz, kendi süresiyle.

### 4.7 `screen-clear`
Gövde `{}`. TV "ekranı çevir" çevirilerini/örtüleri kaldırır, altyazıya dokunmaz. Yerel dinleyiciye "ekran temizle".

### 4.8 `region` (ek alanlar)
Gönderen: alan kimliği (metin), çeviri (boşsa o alanın kutusu kalkar), isteğe bağlı kutu, isteğe bağlı satır yüksekliği.
Gövde: `id`, `text`, varsa `box`, varsa `line`.

Örnekler (test): ("q", "Okçuyu bul", kutu 0.7/0.05/0.95/0.12, satır 0.03) →
`data: {"box":{"bottom":0.12,"left":0.7,"right":0.95,"top":0.05},"id":"q","line":0.03,"text":"Okçuyu bul"}`;
("q", "", kutu yok) → `data: {"id":"q","text":""}`.

Yerel dinleyiciye: (tür alan, metin, kimlik, kutu). Satır yüksekliği verilmez.

### 4.9 `region-clear`
Gövde `{}`. Bütün ek alan kutuları kalkar. Yerel dinleyiciye "alanları temizle".

### 4.10 `style`
Uygulama görünüm değişince ve altyazı göndermeden önce çoğu zaman yollar. Sunucu **son stili saklar** ve yeni bağlanan
her istemciye açılışta verir (§3.1).

Gövde alanları (alfabetik):

| Alan | Değer |
|---|---|
| `autoSize` | Kayıtta "boyutu oyunun altyazısına uydur" varsa o; **yoksa** (eski kayıt) yazı boyu 46 ise `true`, değilse `false` |
| `background` | Yerleşim örtme (`cover`) ve koyuluk **60'tan küçükse 100**; değilse koyuluk 0–100'e kırpılmış |
| `backgroundShape` | `fit` ya da `band` |
| `bold` | `true`/`false` |
| `bottomPercent` | sabit yerleşimde alttan uzaklık (%; olduğu gibi) |
| `displayMode` | `inApp` ya da `overlay` (yalnız Android TV kullanır) |
| `font` | `condensed`, `modern`, `rounded`, `system` |
| `fontSize` | tam sayı (ayardaki kaydırıcı 16–90, varsayılan 46; `ayarlar.md`) |
| `placement` | `cover`, `above`, `below`, `fixed` |
| `stackPrevious` | `true`/`false` (hızlı konuşmada önceki satır soluk üstte kalsın; TV 0.9.16+) |
| `textColor` | `white` ya da `yellow` |
| `watermark` | `true`/`false` (TV'nin sol altındaki küçük Nino işareti) |

Windows `theme` alanını **göndermez** (Mac gönderir).

Örnek (test): boy 58, alt 10, üstünde, koyuluk 40, kalın, sarı, katman, önceki kalsın, bant → gövdede
`"fontSize":58`, `"bottomPercent":10`, `"placement":"above"`, `"background":40` (yerleşim örtme değil), `"bold":true`,
`"textColor":"yellow"`, `"displayMode":"overlay"`, `"stackPrevious":true`, `"backgroundShape":"band"`.
Varsayılan stil → `"font":"condensed"`, `"watermark":true`, `"autoSize":true`.

---

## 5. Görünüm ayarının kaydı (stil)

Stil kullanıcı ayarları dosyasında saklanır (alan adları büyük harfle başlar, sabit listeli değerler **adıyla**
yazılır). Ayarlar ekranındaki karşılıkları `ayarlar.md`'de (oradaki tabloyla aynı alanlar). Eski sürümün kaydında olmayan alanlar varsayılanla dolar. Alanlar ve varsayılanlar:

| Kayıt alanı | Tür / değerler | Varsayılan |
|---|---|---|
| `FontSize` | tam sayı | 46 |
| `BottomPercent` | tam sayı | 7 |
| `Placement` | `Cover`, `Above`, `Below`, `Fixed` | `Cover` |
| `Background` | 0–100 | 100 |
| `Bold` | mantıksal | false |
| `TextColor` | `White`, `Yellow` | `White` |
| `DisplayMode` | `InApp`, `Overlay` | `InApp` |
| `StackPrevious` | mantıksal | true |
| `BackgroundShape` | `Fit`, `Band` | `Fit` |
| `Font` | `Condensed`, `Modern`, `Rounded`, `System` | `Condensed` |
| `Watermark` | mantıksal | true |
| `AutoSize` | mantıksal ya da yok (null) | yok |

"Oyunun altyazısına uydur" sorusunun cevabı: `AutoSize` doluysa o, boşsa `FontSize == 46`. Bu türetilmiş değer kayda
yazılmaz.

Örnekler (test):
- `{"FontSize":58}` → `Font` Condensed, `DisplayMode` InApp, `BackgroundShape` Fit, `Watermark` true, uydur = hayır.
- `{"FontSize":46}` → uydur = evet. `{"FontSize":58,"AutoSize":true}` → evet.
- `{"FontSize":58,"BottomPercent":12}` → (58, 12, Cover, 100, kalın değil, geri kalan varsayılan).
- Boy 46 + `AutoSize:false` kaydedilip okununca uydur = hayır kalır.
- Yazı tipi Modern kaydedilince JSON'da `"Modern"` geçer; katman kaydedilince `"Overlay"`.

---

## 6. Yerel dinleyici olayları (bilgisayar ekranı penceresi)

Sunucu açılmamış olsa da çalışır; olay gönderildiği anda çağıranın iş parçacığında verilir. Kayıt biçimi: tür
(altyazı, temizle, ekran, ekran-temizle, alan, alan-temizle), metin, süre, paragraflı, yerine koy, alan kimliği, kutu.
Hangi olayın neyi verdiği §4'te. `style`, `started`, `ping` verilmez.

Örnekler (test):
- altyazı ("Merhaba", 4000, kutu yok, paragraflı) + temizle → [(altyazı, "Merhaba", 4000, paragraflı), (temizle)].
- ekran [("Harita\nEnvanter"), ("Ayrıl")], 12000 + ekran-temizle → [(ekran, "Harita\nEnvanter\nAyrıl", 12000,
  paragraflı), (ekran-temizle)].
- alan ("q","Okçuyu bul", kutu) + alan ("q","") + alan-temizle → [(alan, "Okçuyu bul", kimlik q, kutu),
  (alan, "", kimlik q), (alan-temizle)].

---

## 7. Uygulamanın sunucuyu kullanışı (TV ile ilgili kısım)

- Bağlı TV sayısı değişince uygulama ana iş parçacığında sayıyı günceller, sağlık izleyicisine bildirir. Ana ekrandaki
  TV durum metni: TV kurulmadıysa "Kurulmadı", sayı > 0 ise "Bağlı", değilse `status.tv.waitingForApp`.
- Samsung bekçisi "TV uygulaması bağlı mı" sorusunu bu sayıyla cevaplar (> 0) — `tv-kurulum.md` §4.
- TV'ye verilen sunucu adresi: `http://<bu bilgisayarın TV'ye bakan adresi>:<dinlenen port>`; adres bulunamazsa
  `127.0.0.1` (adres seçimi `tv-kurulum.md` §1).
- OBS adresleri (ayarlarda kopyalanır): `http://localhost:<port>/obs` ve ağ adresiyle
  `http://<bu bilgisayarın Wi-Fi/Ethernet adresi>:<port>/obs` (localhost kabul etmeyen yayın programları için; adres
  yoksa gösterilmez).
- Çeviri başlarken (bekçi kurulduktan sonra) `started` gönderilir.
- Çeviri TV'ye gidiyor, TV kurulu ama **60 sn** boyunca hiç TV bağlanmadıysa `firewall.settings.title` denetimi devreye
  girer (kural yoksa kart önerilir); ayrıntı güvenlik duvarı tarifinde.

---

## 8. OBS sayfası (`/obs`) — davranış

Sayfa yeni koda yeniden yazılacak (eski dosya `core/` altındaydı ve Mac ile ortaktı; yeni Windows kendi kopyasını
`apps/windows/src/Nino.Core/Resources/` altına koyar ve gömülü kaynak olarak verir). Aşağıdaki davranış korunmalı.

### 8.1 Bağlantı ve adres parametreleri
- Sayfa aynı kökten `/events?viewer=obs` EventSource'u açar (OBS "TV bağlı" sayılmaz; `started` almaz). Yeniden
  bağlanma EventSource'un kendisine bırakılır (sunucu `retry: 2000` verir).
- Dinlenen olaylar: `style`, `subtitle`, `clear`, `region`, `region-clear`. `screen`, `screen-clear`, `started`,
  `ping` yok sayılır; `subtitle`'daki `paragraphs` ve `replace` yok sayılır.
- Adres parametreleri:
  - `size`: yazı boyu (1080 satırlık ekranda piksel); verilirse stilin `fontSize`'ını ezer.
  - `bottom`: alttan uzaklık (%); verilirse stilin `bottomPercent`'ini ezer **ve** yerleşimi hep "sabit" yapar.
  - `bg`: sayıysa altyazı kutusunun koyuluğu (0–100; stilinkini ezer). Ad ise bütün sayfanın zemini (chroma key):
    `green` `#00FF00`, `black` `#000000`, `magenta` `#FF00FF`, `blue` `#0000FF` (harf duyarsız). Adlı zeminde koyuluk
    parametresi yok sayılır.
  - `hint`: `1`/`0` ipucu açık/kapalı. Verilmezse: OBS tarayıcısında (sayfada OBS'in kendi nesnesi tanımlıysa ya da
    tarayıcı kimliğinde `OBS/` geçiyorsa) kapalı, başka yerde açık.

### 8.2 Görünüm (başlangıç)
- Sayfa zemini saydam (adlı zemin verildiyse o renk), taşma gizli.
- Yazı: gri tonlu kenar yumuşatma (renkli alt piksel yumuşatma videoda saçak bırakır), geometrik hassas çizim.
- Altyazı kabı: tam genişlik, alttan **%7**, yatayda ortalı, tıklama geçirgen.
- Altyazı kutusu: en çok **%84** ekran genişliği; iç boşluk 0.25em/0.6em; köşe 0.3em; yazı 600 kalınlık **48px**, satır
  1.3, sistem yazı tipi; beyaz; ortalı; satır sonları korunur ve uzun satır kırılır; gölge (0 0 0.12em siyah ve
  0 0.06em 0.12em siyah); zemin siyah %60. Görünme/kaybolma 0.15 sn saydamlık geçişi.
- Yazı tipleri Google Fonts'tan yüklenir: Barlow, Barlow Condensed, Nunito (600 ve 700). İnmezse sistem yazı tipi.
  Eşleme: `modern` → Barlow, `condensed` → Barlow Condensed, `rounded` → Nunito, `system` → yalnız sistem.
- Renkler: `white` `#FFFFFF`, `yellow` `#FFE135`.

### 8.3 Ölçek
Yazı boyu S için piksel = `max(8, yuvarla(S × sayfa yüksekliği / 1080))` (sayfa yüksekliği bilinmiyorsa 1080).
Sayfa boyutu değişince son stil yeniden uygulanır.

### 8.4 Stili uygulama
- Boy = `size` parametresi, yoksa stilin `fontSize`'ı, yoksa 48. Pozitifse temel boy olur; altyazının boyu temel ×
  satır ölçeği (§8.6).
- İpucunun boyu `max(20, yuvarla(boy × 0.6))`.
- Alt uzaklık (`bottom` parametresi ya da stil) 0–85 arasındaysa ipucunun alt uzaklığı olur; son gösterilen altyazı
  sabit yerleşimdeyse kabın alt uzaklığı da.
- Koyuluk (`bg` sayısı ya da stilin `background`'ı) sayıysa kutu zemini = siyah, saydamlık koyuluk/100. Adlı zeminde
  yarı saydam kutu chroma key'i bozar: saydamlık > 0 ise tam opak, 0 ise yok. Koyuluk hiç yoksa ve adlı zemin varsa
  %60 kuralıyla (yani opak).
- `bold` → 700 / 600. `textColor` tanınıyorsa renk. `font` → yazı tipi ailesi. `placement` saklanır (varsayılan
  `cover`). Açık ek alan kutuları yeniden biçimlenir.

### 8.5 Altyazıyı gösterme
1. Önceki gizleme zamanlayıcısı iptal. Metin boşsa gizle ve dur. İpucu gizlenir.
2. Metin kaydırılır (§8.6), boyu ölçeğe göre ayarlanır.
3. Arap harfi içeriyorsa (Unicode aralıkları U+0620–064A, U+066E–06D3, U+06FA–06FF, U+0750–077F, U+08A0–08FF,
   U+FB50–FDFF, U+FE70–FEFF) yazı yönü sağdan sola; değilse varsayılan.
4. Kip: kutu varsa ve `bottom` parametresi yoksa stilin yerleşimi; değilse "sabit". `cover`/`above`/`below` dışı her
   değer "sabit".
5. **Örtme (cover)**: kap bütün sayfayı kaplar; kutu mutlak konumda, merkezi İngilizce satırın merkezine oturur
   (yatay merkez = (sol+sağ)/2, dikey = (üst+alt)/2, yüzde; kendi boyunun yarısı kadar geri kaydırılır). Stilin
   `backgroundShape`'i `band` ise yatay merkez %50 ve kutu genişliği tam sayfa; değilse en az İngilizce kutunun
   genişliği kadar. Zemin: koyuluk sayıysa 100 ve üstü tam siyah, altı saydamlık koyuluk/100; koyuluk hiç yoksa
   %97 siyah; adlı zeminde her zaman tam siyah.
6. **Üstünde / altında**: kutunun konum ayarları sıfırlanır, stil yeniden uygulanır. Boşluk = sayfa yüksekliğinin
   %1.2'si. Merkez c = (sol+sağ)/2, yarım genişlik h = `max(0.3, min(c, 1−c))`; kap solu `max(0.02, c−h)`, sağı
   `max(0.02, 1−c−h)` (yüzde). Kutunun gerçek yüksekliği ölçülür: üste sığar = yükseklik ≤ üst × sayfa − boşluk;
   alta sığar = yükseklik ≤ (1−alt) × sayfa − boşluk. Üstünde istenip sığmazsa altına, o da olmazsa sabite; altında
   istenip sığmazsa üstüne, o da olmazsa sabite. Üstünde: kabın alt uzaklığı `(1−üst)×100 + 1.2` %; altında: kabın
   üst uzaklığı `alt×100 + 1.2` %.
7. **Sabit**: kap yatayda tam genişlik, alt uzaklık = `bottom` parametresi ya da stilin `bottomPercent`'i (0–85
   arasındaysa).
8. Gizleme zamanlayıcısı: `max(1000, süre || 8000)` ms.
- Gizlerken yalnız görünürlük kalkar; örtme konumu ve metin solma bitene kadar yerinde kalır (yoksa opak kutu kısa
  süre tam yükseklikte siyah pencere gibi görünür). `clear` olayı gizler.

### 8.6 Satır kaydırma (Mac, Windows, Android ve TV ile aynı kural)
Sabitler: satır başına en çok **42** karakter, en çok **3** satır, en küçük ölçek **0.75**.
1. Uzunluk (kod noktası sayısı) ≤ 42 ise ya da metinde zaten satır sonu varsa: olduğu gibi, ölçek 1.
2. Kelimelere böl (boşluklardan; boşlar atılır). İlk 3 kelimeden biri `:` ya da `：` ile bitiyorsa (konuşan adı),
   baştan o kelimeye **ve bir sonrakine** kadar olan kelimeler tek parça sayılır (ad hep ilk satırda kalsın).
3. Parça sayısı < 2 ise olduğu gibi, ölçek 1.
4. Ölçek = `min(1, max(0.75, 42×3 / uzunluk))`; satır sınırı = `taban(42 / ölçek)`; satır sayısı =
   `min(3, max(2, tavan(uzunluk / sınır)))`, ayrıca parça sayısını aşamaz.
5. Dengeli bölme: 2 satırda bütün tek kesim yerleri, 3 satırda (parça ≥ 3 ise) bütün iki kesim yerleri denenir. Satır
   genişliği = parça uzunlukları + aradaki boşluklar (UTF-16 uzunluğu). En uzun satırı en kısa olan seçilir; eşitse
   satır genişliklerinin karelerinin toplamı en küçük olan. Satırlar `\n` ile birleşir.

Örnekler (hesaplanmış, testten değil): 42 karakterlik metin → değişmez; "ARTHUR: Kapıyı tut, evlat, yoksa hepimiz burada kalırız!"
(56 kod noktası) → ölçek 1, sınır 42, 2 satır; "ARTHUR: Kapıyı" tek parça başlar.

### 8.7 Ek alan kutuları (`region`)
- Kimlik boşsa yok sayılır. Metin boşsa o kimliğin kutusu kaldırılır. Değilse ipucu gizlenir; kutu yoksa oluşturulur,
  metin konur.
- Biçim: iç boşluk 0.3em/0.6em, köşe 0.3em, 600 kalınlık, satır 1.25, satır sonları korunur, zemin siyah %85 (adlı
  zeminde tam siyah), yazı rengi altyazınınki. Boy = `max(12, temel boy × 0.55)` (§8.3 ölçeğiyle).
- Kutu verildiyse: sol = sol×100 %, üst = üst×100 %, en az genişlik = (sağ−sol) ekran genişliği, en çok genişlik =
  `max(sağ−sol, min(0.45, 1−sol))` ekran genişliği. Kutu yoksa: yatayda ortalı, üstten %4, en çok %60 genişlik.
- `region-clear` hepsini kaldırır.

### 8.8 İpucu
- Altyazı gelene kadar "Nino: altyazı bekleniyor" (İngilizce: "Nino: waiting for subtitles") **12 sn** görünür.
- Akış hiç açılamadan hata verirse "Nino uygulamasına bağlanılamadı" (İngilizce: "Cannot reach the Nino app") 12 sn.
- Dil: tarayıcı dili `tr` ile başlıyorsa Türkçe, değilse İngilizce. Konum: alttan %7, ortalı, 600 28px, %85 beyaz,
  gölgeli. İpucu kapalıysa hiç görünmez. Altyazı ya da ek alan gelince gizlenir.

---

## 9. Mac ile farklar (eski 8787)

Windows eski sunucusunda **olmayanlar** (Mac'te var): `stopped` olayı, `style.theme`, `subtitle.light`,
`subtitle.cover`, ekran öğesinde `frost`, `/events?app=` sorgusunun okunması. Yeni Windows 8787 tarafında bunları
eklemek zorunlu değildir (eski TV uygulamaları yok sayar); `stopped` yeni protokolde eklenir (§11.5). Yuvarlama,
alan adları, ping, 20 sn tekrar, izleyici kuralı Mac ile aynıdır.

## 10. Platforma bağlı kısımlar (Windows)

- TCP canlılık denetimi soket seçenekleri (açık, boşta 10 sn, aralık 5 sn, deneme 3): .NET'in soket seçenekleriyle
  Windows 10 1709+ destekler; desteklenmezse sessizce atlanır.
- `firewall.settings.title`: sunucu dolu portta başka port seçebildiği için kural port değil **program** kapsamında,
  yalnız Özel ağ profili ve yerel alt ağ için verilir (güvenlik duvarı tarifi). Kurulum adımında "Windows Nino'nun ağı
  kullanmasını sorarsa Özel ağlar için izin verin" ipucu gösterilir.
- Sunucu düz `TcpListener` üzerinde elle HTTP konuşur; `HttpListener` kullanılmaz (yerel olmayan adreste URL ACL /
  yönetici izni ister).

---

## 11. Yeni protokolde Windows göndericisi ne yapmalı

Kaynaklar: `~/Desktop/NinoCore/docs/tarif/protokol.md` (sürüm 1 + uzantılar + gönderici girişi),
`git show claude/yeni-tv-web-2fe593:docs/yeni/tv-web/baglanti.md`, oturum notları `protokol-karari-tv.md`,
`tv-web.md`, `android-tv.md`.

**Karar:** yeni Windows **üç çıkışı aynı anda** besler; uygulama tek bir dağıtıcıya gönderir, dağıtıcı her çıkışa
iletir (bir çıkış hata verirse ötekiler yine alır):
1. **Eski 8787** (§1–§8, değişmeden, kalıcı): eski TV uygulamaları ve OBS.
2. **Giden bağlantı** (Windows istemci, TV sunucu): yeni **Android TV** uygulamasına `ws://<TV>:47800/nino/ws`.
3. **Gönderici girişi** (Windows sunucu, TV istemci; "ters yön"): yeni **LG/Samsung** web uygulamaları Windows'a
   `ws://<bilgisayar>:47800/nino/ws` ile bağlanır.

### 11.1 Ortak kurallar (her iki 47800 yönü)
- Her mesaj UTF-8 JSON, `"app":"nino"` ve `"type"` taşır. Bilinmeyen alan/tür yok sayılır.
- El sıkışmayı **her iki yönde de gönderici (Windows)** başlatır: bağlantı açılınca ilk mesaj
  `{"app":"nino","type":"hello","version":1,"device":"Windows","client":"nino-windows/<uygulama sürümü>"}`.
  TV `{"type":"welcome","version":1,"name":…,"model"?,"appVersion"?}` döner. **5 sn** içinde `welcome` yoksa
  kapatılır. `error` `version_unsupported` gelirse `versions` içindeki en büyük ortak sürümle yeniden denenir; ortak
  sürüm yoksa kullanıcıdan TV uygulamasının yeni sürümünü kurması istenir. `welcome`'daki `model`/`appVersion` TV bilgisi olarak
  saklanır (8787'deki `model` sorgusunun karşılığı; sağlık raporunda gösterilir).
- Canlılık: Windows **5 sn**'de bir `{"type":"ping","t":<ms>}` yollar; **15 sn** TV'den hiçbir şey (pong dahil)
  gelmezse bağlantı kopmuş sayılır. TV'den gelen `ping`'e aynı `t` ile `pong` dönülür.
- Boyut: `cover` taşımayan her mesaj **16 KB** altında tutulur (Windows `cover` üretmez). Çok öğeli `screen` bu sınırı
  aşacaksa — **açık karar**: öğe sayısını kırp (ekran çevirisi zaten en çok 30 grup) ya da 512 KB TV sınırına güven.
  Öneri: önce ölç, 16 KB'ı aşarsa son öğelerden atarak sığdır, günlüğe yaz.
- Hazır olunca (welcome sonrası) TV'ye **sırayla**: son `style`; çeviri sürüyorsa `started`; hâlâ ekranda olması
  gereken son `show` (gönderim anı + süre geçmemişse, kalan süreyle) ve sürüyorsa son örtü `screen`'i. (8787'deki
  "yalnız 20 sn içinde `started`" kuralından farklıdır: yeni protokolde çeviri sürdükçe `started` yollanır.)
- "TV'ye gönderme" kapısı (§3.4) iki 47800 çıkışına da uygulanır: kapalıyken `show`, `clear`, `screen`,
  `screen-clear`, `region`, `region-clear`, `style` gitmez; `started`, `stopped`, `ping` gider.
- **Bağlı TV sayısı** = 8787'deki TV istemcileri + `welcome` almış gelen TV'ler + `welcome` almış giden bağlantı.
  Ana ekran durumu, sağlık, güvenlik duvarı 60 sn kuralı ve Samsung bekçisinin "uygulama bağlı mı" sorusu bu toplamı
  kullanır. OBS yalnız 8787'dedir, sayılmaz.

### 11.2 Eski olayların yeni mesajlara eşlenmesi

| Eski 8787 | Yeni mesaj | Not |
|---|---|---|
| `subtitle` {text, duration, at, box?, paragraphs?, replace?} | `show` {id, text, durationMs, box?, paragraphs?, replace?, source?, position:"bottom"} | `id`: gönderici her `show` için artan tam sayı üretir (oturum boyunca, 1'den). `durationMs` = `duration` (Windows hep süre verir; 0 gönderilmez). `at` atılır. `source`: İngilizce satır elde varsa eklenebilir (isteğe bağlı). Kutu biçimi aynı (§4.2). |
| `clear` {} | `clear` {id: son `show`'un id'si} | Kimlikli gönderilir: geç kalan `clear` yeni altyazıyı silmesin. Hiç `show` yoksa kimliksiz. |
| `started` {} | `started` | 8787'de olduğu gibi çeviri başlayınca. |
| (yok) | `stopped` | **Windows'a yeni**: çeviri durunca (durdur düğmesi, PS5 koptu ve oturum bitti) yollanır; TV rozeti, altyazıyı, örtüleri ve kutuları kaldırır. 8787'ye de eklenebilir (eski TV'ler yok sayar); öneri: ekle, Mac ile aynı olsun. |
| `screen` {duration, items, overlay?} | `screen` {durationMs, items, overlay?} | Öğe alanları ve yuvarlama aynı (§4.6). |
| `screen-clear`, `region` {id, text, box?, line?}, `region-clear` | aynı adla | `region.id` dizge. |
| `style` {…} | `style` {…} | Alanlar ve değerler aynı (§4.10); `backgroundShape` yalnız `fit`/`band`. `theme` Windows'ta yok, gönderilmez. |
| SSE `ping` | — | Yeni protokolün kendi `ping`/`pong`'u. |

### 11.3 Giden bağlantı: Android TV
- Yeni Android TV uygulaması 47800'de HTTP + WebSocket sunucusudur, `_nino._tcp` Bonjour yayını yapar, `GET /nino/info`
  cevabında **`role` alanı yoktur** (TV). Tek göndericiyi kabul eder; yeni gönderici gelince eskisine `replaced` yollar.
- **Adres**: TV kaydının adresi (Android TV kurulumunda ADB taramasıyla bulunup kaydedilir, `tv-kurulum.md` §8). Adres
  yoksa ya da bağlanılamıyorsa **açık karar**: (a) elle yazılmış mDNS sorgusu (`_nino._tcp`; yeni NuGet yasak, UDP
  5353 çok noktaya yayınla küçük bir sorgu yazılabilir), ya da (b) bilgisayarın her ev ağının /24 bölümünde
  `GET http://<ip>:47800/nino/info` taraması (aynı anda 64, ~700 ms), cevabında `"app":"nino"` olup `role:"sender"`
  **olmayan** ilk adres. Öneri: önce (b) (mevcut tarama altyapısıyla aynı), mDNS sonra.
- Yeniden bağlanma: kopunca 1, 2, 4, 8, 8… sn bekleyerek. `replaced` alınırsa (başka cihaz TV'yi aldı) — **açık
  karar**: hemen geri almaya çalışmamak (iki gönderici birbirini atar). Öneri: `replaced` sonrası yalnız kullanıcı
  çeviriyi yeniden başlatınca ya da 60 sn sonra dene.
- Eski Android TV uygulaması (8787'yi tarayan) yeni Windows'la 8787 üzerinden çalışmaya devam eder; ikisi aynı TV'de
  aynı anda olmaz.

### 11.4 Gönderici girişi: LG / Samsung (ters yön)
- Windows **47800**'de dinler (bütün IPv4 adresleri). Yollar:
  - `GET /nino/info` → `200`, `Content-Type: application/json`, `Access-Control-Allow-Origin: *`, gövde
    `{"app":"nino","type":"info","version":1,"versions":[1],"name":"<bilgisayar adı>","id":"<kalıcı kimlik>","role":"sender"}`.
    `id`: ilk açılışta üretilip saklanan rastgele kimlik (öneri: secure store'da değil ayarlarda düz metin; gizli değil).
  - `OPTIONS *` → `204`, CORS başlıkları (`Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: GET, OPTIONS`,
    `Access-Control-Allow-Headers: *`).
  - `GET /nino/ws` → WebSocket'e yükseltme. Diğerleri 404.
- Bağlanan her TV için Windows `hello` yollar, `welcome` bekler (5 sn), sonra §11.1'deki hazırlık mesajları. **Birden
  çok TV** aynı anda bağlanabilir; her mesaj hepsine gider.
- 15 sn sessiz TV kapatılır; TV kendisi 1, 2, 4, 8 sn bekleyerek yeniden bağlanır.
- Bonjour yayını **yapılmaz** (web TV arayamaz). TV göndericiyi açılış parametresinden ya da `/nino/info` taramasından
  bulur.
- Yalnız özel adreslerden (10/8, 172.16/12, 192.168/16, 169.254/16, 127/8) gelen bağlantı kabul edilir.
- Not: `OPTIONS` cevabındaki `Allow-Methods`/`Allow-Headers` başlıkları, `/nino/info`'nun `Content-Type`'ı ve girişteki
  özel adres süzgeci bu tarifin **önerisi**dir; protokol metni yalnız `Access-Control-Allow-Origin: *`'ı ve TV tarafı için
  özel adres kuralını yazar.
- **Açılış parametresi**: LG/Samsung TV uygulaması açılırken (eşleştirme, bekçi, kurulum sonrası; `tv-kurulum.md`)
  bugün `{"server":"http://<ip>:8787"}` verilir. Yeni Windows **ikisini birden** verir:
  `{"server":"http://<ip>:<8787 portu>","link":"ws://<ip>:47800/nino/ws"}`. Eski TV uygulaması `server`'ı kullanır,
  yeni web TV `link`'i tercih eder — **açık karar**: ikisi birden gelirse yeni TV'nin önceliği tv-web tarifinde
  yazılı değil; öneri `link` öncelikli (tv-web oturumuna onaylatılmalı). Samsung'da parametreler `metaTag` JSON
  metninin içine aynı biçimde girer.
- 47800 doluysa: 8787'deki gibi 6 × 1 sn denenir; yine olmazsa giriş açılmaz (web TV'ler yalnız 47800'ü tarar,
  rastgele port işe yaramaz), günlüğe yazılır, eski 8787 yolu çalışmaya devam eder.

### 11.5 Windows'a özgü uygulama notları
- Giriş sunucusu `HttpListener` ile **yazılmamalı** (yerel olmayan adreste URL ACL ya da yönetici ister). 8787
  sunucusundaki gibi düz `TcpListener` + elle HTTP ayrıştırma; `/nino/ws` isteğinde `Sec-WebSocket-Key` ile
  `Sec-WebSocket-Accept` (SHA-1 + base64, RFC 6455) elle hesaplanıp `101 Switching Protocols` yazılır, sonra .NET'in
  akış üstünden WebSocket kurma yeteneğiyle (sunucu rolü, canlı tutma aralığı kapalı; kendi ping'imiz var) devam edilir.
  Böylece yeni paket gerekmez.
- Giden bağlantı için .NET'in istemci WebSocket'i yeter (düz `ws://`, sertifika yok).
- Güvenlik duvarı kuralı program kapsamlı olduğu için 47800'ü de kapsar; ek kural gerekmez.
- Mesaj üreten tek yer olmalı: eski 8787 çerçevesi ve yeni JSON aynı olaydan üretilsin (çifte yuvarlama farkı çıkmasın).
- Sınama: 47800 giriş ve çıkış testleri gerçek ağ yerine geri döngü (127.0.0.1) üzerinde, rastgele portla yapılır.

### 11.6 Açık kararların özeti
1. `screen` 16 KB'ı aşarsa ne yapılacağı (§11.1).
2. Android TV adresi bulunamazsa mDNS mi `/nino/info` taraması mı (§11.3).
3. `replaced` sonrası yeniden bağlanma politikası (§11.3).
4. `server` + `link` birlikte verildiğinde yeni web TV'nin önceliği (§11.4) — tv-web oturumuyla netleşmeli.
5. 8787'ye `stopped` eklensin mi (öneri: evet).

## 12. Ana oturumun kararları (§11.6'daki açık sorular)
1. **16 KB:** TV'ler 512 KB'a kadar kabul eder (protokol kararı), ama `cover` taşımayan mesajlar 16 KB altında tutulur.
   Çok öğeli `screen` sınırı aşarsa listenin sonundan (sıra: köşe → ipucu → mesaj kartı → telefon → harita; sondakiler
   önce) öğe atılarak sığdırılır; atılan sayısı altyazı günlüğüne yazılır.
2. **Android TV'yi bulma:** önce kendi yazdığımız küçük mDNS sorgusu (`_nino._tcp.local`, UDP 5353, paket yok); 3 sn'de
   cevap yoksa yerel /24 ağında `GET http://<ip>:47800/nino/info` taraması (aynı anda 24, 1.2 sn zaman aşımı). Kayıtlı
   TV adresi varsa önce o denenir.
3. **`replaced`:** başka bir gönderici TV'yi aldıysa kendiliğinden yeniden bağlanılmaz (iki bilgisayar birbirini atıp
   durmasın). Yeniden bağlanma yalnız kullanıcı çeviriyi yeniden başlatınca ya da TV'yi yeniden seçince.
4. **`server` + `link`:** LG/Samsung açılış parametresine ikisi de konur; hangisini kullanacağına TV uygulaması karar
   verir (yeni web TV `link`'i önce dener, eski TV yalnız `server`'ı bilir).
5. **Eski 8787'ye `stopped`:** evet, eklenir (eski TV'ler bilinmeyen olayı yok sayar).

## 13. Bağlantı olayları ve nedenleri

TV tarafı ölü bağlantıyı artık kendisi yakaladığı için göndericinin canlılık kuralları zorunludur:
- **Yeni protokol (47800, iki yön):** bağlıyken 5 sn'de bir `ping`; TV'den 15 sn hiçbir şey gelmezse bağlantı
  kapatılır (§11.1). Göndermezsek TV 15 sn'de yeniden bağlanır.
- **Eski 8787 SSE:** 15 sn'de bir kalp atışı (§3.3); yazma hatası alınan dinleyici listeden düşürülür (§3.2).

Her TV bağlantısı (8787 TV istemcisi, 47800'e gelen web TV, Android TV'ye giden bağlantı; **OBS izleyicisi hariç**)
`TvOutput` üzerinden iki olay üretir. Olaylar her iş parçacığından gelebilir; aynı bağlantının kimliği (`Id`) eşleşir.
- `TvLinkConnected(Id, Kind, Port, Address, Model?, AppVersion?, Took)`: 8787'de akış açılınca (model `?model=`
  sorgusundan), 47800'de `welcome` gelince (model ve sürüm `welcome`'dan). `Took`: bağlantının açılışından hazır
  olmasına kadar (8787'de 0).
- `TvLinkDropped(Id, Kind, Port, Address, Reason, WasConnected, After, Model?, AppVersion?, Detail?)`.

| Neden kodu | Anlamı | Nereden |
|---|---|---|
| `closed` | TV kapattı ya da bağlantı karşıdan koptu (kapanış çerçevesi, 0 bayt okuma, bağlantı sıfırlandı) | hepsi |
| `write_failed` | TV'ye yazılamadı | hepsi |
| `silence` | 15 sn TV'den hiçbir şey gelmedi | 47800 |
| `handshake` | 5 sn'de `welcome` gelmedi ya da ortak sürüm yok; bağlantı hiç kurulmadı (`WasConnected` = false) | 47800 |
| `replaced` | başka bir gönderici TV'yi aldı | 47800 |
| `stopped` | Nino kapattı (çeviri durdu, Android TV yeniden başlatıldı, uygulama kapanıyor) — kopma değildir | hepsi |
| `error` | sınıflanamayan hata (512 KB'ı aşan ya da bozuk mesaj, beklenmeyen istisna) | hepsi |

Ortak sürüm önerilip yeniden denenecekse (`version_unsupported` + ortak sürüm var) olay çıkmaz. Hazır olmadan biten
öteki bağlantılar (ör. `welcome`'dan önce kapanan) bildirilmez.

**Günlük:** altyazı günlüğüne (altyazi.log; `TvOutputOptions.Log`) yazılır, adres günlükte durur:
`TV bağlandı (8787, Samsung QE65Q80C): 192.168.1.20`, `TV bağlandı (47800 web TV, OLED55C3, uygulama 3.2): …`,
`TV koptu (Android TV 47800): 15 sn sessizlik [silence], 42 sn bağlı kaldı: …`,
`TV ile el sıkışılamadı (47800 web TV): welcome gelmedi [handshake]: …`, `TV bağlantısı kapatıldı (…): Nino kapattı [stopped]`.
Art arda gelen el sıkışma hataları (Android TV'ye yeniden deneme döngüsü) aynı yol için bir kez yazılır; bir bağlantı
kurulunca seri sıfırlanır.

**Ölçüm** (`olcum.md`; denetleyici yapar, adres ve TV adı asla gitmez):
- `tv_connect` `r:"ok"` her bağlantıda (çeviri dışında da). `ms`: TV bekçisi bir deneme başlattıysa (çeviri başladı ya da
  TV düştü) onun başından, yoksa bağlantının `Took`'u. `proto`: 8787 → `legacy`, 47800 → `nino`.
- `handshake` → başarısız `tv_connect`: `welcome` gelmedi `tv.connect.timeout`, sürüm yok `tv.protocol.mismatch`;
  deneme başına bir kez (bağlantı kurulunca ya da bekçi yeniden başlayınca sıfırlanır).
- `tv_drop` yalnız bağlanmış bir bağlantı **çeviri sürerken** bitince; `after` = bağlı kalınan saniye. Kod eşlemesi
  `olcum.md` tablosuna göre: `closed` → `closed`, `write_failed` → `write_error`, `silence` → `timeout`, `error` →
  `other`; `replaced` tabloda yok, kendi adıyla `replaced` gider (sunucunun kod kuralına uyar). `stopped` gönderilmez.
- `brand`: Android TV bağlantısı → `androidtv`; 47800 girişi → kayıtlı TV LG/Samsung ise o (giriş yalnız web TV'lere
  açık; `welcome` markayı söylemez); 8787 → kayıtlı TV markası (bilinmiyorsa boş).
- `model`/`tvApp` şimdilik gönderilmez (isteğe bağlı alanlar).
