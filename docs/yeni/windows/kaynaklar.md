# Windows: görüntü kaynakları (PS5 Remote Play, oyun penceresi, yakalama kartı, Xbox)

Bu belge yeni Windows uygulaması için bir **tarif**tir: oyun görüntüsünün nereden ve nasıl alındığını, hangi
durumların kullanıcıya nasıl söylendiğini anlatır. Kod yok. Kullanıcıya görünen metinler yeni metin
kataloğunun anahtarıyla (`Text/Catalog/*.json`) verilir; günlük satırları yalnız anlamıyla anlatılır. Yerel C köprüsü ayrı belgede: `yerel-kopru.md`. Mac karşılığı
`git show claude/yeni-mac-c9961f:docs/yeni/mac/kaynaklar.md`; Windows'un farkları her bölümde belirtilmiştir.
Kurulum sihirbazındaki seçim ekranları `kurulum.md`'de, ayar dosyası alanları `kimlikler-veri.md`'de.

**Metinler hakkında:** bu belgede tırnak içinde verilen Türkçe/İngilizce **günlük satırları** yalnız anlam içindir;
kendi cümlenle yaz. Birebir korunması gerekenler yalnız şunlardır: §1.6'daki bekçi satırının işaretli parçası, chiaki'nin
kendi İngilizce satırları (`yerel-kopru.md` §9), Sony/Microsoft'a giden adresler, başlıklar ve gövdeler, ve saklanan
anahtar/alan adları. Xbox köprüsünün iç komut adları ve sayfa ileti türleri (§4) iki tarafı da yeniden yazıldığı için
serbesttir; anlamları ve sıraları korunmalı.

## 0. Ortak sözleşme

### 0.1 Kaynak arayüzü
Her kaynak okuma hattına aynı arayüzle kare verir; hat farkı bilmez:
- **Kare** olayı: BGRA resim (piksel başına 4 bayt; genişlik, yükseklik, satır adımı). Kaynağın kendi iş parçacığında.
- **Durum** olayı: üç evre — **bağlanıyor**, **akıyor**, **bağlı değil (neden, ayrıntı)**.
- **PS5 taşındı** olayı: PS5 yeni bir adreste bulundu; yeni kayıt saklanmalı (yalnız PS5 kaynağı çağırır).
- Komutlar: **başlat**, **durdur** (bloklamaz), **hemen yeniden bağlan** (uykudan uyanma, ağ değişimi, güvenlik
  duvarı kuralı eklendi), **bırak**.
- oyun penceresi ve kart kaynakları ayrıca kendi ayrıntılı durumlarını ve **oyun alanının ekrandaki yerini** bildirir;
  kart kaynağı "oyun penceresi kullanıcı tarafından kapatıldı" ve "tam ekran aç/kapat" komutunu da taşır.

### 0.2 Kopma nedenleri (değerler)
Nedenin adı günlüğe ve sağlık kaydına (sağlık özeti ve otomatik sorun bildirimi) **metin olarak** yazılır; uyumluluk için bu
yazımlar korunmalı: `Stopped`, `ConsoleAsleep`, `InUse`, `Refused`, `Network`, `LoginPasscode`, `NotFound`, `Other`,
`RegistrationInvalid`, `LoginPasscodeIncorrect`, `Rejected`, `RemotePlayDisabled`. Anlamları §1.6'da.

### 0.3 Ayarlar ve hangi kaynağın seçildiği
Üç üst üste binen seçici vardır (hepsi `settings.json`'da; ayrıntı `kimlikler-veri.md`):
- **`settings.section.pictureSource`** (`VideoSource`, metin olarak saklanır: `"Ps5"`, `"Window"`, `"Card"`; eski dosyalarda yoksa Ps5).
- **Konsol** (`GameConsole`, metin: `"Ps5"`, `"Xbox"`; yoksa Ps5) — pencere yolunda hangi pencerenin aranacağı.
- **Eski kare kaynağı** (`FrameSource`, **sayı** olarak saklanır: 0 = PS5, 1 = Remote Play penceresi, 2 = seçilen
  pencere) ve onun yardımcıları: `RemotePlayApp` (sayı: 0 hangisi açıksa, 1 yalnız Sony, 2 yalnız chiaki-ng),
  `CaptureWindow` (`{"ProcessName": …, "Title": …}` ya da null), `XboxLegacyFrameRate` (bool).
- Ayrıca şifreli depoda **konsol türü** (`consoleKind`: PlayStation ya da Xbox, sayı) — "Xbox doğrudan yayın" yolu.

**Çeviri başlarken öncelik sırası** (ilk tutan kullanılır):
1. `settings.section.pictureSource` = Window → **oyun penceresi okuyucusu (GDI)** (§2), konsola göre PS5 ya da Xbox penceresi.
2. `settings.section.pictureSource` = Card → **yakalama kartı** (§3); oyun bu bilgisayarda gösterilsin mi = "altyazı bilgisayarda mı".
3. Konsol türü Xbox → **Xbox doğrudan ev yayını** (§4, köprü + WebView2).
4. Eski kare kaynağı = 1 → **Remote Play penceresi okuyucusu (Graphics.Capture)** (§2.6), uygulama seçimiyle.
5. Eski kare kaynağı = 2 → aynı okuyucu, **kullanıcının seçtiği pencere** ile (§2.6).
6. Değilse **PS5 Remote Play (doğrudan)** (§1); PS5 kaydı ve hesap kimliği yoksa başlatılmaz.

Not (Mac'ten fark): Mac'te ikinci pencere okuyucusu kullanılmıyor; **Windows'ta ikisi de kullanılıyor** (4. ve 5.
madde). Xbox doğrudan yayın **yalnız Windows'ta** var.

### 0.4 Başlatma kuralları (kaynaklarla ilgili kısmı)
- Çeviri zaten sürüyorsa ya da başlıyorsa ikinci oturum açılmaz.
- Kaynağın durum ve alan olayları arayüz iş parçacığına aktarılır ve **yalnız o anki kaynak** dinlenir: eski bir
  oturumun geç gelen olayı yeni oturumu etkilemez (test: kart kaynağı durdurulup yenisi başlatılınca eskisinin
  "okunuyor" ve "pencere kapandı" olayları yok sayılır; çeviri sürer, oyun alanı boş, kart durumu "durdu" kalır).
- Kart kaynağında oyun penceresini kapatmak çeviriyi durdurur.
- Bağlantı koptuğunda (evre "bağlı değil") okuma hattı, ek bölge/telefon/harita izleyicileri sıfırlanır ve TV'deki
  altyazı temizlenir.
- Bilgisayar uykudan uyanınca kaynağa "hemen yeniden bağlan".
- `settings.section.pictureSource` değişir ve çeviri sürüyorsa durdurulup yeni kaynakla yeniden başlatılır (test: pencereden PS5'e
  geçilince, PS5 kurulu değilse eski kaynak durur ve çeviri başlamaz). Kart kaynağında altyazının yeri değişirse kart
  yeniden açılır (TV → bilgisayar: ikinci kart oturumu oyun penceresiyle açılır, birincisi durur).
- Başlatma yarıda hata verirse (ör. yerel kütüphane yok) geride oturum ya da "başlatılıyor" kalmaz, uyku engeli
  kalkar, bilgisayar altyazı penceresi gizlenir; hata çağırana gider; sorun giderilince yeniden başlatılabilir.
- Güvenlik duvarı önerisi yalnız doğrudan PS5 yolunda, akmıyorken ve neden şunlardan biri **değilken** sayılır: PS5
  kapalı, kullanımda, reddetti, şifre gerekli/yanlış, kayıt geçersiz, kodlu ret, Remote Play kapalı.

### 0.5 Çeviri başlatılabilir mi
Kural (birebir): **(kaynak Window ve konsol PS5)** ise evet. Değilse iki koşul birden gerekir:
1. Kaynak hazır: kaynak Window (Xbox penceresi) **ya da** Card **ya da** — konsol türü Xbox ise Microsoft jetonu
   **ve** seçili Xbox konsolu var; değilse eski kare kaynağı 1 (Remote Play penceresi; başka koşul yok) **ya da** 2 ve
   seçilen pencerenin süreç adı ve başlığı boş değil **ya da** 0 (PS5) ve PS5 kaydı **ve** hesap kimliği var.
2. Altyazının gideceği yer: bilgisayarda gösteriliyor **ya da** eşleşmiş TV var (TV kaydı **ve** TV anahtarı).
- Altyazı nereye: PS5 oyun penceresinde her zaman bilgisayarda, TV'ye hiç; Xbox penceresinde ve kartta çıktı ayarına
  göre (TV, bilgisayar ya da ikisi). PS5 yoluna dönülünce çıktı "bilgisayar" ise "TV" olur; kartta "ikisi" yeniden
  açılışta korunur, PS5'te "ikisi" açılışta "TV"ye döner.

---

## 1. PS5 Remote Play (doğrudan, ikinci hesapla)

### 1.1 Veri
- **Kayıtlı PS5**: adres, ad, 16 baytlık kayıt anahtarı (onaltılık ASCII, eksiği sıfırla tamamlanmış), 16 baytlık oturum
  anahtarı. Şifreli depoda `console` anahtarıyla, varsayılan JSON biçimiyle
  (alanlar `Host`, `Name`, `RegistKey`, `Morning`; bayt dizileri base64). Dikkat: eski kayıtta salt okunur
  "uyandırma anahtarı" özelliği de JSON'a `WakeCredential` olarak yazılıyor olabilir (okurken yok sayılır); kesin biçim
  `kimlikler-veri.md`'de.
- **Hesap kimliği**: 8 bayt (şifreli depo, `accountId`, base64).
- **Giriş şifresi**: 4 rakam (şifreli depo, `loginPasscode`), isteğe bağlı.
- **Uyandırma anahtarı**: kayıt anahtarının ilk sıfır baytına kadarki kısmı ASCII olarak okunur ve **onaltılık 64 bit
  sayı** olarak çözülür; çözülemezse yok. Test: anahtar `"1a2b3c4d"` + 8 sıfır → 0x1a2b3c4d. 16 sıfır bayt → yok;
  yokken uyandırma "kayıt anahtarı uyandırma anahtarı değil" hatası verir.

### 1.2 PS5 arama
- İstenirse tek adrese, değilse **yerel ağdaki her adrese ayrı ayrı** sorulur (genel yayına PS5'ten yanıt
  gelmeyebiliyor; tek tek sorgu her ağda çalışıyor). Varsayılan süre **3 sn**.
- **Yerel hedefler:** çalışır durumdaki, geri döngü olmayan her ağ bağdaştırıcısının her IPv4 adresi (geri döngü
  adresi hariç, maskesi olan ve 0.0.0.0 olmayan) için ağdaki **diğer** adresler; en sonda `255.255.255.255`; tekrarlar
  atılır. Ağ bilgisi okunamazsa yalnız genel yayın.
- **Ağdaki adresler** (adres, maske): sunucu sayısı = maskenin tersi. Bu ≤ 1 ya da **> 1023** ise boş (en çok /22).
  Değilse ağ adresi + 1'den ağ adresi + (sayı − 1)'e kadar, kendi adresi hariç. Testler:
  - 192.168.1.10/24 → 253 adres, ilki 192.168.1.1, sonuncusu 192.168.1.254, 192.168.1.10 yok.
  - 192.168.0.1/22 → 1021 adres; /21 → boş. 10.0.0.1/16 → boş.
  - Dönüşüm: "192.168.1.10" ↔ 0xC0A8010A; 0xC0A801FE → "192.168.1.254".
  - Yerel hedefler her zaman `255.255.255.255` içerir, tekrarsızdır, `127.0.0.1` içermez.
- Arama uzun süre uyuyarak beklediği için **ayrı (uzun ömürlü) iş parçacığında** koşar; iptal yalnız beklemeyi
  bırakır; başlamış arama kendi süresi bitene kadar arkada sürer.
- Yanıtlar adrese göre toplanır (aynı adresin sonraki yanıtı öncekinin yerine geçer), adrese göre (sıradan dizgi
  sıralaması) dizilir. Her yanıt: adres, ad (yoksa "PS5"), uyanık mı, çalışan uygulama kimliği ve adı (yoksa yok).
- **Çalışan oyun** (ortak havuz için): yalnız bağlı PS5'in adresine **2 sn** sorulur; yanıt yoksa yok, varsa ilk
  yanıtın uygulama kimliği/adıyla oyun bilgisi (kuralı oyun tanıma belgesinde).
- Kurulumdaki "PS5'leri ara" sonucu günlüğe tek satır: "PS5 araması: bulunamadı" ya da "<ad> <adres>[ (dinlenmede)],
  …".
- **Taşınan PS5'i seçme** (bulunanlar, kayıtlı ad): tek PS5 varsa odur; birden çoksa adı tam eşleşen **tek** PS5;
  emin olunamazsa yok (yanlış konsola bağlanmaktansa adres değiştirilmez). Testler: [A] + "başka ad" → A; [A, B] +
  "PS5-B" → B; [A, B] + "başka ad" → yok; [] → yok.

### 1.3 Eşleşme (`setup.ps5.codeLabel`)
- **Kodu okuma:** boşluk (her türlü), `-`, `–`, `.`, `_` atlanır; başka her karakter Unicode'da "ondalık rakam"
  olmalıdır (başka yazı sistemlerinin rakamları da kabul edilir ve 0–9'a çevrilir); tam **8** rakam olmalı. Değilse yok.
  Testler: "12345678", "1234 5678", " 1234-5678\n", "１２３４５６７８" (tam genişlik), "١٢٣٤٥٦٧٨" (Arapça) → 12345678;
  "01234567" → 1234567; "", yok, "1234567", "123456789", "1234567O" (harf O), "1234567½" → geçersiz.
- Hesap kimliği 8 bayt değilse hemen "geçersiz bağımsız değişken" hatası (test: 4 bayt).
- Kayıt ayrı uzun ömürlü iş parçacığında koşar; iptal yalnız beklemeyi bırakır, PS5'le konuşma kendi süresinde (en çok
  ~30 sn) biter.
- Günlüğe: kayıt başlarken adres ve base64 hesap kimliği; başarıda adres ve PS5 adı.
- Köprünün kayıt işlevi çağrılır; hata düzeyindeki her günlük satırı ayrıca bir listeye toplanır.
- **Sonuç sınıflaması** (köprü dönüşü 1 ve neden ≠ 0 ise "PS5'in bildirdiği neden" vardır):

| Neden / satır | Sonuç (günlük değeri) |
|---|---|
| 0x80108b02 | Yanlış hesap (`WrongAccount`) |
| 0x80108b09 | Kod yanlış / süresi dolmuş (`WrongCode`) |
| 0x80108b10 | Başka cihazda kullanımda (`InUse`) |
| 0x80108b11 | Sistem sürümü uyuşmuyor (`VersionMismatch`) |
| 0x80108b15 | PS5'in Remote Play hizmeti çöktü (`ConsoleCrashed`) |
| neden yok, bir satırda "getaddrinfo" | Adres çözülemedi (`BadAddress`) |
| neden yok, bir satırda "search response", "connect for search", "send search", "Regist search failed", "connect for request" ya da "Regist connect failed" | PS5 yanıt vermedi (`NoAnswer`) |
| neden yok, bir satırda "response HTTP header", "receiving response content" ya da "receive response content" | PS5 isteği aldı, yanıt gelmedi (`NoReply`) |
| köprü dönüşü 2 (iptal = 30 sn doldu) | `NoReply`, ayrıntı: 30 sn içinde yanıt gelmediğini söyleyen kısa İngilizce not |
| köprü dönüşü < 0 | Genel başarısız (`Failed`), ayrıntı "native error <n>" |
| diğer (ör. 0x80108bff ya da hiç bilgi yok) | `Failed` |

  Satır aramaları büyük/küçük harfe duyarlıdır; kurallar yukarıdan aşağı sırayla denenir. Testler: 0x80108b02 →
  WrongAccount; 0x80108bff → Failed; yok → Failed; neden 0x80108b09 + "…search response" satırı → WrongCode (PS5 kod döndürdüyse arama adımı aşılmış demektir); satır çiftleri (ilk, ikinci):
  ("Regist failed to send search: Unknown error", "Regist search failed") → NoAnswer;
  ("Regist connect failed: 10060", "Regist eventually failed to connect for request") → NoAnswer;
  ("Regist eventually failed to connect for search", "Regist search failed") → NoAnswer;
  ("Regist failed to getaddrinfo on 192.168.1.", "Regist eventually failed") → BadAddress;
  ("Regist failed to receive response HTTP header", "Regist eventually failed") → NoReply;
  ("Regist timed out receiving response content", "Regist eventually failed") → NoReply;
  ("Regist response is missing RegistKey (or it was invalid)", "Regist eventually failed") → Failed;
  (yok, ["Regist timed out waiting for search response", "Regist search failed"]) → NoAnswer.
- **Ayrıntı** (iletiye eklenir): hata satırlarından "Reported Application Reason: " içeren ilki varsa o önekten sonrası
  (ör. "0x80108b09 (Regist Failed)"); yoksa ilk hata satırı; satır yoksa yok. Testler: ["Regist received HTTP code
  403", "Reported Application Reason: 0x80108b09 (Regist Failed)", "Regist eventually failed"] → "0x80108b09 (Regist
  Failed)"; ["Regist received HTTP code 500", "Regist eventually failed"] → "Regist received HTTP code 500"; [] → yok.
- Başarısızlık günlüğe hata olarak yazılır: adres, deneme sırası, sonuç ve ayrıntı.
- **Yeniden deneme:** yalnız sonuç "yanıt vermedi" ise (bu aşamada kod henüz PS5'e gitmemiştir; kayıp
  bir UDP paketi yüzünden tekrar denemek zararsızdır) **500 ms** sonra, toplam **3 deneme**. Öbür sonuçlar hemen hata olur (sonuç, neden, ayrıntı).
- Başarıda kayıt: adres = girilen adres, ad = PS5 adı (ilk sıfıra kadar UTF-8), iki anahtar.
- Test (yerel kütüphane varsa): 127.0.0.1'e kayıt → NoAnswer.

**Uygulama tarafı (sihirbazın PS5 adımı):**
- Adres boşsa "PS5 seçilmedi" hatası; kod okunamazsa "kod 8 haneli olmalı"; hesap kimliği yoksa "önce PSN'e giriş
  yapın".
- Kayıt hatasında PS5 kendi kodunu bildirmediyse ve sonuç yanlış hesap ya da adres hatası değilse **güvenlik duvarı
  önerisi** açılır (yanıt bize ulaşmamış olabilir). Beklenmedik hata da öneriyi açar ve genel iletiye ("PS5 kodu
  kabul etmedi") istisna metni parantezle eklenir; günlüğe kaydın beklenmedik hatayla bittiği yazılır.
- Başarıda öneri kapanır, kayıt saklanır, günlüğe adres ve adla "kaydedildi" satırı; adımın altında başarı
  iletisi: `wizard.ps5.paired` (ad, adres; ad boşsa
  "PS5"). Kısa süre sonra, kullanıcı hâlâ PS5 adımındaysa kendiliğinden sonraki adıma geçilir.
- Her eşleşme/giriş hata iletisinin sonuna şu eklenir: `status.sendLogFile` (`%LOCALAPPDATA%\Nino\remoteplay.log`). Ayrıntı varsa iletiye parantezle.

| Sonuç | İleti anlamı (İng. → Tür.) |
|---|---|
| Kod okunamadı | **`source.ps5.pair.codeInvalid`** |
| Hesap yok | **`source.ps5.pair.signInFirst`** |
| Adres yok | **`setup.ps5.notFound`** (Mac'teki yerel ağ izni cümlesi Windows'ta yok) |
| Yanlış hesap | **`source.ps5.pair.wrongAccount`** |
| Yanıt vermedi | **`source.ps5.pair.noAnswer`** |
| Kullanımda | **`wizard.ps5.error.inUse`** |
| Hizmet çöktü | **`source.ps5.pair.serviceCrashed`** |
| Sürüm | **`source.ps5.pair.versionMismatch`** |
| Kod yanlış | **`wizard.ps5.error.wrongCode`** |
| Yanıt gelmedi / iptal | **`wizard.ps5.error.timeout`** |
| Adres hatası | **`source.ps5.pair.badAddress`** |
| Diğer | **`wizard.ps5.error.other`** |

### 1.4 PSN girişi (ikinci hesabın kimliği)
Akış ve istemci bilgileri chiaki-ng'nin kendi PSN girişinden gelir (herkese açık istemci; v1.10.1'de
`gui/include/psnaccountid.h` ve `gui/src/psnaccountid.cpp` — aynı kimlik, sır, kapsam ve yönlendirme).

**Sabitler (birebir):**
- İstemci kimliği: `ba495a24-818c-472b-b12d-ff231c1b5745`; istemci sırrı: `mvaiZkRsAsI1IBkY`.
- Giriş sayfası: `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?` + sorgu, sırayla:
  `service_entity=urn:service-entity:psn`, `response_type=code`, `client_id=<kimlik>`,
  `redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect`,
  `scope=psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update`,
  `request_locale=en_US`, `ui=pr`, `service_logo=ps`, `layout_type=popup`, `smcid=remoteplay`, `prompt=always`,
  `PlatformPrivacyWs1=minimal`.
- Jeton adresi: `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token`.
- Yönlendirme öneki: `https://remoteplay.dl.playstation.net/remoteplay/redirect`.
- **Sorgu kodlaması** (Mac'teki URL bileşenleri gibi): UTF-8 baytları; ASCII harf/rakam ve `-._~:/?@!$'()*,;` olduğu
  gibi, gerisi `%XX` (büyük harf onaltılık). Böylece `:` ve `/` kodlanmaz, boşluk `%20` olur. Testler: giriş adresi
  "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?" ile başlar ve
  "redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect",
  "scope=psn:clientapp%20referenceDataService", "client_id=ba495a24-818c-472b-b12d-ff231c1b5745" içerir.

**Yönlendirmeden kod / hata:**
- Adres mutlak ve (büyük/küçük harfe duyarlı) yönlendirme önekiyle başlıyorsa yönlendirmedir.
- Sorgu `&` ile bölünür (boşlar atılır); her parçada ad ve değer URL'den çözülür (`=` yoksa değer boş).
- **Kod:** yönlendirmede `code` değeri. Test: `<önek>?code=AbC123&cid=x` → "AbC123"; `https://example.com/redirect
  ?code=AbC123` → yok.
- **Sony hatası:** `error` boş değilse `error` + (açıklama varsa) ": " + `error_description` (içindeki `+` boşluğa
  çevrilir) + (kod varsa) " (" + `error_code` + ")". Örnek: `?error=login_required&error_description=Session+ended&error_code=4100` → "login_required: Session ended (4100)".
- **Yapıştırılan metinden yönlendirme:** metin boşsa yok. Önek (büyük/küçük harf duyarsız) aranır; yoksa yok. Önekten
  sonra boşluk, `"`, `'`, `<`, `>` görülene kadar alınır; önek + kalan mutlak adres yapılır. Kod boş değilse ya da Sony
  hatası varsa adres, değilse yok. Testler — kabul (kod "AbC123"): düz adres; başında/sonunda boşluk ve satır sonu;
  tırnak içinde; "redirect <adres> copied". Ret: yok, "", `https://my.account.sony.com/central/signin/`, kodsuz önek,
  `https://example.com/?u=https://remoteplay.dl.playstation.net/remoteplay/redirectx`. Hata yönlendirmesi
  (`?error=access_denied&error_description=denied`) kabul edilir, hata metni "access_denied" ile başlar.
- **"Sunucuya bağlanılamıyor" sayfası:** sayfa metninde (büyük/küçük harf duyarsız) "can not / cannot / can't / can’t
  (tipografik kesme) / could not / couldn't / unable to" + " connect to the server" geçiyorsa. Örnekler — evet: "We couldn't connect to the server right now", "UNABLE TO CONNECT TO THE SERVER (E-102)",
  "Sorry, you can’t connect to the server."; hayır: yok, "Sign in to your account", "Connect to the server later"

**Kodu hesap kimliğine çevirme** (jeton saklanmaz):
- HTTP istemcisi: **çerezsiz** (yeniden girişte eski oturumun çerezleri gitmesin), zaman aşımı **30 sn**.
- Yönlendirmede kod varsa: 
  1. `POST <jeton adresi>`, `Authorization: Basic base64(UTF-8("<kimlik>:<sır>"))`, gövde
     `application/x-www-form-urlencoded`: `grant_type=authorization_code&code=<kod>&scope=<kapsam>&redirect_uri=<önek>`
     (aynı kodlama; test: gövde "grant_type=authorization_code&code=the-code&scope=psn:clientapp%20" ile başlar).
  2. Yanıtta metin türünde `access_token` yoksa: Sony hatası (yanıttaki `error`/`error_description`/`error_code`,
     sayı da olabilir; biçim yukarıdaki gibi) varsa "reddedildi" (ya da çok fazla deneme), yoksa "anlaşılamadı".
  3. `GET <jeton adresi>/<URL-kodlu erişim jetonu>`, aynı Basic başlık. Test: ikinci istek "…/oauth/token/tok123".
  4. Yanıttaki `user_id` (metin ya da sayı) **ondalık, işaretsiz 64 bit**; yoksa/okunamazsa "anlaşılamadı".
  5. 8 baytlık **küçük uçlu** dizi. Testler: "1" → base64 "AQAAAAAAAAA="; "258" → 02 01 00 00 00 00 00 00; "abc",
     "", "-1" → geçersiz.
- Yönlendirmede kod yoksa: Sony hatası varsa "reddedildi" (metinde çok fazla deneme varsa "çok fazla deneme"),
  ayrıntı = hata metni; yoksa "kod yok". Bu durumda **hiç istek yapılmaz**.
- **Hata sınıflaması** (günlük değerleri `NoCode`, `Refused`, `RateLimited`, `Http`, `Network`, `BadResponse`):
  - HTTP başarısızsa gövde okunur: JSON nesnesinde Sony hatası varsa o, değilse kırpılmış metnin ilk 200 karakteri
    (boşsa yok). Durum 429 ya da metin "çok fazla deneme" gibiyse → `RateLimited`; 400/401/403 → `Refused` (kod
    kullanılmış/süresi dolmuş); diğer → `Http`. HTTP kodu saklanır.
  - "Çok fazla deneme gibi": metinde (büyük/küçük harf duyarsız) "too many", "too_many" ya da "rate limit".
  - Başarılı yanıt JSON nesnesi değilse → `BadResponse` (HTTP kodu yok).
  - Ağ hatası → `Network`, ayrıntı hata metni; zaman aşımı → `Network`, ayrıntı "timeout". Çağıranın iptali ağ hatası
    sayılmaz.
  - Testler: 400 + `{}` → Refused, 400; 400 + `{"error":"invalid_client","error_description":"Client not allowed","error_code":4001}` → Refused, ayrıntı
    "invalid_client: Client not allowed (4001)"; 429 + "Too Many
    Requests" → RateLimited, ayrıntı aynı metin; 503 + boş → Http, ayrıntı yok; 200 + `{"error":"invalid_grant"}` →
    Refused, HTTP yok, ayrıntı "invalid_grant"; 200 + `{}` → BadResponse; "No such host is known." ağ hatası → Network,
    ayrıntı bunu içerir; `?error=temporarily_unavailable&error_description=Too+many+requests` → RateLimited;
    `?cid=x` → NoCode.
- Uygulama tarafı: hata günlüğe "PSN girişi başarısız: <tür> HTTP <kod|-> <ayrıntı>"; iletiye "HTTP <kod>" ve ayrıntı
  virgülle birleştirilip parantezle eklenir, sonuna remoteplay.log ipucu. Başarıda "PSN girişi tamam", kimlik saklanır.
  Beklenmedik hata: genel "giriş tamamlanmadı" + istisna metni.

**Giriş penceresi (uygulama içi tarayıcı, WebView2):**
- Pencere başlığı "PlayStation Network", 520×720, sahibinin ortasında, görev çubuğunda yok; üstte başlık ve "İptal"
  (Esc) düğmesi, altında tarayıcı.
- Açılmadan önce WebView2 çalışma ortamı kurulu mu bakılır; değilse Microsoft'un WebView2 indirme sayfası
  (`https://go.microsoft.com/fwlink/p/?LinkId=2124703`) açılır ve ileti: `psnLogin.webView2Missing`. Günlüğe "WebView2 yok" anlamında bir satır yazılır.
- **Her girişte temiz oturum:** `%LOCALAPPDATA%\Nino\webview\` altındaki eski klasörler silinmeye çalışılır, yeni
  rastgele (GUID, tiresiz) adlı klasörde tarayıcı ortamı kurulur; tarayıcı süreci bitince o klasör silinir (silinemeyeni
  sonraki giriş temizler). Ortam nesnesi süreç bitene kadar canlı tutulur (yoksa "süreç bitti" olayı gelmez).
- Her belge oluşturulduğunda sayfaya küçük bir gözcü betiği eklenir: yalnız üst çerçevede; sayfanın görünür metnini
  (ilk 4000 karakter) değiştikçe, en çok **500 ms**'de bir, "nino-page-text:" önekiyle uygulamaya gönderir (Sony arka
  plan isteği düşünce Sony bu hatayı sayfayı yeniden yüklemeden gösterir; bu yüzden gezinme olaylarından anlaşılamaz).
- Gezinme başlarken adres yönlendirme önekiyle başlıyorsa gezinme iptal edilir, adres saklanır, pencere kapanır.
- Gezinme bitince (yönlendirme yakalanmadıysa): başarısız ve iptal değilse sorun = "HTTP <kod>" (kod ≥ 400) ya da web
  hata durumu adı; başarılı ama kod ≥ 400 ise "HTTP <kod>"; başarılıysa sorun silinir. Sorun (önekli) günlüğe yazılır.
- Sayfa metni iletisi Sony alanından geliyorsa (`sony.com`, `sonyentertainmentnetwork.com`, `playstation.com`,
  `playstation.net` ile biten ana bilgisayar) ve "sunucuya bağlanılamıyor" kuralına uyuyorsa: "tarayıcıya taşı"
  işaretlenir, sorun "Sony sunucuya bağlanamıyor" anlamında kısa bir not, günlüğe ana bilgisayar adıyla birlikte girişin
  tarayıcıya taşındığı yazılır, pencere kapanır.
- Tarayıcı süreci çökerse sorun "WebView2 <tür>"; ortam kurulamazsa "WebView2: <hata>" ve pencere kapanır.
- Pencere dönüşü: (yönlendirme, sorun, tarayıcıya taşı). Yönlendirme varsa sorun ve taşıma yok sayılır.

**Giriş adımı:**
- Düğme "Giriş yap" (hesap varsa `psnLogin.signInAgain`, ikincil biçim).
- Pencere tarayıcıya taşı dediyse: sistem tarayıcısında giriş sayfası açılır, adres yapıştırma alanı görünür ve neden
  satırı **`psnLogin.movedToBrowser`** gösterilir.
- Pencere yönlendirmesiz kapandıysa: sorun yoksa "pencere kapandı" iletisi; sorun "429" içeriyorsa "çok fazla deneme",
  değilse "sayfa yüklenemedi" + (sorun). Günlüğe "PSN oturumu tamamlanmadan giriş penceresi kapatıldı[: <sorun>]".
- **Tarayıcı yolu:** "tarayıcıda aç" düğmesi de aynı paneli açar (neden satırı yok). Panel açılırken panoda duran eski
  yönlendirme "son denenen" sayılır (kendiliğinden denenmesin). Uygulama penceresi yeniden etkinleşince, panel
  açıksa ve iş sürmüyorsa, panodaki metin yönlendirme ve son denenenden farklıysa alana yazılır ve gönderilir. Alanda
  Enter ya da "Kaydet" de gönderir. Alan yönlendirme değilse: **`psnLogin.paste.noCode`** Gönderilen adres "son denenen"
  olur (tek kullanımlık kod ikinci kez denenmez). Başarıda alan temizlenir, panel kapanır, panoda yönlendirme varsa
  pano temizlenir.
- **Elle hesap kimliği:** Sony girişi açılamayanlar (ör. servis sağlayıcı engelliyor) base64 kimlik yazar: boşluklar
  atılır, tam **12** karakter ve çözülünce tam **8** bayt olmalı. Geçersizse: **`psnLogin.manualId.invalid`** Geçerliyse web girişiyle aynı biçimde saklanır, günlüğe elle girildiği
  yazılır. Alanda Enter kaydeder (adımın Devam'ına gitmez).

| Giriş sonucu | İleti anlamı |
|---|---|
| Genel / beklenmedik | **`psnLogin.error.failed`** |
| Reddedildi | **`psnLogin.error.refused`** |
| Çok fazla deneme | **`psnLogin.error.rateLimited`** |
| Sunucu hatası | **`psnLogin.error.server`** |
| Ağ | **`psnLogin.error.network`** |
| Anlaşılamadı | **`psnLogin.error.badResponse`** |
| Pencere kapandı | **`wizard.psn.error.windowClosed`** |
| Sayfa yüklenemedi | **`psnLogin.error.pageLoadFailed`** |

### 1.5 Oturum (bağlanma)
Tek iş parçacıklı sıralı bir **oturum kuyruğu** vardır; bütün bağlantı işleri orada koşar. "Gecikmeli gönder" bir
zamanlayıcıyla işi sonra kuyruğa koyar. Kuyruktaki bir işin hatası günlüğe yazılır, kuyruk sürer.

**Kuşak (generation):** her başlat/durdur/hemen-yeniden-bağlan "çalışıyor" bayrağını yazar ve kuşak numarasını
artırır. Kuyruğa konan her iş, oturum olayları ve gecikmeli yeniden denemeler kendi kuşağını taşır; "çalışıyor ve kuşak
aynı" değilse hiçbir şey yapmaz. Test: kuyruk bir engelde tutulurken başlat, sahte bir oturum kutusu (kuşak 1) ve
ardından bağlandı / şifre isteği / ağ nedeniyle kapandı olayı verilip hemen durdurulursa **hiç durum olayı yayılmaz**.

- Kurulum: hesap kimliği 8 bayt değilse hata; kimlik kopyalanır; giriş şifresi normalleştirilir (§1.7).
- **Başlat:** kuşak artar (çalışıyor); kuyrukta: yeniden deneme sayacı sıfırlanır, bağlan.
- **Durdur:** kuşak artar (çalışmıyor); kuyrukta oturum kutusu kapatılır. Bloklamaz (test: < 200 ms).
- **Hemen yeniden bağlan:** çalışmıyorsa bir şey yapmaz; kuşak artar; kuyrukta kutu kapatılır, sayaç sıfırlanır,
  bağlan.
- **Bırak:** bir kez; durdur; kuyrukta kuyruk ve kare dağıtıcı kapatılır.

**Bağlan** (kuyrukta; kuşak geçerli ve açık kutu yoksa):
1. Durum "bağlanıyor".
2. Kayıtlı adrese **2 sn** arama. Yanıt yoksa **taşınma araması** (aşağıda).
3. Aramanın yanıt verip vermediği saklanır (sınıflama için). Günlüğe üç durumdan biri yazılır: arama yanıtsız kaldı ama bağlanmaya devam ediliyor; PS5 (ad, adres) uyanık; PS5 dinlenmede ve uyandırılıyor.
4. PS5 **dinlenmedeyse**: uyandırma gönderilir (hata uyarı olarak günlüğe "wake: <metin>"); **20 sn**'lik son tarihle
   uyanma beklenir: **2 sn** sonra kayıtlı adrese 2 sn arama; uyanık yanıt varsa oturum açılır; yoksa son tarih
   geçmediyse tekrar; geçtiyse **"PS5 kapalı"** nedeniyle yeniden deneme sırasına girilir.
5. Uyanıksa ya da hiç yanıt yoksa **yine de** oturum açılır.

**Taşınma araması:** en çok **30 sn**'de bir yapılır (tüm ağ taraması pahalı; PS5 kapalıyken her denemede yapılmaz).
Bütün ağ **3 sn** taranır; kayıtlı adla taşınan PS5 seçilir (§1.2). Bulunan yoksa ya da adresi aynıysa yok. Farklıysa
uyarı "PS5 yeni adreste: <eski> -> <yeni>", kayıt yeni adresle güncellenir ve "PS5 taşındı" olayı yayılır (işleyici
hatası günlüğe), bulunan döner. Uygulama yeni kaydı saklar.

Not (Mac'ten fark): Windows'ta adresin "kullanılamaz" (0.0.0.0/boş) olması ayrıca ele alınmaz.

**Oturum aç:** köprünün oturum başlatma işlevi kayıtlı adres, kayıt anahtarı ve oturum anahtarı (16 bayta kırpılıp ya
da sıfırla doldurularak), hesap kimliği ve **en çok 20 kare/sn** ile çağrılır. Başlatılamazsa günlüğe adres ve nedenle birlikte oturumun başlamadığı yazılır ve **"diğer"** nedeniyle (ayrıntı: son hata satırı, yoksa oturumun başlamadığını söyleyen sabit İngilizce kısa not) yeniden denenir. Başlarsa kutu saklanır.

**Oturum kutusu:** tek bir yerel oturumun sahibi; geri çağrıların `user` değeri ona sabitlenmiş bir tutamaçtır. Kutu
(ve tutamaç) yerel oturum durup iş parçacıkları bitene dek bırakılmaz; geç gelen geri çağrı her zaman canlı bir nesne bulur.
Kutuyu kapatmak: görüntü bekçisine "bitti" denir; kutu boşaltılır; durdurma (join içerdiği için) **arka planda**
yapılır, kuyruk bekletilmez. Durdurma ve şifre gönderme aynı kilitle korunur; durmuş kutuya şifre gönderilmez.

### 1.6 Olaylar, nedenler, yeniden bağlanma
- **Bağlandı** (kuyrukta; kutu ve kuşak bu oturumunsa): yeniden deneme sayacı **sıfırlanır**, bekçiye "bağlandı (şimdi)"
  denir, durum "akıyor", saniyelik bekçi denetimi başlar.
- **Giriş şifresi isteği:** yanıt hemen hesaplanır (§1.7); kuyrukta (kutu/kuşak geçerliyse) şifre varsa günlüğe şifre isteği ve Ayarlar'daki şifrenin gönderildiği yazılır, şifre gönderilir (olay geri çağrısından değil, kuyruktan).
  Yoksa: **çalışmıyor** yapılır (kuşak artar), kutu kapanır, "bağlı değil (şifre gerekli / şifre yanlış)".
- **Kapandı:** neden hesaplanır (aşağıda), uyarı "Oturum kapandı: neden <sayı> (<ad>) <metin>". Kuyrukta (kutu/kuşak
  geçerliyse): kutu kapanır. Neden **kayıt geçersiz** ya da **Remote Play kapalı** ise çalışmıyor yapılır ve
  "bağlı değil (neden)" — yeniden denenmez. Değilse yeniden deneme sırasına girilir.
- **Görüntü bekçisi:** bağlıyken saniyede bir bakılır. Son görüntüden (ya da bağlanmadan) bu yana **≥ 8 sn** geçtiyse:
  günlüğe kaç saniyedir görüntü gelmediği ve oturumun yeniden kurulduğu yazılır (**bu satırdaki sabit işaret
  parçası** altyazı günlüğündeki duraklama izleyicisiyle paylaşılır: izleyici satırı onunla tanır; ikisi aynı sabiti kullanır), kutu kapanır,
  "diğer" nedeniyle ayrıntı olarak "PS5'ten görüntü yok" anlamında kısa İngilizce not ile yeniden denenir. Neden: chiaki FEC onarımı tutmayınca
  bir kez IDR ister; istenen IDR de bozuk gelirse bir daha istemez, bağlantı açık kalır ama kare gelmez (kablosuz ağda
  birkaç dakikada bir). Bekçi kuralları (testler, ms): bağlandı(0), 1..120 sn her saniye görüntü → 127 000'de yok,
  128 000'de tam 8 sn; bağlandı(0), görüntü 1000 ve 2500 → 9000'de yok; bağlandı(0) → 8000'de var; bağlanmadan görüntü
  (0) → 600 000'de yok; bağlandı(0) + bitti → 600 000'de yok. Kare geri çağrısı her karede bekçiye "görüntü (şimdi)"
  der (bağlı değilken etkisiz).
- **Yeniden deneme sırası:** neden **sınıflanır** (aşağıda), "bağlı değil (neden)" yayılır; kuşak geçerliyse gecikme
  alınır ve o kadar saniye sonra bağlan. Gecikme: 2, 4, 8, 16, **30**, 30, … (sayaç her alışta artar, en çok 5); sayaç
  başlat, hemen-yeniden-bağlan ve **her başarılı bağlanma**da sıfırlanır. Testler: 7 alış → 2, 4, 8, 16, 30, 30, 30;
  iki alış + sıfırla → 2.
- **Sınıflama:** son aramada PS5 yanıt vermediyse ve neden **ağ** ya da **diğer** ise neden "**bulunamadı**", ayrıntı
  kayıtlı adres. Testler (adres 192.168.1.70): ağ + yanıtsız → bulunamadı(adres); diğer("x") + yanıtsız → bulunamadı;
  ağ + yanıtlı → ağ; kullanımda + yanıtsız → kullanımda; kodlu ret + yanıtsız → aynı kalır; kayıt geçersiz + yanıtsız →
  aynı.
- Her durum (bağlanıyor hariç) günlüğe "PS5 oturumu: <evre>[ <neden> <ayrıntı>]". Durum işleyicisi hatası günlüğe.

**Köprünün kapanma nedeninden kullanıcı nedenine:**
- 0 → durduruldu; 1 → kullanımda; 2 → reddetti; 3 → ağ; 4 → diğer (metin = köprünün metni). Testler: kullanımda ve
  durduruldu metinsiz; reddetti metni yok sayılır ("ignored" → yalnız reddetti); diğer "Version Mismatch" → diğer
  ("Version Mismatch").
- **Oturum isteği ipucu:** Oturum isteği (TCP 9295) başarısız olunca chiaki'nin kapanma metni yalnız "Unknown Session Request Error"dır; gerçek neden ondan hemen önce yazılan hata satırındadır. Oturum
  kutusu hata düzeyindeki her günlük satırını ipucu çıkarıcısına verir ve son ipucunu saklar (ayrıca son hata satırını
  "başlatma hatası" olarak saklar):
  - Satırda "Reported Application Reason:" varsa: ardından boşlukları atıp ilk sözcük alınır; "0x" (büyük/küçük harf
    duyarsız) atılır; onaltılık okunamazsa ipucu yok. 0x80108b12 → **Remote Play kapalı**; 0x80108b09, 0x80108b02,
    0x80108b26 (PS5 eşleme anahtarını bulamadı: eşleme silinmiş ya da başka hesapla yapılmış) → **kayıt geçersiz**;
    başka kod → **kodlu ret**, ayrıntı "0x" + 8 haneli küçük harf onaltılık.
  - Değilse satırda "Session request connect failed eventually", "Failed to send session request" ya da "Failed to
    receive session request response" geçiyorsa → **ağ** (PS5 yeni uyandıysa ilk denemelerde olağan).
  - Değilse ipucu yok.
  - Testler: "…0x80108b09 (Regist failed, probably invalid PIN)" → kayıt geçersiz; "…0x80108B02 (Invalid PSN ID)" →
    kayıt geçersiz; "…0x80108b26 (unknown)" → kayıt geçersiz; "…0x80108b12 (unknown)" → Remote Play kapalı;
    "Session request connect failed eventually." / "Failed to receive session request response" / "Failed to send
    session request" → ağ; "…0x80108bff (unknown)" → kodlu ret("0x80108bff"); "Reported Application Reason: zzz",
    "Session request successful", "Failed to parse session request response", yok → ipucu yok.
- **Birleştirme:** köprü nedeni 4 **ve** metin tam "Unknown Session Request Error" ise ipucu, ipucu yoksa **kodsuz
  ret** (PS5 oturumu başlatmadı). Başka her durumda yalnız köprü nedeni (ipucu yok sayılır: "Version Mismatch" +
  ipucu → diğer("Version Mismatch"); kullanımda + ipucu → kullanımda).

Mac'ten farklar (Windows böyle; yeni Windows da böyle yapmalı): yeniden deneme sayacı her bağlanmada sıfırlanır (60 sn
kuralı yok); "kullanımda"da en az 8 sn kuralı yok; art arda görüntüsüz oturumda vazgeçme yok (bekçi her seferinde
yeniden kurar); yerel ağ izni uyarısı yok. **Vazgeçilen nedenler yalnız dört:** kayıt geçersiz, Remote Play kapalı,
şifre gerekli, şifre yanlış.

**Ana ekran metni (PS5 kaynağı):**

| Durum | İleti anlamı |
|---|---|
| Akıyor | **`status.common.connected`** |
| Bağlanıyor | **`status.common.connecting`** |
| Çeviri yok, PS5 eşli | **`status.ps5.pairedIdle`** (ad boşsa "PS5") |
| Çeviri yok, PS5 yok | **`status.common.notConnected`** |
| PS5 kapalı | **`status.ps5.asleep`** |
| Kullanımda | **`status.ps5.inUseElsewhere`** |
| Reddetti | **`status.ps5.refused`** |
| Şifre gerekli | **`status.ps5.passcodeRequired`** |
| Şifre yanlış | **`status.ps5.passcodeWrong`** |
| Kayıt geçersiz | **`source.ps5.status.registrationInvalid`** |
| Remote Play kapalı | **`status.ps5.remotePlayOff`** |
| Bulunamadı | **`status.ps5.notFound`** (ayrıntı yoksa "?") |
| Ağ | **`status.ps5.unreachable`** |
| Kodlu ret | **`status.ps5.sessionRejectedCode`** |
| Kodsuz ret | **`status.ps5.sessionRejected`** (aynı devam) |
| Diğer, ayrıntılı | **`status.common.reconnectingDetail`** (ör. görüntü yok notu ya da chiaki-ng'nin "Version Mismatch" nedeni) |
| Diğer / durduruldu | **`status.common.reconnecting`** |

Durum noktası: akıyorsa yeşil; çeviri sürüyor ama akmıyorsa turuncu; değilse gri.

### 1.7 Giriş şifresi (4 hane)
- Normalleştirme: baştaki/sondaki boşluk atılır; tam 4 karakter ve hepsi ASCII 0–9 olmalı; değilse yok. Testler:
  " 1234 " → "1234"; "0007" → "0007"; yok, "", "123", "12345", "12a4", "١٢٣٤" (Arapça rakam) → yok.
- Yanıt (kayıtlı, yanlış mı): yanlışsa (PS5 yeniden istiyor) gönderilmez → **şifre yanlış**; kayıtlı geçerli şifre
  varsa ASCII baytları gönderilir (test: "1234" → 31 32 33 34); yoksa → **şifre gerekli**. Aynı şifre ikinci kez
  gönderilmez (PS5 aynı yanlış şifreyle durmadan reddetmesin).
- Ayarlar'da: geçerliyse kaydedilir (geçersizse reddedilir), kaldırılabilir; "Kurulumu baştan yap" (sıfırlama) onu da siler.

### 1.8 Kare dağıtıcı
Kareleri yerel iş parçacığından alıp kendi (arka plan, "Nino frames") iş parçacığında iletir. İşleyici doluyken ya
da bekleyen kare varken gelen kare **kopyalanmadan atlanır** (ağ iş parçacığı beklemez, gereksiz bellek ayrılmaz).
Kabul edilen kare sıkı adımla (genişlik×4) kopyalanır. İşleyici hatası günlüğe. Kapatılınca bekleyen kare atılır.
Test: 2×2 kare, satır adımı 12 (4 bayt dolgu), pikseller 1..8,0000,9..16,0000 → ilk teslim (işleyici bekletilirken
ikinci kare atlanır) → serbest bırakıp 100 ms sonra üçüncü kare teslim edilir; toplam **2** teslim, ilkinin adımı 8,
pikselleri 1..16.

### 1.9 Remote Play günlüğü (`%LOCALAPPDATA%\Nino\remoteplay.log`)
- Kaynaklar: chiaki satırları "[chiaki <error|warning|info>] <satır>", uygulama satırları "[nino] <satır>". Dinleyici
  hatası çağıranı düşürmez.
- Yazıcı: satırlar "[yyyy-MM-dd HH:mm:ss] " önekiyle en çok **2000** satırlık sınırlı kuyruğa (dolunca atılır), arka
  plan iş parçacığı dosyaya ekler; dosya **1 MB**'yi geçince içeriğin **ilk yarısı** silinir. Yazma hatası yok
  sayılır. Kullanıcıya gösterilen yol `%LOCALAPPDATA%\Nino\remoteplay.log`.
- Aynı satırlar sağlık kaydına ve altyazı günlüğündeki **duraklama izleyicisine** verilir: "FEC failed" ya da "Video
  FEC failure" → (zaten duraklamada değilse) "görüntü durdu, IDR bekleniyor" anlamında satır; "Received IDR frame"
  → (duraklamadaysa) "görüntü sürdü" + boşluk süresi (ms); bekçi satırı (sabit işaretle tanınır) → "IDR gelmeyecek, oturum
  yeniden kuruluyor" + varsa boşluk süresi.
- Testler (yerel kütüphane varsa): 127.0.0.1'e 600 ms arama boş döner, 0,4–5 sn sürer; 127.0.0.1'e oturum (anahtar
  16×0x31, oturum anahtarı 16×0x01, hesap 8×0x01) 15 sn içinde "bağlı değil" verir (neden durduruldu değil), durdur
  < 200 ms döner, bırakıp 3 sn beklenir (bekleyen yeniden deneme çökmemeli). Kütüphane yoksa (Mac, DLL'siz derleme)
  bu testler atlanır.

### 1.10 Windows'a özgü (PS5 yolu)
- Yerel kütüphane `nino_native.dll` P/Invoke ile, cdecl; geri çağrılar yönetilmeyen-çağrılabilir durağan işlevler,
  nesneye sabitlenmiş tutamaçla ulaşılır. Geri çağrılardan istisna **asla** sızmamalı (süreç uyarısız kapanır).
- "Kütüphane yüklenebiliyor mu" denetimi: yüklemeyi dener, bırakır.
- İlk kullanımda bir kez ağ yığını başlatılır; sıfır dışı dönüş, dönüş kodunu içeren "yerel kütüphane başlatılamadı" hatası.
- Uyandırma köprü hatası: dönüş kodunu içeren "uyandırma gönderilemedi" hatası.
- Köprüye giden anahtarlar sabit uzunluğa getirilir: verilen baytların başı kopyalanır, eksik kalan sıfırla
  doldurulur, fazlası kesilir (testler: [1,2] → 4 bayt [1,2,0,0]; [1,2,3] → 2 bayt [1,2]). Köprüden gelen sabit
  uzunluklu ad ilk sıfır bayta kadar UTF-8 okunur (test: "PS5-123\0garbage" → "PS5-123").

---

## 2. Pencereden okuma (bu bilgisayarda PS Remote Play / chiaki-ng ya da Xbox penceresi)

İki ayrı okuyucu vardır. **Ana okuyucu** (§2.1–2.5, GDI) görüntü kaynağı "Window" iken; **Graphics.Capture
okuyucusu** (§2.6) eski kare kaynağı 1/2 iken kullanılır.

### 2.1 Pencere seçme kuralları
- Aday: görünür, simge durumunda olmayan, Nino'ya ait olmayan her üst düzey pencere; süreç adı (önbellekli; okunamazsa
  boş), başlık (en çok 256 karakter) ve **içerik alanı** (başlık çubuğu ve kenarlık hariç, ekran pikseliyle; içerik
  alanı boşsa aday değil).
- **PS5:** süreç adı + " " + başlık (küçük harf) "remoteplay", "remote play" ya da "chiaki" içeren ve içerik alanı en az
  **320×180** olanlardan alanı en büyük.
- **Xbox:** süreç adı (küçük harf) "xboxpcapp" ya da "greenlight" içeren **ya da** süreç adı tarayıcı listesinde
  (`chrome`, `msedge`, `firefox`, `brave`, `opera`, `vivaldi`, `arc`) olup başlığında (büyük/küçük harf duyarsız)
  "xbox" geçen; en az 320×180; en büyük.
- **Gösterilen ad:** süreç "chiaki" içeriyorsa "chiaki-ng"; "greenlight" → "Greenlight"; "xboxpcapp" → "Xbox"; tarayıcı
  → "xbox.com/play"; değilse "PS Remote Play".
- Testler (PS5): [chrome 1600×900, RemotePlay 400×300, RemotePlay 1280×720 (3), chiaki 200×100] → 3; chiaki-ng
  960×540 → seçilir; süreç "app", başlık "PS Remote Play" 960×540 → seçilir; RemotePlay 300×150 → yok; explorer
  1200×800 → yok. (Xbox): [chrome "Hava durumu - Google Chrome" 1800×1000, msedge "Xbox Cloud Gaming on Xbox.com -
  Microsoft Edge" 1400×800 (2), RemotePlay 1600×900 (3), notepad "xbox alışveriş.txt" 1700×900] → 2; + XboxPcApp "Xbox"
  1500×850 (5) → 5; Greenlight 300×150 → yok; aynı liste PS5 için → 3. Ad: XboxPcApp → "Xbox", msedge → "xbox.com/play",
  RemotePlay → "PS Remote Play".

### 2.2 Oyun alanı
Remote Play görüntüyü pencereye 16:9 sığdırıp ortalar; alan **piksellerden değil ölçüden** hesaplanır: genişlik =
içerik genişliği, yükseklik = genişlik / (16/9); yükseklik içerikten büyükse yükseklik = içerik yüksekliği, genişlik =
yükseklik × 16/9. İkisi yuvarlanır; sol = yuvarla(içerik sol + (içerik gen. − gen.)/2), üst aynı biçimde. Testler:
(100,50,1280,720) → aynı; (0,0,2000,720) → (360,0,1280,720); (0,0,1920,1200) → (0,60,1920,1080); kart penceresi
(0,0,3440,1350) → (520,0,2400,1350); (−1600,100,1280,720) → aynı.
Mac'ten fark: Windows içerik alanını kullandığı için başlık çubuğu ayrıca düşülmez.

**Altyazı penceresinin oyun alanındaki yeri:** genişlik = yuvarla(oyun gen. × 0,9), alt = oyun alt − oyun yük. × 0,03,
sol = yuvarla(oyun sol + (oyun gen. − gen.)/2), üst = yuvarla(alt − pencere yüksekliği). Test: oyun (100,100,1000,500),
pencere 200 → gen. 900, sol 150, üst 100+500−15−200.

### 2.3 Okuma döngüsü (ana okuyucu)
- Ayrı arka plan iş parçacığı ("Nino oyun penceresi"); iş parçacığı **monitör başına DPI farkında (v2)** çalışır
  (farklı ölçekli ikinci ekrandaki pencere de tam boyuyla ölçülsün).
- Çıktı her zaman **1920×1080** BGRA; **saniyede 10** kare (her turun kalanı kadar uyunur); pencere her **1,5 sn**'de
  bir yeniden aranır; mevcut pencere artık yoksa hemen aranır.
- Ekranda hiçbir şey değişmese bile kare düzenli aralıkla gönderilir (hat altyazının bittiğini görüp kaldırabilsin).
- Kare alınırken hata olursa altyazı günlüğüne "oyun penceresi okunamadı: <tür>: <metin>" ve pencere unutulur.
- Bulunamazsa durum "pencere aranıyor"; bulunursa "okunuyor (ad)" ve oyun alanı bildirilir. Yeni pencere seçilince
  ekran-kopyası kipi ve siyah sayacı sıfırlanır.
- Her karede içerik alanı yeniden okunur; değiştiyse (taşındı/büyüdü) pencere bilgisi güncellenir ve oyun alanı
  yeniden bildirilir.
- **Kare alma:**
  1. Ekran-kopyası kipinde değilsek, ya da kipteyken her **20** karede bir: pencerenin kendisi istenir (pencere içeriği
     yazdırma; "yalnız içerik alanı" + "tam içerik" bayrakları: DirectX ile çizen pencereler de verilir). Kaynak yüzey
     içerik boyunda tutulur. Sonuç başarılı ve oyun alanı siyah değilse: kip kapatılır (kipteyse günlüğe pencerenin yeniden kare verdiği ve ekran kopyasının bırakıldığı yazılır), sayaç sıfırlanır, oyun alanı 1920×1080'e ölçeklenir → kare.
     Değilse ve kipte değilsek siyah sayacı artar; **< 30** ise (3 sn; yayın başı/yükleme gerçekten siyahtır) **siyah
     kare** verilir (hat boş ekran görür ve ekrandaki eski altyazıyı kaldırır).
  2. Ekranın o alanı kopyalanır (oyun alanının ekrandaki yeri → 1920×1080). Kipte değilsek: ekran da siyahsa sahne
     gerçekten karanlıktır → sayaç sıfırlanır, bu kare verilir, kipe geçilmez. Değilse kipe geçilir, günlüğe pencerenin kare vermediği ve ekran kopyasına geçildiği yazılır. Ekran kopyasında Nino'nun altyazı penceresi ekran
     kopyalarından gizlenir (altyazı penceresi belgesinde).
- **Siyah mı:** alanın içinde 8×8 = 64 noktaya (sütun/satır 1..8, alan × k/9) bakılır; hepsinin RGB'si 0 ise siyah.
- Ölçekleme "yarım ton" (halftone) yöntemiyle (küçültmede yazı bozulmasın), kopyalama "kaynak kopyala + yakalanan
  katmanlar" (CAPTUREBLT) ile.
- **Altyazı penceresine giden oyun alanı** WPF birimiyle: iş parçacığı bir an **sistem DPI** farkındalığına geçer,
  içerik alanı o birimle okunur, oyun alanı hesaplanır, eski farkındalığa dönülür.
- Durum her değişimde "pencere durumu (durum, ad)" ve genel evre (okunuyor → akıyor, aranıyor → bağlanıyor, durdu →
  bağlı değil/durduruldu) yayılır; oyun alanı değişince ayrıca yayılır. Durdurulduktan sonra artık olay yayılmaz.
- **Durdur:** beklemeden döner; döngü en çok bir tur sonra biter. **Hemen yeniden bağlan:** pencere unutulur.
- PS5 taşındı olayı bu kaynakta hiç yayılmaz.

### 2.4 Ana ekran metni
| Durum | PS5 | Xbox |
|---|---|---|
| Okunuyor | **`status.common.reading`** (ad; yoksa "PS Remote Play") | aynı (yoksa "Xbox") |
| Aranıyor ya da durdu ama çeviri sürüyor | **`status.gameWindow.ps5.startPlaying`** | **`status.gameWindow.xbox.startPlaying`** |
| Durdu | **`status.gameWindow.ps5.idle`** | **`source.window.xbox.idle`** |

Altyazı günlüğüne: görüntü kaynağının oyun penceresi olduğu; pencere durumu (okunuyor + ad / bulunamadı / durdu). Test: pencere kaynağıyla başlatınca PS5 oturumu açılmaz, pencere kaynağı başlar, metin "Open PS
Remote Play…"; "okunuyor (PS Remote Play, alan 0,0,1280,720)" → evre akıyor, metin "Reading PS Remote Play", oyun alanı
o; durdurunca kaynak durur, alan yok, pencere durumu "durdu".

### 2.5 Kurulum yolları (özet; ayrıntı `kurulum.md`)
- `setup.welcome.shortcutRemotePlay`: kaynak Window, konsol PS5, çıktı bilgisayar; çeviri modeli adımına
  geçilir. Geri → karşılama.
- `setup.welcome.shortcutXbox`: kaynak Window, konsol Xbox; TV adımı; Geri → karşılama; "TV'm yok" ile bilgisayar.
- Ayarlarda konsol Xbox'a geçince kaynak Window olur; PS5'e dönünce kaynak (ör. Card) korunur.

### 2.6 Graphics.Capture okuyucusu (eski "Remote Play penceresi" ve "seçilen pencere")
- İki kurulum: (a) uygulama seçimiyle — süreç adları Sony: `RemotePlay`; chiaki: `chiaki`, `chiaki-ng`; "hangisi
  açıksa": ikisi birden. (b) kullanıcının seçtiği pencere — süreç adı ve başlık boş olamaz (hata), yalnız o süreç ve
  **başlığı tam eşleşen** pencere; uygulama açılmaz.
- **Başlat:** kuşak artar, durum "bağlanıyor" (aynı durum iki kez yayılmaz: her "bağlı değil" okuma hattını
  sıfırlıyor). (a)'da seçili uygulamalardan hiçbiri çalışmıyorsa kurulu olan ilki açılır (günlük "<ad> açılıyor" /
  "Remote Play açılamadı: <metin>").
- **Kurulu yol** (ilk var olan): Sony için `Program Files (x86)\Sony\PS Remote Play\RemotePlay.exe`, sonra
  `Program Files\…`; chiaki için `Program Files`, `Program Files (x86)`, `%LOCALAPPDATA%\Programs` altında
  `chiaki-ng\chiaki.exe` ve `chiaki-ng\chiaki-ng.exe`. `settings.source.remotePlayApp.automatic`'da Sony önce. "Kurulu mu" bununla.
- **Arama döngüsü** (her **2 sn**): görünür, simge olmayan, **sahibi olmayan** üst düzey pencereler; süreç adı (büyük/
  küçük harf duyarsız) listede; (b)'de Nino'nun kendi süreci hariç ve başlık eşleşmeli; pencere dikdörtgeni en az
  **400×250**; en büyük alan. Bulunursa yakalama kurulur, günlüğe "<süreç> penceresi okunuyor: G×Y", durum "akıyor".
  Kurulamazsa günlüğe yakalama hatası ve "bağlı değil (diğer, hata metni)". Bulunamazsa bir kez günlüğe beklenen pencere (seçilen pencerede süreç ve başlık; Remote Play'de PS Remote Play ya da chiaki-ng beklendiği) yazılır ve durum "bağlanıyor".
- **Yakalama:** Direct3D 11 donanım aygıtı (BGRA desteği), pencereden yakalama öğesi, serbest iş parçacıklı **2**
  karelik havuz (B8G8R8A8), imleç yakalanmaz. Pencere kapanınca "pencere kapandı" ile yeniden aranır (çeviri durmaz).
  Kare boyu değişince havuz yeni boya kurulur, o kare atlanır. Saniyede en çok **10** kare; önceki kopya sürüyorsa
  atlanır. Kare işlemci belleğine kopyalanır (önceden çarpılmış alfa), **pencerenin kendi boyunda** verilir (1080p'ye
  ölçeklenmez); 2×2'den küçükse atlanır. Kopya hatası günlüğe.
- **Sarı çerçeve:** Windows yakalanan pencereyi sarı çerçeve çizer. Sistem sürümü ≥ 10.0.20348 ve "çerçeve
  gerekli mi" özelliği varsa çerçevesiz yakalama izni istenir; izin verilirse çerçeve kapatılır. Değilse (Windows 10 ev
  sürümleri, ya da Windows 11'de "Ekran görüntüsü kenarlıkları" kapalı) çerçeve kalır, nedeni günlüğe **bir kez**
  yazılır. Yakalama her durumda sürer.
- **Siyah uyarısı:** her karede 4×997 baytta bir örnek; hepsi RGB < 10 ise siyah. Art arda **40** siyah karede (4 sn)
  bir kez günlüğe pencere adıyla "siyah geliyor, yakalama engelleniyor olabilir" anlamında satır ve "bağlı değil (diğer)" ileti
  ile: seçilen pencerede `source.window.selected.black`; değilse **`source.window.rpApp.black`**. Siyah olmayan ilk karede "akıyor"a döner.
- **Pencere listesi** (Ayarlar'daki seçici için): aynı görünürlük/sahip/boy kuralları, Nino'nun kendisi hariç (geri
  besleme olmasın), başlığı boş olmayanlar; tekrarsız, süreç adına sonra başlığa göre sıralı.
- **Durdur:** kuşak artar, arama iptal, yakalama bırakılır, "bağlı değil (durduruldu)". **Hemen yeniden bağlan:**
  çalışıyorsa kuşak artar, bırakılır, "bağlanıyor", yeniden aranır.
- Ana ekran metni (uygulama seçimli): kurulu değilse ve akmıyorsa **`source.window.rpApp.notInstalled`**; akıyor → `status.remotePlayWindow.reading`; bağlanıyor →
  `status.remotePlayWindow.waiting`; çeviri yok → `source.window.rpApp.idle`; bağlı değil →
  ayrıntı varsa o, yoksa "bekleniyor" metni.
- Ana ekran metni (seçilen pencere): seçim yoksa `source.window.selected.none`; akıyor → `status.selectedWindow.reading`; çeviri yok → `source.window.selected.ready`;
  diğer → ayrıntı ya da `status.selectedWindow.waiting` (başlık).
- Konsol başlığı bu kipte `status.console.titleSelectedWindow`.

### 2.7 Windows'a özgü (pencere)
- Ana okuyucu yalnız Win32/GDI: pencere listeleme, görünürlük/simge/var mı denetimi, süreç kimliği, başlık, içerik
  alanı + ekrana çevirme, iş parçacığı DPI farkındalığı (−4 monitör başına v2, −2 sistem), pencere içeriği yazdırma
  (bayrak 0x1|0x2), ekran DC'si, uyumlu DC + üstten alta 32 bit DIB bölümü (eksi yükseklik), StretchBlt (HALFTONE = 4,
  fırça başlangıcı 0,0; SRCCOPY 0x00CC0020 | CAPTUREBLT 0x40000000), GdiFlush.
- İkinci okuyucu: Windows.Graphics.Capture (pencere için yakalama öğesi üretme COM arabirimi), D3D11 aygıtı (sürücü
  türü donanım = 1, bayrak BGRA desteği 0x20, SDK sürümü 7) ve WinRT aygıtına çevirme, yazılım bitmap'e kopyalama,
  çerçevesiz yakalama izni (`GraphicsCaptureAccess`, "Borderless").

---

## 3. HDMI yakalama kartları (HDMI → USB)

Kartlar Windows'a kamera olarak tanıtılır (UVC). Yalnız Windows'un kendi API'leri (Windows.Media.Capture,
Windows.Media.Audio). İki kullanım: geçişli kart → TV (bilgisayar yalnız okur) ve kart → bilgisayar → ekran (Nino oyunu
tam ekran gösterir, sesini çalar; altyazı bilgisayardaysa bu kip).

### 3.1 Aygıt seçimi
- Aygıt: kimlik, ad, **kap** (Windows "System.Devices.ContainerId"; aynı USB kartın görüntü ve ses aygıtları tek kapsayıcıdadır; bilinmiyorsa boş). Etkin görüntü yakalama aygıtları listelenir (liste hatası günlüğe, boş liste).
- Kullanıcının seçtiği aygıt takılıysa o. Değilse adı (küçük harf) web kamerası listesinden bir şey içermeyenler
  arasından kart ipucu içeren ilki, yoksa kalan ilki.
  - Web kamerası: `webcam`, `logitech`, `brio`, `c920`, `c922`, `integrated camera`, `integrated webcam`, `front`,
    `rear`, `ir camera`, `hd camera`, `facetime`.
  - Kart ipucu: `capture`, `hdmi`, `elgato`, `avermedia`, `live gamer`, `game`, `cam link`, `razer`, `ripsaw`,
    `ugreen`, `usb video`, `uvc`, `hd60`, `4k x`, `4k s`, `magewell`, `video`.
  - Örnekler: [Dell FHD Webcam, AVerMedia Live Gamer 4K, Logitech StreamCam] → AVerMedia…; [ASUS HD Camera,
    UVC Capture] → UVC Capture ("hd camera" eler); [Surface Camera Front, Surface Camera Rear] → yok; [IR Camera,
    NoName 4K60, Misc] → NoName 4K60; [] → yok; seçili "b" takılı → b; seçili "gone" → kendiliğinden (a).
- **Kartın ses aygıtı:** kartın kabı boş değilse ve **sistem kabı** değilse (`{00000000-0000-0000-ffff-ffffffffffff}`,
  büyük/küçük harf ve süslü parantez farkı yok sayılır: bilgisayarın kendi aygıtları; bunlarla eşlenirse dahili mikrofon sesi hoparlöre giderdi) aynı kaptaki ilk ses aygıtı; yoksa adı (küçük harf, boş değil) kartın adını içeren
  ya da onun içinde geçen; yoksa ses çalınmaz. Örnekler: kart "AVerMedia Live Gamer 4K" kap {5678} + [Mikrofon (USB
  Audio) {4321}, Line In (Live Gamer) {5678}] → Line In…; kapsız "UGREEN Capture" + [Speakers, UGREEN Capture] → UGREEN
  Capture; [Speakers] → yok; sistem kaplı "Onboard HDMI Grabber" + sistem kaplı mikrofon → yok.

### 3.2 Bağlanma
- **Başlat:** kuşak artar; görüntü aygıtı izleyicisi (eklendi/çıkarıldı → "aygıtlar değişti" olayı + **700 ms** sonra
  bir kez bağlan; art arda gelen olaylar birleşir) — açılamazsa günlüğe; hemen bağlan; saniyede bir **takılma
  denetimi**.
- **Bağlan** (tek seferde bir tane; kuşak geçerliyse): aygıtlar listelenir, seçilir. Yoksa bırakılır, durum "kart yok".
  Aynı kart zaten okunuyorsa ve "yeniden aç" istenmediyse bir şey yapılmaz. Değilse bırakılır ve açılır.
  - Erişim reddi (Windows kamera izni kapalı) → bırakılır, durum "izin yok", **5 sn** sonra yeniden.
  - Diğer hata (çoğu zaman kartı başka bir program tutuyordur: OBS, üreticinin yazılımı ya da Nino'nun kendi kurulum önizlemesi) → günlüğe
    "yakalama kartı açılamadı: <tür>: 0x<HRESULT> <metin>", bırakılır; durum görüntü veriyor değilse "kart yok";
    **3 sn** sonra yeniden.
- **Aç:** yakalama oturumu yalnız görüntü, aygıt kimliğiyle, **işlemci belleği**, **özel denetim**. Oturum hata verirse
  günlüğe hata kodu (0x…) ve metniyle kartın koptuğu, kart unutulur, **1 sn** sonra yeniden. `settings.section.pictureSource`: renk
  türündeki kaynaklardan önce "kayıt" akışı olan; yoksa "kartta görüntü akışı yok" anlamında hata.
  - **Biçim seçimi:** genişlik, yükseklik, kare hızı > 0 olanlar; sırayla: tam 1920×1080 önce; sonra kare hızı (60'ta
    kırpılıp yuvarlanmış) yüksek; sonra 1080'e yükseklik farkı az; sonra sıkıştırılmamış (`NV12`, `YUY2`, `RGB32`,
    `ARGB32`, `BGRA8`, `UYVY`, `I420`, `IYUV`; büyük/küçük harf duyarsız; MJPG'yi açmak hem gecikme hem işlemci yükü getirir).
    Testler: [3840×2160@30 NV12, 1920×1080@30 NV12, 1920×1080@60 MJPG, 1920×1080@59.94 YUY2, 1280×720@60 NV12] →
    1920×1080@59.94 YUY2; [3840×2160@30, 1280×720@60, 640×480@60 YUY2] → 1280×720@60 NV12; [] → yok. Biçim
    ayarlanamazsa günlüğe, varsayılanla sürülür.
  - Kare okuyucu: **BGRA8**, **1920×1080** istenerek (Windows çoğunlukla ekran kartıyla çevirir), gerçek zamanlı kip
    (geç kareler atılır). Başlamazsa "kart okunamadı: <durum>" hatası.
  - Siyah bekçisi sıfırlanır, son kare anı şimdi; günlüğe "yakalama kartı açıldı: <ad>, <G×Y fps biçim | varsayılan
    biçim>"; durum "okunuyor (ad)"; ses isteniyorsa ses açılır.
- **Ses** (oyun bu bilgisayarda gösteriliyorsa): ses yakalama aygıtları listelenir, kartın ses aygıtı bulunur (yoksa
  günlüğe "ses aygıtı bulunamadı; ses çalınmıyor"). Ses grafiği "oyun medyası" kategorisinde, **en düşük gecikme**
  boyutunda; varsayılan çıkış düğümü ve kartın ses girişi (medya kategorisi) düğümü; giriş → çıkış bağlanır, başlatılır.
  Herhangi bir adım olmazsa (erişim reddi: Windows mikrofon izni kapalı — kartın sesi mikrofon gibi görünür) günlüğe
  yazılır, **görüntü yine okunur**. Mac'ten fark: kayıt için ayrıca ses örneği alınmaz.
- **Bırak:** ses durdurulup bırakılır, okuyucu durdurulup bırakılır, oturum bırakılır.
- **Durdur:** bloklamaz; zamanlayıcılar ve izleyici durur, durum "durdu"; bırakma arka planda. Durduktan sonra olay
  yok. **Yenile** (uykudan uyanma, başka aygıt seçildi, takılma): kart unutulur, "yeniden aç" ile hemen bağlan.
- Durum yalnız değişince ve kuşak geçerliyken yayılır.

### 3.3 Kare
- Her karede son kare anı yazılır. Önceki kare hâlâ işleniyorsa yenisi atlanır (birikme yok).
- En son kare alınır; BGRA8 değilse BGRA8'e çevrilir (alfa yok sayılır). Arabellek kilitlenir, ilk düzlemin
  başlangıç, genişlik, yükseklik, adımı okunur; tutarsızsa atlanır.
- **Ekran yüzeyi** varsa kartın tam hızında ona verilir (§3.5).
- **Okuma hattı:** saniyede **10** (şimdi − son ≥ 0,1 − 0,002 sn); siyah denetimi ve durum ("siyah" ya da "okunuyor");
  kare 1920×1080'e kopyalanır (aynı boydaysa düz kopya, değilse en yakın komşu: sütun = min(gen.−1, x·gen./1920),
  satır = min(yük.−1, y·yük./1080)). Testler: (0, −∞) → evet; (0,05, 0) → hayır; (0,1, 0) → evet.
- **Siyah kare:** y ve x 16'dan başlayıp 32 adımla örneklenir; herhangi bir örneğin B, G ya da R'si **> 24** ise siyah
  değil (tampon taşarsa siyah sayılır). Testler: 640×360 hepsi 0 → siyah; hepsi 20 → siyah; hepsi 40 → değil;
  satır adımı 700×4 dolgulu 0'lar → siyah; (16,16) pikselinin yeşili 200 → değil.
- **Siyah bekçisi:** siyah gelmeye başladığı an saklanır; **≥ 4 sn** kesintisiz siyahsa "siyah görüntü". Testler:
  (siyah, 10) hayır; (siyah, 13,9) hayır; (siyah, 14) evet; (siyah değil, 14,1) hayır; (siyah, 15) hayır; (18,5) hayır;
  (19) evet.
- **Takılma bekçisi:** saniyede bir; çalışıyor, kart ve okuyucu açıkken: sessizlik < **3 sn** ise aralık 3 sn'ye döner;
  değilse son yeniden açmadan bu yana aralık geçtiyse: aralık iki katına (en çok **30 sn**), günlüğe kaç saniyedir kare gelmediği ve kartın
  yeniden açıldığı, yenile. (Kart sinyali yeniden kurunca ses akarken görüntü donabiliyor.)

### 3.4 Durum ve metinler
- Durum → evre: okunuyor ya da siyah → akıyor; durdu → bağlı değil (durduruldu); izin yok, kart yok → bağlanıyor.
- Durum noktası: siyah görüntüde **turuncu**, okunuyorda yeşil.

| Durum | İleti anlamı |
|---|---|
| Durdu | **`status.card.idle`** |
| İzin yok | **`status.card.noPermission`** |
| Kart yok | **`status.card.notPlugged`** |
| Siyah | **`status.card.black`** |
| Okunuyor | **`status.common.reading`** (ad; **`status.card.defaultName`**) |

Türkçede `status.card.defaultName` İngilizce kalır (test). Altyazı günlüğüne: görüntü kaynağının yakalama kartı olduğu (oyun bu
bilgisayarda gösteriliyorsa o da) ve kart durumu (izin yok / bulunamadı / siyah + ad / okunuyor + ad / durdu). Seçilen aygıt şifreli depoda `captureCardId` (yok = kendiliğinden); test: "card-1" kaydedilir ve kaynağa
verilir.

### 3.5 Kartın görüntüsünü bilgisayarda gösterme kipi
- Kaynak başlarken, kart açılmadan **önce** (ilk kareden itibaren görünsün) arayüz iş parçacığında kurulur; yüzeyi
  kartın ekran yüzeyi yapılır, tam ekran açılır.
- Başlık "Nino", siyah zemin, uygulama simgesi (yoksa yine açılır), sağdan sola arayüzde de görüntü aynalanmaz.
- Üstte ortada ipucu kutusu (beyaz 15 pt, zemin %59 siyah — alfa 150/255, köşe 18, iç boşluk 18/9, üstten 28): `source.card.gameWindow.hint`. **4 sn** sonra **0,8 sn**'de söner; tıklamayı geçirir.
- **Tam ekran:** (yüklüyse ve normal durumdaysa pencere yeri saklanır) kenarsız, boyutlanamaz; çalışma alanının sol
  üstüne, en az 640×360 ya da yarı boyda konup **büyütülür** (görev çubuğunu da örter, ana ekranda açılır).
- **Pencereye al:** normal, kenarlı, boyutlanabilir; saklı yer yoksa genişlik = min(1280, çalışma alanı × 0,8),
  yükseklik = gen.×9/16 + başlık çubuğu + 2 × yatay kenar; ortalanır.
- **Esc** tam ekranı açar/kapatır (küçültülmüşse önce normal); ana ekrandaki "tam ekran" komutu da aynı. Fare durunca
  **2,5 sn** sonra imleç gizlenir. Gösterilirken ekran uykusu engellenir; kapanınca kalkar.
- Oyun alanı (yüzeyin kabının ekrandaki dikdörtgeninde 16:9 alan, ekran pikseliyle — uygulama sistem DPI'ıyla çalışır)
  her boyut/yer/durum değişiminde, yalnız değişince bildirilir; küçültülünce/kapanınca "alan yok".
- Kullanıcı kapatırsa "kullanıcı kapattı" → kaynak ekran yüzeyini bırakır, "oyun penceresi kapandı" yayar → çeviri
  durur. Çeviri durunca pencere **sessizce** kapanır (bu olay yayılmaz).
- **Ekran yüzeyi:** kart her kareyi okuma iş parçacığında havuzdan alınan bir arabelleğe (sıkı adımla) yazar ve "son
  kare" yapar; önceki alınmadıysa o havuza döner (atlanır). Arayüz her ekran yenilemesinde (yüzey yüklüyken) yalnız en
  son kareyi alır, boy değiştiyse yeni 96 DPI **Bgr32** yazılabilir bitmap kurar (saydamlık baytı yok sayılır; bazı
  kartlar 0 verir), pikselleri yazar, arabelleği havuza döndürür. Gecikme en çok bir yenileme (~17 ms @60 Hz). Uniform
  sığdırma, doğrusal ölçekleme. "Temizle" son kareyi ve görüntüyü siler.

### 3.6 Windows'a özgü (kart)
- `DeviceInformation` (görüntü/ses yakalama sınıfı, kap özelliği), `DeviceWatcher`, `MediaCapture` (yalnız görüntü,
  CPU belleği, özel denetim), `MediaFrameReader` (BGRA8, 1920×1080, gerçek zamanlı), `SoftwareBitmap` çevirme ve
  arabellek kilidi (ham bayt için WinRT bellek arabelleği COM arabirimi), `AudioGraph` (GameMedia, LowestLatency,
  cihaz giriş/çıkış düğümleri). Kamera izni: Ayarlar › Gizlilik ve güvenlik › Kamera; ses için mikrofon izni.

---

## 4. Xbox doğrudan ev yayını (yalnız Windows)

Konsol türü "Xbox" seçilince Nino Xbox'a Microsoft hesabıyla kendisi bağlanır: sinyalleşme gömülü bir Node süreci
("Xbox köprüsü") üzerinden, görüntü ekran dışı bir WebView2 sayfasında WebRTC ile alınır. Medya akışı Xbox ile WebView2
arasında kalır; Nino sesi kapatır, yalnız kareleri okur. **Ses yolu yok.**

### 4.1 Köprü süreci (paket: `xbox-bridge/`)
- Dosyalar uygulama klasöründe `xbox-bridge\`: `bridge.cjs` (paketlenmiş betik), `player.html`, `player.js`,
  `licenses\*`, ve yayın paketinde `node.exe`. `node.exe` yoksa (yerel kaynak derlemesi) sistemdeki `node` kullanılır.
- Derleme: npm bağımlılıkları (sürümler sabit): `ip-address` 10.7.0 (Teredo adresi çözme), `xal-node` 1.1.6-beta2
  (Microsoft girişi, Xbox jetonları), `xbox-webapi` 2.0.0-beta4 (konsol listesi), `xbox-xcloud-player` 0.2.11 (tarayıcı
  WebRTC oynatıcısı); geliştirme: `esbuild` 0.25.12. Betik node22 hedefli tek dosyaya paketlenir; oynatıcının
  `dist/assets/xCloudPlayer.min.js` dosyası `player.js` olarak, `player.html` ve lisanslar `dist/`'e kopyalanır. CI'da
  Node **22.14.0**; `node.exe` CI'daki Node'un kendisinden kopyalanır. Lisanslar: Greenlight (MIT; protokol sırası
  ondan), xal-node, xbox-webapi, xbox-xcloud-player, ip-address, jose, uuid, events, Node.
- Süreç: gizli, penceresiz; stdin/stdout/stderr yönlendirilmiş, **UTF-8** (Türkçe Windows'ta kod sayfası 857/1254
  kullanılırsa konsol adındaki "ı" bozuluyordu: "Oturma Odası" → "Oturma OdasA+"), girişte BOM yok. stderr okunup
  atılır. Betiğin bağımlılıkları stdout'a yazmasın diye betik `console.log`'u susturur (stdout makine kanalıdır;
  jeton/durum basılmamalı).
- **Protokol (JSON satırları):** istek `{"id": <int>, "command": "<ad>", "args": <nesne|null>}`; yanıt
  `{"id", "value", "error"}` (error metinse hata). Bozuk istek satırı yok sayılır. Kimlikler artan sayı.
- **Uygulama tarafı:** süreç ölmüşse yeniden başlatılır (bekleyen istekler `source.xbox.error.bridgeRestarted`
  hatasıyla düşer, yüklü jeton unutulur). Betik yoksa `source.xbox.error.bridgeMissing`; başlatılamazsa `source.xbox.error.bridgeStartFailed`.
  Yazma tek kilitle; her istek satırı yazılıp boşaltılır. Bekleme süresi: `loginPoll` **16 dk**, diğerleri **90 sn**;
  dolarsa `source.xbox.error.bridgeTimeout` (komut adı). stdout kapanırsa bekleyenler `source.xbox.error.bridgeClosed`.
  `stop` komutu süreç yokken hiçbir şey yapmaz. **Jeton yükleme:** aynı jeton zaten yüklüyse tekrar yüklenmez; değilse
  `restore {userToken: <jeton JSON>}`. **Temizle:** süreç öldürülür, bekleyenler `source.xbox.error.sessionReset`.

**Komutlar** (köprü içi):
- `restore {userToken}` — bellekte (diske yazmayan) jeton deposu kurulur (xal-node normalde jetonu düz dosyaya
  yazar; Nino şifreli depoda tutar), "ev" bilgisi unutulur → `{ready: <jeton var mı>}`.
- `loginStart` — cihaz kodu girişi başlar → `{code, url, expiresIn}` (kullanıcı kodu, doğrulama adresi, süre sn).
  Uygulama adresi sistem tarayıcısında açar.
- `loginPoll` — giriş başlamadıysa "Microsoft sign-in has not started"; cihaz kodu yoklanır → `{userToken}`.
  Uygulama jetonu şifreli depoya (`xboxToken`) yazar.
- `consoles` — web jetonuyla Xbox Web API'den konsol listesi → `{consoles: [{id, name, model, streamingEnabled}],
  userToken}`; `model` = konsol türü, `streamingEnabled` = konsol yayını **ve** uzaktan yönetim açık. Uygulama tarafı
  ad yoksa "Xbox", model yoksa "Xbox"; jeton yenilendiyse saklar. Yalnız yayını açık konsol seçilebilir (şifreli depo
  `xboxConsole`: `{Id, Name, Model, StreamingEnabled}`). Kayıtlı konsolun adı listedekiyle farklıysa düzeltilir
  (eski bozuk kodlamalı adlar); yayın ilk kez akınca liste arka planda bir kez sorulur (hata yok sayılır).
- **Ev hizmeti adresi:** GSSV jetonu → "xhome" akış jetonu; bölgelerden varsayılan, yoksa ilki (yoksa "Xbox home
  streaming region was not returned"); adres = bölgenin temel adresi (sondaki `/` atılır), jeton = gsToken, bitiş =
  `validTo` ya da `expiresOn`, okunamazsa şimdi + 30 dk. Bitişe **60 sn**'den fazla varsa önbellekten.
- **API isteği:** `<adres><yol>`, başlıklar: `Accept: application/json`, `Content-Type: application/json`,
  `Authorization: Bearer <gsToken>`, `X-Gssv-Client: XboxComBrowser`, `X-MS-Device-Info`: JSON —
  `appInfo.env`: clientAppId `Microsoft.GamingApp`, clientAppType `native`, clientAppVersion `2203.1001.4.0`,
  clientSdkVersion `8.5.2`, httpEnvironment `prod`, sdkInstallId `""`; `dev.hw`: make `Microsoft`, model `Surface Pro`,
  sdktype `native`; `dev.os`: name `Windows 11`, ver `22631.2715`, platform `desktop`; `dev.displayInfo`: dimensions
  1920×1080 (widthInPixels/heightInPixels), pixelDensity dpiX 1, dpiY 1. Başarısızsa "Xbox service HTTP <kod>:
  <gövdenin ilk 500 karakteri>"; 204 → null; boş gövde → null; değilse JSON.
- **Değiş tokuş** (yol, yük): yükü POST et; sonra en çok **30** kez **250 ms** arayla GET; yanıtta `exchangeResponse`
  varsa onun JSON'u; yoksa değiş tokuşun zaman aşımına uğradığını söyleyen hata.
- Oturum yolu: `/v5/sessions/home/<oturum kimliği><ek>`; oturum yoksa "No Xbox stream session".
- `start {consoleId}` — konsol yoksa "Xbox console not selected". `POST /v5/sessions/home/play`: clientSessionId `""`,
  titleId `""`, systemUpdateGroup `""`, serverId = konsol kimliği, fallbackRegionNames `[]`, settings: nanoVersion
  `V3;WebrtcTransport.dll`, enableOptionalDataCollection false, enableTextToSpeech false, highContrast 0, locale
  `en-US`, useIceConnection false, timezoneOffsetMinutes = yerel UTC farkı (dakika, doğuya artı), sdkType `web`, osName
  `windows`. Oturum kimliği = yanıttaki `sessionPath`'in son parçası; yoksa Xbox'ın oturum vermediğini söyleyen hata; varsa →
  `{sessionId, userToken}`.
- `status` — `GET <oturum>/state`; durum `ReadyToConnect` ise MSAL jetonu alınır ve `POST <oturum>/connect
  {userToken: <lpt>}` yapılır, `connected: true` (aktarım jetonu yanıta konmaz) → durum alanları + `connected` +
  `userToken`.
- `sdp {sdp}` — değiş tokuş `<oturum>/sdp`: messageType `offer`, sdp, configuration: chatConfiguration {bytesPerSample
  2, expectedClipDurationMs 20, format {codec `opus`, container `webm`}, numChannels 1, sampleFrequencyHz 24000}, chat
  {min 1, max 1}, control {min 1, max 3}, input {min 1, max 8}, message {min 1, max 1}.
- `chatSdp {sdp}` — değiş tokuş `<oturum>/sdp`: offer, sdp, configuration {isMediaStreamsChatRenegotiation: true}.
- `ice {candidates}` — değiş tokuş `<oturum>/ice`: messageType `iceCandidate`, candidate = liste. Dönen her aday için:
  aday metninin 5. alanı (boşlukla bölünmüş, 0'dan 4. dizin) `2001` ile başlıyorsa Teredo adresi çözülür ve **9002** ile
  Teredo UDP portu için iki aday **önce** eklenir: `a=candidate:10 1 UDP 1 <Teredo istemci IPv4> <port> typ host `
  (sonda boşluk), diğer alanlar aynı; çözülemezse yalnız özgün. Sonra özgün aday.
- `keepalive` — `POST <oturum>/keepalive {}`.
- `stop` — oturum yoksa `{}`; varsa unutulur ve `DELETE /v5/sessions/home/<kimlik>`.
- Bilinmeyen komut: "Unknown Xbox bridge command: <ad>".

### 4.2 Yayın oturumu (uygulama)
- Başlatılınca bir kez arka planda koşar; günlüğe (altyazı günlüğü, "[Xbox] " önekli) "konsol: id …, ad …, model …".
- Döngü (iptal edilmedikçe):
  1. "bağlanıyor"; jeton yüklenir; `start` (jeton yenilendiyse saklanır); günlüğe "play yanıtı: oturum <ilk 8
     karakter>…" (8 ya da daha kısaysa tamamı; yoksa "?").
  2. En çok **90** kez, **1 sn** arayla `status`: jeton saklanır; durum değiştiyse "state: <eski|-> → <yeni|?>";
     `connected` varsa "connect: başarılı"; konsolun **hata ayrıntısı** (`errorDetails` boş olmayan metin ya da en az
     bir boş olmayan değeri olan nesne) varsa günlüğe. Durum `Provisioned` → çık; `Failed` ya da hata ayrıntısı →
     **kalıcı** hata (ileti: ayrıntı ya da `source.xbox.error.streamFailed`); 90. denemede "Xbox yayını hazır olmayı beklerken
     zaman aşımına uğradı".
  3. Oynatıcı açılır (§4.3) ve kapanması beklenir; iptal değilse görüntü bağlantısının kapandığını söyleyen hata (ya da
     sayfanın bildirdiği son neden).
  4. Her turun sonunda oynatıcı kapatılır ve `stop` (hata yok sayılır).
  5. Yayın en az **60 sn** sürdüyse hata sayacı sıfırlanır (yeni dizi). Sayaç artar. Kalıcıysa ya da sayaç **> 3**
     ise: günlüğe kalıcı hata ya da 3 denemenin bittiği (nedenle); durum **"bağlı değil
     (reddetti)"** ayrıntı: **`source.xbox.status.lost`** ve döngü biter. Değilse bekleme **5, 15, 45 sn**
     (sayaca göre), günlüğe "yeniden deneme n/3: <s> sn sonra", durum "bağlı değil (diğer, neden)". (Neden: konsol oyunun başka bir cihazda açıldığını söyleyip yayını
     kestiğinde kısa aralıkla sonsuz deneme konsolu tekrar tekrar uyarıya düşürüyor, oyunu bozuyordu.)
- **Durdur:** iptal, oynatıcı kapanır, "bağlı değil (durduruldu)". **Hemen yeniden bağlan:** oynatıcı kapanmış sayılır
  (tur yeniden başlar).
- Ana ekran metni (Xbox): akıyor → **Bağlı**; bağlanıyor → **Bağlanıyor…**; çeviri yok: konsol yoksa **Bağlı değil**,
  varsa `status.xbox.readyIdle`;
  durmuş ("reddetti" + ayrıntı) → ayrıntının kendisi; ayrıntılı → `status.xbox.retryingDetail`; değilse **`status.xbox.retrying`**. Xbox hizmeti yoksa "Xbox yayını
  bu sürümde kullanılamıyor"; giriş bitmediyse "Microsoft girişi tamamlanmadı".

### 4.3 Oynatıcı sayfası (ekran dışı WebView2)
- Pencere 1280×720, ekran dışında (−10000, −10000), kenarsız, görev çubuğunda yok, etkinleşmez, boyutlanmaz, başlık
  "Nino Xbox reader". `player.html` yoksa "Xbox oynatıcı eksik".
- Tarayıcı profili `%LOCALAPPDATA%\Nino\xbox-webview`; arka planda kısılmasın diye seçenekler:
  `--disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows`.
  Durum çubuğu ve geliştirici araçları kapalı. Sanal ana bilgisayar `nino-xbox.local` → `xbox-bridge` klasörü (CORS
  reddi); `https://nino-xbox.local/player.html` açılır. Gezinme başarılıysa sayfaya `{"kind":"start",
  "legacyFrameRate": <bool>}` gönderilir; değilse oynatıcı bitti sayılır.
- **Sayfa → uygulama iletileri:**
  - `{"kind":"frame","image":"data:image/jpeg;base64,…"}` — kare meşgulken atlanır. Kare arka planda çözülür (JPEG →
    Bgra32, sıkı adım) ve okuma hattına verilir; tek karenin hatası yok sayılır; bitince sayfaya
    `{"kind":"frameDone"}`. (Önceden arayüz iş parçacığında çözülüyordu; kareler ileti kuyruğunda birikip saniyeler
    önceki kare okunuyordu.)
  - `{"kind":"state","state":…,"detail":…}` — `connected`: günlük "WebRTC bağlandı", yayın başlangıcı (ilk kez)
    kaydedilir, "akıyor". `closed`/`failed`/`error`: günlük "WebRTC <durum>: <ayrıntı>", ilk ayrıntı son neden olur
    (yoksa `source.xbox.error.webrtcLost`), oynatıcı biter.
  - `{"kind":"rpc","id":…,"command":…,"args":…}` — **yalnız** `sdp`, `chatSdp`, `ice`, `keepalive` izinli (giriş ve
    jeton dönen komutlar sayfaya kapalı); değilse `{"kind":"reply","id","error":"Bu komuta izin verilmiyor"}`. İzinliyse
    köprüye iletilir, `{"kind":"reply","id","value"}` ya da `error`.
  - İleti işlenemezse "bağlı değil (diğer, hata)" ve oynatıcı biter.
- **Sayfa betiği:** xCloud oynatıcı "stream" öğesine kurulur (sistem arayüzü yok, dokunma/fare-klavye/eski klavye
  girdisi kapalı), kol titreşimi kapalı. SDP işleyicisi (yeniden müzakere) `chatSdp` ister. Teklif → `sdp` → uzak
  yanıt; yerel ICE toplama "tamam" olana ya da **5 sn** dolana kadar beklenir; adaylar (candidate, sdpMLineIndex,
  sdpMid) `ice` ile gönderilir, dönenler oynatıcıya verilir. Bağlantı durumu her değişimde iletilir; `connected`'da
  ses çıkışı ve video **sessize** alınır, video oynatılır; video öğesi gelene kadar DOM izlenir; video verisi yüklenince
  ve her kare aralığında yakalama; **30 sn**'de bir `keepalive`. Hata → `state: error`.
- **Kare yakalama:** aralık varsayılan **66 ms**, `legacyFrameRate` ile **200 ms** (eski sürümlerin aralığı). Videonun boyu yoksa
  geç; son kareden beri aralık geçmediyse geç; önceki kare onaylanmadıysa ve **1000 ms** dolmadıysa geç (yanıt
  kaybolursa akış durmasın). Kanvas videonun boyunda; JPEG kalite **0,94**.
- `stop` iletisi: zamanlayıcılar durur, bekleyen istekler "Xbox stream stopped" ile düşer, oynatıcı kapanır.

### 4.4 Ayarlar
- "Xbox kare aralığı eski" (`XboxLegacyFrameRate`) değişirse ve Xbox yayını sürüyorsa yayın yeniden başlatılır.
- "Kurulumu baştan yap" (sıfırlama) Xbox jetonunu ve konsolunu, PS5 kaydını, hesap kimliğini ve TV kaydını da siler.

---

## 5. `settings.obs.streamWindow` (çıktı; OBS dışı yayın programları için)

Kaynak değil, ama pencere yakalamayla ilgili: saydam pencere yakalayamayan yayın uygulamaları (ör. TikTok LIVE Studio, Streamlabs)
için, altyazıyı tek renk zemin üstüne çizen olağan bir pencere; programda pencere yakalama kaynağı olarak eklenir, zemin chroma key süzgeciyle kaldırılır.
- Tek örnek: açıksa öne getirilir (küçültülmüşse geri). Başlık **sabit**: **`source.streamWindow.title`** (yakalama
  listesinde bulunsun). İçerik 1280×720 için pencere 1296×759; en az 400×260; boyutlanır; ekran ortası; görev
  çubuğunda; yazı gri tonlu yumuşatma (renk saçağı olmasın).
- Zemin: yeşil `#00FF00` (varsayılan), siyah `#000000`, mor `#FF00FF`; şifreli depoda ad olarak (`green`, `black`,
  `magenta`), okunamazsa yeşil.
- Ölçek = max(0,2, içerik yüksekliği (yoksa 720) / 1080). İç boşluk: yanlarda 24×ölçek, altta yükseklik × 0,07; ek
  alanlar üstten 16×ölçek.
- Olaylar saydam altyazı penceresinin kurallarıyla (Mac kaynaklar §5 ile aynı yığın kuralları; önceki satırları tutma
  ayarı stilden). Ek alan olayı altyazıya dokunmaz (önceden "temizle" sayılıp altyazıyı siliyordu). Pencere altyazı
  yalnız TV'deyken de satırları alır; çeviri durunca temizlenir.
- **Altyazı kutusu:** yazı boyu = max(1, temel × ölçek × (güncel 1 / önceki 0,8) × kaydırma ölçeği); temel = stildeki
  boy 12–200'e kırpılmış (0 ise 46). Zemin yüzdesi > 0 ise kutu **tam siyah** (yarı saydam kutu chroma key'i bozar) ve
  yazı rengi soluklukla (güncel 1, önceki 0,6, daha eski 0,45 alfa); değilse kutu yok, yazıya gölge (siyah, derinlik
  2×ölçek, bulanıklık 4×ölçek, aşağı). Renk beyaz ya da sarı `#FFE135`; kalın ya da yarı kalın; paragrafsa sola, değilse
  ortaya; satır yüksekliği boy × 1,3; köşe 10×ölçek; iç boşluk güncel 26/10, öbür 20/6 (×ölçek); üst boşluk 14×ölçek.
  Solan satır önceki-satır solma süresinde opaklığı 0'a indirir.
- **Ek alan kutusu:** tam siyah, boy max(12, temel × ölçek × 0,55), yarı kalın, satır 1,25; köşe 8, boşluk 14/6, alt
  10 (×ölçek); alanın yatay ortası < 0,4 sola, > 0,6 sağa, arada ortaya. Ek alanlar üstten aşağı sıralı.
- Stil ya da zemin değişince kutular yeniden kurulur.

---

## 6. Uygulama denetleyicisinin kaynakla ilgili testleri (örnek girdi → çıktı)

Bunlar ana ekran/kurulum testleridir ama kaynak seçimine dayanır; yeni testler bunlarla yazılmalı.

**Altyazının bilgisayar ekranında çıkması:**
- Eski ayar `{"SourceLanguage":"en","Style":{"FontSize":58}}` → çıktı TV, tıklamaları geçir kapalı, pencere yeri yok,
  yazı boyu 58.
- Çıktı Both, tıklamaları geçir açık, yer (100, 800, 1200) kaydedilir: JSON'da `"Output":"Both"`, geri okununca aynı.
- PS5 kurulu, TV yok (hesap 8×0x01, PS5 kaydı 192.168.1.253 "PS5" anahtar 16×0x31, oturum anahtarı 16×0x02):
  - TV adımında ilerlenemez; "TV'm yok" → çeviri modeli adımı, çıktı bilgisayar, TV eşleştirmesi denenmez, TV yok.
  - Açılışta sihirbaz TV adımından sürer; "TV'm yok" + üç kez ilerle (model → deneme → daha iyi çeviri → bitti) →
    bitti; yeniden açılışta da bitti.
  - "Kurulumu baştan yap" → yeniden açılışta karşılama. `settings.reset.fromTv` → TV adımı, hesap ve PS5 kalır,
    yeniden açılışta TV adımı.
  - Çıktı bilgisayar: başlatılabilir, TV gösterilmez; başlatınca tek PS5 oturumu, **TV bekçisi açılmaz**; PS5 ağ
    nedeniyle kopsa ve bağlantılar denetlense de **TV'ye hiç dokunulmaz** (TV çağrısı 0); uyku engeli başlar/biter.
    Yarım eşleşmiş Samsung TV (kayıt var, anahtar yok) olsa da aynı.
  - Başlatma "yerel kütüphane yok" hatasıyla düşerse: çalışmıyor, başlatılmıyor, uyku engeli yok, bilgisayar altyazı
    penceresi bir kez gizlenir; hata giderilince başlar.
  - Çıktı yalnız TV ve TV yok: başlatılamaz, TV gerekli, TV durumu "Not set up" → **Kurulmadı**; başlatma denemesi
    oturum açmaz.
  - TV eşli, çıktı bilgisayar ile başlatıldıysa TV bekçisi yok; çıktı Both yapılınca tek bekçi açılır ve çalışır;
    bilgisayara dönünce durur.
  - Çıktı bilgisayarken TV eşleşirse çıktı TV olur.
  - Deneme altyazısı (çıktı bilgisayar): bilgisayar penceresine tek "altyazı" olayı, metin `status.testSubtitle`, süre 8000 ms.
    Çıktı TV iken bilgisayar penceresine olay gitmez; **yayın penceresi** yine alır.
  - Durdurunca yayın penceresi ve bilgisayar penceresi birer kez gizlenir.
  - Yayın zemini varsayılan yeşil; mor seçilince şifreli depoda "magenta", yeniden açılışta mor; "bozuk" → yeşil;
    yeşilin G bileşeni 0xFF; kutu opaklığı zemin %60 → 1, %0 → 0.
  - Tıklamaları geçir iki kez çevrilince açık → kapalı.
  - Çıktı bilgisayar, güvenlik duvarı kuralı yok, TV eşli, PS5 akıyor, 5 dk geçse de güvenlik duvarı önerisi çıkmaz.

**oyun penceresi kurulumu:**
- Ayar `VideoSource = Window` JSON'da `"VideoSource":"Window"`; eski ayar (alan yok) → Ps5.
- Kaynak Window seçilince (PS5 kurulu olmasa da) başlatılabilir, bilgisayarda gösterilir, TV'de değil.
- `setup.welcome.shortcutXbox` → TV adımı, Xbox penceresi, TV'de gösterilir, bilgisayarda değil, başlatılamaz (TV yok);
  Geri → karşılama; çıktı bilgisayar yapılınca başlatılabilir; başlatınca pencere kaynağı Xbox için istenir; ayar
  JSON'da konsol Xbox.
- `setup.welcome.shortcutRemotePlay` → çeviri modeli adımı, oyun penceresi, başlatılabilir; bitti işaretlenince yeniden
  açılışta bitti ve oyun penceresi.
- Ayarlarda konsol Xbox → konsol Xbox, kaynak Window; kaynak Card yapılıp konsol PS5'e dönülünce kaynak Card kalır.

**Kart kurulumu ve denetleyici:**
- Kaynak Card + çıktı TV: kart kullanılır, pencere değil; TV'de gösterilir, TV gerekli, başlatılamaz (TV yok). Çıktı
  bilgisayar: başlatılabilir.
- Kart + çıktı bilgisayar, sonra kaynak PS5 → çıktı TV.
- TV eşli (LG "LG TV" 192.168.1.153, anahtar "tv-key") + kart + TV: başlatılabilir; Both: ikisinde de gösterilir.
- Kart rehberi (bilgisayar): rehber açılır (karşılama adımında), "bilgisayarda" ile bitirilince rehber kapanır, adım
  model kuruluysa "deneme" değilse "çeviri modeli", çıktı bilgisayar, başlatılabilir. Deneme adımından Geri → rehber
  yeniden açık, karşılama. Rehber iptali → kapanır. Rehber yeniden bitirilip "bitti" işaretlenince yeniden açılışta
  bitti ve kart.
- Kart rehberi (TV), TV yok: TV adımı, çıktı TV; Geri → rehber. TV eşliyse doğrudan deneme/çeviri modeli.
- Rehber bitirilip geri dönülüp iptal edilince karşılamada "Devam" → kaynak PS5, adım "ikinci hesap".
- Ayarlardan (adım bitti) rehber bitirilince adım bitti kalır, kart kullanılır, çıktı bilgisayar.
- Kart + çıktı bilgisayar ile başlat (seçili aygıt "card-1"): PS5 oturumu yok, tek kart kaynağı, oyun gösterilir,
  aygıt "card-1"; "kart yok" → metin `status.card.notPlugged`, turuncu; "okunuyor (Elgato HD60 X)" + alan
  (0,0,1920,1080) → akıyor, "Reading Elgato HD60 X", yeşil, oyun alanı o; "siyah" → turuncu; tam ekran komutu bir kez
  iletilir; oyun penceresi kapatılınca çeviri durur, kart durur, alan yok, kart durumu durdu.
- Geçişli kart (TV eşli, çıktı TV): oyun gösterilmez, tek TV bekçisi.

## 7. Emin olunmayan / eksik noktalar

- **Takion yaması:** eski derleme chiaki'ye "kapandıktan sonra gönderme" yaması uyguluyordu; v1.10.1'de yok
  (`yerel-kopru.md` §8). Durdurma testleri v1.10.1'le koşulmalı.
- Eski chiaki alt modülü v1.10.1 değildi; davranış farkları (özellikle kayıt/oturum günlük satırları) canlı denemeyle
  doğrulanmalı. Satır metinleri v1.10.1 kaynağında birebir bulundu.
- Xbox köprüsündeki npm paketleri yeni yazımda "yeni NuGet yok" kuralının dışında (npm); aynı sürümler kullanılabilir
  mi ana oturum karar vermeli. Oynatıcı xCloud kitaplığının iç alanlarına (ses çıkışı, WebRTC istemcisi) erişiyor;
  sürüm değişirse kırılır.
- `XboxConsole`/`console` şifreli depo JSON biçimi burada özetlendi; kesin biçim `kimlikler-veri.md`'de olmalı.
- Sihirbaz ekranlarının metinleri (düğme adları, PS5 adımı açıklamaları) burada yok; `kurulum.md`'de.
