# Windows: yerel Remote Play köprüsü (`native/`, nino_native)

Bu belge bir **tariftir**: yeni `apps/windows/native/` altındaki ince C köprüsünün dışa açtığı arayüzü, içerde ne
yaptığını, nasıl derlendiğini ve testlerini anlatır. Kod yok. Köprüyü kullanan C# katmanı (PS5 bulma, eşleşme,
oturum, yeniden bağlanma) `kaynaklar.md` §1'de.

Köprü **resmî chiaki-ng v1.10.1**'e karşı yazılır (`~/Desktop/NinoCore/NinoRemotePlay/Vendor/chiaki-ng`, commit
`f30da0aaeb96fc0026cc03683153f682352e7d7c`; ayrıntı `~/Desktop/NinoCore/docs/tarif/remote-play.md`). Eski köprünün
kullandığı chiaki işlevleri, alanları ve günlük satırlarının hepsi v1.10.1'de birebir bulundu (§9). Eski derlemenin
uyguladığı **tek yama** v1.10.1'de yoktur; §8'de ayrıca işaretli.

## 0. Genel kurallar

- Tek paylaşımlı kütüphane: Windows'ta `nino_native.dll`, Linux'ta `nino_native.so`, Mac'te (yalnız test için)
  `.dylib`. Dosya adı uyumluluk için aynı kalır: C# tarafı kütüphaneyi bu adla yükler, CI ve kurulum paketi bu adı
  denetler.
- Düz C arayüzü, `cdecl` çağrı biçimi. C# tarafı chiaki yapılarına hiç dokunmaz; yalnız bu belgedeki işlevleri çağırır.
- Bütün dizgeler UTF-8, sıfırla biten. Bütün işlevler iş parçacığı güvenlidir.
- Dönüş değeri kuralı: 0 = başarı, diğerleri hata (istisnalar aşağıda).
- **İşlev adları serbesttir** (iki taraf da yeniden yazılıyor). Eski adların öneki eski projenin kısaltmasıdır; yeni
  kodda **kullanılmaz**. Öneri: `nino_rp_` öneki. Aşağıda her giriş noktası amacıyla anılır; parametre sırası, türleri,
  boyutları ve dönüş değerleri birebir korunmalıdır (C# P/Invoke bildirimleri bunlara göre yazılır).
- Dışa açılan simgeler yalnız bu işlevlerdir (görünürlük varsayılan gizli; Windows'ta dllexport, diğerlerinde
  "default" görünürlük).

## 1. Dışa açılan arayüz

### 1.1 Geri çağrı türleri

| Ad (anlamlı) | İmza (parametre sırası) | Ne zaman |
|---|---|---|
| Günlük | `(int level, const char *message, void *user)` | chiaki'nin günlük satırı. `level`: 0 hata, 1 uyarı, 2 bilgi |
| PS5 bulundu | `(const char *host, const char *name, int awake, void *user)` | Bulunan her PS5 yanıtında. `awake`: 1 açık, 0 dinlenme modunda |
| PS5 bulundu (geniş) | `(const char *host, const char *name, int awake, const char *running_app_titleid, const char *running_app_name, void *user)` | Aynısı, ek olarak o an açık uygulamanın başlık kimliği ve adı (bilinmiyorsa NULL) |
| Kare | `(const uint8_t *bgra, int width, int height, int stride, void *user)` | Çözülmüş kare. BGRA, satır başına `stride` bayt. **Bellek yalnız çağrı süresince geçerlidir** |
| Olay | `(int event, int quit_reason, const char *reason_text, void *user)` | Oturum olayı (§1.4) |

Geri çağrılar köprünün/chiaki'nin kendi iş parçacığında gelir; hızlı dönmeli, istisna sızdırmamalı.

### 1.2 Başlatma

- **Ağ yığınını hazırla** — parametresiz, `int` döner. Uygulama açılışında çağrılır; **birden çok kez çağrılabilir**,
  iş yalnız ilk çağrıda yapılır (Windows'ta tek seferlik başlatma yapısı, diğerlerinde pthread once) ve her çağrı ilk
  çağrının sonucunu döner. İlk çağrıda:
  1. FFmpeg günlüğü tamamen susturulur (masaüstü uygulamasında bu çıktıyı okuyan yok; bozuk karelerde çok satır üretir).
  2. chiaki'nin kütüphane başlatması çağrılır (Windows'ta WSAStartup ve FEC'in Galois tabloları); dönüşü sonuçtur
     (0 başarı).

### 1.3 PS5 arama ve uyandırma

- **Ara** — `(const char *const *targets, int target_count, int timeout_ms, <PS5 bulundu>, void *user)` → `int`.
- **Ara (geniş)** — aynı, geri çağrı geniş olanı → `int`.
  - `targets`, `target_count <= 0` ya da geri çağrı NULL ise hemen **1** döner (iş yapılmaz).
  - Bloklar: `timeout_ms` boyunca aramayı **500 ms'de bir** yineler; bir PS5 birkaç kez bildirilebilir.
  - Başarı 0; arama soketi açılamaz ya da iş parçacığı başlatılamazsa ya da adres dizisi ayrılamazsa **-1**.
  - Ayrıntı §2.
- **Uyandır** — `(const char *host, uint64_t credential)` → `int`. `host` NULL ise 1. `credential`, kayıt anahtarının
  onaltılık değeri (C# tarafı hesaplar, `kaynaklar.md` §1.1). chiaki'nin uyandırma işlevi PS5 kipiyle (ps5 = true),
  ayrı keşif nesnesi olmadan çağrılır; başarı 0, değilse chiaki hata kodu (sıfırdan farklı). Günlük satırları
  hedefsiz (düşürülür).

### 1.4 Kayıt (PS5'in "Cihazı Eşleştir" kodu)

Çıktı yapısı (C düzeni, sırayla, dolgu yok — toplam 0x40 bayt):

| Alan | Boyut | İçerik |
|---|---|---|
| PS5 adı | 0x20 bayt | sıfırla biten metin (en çok 31 karakter; son bayt her zaman 0 yapılır) |
| Kayıt anahtarı | 0x10 bayt | ASCII onaltılık rakamlar, sıfırla doldurulmuş |
| Oturum anahtarı ("morning") | 0x10 bayt | ham 16 bayt |

- **Kayıt ol** — `(const char *host, const uint8_t account_id[8], uint32_t pin, <çıktı yapısı> *out, uint32_t *reason,
  <Günlük> log, void *user)` → `int`.
- Dönüş: **0** başarı, **1** başarısız, **2** iptal, **<0** başlatılamadı (bellek/eşzamanlama nesnesi ya da chiaki
  kaydı başlatılamadı; bu durumda günlüğe "Regist start failed: <chiaki hata metni>" satırı hata düzeyinde yazılır).
- `reason` NULL değilse önce 0 yapılır. Başarısızlıkta (dönüş 1) PS5'in bildirdiği neden kodu yazılır (ör.
  `0x80108b02` = hesap tanınmadı); bilinmiyorsa 0 kalır.
- `host`, `account_id` ya da `out` NULL ise -1.
- Bloklar, **en çok ~30 sn** (§3).

### 1.5 Görüntü akışı

Olay kodları (sayılar uyumluluk için sabit; C# tarafı aynı sayıları kullanır):

| `event` | Anlam | `quit_reason` | `reason_text` |
|---|---|---|---|
| 0 | Bağlandı | 0 | NULL |
| 1 | Oturum kapandı | kapanma nedeni (alt tablo) | §4.3 |
| 2 | `settings.section.passcode` istiyor | **1** ise önceki şifre yanlıştı, ilk istekte 0 | NULL |

| `quit_reason` (olay 1) | Anlam | chiaki'nin kapanma nedenlerinden |
|---|---|---|
| 0 | Durduruldu | durduruldu |
| 1 | Remote Play başka cihazda kullanılıyor | oturum isteği: RP kullanımda |
| 2 | Bağlantı reddedildi / kayıt geçersiz | oturum isteği: bağlantı reddedildi; ctrl: bağlantı reddedildi; PSN kaydı başarısız |
| 3 | Bağlantı koptu (ağ) | akış: karşı taraf bağlantıyı kesti; akış: karşı taraf kapandı; ctrl: bağlanamadı; akış: bilinmeyen |
| 4 | Diğer (`reason_text` açıklar) | geri kalan her şey (bilinmeyen oturum isteği hatası, RP çöktü, sürüm uyuşmazlığı, ctrl bilinmeyen, yok…) |

- **Oturumu başlat** — `(const char *host, const uint8_t regist_key[0x10], const uint8_t morning[0x10],
  const uint8_t account_id[8], int max_fps, <Kare>, <Olay>, <Günlük>, void *user)` → oturum tutamacı ya da **NULL**.
  - `host`, `regist_key`, `morning` ya da `account_id` NULL ise NULL.
  - Kare, olay, günlük geri çağrıları NULL olabilir (o tür bildirim yapılmaz).
  - Sesi ve kumanda girdisini açmadan 1080p, 30 kare/sn H.264 akış ister (§4). Her kare çözülür; en çok `max_fps` kez BGRA'ya
    çevrilip kare geri çağrısına verilir (`max_fps <= 0` ise sınır yok).
  - Hata olursa NULL; nedeni günlüğe hata düzeyinde yazılır (çözücü açılamadı; oturum kurulamadı + neden;
    oturum başlatılamadı + neden). C# tarafı başlatma hatası olarak **son hata satırını** gösterir.
- **Giriş şifresini gönder** — `(oturum, const uint8_t *pin, size_t pin_size)` → `int`. PIN ASCII rakamlardır.
  Oturum ya da PIN NULL ya da boyut 0 ise chiaki'nin "geçersiz veri" hata kodu döner; değilse chiaki'nin şifre gönderme
  işlevinin sonucu (0 başarı). **Olay geri çağrısının içinden çağrılmamalı** (chiaki olayı kilit tutarken verir).
- **Oturumu durdur** — `(oturum)` → yok. NULL ise bir şey yapmaz. chiaki oturumuna dur der, iş parçacıklarını bekler
  (join), oturumu ve çözücüyü bırakır, belleği serbest bırakır. Döndükten sonra **hiçbir geri çağrı gelmez**. Aynı
  oturum için yalnız bir kez çağrılmalı; geri çağrı içinden çağrılmamalı.

## 2. Arama ayrıntısı

1. Günlük nesnesi yalnız hata düzeyinde ve hedefsiz kurulur (satırlar düşürülür; chiaki'nin varsayılanı stdout'a
   yazardı).
2. Keşif nesnesi IPv4 için kurulur.
3. **Windows'a özgü:** keşif soketinde `SIO_UDP_CONNRESET` kapatılır (değer `_WSAIOW(IOC_VENDOR, 12)`; başlıkta yoksa
   tanımlanır). Neden: ulaşılamayan bir adrese giden paketin ICMP yanıtı `recvfrom`'u `WSAECONNRESET` ile bozar ve
   chiaki'nin arama döngüsü sona erer; bütün alt ağa paket gönderildiği için bu bildirim mutlaka susturulmalıdır. Bunun için keşif yapısının soket
   alanına erişilir (v1.10.1'de `socket` alanı var).
4. Keşif iş parçacığı başlatılır; bildirilen her yanıt için: adres yoksa ya da yanıt **PS5 değilse** (chiaki'nin "PS5
   mi" sınayıcısı) yok sayılır. Ad yoksa `"PS5"`. Uyanık sayılması chiaki'nin "hazır" durumudur (READY), başka her
   durum dinlenme. Geniş geri çağrıda çalışan uygulamanın kimliği ve adı chiaki'nin verdiği gibi (NULL olabilir).
5. Hedef dizisi: her NULL olmayan hedef, PS5 keşif portuyla (chiaki'nin PS5 keşif portu sabiti, 9302) IPv4 adresine
   çevrilir; çevrilemeyen ("not-an-address" gibi) atlanır.
6. Paket: komut "SRCH", protokol sürümü chiaki'nin PS5 sabiti (`"00030010"`).
7. Döngü: bitiş = şimdi + `timeout_ms` (negatifse 0). En az bir kez: her geçerli adrese paket gönderilir, 500 ms
   uyunur; bitişe kadar tekrarlanır. (Yani 600 ms'lik arama iki tur, ~1 sn sürer.)
8. İş parçacığı durdurulur, keşif bırakılır.

## 3. Kayıt ayrıntısı

1. Bağlam ayrılır (karşılıklı dışlama + koşul değişkeni, "bitti" bayrağı, olay türü, kayıtlı PS5 bilgisi, neden kodu,
   günlük hedefi).
2. Günlük maskesi: hata | uyarı | bilgi. Her satır önce **neden okuyucusuna** verilir (§9.1): satırda
   `"Reported Application Reason: 0x"` varsa ardındaki onaltılık sayı neden olarak saklanır (kilit altında). PS5'in ret
   kodu kayıt olayında taşınmaz, yalnız bu günlük satırında görünür; satır olaydan önce aynı iş parçacığında gelir. Sonra satır, düzeyiyle,
   çağıranın günlük geri çağrısına iletilir.
3. Kayıt bilgisi: hedef PS5 (chiaki'nin `PS5_1` hedefi), adres, genel yayın **kapalı**, PSN çevrimiçi kimliği **yok**
   (yalnız 8 baytlık hesap kimliği kopyalanır), PIN, konsol PIN'i 0, delik açma bilgisi ve RUDP yok.
4. Kayıt başlatılır; başlamazsa dönüş -1 (§1.4).
5. Olay geri çağrısı yalnız ilk olayı kaydeder: türü (olay NULL ise "başarısız"), başarılıysa ve kayıtlı PS5 bilgisi
   varsa onun kopyası; "bitti" işaretlenir, koşul uyarılır.
6. **30 000 ms** "bitti" beklenir. Süre dolarsa kilit bırakılır, chiaki kaydına dur denir, yeniden kilitlenip (süresiz)
   "bitti" beklenir (durdurma "iptal" olayını üretir).
7. chiaki kaydı bırakılır (kayıt iş parçacığı olayı bildirdikten sonra biter; bırakma onu bekler).
8. Sonuç:
   - Başarı ve PS5 bilgisi var: çıktı yapısı sıfırlanır; ad (`server_nickname`, 0x20 bayt, son bayt 0'a zorlanır),
     kayıt anahtarı (`rp_regist_key`, 0x10), oturum anahtarı (`rp_key`, 0x10) kopyalanır → **0**.
   - İptal → **2** (pratikte yalnız 6. adımdaki 30 sn dolunca olur; PS5 yanıt vermemiştir).
   - Diğer → `reason`'a saklanan neden yazılır → **1**.

## 4. Oturum ayrıntısı

### 4.1 Kurulum
1. Oturum nesnesi ayrılır; geri çağrılar ve `user` saklanır. Günlük maskesi hata | uyarı | **bilgi** (bilgi satırları
   gerekli: görüntü duraklaması satırları bilgi düzeyindedir, §9.3).
2. Kare sınırlayıcı `max_fps` ile kurulur (§5).
3. H.264 çözücü açılır (§6); açılamazsa NULL.
4. chiaki bağlantı bilgisi:
   - PS5: evet; adres (chiaki oturum açılırken kopyalar); kayıt anahtarı ve oturum anahtarı 16'şar bayt.
   - Görüntü profili: chiaki'nin hazır ayarı **1080p, 30 kare/sn**, kodek **H.264**; profil kendiliğinden düşürme
     **açık** (PS5 desteklemiyorsa).
   - Klavye kapalı, DualSense kapalı, **ses kapalı** (chiaki'nin "ses kapalı" seçeneği; görüntü açık), otomatik kayıt
     kapalı, delik açma oturumu ve RUDP soketi yok.
   - Hesap kimliği 8 bayt.
   - Paket kaybı üst sınırı **0.05**.
   - FEC onarımı tutmazsa anahtar kare (IDR) iste: **açık**.
5. chiaki oturumu kurulur; olmazsa çözücü bırakılır, NULL.
6. Olay geri çağrısı ve **görüntü örneği geri çağrısı** bağlanır.
7. **Görüntü engeli bildirimi** ("display sink") **mutlaka** atanır: PS5 korumalı içerik yüzünden görüntünün
   gösterilemeyeceğini ya da yeniden gösterilebileceğini bildirdiğinde chiaki'nin ctrl iş parçacığı bu geri çağrıyı **koşulsuz** çağırır
   (v1.10.1 ctrl.c'de denetim yok: ekran-a/ekran-b iletileri ve ctrl yanıtındaki "rp_prohibit"). Atanmazsa NULL işlev
   çağrılır, uygulama çöker. Yapılacak bir şey yok: yalnız görüntünün korumalı içerik yüzünden
   gösterilemediğini ya da yeniden gösterilebildiğini söyleyen bir bilgi satırı yazılır; akış sürer. (Bu resmî v1.10.1 API'sidir, yama değil.)
8. chiaki oturumu başlatılır; olmazsa (başlamadığı için beklenecek iş parçacığı yoktur) oturum ve çözücü bırakılır,
   NULL.

### 4.2 Görüntü örneği (akış iş parçacığında)
chiaki'nin imzası: `(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)` → `bool`.
Kayıp/kurtarılmış bilgisi kullanılmaz.
1. Çözücü hazır değilse `true`.
2. Örnek çözülür (**her örnek çözülmelidir**; sonraki kareler öncekilere dayanır).
3. Çözücü hatası → **`false`** döner: chiaki bunu bozuk kare sayar ve yeni anahtar kare ister.
4. Kare yoksa ya da kare geri çağrısı yoksa `true`.
5. Sınırlayıcı (monoton µs saat) geçirmezse `true` (kare çözüldü ama BGRA'ya çevrilmez).
6. Kare BGRA'ya çevrilir; başarılıysa kare geri çağrısı çağrılır (BGRA tampon, genişlik, yükseklik, stride). Kare
   bırakılır. `true`.

### 4.3 Olaylar (oturum iş parçacığında)
- Olay geri çağrısı yoksa ya da olay NULL ise bir şey yapılmaz.
- Bağlandı → olay 0.
- Giriş şifresi isteği → olay 2, `quit_reason` = chiaki'nin "şifre yanlış" bayrağı (1/0).
- Kapandı → olay 1, `quit_reason` = §1.5 eşlemesi. `reason_text`: neden **4 (diğer)** ise chiaki'nin **neden adı
  metni** (ör. `"Unknown Session Request Error"`, `"Version Mismatch"`); değilse karşı tarafın gönderdiği ek neden
  metni (çoğunlukla NULL).
- Diğer olaylar yok sayılır.

## 5. Kare sınırlayıcı

- Kurulum: `max_fps > 0` ise en kısa aralık = 1 000 000 / max_fps µs (tamsayı bölme), değilse 0. "Son an yok".
- Sor (şimdi µs): son an varsa ve `şimdi − son < en kısa aralık` ise geçirmez; değilse son = şimdi, geçirir.
- Test: 4 kare/sn sınırla, 30 kare/sn gelen 30 kare (saat her karede 1 000 000/30 µs ilerler, 0'dan başlar) → **4 ya
  da 5** kare geçer. Sınır 0 iken aynı anda (5 µs) iki soru → ikisi de geçer.
- C# tarafı oturumu **en çok 20 kare/sn** ile açar (`kaynaklar.md` §1.5; eski kodda bir yorum 15 der, geçerli değer
  20'dir).

## 6. H.264 çözücü (FFmpeg)

- Açılış: FFmpeg'in H.264 çözücüsü bulunur (yoksa hata); bağlam, paket ve kare ayrılır. **Düşük gecikme** bayrağı açık;
  iş parçacığı türü yalnız **dilim** (kare iş parçacıkları gecikme ekler, dilim eklemez), iş parçacığı sayısı 0
  (kendiliğinden). Kaynak biçimi "bilinmiyor" (-1).
- **Çöz(veri, boyut)**: veri NULL ya da boyut 0 → 0 (kare yok). Paket gönderilir; çözücü "dolu" (EAGAIN) derse bekleyen
  kareler alınıp atılır ve paket bir kez daha gönderilir. Gönderim hatası → **-1**. Sonra çıkan bütün kareler alınır;
  birden çok çıkarsa **yalnız sonuncusu** tutulur → 1; hiç çıkmazsa 0. (Girdi Annex-B'dir, chiaki böyle verir;
  FFmpeg okuma için girdi sonunda FFmpeg'in dolgu payı kadar bayt bulunmalıdır — chiaki'nin tamponu ve testler
  bunu sağlar.)
- **BGRA'ya çevir(kare)**:
  1. Genişlik ya da yükseklik ≤ 0 → başarısız.
  2. Boy değiştiyse ya da tampon yoksa: stride = genişlik×4, **64'e yuvarlanmış**; tampon stride×yükseklik ayrılır.
  3. Ölçekleyici aynı boyda, hedef BGRA, en yakın komşu (point) yöntemiyle önbellekten alınır.
  4. Kaynak biçimi, renk alanı ya da renk aralığı değiştiyse renk ayrıntıları yeniden kurulur: kaynak katsayıları
     renk alanı BT.470BG ya da SMPTE170M ise **BT.601**, **değilse BT.709** (PS5 görüntüsü 709 kullanır; akış renk alanını
     söylemediğinde HD görüntü için 709 seçilir, oysa FFmpeg kendi başına 601 alırdı). Kaynak tam aralık: renk aralığı JPEG ya da biçim YUVJ420P
     ise. Hedef: BT.709, tam aralık. Parlaklık 0, karşıtlık ve doygunluk 1<<16.
  5. Ölçekle; dönen satır sayısı yüksekliğe eşitse başarılı. Alfa baytı 255 olur.
- Kapanış: bağlam, paket, kare, ölçekleyici, tampon bırakılır.

## 7. Derleme

- CMake (3.20+), C. chiaki-ng kaynak klasörü bir değişkenle verilir (yeni yerleşimde vendor klasörü ya da alt modül
  **v1.10.1**); FFmpeg kurulumu bir önekle (`include/`, `lib/`). Testler bir seçenekle (varsayılan açık).
- Windows dışında konumdan bağımsız kod açık (statik libchiaki paylaşımlı kütüphanenin içine bağlanır; Linux'ta
  bağlayıcı aksi halde "-fPIC ile derle" der).
- Windows'ta: yalnız statik kütüphaneler aranır (`.a`), OpenSSL statik; miniupnpc statik bildirimi tanımlanır
  (başlıklar aksi halde dllimport bildirir).
- chiaki seçenekleri (hepsi KAPALI): arayüz, komut satırı, testler, FFmpeg çözücüsü (köprü kendi FFmpeg'ini kullanır),
  Raspberry Pi çözücü, Opus, Speex, Setsu, Steam Deck, Steam kısayolu, Borealis, paylaşımlı kütüphane; curl için
  nghttp2, libidn2, zstd, brotli, libpsl, libssh2, librtmp, zlib, LDAP kapalı. **Yeni:** v1.10.1'de "internet
  üzerinden Remote Play" (RUDP) seçeneği AUTO'dur; Mac derlemesi gibi KAPALI yapılmalı (yerel ağ dışı bağlantı
  kullanılmıyor). Bu ayarla MSYS2/MinGW derlemesi **henüz denenmedi**.
- chiaki alt klasör olarak eklenir (tümüyle derlenmez, yalnız kütüphane hedefi).
- FFmpeg: avcodec, swscale, avutil (önce önekte, yoksa sistemde aranır).
- Bağımlılıklar: chiaki kütüphanesi + üç FFmpeg kütüphanesi. Windows'ta ek sistem kütüphaneleri: ws2_32, wsock32,
  iphlpapi, bcrypt, crypt32, secur32, advapi32, user32, shell32, ole32, gdi32, normaliz; bağlama `-static
  -static-libgcc`. Mac'te z, CoreFoundation, Security, SystemConfiguration, CoreServices çerçeveleri.
- DLL: önek yok (`nino_native.dll`), görünürlük gizli; Windows'ta tanımsız simgeye izin yok ve semboller atılır
  (`-s`; DLL ~10 MB'tan küçülür).
- Test yürütücüsü kaynak dosyayı doğrudan içerir (iç işlevlere erişmek için).

### 7.1 CI (Windows, MSYS2 mingw64)
- Satır sonları olduğu gibi (autocrlf kapalı, eol lf).
- chiaki ve gereken alt modülleri: nanopb, jerasure, gf-complete, curl (sığ).
- MSYS2 paketleri: cc, cmake, ninja, pkgconf, nasm, python, python-protobuf, protobuf, openssl, json-c, libevent,
  miniupnpc; ayrıca make, diffutils, tar, xz.
- **FFmpeg 7.1.2** kaynaktan, en küçük yapılandırma (LGPL): statik, paylaşımsız, hata ayıklamasız; her şey kapalı,
  otomatik algılama kapalı, **w32threads** açık; programlar, belgeler, ağ, avdevice, avformat, avfilter, swresample
  kapalı; avcodec, avutil, swscale açık; yalnız **h264 çözücü** ve **h264 ayrıştırıcı**. İndirme önce ffmpeg.org'dan
  (`ffmpeg-7.1.2.tar.xz`, 5 yeniden deneme, 5 sn arayla), olmazsa GitHub'daki `n7.1.2` etiketinin arşivi. Derlenen önek
  önbelleğe alınır (anahtar sürüm + "mingw64-h264-swscale-v1"); sonraki adımlar başarısız olsa da önbelleğe yazılır.
- Statik bağımlılıkların varlığı denetlenir: libcrypto.a, libjson-c.a, libevent.a, libminiupnpc.a ve FFmpeg `.a`'ları.
- Yapılandır (Ninja, Release, FFmpeg öneki) → derle → yerel testleri koş (girdi: §10'daki örnek dosya).
- **DLL bağımlılık denetimi:** DLL'in içe aktarma tablosundaki her DLL şu listede olmalı (küçük harf): kernel32,
  user32, advapi32, shell32, ole32, oleaut32, gdi32, ws2_32, wsock32, iphlpapi, bcrypt, bcryptprimitives, crypt32,
  secur32, normaliz, msvcrt, ntdll, `api-ms-win-*`, ucrtbase. Başka varsa derleme durur ("izin verilmeyen bağımlılık").
- **Dışa aktarım denetimi:** başlatma, arama, geniş arama, uyandırma, kayıt, oturum başlat, oturum durdur işlevleri
  DLL'in dışa aktarımında olmalı (yeni adlarla güncellenir).
- DLL yapı çıktısı olarak yüklenir; .NET işi onu `native/bin/` altına koyar. RemotePlay projesi `native/bin/
  nino_native.dll` (ve Linux'ta `.so`) **varsa** çıktıya ve yayın klasörüne kopyalar; yoksa DLL'siz derlenir (Mac'te
  testler yerel testleri atlar). Yayın işi `nino_native.dll`'in yayın klasöründe olduğunu denetler.

## 8. Eski derlemenin chiaki'ye uyguladıkları (v1.10.1'de YOK) — işaretli

1. **Takion gönderim tamponu, kapandıktan sonra gönderme yaması** (eski CI chiaki'ye uyguluyordu). Sorun: Takion'un
   iş parçacığı, akış bağlantısı "bağlantıyı kes" iletisini göndermeden önce bitebiliyor; bırakılmış gönderim tamponuna
   paket itiliyor. Yama tampona bir "canlı" bayrağı ekliyordu: başlatma başarıyla bitince açık, bırakmanın ilk adımında
   kapalı; bırakmada paket dizisi NULL'a ve sayaçlar 0'a çekiliyor; "paket it" çağrısı tampon canlı değilse paketi
   serbest bırakıp "iptal" hatasıyla dönüyordu. **v1.10.1'de bu koruma yok** (yalnız "dur" bayrağı var). Köprünün
   arayüzü bu yamaya dayanmaz, ama **durdurma yolu** dayanıyor olabilir. **Açık risk:** §10'daki "kapalı porta oturum"
   ve "başlatır başlatmaz durdur" testleri ve C# tarafındaki "yeniden bağlanırken durdur" testi (`kaynaklar.md` §1.9)
   v1.10.1'le koşulmalı; çökme ya da bozulma görülürse ya resmî sürümün bir düzeltmesi beklenir ya da durdurma sırası
   köprüde güvenli hale getirilir (eski yamayı almadan). Karar ana oturumun.
2. **nanopb sembol öneki başlığı**: yalnız Mac/iOS derlemesi içindi (Firebase'in getirdiği nanopb 0.3 ile çakışma).
   Windows köprüsünde **kullanılmıyordu**; gerekmez.
3. Eski alt modül farklı bir depo adresine ve v1.10.1 olmayan bir commit'e (`0c4a45df…`) bağlıydı; v1.10.1'e karşı
   doğrulanamadı. v1.10.1 başlıklarında tek tek bulunanlar: kütüphane başlatma; keşif başlatma/iş parçacığı/gönderme/
   bırakma, "PS5 mi" sınayıcısı, PS5 keşif portu (9302), protokol sürümü ("00030010"), SRCH komutu, keşif yapısının
   soket alanı, yanıttaki ad/durum/çalışan uygulama alanları, uyandırma (ps5 bayraklı); kayıt bilgisi alanları (hedef,
   adres, genel yayın, çevrimiçi kimlik, hesap kimliği, PIN, konsol PIN'i, delik açma), kayıt başlat/durdur/bırak, olay
   türleri, kayıtlı PS5 alanları (`server_nickname` 0x20, `rp_regist_key` 0x10, `rp_key` 0x10); oturum kur/başlat/dur/
   bekle/bırak, olay ve görüntü örneği geri çağrısı atama, görüntü engeli bildirimi atama, giriş şifresi gönderme,
   1080p ve 30 kare/sn hazır ayarları, H.264 kodeği, bağlantı bilgisi alanları (§4.1), kapanma nedenleri ve neden adı
   metni, şifre isteği olayı ("şifre yanlış" bayrağı); "geçersiz veri" ve "zaman aşımı" hata kodları; koşullu bekleme
   (yüklemli, zaman aşımlı); monoton µs/ms saat. Davranış farkı yine de olabilir (canlı deneme gerekli).

## 9. chiaki'nin İngilizce günlük satırlarına dayanan kurallar

Uygulamanın birçok kararı chiaki'nin günlük metinlerine dayanır. v1.10.1'de hepsi aynı metinle bulundu. chiaki
güncellenirse bu bölüm yeniden denetlenmelidir.

### 9.1 Neden kodu satırı
- Kayıt (`regist.c`) ve oturum isteği (`session.c`) aynı biçimi hata düzeyinde yazar:
  `"Reported Application Reason: %#x (<açıklama>)"` → ör. `Reported Application Reason: 0x80108b02 (Invalid PSN ID)`.
- Köprünün okuyucusu: satırda `"Reported Application Reason: 0x"` aranır; ardındaki onaltılık rakamlar okunur; hiç
  rakam yoksa okunmadı. Testler: `"Reported Application Reason: 0x80108b02 (Invalid PSN ID)"` → 0x80108b02;
  `"Regist waiting for response"` → yok; NULL → yok.

### 9.2 Kayıt hata satırları (C# sınıflaması, `kaynaklar.md` §1.3)
`getaddrinfo`; `search response`; `connect for search`; `send search`; `Regist search failed`; `connect for request`;
`Regist connect failed`; `response HTTP header`; `receiving response content`; `receive response content`. Örnek tam
satırlar: "Regist timed out waiting for search response", "Regist failed to send search: <hata>", "Regist eventually
failed to connect for search", "Regist eventually failed to connect for request", "Regist connect failed: 10060",
"Regist failed to getaddrinfo on <adres>", "Regist failed to receive response HTTP header", "Regist timed out receiving
response content", "Regist received HTTP code 403", "Regist eventually failed", "Regist response is missing RegistKey
(or it was invalid)".

### 9.3 Oturum satırları
- Oturum isteği düşünce kapanma metni `"Unknown Session Request Error"` (chiaki'nin neden adı); gerçek neden, aynı iş parçacığının biraz önce yazdığı satırlardadır: `"Session request connect failed eventually."`, `"Failed to send session
  request"`, `"Failed to receive session request response"` ya da §9.1 satırı.
- Görüntü duraklaması (bilgi/uyarı düzeyi): `"FEC failed, waiting for IDR frame"` (ayrıca hata düzeyinde `"FEC
  failed"`), `"Video FEC failure, already waiting for requested IDR"` (istenen IDR de bozuk geldi; chiaki bir daha
  istemez), `"Received IDR frame, resuming decode"`.
- Sağlık sayaçları: `"Takion Send Buffer re-sending packet …"` (içinde "Send Buffer re-sending packet"), `"Takion Send
  Buffer overflow"` ("Send Buffer overflow"), `"… corrupt frame …"`.

## 10. Testler (yerel)

Test yürütücüsü tek argüman alır: örnek H.264 dosyası; yoksa kullanım satırı yazıp 2 ile çıkar. Başarısızlıkları
sayar; varsa sayıyı yazıp 1, yoksa "all native tests passed" yazıp 0.

**Örnek dosya** (eski ağaçta durur, bağlantı verilemez; yeniden üretilir): FFmpeg'in `testsrc2` deseni, **1920×1080**,
**6 kare**, H.264 Annex-B ham akış. Eski dosyanın özellikleri (ffprobe ile okundu): High profil, düzey 4.0, yuv420p,
renk alanı/aralığı belirtilmemiş, kareler I + 5×P, her kare tek dilim, SPS'teki yeniden sıralama derinliği
(`has_b_frames`) **2** (PS5'te 0), ~164 KB. Aynı özellikleri veren komut (bu Mac'te denendi):
`ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 6 -c:v libx264 -pix_fmt yuv420p -f h264 sample-1080p.h264`.
Koşullar: tam 6 erişim birimi çıkmalı (kare başına tek dilim; dilim iş parçacıkları kapalı), ilk birim SPS/PPS + IDR
olmalı, yeniden sıralama derinliği ≤ 2 olmalı (yoksa "boşaltmadan önce en az 4 kare" denetimi tutmaz). Dosya yeni ağaçta
test verisi olarak üretilip saklanabilir (karar ana oturumun).

Testin yardımcısı Annex-B'yi PS5'in gönderdiği gibi **erişim birimlerine** (kare) böler: başlangıç kodlarını
(00 00 01) bulur, bir NAL'ın sonunu bir sonrakinin başlangıç kodundan önceye çeker (önceki bayt 0 ise o da atılır);
NAL türü (ilk bayt & 0x1f) 7 (SPS), 9 (AUD) ya da dilim (1 veya 5) ise ve mevcut birimde dilim varsa yeni birim
başlar; her NAL'ın önüne 00 00 00 01 konur.

| Test | Beklenen |
|---|---|
| Başlatma iki kez | ikisi de 0 |
| Neden satırı okuma | §9.1 örnekleri |
| Kare sınırlayıcı | §5 örnekleri |
| Kapanma nedeni eşlemesi | durduruldu→0; RP kullanımda→1; oturum isteği reddedildi, ctrl reddedildi, PSN kaydı başarısız→2; karşı taraf kesti, karşı taraf kapandı, ctrl bağlanamadı, akış bilinmeyen→3; sürüm uyuşmazlığı→4 |
| Örnek çözülür | 6 erişim birimi çıkar; her birim çözülür, hata yok; çıkan her kare BGRA'ya çevrilir: 1920×1080, stride ≥ 1920×4, 540. satırda renkler tek düze değil, alfa 255; döngüde en az 4 kare çıkar (yeniden sıralama gecikmesi), çözücü boşaltılınca (NULL paket) toplam **6** |
| Yeni çözücü yalnız ilk birimle | çöz ≥ 0; boşaltınca tam **1** kare (1080p) |
| Çöp girdi çökmez | `00 00 00 01 65 ff 00 12` (8 bayt + dolgu) → çöz ≤ 0; NULL/0 → 0 |
| Arama süre dolunca döner | hedefler "127.0.0.1" ve "not-an-address", 600 ms → dönüş 0, süre 500 ms ≤ t < 3000 ms, bulunan 0; hedefsiz (NULL, 0) → sıfırdan farklı |
| Geniş arama | "127.0.0.1", 600 ms → 0, bulunan 0; geri çağrı NULL → sıfırdan farklı |
| Kapalı porta oturum kapanmayı bildirir | 127.0.0.1, kayıt anahtarı 16×0x31, oturum anahtarı 16×0x01, hesap 8×0x01, 15 kare/sn: tutamaç NULL değil; 15 sn içinde "kapandı" olayı gelir, nedeni "durduruldu" değil; durdurma **< 2000 ms** sürer |
| Başlatır başlatmaz durdur | sıfır anahtarlarla, geri çağrısız: tutamaç NULL değil, durdurma çökmez |
