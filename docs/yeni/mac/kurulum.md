# Mac: ilk açılış kurulum sihirbazı

Bu belge yeni Mac uygulaması için bir **tarif**tir: sihirbazın neye benzediğini ve nasıl davrandığını anlatır. Kod
içermez. Metinler yeni uygulamanın metin anahtarıyla verilir: anahtarlar noktalı adlardır (ör. `setup.continue`) ve
alanlara göre ayrı xcstrings dosyalarında durur (Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport).
Metinlerin kendisi bu belgeye yazılmaz (onlar xcstrings dosyalarındadır); anahtarın yanında yalnız metnin ne dediği
kısaca anlatılır. Çok kısa düğme ve etiket adları parantezde verilebilir. Yeni uygulamada karşılığı olmayan metinler
de kendi sözlerimizle anlatılır.

Ölçüler nokta (pt) cinsindendir. Renk ve yazı adları `design/tokens.json`'daki rollerdir (accent, accentText,
textSecondary, success, warning, danger, surface2, accentSoft…). Boşluk adları: xs 4, s 8, m 12, l 16, xl 24, xxl 32.
Yazılar: başlık 22 yarı kalın, manşet 17 yarı kalın, gövde 15, açıklama 13 orta, düğme 15 yarı kalın.

Kapsam: sihirbazın çerçevesi ve yedi adımı, PSN girişi, PS5 eşleştirmesi, yakalama kartı rehberi ve Xbox bağlantı
listesi. TV adımındaki uygulama kurulum kartlarının ayrıntısı `tv-kurulumu.md`'de; görüntü kaynaklarının çalışma
biçimi `kaynaklar.md`'de.

---

## 1. Sihirbaz ne zaman açılır

- Ana pencere (en az 1040×720, en çok 1300 genişlik) iki şeyden birini gösterir: kurulum bittiyse ana ekran,
  bitmediyse sihirbaz. Açılış logosu kalkınca sihirbaz görünür.
- Uygulama açılırken başlangıç adımı:
  - Kurulum "bitti" sayılıyorsa ana ekran.
  - Görüntü kaynağı PS5 değilse (oyun penceresi ya da yakalama kartı) ve "kurulum bitti" kaydı varsa ana ekran.
  - Değilse: hesap kimliği **ve** PS5 kaydı varsa doğrudan **TV adımı** (yarım kalan kurulum TV'den sürer),
    yoksa **Hoş geldin**.
- "Kurulum bitti" kaydı Anahtarlık'ta tutulur; sihirbaz son adımdan sonra "bitti" durumuna ilk geçtiğinde `true` yazılır. Kayıt hiç
  yoksa (çok eski kurulum) hesap + PS5 + eşleşmiş TV varsa bitti sayılır ve bu yazılır.
- Ayarlardan gelen yollar:
  - Her şeyi sıfırlama (`settings.reset.everything` (Reset everything / Her şeyi sıfırla)): hesap kimliği, PS5 kaydı, TV, TV anahtarları, TV uygulama
    sürümü, "bitti" kaydı ve PS5 giriş şifresi silinir; konsol seçimi boşalır; sihirbaz konsol seçiminden başlar.
  - TV'den yeniden kurma (`settings.reset.fromTV` (TV'den başlayarak yeniden kurma düğmesi)): yalnız TV bilgileri ve
    "bitti" kaydı silinir; "TV'm yok" seçiliyse çıktı yeniden TV olur; sihirbaz TV adımından açılır.
  - Hesap bağlama (görüntü PS5'ten ama hesap ya da eşleşme yok; yeni uygulamada bu düğmenin henüz kendi metni yok):
    sihirbaz İkinci hesap adımından açılır.

## 2. Çerçeve

Yukarıdan aşağı:

1. **Üst şerit:** solda 26 pt logo, yanında 16 pt kelime işareti (kalın yuvarlak uygulama adı, altında harf aralıklı
   büyük harfli alt yazı, textSecondary). Aralarında 8. Yatay iç boşluk 24, üstten 12.
2. **Kart:** en çok 700 genişlikte, ortalı, kalan yüksekliği dolduran tek cam kart (köşe 22, ince cam kenarı, çok
   hafif gölge). Kartın içi dikey kaydırılır, kaydırma çubuğu görünmez. İçerik yatayda 32, dikeyde 16 boşluklu.
   Kartın kendisi yatayda 32, üstten 12 içeride.
3. **Alt düğme sırası:** en çok 700 genişlik, yatayda 32, dikeyde 16 boşluk.
   - Ortada **sayfa noktaları:** adım sayısı 7 ("bitti" durumu sayılmaz). Nokta 7×7 kapsül; geçerli olan 24 genişliğe uzar.
     Geçerli ve geçilmiş olanlar accent, kalanlar textSecondary %30. Aralık 7. Yaylı geçiş (0,4 sn).
     Erişilebilirlik: `setup.dots %lld %lld` (kaçıncı adımda olunduğunu ve toplam adım sayısını söyleyen etiket).
   - Solda **Geri** (hayalet düğme, 44 yükseklik, sola ok simgesi): `setup.back` (Back / Geri). Yalnız ilk ekranda (konsol
     seçimi) görünmez.
   - Sağda adıma göre:
     - "Daha iyi çeviri" adımında ve Gemini hazır değilse: `setup.skip` (Skip for now / Şimdilik geç) (ikincil, 44).
     - Değilse **Devam** (birincil, 44, en az 120 genişlik, Return kısayolu): `setup.continue` (Continue / Devam). Deneme adımında
       ve konsol seçim ekranında görünmez. İlerleme koşulu sağlanmıyorsa soluk ve tıklanmaz.
- Adım değişince yeni adım sağdan kayarak ve belirerek gelir, eskisi sola kayarak gider (yaylı, 0,45 sn, sönüm 0,86).
- Pencerenin sağ altında (Devam'ın üstünde, alttan 96) "Nino'ya Sor" robotu durur (bkz. `ninoya-sor.md`).
- Yakalama kartı rehberi açıkken (bkz. §10) kart ve alt sıra yerine rehber gösterilir; geçiş 0,25 sn solma.

### Ortak adım düzeni

Her adım aynı dikey düzendedir (aralık 12):

- **Simge:** Hoş geldin'de 84 pt logo (accent %45 parıltılı gölge). Öbür adımlarda 56 pt degrade simge kutusu: köşesi
  boyunun %30'u, accentHi'den koyu laciverde (#003085 civarı) çapraz degrade, üstten aşağı beyaz %50→%5 ince kenar,
  beyaz simge (boyun %42'si), accent %45 gölge. Adım açılınca simge %70'ten büyüyerek ve belirerek gelir (yaylı,
  0,55 sn, sönüm 0,7).
- **Başlık:** 26 kalın yuvarlak, ortalı.
- **Açıklama:** 14, textSecondary, ortalı, satır arası 2, en çok 540 genişlik.
- **İçerik:** tam genişlik, üstten 8.

Adımların simgeleri (SF Symbols): İkinci hesap `person.crop.circle.badge.plus`, PSN girişi `key.fill`, PS5
`gamecontroller.fill`, TV `tv.fill`, Deneme `captions.bubble.fill`, Daha iyi çeviri `wand.and.stars`.

### Ortak küçük parçalar

- **Numaralı satır:** solda 32 pt daire (aynı degrade, beyaz 15 kalın yuvarlak rakam, hafif gölge), sağda gövde
  yazısı (satır arası 3); kendi cam karosunda, iç boşluk 16.
- **İpucu:** açıklama yazısı, textSecondary, satır arası 2.
- **Hata:** `exclamationmark.triangle.fill` simgeli, açıklama boyu, **warning** renginde (kırmızı değil).
- **Bitti etiketi:** `checkmark.circle.fill` simgeli, gövde yarı kalın, success.
- **Seçenek kartı:** solda görsel (88×60; görsel yoksa 44 pt degrade simge), başlık (manşet) ve açıklama, sağda 13 pt
  sağ ok. Üstüne gelince kart etkin kenarlı olur, %1 büyür, ok accentText'e döner ve 3 pt sağa kayar.
- **Düğmeler:** köşe 14. Birincil: accent'ten laciverte dikey degrade, üstte beyaz ince ışık kenarı, beyaz yazı,
  accent gölge; ikincil: cam zemin, ince cam kenar; tehlikeli: dangerSoft zemin, danger yazı; hayalet: zeminsiz,
  accentText yazı. Basılınca %97. Normal yükseklik 40, büyük 44.
- **Metin alanı:** düz alan, gövde yazısı, yatay 16, en az 44 yükseklik.

---

## 3. Adım 1: Hoş geldin

Üç hâli vardır. Konsol seçimi kaydedilmez: yarım kalan kurulum yeniden açılınca yine sorulur.

### 3a. Konsol seçimi (ilk ekran)

- Başlık `setup.welcome.choose.title` (hangi konsolda oynandığını soran başlık).
- Açıklama `setup.welcome.choose.message` (iki konsolun da desteklendiğini, seçimin ileride ayarlardan değişebileceğini anlatır).
- Simge yeri: logo.
- Yan yana iki büyük kart (aralık 12), her biri en az 280 yükseklikte cam karo:
  - Üstte 180 yükseklikte konsol görseli, alta yaslı (sehpada duruyormuş gibi). PS5 dik, Xbox yatık (yatay 12 içeri).
  - Altında ad (manşet) ve sağda 13 pt yarı kalın sağ ok (sağdan sola dillerde döner); altında açıklama.
  - Üstüne gelince accent %90 1,5 pt kenar ve %1,5 büyüme (0,15 sn).
  - PS5 kartı: ad konsolun adı (çevrilmez), açıklama `setup.welcome.choose.ps5` (kablosuz ağda Remote Play'le ve ek bir PSN hesabıyla çalıştığını belirtir).
  - Xbox kartı: ad konsolun adı (çevrilmez), açıklama `setup.welcome.choose.xbox` (desteklenen Xbox modellerini sayar ve görüntünün bu Mac'e aktarıldığını belirtir).
- Görseller saydam zeminli iki ayrı resimdir. Not: bunlar konsol tasarımlarına benziyor; mağazaya gitmeden markasız
  çizimle değiştirilmeli.
- Tıklanınca o konsolun karşılaması açılır (solma geçişi). PS5 seçilince oyun konsolu PS5, görüntü kaynağı PS5 olur.
- Bu ekranda Geri ve Devam görünmez.

### 3b. Çeviri dili seçici (üç hâlde de)

- Kartın sağ üstünde, sağdan sola dillerde de sağda kalan hap düğme: bayrak (18 pt) + dilin kendi adı (açıklama
  yarı kalın) + 10 pt aşağı ok (textSecondary). Yükseklik 34, yatay 12, zemin beyaz %8, kenar accent %60.
- Basınca bayraklı dil listesi açılır (Türkçe başta); seçili olanın yanında "✓". Seçim çeviri dilini hemen değiştirir.
- İpucu ve erişilebilirlik adı: `setup.language` (seçicinin çeviri dilini değiştirdiğini söyleyen etiket; TR: Çeviri dili).

### 3c. PS5 karşılaması

- Başlık `setup.welcome.ps5.title` (Nino'ya hoş geldiniz diyen başlık (Türkçesinde uygulamanın tam adı geçer); EN: Welcome to Nino).
- Açıklama çeviri diline göre değişir (üçünde de anlam aynı: Nino konsoldaki oyunların İngilizce yazılarını alır,
  çevirisini televizyonda görüntünün üzerine koyar, oyuncu da kendi koluyla oynamayı sürdürür):
  - Türkçe: `setup.welcome.ps5.message.turkish` (yukarıdaki anlamı Türkçe çeviri diye adlandırarak söyler)
  - Arapça: `setup.welcome.ps5.message.arabic` (aynı anlam, çeviri Arapça diye adlandırılır)
  - Öbür diller: `setup.welcome.ps5.message.other` (aynı anlam, dil adı yerine "sizin diliniz" denir)
- İçerik:
  - Üst satır: solda `setup.welcome.need` (What you need / İhtiyacınız olanlar) (açıklama, textSecondary, BÜYÜK HARF); sağda saat simgeli
    `setup.welcome.duration` (kurulumun yaklaşık 5 dakika sürdüğünü söyleyen not). Yatay 4 içeri.
  - Yan yana üç **gereksinim karosu** (aralık 12, her biri en az 150): 48 pt daire (accentHi→lacivert degrade, accent
    %40 gölge) içinde 20 pt beyaz simge; altında başlık (manşet) ve açıklama. Açılınca %96'dan büyüyerek ve belirerek
    gelir (yaylı 0,5 sn, 0,05 sn gecikme).
    - `gamecontroller.fill`: başlık konsolun adı (çevrilmez); açıklama `setup.welcome.need.ps5` (konsolun bu bilgisayarla tek bir kablosuz ağı paylaşması gerektiğini anlatan not)
    - `tv.fill`: `setup.welcome.need.tv` (Smart TV / Akıllı TV) / `setup.welcome.need.tv.detail` (desteklenen TV türlerini sayan not: Android TV, Google TV, LG ve Samsung)
    - `person.crop.circle.badge.plus`: `setup.welcome.need.account` (ek bir PSN hesabı gerektiğini söyleyen kısa başlık) / `setup.welcome.need.account.detail` (hesabın ücretsiz olduğunu ve 2 dakikada açıldığını söyleyen not; EN: Free, ready in 2 minutes)
  - Altta iki kısa yol bağlantısı (açıklama yarı kalın, accentText, aralarında esnek boşluk, üstten 8):
    - `macwindow` `setup.welcome.thisComputer` (oyunu zaten bilgisayarında Sony'nin Remote Play programıyla oynayanlar için kısa yol bağlantısı).
      İpucu: `setup.welcome.thisComputer.help` (bu yolda televizyona da ek hesaba da gerek olmadığını; Nino'nun açık Remote Play penceresinden okuyup çeviriyi görüntünün üzerine koyduğunu anlatan not). Tıklanınca: konsol PS5, görüntü kaynağı oyun
      penceresi, sihirbaz **biter** (ana ekran).
    - `cable.connector` `setup.welcome.captureCard` (elinde yakalama kartı bulunanlar için kısa yol bağlantısı). İpucu:
      `setup.welcome.captureCard.help` (bu yolda ek hesaba gerek olmadığını; görüntünün karttan alınıp çeviriyle birlikte gösterildiğini anlatan not). Tıklanınca yakalama kartı rehberi açılır (§10).
- Geri: konsol seçimine döner. Devam: İkinci hesap adımı.

### 3d. Xbox karşılaması

- Simge `gamecontroller.fill`. Başlık `setup.xbox.title` (Connect Your Xbox / Xbox'ı Bağlayın). Açıklama `setup.xbox.message` (adımların Nino tarafından tek tek kendiliğinden yoklandığını, işin bir defalık olduğunu anlatır).
- İçerik en çok 640 genişlikte, ortalı: Xbox bağlantı listesi (§11), altında yan yana (aralık 16) iki bağlantı:
  - `safari` `setup.xbox.browser` (hiçbir şey yüklemeden web üzerinden denemeyi öneren bağlantı): tarayıcıda
    `https://www.xbox.com/play/consoles` açılır.
  - `setup.welcome.captureCard` (PS5 karşılamasındakiyle aynı bağlantı ve davranış).
- Devam'a basılınca PS5 adımları atlanır: konsol Xbox, görüntü kaynağı oyun penceresi, doğrudan **TV adımı**.
  TV adımından Geri'ye basılırsa yine buraya dönülür (PS5 adımlarına düşmez).

---

## 4. Adım 2: Ek PSN hesabı

- Başlık `setup.account.title` (altyazıyı okumak için ayrı bir PSN hesabı gerektiğini söyleyen başlık).
- Açıklama `setup.account.message` (Nino'nun bu ayrı hesapla Remote Play üzerinden oyunu izlediğini; oyuncunun kendi hesabı kullanılsa konsolun kolu devreden çıkaracağını; ayarın bir defalık olduğunu anlatır).
- Dört numaralı satır (aralık 12):
  1. `setup.account.step1` (playstation.com üzerinde farklı bir e-postayla parasız bir hesap oluşturma adımı)
  2. `setup.account.step2` (konsola yeni kullanıcı ekleyip o hesapla bir defa oturum açma adımı)
  3. `setup.account.step3` (yeni kullanıcıdan çıkmadan PS5 menüsünde Uzaktan Oynama ayarına girip uzaktan oynamayı etkinleştirme ve listenin sonundaki bağlantı durumunu gizleme seçeneğini açma adımı) Amaç: PS5'in oyunun üstünde Remote Play bildirimi göstermemesi.
  4. `setup.account.step4` (asıl kullanıcıya geri dönüp PS5'in bildirim ayarından uyarıları susturma adımı; amaç yazıların üstüne açılır kutu düşmemesi)
- İpucu: `setup.account.mainAccountHint` (kol açılırken konsolda asıl hesabın seçilmesi gerektiğini, Nino'ya ayrılan hesapla oynanırsa kolun oyunda tepki vermeyeceğini anlatan uyarı; "ana" sözcüğü büyük harfle vurgulanır)
- Altta bir cam kart:
  - Satır: `setup.account.window.title` (ek hesap olmadan, ekranda açık duran Remote Play penceresinden okumayı öneren satır) (gövde
    yarı kalın) ve sağda ikincil `setup.account.window.select` (Select / Seç).
  - İpucu: `setup.account.window.hint` (yazıların Mac'te çalışan iki programdan birinin (PS Remote Play, chiaki-ng) penceresinden alındığını; ek hesap ve konsol eşleştirmesi istemediğini; televizyonun ileride eklenebileceğini anlatan not)
  - İki program da yüklü bulunmazsa: `setup.account.window.missing` (bilgisayarda iki programın da olmadığını söyleyen satır) ve iki ikincil düğme
    `setup.account.window.getRemotePlay` (Sony'nin Remote Play programının indirme sayfasını açan düğme)
    (`https://remoteplay.dl.playstation.net/remoteplay/`), `setup.account.window.getChiaki` (chiaki-ng indirme düğmesi)
    (`https://github.com/chiaki-ng/chiaki-ng/releases/latest`). Kurulu mu sorusu paket kimliğine bakar:
    `com.playstation.RemotePlay`, `org.streetpea.chiaking`.
  - **Seç**'e basılınca: konsol PS5, görüntü kaynağı oyun penceresi; TV eşleşmemişse çıktı bilgisayar ekranı;
    sihirbaz **biter**.
- Devam her zaman açık.

## 5. Adım 3: İkinci hesapla PSN girişi

- Başlık `setup.psn.title` (ek hesapla oturum açmayı isteyen başlık).
- Açıklama `setup.psn.message` (yeni açılan ek hesapla PSN'e girilmesini; okumanın o hesapla yapıldığını ve yalnız kimlik numarasının tutulduğunu anlatır).
- İçerik ortalı, aralık 16.

### Giriş yapılmamışken
- En çok 520 genişlikte cam karo (iç 16), üç güvence satırı, aralarında %40 saydam ayraç. Her satırda 26 genişlikte
  17 pt yarı kalın accentText simge ve gövde yazısı:
  - `lock.shield.fill` `setup.psn.assure.password` (parolanın yalnız Sony sayfasına girildiğini, Nino'nun onu hiç görmediğini anlatır)
  - `person.text.rectangle.fill` `setup.psn.assure.idOnly` (kimlik numarası dışında hiçbir bilgi tutulmadığını anlatır)
  - `checkmark.seal.fill` `setup.psn.assure.once` (girişin bir defalık olduğunu, yeniden istenmeyeceğini anlatır)
- Büyük birincil düğme (44, en az 260): `person.crop.circle.fill` `setup.psn.signIn` (PlayStation hesabıyla giriş düğmesi). İşlem sürerken kapalı; altında küçük dönen gösterge.
- Altında hata metni (seçilebilir).
- Altında elle giriş bağlantısı: `setup.psn.manual.open` (Sony sayfası gelmezse kimliği elle yazmayı öneren bağlantı) (açıklama yarı kalın, accentText). Basılınca yerine:
  - İpucu: `setup.psn.manual.hint` (Sony sayfası gelmediğinde (kimi servis sağlayıcıları onu engeller) ek hesabın kimliğinin base64 biçiminde, 12 karakter olarak yazılmasını ister ve bir örnek verir)
  - En çok 240 genişlikte boş alan + birincil `setup.psn.manual.save` (Save / Kaydet) (Return da kaydeder).
  - Kural: boşluklar atılır; tam 12 karakter olmalı ve base64 çözümü tam 8 bayt vermeli. Olmazsa:
    `setup.psn.manual.invalid` (yazılanın kimlik olmadığını, 12 karakterlik base64 beklendiğini örnekle söyleyen hata). Olursa web girişiyle aynı biçimde saklanır ve ekran "giriş yapıldı" hâline geçer.

### Giriş yapılmışken
- En çok 520 genişlikte karo (iç 16): solda 44 pt `person.crop.circle.badge.checkmark` degrade simge; ortada
  `setup.psn.signedIn` (Signed in / Giriş yapıldı) (manşet, success) ve altında `setup.psn.accountID` (PSN account ID / PSN hesap kimliği) + ": " + maskeli kimlik (açıklama eş
  aralıklı, textSecondary). Maske: base64 metnin ilk 4 ve son 4 karakteri, arada "••••" (8 karakterden kısaysa olduğu
  gibi). Sağda tehlikeli `setup.psn.signOut` (Sign Out / Çıkış Yap): yalnız hesap kimliği silinir.
- Başka düğme yok. Devam yalnız hesap kimliği varken açık.

### Giriş penceresi
- Sayfa üstünde açılan 520×680 pencere: üstte PlayStation Network adı (manşet, çevrilmez, metin anahtarı yok) ve sağda
  ikincil `console.psn.cancel` (Cancel / Vazgeç) (iç 12), ayraç, altında gömülü tarayıcı.
- Tarayıcı **kalıcı olmayan** veri deposuyla açılır (çerez ya da oturum saklanmaz; her giriş temiz başlar).
- Açılan adres: `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize` ve şu sorgu alanları:
  `service_entity=urn:service-entity:psn`, `response_type=code`, `client_id` (Remote Play istemcisinin herkesçe bilinen
  kimliği), `redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect`, `scope=psn:clientapp
  referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect
  sessionManager:remotePlaySession.system.update`, `request_locale=en_US`, `ui=pr`, `service_logo=ps`,
  `layout_type=popup`, `smcid=remoteplay`, `prompt=always`, `PlatformPrivacyWs1=minimal`.
- İstemci bilgileri, kaynağı herkese açık olan chiaki-ng programının PSN hesap kimliği akışındakilerle aynıdır
  (`gui/src/psnaccountid.cpp`): `client_id` = `ba495a24-818c-472b-b12d-ff231c1b5745`, gizli anahtar = `mvaiZkRsAsI1IBkY`.
- Tarayıcı her gezinmede adrese bakar. Adres yönlendirme önekiyle başlıyor ve içinde `code` **ya da** `error` alanı
  varsa: gezinme iptal edilir, adres yakalanır (yalnız bir kez), pencere kapanır, çözümleme başlar.
- Ana çerçeve yanıtı HTTP 400 ve üstüyse "sayfa sorunu" olarak "HTTP <kod>" saklanır (günlüğe de yazılır); başarılı
  yanıt sorunu temizler. Sayfa yüklenemezse sistemin hata metni saklanır; bizim iptalimizden doğan hatalar (iptal,
  "çerçeve yüklemesi politika yüzünden kesildi") sayılmaz.

### Hesap kimliğini çıkarma (davranış)
1. Yönlendirmede `code` doluysa: kod, `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token` adresine POST
   ile gönderilir: `grant_type=authorization_code`, `code`, aynı `scope`, aynı `redirect_uri`; istemci kimliği ve
   gizli anahtarı Basic yetkilendirme başlığında. İstek çerezsiz, önbelleksiz, 30 sn zaman aşımlıdır.
2. Yanıttaki `access_token` alınır; aynı token adresine token yol olarak eklenip GET yapılır
   (`…/oauth/token/<access_token>`, yine Basic başlıkla).
3. Bu yanıttaki `user_id` (ondalık metin) 64 bit sayıya çevrilir ve **8 baytlık little-endian** dizisi olarak
   saklanır. Hesap kimliği budur. Token hiçbir yerde saklanmaz.
4. Saklama: Anahtarlık'ta "hesap kimliği" kaydı olarak; ekranda base64 hâli maskeli gösterilir.

Yönlendirmede `error` varsa metin `error` alanının değeri, iki nokta, `error_description` ve parantez içinde `error_code` olarak birleştirilir (Sony açıklamadaki
boşlukları "+" yazar, boşluğa çevrilir).

### Hatalar ve iletileri
Her iletinin sonuna şu eklenir (ayrıntı varsa önce parantez içinde ayrıntı): `console.error.sendLog` (sorun sürerse `%@` ile gösterilen dosyanın bize yollanmasını isteyen ek cümle) (`%@` Remote
Play günlüğünün yoludur).

| Durum | Anahtar (anlamı) |
|---|---|
| Yönlendirmede ne kod ne hata | `console.psn.error.incomplete` (giriş yarım kaldı, bir daha denensin) |
| Sony reddetti (yönlendirmede hata ya da token isteği 400/401/403) | `console.psn.error.rejected` (Sony oturumu sonlandırmadı; bir dakika beklenip ek hesapla yeniden denensin) |
| Çok fazla deneme (HTTP 429 ya da metinde "too many", "too_many", "rate limit") | `console.psn.error.tooManyAttempts` (art arda çok deneme yapıldı; yeni giriş için yaklaşık 15 dakika beklensin) |
| Başka HTTP hatası | `console.psn.error.server` (Sony tarafı hata döndü; biraz beklenip yeniden denensin) |
| Ağ hatası | `console.psn.error.network` (Sony'ye erişilemedi; internet denetlenip yeniden denensin) |
| Yanıt okunamadı (JSON değil, `user_id` yok) | `console.psn.error.unreadable` (Sony'nin yanıtı çözülemedi; tekrar denensin, sürerse Nino güncellensin) |
| Pencere yönlendirme yakalanmadan kapandı, sayfa sorunu yok | `console.psn.error.windowClosed` (pencere iş bitmeden kapandı; yeniden başlatılıp yeni pencerede tamamlansın) (bu iletide dosya eki yok) |
| Pencere kapandı, sayfa sorunu vardı | Sorun metninde "429" varsa "çok fazla deneme" iletisi, yoksa `console.psn.error.pageFailed` (Sony sayfası yüklenmedi; internet denetlenip yeniden denensin) |

Ayrıntı: HTTP kodu ("HTTP 401") ve Sony'nin hata metni virgülle birleştirilir. Sony JSON vermediyse yanıt gövdesinin
ilk 200 karakteri ayrıntı olur. Her sonuç Remote Play günlüğüne yazılır (girişin tamamlandığı ya da neden başarısız
olduğu).

## 6. Adım 4: PS5'i bağla (eşleştirme)

- Başlık `setup.ps5.title` (konsolu bağlamayı isteyen başlık). Açıklama `setup.ps5.message` (konsolun gösterdiği sekiz rakamlı kodun girilmesini ister).
- Adım açılınca PS5 araması hemen başlar.

### Eşli PS5 varken (ve yeniden eşleme istenmediyse)
- Tek karo (iç 16): 44 pt `checkmark` degrade simge; `setup.ps5.paired` (PS5 paired / PS5 eşlendi) (manşet, success) ve altında
  "<ad> · <adres>" (ad boşsa konsolun adı); sağda ikincil `setup.ps5.pairAgain` (Pair Again / Yeniden Eşle) (aşağıdaki formu açar).

### Form (yukarıdan aşağı, ortalı, aralık 16)
1. **Hesap yoksa uyarı şeridi:** warning %10 zeminli, köşe 14, iç 12: 20 pt warning
   `person.crop.circle.badge.exclamationmark`, `setup.ps5.needAccount` (önce ek hesapla oturum açılmasını isteyen uyarı) (açıklama yarı kalın), sağda birincil `setup.ps5.needAccount.signIn` (Sign In / Giriş Yap) (PSN adımına
   gider).
2. **Üç adım kartı** yan yana (aralık 12, her biri en az 130, iç 12): üstte solda 36 pt degrade simge, sağda 22 kalın
   yuvarlak numara (textSecondary %60); altında başlık (manşet) ve yol (açıklama, textSecondary). Son eşleştirme hata
   verdiyse üç kartın çevresinde warning %80 1,5 pt kenar.
   - 1 `person.2.fill` `setup.ps5.step1.title` (konsolda ek kullanıcıya geçilmesini söyleyen başlık) /
     `setup.ps5.step1.path` (PS5'te kullanıcı değiştirmenin yolu: PS tuşu, sonra profil görseli, sonra kullanıcı değiştir)
   - 2 `gearshape.fill` `setup.ps5.step2.title` (konsolun eşleştirme ekranını açmayı söyleyen başlık) / `setup.ps5.step2.path` (o ekrana giden PS5 menü yolu: sistem ayarlarından uzaktan oynama bölümüne, oradan eşleştirmeye)
   - 3 `number` `setup.ps5.step3.title` (Enter the code / Kodu yazın) / `setup.ps5.step3.path` (kodun alttaki kutulara girilmesini ve 5 dakika işe yaradığını söyler)
3. **PS5 durum hapı:** açıklama yarı kalın; yatay 16, dikey 8; zemin beyaz %6, ince cam kenar. Hâller:
   - Aranıyor: küçük dönen gösterge + `setup.ps5.searching` (PS5'in arandığını söyleyen durum; TR: PS5'iniz aranıyor…) (textSecondary).
   - Birden çok bulundu: yeşil `checkmark.circle.fill` + açılır seçici ("<ad> — <adres>"); ilk bulunan seçili gelir.
   - Bir tane: yeşil işaret + `setup.ps5.found %@` (%@ found / %@ bulundu).
   - Hiç yok: warning `exclamationmark.circle.fill` + `setup.ps5.notFound` (PS5 not found / PS5 bulunamadı), yanında bağlantı
     `setup.ps5.useIP` (IP adresiyle bağlanmayı öneren bağlantı; EN: Connect with an IP address). Basılınca aynı hapın içinde 230×30 alan açılır:
     yer tutucu `setup.ps5.ipPlaceholder` (örnek bir IP adresi gösteren yer tutucu); Return bağlanır. (Kod kutuları ve
     düğme yerinden oynamaz.)
   - Arama bitince sonda "·" ve `setup.ps5.searchAgain` (Search again / Yeniden ara) bağlantısı.
   - Hiç bulunamadıysa hapın ipucu: `setup.ps5.notFound.help` (konsol çıkmadı; açık olup bu ağda bulunduğu denetlensin ya da adresi elle yazılsın; ayrıca macOS'un Yerel Ağ izninde Nino'ya onay verilmiş olmalı)
4. **8 kutulu kod** (telefon doğrulama kodu gibi): kutu 44×56, köşe 12, aralık 8; dördüncü kutudan sonra "–"
   (textSecondary). Rakam 26 yarı kalın yuvarlak eş genişlikli. Kutu zemini textSecondary %10, kenar textSecondary %45
   1,5 pt; sıradaki kutu (alan odaktayken) accent 2 pt. Açık temada da kutular görünmeli. Sağdan sola dillerde de
   soldan sağa dizilir.
   - Kutuların üstünde görünmez bir metin alanı durur (tıklanınca odak ona geçer; adım açılınca odaklıdır).
     Erişilebilirlik adı `setup.ps5.codeLabel` (8-digit code / 8 haneli kod). Yalnız rakam kabul edilir, en çok 8 hane. Yeni rakam
     yazılınca önceki hata ve "eşlendi" durumu temizlenir. Return bağlanır.
5. **Bağlan** (birincil, 44, en az 220): `setup.ps5.connect` (Connect / Bağlan). Açık olması için: çalışmıyor, az önce eşleşmemiş,
   8 hane yazılmış, hesap kimliği var, adres (seçili PS5 ya da yazılan IP) boş değil.
6. Çalışırken: küçük gösterge + `setup.ps5.connecting` (konsola bağlanma sürdüğünü ve yarım dakikaya dek uzayabileceğini söyleyen durum)
7. Başarıda düğmenin hemen altında bitti etiketi: `setup.ps5.success %@ %@` (PS5 paired: %1$@ (%2$@). Press Continue. / PS5 eşlendi: %1$@ (%2$@). Devam'a basın.) (ad, adres). Kod alanı temizlenir;
   görünüm bu iletiye kaydırılır (50 ms sonra), ~1 sn sonra kendiliğinden sonraki adıma geçilir. Kullanıcı bu arada
   Geri'ye bastıysa ya da adım değiştiyse geçilmez.
8. Hata metni (ortalı, seçilebilir); hata varsa altında ikincil `setup.ps5.showLog` (günlük dosyasını gösterme düğmesi; EN: Show Log File): Remote Play günlüğü Finder'da seçili açılır; dosya yoksa klasörü oluşturulup açılır.

### Eşleştirme (davranış)
- **PS5 araması:** yerel ağdaki her adrese tek tek (genel yayın değil) PS5 arama paketi gönderilir: UDP **9302**,
  protokol sürümü "00030010". 3 sn boyunca, 0,5 sn arayla tekrarlanır. Yalnız PS5 yanıtları alınır: adres, ad, uyanık
  mı (dinlenmede mi), çalışan oyun. Bulunanlar günlüğe yazılır (dinlenmede olanlar işaretlenir).
- **Yerel ağ izni tahmini:** doğrudan bağlı alt ağda en az 4 adres denendi, hiçbir gönderim kabul edilmedi, hepsi "No
  route to host" ya da "not permitted" ile düştü ve hiçbir PS5 yanıt vermediyse izin kapalı sayılır. Tek hata satırı
  işaret değildir.
- **Adres temizliği:** elle yazılan adres temizlenir ("192.168.1.5:9295", "http://…", virgüllü yazım). Adres değilse ya
  da 0.0.0.0, boş, yayın adresi gibi kullanılamaz bir adresse eşleştirme denenmez.
- **Kod okuma:** boşluk, "-", "–", ".", "_" atlanır; başka karakter varsa ya da 8 hane değilse geçersiz. Başka yazı
  sistemlerinin onluk rakamları da kabul edilir.
- **Kayıt:** hedef PS5, verilen adres, hesap kimliği (8 bayt değilse hata), 8 haneli kod. PS5 arama paketine hiç yanıt
  vermezse (kod PS5'e ulaşmadı) 0,5 sn arayla en çok 3 kez denenir; öbür hatalarda tekrar yok.
- **Başarı:** PS5'in verdiği ad, 16 baytlık kayıt anahtarı ve 16 baytlık oturum anahtarı alınır. Anahtarlardan biri
  tamamen sıfırsa başarı sayılmaz. Kayıt (adres, ad, iki anahtar) Anahtarlık'ta "PS5" kaydı olarak saklanır; günlüğe
  kaydın saklandığı yazılır.

| Neden | Anahtar (anlamı) |
|---|---|
| Adres boş | `console.pair.error.noAddress` (konsol bulunamadı; açıklığı ve ağı denetlensin ya da adres elle girilsin) |
| Adres geçersiz / çözülemedi | `console.pair.error.badAddress` (bu adreste konsol yok; doğru adresin PS5'in ağ ayarlarındaki bağlantı durumu sayfasında yazdığını söyler) |
| Kod 8 hane değil | `console.pair.error.badCode` (The code needs exactly 8 digits. / Kodun tam 8 rakamdan oluşması gerekiyor.) |
| Hesap yok | `console.pair.error.noAccount` (önce ek hesapla PSN girişi yapılmalı) |
| PS5 hesabı tanımadı | `console.pair.error.accountNotRecognised` (konsol bu hesabı bilmiyor; kod, Nino'daki hesabın açık olduğu kullanıcıdan alınsın ya da Nino'ya o kullanıcıya ait hesapla yeniden girilsin) |
| Kod hatalı ya da eskimiş | `console.pair.error.wrongCode` (kod hatalı ya da süresi geçmiş; eşleştirme ekranı yeniden açılıp taze kod girilsin) |
| PS5 yanıt vermedi | `console.pair.error.noAnswer` (konsoldan ses yok; uyku dışında açık, bu bilgisayarla tek ağda ve Remote Play'i etkin olduğu denetlenip yeniden denensin) |
| İsteği aldı, yanıt gecikti (ya da iptal) | `console.pair.error.lateAnswer` (istek ulaştı ama yanıt geç kaldı; eşleştirme ekranı yeniden açılıp taze kod girilsin) |
| Başka cihazda kullanımda | `console.pair.error.inUse` (Remote Play şu an başka cihazda; orada sonlandırılıp taze kod girilsin) |
| PS5 hizmeti çöktü | `console.pair.error.crashed` (konsoldaki Remote Play çöktü; konsol yeniden başlatılıp taze kod girilsin) |
| Sistem sürümü desteklenmiyor | `console.pair.error.unsupportedVersion` (bu konsol yazılımı sürümü henüz tanınmıyor; Nino'nun yenisi kurulup denensin) |
| macOS Yerel Ağ izni yok | `console.pair.error.localNetworkBlocked` (macOS, Nino'nun ev ağına erişimini kesmiş; macOS'un Yerel Ağ izninde onay verilip taze kod girilsin) |
| Sınıflanamayan | `console.pair.error.refused` (konsol kodu kabul etmedi; eşleştirme ekranı yeniden açılıp çıkan yeni kod yazılsın) |

Sınıflama: PS5'in bildirdiği nedene göre (hesap geçersiz, kayıt başarısız, kullanımda, sürüm, çöktü); neden yoksa
Remote Play kitaplığının hata satırlarına göre ("getaddrinfo" → adres; gönderim satırında "No route to host"/"not
permitted" → yerel ağ izni; arama/bağlantı satırları → yanıt yok; yanıt başlığı/içeriği satırları → yanıt gecikti).
İletilerin ardına ayrıntı (PS5'in kodu ya da ilk hata satırı) parantezle ve `console.error.sendLog` eki gelir. Devam
yalnız PS5 kaydı varken açık.

## 7. Adım 5: TV'yi bağla

- Başlık `setup.tv.title` (televizyonu bağlamayı isteyen başlık). Açıklama `setup.tv.message` (televizyonun açılmasını; bağlanırken bir defa çıkacak izin sorusunun kumandayla onaylanmasını; TV uygulaması yoksa bu ekranın yüklemeye yardım ettiğini anlatır)
- İçerik sola yaslı, aralık 16. Eşleşmiş TV varsa en üstte TV'nin adıyla bitti etiketi: `setup.tv.paired %@` (Connected to %@ / %@ bağlandı).
- TV yokken, aramada değilken ve bağlanmıyorken önce tür sorulur: `setup.tv.which` (televizyonun hangi türden olduğunu soran soru)
  (manşet) ve üç seçenek kartı:
  1. Android görseli (yoksa `tv.fill`): başlık iki platformun adı (Android ve Google'ın TV sistemleri, çevrilmez) /
     `setup.tv.android.detail` (Android tabanlı desteklenen markaları sayan açıklama; sayılanlar: TCL, iFFALCON, Sony, Philips, Vestel, Arçelik, Beko, Grundig, ardından "ve diğerleri"). Tıklanınca adı Android TV, adresi boş bir Android TV ile hemen eşleşilir.
     - Konsol Xbox değilse altında bağlantı: `photo.on.rectangle` `setup.tv.android.photoGuide` (Android TV kurulumunu resimlerle anlatan rehberi açan bağlantı)
       (`https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM-ANDROID-TV.md`), soldan 4.
  2. LG/Samsung görseli (yoksa `sparkles.tv.fill`): `setup.tv.lgSamsung` (iki markanın adını veren başlık) / `setup.tv.lgSamsung.detail` (webOS ile Tizen televizyonlarını ağda Nino'nun kendiliğinden bulduğunu söyleyen açıklama). Tıklanınca arama listesi açılır ve
     arama başlar.
  3. Mac görseli (yoksa `desktopcomputer`): `setup.tv.noTV` (televizyon olmadan yazıları bilgisayar ekranında göstermeyi öneren başlık). Açıklama konsola göre: Xbox `setup.tv.noTV.xbox` (oyunun bilgisayardaki Xbox penceresinde sürdüğünü, çevirinin orada belirdiğini, televizyonun ileride eklenebileceğini anlatan not); PS5 `setup.tv.noTV.ps5` (oyunun bilgisayarda Remote Play'le sürdüğünü, çevirinin o pencerede belirdiğini, televizyonun ileride eklenebileceğini anlatan not). Tıklanınca çıktı bilgisayar ekranı olur ve sonraki adıma geçilir.
- **LG/Samsung listesi** (cam kart): başlık satırı 32 pt `wifi` degrade simge + `setup.tv.list.title` (ağda bulunan iki marka televizyonun listelendiğini söyleyen başlık) (manşet) + arama sürerken gösterge + sağda ikincil
  `setup.tv.list.searchAgain` (Search Again / Yeniden Ara) (arama sürerken kapalı). Boşsa ipucu `setup.tv.list.empty` (iki markadan hiç televizyon çıkmadığını, açıklığının ve ağın denetlenmesini söyleyen not). Her TV için satır "<ad> — <adres>" ve
  sağda birincil `setup.tv.list.connect` (Connect / Bağlan) (bağlanırken kapalı). Kartın altında hayalet `chevron.left`
  `setup.tv.list.another` (tür seçimine geri dönme bağlantısı) (tür sorusuna döner).
- Bağlanırken gösterge + Samsung'da `setup.tv.connecting.samsung` (televizyondaki onay sorusunun kumandayla kabul edilmesini isteyen ve Nino'nun 60 saniye beklediğini belirten not); öbürlerinde `setup.tv.connecting` (TV'deki isteği onaylamayı söyleyen kısa not)
- Bağlantı hataları: Samsung reddetti → `setup.tv.error.samsungRefused` (televizyon bağlantıyı geri çevirdi; Samsung menüsündeki cihaz bağlantı yöneticisinin listesinde Nino'ya onay verilip yeniden bağlanılsın diyen hata); Samsung 60 sn'de onaylanmadı → `setup.tv.error.samsungNotAccepted` (onay sorusu 60 saniyede kabul görmedi; soru hiç belirmediyse televizyonun giriş ekranına dönülüp yeniden bağlanılsın; Nino daha önce geri çevrildiyse aynı Samsung cihaz listesinden onay verilsin); diğer her şey →
  `setup.tv.error.noResponse` (televizyondan yanıt gelmedi; açıklığı ve ağı denetlensin diyen hata)
- Hatanın altında **TV uygulaması kartı** (bkz. `tv-kurulumu.md` §5). Seçilen TV LG değilse ve uygulama paketi
  uygulamayla gelmediyse (geliştirici derlemesi) ayrıca: `setup.tvApp.title` (Nino TV app / Nino TV uygulaması) başlıklı kart, metin
  `setup.tv.guide.text` (TV uygulamasının kılavuzdaki adımlarla yüklenip başlatılmasını, sonra bu bilgisayarı kendiliğinden bulacağını söyleyen metin) ve bağlantı `setup.tv.guide.open` (Open the Guide / Rehberi Aç)
  (`https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM.md#5-tv-uygulamas%C4%B1n%C4%B1-kurma`).
- Adım açılınca: TV eşleşmiş ama uygulama durumu bilinmiyorsa (kurulum yarıda kalmış) uygulama yeniden denetlenir.
- Devam: eşleşmiş TV varsa ya da çıktı bilgisayar ekranıysa açık.

## 8. Adım 6: Deneyelim

- Başlık `setup.test.title` (deneme adımının başlığı). Açıklama çıktıya göre: bilgisayar `setup.test.message.computer` (bilgisayar ekranının alt kısmında bir deneme yazısı çıkacağını söyler); TV
  `setup.test.message.tv` (televizyona bir deneme yazısı yollanacağını, onun görüntünün alt kısmında belirmesi gerektiğini söyleyen açıklama)
- İçerik ortalı, aralık 16:
  - 400×225 TV önizlemesi (altyazı stili önizleme bileşeni), içinde canlı satır `setup.test.line` (kendisinin deneme amaçlı olduğunu söyleyip oyunun üzerinde seçilip seçilmediğini soran örnek satır). TV çıktısında sol üstte hap:
    7 pt nokta (TV uygulaması bağlıysa yeşil, değilse turuncu) + `setup.test.tvConnected` (TV connected / TV bağlı) /
    `setup.test.tvWaiting` (TV uygulamasının beklendiğini söyleyen durum) (11 yarı kalın beyaz), yükseklik 24, yatay
    10, siyah %45, kenardan 10.
  - Gönderilmeden önce büyük birincil düğme (44, en az 280): bilgisayar `setup.test.show` (deneme altyazısını bu ekranda gösterme düğmesi; EN: Show Test Subtitle), TV `setup.test.send` (deneme altyazısını TV'ye gönderme düğmesi). Gönderirken beyaz
    gösterge + `setup.test.showing` (Showing… / Gösteriliyor…) / `setup.test.openingTV` (televizyondaki uygulamanın başlatıldığını söyleyen durum); düğme
    kapalı.
  - Gönderildikten sonra: soru (manşet) `setup.test.question.computer` (altyazının ekranda görünüp görünmediğini soran soru) / `setup.test.question.tv` (altyazının TV'de görünüp görünmediğini soran soru), yanında ikincil 44
    `setup.test.no` (No / Hayır) ve birincil 44 `setup.test.yes` (olumlu yanıt düğmesi) (Return). Olumlu yanıt: altyazı penceresi ayarlama kapanır,
    sonraki adım.
  - Olumsuz yanıttan sonra: warning `lightbulb.fill` satırı: bilgisayar `setup.test.tip.computer` (deneme yazısının alt kısımda yalnız kısa bir süre durduğunu söyleyip tekrar yollamayı öneren ipucu); TV `setup.test.tip.tv` (televizyonun ve üstündeki Nino uygulamasının çalıştığı denetlenip tekrar yollanmasını öneren ipucu) ve TV'de yanında hayalet
    `setup.test.reconnect` (TV'yi yeniden bağlama düğmesi) (TV adımına döner).
  - Altında küçük bağlantı `arrow.clockwise` `setup.test.sendAgain` (Send again / Tekrar gönder) (gönderirken yukarıdaki gönderme metinleri).
  - Bilgisayar çıktısında en altta bağlantı `setup.test.adjust` (altyazı penceresinin yerini ayarlama bağlantısı; TR: Altyazı penceresini ayarla):
    altyazı penceresinin yer ayarlama kipini açar (açıkken kapalı).
- **Gönderme davranışı:** altyazı sunucusu kapalıysa açılır. TV'ye gidiyorsa ve hiç TV uygulaması bağlı değilse önce
  TV uygulaması açılır (Android TV'de kurulum/açma denetimi, LG/Samsung'da uygulamayı başlatma) ve 0,5 sn arayla en
  çok ~10 sn bağlanması beklenir. Sonra stil ve deneme satırı gönderilir: süre 8000 ms, kutu en son görülen altyazının
  yeri; yoksa yatayda %30–%70, altyazı bölgesinin altından 0,10 ile 0,03 yukarıda.
- Bu adımda Devam görünmez; ilerlemek `setup.test.yes` düğmesiyledir. Geri çalışır.

## 9. Adım 7: Gemini ile akıcı çeviri (parasız, isteğe bağlı)

- Başlık `setup.gemini.title` (parasız ama daha akıcı çeviri sunan adımın başlığı).
- Açıklama `setup.gemini.message` (parasız yerleşik çevirinin internetsiz çalıştığını ama sık sık kaskatı kaldığını; Gemini'nin çok daha akıcı olduğunu ve parasız bir Google anahtarının yettiğini; adımın atlanabileceğini anlatır)
- **Gemini hazır değilken** (motor Gemini değil ya da anahtar yok), tek cam karo (iç 16, aralık 12):
  - Üç sıkı adım satırı: 26 pt degrade daire, 13 kalın beyaz rakam, gövde yazısı:
    1. `setup.gemini.step1` (anahtar alma düğmesine basılıp Google hesabıyla girilmesini söyler)
    2. `setup.gemini.step2` (Google sayfasındaki "Create API key" düğmesine basıp çıkan anahtarın kopyalanmasını söyler)
    3. `setup.gemini.step3` (anahtarın alana yapıştırılıp kaydet-dene düğmesine basılmasını söyler)
  - Tek sıra (üstten 4, aralık 12): birincil `setup.gemini.getKey` (parasız anahtar alma düğmesi) (`https://aistudio.google.com/apikey`
    açılır), gizli alan `setup.gemini.keyField` (anahtar alanının etiketi), ikincil `setup.gemini.save` (Save and Test / Kaydet ve Dene) (denerken `setup.gemini.testing` (Testing… / Deneniyor…);
    denerken ya da alan boşken kapalı).
  - Kaydet: anahtar örnek bir satır çevrilerek denenir. Kabul edilince Gemini seçilir, alan boşalır. Hata olursa karo
    altında hata metni (çeviri ayarlarındaki anahtar hata metinleriyle aynı).
- **Gemini hazırken:** karo (iç 16): solda 40 pt `checkmark` + `setup.gemini.ready` (Gemini is ready / Gemini hazır) (20 kalın yuvarlak), altında
  `setup.gemini.ready.detail` (altyazıların artık Gemini ile çevrileceğini söyleyen not) (textSecondary). Sağda 300×169
  TV önizlemesi: deneme yapıldıysa Gemini'nin örnek çevirisi, yoksa akan örnek cümleler (`setup.gemini.sample1`,
  `setup.gemini.sample2`, `setup.gemini.sample3`).
- Altta üç kısa not (açıklama küçük, textSecondary, aralık 6):
  - `lock.fill` `setup.gemini.note.privacy` (Google'a yalnız oyunun altyazılarının gittiğini söyleyen not)
  - `gauge.with.dots.needle.33percent` `setup.gemini.note.limit` (parasız kota bitince yerleşik çevirinin işi üstlendiğini söyleyen not)
  - `slider.horizontal.3` `setup.gemini.note.others` (başka motorların — DeepL, OpenAI, Claude, kendi bilgisayarda çalışan model — ileride çeviri ayarlarından seçilebileceğini söyleyen not)
- Sağ alt düğme: Gemini hazır değilken `setup.skip`, hazırken `setup.continue`. İkisi de kurulumu bitirir (ana ekran).

---

## 10. Yakalama kartı rehberi

Hoş geldin'deki `setup.welcome.captureCard` bağlantısıyla açılır. Sihirbaz kartının yerini alır (aynı ölçüler: en çok
700, kaydırılan cam kart, dikeyde 24). Ayarlardan ayrı bir pencerede de açılır (o zaman yatay kenar 24). Üç sayfa;
sayfa geçişi sihirbazınkiyle aynı kayma.

**Alt sıra:** ortada 3 sayfa noktası (sihirbazınkiyle aynı), solda hayalet Geri (ayarlar penceresinde ilk sayfada
`xmark` `setup.card.cancel` (Cancel / Vazgeç)), sağda birincil (en az 120, Return) `setup.continue` (Continue / Devam), son sayfada `setup.card.done` (Done / Bitti).
İlk sayfada Geri rehberi kapatır; sihirbaz rehberi açan karşılamaya (PS5'inki ya da Xbox'ınki) döner.

**Başlangıç seçimi:** görüntü kaynağı zaten kart ve çıktı TV ise akıllı TV seçeneği seçili gelir, değilse monitör
seçeneği.

1. **Bağlantı** (simge `cable.connector`): `setup.card.connect.title` (konsolun hangi düzenle bağlandığını soran başlık) /
   `setup.card.connect.message` (kartın konsol görüntüsünü HDMI'dan alıp USB'yle bilgisayara aktardığını; ek hesap ve Remote Play istemediğini anlatır) İki seçenek (aralık 12), her biri karo (iç 16; seçiliyse 1,5 pt accent kenar): solda
   22 pt `checkmark.circle.fill` (accent) ya da `circle` (textSecondary); başlık, açıklama ve kablo şeması (36×30
   accentSoft kutularda 16 pt simgeler, aralarında küçük sağ ok).
   - `setup.card.monitor` (monitör ya da üstüne uygulama yüklenemeyen televizyon seçeneği) / `setup.card.monitor.detail` (oyunun sesiyle birlikte bilgisayarda bütün ekranı kapladığını, çevirinin üstte durduğunu, bilgisayarın ekrana HDMI kablosuyla bağlanacağını anlatan açıklama) Şema: kol → kablo → dizüstü → ekran.
   - `setup.card.tv` (üstünde Nino uygulaması olan akıllı televizyon seçeneği) / `setup.card.tv.detail` (görüntüyü dışarı da veren (passthrough) bir kart gerektiğini; oyunun beklemesiz televizyona aktığını; Nino'nun kartı okuyup çeviriyi televizyondaki uygulamaya yolladığını anlatan açıklama) Şema: kol → kablo → TV.
2. **HDCP** (simge `lock.open.fill`): `setup.card.hdcp.title` (konsolda HDCP korumasının devreden çıkarılmasını isteyen başlık) /
   `setup.card.hdcp.message` (HDCP adlı korumanın kartları durdurduğunu, oyunlara dokunmadığını, işin bir defalık olduğunu anlatan açıklama) Üç numaralı satır (aralık 16):
   1. `setup.card.hdcp.step1` (konsolun kısa süre için kartsız, doğrudan bir ekrana takılmasını isteyen adım; çünkü bu ayar kart aradayken değişmez)
   2. `setup.card.hdcp.step2` (PS5'te HDMI ayarlarını açmayı söyleyen adım)
   3. `setup.card.hdcp.step3` (HDCP'yi kapatıp PS5'i kartın HDMI girişine bağlamayı söyleyen adım)
   - İki not (açıklama, textSecondary): `info.circle` `setup.card.hdcp.netflix` (koruma kapalıyken Netflix türü dizi-film uygulamalarının konsolda açılmadığını, izlemek için korumanın geri açılacağını söyleyen not); `headphones`
     `setup.card.hdcp.headset` (kola kulaklık bağlıysa sesin oraya aktığını, kartın sessiz kaldığını söyleyen not)
3. **Takma ve deneme** (simge `checkmark.seal.fill`): `setup.card.plug.title` (kartın bağlanmasını isteyen başlık) / TV
   seçiliyse `setup.card.plug.tv` (kablo şeması: konsol → kartın HDMI girişi; kartın HDMI çıkışı → televizyon; kartın USB'si → bilgisayar); değilse `setup.card.plug.monitor` (kablo şeması: konsol → kartın HDMI girişi; kartın USB'si → bilgisayar; bilgisayar → ekran) İçerik: kart denetimi (aşağıda).

**Bitti:** görüntü kaynağı kart olur; çıktı, seçime göre TV veya bilgisayar. Sihirbazdan açıldıysa rehber kapanır; TV seçildi ve
TV eşleşmemişse TV adımına, değilse doğrudan Deneme adımına geçilir. Ayarlardan açıldıysa yalnız seçim kaydedilir ve
pencere kapanır.

### Kart denetimi (rehberin son sayfası ve ayarlar)
- 220 yükseklikte, köşe 14 canlı önizleme (siyah zemin, görüntü oranı korunur). Görüntü açıkken kart kısa süre açılır,
  kapanınca bırakılır; çeviri sürerken açılmaz. Aygıt takılıp çıkarılınca liste yenilenir.
- Görüntü yokken ortada 30 pt simge (izin yoksa `lock.fill`, değilse `cable.connector`) ve manşet: izin yok
  `setup.card.check.cameraNeeded` (kamera izni gerektiğini söyleyen başlık; TR: Kamera izni gerekli); kart yok ya da başlamadı
  `setup.card.check.looking` (kartın arandığını söyleyen durum) (beyaz %85).
- Sol üstte hap (11 yarı kalın beyaz, 24 yükseklik, siyah %50): 7 pt nokta (çalışıyorsa yeşil, durmuşsa gri, değilse
  turuncu) ve kartın adı / `setup.card.check.noCard` (kart bulunamadığını söyleyen etiket; EN: No card found) /
  `setup.card.check.searching` (Searching… / Aranıyor…) / `setup.card.check.noPermission` (No permission / İzin yok).
- Altında durum satırı (açıklama; iyi ise success `checkmark.circle.fill`, değilse warning
  `exclamationmark.triangle.fill`):
  - Çalışıyor: `setup.card.check.working` (kartın işlediğini, konsol görüntüsünün ulaştığını söyleyen durum)
  - Siyah: `setup.card.check.black` (kartın bağlı ama görüntünün siyah olduğunu, PS5'i açıp HDCP'yi kapatmayı (önceki adım) söyleyen durum)
  - İzin yok: `setup.card.check.permission` (macOS'un kartları kamera saydığını; macOS'un Kamera izninde Nino'ya onay verilip uygulamanın yeniden başlatılmasını söyleyen durum) ve ikincil
    `setup.card.check.openSettings` (kamera ayarlarını açan düğme)
    (`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`).
  - Kart yok: `setup.card.check.plugIn` (kartın bilgisayardaki USB 3 yuvasına takılmasını, araya çoklayıcı girdiyse doğrudan bilgisayarın yuvasının denenmesini söyleyen durum)
- Birden çok görüntü aygıtı varsa seçici `setup.card.check.device` (Capture device / Capture Card): `setup.card.check.automatic` (Automatic / Otomatik) + aygıt
  adları. Seçim saklanır ve önizleme hemen o aygıta geçer.

## 11. Xbox bağlantı listesi

Hoş geldin'in Xbox hâlinde ve ana ekrandan açılan Xbox bağlama penceresinde aynı liste. Dört satır (aralık 8);
yalnız sıradaki adımın düğmesi görünür. Liste görünürken Xbox durumu saniyede bir yoklanır (iç içe açılan görünümler
sayılır; sonuncusu kapanınca durur). Satır geçişleri yaylı (0,45 sn, sönüm 0,85).

**Satır:** cam karo (iç 12). Birinci satır her zaman "elle" satırıdır: gri rozet (textSecondary %18 daire, gri
numara), tam opaklık, accentText simge, kenarsız, açıklama görünür, düğme yok. Öbür satırlar: Solda 26 pt rozet: bitti → success daire + beyaz 13 kalın `checkmark`; sıradaki → accent
daire + beyaz numara; sonraki → textSecondary %18 daire + gri numara. Ortada simge (sonrakilerde gri, değilse
accentText) + başlık (manşet); bitmemişse açıklama (textSecondary); sıradakiyse altında düğme(ler) (üstten 4).
Sıradaki satırın çevresinde accent %70 1,5 pt kenar (köşe 16); sonraki satırlar %55 saydam.

1. `antenna.radiowaves.left.and.right` (elle): `setup.xboxList.remote` (konsolda uzaktan erişimin açılmasını söyleyen başlık) / `setup.xboxList.remote.detail` (Xbox menüsündeki ilgili ayarın yolunu verir ve Xbox uygulamasının tercihlerinde bütün cihazlara bağlantı izni verilmesini söyler)
2. `arrow.down.app.fill` kurulum: başlık kuruluysa `setup.xboxList.install.done` (Greenlight'ın yüklü olduğunu bildiren başlık), değilse `setup.xboxList.install` (Greenlight'ı yükleme başlığı/düğmesi) / `setup.xboxList.install.detail` (Greenlight'ı macOS için parasız bir Xbox istemcisi diye tanıtır; görüntüsü en keskin olduğundan yazıların en sağlam onunla okunduğunu söyler)
   Düğme: birincil `arrow.down.circle.fill` `setup.xboxList.install`, altında küçük not
   `setup.xboxList.install.note` (indirmenin yaklaşık 220 MB olduğunu, Nino'nun indirip Uygulamalar'a koyup açtığını söyleyen not) (hata varsa not yerine danger renkli hata). Kurulurken düğme yerine en çok 320 genişlikte ilerleme
   çubuğu ve `setup.xboxList.installing %lld` (Greenlight'ın kurulduğunu yüzdesiyle söyleyen durum; eş genişlikli rakam, Türkçede yüzde işareti önde).
3. `person.crop.circle.badge.checkmark` giriş: `setup.xboxList.signIn.done` (Microsoft hesabıyla girildiğini söyleyen başlık) / `setup.xboxList.signIn` (Microsoft hesabıyla girmeyi söyleyen başlık); açıklama
   `setup.xboxList.signIn.detail` (Greenlight'ın çıkardığı kodun, konsoldaki hesapla microsoft.com/link adresine girilip ardından Greenlight'ta onaylanacağını anlatan açıklama) Düğmeler: birincil `play.fill`
   `setup.xboxList.openGreenlight` (Greenlight'ı başlatma düğmesi), ikincil `arrow.up.right.square` `setup.xboxList.openLink` (microsoft.com/link sayfasını açan düğme) (`https://www.microsoft.com/link`).
4. `play.tv.fill` yayın: yayın açıksa `setup.xboxList.start.done` (konsol görüntüsünün artık bilgisayarda olduğunu bildiren başlık) / `setup.xboxList.start.doneDetail` (Nino'nun altyazıyı Greenlight penceresinden okuduğunu söyleyen not);
   değilse `setup.xboxList.start` (konsol yayınını başlatma başlığı) / `setup.xboxList.start.detail` (Greenlight'ta konsolun seçilip başlatılmasını; yükleme simgesi takılı kalırsa öteki Xbox yayınlarının kapatılıp macOS'un Yerel Ağ izninde Greenlight'a onay verilmesini anlatan açıklama)
   Düğme: birincil `arrow.right.circle.fill` `setup.xboxList.goToGreenlight` (Greenlight penceresine geçme düğmesi).

Hangi adımda olunduğu: yayın açıksa bitti; kurulu değilse kurulum; girişli değilse giriş; değilse yayın. Nasıl
anlaşıldığı `kaynaklar.md` §4'te.

**Ana ekrandaki pencere** (600×640, iç 24): üstte 40 pt `gamecontroller.fill` degrade simge + `setup.xbox.title`
(başlık) ve altında Nino'nun her adımı kendisi denetleyip sıradakine geçtiğini söyleyen tek cümle (`setup.xbox.message`
metninin ilk cümlesi); ortada kaydırılan liste; altta bitince solda success renkli, bağlantının tamam olduğunu söyleyen
etiket (manşet), sağda bitince birincil bitirme düğmesi, değilse ikincil kapatma düğmesi (Return). Bu pencere yeni
uygulamada henüz yok; bu üç kısa metnin kendi anahtarı da yok.

**Ana ekran düğmesi:** görüntü Xbox penceresinden okunuyorsa ve bağlantı bitmediyse büyük birincil düğme (en az 220):
yayın adımındaysa `home.xbox.start` (Start your Xbox / Xbox'ınızı açın), değilse `home.xbox.connect` (Connect your Xbox / Xbox'ı bağla). Pencereyi açar.

## 12. Gezinme kuralları (özet)

| Adım | Devam açık mı | Devam / Geri |
|---|---|---|
| Hoş geldin, konsol seçilmemiş | düğme yok | kart tıklanınca karşılama |
| Hoş geldin, PS5 | evet | İkinci hesap / konsol seçimine |
| Hoş geldin, Xbox | evet | TV adımı (Xbox ayarlarıyla) / konsol seçimine |
| İkinci hesap | evet | PSN girişi / Hoş geldin |
| PSN girişi | hesap kimliği varsa | PS5 / İkinci hesap |
| PS5 | PS5 kaydı varsa (eşleşince ~1 sn'de kendiliğinden) | TV / PSN girişi |
| TV | TV eşleşmiş ya da çıktı bilgisayar | Deneme / PS5 (Xbox yolunda Hoş geldin) |
| Deneme | Devam yok; `setup.test.yes` | Daha iyi çeviri / TV |
| Daha iyi çeviri | her zaman (`setup.skip` ya da `setup.continue`) | biter / Deneme |

Kısa yollar sihirbazı hemen bitirir: Hoş geldin'deki `setup.welcome.thisComputer` bağlantısı ve İkinci hesap
adımındaki `setup.account.window.select` düğmesi.
Geliştirici derlemesinde bir başlatma bayrağıyla tasarım denemesi için her adımda Devam açılabilir (giriş ve eşleşme
beklenmez); yayın sürümünde yoktur.
