# Mac: görüntü kaynakları (PS5 Remote Play, yakalama kartı, Xbox, oyun penceresi)

Bu belge yeni Mac uygulaması için bir **tarif**tir: oyun görüntüsünün nereden ve nasıl alındığını, hangi durumların
kullanıcıya nasıl söylendiğini anlatır. Kod içermez. Metinler yeni uygulamanın anahtarlarıyla
verilir: anahtarlar noktalı adlardır (ör. `settings.done`) ve alanlarına göre ayrı xcstrings dosyalarında durur (Home,
Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport); anahtarın yanında metnin ne dediği kısaca anlatılır.
Kaynakların kurulumdaki seçimi `kurulum.md`'de.

## 0. Ortak sözleşme

- Dört kaynak vardır; ayarda iki alan belirler: **görüntü kaynağı** (Remote Play ile doğrudan PS5, bu Mac'teki oyun
  penceresi ya da yakalama kartı; ayar dosyasındaki saklı değerleri veri uyumu belgesindedir) ve **konsol** (PS5 veya Xbox). Xbox her zaman oyun penceresi
  (Greenlight ya da tarayıcı) ya da yakalama kartı ile çalışır; Xbox'a doğrudan bağlanma yoktur.
- Her kaynak okuma hattına aynı arayüzle kare verir: tam renkli bir resim, hat farkı bilmez. Kaynak üç durum bildirir:
  **bağlanıyor**, **akıyor**, **bağlı değil (neden)**. Kart ve pencere kaynakları ayrıca kendi ayrıntılı durumlarını
  bildirir (ana ekranın metni bunlardan gelir).
- Kare hızı: okuma hattı bir önceki kare bitmeden yenisini almaz; kaynaklar saniyede 10 civarı verir (PS5 en çok 20).
- Çeviri başlatılabilir mi:
  - PS5 oyun penceresi: her zaman (altyazı bu Mac'te pencerenin üstünde).
  - Öbürleri: kaynak hazır (pencere/kart seçili ya da PS5 kaydı **ve** hesap kimliği var) **ve** altyazının gideceği
    yer var (bilgisayar ekranı seçili ya da TV eşleşmiş).
- Altyazı nereye gider:
  - **Bilgisayar ekranında:** PS5 oyun penceresinde her zaman; değilse çıktı ayarı bilgisayarsa.
  - **TV'ye:** PS5 oyun penceresinde hiçbir zaman (oyun bu Mac'te oynanıyor); değilse çıktı ayarı TV ise.
- Çeviri başlarken: sistem uykusu engellenir (ayara göre ekran uykusu da), Mac uykudan uyanınca kaynağa "hemen yeniden
  bağlan" ve TV bekçisine "yeniden bağlan" denir. Kaynak değişirse ve çeviri sürüyorsa durdurulup yeni kaynakla yeniden
  başlatılır.
- Bağlantı koptuğunda okuma hattı ve bölge izleyici sıfırlanır, TV'deki altyazı temizlenir, TV'ye "durdu" gönderilir.

---

## 1. PS5 Remote Play (doğrudan, ikinci hesapla)

Kurulumda eşleştirilen PS5'e (kayıt: adres, ad, iki 16 baytlık anahtar) ve ikinci hesabın 8 baytlık kimliğine
dayanır. Remote Play protokolü, kaynağı açık bir Remote Play kitaplığıyla konuşulur.

### Bağlanma
1. Durum "bağlanıyor".
2. Kayıtlı adres kullanılabilirse o adrese 2 sn'lik PS5 araması yapılır. Adres kullanılamazsa (eski kayıtlarda 0.0.0.0
   ya da boş) ya da yanıt yoksa bütün ağ taranır ve PS5 yeniden bulunmaya çalışılır: tek PS5 varsa odur, birden çoksa
   adı tek eşleşen; emin olunamazsa bulunamadı. Yeni adres bulunursa uygulamaya bildirilir ve saklanır (0.0.0.0 gibi
   geçersiz adres asla saklanmaz). Tüm ağ taraması pahalıdır; PS5 kapalıyken her denemede yapılmaz.
3. Adres hâlâ yoksa oturum açılmaz, "ağ" nedeniyle yeniden denenir.
4. PS5 dinlenmedeyse uyandırma paketi gönderilir (kayıt anahtarının onaltılık değeriyle); 2 sn arayla 2 sn'lik
   aramalarla en çok 20 sn uyanması beklenir. Uyanınca oturum açılır; uyanmazsa neden "PS5 kapalı" olur ve olağan
   yeniden deneme sırasına girilir (vazgeçilmez).
5. Oturum açılır: görüntü 1080p, 30 kare/sn istenir. Kol girdisi gönderilmez. Ses yalnız istenirse (geliştirici kaydı)
   alınır.
6. PS5 ikinci hesap için 4 haneli **giriş şifresi** isterse: Ayarlar'da kayıtlı geçerli şifre varsa ilk istekte
   gönderilir; yoksa ya da PS5 önceki şifreyi kabul etmediyse oturum kapatılır (yanlış şifreyle döngüye girilmez).
7. Her kare çözülür, resim saniyede en çok 20 kez üretilir.

### Yeniden bağlanma
- Kopunca (ya da oturum açılamayınca) bekleme: 2, 4, 8, 16, sonra hep 30 sn. Aralık ancak oturum 60 sn'den uzun sürüp kapandıysa baştan başlar
  (kısa süren oturumlarda büyümeye devam eder; PS5'te ikinci hesabın durmadan girip çıkmasını önler).
- "Başka cihazda kullanılıyor"da en az 8 sn (8, 16, 30).
- **Görüntü bekçisi:** bağlıyken 8 sn hiç kare gelmezse (bağlantı açık görünse de) oturum kapatılıp yeniden kurulur.
  Art arda 3 oturumda hiç kare gelmezse yeniden bağlanma bırakılır (neden "görüntü yok").
- **Vazgeçilen nedenler** (oturum durur, yeniden denenmez): kayıt geçersiz, PS5'te Remote Play kapalı, giriş şifresi
  gerekli ya da yanlış, art arda görüntüsüz oturum. Öbür bütün nedenlerde (PS5 kapalı, kullanımda, reddetti, ağ,
  bulunamadı, kodlu ret, diğer) yeniden denenir.
- Uygulamadan "hemen yeniden bağlan" gelince (uyanma, ağ değişimi) sayaçlar sıfırlanır, oturum baştan kurulur.

### Kopma nedenleri ve ana ekran metni
Ağ hatası ya da sınıflanamayan neden ve PS5 aramaya da yanıt vermediyse neden "kayıtlı adreste bulunamadı" olur.

| Neden | Anahtar | Ne der (EN ve TR aynı anlamda) |
|---|---|---|
| Akıyor | `home.status.connected` | bağlantının kurulu olduğunu söyleyen tek kelime |
| Bağlanıyor | `home.status.connecting` | bağlantının kurulmakta olduğunu söyler (yerel ağ izni yok gibi görünüyorsa yerine izin uyarısı) |
| Çeviri başlamadı, PS5 eşli | `home.status.paired %@` | `%@` adlı konsolla eşli olunduğunu, bağlantının çeviri başlayınca kurulacağını söyler |
| Çeviri başlamadı, PS5 yok | `home.status.notConnected` | henüz bağlantı olmadığını söyler |
| PS5 kapalı | `home.drop.asleep` | konsolun açılmasını ister |
| Başka cihazda | `home.drop.inUseElsewhere` | Remote Play'in o an başka bir aygıtta kullanıldığını söyler |
| Reddetti | `home.drop.refused` | konsolun bağlantıyı geri çevirdiğini söyleyip konsolun kurulumunun baştan yapılmasını ister |
| Şifre gerekli | `home.drop.passcodeRequired` | konsolun bu hesap için oturum şifresi beklediğini söyler; şifreyi Nino ayarlarına yazmayı ya da konsolda o hesabın şifresini kaldırmayı önerir |
| Şifre yanlış | `home.drop.passcodeWrong` | ayarlarda saklanan oturum şifresinin konsolca reddedildiğini söyler; şifreyi orada düzeltmeyi ya da konsolda o hesabın şifresini kaldırmayı önerir |
| Kayıt geçersiz (PS5 kodu 0x80108b09, 0x80108b02, 0x80108b26) | `home.drop.pairingInvalid` | eşlemenin artık geçmediğini söyler; Nino ayarlarından ikinci hesapla eşlemeyi tekrarlamayı ister |
| Remote Play kapalı (0x80108b12) | `home.drop.remotePlayDisabled` | konsolda Remote Play'in kapalı olduğunu söyler; konsolun kendi menüsündeki Remote Play açma anahtarını (EN: Settings › System › Remote Play; TR: Ayarlar › Sistem › Uzaktan Oynama) gösterip sonra çeviriyi tekrar başlatmayı ister |
| Görüntü yok | `home.drop.noPicture` | konsoldan kare gelmediğini söyler; Remote Play'in kapatılmış olup olmadığını ya da konsolun dinlenme kipinde olup olmadığını sorup bakıldıktan sonra tekrar başlatmayı ister |
| Adreste bulunamadı | `home.drop.notFound %@` | `%@` adresinde konsol bulunmadığını söyler; açık olup olmadığına ve Mac'in ağına bağlı durduğuna bakmayı ister, bağlantının yeniden denendiğini ekler |
| Ağ | `home.drop.network` | konsola ulaşılamadığını ve bağlantının yeniden denendiğini söyler |
| Oturum isteği reddedildi, kodlu (TCP 9295) | `home.drop.rejectedCode %@` | konsolun isteği `%@` ret koduyla geri çevirdiğini söyler; olası sebep olarak başka bir Remote Play programının (PS Remote Play) çalışıyor olmasını ya da konsolun başka bir oturumda olmasını sayar, o programı kapatıp konsolu yeniden başlatarak tekrar denemeyi ister (kod "0x%08x") |
| Oturum başlamadı, kodsuz | `home.drop.rejected` | konsolun oturumu açmadığını söyler; gerisi bir üstteki satırla aynı |
| Diğer, ayrıntılı | `home.drop.otherDetail %@` | bağlantının yeniden denendiğini söyleyip parantezde ayrıntıyı (`%@`) verir |
| Diğer | `home.drop.other` | bağlantının yeniden denendiğini söyler |


### Yerel ağ izni
- macOS izni doğrudan okutmaz; PS5 aramasındaki gönderim sonuçlarından tahmin edilir (`kurulum.md` §6: en az 4 yerel
  adres, hiçbiri kabul edilmedi, hepsi "No route to host"/"not permitted", hiçbir PS5 yanıt vermedi).
- Oturum işaret değişince bildirir; çeviri sürmüyorsa yok sayılır, PS5 akmaya başlayınca kalkar.
- İşaret varken "bağlanıyor", "bulunamadı", "ağ" ve "diğer" durumlarında metin şu uyarı olur: `home.warning.localNetwork`
  (Nino'nun yerel ağa erişemiyor olabileceğini söyler; macOS'un Yerel Ağ izin sayfasından izni verip uygulamayı kapatıp
  açmayı ister). Ayarlar adresi: `x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork`.

### Günlük
Remote Play günlüğüne (`remoteplay.log`) yazılanlar: arama sonuçları, gönderilemeyen paketlerin tek satırlık özeti
("N× <hata>…; yerel adres X, kabul edilen Y"), oturum başlangıcı ("<ad> <adres> uyanık / dinlenmede, uyandırılıyor"),
uyandırma hatası, adres değişikliği, kopma nedenleri. Altyazı günlüğüne yalnız tür ("PS5: bağlanıyor/bağlandı/bağlantı
yok").

---

## 2. Oyun penceresi (Mac üzerinde: PS Remote Play / chiaki-ng ya da Xbox penceresi)

Ekran yakalama çerçevesiyle (ScreenCaptureKit) yalnız seçilen pencere okunur; Nino'nun kendi altyazı penceresi asla
kareye girmez. PS5'e ikinci oturum açılmadığı için ikinci hesap gerekmez.

### Pencereyi bulma (1,5 sn'de bir)
- **İzin:** Ekran Kaydı izni yoksa macOS izin penceresi **bir kez** istenir; izin verilince Nino yeniden açılmalıdır.
  Durum "izin yok".
- Masaüstü dışı, katman 0 olan ve Nino'ya ait olmayan pencereler listelenir. PS5 yolunda yalnız ekranda olanlar;
  Xbox yolunda ekranda olmayanlar da (tarayıcı çoğu zaman ayrı masaüstünde tam ekrandır).
- **PS5 seçimi:** uygulama adı ya da paket kimliğinde "remote play", "remoteplay" ya da "chiaki" geçen, en az 320×180
  olan pencerelerden en büyüğü. (Geliştirici derlemesinde bir ayarla başka bir uygulama hedeflenebilir.)
- **Xbox seçimi**, sırayla:
  1. Greenlight'ın yayın penceresi (başlığı "Greenlight - <kelime> <konsol kimliği>"; §4), en büyüğü.
  2. Uygulama adı ya da paket kimliğinde "greenlight" geçen **herhangi bir** pencere **ya da** başlığında "xbox",
     "uzaktan oynama" veya "remote play" geçen bir tarayıcı penceresi; en büyüğü. Tarayıcı sayılan paket kimliği
     önekleri (küçük harf): `com.apple.safari`, `com.google.chrome`, `com.microsoft.edgemac`,
     `company.thebrowser.browser`, `org.mozilla.firefox`, `com.brave.browser`, `com.operasoftware.opera`,
     `com.vivaldi.vivaldi`.
  3. Ekranı kaplayan bir tarayıcı penceresi (yayın başlayınca sekme başlığı oyunun adı olabilir).
  Her yolda en az 320×180.
- **Tam ekran sayılma:** pencere bir ekranın sol kenarı, genişliği ve alt kenarıyla (±2) örtüşüyor ve yüksekliği ekranın
  %85'inden fazla (çentikli ekranlarda tam ekran pencere ekrandan kısa olabilir).
- Bulunamazsa durum "pencere aranıyor"; aday pencereler (tarayıcılar ve yeterince büyükler, en çok 12 tane, "uygulama
  "başlık" GxY tam ekran") yalnız liste değişince altyazı günlüğüne yazılır.

### Okuma
- **Oyun alanı:** Remote Play görüntüyü pencereye 16:9 sığdırıp ortalar. Alan piksellerden değil pencere ölçüsünden
  hesaplanır (karanlık sahnede siyah bant aramak yanılır): tam ekran değilse üstten başlık çubuğu kadar (28 pt, en çok
  pencere yüksekliğinin ¼'ü) düşülür; kalan alana sığan en büyük 16:9 dikdörtgen ortalanır.
- Yalnız bu alan okunur ve **1920×1080**'e ölçeklenir (PS5 kareleriyle aynı boy). İmleç ve ses yakalanmaz, kuyruk 3.
- Ekran yakalama görüntü değişmeyince kare göndermez; bu yüzden son kare saniyede 10 kez yeniden verilir (okuma hattı
  satırı bitirip kaldırabilsin). Yalnız "tamamlanmış" kareler alınır; kare kendi belleğine kopyalanır.
- Aynı pencere taşınır ya da büyürse akış kapatılmadan alan güncellenir; başka pencere seçilirse akış yeniden kurulur.
  Pencere kapanır ya da akış hata verirse yeniden aranır (çeviri durmaz).
- **Oyun alanının ekrandaki yeri** (sol üst başlangıç) uygulamaya bildirilir; bilgisayar ekranındaki altyazı penceresi
  bu alana oturur. Okuma bitince "alan yok" bildirilir.

### Ana ekran metni
| Durum | Anahtar | Ne der (EN ve TR aynı anlamda) |
|---|---|---|
| Durdu, Xbox | `home.window.idleXbox` | Xbox yayın penceresinin okunacağını söyleyen kısa satır |
| Durdu, PS5, Remote Play Mac'e kurulmamış | `home.window.appMissing` | Remote Play uygulamasının Mac'te bulunmadığını, Nino ayarlarındaki görüntü kaynağı bölümünden edinilebileceğini anlatır |
| Durdu, PS5 | `home.window.idle` | Mac'te çalışan Sony uygulamasının (PS Remote Play) penceresinin kullanılacağını söyleyen kısa satır |
| İzin yok | `home.window.screenRecordingDenied` | macOS'un Ekran Kaydı izin sayfasından Nino'ya izin verip uygulamayı tekrar açmayı ister |
| Aranıyor, Xbox | `home.window.searchingXbox` | yayının Greenlight'ta başlatılmasını ister; takılan için Xbox bağlama düğmesini gösterir |
| Aranıyor, PS5 | `home.window.searching` | PS Remote Play veya chiaki-ng açılıp bir oyunun başlatılmasını ister |
| Okunuyor | `home.reading %@` | `%@` (uygulama adı) okunduğunu söyler |

Altyazı günlüğüne: "görüntü kaynağı: oyun penceresi (Xbox: Greenlight / xbox.com/play | PS Remote Play / chiaki-ng)",
"oyun penceresi: macOS kayıt izni yok, pencere okunamıyor", "oyun penceresi: aranıyor", "oyun penceresi: <uygulama> okunuyor".

### Remote Play Mac'e kurulmuş mu, indirme
- Kurulu mu sorusu paket kimliğiyle: Sony `com.playstation.RemotePlay`, chiaki-ng `org.streetpea.chiaking`. Seçim
  "otomatik"se ikisinden biri yeter.
- İndirme sayfaları (adres olgudur): `https://remoteplay.dl.playstation.net/remoteplay/` ve
  `https://github.com/chiaki-ng/chiaki-ng/releases/latest` (tarayıcıda açılır).
- Not: eski uygulamada ikinci bir pencere okuyucu daha var (yalnız bu iki uygulamayı paket kimliğiyle arayan,
  en az 400×250, 2 sn'de bir, çeviri başlarken uygulamayı kendisi açan). Bugün çeviri başlatılırken **kullanılmıyor**;
  yalnız "kurulu mu" sorusu ve indirme adresleri ondan geliyor. Yeni uygulamada yukarıdaki tek okuyucu yeterli.

---

## 3. Yakalama kartı (HDMI → USB)

HDMI yakalama kartları macOS'ta kamera gibi görünür (UVC). Yalnız Apple'ın kamera çerçevesi (AVFoundation) kullanılır.
İki kullanım:
- **PS5 → kart (geçişli) → TV:** oyun TV'de, altyazı TV uygulamasında. Mac yalnız okur, oyunu göstermez.
- **PS5 → kart → Mac → ekran:** oyunu Nino tam ekran gösterir, sesini çalar, altyazı üstünde. (Altyazı bilgisayar
  ekranındaysa bu kip.)

### Aygıt seçimi
- Harici görüntü aygıtları listelenir (macOS 14+: "harici" türü; ses için mikrofon + harici).
- Kullanıcının seçtiği aygıt takılıysa o. Değilse adı bilinen web kameralarına benzemeyenler (facetime, webcam,
  iphone, ipad, logitech, brio, c920, c922, continuity, desk view) arasından adında kart ipucu geçen ilki (capture,
  hdmi, elgato, avermedia, live gamer, game, cam link, razer, ripsaw, ugreen, usb video, uvc, hd60, 4k x, 4k s,
  magewell, video); yoksa kalan ilki.
- Kartın ses aygıtı: aynı USB model kimliği, yoksa adı birbirini içeren.

### Okuma
- İzin: kamera izni sorulur (verilmezse durum "izin yok"). Ses gerekiyorsa mikrofon izni de sorulur; verilmezse
  görüntü yine okunur, yalnız ses çalınmaz.
- Oturum mümkünse 1920×1080 ön ayarıyla; kareler sistem tarafından **1920×1080 BGRA**'ya ölçeklenir, geç kareler
  atılır. Kart saniyede 60 kare verir; okuma hattına saniyede 10 kare verilir (her biri kopyalanarak, kartın kare havuzu
  tükenmesin).
- **Siyah görüntü:** her verilen karede seyrek örnek alınır (32 pikselde bir); en parlak örnek bile 24/255'in altındaysa
  kare siyahtır. 4 sn kesintisiz siyahsa durum "siyah görüntü" (PS5 kapalı, kablo yok ya da HDCP açık); siyah olmayan
  ilk karede "okunuyor"a döner.
- **Takılma bekçisi:** saniyede bir bakılır; 3 sn hiç kare gelmezse (ses akarken görüntü donabiliyor) oturum baştan
  kurulur. Yeniden deneme aralığı her seferinde iki katına çıkar, en çok 30 sn; kare gelince 3 sn'ye döner.
- Aygıt takılınca/çıkarılınca, oturum hata verince ya da kesinti bitince yeniden bağlanılır. Aynı kart zaten okunuyorsa
  dokunulmaz. Uykudan uyanınca "yenile".
- Ses: oyun bu Mac'te gösteriliyorsa kartın sesi tam ses (1,0) çalınır. Geliştirici kaydı için ayrıca 16 kHz tek kanal
  örnekler alınabilir.
- Kart bağlanınca ad, çözünürlük, en yüksek kare hızı ve biçim sistem günlüğüne yazılır.

### Oyun penceresi (Mac'te gösterme kipi)
- Mac'e HDMI ile bir dış ekran bağlıysa (dahili olmayan) oyun orada, yoksa ana ekranda açılır. Pencere başlığı uygulamanın adı,
  siyah zemin, oranı 16:9'a kilitli, başlangıçta ekranın görünür alanından yatayda 80, dikeyde 60 içeride; açılır açılmaz
  **tam ekrana** geçer ve Nino öne gelir.
- Görüntü kart oturumundan doğrudan ekran kartıyla çizilir (okuma hattından geçmez, en az gecikme), oran korunur.
- **Esc** tam ekrandan çıkar (pencereyi kapatmaz). Fare durunca imleç gizlenir. Pencereyi kapatmak **çeviriyi
  durdurur**. Menü çubuğunda tam ekranı açıp kapatan `home.menu.gameFullScreen` (oyunu tüm ekrana yayan
  komut) var (küçültülmüşse önce geri getirir).
- Oyun alanı (pencerenin içindeki 16:9 alan, ekran koordinatlarında, sol üst başlangıç) her boyut/yer/ekran/tam ekran
  değişiminde bildirilir; küçültülünce "alan yok". Altyazı penceresi bunun alt kısmına oturur.
- Oyun gösterilirken ekran uykusu engellenir. Ekran uyanınca, oturum kilidi açılınca ya da kart oturumu yeniden
  kurulunca görüntü katmanı oturuma yeniden bağlanır (yoksa eski karede donabiliyor).

### Durum ve metinler
- Kaynak durumu: okunuyor ya da siyah → "akıyor"; durdu → "bağlı değil"; izin yok ya da kart yok → "bağlanıyor".

| Durum | Anahtar | Ne der (EN ve TR aynı anlamda) |
|---|---|---|
| Durdu | `home.card.idle` | yakalama kartının okunacağını söyleyen kısa satır |
| İzin yok | `home.card.cameraDenied` | macOS'un Kamera izin sayfasından Nino'ya izin verip uygulamayı tekrar açmayı ister |
| Kart yok | `home.card.noCard` | kartı takmayı isteyen kısa satır |
| Siyah | `home.card.black` | gelen karenin kapkara olduğunu söyler; konsolu açmayı ya da konsolun HDMI ayarlarındaki HDCP seçeneğini kapatmayı önerir |
| Okunuyor | `home.reading %@` | `%@` (kartın adı) okunduğunu söyler |

Altyazı günlüğüne: "görüntü kaynağı: yakalama kartı (oyun bu bilgisayarda gösteriliyor)", "yakalama kartı: kamera izni
yok / bulunamadı / görüntü siyah (<ad>) / okunuyor (<ad>)". Kurulum rehberi ve canlı önizleme `kurulum.md` §10'da.

---

## 4. Xbox (Greenlight ya da tarayıcı)

Xbox ev yayını bu Mac'e ücretsiz, kaynağı açık **Greenlight** uygulamasıyla (MIT) gelir; ikinci yol tarayıcıdaki `xbox.com/play`
sayfasıdır. Nino Greenlight'ı yönetmez, gömmez; yalnız dışarıdan izler ve kullanıcıyı sonraki adıma götürür. Görüntü §2'deki
oyun penceresi okuyucusuyla (Xbox hedefiyle) okunur; altyazı TV'ye veya bu Mac'e gider.

### Durum yoklama (bağlantı listesi görünürken saniyede bir)
- **Kurulu mu:** `/Applications/Greenlight.app` ya da `~/Applications/Greenlight.app` var mı.
- **Açık mı:** paket kimliği `com.unknownskl.greenlight` olan çalışan uygulama.
- **Girişli mi:** `~/Library/Application Support/greenlight-desktop/config.json` okunur; `user.tokenstore` kaydı (iç
  içe `user` → `tokenstore` ya da düz `user.tokenstore` anahtarı) boş olmayan bir metinse (ve "{}" değilse) ya da
  nesneyse girişli. Jetonların içeriğine bakılmaz, yalnız varlığına.
- **Yayın açık mı:** açıksa, sahibi adında "greenlight" geçen ve başlığı "Greenlight - " ile başlayıp son kelimesi en az
  8 karakterlik, tamamen onaltılık ve en az bir rakam içeren (konsol kimliği) bir pencere var mı. Orta kelime
  Greenlight'ın diline göre değişir; menü sayfaları ("Greenlight - My consoles") sayılmaz. Başlıkları okumak Ekran
  Kaydı izni ister.
- **Adım:** yayın açık → bitti; kurulu değil → kurulum; girişli değil → giriş; değilse → yayın.

### Tek tıkla kurulum
1. `https://api.github.com/repos/unknownskl/greenlight/releases/latest` (`Accept: application/vnd.github+json`)
   okunur. 200 değilse ya da yanıtta adı `-universal.dmg` ile biten dosya yoksa: `capture.greenlight.error.latest`
   (Greenlight'ın son yayınına erişilemediğini söyleyip ağ bağlantısına bakmayı ister)
2. Dosya indirilir; ilerleme indirilen/boyut × 0,95 (en çok %95). Başarısızsa `capture.greenlight.error.download`
   (indirmenin yarıda kaldığını söyleyip ağa bakıp tekrar denemeyi ister)
3. GitHub dosya için `sha256:` özeti verdiyse indirilen dosyanın SHA-256'sı karşılaştırılır; tutmazsa `capture.greenlight.error.damaged`
   (inen dosyanın sağlam gelmediğini söyleyip bir daha denemeyi ister)
4. Kalıp görünmeden, salt okunur, Finder'da açılmadan geçici bir noktaya bağlanır; içindeki `.app` önce
   `/Applications`'a, olmazsa `~/Applications`'a kopyalanır (varsa eskisi silinir). Kalıp ayrılır, dosyalar silinir.
   Olmazsa `capture.greenlight.error.copy` (Greenlight'ın Uygulamalar klasörüne yerleştirilemediğini söyler)
5. İlerleme %100, durum yenilenir, Greenlight açılır.
- `setup.xboxList.openGreenlight` (Open Greenlight / Greenlight'ı Açın) ve `setup.xboxList.goToGreenlight` (Go to
  Greenlight / Greenlight'a Geçin): çalışıyorsa öne getirilir, değilse kurulu kopya açılır.
- Microsoft giriş sayfası: `https://www.microsoft.com/link`.
- Kurmadan deneme: tarayıcıda `https://www.xbox.com/play/consoles`.

---

## 5. Bilgisayar ekranında gösterme (altyazı penceresi)

`setup.tv.noTV` (TV'si olmayan kullanıcıya altyazıyı Mac ekranında göstermeyi öneren seçenek) seçildiğinde, PS5 oyun penceresi kaynağında ve kartın Mac'te gösterme kipinde
altyazı bu Mac'te, oyunun üstünde saydam bir pencerede gösterilir. Pencerenin kendisi (görünüşü, yeri, sürükleme)
altyazı penceresi belgesinde; burada davranışı:

- Pencere TV'ye giden olayların aynısını alır ve TV uygulamasıyla aynı yığın kurallarını kullanır; TV kurulu olmasa da
  çalışır. Pencere yalnız altyazı bilgisayarda gösteriliyorsa (ya da yayın penceresi açıksa) olay işler.
- **Görünürlük:** altyazı bilgisayardaysa ve ekranda en az bir satır ya da ek alan varsa, ya da yer ayarlanıyorsa.
- **Olaylar:**
  - Altyazı: "ekranı çevir" gösterimi bitirilir; yığına eklenir (önceki satırları tutma ayarı stilden; paragraf ve
    "yerine geç" bilgisi korunur).
  - Ekran çevirisi: çeviri satır satır gösterilir ve süresi boyunca tutulur; hemen ardından gelen "temizle" (yalnız
    "ekran çevriliyor…" yazısı içindir) onu kaldırmaz.
  - Ekran çevirisini temizle: süre dolmamışsa yığın gizlenir.
  - Temizle: ekran çevirisi gösterilmiyorsa yığın temizlenir.
  - Ek alan (görev, telefon, bildirim): kimliğine göre eklenir/değiştirilir (boş metin kaldırır); yukarıdan aşağı
    sıralanır. Kutunun yatay ortası %40'tan solda ise sola, %60'tan sağda ise sağa, arada ortaya yaslanır. Ek alanlar
    altyazının üstünde küçük kutularda durur.
  - Ek alanları temizle: hepsi kalkar.
- Görünen satırlar her değişimde yenilenir ve bir sonraki değişim anına (solma, kalkma) zamanlayıcı kurulur.
- Çeviri durunca ya da altyazı artık bilgisayarda değilse her şey hemen kalkar; bilgisayarda değilse yer ayarı da
  kapanır.
- **Tıklamaları geçir:** ayar açıksa ve yer ayarlanmıyorsa pencere fareyi geçirir. ⌥⌘L ve menü çubuğu seçeneği bunu
  açıp kapatır; kısayol yalnız çeviri sürerken ve altyazı bilgisayardayken etkindir.
- Oyun alanı kaynak tarafından bildiriliyorsa (oyun penceresi ya da kart penceresi) pencere oraya oturur.
