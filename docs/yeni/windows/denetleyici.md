# Windows: uygulama denetleyicisi (ekranların tek kaynağı) — tarif

Bu belge yeni Windows uygulamasının **denetleyicisini** tarif eder: ekranların okuduğu bütün durum, ekranların
çağırdığı bütün eylemler, kurulum sihirbazının akışı, çevirinin başlama/durma yaşam döngüsü, PS5/Xbox/TV bağlanma ve
kopma, zamanlamalar ve ekranlara verilen durum metinleri. Kod yoktur. Metinler yalnız **anlam** olarak verilir
(İngilizce anlamı / Türkçe anlamı); yeni kod kendi anahtarını ve cümlesini yazar.

Yer: `apps/windows/src/Nino.Shell/` (net10.0, WPF'siz). **Linux da kullanır**: Linux sunucusu (`linux/Nino.Linux`) aynı
denetleyiciyi kendi hizmet nesnesiyle kurar (bkz. §3.4). Bu yüzden denetleyicide hiçbir Windows API'si yoktur; Windows'a
özgü her şey platform arayüzlerinin arkasındadır (§3) ve §21'de toplanmıştır.

Ayar alanlarının tam listesi, JSON adları ve dosya yerleri `kimlikler-veri.md`'dedir; burada ayarların **davranışa
etkisi** anlatılır. Sağlık, sorun bildirme ve Nino'ya Sor ayrı belgede: `saglik-bildirim-sor.md`.
Mac karşılığı: Mac'teki uygulama modeli (Mac `ana-ekran.md`, `kurulum.md`, `tv-kurulumu.md`); Windows farklıysa Windows esastır.

---

## 1. Genel kurallar

- Denetleyici tek nesnedir; uygulama açıkken bir tane vardır. Ekranlar ona bağlanır, özellik değişikliği bildirimiyle
  (her özellik değişince adıyla bir "değişti" olayı) yenilenir. Bir özellik değişince ona **bağlı özellikler de**
  bildirilir (ör. çeviri başlayınca "PS5 durum metni", "PS5 noktası", "TV noktası", "kart oynatıcısı görünür mü",
  "ana hesap ipucu" da bildirilir). Değer aynıysa bildirim yapılmaz.
- Kurucuya altı şey verilir: hizmetler (§3.3), şifreli depo (§3.1), ayar deposu (§3.2), uyku bekçisi (§3.1),
  metin kataloğu (o anki arayüz dili) ve **arayüze aktarma işlevi** ("bu işi arayüz iş parçacığında çalıştır").
  - Arka plandan gelen her olay (kare, oturum durumu, TV sayısı, model ilerlemesi, havuz cevabı, Xbox jetonu…) bu
    aktarma işleviyle arayüz iş parçacığına geçirilir; durum yalnız orada değişir.
  - Testlerde aktarma işlevi "hemen çalıştır"dır (eşzamanlı). Linux'ta kendi tek iş parçacıklı kuyruğudur.
- Kare iş parçacığında çalışan kare işleyicisinden **hiçbir hata dışarı kaçmaz** (kaçarsa süreç kapanırdı); her hata
  yutulur, tek bir karenin okunamaması akışı durdurmaz.
- Denetleyici iki günlüğe yazar: **remoteplay.log** (bağlantı, eşleştirme, başlatma; `[nino] ` önekli satırlar) ve
  **altyazi.log** (oturum, okuma hattı, oyun, sağlık; Türkçe kısa satırlar). Günlük satırlarının içeriği aşağıda
  yeri geldikçe verilir (Türkçe, ekran dilinden bağımsız; destek bunları okur).

---

## 2. Sabitler

| Ne | Değer |
|---|---|
| TV uygulamasının kimliği (LG'de başlatılan uygulama) | `com.ninotranslator.tv` |
| Altyazı sunucusunun varsayılan portu | 8787 |
| 8787 için açma denemesi | 6 kez, aralarda 1 sn (testte 0); olmazsa işletim sisteminin verdiği boş port |
| TV bekçisinin (TV uygulamasını açık tutan) aralığı | 5 sn |
| PS5'e "çalışan oyun" sorusu | bağlıyken 2 dakikada bir |
| "Hangi oyun?" kartı için bakış | çeviri sürerken 15 sn'de bir |
| Havuz çevirisi eşitlemesi | oturum/oyun değişince hemen (zorla), sonra 60 sn'de bir; her turda önce "buradayım" |
| Güvenlik duvarı: PS5 sorunu sayılması | 20 sn yeniden bağlanma |
| Güvenlik duvarı: TV beklemesi | 60 sn bağlanmama |
| LG geliştirici modu uzatma | en sık 20 saatte bir (TV başına) |
| Güncelleme denetimi | açılışta, sonra 3 saatte bir |
| Bu açılışta bitmemiş otomatik indirme sınırı | 3 |
| Sürüm başına kendiliğinden kurulum denemesi | 2 (bkz. §17) |
| Okuma takılması (kare kapısı) | bir okuma 15 sn bitmezse hat yeniden kurulur |
| Gelişmiş bekleme süreleri (bozuk okuma, yarım satır) | 0–2000 ms arasına kırpılır; varsayılan 800 ve 300 ms |
| Hızlı altyazı algılama açıkken aynı okumanın yeniden kullanımı | en çok 2 kare (kapalıyken 20) |
| Ücretsiz çevirinin CPU iş parçacığı | varsayılan 2; işlemci sayısına göre normalleştirilir |
| Ekran tanıma karesi | en çok 768 px genişlik, JPEG kalite 60 |
| Telefon/harita yan çevirilerinin TV'de kalma süresi | 120 sn; gösteriliyorsa 60 sn'de bir yeniden gönderilir |

---

## 3. Platform arayüzleri (denetleyicinin dış dünyadan istedikleri)

Denetleyici hiçbir şeyi kendisi yapmaz; aşağıdaki arayüzleri çağırır. Windows'ta bunları uygulama katmanı
(`Nino.App`) doldurur; Linux'ta Linux sunucusu; testlerde sahteleri. Arayüzün **varsayılan davranışı** olan üyeler
(ör. "yoksa null döner") doldurulmayabilir; o zaman özellik o derlemede kapalı sayılır.

### 3.1 Küçük arayüzler

- **Şifreli depo** (anahtar → değer; kaydet, yükle, sil). Herhangi bir türü JSON gibi saklar. Windows'ta DPAPI ile
  şifreli `secure.dat`; Linux'ta yalnız sahibinin okuyabildiği (0600) `secure.json`. Denetleyicinin kullandığı
  anahtarlar §4'te.
- **Ayar deposu** (ayarları yükle, kaydet). Windows'ta `%LOCALAPPDATA%\Nino\settings.json`. Yükleme hatasında
  varsayılan ayarlar; kaydetme hatası işi yarıda bırakmaz (ayar bellekte geçerli kalır, sonraki kayıtta yazılır).
  Windows'ta **ilk açılışta** (dosya yoksa) çeviri dili Windows'un arayüz diline göre seçilir (ör. Arapça Windows'ta
  Arapça); eski kayıtlar Türkçe açılır.
- **Uyku bekçisi**: "başla(ekran da açık kalsın mı)" ve "bitir". Çeviri sürerken bilgisayar boşta uykuya geçmesin.
  "Ekran da açık kalsın" bayrağı çeviri sürerken yeniden çağrılarak değiştirilebilir (§10.3). Linux'ta boş.
- **TV bekçisi**: başlat(aralık), durdur, şimdi yeniden bağlan. TV uygulamasını açık tutar; TV kapalıysa açılınca
  bağlanır. Android TV için boş bekçi (TV uygulaması bilgisayarı kendisi bulur).
- **Güvenlik duvarı** (yalnız Windows): "bu exe için Özel ağda kural var mı" (yönetici gerekmez), "yönetici izniyle
  kuralı ekle" (izin verilmez ya da kural yine yoksa false), "bağlı ağlardan biri Ortak mı" (varsayılan false).
- **Güncelleyici** (yalnız Windows kurulumunda): kendini güncelleyebilir mi, indirme sayfası adresi, "daha yeni sürüm
  var mı" (numara ya da yok), "indir, kur, yeniden başlat (ilerleme, kurulumdan hemen önce çağrılacak iş)". Kurulumdan
  önceki iş hata fırlatırsa kurulum başlamaz.

### 3.2 Görüntü kaynakları

- **Yayın oturumu** (PS5 Remote Play, Xbox yayını, Remote Play penceresi, seçilen pencere): olaylar "kare geldi"
  (oturumun kendi iş parçacığında, en çok saniyede 15), "durum değişti", "konsol yeni adreste"; eylemler başlat, durdur
  (bloklamaz), şimdi yeniden bağlan (uykudan uyanınca, ağ değişince), kapat.
  - Durum = evre (bağlı değil / bağlanıyor / görüntü geliyor) + bağlı değilse neden (tür + ayrıntı). Neden türleri:
    durduruldu (kullanıcı), PS5 uykuda, başka cihazda kullanımda, reddetti, ağ, giriş şifresi isteniyor, bulunamadı
    (ayrıntı: adres), diğer, eşleşme geçersiz, giriş şifresi yanlış, oturum reddedildi (ayrıntı: PS5'in kodu, ör.
    `0x80108bff`), Uzaktan Oynatma kapalı.
- **Pencere kaynağı** (oyun penceresi) (yayın oturumu + iki olay): "pencere durumu (durdu / pencere aranıyor / okunuyor) ve
  okunan uygulamanın adı", "oyun alanının ekrandaki yeri ya da yok". Kaynak kendi durumunu yayın durumuna da çevirir:
  okunuyor → görüntü geliyor, aranıyor → bağlanıyor, durdu → durduruldu.
- **Kart kaynağı** (yakalama kartı) (yayın oturumu + olaylar): "kart durumu" (durdu, kamera izni yok, kart yok, görüntü siyah
  (ad), okunuyor (ad)), "oyun alanının yeri", "oyunu gösteren pencere kapatıldı"; eylem "tam ekrana al/çık". Kart
  durumu yayın durumuna: okunuyor ve siyah → görüntü geliyor, durdu → durduruldu, diğerleri → bağlanıyor.

### 3.3 Hizmetler arayüzü (büyük arayüz), sorumluluğa göre

Her üye: ne yapar, denetleyici ne zaman çağırır. "(V)" = varsayılanı var, doldurulmayabilir.

**PS5 ve PSN**
- PS5 ara (ağdaki konsollar: adres, ad, uyanık mı).
- Giriş yönlendirmesinden hesap kimliği (8 bayt) — PSN girişi bitince.
- PS5'e kayıt ol (adres, hesap kimliği, `setup.ps5.codeLabel`) → kayıtlı konsol.
- PS5 yayın oturumu oluştur (konsol, hesap kimliği, kayıtlı 4 haneli giriş şifresi ya da yok).
- PS5'te çalışan oyun (yalnız bağlı PS5'in adresine keşif sorusu) (V: bilinmiyor).

**Xbox** (V: yok) — ayrı Xbox hizmeti: "jeton yenilendi" olayı, temizle, girişi başlat (kod + adres + süre),
girişi bitir (jeton), konsolları bul (jetonla; kimlik, ad, model, yayın açık mı), yayın oluştur (konsol, jeton, eski
kare aralığı mı).

**Pencere ve kart kaynakları**
- oyun penceresi kaynağı oluştur (konsol: PS5 ya da Xbox) (V: yok).
- Kart kaynağı oluştur (oyun bu bilgisayarda gösterilsin mi, tercih edilen aygıt kimliği) (V: yok).
- Remote Play penceresi kaynağı oluştur (uygulama: kendiliğinden / Sony / chiaki-ng) (V: desteklenmez).
- seçilen pencere kaynağı oluştur (süreç adı + başlık) (V: desteklenmez).
- Seçilebilecek görünür pencereler (V: boş).
- Seçilen Remote Play uygulaması kurulu mu (V: evet).

**TV**
- TV ara (LG + Samsung).
- TV ile eşleş ve TV uygulamasını sunucu adresini vererek açmayı dene → (jeton, açılabildi mi). Android TV'de hiçbir şey
  yapılmaz, (boş jeton, açıldı) döner.
- TV bekçisi oluştur (TV, jeton, başlatma parametreleri `server=<adres>`, "TV uygulaması şu an bağlı mı" sorusu,
  "TV yeni adreste" geri çağrısı, "TV yeni jeton verdi" geri çağrısı).
- LG: paketle gelen TV uygulaması sürümü (yoksa yok), geliştirici modu açık mı, TV parolasıyla geliştirici anahtarı
  al, TV'de kurulu sürüm, kur, geliştirici modu süresini baştan başlat (kalan saat ya da bilinmiyor).
- Samsung/Android: markaya göre paketle gelen uygulama (dosya + sürüm) ya da yok.
- Samsung: geliştirici modu açık mı, ön denetim (TV'nin 8001 bilgisi: geliştirici modu ve "Host PC IP", ve bu bilgisayarın TV'ye çıkan ağdaki adresi) (V: ikisi de bilinmiyor), kur (eksik/eskiyse; olay geri çağrısıyla) → (TV'deki sürüm,
  kuruldu mu).
- Android TV: hata ayıklama (ADB) açık mı, ağda ADB'si açık cihazları tara, kur (eksik/eskiyse; olaylarla) → sürüm.
- Kurulum olayları: "Samsung hesabıyla giriş beklenir (adres)", "TV ekranında onay beklenir", "ilerleme (adım adı)".
  Adım adları: `reading`, `signin`, `certificate`, `signing`, `installing`, `uninstalling`.

**Yazı tanıma**
- Oyun dili için okuyucu (yoksa yok: hiç OCR dili kurulu değil).
- Tek geçişte okuyan okuyucu (telefon ekranı, harita kartı) (V: normal okuyucu).
- Oyun dilinin kendi OCR paketi kurulu mu (V: evet). Değilse Windows sistemin diliyle okur, İngilizce bozulur.
- Küçük JPEG (kare, en çok genişlik, kalite) — oyunu ekrandan tanımak için (V: yok).

**Çeviri**
- Ücretsiz model (§3.5).
- DeepL çevirmeni (anahtar, yedek çevirmen, hedef dil) (V: yok); DeepL anahtarını dene (V: ulaşılamadı).
- Yapay zekâ çevirmeni (sağlayıcı, anahtar, model, yedek, "oynanan oyun" sorusu, hedef dil) (V: yok);
  yapay zekâ anahtarını örnek satırla dene (V: ulaşılamadı).
- Yerel model (Ollama/LM Studio) çevirmeni (sunucu, anahtar boş olabilir, yedek, oyun, hedef) (V: yok); dene.

**Paketler, havuz, geçmiş, sağlık, güncelleme**
- Oyun paketi kütüphanesi (V: yok); satırı paketlerde ara (V: yok).
- Ortak satır havuzu (V: yok); Nino çeviri havuzu (V: yok); paket güncelleyicisi (V: yok).
- Geçmiş dosyasının yolu (V: yok → diske yazılmaz).
- Sağlık klasörü (V: yok → sorun dosyası yok, ağ izlenmez, otomatik bildirim gitmez).
- Sorun bildirimini gönder (V: "gönderilemedi").
- Güncelleyici (V: yok), kendiliğinden kurulum sayaç dosyası (V: veri klasöründe `auto-update-tried.txt`),
  güvenlik duvarı (V: yok).

### 3.4 Linux neyi doldurur (Linux da kullanır)

Linux sunucusu denetleyiciyi aynen kurar (uyku bekçisi boş, depo `secure.json`, ayarlar `settings.json`, metin dili
`NINO_LANG` ya da sistem dili). Doldurduğu: PS5 arama/giriş/kayıt/oturum, TV arama/eşleşme/bekçi, LG/Samsung/Android
TV kurulumu, yazı tanıma (Tesseract), ücretsiz model (yalnız İngilizce→Türkçe, GPU yok). **Doldurmadığı** (varsayılan
kalır): Xbox, pencere ve kart kaynakları, yapay zekâ ve yerel model çevirmenleri, paketler, havuzlar, geçmiş, sağlık
klasörü (yani Linux'ta sorun kaydı dosyası, ağ izleme ve otomatik bildirim yok), güncelleyici, güvenlik duvarı.
Gözlem: Linux'un DeepL/Claude çevirmeni eski imzalı bir yöntemde duruyor ve arayüzün üç parametreli üyesini
karşılamıyor; denetleyici onu çağırmaz (Linux'ta denetleyici üzerinden çevrimiçi çeviri fiilen yok). Linux paneli
denetleyicinin şu eylemlerini kullanır: ilerle, geri, PSN girişini bitir, PS5 ara, kayıt ol, TV ara, eşleş, TV'ye uygulama kurma/yenileme, model indir, deneme altyazısı, sıfırla, başlat, durdur, duraklat, ayarlar, DeepL anahtarı
kaydet/sil, son kare. `NINO_AUTOSTART=1` ise kurulum bittiyse açılışta çeviriyi kendisi başlatır.

### 3.5 Ücretsiz model arayüzü

- Bu dil çifti destekleniyor mu, kurulu mu, indir (ilerleme 0–1), çevirmen oluştur.
- "GPU kullanılamadı, CPU'ya geçildi" olayı; aygıt seç (CPU/GPU); CPU iş parçacığı sayısı seç.
- "Motor bu bilgisayarda açılamadı" bilgisi ve bir kez gelen olayı (herhangi bir iş parçacığından).

---

## 4. Şifreli depodaki anahtarlar ve kullanımı

(Biçim ve tam liste `kimlikler-veri.md`'de; burada ne zaman yazılıp silindiği.)

| Anahtar | İçerik | Yazılır | Silinir |
|---|---|---|---|
| `accountId` | PSN hesabının kimliği (8 bayt) | PSN girişi ya da elle girişte | `settings.reset.everything` |
| `console` | kayıtlı PS5 | kayıtta; PS5 yeni adreste bulununca | `settings.reset.everything` |
| `consoleKind` | PlayStation / Xbox | karşılamada konsol türü seçilince | `settings.reset.everything` |
| `consoleKindLocked` | konsol türü kilitli mi | karşılamadan "Devam"da (true) | `settings.reset.everything` |
| `xboxToken`, `xboxConsole` | Xbox jetonu, seçilen Xbox | giriş/seçim/jeton yenilenince/ad düzelince | `settings.reset.everything` |
| `tv` | eşleşen TV (ad, adres, marka) | eşleşmede, TV yeni adreste, Android TV bulununca | iki sıfırlamada |
| `tvKey` | TV jetonu | eşleşmede; bekçi yeni jeton verince | iki sıfırlamada |
| `tvDevKey` | LG geliştirici anahtarı | parolayla alınınca | TV anahtarı reddedince; iki sıfırlamada |
| `tvAppVersion` | Nino'nun Samsung/Android'e kurduğu sürüm | kurulum/sürüm denetimi sonunda | TV markası ya da (Android dışında) adresi değişince; iki sıfırlamada |
| `devSessionRenewed.<küçük harf TV adresi>` | LG süresinin son uzatıldığı an | uzatılınca | — |
| `setupComplete` | kurulum bitti mi | §6.1 | iki sıfırlamada |
| `loginPasscode` | `settings.section.passcode` (4 hane) | Ayarlar'da girilince | elle; `settings.reset.everything` |
| `lastGames` | PS5 adı → son seçilen oyun | oyun seçilince | — |
| `captureCardId` | tercih edilen yakalama aygıtı (bu bilgisayara özgü) | seçilince; boş seçilince silinir | — |
| `streamBackground` | yayın penceresi zemini: `green`/`black`/`magenta` | seçilince | — |
| `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey`, `localAIKey` | anahtarlar | kabul edilen anahtar | "anahtarı kaldır" |

Anahtarların kendisi arayüze **hiçbir zaman** dönmez; ekranlar yalnız "kayıtlı mı" sorar.

---

## 5. Açılış (kurucu) sırası

1. Xbox hizmeti varsa "jeton yenilendi" olayına abone olunur (§12.6).
2. Depodan okunur: hesap kimliği, konsol, konsol türü (yoksa PlayStation), kilit (yoksa açık), Xbox jetonu, Xbox
   konsolu, TV.
3. Ayarlar yüklenir; listede olmayan yapay zekâ modelleri varsayılana döner; CPU iş parçacığı normalleştirilir.
4. **Eski "ikisinde de" düzeltmesi:** altyazı yeri "ikisi de" ve görüntü kaynağı yakalama kartı **değilse** yer
   "TV" yapılır (TV'si olanlarda bilgisayarda en önde pencere açılmaz). Kartta "ikisi de" korunur (oyunun bu
   bilgisayarda da gösterilmesi demektir).
5. Ücretsiz modele CPU iş parçacığı ve aygıt bildirilir.
6. Ayar yüklenenden farklıysa (model düzeldi, iş parçacığı, eski "ikisi de") **hemen kaydedilir**.
7. İlk adım belirlenir (§6.1).
8. Altyazı sunucusu nesnesi kurulur ve olaylarına bağlanılır (TV sayısı değişti, TV modelini bildirdi, olay gönderildi);
   "TV'ye gönder" bayrağı altyazı yerine göre ayarlanır. (Sunucu burada **açılmaz**; ilk ihtiyaçta açılır, §15.)
9. Paketler ve havuzlar başlatılır (§13.1).
10. Ücretsiz modelin "motor açılamadı" ve "GPU'dan CPU'ya düşüldü" olaylarına abone olunur.
11. Geçmiş dosyası varsa yüklenir.
12. Sorun bekçisi kurulur ve başlatılır (ayrıntı `saglik-bildirim-sor.md`).

---

## 6. Kurulum sihirbazı

### 6.1 Adımlar ve ilk adım

Adımlar sırasıyla: karşılama → ikinci hesap → PSN girişi → konsol → TV → çeviri modeli → deneme → isteğe bağlı
Gemini anahtarı (daha iyi çeviri için, ücretsiz) → son.

"Kurulum bitti mi" kuralı:
- Kayıtlı `setupComplete` değeri esastır. Yalnız sihirbazın sonuna gelinince (Bitti adımına geçilince) true yazılır.
  Böylece Samsung'da TV eşleşmiş ve kurulum sürerken Nino kapanırsa, eşleşme kayıtlı olduğu hâlde kurulum tamamlanmış sayılmaz.
- Hiç kayıt yoksa (çok eski kurulum): "konsol hazır **ve** TV eşleşmiş" yeter, sonuç bir kez kaydedilir.
- "Konsol hazır": Xbox türünde jeton ve Xbox konsolu; PlayStation'da hesap kimliği ve kayıtlı PS5.
- "TV eşleşmiş": depoda TV **ve** TV jetonu var.

Açılışta ilk adım:
- **Bitti**: (PlayStation türü **ve** görüntü Remote Play penceresinden ya da seçilen pencereden okunuyor) — bu durumda
  kurulum kaydına hiç dokunulmaz —, ya da yukarıdaki "kurulum bitti" kuralı doğru, ya da (görüntü kaynağı PS5 değil
  [oyun penceresi ya da kart] **ve** `setupComplete` true).
- Değilse konsol hazırsa **TV** adımı (yarım kalan kurulum TV'den sürer).
- Değilse **Karşılama**.

### 6.2 Adım sayısı ve numarası

- Toplam adım = Bitti'nin sırası (8); Xbox türünde 1 eksik (İkinci hesap adımı yok).
- Gösterilen numara = adım sırası + 1; Xbox'ta İkinci hesaptan sonraki adımlarda 1 eksik; toplamı geçmez.
- Adım değişince: eşleştirme adımında gösterilen güvenlik duvarı ipucu temizlenir (çalışıyor durumunda değilse), Bitti'ye
  gelinince `setupComplete`=true yazılır.

### 6.3 "Devam edilebilir mi"

| Adım | Koşul |
|---|---|
| Karşılama, İkinci hesap, Deneme, Daha iyi çeviri | her zaman |
| PSN girişi | Xbox'ta jeton, PlayStation'da hesap kimliği var |
| PS5 | Xbox'ta Xbox konsolu seçili, PlayStation'da kayıtlı PS5 var |
| TV | TV eşleşmiş **ya da** altyazı yeri "yalnız bilgisayar" |
| Çeviri modeli | model kurulu (§9; ücretsiz modeli olmayan dilde her zaman) |
| Bitti | hayır |

### 6.4 İlerle ve Geri

**İlerle** (devam edilemiyorsa ya da Bitti'deyse hiçbir şey):
- Karşılamadan ilerlerken: model indirmesi arka planda başlar; konsol türü kilitlenir ve kaydedilir; görüntü kaynağı
  PS5 değilse PS5 yapılır (karşılamadan "Devam" PS5 ya da Xbox yayını yoludur; önceden seçilmiş pencere/kart bırakılır).
- Karşılamada Xbox türündeyse doğrudan PSN girişi adımına (İkinci hesap atlanır); değilse bir sonraki adım.

**Geri** (sırayla ilk tutan kural):
1. PS5 oyun penceresi kısa yolundan gelinmiş ve Çeviri modeli adımındaysa → Karşılama.
2. Xbox penceresi kısa yolundan gelinmiş ve TV adımındaysa → Karşılama.
3. Kart kullanılıyor ve (TV adımında ya da TV'ye gitmeyen kurulumda Deneme adımında) → Karşılama ve kart
   rehberi yeniden açık.
4. Aksi hâlde Karşılama değilse bir geri; Xbox'ta PSN girişinden Karşılama'ya.

### 6.5 Kısa yollar (karşılamadaki seçimler)

- **`setup.welcome.shortcutRemotePlay`**: görüntü kaynağı oyun penceresi, konsol PS5, altyazı yeri
  bilgisayar; Çeviri modeli adımına atlanır; model indirmesi başlar.
- **`setup.welcome.shortcutXbox`**: görüntü kaynağı oyun penceresi, konsol Xbox, altyazı yeri TV; TV adımına atlanır; model
  iner. (TV adımında "TV'm yok" seçilirse altyazı bilgisayarda, pencerenin üstünde.)
- **`setup.welcome.shortcutCaptureCard`**: kart rehberi açık olur (PS5 adımlarının yerine), model iner. Rehberden vazgeçilirse
  karşılamaya dönülür. Rehber bitince (TV'ye mi bilgisayara mı): kaynak kart, yer TV ya da bilgisayar. Rehber
  sihirbazdan açıldıysa: TV seçildi ve TV eşleşmemişse TV adımı; değilse model kuruluysa Deneme, değilse Çeviri modeli.
  Rehber Ayarlar'dan açıldıysa (rehber açık değilken bitirme) yalnız seçim kaydedilir, adım değişmez.
- **"İkinci hesabım yok"** (İkinci hesap adımında): görüntü Remote Play penceresinden; TV eşleşmemişse yer bilgisayar
  (eşleşmişse yer korunur); doğrudan Bitti.
- **"OBS / oyun penceresi seç"**: görüntü seçilen pencereden; aynı yer kuralı; doğrudan Bitti. Pencere sonradan
  Ayarlar'da seçilir; seçilmeden başlatılamaz (bütün masaüstünü taramaya hiç düşülmez).
- **"TV'm yok" (TV adımında)**: yer bilgisayar, sonra İlerle (Çeviri modeli adımı).
- **Ayarlar › Bağlantı'da konsol değişimi**: konsol Xbox'a geçerken görüntü kaynağı PS5 ise oyun penceresine geçer
  (Xbox'a doğrudan bağlanma yok); kart seçiliyse kart kalır. Aynı konsola geçmek bir şey yapmaz.
- **Ayarlar'da `settings.source.linkAccount`**: görüntü PS5'ten okunacak ama hesap ya da PS5 yoksa görünür; sihirbaz İkinci hesap
  adımından açılır.

### 6.6 Konsol türü ve Xbox

- Konsol türü yalnız Karşılama'da, kilitli değilken, farklı bir türe ve (Xbox için) Xbox hizmeti varken değişir; kaydedilir.
- Xbox girişi: hizmetten kod ve adres alınır, adres tarayıcıda açılır; giriş bitince jeton kaydedilir. Xbox hizmeti
  yoksa "Xbox yayını bu sürümde yok" hatası; jeton yokken konsol aranırsa "Microsoft girişi bitmedi" hatası.
- Konsol listesi sorulunca kayıtlı Xbox listede **aynı kimlikle farklı adla** varsa kayıtlı ad düzeltilir (eski
  sürümler UTF-8 adı bozuk kaydediyordu: "Oturma OdasA+" → "Oturma Odası").
- Yayını kapalı konsol seçilemez.
- Xbox görüntüsü ilk geldiğinde liste arkada tek sefer istenir, yalnız ad tazelenir; hata yok sayılır.
- Hizmetin "jeton yenilendi" olayı: kayıtlı jetondan farklıysa ve hâlâ Xbox türündeyse ve arada sıfırlama olmadıysa
  (nesil sayacı) jeton güncellenip kaydedilir.

### 6.7 PSN girişi

- Yönlendirme adresinden hesap kimliği alınır. Başarıda kimlik kaydedilir, remoteplay.log'a "PSN girişi tamam".
- Sony'nin tarayıcıdaki giriş sayfası da açılabilir (uygulama içi pencere "sunucuya bağlanılamıyor" derse); kullanıcı
  yönlendirme adresini kopyalayıp verir.
- Hatalar ayrı ayrı anlatılır; iletinin sonuna **ayrıntı** (varsa "HTTP <kod>" ve Sony'nin hata metni, virgülle) ve
  her zaman **günlük ipucu** eklenir: "Sürerse bize şu dosyayı gönderin: <remoteplay.log yolu>".

| Giriş hatası | Hata kodu | Anlamı |
|---|---|---|
| Sony reddetti | giriş reddedildi | Sony girişi tamamlamadı; bir dakika bekleyip ikinci hesapla yeniden girin |
| Çok deneme (429) | sınır | Çok fazla deneme; ~15 dakika bekleyin |
| HTTP hatası | sunucu | Sony'nin giriş sunucusu hata verdi; birkaç dakika sonra |
| Ağ | ağ | Sony'ye ulaşılamadı; interneti denetleyin |
| Bozuk cevap | bozuk cevap | Cevap okunamadı; sürerse Nino'yu güncelleyin |
| Kod yok / diğer | geçersiz giriş | Giriş tamamlanmadı, yeniden deneyin |
| Beklenmeyen istisna | geçersiz giriş | Aynı genel ileti + parantez içinde istisnanın iletisi |

- Giriş penceresi yönlendirme olmadan kapandıysa: sorun yoksa "pencere giriş bitmeden kapandı; Giriş'e basıp
  pencerede bitirin"; sorun metninde "429" geçiyorsa sınır hatası; başka sorun varsa "Sony'nin giriş sayfası
  açılamadı; interneti denetleyin" + (sorun) + günlük ipucu.
- **Elle hesap kimliği**: boşluklar atılır; tam 12 karakter olmalı ve base64 çözülünce tam 8 bayt. Geçerliyse
  web girişiyle aynı biçimde saklanır, true; değilse false ve hiçbir şey kaydedilmez.
  Örnekler: `""`, `"AQIDBAUGBw=="` (7 bayt), `"AQIDBAUGBwgJ"` (9 bayt), `"AQIDBAUGBw!="`, `"1234567890"` → reddedilir;
  8 baytın base64'ü baş/son boşluklu verilince → kabul.

### 6.8 PS5 kaydı (eşleştirme)

Girdi: adres ve kod. Sıra:
1. Adres kırpılır; boşsa → `wizard.ps5.error.notFound`.
2. Kod: boşluk/tire atılınca tam 8 rakam olmalı (`"1234 5678"` kabul → 12345678); değilse → "Kod 8 hane olmalı"
   (`"1234"`, `""`, `"123456789"`, `"1234567O"` reddedilir; kayıt hiç denenmez).
3. Hesap kimliği yoksa → "Önce PSN'e girin".
4. Kayıt denenir. Hata eşlemesi (iletiye PS5'in ayrıntısı parantezle ve günlük ipucu eklenir):

| Kayıt hatası | Anlamı |
|---|---|
| hesap yanlış | PS5 bu hesabı tanımadı; kodu Nino'da kullandığınız hesapla girmiş PS5 kullanıcısından alın ya da o hesapla yeniden girin |
| yanıt yok | PS5 yanıt vermedi; açık (dinlenmede değil), aynı ağda ve Uzaktan Oynatma açık olsun |
| kullanımda | Uzaktan Oynatma başka cihazda; orada kapatıp yeni kod girin |
| PS5 hizmeti çöktü | PS5'i yeniden başlatıp yeni kod girin |
| sürüm uyuşmazlığı | bu PS5 sistem sürümü henüz desteklenmiyor; Nino'yu güncelleyin |
| kod yanlış | kod yanlış ya da süresi doldu; PS5'te Cihaz Eşleştir'i yeniden açıp yeni kodu girin |
| cevap gelmedi / iptal (süre doldu) | PS5 isteği aldı ama zamanında yanıt vermedi; yeniden Cihaz Eşleştir |
| kötü adres | bu adreste PS5 yok; Ayarlar › Ağ › Bağlantı Durumu'ndaki IP'ye bakın |
| diğer | PS5 kodu reddetti; Cihaz Eşleştir'i yeniden açıp yeni kodu girin |
| beklenmeyen istisna (ör. yerel kütüphane yüklenemedi) | "diğer" iletisi + (istisna iletisi) + günlük ipucu; günlüğe tam istisna |

   - Güvenlik duvarı önerisi: PS5 kendi kodunu bildirmediyse **ve** hata "hesap yanlış" ya da "kötü adres" değilse,
     ve beklenmeyen istisnada, kural denetlenir ve gerekirse öneri çıkar (§16). PS5 kod bildirdiyse yanıt gelmiş demektir; neden güvenlik duvarı olamaz.
   - Örnek: kod yanlış + ayrıntı "0x80108b09 (Regist failed, probably invalid PIN)" → iletide bu ayrıntı ve günlük yolu yazar.
5. Başarıda: güvenlik duvarı önerisi temizlenir, konsol kaydedilir, remoteplay.log'a `[nino] ` önekiyle adres ve adla
   "kaydedildi" satırı.
6. **Eşleşme iletisi** (PS5 adımında Bağlan düğmesinin altı): eşleşme yoksa boş; varsa `wizard.ps5.paired` (ad, adres;
   ad boşsa "PS5"). Örnek değerler: ad PS5-789, adres 192.168.1.253.
7. **Eşleşme sonrası kendiliğinden ilerleme**: ekran kısa süre sonra "devam et" der; yalnız PS5 adımındaysa ve konsol
   kayıtlıysa İlerle çalışır (kullanıcı bu arada Geri'ye bastıysa bir şey olmaz).

### 6.9 TV eşleşmesi

1. Altyazı sunucusu açılır (§15).
2. TV'ye eşleşme: kayıtlı jetonla, sunucu adresiyle (§15.2).
3. TV markası değiştiyse ya da (Android TV dışında) adresi değiştiyse kayıtlı "kurulan TV uygulaması sürümü" silinir.
4. TV kaydedilir. Jeton kaydı: **Samsung jetonla gelen bağlantıda yeni jeton vermeyebilir; boş jeton saklı olanı
   silmez** (yeni jeton boşsa eskisi kalır).
5. "TV uygulaması açılamadı" bilgisi saklanır (eşleşme "açılamadı" döndüyse).
6. Daha önce "TV'm yok" seçildiyse (yer bilgisayar) yer TV yapılır.
7. TV durumları bildirilir; LG'de TV uygulaması denetimi **beklenir**, Samsung/Android'de arka planda başlatılır
   (Samsung hesabıyla giriş ya da Android onayı birkaç dakika alabilir; eşleşme bunu beklemez). Ayrıntı §8.
- TV ağda yeni adreste bulununca (bekçiden) TV kaydı güncellenir.

### 6.10 Sıfırlamalar ve giriş şifresi

- **`settings.reset.everything`**: çeviri durur; Xbox nesil sayacı artar, Xbox hizmeti temizlenir; şu anahtarlar silinir: hesap,
  konsol, konsol türü, kilit, Xbox jetonu, Xbox konsolu, TV, TV jetonu, LG anahtarı, TV uygulaması sürümü, kurulum
  bitti, giriş şifresi. Bellek de sıfırlanır (PlayStation türü, kilit açık), TV uygulaması durumu bilinmiyor, kart
  rehberi kapalı, adım Karşılama.
- **`settings.reset.fromTv`**: çeviri durur; TV, TV jetonu, LG anahtarı, TV uygulaması sürümü, kurulum bitti
  silinir; PS5 hesabı ve eşleşmesi kalır; yer bilgisayarsa TV yapılır; adım TV.
- **`settings.section.passcode`**: yalnız 4 rakam (kırpılarak) kaydedilir (`" 4321 "` kabul, `"12a4"` red); oturum açılırken
  PS5'e verilir; kaldırılınca sonraki oturumda verilmez. Arayüze yalnız "kayıtlı mı" döner.

---

## 7. Ayarlar değişince (ayar yazıcısının kuralları)

Ekran yeni ayarı verir; denetleyici şu sırayla düzeltir ve uygular:

1. CPU iş parçacığı normalleştirilir.
2. **İki kaynak seçimi tek seçim gibi davranır.** (Kaynak 1: "görüntü kaynağı" = PS5 / oyun penceresi / kart.
   Kaynak 2: "çerçeve kaynağı" = PS5 / Remote Play penceresi / seçilen pencere.)
   - Çerçeve kaynağı değişti ve PS5 değil, görüntü kaynağı da PS5 değilse → görüntü kaynağı PS5 olur.
   - Değilse, görüntü kaynağı değişti ve PS5 değil, çerçeve kaynağı da PS5 değilse → çerçeve kaynağı PS5 olur.
3. `settings.section.pictureSource` PS5'e döndü, çerçeve kaynağı PS5 ve yer TV değilse → yer TV olur (PS5 yolunda yer seçilmez).
4. Değer değişmediyse hiçbir şey yapılmaz. Değiştiyse kaydedilir ve altyazı biçemi TV'ye yeniden gönderilir.
5. Yer değiştiyse → §10.3 "yer değişti".
6. Yer değişti, görüntü kaynağı aynı, kart kullanılıyor ve çeviri sürüyorsa → durdur ve yeniden başlat (oyunun bu bilgisayarın ekranında olup olmayacağı değişti).
7. `settings.section.pictureSource` değiştiyse → "yer değişti" işlemleri, durumlar bildirilir; çeviri sürüyorsa durdur, yeniden başlat.
8. Çeviri dili değiştiyse çeviri havuzuna yeni dil verilir (hat yeniden kurulmadan önce).
9. `pack.settings.title` açılıp kapandıysa ve hat varsa paket araması hatta yeniden bağlanır.
10. Hat varsa "konuşan adı göster" hatta hemen uygulanır.
11. Bekleme süreleri değiştiyse ve hat varsa hatta uygulanır (0–2000 ms kırpılmış).
12. Ortak havuz açılıp kapandıysa: satır havuzu ve çeviri havuzu açılıp kapanır; hat varsa paket araması yeniden
    bağlanır ve havuz eşitlemesi yeniden başlar.
13. Aygıt (CPU/GPU) değiştiyse "GPU'dan düşüldü" uyarısı kalkar, modele yeni aygıt bildirilir.
14. CPU iş parçacığı değiştiyse modele bildirilir.
15. Ek bölge izleyicisi güncellenir (§12.2).
16. Çerçeve kaynağı ya da seçilen pencere değiştiyse ilgili durumlar bildirilir.
17. Çeviri sürüyorken çerçeve kaynağı değiştiyse, ya da Remote Play penceresi yolunda uygulama değiştiyse, ya da
    seçilen pencere yolunda pencere değiştiyse, ya da Xbox türünde eski kare aralığı ayarı değiştiyse → durdur ve
    yeniden başlat (başlatma hatası yalnız remoteplay.log'a "Çeviri yeniden başlatılamadı: …").
18. "Çeviri değişti" = çevrimiçi aç/kapa, çevrimiçi motor, üç yapay zekâ modeli, yerel sunucu adresi/modeli, aygıt
    ya da iş parçacığı değişti. "Dil değişti" = kaynak ya da hedef dil.
    - Dil değiştiyse "model kurulu", "ücretsiz modeli var mı", "devam edilebilir mi" bildirilir.
    - Çeviri ya da dil değişti ve çeviri sürmüyorsa çevirmen durumu yenilenir (§11.4).
    - Çeviri sürerken dil, çeviri ya da "hızlı altyazı algılama" değiştiyse çevirmen durumu yenilenir ve **hat
      yeniden kurulur** (yeni okuyucu, yeni çevirmen).

Kısa eylemler: **Num 7 / ana ekran seçeneği** tıklama geçirgenliğini tersine çevirir; altyazı penceresinin yeri
kaydedilir; "ücretsiz anahtar al" Gemini'yi motor yapar (anahtar alınana kadar ücretsiz çeviri kullanılır).

---

## 8. TV uygulamasının kurulumu (durum makinesi)

TV uygulaması durumu: **bilinmiyor, kuruluyor (çalışıyor), güncel (sürüm), geliştirici modu kapalı, parola gerekli
(hata), başarısız (hata, sebep, Host PC IP, bu bilgisayarın adresi), Samsung hesabıyla giriş bekleniyor (adres), onay için TV'nin beklenmesi**. Metinleri `tv-kurulumu.md`/TV ileti belgesinde; denetleyici yalnız durumu üretir.

"Nino kurabilir mi": TV var ve (LG'de paketle gelen LG sürümü var; Samsung/Android'de o markanın paketi var).
"Yeniden denetle" aynı anda iki kez çalışmaz (bekleme ekranı ve çeviri başlangıcı birlikte çağırabilir).
"Kurulum gerekir mi" (Samsung/Android): kayıtlı sürüm yoksa ya da paket daha yeniyse.

### 8.1 LG
1. Paket yoksa bir şey yapılmaz. Geliştirici modu sorulur.
2. Bu arada durum "kuruluyor" olduysa (parola alanından kurulum başladı) dokunulmaz.
3. Geliştirici modunun kapalı olması: son eşleşmede uygulama açılamadıysa "geliştirici modu kapalı", açıldıysa "bilinmiyor".
4. Açık ama LG anahtarı yok: açılamadıysa "parola gerekli", açıldıysa "bilinmiyor" (çalışan uygulamada bir şey istenmez).
5. Anahtar varsa kurulum adımı: "kuruluyor"; TV'deki sürüm okunur; kurulu ve paket daha yeni değilse "güncel (TV'deki
   sürüm)" + süre uzatma; değilse kurulur → "güncel (paket sürümü)", "açılamadı" bilgisi silinir, süre uzatılır, TV
   uygulaması açılır.
   - TV anahtarı reddettiyse (geliştirici modu kapatılıp açılınca TV anahtarı yeniler) anahtar silinir, "parola gerekli".
   - Diğer hata → "başarısız" (sebep yalnız "kurulamadı" ve "yer yok" hatalarında, boş değilse).
- **Parolayla kurulum**: "kuruluyor"; parola kırpılıp anahtar alınır, kaydedilir, kurulum adımı. Anahtar alınamazsa
  "parola gerekli (hata: yanlış parola / anahtar sunucusu kapalı …)".
- **Süre uzatma**: TV başına; son uzatmadan 20 saat geçmediyse yapılmaz; uzatılırsa kalan saat gösterilir ve an kaydedilir.
- **Kurulumdan sonra açma**: bekçi varsa bekçiye "yeniden bağlan"; yoksa TV ile yeniden eşleşilir (hata yok sayılır).

### 8.2 Samsung
1. Paket yoksa bir şey yapılmaz. "Hatırlanan güncel" = kurulum gerekmiyor.
2. Ön denetim (8001). Geliştirici modunun açık olduğu ancak şöyle kabul edilir: 8001 "kapalı" demiyorsa **ve** geliştirici modu sorusu
   açık diyorsa.
3. Kapalıysa: hatırlanan güncelse "güncel (kayıtlı sürüm)", değilse "geliştirici modu kapalı".
4. **Host PC IP uyuşmazlığı** (TV'deki Host PC IP bu bilgisayarın adresi değil): sdb hiç denenmez. Hatırlanan güncelse
   "güncel"; değilse "başarısız: Host PC uyuşmazlığı" + TV'deki IP + bu bilgisayarın adresi. Düzelince sonraki
   denetimde kurulur.
5. Durum: hatırlanan güncelse "güncel" (denetim sessiz sürer), değilse "kuruluyor". Kurulum çağrılır; olaylar §8.4.
6. Sonuç sürümü (boşsa paket sürümü) kaydedilir → "güncel"; gerçekten kurulduysa TV uygulaması açılır.
7. Hata "ulaşılamadı" ve hatırlanan güncelse → "güncel" (çalışan uygulama "kurulamadı" gösterilmez). Diğer her hata →
   "başarısız" ve **her hatanın ayrıntısı gösterilir**.
- Not: TV'de eski kalan uygulama (bilgisayar kendi kaydına göre güncel sanıyor olsa da) güncellenir; kurulum işi TV'deki
  sürüme kendisi bakar.

### 8.3 Android TV
1. Paket yoksa bir şey yapılmaz. Adres boşsa ya da o adreste ADB kapalıysa: kurulum gerekmiyorsa "güncel"; gerekiyorsa
   ağ taranır, ilk bulunan adres kullanılır; hiçbiri yoksa "geliştirici modu kapalı".
2. "Kuruluyor"; kurulur; bulunan adres TV kaydına yazılır, sürüm kaydedilir → "güncel". Hata → "başarısız" (sebep
   kurallı, §8.1 gibi).

### 8.4 Kurulum olayları
Kurulum tamamlandıktan sonra gecikerek gelen olay sonucu değiştirmez: olay yalnız Samsung denetimi sürerken ya da durum
kuruluyor/giriş/onay iken işlenir.
- Giriş bekleniyor (adresli) → "Samsung hesabıyla giriş bekleniyor" ve adres tarayıcıda açılır.
- TV'de onay → "TV'de onay beklemesi".
- İlerleme ve durum girişteyse → "kuruluyor".
- İlerleme, durum "kuruluyor" değil ve adım TV'yi değiştiren bir adımsa (`signin`, `certificate`, `signing`,
  `installing`, `uninstalling`) → "kuruluyor" (sessiz denetim güncelleme kurmaya başladı).

---

## 9. Çeviri modeli indirme

- "Ücretsiz modeli var mı" = bu dil çifti destekleniyor. "Model kurulu" = ücretsiz modeli yoksa **kurulu sayılır**
  (indirilecek bir şey yok; çeviriyi yapay zekâ yapar), varsa kurulu mu.
- İndirmeyi başlat: kuruluysa ya da süren indirme varsa bir şey yapılmaz. İniyor=evet, hata temizlenir; ilerleme
  arayüze aktarılır. Bitince ilerleme 1; hata olursa hatanın iletisi gösterilir; her durumda iniyor=hayır, "kurulu" ve
  "devam edilebilir" bildirilir, çevirmen durumu yenilenir; çeviri sürüyor ve çevirmen hazırsa hat yeni çevirmenle kurulur.
- İndirme karşılamadan "Devam"da ve kısa yollarda başlar (kullanıcı diğer adımlarla uğraşırken iner).

---

## 10. Çeviri yaşam döngüsü

### 10.1 "Başlatılabilir mi"

- oyun penceresi (PS5) kullanılıyorsa her zaman (altyazı o pencerenin üstündedir).
- Aksi hâlde [görüntü kaynağı hazır] **ve** [altyazı bilgisayarda gösteriliyor **ya da** TV eşleşmiş]:
  - `settings.section.pictureSource` hazır: oyun penceresi (Xbox) ya da kart **ya da** Xbox türünde jeton+konsol **ya da**
    (PlayStation'da) Remote Play penceresi yolu **ya da** seçilen pencere yolu ve süreç adı + başlık dolu **ya da** PS5
    yolu ve kayıtlı PS5 + hesap.

"TV'de gösteriliyor mu" = (oyun penceresi değil ya da Xbox penceresi) ve yer TV ya da ikisi.
"Bilgisayarda gösteriliyor mu" = oyun penceresi (PS5) ya da yer bilgisayar ya da ikisi.
"TV gerekli" (ana ekranda "TV bağla" düğmesi) = TV'de gösteriliyor ve TV eşleşmemiş.
"Kart oynatıcısı görünür" = çeviri sürüyor, kart ve bilgisayarda gösteriliyor.

### 10.2 Başlat

Çeviri sürüyorsa, başlatılıyorsa ya da başlatılamıyorsa hiçbir şey (iki kez basmak ikinci oturum açmaz).
1. Pencere yolundaysa pencere kaynağı istenir (yoksa çık); kart yolundaysa kart kaynağı istenir (oyun bu
   bilgisayarda gösterilsin mi = bilgisayarda gösteriliyor mu; tercih edilen aygıt) (yoksa çık).
2. Bu ikisi yoksa ve Xbox değilse ve pencere yolları değilse PS5 ve hesap şart (yoksa çık).
3. "Başlatılıyor" = evet. remoteplay.log: "Çeviri hazırlanıyor; altyazı: <yer>, TV: <marka ya da yok>".
4. Çevirmen durumu yenilenir; altyazı sunucusu açılır (açılamazsa TV "bekleniyor" kalır, hata yok sayılır); biçem TV'ye.
5. Duraklatma kalkar, ölçüm satırı boşalır, **hat kurulur** (§11).
6. altyazi.log: "oturum başladı: <kaynak>→<hedef>, motor: <motor ya da ücretsiz>, paketler: açık/kapalı, görüntü:
   <oyun penceresi / yakalama kartı / Xbox / Remote Play penceresi / seçilen pencere / PS5>, ağ: <kablo/wifi…>".
7. Sağlık kaydedici ve sorun bekçisine "oturum başladı".
8. Kaynak oluşturulur ve olaylarına bağlanılır — **yalnız şu anki oturumun olayları dinlenir** (eski oturumun geç olayı
   yok sayılır):
   - Pencere: durum ve oyun alanı. Kart: durum, oyun alanı, **oyun penceresi kapanınca çeviri durur**.
   - Xbox: Xbox hizmetinden yayın (eski kare aralığı ayarıyla); "ad tazelendi" işareti sıfırlanır.
   - Remote Play penceresi: seçili uygulamayla. seçilen pencere: hedef pencereyle.
   - PS5: konsol, hesap ve kayıtlı giriş şifresi.
   - Her kaynakta: durum değişti → §10.6; konsol yeni adreste → konsol kaydı güncellenir; kare geldi → §10.7.
   - Günlük satırları: "Çeviri başladı; …" (hangi kaynak, PS5 ise adı ve adresi).
9. Kaynak başlatılır, oturum olur; TV bekçisi başlar (§10.4); oyun algılama başlar (§13.3).
10. Uyku bekçisi başlar (ekran açık kalsın mı: §10.3); çalışıyor = evet; **TV'ye "çeviri başladı" olayı** gönderilir
    (TV kısa bir balon gösterir; sonradan ~20 sn içinde bağlanan TV de görür); güvenlik duvarı saatleri güncellenir.
11. Herhangi bir hata: remoteplay.log'a "Çeviri başlatılamadı: <tür>: <ileti>", **durdur** (geride oturum kalmasın),
    hata çağırana fırlatılır. Her durumda "başlatılıyor" = hayır.

### 10.3 Altyazı yeri değişti / ekran açık kalsın

- "Ekran da açık kalsın" = (Xbox değil ve görüntü Remote Play penceresinden ya da seçilen pencereden) **ya da**
  bilgisayarda gösteriliyor. (Ekran kapalıyken pencere yakalamadan kare gelmez; TV'de oynayan kullanıcının ekranı ~10 dk'da
  kapanıp altyazı kesiliyordu.) PS5/Xbox'tan doğrudan okunup yalnız TV'ye gidiyorsa ekran kendi ayarıyla kapanabilir.
- Yer değişince: sunucunun "TV'ye gönder" bayrağı güncellenir; bilgisayarda gösterilmiyorsa ayarlama modu kapanır ve
  pencere hemen boşaltılır; durumlar bildirilir; güvenlik duvarı saatleri güncellenir. Çeviri sürüyorsa uyku bekçisi
  yeni bayrakla yeniden çağrılır; TV'de gösteriliyorsa bekçi başlar, değilse durur ve atılır.
- Örnek (test): PS5 + yalnız TV → uyku var, ekran kapanabilir; sürerken "ikisi de" → ekran açık; geri "TV" → kapanabilir;
  durdur → uyku yok; Remote Play penceresi yolunda başlat → ekran açık.

### 10.4 TV bekçisi

Bekçi yoksa ve TV'de gösteriliyor ve TV eşleşmişse kurulur: TV, kayıtlı jeton, parametre `server=<sunucu adresi>`,
"TV uygulaması bağlı mı" = sunucuda bağlı istemci var mı (Samsung'da bağlıyken TV'ye dokunulmaz), TV yeni adreste →
kaydet, yeni jeton → kaydet. 5 sn aralıkla başlar; ardından TV uygulaması denetimi arka planda başlar (§8).
TV'siz ya da yalnız bilgisayarda gösterimde **hiçbir TV hizmetine dokunulmaz** (TV aranmaz, beklenmez; yarım eşleşmiş
TV'de de — TV kayıtlı ama jetonu yok).

### 10.5 Durdur

Sırayla: oturum durdurulur ve atılır; PS5 oyun sorusu bırakılır; oyun algılama ve havuz eşitlemesi durur; çeviri
havuzu kaydedilir; bekçi durur; hat sıfırlanır. Hat vardıysa: sağlık kaydedici ve bekçiye "oturum bitti", altyazi.log'a
"sağlık: <özet, satırlar ' · ' ile>" ve "oturum bitti". Hat atılır; ek bölge izleyicisi kalkar; kare kapısı sıfırlanır
(yeni Başlat takılmış eski okumayı beklemez); okuyucu bırakılır; ekran çevirisi iptal, TV'de ekran çevirisi
duruyorsa temizlenir; duraklatma kalkar; etkin dil yok; çevrimiçi uyarı kalkar; çalışıyorduysa uyku bekçisi biter;
çalışıyor = hayır. **Bekleyen güncelleme** (çeviri sürerken bulunmuş) uygulama kapanmıyorsa ve kendiliğinden kurulabiliyorsa
şimdi arka planda kurulur. Oturum durumu "durduruldu", pencere durumu durdu, uygulama adı yok, kart durdu, oyun alanı
yok; güvenlik duvarı saatleri güncellenir, "kural görüldü" unutulur, öneri temizlenir; bilgisayar penceresi ve yayın
penceresi hemen boşaltılır.

- **Uykudan uyanış**: oturuma "şimdi yeniden bağlan", bekçiye "yeniden bağlan".

### 10.6 Oturum durumu değişti

- Yalnız görüntü kaynağı PS5 yolundayken (oyun penceresi/kart değilken; Xbox ve Remote Play penceresi bu yolda sayılır)
  ve evre değiştiyse: altyazi.log "<başlık>: bağlanıyor / bağlandı / bağlantı yok"; sağlık kaydına bağlanıyor /
  görüntü geldi (+ bekçiye "PS5 geri geldi") / koptu (neden; kullanıcının durdurması kopma sayılmaz; kopmada bekçiye
  "PS5 koptu (neden, önceki evre görüntü geliyor muydu)").
  Başlık: Xbox'ta "Xbox", seçilen pencere yolunda `status.console.titleSelectedWindow` anlamı, diğer "PS5".
- Durum yazılır; güvenlik duvarı saatleri güncellenir.
- Xbox değilse PS5 oyun sorusu görüntü gelince başlar, gitmeyince biter (§13.3). Xbox'ta ilk görüntüde ad tazelenir.
- **Bağlantı koptuysa** TV'de eski altyazı kalmasın: hat, ek bölge, telefon ve harita okuyucuları sıfırlanır, TV'ye
  "temizle" gönderilir (test: TV olay akışında `event: clear` görülür).
- Pencere durumu değişince altyazi.log'a pencere durumu (okunuyor + uygulama / bulunamadı / durdu); kart durumu
  değişince kart durumu (izin yok / bulunamadı / siyah + ad / okunuyor + ad / durdu) yazılır. Aynı değer tekrar
  gelirse bir şey yapılmaz.

### 10.7 Kare işleyici (kare iş parçacığında)

1. Gelme anı ölçülür (gecikme buradan). Arayüze aktarılır: "son kare" güncellenir, gerekirse oyun ekrandan tanınır (§13.3).
2. Duraklatılmışsa kare yalnız saklanır (ek bölge ve serbest alan için); altyazı okunmaz.
3. Hat yoksa çık. Ek bölge izleyicisine kare verilir (kendi seyrek temposuyla).
4. Telefonlu oyunda (§12.3): okuyucular eksikse ve kurulamaz değilse ve kuruluş zaten sıraya alınmadıysa arayüzde
   kurulur; harita ve telefon okuyucularına kare; yan çeviriler gösteriliyorsa ve son gönderimden 60 sn geçtiyse yeniden gönderilir.
5. **Kare kapısı**: aynı anda hatta tek kare girer. Meşgulse kare atlanır (biriktirilmez). Önceki okuma 15 sn'dir
   bitmediyse altyazi.log'a okumanın kaç ms'dir sürdüğü ve hattın yeniden kurulduğu yazılır; hat arayüzde yeniden kurulur.
6. Girdiyse hat kareyi altyazı bölgesiyle ve gelme anıyla işler; bitince kapıdan çıkılır.

---

## 11. Okuma hattı ve çevirmen zinciri

### 11.1 Hattı kur
Eski hat, ek bölge izleyicisi, telefon/harita okuyucuları sıfırlanır; kare kapısı sıfırlanır; etkin dil = kaynak dil.
Okuyucu istenir; "OCR eksik" = okuyucu yok **ya da** dilin OCR paketi yok (okuma sürse de ana ekran uyarır). Okuyucu
yoksa hat kurulmaz. Okuma zamanlayıcısı: hızlı algılama açıkken en çok 2, kapalıyken 20 kare yeniden kullanım.
Hat: okuyucu + çevirmen (§11.2) + sunucu + zamanlayıcı; "konuşan adı göster" ayardan. Bağlanan geri çağrılar:
- Ölçüm hazır → sağlık kaydına satır (çeviri süresi; paket satırında yok), ölçüm satırı `status.translation.metrics` (OCR, çeviri ve gecikme ms;
  ör. 40, 300, 520). Satır gelene kadar boş.
- Satır gösterildi → kaynağı paket mi motor mu; yalnız tek bir pakette bulunduysa o pakete oy; oy oyunu tanıttıysa
  kart kapanır ve oyun yayınlanır; son kaynak/çeviri, altyazının son yeri (deneme altyazısı oraya konur), geçmişe ekle.
- Çeviri sonucu → çevirmen durumu (hata ya da hazır). Pakette bulunamadı → havuza öner (§13.2).
- Günlük → altyazi.log; paket adı → şu anki paket kapsamı.
- Telefon paneli aranır mı → telefonlu oyun; telefon yazıları → telefon okuyucusunun son yazıları (altyazı sayılmaz);
  telefon arayüzü görüldü → telefon okuyucusuna; menü ekranı mı → harita açık mı.
- Görev şeridi sınırı: Windows'ta **kapalı** (görev şeridini ayrıca çeviren bölüm yok; şerit altyazı yolunda elenirse hiç çevrilmeyecekti).
Sonra paket araması bağlanır (§13.2), bekleme süreleri uygulanır, çevrimiçi uyarı kalkar, ek bölge izleyicisi
güncellenir, havuz eşitlemesi başlar.

### 11.2 Çevirmen zinciri (dıştan içe)
1. **Hedef yazı bekçisi**: Hedef Arapçayken Arap harfli satırlar (PS5 menüsü Arapçaysa) çevirmene gönderilmez.
2. **Havuz öncelikli sarmalayıcı** (çeviri havuzu varsa): havuz öncelikli oyunda (sunucu listesi; varsayılan GTA 6)
   çeviri yalnız havuzdan (önceki satırların bağlamıyla), gelmezse ücretsiz yerel çevirmenden; kullanıcının anahtarlı motoruna gidilmez — ortak havuz ayarı kapalı olsa da.
3. **Temel çevirmen**: yerel çevirmen (§11.3); çevrimiçi etkin değilse ya da motorun anahtar adı yoksa yerel. Yerel
   modelde (sunucu geçerliyse) yerel model çevirmeni, kayıtlı anahtar ya da boş. Bulut motorlarında anahtar yoksa
   yerel; varsa yapay zekâ çevirmeni (seçili model) ya da DeepL. Yedek: açılamayan ücretsiz motor yedek olamaz (yedek yok;
   çevrimiçi çeviremeyince satır yeniden denenir). Oyun adı modele bağlam olarak gider ve önbelleği ayırır: yalnız
   **kararlı oyun** (PS5'in bildirdiği, seçilen ya da çoğunluk paketi), son eşleşen paket değil. Çevrimiçi çevirmen
   "hata durumu değişti" bildirirse ana ekrandaki çevrimiçi uyarısı güncellenir (düzelince kalkar).
4. **Yerel çevirmen**: desteklenmiyor → "desteklenmiyor" çevirmeni; kurulu değil → "indirilmeli"; motor açılamadı →
   "motor açılamadı"; oluşturma hatası → remoteplay.log + (çevrimiçi etkin değilse) çevirmen durumu "motor açılamadı";
   çeviri başlatma yarıda kalmaz (paketler ve çevrimiçi motorlar çalışır). "Kullanılamaz" çevirmen her çeviride
   nedenini taşıyan hata fırlatır.

### 11.3 Çevrimiçi çeviri etkin mi
Ayar açık **ve** kaynak İngilizce **ve** hedef dil listede **ve** (motor DeepL değil ya da DeepL bu dili destekliyor)
**ve** motor hazır. Hazır: yerel modelde sunucu adresi geçerli (anahtar gerekmez); bulutta anahtar kayıtlı.

### 11.4 Çevirmen durumu (ana ekran uyarısı)
Çevrimiçi etkinse hazır; değilse sırayla desteklenmiyor / indirilmeli / motor açılamadı / hazır.
"GPU'dan düşüldü" olayı ana ekranda uyarı açar; aygıt değişince kalkar. "Motor açılamadı" olayı çevirmen durumunu yeniler.

### 11.5 Anahtarlar
- **DeepL kaydet**: kırpılır, denenir; geçerli ya da kotası bitmişse kaydedilir (§11.6); sonuç döner.
- **DeepL kullanımı**: kayıtlı anahtarla denenir; yoksa "geçersiz".
- **Yapay zekâ kaydet**: kırpılır, seçili modelle örnek satır çevrilir; geçerli, kota bitmiş ya da model reddedildi ise
  kaydedilir. **Dene**: kayıtlı anahtarla; yoksa "geçersiz".
- **Yerel model dene**: adres geçersizse "ulaşılamadı". Yazılan anahtar varsa o, yoksa kayıtlı (ya da boş) kullanılır;
  girilen anahtarı sunucu onayladıysa (aynı üç sonuç) kaydedilir.
- **Kaldır**: yerel modelde anahtar silinir, motor seçili kalır; seçili ve sürüyorsa hat anahtarsız yeniden kurulur.
  Diğerlerinde silinir; o motor seçiliyse motor ücretsize döner; çevirmen durumu yenilenir.
- **Kaydet (iç)**: yazılır; motor zaten seçiliyse ve çeviri sürüyorsa hat yeni anahtarla kurulur, değilse motor seçilir;
  çevirmen durumu yenilenir.
- Örnekler (testten): reddedilen DeepL anahtarı (`"  wrong  "` → denenen `"wrong"`) kaydedilmez, çevrimiçi açılmaz.
  Kabul edilen `key:fx` → çevrimiçi açık, model inmemiş olsa da durum hazır; başlatınca DeepL bu anahtarla ve
  **yedeksiz** (model inmemiş) kurulur; kaldırınca çevrimiçi kapanır, durum "indirilmeli". Claude: varsayılan model
  `claude-haiku-5-5` ile denenir; model `claude-sonnet-5-5` seçilip kabul edilince çevirmen bu modelle kurulur.
  Yerel: LM Studio adresi + `" qwen2.5-7b-instruct "` → deneme `http://localhost:1234/v1/chat/completions` ve model
  `qwen2.5-7b-instruct`, anahtar boş; `" lm-key "` kabul edilince kaydedilir; çevirmen önbellek kimliği
  `local:localhost:1234/qwen2.5-7b-instruct`; adres `ftp://nowhere` → etkin değil, deneme "ulaşılamadı".
  Kayıtlı model listede yoksa varsayılana döner ve hemen kaydedilir (OpenAI `gpt-4o` → `gpt-6-luna`, Gemini boş →
  `gemini-3.5-flash-lite`, Claude `claude-sonnet-5-5` kalır). Eski ayar `{"OnlineTranslation":true}` → motor DeepL.

---

## 12. Tek seferlik işler ve ek okuyucular

### 12.1 Deneme altyazısı, duraklatma, anlık görüntü
- **Deneme altyazısı**: biçem gönderilir; yer: oyunda altyazı görüldüyse son yeri, yoksa (0,3 … 0,7 yatay; altyazı
  bölgesinin altından 0,1 ile 0,03 yukarısı) kutusu; metin `status.testSubtitle`,
  8000 ms. "TV'de dene" çeviri yokken sunucuyu da açar (port açılamazsa yalnız bilgisayar penceresine gider).
- **Num 0 (duraklat/sürdür)**: yalnız çeviri sürerken. Duraklatınca hat sıfırlanır ve TV temizlenir; ek bölgeler de
  okunmaz (kutular kalkar); TV'ye 1800 ms "`status.pause.paused` / sürdürüldü". Ek bölge ve serbest alan çevirisi sürmeye devam eder.
- **Num 8**: "anlık görüntü istendi" olayı (ayar ekranı oyunun şu anki görüntüsünü yeniden alsın).

### 12.2 Ek bölgeler (Num 1–3) ve serbest alan (Num 5)
- 3 ek bölge; her birinin hedefi TV / bilgisayar / ikisi (varsayılan TV); "sürekli oku" (varsayılan kapalı).
- **Tek seferlik ek bölge**: bölge kapalıysa "ayarlı değil"; son kare yoksa "çalışmıyor"; aksi hâlde bölge okunur,
  TV'ye (hedef bilgisayar değilse) ve bilgisayar açılır penceresine (hedef TV değilse) gider.
- **`shortcut.action.freeArea`**: verilen karedeki alan bir kez okunur; TV'ye (serbest alan hedefi bilgisayar değilse) gönderilir;
  bilgisayarda gösterilmek üzere sonuç her durumda döner (açılır pencereye gönderilmez; serbest alan penceresi kendisi gösterir).
- Ortak kural: çeviri yok ya da okuyucu yok → "çalışmıyor"; önceki istek bitmediyse → "meşgul" (üst üste basmak ikinci
  okuma başlatmaz). Çevirmen hatası → çevirmen durumu güncellenir, "çevirmen yok"; başka hata → "başarısız".
  Yazı yoksa: `status.area.noText` TV'de alanın kendi kutusunda 2500 ms ve/veya açılır pencerede 2500 ms →
  "yazı yok". Varsa süre çeviriye göre hesaplanır; TV'ye kutusu ve paragraf biçimiyle; son kaynak/çeviri güncellenir,
  açılır pencere (gerekiyorsa) → "gösterildi".
- **Sürekli ek bölge izleyicisi**: hat var, duraklatılmamış ve en az bir "sürekli" bölge (açık ve sürekli seçili; kimlik
  `area1..3`, ad `Area 1..3`) varken kurulur; kendi okuyucusu ve çevirmeni vardır (altyazıyı bekletmesin); paket
  araması paketler etkinse. Değilse sıfırlanıp kaldırılır (kutuları TV'den kalkar). Çevirisi "bölge" olayıyla gider;
  durunca "bölge temizle".

### 12.3 Telefon ve harita kartı (GTA 6 gibi havuz öncelikli oyunlar)
(Ayrıntılı kurallar `telefon-harita.md`'de; denetleyicinin bağladıkları.)
- **Telefonlu oyun mu**: duraklatılmamış **ve** (havuz öncelikli oyun etkin **ya da** (kaynak İngilizce ve oyun hiç
  bilinmiyor ya da yalnız paketten tahmin edildi ve havuzun öncelik listesi bu hedef dile izin veriyor)).
- Değilse iki okuyucu sıfırlanıp kaldırılır. Öyleyse eksik okuyucu tek geçişli okuyucuyla kurulur; ikisi aynı yedek
  çevirmeni paylaşır. Telefon okuyucusu: harita son 8 sn'de açıksa duraklar; telefon ekranı görülünce oyun GTA 6 sayılır;
  bilinmeyen mesajlar tek istekte havuza, gelmeyenler yedek çevirmene; Türkçede sözlük açık. Harita okuyucusu: okumadaki
  oyun işaretinden oyun tanınır; başlık ve cümleler tek istekte havuza; hedef dil verilir. İkisinde de "bilinen çeviri"
  çeviri havuzunun deposundan bakılır.
- Okuyuculardan biri kurulamadıysa (OCR dili yok) hat baştan kurulmadıkça bir daha denenmez.
- **Havuza toplu soru**: ortak havuz açıkken ya da havuz öncelikli bir oyunda, oyun adıyla; değilse hepsi boş döner.
- **Yedek çeviri**: havuz öncelikli oyunda sadece ücretsiz yerel çevirmen (kullanıcının anahtarı kullanılmaz), diğerlerinde
  kullanıcının motoru; ikisi de hedef yazı bekçisinden geçer.
- **Gönderim**: telefon ve harita öğeleri birlikte tek bir "ekran" olayında, 120 000 ms, "yan çeviri" işaretli (TV
  altyazıyı silmez). Öğe yoksa ve önceden gösterilmişse TV'deki ekran çevirisi temizlenir.
- **Ekrandan oyun tanındı** (işaretlerden): çeviri sürüyorsa ve oyun zaten aynı değilse ve kaynak PS5 ya da kullanıcı
  değilse: altyazi.log'a oyunun ekrandaki yazılardan tanındığı (adıyla), görülen oyun olur, kart kapanır, yayınlanır, havuz
  eşitlemesi yeniden başlar.

### 12.4 `shortcut.action.translateScreen` (Num 9)
- Çeviri yok ya da okuyucu yok → "çalışmıyor". Çeviri var ama kare yok → TV'ye 4000 ms "Ekran yakalanamadı: PS5'ten
  henüz görüntü yok." ve "çalışmıyor" (tuş sessizce yok sayılmaz).
- İş sürüyorsa iptal edilir, ekran temizlenir → "temizlendi". TV'de önceki ekran çevirileri hâlâ duruyorsa (kalkış anı
  gelmediyse) temizlenir → "temizlendi".
- Aksi hâlde: TV'ye 2500 ms `status.screenTranslate.working`; karedeki her yazı grubu ayrı çevrilir ve hazırlandıkça TV'ye "ekran"
  olayıyla kendi yerinde gider (yapay zekâda hepsi tek istekte); kalkış anı güncellenir. Bitince TV'deki altyazı
  temizlenir; öğe yoksa 2500 ms `status.screenTranslate.noText` → "yazı yok"; varsa "gösterildi". bilgisayar ekranında
  gösterimde bu olaylar bilgisayar penceresine de gider.
- Hata: iptal → "temizlendi". Çevirmen hatası → çevirmen durumu, "çevirmen yok". Diğer → remoteplay.log ve "başarısız".
  İkisinde de TV temizlenir ve 6000 ms "Ekran çevrilemedi: <neden>".
- **Neden** sırası: çevrimiçi çevirmenin son hatası varsa onun açıklaması (motor adı ve yerel sunucuyla); son satır
  dakika sınırına takıldıysa "<motor> dakikalık sınırına ulaştı. Bir dakika sonra deneyin."; değilse çevirmen hatasının
  durumu "indirilmeli" → `status.screenTranslate.reason.notDownloaded`, "motor açılamadı" → `status.screenTranslate.reason.engineFailed`,
  diğer → `status.screenTranslate.reason.generic`
- Test: yazılı karede ilk basış "gösterildi", ikinci "temizlendi", üçüncü yine "gösterildi".

---

## 13. Paketler, havuzlar, oyun

### 13.1 Açılışta
- Paket kütüphanesi arka planda ısıtılır, sonra yüklü paket listesi yayınlanır (sonra yeniden yükleme yapılmışsa, sıraya
  alınmış eski boş liste yenisini ezmemeli — test: kullanıcı paketi yazılıp yeniden yüklendikten sonra açılıştan kalan
  yayın listeyi boşaltmaz).
- Paket güncelleyici varsa: hemen (ilk seferde zorla) ve sonra günde bir bakılır; yeni paket inince paketler yeniden
  okunur, altyazi.log "paketler güncellendi: <inen ve kaldırılanlar>". Ağ/dosya hatası sonraki bakışa kalır.
- Çeviri havuzuna dil ve açık/kapalı (ortak havuz ayarı) verilir. Satır havuzu açık/kapalı ve arka plan gönderimi
  (dakikada bir ve ağ gelince; sunucu onaylayana kadar satırlar diskte).
- "Paketleri yeniden yükle" (Ayarlar): kütüphane yeniden okunur, liste güncellenir.

### 13.2 Paket araması ve havuza öneri
- Paketler etkin = ayar açık **ve** İngilizce→Türkçe **ve** kütüphane var.
- Havuz çevirileri etkin = ortak havuz açık **ve** kaynak İngilizce **ve** çeviri havuzu var.
- Hattın paket araması (paketler etkin ya da kaynak İngilizce ve havuz deposu var): önce (havuz öncelikli oyun değilse)
  paket; sonra havuz deposu (havuz çevirileri etkinse ya da havuz öncelikli oyunda). Havuzdaki çeviriye Türkçe
  düzeltmeler uygulanmaz.
- Pakette bulunamayan satır: kaynak İngilizce değilse bir şey yok. Paketler etkin değil ve havuz öncelikli değilse ve
  satır bir pakette **varsa** önerilmez. Satır havuzuna (paket kapsamıyla) önerilir. Havuz çevirileri ya da havuz
  öncelikli etkinse bağlama eklenir ve sunucuya sorulur; daha iyi çeviri gelirse ekrandaki satır yükseltilir.

### 13.3 `home.card.game.label`
Dört kaynak, öncelik: PS5'in bildirdiği → kullanıcının seçtiği → paket çoğunluğu (son 20 satırın 5'i) → ekrandan.
(Kurallar Mac `ninoya-sor.md` §6 ile aynı.) Denetleyici:
- **Oturum başında**: oyun algılama yeni oturuma geçer, ekran tanıma zamanlaması sıfırlanır, kart kapanır, oyun
  yayınlanır; 15 sn'de bir bakılır: "sor" ayarı **ve** ortak havuz açık, sorulmadı, hiç bilinmiyor ve en az 120 sn
  sürdüyse kart **bir kez** açılır. Durunca bakış biter, kart kapanır.
- **PS5 oyun sorusu** (satır havuzu varsa): bağlı ve PS5 adresi varsa 2 dakikada bir sorulur; değişen oyun
  altyazi.log'a "PS5'te çalışan oyun: <ad ya da ?> (<kimlik ya da ?>)". Bağlantı bitince bırakılır, konsol bilgisi
  silinir. İptal edildikten sonra gelen cevap yazılmaz.
- **Ekrandan tanıma** (arayüzde, her karede): çeviri sürüyor, ortak havuz açık, kaynak İngilizce, (paket kapsamı varken
  havuz öncelikli oyun etkin değil), çeviri havuzu açık ve zamanlama izin veriyorsa (oyun bilinmiyorsa ~8 sn sonra,
  dakikada bir, en çok 6; ekrandan bilinen oyunda 5 dk sonra, sonra 20 dk'da bir, en çok 12) kare küçük JPEG yapılıp
  sunucuya gönderilir. Sonuç altyazi.log'a: tanınamadı (deneme sırasıyla) ya da yeniden bakışta seçilemedi (eski
  adıyla kalır); aynı oyun → doğrulandı; farklı → tanındı ya da değişti (eski → yeni), görülen
  oyun olur, kart kapanır, yayınlanır.
- **Seç**: ad temizlenir (boşsa bir şey yok); seçilir; PS5 adı (yoksa adresi) biliniyorsa `lastGames`'e yazılır; kart
  kapanır; yayınlanır. **Değiştir**: soruldu işaretlenir, kart açılır. **Sorma**: soruldu, kart kapanır.
- **Öneriler**: arama metni + kurulu paketlerin oyunları + bu PS5'te son seçilen.
- **Yayınla**: paket kütüphanesi elle seçilen oyunun paketiyle sınırlanır (paketi yoksa hiç aranmaz); "oynanan oyun"
  güncellenir; önceki yayından farklıysa: hat varsa havuz eşitlemesi yeniden, oyun varsa paket sunucusuna o oyun için
  bakılır (en sık oyun denetim aralığında).
- **Havuz eşitlemesi**: havuz çevirileri etkinse; zorla bir eşitleme, sonra her 60 sn'de "buradayım" + eşitleme. Oyun:
  paket kapsamı varsa o, yoksa bilinen oyun. Havuz öncelikli soruların oyunu: bilinen oyun öncelik listesindeyse o,
  değilse kapsam listedeyse kapsam, değilse kapsam ya da bilinen.
- **Ana ekran yazıları**: "havuz öncelikli canlı oyun" = dört kaynaktan biriyle bilinen bir oyun adı **var** (hiç
  oyun bilinmiyorsa kapalı) **ve** havuz, havuz öncelikli soruların oyununu (yukarıdaki kural) bu hedef dilde
  öncelikli sayıyor; salon sahnesindeki TV fonu buna göre. (Eski kodun yorumu "yalnız paket tahmini saymaz" diyor ama
  davranış: bilinen oyun hangi kaynaktan olursa olsun sayılır.) Alt şeritteki
  çeviri kaynağı: öyleyse `status.translation.poolActive`, değilse motor ücretsizse "Ücretsiz", değilse motorun adı. Örnek: GTA VI
  seçilince `status.translation.poolActive`; RDR2 seçilince motora döner; hedef dil Almanca ise GTA 6'da da motor; havuzsuz
  derlemede hiç açılmaz.
- **İndirme sayısı**: çeviri havuzunun son bildiği toplam; hiç alınamadıysa yok (gösterge gizli). Yenile: sunucu ayarı
  sorulur (en sık 10 dakikada bir); değiştiyse bildirilir; alınamazsa eski kalır; yeniden açılışta saklanan sayı.
  Örnek: `{"translate":{"enabled":true},"downloads":3439}` → 3439.

---

## 14. Bilgisayardaki altyazı penceresi, yayın penceresi, geçmiş, cihaz bilgileri

- Sunucunun gönderdiği her altyazı olayı (altyazı, temizle, ekran, bölge…) **yayın penceresi** olayı olarak her zaman,
  **bilgisayar penceresi** olayı olarak yalnız bilgisayarda gösteriliyorsa arayüze verilir (TV uygulamasıyla aynı yığın
  mantığıyla gösterilir). Durunca ikisine de "hemen boşalt". Test: yalnız TV'de deneme altyazısı bilgisayar penceresine
  gitmez ama yayın penceresine gider.
- Ayarlama modu (pencere taşınıyor/genişletiliyor: örnek yazı görünür, tıklamalar geçmez); kısayol bekleme modu
  (Ayarlar'da yeni kısayol beklenirken genel kısayollar bırakılır).
- `settings.obs.streamWindow` zemini: depoda adıyla; okunamazsa yeşil. RGB: yeşil 00FF00, siyah 000000, mor FF00FF. Düz zeminde
  kutu ya tam koyu ya hiç yok: arka plan yüzdesi > 0 ise opaklık 1, değilse 0.
- OBS ağ adresi: bilgisayarın ağ adresi varsa `http://<adres>:<port>/obs`.
- **Geçmiş**: gösterilen satır eklenir (eklenmezse bildirim yok); değişti bildirilir; dosyaya arka planda **sırayla**
  yazılır (yazmalar üst üste binmez; kilitli dosya sonraki satırda yeniden denenir). Temizle: liste ve dosya boşalır.
  Dosya yoksa (Linux, test) yazılmaz. Test: bir altyazı satırı okununca geçmişte (kaynak, sahte çevirmenin "TR: " önekli çevirisi, motor) ve
  ölçüm satırı İngilizcede "OCR <sayı> ms · Translation <sayı> ms · Delay <sayı> ms" kalıbına uyar; yeni oturumda ölçüm satırı ilk altyazıya dek boş kalır.
- **`device.title`** ve tek satırlık özet: `saglik-bildirim-sor.md` §5. TV satırına TV uygulamasının bildirdiği model
  de girer (sunucudan gelir, temizlenmiş).

### 14.1 Altyazı penceresinin yeri (saf hesap)
- Ölçek = birincil ekran yüksekliği / 1080, 0,5–4 arası; okunamazsa 1.
- Yazı boyu: ≤0 ise 46, değilse 12–200 arası.
- Pencere yüksekliği = yazı boyu × ölçek × 8,1 + 140 × ölçek (yuvarlanır; üç satır ve kayma payı).
- Yer: kayıtlı yer sonlu ve genişliği > 0 ise genişlik 320 ile tüm ekranlar genişliği arasına kırpılır; tüm
  ekranlardan biriyle yatayda ve dikeyde en az 80 birim (ya da kendi boyu küçükse o) kesişiyorsa kayıtlı yer kalır.
  Değilse çalışma alanının altında ortada: genişlik çalışma alanının %70'i (yuvarlanmış, en az 320), alt kenar çalışma
  alanının altından yüksekliğinin %4'ü yukarıda. Çalışma alanı okunamazsa tüm ekranlar, o da okunamazsa 1280×720.
  Yükseklik bozuksa varsayılan yazı boyuyla.
- Genişletirken: 320 ile tüm ekranlar genişliği (okunamazsa sınırsız) arası; bozuk genişlik 320.
- Kaydedilecek yer: üçü sonlu ve genişlik > 0 ise yuvarlanmış; değilse kaydedilmez.
- Örnekler (1920×1080 ekran, çalışma alanı 1920×1032, yükseklik 500): kayıt yok → genişlik 1344, sol 288, üst
  1032 − 41,28 − 500. (100, 400, 1000) kalır. NaN/sonsuz/0/negatif genişlik → varsayılan. (2100,400), (−3000,400),
  (100,1060), (100,−480) ekran dışı → varsayılan. Soldaki ikinci ekranda (−1600, 500, 1200) kalır. Genişlik 99999 →
  1920; 10 → 320. Kaydet (10.2, 20.6, 799.7) → (10, 21, 800). Ölçek 2160 → 2.

### 14.2 Pencere kaynağı kuralları (saf)
- PS5 için aranan parçalar (süreç adı + başlık, küçük harf): "remoteplay", "remote play", "chiaki". En az 320×180 içerik
  alanı; en büyük alanlı olan seçilir.
- Xbox için: süreç adında "xboxpcapp" ya da "greenlight" geçen, ya da süreç adı tarayıcılardan biri (chrome, msedge,
  firefox, brave, opera, vivaldi, arc) ve başlığında "xbox" (büyük/küçük harf duyarsız) geçen; aynı boy sınırı, en büyüğü.
- Gösterilen uygulama adı: chiaki → "chiaki-ng", greenlight → "Greenlight", xboxpcapp → "Xbox", tarayıcı →
  "xbox.com/play", diğer → "PS Remote Play".
- Oyun alanı: içerik alanında ortalanmış 16:9 (genişlikten hesap, sığmazsa yükseklikten), yuvarlanmış. Örnek: 2000×720
  → (360, 0, 1280, 720); 1920×1200 → (0, 60, 1920, 1080).
- Altyazı penceresi oyun alanının üstüne: genişlik %90, alt kenar oyunun altından yüksekliğin %3'ü yukarıda.
  Örnek: oyun (100,100,1000,500), yükseklik 200 → genişlik 900, sol 150, üst 385.

### 14.3 Salon sahnesi ölçüleri (saf hesap; ana ekran çizer)
Görseller 1672×941 piksel. Mantıksal TV ekranı 588 genişlik (ekran içeriği bu genişliğe göre tasarlanıp görseldeki
ekrana büyütülür). Fiş prize 120 piksel kala tam döner; kablo serbest boyu 330, kalınlığı 8; priz kenarı 86.
- PS5 sahnesi (`living-room.png`): ekran (149,40,1151,595), TV çerçevesi (139,27,1171,621), sehpa (49,713,1502,160),
  priz (1564,378), kablo başı (1550,734), görseldeki kablonun son parçası (1490,706)→(1522,706)→(1535,709)→(1545,716)→
  (1552,727), çıkış yönü (0,5; 0,87), fişin sarktığı yer (1600,885).
- Xbox sahnesi (`living-room-xbox.png`): ekran (136,40,1185,596), çerçeve (121,26,1214,630), sehpa (43,733,1580,167),
  priz (1561,381), kablo başı (1572,722), görselde kablo yok, çıkış yönü (1; 0,1), sarkma yeri (1646,912).
- Sola kaydırma = en az 0, 2 × (genişlik/2 − sehpanın ortası) → PS5 72, Xbox 6. Ekran büyütmesi = ekran genişliği / 588.
- Fişin dönüşü (radyan; 0 aşağı): dinlenme-priz uzaklığı 120'den büyük ve fiş prize 1'den uzaksa, t = (dinlenme
  uzaklığı − fiş uzaklığı) / (dinlenme uzaklığı − 120), 0–1 kırpılır, yumuşatılır (t²(3−2t)); hedef açı = atan2(−(prizX −
  fişX), prizY − fişY); dönüş = yumuşatılmış × hedef. Uçların yönü (−sin θ, cos θ).
- Kablo: başlangıç = son parçanın son noktası (yoksa kablo başı). Takılıyken: uç (fişX, fişY+30), denetim 1 = başlangıç +
  çıkış×90, denetim 2 = (uçX+10, uçY+170). Çıkıkken: fişin arkası = fiş − uç yönü×40; sarkma = max(0, 330 − arka ile
  başlangıç uzaklığı) × 0,45; denetim 1 = başlangıç + çıkış×70 (+sarkma y'ye), denetim 2 = arka − uç yönü×80 (+sarkma y'ye).
- Örnekler: PS5 dinlenen fişte uç (1600,845), denetim 2 x 1600; takılı PS5 uç (1564,408), denetim 1 (1597, 805,3),
  denetim 2 (1574,578); Xbox dinlenen uç (1646,872), takılı uç (1561,411), denetim 1 (1662,731).

---

## 15. Altyazı sunucusu açılışı ve adresler

### 15.1 Açılış
- Açıksa bir şey yapılmaz; süren açılış varsa o beklenir (denemeler arasında ikinci sunucu kurulmasın).
- 8787 denenir; "port dolu" hatasında (6. denemeye kadar): eski sunucu olaylardan çözülüp atılır, yeni 8787 sunucusu
  kurulup bağlanır, 1 sn beklenir. (Nino yeniden başlatılınca önceki sürecin tuttuğu 8787 birkaç saniye boşalmayabilir; o an rastgele bir porta geçilirse TV — yalnız 8787'yi tarar — beklemede kalıyordu.) İkinci ve sonraki denemede açılırsa
  altyazi.log'a sunucunun 8787'de kaçıncı denemede açıldığı.
- 6 deneme de olmazsa: altyazi.log'a 8787'nin açılamadığı (iletiyle) ve boş bir porta geçildiği, port 0 ile yeni sunucu
  (TV'ye adres her bağlantıda yeniden bildirildiğinden herhangi bir port olur). Gerçek port saklanır.
- TV sayısı değişince: arayüzde sayı, güvenlik duvarı saatleri, sorun bekçisine bildirim. TV modelini bildirince saklanır.

### 15.2 Adresler
- **`translation.local.address`** (TV'ye): `http://<TV'ye ulaşan bu bilgisayar adresi ya da 127.0.0.1>:<port>`.
- **bu bilgisayarın adresi** (TV'ye yakın): TV adresi geçerli IPv4 ise işletim sisteminin o adrese çıkacağı kaynak
  adres önce gelir (bağdaştırıcı birden çoksa doğru adres); VPN ve sanal bağdaştırıcılar başka adres kalmadıysa seçilir. TV'nin adresi bilinmiyorsa Wi-Fi/Ethernet adresi. Samsung'da "Host PC IP" olarak yazılacak adres de budur.

---

## 16. `firewall.settings.title` önerisi

Durum: **yok, öner (düğme), çalışıyor (Windows izni bekleniyor), izin verildi, başarısız (düğme yeniden), ortak ağ
(düğme yok; ağı Özel yapın)**.
- **Saatler** (her durum değişiminde ve denetimde güncellenir):
  - PS5 sorunu: Xbox değil, çeviri sürüyor, görüntü kaynağı PS5 yolunda, görüntü gelmiyor ve neden şunlardan biri
    **değil**: uykuda, başka cihazda, reddetti, giriş şifresi, giriş şifresi yanlış, eşleşme geçersiz, oturum
    reddedildi, Uzaktan Oynatma kapalı. Sorun başladığı an saklanır; bitince silinir.
  - TV beklemesi: çeviri sürüyor, TV'de gösteriliyor, TV eşleşmiş, bağlı TV yok.
- **Denetim** (ana ekran birkaç saniyede bir çağırır): saatler güncellenir; çeviri yoksa ya da güvenlik duvarı hizmeti
  yoksa çık. İki saat de boşsa öneri temizlenir. PS5 ≥20 sn ya da TV ≥60 sn ise, öneri yoksa, bu oturumda kural
  görülmediyse ve denetim sürmüyorsa: sorun bulunur (kural yok → öner; kural var ve ortak ağ → ortak ağ; diğer → yok).
  Arada çeviri durduysa sonuç yazılmaz. "Yok" çıkarsa "kural görüldü" işaretlenir (bir oturumda kurallar bir kez taranır).
- **Kural okuma hatası** izin var gibi gösterilmez (kural yok sayılır). Ortak ağ sorusu hatası "ortak değil".
- **İzin ver**: hizmet yoksa ya da çalışıyorsa false. Çalışıyor; ekleme (hata = eklenemedi) → izin verildi / başarısız.
  Eklendiyse kural görüldü; çeviri sürüyorsa PS5'e ve bekçiye hemen yeniden bağlan. Sonra hâlâ bağlanmasa da "izin
  verildi" kalır, yeniden önerilmez.
- **Ayarlar durumu**: hizmet yoksa yok; varsa (kural var mı, ortak ağ mı).
- Eşleştirme hatasında öneri §6.8. Adım değişince ve Durdur'da öneri temizlenir (çalışıyor değilse).
- Test örnekleri: PS5 ağ kopması 19 sn → yok, 21 sn → öner. Bağlanıyor 30 sn → öner; görüntü gelince → yok. TV 50 sn →
  yok, 61 sn → öner. Kural var + ortak ağ + TV 61 sn → ortak ağ. Kural var, özel ağ → yok. PS5 uykuda 120 sn → yok ve
  kural hiç taranmaz. Kural var, iki denetim → bir tarama. İzin ver → izin verildi, oturuma 1, bekçiye 1 yeniden bağlan;
  120 sn sonra hâlâ izin verildi. Durdur → yok, sonra denetim de yok. Yalnız bilgisayarda gösterimde TV beklenmez.
  Eşleştirme: genel kayıt hatası + kural yok → öner; kural var → yok; kural var + ortak → ortak ağ; hesap yanlış /
  kötü adres → yok ve tarama yok; ağ istisnası → öner ve ileti istisnanın iletisini içerir; izin ver → izin verildi,
  TV adımına geçince yok; kullanıcı reddederse başarısız; hizmetsiz derlemede hiçbir şey.

---

## 17. Uygulama güncellemesi (denetleyicinin payı)

(Güncelleyicinin kendisi ayrı belgede.)
- Durumlar: yeni sürüm numarası, güncelleniyor, ilerleme, hata, "kendini güncelleyebilir mi".
- **Denetle**: güncelleyici yoksa çık. Ağ/zaman aşımı/dosya/geçersiz işlem hataları sessiz. Uygulama kapanmıyorsa, yeni
  sürüm varsa, kendini güncelleyebiliyorsa ve kendiliğinden kurulabiliyorsa (sürüm başına 2 deneme dolmadı **ve** bu
  açılışta bitmemiş otomatik indirme 3'ten az): çeviri sürüyorsa "bekleyen kurulum" işaretlenir (çeviri
  durunca kurulur, oyun bölünmez), değilse hemen kendiliğinden kurulur. İlk denetimde 3 saatlik döngü başlar (her
  turda arayüzde yeniden denetle).
- **Kur** (düğme ya da kendiliğinden): güncelleyici yoksa, zaten kuruluyorsa ya da kendiliğinden ve kapanıyorsa çık.
  Kendini güncelleyemiyorsa indirme sayfası tarayıcıda açılır. Bekleyen işaret silinir, güncelleniyor, hata temizlenir;
  **önce çeviri durur**; indirilir; kurulum başlamadan hemen önce deneme sayılır (sayaç dosyaya yazılamazsa ve
  kendiliğindense hata fırlatılır → kurulum başlamaz; aksi hâlde sürüm değişmeyen kurulum her açılışta yeniden
  başlardı). Hata (ağ, iptal, dosya, geçersiz işlem, yetki): ileti gösterilir; kendiliğinden ve kurulum aşamasına
  gelinmediyse yarıda kalan indirme sayılır. Her durumda güncelleniyor = hayır.
- Sayaç dosyası: `auto-update-tried.txt`, iki satır (sürüm, sayı); eski biçim (yalnız sürüm) bir deneme sayılır.

---

## 18. Kapanış

"Kapanıyor" işaretlenir (Durdur bekleyen güncellemeyi başlatmasın; indirme kapanan uygulamada yarıda kalırdı —
bekleyen güncelleme sonraki açılışta). Olay abonelikleri çözülür; Durdur; sorun bekçisi kapanır; Xbox hizmeti kapatılır;
sunucu kapanır; zamanlayıcılar durur; satır havuzu ve çeviri havuzu kapanır (havuz satırları zaten diskte; kapanışta ağ
beklenmez).

---

## 19. Ekranlara verilen durum metinleri

### 19.1 Konsol/görüntü kaynağı durum metni (tek satır; ana ekran)
Öncelik: oyun penceresi → kart → Xbox türü → Remote Play penceresi → seçilen pencere → PS5.

**PS5** (`StatusText`):
| Durum | Metin anahtarı |
|---|---|
| görüntü geliyor | `status.common.connected` |
| bağlanıyor | `status.common.connecting` |
| çeviri yok, eşleşme yok | `status.common.notConnected` |
| çeviri yok, eşleşmiş | `status.ps5.pairedIdle` (ad; ad boşsa "PS5") |
| uykuda | `status.ps5.asleep` |
| başka cihazda | `status.ps5.inUseElsewhere` |
| reddetti | `status.ps5.refused` |
| giriş şifresi | `status.ps5.passcodeRequired` |
| giriş şifresi yanlış | `status.ps5.passcodeWrong` (bir kez gönderilir; döngü yok) |
| eşleşme geçersiz | `status.ps5.pairingInvalid` |
| Uzaktan Oynatma kapalı | `status.ps5.remotePlayOff` |
| bulunamadı | `status.ps5.notFound` (adres; yoksa "?") |
| ağ | `status.ps5.unreachable` |
| oturum reddedildi + kod | `status.ps5.sessionRejectedCode` (kod) |
| oturum reddedildi, kodsuz | `status.ps5.sessionRejected` |
| diğer + ayrıntı | `status.common.reconnectingDetail` (ayrıntı) |
| diğer / durdu | `status.common.reconnecting` |

Testte denenenler: uykuda, ağ, bulunamadı (adresle: metinde adres geçer), "diğer + ayrıntı" (ayrıntı chiaki-ng'nin
oturum nedeni olduğunda metne aynen girer), kodlu ret (Türkçede kod metne girer, ör. 0x80108bff), eşleşmiş başlamamış
(Türkçede PS5 adı metne girer) ve Türkçe "bağlı".

**Xbox**: görüntü → `status.common.connected`; bağlanıyor → `status.common.connecting`; çeviri yok → konsol yoksa
`status.common.notConnected`, varsa `status.xbox.readyIdle` (ad); reddetti ve ayrıntı varsa ayrıntının kendisi (denemeler
bitti, oturum durdu); başka ayrıntı varsa `status.xbox.retryingDetail`; değilse `status.xbox.retrying`.

**Remote Play penceresi**: görüntü gelmiyor ve uygulama kurulu değilse `status.remotePlayWindow.notInstalled`. Görüntü →
`status.remotePlayWindow.reading`; bağlanıyor → `status.remotePlayWindow.waiting`; çeviri yok →
`status.remotePlayWindow.idle`; diğer → ayrıntı ya da bekleniyor metni. İndirme sayfaları: Sony
`https://remoteplay.dl.playstation.net/remoteplay/`, chiaki-ng `https://github.com/chiaki-ng/chiaki-ng/releases/latest`.

**`status.console.titleSelectedWindow`**: hedef yoksa ya da adı/başlığı boşsa `status.selectedWindow.notChosen`; görüntü →
`status.selectedWindow.reading`; çeviri yok → `status.selectedWindow.idle` (başlık); diğer → ayrıntı ya da
`status.selectedWindow.waiting` (başlık).

**oyun penceresi** (PS5): okunuyor → `status.common.reading` (uygulama adı; yoksa "PS Remote Play"); aranıyor
ya da (çeviri sürüyor ve durdu) → `status.gameWindow.ps5.startPlaying`; çeviri yok → `status.gameWindow.ps5.idle`.
Xbox: okunuyor → `status.common.reading` (uygulama adı; yoksa "Xbox"); aranıyor/sürüyor →
`status.gameWindow.xbox.startPlaying`; yok → `status.gameWindow.xbox.idle`.

**Kart**: izin yok → `status.card.noPermission`; kart yok → `status.card.notPlugged`; siyah → `status.card.black`;
okunuyor → `status.common.reading` (aygıt adı; yoksa `status.card.defaultName`, Türkçede de İngilizce kalır); diğer →
`status.card.idle`.

**Konsol başlığı**: Xbox türünde "Xbox", seçilen pencere yolunda `status.console.titleSelectedWindow`, diğer "PS5".

### 19.2 Noktalar (renk)
- Konsol noktası: kart siyah görüntüdeyse sarı; değilse görüntü geliyorsa yeşil, çeviri sürüyorsa sarı, değilse gri.
- TV noktası: TV yoksa gri; bağlı TV varsa yeşil (çeviri yokken de); çeviri sürüyorsa sarı; değilse gri.
- TV metni: TV yok → "Kurulmadı"; bağlı → "Bağlı"; değilse `status.tv.waitingForApp`.

### 19.3 Diğer göstergeler
- **Ana hesap ipucu** (GitHub #231): çeviri sürüyor, Xbox değil, PS5 yolu (iki kaynak da PS5), henüz hiç çeviri gelmedi →
  PS5 açılırken ana hesabın seçilmesi gerektiğini hatırlatan ipucu çıkar.
- Çevirmen durumu, çevrimiçi uyarı (motor ve durum), OCR eksik, GPU uyarısı, duraklatıldı, son kaynak/çeviri, son kare,
  etkin dil, sunucu portu, model indirme (iniyor, ilerleme, hata), TV uygulaması durumu, LG kalan saat, güvenlik duvarı,
  güncelleme durumları, yüklü paketler, oynanan oyun, "hangi oyun" kartı açık mı, son seçilen oyun, geçmiş, ölçüm satırı,
  pencere/kart durumu ve oyun alanı, kart rehberi açık mı, tercih edilen kart, havuz kuruluş kimliği.
- Çevrimiçi hata açıklaması (Ayarlar ve ana ekran aynı metni kullanır; %@ = motor adı): geçerli →
  `status.online.working`; geçersiz → `status.online.invalidKey`; kota → `status.online.quota`; model reddi →
  `status.online.modelRejected`; diğer → `status.online.unreachable`. Yerel modelde: anahtar reddi →
  `status.online.local.keyRejected`; kota → `status.online.local.busy`; model reddi LM Studio'da
  `status.online.local.lmStudioModelMissing`, diğerinde `status.online.local.modelMissing`; ulaşılamadı Ollama'da
  `status.online.local.ollamaDown`, LM Studio'da `status.online.local.lmStudioDown`, diğerinde
  `status.online.local.unreachable`. Motor adı: yerel model çevrilir (`status.online.localModelName`),
  diğerleri marka adı.

---

## 20. Test senaryoları (yeni testler bunlarla yazılır)

Sahte dünya: bellek deposu, bellek ayarları, uyku bekçisi (etkin mi, ekran açık mı), sahte yayın (başlatıldı mı,
yeniden bağlanma sayısı, durum/kare/yeni adres yayar), sahte pencere ve kart kaynakları, sahte bekçi, sahte model
(yalnız en→tr destekli; indirme 0,5 ilerleme bildirir, kapı verilirse onu bekler; oluşturma hatası verilebilir;
"başarısız" yapılabilir; çevirmen "TR: " önekiyle yankılar), sahte okuyucu, sahte hizmetler (PS5 `192.168.1.253`
"PS5-789" uyanık; TV "LG TV" `192.168.1.153`; kayıtta konsol adı "PS5-789"; eşleşme jetonu `tv-key`, TV'de uygulama
`0.6.1`, paket `0.6.1`, LG parolası `ABC123` → anahtar `dev-key`, uzatma 999 saat). Arayüz aktarması "hemen çalıştır",
sunucu yeniden deneme beklemesi 0.

Kurulum:
1. Yeni kurulum Karşılama'da başlar.
2. Hesap + konsol + TV + jeton kayıtlı → Bitti, ve `setupComplete`=true bir kez kaydedilir.
3. Hesap + konsol kayıtlı → TV adımı; Samsung'la eşleşince TV var ama yeniden açılışta yine TV adımı, `setupComplete`=false.
4. Aynı durumda dört İlerle → Bitti; yeniden açılışta Bitti.
5. "TV'm yok" → yeniden açılış TV adımı; üç İlerle → Bitti; yeniden açılış Bitti.
6. Bütün adımlar sırayla (Karşılama → İkinci hesap → PSN [giriş] → PS5 [kayıt] → TV [eşleşme] → Model → Deneme → Daha iyi
   çeviri → Bitti).
7. Daha iyi çeviri geçilebilir (motor ücretsiz kalır); Geri → Daha iyi çeviri; Geri → Deneme.
8. Gemini anahtarı `"  AIza-free  "` → denenen (Gemini, `AIza-free`, ücretsiz katmanlı varsayılan model), kaydedilir, motor
   Gemini, "ücretsiz Gemini kullanılıyor" bildirilir; İlerle → Bitti. Yanlış anahtar kaydedilmez; kota bitmiş anahtar kaydedilir.
9. "Ücretsiz anahtar al" → motor Gemini, çevrimiçi etkin değil (anahtar yok).
10. Model inmemişken Karşılama'dan İlerle → indirme 1 kez başladı, iniyor; model adımında devam edilemez; indirme
    bitince devam edilebilir ve ilerleme 1.
11. Eşleşme sonrası kendiliğinden ilerleme yalnız PS5 adımından (Geri'den sonra PSN'de kalır; PS5 adımına konunca TV'ye geçer).
12. Kısa yollar: oyun penceresi → Model adımı, başlatılabilir, yeniden açılışta Bitti; Xbox penceresi → TV adımı, TV'de
    gösterim, başlatılamaz (TV yok), Geri → Karşılama, yer bilgisayar → başlatılabilir, pencere kaynağına Xbox verilir;
    kart rehberi (bilgisayar) → Model ya da Deneme, Geri → rehber, yeniden açılış Bitti; kart rehberi (TV) TV yoksa TV
    adımı, varsa Deneme/Model; rehberden vazgeçip Karşılama'dan İlerle → görüntü kaynağı PS5, İkinci hesap.
    İkinci hesap yok → Bitti, Remote Play penceresi, yer bilgisayar, hesap yok, başlatılabilir. OBS/pencere → Bitti ama
    pencere seçilene kadar başlatılamaz; `obs64` / `Fullscreen Projector (Scene)` seçilince başlatılabilir.
13. Ayarlar'da konsol Xbox → oyun penceresi; kart seçiliyken PS5'e dönmek kartı bırakmaz.
14. Pencere modunda kurulup PS5'e geçilince `settings.source.linkAccount` görünür, başlatılamaz; bağla → İkinci hesap.

Çeviri:
15. İki kez Başlat aynı anda → tek oturum, tek bekçi.
16. Bekçinin yeni jetonu (`new-token`) kaydedilir. Samsung eşleşmesinde boş jeton saklı `samsung-token`'ı silmez.
17. Başlat → uyku etkin; Durdur → değil. PS5 yeni adres `192.168.1.77` → kaydedilir.
18. Kopma → TV akışında `event: clear`. Başlat → `event: started` (hemen sonra bağlanan TV de alır).
19. Ayar değişince güvenli depoda yalnız `setupComplete` durur; yazı boyu 58 yeniden açılışta kalır.
20. Çeviri sürerken kaynak dil `ja` → etkin dil `ja`, okuyucu dilleri [en, ja].
21. OCR paketi yok → OCR eksik; hiç OCR yok → OCR eksik.
22. Ücretsiz motor oluşturulamaz → çeviri yine başlar, durum "motor açılamadı". Motor ısınırken açılamadı → uyarı hemen;
    DeepL seçilince hazır ve DeepL yedeksiz; DeepL kaldırılınca yine "motor açılamadı".
23. Giriş şifresi: `12a4` red, `" 4321 "` kabul; oturuma `4321`; kaldırınca yok; `settings.reset.everything` şifreyi siler.
24. Ekran açık kalsın (§10.3 örneği).
25. seçilen pencere yolunda başlat → seçilen pencere kaynağı, PS5 oturumu yok; pencere `game`/`Gameplay` yapılınca yeni
    kaynakla yeniden başlar (iki kaynak), çalışıyor.
26. Remote Play penceresi (chiaki) kurulu, kayıt yok → Bitti, kurulum kaydına dokunulmamış, başlatılabilir, metin
    `status.remotePlayWindow.idle`; başlatınca chiaki kaynağı, PS5 oturumu yok. Uygulama yoksa `status.remotePlayWindow.notInstalled`.
27. PS5 ile sürerken çerçeve kaynağı Remote Play penceresi → yeni kaynak (kendiliğinden) ile ikinci oturum, çalışıyor.
28. Xbox eski kare aralığı ayarı yayına geçer ve kaydedilir.
29. Pencere kaynağında: PS5/TV olmadan başlar, PS5 oturumu yok; metin `status.gameWindow.ps5.startPlaying`;
    okunuyor (PS Remote Play, 1280×720) → evre görüntü, metin `status.common.reading` (PS Remote Play), oyun alanı;
    Durdur → kaynak durdu, alan yok, pencere durdu. Pencerede sürerken PS5'e dönülünce (PS5 kurulu değil) eski kaynak
    durur, çeviri başlamaz.
30. Kart: tercih `card-1` depoda; metin `status.card.idle`; başlat → kart kaynağı (oyun gösteriliyor, `card-1`),
    kart oynatıcısı görünür; kart yok → metin ve sarı; okunuyor (Elgato HD60 X, 1920×1080) → görüntü, yeşil, alan; siyah →
    sarı; tam ekran 1 kez; oyun penceresi kapanınca çeviri durur, kart durdu. Geçişli kart (TV) → oyun gösterilmez, bekçi
    var. Kartta yer TV→bilgisayar → kart yeniden açılır (ikincisi oyunu gösterir). Eski kart oturumunun geç olayları yok
    sayılır. Kartta "ikisi de" yeniden açılışta korunur; PS5'te "ikisi de" TV olur. Ayarlar'dan rehber bitirme yalnız seçimi kaydeder.
31. Yalnız bilgisayarda gösterim: başlatılabilir, TV'de değil, bekçi yok; TV hizmetine hiç dokunulmaz (PS5 ağ kopması ve
    denetimde de; yarım eşleşmiş Samsung'da da). Başlatma hatası (yerel kütüphane yok) → çalışmıyor, başlatılmıyor, uyku
    yok, bilgisayar penceresi bir kez boşaltıldı, hata fırlatılır; sorun kalkınca başlar. Yalnız TV ve TV yok → başlatılamaz,
    "TV gerekli", "Kurulmadı". Sürerken "ikisi de" → bekçi çalışır; "bilgisayar" → durur. "TV'm yok"tan sonra TV eşleşince yer TV.
32. Ek bölge: varsayılan kapalı ve sürekli değil; yalnız açık + sürekli olanlar izlenir (`area1`); sürekli bölge tuşsuz
    okunur ve "bölge" olayı gelir, ek okuyucu sayesinde okuyucu dili iki kez istenir; durunca "bölge temizle". Ayarsız →
    "ayarlı değil"; çeviri yok → "çalışmıyor"; boş kare → "yazı yok"; serbest alan varsayılan TV, çeviri yokken "çalışmıyor",
    boş alanda "yazı yok". Bilgisayar hedefli bölgede açılır pencereye `status.area.noText` gider; TV hedefinde gitmez.
33. `shortcut.action.translateScreen`: çeviri yok → "çalışmıyor"; boş kare → "yazı yok"; yazılı kare → göster/temizle/göster; yalnız
    bilgisayarda gösterimde "ekran" olayı bilgisayar penceresine gelir (metni çevrilmiş) ve ikinci basışta "ekran temizle";
    kare yokken "PS5" geçen bir altyazı gelir.
34. Durum metinleri ve noktalar: §19 tabloları; çeviri yokken bağlı değil gri; sürüyor ve bağlı değil/bağlanıyor sarı;
    TV 0 sürüyor sarı; bağlı yeşil; TV 1 çeviri yokken yeşil.
35. TV uygulaması (LG): uygulama bulunmuyor + geliştirici kapalı → "geliştirici modu kapalı"; geliştirici açık + anahtar yok →
    "parola gerekli"; `" ABC123 "` → "güncel 0.6.1", 1 kurulum, anahtar kaydedildi, eşleşme sayısı +1 (uygulama açıldı);
    yanlış parola → hata "yanlış parola", anahtar sunucusu kapalı → "anahtar sunucusu kapalı", kurulum yok; eski 0.4.0 →
    sorulmadan kurulur; güncel → kurulmaz; anahtar reddi → anahtar silinir, "parola gerekli"; uzatma 999 saat ve günde bir
    (ikinci denetimde yine 1). Çalışan uygulama + anahtar yok → "bilinmiyor". Samsung TV LG yolundan kurulmaz.
36. Samsung (paket 0.7.0): geliştirici kapalı → adımlar, "kurabilir"; giriş olayı → tarayıcıda giriş sayfası açılır,
    "güncel 0.7.0", sürüm kaydı, ikinci denetimde kurulum tekrarlanmaz; TV'de 0.6.0 ama kayıt 0.7.0 → yine kurulur;
    TV'de 0.7.0 → kurulmaz, kayıt 0.7.0; ulaşılamadı + kayıt var → "güncel"; kayıt yoksa "başarısız: ulaşılamadı", sebep
    "sdb: closed"; Host PC IP `192.168.1.50` ≠ `192.168.1.34` → sdb denenmez, iki adres durumda; düzelince kurulur;
    8001 "kapalı" → adımlar; giriş başarısız → başarısız; paket engellendi + "app_id[NinoTVApps.Nino] install failed[118,
    -22]" → sebep bu; giriş hatası sebebi: girişin 10 dakikada bitmediği.
37. Android TV (paket 0.7.0, adres boş): bulunamaz → "geliştirici modu kapalı"; `192.168.1.40` ağda bulununca + onay
    olayı → "güncel 0.7.0", TV adresi ve kaydı `192.168.1.40`.
38. TV yeni adreste (`192.168.1.230`) → bellek ve depo güncellenir.

Diğer: GTA VI seçilince "havuz öncelikli canlı oyun" açılır, RDR2'de kapanır, havuzsuz derlemede açılmaz; indirme sayısı
senaryosu §13.3; ayarların JSON'a metin olarak (ör. `"VideoSource":"Window"`, `"Output":"Both"`, `"OnlineEngine":"Gemini"`)
yazılması `kimlikler-veri.md`'de.

---

## 21. Windows'a özgü (platform) kısımlar

Denetleyicinin kendisinde Windows API'si yoktur; aşağıdakiler `Nino.App`'teki hizmet uygulamasındadır:
- **Şifreli depo**: DPAPI (kullanıcı kapsamı) ile `%LOCALAPPDATA%\Nino\secure.dat`.
- **Ayarlar**: `%LOCALAPPDATA%\Nino\settings.json`; ilk açılışta hedef dil Windows arayüz dilinden.
- **Uyku bekçisi**: Windows'un "sistem gerekli" (ve isteğe bağlı "ekran gerekli") yürütme durumu; çeviri bitince eski hâline.
- **Uykudan uyanış**: uygulama sistem güç olayını dinleyip denetleyiciye "uyandı" der.
- **Güvenlik duvarı**: `firewall.settings.title`'nda bu exe için Özel profilde gelen TCP/UDP kuralı; ekleme yönetici
  izniyle (UAC); ağ profili Ortak mı sorusu.
- **Pencere ve kart kaynakları**: Windows Graphics Capture (pencere), Media Foundation/kamera aygıtları (kart); kamera
  izni Windows Gizlilik ayarından.
- **Yazı tanıma**: Windows OCR; dil paketi yoksa sistem diliyle okur (uyarı). İngilizcede Windows yazım denetimi sözlüğü
  okuma puanı ve "bozuk okuma" denetimi olarak açılır, diğer dillerde kapalı; her okuyucu kurulumunda yeniden ayarlanır.
  Paketteki satırlar "doğru okuma" ölçüsü olur (yalnız birebir).
- **Ücretsiz model**: Türkçe için CTranslate2 (isteğe bağlı NVIDIA CUDA; `nvcuda.dll` yoksa CUDA çalışma zamanı ~565 MB
  indirilmez, doğrudan CPU), diğer dillerde ONNX; aygıt ya da iş parçacığı değişince açık çevirmenler kapanır. Motor
  açılamazsa hata günlüğüne bir kez yazılır ve olay verilir. Türkçe yeni model kurulunca eski ONNX klasörü (`en-tr`) silinir.
- **Küçük JPEG** (oyun tanıma): WPF kodlayıcısı (bkz. `saglik-bildirim-sor.md` §7.5).
- **Güncelleyici**: Velopack; kurulum dosyasıyla kurulmadıysa (zip) yalnız indirme sayfası.
- **Tarayıcı açma**: varsayılan tarayıcı (PSN, Xbox, Samsung hesabıyla giriş, indirme sayfası). Denetleyicide "tarayıcıda aç"
  bir işlevdir; arayüz atar (testte boş).
- **Samsung cihaz adı**: yeni eşleşmede "Nino", eski eşleşmede eskisi kalır (ad değişirse TV izni yeniden sorar);
  hatırlanan ad şifreli depoda (`samsungClientName`).
- **LG anahtar dosyası**: ssh anahtarı geçici bir dosyaya yalnız komut süresince yazılır, sonra silinir.
- **Samsung/Android kurulum günlüğü**: `%LOCALAPPDATA%\Nino\tvinstall.log`; kalıcı dosyalar `samsung\` ve `adb\` klasörlerinde.
- **Paketle gelen TV uygulamaları**: exe'nin yanındaki `tv-app\` klasöründe `*.ipk` (LG), `*.wgt` (Samsung), `*.apk` (Android).
