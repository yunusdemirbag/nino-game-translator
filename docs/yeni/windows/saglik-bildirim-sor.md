# Windows: sistem sağlığı, sorun kaydı, otomatik bildirim, `settings.about.reportProblem`, Nino'ya Sor — tarif

Kod yoktur; metinler yalnız **anlam** olarak (İngilizce / Türkçe anlamı) verilir. Sunucuya giden JSON alan adları,
dosya adları, sınırlar ve sabit (çevrilmeyen) değer sözcükleri uyumluluk için **birebir**dir.
Platformdan bağımsız parçalar `apps/windows/src/Nino.Core/` (Linux da kullanır), denetleyiciye bağlanan sorun bekçisi
`Nino.Shell/`, ekranlar ve fotoğraf kodlayıcı `Nino.App/` (WPF). Denetleyici: `denetleyici.md`.
Mac karşılığı: Mac `gecmis-hakkinda-saglik.md` (`settings.section.systemHealth`, `settings.about.reportProblem`) ve `ninoya-sor.md`. Farklar her bölümün
sonunda.

---

## 1. Sağlık kaydedici (oturum sayıları)

Uygulama boyunca **tek** paylaşılan kaydedici vardır (denetleyici, Remote Play günlük dinleyicisi ve ekranlar aynısını
kullanır). Kilitle korunur; her yerden çağrılabilir. Saat dışarıdan verilebilir (testler).

Sayılar (anlık görüntüde): etkin mi, başlama anı, şu an görüntü geliyor mu, görüntünün geldiği toplam saniye,
bağlanma denemesi, bağlanma, akışta kopma, son kopma nedeni (ad), **kopuk olduğu an** (geri gelince yok), oturumdaki ağ
kopması, TV kopması, yeniden gönderilen paket, gönderim tamponu taşması, görüntü durması, bozuk kare bildirimi, altyazı
satırı, çeviri sayısı, çeviri süresi ortancası, en uzun çeviri süresi.

Olaylar:
- **Oturum başladı**: her şey sıfırlanır, etkin = evet, başlama anı = şimdi.
- **Oturum bitti**: akış süresi kapanır; etkin ve "görüntü geliyor" = hayır. **Sayılar silinmez** (kullanıcı Ayarlar'ı genellikle sorunlu bir oturumun ardından açar); yeni oturumda sıfırlanır.
- **Bağlanıyor**: deneme +1.
- **Görüntü geldi**: bağlanma +1, görüntü geliyor = evet, kopukluk biter; akış saati (yoksa) şimdi başlar.
- **Koptu (neden ya da yok)**: neden yoksa kullanıcının durdurmasıdır, kopma sayılmaz. Görüntü geliyorken nedenli
  kopma +1. Nedenliyse kopukluk anı (yoksa) şimdi; son neden yazılır. Görüntü geliyor = hayır, akış saati kapanır.
- **Ağ gitti** ve `health.problem.tvDropped`: yalnız oturum etkinken +1.
- **Remote Play günlük satırı** (saniyede yüz kez gelebilir, hızlı): içinde
  "Send Buffer re-sending packet" → yeniden gönderim +1; "Send Buffer overflow" → taşma +1; "FEC failed" ya da
  "Video FEC failure" → durmada değilse durma +1 ve "durmada"; "Received IDR frame" → durma biter (yeni anahtar kare);
  "corrupt frame" → bozuk kare +1. (Bir donmada libchiaki birkaç FEC satırı yazar; bir kez sayılır.)
- **Ekrana giden satır (çeviri süresi ya da yok)**: satır +1; süre varsa (paket satırında yok) son 200 süre tutulur,
  çeviri +1, en uzun güncellenir.
- **Anlık görüntü**: akış sürüyorsa geçen süre eklenir; ortanca = sıralanmış son 200 sürenin ortadaki elemanı
  (çift sayıda üstteki; yoksa yok).

Türetilenler: ölçüm yok = başlama anı yok. "Kopuk" = etkin, görüntü gelmiyor, kopukluk anı var. Oranlar yalnız
en az **0,5 dk** akıştan sonra: dakikada kayıp = (yeniden gönderim + taşma) / dakika; dakikada durma = durma / dakika.

### 1.1 Kararlar (yeşil/sarı/kırmızı), eşikler birebir
- **Görüntü**: oran yoksa bilinmiyor; kayıp ≥ 100/dk ya da durma ≥ 4/dk → sorun; kayıp ≥ 10 ya da durma ≥ 2,5 → uyarı;
  değilse iyi.
- `health.check.ps5.name`: ölçüm yoksa bilinmiyor; kopuksa sorun; hiç bağlanmadıysa deneme ≥ 2 ise sorun, değilse bilinmiyor;
  kopma ≥ 3 ise uyarı; değilse iyi.
- `health.check.speed.name` (ortanca): yoksa bilinmiyor; ≥ 3000 ms sorun; ≥ 1500 ms uyarı; değilse iyi.
- **Ağ**: kablo iyi; ağ yok sorun; bilinmiyor bilinmiyor; Wi-Fi ve diğer → görüntünün kararı (ölçülmeden yeşil gösterilmez).
- **Ağ türü bulma**: çalışan, geri döngü olmayan ve varsayılan ağ geçidi olan arabirimler; hiç yoksa ağ yok; biri
  Ethernet türündeyse kablo; biri kablosuzsa Wi-Fi; değilse diğer; hata olursa bilinmiyor. (İzin istemez.)

### 1.2 Muhtemel sebepler (önemliden önemsize; ilk olan başlık olur)
1. Ölçüm yoksa: ağ yoksa yalnız **ağ yok** sebebi, değilse hiçbiri.
2. Ağ yoksa **ağ yok**.
3. Kopuksa ve ağ varsa **PS5 koptu** (son neden, oturumda ağ gitmiş miydi); değilse hiç bağlanmadı ve
   deneme ≥ 2 ise **hiç bağlanamadı** (son neden).
4. Ağ kopması > 0, ağ var ve kopuk değilse **ağ gidip geldi** (sayı).
5. Görüntü ≥ uyarı ise **görüntü kaybı** (Wi-Fi ya da diğer bağlantıda mı, sorun düzeyinde mi).
6. Kopuk değil, kopma ≥ 3, görüntü uyarının altında ve ağ kopması 0 ise **sık kopma** (sayı).
7. Çeviri ≥ uyarı ise **çeviri yavaş** (ortanca ms).
8. TV kopması > 0 ise **TV koptu** (sayı).
Örnekler: 30 dk akış, ağ kopması, sonra "bulunamadı" → kopuk, kopma 1, son neden `NotFound`, kopukluk anı 30. dakika,
bağlantı sorun, ilk sebep PS5 koptu (neden `NotFound`, ağ kaybı yok); görüntü gelince kopukluk biter, bağlantı iyi.
Ağ gitti sonra kopma → ilk sebep PS5 koptu (neden `Network`, ağ kaybından sonra). Ağ yokken PS5 kopması ayrıca sebep değil.
Kullanıcı durdurması kopukluk değildir, sebep çıkmaz. TV koptu → tek sebep TV koptu (sayı 1).

### 1.3 Düz metin özeti (destek için; altyazı metni ve adres yok). Altı satır, Türkçe, sayılar nokta ondalıklı:
Her satır `<kısa Türkçe etiket>: <değer>` ya da virgülle ayrılmış `<etiket> <değer>` öbeklerinden oluşur; etiketleri yeni
yazım kendisi seçer, **sıra ve değerler** şöyledir:
1. ağ türü (küçük harf ad: `wired`/`wifi`/`other`/`offline`/`unknown`), oturumdaki ağ kopması, TV kopması; kopuksa ek
   öbek: PS5'in kaç saniyedir (tam) kopuk olduğu
2. akış dakikası (bir ondalık), bağlanma denemesi, bağlanma, akışta kopma
3. son kopma nedeninin adı (yoksa `-`)
4. yeniden gönderim, tampon taşması, parantez içinde dakikada kayıp (yoksa `-`)
5. görüntü durması, parantez içinde dakikada durma (yoksa `-`), bozuk kare sayısı
6. altyazı satırı, çeviri sayısı, ortanca (ms ya da `-`), en uzun (ms)
Bu metin oturum sonunda altyazi.log'a satırlar " · " ile birleştirilerek, başında kısa bir "sağlık" etiketiyle de yazılır.

### 1.4 Sebeplerin ve sorunların ekrandaki metinleri (anlam; `reading.target.computer` denir, "Mac" asla)
| Sebep | Başlık | Ne yapılmalı |
|---|---|---|
| ağ yok | `health.cause.offline.title` | `health.cause.offline.advice` |
| PS5 koptu, ağ kaybından sonra | `health.cause.droppedAfterNetwork.title` | `health.cause.droppedAfterNetwork.advice` |
| PS5 koptu, neden uykuda | `health.cause.consoleAsleep.title` | `health.cause.consoleAsleep.advice` |
| PS5 koptu, neden başka cihazda | `health.cause.otherDevice.title` | `health.cause.otherDevice.advice` |
| PS5 koptu (diğer) | `health.cause.dropped.title` | `health.cause.dropped.advice` |
| hiç bağlanamadı | `health.cause.unreachable.title` | `health.cause.unreachable.advice` |
| ağ gitti geldi | `health.cause.networkFlapping.title` | `health.cause.networkFlapping.advice` |
| görüntü kaybı, Wi-Fi | `health.cause.pictureLossWifi.title` | `health.cause.pictureLossWifi.advice` |
| görüntü kaybı | `health.cause.pictureLoss.title` | `health.cause.pictureLoss.advice` |
| sık kopma | `health.cause.frequentDrops.title` | `health.cause.frequentDrops.advice` |
| çeviri yavaş | `health.cause.slowTranslation.title` | `health.cause.slowTranslation.advice` (%@ = saniye, bir ondalık, yerel ondalık işareti) |
| TV koptu | `health.cause.tvDropped.title` | `health.cause.tvDropped.advice` (%@ = sayı) |

Sorunların kısa adı: `health.problem.ps5Dropped` / `health.problem.ps5Unreachable` / `health.problem.networkLost` /
`health.problem.tvDropped`. Her sebep ve sorunun Türkçesi ayrı olmalı (test: İngilizcesiyle aynı olmasın; "Mac" geçmesin;
sayı Türkçe metinde de yazılsın).

---

## 2. Sorun kaydı (oturumlar arası kalan liste)

- Dosya: sağlık klasöründe (`%LOCALAPPDATA%\Nino`) `sorunlar.json`. JSON dizi; alan adları küçük harfle başlar
  (Mac ile aynı), boş alanlar yazılmaz, tür adları küçük harfle başlar: `ps5Dropped`, `ps5Unreachable`, `networkLost`,
  `tvDropped`. Türkçe harfler kaçırılmaz.
- Bir kaydın alanları: `id` (GUID), `date` (UTC), `kind`, `reason` (kopma nedeninin adı, adres yok), `streamedMinutes`
  (o ana kadar akış dakikası; ölçüm yoksa yok), `lossPerMinute`, `stallsPerMinute`, `network` (`wifi`, `wired`…),
  `game`. Altyazı metni, PS5 adı ya da adres **içermez**.
- **Uyum doğrulamasıyla kesinleşen (eski dosyanın baytları):** `date` UTC olarak **`Z` ile** yazılır, kesir varsa en
  kısa haliyle (`"2026-11-22T18:04:05.123Z"`, `"2026-11-22T18:10:00Z"`); `+00:00` yazılmaz (eski okuyucu ofsetli
  tarihi yerel saate çevirir). Alanlar şu sırayla: `id, date, kind, reason, streamedMinutes, lossPerMinute,
  stallsPerMinute, network, game`. Hesaplanan değerler (Türkçe ad, destek satırı) dosyaya **yazılmaz**. Test:
  `Fixtures/Compat/old/small/sorunlar.json`.
- En çok **40** kayıt, en yenisi sonda; fazlası baştan atılır. Yazım geçici dosyaya (`.tmp`) yazılıp yerine taşınarak.
  Okuma/yazma hataları sessiz. Okunurken de son 40 alınır. Temizleme dosyayı siler. Klasör yoksa (testler, Linux) yalnız bellekte.
- Bir andan sonraki kayıtların sorgusu (tarih ≥ verilen).
- **Destek satırı** (Türkçe, ekran dilinden bağımsız): `gg.AA SS:dd <Türkçe ad>` + (neden varsa ` (<neden>)`), sonra
  " · " ile: akış dakikası varsa tam dakika + "dk" ve kısa bir "oynandı" sözü, ağ türü (`ağ <ağ>` biçiminde), oranlar
  varsa dakikada kayıp (tam) ve dakikada durma (bir ondalık) `/dk` ile, oyun varsa adı. Yerel saatle. Türkçe adlar her tür
  için Türkçe katalogdaki kısa ad (`health.problem.*`). Biçim örneği (kendi örneğimiz):
  `03.02 09:15 <PS5 kopma adı> (Network) · 7 dk <oynandı sözü> · ağ wired · kayıp 3/dk, durma 1.5/dk · Elden Ring`.

---

## 3. Sorun bekçisi (çeviri sürerken sorunları yakalar)

Denetleyici kurar; bütün çağrılar arayüz iş parçacığındandır. Denetleyiciden sorduğu: çeviri sürüyor mu, `health.check.picture.name`
geliyor mu, altyazı TV'ye gidiyor mu, bağlı TV sayısı, otomatik bildirim açık mı, oynanan oyun, ağ türü, başlık
(muhtemel sebebin ekran dilindeki başlığı), bildirim gövdesi kurucu, günlük, "liste değişti".

Sabitler: **PS5 geri gelmedi = 180 sn**, **TV kopması = 20 sn** (TV uygulaması 2 sn'de yeniden bağlanır; kısa kopmalar
sayılmaz). Bekleme işlevi dışarıdan verilebilir (testler elle bitirir).

- **Başlat** (açılışta): ağ türü okunur; sağlık klasörü varsa (yalnız gerçek uygulamada) ağ olaylarına abone olunur —
  hem "ağ kullanılabilirliği değişti" hem "ağ adresi değişti" (VPN/sanal bağdaştırıcı açıkken ilki gelmeyebilir); olay
  arka planda gelir, tür yeniden bulunup arayüze aktarılır. Bir önceki açılışta yollanamamış bildirim kaldıysa arka planda gönderilir.
- **Oturum başladı**: "bu oturumda bildirildi" sıfırlanır, oturum başlangıcı = şimdi, son TV sayısı alınır.
- **Oturum bitti**: iki zamanlayıcı iptal; oturum başından beri sorun kaydı olduysa **ya da** görüntü ya da çeviri
  kararı "sorun" ise otomatik bildirim gönderilir; oturum başlangıcı silinir.
- **Kayıt**: sağlık sayıları, ağ türü ve oyunla kayıt oluşturulur, listeye eklenir, altyazi.log'a kısa bir "sorun"
  etiketiyle destek satırı yazılır; "liste değişti" olayı.
- **PS5 koptu (neden, görüntü geliyor muydu)**: çeviri yoksa hiçbir şey. Görüntü geliyorduysa `ps5Dropped` kaydı. Zamanlayıcı
  varsa ikincisi kurulmaz (yeniden denemeler). 180 sn sonra (iptal edilmediyse): çeviri sürüyor ve görüntü gelmiyorsa
  `ps5Unreachable` kaydı (neden: kaydedicideki son neden) **ve** otomatik bildirim.
- **PS5 geri geldi**: zamanlayıcı iptal.
- **TV sayısı değişti**: > 0 ise TV zamanlayıcısı iptal. 0'a düştüyse ve önceki > 0, çeviri sürüyor, TV'ye gidiyor ve
  zamanlayıcı yoksa: 20 sn sonra çeviri sürüyor ve TV hâlâ 0 ise kaydediciye TV kopması ve `tvDropped` kaydı.
- **Ağ değişti**: yeni tür "ağ yok", önceki "ağ yok" değil ve çeviri sürüyorsa kaydediciye ağ kopması ve `networkLost` kaydı.
- **Otomatik bildirim**: ayar kapalıysa ya da bu oturumda gönderildiyse yok; işaretlenir; metin = tespitler (§4, otomatik);
  gövde kurulamazsa (klasör yok) yok. Gönderim **beklenmeden** başlatılır (bildirim ilk beklemeye girmeden dosyaya kaydedilir; uygulama kapanırken gönderilemese de sonraki açılışta gider); sonuç altyazi.log'a tek satır: otomatik bildirimin
  gittiği ya da gidemediği (sonra denenecek ya da günlük sınır).
- Kapatılınca zamanlayıcılar iptal, ağ aboneliği çözülür.

Otomatik bildirimin gövdesi (denetleyici kurar): kuruluş kimliği (§6.2), uygulama sürümü, `setup.welcome.translationLanguage`, metin, iletişim
yok, günlük yok, fotoğraf yok, cihaz özeti (§5), tür `auto`.

Testler: (sahte bekleme; ağ Wi-Fi, oyun "GTA 6", bildirim sahte "gönderildi")
- PS5 görüntü gelirken `NotFound` ile koptu → bir `ps5Dropped` kaydı; ikinci kopma çağrısı ikinci zamanlayıcı kurmaz,
  bekleyen tek bekleme 180 sn; bitince son kayıt `ps5Unreachable`, 1 bildirim; metin otomatik etiketiyle başlar,
  muhtemel sebep satırında `health.cause.dropped.title` ve "GTA 6" içerir, tür `auto`, günlük yok; oturum bitince ikinci bildirim yok.
- Kopup geri gelen PS5 bildirilmez, `ps5Unreachable` kaydı yok.
- Ağ yok → tek `networkLost` kaydı, kaydedicide 1; ikinci "ağ yok" sayılmaz; oturum bitince 1 bildirim.
- Temiz oturum ve kapalı ayar: hiçbir şey gönderilmez; kapalı ayarda kayıt yine tutulur.
- TV 0 sonra 1 → kayıt yok; TV 0 ve 20 sn → bir `tvDropped` kaydı, kaydedicide TV kopması 1.
- Çeviri yokken PS5 kopması ve ağ yok hiçbir şey kaydetmez, zamanlayıcı kurmaz.
- Otomatik bildirim ayarı varsayılan **açık**.

---

## 4. Bildirim metni (Nino'nun tespitleri)

`settings.about.reportProblem` ve otomatik bildirim aynı metni kurar. Parçalar boş satırla (`\n\n`) ayrılır:
1. Giriş satırı: otomatikse köşeli ayraç içinde "otomatik" etiketi + Nino'nun bir sorun fark ettiğini ve kullanıcının bir
   şey yazmadığını söyleyen tek cümle; kullanıcı bir şey yazmadıysa köşeli ayraç içinde "hataları gönder" etiketi +
   kullanıcının açıklama yazmadığını, tespitlerin aşağıda olduğunu söyleyen tek cümle; yazdıysa kırpılmış yazısı.
2. Uzun tirelerle (`— … —`) çevrili "Nino'nun tespitleri" başlığı + (başlık varsa) `\n` + "muhtemel sebep" etiketi,
   `: ` ve başlık + (son **3 günün** sorunları varsa) `\n` + son sorunlar etiketi + `:\n` ve en çok son **12** sorun her
   biri `• <destek satırı>` satırında + `\n<özet (§1.3)>`.
- Bu sabit Türkçe öbekler sunucu ve ekip içindir, çevrilmez (sözcüklerini yeni yazım seçer). Başlık ekran dilindedir.
- Toplam en çok **4000** UTF-16 birimi; kesim yüksek vekil karakterin ortasına düşerse o karakter de atılır.
- Örnekler: boş yazı + bir sebep başlığı + bir ağ kaydı → "hataları gönder" etiketiyle başlar, muhtemel sebep satırında
  o başlık ve ağ kaydının Türkçe kısa adı geçer. Kullanıcı "Ses var, yazı yok" yazınca metin onunla başlar. 3000 emoji →
  ≤ 4000 birim, son karakter yarım değil.

---

## 5. `device.title`

Kullanıcının ne kullandığının kısa özeti; `settings.section.systemHealth`'nda görünür ve her bildirime (`settings.about.reportProblem`, otomatik, Nino'ya
Sor) eklenir. **Kişiyi tanıtan hiçbir şey yoktur**: bilgisayar adı, kullanıcı adı, seri numarası, IP, hesap adı, TV'nin ya
da PS5'in kullanıcı verdiği ad, seçilen pencerenin başlığı, kart adı girmez. Değerler **çevrilmez** (ekip okur).

Satırlar (sabit kimlik → değer), boş olan satır olmaz; değerlerde satır sonları boşluğa, `|` `/`'ye çevrilir, kırpılır:
- `app`: uygulama sürümü.
- `device`: bilgisayarın üreticisi ve modeli (BIOS'un kayıt defterindeki üretici ve ürün adı). Yer tutucular
  (BIOS üreticilerinin boş bıraktığı alana koyduğu sabit değerler: "system manufacturer", "system product name", OEM'in
  doldurmasını isteyen iki yazım — noktalı ve noktasız "o.e.m." —, "default string", "not applicable", "not specified",
  "none", "unknown", "o.e.m.", "oem"; büyük/küçük harf duyarsız) model sayılmaz. İkisi de yoksa `Windows PC`;
  biri yoksa öbürü; model üreticinin adıyla başlıyorsa yinelenmez, değilse "üretici model". Örnek: `ASUS ASUS TUF A15` → `ASUS TUF A15`.
- `system`: ana sürüm 10 ve yapı ≥ 22000 → `Windows 11`, 10 ve altı → `Windows 10`, diğer `Windows <ana>.<alt>`; yapı > 0 ise
  ` (<yapı>)`. Örnek: 10.0, yapı 22631 → `Windows 11` + boşluk + `(22631)`. Windows dışında sistemin açıklaması.
- `tv`: TV yoksa yok. Marka (`Samsung Tizen`, `Android TV`, diğer `LG webOS`), TV uygulamasının bildirdiği model
  (varsa), sürüm gibi görünüyorsa (rakamla başlar, en çok 31 karakter harf/rakam/`.`/`-`/`+`) "TV uygulaması" sözü +
  boşluk + sürüm, bağlı olup olmadığını söyleyen kısa Türkçe söz; " · " ile. Sürüm: TV uygulaması durumundaki sürüm, yoksa kayıtlı kurulan sürüm.
- `console`: Türkçe kısa adlar, biçim `<konsol> · <yol>`: kart → yakalama kartının Türkçe adı (konsol öneki yok); oyun
  penceresi → `Xbox · <pencere sözü>` / `PS5 · <pencere sözü>`; Xbox türü → `<Xbox modeli> · <uzaktan oynatma sözü>`;
  Remote Play penceresi → `PS5` + ` · ` + `Remote Play` + pencere sözü + ` (PS Remote Play)` / ` (chiaki-ng)` / hiçbir
  şey; seçilen pencere → seçilen pencerenin Türkçe adı; diğer (PS5 akışı) `PS5` + ` · ` + `Remote Play`.
  Xbox modeli: `Xbox` ile başlayıp 1–20 harf/rakamla süren değerde küçük harf/rakamdan sonra gelen büyük harfin önüne
  boşluk (`XboxSeriesX` → `Xbox Series X`, `XboxOne` → `Xbox One`, `Xbox` → `Xbox`); başka her şey (ad, boş) `Xbox`.
- `status`: çevirinin açık mı kapalı mı olduğunu söyleyen kısa Türkçe söz + oyun penceresinde `, pencere: <Stopped|LookingForWindow|Capturing>`, kartta
  `, kart: <Stopped|NeedsPermission|NoCard|BlackPicture|Capturing>`, diğer `, <PS5|Xbox>: <Disconnected|Connecting|Streaming>`
  ve kopuk + nedenli ise ` (<neden adı>)` ya da ayrıntı tam olarak `0x` + 1–8 onaltılık ise ` (<neden> <kod>)`
  (adres gibi ayrıntılar alınmaz). Son kopma nedeni 1–40 ASCII harften oluşuyorsa `, <son kopma sözü>: <ad>`. Sonuna
  oyun: `, <oyun sözü>: <ad>` ya da oyunun tanınmadığını söyleyen söz.
- **Özet** (sunucuya): `app: … | device: … | system: … | tv: … | console: … | status: …` (` | ` ile), en çok **600**
  karakter. İsteğe konurken kırpılır, 600'e kesilir, boşsa alan hiç gönderilmez.

Örnekler (kendi örneklerimiz): TV (LG, kullanıcı adı "Salon ekranı", sürüm 2.1.0, bağlı) → `LG webOS · <TV uygulaması> 2.1.0 ·
<bağlı>` (kullanıcının verdiği ad girmez); Samsung modeli "Samsung UE55TU7000" bağlı, sürüm yok → `Samsung Tizen · Samsung
UE55TU7000 · <bağlı>`; Android ` 1.4.2-rc.1 ` (boşluklu) → `Android TV · <TV uygulaması> 1.4.2-rc.1 · <bağlı>`; sürüm
yerine adres gibi bir değer ("10.0.0.7 / y") → `LG webOS · <bağlı değil>`. Durum: çeviri kapalı + PS5 kopuk →
`<kapalı>, PS5: Disconnected`; ayrıntı `0x8010ffff` ile reddedildi → `<açık>, PS5: Disconnected (Rejected 0x8010ffff)`;
bulunamadı + adres → `<açık>, PS5: Disconnected (NotFound)` (adres girmez); son kopma `ConsoleAsleep` → `…, <son kopma
sözü>: ConsoleAsleep`; son kopma adı yerine ad + adres ("Oturma-PS5 10.0.0.9") → eklenmez; pencere yakalanıyor →
`<açık>, pencere: Capturing`; kart yok → `<açık>, kart: NoCard`; Xbox reddetti → `<açık>, Xbox: Disconnected (Refused)`. Denetleyiciden alınan satır sırası `app, device, system, tv, console, status`;
özette PS5 adı, TV adı, `192.168` ve TV jetonu geçmez. TV yoksa `tv` satırı yok.
TV modeli sunucuda temizlenir: `/events?model=Samsung%20UE55TU7000` → `Samsung UE55TU7000`; `%3Cscript%3EX` → `scriptX`;
başka parametreyle birlikte de okunur; boş/yok → yok; en çok 60 karakter.

---

## 6. Otomatik bildirici ve `settings.about.reportProblem` gönderimi

### 6.1 Sunucu sözleşmesi (`POST /v1/reports`)
- Adres = havuz kök adresi + `/v1/reports`. Kök adres sırası: `NINO_POOL_URL` ortam değişkeni → havuz klasöründeki
  (`%LOCALAPPDATA%\Nino\pool\`) `endpoint.txt` → canlı adres `https://nino-pool.y-demirbag2506.workers.dev`. Değer
  http/https mutlak adres değilse atlanır. Kök yoksa adres yok.
- Başlık `Content-Type: application/json; charset=utf-8`. Zaman aşımı 60 sn (Windows).
- Gövde (boş alanlar yazılmaz; base64'teki `+` ve Türkçe harfler kaçırılmaz):
```json
{
  "v": 1,
  "install": "<kuruluş kimliği, 8–64 karakter>",
  "app": "<sürüm, en çok 40 karakter>",
  "platform": "windows",
  "language": "<çeviri dili kodu>",
  "text": "<en çok 4000>",
  "contact": "<isteğe bağlı, en çok 200>",
  "log": "<isteğe bağlı, en çok 60000 karakter; fazlası baştan kesilir>",
  "images": [ { "mime": "image/jpeg", "data": "<base64>" } ],
  "device": "<cihaz özeti, en çok 600; boşsa yok>",
  "kind": "auto"
}
```
  - Metin ve iletişim kırpılıp kesilir; boş iletişim/günlük gönderilmez; `images` **her zaman dizi** (boş da olur), en
    çok 3, boş bayt atlanır; `kind` yalnız otomatikte (`auto`; eski sunucu yok sayar, metin de "[Otomatik]" ile başlar).
- Cevap: 200 → gönderildi (gövdede `id` dizgisi varsa okunur, ör. `{"ok":true,"id":"r-1"}`); 429 → sınır (Retry-After
  süresi okunur); 413 → çok büyük; 400 → reddedildi; diğer → başarısız. Ağ hatası, zaman aşımı → başarısız (istisna
  fırlatılmaz; yalnız dışarıdan iptal edildiyse fırlatılır).
- Sınırlar: sunucunun fotoğraf başına sınırı 1500 KB; bizim hedef 900 KB (3 × 900 KB base64 ≈ 3,6 MB); gövde en çok 4 MB.
  Test: 3 × 900 KB fotoğraf + 5000 karakterlik "ş" metni + 60000 karakterlik Arapça günlük ≤ 4 MB.

### 6.2 Kuruluş kimliği
Havuzun kuruluşa özgü rastgele kimliği 8–64 karakterse o. Değilse `report-install.txt` (veri klasöründe) okunur,
8–64 karakterse o; değilse yeni bir GUID (32 onaltılık, tiresiz) üretilir ve dosyaya yazılır (yazılamazsa bu açılışta yine
kullanılır). Örnek: havuz `pool-install-id` → o; yoksa üretilen kimlik sonraki çağrıda aynı; havuz `short` (kısa) → dosyadaki.

### 6.3 Otomatik bildirici (günlük sınır ve bekleyen bildirim)
- Dosya: **`otomatik-bildirim.json`** (sağlık klasöründe), alanlar `Day` (`yyyy-MM-dd`, yerel gün), `Sent` (o gün
  gönderilen), `Pending` (bekleyen gövde, §6.1 biçiminde; yoksa yazılmaz). Geçici dosya + taşıma ile yazılır.
- **Uyum doğrulamasıyla kesinleşen:** dosya, eski uygulama gibi .NET'in **varsayılan** kaçışıyla yazılır: `Pending`
  içindeki ASCII dışı harfler ve `" < > & ' +` `\uXXXX` olur (`ba\u011Flant\u0131s\u0131`, `\u0022x\u0022`). Sunucuya
  giden gövde ayrıca §6.1 biçiminde (harfler kaçışsız) yeniden üretilir. Test: `Fixtures/Compat/old/small/otomatik-bildirim.json`.
- Günde en çok **3** otomatik bildirim (sunucunun kuruluş başına günde 10 bildirim sınırının büyük kısmı elle yollananlara kalsın).
- **Gönder**: gövdeye tür `auto`, günlük/iletişim yok, fotoğraf boş zorlanır. Bugünkü sayı 3 ise false. Gün değiştiyse
  sayaç sıfırlanır; sayı +1; bekleyen = bu gövde; **gönderilmeden önce dosyaya yazılır**. Sonra teslim.
- **Teslim**: gönderim sonucu (istisna = başarısız). Başarısızsa (ağ yok/yanıt yok) bekleyen kalır, false (sonraki açılışta
  denenir). Değilse bekleyen aynı gövdeyse (JSON karşılaştırması) silinir ve yazılır; sonuç "gönderildi" ise true
  (sunucu reddettiyse ya da sınırdaysa tekrar denenmez, false).
- **Bekleyeni gönder** (açılışta): bekleyen varsa teslim.
- Testler: 5 gönderimde 3'ü gider; ilkinde `kind`=`auto`, `log`/`contact` yok, `images` boş dizi; sınır dosyada kalır
  (yeni nesne "bugün gönderilemez"); 24 saat sonra gönderilebilir. Çevrimdışı gönderim false; sonraki açılışta bekleyen
  var, gönderilir, bir daha gönderilmez, sonra bekleyen yok. Hiç bitmeyen gönderimde yeni nesne bekleyeni görür (kapanırken
  kaybolmaz). Reddedilen bildirim tekrar denenmez, bekleyen yok.

### 6.4 Günlükleri toplama ve gizleme (`settings.about.reportProblem`'de `report.includeLog.title`)
- Dosyalar ve payları (her birinin sonundan): `hata.log` 10 000, `remoteplay.log` 18 000, `altyazi.log` 24 000,
  `tvinstall.log` 8 000 karakter (hepsi `%LOCALAPPDATA%\Nino`). Olmayan atlanır; hiçbiri yoksa günlük yok.
- Dosya sonu okuma: yazılırken de okunabilsin diye paylaşımlı açılır; karakter başına en çok 4 bayt hesabıyla sondan
  okunur; dosyanın ortasından başlandıysa ilk yarım satır atılır; sonra pay kadar son karakter (§ kesim kuralı).
- Her parça `— <dosya adı> —\n<sonu, sondaki boşluk kırpılmış>`; parçalar boş satırla birleşir; **önce gizlenir, sonra**
  toplam 60 000 karaktere kesilir (kesimin ortasında kalan anahtar uzunluk kalıplarından kaçmasın).
- **Son N karaktere kesim**: metin uzunsa son N alınır; kesim satır ortasına düştüyse (ilk satır sonu son karakter değilse)
  o yarım satır atılır.
- **Gizleme** (`[gizlendi]` ile değiştirilir), sırayla:
  1. `Bearer` ya da `Basic` (büyük/küçük duyarsız) + boşluk + en az 8 karakterlik belirteç (harf, rakam, `._~+/=-`) →
     şema kalır, değer gizlenir (`Bearer <belirteç>` → `Bearer [gizlendi]`).
  2. **Atamalar**: önünde harf olmayan şu adlar (duyarsız): api_key/api-key/apikey, key, token, access_token,
     refresh_token, secret, client_secret, password, passwd, pwd, passcode, pin, auth, authorization, cookie,
     session_key, npsso; ardından isteğe bağlı tırnak, boşluk, `=` ya da `:`, boşluk, isteğe bağlı tırnak; değer boşluk,
     tırnak, `&`, `,`, `;` gelene kadar. Değer zaten gizlenmişse ya da "Bearer"/"Basic" ise dokunulmaz; değilse ad kalır,
     değer gizlenir. (`hotkey=F8` kalır: önünde harf var.)
  3. Kalıplar: Google anahtarı (`AIza` + en az 20 harf/rakam/`_-`), `sk-` + en az 16 (`sk-proj-…`, `sk-ant-…`), GitHub
     (`gh` + p/o/u/s/r + `_` + en az 20 harf/rakam), UUID (8-4-4-4-12 onaltılık, isteğe bağlı `:fx`), en az 32 onaltılık
     karakterlik dizi.
  4. Uzun belirteç: önünde harf/rakam/`+/_-` olmayan, en az 40 karakter harf/rakam/`+/_-` ve en çok 2 `=`; içinde hem
     rakam hem harf varsa gizlenir.
- Gizlenen örnekler (kendi örneklerimiz): `Authorization: Basic QWxhZGRpbjpvcGVu` → `Authorization: Basic [gizlendi]`,
  `yanıt pin=4821 geldi` (değer gizlenir), `{"client_secret":"x9y8z7w6"}`, `cookie: s=abc.def`, `x refresh_token=r1r2 y`,
  `my_password: hunter`, `gemini_key=q1w2` (`=q1w2` kalmaz; önünde `_` var, harf değil), `AIza` + 24 karakterlik anahtar,
  `sk-` + 20 karakterlik anahtar (`sk-proj-…`, `sk-ant-…` biçimleri de), `ghp_` + 24 harf/rakam, UUID (sonunda `:fx`
  olanı da), 34 onaltılık karakterlik dizi, JWT benzeri 50 karakterlik harf-rakam dizisi.
- Aynen kalan örnekler: saat + okunan İngilizce satır + çevirisi (soru işaretli, tırnaklı) satırı, model dosyasının
  `%LOCALAPPDATA%` altındaki tam yolu + "yüklendi", bir .NET istisna adı + `Nino.` ile başlayan yöntem yolu, ISO saat +
  özel ağ adresi + çözünürlük + fps satırı, `hotkey=F8` içeren satır (önünde harf var).
- Test: `hata.log` iki satır (biri `key=` + 12 karakterlik değer) + 5000 satırlık `altyazi.log` + olmayan dosya, sınır
  2500 → ≤ 2500, gizli değer yok, iki başlık var, olmayanın adı yok, son satırla biter. 100 numaralı satırlık metinden
  son 25 karakter: yarım satır atılır, tam satırla başlar ve son satırla biter.

### 6.5 Fotoğraf sığdırma (Core, kodlayıcıdan bağımsız)
- Boyut: en uzun kenar 1600'ü geçmez, oran korunur, büyütülmez (3840×2160 → 1600×900; 1080×2400 → 720×1600; 800×600 aynı).
- Denemeler: kenar 1600, 1280, 1024, 800, 640; her birinde kalite 70, 55, 40 (önce kalite, sonra boyut). Sınırın altında
  kalan ilk sonuç; hiçbiri sığmazsa yok. `settings.about.reportProblem` sınırı 900 KB, Nino'ya Sor 600 KB.

---

## 7. Ekranlar (Windows)

### 7.1 `settings.section.systemHealth` (Ayarlar içindeki sayfa)
- 2 sn'de bir yenilenir (görünürken). Yukarıdan aşağı kartlar:
  1. **Muhtemel sebep kartı**: sebep varsa uyarı işareti + ilk sebebin başlığı, altında ne yapılacağı, diğer sebepler "• <başlık>"
     satırlarında (ikincil renk). Sebep yok ama oturum etkin ve görüntü geliyorsa `health.allGood`. Değilse gizli.
  2. **Denetimler kartı**: ipucu (ölçüm yoksa `health.checks.hint.noData`;
     oturum bittiyse `health.checks.hint.lastSession`; sürüyorsa gizli). Satırlar
     (nokta rengi: iyi yeşil, uyarı sarı, sorun kırmızı, bilinmiyor gri; durum yazısı `health.level.good` /
     `health.level.warning` / `health.level.problem` / `health.level.unknown`; uyarı ya da sorunda altında öneri):
     - `health.check.network.name`: değerler ve öneriler `health.check.network.*` anahtarlarından (kablo, Wi-Fi, diğer, ağ
       yok, denetleniyor; öneri: ağ yoksa aynı modeme bağlanma, değilse görüntü kaybına karşı kablo ya da 5 GHz).
     - `health.check.ps5.name`: ölçüm yok `health.check.notStarted`; kopuksa `health.check.ps5.disconnectedFor` (en az 1);
       hiç bağlanmadıysa `health.check.ps5.neverConnected`; kopma yoksa `health.check.ps5.noDrops`; değilse kopma sayısı
       (`health.check.ps5.drops`). Öneri son nedene göre `health.check.ps5.advice.*`: uykuda (açın ya da dinlenmede
       İnternete bağlı kalsın), başka cihazda (orada kapatın), giriş şifresi `health.check.ps5.advice.loginPasscode`,
       Uzaktan Oynatma kapalı (PS5'te açın), eşleşme geçersiz ya da reddetti (yeniden kurulumdan yeniden eşleyin),
       bulunamadı (açık ya da dinlenmede ve aynı ağda mı), diğer `health.check.ps5.advice.other`.
     - `health.check.picture.name`: oran yoksa ölçüm yok `health.check.notStarted`, görüntü gelmiyor
       `health.check.picture.noPicture`, değilse `health.check.picture.measuring`; varsa dakikada kayıp paket (tam) ve
       donma (bir ondalık) değeri. Öneri `health.check.picture.advice`.
     - `health.check.speed.name`: ortanca yoksa: ölçüm yok `health.check.notStarted`, satır varsa
       `health.check.speed.allInstant`, değilse `health.check.speed.noSubtitles`; varsa satır başına saniye ve satır sayısı. Öneri: çevrimiçi etkin ya da motor yerel
       model ise `health.check.speed.advice.freeEngine`, değilse `health.check.speed.advice.closeApps`.
     - **TV**: çeviri yok ya da TV'ye gitmiyor → bilinmiyor; bağlı TV varsa iyi, değilse sorun. Değer: TV'ye gitmiyor
       `health.check.tv.notSent`, çeviri yok `health.check.notStarted`, bağlı `status.common.connected`, değilse
       `status.common.notConnected`. Öneri `health.check.tv.advice`.
     - Windows metinleri "Mac" demez, `reading.target.computer` anlamını kullanır; USB-C Ethernet adaptörü önerisi yoktur.
       Yeni kod doğrudan "bilgisayar" metinleri yazmalı.
  3. **`health.recent.title` kartı** (kayıt varsa): en çok 8, en yenisi üstte; solda yerel tarih-saat, sağda kısa ad. Altında:
     otomatik bildirim açıksa `health.recent.autoOn`, kapalıysa `health.recent.autoOff`.
  4. TV uygulaması kurulum kartı (adımlar ve hata, `common.retry`; ayrıntısı TV belgesinde).
  5. **Ayrıntılar** (açılır): salt okunur eş aralıklı yazı kutusu (odaktayken yenilenmez): satır 1 `Nino <sürüm>, Windows
     <sürüm>, <n> çekirdek`; satır 2 `motor: <motor ya da ücretsiz>, çeviri: sürüyor|durdu, PS5: <evre>`; satır 3
     `TV: <marka ya da yok>, bağlı TV uygulaması <n>, TV uygulaması: <durum>[ <sürüm>][ hata <hata>]`; özet (§1.3); boş
     satır; uzun tirelerle çevrili `altyazi.log` başlığı (dosya adı + "son satırlar" anlamı) + son 40 satır; boş satır; aynı
     biçimde `tvinstall.log` başlığı + son 8 satır (dosyanın son 64 KB'ından; dosya yoksa `-`). Düğmeler:
     `health.details.copy` (→ `common.copied`) ve `health.details.saveZip`. Zip: kullanıcının `Downloads` klasörüne `Nino-kayitlar-<yyyy-MM-dd-HH-mm-ss>.zip`; veri klasöründe
     adında `.log` geçen her dosya + `ayrintilar.txt` (ayrıntı yazısı); sonra Gezgin'de dosya seçili açılır. Hata: `health.details.saveFailed`
     + parantez içinde sistem iletisi. Gizlilik notu `health.details.privacy` (zip'i yardım edene gönderme; günlüklerde
     okunan altyazılar, PS5 adı ve ev ağı adresi var; şifre, anahtar, hesap bilgisi yok).
  6. `device.title`: ipucu `device.hint`; satırlar (solda ad: `device.label.app` / `device.label.device` / `device.label.system` / TV / Konsol / `device.label.status`; sağda değer); yalnız özet değişince yeniden kurulur. `device.copy` (özeti panoya; 3 sn
     `common.copied`).
- Pano hataları sessiz.

### 7.2 `settings.about.reportProblem` penceresi
- Ayarlar › Hakkında › `settings.about.reportProblem`'den (ve Nino'ya Sor'daki düğmeden) açılan sahipli pencere; genişlik 540, yükseklik
  içeriğe göre (en çok çalışma alanı − 80, kayar), boyut değiştirilemez, görev çubuğunda yok, sahibinin ortasında.
- İçerik, yukarıdan aşağı:
  1. Başlık `settings.about.reportProblem`.
  2. `report.noticed.title` kutusu (kenarlıklı, 12 köşe): başlık; muhtemel sebep (kalın) ve son **3 günün** en çok
     **6** sorunu (en yenisi üstte, `report.noticed.problemLine`: kısa saat + kısa ad); ikisi de yoksa
     `report.noticed.empty`; birincil `report.sendProblems` düğmesi
     (açıklama yazmadan gönderir).
  3. `report.moreTitle`
  4. Açıklama kutusu (çok satırlı, 140 yükseklik, en çok 4000 karakter, yer tutucu `report.descriptionPlaceholder`;
     Enter yeni satır açar).
  5. Fotoğraflar: 88×88 küçük resimler (12 köşe, sağ üstte ✕ `common.photo.remove`), 3'ten azsa "+" düğmesi ("`report.addPhoto`",
     çoklu dosya seçici). İpucu `report.photosHint`.
  6. İletişim kutusu (yer tutucu `report.contactPlaceholder`, en çok 200).
  7. `report.includeLog.title` (varsayılan açık): `report.includeLog.hint`
  8. `report.autoReport.title` (ayara bağlı; değiştirince ayar hemen değişir): `report.autoReport.hint`
  9. Gizlilik: `report.privacy`
  10. Hata yazısı (gizli), belirsiz ilerleme çubuğu (gizli), sağda `common.cancel` (Esc) ve `common.send`.
- `common.send` açıklama boşken de etkindir. Gönderirken: `report.sending`, alanlar salt okunur, günlük ve fotoğraf ekleme
  kapalı, ilerleme görünür.
- **Gönderim**: adres yoksa hemen `report.error.failed`. Metin =
  tespitler (§4, otomatik değil, kullanıcının yazdığıyla), iletişim, günlük (açıksa, arka planda toplanıp gizlenir),
  fotoğraflar, sürüm, **dil = çeviri dili**, kuruluş kimliği, cihaz özeti. Pencere bu arada kapatıldıysa sonuç gösterilmez.
  Sonuç: gönderildi → ortada yeşil ✓, `report.thanks`, `common.close`; 2,5 sn sonra kendiliğinden kapanır.
  Sınır → `report.error.dailyLimit`; çok büyük → `report.error.tooLarge`; reddedildi → `report.error.rejected`; diğer → `report.error.failed`.
  Başarısızlıkta form olduğu gibi kalır, yeniden denenebilir.
- **Fotoğraflar** (dosya seçici, sürükle-bırak, Ctrl+V): sırayla açılır, JPEG'e (en çok 900 KB, arka planda) çevrilir,
  3'te durur. Açılamayan ya da sığmayan olursa `common.photo.openFailed`. Sürükle-bırak yalnız dosya; gönderirken ya da 3 doluyken
  kabul edilmez; uzantıya göre görüntü dosyaları alınır. Ctrl+V: panoda resim ya da dosya bulunursa **ve** (imleç bir yazı
  kutusunda değil **ya da** panoda metin yok) ise fotoğraf olarak eklenir; değilse metin kutusu metni yapıştırır (Excel/OneNote
  hem metin hem görüntü koyar). Panoda dosya listesi varsa oradaki resim dosyaları, yoksa panodaki resim.

### 7.3 Nino'ya Sor penceresi
- Ana ekranın ve sihirbazın köşesindeki robot düğmesinden ya da Ayarlar › Hakkında bölümünden `home.robot.askNino` ile açılır. Açıksa öne
  gelir. **Sahibi her zaman ana penceredir** (Ayarlar'dan açılmış olsa bile Ayarlar kapanınca sohbet açık kalsın).
- Pencere 440 × 680, en az 360 × 460, boyutlandırılabilir, görev çubuğunda yok, sahibinin ortasında; sürükle-bırak kabul eder.
- **Başlık şeridi** (alt çizgili): 44 px göz kırpan robot (cevap beklenirken "düşünüyor" hareketi), "Nino" ve altında
  `ask.subtitle`; sağda hayalet `ask.newChat` düğmesi (artı simgesi): sohbet sıfırlanır, ekler ve yazı temizlenir,
  odak yazı kutusunda. (Mac'ten farkı: düğme her zaman görünür; Kapat düğmesi yok, pencerenin kendi kapatması var.)
- **Mesajlar** (kaydırılır; her değişimde tamamı yeniden çizilir ve en alta kayar):
  - İlk balon her zaman yerel selam (sunucuya gitmez; Mac ile aynı anlam: `ask.greeting`).
  - Sohbet boşken ve beklenmiyorken öneri hapları (36 px içeriden): `ask.suggestion.ps5TvPhone`, `ask.suggestion.ps5MonitorPc`,
    `ask.suggestion.xboxTv`, `ask.suggestion.installTvApp` — basınca o hapın **arayüz dilindeki** metni ekler olmadan gönderilir.
  - Nino satırı: altta 28 px robot (göz kırpmaz), yanında açık zeminli balon (köşeler 18, kuyruk tarafı alt-sol 6).
    Cevap biçimli (§8.4): paragraflar; numaralı adımlar 21 px vurgu renkli yuvarlak rozette beyaz kalın numara (iki
    basamakta hap), maddeler rozet genişliğinde sütunda 6 px vurgu noktası; asılı girinti; ardışık liste öğeleri arası 8,
    diğer bloklar arası 10; http(s) bağlantıları vurgu renkli, tıklanınca tarayıcıda açılır. Sağdan sola dilde sütunlar
    aynalanır. Cevapta bildirim kimliği varsa balonun altında yeşil hap `ask.reportSent`.
  - Kullanıcı balonu: sağda, vurgu zemin, beyaz yazı (köşeler 18, kuyruk alt-sağ 6), solda 48 boşluk; fotoğraflar 96 px
    (10 köşe) yazının üstünde.
  - Balonlar pencere genişliğinin ~%78'ini (− 40; en az 220) geçmez.
  - "Yazıyor": robot düşünür, üç 7 px nokta sırayla parlar (0,25→1 saydamlık, 420 ms, gidip gelen, 160 ms aralık);
    "Hareketi azalt" açıksa durağan. Ekran okuyucuya `ask.typing`.
  - Yerel uyarı balonları (Nino satırında; sunucuya gitmez):
    | Sonuç | Anlam | Düğme |
    |---|---|---|
    | yardımcı kapalı | `ask.alert.disabled` | birincil `settings.about.reportProblem` (`settings.about.reportProblem` penceresini açar) |
    | sınır | `ask.alert.dailyLimit` | — |
    | yoğun | `ask.alert.busy` | — |
    | reddedildi | `ask.alert.rejected` | — |
    | başarısız | `ask.alert.failed` | son uyarıysa ve beklenmiyorsa `common.retry` |
  - Son eklenen Nino cevabı ya da uyarısı ekran okuyucuya canlı bölge olarak okunur ("Nino: <metin>").
- **Yazma alanı** (üst çizgili): ekler satırı (56 px küçük resimler, ✕), hata yazısı, satır: ataç düğmesi (ipucu `ask.attachTooltip`; 3 doluyken kapalı),
  yazı kutusu (yer tutucu `ask.placeholder`, en çok 2000 karakter, en çok 132 px yükseklik, kayar; **Enter gönderir,
  Shift+Enter yeni satır**), 40×40 birincil gönder düğmesi (ok; Arapça arayüzde ayna). Altta ortada küçük not: `ask.disclaimer`
- Gönder etkin: beklenmiyor **ve** (yazı boş değil ya da en az bir ek var).
- **Gönder**: beklenirken bir şey yapılmaz; yazı (ya da hap metni) ve ekler alınır; elle gönderimde yazı ve ekler
  temizlenir; hata yazısı gizlenir; sohbete gönderilir.
- **İstek kurma** (arka planda): adres = havuz kökü + `/v1/assistant`; **dil = arayüz dili** (`settings.about.reportProblem`'den farklı:
  orada çeviri dili); kuruluş kimliği §6.2; cihaz özeti **her mesajda yeniden** alınır (TV sonradan bağlanmış olabilir).
- **Ekler**: dosya seçici, sürükle-bırak, Ctrl+V (`settings.about.reportProblem`'deki kurallar); fotoğraf başına en çok **600 KB**; açılamazsa
  `common.photo.openFailed`

### 7.4 Fotoğraf hazırlama (Windows, WPF)
- Açılabilen uzantılar: png, jpg, jpeg, heic, heif, webp, bmp, gif, tif, tiff (HEIC/WebP kodlayıcısı kuruluysa).
- Dosyadan: Windows Imaging Component ile ilk kare; EXIF yönü uygulanır (3 → 180°, 6 → 90°, 8 → 270°; okunamazsa düz);
  saydamlık beyaz zemine çizilir; 24 bit renge çevrilir; donmuş (iş parçacıkları arası).
- Panodan: önce panodaki PNG (saydamlığı doğru), olmazsa panonun görüntüsü (yalnız DIB varsa alfa çoğu zaman sıfırdır,
  yok sayılır). Pano erişim hataları sessiz.
- JPEG: §6.5 denemeleri; her denemede boyut sığdırılır (yüksek kaliteli ölçekleme), kodlanır.

### 7.5 Oyun tanıma karesi (küçük JPEG)
Kare (BGRA, 32 bit) boşsa ya da piksel dizisi kısa ise yok. Genişlik en çok verilen değere küçültülür (oran korunur;
büyütülmez), kalite 1–100 kırpılır, JPEG. Her kodlama hatası (geçersiz değer, desteklenmez, bellek…) → yok.

---

## 8. Nino'ya Sor: sunucu sözleşmesi ve sohbet

### 8.1 İstek (`POST /v1/assistant`)
```json
{
  "v": 1,
  "install": "<kuruluş kimliği>",
  "app": "<sürüm, en çok 40>",
  "platform": "windows",
  "language": "<arayüz dili kodu>",
  "messages": [
    { "role": "user", "text": "...", "images": [ { "mime": "image/jpeg", "data": "<base64>" } ] },
    { "role": "assistant", "text": "..." }
  ],
  "device": "<cihaz özeti; boşsa yok>"
}
```
- Başlık `Content-Type: application/json; charset=utf-8`; zaman aşımı 60 sn; boş alanlar yazılmaz; kaçırma yok.
- Fotoğrafsız mesajda `images` **hiç yazılmaz**; Nino mesajında asla yoktur.
- Kurma kuralları:
  1. Boş metinli mesajlar atılır (fotoğraflı kullanıcı mesajı hariç). Hiç kalmadıysa ya da son mesaj kullanıcınınki değilse
     **hata** (gönderilmez; sohbette "başarısız" uyarısına dönüşür).
  2. Son **24** mesaj; baştaki Nino mesajları atılır (ilk mesaj kullanıcınınki olur).
  3. Fotoğraf taşıyacaklar: fotoğraflı **en yeni 2** kullanıcı mesajı; her birinde en çok **3** fotoğraf (boş bayt atlanır).
  4. Daha eski fotoğraflı kullanıcı mesajında fotoğraf gitmez, metnin sonuna ` [screenshot]` eklenir (metin boşsa yalnız
     `[screenshot]`; sunucu boş mesajı atar).
  5. Her metin kırpılır, en çok **2000** karakter.
  6. Gövde **6 MB**'ı aşarsa fotoğraf taşıyanlardan en eskisi metne indirilir (`[screenshot]`), yeniden denenir; sığana ya da
     fotoğraflı kalmayana kadar.
- Örnekler: 20 soru-cevap + son soru → ≤ 24 mesaj, ilk "user", son "son soru", tam 23 mesaj (24'ün ilki Nino'ydu). 3000
  karakterlik metin → 2000. Mesajlar [ilk (2 foto), a, "" (1 foto), b, üçüncü (1 foto), c, dördüncü (5 foto)] → ilk
  `ilk [screenshot]` fotoğrafsız, üçüncü mesaj `[screenshot]` fotoğrafsız, beşinci 1 foto, yedinci 3 foto. Yalnız fotoğraflı
  son mesaj kabul (metin ""). 24 000 bayt sınırla iki 3'er fotoğraflı (4000 bayt) mesaj → eski mesaj fotoğrafsız
  `eski [screenshot]`, yeni 3 foto; 2000 bayt sınırla hepsi fotoğrafsız, `yeni [screenshot]`. 2 × 3 × 600 KB fotoğraf 6 MB'a sığar.

### 8.2 Cevap eşlemesi
Gövde nesneyse `error`, `reply`, `report` dizgileri okunur (bozuk JSON yok sayılır). Retry-After: süre ya da tarih − şimdi.
| Kod | Sonuç |
|---|---|
| 200, `reply` dolu | cevap (kırpılmış), `report` boş değilse bildirim kimliği |
| 200, `reply` yok/boş ya da JSON değil | başarısız |
| 503 + `error:"assistant_disabled"` | yardımcı kapalı |
| 429 + `error:"busy"` | yoğun (Retry-After) |
| 429 (diğer) | sınır (Retry-After) |
| 400, 413 | reddedildi (yeniden denemek işe yaramaz) |
| diğer (503 başka, 502 `model_failed`/`refused`, 500 HTML…) | başarısız (yeniden denenebilir) |
Ağ hatası, zaman aşımı, adres yok → başarısız (dışarıdan iptal edildiyse fırlatılır).
Örnek: `{"ok":true,"reply":"  Evet.  ","report":"r-42"}` → "Evet.", `r-42`; `report:null` → kimlik yok.

### 8.3 Sohbet durumu
- Uygulama oturumu boyunca **tek** sohbet; pencere kapatılıp yeniden açılınca korunur, uygulamadan çıkınca silinir (diske yazılmaz).
- Girdiler: kullanıcı (metin kırpılmış, en çok 3 JPEG), Nino (metin, bildirim kimliği), uyarı (sonuç). Uyarılar ve yerel
  selam sunucuya **gitmez**. "Tekrar dene" yalnız son girdi bir "başarısız" uyarısıysa.
- **Gönder**: beklenirken ya da yazı boş ve ek yoksa false. Kullanıcı girdisi eklenir, gönderim yürütülür, true.
- **Tekrar dene**: beklenirken, boşken ya da son girdi yeniden denenebilir değilse false; son uyarı kaldırılır, aynı sohbet
  aynen yeniden gönderilir.
- **Yürütme**: nesil numarası alınır, bekleniyor = evet, değişti; gönderilecek mesajlar (kullanıcı ve Nino) ile istenir;
  ağ/iptal/dosya/biçim hatası "başarısız" olur. **Yeni sohbet arada yapıldıysa sonuç yok sayılır.** Bekleniyor = hayır;
  cevapsa Nino girdisi, değilse uyarı eklenir; değişti.
- `ask.newChat`: nesil +1, girdiler silinir, bekleniyor = hayır, değişti.
- "Değişti" olayı herhangi bir iş parçacığından gelebilir; pencere arayüze aktarır.
- Testler (kendi örneklerimiz): "PS5 nerede takılı?" → cevap ("HDMI 2'de.", `r-1`); "Kablo uzun mu?" → başarısız uyarısı,
  yeniden denenebilir, ilk cevapta kimlik `r-1`; Tekrar dene → aynı mesajlar gönderilir (["PS5 nerede takılı?", "HDMI 2'de.",
  "Kablo uzun mu?"]), uyarı kalmaz, son cevap gelir.
  Yardımcı kapalı → uyarı, yeniden denenemez, Tekrar dene false, gönderilecek tek mesaj. Bekleyen gönderim varken ikinci
  gönderim false; Yeni sohbet sonra geç cevap → sohbet boş, beklenmiyor. Boş mesaj gönderilmez; 4 fotoğraf → 3.

### 8.4 Cevabın bloklara ayrılması (Mac/iPhone/Android ile aynı kurallar)
- Satır sonları `\r\n` ve `\r` → `\n`. Her satır kırpılarak değerlendirilir.
- Boş satır bloğu kapatır.
- `^\s*` + 1–2 rakam + `.` ya da `)` + en az bir boşluk + boş olmayan yazı → **numaralı adım** (numara, yazı).
  ("1999. sürüm" adım değil: dört basamak.) `12) Kabloyu çek.` → adım 12 "Kabloyu çek.".
- `^\s*` + `-`, `•` ya da `*` + en az bir boşluk + yazı → **madde**.
- Değilse: açık blok paragrafsa ya da satır (ham hâliyle) boşluk/sekmeyle başlıyorsa açık bloğa `\n` + satır eklenir
  (paragraf içi satır sonu korunur; adımın altındaki girintili satır adımın devamıdır); değilse yeni paragraf.
- `-yok\n1.yok` → tek paragraf (işaretten sonra boşluk yok). Yalnız boşluklu metin → blok yok.
- **Bağlantılar**: `http://` ya da `https://` + boşluk, `<>"')]` olmayan karakterler; sondaki `. , ; : ! ?` bağlantıya
  girmez; yalnız http/https mutlak adresler bağlantı olur (javascript:, file: olmaz). Parçalar: düz yazı / bağlantı.
- Örnek (kendi örneğimiz): "Böyle yap:\n\n1. TV'yi aç.\n2) https://nino.example/tv sayfasını aç.\n\nSonra haber ver.\nBekliyorum."
  → [paragraf "Böyle yap:"], [adım 1 "TV'yi aç."], [adım 2: bağlantı `https://nino.example/tv` + " sayfasını aç."],
  [paragraf "Sonra haber ver.\nBekliyorum."]. Ardışık adımlar paragraf içinde de ayrılır; "   Açılmazsa fişi çek."
  girintili satır adım 2'ye eklenir. Maddeli örnek: "Lazım olan:" paragraf, "Kumanda", "HDMI kablosu", "Ev ağı" maddeleri,
  "1999. sürüm de çalışır." paragraf.

---

## 9. Mac'ten farklar (Windows esas)

- Sağlık metinlerinde Mac yerine bilgisayar (`reading.target.computer` anlamı); USB-C adaptör önerisi yok.
- Nino'ya Sor: zaman aşımı 60 sn (Mac 90), User-Agent başlığı yok; fotoğraf hedefi 600 KB (Mac 900 KB); 413 "reddedildi"
  sayılır ve tek bir `ask.alert.rejected` uyarısı (Mac'te "çok büyük" ayrı); 6 MB aşımında en eski
  fotoğraflı mesajdan başlayarak teker teker metne indirilir; 503 başka hata "başarısız" (Mac'te "yoğun"); sınır ve
  günlük sınır uyarısında `settings.about.reportProblem` düğmesi yalnız "yardımcı kapalı" uyarısında; `settings.about.reportProblem` aynı pencerede değil ayrı pencerede
  açılır; ayrı pencere (Mac sayfa); `ask.newChat` her zaman görünür; gönderilemeyen kullanıcı balonu soluklaşmaz, uyarı
  Nino balonu olarak gelir.
- `settings.about.reportProblem`: dil alanı çeviri dili; fotoğraf denemeleri sabit boy/kalite listesi; Ctrl+V kuralı.
- Otomatik bildirim gövdesinin dili çeviri dili; Linux'ta sağlık klasörü olmadığından otomatik bildirim yok.

## 10. Windows'a özgü kısımlar

- Ağ türü: .NET ağ arabirimi listesi (izin gerekmez); ağ olayları: işletim sisteminin "ağ kullanılabilirliği" ve "ağ adresi
  değişti" bildirimleri.
- `device.label.device`: kayıt defteri `HKLM\HARDWARE\DESCRIPTION\System\BIOS` → `SystemManufacturer`, `SystemProductName`
  (güvenlik/yetki/dosya hatasında `Windows PC`); sistem adı Windows sürüm numarasından.
- Fotoğraflar ve küçük JPEG: WPF/Windows Imaging Component (BitmapDecoder, JPEG kodlayıcı), pano (PNG biçimi, DIB,
  dosya listesi), sürükle-bırak dosya biçimi, dosya seçici süzgeci `*.png;*.jpg;*.jpeg;*.heic;*.heif;*.webp;*.bmp;*.gif;*.tif;*.tiff`.
- Zip: `Downloads` klasörü, Gezgin'de `/select` ile gösterme.
- Bağlantılar varsayılan tarayıcıda açılır.
- Veri klasörü `%LOCALAPPDATA%\Nino`: `sorunlar.json`, `otomatik-bildirim.json`, `report-install.txt`, günlükler
  (`hata.log`, `remoteplay.log`, `altyazi.log`, `tvinstall.log`), `pool\endpoint.txt` (isteğe bağlı sunucu kökü).
