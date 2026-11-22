# Nino iOS: uygulama modelinin davranışı

Bu belge şu anki iPhone/iPad uygulamasının (`nino-ios/Nino/`: `PhoneModel`, sağlık izleme, servisler, hatalar,
indirme sayacı, `Account/`, `NinoApp`) ne yaptığını düzyazıyla anlatır. Yeni uygulama aynı davranışı kendi koduyla
kurmalıdır. Kalıcı kayıtların biçimi ayrı belgede: `kalicilik.md`.

Metinler burada yalnız yeni uygulamanın metin anahtarıyla anılır (`apps/ios/Nino/Resources/Localizable.xcstrings`;
metnin kendisi ve dillere göre karşılıkları oradadır). Katalogda karşılığı olmayan metinler kısa bir anlam
notuyla anlatılır.

---

## 1. Açılış

Sıra önemlidir:

1. Test süreci mi diye bakılır (Xcode test ortam değişkeni). Testte kalıcı hiçbir şeye dokunulmaz.
2. **Klasör taşıma** (eski klasör → `Nino`), hiçbir dosya açılmadan önce (bkz. `kalicilik.md` 5.1).
3. Paket kitaplığı kurulur: uygulamayla gelen paketler, üstüne sunucudan inenler, en üstte içe aktarılanlar.
4. Model kurulur. Üç yol vardır: test (bellekte depo), hata ayıklama kipleri (bkz. 11), normal (Anahtar Zinciri).
5. Ekran açık tutma, bağlantı kopması bildirimi ve bildirim izni isteme bağlanır (testte değil).
6. Geçmiş (`history.json`) okunur (testte ve deneme karesinde değil).
7. Uygulama düzeyi model kurulur (paket indirme, tanıtım turu). Paket sunucusu adresi Info.plist'teki paket adresi
   anahtarından gelir (değer depoda olmayan gizli yapılandırma dosyasından girer); boşsa (ya da `$(` ile başlıyorsa)
   paket indirme hiç çalışmaz.
8. Arayüz dili çeviri diline göre ayarlanır (bkz. 9).
9. Pencere açılınca paket yenileme döngüsü başlar.

Model kurulurken (constructor) yapılanlar:

- Anahtar Zinciri'nden: `accountId`, `console`, `tv`, `tvKey` (yalnız var/yok), `loginPasscode` (geçerli mi),
  `xboxConsole`, `xboxUserToken`.
- UserDefaults'tan: `platform`, `settings`, `setupSkipped`, `disabledPacks`, `tvAppInstalled`, `lastGames`.
- Hangi çeviri anahtarlarının kayıtlı (ve boş olmayan) olduğu bir kümeye alınır; sonraki kararlar bu kümeye bakar.
- Remote Play günlüğü açılır (testte ve deneme karesinde değil).
- Sorun kaydı, otomatik bildirimci, ortak havuz ve çeviri havuzu kurulur (testte devre dışı).
- Altyazı sunucusu nesnesi kurulur ama **başlatılmaz** (ilk TV eşleşmesinde, deneme altyazısında ya da çeviri
  başlarken başlar).

---

## 2. Kurulum adımları (Step)

Adımlar sırayla: `welcome` (0), `psnLogin` (1), `console` (2), `output` (3), `done` (4).

### 2.1 Açılıştaki adım (kayıtlardan hesaplanır, saklanmaz)

```
skipped  = UserDefaults setupSkipped
complete = Anahtar Zinciri setupComplete == true
psReady  = accountId var VE console var
xboxReady= platform == xbox VE geçerli Xbox jetonu VE xboxConsole var

step = done    eğer complete VE (skipped VEYA psReady VEYA xboxReady)
       output  değilse ve skipped
       welcome değilse
```

`platformChosen` da hesaplanır: UserDefaults'ta `platform` var **veya** `accountId` var **veya** `console` var (PS5'i
önceden eşlenmiş kullanıcıya konsol türü yeniden sorulmaz). `platform` yoksa konsol türü PlayStation sayılır.

### 2.2 İlerleme kuralları

| Adım | İleri düğmesi (`common.next`) açık mı |
|---|---|
| `welcome` | Her zaman |
| `psnLogin` | PlayStation: `accountId` var. Xbox: Microsoft girişi var |
| `console` | PlayStation: `console` var. Xbox: Xbox seçili |
| `output` | TV var (`tv` + `tvKey`) **veya** `output` = `computer` (`tv.none`) |
| `done` | Yok |

- Adım `done`'a **geçtiği an** Anahtar Zinciri'ne `setupComplete = true` yazılır.
- Şimdilik atla (`common.skipfornow`): `setupSkipped = true`, adım `output`. Bu kullanıcı PS5'siz ana ekrana gider; eşleme sonra yapılır.
- TV yok (`tv.none`): `output = computer`, bir adım ilerler.
- Geri: bir önceki adım.
- **Kurulum sıfırlama:** çeviri durur; Anahtar Zinciri'nden `accountId`, `console`, `tv`, `tvKey`, `setupComplete`,
  `loginPasscode`, `xboxConsole` silinir; Xbox çıkışı yapılır (jeton silinir); UserDefaults'tan `platform` ve
  `setupSkipped` silinir; adım `welcome`. Ayarlar, çeviri anahtarları, geçmiş ve `welcomeSeen` **kalır**.

### 2.3 Ekran akışı (kök görünüm)

1. `welcomeSeen` false ise karşılama gösterilir. Bitince `welcomeSeen = true` ve adım `welcome` ise bir ilerler.
2. Adım `done` değilse kurulum ekranları:
   - `welcome`/`psnLogin`: konsol türü seçilmemişse önce tür seçimi; sonra PlayStation için PSN girişi, Xbox için
     Microsoft girişi. Giriş bitince adım `welcome`'daysa iki, değilse bir ilerler.
   - `console`: PS5 eşleme (Xbox'ta Xbox seçimi).
   - `output` (ve `done`): altyazının yeri (TV seçimi ya da `tv.none`).
3. `done` ise ana ekran ve alt sayfalar (Ayarlar, Profil, Paketler, Dil, Geçmiş, Hakkında, TV kurulum/güncelleme,
   PS5 eşleme). Kurulumu atlamış kullanıcı PS5 eşlemeye girerse ve PSN girişi yoksa önce giriş istenir.
4. Tanıtım turu: ana ekranda, alt sayfa açık değilken, çeviri sürmüyorken ve `coachTourDone` false iken.

### 2.4 PSN girişi ve PS5 eşleme

- PSN girişi: giriş penceresinin yönlendirme adresinden hesap kimliği (8 bayt) alınır, `accountId` olarak yazılır.
- PS5 arama: yerel ağda aranır; ilk aramada iOS yerel ağ iznini sorduğu için boş dönerse bir kez daha aranır.
- Eşleme: adres kırpılır; boşsa hata; kod 8 hane değilse hata; `accountId` yoksa hata. Başarıda `console` yazılır.
- Hatalar kullanıcıya şu metinlerle gösterilir; ayrıntı (PS5 kodu, Sony yanıtı) varsa metnin sonuna parantezle eklenir:
  `Metin (ayrıntı)`.

| Durum | Metin anahtarı |
|---|---|
| Kod 8 hane değil | `pair.error.codelength` |
| PSN girişi yok | `psn.error.signinfirst` |
| Adres boş | `pair.error.notfound` |
| Hesap tanınmadı | `pair.error.wrongAccount` |
| Kod yanlış/süresi doldu | `pair.error.wrongCode` |
| PS5 yanıt vermedi | `session.error.noanswer` |
| İstek alındı, yanıt geç / iptal | `pair.error.late` |
| Başka cihazda kullanımda | `pair.error.inUse` |
| PS5 hizmeti çöktü | `pair.error.crashed` |
| Sürüm desteklenmiyor | `pair.error.version` |
| Adres yanlış | `pair.error.notatAddress` |
| Yerel ağ engelli | anahtarı yok: iOS'un yerel ağ iznini (Ayarlar › Gizlilik ve Güvenlik › Yerel Ağ) açıp yeni kod girmesini söyleyen bir not (`pair.help.body` buna yakın) |
| Diğer eşleme hatası | `pair.error.badcode` |
| Giriş kodu gelmedi / bilinmeyen | `signin.error.incomplete` |
| Sony reddetti | `psn.error.notcompleted` |
| Çok deneme | `psn.error.ratelimit` |
| Sony sunucu hatası | `psn.error.server` |
| Ağ yok | `psn.error.network` |
| Yanıt okunamadı | `psn.error.badresponse` |
| Pencere kapandı | `psn.error.windowclosed` |

### 2.5 TV eşleşmesi

1. Altyazı sunucusu başlatılır (bkz. 5).
2. TV markasına göre:
   - **LG:** WebSocket (SSAP; önce şifreli 3001, olmazsa 3000). İlk seferde TV ekranında onay istenir (en çok 60 sn).
     Dönen client-key saklanır. Ardından TV uygulaması (`com.ninotranslator.tv`) `server` parametresiyle açılır.
   - **Samsung:** `wss://TV:8002/...samsung.remote.control` bağlantısı, dönen jeton saklanır (boş jeton gelirse eski
     korunur). TV uygulaması (`NinoTVApps.Nino`) `server` parametresiyle açılır.
   - **Android TV:** telefon TV'yi denetlemez; eşleşme hemen "başarılı" sayılır, `tvKey` boş metin olarak yazılır. TV
     uygulaması telefonu ağda kendisi bulur (bkz. 5).
3. `tv` ve `tvKey` yazılır. TV uygulaması açılamadıysa "uygulama eksik" işareti (`tv.status.noapp`) konur (kurulum önerisi).
4. Ayar `output` = `computer` idiyse `tv` yapılır.

`server` parametresi: `http://<telefonun TV ile aynı ağdaki IPv4 adresi>:<port>`. Adres, TV adresine en yakın ağ
bağdaştırıcısından seçilir (VPN, hücresel ve sanal bağdaştırıcılar atlanır); bulunamazsa `127.0.0.1`. TV adresi boşsa
`192.168.1.1` varsayılarak seçilir.

Telefondan TV uygulaması kurulduğunda (LG/Samsung/Android TV kurulum ekranı) TV hatırlanır (`tvAppInstalled`); o TV
henüz eşli değilse kendiliğinden eşlenir (ad: "Android TV", "LG TV", "Samsung TV"); adım `output`'taysa
`setupComplete = true` yazılır.

### 2.6 TV uygulaması sürüm denetimi

- TV uygulaması altyazı sunucusuna **ilk bağlandığında** (0 → 1 istemci) ve uygulama açılınca sessizce yapılır; en çok
  dakikada bir (zorla istenmedikçe).
- Hedef: `tvAppInstalled` varsa o TV, yoksa eşli TV. Sürüm Samsung'da sdb, Android TV'de adb, LG'de geliştirici modu
  SSH'ı ile okunur (LG'de kayıtlı anahtar ve açık geliştirici modu yoksa okunmaz; okununca geliştirici modu süresi en
  çok 20 saatte bir uzatılır).
- Uygulamanın içindeki TV paketi daha yeniyse ana ekranda TV uygulaması için yeni sürüm önerisi çıkar. Okunan sürüm
  `tvAppInstalled`'a yazılır.

---

## 3. Çeviri oturumunun yaşam döngüsü

### 3.1 Başlatma

Başlatılabilir mi: PlayStation'da `console` + `accountId`, Xbox'ta seçili Xbox + giriş; ve altyazı telefonda
gösterilecekse (`output` = `computer`) ya da TV varsa. Zaten çalışıyorsa ya da başlıyorsa bir şey yapılmaz. Demo
açıksa önce kapatılır.

Başlatma sırası:

1. "Başlıyor" işareti; çeviri motorunun durumu yenilenir (ücretsiz çeviri indirilmiş mi, destekleniyor mu).
2. Altyazı sunucusu başlatılır (hata olursa sessizce geçilir), stil TV'ye gönderilir.
3. Okuma hattı kurulur (bkz. 6).
4. Bağlantı oturumu kurulur: Xbox'ta Xbox yayın oturumu (`xboxAudioOnDevice` ayarıyla); PS5'te Remote Play oturumu
   (kayıtlı giriş şifresi varsa onunla).
5. Son hata nedeni silinir, oturum başlar; TV açık tutucu başlar (yalnız `output` TV'yi kapsıyorsa ve TV varsa; 5 sn'de
   bir).
6. Oyun seçimi başlar (PS5 adı ile; "oyunu sor" yalnız `askGame` ve `sharePool` açıkken).
7. Çalışıyor = evet. Sağlık kaydı başlar; TV'ye `started` olayı gider; sayaçlar, son satırlar sıfırlanır; başlangıç
   anı tutulur.
8. Ekran açık tutulur. Bağlantı bildirimi tercihi (`settings.notify.drop`) açıksa bildirim izni istenir (iOS yalnız ilk seferde sorar).

### 3.2 Durdurma

1. Oturum süresi hesaplanır ve `lastSessionSeconds`'a yazılır.
2. Sağlık kaydı biter (bu oturumda sorun olduysa otomatik bildirim; bkz. 10).
3. Oyun seçimi, oturum, oyun sorgusu, TV açık tutucu, okuma hattı, havuz eşitlemesi, ek alan/köşe/telefon/harita
   okuyucuları durur.
4. Okuma kapısı sıfırlanır (takılmış okuma yeni başlatmayı bekletmez).
5. Çalışıyor = hayır, çevrimiçi hata ve son neden silinir, durum `disconnected(stopped)`.
6. Telefondaki altyazılar ve "ekranı çevir" sonuçları kalkar. Ekran açık tutma bırakılır.

Not: durdurmada TV'ye `stopped` olayı gönderilmez (TV satırları kendi süresinde kaldırır).

### 3.3 Ön plan / arka plan (scenePhase)

Uygulamada arka plan kipi (`UIBackgroundModes`) yoktur: iOS arka plandaki uygulamayı askıya alır, PS5 ve TV bağlantıları
kopar.

| Geçiş | Davranış |
|---|---|
| `background` | "Arka plana gitti" işareti; sağlık zamanlayıcıları iptal (arka plandaki kopmalar sorun sayılmaz); ortak havuz kuyruğu hemen gönderilir |
| `inactive` | Hiçbir şey (Denetim Merkezi, bildirim, izin penceresi) |
| `active` | Ekran açık tutma bayrağı yeniden uygulanır; "ön planda" işareti; çeviri sürüyorsa: arka plandan dönüldüyse **ya da** oturum o an bağlı/bağlanıyor değilse PS5 oturumu hemen yeniden kurulur; TV açık tutucu her durumda yeniden bağlanır |

Yalnız `inactive`'den dönmek canlı PS5 oturumunu kapatıp açmaz (eskiden açıyordu; PS5'te ikinci hesap girip çıkıyordu).

### 3.4 Durum değişiminde model ne yapar

- Durum yazılır; çalışıyorsa "son neden" kuralı uygulanır (3.5).
- Akış sürerken kendiliğinden koptuysa (neden `stopped` değil) ve tercih açıksa bağlantı kopması bildirimi (bkz. 8).
- Bağlanınca PS5'e 2 dakikada bir çalışan oyun sorulur (yalnız PS5; havuza giden satırlar oyunla gitsin diye).
  Bağlantı gidince sorgu durur ve oyun "bilinmiyor" olur.
- Her kopmada okuma hattı ve bütün yan okuyucular sıfırlanır, TV'ye `clear` gider.

### 3.5 "Son neden" kuralı

Ana ekran yeniden denenirken de nedeni gösterebilsin diye son kopma nedeni tutulur:

| Yeni durum | Son neden |
|---|---|
| `streaming` | Silinir |
| `connecting` | Değişmez |
| `disconnected(stopped)` | Değişmez |
| `disconnected(other)` | PS5'te değişmez; Xbox'ta bu neden olur (Xbox kendi metnini verir) |
| Başka `disconnected(...)` | Bu neden olur |

Durdurulduktan sonra geç gelen durum değişikliği nedeni geri getirmez (yalnız çalışırken güncellenir).

---

## 4. PS5 bağlantısının durumları

### 4.1 Oturumun kendi davranışı (Remote Play katmanı)

- **Bağlanma:** kayıtlı adres kullanılabilirse oraya 2 sn'lik arama; adres yoksa ya da yanıt yoksa (en çok 30 sn'de
  bir) bütün ağda 3 sn arama. Tek PS5 bulunursa ya da adı tek eşleşen bulunursa adres güncellenir ve model kaydı
  (`console`) yenilenir.
- **Uyandırma:** PS5 dinlenmedeyse uyandırma gönderilir, 2 sn'de bir bakılarak en çok 20 sn beklenir; uyanmazsa
  `consoleAsleep` ile yeniden deneme.
- **Yeniden deneme aralığı:** 2, 4, 8, 16, sonra hep 30 sn. `inUse` nedeninde en az 8'den başlar. Aralık, oturum en az
  60 sn bağlı kaldıktan sonra kapanırsa baştan başlar (kısa süren bağlantılar aralığı büyütmeye devam eder).
  `reconnectNow` aralığı sıfırlar ve hemen bağlanır.
- **Görüntü bekçisi:** bağlıyken 8 sn hiç kare gelmezse oturum kapatılıp yeniden kurulur. Art arda 3 oturumda hiç
  kare gelmezse vazgeçilir: `noPicture`.
- **Giriş şifresi:** PS5 isterse kayıtlı 4 hane bir kez gönderilir. Şifre yoksa `loginPasscode`, PS5 kabul etmezse
  `loginPasscodeIncorrect`.
- **Kalıcı nedenler** (yeniden denenmez, oturum kendini durdurur): `registrationInvalid` (PS5 kodları 0x80108b09,
  0x80108b02, 0x80108b26), `remotePlayDisabled` (0x80108b12), `noPicture`, `loginPasscode`, `loginPasscodeIncorrect`.
  **Dikkat:** bu durumda model "çalışıyor" kalır ve nedeni gösterir; ön plana dönüşteki yeniden bağlanma da işe yaramaz
  (oturum durmuştur). Kullanıcı durdurup yeniden başlatmalıdır.
- Ağ hatası olup PS5 aramaya da yanıt vermediyse neden `notFound(adres)` olur (adres kullanılabilirse; değilse
  `network`).
- PS5'in tanımadığı oturum reddi: günlükteki "Reported Application Reason" kodu varsa `rejected(kod)`, yoksa
  `rejected(nil)`.

### 4.2 Kullanıcıya gösterilen metinler

PS5 durum satırı: bağlıysa `status.connected`, bağlanıyorsa `status.connecting`, kopuksa: çeviri sürmüyorsa
`status.disconnected`; sürüyorsa nedenin metni, metni yoksa `status.reconnecting`.

Ana ekrandaki sorun satırı yalnız şu durumda dolu: çeviri sürüyor, demo değil, akış yok ve son neden biliniyor (o
nedenin metni). Aksi hâlde boş (`status.connecting` görünür).

| Neden | Metin anahtarı |
|---|---|
| (bağlı) | `status.connected` |
| (bağlanıyor) | `status.connecting` |
| (çeviri kapalı) | `status.disconnected` |
| metni olmayan | `status.reconnecting` |
| `consoleAsleep` | `ps5.turnon` |
| `inUse` | `session.error.inuse` |
| `refused` | `session.error.refused` |
| `loginPasscode` | `ps5.reason.passcode` |
| `loginPasscodeIncorrect` | `ps5.reason.passcodeWrong` |
| `registrationInvalid` | anahtarı yok: PS5'in eşlemeyi kabul etmediğini, PS5'i ikinci hesapla yeniden eşlemesini söyleyen kısa not |
| `remotePlayDisabled` | anahtarı yok: PS5'te Remote Play'in kapalı olduğunu, PS5 ayarlarından açıp yeniden başlatmasını söyleyen kısa not |
| `noPicture` | `session.error.nopicture` |
| `notFound(adres)` | `session.error.notatip` (adres metne konur) |
| `network` | `session.error.unreachable` |
| `rejected(kod)` | `session.error.rejected` (kod metne konur) |
| `rejected(nil)` | `session.error.notstarted` |
| `other(metin)` | PS5'te metin yok (`status.reconnecting`); Xbox'ta gelen metin olduğu gibi |
| `stopped` | Metin yok |

`rejected` kodu `0x` + 8 küçük onaltılık haneyle yazılır (ör. `0x80108bff`). Cihaz bilgisi kartında (Sorun Bildir)
adres ya da serbest metin taşıyan nedenler sabit metne çevrilir: `notFound`/`network` → `session.error.unreachable`,
`other`/`stopped` → `status.reconnecting`, `rejected(kod)` → yalnız kod.

TV durum satırı: TV uygulaması bağlıysa `status.connected`, değilse TV uygulamasını beklediğini söyleyen kısa bir durum
metni (yeni katalogda anahtarı yok).

---

## 5. TV'ye gönderim

Eski uygulamada **telefon sunucudur**, TV istemcidir.

- Sunucu: telefonda HTTP, port **8787** (TCP canlılık denetimi açık: 10 sn boşta, 5 sn aralık, 3 deneme; Nagle
  kapalı). 8787 açılamazsa rastgele bir porta düşülür. **Tuzak:** Android TV uygulaması telefonu ağda 8787'yi tarayarak
  bulur (aşağıda); rastgele porta düşülürse Android TV bulamaz. LG ve Samsung'da adres `server` parametresiyle
  verildiği için sorun olmaz.
- Uç noktalar:

| İstek | Yanıt |
|---|---|
| `GET /events` | Server-Sent Events akışı. `?model=…` TV'nin marka/modelini bildirir (harf, rakam, boşluk ve `.-_()` dışı atılır, en çok 60 karakter); `?viewer=obs` izleyicidir, TV sayılmaz |
| `GET /hello` | `{"app":"nino"}` (TV uygulaması ağdaki telefonu bununla tanır) |
| `GET /obs` | OBS katmanı sayfası |
| `OPTIONS *` | 204 |
| Diğer | 404 |

  Bütün yanıtlarda `Access-Control-Allow-Origin: *`.
- Akış açılınca önce `retry: 2000`, sonra (varsa) son stil, sonra (çeviri son 20 sn içinde başladıysa ve izleyici
  değilse) `started` gönderilir.
- Olay biçimi: `event: <ad>\ndata: <sıralı anahtarlı JSON>\n\n`. 15 sn'de bir canlı tutma: `: ping` yorum satırı ve
  `event: ping` / `data: {}`.
- Olaylar:

| Olay | Gövde |
|---|---|
| `style` | Stil alanları (bkz. `kalicilik.md` 4.3; `background` 0–100'e sıkıştırılır) |
| `subtitle` | `text`, `duration` (ms), `at` (Unix ms), isteğe bağlı `box` {left, top, right, bottom; 4 ondalık}, `replace: true`, `light` (0–1), `cover` (base64 JPEG) |
| `clear` | `{}` |
| `screen` | `duration`, `items` [{box, line, text, isteğe bağlı paragraphs, plain, italic, fill, ink, angle, alpha, side, frost, backdrop, card}], isteğe bağlı `overlay: true` (köşe/telefon/harita çevirileri; o anki altyazıyı silmez) |
| `screen-clear` | `{}` |
| `region` | `id`, `text` (boşsa kutu kalkar), isteğe bağlı `box`, `line` |
| `region-clear` | `{}` |
| `started` / `stopped` | `{}` |

- "Altyazı TV'ye gitsin mi" (`output` TV'yi kapsıyor mu) kapalıyken altyazı olayları (`subtitle`, `clear`, `screen`,
  `screen-clear`, `style`, `region`, `region-clear`) TV'lere gitmez; öbürleri gider. Gönderimde hata veren bağlantı
  düşürülür. Bağlı TV sayısı değişince model bilgilendirilir (izleyiciler sayılmaz).
- Sunucuya giden her `subtitle`/`clear`/`screen`/`region` olayı aynı anda telefonun kendi ekranına da verilir (bkz. 7).
- **TV'nin telefonu bulması:** TV uygulaması önce kendisine verilen adresi dener; art arda yanıt alamazsa kendi /24
  ağını (ve kayıtlı adresin ağını) 1–254 arası `http://x.y.z.N:8787/hello` diye tarar; yanıtında `nino` geçen ilk adres
  telefondur.
- **TV açık tutucu (LG/Samsung):** 5 sn'de bir bakar. TV kendi girişine geçtiyse (HDMI/yayın ekranı) TV uygulamasını
  yeniden öne getirir; kullanıcının bilerek açtığı uygulamalara dokunmaz. Samsung'da yalnız TV uygulaması telefona bağlı
  değilken ve en çok 30 sn'de bir dokunur (sürekli bağlantı TV'de bildirim çıkarıp PS5 kolunu düşürüyordu). TV yeni
  adreste bulunursa `tv` güncellenir; Samsung yeni jeton verirse `tvKey` güncellenir. Android TV'de açık tutucu yoktur.
- Deneme altyazısı (`tv.test.send`): sunucu başlatılır, stil ve 8 sn'lik `tv.test.text` satırı (arayüz dilinde)
  gönderilir.

---

## 6. Okuma ve çeviri hattı (özet)

- Her kare gelince: önizleme karesi güncellenir; oyun tanıma gerekiyorsa denenir; ek alanlar (açık olanlar, en çok
  3) ayrı ve seyrek okunur; köşe/ipucu ve oyundaki telefon/harita okuyucuları ayrı okunur ("ekranı çevir" sürmüyorsa).
- Ana altyazı okumasına aynı anda tek kare girer; önceki okuma sürüyorsa kare atlanır. Bir okuma uzun süre bitmezse
  ("takıldı") okuma hattı yeniden kurulur.
- Okuma hattı şu değişikliklerde yeniden kurulur (çeviri sürüyorsa): çevrimiçi çeviri aç/kapa, hedef dil, motor, bulut
  modelleri, hızlı algılama, köşe çevirisi; çeviri anahtarı kaydedilince seçili motorsa.
- Çeviri sırası:
  1. Oyun paketi: yalnız `gamePacks` açık ve İngilizce→Türkçe ise; kapatılan paketten gelen eşleşme sayılmaz.
     Havuz öncelikli oyunda (GTA 6) paketlere bakılmaz.
  2. Çeviri havuzunun hazır çevirisi: `sharePool` açık ve kaynak İngilizce ise (havuz öncelikli oyunda ortak havuz
     kapalı olsa da).
  3. Havuz öncelikli oyun: sunucuya sorulur (en çok ~1,5 sn), gelmezse ücretsiz cihaz çevirisi; kullanıcının anahtarlı
     motoru çağrılmaz.
  4. Seçili motor: çevrimiçi çeviri etkinse (aşağıdaki koşul) DeepL ya da yapay zekâ (oyunun adı bağlam olarak gider),
     değilse Apple'ın cihaz üstü çevirisi. Hepsinin önbelleği var (bkz. `kalicilik.md`).
- Çevrimiçi çeviri etkin: `onlineTranslation` açık **ve** kaynak İngilizce **ve** hedef dil listede **ve** (motor DeepL
  değil ya da DeepL bu dili destekliyor) **ve** o motorun anahtarı kayıtlı.
- Pakette bulunmayan İngilizce satır ortak havuza önerilir; havuz açıksa sunucu o an çevirir, satır hâlâ ekrandaysa
  cihazın çevirisinin yerine konur.
- Zaten hedef dilde olan satır (PS5 menüsü) çevirmene gitmez.
- Anahtar kaydetme: önce denenir. Yapay zekâda başarı, kota aşımı ya da model reddi "kabul"; DeepL'de geçerli ya da
  kota aşımı "kabul". Kabulse Anahtar Zinciri'ne yazılır ve motor seçilir. Anahtar silinince o motor seçiliyse
  çevrimiçi çeviri kapanır.
- "Ekranı çevir": çeviri sürerken bütün kare bir kez okunur, yazı grupları çevrilip yazının yerinde gösterilir; ikinci
  dokunuş kaldırır. Metinler:

Yeni katalogda bu özelliğin metinleri yok; gerekirse şu anlamlarda kısa metinler eklenir:

| Durum | Anlamı |
|---|---|
| Kare yok | PS5'ten henüz görüntü gelmediği için ekran yakalanamadı |
| Sürüyor | ekran çevriliyor (bekleme metni) |
| Yazı yok | ekranda okunacak yazı çıkmadı |
| Hata kalıbı | ekran çevrilemedi + hatanın kendisi (`%@`) |
| Dakika sınırı | motor (`%@`) dakikalık sınıra takıldı, biraz sonra yeniden denensin |
| İndirilmemiş | Apple'ın ücretsiz çevirisi henüz indirilmemiş |
| Desteklenmiyor | ücretsiz çeviri bu cihazda çalışmıyor (dil desteği için `translate.error.unsupportedlang`) |
| Diğer | genel bir hata, yeniden denensin |

- Hedef dil değişince: telefondaki satırlar, son satırlar listesi ve son satır silinir; çeviri sürüyorsa TV'ye `clear`.

---

## 7. Telefon ekranındaki altyazı ve yığın kuralları

Telefon ekranında yalnız `output` telefonu kapsıyorsa (`computer`) gösterilir. Sunucuya giden olaylar telefona da
gelir; satırlar TV uygulamasıyla **aynı yığın kurallarıyla** gösterilir:

- En çok 3 satır: en altta son satır (`current`, tam boy), üstünde önceki (`previous`, küçük ve soluk), en üstte iki
  önceki (`older`).
- Yeni satır, önceki satır **1,5 sn içinde** gösterilmişse, ikisi de çok satırlı (paragraf) değilse ve aynı cümle
  değilse önceki üste çıkar. Üstte hâlâ tam görünen (solmaya başlamamış) bir satır varsa o da en üste kayar.
- Yeni satır yığılmıyorsa (geç geldi, paragraf, aynı cümle ya da yığma kapalı) üstteki iki satır da hemen kalkar.
- Üste itilen satırların 1,5 sn'lik tam görünme süresi itildikleri andan başlar.
- `replace` işaretli satır öncekinin yerine geçer, üste yığılmaz (üstteki eski satırlar kalır).
- Ayarlardaki önceki satırları bırakma tercihi (`settings.stack.lines`, `stackPrevious`) kapalıysa yığılma olmaz.
- Üstteki satır 1,5 sn tam görünür, sonra 0,4 sn solarak kalkar.
- Son satırın süresi: bildirilen süre > 0 ise en az 1,2 sn olmak üzere o süre; değilse `2 + 0,06 × karakter sayısı`
  saniye, en çok 8 sn.
- `clear` gelince: satır okunacak kadar (`2 + 0,06 × uzunluk`, en çok 5 sn) görünmüşse hemen kalkar, görünmemişse o
  süre dolunca kalkar.
- Son satır kalkınca üsttekiler de kalkar. Çeviri durunca her şey hemen kalkar.
- "Aynı cümle": küçük harfe çevrilip noktalama (Arapça virgül, soru işareti, noktalı virgül dahil) atıldıktan sonra
  boşluklar yok sayılarak eşitse ya da biri ötekini içeriyorsa. Tek sözcüklü satır ancak ötekinde tam sözcük olarak
  geçerse aynıdır ("No!" ≠ "Not now!").
- Uzun satır görünümde en çok 3 satıra dengeli bölünür; paragraf yazıları olduğu gibi kalır.
- Model bir sonraki değişim anına (solma ya da kalkma) zamanlayıcı kurar ve o an görünümü yeniler.
- Ek alan çevirileri (`region`) telefon ekranında da kendi yerlerinde küçük kutularda gösterilir; boş metin kutuyu
  kaldırır. Köşe/ipucu/mesaj çevirileri telefonda yazının yerinde yarı saydam görünür (altyazı TV'deyken boştur).
  Oyundaki telefonun yanındaki panel ve harita kartı yalnız TV'dedir.

---

## 8. Bildirimler

- Tek yerel bildirim: PS5 bağlantısının kopması (`notify.ps5.lost`).
  - İzin, çeviri başlarken bağlantı bildirimi tercihi (`settings.notify.drop`, `notifyDisconnect`, varsayılan açık) açıksa istenir (uyarı + ses).
  - Akış sürerken kendiliğinden kopulunca (kullanıcı durdurmadı, neden `stopped` değil) ve tercih açıksa gönderilir;
    **uygulama ön plandaysa gönderilmez**.
  - Kimlik hep `connection-lost`: art arda kopmalarda biriken değil, son bildirim kalır. Hemen (tetikleyicisiz) gösterilir.

| | Metin anahtarı |
|---|---|
| Başlık | `notify.ps5.lost` |
| Gövde | `notify.stopped` |

- Profil'deki yeni paket bildirimi tercihi (`notifyPackUpdates`) saklanır ama hiçbir yerde kullanılmaz; paket
  bildirimi yoktur.

---

## 9. Arayüz dili ve hedef diller

Hedef diller (kod, kendi adı) bu sırayla: `tr` Türkçe, `ar` العربية, `hi` हिन्दी, `id` Bahasa Indonesia, `th` ไทย,
`vi` Tiếng Việt, `ur` اردو, `bn` বাংলা, `ms` Bahasa Melayu, `tl` Filipino, `nl` Nederlands. Varsayılan Türkçe.
Filipince Fince ile karışmasın diye `tl` koduyla tutulur.

- İlk açılışta (kayıtlı ayar yoksa) hedef dil: sistemin ilk tercih dili listedeyse o (`fil…` → `tl`), değilse `tr`.
- DeepL'in desteklediği hedefler: `tr`, `ar`, `id`, `th`, `vi`, `nl`.
- Oyun paketleri, sözlük ve Türkçe düzeltmeler yalnız Türkçe hedefte.
- **Arayüz dili hedef dili izler** (her dilin arayüz çevirisi var): hedef listedeyse arayüz o dilde (`tl` için Apple
  kodu `fil`), değilse İngilizce.
  - Açılışta, metinler okunmadan önce ve hedef dil her değiştiğinde UserDefaults `AppleLanguages` = [o dil] yazılır
    (eski ekranlar bir sonraki açılışta o dilde açılsın diye).
  - Görünüm ağacına o dilin yerel ayarı ve yazı yönü anında verilir: `ar`, `ur` (ve `fa`, `he`) sağdan sola.
  - Not: uygulama dosyasındaki bir açıklama "arayüz yalnız Türkçe ya da Arapça" der; kod bütün listeyi destekler.
    Doğrusu kod.
- Arayüz her zaman açık renk temadadır (`appearance` ayarı iOS'ta kullanılmaz).

---

## 10. Sağlık izleme ve otomatik sorun bildirimi

- Ağ türü sürekli izlenir (Wi-Fi / kablolu / diğer / yok); izin istemez.
- Çeviri sürerken ve uygulama ön plandayken kaydedilen sorunlar:
  - Akış sürerken PS5 koptu → `ps5Dropped` (neden adıyla, adres olmadan).
  - PS5 kopuk ve 180 sn içinde geri gelmedi → `ps5Unreachable` ve hemen otomatik bildirim.
  - TV bağlıyken koptu (TV'ye gönderim açıkken) ve 20 sn içinde geri gelmedi → `tvDropped`.
  - Ağ gitti → `networkLost`.
- Oturum bitince: bu oturumda sorun kaydı olduysa ya da görüntü/çeviri sağlığı "sorunlu" ise otomatik bildirim.
- Otomatik bildirim yalnız `autoReport` açıkken, oturumda en çok bir kez, günde en çok 3 kez gider; içeriği özet ve
  cihaz bilgisidir (sürüm, model, TV markası/TV uygulaması sürümü, konsol türü, durum, oyun). Konsolun/TV'nin adı,
  hesap adı, IP adresi ve altyazı metni gitmez. Gönderilemeyen bildirim saklanır, sonraki ilk oturumda yeniden denenir.
- Sorun kaydı son 3 günün olaylarıyla Sorun Bildir (`report.title`) metnine eklenir.

---

## 11. Demo ve hata ayıklama kipleri

**Demo (`demo.try`)** gerçek sürümde de vardır: gerçek oturum yoksa açılır; ağa ve PS5'e dokunmaz; ekran açık
tutulur. 0,7 sn bekler, sonra sırayla örnek satırları 2,8 sn gösterir, 0,6 sn boşluk bırakır (hedef dile göre örnekler).
Gerçek çeviri başlatılınca demo kapanır.

Yalnız hata ayıklama derlemesinde (ortam değişkenleriyle):

| Değişken | Ne yapar |
|---|---|
| `NINO_DEMO=1` | Kurulum bitmiş gibi açılır: bellekte depo (Anahtar Zinciri'ne dokunmaz) içine uydurma `accountId`, PS5 (`192.168.1.103`, `PS5-002`), LG TV (`Salon TV`, `192.168.1.50`), `tvKey` ve `setupComplete` konur. UserDefaults gerçek olanıdır (ayarlar okunur/yazılır) |
| `NINO_TEST_FRAME=<png>[,<png>…]` | PS5'siz deneme karesi. Bellekte depo + her açılışta silinen ayrı UserDefaults takımı (`nino-test-frame`); karşılama atlanır; geçmiş okunmaz/yazılmaz; günlük, havuz, sorun kaydı kapalı; sunucu başlatılmaz, ağa çıkılmaz. Altyazı telefona alınır, kareler saniyede ~3 kez okuma hattına verilir, birden çok görüntüde 2,4 sn'de bir sıradakine geçilir; çeviri sabit, sahte bir çevirmenden gelir (bilmediği yazıyı aynen döndürür) |
| `NINO_FAKE_PROBLEM=1` | PS5'siz "bağlanılamıyor" görünümü: çalışıyor, durum bağlanıyor, son neden `rejected(0x80108bff)` |
| `NINO_START_DEMO=1` | Demo ana ekran açılınca başlar |
| `NINO_FULLSCREEN=1` | Demo başlar ve tam ekran altyazı açılır |
| `NINO_WELCOME_PAGE`, `NINO_FAKE_OLD_IOS` | Karşılama sayfası seçimi ve eski iOS görünümü denemesi (arayüz) |
| `NINO_POOL_URL` | Havuz sunucusunun adresi (hata ayıklamaya özgü değil, her derlemede okunur) |

---

## 12. Ekranın açık kalması

- İki neden vardır: çeviri (demo dahil) ve TV kurulumu. Biri bittiğinde öbürü sürüyorsa ekran açık kalır.
- Bir neden eklenince iOS'un "boşta kilitleme" bayrağı kapatılıp açılarak zorla yeniden uygulanır; neden varken 20 sn'de
  bir ve uygulama her ön plana geldiğinde yeniden uygulanır (iOS bayrağı kendiliğinden sıfırlayabiliyor). Neden
  kalmayınca bayrak kalkar ve zamanlayıcı durur.

---

## 13. Geçmiş

- Okuma hattı her çeviri çiftini verdiğinde geçmişe eklenir (paketten mi motordan mı geldiği ile).
- Yeni satırın kaynağı en son kaydınkine benziyorsa yeni kayıt açılmaz, son kayıt güncellenir (kimliği aynı kalır).
- Çeviri boşsa eklenmez; metinler 500 karakterde kesilir; en çok 200 kayıt, en yenisi başta.
- Her değişiklikte dosyaya arka planda yazılır. Temizleme (`common.clear`) hepsini siler ve yazar.
- Ayrıca bu oturumun son 30 satırı (bellekte) ve oturum sayaçları (kaç satırın hazır çeviriden geldiği / toplam) tutulur.

---

## 14. Oyun paketleri

- Kaynak sırası: uygulamayla gelen < sunucudan inen < içe aktarılan (aynı kimlik öncekinin yerine geçer).
- İndirme (paket sunucusu adresi varsa): açılışta hemen (zorla), sonra uygulama açık kaldıkça 24 saatte bir; PS5'te
  yeni oyun tanınınca son bakış 10 dakikadan eskiyse hemen. `GET v1/packs` liste; eksik ya da SHA-256'sı değişen paket
  `GET v1/packs/<kimlik>` ile iner ve doğrulanır (tutmazsa yazılmaz, hata); listede olmayan yerel paket silinir.
  İndirilen paket varsa okuma hattı ve paket listesi yenilenir.
- Durum metinleri:

Yeni katalogda anahtarı yok; anlamları:

| Durum | Anlamı |
|---|---|
| Ağ yok | internet yok, telefondaki paketlerle devam ediliyor |
| Diğer hata | paketler güncellenemedi, telefondaki paketlerle devam ediliyor |

- Paketler ekranında karoya dokunmak paketi kapatır/açar (`disabledPacks`); okuma hattı hemen yeni listeyle eşleşir.
- Son satırı veren paketin başlığı şu an oynanan oyun olarak gösterilir (`home.nowplaying`); çeviri durunca silinir.

---

## 15. Ortak havuz

- `sharePool` (varsayılan açık) ve kaynak İngilizceyken pakette bulunmayan İngilizce satırlar anonim olarak (rastgele
  kuruluş kimliği, oturum kimliği, oyun adı) havuz sunucusuna toplu gönderilir (`v1/batches`, 200'lük parçalar, hatada
  30 sn'den 1 saate kadar artan bekleme). Kapatılınca kuyruk silinir.
- Çeviri havuzu: oyun başlarken ve dakikada bir o oyunun hazır çevirileri iner (`v1/translations`), sunucu ayarı
  okunur (`v1/config`; havuz öncelikli oyunlar, diller, bekleme süresi), canlılık bildirilir (`v1/ping`).
  Havuz öncelikli oyun varsayılanı GTA 6, varsayılan dil yalnız Türkçe.
- Oyun tanıma: oyun bilinmiyorsa başlangıçtan ~8 sn sonra, olmazsa dakikada bir, en çok 6 kez küçük bir JPEG kare
  sunucuya gönderilip (`v1/identify`) oyunun adı sorulur; ekrandan tanınan oyun 5 dk sonra bir kez, sonra 20 dk'da bir
  (en çok 12 kez) yeniden doğrulanır. PS5'in bildirdiği ya da kullanıcının seçtiği oyun her zaman önce gelir.
  Yalnız `sharePool` açık ve kaynak İngilizceyken.
- Oyun paketle tanınmazsa ve `askGame` + `sharePool` açıksa çeviri başladıktan iki dakika sonra bir kez oyun sorulur;
  seçilen oyun o konsol için hatırlanır (`lastGames`; anahtar PS5'in adı, adı yoksa adresi; Xbox'ta Xbox'ın adı, adı
  yoksa `Xbox`).
- Arka plana geçerken bekleyen kuyruk hemen gönderilir.

---

## 16. Toplam indirme sayacı

- Ana ekranda TV'nin köşesinde gösterilen sayı. Havuz sunucusunun `GET /v1/config` yanıtındaki `downloads` alanından
  (pozitif tam sayı) okunur; en çok 10 dakikada bir sorulur, 10 sn zaman aşımı, önbellek kullanılmaz, yalnız 200 yanıtı
  kabul.
- Alınan sayı `ninoDownloadTotal`'a yazılır; alınamazsa son bilinen sayı kalır; hiç alınmadıysa sayaç görünmez.
  İstek kullanıcıya ait bilgi taşımaz; sayıya ekleme yapılmaz.

---

## 17. Ölçüm

Uygulama hiçbir ölçüm göndermez. Model ölçüm olayları üretir (`session_start`, `session_stop`, `pack_hit`,
`tv_connected`, `packs_updated`) ama bunları alan tek uygulama boş olandır. Yeni uygulamada bu katman hiç olmayabilir.
