# Android: TV tarafı (altyazı gönderme, TV bulma, TV uygulaması kurma) — davranış tarifi

Bu belge eski Android telefon uygulamasının TV ile ilgili **ne yaptığını** anlatır, nasıl yazıldığını anlatmaz.
Temiz-oda yeniden yazımı için hazırlandı: eski koddan sınıf adı, işlev adı ya da kod parçası yok. Adı geçenler
yalnız şunlar: ağda giden alan adları ve portlar (bunlar protokolün kendisidir), TV'lerin kendi kabuk komutları,
Samsung/LG/Google'ın kamuya açık uç noktaları, Android'in kendi API'leri ve kullanıcıya gösterilen metinlerin
`strings.xml` anahtarları.

Yeni protokolün tarifi: `NinoCore/docs/tarif/protokol.md`. Yeni uygulama TV'ye onunla gönderecek. Farklar ve
yeni protokolde karşılığı olmayan alanlar 1.6 ve 1.7'de.

---

## 1. Eski altyazı sunucusu

### 1.1 En önemli fark: roller ters

| | Eski | Yeni (protokol sürüm 1) |
|---|---|---|
| Kim dinler | **Telefon** dinler (sunucu) | **TV** dinler (gösterici) |
| Kim bağlanır | **TV** telefona bağlanır | **Telefon** TV'ye bağlanır |
| Port | **8787** TCP (sabit; Mac ve Windows da aynı) | **47800** TCP (ayarlanabilir) |
| Taşıma | HTTP üstünde **Server-Sent Events** (tek yönlü, telefondan TV'ye) | HTTP + **WebSocket** (çift yönlü) |
| Bulma | TV, kendi /24 ağını tarar, her adrese `GET /hello` sorar | Telefon Bonjour `_nino._tcp` ile TV'yi bulur ya da elle IP + `GET /nino/info` |
| Aynı anda | Birden çok TV ve izleyici aynı anda bağlanabilir | TV tek göndericiyi kabul eder |

Sonuç: eskide telefonun TV'yi bulmasına gerek yoktu; TV telefonu kendisi buluyordu. Telefondaki SSDP araması
(bölüm 2) yalnız "ağda hangi TV var" listesi ve TV uygulaması kurulumu içindi. **Yeni uygulamada altyazı
bağlantısı için telefonun TV'yi bulması şart:** mDNS taraması ve elle adres yolu altyazının ana yolu olur.

### 1.2 Sunucunun yaşam döngüsü

- Sunucu, çeviri hizmeti başlayınca açılır ve çeviri durunca kapanır. Çeviri yokken TV bağlanamaz; TV bekleme
  ekranında kalır ve aramayı sürdürür.
- Port açılamazsa (başka uygulama 8787'yi tutuyorsa) çeviri yine sürer ama ekranda `error_port` hatası çıkar.
- Sunucu açılır açılmaz o anki görünüm ayarı (`style`) bir kez yayınlanır ve saklanır.
- Bağlı TV sayısı her değiştiğinde ana ekrandaki durum ve "sorun geçmişi" güncellenir. Sayı 0'dan 1'e çıkınca
  kullanım verisine "TV bağlandı" olayı yazılır.
- Hedef "telefon ekranı" seçiliyse altyazı olayları TV'lere **gitmez** (yalnız izleyicilere gider). `style` ve
  `started` yine TV'ye gider. Hedef çeviri sürerken değişirse bu anında uygulanır.
- Sunucudan geçen her altyazı ve temizleme olayı telefonun kendi ekranındaki altyazı görünümüne de verilir.

### 1.3 HTTP yolları

Sunucu, isteğin ilk satırını ve başlıklarını boş satıra kadar okur. Başlıklar 64 KB'ı geçerse bağlantı kapanır.
Bütün yanıtlarda `Access-Control-Allow-Origin: *` vardır; TV sayfası bir web uygulamasıdır.

| İstek | Yanıt |
|---|---|
| `OPTIONS *` | `204 No Content`, bağlantı kapanır (CORS ön isteği) |
| `GET /hello` | `200`, gövde tam olarak `{"app":"nino"}`, bağlantı kapanır. TV taramada bunu arar. |
| `GET /events` | SSE akışı açılır (aşağıda) |
| `GET /events?model=<TV modeli>` | Aynı akış. TV kendi marka ve modelini söyler, ör. "Samsung QE65Q80C". |
| `GET /events?viewer=obs` | "İzleyici" akışı: OBS gibi yayın araçları için. TV sayısına katılmaz. Hedef telefon olsa da altyazıyı alır. |
| Başka her şey | `404`, bağlantı kapanır |

`model` değeri URL çözülür. Yalnız harf, rakam, boşluk ve `.-_()` kalır, en çok 60 karakter tutulur. Boşsa yok
sayılır. Model, sorun bildirimlerine "TV modeli" olarak eklenir.

### 1.4 Akışın biçimi

- Yanıt başlıkları: `200 OK`, `Content-Type: text/event-stream; charset=utf-8`, `Cache-Control: no-cache`,
  `Connection: keep-alive`, CORS.
- İlk satır `retry: 2000`. Tarayıcının EventSource'u kopunca 2 sn sonra yeniden dener.
- Ardından, bağlanan TV'ye hemen:
  1. son `style` olayı (varsa);
  2. çeviri **son 20 saniye içinde** başladıysa bir `started` olayı. Böylece geç bağlanan TV de "çeviri başladı"
     balonunu görür. İzleyicilere gitmez.
- Her olay standart SSE biçimindedir: `event: <ad>`, sonra `data: <tek satır JSON>`, sonra boş satır.
- **JSON biçimi Mac/Windows ile bayt bayt aynıdır:** anahtarlar alfabetik sıralı, boşluk yok, Türkçe harfler
  kaçışsız (yalnız `"`, `\` ve satır sonu kaçışlı). Kutu oranları 0–1'e sıkıştırılır, dört basamağa yuvarlanır,
  sondaki sıfırlar atılır (0.8750 → 0.875; 1.0 → 1). Açı tek basamağa yuvarlanır ve işaretli olabilir.
- **Canlı tutma:** 15 saniyede bir hem bir SSE yorum satırı (`: ping`) hem de adlı bir `ping` olayı (`data: {}`)
  gider. Yorumu EventSource görmez; adlı olayı TV sayfası görür ve "bağlantı canlı" sayar.
- TCP canlılık denetimi (keepalive) açık, Nagle kapalıdır: küçük olaylar beklemeden gider.
- Yazma tek bir gönderim iş parçacığında, sırayla yapılır. Yazma hatası alan TV kopmuş sayılır ve listeden çıkar.
  Yavaş bir TV öbürlerini bekletmez.
- TV bağlantıyı kapatınca (okuma biter) TV listeden çıkar.

### 1.5 Olaylar ve alanları

**`subtitle`** — altyazıyı göster

| Alan | Ne |
|---|---|
| `text` | Gösterilecek çeviri (zorunlu). Satır sonu içerebilir. |
| `duration` | Ekranda kalma süresi, ms. Normal altyazıda **15000**, deneme altyazısında 8000, bilgi iletilerinde 2500–6000. |
| `at` | Telefonun gönderdiği an (Unix ms). |
| `box` | İsteğe bağlı. Oyundaki İngilizce altyazının ekrandaki yeri: `left`, `top`, `right`, `bottom` (0–1, üstten ve soldan oran). TV çeviriyi buna göre yerleştirir. |
| `replace` | İsteğe bağlı, yalnız `true`. Satır az önceki satırın uzamış ya da düzelmiş okumasıdır. TV onu öncekinin üstüne yığmaz, yerine koyar. Eski TV uygulamaları yok sayar. |
| `paragraphs` | İsteğe bağlı, yalnız `true`. Metin çok parçalıdır; TV satır satır, sola yaslı gösterir. |

**`clear`** — altyazıyı kaldır. Gövde `{}`. Kimlik yok; ekrandaki altyazı ne olursa silinir.

**`style`** — TV'deki görünüm. Çeviri başlayınca, her TV bağlandığında ve Ayarlar'da her değişiklikte gider.

| Alan | Değerler | Ne |
|---|---|---|
| `autoSize` | true/false (varsayılan true) | TV yazı boyunu oyunun İngilizce satırına uydursun mu. Açıkken TV `fontSize`'ı yok sayar. |
| `background` | 0–100 tam sayı (varsayılan 100) | Kutunun koyuluğu, yüzde. TV 100'e böler. |
| `backgroundShape` | `fit` / `band` | Kutu yazı kadar mı, ekran boyu bant mı. Eski TV'ler tanımaz, `fit` gibi davranır. |
| `bold` | true/false | Kalın yazı. |
| `bottomPercent` | tam sayı (varsayılan 7) | Sabit yerleşimde alttan uzaklık, yüzde. |
| `displayMode` | `inApp` / `overlay` | Yalnız Android TV: PS5 görüntüsü TV uygulamasının içinde mi, yoksa altyazı HDMI ekranının üstünde katman mı. |
| `font` | `condensed` / `modern` / `rounded` / `system` | Yazı tipi. Tanınmayan ya da eksik ad `condensed` olur. |
| `fontSize` | 36 küçük, 46 orta (varsayılan), 58 büyük, 72 çok büyük | Yazı boyu. |
| `placement` | `cover` / `above` / `below` / `fixed` | Çevirinin oyundaki İngilizce altyazıya göre yeri: üstünü örter, üstünde, altında ya da sabit yerde. |
| `stackPrevious` | true/false (varsayılan true) | Hızlı konuşmada önceki satırlar yeni satırın üstünde kısa süre soluk kalsın mı. |
| `textColor` | `white` / `yellow` | Yazı rengi. |
| `watermark` | true/false (varsayılan true) | TV'nin sol altındaki küçük Nino işareti. |

**Koyuluk kuralı:** `cover` kipinde koyuluk %60'ın altındaysa TV'ye 100 gider. Saydam kutu oyundaki İngilizceyi
gizleyemez, iki yazı karışır. Bu kural ayar kaydedilirken uygulanır. Ayarlar'daki kaydırıcı o kipte %60'tan
başlar ve gösterdiği yüzde TV'ye gidenle aynıdır. Öbür kiplerde 0–100 aralığının tamamı geçerlidir. Aralık dışı
değer sınıra çekilir.

**`region`** — ek alan çevirisi (görev yazısı, oyun içi telefon, bildirim gibi, kullanıcının işaretlediği alanlar)

| Alan | Ne |
|---|---|
| `id` | Alanın kimliği (metin). |
| `text` | Çeviri. **Boşsa o alanın kutusu kalkar.** |
| `box` | İsteğe bağlı. Yazının karedeki yeri (0–1). |
| `line` | İsteğe bağlı. Satır yüksekliği, ekran yüksekliğine oranla (0–1, dört basamak). |

**`region-clear`** — bütün ek alan kutuları kalkar (çeviri durdu). Gövde `{}`.

**`screen`** — "Ekranı çevir" sonuçları ve oyun sürerken gelen yan çeviriler

| Alan | Ne |
|---|---|
| `duration` | ms. Elle "Ekranı çevir"de kullanıcının seçtiği süre; sürekli yan çevirilerde 120000. |
| `overlay` | İsteğe bağlı, yalnız `true`. Sürekli gelen yan çeviriler (oyunun telefonundaki mesajlar, harita kartı). TV o an görünen altyazıyı **silmez**. Bu olay telefonun kendi ekranına da gitmez. |
| `items` | Liste, en çok 30 öğe. Her öğe aşağıda. |

Her `items` öğesi:

| Alan | Ne |
|---|---|
| `text` | Çeviri. Parçalar ayrı satırlarda. |
| `box` | Yazının yeri (0–1). |
| `line` | Tipik satır yüksekliği (0–1). Yazı boyu buna göre seçilir. |
| `paragraphs` | `true`: çok satırlı, sola yaslı. |
| `plain` | `true`: arka kutu çizilmez; yazı yalnız gölgeyle, oyundaki yazıya benzer biçimde durur. |
| `italic` | `true`: eğik yazı (telefon araması). |
| `fill` | Oyunun kutusunun rengi, `#rrggbb`. Verilmişse Türkçe aynı zeminle yazılır. |
| `ink` | Yazı rengi, `#rrggbb` (`fill` ile birlikte). |
| `angle` | Dönme açısı, derece, saat yönü artı. Yalnız mutlak değeri 0.3'ten büyükse gider. Eğik tutulan telefonun balonları için. |
| `alpha` | Zeminin saydamlığı, 0–1, iki basamak (`fill` ile). |
| `side` | `true`: balon oyunun kutusunun üstünde değil yanında. TV daha yuvarlak ve gölgeli çizer. |
| `backdrop` | `true`: yazısız zemin (oyun telefonunun yanındaki mesaj paneli). Balonlar onun üstünde durur. |
| `card` | `true`: haritadaki görev kartının çevirisi; TV onu oyundaki karta benzeyen bir kart olarak çizer. |

**`screen-clear`** — "Ekranı çevir" çevirileri kalkar, altyazıya dokunulmaz. Gövde `{}`.

**`started`** — çeviri başladı. TV robotun yanında 7 sn `translation_started_notice`
balonunu gösterir (`translation_started_notice`). Gövde `{}`. Altyazı olayı sayılmaz: hedef telefon olsa da TV'ye
gider. Eski TV'ler yok sayar.

**`ping`** — 1.4'te anlatıldı.

### 1.6 Eski olay → yeni mesaj eşlemesi

| Eski | Yeni | Not |
|---|---|---|
| `GET /hello` → `{"app":"nino"}` | `GET /nino/info` → `info` (ad, kimlik, sürümler) | Yön ters: artık telefon TV'ye sorar. |
| `subtitle` (`text`, `duration`) | `show` (`id`, `text`, `durationMs`, `source`, `position`) | Yeni protokolde altyazı **numarası (`id`) zorunlu**. Eskide yoktu; yeni uygulama her satıra artan bir numara vermeli. |
| `clear` | `clear` (isteğe bağlı `id`) | Yeni uygulama geç gelen temizlemenin yeni satırı silmemesi için `id` göndermeli. Eskide bu koruma yoktu. |
| `ping` (telefondan TV'ye, 15 sn) | `ping`/`pong` (telefondan, 5 sn; TV aynı `t` ile yanıtlar) | 15 sn yanıt yoksa telefon yeniden bağlanır (1, 2, 4, 8 sn). |
| SSE `retry: 2000` (TV yeniden bağlanır) | Yeniden bağlanma telefonun işi | |
| Bağlanınca son `style` yeniden gönderilir | — | Yeni uygulama her `welcome`'dan sonra görünümü yeniden göndermeli (alan eklenince). |
| Yok | `hello`/`welcome`/`error` el sıkışması, sürüm pazarlığı | `version_unsupported` gelirse kullanıcıya `tvapp_update_button` denmeli (bölüm 3.5 ile bağlanabilir). |

### 1.7 Yeni protokolde karşılığı olmayan alanlar

Bunlar ileride protokole **isteğe bağlı alan** ya da yeni `type` olarak eklenmeli. Protokolün kuralı gereği
isteğe bağlı alan eklemek sürümü artırmaz, bilinmeyen alan ve tür yok sayılır.

**`show` mesajına eklenecekler**
- `box` (left/top/right/bottom, 0–1): İngilizce altyazının yeri. Yeni protokolde yalnız `position: bottom|top`
  var. `cover`/`above`/`below` yerleşimleri bu bilgi olmadan çalışmaz. **En önemlisi bu.**
- `replace` (bool): önceki satırın düzeltilmiş okuması; yığma yerine yerine koyma.
- `paragraphs` (bool): çok parçalı, sola yaslı gösterim.
- `at` (Unix ms): gönderilme anı. Eskide gidiyordu; TV'nin kullanıp kullanmadığı belirsiz.
- Varsayılan süre farkı: eski normal altyazı 15 sn sonra kendiliğinden kalkardı. Yenide `durationMs` 0 ya da yoksa
  `clear` gelene kadar kalır. Yeni uygulama ya `durationMs: 15000` göndermeli ya da kendisi `clear` yollamalı.

**Yeni bir `style` mesajı (bütün alanlarıyla)** — yeni protokolde görünüm ayarı hiç yok:
`autoSize`, `background`, `backgroundShape`, `bold`, `bottomPercent`, `displayMode`, `font`, `fontSize`,
`placement`, `stackPrevious`, `textColor`, `watermark`. Bağlantı başında ve her değişiklikte gönderilmeli. TV
bağlantı kopunca son görünümü korumalı.

**Yeni `region` / `region-clear` mesajları:** `id`, `text` (boşsa kaldır), `box`, `line`.

**Yeni `screen` / `screen-clear` mesajları:** `duration`, `overlay`, `items[]` ve öğe alanları `text`, `box`, `line`,
`paragraphs`, `plain`, `italic`, `fill`, `ink`, `angle`, `alpha`, `side`, `backdrop`, `card`.

**Yeni `started` mesajı.** TV'nin 20 sn içinde bağlanırsa yine göstermesi kuralıyla.

**`hello` mesajına eklenecekler**
- TV modeli eskide TV'den telefona gidiyordu (`?model=`). Yenide yön ters. TV modeli `GET /nino/info` ya da
  `welcome` cevabına isteğe bağlı `model` alanı olarak eklenmeli. Sorun bildirimleri bunu kullanıyor.

**Protokol düzeyinde eksikler**
- **İzleyici (OBS) akışı:** eskide `?viewer=obs` ile ayrı, TV sayısına katılmayan dinleyiciler vardı. Yenide TV
  tek göndericiyi kabul eder; telefonda dinleyen sunucu yok. Ya ayrı bir izleyici yolu eklenmeli ya da bu özellik
  bilerek bırakılmalı.
- **Birden çok TV:** eskide aynı anda birden çok TV bağlanabiliyordu. Yenide gönderici her TV'ye ayrı bağlantı açmalı.
- **16 KB sınırı:** 30 öğeli bir `screen` mesajı (her öğe kutu, renk, açı taşır, metinler uzun olabilir) 16 KB'ı
  aşabilir. Ya sınır yükseltilmeli ya da gönderici bölmeli.
- **Erişim:** eski sunucu CORS'u herkese açıktı, adres süzgeci yoktu. Yeni TV yalnız özel IP aralıklarını kabul
  eder. Bu bir daralma, sorun değil.
- **TV'nin kendiliğinden temizlemesi:** yeni TV 20 sn hiç mesaj almazsa ekranı temizler. 5 sn'lik `ping` bunu
  önler; eskide böyle bir kural yoktu.

---

## 2. TV bulma ve elle adres

### 2.1 SSDP araması (telefondan)

- UDP ile `239.255.255.250:1900` adresine `M-SEARCH` gönderilir: `MAN: "ssdp:discover"`, `MX: 2`. Üç arama hedefi
  (ST) vardır ve her biri **iki kez** gönderilir:

| ST | Marka |
|---|---|
| `urn:lge-com:service:webos-second-screen:1` | LG |
| `urn:samsung.com:device:RemoteControlReceiver:1` | Samsung |
| `urn:dial-multiscreen-org:service:dial:1` | Android TV (DIAL; Chromecast/Google TV de bununla görünür) |

- Yanıtlar yaklaşık **3 sn** dinlenir (her okuma 300 ms bekler). Yanıttaki `ST` ya da `NT` satırından marka,
  `LOCATION` satırındaki URL'nin sunucusundan TV adresi çıkarılır. Hedeflerden biri değilse yanıt atılır.
- Aynı adres birden çok yanıt verirse LG/Samsung, DIAL'a üstün gelir. Birçok LG ve Samsung TV DIAL'a da yanıt verir.
- TV'nin adı için `LOCATION` adresindeki aygıt tanımı (XML) okunur ve `<friendlyName>` alınır, ör.
  "[LG] webOS TV <model>". Okuma 1,5 sn bağlantı + 1,5 sn okuma süresiyle sınırlıdır. Okunamazsa ad "LG TV",
  "Samsung TV" ya da "Android TV" olur.
- Bu arama şu yerlerde yapılır: profil ekranındaki "ağdaki TV'ler" bilgisi, ilk kurulumda TV seçimi, TV kurulum
  ekranı (marka henüz seçilmemişse ilk bulunan LG/Samsung, yoksa ilk bulunan, hiçbiri yoksa Samsung seçilir) ve
  her markanın kurulum ekranı.

### 2.2 Markaya göre ek arama

- **Samsung:** önce SSDP. Her bulunan TV'ye ayrıca `http://<TV>:8001/api/v2/` sorulur (1,5 sn, iki deneme).
  SSDP hiç yanıt vermezse telefonun /24 ağındaki 254 adresin hepsine (kendisi hariç, aynı anda en çok 32) aynı
  soru 700 ms süreyle sorulur. Yanıtın `device` nesnesinden şunlar okunur:
  - `name` ve `modelName`;
  - `developerMode` ("1" ya da "true" açık demek);
  - `developerIP` ("0.0.0.0" yok sayılır).
  Bu bilgiyle listede `tvinstall_dev_on` (`tvinstall_dev_on`), "kapalı" (`tvinstall_dev_off`) ya da
  `tvinstall_dev_other_ip` (`tvinstall_dev_other_ip`) yazılır.
- **Android TV:** DIAL ile görünenler + telefonun /24 ağında **5555 portu açık** olanlar (700 ms bağlantı denemesi,
  aynı anda en çok 32). 5555'i açık olanlar listede üstte ve `tvinstall_android_debug_on` yazılı
  (`tvinstall_android_debug_on`). İlk 5555'i açık TV kendiliğinden seçilir.
- **LG:** yalnız SSDP. Her bulunan TV için 9922 portuna 1,5 sn bağlantı denenir; açıksa geliştirici modu açık
  sayılır. Geliştirici modu açık ilk TV, yoksa ilk TV seçilir.
- Hiç TV bulunamazsa elle adres alanı kendiliğinden açılır. Bulunsa da "TV'm listede yok" (`tvinstall_not_found`)
  ile açılabilir.

### 2.3 Telefonun kendi adresi

Samsung'un geliştirici modunda "Host PC IP" olarak yazılacağı için gösterilir. Seçim sırası şöyle:
1. Wi-Fi ağındaki ilk IPv4 adresi (geri döngü olmayan);
2. yoksa Ethernet ağındaki;
3. VPN ağları atlanır.

Bulunamazsa `tvinstall_phone_ip_unknown` (`tvinstall_phone_ip_unknown`) yazılır.

### 2.4 Elle adres temizleme

Elle yazılan TV (ve PS5) adresi şu kurallarla temizlenir:
- Baştaki ve sondaki boşluk atılır. **Virgüller noktaya döner**: Türkçe sayı klavyesinde nokta yok, kullanıcılar
  "192,168,1,5" yazıyordu.
- `http://` gibi `://` ile biten önek atılır. İlk `/`, `?` ya da `#`'den sonrası atılır.
- Tek bir `:` varsa port sayılıp atılır. Port boş ya da rakam dışıysa adres reddedilir. Birden çok `:` (IPv6)
  reddedilir; TV'ler IPv4 ile eşleşir.
- Sondaki tek nokta atılır.
- Yalnız rakam ve noktadan oluşuyorsa tam dört parça, her biri 1–3 hane ve 0–255 olmalı. Baştaki sıfırlar
  düşer, "010" → "10" olur.
- Değilse ağ adı olarak kabul edilir (RFC 1123: harf, rakam, tire; etiket 1–63, tireyle başlamaz/bitmez; en az
  bir harf; en çok 253 karakter) ve küçük harfe çevrilir, ör. "lgwebostv.local".
- Uymazsa `address_invalid`
  (`address_invalid`).
- LG ve PS5 ekranları bu temizlemeyi kullanır. Samsung ekranı yalnız boşluğu kırpar. Android TV ekranı portu
  ayrıca okur (3.1).

### 2.5 Eski TV uygulamasının telefonu bulması (yeni protokolde gerekmez, bilgi için)

- TV, telefonun adresini saklar ve önce ona bağlanır. Art arda 3 hata olursa 3 sn içinde, değilse 30 sn sonra ağ
  taranır.
- Taranan ağlar: TV'nin kendi /24 ağı (TV adresini söyleyebiliyorsa, en çok 3 sn beklenir) ve saklı adresin /24
  ağı. Her adrese `http://<adres>:8787/hello` sorulur: 1,2 sn süre, aynı anda 24 istek. Yanıt 200 ve gövdede
  "nino" geçiyorsa bulunmuş sayılır, adres saklanır ve `/events`'e bağlanılır.
- Bulunamazsa 30 sn sonra yeniden taranır.

---

## 3. Telefondan TV'ye uygulama kurma

Ortak noktalar:
- Telefon ve TV aynı Wi-Fi'da olmalı. Bilgisayar gerekmez.
- Ekran üstte marka seçici gösterir: Samsung, LG, Android TV. Seçim saklanır.
- TV paketleri telefon uygulamasının içinde gelir (3.5). Paket yoksa `tvinstall_err_package_missing`
  (`tvinstall_err_package_missing`).
- Her adım ve TV'nin bütün yanıtları uygulamanın klasöründeki bir kurulum günlüğüne zaman damgasıyla yazılır.
  Günlük 512 KB'ı geçince baştan başlar. Hata ekranında `tvinstall_share_log` (`tvinstall_share_log`)
  günlüğün son 60.000 karakterini paylaşım menüsüyle gönderir.
- İlerleme adımları kullanıcıya Türkçe gösterilir (`tvinstall_step_*`): bağlanılıyor, TV okunuyor, eşleniyor,
  TV'de onay, anahtar alınıyor, Samsung girişi, sertifika, imzalama, kuruluyor, eski kopya kaldırılıyor,
  uygulama açılıyor.
- Bütün markalarda akış aynıdır:
  1. TV'deki sürümü oku.
  2. Telefondaki sürümle karşılaştır (3.5).
  3. TV'deki **aynı ya da yeni** ise yalnız uygulamayı aç (`tvinstall_up_to_date`,
     `tvinstall_up_to_date`).
  4. Eski ya da yoksa kur, doğrula, aç.
  5. Uygulama açılamasa da kurulum başarılı sayılır.
- Başarıdan sonra TV (marka, adres, Android TV'de port, sürüm) kaydedilir. Altyazı hedefi "TV" yapılır ve ilk
  kurulum tamamlanmış sayılır; yoksa uygulama her açılışta ilk kurulumun 3. adımına dönüyordu. Ekranda "Kurulum tamam:
  Nino … TV'de başlatılıyor." ve "TV'de Nino'nun bekleme ekranı görünür … Şimdi ana ekranda çeviriyi başlatın;
  telefon TV'yi kendisi bulacaktır." (`tvinstall_done`, `tvinstall_next`). Yeni protokolde TV'yi telefon bulur; son
  cümle buna göre yazıldı.
- İşler arka planda (IO iş parçacığı) yapılır. Kurulum sırasında marka seçici gizlenir, düğme kapalıdır.

### 3.1 Android TV / Google TV (ADB)

#### Kullanıcı adımları

İki bağlantı yolu vardır, ekranda "Bağlantı yolu" seçicisiyle seçilir (`tvinstall_android_mode`).

**a) USB/ağ hata ayıklama (varsayılan, port 5555)**
1. Geliştirici seçeneklerini görünür yapın: TV'de Ayarlar › Sistem (veya Cihaz Tercihleri) › Hakkında ›
   "Android TV OS derlemesi" satırına üst üste 7 kez dokunun.
2. Ayarlar › Sistem › Geliştirici seçenekleri altında USB hata ayıklama'yı etkinleştirin. Kimi TV'lerde ek olarak
   "Ağ hata ayıklaması" / "ADB over network" seçeneği bulunur; varsa onu da etkinleştirin.
3. "Kur ve aç"a dokunun. TV'de "USB hata ayıklamasına izin verilsin mi?" penceresi çıktığında "Bu cihazdan her
   zaman izin ver" kutusunu işaretleyip İzin ver'i seçin.

Adres alanı: "TV'nin IP adresi". Port yazılmazsa 5555 kullanılır.

**b) Kablosuz hata ayıklama (Android 11+, Google TV)**
1. Aynı 1. adım.
2. Geliştirici seçenekleri › Kablosuz hata ayıklama'yı etkinleştirip bu bölüme girin. En üstte görünen "IP adresi
   ve bağlantı noktası" değerini TV adresi alanına girin, ör. `192.168.1.20:41235`. **Port zorunludur ve her açılışta değişir.**
3. İlk kurulumda "Cihazı eşleme kodu ile eşle"yi seçin. Açılan pencerede yazan adres ve portu 6 haneli kodla
   beraber girin, **pencere kapanmadan** "Kur ve aç"a dokunun. Daha önce eşlendiyse kod boş bırakılır.

Doğrulamalar şöyle:
- Kablosuz yolda port yoksa: `tvinstall_android_need_port` (`tvinstall_android_need_port`).
- Kod yazılmış ama eşleme adresi/portu yoksa: "Eşleme kodunu yazarken eşleme penceresinde görünen adresi ve portu
  da girin…" (`tvinstall_android_need_pair_port`).
- Koddan yalnız rakamlar alınır.
- "IP:port" ayrıştırmasında son `:`'dan sonrası 1–65535 olmalı.

#### Anahtar

- Telefon bir kez 2048 bit RSA anahtarı üretir ve uygulamanın yedeklenmeyen klasöründe PKCS#8 olarak saklar.
  Android TV için ayrı, Samsung için ayrı bir dosya tutulur.
- Açık anahtar adb'nin biçiminde gönderilir: Android `RSAPublicKey` yapısı (sözcük sayısı = 64, n0inv, modül ve R²
  küçük-endian 256'şar bayt, üs) base64'lenir, sonuna boşluk ve `nino@phone` eklenir.

#### Ağ adımları: ADB protokolü (AOSP `packages/modules/adb`, protocol.txt)

1. TCP bağlantısı (5 sn süre, Nagle kapalı).
2. Çerçeve biçimi: 24 baytlık küçük-endian başlık. Alanlar sırayla komut, arg0, arg1, veri uzunluğu, veri bayt
   toplamı ve komut XOR 0xFFFFFFFF; ardından veri gelir. Okurken yalnız sihirli sayı ve uzunluk (en çok 1 MB)
   denetlenir. Yeni adbd'ler denetim toplamını 0 gönderir, bu kabul edilir.
3. `CNXN` gönderilir: sürüm `0x01000001`, en büyük veri 256 KB, veri `host::` + NUL.
4. Gelen yanıta göre:
   - **`STLS`** (kablosuz hata ayıklama portu): `STLS` (sürüm `0x01000000`) geri gönderilir ve aynı soket üstünde
     **TLS 1.3** başlar.
     - Telefon, adb anahtarından üretilmiş kendinden imzalı X.509 sertifikasıyla kendini tanıtır: CN=Nino,
       10 yıl geçerli, imza SHA256withRSA, istemci imzası RSA-PSS-SHA256.
     - TV'nin sertifikası **denetlenmez** (adb de denetlemez).
     - TLS kurulamazsa ya da TLS'ten sonra bağlantı kapanırsa **"eşlenmemiş"** sayılır. TLS 1.3'te istemci el
       sıkışmayı TV'den önce bitirir; ret ancak sonraki okumada görünür.
   - **`AUTH` jeton (tür 1), ilk kez:** jeton imzalanıp `AUTH` imza (tür 2) gönderilir. **Dikkat:** adb imzası
     jetonu yeniden özetlemez. 20 baytlık jeton doğrudan SHA-1 DigestInfo önekiyle PKCS#1 v1.5 dolgusuna konup
     RSA ile imzalanır. Samsung'un sdb'si ise jetonu SHA1withRSA ile özetleyerek imzalanmasını bekler (3.3).
   - **`AUTH` jeton, ikinci kez:** imza tanınmadı, TV bu telefonu ilk kez görüyor. `AUTH` açık anahtar (tür 3)
     gönderilir, veri anahtar satırı + NUL. TV ekranında onay sorusu çıkar. Kullanıcıya "TV'de 'USB hata
     ayıklamasına izin verilsin mi?' penceresi çıkınca … İzin ver'e dokunun" (`tvinstall_step_approve`) gösterilir. Onay için
     **90 sn** beklenir. Bir kez daha jeton gelirse "onaylanmadı" sayılır.
   - **`CNXN`:** bağlantı kuruldu. En büyük veri = min(256 KB, TV'nin önerdiği; 0 ise 4096). Okuma süresi 120 sn
     olur. El sıkışma sırasında okuma süresi 10 sn'dir.
   - Başka bir paket gelirse "ulaşılamadı" sayılır.
5. Kanallar: `OPEN` (yerel kimlik, 0, hizmet adı + NUL) gönderilir, TV `OKAY` ile uzak kimliği verir.
   - Veri `WRTE` ile en büyük veri boyunda parçalar hâlinde gider; her parça için `OKAY` beklenir.
   - Gelen `WRTE`'ye `OKAY` dönülür. `CLSE` kanalı kapatır.
   - Bir anda tek kanal açıktır. Başka kanala gelen veriye `CLSE` dönülür.
6. Kullanılan hizmetler:
   - `shell:dumpsys package com.ninotranslator.tv`: `versionName=` ile kurulu sürüm, `installerPackageName=` ile
     kaynak (`com.android.vending` ise Google Play'den kurulmuş).
   - Kurulum (Android 7+): `exec:cmd package install -r -S <bayt>`. APK doğrudan kanala akıtılır.
   - Çıktıda ne "Success" ne "Failure" varsa (eski TV, `exec:` ya da `cmd package` yok): dosya `sync:` ile
     `/data/local/tmp/nino-tv.apk`'ya gönderilir. Akış: `SEND "yol,kip"` (kip = 0100000 | 0644, onluk), 64 KB'lık
     `DATA` paketleri, `DONE` + değiştirilme zamanı; TV `OKAY` ya da `FAIL <ileti>` döner. Sonra
     `shell:pm install -r <yol>` çalışır ve dosya silinir.
   - Katman izni: `shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow`. Çıktıda "Error",
     "Exception", "Unknown" ya da "not allowed" varsa `shell:pm grant com.ninotranslator.tv
     android.permission.SYSTEM_ALERT_WINDOW` denenir. Verilemezse kurulum yine başarılıdır.
     **Bu izin her seferinde verilir, "zaten güncel" durumunda da.** Verilmezse TCL TV'lerde "PS5 görüntüsü
     Nino'nun içinde gelmiyor…" uyarısı çıkar.
   - Açma: `shell:am start -n com.ninotranslator.tv/.MainActivity`.
   - Kaldırma (yalnız kullanıcı onayıyla): `shell:pm uninstall com.ninotranslator.tv`.

#### Kablosuz hata ayıklama eşlemesi (AOSP `pairing_connection`, `pairing_auth`)

Kod yazılmışsa bağlantıdan **önce** eşleme portuna bağlanılır (5 sn bağlantı, 15 sn okuma süresi).
1. TLS 1.3 (yukarıdaki gibi aynı sertifikayla).
2. TLS'ten dışa aktarılan anahtar malzemesi (RFC 8446 exporter): etiket `adb-label` + NUL, bağlam boş, 64 bayt.
3. Şifre = 6 haneli kod (ASCII) + bu 64 bayt.
4. SPAKE2 (BoringSSL'in edwards25519 SPAKE2'si):
   - Telefon "alice" rolündedir. Adlar NUL ile biter: `adb pair client` + NUL ve `adb pair server` + NUL.
   - M ve N noktaları BoringSSL'deki sabitlerdir.
   - Şifre SHA-512 ile özetlenir ve skalere indirgenir. BoringSSL'in "password scalar hack"i uygulanır: alt üç
     bit sıfır olacak biçimde l, 2l, 4l eklenir.
   - Özel skaler 64 rastgele bayttan indirgenip 8 ile çarpılır.
   - Sonuç anahtarı SHA-512 ile bulunur. Sırasıyla telefonun adı, TV'nin adı, telefonun mesajı, TV'nin mesajı,
     ortak nokta ve şifre özeti eklenir; her parçanın önünde 8 baytlık küçük-endian uzunluk durur. Çıkan 64 bayt
     anahtar malzemesidir.
5. Paket biçimi: sürüm baytı (1), tür baytı (0 = SPAKE2 mesajı, 1 = eş bilgisi), 4 bayt **büyük-endian**
   uzunluk, veri. Telefon SPAKE2 mesajını yollar, TV'ninkini okur.
6. Şifreleme anahtarı HKDF-SHA256 ile türetilir: tuz yok (32 sıfır bayt), bilgi `adb pairing_auth aes-128-gcm
   key`, 16 bayt. Şifre AES-128-GCM'dir.
   - Nonce 12 bayttır; ilk 8 baytı her yönde 0'dan sayan küçük-endian sıra numarasıdır.
7. Telefon 8192 baytlık eş bilgisini şifreleyip gönderir: ilk bayt 0 (RSA açık anahtar), ardından anahtar satırı.
   TV'nin eş bilgisi okunup çözülür. Çözülemezse ya da TV bağlantıyı kapatırsa **kod yanlış** sayılır.
8. Eşleme bitince TV bu telefonun anahtarını tanır. Bağlantı portunda TLS'le kabul edilir, onay sorusu çıkmaz.

#### Google Play yolu (kodda var, kapalı)

- Kodda Play yolu var: TV'de Play Store varsa Play sayfası açılır, kullanıcı TV'de Yükle'ye basar, sürüm 3 sn'de
  bir, 4 dk boyunca izlenir, süre dolarsa APK'ya geçilir.
- Ama **kapalı**. Play'deki aynı kimlikli uygulama bu uygulama değil, her zaman telefondaki APK kurulur.
- Yalnız "TV'deki kopya Play'den mi" bilgisi hata iletisini seçmek için kullanılır.

#### Hata durumları ve kullanıcıya gösterilen

| Durum | Ne zaman | İleti |
|---|---|---|
| Ulaşılamadı | Bağlantı kurulamadı, el sıkışmada koptu, beklenmeyen paket | `tvinstall_android_err_unreachable`: `tvinstall_android_err_unreachable` |
| Onaylanmadı | Onay beklenirken bağlantı kapandı, 90 sn doldu ya da TV yine sordu | `tvinstall_android_err_not_approved` |
| Eşlenmemiş | TLS reddedildi | `tvinstall_android_err_not_paired`: "önce eşleyin…" |
| Eşleme olmadı | Kod yanlış, pencere kapandı, TLS/SPAKE2 hatası | `tvinstall_android_err_pairing`: `tvinstall_android_err_pairing` |
| Yerine kurulamıyor | Çıktıda `INSTALL_FAILED_UPDATE_INCOMPATIBLE` ya da `INSTALL_FAILED_VERSION_DOWNGRADE` | Kaynak Play ise `tvinstall_android_err_play_copy`, değilse `tvinstall_android_err_other_copy` (0.9.18 ve önceki TV paketleri her derlemede değişen bir anahtarla imzalıydı). Altta **`tvinstall_android_replace`** düğmesi (`tvinstall_android_replace`) çıkar. Basılırsa kaldırılır ve yeniden kurulur; TV uygulamasının ayarları silinir. **Kendiliğinden kaldırılmaz.** |
| Kaldırma işe yaramadı | Kaldırıp kurduktan sonra yine aynı imza hatası | `tvinstall_android_err_remove_manually`: Ayarlar › Uygulamalar › Tüm uygulamalar › Nino TV › Kaldır |
| Yer yok | `INSTALL_FAILED_INSUFFICIENT_STORAGE` ya da "No space left" | `tvinstall_err_space` |
| Kurulamadı | Başka bir hata (çıktıda "Success" yok) | `tvinstall_err_failed` + ayrıntı |
| Bağlantı koptu | Adımlar arasında giriş/çıkış hatası | `tvinstall_err_connection` |

Ayrıntı (TV'nin çıktısı) iletinin altına "Ayrıntı: …" (`tvinstall_details`) olarak eklenir. "Yerine kurulamıyor"
ve "kendiniz kaldırın" iletilerinde eklenmez.

### 3.2 LG webOS (Developer Mode, SSH 9922)

#### Kullanıcı adımları
1. webostv.developer.lge.com adresinden ücretsiz bir LG geliştirici hesabı oluşturun.
2. LG Content Store'dan TV'ye **Developer Mode** uygulamasını yükleyin, hesabınızla oturum açın ve **Dev Mode
   Status**'u etkinleştirin. Ardından TV kendiliğinden yeniden başlar.
3. Developer Mode uygulamasına tekrar girin ve **Key Server**'ı etkinleştirin. Uygulama ekranda açık dursun;
   6 karakterli **Passphrase** sol alt köşede belirir.
4. Passphrase'i alana girip "Kur ve aç"a dokunun. Bu parola sadece ilk kurulumda sorulur. Anahtar kayıtlıysa alanın
   etiketi `tvinstall_lg_passphrase_saved` olur (`tvinstall_lg_passphrase_saved`).

Bilgi notu: geliştirici modu en çok 1000 saat açık kalır. Süre dolarsa TV uygulaması silinir
(`tvinstall_lg_session_note`). Uzatma için Belirsizlikler'e bakın.

#### Ağ adımları
1. **Anahtar alma** (yalnız kayıtlı anahtar yoksa ya da reddedildiyse, ve parola yazılmışsa):
   - `GET http://<TV>:9991/webos_rsa` istenir (5 sn). 200 dışı bir yanıt ya da bağlantı hatası **"Key Server
     kapalı"** demektir.
   - Gelen metinde `PRIVATE KEY` yoksa yine "Key Server kapalı" sayılır.
   - Anahtar eski PEM biçimindeyse (`Proc-Type: 4,ENCRYPTED`, `DEK-Info: <şifre>,<IV>`) uygulamanın içinde
     çözülür.
     - Şifreler: DES-EDE3-CBC, AES-128/192/256-CBC.
     - Anahtar türetme OpenSSL'in EVP_BytesToKey'idir: MD5, tek tur, tuz = IV'nin ilk 8 baytı.
     - Dolgu hatası ya da çözülen verinin geçerli bir ASN.1 dizisi (0x30 + tutan uzunluk) olmaması **"parola
       yanlış"** demektir.
     - TV ekranındaki parola büyük harflidir; kullanıcı küçük harfle girdiyse büyük harfe çevrilmiş hali de denenir.
   - Başka biçimdeyse (ör. OpenSSH) SSH kütüphanesi çözer; parola aynı kuralla denenir.
   - Çözülen parolasız anahtar TV adresine göre yedeklenmeyen klasöre kaydedilir.
2. **SSH:** `<TV>:9922`, kullanıcı `prisoner`, yalnız açık anahtarla giriş, 8 sn bağlantı süresi.
   - TV'nin ana makine anahtarı **denetlenmez**; fabrika ayarında değişir.
   - Eski webOS'lar için eski algoritmalar da açılır: ana makine anahtarı `ssh-rsa`; açık anahtar
     `rsa-sha2-256`, `rsa-sha2-512`, `ssh-rsa`; anahtar değişimi `diffie-hellman-group14-sha1`,
     `diffie-hellman-group1-sha1`.
   - Her komut ayrı bir `exec` kanalında çalışır (5 dk süre). Çıkış kodu ve stdout + stderr alınır.
3. **Sürüm okuma:** `cat /media/developer/apps/usr/palm/applications/com.ninotranslator.tv/appinfo.json` ve
   `"version"` alanı. Dosya yoksa uygulama kurulu değil.
4. **Yükleme:**
   - `/media/developer/temp` klasörü oluşturulur.
   - Önceki denemelerden kalan Nino paketleri silinir.
   - Paket, sürümdeki adıyla (`com.ninotranslator.tv_<sürüm>_all.ipk`) `cat > dosya` komutunun girişine
     yazılarak gönderilir.
   - `wc -c` ile boyut denetlenir; tutmazsa "paket eksik ya da bozuk ulaştı" denir. `wc` yoksa bu denetim atlanır.
5. **Kurulum:** ares-install'un yaptığı gibi `luna-send-pub -i` ile
   `luna://com.webos.appInstallService/dev/install` çağrılır, parametre
   `{"id":"com.ares.defaultName","ipkUrl":"<yol>","subscribe":true}`.
   - Abonelik, girişi bir `sleep`'ten gelen arka plan sürecinde açık tutulur. Yanıtlar geçici bir günlük
     dosyasına yazılır.
   - TV "installed" ya da "success" dediğinde, hata verdiğinde, süreç bittiğinde ya da **180 sn** dolduğunda
     günlük basılır ve süreç kapatılır.
   - Yanıtlar satır satır JSON olarak okunur; yarım satırlar birleştirilir.
     - `returnValue: false` hatadır, sebep `errorText`/`errorMessage` + `errorCode`'dur.
     - `details.state` içinde "failed" hatadır, sebep `details.reason`/`errorText` + `errorCode`'dur.
     - `details.state` "installed" ya da "success…" ise başarıdır.
6. **Doğrulama:** `appinfo.json`'daki sürüm beklenen olana kadar 2 sn'de bir bakılır. Kurulum yanıtı başarı
   dediyse 30 sn, demediyse 60 sn beklenir.
   - Sürüm görünürse geçici paket silinir.
   - Görünmezse "kurulamadı" denir. Başarı yanıtı yoksa paket silinmez: kurulum TV'de sürüyor olabilir, sonraki
     deneme onu temizler.
7. **Açma:** `luna-send-pub -n 1 luna://com.webos.applicationManager/launch '{"id":"com.ninotranslator.tv"}'`.
8. **Oturum uzatma** (en çok 20 saatte bir, TV başına):
   - TV'den `cat /var/luna/preferences/devmode_enabled` ile oturum jetonu okunur. Boşsa ya da boşluk içeriyorsa
     vazgeçilir.
   - `https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=<jeton>` çağrılır; yanıtta "success"
     olmalı.
   - `https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=<jeton>` çağrılır. Yanıttaki
     `saat:dakika:saniye` kalan süredir.
   - Başarılıysa zaman TV adresine göre saklanır (adres kırpılıp küçük harfe çevrilir).
   - Kurulum ekranında kurulumdan sonra ve her sessiz sürüm denetiminde denenir. Hata kullanıcıya gösterilmez.

#### Kayıtlı anahtar akışı
- Kayıtlı anahtar varsa önce o denenir. TV "anahtar reddedildi" derse kayıtlı anahtar silinir, yeni anahtar
  alınır (parola gerekir) ve bir kez daha denenir. Geliştirici modu yeniden açılınca TV yeni anahtar üretir.
- Parola yazılmamışsa ve yeni anahtar gerekiyorsa "anahtar reddedildi" iletisi çıkar.

#### Hata durumları

| Durum | İleti |
|---|---|
| 9922 yanıt vermiyor (geliştirici modu kapalı ya da başka ağ) | `tvinstall_lg_err_unreachable` |
| Key Server kapalı ya da anahtar yerine başka bir şey döndü | `tvinstall_lg_err_key_server` |
| Parola yanlış | `tvinstall_lg_err_passphrase` |
| SSH "Auth fail", anahtar okunamadı ya da parola yazılmadı | `tvinstall_lg_err_key_refused` |
| Yer yok: TV'nin yanıtında "no space", "not enough space/storage", "insufficient…", "out of space", "storage/disk full", "ENOSPC", "lack of space" | `tvinstall_err_space` |
| Kurulum hatası ya da sürüm görünmedi | `tvinstall_err_failed`. TV'nin yanıtı "TV'nin yanıtı: …" (`tvinstall_lg_tv_says`) olarak eklenir, en çok 500 karakter. |
| Komut 5 dk'da bitmedi ya da SSH kanalı koptu | `tvinstall_err_connection` |

### 3.3 Samsung Tizen (sdb, Samsung sertifikası, imza)

#### Kullanıcı adımları
1. TV'de Uygulamalar bölümüne girin.
2. Kumandadan sırayla **1 2 3 4 5** tuşlayın (veya ekrandaki klavyeyle 12345 girin); geliştirici modu penceresi
   belirir. Kimi yeni modellerde bunu Uygulamalar › Uygulama Ayarları ekranında yapmak gerekir.
3. Developer mode'u **On** konumuna getirin, **Host PC IP** alanına telefonun adresini girin (ekranda gösterilir) ve
   OK'e dokunun.
4. TV'yi **kapatıp açın**: güç tuşunu TV kapanıncaya dek 2 sn kadar basılı tutun. Tuşa kısa basılırsa TV sadece
   beklemeye geçer.
5. "Kur ve aç". İlk kurulumda bir defaya mahsus ücretsiz bir Samsung hesabıyla oturum açılır; Samsung uygulamayı
   ancak o TV'ye özel bir sertifikayla kabul eder. Telefonun adresi değişirse Host PC IP adımı tekrarlanır
   (`tvinstall_signin_note`).

Desteklenen TV'ler: 2016 ve sonrası (Tizen 2.4+). 2016–2018 modelleri deneysel (`tvinstall_supported`).

#### Ağ adımları: sdb (ADB'nin Tizen karşılığı, port 26101)
1. TCP bağlantısı (10 sn süre, 120 sn okuma süresi). Samsung'un sdbd'si yeni bağlantıyı el sıkışma ortasında
   bazen kapatır, özellikle bir öncekinin hemen ardından. Bu yüzden **üç kez**, aralarda 400 ms beklenerek
   denenir.
2. Çerçeve ADB'ninkiyle aynıdır: 24 bayt küçük-endian başlık. Ama burada **denetim toplamı denetlenir**
   (verinin bayt toplamı); uzunluk en çok 16 MB'tır.
3. `CNXN` gönderilir: sürüm `0x01000000`, en büyük veri 4096, veri `host::sdb-net-client` (NUL yok).
4. Gelen yanıta göre:
   - `AUTH` jeton (tür 1): **SHA1withRSA ile (jeton özetlenerek)** imzalanıp gönderilir. adb'den farklıdır.
   - `AUTH` tür 3: açık anahtar satırı (`nino@android` adıyla) + NUL gönderilir.
   - `CNXN`: kuruldu. En büyük veri = min(4096, TV'nin önerdiği).
   - Çoğu Samsung TV kimlik doğrulama istemez.
5. Kanal açma ADB gibidir, yerel kimlikler 'b'den başlar. TV'nin kendiliğinden açtığı kanala `CLSE` dönülür.
   TV kanal açılmadan veri yazabilir; bu veri saklanır.
6. Kullanılan hizmetler (`shell:<komut>` + NUL):
   - `capability:` + NUL: yanıtın ilk 2 baytı uzunluktur, sonra `anahtar:değer` satırları gelir. Kullanılanlar:
     - `platform_version` (Tizen sürümü);
     - `sdk_toolpath` (yoksa `/opt/usr/apps/tmp`).
   - `0 vd_applist`: kurulu uygulamalar. Satırlar `---- anahtar = değer ----` biçimindedir; `=` içermeyen ve
     `----` içeren satır kayıt ayırıcıdır. `app_tizen_id` ya da `app_id` `NinoTVApps.Nino` veya `NinoTVApps` olan
     kaydın `app_version`'ı kurulu sürümdür.
   - `0 getduid`: TV'nin kimliği (DUID). İlk satır en az 8 karakter olmalı, yalnız harf, rakam ve `_-+=/`. Yavaş
     TV'lerde ilk yanıt boş gelebilir, 500 ms arayla 3 kez denenir.
   - `sync:` + NUL: dosya gönderme. Akış `SEND <yol>`, 64 KB'lık `DATA`, `DONE` + zaman. `OKAY` ya da
     `FAIL <ileti>` beklenir.
   - `0 vd_appinstall NinoTVApps.Nino <yol>`: kurulum. **TV kurulum başarısız olsa da komutu başarılı bitirir;
     sonuç çıktıdan anlaşılır** (aşağıda).
   - `0 vd_appuninstall <kimlik>`: kaldırma.
   - `0 was_execute NinoTVApps.Nino`: açma.

#### Kurulum akışı
1. Bağlan ve TV'yi oku. Tizen 2.4'ten eskiyse **"çok eski"** denir. 5.0'dan eskiyse günlüğe "deneysel" yazılır.
2. Kurulu sürümü oku ve karşılaştır. Güncelse yalnız aç.
3. DUID'i oku. Bu TV için kayıtlı imza profili var mı bakılır:
   - profil, uygulama klasöründe DUID'e göre adlanmış bir klasördür;
   - içinde PKCS#8 anahtar, yazar sertifikası, dağıtıcı sertifikası, cihaz profili ve DUID dosyası durur;
   - geçerli sayılması için iki sertifika da şu andan 1 gün sonrası için geçerli olmalı ve DUID tutmalı.
4. Yoksa **Samsung girişi** yapılır:
   - Giriş sayfası:
     `https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h&redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback&state=accountcheckdogeneratedstatetext&tokenType=TOKEN`.
     Tizen Studio ve masaüstü uygulamaları da bu yolu kullanır.
   - Sayfa uygulama içindeki tam ekran bir WebView'da açılır. Ayarları:
     - JavaScript ve DOM depolama açık;
     - https sayfasından http://localhost'a gönderim için karışık içeriğe izin verilir;
     - çerezler ve üçüncü taraf çerezleri açık;
     - kullanıcı aracısından `; wv` çıkarılır, Samsung'un sayfaları WebView imzasıyla sorun çıkarıyor.
   - Üstte "Tarayıcıda açın" (`tvinstall_signin_browser`) düğmesi aynı adresi telefonun tarayıcısında açar.
     İkisi de aynı cihazın localhost'una gönderir.
   - Telefon `127.0.0.1:4794`'te küçük bir HTTP dinleyicisi açar. Samsung jetonu `POST /signin/callback`'e
     gönderir. Gövde `code=<JSON>&state=<…>` biçimindedir.
     - `state` tutmalı.
     - `code` çözülürken **`+` boşluğa çevrilmez**, yalnız `%XX` dizileri çözülür.
     - JSON'da `access_token`, `userId` (zorunlu) ve `inputEmailID` (isteğe bağlı) bulunur.
     - Başarıda tarayıcıya girişin bittiğini iki dilde (Türkçe/İngilizce) söyleyen kısa bir sayfa döner. Hesap bilgisi yoksa 400, başka yolsa
       404 döner.
   - **10 dk** beklenir. Dolarsa "giriş tamamlanmadı" denir; Samsung'un hata alanları günlüğe yazılır, jeton
     yazılmaz. Kullanıcı kapatırsa (geri tuşu) giriş iptal edilir. Ekrandan çıkılınca dinleyici kapanır.
5. **Sertifika alma:**
   - Yeni 2048 bit RSA anahtar çifti üretilir.
   - Aynı anahtarla, SHA256withRSA imzalı iki PKCS#10 isteği hazırlanır:
     - yazar isteği: konu `CN=Nino`;
     - dağıtıcı isteği: konu `CN=TizenSDK` (+ e-posta varsa `emailAddress`). İstek eklentisinde Subject Alt Name
       olarak iki URI bulunur: `URN:tizen:packageid=` ve `URN:tizen:deviceid=<DUID>`. Adlar olduğu gibi, büyük
       harfle yazılır. **TV, imzayı yalnız kendi DUID'i sertifikada yazılıysa kabul eder.**
   - Üç POST gönderilir (multipart/form-data; 20 sn bağlantı, 60 sn okuma):
     1. `https://svdca.samsungqbe.com/apis/v3/authors`: alanlar `access_token`, `user_id`, `platform=VD`, dosya
        `csr` (`author.csr`).
     2. `https://svdca.samsungqbe.com/apis/v1/distributors`: aynı alanlar + `privilege_level=public`,
        `developer_type=Individual`, dosya `csr` (`distributor.csr`). Yanıt **cihaz profili**dir (Tizen 4 ve
        öncesi için) ve saklanır.
     3. `https://svdca.samsungqbe.com/apis/v3/distributors`: 2. ile aynı. Yanıt dağıtıcı sertifikasıdır.
   - 2xx dışı yanıt ya da sertifika yerine hata metni gelirse "sertifika alınamadı" denir. Samsung'un JSON hata
     alanları (`code`, `errorCode`, `error`, `message`, `errorMessage`, `error_description`) ayrıntıya eklenir.
6. **Cihaz profili** (Tizen 3.0–4.0, yani 2.4 < sürüm ≤ 4.0): saklanan profil TV'nin `sdk_toolpath` klasörüne
   `device-profile.xml` olarak gönderilir. Gönderilemezse yine devam edilir.
7. **İmzalama** (W3C Widget Signature):
   - Uygulamayla gelen imzasız `.wgt` açılır. Klasör girdileri ve eski `author-signature.xml` / `signature1.xml`
     atılır, öbür dosyaların sırası korunur.
   - Özet SHA-512, imza RSA-SHA512'dir.
   - `author-signature.xml` (Id `AuthorSignature`): paketin her dosyasına bir Reference ve `#prop` nesnesine bir
     Reference.
   - `signature1.xml` (Id `DistributorSignature`): önce yazar imzası dosyası, sonra bütün dosyalar, sonra `#prop`.
   - `#prop` nesnesi üç SignatureProperty içerir: `profile` (`…widgets-digsig#profile`), `role`
     (`…#role-author` ya da `…#role-distributor`) ve boş `identifier`.
   - Kanonikleştirme: SignedInfo exclusive C14N, nesne C14N 1.1 ile. XML bildirimi ve boşluk yoktur, öğeler açık
     kapanışlıdır. Böylece dosyadaki metin kanonik biçimle aynıdır ve TV aynı baytları bulur.
   - KeyInfo'da zincir bulunur: yaprak sertifika ve onu veren Samsung ara sertifikası, kök yok. Ara sertifikalar
     uygulamaya gömülüdür: Tizen Studio'dan değiştirilmeden alınmış dört PEM (yazar CA'ları ve "public2"
     dağıtıcı CA'ları). Ad karşılaştırması kanonik biçimde yapılır.
   - Yeni zip'te sıra şöyledir: önce yazar imzası, sonra dağıtıcı imzası, sonra dosyalar.
8. **Kurulum:**
   - Paket `sdk_toolpath/nino-<rastgele 8 hex>.wgt` olarak gönderilir ve `vd_appinstall` çalıştırılır.
   - Çıktı sınıflandırılır (aşağıda). Sorun "eski kopyayı kaldırmak işe yarayabilir" türündense önce
     `vd_appuninstall NinoTVApps`, sonra `vd_appuninstall NinoTVApps.Nino` çalıştırılır ve **bir kez daha**
     kurulur. Kaldırma hatası yine de denemeyi durdurmaz.
   - TV sertifikayı reddederse kayıtlı profil kenara konur (yeniden adlandırılır). Sonraki denemede yeniden giriş
     ve yeni sertifika istenir.
9. **Doğrulama:** kurulumdan sonra sürüm yine okunur. Hâlâ beklenenden eskiyse "kurulumu bitirdi ama TV'de hâlâ …
   var" denir.
10. **Açma.**

#### `vd_appinstall` çıktısının sınıflandırılması

Büyük/küçük harf duyarsız aranır. Yalın "failed" kelimesi aranmaz, ilgisiz satır başarısızlık sanılmasın.

- **Başarısız sayılır:** çıktıda "install failed", "val[fail]", "not enough space", "download failed[116]" ya da
  bağlantı kopması varsa.
- **Bağlantı koptu:** "transport connection", "connection reset by peer", "broken pipe".
- **Uyumsuz:** `install failed[118, -4]`, `[118, -19]`, `[118019]`.
- **Yer yok:** `download failed[116]`, "not enough space".
- **Sertifika kodu:** `install failed[118, -12]`, `[118012]`, `[118, -11]`, `[118011]`.
  - Kodla birlikte "Check certificate error" varsa ve "same id and different certificate" yoksa: "not valid yet"
    geçiyorsa **TV saati geride**, geçmiyorsa **sertifika reddedildi**.
  - Değilse (ya da "Author certificate not match" varsa) **başka sertifikalı eski kopya**.
- **Paket engelli:** `install failed[118, -22]`, `[118022]`.
- Başka her şey "diğer"dir.
- Eski kopyayı kaldırmak yalnız "başka sertifikalı eski kopya", "paket engelli" ve "diğer"de denenir.
- Kullanıcıya gösterilen ayrıntı: "fail", "error", "reason", "not match", "space" içeren ilk 3 farklı satır; yoksa
  son 3 satır. En çok 400 karakter.

#### Hata durumları

| Durum | İleti |
|---|---|
| sdb bağlanamadı ya da DUID okunamadı | `tvinstall_err_unreachable`: `tvinstall_err_unreachable` |
| Tizen < 2.4 | `tvinstall_err_too_old` |
| Giriş olmadı, iptal ya da 10 dk doldu | `tvinstall_err_login` |
| Samsung sertifika vermedi | `tvinstall_err_certificate` |
| Yer yok | `tvinstall_err_space` |
| Başka sertifikalı kopya kaldırılamadı | `tvinstall_err_mismatch` |
| Sertifika reddedildi | `tvinstall_err_rejected` (TV internete bağlı mı, saat doğru mu; yeniden giriş gerekecek) |
| TV saati geride | `tvinstall_err_clock` |
| Paket engelli (118, -22) | `tvinstall_err_blocked` (Nino'yu sil; olmazsa Smart Hub'ı sıfırla, öbür uygulamalar da gider) |
| Bağlantı koptu | `tvinstall_err_connection` |
| Diğer | `tvinstall_err_failed` |

"Kurulamadı" ve "sertifika reddedildi"de ayrıca `tvinstall_maintenance` eklenir: TV'nin kendi sunucu bakım uyarısı
çıkıyorsa TV Samsung'a ulaşamıyor demektir.

### 3.4 Sessiz sürüm denetimi ve güncelleme önerisi

- Uygulama açılınca ve ana ekrandaki TV bağlantı durumu her değiştiğinde, **kayıtlı TV'deki** sürüme sessizce
  bakılır. Aynı anda tek denetim çalışır.
- Kullanıcıdan hiçbir şey istenmez: Samsung girişi yok, Android TV onayı beklenmez (TV onay isterse vazgeçilir),
  LG parolası sorulmaz.
- Önce portun açık olup olmadığına bakılır (700 ms): Samsung'da 26101, Android TV'de kayıtlı port ya da 5555,
  LG'de 9922 + kayıtlı anahtar. Kapalıysa denetim bırakılır ve durum değişmez.
- LG'de bu denetim sırasında oturum uzatma da denenir (3.2, en çok 20 saatte bir).
- TV'deki sürüm telefondakinden eskiyse:
  - ana ekranda bir kart çıkar: `tvapp_update_title`, "Sürümler farklı: … TV'de X, telefonda Y.
    Güncelleme yaklaşık bir dakika alır; TV'yi açık ve aynı Wi-Fi'da tutun." (`tvapp_update_title`,
    `tvapp_update_body`);
  - Ayarlar'daki TV uygulaması satırında "Güncelleme var: Y" (`tvapp_update_short`) yazar.
  - Değilse satırda "marka · sürüm" görünür.
- Karttaki `tvapp_update_button` düğmesi kurulum ekranını o marka ve TV seçili açar ve kurulumu **hemen
  başlatır**. Kullanıcı ana ekranda onaylamış sayılır.
- Telefon güncellemeyi kendiliğinden kurmaz; masaüstü uygulamaları kendiliğinden kurar.

### 3.5 TV paketleri ve sürüm karşılaştırma

- Telefon uygulamasıyla üç paket gelir:
  - **Android TV APK.** Sürümü APK'nın kendisinden (paket yöneticisinin arşiv bilgisi, `versionName`) okunur.
  - **LG IPK** (bir `ar` arşivi: `debian-binary`, `control.tar.gz`, `data.tar.gz`). Sürümü dosya adından
    okunur: `com.ninotranslator.tv_<sürüm>_all.ipk`, `_` ile ayrılmış 2. parça.
  - **Samsung WGT** (imzasız). Derlemede Tizen kaynaklarından paketlenir. Sürümü derleme anında `config.xml`'deki
    `version` değeri olarak uygulamaya yazılır.
- Hangi paketin hangi sürümden geldiği `anahtar=değer` satırlı bir dizin dosyasında durur. `#` ile başlayan ve
  boş satırlar atlanır. Örnek anahtarlar: `release`, APK adı, IPK adı.
- Android TV ve LG paketleri derlemede kaynaktan derlenmez. Mac ve Windows'un da kurduğu dağıtım klasöründen
  (`dist/tv-app`) en yüksek sürümlü dosya alınır; böylece hepsi aynı imzalı kopyayı kurar ve birbirini
  güncelleyebilir. Klasörde paket yoksa önceki kopya kalır, hiç yoksa uygulama "paket yok" der. CI paketleri şart
  koşar.
- **Sürüm karşılaştırma:** `.` ve `-` ile parçalara bölünür. Sayı olmayan parça 0 sayılır, eksik parça 0'dır.
  Parça parça sayısal karşılaştırılır; 0.10.0, 0.9.9'dan yenidir. Yalnız "telefondaki **kesin** yeni" ise
  kurulur. "beta.37" gibi sonekler 0'a düşer.
- TV uygulamasının kimlikleri: Android TV ve LG `com.ninotranslator.tv`, Samsung uygulama `NinoTVApps.Nino`
  (paket `NinoTVApps`).

---

## Belirsizlikler

1. **LG oturum uzatma çelişkisi:** kod, kurulumdan sonra ve her sessiz denetimde oturumu (en çok 20 saatte bir)
   LG'nin sunucusundan uzatıyor. Ama kullanıcıya gösterilen not (`tvinstall_lg_session_note`) "Telefon bu süreyi
   uzatmaz… EXTEND'e basın" diyor. Hangisinin doğru davranış olduğu, ve LG uç noktalarının hâlâ çalışıp
   çalışmadığı denenmeli.
2. **LG paket adı uyuşmazlığı:** derleme betiği dağıtım klasöründe `com.nino.tv_<sürüm>_all.ipk` adını arıyor.
   Çalışma anı ve TV'deki kimlik `com.ninotranslator.tv_…` bekliyor. Biri eski ad kalıntısı olabilir; LG paketinin
   telefona gerçekten girip girmediği belirsiz.
3. **Google Play yolu:** Android TV kurucusunda Play'den kurma yolu tam yazılı ama kapalı. Play'deki aynı kimlikli
   uygulamanın kime ait olduğu ve yeni uygulamada bu yolun gerekip gerekmediği karar verilmeli.
4. **`at` alanı:** her `subtitle` olayında gönderiliyordu. TV uygulamalarının bunu (ör. gecikme ölçmek ya da eski
   olayı atmak için) kullanıp kullanmadığını yalnız telefon kodundan anlayamadım.
5. **Samsung elle adres:** Samsung ekranı adresi yalnız kırpıyor, LG/PS5'teki temizleme kurallarını uygulamıyor.
   Bilerek mi, unutulmuş mu belli değil. Yeni uygulamada hepsinde aynı kural olmalı.
6. **Yeni protokolde altyazı süresi:** eskide normal satır 15 sn sonra TV'de kendiliğinden kalkıyordu. Yenide
   varsayılan "clear gelene kadar". Yeni uygulamanın hangisini seçeceği (sabit 15 sn mi, satır uzunluğuna göre mi,
   açık `clear` mı) karar verilmeli.
7. **Birden çok TV ve OBS izleyicisi:** yeni protokol tek gönderici ve TV-sunucu modeline geçtiği için bu iki
   özelliğin yeni uygulamada nasıl yapılacağı (ya da bırakılacağı) açık değil.
8. **Android TV'de `MainActivity` adı:** açma komutu TV uygulamasının etkinlik adını sabit varsayıyor. Yeni TV
   uygulamasında ad değişirse `monkey`/`am start` ile paket adından başlatma daha sağlam olur. Bu TV tarafının
   kararı.
9. **Sessiz denetimde Samsung kimlik doğrulaması:** Samsung'da sdb kimlik doğrulaması istenirse anahtar
   gönderilir; TV'de onay sorusu çıkıp çıkmadığı (Android TV'deki gibi) koddan anlaşılmıyor. Çoğu Samsung istemez.
10. **mDNS:** yeni protokolde TV'yi bulmak için `_nino._tcp` gerekiyor. Eski telefonda mDNS kodu yok. Android'in
    NsdManager'ının bazı TV/router'larda güvenilmezliği bilinen bir sorun. SSDP benzeri bir yedek (ya da eski TV
    gibi /24 taraması, `GET /nino/info` ile) düşünülmeli.
