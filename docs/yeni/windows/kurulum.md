# Windows uygulaması: kurulum sihirbazı

Bu belge ilk açılış kurulum sihirbazının çerçevesini, her adımın ekranını ve yakalama kartı rehberinin çerçevesini anlatır.
Ortak bileşenler `tasarim-dili.md`'de (ör. "adım düzeni", "numaralı satır", "kart", "ikincil düğme"), ana pencere ve
robot `ana-ekran.md`'de. Ölçüler px. Adımların arkasındaki iş (PSN girişi, PS5 eşleştirmesi, TV keşfi/eşleştirmesi,
TV uygulaması kurulumu, model indirme, Gemini anahtar denemesi, adım ilerletme kuralları) denetleyicinin ve ilgili
hizmetlerin belgelerinde; burada ekranın ne gösterdiği, neyi okuduğu ve neyi çağırdığı yazılır.

Metinler: anlamı Türkçe ve İngilizce verilir. Bazı Türkçe metinlerin anlamı İngilizce anahtarından farklıdır; bu
durumda ikisi de verilir ve **ikisi de korunur**: Türkçe arayüzde Türkçe anlam, diğer dillerde İngilizce anlam
gösterilir (ör. PSN adımında "parolanın doğrudan Sony'ye gittiği" cümlesi yalnız İngilizce anlamda var; atılmaz).

Sihirbaz, kabuğun (ana pencere) içinde, kurulum "bitti" değilken gösterilir. Robot sağ altta durur (`ana-ekran.md`
§2.2).

---

## 1. Çerçeve

Dört yandan 24 boşluklu, iki sütunlu ızgara: solda doğal genişlikte adım listesi, sağda kalan alan.

### 1.1 Sol: adım listesi (kart, 240 geniş, iç boşluk yatay 12 dikey 20, sağında 16 boşluk)

Yukarıdan aşağı (alt kısım alta yapışık, liste ortada kalan yeri doldurur):

- **Üst** (yanlardan 12, altta 16): 32 × 32 logo kutusu (köşe 7,2) + 12 boşluk + `setup.sidebar.title`, bölüm başlığı
  stili (22 yarı kalın), dikeyde ortalı.
- **Orta:** dikey kaydırılabilir adım satırları (§1.2). Odak almaz.
- **Alt** (yanlardan 12, üstte 16):
  - İkincil `setup.sidebar.reset`, altta 14 boşluk; yalnız konsol türü kilitliyse görünür (denetleyici
    söyler; eskisinde Hoş geldin adımında "Devam"a basılınca kilitlenir ve kalıcı saklanır; kilitliyken Hoş geldin'deki
    konsol radyoları devre dışıdır). Tıklayınca kurulum sıfırlanır ve adım yeniden gösterilir.
  - Sayaç: `setup.stepCounter` (X, Y), küçük etiket stili, altta 8.
  - İlerleme çubuğu: değer X / Y.

Sayaç ve çubuk adım değişince ve konsol türü değişince güncellenir. X ve Y denetleyiciden: Y = 8 (Xbox'ta 7, ikinci PSN
hesabı adımı yok); X = adımın sırası + 1, Xbox'ta ikinci hesap adımından sonrakiler için 1 eksik, en çok Y.

### 1.2 Adım satırları

Sıra: Hoş geldin, ikinci hesap, Giriş, Konsol, TV, Çeviri modeli, Deneyelim, Daha doğal çeviri. Xbox seçiliyse
ikinci hesap adımı listede yoktur ve sonraki numaralar bir kayar.

Her satır (tıklanamaz; yalnız bilgi): iç boşluk yatay 12 dikey 8, altta 4 boşluk, en az 44 yükseklik, köşe 14.

- Solda 28 × 28 daire (köşe 14, dikeyde ortalı):
  - Tamamlanan (sırası şimdikinden küçük): zemin success, içinde onay simgesi (U+E73E, simge yazısı).
  - Şimdiki: zemin accent, içinde numara.
  - Sıradaki: zemin border, içinde numara.
  - İşaret 13 px yarı kalın, tek satır, ortalı; rengi tamamlanan/şimdikide onAccent, sıradakide textSecondary.
- Sağında 12 boşlukla ad (dikeyde ortalı): tamamlanan/şimdikide textPrimary, sıradakide textSecondary; şimdikide yarı
  kalın.
- Şimdiki satırın zemini surface2; diğerleri saydam.
- Ekran okuyucu adı: "<numara>. <ad>".

Adların anlamı (satırdaki ad = adımın başlığı; Xbox'ta bazıları farklı, ve listedeki Xbox adları adım ekranındaki
başlıklardan farklıdır):

| Adım | Metin anahtarı |
|---|---|
| Hoş geldin | `setup.welcome.title` |
| İkinci hesap | `setup.psnAccount.title` |
| Giriş (PS5) | `setup.psnSignIn.title` |
| Giriş (Xbox) | `setup.steps.signInXbox` (adım ekranında: `setup.msSignIn.title`) |
| Konsol (PS5) | `home.toggle.connectPs5` |
| Konsol (Xbox) | `setup.steps.consoleXbox` (adım ekranında: `setup.xbox.title`) |
| TV | `setup.tv.title` |
| Çeviri modeli | `setup.model.title` |
| Deneyelim | `setup.try.title` |
| Daha doğal çeviri | `setup.better.title` |

### 1.3 Sağ: adım alanı

Yukarıdan aşağı: adım kartı (kalan yeri doldurur) ve altında düğme satırı.

- **Adım kartı:** iç boşluğu 0 olan kart; içinde dikey kaydırılabilir alan; onun içinde adımın içeriği, dört yandan
  32 boşlukla.
- **Düğme satırı** (üstten 16):
  - Solda `common.back`: ikincil, en az 160 geniş, en az 44 yüksek. Hoş geldin adımında **gizli ama yeri korunur**.
    Tıklayınca denetleyiciden bir adım geri gitmesini iste.
  - Sağda `common.continue`: birincil, en az 200 geniş, en az 44 yüksek, varsayılan düğme (Enter basar). Etkinliği
    denetleyicinin "ilerlenebilir mi" değerine bağlı. Deneyelim adımında gizli (yeri korunur). Tıklayınca ilerle.
  - "Daha doğal çeviri" adımında ücretsiz Gemini kullanılmıyorsa: yazısı "Şimdilik geç" (EN `setup.skipForNow`), ikincil
    görünüm, varsayılan düğme DEĞİL (anahtar alanında Enter adımı geçmesin). Gemini anahtarı doğrulanınca yeniden birincil
    "Devam" ve varsayılan. Bu, adım değişince ve "ücretsiz Gemini kullanılıyor mu" değişince yeniden hesaplanır.
- Adım değişince içerik yeniden kurulur (her adım ekranı her gösterilişte yeni kurulur ve yüklenince kendi işini
  başlatır).
- Hangi ekran: Hoş geldin; İkinci hesap; Giriş (Xbox ise Microsoft girişi, değilse PSN girişi); Konsol (Xbox ise Xbox
  listesi, değilse PS5 eşleştirmesi); TV; Çeviri modeli; Deneyelim; diğer her durumda Daha doğal çeviri.

### 1.4 yakalama kartı rehberi yer değiştirmesi

Denetleyici "yakalama kartı kurulumu etkin" derse sağdaki adım alanı (kart ve Geri/Devam) gizlenir, yerine yakalama kartı
rehberi (§12) gelir; etkinlik bitince geri döner. Gösterilen taraf 250 ms'de 0 → 1 belirir (hareketi azalt'a bakmaz).
Sol adım listesi yerinde kalır.

---

## 2. Adım: Hoş geldin

Adım düzeni; başlık `setup.welcome.title`.

**Açıklama** (konsola göre değişir):
- PS5: Nino'nun PS5 ya da Xbox oyunlarının İngilizce altyazılarını okuyup Türkçe çevirisini TV'de oyunun üstünde
  gösterdiği; kullanıcının TV'de kendi kumandasıyla oynamaya devam ettiği.
- Xbox: Xbox desteğinin beta olduğu; Nino'nun oyun görüntüsündeki altyazıyı okuyup çeviriyi TV'de ya da bilgisayarda
  gösterdiği; kendi kumandayla oynamaya devam edildiği.

**Sağ üstte çeviri dili seçici** (adım düzeninin üstüne, üstten 4, sağdan 4; sağdan sola arayüzde de görünürde sağ
üstte kalır): açılır liste, en az 190 geniş, her zaman soldan sağa; ekran okuyucu adı `setup.welcome.translationLanguage`. Öğeler: bayrak + dilin kendi adı (`tasarim-dili.md` §8.17), sırayla Türkçe en üstte. Seçili olan, ayarlardaki
hedef dilin kodu. Seçim değişince, farklıysa ayarlardaki hedef dil yazılır. Ayarlar değişince liste yeniden kurulur.
**Windows'ta arayüz dili değişmez** (Windows'un dilidir); yalnız çeviri dili değişir.

**İçerik** (dikey):
1. Kart `setup.welcome.chooseConsole`, altında 16:
   - Radyo "PlayStation 5" (çevrilmez), altında 12.
   - Radyo "Xbox Series / Xbox One (Beta)".
   - Yüklenince hangisinin seçili olduğu denetleyiciden (Xbox mu) alınır; konsol türü kilitliyse ikisi de devre dışı.
   - Seçilince (yükleme bittikten sonra) denetleyiciye konsol türü bildirilir; açıklama ve gereksinimler yenilenir.
2. Xbox gereksinimleri (yalnız Xbox'ta, ipucu stili): aynı ağdaki ev Xbox'ı, Microsoft hesabı ve altyazının görüneceği TV
   ya da bilgisayar gerektiği; Xbox'ta uzaktan oynatmanın açık olması gerektiği.
3. PS5 gereksinimleri kartı (yalnız PS5'te) "Gerekenler:" (EN `setup.welcome.youWillNeed`): alt alta, aralarında 8:
   - `setup.welcome.needPs5`.
   - `setup.welcome.needLgTv`.
   - `setup.welcome.needSecondAccount`.
4. Kısa yollar (üstten 16; iki konsolda da):
   - Alt satıra kayan sıra:
     - İkincil, yatay iç boşluk 16, sağda 12: `setup.welcome.shortcutRemotePlay` (anlamı: bu bilgisayarda PS Remote
       Play ile oynamak) → oyun penceresi kurulumu (PS5 eşleştirmesine, ikinci hesaba ve TV'ye ihtiyaç yok).
     - İkincil, aynı ölçüler: `setup.welcome.shortcutXbox`; ipucu balonu: Xbox uygulamasında Uzaktan
       oynat'ın, Greenlight'ın ya da xbox.com/play'in başlatılması, Nino'nun o pencereyi okuyup çeviriyi TV'ye
       gönderdiği → Xbox penceresi kurulumu.
     - Hayalet: simge U+E703 (16 px) + 8 + `setup.welcome.shortcutCaptureCard`; ipucu balonu: ikinci
       hesap gerekmediği, Nino'nun oyunu karttan okuyup çeviriyle gösterdiği → yakalama kartı kurulumu (§12).
   - İpucu (üstten 8): TV ya da ikinci hesap gerekmediği; Nino'nun Remote Play penceresini okuyup çeviriyi oyunun üstünde
     gösterdiği.

## 3. Adım: ikinci hesap (Xbox'ta yok)

Başlık: `setup.psnAccount.title`.
Açıklama: `setup.psnAccount.description` (Türkçe anlamı: altyazı bu hesapla okunur, kullanıcı kendi hesabıyla oynar, kurulum bir
kez yapılır; İngilizce anlamı: Nino oyunu Remote Play ile izler; kendi hesabını kullansa PS5 kolu kapatırdı; ikinci hesapla
rahatsız edilmeden oynanır).

İçerik:
1. Numaralı satırlar:
   1. playstation.com'da farklı bir e-postayla ücretsiz hesap açın.
   2. PS5'te Kullanıcı Ekle'yi seçip yeni hesapla bir kez giriş yapın.
   3. Yeni hesaptayken Ayarlar › Sistem › Uzaktan Oynama'da "Uzaktan Oynama'yı Etkinleştir"i açın.
   4. Türkçe anlamı: kendi hesabında bildirimleri kapatması (uyarılar altyazının üstüne çıkmasın); İngilizce anlamı
      farklı: kendi kullanıcısına dönmesi, bunun bir kez yapıldığı.
2. İpucu (üstten 8): oynamak için kol açılınca PS5'te ANA hesabın seçilmesi; Nino'nun giriş yaptığı ikinci hesapla
   oynanmaması, yoksa kolun oyunda çalışmayacağı.
3. Kart (üstten 16):
   - Üst satır: `setup.psnAccount.remotePlayWindowTitle` (yarı kalın), sağda ikincil `setup.select`
     → Remote Play penceresi okuma kurulumu (eskisinde: kare kaynağı Remote Play penceresi olur, TV yoksa çıkış
     bilgisayar ekranı olur ve kurulum doğrudan biter; ayrıntı denetleyici belgesinde).
   - İpucu (üstten 8): Nino'nun altyazıyı bu bilgisayarda açık PS Remote Play ya da chiaki-ng penceresini okuduğu; ikinci
     hesap ve PS5 eşleştirmesi gerekmediği; TV'nin sonra bağlanabileceği.
   - İndirme bölümü (üstten 12): yalnız bu bilgisayarda PS Remote Play de chiaki-ng de kurulu değilse (denetleyici
     söyler, "otomatik" uygulama seçimiyle). İpucu: ikisinin de kurulu olmadığı. Altında yatay (üstten 8): ikincil `setup.psnAccount.downloadRemotePlay` (sağda 8) → `https://remoteplay.dl.playstation.net/remoteplay/`; ikincil `setup.psnAccount.downloadChiaki`
     → `https://github.com/chiaki-ng/chiaki-ng/releases/latest`. Varsayılan tarayıcıda açılır.
4. Kart (üstten 12):
   - Üst satır: `setup.psnAccount.captureWindowTitle` (yarı kalın), sağda ikincil `setup.select` →
     yakalama penceresi kurulumu.
   - İpucu: Nino'nun yalnız Ayarlar › `settings.section.pictureSource`'nda seçilen OBS projektörünü ya da oyun penceresini okuyabildiği;
     ikinci PSN hesabı ya da ek yakalama uygulaması gerekmediği.

## 4. Adım: PSN girişi (PS5)

Başlık: "İkinci hesabınızla giriş yapın" (EN `setup.psnSignIn.title`).
Açıklama: TR `setup.psnSignIn.description` (EN anlamı
farklı: parolanın doğrudan Sony'ye gittiği, Nino'nun yalnız hesap kimliğini sakladığı.)

**Yerleşim** (yukarıdan aşağı):
1. `setup.signedIn`, tamam stili, altta 12; yalnız hesap varken.
2. Giriş düğmesi: hesap yokken birincil `psnLogin.signIn`; varken ikincil `psnLogin.signInAgain`.
3. Hata yazısı (hata stili), üstten 12.
4. İkincil `setup.psnSignIn.signInInBrowser`, üstten 20, sola yaslı.
5. Tarayıcı bölümü (üstten 20, başta gizli):
   - Neden (ipucu, altta 6; yalnız kendiliğinden geçildiyse): Sony'nin giriş sayfasının uygulama içinde sunucusuna
     bağlanamadığı, girişin tarayıcıya taşındığı.
   - Yol (ipucu, altta 6): açılan tarayıcıda ikinci hesapla giriş yapılması; bitince tarayıcının yalnız "redirect" yazan
     bir remoteplay.dl.playstation.net sayfasında kalacağı; adres çubuğundaki adresin tamamının kopyalanıp buraya
     dönülmesi; Nino'nun kopyalanan adresi kendiliğinden alacağı, almazsa aşağıya yapıştırılıp Kaydet'e basılması.
   - Yatay: 340 geniş metin alanı + 12 boşluk + birincil `common.save`.
   - İkincil `setup.psnSignIn.openBrowserAgain`, üstten 8, sola yaslı → giriş sayfasını yeniden aç.
   - Tarayıcı hata yazısı, üstten 8.
6. İkincil `setup.psnSignIn.enterIdManually`, üstten 12, sola yaslı.
7. Elle giriş bölümü (üstten 20, başta gizli):
   - İpucu (altta 6): Sony'nin giriş sayfası açılmıyorsa (bazı internet sağlayıcıları engelliyor) ikinci hesabın PSN kimliğinin base64 olarak girilmesi (12 karakter, ör. `AbCdEfGhIjk=`).
   - Yatay: 240 geniş metin alanı (en çok 24 karakter) + 12 + birincil "Kaydet".
   - Elle giriş hata yazısı, üstten 8.

**Davranış:**
- **Giriş Yap:**
  1. Giriş penceresi WebView2 ister. Bileşen yoksa: hata yazısına "giriş penceresi için Microsoft'un WebView2 bileşeni
     gerekiyor ama bu bilgisayarda yok; az önce açılan sayfadan kurun, sonra yeniden Giriş yap'a basın" anlamı yazılır,
     WebView2 indirme sayfası tarayıcıda açılır (açılamazsa sessiz), günlüğe not düşülür, durulur.
  2. Giriş penceresi bu pencerenin üstünde (kipli) açılır (ayrı belge). Üç sonuç döner: yönlendirme adresi, sorun,
     "tarayıcıya geç".
  3. Adres yok ve "tarayıcıya geç" ise: hata temizlenir, tarayıcı yolu kendiliğinden açılır (neden satırı görünür).
  4. Adres yok (pencere giriş bitmeden kapandı): hata yazısına denetleyicinin "giriş penceresi sorunu" iletisi.
  5. Adres varsa girişi tamamla.
- **Girişi tamamla:** giriş düğmesi devre dışı, hata temizlenir; denetleyiciye adres verilir. Kullanıcıya dönük hata
  gelirse iletisi yazılır; beklenmeyen hata gelirse "giriş geçersiz" açıklaması + boşluk + "(ayrıntı)" yazılır. Sonunda
  düğme açılır ve yazısı/türü yenilenir.
- **`setup.psnSignIn.signInInBrowser`** (elle ya da kendiliğinden): `setup.psnSignIn.signInInBrowser` düğmesi gizlenir, bölüm görünür, neden
  satırı yalnız kendiliğinden geçişte görünür, tarayıcı hata yazısı temizlenir. O an panoda duran (eski girişten kalma)
  yönlendirme adresi "son denenen" sayılır ki kendiliğinden denenmesin. Giriş sayfası tarayıcıda açılır, metin alanına
  odaklanılır.
- **Pencere öne gelince** (kullanıcı tarayıcıdan döndü): bölüm görünür ve giriş düğmesi açıksa panodaki metin okunur
  (okunamazsa geçilir). İçinden yönlendirme adresi çıkarılabiliyorsa ve son denenenle aynı değilse alana yazılır ve
  gönderilir. (Çıkarma kuralı PSN hesabı belgesinde.)
- **Gönder** (Kaydet, alanda Enter ya da kendiliğinden): giriş düğmesi kapalıysa (iş sürüyor) bir şey yapma. Alandan
  adres çıkarılamıyorsa tarayıcı hata yazısı: "Bu adreste giriş kodu yok. Adres
  `https://remoteplay.dl.playstation.net/remoteplay/redirect?code=` ile başlamalı." anlamında. Çıkarılırsa son denenen
  yapılır ve giriş tamamlanır. Hesap oluştu ve hata yoksa: alan boşaltılır, bölüm gizlenir, `setup.psnSignIn.signInInBrowser`
  geri gelir, panoda yönlendirme adresi varsa pano temizlenir (tek kullanımlık kod kalmasın).
- **Hesap kimliğini elle gir:** düğme gizlenir, bölüm açılır, alana odaklanılır. Alanda Enter kaydeder (adımın Devam'ına
  gitmez). Kaydet: denetleyici kimliği kabul ederse elle giriş ve genel hata yazıları temizlenir, giriş düğmesi
  yenilenir; etmezse elle giriş hata yazısı: geçerli bir kimlik olmadığı, base64'te 12 karakter olduğu, ör.
  `AbCdEfGhIjk=`.

## 5. Adım: Microsoft girişi (Xbox)

Başlık `setup.msSignIn.title`. Açıklama: Xbox hesabının
Greenlight'taki gibi Microsoft cihaz koduyla bağlandığı; giriş sayfasının varsayılan tarayıcıda açıldığı.

Yerleşim: `setup.signedIn` (tamam stili, altta 12; Xbox hesabı varken) → birincil `setup.msSignIn.signIn` →
kod bölümü (üstten 16, altta 8, başta gizli): `setup.msSignIn.codeLabel` ipucu (altta 4); kod: salt okunur,
çerçevesiz, saydam zeminli metin alanı, 30 px kalın, el imleci, altta 4; bağlantı satırı (altta 8): bağlantı yazısı
adresin ana makinesi ("www." atılmış) + yolu (sondaki "/" atılmış), ör. "microsoft.com/link"; adımlar ipucu → durum
ipucu → hata yazısı (üstten 12).

Davranış:
- Giriş düğmesi: iş sürüyorsa bir şey yapma. Düğme kapanır, hata temizlenir, durum `setup.msSignIn.statusOpening`.
  Denetleyiciden giriş başlatması istenir → kod ve adres gelir. Kod alana yazılır ve panoya kopyalanır; bağlantı
  kurulur; adımlar ipucu üç satır: (1) kodun kopyalandığı ve tarayıcıda microsoft.com/link'in açıldığı, açılmadıysa
  yukarıdaki bağlantıya tıklanması; (2) kodun yapıştırılıp Xbox'ta kullanılan Microsoft hesabıyla giriş yapılması ve
  izin verilmesi; (3) Nino'ya dönülmesi, girişin kendiliğinden biteceği. Kod bölümü görünür; durum `setup.msSignIn.statusWaiting`. Denetleyicinin girişi bitirmesi beklenir; bitince kod bölümü gizlenir, durum `setup.msSignIn.statusDone` Hata olursa kod bölümü gizlenir, hata yazısı hatanın iletisi, durum `setup.msSignIn.statusFailed` Sonunda düğme açılır.
- Koda tıklamak: kod yeniden kopyalanır ve tümü seçilir. Bağlantıya tıklamak: kod kopyalanır, adres tarayıcıda açılır.
  Pano kilitliyse (başka uygulama tutuyor) sessizce geçilir.

## 6. Adım: PS5'i bağla

Başlık "PS5'inizi bağlayın" (EN `home.toggle.connectPs5`). Açıklama: PS5'in açılması; ikinci kullanıcıyla Ayarlar › Sistem ›
Uzaktan Oynama › Cihazı Eşleştir'in açılıp orada görünen `setup.ps5.codeLabel`'un girilmesi.

**Yerleşim:**
1. Eşli PS5'in adı (tamam stili, altta 16; ad boşsa "PS5"); yalnız eşli PS5 varken.
2. Kart:
   - Üst satır (altta 12): "PS5" (karo başlığı), sağda ikincil `tv.search.again`.
   - Bulunamadı ipucu (altta 8): PS5'in ağda görülmediği; açık ve aynı ağda olduğundan emin olunması ya da IP adresinin
     girilmesi. Yalnız hiç bulunamadıysa.
   - Elle adres alanı: 320 geniş, sola yaslı; yalnız hiç bulunamadıysa.
   - Bulunan PS5'ler: her biri radyo "<ad> — <adres>".
3. `setup.ps5.codeLabel` ipucu (üstten 20, altta 6).
4. Kod alanı: 240 geniş, sola yaslı, yazı 22 px yarı kalın (code), en az 52 yüksek, en çok 16 karakter (boşluk ve tire
   payı).
5. Birincil `common.connect`, üstten 16.
6. Çalışıyor ipucu (üstten 12, başta gizli): PS5'e bağlanıldığı, 30 saniyeyi bulabileceği.
7. Eşleşti yazısı (tamam stili, alt satıra kayar, üstten 12, başta gizli).
8. Hata yazısı (üstten 12).
9. İkincil `setup.showLogFile`, üstten 8, sola yaslı; yalnız hata varken.
10. Güvenlik duvarı kartı (üstten 12; `ana-ekran.md` §3.5; çeviri sürmediği için PS5 eşleştirme metinleriyle).

**Davranış:**
- Yüklenince eşli ad gösterilir ve arama yapılır.
- **Arama:** "Yeniden Ara" kapanır, liste boşaltılır, denetleyiciden PS5'ler istenir. Henüz seçim yoksa ilk bulunanın
  adresi seçilir. Seçili adres işaretli gelir; radyo seçilince seçim o adres olur. Hiç yoksa bulunamadı ipucu ve elle
  adres alanı görünür. Sonunda düğme açılır.
- Kullanılacak adres = seçili adres, yoksa elle adres alanının kırpılmış metni.
- Kod ya da adres alanında Enter: olay tüketilir (Devam'a gitmez); iş sürmüyorsa ve Bağlan açıksa bağlanılır.
- Kod değişince: iş sürmüyorsa ve kod boş değilse Bağlan açılır.
- **Bağlan:** iş sürüyorsa bir şey yapma. İş başlar; Bağlan kapanır; çalışıyor ipucu görünür; hata temizlenir; eşleşti
  yazısı gizlenir. Denetleyiciden adres ve kodla eşleştirme istenir.
  - Başarı: eşli ad yenilenir.
  - Kullanıcıya dönük hata: iletisi yazılır (eksik kod/adres dahil; hiçbir sonuç sessiz kalmaz).
  - Beklenmeyen hata: Remote Play günlüğüne not; yazı "eşleştirme başarısız" açıklaması + " (ayrıntı) " + "Sorun
    sürerse bu dosyayı bize gönderin: <günlüğün gösterilen yolu>".
  - Sonunda: iş biter, çalışıyor ipucu gizlenir, Bağlan = eşleşmediyse açık, eşleştiyse kapalı; hata varsa `setup.showLogFile` düğmesi görünür.
  - Eşleştiyse: eşleşti yazısı "✓ " + denetleyicinin eşleşme metni, görünür; kod alanı boşaltılır; Bağlan açıkça kapalı
    tutulur (yeni kod yazılınca açılır); yazı görünür alana kaydırılır; 1 sn beklenir; adım hâlâ ekrandaysa
    denetleyiciye "eşleşmeden sonra devam" denir (sonraki adım).
- **Günlük dosyasını göster:** günlüğün klasörü yoksa oluşturulur; dosya varsa Dosya Gezgini'nde seçili açılır, yoksa
  klasör açılır. Açılamazsa sessiz (yol zaten hata yazısında).

## 7. Adım: Ev Xbox'ını seç

Başlık `setup.xbox.title`. Açıklama: Xbox'ın açık ve bilgisayarla aynı ağda olması,
Xbox ayarlarından uzaktan oynatmanın açılması.

Yerleşim: birincil `setup.xbox.findConsoles` → durum ipucu (üstten 16, altta 8) → konsol listesi → hata
yazısı (üstten 12).

Davranış: yüklenince ve düğmeyle arama. Düğme kapanır, hata temizlenir, durum `setup.xbox.searching`, liste
boşaltılır, denetleyiciden konsollar istenir. Sonuç: hiç yoksa durum `setup.xbox.noneFound`
bulunamadı.", varsa `setup.xbox.chooseOne`. Her konsol bir radyo (altta 12): ad ve parantez içinde model; uzaktan oynatma
kapalıysa `setup.xbox.consoleItemRemoteOff` biçimi kullanılır ve radyo devre dışıdır. Denetleyicinin seçili konsoluyla aynı
kimlikteyse işaretli; seçilince denetleyiciye o konsol bildirilir. Hata olursa hata yazısı iletisi, durum `setup.xbox.loadFailed`. Sonunda düğme açılır.

## 8. Adım: TV'yi bağla

Başlık "TV'nizi bağlayın" (EN `setup.tv.title`). Açıklama: TV'nin açılması; Bağlan'a basınca TV'nin bir kez izin
isteyeceği, kumandayla onaylanması; `tvApp.title` kurulu değilse bu ekranın kurmaya yardım edeceği.

**Yerleşim:**
1. Eşli TV'nin adı (tamam stili, altta 16); yalnız eşli TV varken.
2. Kart:
   - Üst satır (altta 12): "TV" (karo başlığı), sağda ikincil "Yeniden Ara".
   - Bulunamadı ipucu: hiçbir LG/Samsung TV bulunamadığı; TV'nin açık ve aynı ağda olduğundan emin olunması. Yalnız hiç
     bulunamadıysa.
   - Bulunan TV'ler: her biri bir satır (üst/alt 4): solda "<ad> — <adres>", sağda birincil "Bağlan".
3. Kart (üstten 16): üst satır Android TV ile Google TV adları eğik çizgiyle (normal kalınlık; çevrilmez), sağda ikincil "Seç"; ipucu (üstten
   8): Vestel, Arçelik, Beko, Grundig, Philips ve Android TV kullanan diğer TV'ler.
4. Kart (üstten 16): üst satır TR `setup.tv.noTvTitle` (yarı kalın), sağda ikincil "Seç"; ipucu: altyazının oyunun üstünde bir pencerede görüneceği, TV'nin sonra
   bağlanabileceği.
5. Bekleme ipucu (üstten 16, başta gizli).
6. İpucu (üstten 16): Windows Nino'nun ağı kullanıp kullanamayacağını sorarsa özel ağlar için izin verilmesi.
7. İpucu (üstten 8): TV bağlanamıyorsa `firewall.settings.title`'nın Nino'yu engelliyor olabileceği; Ayarlar › Windows
   Güvenlik Duvarı'ndan izin verilmesi ve bu ağın Windows'ta "Özel" yapılması.
8. Hata yazısı (üstten 12).
9. TV uygulaması kartı (üstten 16; §8.1).
10. Elle kurulum kartı (üstten 16) `tvApp.title`: yalnız eşli TV varsa, LG değilse ve uygulamayla gelen TV paketi
    yoksa (geliştirici derlemesi). Metin: `tvApp.title`'nın rehberdeki adımlarla bu TV'ye kurulup açılması,
    uygulamanın bu bilgisayarı kendisi bulacağı. İkincil "Rehberi Aç" (üstten 8) → proje deposundaki kurulum belgesinin
    5. bölümü (TV uygulamasının kurulumu)
    (sitenin kurulum rehberi: `SiteLinks.TvApp` (Türkçe `#kurulum`, Android TV `#android-tv-elle`, Arapça `ar/kurulum`, diğer diller `#english`)).

**Davranış:**
- Yüklenince: eşli ad ve elle kurulum kartı gösterilir; TV eşliyse ve TV uygulamasının durumu "bilinmiyor"sa (kurulum
  yarıda kalmış olabilir) denetleyiciden TV uygulamasına yeniden bakması istenir; arama yapılır.
- **Arama:** "Yeniden Ara" kapanır, liste boşaltılır, denetleyiciden TV'ler istenir, satırlar kurulur, bulunamadı ipucu
  ayarlanır, düğme açılır.
- **Bağlan / Android TV Seç:** TV listesi devre dışı; bekleme ipucu: Samsung'da `setup.tv.waitSamsung` (TV'deki izin kutusunun kumandayla onaylanması, 60 sn bekleme), diğerlerinde `setup.tv.waitOther`. Hata temizlenir.
  Denetleyiciden eşleştirme istenir; başarıda eşli ad yenilenir; hata olursa hata yazısına denetleyicinin markaya göre
  "eşleştirme sorunu" iletisi. Sonunda bekleme gizlenir, liste açılır. Android TV "Seç" adı "Android TV", adresi boş,
  markası Android TV olan bir TV ile eşleştirme ister (TV ağda aranır).
- **Monitörde göster Seç:** denetleyiciye "bilgisayar ekranını kullan" denir (TV kurulmaz, sonraki adıma geçilir).

### 8.1 TV uygulaması kartı

Kart, başlık `tvApp.title`. TV uygulamasının durumu "bilinmiyor"sa bütün kart gizli.
Marka: eşli TV'nin markası, yoksa LG.

İçerik (yukarıdan aşağı):
- Durum yazısı (alt satıra kayar), duruma göre:
  - Kuruluyor: `tvApp.status.installing`.
  - Güncel: `tvApp.status.ready` (sürüm).
  - Geliştirici modu kapanıkken: LG → uygulamanın kurulu olmadığı, geliştirici modu açılınca Nino'nun kurabileceği;
    Samsung → `tvApp.status.devModeOffSamsung`; diğer (Android) → hata ayıklama açılınca Nino'nun ağ üzerinden kendisi
    kuracağı.
  - Parola gerekli: `tvApp.status.passphraseNeeded`
  - Samsung hesabıyla giriş: `tvApp.status.samsungSignIn`.
  - TV'de onay: `tvApp.status.approveOnTv`
  - Diğer: boş.
- Ayrıntı (ipucu, üstten 4; boşsa gizli):
  - Samsung hesabıyla giriş: `tvApp.detail.samsungSignIn` + boşluk + `tvApp.detail.samsungSignInNoAccount`.
  - TV'de onay: `tvApp.detail.approveOnTv`.
  - Güncel ve LG: kalan saat biliniyorsa `tvApp.detail.lgHoursLeft` (saat); bilinmiyorsa `tvApp.detail.lgAutoExtend`.
  - Güncel ve Samsung: kaynak değiştirme ipucu `tvApp.detail.samsungSourceSwitch`.
- LG adımları (üstten 8; geliştirici modu kapalı ve LG): üç ipucu satırı: (1) webostv.developer.lge.com'da ücretsiz
  hesap; (2) TV'de LG Content Store'dan Developer Mode uygulamasını kurup giriş; (3) Dev Mode Status'un açılması, TV'nin
  yeniden başlayıp bu ekranın kendiliğinden devam edeceği.
- Samsung adımları (üstten 8; marka Samsung ve (geliştirici modu kapalı ya da durum "başarısız" ve hatası "ulaşılamıyor"
  ya da "Host PC IP uyuşmuyor")):
  (1) TV'de Uygulamalar'ın açılması, sayfanın en altında Uygulama Ayarları varsa onun seçilmesi; (2) 1 2 3 4 5
  yazılması, kumandada rakam yoksa 123 tuşuyla ekrandan seçilmesi, beşinci rakamdan sonra Geliştirici modu penceresinin
  açılacağı; (3) Developer mode'un On yapılıp Host PC IP alanına **bu bilgisayarın adresinin** (denetleyiciden; yoksa
  "?") yazılması, her bölümün başına sıfır koymadan (001 değil 1), sonra OK; adres değiştirilemiyorsa önce 123 tuşu;
  (4) TV'nin yeniden başlatılması (güç tuşu Samsung logosu görünene kadar basılı ya da bir dakika fişten çekme), bu
  ekranın kendiliğinden devam edeceği; ek ipucu (üstten 4): sonra ücretsiz Samsung hesabıyla bir kez giriş yapılacağı,
  Samsung'un imzalamak için buna ihtiyaç duyduğu; ek ipucu (üstten 4): TV kaynak değiştiriyorsa Ayarlar › Tüm Ayarlar ›
  Bağlantı › Harici Cihaz Yöneticisi'nden Anynet+ (HDMI-CEC) ve otomatik kaynak değiştirme ayarının kapatılması.
- Android adımları (üstten 8; geliştirici modu kapalı ve Android): (1) Ayarlar › Cihaz Tercihleri › Hakkında (Google TV:
  Ayarlar › Sistem › Hakkında); (2) Yapı numarasında geliştirici olduğunu söyleyene kadar 7 kez Tamam; (3) Cihaz
  Tercihleri (Google TV: Sistem) › Geliştirici seçenekleri'nde USB hata ayıklamanın, görünüyorsa Ağ hata ayıklamanın da
  açılması; ipucu (üstten 4) `tvApp.android.searching`; ipucu: menü adlarının markaya göre değişebileceği, uygulama zaten
  kuruluysa adımın geçilebileceği; ikincil `tvApp.android.usbInstead` (üstten 8) → Android TV kurulum rehberi
  (sitenin Android TV rehberi: `SiteLinks.TvApp(…, androidTv: true)`).
- Parola bölümü (üstten 8; parola gerekliyken ya da LG'de geliştirici modu kapalıyken — Nino geliştirici modunu algılayamasa da TV'de Key Server açıksa kullanıcı takılmasın): ipucu: TV'de Developer Mode uygulamasının açılıp Key Server'ın
  etkinleştirilmesi, uygulamanın ekranda bırakılması, gösterilen Passphrase'in yazılması. Altında (üstten 8) iki sütun:
  esnek metin alanı + 8 boşluk + birincil "TV'ye Kur". Alan boş/boşluksa bir şey yapmaz; değilse denetleyiciden parolayla
  TV uygulamasının kurulması istenir.
- Yeniden aç bölümü (üstten 8; Samsung hesabıyla giriş durumunda): ipucu: giriş penceresi açılmazsa tarayıcının onu açılır pencere
  olarak engellemiş olabileceği, adres çubuğundaki simgeden izin verilip "Sayfayı yeniden aç"a basılması. Altında yatay
  (üstten 8): ikincil `tvApp.reopen.reopenPage` → durumun adresini tarayıcıda aç; ikincil `tvApp.reopen.copyLink` (soldan 8) →
  adres panoya, yazı `common.copied` olur (pano kilitliyse değişmez). Başka duruma geçince yazı yeniden `tvApp.reopen.copyLink`.
- Sorun yazısı (hata stili, üstten 8): denetleyicinin duruma, markaya, TV kurulum günlüğünün yoluna ve bu bilgisayarın
  adresine göre verdiği sorun iletisi.
- İkincil "Tekrar Dene" (üstten 8, sola yaslı; yalnız "başarısız"da) → TV uygulamasına yeniden bak.

Zamanlama ve olaylar:
- Geliştirici modu kapanıkken ya da Samsung'da sorun "Host PC IP uyuşmuyor"ken her 3 sn'de denetleyiciden TV uygulamasına
  yeniden bakması istenir (kullanıcı TV'de modu açınca / adresi düzeltince kendiliğinden devam); diğer durumlarda durur.
- TV uygulamasının durumu, kalan geliştirici modu saati ya da eşli TV değişince kart yeniden çizilir.
- Bilgisayarın ağ adresi değişince (Wi-Fi değişimi, VPN) kart yeniden çizilir (gösterilen "Host PC IP" eskide kalmasın).
- Ekrandan kalkınca zamanlayıcı ve olaylar bırakılır.

## 9. Adım: `setup.model.title`

Başlık `setup.model.title`. Açıklama: Nino'nun çeviriyi bu bilgisayarda internetsiz yaptığı; İngilizce–Türkçe
modelin (yaklaşık 475 MB) bir kez indirilip bu bilgisayarda kaldığı.

- Yüklenince denetleyiciden model indirmesini başlatması istenir (zaten iniyorsa ya da kuruluysa bir şey olmaz).
- İndirilirken: "İndiriliyor…" ipucu (altta 8) + ilerleme çubuğu.
- Kuruluysa: `setup.model.ready` (tamam stili).
- İndirme hatası varsa: "İndirme tamamlanmadı; internet bağlantınızı kontrol edip tekrar deneyin." anlamında hata yazısı
  (altta 12) + birincil "Tekrar Dene" → indirmeyi yeniden başlat.

## 10. Adım: Deneyelim

Başlık "Deneyelim" (EN `setup.try.title`). Açıklama: Nino'nun TV'ye örnek bir altyazı göndereceği, ekranın altında
oyunun üstünde görünmesi gerektiği.

Altyazı bilgisayar ekranına gidiyorsa ("TV'm yok" seçildi) yüklenince metinler değişir: açıklama `setup.try.descriptionScreen` (örnek altyazının monitörün altında görüneceği); soru `setup.try.questionScreen`; ipucu
`setup.try.notSeenScreen`; "Altyazı penceresini ayarla" düğmesi
görünür.

Yerleşim:
1. Yatay: birincil `setup.try.sendSample` + (yalnız bilgisayar çıkışında, soldan 12) ikincil `setup.try.adjustWindow`.
2. Soru kartı (üstten 20, başta gizli), başlık `setup.try.questionTv`: yatay birincil `setup.try.yesISeeIt` (varsayılan
   düğme) + soldan 12 ikincil "Hayır"; ipucu (üstten 12): görülmüyorsa `tvApp.title`'nın açık olduğundan emin
   olunması ve TV'nin yeniden bağlanması.
3. İpucu (üstten 20): Nino'nun okuduğu İngilizce altyazıları herkes için daha iyi çeviriler hazırlamak üzere anonim
   olarak ortak havuza gönderdiği; Ayarlar'dan kapatılabileceği.

Davranış:
- Gönder: denetleyiciden deneme altyazısı göndermesi istenir; gönder düğmesi ikincil görünüme geçer; soru kartı görünür.
- Ayarla: denetleyiciye "altyazı penceresi ayarlanıyor" denir (pencere ayar kipine girer).
- Evet: ayar kipi kapatılır, ilerlenir. Hayır: TV adımına dönülür.
- Bu adımda alttaki "Devam" gizlidir; ilerlemenin tek yolu "Evet".

## 11. Adım: Daha doğal çeviri (ücretsiz, isteğe bağlı)

Başlık TR "Daha doğal çeviri, ücretsiz" (EN `setup.better.title`). Açıklama: ücretsiz çevirinin internetsiz
çalıştığı ama çoğu zaman yapay durduğu; Google'ın Gemini'sinin çok daha doğal çevirdiği, ücretsiz bir Google anahtarının
yettiği; TR'de ayrıca "İsterseniz bu adımı atlayabilirsiniz." cümlesi var.

Yerleşim:
1. Kart: `setup.better.deviceTitle` (altta 8); açılır liste, 240 geniş, sola yaslı: `setup.better.deviceCpu` ve "GPU (Beta) ·
   NVIDIA CUDA"; ipucu (üstten 8): CPU'nun her bilgisayarda çalıştığı; GPU'nun uyumlu NVIDIA kartı istediği, ilk seçimde
   NVIDIA'dan yaklaşık 565 MB CUDA dosyası indirildiği (diskte yaklaşık 790 MB), kullanılamazsa CPU'ya geçildiği; GPU'dan
   düşüldüyse warning renkli `setup.better.gpuFallback` (üstten 8). Seçim ayarlardaki çeviri
   aygıtına yazılır; yüklenince ayardaki değer seçili gelir.
2. Hazır yazısı (tamam stili, üst/alt 16, alt satıra kayar; yalnız ücretsiz Gemini kullanılıyorsa): `setup.better.geminiReady`.
3. Yeni anahtar bölümü (Gemini kullanılmıyorsa):
   - Kart: numaralı satırlar (1) "Ücretsiz anahtar al"a basıp Google hesabıyla giriş, (2) "Create API key"e basıp
     anahtarın kopyalanması, (3) anahtarın buraya yapıştırılıp kaydet-ve-dene düğmesine basılması; birincil `setup.better.getFreeKey` (üstten 8, sola yaslı) → Gemini anahtar sayfası (`https://aistudio.google.com/apikey`) tarayıcıda.
   - Yatay (üstten 16): 320 geniş parola alanı (dikeyde ortalı) + soldan 12 ikincil `setup.better.saveAndTest` (alan boşken devre
     dışı; kırpılmış parola boş değilse açık).
4. Durum ipucu (üstten 12, başta gizli) ve hata yazısı (üstten 12, başta gizli).
5. İpucu (üstten 16): altyazı metninin Google'a gönderildiği; ücretsiz anahtarda Google'ın onu ürünlerini geliştirmek
   için kullanabileceği ve çalışanlarının okuyabileceği; yalnız oyunun altyazılarının gönderildiği.
6. İpucu (üstten 8): ücretsiz anahtarın dakika başına sınırı olduğu; sınır dolunca o satırın ücretsiz çeviriyle
   çevrileceği.

Kaydet ve dene: düğme kapanır, yazısı `setup.better.testing`; durum ve hata gizlenir. Denetleyiciden Gemini anahtarını
kaydedip denemesi istenir. Anahtar kaydedildiyse alan boşaltılır. Sonuç "geçerli" ise durum ipucu "Çalışıyor. Örnek
çeviri: <örnek>" (örnek yoksa boş); değilse hata yazısı sonucun açıklaması (Gemini için; denetleyici verir). Görünür
olur. Hazır/yeni anahtar bölümleri yenilenir. Sonunda düğme yazısı `setup.better.saveAndTest`'ye döner ve alana göre açılır.

Alttaki düğme bu adımda "Şimdilik geç" / "Devam" olur (§1.3).

---

## 12. yakalama kartı rehberi (sihirbazda adım alanının yerine)

Üç sayfalı rehber; sayfaların içeriği (kart önizlemesi ve denetimi dahil) kart belgesinde (`kaynaklar.md` §3). Burada çerçeve ve
ilk iki sayfa.

### 12.1 Çerçeve

- Alt satır (üstten 16), üst üste üç parça:
  - Ortada sayfa noktaları: yatay, ortalı; her nokta 7 yüksek, köşe 3,5, yanlarda 3,5 boşluk; şimdiki sayfa 24 geniş,
    diğerleri 7. Şimdiki ve önceki sayfalar accent, sonrakiler border. Ekran okuyucu adı "Adım X / 3".
  - Solda hayalet düğme, en az 120 geniş, en az 44 yüksek: "Geri" (ayarlardan açılan pencerede ilk sayfada "Vazgeç",
    EN "Cancel").
  - Sağda birincil, en az 200 geniş, en az 44 yüksek, varsayılan: son sayfa değilse "Devam", sonda `common.done`.
- Üstte iç boşluğu 0 olan kart; içinde dikey kaydırılabilir alan; içinde 32 boşlukla sayfa.
- Geri: sayfa > 0 ise önceki sayfa; ilk sayfada pencerede pencereyi kapat, sihirbazda denetleyiciye "yakalama kartı
  kurulumunu iptal et".
- Devam: son sayfa değilse sonraki; sonda denetleyiciye "yakalama kartı kurulumunu bitir (TV'ye mi)" ve pencereyse kapat.
- Sayfa değişimi: yeni sayfa 28 px sağdan (Arapçada soldan) 320 ms'de yerine kayar (kübik ease-out) ve 260 ms'de belirir.
  İlk gösterimde animasyon yok.
- Başlangıçta "TV'ye mi" = yakalama kartı kullanılıyor ve altyazı TV'de gösteriliyor.

### 12.2 Sayfa 1: Bağlantı biçimi

Adım düzeni; başlık "PS5'iniz nasıl bağlı?" (EN `cardGuide.page1.title`); açıklama: yakalama kartının PS5 görüntüsünü
HDMI'dan alıp USB ile bu bilgisayara verdiği; ikinci PSN hesabı ya da Remote Play gerekmediği.

İki seçenek karosu (ikincisi üstten 12), her biri tam genişlikte, içeriğini olduğu gibi gösteren tıklanabilir düğme (el
imleci, klavyeyle seçilebilir, odak işareti yok). Karo bir karttır; seçiliyse "etkin" (accent çerçeve).

- İçerik: solda seçim halkası (seçili U+EC61 accent, değil U+EA3A textSecondary; 22 px; yukarıya yaslı; sağında 16);
  sağda başlık (karo başlığı), açıklama (ipucu, üstten 6), kablo şeması (üstten 12, yatay): simge kutuları arasında
  "→" (Arapçada "←"; küçük etiket stili, yanlarda 8). Kutu 36 × 30, köşe 8, zemin accentSoft, içinde 16 px accentText
  simge.
- Seçenek 1 `cardGuide.page1.monitorTitle`: Nino'nun oyunu sesiyle bu
  bilgisayarda tam ekran gösterdiği, çevirinin üstte olduğu; bilgisayarın ekrana HDMI ile bağlanması. Şema: kol (U+E7FC)
  → kablo (U+E703) → bilgisayar (U+E7F8) → monitör (U+E7F4).
- Seçenek 2 `cardGuide.page1.tvTitle`: HDMI çıkışlı (passthrough) bir kart gerektiği;
  oyunun gecikmesiz doğrudan TV'ye gittiği; Nino'nun kartı okuyup çeviriyi TV uygulamasına gönderdiği. Şema: kol →
  kablo → TV (U+E7F4).
- Seçilen değişirse sayfa yeniden kurulur. Ekran okuyucu: başlık adıyla, seçiliyse "seçili" durumu.

### 12.3 Sayfa 2: HDCP

Başlık "PS5'te HDCP'yi kapatın" (EN `cardGuide.page2.title`); açıklama: PS5'in HDCP adlı kopya korumasıyla kartları
engellediği; oyunların etkilenmediği; bir kez yapıldığı.

Numaralı satırlar: (1) PS5'in kısa süre doğrudan bir TV'ye/monitöre bağlanması (ayar kart üzerinden değiştirilemez);
(2) PS5'te Ayarlar › Sistem › HDMI; (3) "HDCP'yi Etkinleştir"in kapatılması, sonra PS5'in kartın HDMI girişine
bağlanması. Sonra bilgi satırları (simge 16 px, yukarı yaslı, sağında 10, simge ve yazı textSecondary, ipucu stili):
bilgi simgesi (U+E946) ile `cardGuide.page2.netflixInfo` (üstten
8, altta 12); kulaklık simgesi (U+E7F6) ile `cardGuide.page2.headsetInfo`.

### 12.4 Sayfa 3: Kartı takın

Başlık `cardGuide.page3.title`; açıklama TV'ye göre: TV'ye ise "PS5 → kartın HDMI girişi, kartın
HDMI çıkışı → TV, kartın USB'si → bu bilgisayar"; değilse "PS5 → kartın HDMI girişi, kartın USB'si → bu bilgisayar;
sonra bilgisayarı ekrana bağlayın". İçerik: kart önizlemesi ve denetimi (220 yüksek önizleme; ayrı belge).

### 12.5 Ayarlardan açılan rehber penceresi

Başlık `cardGuide.window.title`; 760 × 760, en az 620 × 560; görev çubuğunda görünmez; sahibinin
ortasında; kipli. Zemin pencere zemini, yazı textPrimary; rehber 24 kenar boşluğuyla. Bitince/vazgeçilince kapanır.

---

## 13. Gezinme özeti (ekranın çağırdıkları)

- Devam → ilerle; Geri → geri; ilerlenebilirlik denetleyiciden.
- Kısa yollar: oyun penceresi kurulumu, Xbox penceresi kurulumu, yakalama kartı kurulumu (Hoş geldin); Remote Play penceresi
  okuma, yakalama penceresi (İkinci hesap); bilgisayar ekranını kullan (TV); eşleşmeden sonra devam (PS5); TV adımına dön
  (Deneyelim "Hayır"); kurulumu sıfırla (sol liste).
- Ana ekrandan sihirbaza dönüş: TV yazısına tıklama (TV yoksa) ve başlatılamayan aç/kapat (`ana-ekran.md` §3.2, §4.11).

## 14. Tema, sağdan sola ve hareket

- **Tema:** sihirbazda yalnız belirteç renkleri kullanılır (zemin, kartlar, düğmeler, adım daireleri, yazılar); açık ve
  koyu temada aynı yerleşim, yalnız renkler değişir. Sabit renk yok.
- **Sağdan sola (ar/ur arayüzü):** bütün düzen aynalanır: adım listesi sağda, adım alanı solda; adım satırında daire
  sağda, ad solunda; "Geri" sağda, "Devam" solda; kartlardaki "Seç"/"Yeniden Ara" düğmeleri solda. Hoş geldin'deki dil
  seçicisi görünürde yine sağ üstte durur (sağdan sola düzende "sol" hizası verilir). Soldan sağa kalanlar: dil seçicisi
  ve bayraklı satırları, kart önizlemesinin çerçevesi, robot görseli. yakalama kartı rehberinde sayfalar öteki yandan
  kayar, kablo şemasında "←" kullanılır.
- **Hareket:** sihirbazın iki animasyonu (adım alanı ↔ rehber 250 ms belirme; rehberde sayfa kayması) hareketi azalt'a
  bakmaz. Robot ve balon kuralları `ana-ekran.md` §2.

## 15. Windows'a özgü (platform) kısımlar

| Yetenek | Ne için | Ayar |
|---|---|---|
| WebView2 | PSN giriş penceresi | yoksa indirme sayfası açılır |
| Pano (okuma, yazma, temizleme) | PSN yönlendirme adresini kendiliğinden almak, Xbox kodunu ve Samsung bağlantısını kopyalamak | kilitliyse sessiz geçilir |
| Pencere "öne geldi" olayı | Tarayıcıdan dönüşte panoyu okumak | yalnız tarayıcı bölümü açıkken |
| Ağ adresi değişti olayı | Samsung "Host PC IP" satırını tazelemek | |
| Dosya Gezgini `/select,` | Remote Play günlüğünü göstermek | |
| Varsayılan tarayıcıyla adres açma | İndirme sayfaları, rehberler, Gemini anahtar sayfası, Microsoft cihaz kodu | kabukla |

## 16. Mac'ten farklar

Windows sihirbazında solda sürekli görünen adım listesi (logo, sayaç, ilerleme, sıfırlama düğmesi) vardır; adım
içeriği sola yaslı, simgesiz bir kartın içindedir; Geri/Devam düğmeleri kartın alt kenarının altında durur. Mac'teki konsol/TV seçim görselleri,
simge kutuları, ortalı düzen ve belirme yayı yoktur. Windows'a özgü: OBS/oyun penceresi ve Remote Play penceresi kısa
yolları, PS Remote Play/chiaki-ng indirme düğmeleri, WebView2 denetimi, tarayıcıda giriş ve panodan kendiliğinden alma,
güvenlik duvarı kartı ve ipuçları, günlük dosyasını gösterme, ücretsiz çeviri aygıtı (CPU/GPU) seçimi, Android TV için
USB bellek rehberi. Arayüz dili çeviri diliyle değişmez.
