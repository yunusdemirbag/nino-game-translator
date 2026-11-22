<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Linux sunucusu: davranış tarifi

Bu belge şimdiki Linux uygulamasının (`linux/Nino.Linux`) **ne yaptığını** anlatır; nasıl yazıldığını değil.
Yeni uygulama (`apps/linux/`) bu tarife göre, eski koddan bağımsız yazılır. Metinler (panel yazıları, istem
metni) burada yalnız anlamıyla verilir; yeni uygulamada yeniden yazılır.

## 1. Ne işe yarar

- Ekransız bir Linux makinesinde (çoğunlukla Docker'da) çalışan Nino. Arayüzü yoktur; kurulum ve denetim aynı ağdaki
  bir tarayıcıdan açılan **panel** ile yapılır.
- Akışın tamamı (sihirbaz adımları, PS5 oturumu, okuma, çeviri, TV'ye gönderme) masaüstü uygulamalarıyla aynı
  denetleyiciden gelir. Linux'a özgü olanlar yalnız: panel, Tesseract ile yazı tanıma, dosyada anahtar saklama,
  PSN girişinin "adres yapıştırma" ile yapılması, tanı araçları.
- Linux'ta olmayanlar: uygulama güncellemesi, klavye kısayolları, güvenlik duvarı kartı, uyku engelleme (sunucu
  uyumaz; uyku koruyucusu boş çalışır).

## 2. Çalıştırma

- Tek çalıştırılabilir dosya: `nino` (dotnet derlemesinin adı).
- İki kip:
  1. **Sunucu** (argümansız): panel ve çeviri.
  2. **Tanı**: `nino --read-raw <dosya> <genişlik> <yükseklik> [--translate]` (bkz. §8). Sunucu açılmaz.
- Açılışta veri klasörü oluşturulur.
- Açılışta günlüğe iki satır düşer: sürüm + panel adresi (makinenin yerel IPv4 adresi, bulunamazsa `localhost`);
  veri klasörü + PS5 kütüphanesi var/yok + yazı tanıma var/yok + LG paketi sürümü/yok.
- Kapanırken denetleyici en çok 5 sn beklenerek kapatılır.

### Ortam değişkenleri

| Ad | Varsayılan | Anlamı |
|---|---|---|
| `NINO_DATA` | `~/.local/share/Nino` | Veri klasörü (Docker'da `/data`). |
| `NINO_LANG` | sistem dili (iki harf) | Sunucunun ürettiği hata/durum metinlerinin dili (`tr`/`en`). Panelin kendi dili tarayıcıyı izler. |
| `NINO_PANEL_PORT` | `8788` | Panel portu; sayı değilse varsayılan. Tüm arabirimlerde (`0.0.0.0`) dinler. |
| `NINO_AUTOSTART` | kapalı | `1` ise açılışta, kurulum bitmişse çeviri kendiliğinden başlar (dinlenmedeki PS5'i uyandırır, bu yüzden varsayılan kapalı). |
| `NINO_OCR_STRONG` | `75` | Tesseract sözcük güveni bu değerin üstündeyse "kesin" sayılır. |
| `NINO_OCR_MIN_WORD` | `60` | Satır başı/sonundaki bu güvenin altındaki parçalar kırpılır. |
| `NINO_OCR_DUMP` | yok | Verilirse Tesseract'a giden her görüntü bu klasöre dökülür (§6.5). |
| `OMP_THREAD_LIMIT` | Docker'da `1` | Tesseract'ın OpenMP iş parçacıkları; kısa satırda yarar yok, işlemciyi doldurur. |

### Portlar

- `8788`: panel (parolasız; yalnız ev ağında açık tutulmalı).
- `8787`: eski TV uygulamalarının bağlandığı altyazı sunucusu (eski SSE düzeni; ortak çekirdekte).
- `47800`: yeni protokol (protokol-karari-tv.md): gönderici `GET /nino/info` (role:"sender") ve `/nino/ws` sunar;
  Android TV'ye de bu portta bağlanılır. Ortak çekirdekte.
- Ağ: PS5 araması UDP yayını, TV araması SSDP. Docker'da `network_mode: host` gerekir.

## 3. Veri klasörü

| Dosya/klasör | İçerik | Kural |
|---|---|---|
| `secure.json` | Gizli değerler: hesap kimliği, PS5 kaydı, TV anahtarları, çevrimiçi çeviri anahtarı vb. | Tek JSON nesnesi, anahtar → değer (System.Text.Json biçimi). İzin **0600**. Yazma: önce `secure.json.tmp`, izin verilir, sonra üstüne taşınır. Bozuk/okunamaz dosya boş sayılır (kurulum baştan); ardından yazılan değer sorunsuz okunur. Okunan değer beklenen türe çevrilemezse "yok" sayılır. |
| `settings.json` | Sıradan ayarlar (masaüstüyle aynı ayar kaydı; PascalCase alan adları). | Okunamaz/bozuksa varsayılan ayarlar. Yazma doğrudan. |
| `models/en-tr/` | Cihaz üstü çeviri modeli (~530 MB, bir kez indirilir). | |
| `remoteplay.log` | PS5 bağlantı günlüğü (§7). | 1 MB'yi geçince eski yarısı atılır. |
| `tvinstall.log` | Samsung kurulumunun ayrıntılı günlüğü. | |
| `samsung/` | Samsung imza/sertifika dosyaları. | |
| `adb/` | Android TV'ye kurulum için adb anahtarı. | |

`secure.json` anahtar adları masaüstüyle aynıdır (veri taşıma için korunur): `accountId`, `console`, `tv`, `tvKey`,
`tvDevKey`, `tvAppVersion`, `devSessionRenewed.<host>`, `deepLKey`, `setupComplete`, giriş şifresi vb. Panelin
"çevrimiçi çeviri anahtarı" **`deepLKey`** anahtarında durur; içi Claude ya da DeepL anahtarı olabilir.

## 4. Panel (HTTP)

Tek sayfa (`/`), bağımlılıksız HTML+JS, gömülü kaynak. Logo `/logo.svg` (gömülü). Sayfa 1,5 sn'de bir
`/api/state` çeker; durum değişmedikçe yeniden çizmez; çizerken yazılan metin, imleç yeri ve odak korunur; sürgü
sürüklenirken çizmez. Her eylem düğmesi beklerken döner ve kilitlenir; hata o eylemin yanında gösterilir; sonra
durum yenilenir. Panel dili tarayıcı dili `tr` ile başlıyorsa Türkçe, değilse İngilizce. Açık/koyu tema
(`prefers-color-scheme`), Nino renkleri (sıcak açık zemin, tek sarı vurgu), en fazla 640 px genişlik.

### 4.1 Uçlar

Bütün denetleyici işleri **tek bir sıradan** (seri iş parçacığı) geçer; `await` sonrası da o sıraya döner.

| Yöntem | Yol | Gövde | Ne yapar |
|---|---|---|---|
| GET | `/` | | Panel sayfası |
| GET | `/logo.svg` | | Logo |
| GET | `/api/state` | | Durum anlık görüntüsü (§4.2) |
| GET | `/api/log` | | `{lines: [...]}` son 400 günlük satırı |
| POST | `/api/advance` | | Sihirbazda ileri |
| POST | `/api/back` | | Sihirbazda geri |
| POST | `/api/psn` | `{redirect}` | PSN girişini tamamlar (§4.3) |
| GET | `/api/consoles` | | PS5 araması → `[{name, host, isAwake, …}]` |
| POST | `/api/register` | `{host, pin}` | PS5 eşleme (host kırpılır) |
| GET | `/api/tvs` | | TV araması (LG + Samsung aynı anda; süreleri günlüğe) → `[{name, host, brand}]` |
| POST | `/api/pair` | `{name, host, brand}` | TV eşleme (host kırpılır) |
| POST | `/api/tv-app/install` | `{passphrase}` | LG TV uygulamasını geliştirici moduyla kurar |
| POST | `/api/tv-app/refresh` | | TV uygulamasının durumunu yeniden denetler |
| POST | `/api/model/download` | | Çeviri modelini indirmeye başlar |
| POST | `/api/test-subtitle` | | TV'ye deneme altyazısı |
| POST | `/api/reset` | | Kurulumu sıfırlar (panel önce onay sorar) |
| POST | `/api/start` | | Çeviriyi başlatır |
| POST | `/api/stop` | | Durdurur |
| POST | `/api/pause` | | Altyazıyı duraklatır/sürdürür |
| POST | `/api/settings` | `{region?, style?, onlineTranslation?}` | Verilen alanları değiştirir (§4.4) |
| POST | `/api/deepl` | `{key}` | Çevrimiçi anahtarı kaydedip dener → `{state}` |
| DELETE | `/api/deepl` | | Anahtarı siler |
| GET | `/api/frame.png?width=` | | PS5'ten gelen son karenin küçültülmüş PNG'si; genişlik 160–1920 (yoksa 960); kare yoksa 404 |
| POST | `/api/read-test` | | Son karede altyazı bölgesini bir kez okur → `{ms, width, height, lines, subtitle}`; kare yoksa 400 "henüz oyun görüntüsü yok" |
| POST | `/api/translate-test` | `{text}` | Metni çevirir → `{text, ms, engine}` (§5) |

Yanıt kuralları: eylem başarılıysa `200 {ok:true}`; sorgu başarılıysa sonuç JSON'u. Hata: `{error: <ileti>}`;
uygulama hatası ya da geçersiz işlem ise **400**, başka her hata **500**; her hata günlüğe "tür: ileti" olarak yazılır.
JSON'da enum'lar ad olarak (string) gider; alan adları camelCase.

### 4.2 Durum (`/api/state`)

`version, language, step, stepNumber, stepCount, canAdvance, hasAccount, psnLoginUrl, redirectPrefix,
console{name,host}|null, tv, tvApp{kind,version,error,url,reason}, canInstallTvApp, bundledTvApp, devModeHoursLeft,
computerAddress, serverPort, model{installed,downloading,progress,error}, running, starting, paused,
ps5{text,tone,phase,reason,detail}, tvStatus{text,tone,clients}, lastSource, lastTranslation, translator, ocrMissing,
nativeAvailable, hasFrame, hasDeepLKey, onlineEngine ("Claude"|"DeepL"|null), settings{region, style,
sourceLanguage, targetLanguage, onlineTranslation}`.

Çevrimiçi anahtarın kendisi panele **hiç** dönmez; yalnız motor adı.

### 4.3 PSN girişi

Panel Sony giriş sayfasını yeni sekmede açar; kullanıcı girişten sonra açılan yönlendirme adresini yapıştırır.
Yapıştırılan metin kırpılır; `://` içermiyorsa: `=` içeriyorsa başındaki `?` atılıp yönlendirme önekine sorgu
olarak eklenir, içermiyorsa `code=<metin>` olarak eklenir. Mutlak adres olamıyorsa "geçersiz giriş" hatası.
Adresteki koddan hesap kimliği alınır; kod yoksa aynı hata.

### 4.4 Ayar doğrulama

- Bölge yalnız şu koşulda kabul edilir: üst ≥ 0, sol ≥ 0, alt ≤ 1, sağ ≤ 1, yükseklik ≥ 0,05, genişlik ≥ 0,1.
  Geçersizse sessizce yok sayılır (diğer alanlar yine uygulanır).
- Stil olduğu gibi alınır. Panelde iki seçim: yazı boyu (36 küçük / 46 orta / 58 büyük / 72 çok büyük) ve yer
  (Cover örter / Above üstünde / Below altında / Fixed ekranın altında sabit).

### 4.5 Sayfa akışı

Sihirbaz ilerleme çubuğu + adım içeriği + altta Geri (ilk adımda yok) ve Başla/Devam/Bitir (`canAdvance` değilse
kilitli).

1. **Karşılama**: ne yaptığı; gerekenler (PS5, aynı ağda TV, ikinci PSN hesabı). Sağlık kartı: PS5 kütüphanesi
   yoksa, Tesseract yoksa, LG paketi yoksa uyarı.
2. **İkinci hesap**: neden ikinci hesap (kol kapanmasın); PS5'te yeni kullanıcı + ücretsiz PSN hesabı, Uzaktan
   Oynatmayı etkinleştir, giriş parolası olmasın.
3. **PSN girişi**: Sony sayfası düğmesi, adresi kopyalama yönergesi, adres alanı, "tamamla"; hesap alındıysa onay.
4. **PS5**: Cihaz Bağla yönergesi; ara düğmesi; bulunanlar listesi (dinlenmedeyse belirtilir; tek bulunduysa adres
   kendiliğinden dolar; seçince kod alanına odak); bulunamadıysa uyarı; elle adres + 8 haneli kod; eşle.
5. **TV**: ara; liste (ad, marka, adres); seçince eşleme; bulunamadıysa uyarı; elle LG adresi (ad "LG TV",
   marka Lg); bağlanınca TV uygulaması kartı:
   - Working: kuruluyor; UpToDate: sürüm + geliştirici modu kalan saat; DevModeOff: yönergeler + yeniden dene;
     NeedsPassphrase: (hata varsa açıklaması) + yönergeler + 6 karakterli parola alanı + kur; Failed: hata + sebep +
     yeniden dene; SignIn: Samsung giriş bağlantısı; ApproveOnTv: TV'deki hata ayıklama izni; bilinmiyor: denetle.
   - Parola hataları: WrongPassphrase, KeyServerOff, Unreachable, ToolMissing (ssh-keygen yok) için açıklama.
   - LG yönergesi: Developer Mode uygulaması + hesap, Dev Mode Status aç (TV yeniden başlar), Key Server aç.
     Samsung'da "Host PC IP" olarak sunucunun adresi gösterilir.
6. **Çeviri modeli**: çeviri sunucuda yapılır, bir kez ~530 MB indirilir; kurulu / yüzdeli indirme / hata + indir.
7. **Deneme**: TV durumu + deneme altyazısı gönder.
8. **Daha iyi çeviri** (`BetterTranslation`): eski panelde bu adımın içeriği yoktu (boş sayfa + Devam). Yeni panelde
   bu adımda isteğe bağlı çevrimiçi çeviri kartı gösterilir; atlanabilir.

**Ana ekran** (kurulum bitti):
- Durum kartı: PS5 ve TV satırı (renkli nokta: Idle gri, Warning turuncu, Good yeşil), PS5 ayrıntısı; çevirmen hazır
  değilse model kartı; Tesseract yoksa hata.
- Büyük düğme: çeviriyi başlatır (başlarken bekleme yazısı) ya da durdurur (kırmızı). Çalışırken: duraklat/sürdür ve
  deneme altyazısı.
- Son altyazı: çeviri büyük, kaynak küçük; yoksa henüz okuma olmadığını söyleyen soluk bir satır.
- Altyazı alanı: son karenin önizlemesi (640 px) üstünde bölge çerçevesi; görüntüyü yenileyen düğme; alanı o an okuyan düğme
  (ms, boyut, satırlar); dört sürgü (üst/alt/sol/sağ, %); bırakınca kaydedilir.
- TV'de görünüm: yazı boyu ve yer seçimi.
- İnternetten çeviri kartı (§5): anahtar yoksa parola alanı + kaydedip deneyen düğme; varsa açık/kapalı + motor adı, aç/kapat,
  anahtarı sil. Deneme sonucu Valid ya da QuotaExceeded ise alan temizlenir; Invalid/QuotaExceeded/Unreachable
  açıklaması gösterilir. Açıklama: metin Anthropic'e/DeepL'e gider, 3 sn'de yanıt yoksa yerel model çevirir.
- Cümle çevirme kartı: kullanıcının yazdığı İngilizce cümle (boşsa örnek bir cümle) → çeviri, ms, motor.
- Kurulum kartı: PS5 ve TV bilgisi, TV uygulaması satırı, TV uygulamasını yeniden denetleyen düğme, kurulumu baştan alan düğme (onaylı).
- Günlük (açılır): açıkken 1,5 sn'de bir `/api/log`, en alta kaydırılır.

## 5. Çeviri

- Cihaz üstü model: yalnız İngilizce → Türkçe (OPUS-MT, `models/en-tr`). Model belleğe bir kez yüklenir,
  oluşturulunca hemen arka planda ısıtılır. Süresi 5 ms'yi geçen çeviriler günlüğe yazılır.
- Çevrimiçi anahtar `sk-ant-` ile başlıyorsa (boşluklar kırpılarak) **Claude**, değilse **DeepL**.
- Claude çevirmeni (davranış):
  - Model `claude-haiku-5-5`, düşünme kapalı, düşük çaba, en çok 300 belirteç, yeniden deneme yok.
  - Zaman aşımı 3 sn; hata ya da zaman aşımında 30 sn Claude denenmez, o sürede satırlar yerel modele gider.
  - Son 3 **gösterilen** satır bağlam olarak gider (`<earlier>…</earlier><line>…</line>`; bağlam yoksa yalnız
    `<line>`).
  - Önbellek 4096 satır (dolunca boşaltılır). Önceden çeviri (prefetch) destekler; aynı anda en çok 3 bekleyen.
  - Ret ya da boş yanıt da yerel modele düşer; düşme sebebi günlüğe yazılır. Yerel model yoksa "model gerekli" hatası.
  - Sistem istemi: oyun altyazısını TV için Türkçeye çevir; yalnız çeviriyi ver; konuşmacı etiketini aynen bırak;
    OCR hatalarını sessizce düzelt (`|`→`I`, ad sonrası artık işaretler, bölünmüş sözcükler); adları çevirme;
    "sen" ile gündelik konuş; aslı kadar kısa; arayüz iletileri de çevrilir; okunamayan gürültüyü aynen döndür;
    önceki satırlar yalnız bağlamdır.
  - Anahtar denemesi: modeli sorgular (ücretsiz), 8 sn zaman aşımı → Valid / Invalid (yetkisiz/yasak) /
    QuotaExceeded (hız sınırı) / Unreachable.
- Çeviri denemesi (`/api/translate-test`): model kurulu değilse 400 (model henüz yok). Çevrimiçi açık ve anahtar
  varsa çevrimiçi (yerel modele düşerek), yoksa yerel; motor adı "Claude"/"DeepL"/"yerel model".

## 6. Yazı tanıma (Tesseract)

### 6.1 Kütüphane

- Sistemin `libtesseract`'ı (C arayüzü). Sırayla denenir: `libtesseract.so.5`, `.so.4`, `.so`, `.dylib`, `tesseract`.
  Kütüphane ya da dil verisi yoksa okuyucu oluşmaz ("Tesseract bulunamadı" günlüğe; durumda `ocrMissing`).
- Dil adları: en→eng, ja→jpn, de→deu, fr→fra, es→spa, it→ita, pt→por, ru→rus, ko→kor, zh→chi_sim, diğeri aynen.
  Oyun dilinin verisi yoksa İngilizce veriyle okunur.
- Motor ayarları: sayfa bölme "tek blok" (6), `debug_file=/dev/null`, kaynak çözünürlüğü 150 ppi.
- Aynı anda birkaç motor: işlemci sayısı 2–4 arasına sıkıştırılır; boşta olanlar yeniden kullanılır.
- Okuyucu dil değişmedikçe bir kez oluşturulur; dil değişince eskisi kapatılır.

### 6.2 Okuma sırası

- 40×40'tan küçük görüntü boş okunur.
- Önce **yalnız beyaz yazı** süzgeciyle okunur. Satır bulunursa: renkli kip kapanır; bulunan yazının çevresi
  (yazının üstünden ve altından birer satır yüksekliği pay, tüm genişlik; bant 40 px'ten kısaysa atlanır) **ham**
  okunur; sözcüğe daha çok benzeyen okuma (gürültü puanı) seçilir, eşitlikte beyaz.
- Beyaz yazı yoksa: derin okuma değilse ve renkli kip kapalıysa boş. Değilse bölgenin tamamı ham okunur; satır
  bulunursa renkli kip açılır (ekranda kaldıkça her kare ham da okunur). Derin okumada hâlâ yoksa: ortadaki %40'lık
  şerit 2 kat büyütülüp beyaz süzgeçle okunur, kutular şeridin yerine göre çevrilir.
- Gri dönüşüm: (R·3 + G·6 + B)/10. Ham okumada ters çevrilir (açık yazı → koyu).

### 6.3 Sözcük süzgeci (satır başına)

- Ağırlık = sözcükteki harf/rakam sayısı (en az 1).
- "Kesin" sözcüklerin ağırlığı toplamın yarısından azsa ya da satırda 2'den az harf/rakam varsa satır atılır.
- Kalan satırın başından ve sonundan güveni en düşük eşiğin altında olanlar kırpılır (ortadakilere dokunulmaz).
- Tek başına dik çizgi `|` içeren ve yalnız harf/kesme/nokta/virgül/ünlem/soru işaretinden oluşan sözcükte `|` → `I`.

### 6.4 Satır kutuları

- Satır kutusu sözcük kutularının birleşimi (görüntüye oranla 0–1). Aynı hizada aralarındaki boşluk "ayrı yazı"
  sayılacak kadar genişse satır orada bölünür (ortak kural çekirdekte).
- Kutunun yüksekliği üstten ve alttan %20 genişletilir (0–1 içinde kalır).
- Satırlar yukarıdan aşağı sıralanır.

### 6.5 Döküm (`NINO_OCR_DUMP`)

Her görüntü `ocr-0001.pgm` (P5 gri) ve yanına `ocr-0001.txt`: her satır `+`/`-` (süzgeçten geçti mi) ve
`sözcük[güven]` listesi. Yazılamazsa okuma sürer.

### 6.6 Süre günlüğü

Okunan metin bir öncekinden farklıysa bir satır: süre (ms), derin olup olmadığı, metin ya da boş olduğu.

## 7. PS5 günlüğü

PS5 kütüphanesinin her satırı zaman damgasıyla `remoteplay.log`'a yazılır (arka planda, en çok 2000 satır kuyruk;
yazılamazsa sessizce geçer). "info" düzeyinde olmayan satırlar panel günlüğüne de düşer. Dosya 1 MB'yi geçince
ilk yarısı atılır. PS5 kütüphanesinin (`nino_native`) yüklenip yüklenemediği açılışta bir kez denetlenir.

## 8. Tanı: `--read-raw`

- Ham BGRA kare dosyası (`ffmpeg -i kare.png -pix_fmt bgra -f rawvideo kare.bgra`).
- Dosya genişlik×yükseklik×4'ten küçükse hata iletisi, çıkış kodu **2**. Tesseract yoksa **3**. Başarıda **0**.
- Varsayılan ayarlardaki altyazı bölgesi dört kez okunur: ilk ikisi derin, son ikisi olağan; her biri için süre ve
  bölge boyutu yazılır. Sonuncunun satırları ve altyazı bloğu yazılır.
- `--translate` ve altyazı boş değilse: model yoksa indirilir, satır sonları boşluğa çevrilip iki kez çevrilir
  (ikincisi ısınmış model süresi).
- Bölge okuma (panel denemesiyle aynı): kare bölgeye kırpılır, okunur, süre ölçülür; düğme ipuçları ve OCR
  gürültüsü atılıp bölgedeki altyazı bloğu seçilir.

## 9. Önizleme PNG'si

Son kare, genişliği en çok istenen kadar olacak biçimde tam sayı adımla seyreltilir (adım = ⌈genişlik/en çok⌉),
RGB 8 bit, zlib en hızlı sıkıştırma; bağımlılıksız PNG.

## 10. Günlük

Her satır `[SS:dd:ss] [kaynak] ileti` biçiminde konsola (Docker'da `docker logs`) ve bellekteki son 400 satıra.
Kaynaklar: panel, tv, ocr, okuma, çeviri, ps5. Seri sıradaki yakalanmamış hata kaynağı panel olan bir satırla yazılır.

## 11. TV uygulamaları

- Kurulum paketleri uygulamanın yanındaki `tv-app/` klasöründen: `*.ipk` (LG), `*.wgt` (Samsung), `*.apk` (Android TV).
  Sürüm dosya adından okunur.
- LG: geliştirici modu açık mı; parola ile anahtar alma (`ssh-keygen` gerekir); kurulu sürüm; kurma; geliştirici
  oturumunu uzatma (15 sn zaman aşımı, hata → yok). ssh anahtarı geçici dosyaya (0600) yazılır, iş bitince silinir.
- Samsung: geliştirici modu, imzalama, gerekirse tarayıcıda Samsung girişi (10 dk), kurulum; hatalar ortak
  geliştirici modu hata türlerine çevrilir; beklenmeyen hata genel "kurulum olmadı" türüdür.
- Android TV: ağdan bulunur; hata ayıklama izni TV'de onaylanır; adb ile kurulur. Eşlemede sunucu Android TV'yi
  denetlemez (TV uygulaması sunucuyu kendisi bulur), canlı tutucu boştur.
- LG/Samsung eşlemesi: bağlanıp anahtar/belirteç alınır, TV uygulaması `server=<adres>` parametresiyle açılır
  (açılamazsa eşleme yine geçerli, uygulama açılmadı bilgisiyle). Canlı tutucu TV'nin yeri değişirse yeniden arayıp bulur.

## 12. Docker

- Çok aşamalı derleme (Ubuntu 24.04): LG paketi → yerel PS5 kütüphanesi (libchiaki + FFmpeg; örnek h264 ile sınanır)
  → .NET yayını → çalışma imajı (aspnet:10.0-noble; FFmpeg, libchiaki bağımlılıkları, libtesseract5,
  tesseract-ocr-eng, openssh-client, ca-certificates). Eksik paylaşımlı kütüphane derlemede yakalanır.
- `NINO_DATA=/data`, `HOME=/data`, `OMP_THREAD_LIMIT=1`; `/data` birimi; uygulama kullanıcısı ile çalışır;
  `EXPOSE 8788 8787`.
- `compose.yml`: `network_mode: host`, `restart: unless-stopped`, `NINO_LANG=tr`, `nino-data:/data`.
- `build.sh`: chiaki-ng alt modüllerini hazırlar ve imajı derler.

## 13. Yeni sürümde bilerek değişenler

- Panel ve konsol metinleri yeniden yazıldı (anlamları aynı). Çeviri denemesinin örnek cümlesi değişti.
- Günlük satırları: okuma süresi `… ms, derin → metin` (boşsa `—`); panel hatası `ileti (tür)`.
- `remoteplay.log` yarıya inerken kalan kısım bir satırın başından başlar (eskiden satır ortasından başlayabilirdi).
- `--read-raw`: çekirdek bağlı değilken çıkış kodu **4**; eksik argümanda **1**.
- "Daha iyi çeviri" adımı boş değil (§4.5).
- Docker imajı LG/Samsung paketlerini ortak web TV uygulamasından (`apps/tv-web`) üretir; Android TV paketi isteğe
  bağlı olarak `apps/linux/tv-apk/` altından alınır.
- Okuyucunun büyütmesi (orta şerit ×2) çekirdeğin büyütmesini kullanır; Linux ve masaüstü aynı pikselleri okur.
- Akışın tamamı artık ortak denetleyiciden (`NinoController`) gelir; masaüstüyle aynı kurallar geçerlidir:
  - Karşılama'dan ileri geçince çeviri modeli arka planda inmeye başlar.
  - Kurulum bitti sayılması: `setupComplete` + PS5 hazır; kayıt yoksa "PS5 hazır ve TV eşli" (eski birimler böyle açılır).
  - Uygulamaya gömülü oyun paketi yoktur; ortak havuz ve paket sunucusu Linux'ta kapalıdır.
  - Çevrimiçi çeviri anahtarları ayrı yerlerde: Claude `claudeKey`, DeepL `deepLKey`; motor ayarda (`OnlineEngine`).
    Panelin tek alanı `sk-ant-` ile başlayanı Claude'a kaydeder.
  - Yerel çeviri süresi günlüğü ("yerel model N ms") yok; yerine çekirdeğin altyazi.log / hata.log satırları var.
- `--read-raw` ve "bu alanı şimdi oku" kayıtlı altyazı bölgesini kullanır (eskiden `--read-raw` varsayılan bölgeyi).
- Yeni günlük dosyaları: `altyazi.log`, `hata.log`; ölçüm kuyruğu `telemetry/` (istemciyi ortak denetleyici yönetir), kurulum kimliği `pool-translations/install`.
- Türkçe model: eski `models/en-tr` (ONNX) korunur ve kullanılır; yeni kurulumlar CT2 modelini indirir
  (`models/en-tr-ct2`, Python işçisi `ct2/`).
- Yeni ortam değişkeni `NINO_TESSERACT_LIBRARY`: libtesseract'ın tam yolu (verilmezse eskisi gibi adlarla aranır).
- Sürüm masaüstüyle aynı: 4.5.0.
- Uyku: sunucu uyuyup uyanınca (tekdüze saat ile duvar saati arasındaki farktan anlaşılır) denetleyiciye uyku ve uyanış art arda bildirilir; PS5/TV bağlantısı hemen yenilenir, teşhis aradaki kopmayı arıza saymaz.
