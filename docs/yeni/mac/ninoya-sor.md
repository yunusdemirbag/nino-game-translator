# Mac: Nino'ya Sor (kurulum yardımcısı) ve oyun tanıma

Bu belge yeni Mac uygulaması için bir **tarif**tir: neyin nasıl göründüğünü ve nasıl davrandığını anlatır. Kod
içermez. Metinler yeni uygulamanın anahtarlarıyla verilir: anahtarlar noktalı adlardır (ör. `settings.done`) ve
alanlarına göre ayrı xcstrings dosyalarında durur (Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport);
anahtarın yanında ya yeni EN / TR metni ya da, eskiyle örtüşebilecek yerlerde, metnin ne dediğine dair kısa açıklama durur.

Kapsam: Nino'ya Sor robotu, sohbet sayfası, sunucu sözleşmesi, oyunu soran kart (`sheets.game.title`) ve oyunun hangi
yollardan tanındığı. Sorun Bildir formunun ayrıntısı (alanlar, günlük ekleme, gizli bilgi silme) ayrı belgede
anlatılır; burada yalnız sohbetle bağlantısı var.

---

## 1. Robot

### Görseller
- İki kare: gözler açık ve gözler kapalı (göz kırpma). Kaynak: `design/bot-png/nino-bot-256.png` ve
  `design/bot-png/nino-bot-blink-256.png` (128 ve 512 boyları da var). Uygulama paketine doğrudan kopyalanır.
- Robot: beyaz gövdeli, büyük mavi parlak gözlü, başında kırmızı Türk bayraklı şapka, kulağında "文A" çeviri rozeti,
  çevresinde mavi yörünge halkası olan sevimli bir robot.
- Görsel bulunamazsa yerine sistemin gülen yüz simgesi (vurgu renginde) çizilir.

### Hareketler (üçü ayrı ayrı açılıp kapanır)
- **Göz kırpma:** her 4 ile 5 saniye arasında rastgele bir anda, yaklaşık 150 ms gözler kapalı kareye geçer, sonra açılır.
- **Süzülme:** robot yukarı aşağı hafifçe süzülür; genlik robot boyunun %5'i, bir yön 1,6 sn, yumuşak, sonsuz, gidip gelen.
- **Düşünme:** cevap beklenirken baş sağa sola ±6 derece sallanır (0,5 sn, gidip gelen). Bitince 0,2 sn'de düz durur.
- Sistemde **"Hareketi azalt"** açıksa hiçbiri olmaz: robot hareketsiz durur.
- Robot ekran okuyucudan gizlidir (süs); erişilebilirlik adı onu taşıyan düğmededir.

### "Yazıyor" noktaları
- Yan yana üç küçük daire (çap 7, aralık çapın 0,6'sı). Her biri 1,2 sn'lik dalgayla sırayla büyüyüp küçülür ve
  solup koyulaşır (saydamlık %35 ile %100, boy %75 ile %110 arası; her nokta bir öncekinden biraz geride).
- "Hareketi azalt" açıksa noktalar orta değerde sabit durur.

---

## 2. Yüzen robot düğmesi

- Kurulum ve ana ekran açılış logosu kalktıktan sonra pencerenin köşesinde yuvarlak bir düğme belirir (büyüyerek ve
  belirerek gelir).
  - **Ana ekranda sol altta** (soldan geniş kenar boşluğu, alttan 60 pt). Sağ altta fiş ve kablo durduğu için sola alındı.
  - **Kurulum sihirbazında sağ altta**, `setup.continue` (Continue / Devam) düğmesinin üstünde (alttan 96 pt).
- Görünüş: 60 pt çaplı daire, içinde 44 pt robot (süzülür, göz kırpar). Zemin %92 opak beyaz, üstünde cam efekti ve
  ince cam kenar çizgisi; altında vurgu renginde yumuşak gölge.
- Fare üstüne gelince düğme %5 büyür, gölge koyulaşır ve genişler (yaylı animasyon).
- İpucu ve erişilebilirlik adı: `home.askNino` (Ask Nino / Nino'ya Sor).
- Tıklanınca sohbet sayfası açılır.

### "Çeviri başladı" balonu
- Çeviri başladığında (kurulum bitmişse) robotun sağında 7 saniyeliğine bir hap balon çıkar:
  `home.startedBubble` (Nino ağzından çevirinin devreye girdiğini bildirip keyifli oyun dileyen kısa balon)
- Kalın 17 pt beyaz yazı, %55 siyah hap zemin, ince beyaz kenar. Soldan kayarak ve belirerek gelir (yaylı), 0,4 sn'de
  solarak gider. Çeviri durursa hemen kaybolur. Yeniden başlatılınca sayaç baştan başlar.

### Başka girişler
- Ayarlar listesinde `settings.section.askNino` (Ask Nino / Nino'ya Sor) satırı (mavi zemin üstünde konuşma balonları
  simgesi; `settings.section.updates` (Updates / Güncellemeler) ile `settings.section.report` (Report a problem / Sorun
  Bildir) arasında). Tıklanınca Ayarlar kapanır, ~0,35 sn sonra sohbet sayfası açılır (ayarların içinde açılmaz).

---

## 3. Sohbet sayfası

Ana pencerenin üstünde açılan sabit boyutlu sayfa: **540 × 660 pt**. Yukarıdan aşağı: başlık, ince çizgi, mesajlar,
yazma alanı.

### Başlık
- Solda 46 pt beyaz daire içinde 40 pt robot (cevap beklenirken "düşünme" sallanması).
- Yanında iki satır: kalın yazıyla uygulamanın adı, altında gri küçük `sheets.ask.subtitle` (Setup helper / Kurulum yardımcısı).
- Sağda:
  - Sohbette en az bir mesaj varsa hayalet düğme `sheets.ask.newChat` (New chat / Yeni sohbet) (kalem ve kare simgesi). Basınca her şey
    silinir, bekleyen istek iptal edilir.
  - `sheets.common.close` (Close / Kapat) (ikincil düğme). Esc de kapatır.
- Sorun Bildir moduna geçilince başlığın solunda geri oku (`sheets.common.back`: Back / Geri) çıkar, alt yazı
  `sheets.report.title` (Report a Problem / Sorun Bildir) olur, `sheets.ask.newChat` düğmesi gizlenir.

### Mesaj listesi
- Kaydırılabilir dikey liste, iç kenar boşluğu geniş. Yeni mesaj ya da "yazıyor" durumu değişince 0,25 sn'de en alta
  kayar; sayfa açılınca da en alttadır.
- **Her zaman ilk balon robotun selamıdır** (sunucuya gönderilmez):
  `sheets.ask.greeting` (robot 👋 ile kendini tanıtır, kurulumla ilgili her soruya açık olduğunu söyler; sonra kullanıcının elindeki aygıtları (PS5/Xbox, TV/monitör, telefon/bilgisayar) ve kurulumu nereye yapmak istediğini sorar)
- Sohbet boşken selamın altında **öneri hapları** (robotun hizasından, 34 pt içeriden, sığmayan alt satıra geçer):
  - `sheets.ask.suggest.ps5TVPhone` (PS5, a TV and a phone / PS5 + TV + telefonum)
  - `sheets.ask.suggest.ps5MonitorComputer` (PS5, monitör ve bilgisayardan oluşan düzeni seçen hap)
  - `sheets.ask.suggest.xboxTV` (Xbox + TV / Xbox + TV)
  - `sheets.ask.suggest.tvApp` (TV uygulamasının nasıl kurulacağını soran hap)
  - Görünüş: açık vurgu zeminli hap, vurgu renginde orta kalınlıkta yazı, ince vurgu kenarı.
  - Dokununca o hapın **arayüz dilindeki** metni hemen soru olarak gönderilir (sistem dili İngilizce olsa bile Türkçe
    arayüzde Türkçe metin gider). Robotun bütün yerel metinleri de arayüz dilinden okunur; o dilde yoksa İngilizcesi.

#### Robot balonu
- Solda 26 pt küçük robot (hareketsiz; "yazıyor" balonunda göz kırpar ve sallanır), yanında cam zeminli, 18 pt yuvarlak
  köşeli balon, ince cam kenarı. Sağda en az 48 pt boşluk kalır.
- Robotun cevabı biçimli gösterilir:
  - Boş satır blokları ayırır.
  - `1.` ya da `1)` ile başlayan satır (en çok iki basamak) **numaralı adım**dır: solda vurgu renginde yuvarlak rozet
    (çap 21, içinde beyaz kalın yuvarlak rakam; iki basamaklıysa hap), yanında yazı. "2024. yılında" gibi satır adım sayılmaz.
  - `-`, `•` ya da `*` ile başlayan satır **madde**dir: rozet genişliğinde vurgu renginde kalın nokta, yanında yazı.
  - Kayan satırlar rozetin altına değil yazının hizasına gelir (asılı girinti).
  - Bir adımın/maddenin hemen altındaki **girintili** satır onun devamıdır; girintisiz satır yeni paragraf başlatır.
    Paragraf içindeki tek satır sonları korunur.
  - Ardışık iki liste öğesi arası 8 pt, diğer bloklar arası 10 pt.
  - `http`/`https` ve `www.` bağlantıları tıklanabilir (sondaki noktalama bağlantıya dahil edilmez).
  - Yazı seçilebilir. Sağdan sola dillerde rozet kendiliğinden sağa geçer.
- Robot cevabıyla birlikte ekibe bildirim açtıysa balonun altında yeşil hap: onay işareti ve `sheets.ask.reportSent`
  (Report sent / Bildirim gönderildi).

#### Kullanıcı balonu
- Sağa yaslı, vurgu mavisi zemin, beyaz yazı, 18 pt köşe; solda en az 72 pt boşluk.
- Fotoğraf eklendiyse yazının üstünde 84 × 64 pt küçük resimler (10 pt köşe). Yazı seçilebilir.
- Gönderilemediyse (ağ/sunucu hatası) balon %60 soluk görünür ve altında kırmızı ünlem simgeli
  `sheets.ask.notSent` (Not sent / Gönderilemedi), yanında `sheets.ask.tryAgain` (Try again / Tekrar dene) bağlantı düğmesi (cevap beklenirken pasif).
  Yalnız son kullanıcı mesajında ve yalnız yeniden denenebilen hatalarda görünür.

#### "Yazıyor" balonu
- Cevap beklenirken robot balonu içinde üç nokta animasyonu. Erişilebilirlik: `sheets.ask.typing` (Nino is typing… / Nino yazıyor…)

#### Hata balonları (robotun ağzından, yerel; sunucuya gitmez)
| Durum | Anahtar | EN | TR |
|---|---|---|---|
| Yardımcı sunucuda henüz kapalı | `sheets.ask.error.disabled` | *robotun neredeyse hazır olduğunu söyleyip o zamana kadar sorunun Sorun Bildir'den ekibe gönderilmesini istediği satır* | *(Türkçesi aynı anlamda)* |
| Kullanıcı bugün çok sordu | `sheets.ask.error.dailyLimit` | *bugünlük soru sayısının çok olduğunu 🙂 ile söyleyip yarına bırakmayı öneren satır* | *(Türkçesi aynı anlamda)* |
| Sunucu yoğun / bütçe doldu | `sheets.ask.error.busy` | *robotun o an yetişemediğini söyleyip kısa süre sonra tekrar denemeyi isteyen satır* | *(Türkçesi aynı anlamda)* |
| Gövde/fotoğraf çok büyük | `sheets.ask.error.tooLarge` | *gönderinin fazla büyük olduğunu söyler, fotoğraflardan birini çıkarıp yeniden denemeyi ister* | *(Türkçesi aynı anlamda)* |
| Sunucu biçimi reddetti | `sheets.ask.error.rejected` | *mesajın anlaşılamadığını söyleyip başka sözcüklerle yeniden yazılmasını rica eden satır* | *(Türkçesi aynı anlamda)* |
| Ağ yok, sunucu hatası, adres yok | `sheets.ask.error.offline` | sunucuya ulaşılamadığını söyleyip internete bakıp yeniden denemeyi ister | Sunucuya ulaşamadım. İnternetine bakıp yeniden dene. |

- `sheets.ask.error.disabled` ve `sheets.ask.error.dailyLimit` balonlarının altında birincil `sheets.report.title`
  (Report a Problem / Sorun Bildir) düğmesi vardır; basınca sayfa Sorun
  Bildir moduna geçer (kurulumda Ayarlar olmadığı için form aynı sayfada açılır).
- Yeni bir mesaj gönderilince ya da yeniden denenince önceki hata balonları sohbetten kalkar.

### Yazma alanı
- En altta, yatay geniş kenar boşluklu.
- Eklenmiş fotoğraf varsa üstte 64 × 48 pt küçük resimler (8 pt köşe, ince kenar), her birinin sağ üstünde yarı saydam
  siyah üstüne beyaz çarpı ile kaldırma düğmesi (`sheets.photo.remove`: Remove photo / Fotoğrafı kaldır). Fotoğraf hazırlanırken
  yanında küçük dönen gösterge.
- Okunamayan dosya eklendiyse kırmızı hata satırı: `sheets.photo.unreadable` (Nino couldn't open this file as a picture. / Nino bu dosyayı resim olarak açamadı.)
- Alt satır, soldan sağa:
  1. **Fotoğraf ekle** düğmesi (fotoğraf + artı simgesi, 36 × 36). İpucu: `sheets.ask.addScreenshot` (Add a screenshot; TR metni ekran görüntüsü eklemeye çağırır).
     Sınır dolunca gri ve pasif. Tıklanınca dosya seçici açılır (yalnız resim, çoklu seçim).
  2. **Yazı kutusu:** yer tutucu `sheets.ask.placeholder` (Ask Nino… / Nino'ya sor…); 1 ile 6 satır arası büyür; cam zemin, 18 pt köşe,
     ince cam kenar; en az 36 pt yükseklik. Sayfa açılınca odak buradadır. Enter gönderir.
  3. **Gönder** düğmesi: 36 pt daire, içinde beyaz kalın yukarı ok. Gönderilebilirse vurgu mavisi, değilse soluk gri ve
     pasif. Erişilebilirlik: `sheets.ask.send` (Send / Gönder).
- Gönderilebilir: yazı boş değil ya da en az bir fotoğraf var, ve cevap beklenmiyor, ve fotoğraf hazırlanmıyor.
- Gönderince yazı kutusu ve ekler temizlenir, odak yazı kutusunda kalır.

### Fotoğraf ekleme yolları
- Fotoğraf düğmesi (dosya seçici).
- Sayfaya **sürükle-bırak** (Finder'dan dosya ya da başka uygulamadan resim). Sürüklerken mesaj alanının çevresinde
  vurgu renginde kesik çizgili yuvarlak köşeli çerçeve belirir. Sorun Bildir modunda ya da sınır doluyken bırakma kabul edilmez.
- **⌘V:** panoda resim dosyası varsa ek olarak alınır; panoda yalnız resim verisi varsa (ekran görüntüsü, başka
  uygulamadan kopyalanan resim) o alınır. Panoda yazı da varsa normal yazı yapıştırma olur. Sorun Bildir modunda devre dışı.
- Mesaj başına **en çok 3 fotoğraf**; fazlası alınmaz. 60 MB'den büyük dosya okunmaz (okunamadı sayılır).
- Her fotoğraf arka planda küçültülür: en uzun kenar en çok 1600 px, döndürme bilgisi uygulanır, saydam alan beyaza
  boyanır, JPEG yapılır (kalite 0,7 → 0,55 → 0,4 denenir; 900 KB'yi geçerse boyut dörtte üçe indirilip yeniden denenir,
  200 px altına inmez). Okunamazsa o dosya atlanır ve hata satırı görünür.

### Sohbetin ömrü
- Sohbet uygulama açık kaldıkça bellekte durur: sayfa kapanıp açılınca kaybolmaz.
- Uygulama kapanınca silinir; diske yazılmaz.

---

## 4. Sunucu sözleşmesi

### Adres
- Nino havuz sunucusunun kökü + `v1/assistant`, **POST**.
- Kök adres sırası: `NINO_POOL_URL` ortam değişkeni → `ninoPoolURL` kullanıcı ayarı → canlı adres
  `https://nino-pool.y-demirbag2506.workers.dev`. (Değer `http` ile başlamıyorsa atlanır.) Hiçbiri yoksa "adres yok" hatası.
- Zaman aşımı 90 sn. Başlıklar: `Content-Type: application/json`, `User-Agent: nino-assistant/1 (mac; <sürüm>)`.

### İstek gövdesi (JSON, anahtarlar sıralı, `/` kaçırılmaz)
```json
{
  "v": 1,
  "install": "<kuruluş kimliği>",
  "app": "<uygulama sürümü>",
  "platform": "mac",
  "language": "<arayüz dili kodu, ör. tr>",
  "device": "<cihaz özeti; boşsa alan yok>",
  "messages": [
    { "role": "user", "text": "...", "images": [ { "mime": "image/jpeg", "data": "<base64>" } ] },
    { "role": "assistant", "text": "..." }
  ]
}
```
- **install:** havuzun kullandığı anonim kuruluş kimliğiyle aynı (sunucu tuzlayıp özetler).
- **language:** çeviri dilinden türetilen arayüz dili.
- **device:** cihaz satırlarının kısa özeti (uygulama, Mac modeli, sistem, TV markası/modeli/TV uygulaması sürümü ve
  bağlı olup olmadığı, konsol). Kişisel bilgi içermez. Belli bir uzunlukta kesilir. Modele gönderilmez; yardımcı
  bildirim açarsa bildirime eklenir. Bağlam her mesajda yeniden toplanır (TV sonradan bağlanmış olabilir).
- **messages** hazırlanırken:
  - Yerel hata balonları ve gönderilemeyen mesajlar katılmaz (yeniden denenen mesaj katılır).
  - Boş metinli mesajlar atılır (fotoğraflı kullanıcı mesajı hariç).
  - En çok **son 24 mesaj**.
  - Her metin kırpılır ve **en çok 2000 karakter** (UTF-16 birimiyle sayılır; karakterin ortasından kesilmez).
  - Her mesajda en çok 3 fotoğraf.
  - Fotoğraflar yalnız **fotoğraflı son iki kullanıcı mesajında** gider; daha eskilerde fotoğraf atılır ve metnin başına
    `[screenshot]` yazılır (metin boşsa yalnız `[screenshot]`).
  - İlk mesaj robotunsa (kırpma yüzünden) atılmaz.
- Son mesaj kullanıcınınsa ve boş değilse gönderilir; değilse istek gönderilmez ("reddedildi").
- Gövde **6 MB'yi geçerse** yalnız en son fotoğraflı mesajın fotoğrafları bırakılır (öbürleri `[screenshot]` olur);
  yine sığmazsa "çok büyük" hatası.

### Cevap
- 2xx ve gövde `{ "ok": true, "reply": "<metin>", "report": "<kimlik ya da boş>" }`: metin kırpılır; boşsa ya da
  `ok:false` ise sunucu hatası sayılır. `report` doluysa `sheets.ask.reportSent` hapı gösterilir.
- Durum kodu eşlemesi:

| Kod / gövde | Durum | Yeniden denenir mi |
|---|---|---|
| 400 | reddedildi | hayır |
| 413 | çok büyük | hayır |
| 429 + `error:"busy"` | yoğun | evet |
| 429 (diğer) | bugün çok soruldu | hayır |
| 503 + `error:"assistant_disabled"` | yardımcı kapalı | hayır |
| 503 (diğer) | yoğun | evet |
| diğer kodlar, 2xx ama boş cevap | sunucu hatası | evet |
| ağ hatası, HTTP olmayan cevap | çevrimdışı | evet |
| adres yok | adres yok | evet |

- Sunucu tarafında sınırlar aynıdır (24 mesaj, 2000 karakter, mesaj başına 3 fotoğraf). Sunucu soruyu kendi bilgi
  tabanıyla birlikte bir dil modeline sorar.

---

## 5. Sorun Bildir ile bağlantı

- Sohbet sayfasında Sorun Bildir moduna geçilince mesajlar ve yazma alanı gizlenir, yerine kaydırılabilir alanda Sorun
  Bildir formu açılır; geri oku ile sohbete dönülür (sohbet korunur).
- Form `v1/reports` adresine gider; aynı kuruluş kimliği ve aynı fotoğraf küçültme kullanılır. Ayrıntılar ayrı belgede.

---

## 6. Oynanan oyun: nereden bilinir

Oyunun adı ortak havuza giden satırlara eklenir; sunucu aynı oyunun satırlarını ayrı pakete toplar. Kullanıcıya dair
bir şey gitmez, yalnız oyunun adı (ve varsa kimliği).

### Dört kaynak, öncelik sırasıyla
1. **PS5'in bildirdiği (konsol):** PS5'e bağlıyken 120 sn'de bir yalnız bağlı PS5'in adresine keşif sorusu gider
   (2 sn bekleme). Yanıttaki çalışan uygulama kimliği ve adı okunur. Kimlik biçimi: dört büyük harf + beş rakam,
   isteğe bağlı `_00` eki (ör. `PPSA01234`, `CUSA00419_00`); biçim tutmazsa (ana ekran, sistem uygulaması) alınmaz.
   PS5 çoğu zaman bu bilgiyi boş verir. Bağlantı kopunca konsol bilgisi silinir.
   PS5 elle seçilenden **başka** bir oyun bildirirse elle seçim eskimiş sayılır ve silinir.
2. **Kullanıcının seçtiği:** oyun sorma kartından (`sheets.game.title`) ya da oyun satırındaki değiştirme bağlantısından.
3. **Paket çoğunluğu:** her gösterilen satır için, satır yalnız tek bir hazır pakette bulunan anahtarla geldiyse o
   pakete oy sayılır. Son **20** satırın en az **5**'i aynı paketten gelince oyun o paketin oyunudur. Oyunu bilinmeyen
   satırların genel paketi oy sayılmaz. Otomatik toplanmış paket adı oyun kimliğini taşıyorsa kimlik de alınır.
   Bu tahmin "kesin" sayılmaz.
4. **Ekrandan tanınan:**
   - **Yerel işaretler:** ekrandaki yazılarda oyuna özgü izler (şu an yalnız GTA 6: harita ekranının tuş listesi,
     duraklatma menüsünde iki kahramanın adının birlikte geçmesi ya da "BRIEF" + "PROGRESS" sekmeleri, oyun içi
     telefonun mesaj uygulaması adı). Bulunursa oyun "GTA 6" olur; PS5 ya da kullanıcı başka oyun söylüyorsa dokunulmaz.
   - **Sunucuya kare:** oyun bilinmiyorsa Remote Play karesi 768 px genişliğe küçültülüp JPEG (en çok 450 KB) olarak
     havuz sunucusunun `v1/identify` adresine POST edilir (30 sn zaman aşımı). Gövde:
     `{ "v":1, "install", "app", "platform":"mac", "image":"<base64>" }`; cevap `{ "game": "<ad>" }`. Sunucu kareye bir
     modelle bakıp oyunun adını söyler.
   - Zamanlama: oyun bilinmiyorsa çeviri başladıktan ~8 sn sonra, sonra dakikada bir, **en çok 6 deneme**. Oyun
     ekrandan tanındıysa yedek olarak 5 dk sonra bir kez doğrulama, sonra 20 dakikada bir (en çok 12 kez); başka oyun
     derse oyun değişir. Konsol, kullanıcı ya da paket söylüyorsa bakılmaz.
   - Yalnız ortak havuz açık ve kaynak dil İngilizceyken çalışır.

- Geçerli oyun: **konsol → kullanıcı → paket → ekran** sırasıyla ilk dolu olan.
- "Kesin" sayılan: konsol, kullanıcı ya da ekran (paket tahmini değil).
- Kullanıcı elle seçtiyse ve PS5 bir oyun bildirmiyorsa satırlar yalnız o oyunun paketinde aranır; paketi yoksa hiç
  pakette aranmaz.
- Oyun değişince: ana ekran hemen yenilenir (oyuna özel fon, `home.translation.poolGame %@` şeridi: Nino · %@ active / Nino · %@ etkin), o oyunun paketine sunucuda bakılır,
  havuzdaki çevirileri hemen iner.
- Yeni çeviri oturumunda paket penceresi, konsol bilgisi ve "soruldu" işareti sıfırlanır; kullanıcının seçimi uygulama
  açık kaldıkça kalır.

### Oyun adlarının karşılaştırılması
İki ad aynı oyun mu diye bir **anahtar**la bakılır (sunucuyla aynı kural): küçük harf, aksanlar ve ™®© atılır,
kesme işaretleri silinir, `ı` → `i`, `&` → `and`, harf ile rakam arasına boşluk (`gta6` → `gta 6`), Roma rakamları
sayıya (II–XVI), baştaki "the" atılır, bilinen uzun adlar kısaltılır ("grand theft auto" → gta, "call of duty" → cod,
"red dead redemption" → rdr, "ea sports fc" → fc, "ea sports" silinir), en çok 80 karakter.
Örnek: "Grand Theft Auto VI" ve "GTA 6" → `gta 6`.
Oyun adı temizlenir: denetim karakterleri boşluğa, fazla boşluk teke, en çok 120 karakter; boşsa ad yok.

---

## 7. Oyun sorma kartı ve oynanan oyun satırı

> Not: eski Mac uygulamasında bu kart ve satır yalnız klasik ana ekranın sol sütununda, çeviri sürerken görünüyordu.
> Varsayılan ana ekran (salon sahnesi) bunları göstermiyor; o sütun da artık kullanılmıyor. Ayar anahtarı
> (`settings.packs.ask`: EN metni oynanan oyunun sorulmasını açar / Oynadığım oyunu sor; ipucu `settings.packs.askHint`:
> oyunu hiçbir paket tanımazsa Nino'nun, çeviri başlamasının üzerinden iki dakika geçince bunu tek bir kez
> soracağını anlatır) gizli Oyun paketleri sayfasında. Yeni uygulamada yeri ürün kararıdır; davranış aşağıdaki gibidir.

### Ne zaman açılır
- Çeviri başladıktan sonra 15 sn'de bir bakılır. Şunların hepsi doğruysa kart **bir kez** kendiliğinden açılır:
  `settings.packs.ask` ayarı açık **ve** ortak havuz açık, bu oturumda daha önce sorulmadı, oyun hiçbir yoldan
  bilinmiyor, çeviri en az **120 sn**dir sürüyor.
- Oyun sonradan herhangi bir yoldan tanınırsa açık kart kapanır.
- Çeviri durunca kart kapanır.

### Kart
- Başlık: `sheets.game.title` (EN metni hangi oyunun oynandığını sorar / Hangi oyunu oynuyorsun?); sağda küçük gri
  bağlantı düğmesi `sheets.game.dontAsk` (Don't ask / Sorma) (bu oturumda bir daha sorulmaz).
- İpucu: `sheets.game.hint` (paketlerde bulunmayan satırların oyun adıyla birlikte ortak havuza aktarıldığını, bu sayede o
  oyunun hazır çevirisinin daha erken geleceğini anlatır)
- Arama kutusu (36 pt): `sheets.game.search` (Search games / Oyun ara). Enter, yazılan adı seçer.
- Altında en çok **5 öneri** satırı, aralarında ince çizgi. Satır: oyun adı; bu PS5'te son seçilen oyunsa sağda gri
  `sheets.game.lastPlayed` (Last played / Son oynanan). Tıklanınca o oyun seçilir.
- Yazılan ad önerilerde (anahtarca) yoksa ikincil düğme: `sheets.game.useCustom %@` (Not in the list: use “%@”; TR metni yazılan adın listede olmadığını söyleyip
  onu kaydetmeyi önerir).
- Karo görünümünde, tam genişlik.

### Öneriler
- Sıra: önce bu PS5'te son oynanan, sonra kurulu paketlerin oyunları (genel paket hariç), sonra sabit popüler oyunlar
  listesi; aynı oyun (anahtarca) bir kez.
- Popüler liste (Android ve Windows'ta aynı): GTA 6, GTA 5, Red Dead Redemption 2, Ghost of Yōtei, Marvel's Spider-Man 2,
  Death Stranding 2: On the Beach, Elden Ring, Elden Ring Nightreign, Assassin's Creed Shadows, Call of Duty: Black Ops 7,
  Call of Duty: Black Ops 6, Battlefield 6, EA Sports FC 26, Mafia: The Old Country, The Last of Us Part II Remastered,
  God of War Ragnarök, Cyberpunk 2077, Hogwarts Legacy, Resident Evil Requiem, Silent Hill f, Metal Gear Solid Delta:
  Snake Eater, Borderlands 4, Kingdom Come: Deliverance II, Clair Obscur: Expedition 33, Final Fantasy VII Rebirth,
  Stellar Blade, Black Myth: Wukong, Baldur's Gate 3, Horizon Forbidden West, Alan Wake 2, Indiana Jones and the Great
  Circle, Dying Light: The Beast, Ghost of Tsushima, Star Wars Outlaws, The Witcher 3: Wild Hunt, Monster Hunter Wilds,
  Split Fiction, Hollow Knight: Silksong.
- Arama boşsa listenin başı. Arama varsa: anahtarı aramanın anahtarını içerenler (ayrıca "GTA 6"/"GTA 5" için uzun
  adları "Grand Theft Auto VI/V" düz yazıyla da aranır); adı aramayla **başlayanlar önde**.

### Seçimin saklanması
- Seçim bu oturumda geçerlidir ve PS5'in adıyla (ad yoksa adresiyle; bu Mac'teki oyun penceresinden (PS Remote Play) okurken PS5 yoksa
  hiç) kalıcı saklanır: `PS5 adı → oyun adı` sözlüğü. Aynı PS5'te sonraki oturumda kartın ilk önerisi ve `sheets.game.lastPlayed` olur.

### Oynanan oyun satırı (kart kapalıyken)
- Solda karo simgesi (oyun kolu), yanında satırın oynanan oyunu gösterdiğini belirten gri küçük etiket, altında oyunun
  adı ya da oyunun bilinmediğini söyleyen tek kelime (tek satır). Bu metinlerin yeni karşılığı yok.
- Sağda vurgu renginde küçük kalın bağlantı: oyun bilinmiyorsa seçmeye, biliniyorsa değiştirmeye çağıran tek kelime
  (yeni karşılığı yok).
  Basınca kart elle açılır (ve bu oturumda kendiliğinden sorulmaz).
