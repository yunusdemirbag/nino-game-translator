# Windows: kimlikler, veri, açılış, güncelleme, güvenlik duvarı

Bu belge yeni Windows uygulaması için bir **tarif**tir: eski Windows uygulamasının kendini nasıl tanıttığı (exe adı,
paket kimliği, sürüm), verisini nereye ve hangi biçimde yazdığı, nasıl açıldığı, nasıl güncellendiği ve Windows
güvenlik duvarıyla (Windows Firewall) ne yaptığı. Kod yok. Ayar dosyasının alan alan anlatımı ayrı belgede: `ayarlar-modeli.md`.

Genel kural: **kimlikler eskisiyle birebir aynı kalır** (exe adı, Velopack paket kimliği, veri klasörü, dosya adları,
JSON alan adları). Değişirse kurulu kullanıcılar güncellemeyi alamaz, ayarlarını ve girişlerini kaybeder, güvenlik
duvarı izni yeniden sorulur. Okurken hoşgörülü, yazarken eski biçime sadık ol.

Mac karşılığı: `git show claude/yeni-mac-c9961f:docs/yeni/mac/veri-uyumu.md`. Biçimleri aynı olan dosyalarda
"Mac veri-uyumu §x ile aynı" denir; Windows'a özgü her şey burada yazılıdır.

---

## 1. Uygulamanın kimliği

| Ne | Değer | Not |
|---|---|---|
| Çalıştırılabilir dosya | `Nino.exe` | Derleme adı `Nino`. **Değişmez**: Velopack, güvenlik duvarı kuralı ve kısayollar bu ada ve yola bağlı |
| Dosya özelliklerinde başlık / ürün / şirket | `Nino` / `Nino` / `Nino` | Görev Yöneticisi ve güvenlik duvarı sorusu bunları gösterir |
| Telif satırı (dosya özellikleri) | "AGPL-3.0. Uses chiaki-ng (AGPL-3.0)." | Telif bildirimi ayrıca NOTICE ve Hakkında'da |
| Simge | `Assets\Nino.ico` (exe simgesi ve pencere simgesi) | |
| Hedef | .NET 10, Windows SDK 10.0.22621 ile derlenir, **en düşük Windows 10.0.19041** | 22621 yalnız sarı yakalama çerçevesini kapatma API'si için; yeni API'ler çalışırken var mı diye denetlenir |
| Mimari | yalnız `win-x64`, kendi içinde (.NET çalışma zamanı uygulamayla gelir) | |
| Arayüz | WPF | Giriş noktası özel bir başlangıç yöntemi (Velopack kancaları WPF'ten önce çalışmalı, §3) |
| Sürüm | Derlemede verilir (`Version` = etiketten `v` atılmış hali, ör. `0.1.0-beta.10`, `4.0.6`); verilmezse 0.1.0 | Uygulama içi sürüm: bilgi sürümünün `+` öncesi (ör. `4.0.6+abc123` → `4.0.6`); okunamazsa `0.0.0`. Etiketsiz CI derlemesinde sürüm Mac'in `mac/project.yml`'deki pazarlama sürümünden alınır |
| Paket sunucusu adresi | Derleme özniteliği `NinoPacksUrl` (derlemede verilir; boşsa paket indirme kapalı) | Bugün verilmiyor: paket indirme kapalı |
| GitHub deposu | `https://github.com/yunusdemirbag/nino-game-translator` | Güncelleme, sürüm sayfası, sorun bildirme sayfası (`…/issues`) |

### 1.1 Çözüm ve paket sürümleri (yeni NuGet paketi eklenmez; bunlar kullanılabilir)

| Katman | Paketler |
|---|---|
| Uygulama (WPF) | System.Security.Cryptography.ProtectedData 10.0.0, Microsoft.Web.WebView2 1.0.3537.50, Velopack 1.2.161 |
| Çekirdek | SSH.NET 2026.0.0 (LG geliştirici modu) |
| Çeviri | Microsoft.ML.OnnxRuntime 1.31.1, Microsoft.ML.Tokenizers 2.0.1 |
| TV kurulumu | TizenSdb.Core 1.1.9 |
| Testler (5 proje, hepsi net10.0) | Microsoft.NET.Test.Sdk 17.14.1, xunit 2.9.3, xunit.runner.visualstudio 3.1.4, coverlet.collector 6.0.4 |

Ortak derleme ayarları: en son dil sürümü, null denetimi açık, örtük `using`'ler açık, WPF projesinin Mac'te de
derlenebilmesi için Windows hedeflemesi açık. TV kurulum yardımcısı (`nino-tv-helper`, Mac'e gömülür) Native AOT, sabit
kültür, kısmi kırpma; XML imza ve TizenSdb derlemeleri kırpılmaz.

### 1.2 Uygulamanın yanına konan dosyalar (yayın klasörü)

| Klasör / dosya | İçerik | Kim kullanır |
|---|---|---|
| `Nino.exe`, `Nino.dll`, öbür DLL'ler, `Nino.deps.json` | Uygulama | `Nino.deps.json` açılışta eksik DLL denetimi için okunur (§3.3) |
| `nino_native.dll` | Remote Play köprüsü (libchiaki + FFmpeg) | CI'da derlenir; yalnız Windows'un kendi DLL'lerine bağlı olmalı |
| `tv-app\*.ipk`, `tv-app\*.wgt`, `tv-app\*.apk` | LG, Samsung, Android TV uygulama paketleri | TV kurulumu; LG için ilk `*.ipk`, Samsung için `*.wgt`, Android TV için `*.apk` |
| `xbox-bridge\bridge.cjs`, `player.html`, `player.js`, `node.exe` (varsa), `licenses\*` | Xbox yayın köprüsü | Xbox tarifinde |
| `ct2\` | Gömülü Python 3.12 + CTranslate2 + `worker.py` | Türkçe ücretsiz çeviri (çeviri tarifinde) |
| `onnxruntime.dll`, `onnxruntime_providers_shared.dll` | ONNX Runtime | Türkçe dışı ücretsiz diller |
| `vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll`, `msvcp140_1.dll` (+ `ct2\` içinde de) | Visual C++ çalışma zamanı, uygulamanın yanına dağıtım (en az 14.40) | Yönetici izni istemeden kurulabilsin |
| `Fonts\OFL-*.txt` | Altyazı yazı tiplerinin lisansı | Yazı tipleri (Barlow, Barlow Condensed = "NinoAction", Nunito; Bold ve SemiBold) uygulamanın içine gömülü |
| `LICENSE`, `THIRD-PARTY-NOTICES.md` | Lisanslar | Velopack paketine ve zip'e konur |

Uygulamanın içine (WPF kaynağı) gömülü görseller: `logo.png`, `living-room.png`, `living-room-xbox.png` (Mac'in
görseliyle aynı dosya), `Nino.ico`, Nino'ya Sor robotunun iki karesi (`nino-bot-256.png`, `nino-bot-blink-256.png`).
Yeni uygulama bunları kendi `Resources/` klasöründe tutar (eski klasörlere bağlantı yok).

---

## 2. Kurulum ve paket (Velopack)

| Ne | Değer |
|---|---|
| Velopack paket kimliği | **`NinoGameTranslator`** |
| Paket başlığı | "Nino Game Translator" (Başlat menüsü / masaüstü kısayolunun ve Programlar listesinin adı) |
| Paket yazarı | "Yunus Demirbag" |
| Ana exe | `Nino.exe` |
| Gerekli bileşen | WebView2 (PlayStation giriş penceresi ister; eksikse kurulum kurar) |
| Kanal | Velopack'in Windows varsayılanı `win` (dosya adlarında görünür) |
| Kurulum dosyası | Velopack `NinoGameTranslator-win-Setup.exe` üretir, yayında adı **`Nino-Windows-Setup.exe`** |
| Güncelleme dosyaları | `NinoGameTranslator-<sürüm>-full.nupkg`, varsa önceki sürüme göre delta paketi, `RELEASES`, `releases.win.json`, `assets.win.json`. "Portable" zip yayına konmaz |
| Zip dağıtımı | `Nino-windows-x64.zip` (yayın klasörünün tamamı + LICENSE + THIRD-PARTY-NOTICES). Zip'ten açılan kopya kendini güncelleyemez |
| Kurulum yeri | `%LOCALAPPDATA%\NinoGameTranslator\` : kökte `Update.exe` ve başlatıcı `Nino.exe`, uygulama `current\Nino.exe`, paketler `packages\` |
| Kısayollar | Velopack'in varsayılanı (masaüstü ve Başlat menüsü), başlatıcı `…\NinoGameTranslator\Nino.exe`'yi açar. Uygulama kısayol kodu yazmaz |
| Yönetici izni | Kurulum istemez (kullanıcı klasörü) |
| İmza | Windows paketi kod imzası taşımaz (CI'da imza adımı yok) |

Paketleme: önceki sürümün Velopack dosyaları GitHub'dan indirilir (yoksa yalnız tam paket), sonra paketlenir. Her CI
derlemesinde paketleme denenir. Sürümde, GitHub sürümüne `Nino-Windows-Setup.exe`, iki nupkg, `RELEASES`,
`releases.win.json`, `assets.win.json` yüklenir. **Her etikette bütün uygulamalar aynı numarayla** derlenip yüklenir:
zip kopyası "yeni sürüm var" kararını GitHub'daki son etiketin adına göre verir.

Başlatıcı ayrıntısı (veri klasörü kararında kullanılır): başlatıcının yolu = uygulama exe'sinin **iki üst** klasörü +
aynı dosya adı. Örnek: `…\NinoGameTranslator\current\Nino.exe` → `…\NinoGameTranslator\Nino.exe`. Yol boşsa ya da üst
klasör yoksa (ör. yalnız `Nino.exe`) başlatıcı yok.

---

## 3. Açılış

### 3.1 Sıra (giriş noktası)

1. Komut satırında **tek** argüman varsa ve `--configure-local-firewall` ise: arayüz açılmaz; güvenlik duvarı kuralları
   yazılır (§11.4), çıkış kodu başarıda 0, değilse 1; süreç biter. (Bu yol UAC ile yönetici olarak açılır; veri
   klasörüne dokunmaz, taşımaz.)
2. Velopack kancaları çalıştırılır. Kaldırma öncesi kancada: bu exe'nin yönettiği güvenlik duvarı kuralları sessizce
   silinir (§11.5). Kurulum/güncelleme/kaldırma çağrılarında süreç burada biter; normal açılışta hiçbir şey olmaz.
3. **Veri klasörü hazırlanır** (§5): veriye kullanan bütün adımlardan ve ilk günlük satırından evvel. Çekirdek DLL'i yüklenemezse
   hata verilmez, "Veri klasörü hazırlanamadı" günlüğe yazılır, açılış sürer (nedeni 3.3 gösterir). Taşıma hatası
   olduysa taşınamadığını ve bu açılışta eski klasörün kullanıldığını söyleyen satır (+ yol), kopyalandıysa eski klasörün
   başka bir uygulamayla paylaşıldığı için yerinde bırakıldığını, verinin yeni klasöre kopyalandığını ve modellerin
   kopyalanmayıp gerekince yeniden indirileceğini söyleyen satır (+ eski ad, yeni yol) `hata.log`'a yazılır.
4. WPF uygulaması kurulur; kapanma kuralı: ana pencere kapanınca uygulama kapanır. Ortak stiller yüklenir.
5. Başlangıçta (§3.2–3.4) eksik dosya denetimi, hata yakalayıcılar, denetleyici ve pencere.

### 3.2 Başlangıç argümanları

- `--render-screens <klasör>` (tam iki argüman): ekran görüntüsü kipi. Pencere açılmaz; bütün ekranlar açık ve koyu
  temada PNG'ye dökülür (dosya adları: `adim-<n>-<adım>-<tema>.png`, `ana-<tema>.png`, `pencere-<tema>.png`,
  `ayarlar-<tema>.png` (1000 genişlik), `hakkinda-<tema>.png` (460×640)). Hatalar pencere yerine klasördeki
  `errors.txt`'ye eklenir. CI en az 22 PNG bekler ve eksik DLL denetimini de bu kipte yapar. Bu kipte hata yakalayıcılar
  kurulmaz.
- Başka argüman yoktur.

### 3.3 Eksik DLL denetimi

Uygulama klasöründeki `Nino.deps.json` okunur; `targets` altındaki her kitaplığın `runtime` bölümündeki her dosyanın
**yalnız adı** alınır (büyük/küçük harf duyarsız, sıralı); klasörde olmayanlar "eksik"tir. Dosya yoksa ya da okunamazsa
eksik yok sayılır. Eksik varsa uygulama açılmaz: ileti gösterilir, `hata.log`'a yazılır, çıkış kodu **3**.
Bu denetim ve hata gösterimi yalnız .NET'in kendi türleriyle çalışmalı (uygulamanın öbür DLL'leri eksik olabilir).

Eksik dosya iletisi (Türkçe arayüzde Türkçe, değilse İngilizce): `app.error.missingFiles` + en çok 8 dosya madde
işaretiyle (fazlası `app.error.missingFilesMore`) + `app.error.missingFilesHelp` (anlamı: en sık neden antivirüs
karantinası; Windows Güvenliği › Virüs ve tehdit koruması › Koruma geçmişi'nden geri yükleme ya da
Nino-windows-x64.zip'i yeniden indirip tümünü ayıklama; programı zip'in içinden çalıştırmama).
CI denetimi: `Nino.RemotePlay.dll` silinince ileti bu adı içermeli.

Dil seçimi bu iletilerde: Windows arayüz dilinin iki harfi `tr` ise Türkçe, değilse İngilizce (12 dil burada yok).

### 3.4 Denetleyici ve pencere

1. Remote Play günlüğü başlatılır (§8), altyazı günlüğü açılır.
2. Arayüz dili sağdan solaysa (Arapça, Urduca) bütün pencerelerin yönü yüklenirken sağdan sola yapılır (ilk pencereden
   önce kayıt edilir).
3. Uygulama denetleyicisi kurulur: gerçek hizmetler, şifreli depo (§7), ayar dosyası (`ayarlar-modeli.md`), uyku
   engelleyici (§12.2), arayüz dili, arayüz iş parçacığına aktarma. Tarayıcıda açma işi §12.3'teki yöntemle verilir.
4. Görünüm ayarı (varsayılan "sistemle aynı") pencere açılmadan uygulanır; "sistemle aynı" seçiliyken Windows teması
   değişince kaynaklar yenilenir; ayar değişince anında uygulanır (§12.4).
5. Ana pencere kurulur ve gösterilir. Ana pencere: güç olaylarını dinler (uykudan uyanınca bağlantılar hemen yenilenir),
   pencere tutamağı hazır olunca genel kısayolları kurar (§12.1), bilgisayar ekranındaki altyazı penceresini bağlar
   (kurulamazsa günlüğe yazar ve metin anahtarı `overlay.error.message` iletisini gösterir, uygulama sürer). Kapanınca hepsi bırakılır, denetleyici kapatılır.
6. Ana ekran ilk açılışta güncelleme denetimini başlatır (§10).

Başlatırken herhangi bir hata: metin anahtarı `app.error.startup` + hata türü ve iletisi + rapor ipucu; günlüğe
yazılır, ileti gösterilir, çıkış kodu 3.

Rapor ipucu (her hata iletisinin sonu): `app.error.reportHint` (hata.log'un tam yolu ve bu dosyayla GitHub'da sorun bildirme önerisi) + alt satırda sorunlar sayfasının adresi (ileti kutusunda bağlantı
tıklanamaz, adres açıkça yazılır). İngilizcesi aynı anlam.

### 3.5 Açılıştan sonraki hatalar

- Arayüz iş parçacığındaki yakalanmamış hata: günlüğe yazılır, **uygulama kapanmaz** (yapılan iş, ör. az önce bitirilen
  PSN girişi kaybolmasın), ileti hatanın içinde değil sonra, arayüz boşalınca (arka plan önceliğiyle) gösterilir. Aynı
  anda tek ileti açık olur; aynı ileti 30 sn içinde yinelenirse yalnız günlüğe yazılır.
- Arka plan iş parçacığında süreci kapatan hata: günlüğe "(uygulama kapanıyor)" notuyla yazılır, hemen `app.error.crash` + hata + rapor ipucu iletisi gösterilir.
- Gözlenmemiş görev hatası: yalnız günlüğe yazılır, gözlenmiş sayılır.
- İleti gösterirken çıkan hata da yalnız günlüğe yazılır; günlüğe yazma hatası sessizce yutulur.

### 3.6 Tek kopya kilidi

**Yok.** Eski uygulama mutex, adlı olay ya da boru kullanmaz; ikinci bir Nino açılabilir. İkinci kopya TV sunucusu için
8787'yi alamazsa rastgele bir porta geçer (TV yanlış kopyaya bağlanabilir; TV bağlantısı tarifinde). Tek etkisi veri
klasörü taşımasındadır: aynı klasörden çalışan başka bir kopya açıksa taşıma ertelenir (§5.3). Yeni uygulama da kilit
eklememeli (geliştirici deneme kopyası açabilmeli) ya da eklerse yalnız aynı kurulum yolu için eklemeli.

---

## 4. Arayüz dili ve çeviri dili

- **Arayüz dili** Windows'un arayüz dilinden gelir, ayarlardan değil (Mac'te çeviri dili arayüzü de çeker; Windows'ta
  çekmez). Kural: kod küçük harfe çevrilir; `fil` ile başlıyorsa ya da `tl` ise `fil`; değilse ilk iki harf
  `tr, ar, hi, id, th, vi, ur, bn, ms, fil, nl` içindeyse o, değilse `en`. Örnek: `de` → `en`, `tr-TR` → `tr`,
  `fil-PH` → `fil`, `tl` → `fil`. Sağdan sola: `ar`, `ur`.
- Metin arama: anahtar katalogda yoksa anahtarın kendisi; varsa bu dildeki değer, yoksa İngilizce değer, o da yoksa
  anahtar. Büyük harfe çevirme arayüz dilinin kültürüyle yapılır (Türkçede i→İ: "Gizli dizin" → "GİZLİ DİZİN");
  kültür yoksa sabit kültürle.
- Biçim belirteçleri: `%@`, `%d`, `%lld`, `%1$@` gibi (uzunluk harfleri `l`, `h`, `q`, `z` atlanır; tür harfleri
  `@ d D i u U x X f g s`). Sıralı belirteçler 0'dan sayar; konumlu `%n$` belirteç n'inci değeri alır ve sayacı
  ilerletmez. `%%` → `%`. Tanınmayan belirteç olduğu gibi kalır. Eksik değer boş yazılır. Değerler o anki kültürle
  yazıya çevrilir. Örnek: `setup.stepCounter` (2, 6) → Türkçede "Adım 2 / 6"; "%1$@ x %2$@ %% %lld %@ %q" ("A","B") →
  "A x B % A B %q".
- **Çeviri dilleri** (kod, kendi adı; Türkçe hep ilk): `tr` Türkçe, `ar` العربية, `hi` हिन्दी, `id` Bahasa Indonesia,
  `th` ไทย, `vi` Tiếng Việt, `ur` اردو, `bn` বাংলা, `ms` Bahasa Melayu, `tl` Filipino, `nl` Nederlands (11 dil).
  Kod karşılaştırması ilk iki harf, küçük harf. İngilizce adlar (istemlerde): Arabic, Hindi, Indonesian, Thai,
  Vietnamese, Urdu, Bengali, Malay, Filipino, Dutch; öbür her şey Turkish. DeepL'in desteklediği hedefler:
  `tr, ar, id, th, vi, nl`. Listede olmayan kodun "kendi adı" kodun kendisi. `fi` desteklenmez.
- "Zaten hedef dilde" kuralı: hedef `ar` ya da `ur` ise ve yazıda Arap harfi varsa; hedef `th` (U+0E00–0E7F), `hi`
  (U+0900–097F), `bn` (U+0980–09FF) ise o yazının harfi varsa. Böyle satır çevirmene gönderilmez, olduğu gibi döner
  (hat onu göstermez). Türkçe hedefte Arapça satır da çevirmene gider. Arap harfi aralıkları: U+0620–064A, U+066E–06D3,
  U+06FA–06FF, U+0750–077F, U+08A0–08FF, U+FB50–FDFF, U+FE70–FEFF.
- Sağdan sola yazım: metinde Arap harfi bulunursa her paragrafın önüne (zaten yoksa) U+200F konur; iki kez uygulamak sonucu
  değiştirmez. Örnek: "TOMAS: أين الخريطة؟\nفيرا، انتظري" → her iki satırın başında U+200F.

---

## 5. Veri klasörü ve eski klasörden taşıma

### 5.1 Yer

`%LOCALAPPDATA%\Nino` (`Nino` adı sabit). Eski sürümler başka bir klasör adı kullanıyordu: o ad yalnız `LegacyNames`
dosyasında base64 kodlu durur (yeni uygulamada da öyle). Bütün yollar bu tek klasörün altındadır; yolu kuran tek bir
bileşen vardır. Kullanıcıya gösterilen yol biçimi: `%LOCALAPPDATA%\<kullanılan klasör adı>\<dosya>` (Dosya Gezgini'nin adres alanına girilebilir), ör. `%LOCALAPPDATA%\Nino\hata.log`; eski klasör kullanılıyorsa eski adla.

Windows dışında (Linux sunucusu, Mac'te koşan testler) hiçbir şey taşınmaz ya da oluşturulmaz ve klasör adı **eski ad**
olarak kalır (Linux uygulaması aynı klasörü kendisi kurar).

### 5.2 Karar zamanı

- Karar süreç başına **bir kez** verilir ve değişmez.
- Yalnız açılıştaki hazırlık çağrısı diske yazabilir (taşır, kopyalar, oluşturur). Hazırlık çağrılmadan biri yolu
  sorarsa (testler, araçlar) taşımasız karar verilir: önce yeni klasör, o yoksa ve eskisi duruyorsa eskisi, ikisi de yoksa
  yenisi (oluşturmadan).
- Hazırlıktan önce karar verilmişse hazırlık bir şey yapmaz.

### 5.3 Kural (yalnız Windows'ta, hazırlık çağrısında)

1. **Eski klasör varsa ve yeni klasör yoksa ya da bomboşsa:**
   1. Açık duran aynı adlı süreçlere bakılır (§5.5). Uygulamanın başka bir kopyası çalışıyorsa bu adım atlanır: bu
      açılışta eski klasör kullanılır; taşımanın başka bir kopya açık olduğu için ertelendiğini söyleyen
      bir not taşıma hatası olarak kaydedilir (`hata.log`'a gider).
   2. Eski klasörün "başka uygulamayla ortak" olup olmadığına karar verilir. Ortak sayılır: başka klasörden çalışan
      açık bir aynı adlı süreç varsa; ya da eski klasörün içinde bir Velopack kurulumu izi varsa (`Update.exe` dosyası,
      `current\` ya da `packages\` klasörü; herhangi biri yeter); ya da eski klasörün yanında (`%LOCALAPPDATA%`
      altında) asıl uygulamanın Velopack kurulum klasörü varsa (eski kodda bu klasörün adı sabit `NinoApp`).
   3. Yeni klasör bomboşsa silinir (yalnız boşsa; içinde bir şey varsa silinmez).
2. **Karar:**
   - Yeni klasör varsa (içinde tek dosya bile varsa): o kullanılır; eskisine dokunulmaz, birleştirilmez.
   - İkisi de yoksa: yenisi kullanılır ve oluşturulur (oluşturulamazsa dönen yol değişmez; dosyayı yazan kod hatayı kendisi alır).
   - Yalnız eski varsa ve ortak değilse: **taşınır** (iki klasör aynı üst klasörde olduğu için tek bir yeniden
     adlandırma; ya hep ya hiç).
   - Yalnız eski varsa ve ortaksa: **kopyalanır** (§5.4), eski klasör olduğu gibi kalır.
   - Taşıma/kopya hangi nedenle olursa olsun başarısızsa: o arada yeni klasör oluştuysa (aynı anda açılan başka kopya
     önce taşıdı) yeni klasör kullanılır, hata yok sayılır; değilse **eski klasör kullanılır, yeni klasör
     oluşturulmaz** (yoksa sonraki açılışta boş yeni klasör seçilirdi, ayarlar kaybolmuş görünürdü) ve hata kaydedilir.
     Taşıma/kopya sonraki açılışta yeniden denenir.
3. Karar şunları bilir: kullanılan yol, klasör adı (yeni ya da eski), varsa hata, "kopyalandı" bayrağı.

Testlerden çıkan durumlar (hepsi geçici klasörde):
- Yalnız eski → taşınır, içerik (alt klasörler dahil) aynen yeni adda; eski klasör kalmaz.
- Taşıma G/Ç, izin ya da başka bir hatayla başarısız → eski klasör kullanılır, yeni klasör yok, hata kaydı var.
- İkisi de var → yeni kullanılır, ikisine de dokunulmaz. Hiçbiri yok → yeni oluşturulur.
- Taşıma başarısız ama yeni klasör o arada belirdi → yeni kullanılır, hata yok.
- Hazırlık olmadan → hiçbir şey taşınmaz, oluşturulmaz.
- Açık dosya yüzünden engellenen taşıma → eski klasör bütün kalır, yeni klasör yok.
- Başka kopya açık → ertelenir; eski veri yoksa süreç listesine hiç bakılmaz.
- Boş yeni klasör eski verinin önüne geçmez (silinip taşıma yapılır); ama hazırlık yokken ya da başka kopya açıkken
  boş yeni klasöre dokunulmaz. İçinde tek dosya olan yeni klasör kazanır.
- Ortaklık işaretlerinin her biri tek başına (`Update.exe` dosyası, `current` klasörü, `packages` klasörü, yanındaki
  kurulum klasörü, başka yerden çalışan süreç) kopyaya yol açar; kopyada kurulum girdileri eski klasörde kalır.
- Hiçbir işaret yoksa eski klasör bütün olarak taşınır. Başka kopya açıksa klasör ortak olsa da ertelenir.

### 5.4 Kopyalama (ortak eski klasör)

1. Yeni klasörün yanında (`%LOCALAPPDATA%` altında) `Nino.kopya-*` adlı artık klasörler (yarıda kesilmiş önceki
   denemeler) silinir (silinemeyen geçilir).
2. Geçici klasör `Nino.kopya-<tiresiz rastgele kimlik>` oluşturulur; eski klasör içine kopyalanır. Kurallar:
   - **Yalnız en üst düzeyde atlananlar** — klasörler: `current`, `packages`, `models`, `webview`, `xbox-webview` ve
     `cuda-` ile başlayan her klasör; dosyalar: sonu `.exe`, `.nupkg`, `.log`, `.log.1`, `.tmp` olanlar
     (büyük/küçük harf duyarsız). Gerekçe: başka uygulamanın kurulumu Nino'nun değil; modeller ve CUDA yüzlerce MB–GB
     (eksik model ana ekrandaki kartla yeniden indirilir); WebView2 profilleri öbür uygulama açıkken kilitli ve yalnız
     giriş sayfası çerezleri; günlükler öbür uygulamanınki.
   - Kopyalananlar örnek: `settings.json`, `secure.dat`, `packs`, `adb`, `samsung`, `pool`, `translations`, `glossary`.
     Atlananlar örnek: `current`, `packages`, `Models` (harf duyarsız), `cuda-12.8`, `webview`, `xbox-webview`,
     `Update.exe`, `Nino.exe`, `hata.log`, `remoteplay.log`, `altyazi.log.1`, `secure.dat.tmp`.
   - Hiçbir düzeyde bağlantı (junction, simgesel bağ; yeniden ayrıştırma noktası) izlenmez, atlanır.
3. Geçici klasöre `kopyalandi.txt` yazılır: verinin hangi klasörden ne zaman (<yyyy-AA-gg SS:dd>) kopyalandığını, eski
   klasörün paylaşıldığı için yerinde bırakıldığını ve modellerin kopyalanmadığını anlatan kısa Türkçe not (metni yeni
   yazılır; okunmaz, yalnız kullanıcı için).
4. Geçici klasör tek yeniden adlandırmayla `Nino` olur.
5. Herhangi bir adım başarısızsa geçici klasör silinir ve hata yükselir (yarım kopya yeni klasör olmasın) → §5.3'teki
   başarısızlık kuralı.

### 5.5 Açık kopyaları sınıflandırma

- Bu oturumdaki (aynı Windows oturum kimliği), bu süreçle aynı süreç adını taşıyan öbür süreçlerin exe yolları alınır.
  Yolu okunamayan süreç (kapanmakta ya da yönetici haklarıyla çalışıyor) "yolu yok" sayılır. Süreç listesi hiç alınamazsa
  sonuç "yok".
- Sınıflandırma (kendi yolumuz ve öbürlerinin yolları):
  - Öbürlerinden birinin yolu yoksa ya da kendi yolumuz bilinmiyorsa (ve en az bir öbür varsa) → **bu uygulamanın
    kopyası** (temkinli: ertele).
  - Velopack başlatıcısının yolu (§2) sayılmaz.
  - Aynı klasörden çalışan → bu uygulamanın kopyası.
  - Başka klasörden çalışan → başka uygulama (ama listede sonra "bu uygulamanın kopyası" çıkarsa o kazanır).
  - Hiçbiri → yok.
- Örnekler (`K` = `…\NinoGameTranslator`): kendi `K\current\Nino.exe`; öbürleri `[]` → yok; `[K\Nino.exe]` → yok
  (başlatıcı); `[K\current\Nino.exe]` → bu uygulama; `[asıl\current\Nino.exe, K\current\Nino.exe]` → bu uygulama;
  `[asıl\current\Nino.exe]` → başka; `[K\Nino.exe, asıl\current\Nino.exe]` → başka; `[asıl…, yolu yok]` → bu
  uygulama; kendi yolu bilinmiyor + `[asıl…]` → bu uygulama; kendi yolu bilinmiyor + `[]` → yok.

---

## 6. `%LOCALAPPDATA%\Nino` içindekiler

| Yol | Biçim | Ne / kim yazar | Mac'le ilişki |
|---|---|---|---|
| `settings.json` | JSON, `ayarlar-modeli.md` | Kullanıcı ayarları | Mac'te UserDefaults; alan adları farklı |
| `secure.dat` (+ yazarken `secure.dat.tmp`) | DPAPI şifreli JSON (§7) | Hesap, PS5, TV anahtarları, çeviri anahtarları | Mac'te Anahtarlık |
| `history.json` (+ `.tmp`) | §13.2 | Çevrilen satırların geçmişi | Mac veri-uyumu §3 ile **aynı biçim** |
| `sorunlar.json` | Mac §3 ile aynı | Sorun geçmişi (`settings.section.systemHealth`) | aynı |
| `otomatik-bildirim.json` | Mac §3 ile aynı | Otomatik sorun bildirimi sayacı | aynı |
| `report-install.txt` | tek satır kimlik | Sorun bildirme / Nino'ya Sor'un kuruluş kimliği (havuz kimliği yoksa kullanılır) | sorun bildirme tarifinde |
| `auto-update-tried.txt` | §10.3 | Kendiliğinden güncelleme deneme sayacı | Windows'a özgü |
| `pool\` | `state.json`, `pending.jsonl`, `outbox\*.json`, `parked\*.json`, `rejected.jsonl`, `endpoint.txt` (varsa sunucu adresini değiştirir) | Ortak havuz istemcisi | Mac veri-uyumu §3.1 ile aynı (platform `windows`) |
| `pool.json` | eski satır havuzu kuyruğu | Bir kez `pool\`'a aktarılır | Mac §3 ile aynı |
| `pool-translations\` | `translations-<dil>.json`, `install`, `downloads.txt` (§13.4) | Nino çeviri havuzundan inenler | Mac'te `Translations/` içinde; **Windows'ta ayrı klasör** |
| `translations\` | `v1-<motor>-<kaynak>-<hedef>.jsonl`, `v1h-<sha256>.jsonl` (§13.1) | Çeviri önbellekleri (motor + dil çifti başına) | Mac §3.2 ile aynı biçim; klasör küçük harf |
| `packs\` | `*.json.gz` (paket güncelleyici), `*.json` (içe aktarılan); `.<kimlik>.download`, `.<rastgele>.tmp` geçici | Kullanıcının/sunucunun oyun paketleri | Mac §3.3 ile aynı biçim |
| `packs-remote.json` | Mac §3 ile aynı | Paket güncelleyici durumu (bugün kapalı) | aynı |
| `glossary\` | `*.json`, ad sırasıyla | Kullanıcı terim sözlükleri | Mac §3.4 ile aynı biçim; klasör küçük harf |
| `models\` | `en-tr-ct2\` (CTranslate2 Türkçe modeli; `model.bin`, `shared_vocabulary.json` ya da `source_/target_vocabulary.json`, `config.json`, `LICENCE.txt`), `en-<dil>\` (ONNX modelleri, `vocab.json`…), eski `en-tr\` | Ücretsiz çeviri modelleri | Windows'a özgü (çeviri tarifinde) |
| `cuda-12.8\` | CUDA çalışma zamanı DLL'leri + `CUDA-LICENSE.txt` | GPU seçilince indirilir | Windows'a özgü |
| `adb\adbkey` | ADB özel anahtarı | Android TV kurulumu. **Silinirse TV yeniden izin sorar** | Mac §3 ile aynı |
| `samsung\` | `author.p12`, `distributor.p12`, `device-profile.xml`, `password.txt`, `duid.txt` | Samsung TV sertifikaları | Mac'teki yardımcı klasörüyle aynı içerik |
| `webview\<rastgele>\` | WebView2 profili | PSN giriş penceresi: **her girişte yeni, temiz profil**; açılırken önceki artık klasörler silinir, tarayıcı süreci bitince klasör silinir (silinemeyeni sonraki giriş temizler) | Windows'a özgü |
| `xbox-webview\` | WebView2 profili (kalıcı) | Xbox oynatıcı penceresi | Windows'a özgü |
| `hata.log` | §8 | Açılış ve beklenmeyen hatalar | Windows'a özgü |
| `remoteplay.log` | §8 | PS5 bağlantısı günlüğü | Mac'te `~/Library/Logs/Nino` |
| `altyazi.log`, `altyazi.log.1` | §8 | Altyazı günlüğü | aynı biçim |
| `tvinstall.log` | §8 | TV kurulum günlüğü | aynı biçim |
| `kopyalandi.txt` | düz metin | §5.4 | aynı anlam |

Mac'te olup Windows'ta olmayanlar: `subtitle-layout.json`, `phone-memory-<dil>.json`, `Covers/`, `dubbing/`,
`frames/`, `takilma-*.txt` (Windows'ta böyle dosya yazılmaz).

Uygulamanın kendi dışında yazdığı: sistem sağlığı penceresindeki kayıtları dışa aktarma düğmesi İndirilenler klasörüne
`Nino-kayitlar-<yyyy-AA-gg-SS-dd-ss>.zip` yazar (içinde `ayrintilar.txt` ve günlükler; saglik-bildirim-sor.md'de).

---

## 7. `secure.dat` (şifreli depo)

### 7.1 Dosya biçimi

- İçerik: bütün anahtarları tutan **tek bir JSON nesnesinin** UTF-8 metni (girintisiz), Windows veri korumasıyla
  (DPAPI, **geçerli kullanıcı** kapsamı) şifrelenmiş ikili blob. Dosyada başka başlık yok.
- **Ek anahtar (entropy): düz metin `nino-secure-store`'un UTF-8 baytları.**
- Okuma: dosya yoksa boş nesne. Dosya okunur, yeni ek anahtarla çözülür. Şifre çözülemezse **eski ek anahtarla**
  (`LegacyNames`'te base64 duran değer; değeri burada yazılmaz) denenir; o tutarsa içerik nesneyse hemen **yeni ek
  anahtarla yeniden yazılır** (bir kezlik geçiş). İkisi de tutmazsa ya da JSON bozuksa boş nesne döner (başka
  kullanıcıdan taşınmış ya da bozuk dosya: kurulum yeniden yapılır). Dikkat: bu durumda sonraki ilk kayıt dosyanın
  üstüne yalnız yeni anahtarla yazar; eski içerik kaybolur. Yeni uygulama okunamayan dosyayı yazmadan önce
  `secure.dat.bozuk-<zaman>` gibi kenara alabilir (önerilir; eski uygulama yapmıyor).
- Yazma: her kayıt/silmede bütün nesne yeniden okunur, değiştirilir, şifrelenir, `secure.dat.tmp`'ye yazılır, sonra
  `secure.dat`'ın üstüne taşınır. Klasör yoksa oluşturulur. Silme yalnız anahtar varsa dosyayı yazar.
- Bütün işlemler tek kilit altında (aynı süreçte eşzamanlı yazma yok).
- Değer okuma: anahtar yoksa "yok"; değer istenen tipe çevrilemezse "yok".
- Değerler varsayılan JSON yazımıyla: alan adları **büyük harfle başlar**, bu dosyadaki enum'lar **sayı**, bayt dizileri
  base64 dizgesi, tarihler ISO-8601 ofsetli dizge.

### 7.2 Anahtarlar

| Anahtar | Değer biçimi | Ne zaman yazılır / silinir |
|---|---|---|
| `accountId` | base64 dizgesi (8 baytlık PSN hesabı kimliği), ör. `"AQIDBAUGBwg="` | PSN girişi bitince |
| `console` | `{"Host": "192.168.0.5", "Name": "PS5-123", "RegistKey": base64 (16 bayt), "Morning": base64 (16 bayt), "WakeCredential": sayı ya da null}` | PS5 eşleşince; adres değişince yeni adresle. `WakeCredential` hesaplanan bir alandır (kayıt anahtarındaki onaltılık ASCII metnin ilk sıfır bayta kadarki sayı değeri), eski uygulama yazar ama okurken yok sayar; yeni uygulama yazmayabilir |
| `consoleKind` | sayı: 0 = PlayStation, 1 = Xbox | Konsol türü seçilince. Yoksa PlayStation |
| `consoleKindLocked` | Bool | Konsol türü kilitlenince (ilk çeviri başlayınca) `true`. Yoksa `false` |
| `xboxToken` | dizge | Xbox girişi / jeton yenilenince |
| `xboxConsole` | `{"Id": dizge, "Name": dizge, "Model": dizge, "StreamingEnabled": Bool}` | Xbox seçilince |
| `tv` | `{"Name": dizge, "Host": dizge, "Brand": sayı}`; Brand 0 = LG, 1 = Samsung, 2 = Android TV; yoksa LG | TV eşleşince; TV ağda yeni adreste bulununca. (Mac'te `brand` yazıyla tutulur; Windows'ta sayı) |
| `tvKey` | dizge | LG istemci anahtarı / Samsung jetonu / Android TV boş dizge. Samsung'da boş gelen yeni jeton eskisinin üstüne yazılmaz. TV bağlantıda yeni jeton verince saklanır |
| `tvDevKey` | dizge | LG geliştirici modu anahtarı; geçersiz çıkınca silinir |
| `tvAppVersion` | dizge | Samsung ve Android TV'ye kurulan TV uygulaması sürümü; TV markası ya da adresi değişince silinir |
| `devSessionRenewed.<adres>` | ISO-8601 ofsetli tarih dizgesi (ör. `"2026-11-22T10:00:00+00:00"`) | LG geliştirici modu süresinin bu TV için son uzatıldığı an (UTC). Adres kırpılmış ve küçük harf. (Mac'te UserDefaults'ta; Windows'ta **burada**) |
| `lastGames` | `{"<PS5 adı>": "<oyun adı>"}` | Ana ekrandaki oyun kartında (`home.card.game.label`) elle seçilince |
| `captureCardId` | dizge (aygıt kimliği) | Kart (yakalama aygıtı) seçilince; seçim kaldırılınca silinir. Yalnız bu makinede geçerli |
| `streamBackground` | dizge: `green`, `black`, `magenta` | OBS'siz yayın penceresinin (`settings.obs.streamWindow`) zemin rengi. Okunamayan/bilinmeyen değer → `green`. Okuma büyük/küçük harf duyarsız |
| `setupComplete` | Bool | §7.3 |
| `loginPasscode` | dizge, tam 4 rakam | İkinci hesabın PS5 parolası (`settings.section.passcode`); kırpılır, 4 rakam değilse kaydedilmez/geçersiz sayılır; Ayarlar'dan silinebilir |
| `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey`, `localAIKey` | dizge | Kullanıcının çeviri anahtarları ("anahtar var" = boş olmayan dizge). Anahtar kaldırılınca silinir |
| `samsungClientName` | dizge | Samsung TV'ye gönderilen cihaz adı. Kayıtlıysa hep o; yoksa yeni ad `Nino` (önceki sürümün adı da bugün `Nino`). Yeni ad kullanılınca ve kayıtlıdan farklıysa kaydedilir |

Sıfırlama: tam sıfırlama (`settings.reset.everything`) → `accountId`, `console`, `consoleKind`, `consoleKindLocked`, `xboxToken`,
`xboxConsole`, `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete`, `loginPasscode` silinir (çeviri anahtarları,
`lastGames`, `captureCardId`, `streamBackground`, `devSessionRenewed.*`, `samsungClientName` kalır).
TV'den itibaren sıfırlama → `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete`.

### 7.3 Kurulum bitti mi (açılışta)

- Konsol hazır: Xbox'ta `xboxToken` ve `xboxConsole` var; PlayStation'da `accountId` ve `console` var.
- TV eşli: `tv` var ve `tvKey` var (boş dizge de "var").
- `setupComplete` hiç yoksa (çok eski kurulum): "bitti" = konsol hazır **ve** TV eşli; bu değer hemen kaydedilir.
  Varsa: "bitti" = konsol hazır **ve** kayıtlı değer.
- Ana ekran açılır (adım "bitti") eğer: (konsol PlayStation ve `FrameSource` pencere ya da seçilen pencere) **veya**
  yukarıdaki "bitti" **veya** (`VideoSource` PS5 değil ve `setupComplete` = true). Değilse konsol hazırsa TV adımı,
  değilse karşılama adımı.
- Sihirbaz "bitti" adımına gelince `setupComplete` = true yazılır.

---

## 8. Günlükler

| Dosya | Satır biçimi | Sınır | Yazan |
|---|---|---|---|
| `hata.log` | `[yyyy-AA-gg SS:dd:ss] <ileti>` + satır sonu + hatanın tam metni (yoksa boş) + boş satır | sınırsız | Açılış hataları, yakalanmamış hatalar, ayarların kaydedilemediği, genel kısayolun başka uygulamada olduğu (+ tuşlar), tarayıcının açılamadığı, ücretsiz çevirmenin kurulamadığı, altyazı penceresinin kurulamadığı durumlar (her biri tek satırlık Türkçe günlük notu; metni yeni yazılır). Eşzamanlı yazımlar kilitle sıralanır; yazılamazsa sessizce geçilir. Çekirdek DLL'i yokken yer: yeni klasör varsa o, yoksa eski klasör varsa o, yoksa yeni |
| `remoteplay.log` | `[yyyy-AA-gg SS:dd:ss] [nino] <uygulama notu>` ya da `[chiaki error|warning|info] <kitaplık satırı>` | 1 MiB'ı (1 048 576 bayt) geçince dosyanın **ilk yarısı silinir** (karakter ortasından), sonra eklenir | Arka plan iş parçacığı, en çok 2000 satırlık kuyruk (dolarsa satır atılır) |
| `altyazi.log` | `[yyyy-AA-gg SS:dd:ss.fff] <satır>` | Eklenecek satırla 1 MiB'ı geçecekse dosya `altyazi.log.1` olur (eskisinin üstüne), yeni dosya başlar; en çok ~2 MB | Arka planda, 2000'lik kuyruk (dolarsa satır atılır); açılışta etkinleşir (testlerde kapalı). "Bekleyenleri yaz" işlemi (en çok 2 sn bekler) yalnız testlerde kullanılır; uygulama kapanırken çağrılmaz (yeni uygulama kapanışta çağırabilir) |
| `tvinstall.log` | `[yyyy-AA-gg SS:dd:ss] <ileti, sondaki boşluklar kırpılmış>` | 1 MiB'ı geçince eski yarı silinir, kalan **satır başından** başlar | TV kurulumu; Samsung hesabı jetonu ve parolalar yazılmaz |

Altyazı günlüğü yardımcıları:
- Alıntı: satır sonlarıyla bölünür, parçalar kırpılır, boşlar atılır, ` / ` ile birleştirilir; 120 karakteri (Unicode
  karakter, vekil çiftler bölünmez) aşarsa ilk 119 + `…`; çift tırnak içinde. Örnek: "MIRA: Close the hatch!\nHurry." →
  `"MIRA: Close the hatch! / Hurry."`.
- Görüntü duraklaması izleyici (Remote Play kitaplığının satırlarından): "FEC failed" ya da "Video FEC failure" içeren
  satır, duraklama yoksa başlatır → görüntünün FEC hatasıyla durduğunu ve IDR karesinin beklendiğini söyleyen not
  (duraklama sürerken yenisi bir şey yazmaz). "Received IDR frame" içeren satır, duraklama varsa bitirir → görüntünün
  IDR karesiyle sürdüğünü söyleyen not + ` (<n> ms boşluk)`. PS5 oturumunun görüntü gelmediği için yeniden kurulduğunu
  bildiren uygulama satırı → IDR karesinin gelmeyeceğini, oturumun yeniden kurulduğunu söyleyen not + duraklama varsa
  ` (<n> ms boşluk)`; duraklama sıfırlanır. (Notlar Türkçe, yeni yazılır; yalnız günlükte.) Öbür satırlar
  bir şey yazmaz.
- Çeviri yoklaması (her çeviri isteğine bağlı; aynı mantıksal akışta görünür): önbellekten dönen parçaları ve motorun
  yeni ürettiği parçaları (motor adıyla) sayar. Sonuç: yeni parça varsa `çeviri:<son yeni parçanın motoru>` (motor adı
  boşsa yedek ad); yoksa önbellekten dönen varsa `önbellek`; hiçbiri yoksa `çeviri:<yedek ad>` (yedek ad verilmezse
  `motor`). Örnek: `çeviri:deepl`, `önbellek`, `çeviri:opus`.

Sorun bildirirken eklenen günlük sonları (ör. `remoteplay.log`'un son 18 000 karakteri) sorun bildirme tarifinde.

---

## 9. Gömülü kaynaklar

Eski uygulama bunları başka klasörlerden (Mac ve ortak çekirdek) bağlantıyla gömüyordu. Yeni uygulama **kendi
dosyalarını** yeniden üretir (bağlantı yok), biçim aynı kalır. Gömülü kaynak adları: `glossary-en-tr.json`,
`ai-models.json` (`Resources/`), `link/obs.html`, `text/<dil>.json` (`Text/Catalog/`), `design/tokens.json`
(`Design/`) ve Samsung PEM'leri. Oyun paketi gömülmez (§9.3).

### 9.1 `tokens.json` (tasarım değerleri)

Nesne: `name` ("Nino"), `version` (4), `fontFamily` (`{"mac": "SF Pro (sistem)", "windows": "Segoe UI Variable"}`),
`color` (ad → `{"light": "#RRGGBB", "dark": "#RRGGBB"}`), `font` (ad → `{"size": sayı, "weight": "regular"|"medium"|"semibold"}`),
`space`, `radius`, `size` (ad → sayı). Parıltı (`glow`) alanı yok. Okuyucu alan adlarında harf duyarsız, bilinmeyen
alanları atlar. Bulunamazsa ya da bozuksa açılış hatası.

Renkler (21 çift) Mac `tasarim-dili.md` tablosuyla aynı; ek olarak `onDanger` açık #FFFFFF, koyu #17181B.
Öbür değerler:
- `font`: display 28 semibold, title 22 semibold, headline 17 semibold, body 15 regular, callout 13 medium,
  caption 13 medium, button 15 semibold, code 22 semibold.
- `space`: xs 4, s 8, m 12, l 16, xl 24, xxl 32, hair 4, inline 8, gap 12, tile 16, screen 24.
- `radius`: card 22, control 14, inner 10, tag 6, pill 999.
- `size`: buttonHeight 40, buttonLarge 44, primaryActionHeight 52, rowHeight 40, keycap 24, statusDot 8,
  sidebarWidth 240, mainColumn 380, windowWidth 1040, windowHeight 720.

Yardımcılar: "#RRGGBB" → 0–1 aralığında üç kanal (7 karakter ve `#` değilse geçersiz). WCAG 2 kontrastı: kanal
≤ 0.03928 ise /12.92, değilse ((c+0.055)/1.055)^2.4; parlaklık 0.2126R + 0.7152G + 0.0722B; oran
(büyük+0.05)/(küçük+0.05). Örnek: #000000/#FFFFFF = 21; #777777/#FFFFFF ≈ 4.48.
Testlerin istediği değişmezler (yeni değerler de sağlamalı): her renk geçerli; textPrimary background/surface/surface2
üstünde ≥ 7; textSecondary (ve öbür yazı renkleri) background/surface/surface2 üstünde ≥ 4.5; accentText/accentSoft ≥
4.5; pro background/surface/proSoft üstünde ≥ 4.5; danger/dangerSoft ≥ 4.5; success/successSoft ≥ 4.5; onAccent/accent
≥ 3 (açıkta ≥ 4.5); onDanger/danger ≥ 4.5; köşe değerleri kümesi {6, 10, 14, 22, 999}; yazı boyları {13, 15, 17, 22, 28}
içinde; ağırlıklar {regular, medium, semibold}; body ≥ 15, caption ≥ 12.

WPF'e aktarma: her renk `<ad>Brush`, boşluk `space.<ad>` (sayı) ve `pad.<ad>` (dört kenar), köşe `radius.<ad>`, boyut
`size.<ad>`; pencere zemini = background (düz renk, degrade yok). Ayrıntı tasarım dili tarifinde.

### 9.2 Metin katalogları (eski: `Localizable.xcstrings` + `Windows.xcstrings`; yeni: `Text/Catalog/*.json`)

- Biçim: Apple xcstrings JSON. Kök: `sourceLanguage` ("en"), `version` ("1.0"), `strings` (anahtar → kayıt). Anahtar
  İngilizce metnin kendisidir. Kayıt: `localizations` → dil kodu → `stringUnit` → `value` (ayrıca `state`; okunmaz).
  `extractionState`, çoğul `variations` gibi öbür alanlar okunmaz. Dil kodları: `tr, ar, bn, fil, hi, id, ms, nl, th,
  ur, vi` (+ gerekirse `en`).
- Önce ortak katalog (Mac'inki, ~3,6 MB) okunur, sonra Windows'a özgü katalog (74 anahtar: "bu Mac" yerine "bu
  bilgisayar", Windows ayar yolları, Xbox uygulaması…) aynı biçimle okunup **aynı anahtarı ezer**. Windows kataloğu
  yoksa sorun değil; ortak katalog yoksa açılış hatası.
- Yeni uygulama kataloğu yeniden yazar (mimari kuralı): `apps/windows/src/Nino.Core/Text/Catalog/<dil>.json`, düz
  JSON nesnesi (noktalı anahtar → değer), 12 dil; anahtarın tarifte göründüğü yer `catalog-where.json`'da. Eski xcstrings
  okunmaz. Testler en az şunu arar: çeviri başlatma düğmesi, ana ekrandaki toplam indirme sayacı (`home.tv.totalDownloads`;
  büyük harfe çevrilmiş hâli de), TV fişinin boş durum ipucu (`home.tv.idle`), çeviri başlayınca çıkan balon
  (`home.toast.translationStarted`), `common.settings`, `setup.welcome.translationLanguage` ve cihaz bilgisi anahtarları
  (`device.title`, `device.label.app`, `device.label.device`, `device.label.system`, `device.label.status`,
  `device.copy`, `common.copied`, `device.hint`) tr ve ar'da çevrili olmalı.

### 9.3 Paketler (gömülmez)

Eski uygulama dokuz oyun paketini (`packs/<kimlik>.json.gz`, biçim 2) uygulamanın içine gömüyordu. Yeni uygulama **hiç
paket gömmez**: paketler yalnız ortak havuzdan `/v1/packs` ile iner ve kullanıcının paket klasörüne yazılır
(havuz-paketler.md §2.2, §2.6). Paket dosyasının biçimi (sarılı biçim 1, düz biçim, biçim 2: `entries`, `segments`,
`fuzzy`) havuz-paketler.md §2.1'de; içe aktarılan ve indirilen paketler o biçimle okunur. Testler kendi deneme
paketlerini kullanır (`tests/Nino.Core.Tests/Fixtures/pack-*.json.gz`, `tools/gen-vectors.py` üretir).

### 9.4 `ai-models.json` (yapay zekâ modelleri)

Şema: nesne; `_about` (dizge, yok sayılır) ve hizmet adı → model dizisi. Dizi olmayan her alan atlanır; boş dizi
hizmeti eklemez. Model öğesi: `id` (zorunlu), `text` (zorunlu; görünen adın metin kataloğu anahtarı; eski dosyadaki
`label` alanının yerini alır, eski dosya okunmaz), `effort` (isteğe bağlı:
OpenAI `reasoning_effort` / Claude `output_config.effort`), `thinking` (isteğe bağlı: Gemini
`thinkingConfig.thinkingLevel` / Claude `thinking.type`), `freeTier` (yalnız `true` ise doğru; yoksa yanlış),
`requestsPerMinute` (tam sayı; yoksa sınırsız). **İlk model varsayılandır.** Kullanıcı yalnız listeden seçer.

Değerler (birebir):

| Hizmet | id | text | effort | thinking | freeTier | requestsPerMinute |
|---|---|---|---|---|---|---|
| `gemini` | `gemini-3.5-flash-lite` | `ai.model.fast` | — | — | true | 15 |
| `gemini` | `gemini-3.6-flash` | `ai.model.better` | — | `LOW` | true | 10 |
| `openai` | `gpt-6-luna` | `ai.model.fast` | `none` | — | — | — |
| `openai` | `gpt-6.1-terra` | `ai.model.better` | `none` | — | — | — |
| `claude` | `claude-haiku-5-5` | `ai.model.fast` | `low` | `disabled` | — | — |
| `claude` | `claude-sonnet-5-5` | `ai.model.better` | `low` | `between_tools` | — | — |

`ai.model.fast` hızlı ve ucuz, önerilen seçeneği; `ai.model.better` daha iyi ama biraz yavaş seçeneği anlatır.

Hizmet kimlikleri `gemini`, `openai`, `claude`, `local`; önbellekteki motor adı `<hizmet>:<model>` (ör.
`gemini:gemini-3.5-flash-lite`). Yerel modelde liste yok: varsayılan `translategemma:4b`, sunucu varsayılanları Ollama
`http://localhost:11434/v1`, LM Studio `http://localhost:1234/v1`. Anahtar sayfaları: Gemini
`https://aistudio.google.com/apikey`, OpenAI `https://platform.openai.com/api-keys`, Claude
`https://platform.claude.com/settings/keys`, yerel `https://ollama.com/download`. Ücretsiz katmanı olan hizmet:
yalnız Gemini. Görünen adlar: Gemini, OpenAI, Claude; yerel model çevrilir (metin anahtarıyla).

### 9.5 `glossary-en-tr.json` (genel terim sözlüğü)

Mac veri-uyumu §3.4 biçimi: `{"game": "Genel", "terms": {26 İngilizce→Türkçe}, "keep": [], "keepExact": [1 ad],
"phrases": {10 düzenli ifade→düz İngilizce}, "lines": {62 hazır satır}}`. Kullanıcı sözlükleri (`glossary\*.json`) bunun
üstüne ad sırasıyla eklenir. Eski dosya kopyalanmaz: içerik `tools/gen-vectors.py` ile kendi örneklerimizden üretilir
(bayt bayt aynı çıkar); kullanımı ve izi ceviri.md §5.5–5.6'da.

### 9.6 `obs-overlay.html`

~17 KB'lık tek sayfa: altyazı sunucusunun `/obs` yolunda verdiği OBS tarayıcı kaynağı katmanı (`?bg=green` gibi düz
zemin seçeneğiyle; zemin renkleri §7.2 `streamBackground` ile aynı: yeşil #00FF00, siyah #000000, mor #FF00FF). İçeriği
TV bağlantısı/sunucu tarifinde; yeni uygulama aynı davranışı veren sayfayı yeniden yazar.

### 9.7 Samsung ara sertifikaları

TV kurulumu katmanına gömülü dört PEM (Tizen Studio'dan, değiştirilmeden): `author_ca.pem`, `public2.pem`,
`vd_tizen_dev_author_ca.pem`, `vd_tizen_dev_public2.pem`; kaynak adı `SamsungCa.<ad>.pem`. Üçüncü taraf verisi olarak
aynen kopyalanır.

---

## 10. Güncelleme

### 10.1 Kaynak

- Kurulumla (Velopack) gelen kopya: Velopack'in GitHub kaynağı, depo `https://github.com/yunusdemirbag/nino-game-translator`,
  erişim jetonu yok, **ön sürümler dahil edilmez** (sürümler GitHub'da "en son" olarak, ön sürüm işaretsiz yayımlanır;
  beta etiketleri de). "Kendini güncelleyebilir" = Velopack kurulumu içinden çalışıyor.
- Zip kopyası (kurulu değil): `https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest`
  okunur (User-Agent `Nino`, 10 sn zaman aşımı); `tag_name`'in başındaki `v`'ler atılır; bu sürümden yeniyse o numara,
  değilse "yok". Ağ/JSON/alan hatasında "yok". Sürüm sayfası: `…/releases/latest`.

### 10.2 Akış

- Ana ekran açılınca bir kez denetlenir, sonra **3 saatte bir** (döngü bir kez kurulur). Ağ yoksa sessizce geçilir.
- Yeni sürüm bulunur, kendini güncelleyebiliyor ve kendiliğinden kurulum hakkı varsa (§10.3, ayrıca bu açılışta bitmemiş otomatik indirme sayısı < 3):
  - Çeviri sürmüyorsa hemen kendiliğinden kurulur.
  - Çeviri sürüyorsa "bekleyen kurulum" işaretlenir; çeviri durunca kurulur (oyun bölünmesin). Uygulama kapanırken
    başlatılmaz (bekleyen kurulum sonraki açılışta yeniden bulunur).
- "Güncelle" düğmesi: kendini güncelleyemiyorsa sürüm sayfası tarayıcıda açılır, başka bir şey yapılmaz.
- Kurulum: zaten sürüyorsa ya da (kendiliğinden ve kapanıyorsa) yapılmaz. Bekleyen işaret kaldırılır, "güncelleniyor"
  açılır, hata temizlenir; çeviri sürüyorsa durdurulur; indirilir (ilerleme 0–1); indirme bitip kurulum başlamadan hemen
  önce deneme sayacı yazılır; sayaç **yazılamazsa ve kurulum kendiliğindense** kurulum başlatılmaz (hata: "güncelleme
  denemesi kaydedilemedi; kurulum kendiliğinden başlatılmadı"); düğmeyle başlatılan kurulum sayaç yazılamasa da sürer.
  Sonra Velopack kurar ve uygulamayı yeniden başlatır.
- Hata (ağ, iptal, G/Ç, izin, geçersiz durum): hata iletisi gösterilir; kendiliğinden kurulumda indirme aşamasında
  olduysa "yarıda kalan indirme" sayısı artar. "Güncelleniyor" kapanır.

Testlerden: boştayken yeni sürüm bir kez kurulur; indirme hatası hakkı tüketmez (sayaç dosyası oluşmaz), sonraki
denemede kurulur ve sayaç 1 olur; aynı açılışta indirme 3 kez yarıda kalırsa bir daha kendiliğinden denenmez; sürümü
değiştirmeyen kurulum sürüm başına 2 kez kendiliğinden denenir, sonra yalnız düğme kalır (düğme yine çalışır); yeni
numara (10.0.0) çıkınca sayım baştan; çeviri sürerken bulunan güncelleme durunca kurulur; çeviri sürerken kapanırsa
kurulum başlamaz; indirme sırasında kapanırsa deneme sayılmaz; çeviri sürerken düğmeye basılınca tek kurulum olur; zip
kopyasında yalnız sayfa açılır, indirme yok.

### 10.3 Deneme sayacı (`auto-update-tried.txt`)

- Biçim: iki satır: `<sürüm>\n<sayı>\n`.
- Okuma: satırlar kırpılır, boşlar atılır; ilk satır sorulan sürüm değilse 0; ikinci satır pozitif tam sayıysa o, yoksa
  (yalnız sürüm yazan eski biçim) 1. Dosya yoksa/okunamazsa 0.
- Deneme sayısı = max(bu süreçte bellekte tutulan sayım [aynı sürümse], dosyadaki). En çok **2**; 2'ye ulaşınca
  "tükendi".
- Kayıt: sayı = max(bellek, dosya) + 1; bellek güncellenir; dosya yazılır (klasör yoksa oluşturulur). Yazılamazsa
  "başarısız" döner, bellekteki sayım sürer. Dosya yolu yoksa (testler) yalnız bellek.
- Örnekler: "1.2.3" için 0 → kayıt → 1 → kayıt → 2 (tükendi); "1.2.4" 0'dan başlar, onu kaydedince "1.2.3" artık 0
  okunur (dosyada tek sürüm durur). Dosya içeriği yalnız "1.2.3" → 1 deneme, tükenmemiş.

### 10.4 Sürüm karşılaştırma

- Baştaki/sondaki boşluk kırpılır, baştaki `v` atılır, `+` sonrası atılır. İlk `-`'ye kadar çekirdek (noktayla
  ayrılmış sayılar; sayı değilse 0), sonrası ön sürüm parçaları (noktayla).
- Çekirdek parça parça (eksik parça 0) karşılaştırılır. Eşitse: ön sürümü olmayan, olandan yenidir. İkisinde de varsa
  parça parça: biri bittiyse kısa olan eskidir; ikisi sayıysa sayı olarak; yalnız biri sayıysa sayı olan eskidir;
  ikisi de yazıysa sıralı karşılaştırma.
- Örnekler: 0.1.0 > 0.1.0-beta.9; 0.1.0-beta.10 > 0.1.0-beta.9; v4.0.1 > 4.0.0; 1.0.0-rc > 1.0.0-beta;
  1.0.0-beta.2 > 1.0.0-beta; 1.0 = 1.0.0; 1.0.0-1 < 1.0.0-a; 1.2.3+abc = 1.2.3.

---

## 11. Güvenlik duvarı (Windows)

PS5 Remote Play ve TV'nin bağlandığı altyazı sunucusu (8787, doluysa başka port) dışarıdan bağlantı alır; keşif ve PS5
yayını değişken UDP portları kullanır. Bu yüzden kural **port kısıtlamaz**: programa ve ağa göre daraltılır.

### 11.1 Kurallar

| Ad | Grup | Program | Yön | Eylem | Profil | Protokol | Uzak adres | Yerel adres | Portlar |
|---|---|---|---|---|---|---|---|---|---|
| `Nino - Local TCP` | `Nino.LocalNetwork` | bu `Nino.exe`'nin tam yolu | gelen (1) | izin (1) | yalnız Özel (2) | TCP (6) | `LocalSubnet` | hepsi | hepsi |
| `Nino - Local UDP` | `Nino.LocalNetwork` | aynı | gelen | izin | yalnız Özel | UDP (17) | `LocalSubnet` | hepsi | hepsi |

Ek alanlar: açıklama (kuralın Nino'nun TV ve Remote Play için özel yerel ağ izni olduğunu söyleyen tek İngilizce cümle; eşleşmede kullanılmaz), arayüz türü `All`, belirli arayüz yok,
kenar geçişi kapalı, etkin. COM'da protokol portlardan **önce** atanmalı. Kural exe yoluna bağlıdır; Velopack
güncellemeleri aynı `current` klasörünü kullandığı için kural güncellemelerde geçerli kalır.

Eski adlar (veri taşıma için; değerleri `LegacyNames`'teki eski klasör adından türetilir):
- **En eski geniş kural**: ad = eski ad; bu exe; gelen izin; **her protokol (256)**; üç profil (1|2|4 = 7); her adres,
  her port, servis yok, grup yok, arayüz `All`, arayüz kısıtı yok, kenar geçişi yok.
- **Önceki sürümün dar kuralları**: adlar `<eski ad> - Local TCP` / `<eski ad> - Local UDP`, grup `<eski ad>.LocalNetwork`,
  bu exe, gelen izin. Bunlar tam izin sayılır (yalnız adını değiştirmek yönetici izni istemez); izin başka bir
  nedenle zaten alınırken yeni adlara çevrilir. Eski uygulamanın **kendi exe'si** için yazdığı aynı adlı kurallara
  dokunulmaz.

Ad karşılaştırmaları büyük/küçük harf duyarsız. Program karşılaştırması: ortam değişkenleri açılıp tam yola çevrilir,
harf duyarsız; boş ya da çevrilemeyen yol eşleşmez. Kapsam okurken: boş → `*`; `LocalSubnet` (harf duyarsız) →
`LocalSubnet`. TCP/UDP dışı protokolde portlar `*` sayılır.

### 11.2 İzin var mı (yönetici gerekmez)

1. Özel profilde güvenlik duvarı açıksa ve Özel profilde "bütün gelen bağlantıları engelle" açıksa → **yok**.
2. Güvenlik duvarı açık, şu anki profil türleri Özel'i içeriyor ve yerel ilke değiştirme durumu 0 değilse (yerel
   kurallar grup ilkesiyle geçersiz) → **yok**.
3. Kural listesinde bu exe'nin en eski geniş kuralı varsa → **yok** (taşınması gerekiyor).
4. Özel profilde güvenlik duvarı kapalıysa → **var**.
5. TCP ve UDP için ayrı ayrı: etkin, gelen, Özel profili içeren, protokolü o ya da "her protokol" olan kurallara
   bakılır. Bunlardan biri **engel** ise ve (programı bu exe ise **ya da** programsız, servissiz, her port, uzak adres
   her yer/yerel alt ağ, yerel adres her yer olan genel bir engelse) → **yok**. Başka programın ya da servisin engeli
   sayılmaz. Sonra en az bir **izin** olmalı: programı bu exe, uzak adres her yer ya da `LocalSubnet`, yerel adres her
   yer, yerel ve uzak port her yer, servis yok, arayüz `All`, arayüz kısıtı yok. Yoksa → **yok**.
6. İkisi de geçerse → **var**.

Testler: dar iki kural yazılınca var; profil yalnız Ortak (1) ya da Etki alanı (4) → yok; uzak adres tek IP, yerel port
8787, uzak port 9296, arayüz `Wireless`, servis adı dolu → her biri yok; kapalı kural, giden yön, arayüz kısıtlı, başka
program, yalnız TCP kuralı → yok.

### 11.3 "Ortak ağ" denetimi

Ağ listesi yöneticisi (COM, CLSID `DCB00C01-570F-4A9B-8D69-199FDBA5723B`) üzerinden bağlı ağlar gezilir; kategorisi 0
(Ortak) olan bağlı ağ varsa "ortak ağ var". Hata olursa "yok". Ağın kategorisi uygulama tarafından değiştirilmez.

### 11.4 Kuralı ekleme

- Uygulama kendini `--configure-local-firewall` argümanıyla, **runas** (UAC) fiiliyle, gizli pencereyle yeniden başlatır
  (kabuk komutu üretilmez; boşluk, `&`, `%` içeren yollar güvenli). Bekler; çıkış kodu 0 değilse başarısız. Sonra izin
  yeniden okunur; ancak "var" ise başarı. UAC reddedilirse ya da süreç açılamazsa başarısız.
- Yardımcı süreç (yönetici) şu sırayla yazar (ya hep ya başarısız):
  1. Yeni adlardan biri (`Nino - Local TCP/UDP`) bu exe'nin yönetilen kuralı olmayan bir kurala aitse (başka program,
     başka grup, başka yön/eylem) → **başarısız**, hiçbir şey yazılmaz (yabancı kuralın üstüne yazılmaz).
  2. Eski geniş kuralı içeren ad grubunda bu exe'ye ait olmayan kural da varsa → başarısız (adla silme yabancıyı da
     silebilirdi).
  3. Silinecek ad grupları: tamamı bu exe'ye ait, yönetilen kural içermeyen ve içinde eski geniş kural **ya da** bu
     exe'nin yerel engeli (gelen, engel, Özel profili içeren, bu exe, grupsuz, servissiz; ör. Windows'un ilk sorusu kapatıldığında oluşturduğu kural) olan gruplar; ayrıca tamamı önceki sürümün dar kuralı olan gruplar. Aynı adı
     başka program da kullanıyorsa o ad silinmez.
  4. Planlanan son durum (yönetilenler ve silinecekler çıkarılmış + iki yeni kural) izin denetiminden geçmezse (ör.
     genel bir engel var) → başarısız.
  5. İki kural yazılır: aynı adlı bu exe'nin kuralları varsa (program, grup, yön, eylem tutuyorsa) yerinde güncellenir;
     aynı adlı ama bunlardan biri tutmayan kural varsa hata; hiç yoksa eklenir.
  6. Yazılan iki kural birebir okunamıyorsa → başarısız (eski geniş izin, yazılamayan yeni kuralı maskelemesin; eski
     kural silinmeden kalır).
  7. Silinecek her ad için, ad listede kaldıkça (grup sayısı kadar) adla silme tekrarlanır.
  8. Sonuç: izin denetimi.
- Testlerden: eski geniş kural + kullanıcının özel kuralı → eski silinir, özel kalır, yeniden çalıştırmada kopya
  eklenmez (toplam 3 kural); kendi exe engeli izinle değiştirilir; yabancı kuralla aynı adı paylaşan engel korunur ve
  izin iddia edilmez; Ortak profil engeli korunur; genel engel sayılır, başka program/servis engeli sayılmaz; yazma
  başarısızsa eski izin bozulmadan kalır; sessizce başarısız yazma eski izinle maskelenmez; yönetilen ad çakışması
  (harf farkıyla da) yabancıyı ezmez; eski ad çakışması yabancıyı silmez; yeni kurulum yeni adları alır; önceki
  adlar sayılır, izin alınırken yeniden adlandırılır, eski uygulamanın kuralları kalır, başka programla paylaşılan
  önceki ad silinmez; güvenlik duvarı kapalıyken izin kuralı gerekmez ama eski geniş kuralın taşınması yine uygulanır.

### 11.5 Kaldırırken

Velopack kaldırma öncesi kancası: ad grupları gezilir; grubun **tamamı** bu exe'nin yönetilen (yeni ya da önceki adlı)
ya da eski geniş kuralıysa o adın bütün kuralları silinir. Başka programların ve kullanıcının özel kuralları korunur.
Yönetici izni yoksa ya da hata olursa sessizce geçilir (kaldırma durmaz).

### 11.6 Ne zaman önerilir (denetleyici)

- Kart durumları: yok, öner (düğme), çalışıyor (Windows'un izin sorusu bekleniyor), izin verildi (kısa onay),
  başarısız (düğme yeniden), ortak ağ (kural var ama ağ "Ortak"; düğme gösterilmez, ağın Özel yapılması önerilir).
- Ana ekran birkaç saniyede bir denetler: PS5 **20 sn**'dir bağlanamıyorsa (yalnız PS5 yolunda, Xbox değilse, akış
  yoksa ve neden PS5 kapalı / başka cihazda / reddetti / giriş şifresi / şifre yanlış / kayıt geçersiz / kodlu ret /
  Remote Play kapalı değilse) ya da TV **60 sn**'dir bağlanmadıysa (altyazı TV'ye gidiyor, TV eşli, bağlı TV yok):
  kart yoksa, bu oturumda kural daha önce bulunmadıysa ve denetim sürmüyorsa denetlenir: kural yoksa "öner", kural var
  ve ortak ağ varsa "ortak ağ", ikisi de değilse "bu oturumda kural bulundu" (bir daha taranmaz). İkisi de bağlanınca
  kart kalkar (çalışıyor durumu hariç). Çeviri durunca sıfırlanır.
- PS5 eşleştirmesi başarısız olunca da denetlenir; adım değişince kart kalkar.
- "İzin ver" düğmesi: çalışıyor → ekle → izin verildi/başarısız. Başarıda çeviri sürerken PS5'e ve TV'ye bağlanma hemen tekrarlanır.
- Ayarlar ekranı: güvenlik duvarı desteklenmiyorsa (Windows dışı) hiçbir şey; yoksa (kural var mı, ortak ağ var mı).
- Kural okunamazsa izin verilmiş gibi gösterilmez ("yok" sayılır).

---

## 12. Öbür Windows yetenekleri

### 12.1 Genel kısayollar

- Ana pencerenin tutamağına bağlı genel kısayol kaydı (RegisterHotKey); tekrar etmeme bayrağı (0x4000) + değiştiriciler.
  İleti: WM_HOTKEY (0x0312); yalnız kendi kaydettiği kimliklere tepki verir, iletiyi "işlendi" sayar.
- Kimlikler: tablo sırasındaki n'inci kısayol için **0x4353 + n** (0'dan). "Tuş boş mu" denemesi için kısa süre alınıp
  bırakılan kimlik **0x43FF**.
- Kısayollar **yalnız çeviri sürerken ve Ayarlar yeni tuş beklemiyorken** tutulur (çeviri kapalıyken sayı tuşları
  Excel gibi uygulamalarda normal çalışsın). Tablo ayarlardan her değişimde yeniden çözülür; tablo değişince tutuluyorsa
  bırakılıp yeniden alınır.
- Tutulamayan tuş (başka uygulama, ör. Windows'un dil kısayolu) sessizce atlanır; aynı işin öbür tuşu çalışır. Başarısız
  tuş listesi değiştiğinde bir kez `hata.log`'a tuşların başka uygulamada olduğunu söyleyen satır (+ etiketler) yazılır.
- Ayarlar'da tuş seçilirken Nino kendi kısayollarını bırakır; seçilen tuş alınamıyorsa başka uygulama tutuyordur
  ("meşgul" uyarısı).
- İş eşlemesi: ExtraRegion1..3 → o ek bölgeyi bir kez çevir; PauseSubtitles → altyazıyı duraklat/sürdür; Snapshot →
  ayar ekranı görüntüsünü yenile; FreeArea → serbest alan penceresi; Screen → ekranı çevir; ClickThrough → tıklamalar
  geçsin aç/kapat (ayar kaydedilir).

### 12.2 Uyku engeli

Uygulama iş parçacığı yürütme durumu (SetThreadExecutionState) sürekli bayrakla (0x80000000) her seferinde baştan
verilir:
- Çeviri başlayınca: sistem uykusu engellenir (0x1); "ekran da açık kalsın" istendiyse (görüntü bu bilgisayardaki bir pencereden alınıyor ya da altyazı bu ekranda çıkıyor) ekran (0x2) da. Çeviri sürerken yeniden çağrılıp ekran isteği açılıp
  kapanabilir.
- Oyun bu bilgisayarın ekranında oynanırken (yakalama kartı) ekran ayrıca açık tutulur (kullanıcı kolla oynar, bilgisayar
  dokunuş görmez).
- Ekran isteği varsa her zaman sistem uykusu da engellenir. Çeviri durunca yalnız sürekli bayrak kalır (engeller
  kalkar; yakalama kartının ekran isteği ayrıca sürüyorsa o kalır).

### 12.3 Tarayıcıda açma

Varsayılan tarayıcıda adres açılmadan hemen önce "her süreç öne gelebilir" izni verilir (AllowSetForegroundWindow, -1),
sonra kabukla açılır. Gerekçe: Windows, öndeki uygulama izin vermediğinde başka bir programın penceresini öne almaz; Samsung
giriş sayfası arkada açılıp görünmüyordu. Açılamazsa `hata.log`'a "Tarayıcı açılamadı" ve `tvinstall.log`'a adresle
birlikte neden yazılır; kart "sayfayı yeniden aç" ile bekler.

### 12.4 Tema

Sistem teması (`settings.appearance.system`): `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` altındaki `AppsUseLightTheme`
değeri 0 ise koyu, değilse (yoksa da) açık. Kullanıcı tercihleri "Genel" kategoride değişince yeniden okunur.

### 12.5 Cihaz bilgisi (kayıt defteri)

Bilgisayarın üreticisi ve modeli `HKLM\HARDWARE\DESCRIPTION\System\BIOS` altındaki `SystemManufacturer` ve
`SystemProductName`'den okunur (bilgisayar adı, kullanıcı adı, seri numarası okunmaz). Kurallar §13.3.

### 12.6 Platform yetenekleri özeti

| Yetenek | Ne için | Ayar |
|---|---|---|
| DPAPI (geçerli kullanıcı) | `secure.dat` | ek anahtar `nino-secure-store` (eski: LegacyNames) |
| Velopack | kurulum, güncelleme, kaldırma kancası | paket `NinoGameTranslator`, kanal `win`, GitHub, ön sürüm yok |
| WebView2 | PSN girişi, Xbox oynatıcı | profiller `webview\<rastgele>` (geçici), `xbox-webview` (kalıcı) |
| HNetCfg.FwPolicy2 / HNetCfg.FWRule (COM) | güvenlik duvarı okuma/yazma | §11 |
| Ağ listesi yöneticisi (COM) | ağ "Ortak" mı | §11.3 |
| UAC (runas) | kural yazan yardımcı süreç | `--configure-local-firewall` |
| RegisterHotKey / WM_HOTKEY | genel kısayollar | §12.1 |
| SetThreadExecutionState | uyku engeli | §12.2 |
| AllowSetForegroundWindow | tarayıcı öne gelsin | §12.3 |
| Kayıt defteri (HKCU tema, HKLM BIOS) | tema, cihaz modeli | §12.4–12.5 |
| Güç olayları (uykudan uyanma) | bağlantıları hemen yenile | ana pencere |
| Süreç listesi (aynı ad, aynı oturum, exe yolu) | veri klasörü taşıma kararı | §5.5 |

---

## 13. Çekirdekteki küçük veri bileşenleri

### 13.1 Çeviri önbelleği (`translations\*.jsonl`)

- Biçim Mac veri-uyumu §3.2 ile aynı: her satır iki öğeli JSON dizisi `["kaynak","çeviri"]` + `\n`, UTF-8 BOM'suz,
  sona eklenir; aynı anahtar birden çok geçebilir, sonuncusu geçerli. Windows yazarken ASCII dışını ve `" < > &`'yi
  `\uXXXX` kaçışıyla yazar (ör. `["Pull \"the\" <lever> &","Kolu çek."]`); okurken
  Mac'in kaçışsız satırlarını da okur.
- Dosya adı: motor, kaynak, hedefin **üçü de** yalnız küçük harf a–z, rakam ve `-`'den oluşuyorsa
  `v1-<motor>-<kaynak>-<hedef>.jsonl` ve her parçada harf/rakam/`_` dışı karakter `_` olur (ör. `opus-mt` →
  `v1-opus_mt-en-tr.jsonl`, `v1-opus_mt-en-ar.jsonl`). Değilse `v1h-<sha256>.jsonl`; özet `motor \0 kaynak \0 hedef`
  metninin UTF-8 SHA-256'sı, küçük harf onaltılık. Örnekler: `local:model.a`/en/tr →
  `v1h-6b5f11ab62999719865a030d1fb7f93bbcf1184290b58d4d603d1bee6c03249c.jsonl`; `gemini:gemini-3.5-flash-lite`/en/tr →
  `v1h-1aa82a53a8896bbdf8841c6a44e31bc0ec2a382935938bda14071a3444e0ca98.jsonl`. `local:qwen2.5:7b` ile
  `local:qwen2-5:7b`, `local:model.a` ile `local:model_a`, `opus-mt` ile `opus_mt` asla aynı dosyayı paylaşmaz.
  Biçim sürümü 1 (temizlik kuralları değişince artar).
- Motor kimlikleri (dosya adındaki motor): yerel Marian/CTranslate2 motorunun kimliği, `deepl`, `<hizmet>:<model>`,
  yerel model sunucusu için `local:<sunucu>/<model>` (ör. `local:localhost:11434/qwen2.5:7b`). Hedef dile göre ayrı
  dosya (Türkçe çeviri Arapçaya karışmaz).
- Aynı dosya için süreçte tek önbellek nesnesi (dosya yolu harf duyarsız eşlenir); dosya ilk kullanımda okunur.
- Bellekte en çok 20 000 kayıt (en az 1). Okuma: boş satır atlanır; bozuk JSON, iki öğeli olmayan ya da boş öğeli
  satır atlanır (sayılır ama kayıt olmaz). Kullanım sırası okunma sırasıdır.
- Sınır aşılınca en uzun süredir kullanılmayanlardan (aşım + sınırın onda biri) kadarı atılır. Okuma sonunda dosyadaki
  satır sayısı > kayıt + sınır/2 ise dosya bellektekilerle yeniden yazılır.
- Bulma kaydı "son kullanılan" yapar. Saklama: anahtar ya da değer boşsa hiçbir şey; aynı değer zaten varsa yalnız
  "kullanıldı" işaretlenir (dosyaya yazılmaz); değilse kayıt, gerekirse atma, dosyaya ekleme. Dosya satırı sınırın
  2 katına (40 000) ulaştıysa ekleme yerine bellektekilerle (en eski kullanılandan yeniye) yeniden yazılır:
  `<dosya>.tmp`'ye yazılıp üstüne taşınır.
- Disk hatası çeviriyi durdurmaz (önbellek yalnız bellekte çalışır). Dosyasız (yalnız bellek) kullanım da var.
- Testler: yeniden açılışta kalır; motorlar ayrı; tırnak ve satır sonu içeren satırlar gidip gelir; sınır 10'da s0
  yeniden kullanılınca s1 atılır, s0 ve s10 kalır; sınır 5 ile 6 tur × 5 kayıt sonrası dosya ≤ 10 satır ve son değer
  okunur; `["Row!","Kürek çek!"]`, `not json`, `["lonely"]` → yalnız Row!; boş değer saklanmaz, dosya oluşmaz.

### 13.2 Satır geçmişi (`history.json`)

- Biçim Mac ile **birebir**: `{"version":1,"entries":[{"id":0,"date":"2026-11-12T10:00:00Z","source":"Close the hatch!","translation":"Kapağı kapat!","origin":"pack"}]}`.
  Alan adları küçük harf; `origin` `pack` ya da `engine`; tarih UTC, saniyeye kadar, `Z` ile (kesirli saniye yazılmaz;
  Mac okuyucusu kabul etmez). Okurken her ISO-8601 biçimi kabul edilir ve UTC'ye çevrilir. Türkçe harfler kaçışsız
  yazılır.
- En yeni başta; en çok 200 satır; metin başına en çok 500 karakter (kaynak ve çeviri ayrı kırpılır).
- Ekleme: çeviri kırpılır, boşsa eklenmez. İlk kaydın kaynağı yenisine benzerse (okuma hattındaki satır benzerliği
  kuralı, normalize edilmiş metinlerle) yeni kayıt açılmaz, ilk kayıt (aynı kimlikle) yeni tarih/kaynak/çeviri/kökenle
  güncellenir. Değilse yeni kimlikle başa eklenir, sınır aşılırsa sondan atılır. Kimlik süreç içinde artar; dosyadan
  okununca en büyük kimlik + 1'den sürer.
- Bir andan sonrası (oturum başı) listelenebilir. Kopyalama metni: her kayıt `[SS:dd:ss] <çeviri>\n<kaynak>` (yerel
  saat), kayıtlar boş satırla ayrılır. Örnek (UTC+3): `[13:01:05] Kapağı kapat!\nClose the hatch!\n\n[13:00:00] Feneri yak\nLight the lantern`.
- Okuma: dosya yok/bozuk/tarih okunamaz (`"yesterday"`)/bilinmeyen köken (`"radio"`) → **boş geçmiş**. Kaynağı ya da
  çevirisi eksik kayıtlar atlanır; sınır kadarı alınır. Yazma: `.tmp`'ye yazıp üstüne taşıma; klasör yoksa oluşturulur.

### 13.3 Cihaz bilgisi

- Satırlar sırayla (sabit kimlik, çevrilmez; sunucuya bu gider): `app` (uygulama sürümü), `device` (model), `system`
  (işletim sistemi), `tv`, `console`, `status`. Değerlerde CRLF/CR/LF boşluk, `|` → `/`, kırpılır; boş değer satır olmaz.
- Özet: `id: değer` çiftleri ` | ` ile; en çok 600 karakter (fazlası kesilir). Örnek:
  `app: 0.2.1 | device: Acer Nitro 5 | system: Windows 11 (22631) | tv: Samsung QN90 / bağlı | console: PS5 / Remote Play`.
  İstek gövdesine konurken kırpılır, 600'e kesilir, boşsa alan hiç gönderilmez.
- Sistem adı: ana sürüm 10 ise yapı ≥ 22000 → "Windows 11", değilse "Windows 10"; başka ana sürümde
  "Windows <ana>.<alt>"; yapı > 0 ise ` (<yapı>)`. Örnek: 10.0.22631 → "Windows 11 (22631)", 10.0.19044 →
  "Windows 10 (19044)", 6.1.7601 → "Windows 6.1 (7601)". Windows dışında sistemin açıklaması.
- Model: üretici ve ürün temizlenir; yer tutucular model sayılmaz (harf duyarsız: "system manufacturer", "system
  product name", "to be filled by o.e.m.", "to be filled by oem", "default string", "not applicable", "not specified",
  "none", "unknown", "o.e.m.", "oem"). İkisi de yoksa "Windows PC"; biri yoksa öbürü; ürün üreticinin adıyla
  başlıyorsa (harf duyarsız) yalnız ürün, değilse "üretici ürün". Örnekler: "Dell Inc." + "XPS 13" → "Dell Inc. XPS 13"; Acer +
  "Acer Nitro 5" → "Acer Nitro 5"; "Gigabyte Technology" + yer tutucu ürün → yalnız üretici; yer tutucu üretici + yer
  tutucu ürün → "Windows PC"; null + null → "Windows PC". Okunamazsa ya da
  Windows dışında "Windows PC".

### 13.4 Toplam indirme sayacı (`pool-translations\downloads.txt`)

- Sunucunun `GET /v1/config` cevabındaki `downloads` alanı (havuz ayarı zaten soruyor; ayrı istek yok). Ana ekran en çok
  600 sn'de bir yeniler.
- Ayrıştırma: kök nesne, `downloads` sayı ve > 0; tam sayı değilse kesirsiz ondalık da (3439.0) kabul; kesirli, taşan,
  0, negatif, dizge, dizi, bozuk, boş → yok. Örnekler: `{"ok":true,"downloads":3439}` → 3439; `{"ok":true}`,
  `{"downloads":0}`, `bozuk`, `{"downloads":"3439"}`, `{"downloads":-5}`, `{"downloads":12.5}`, `[3439]`, boş → yok.
- Sayı değiştiyse dosyaya düz sayı olarak (`3502`) `.tmp` + taşıma ile yazılır. Açılışta dosyadan okunur (yalnız
  rakam, > 0; bozuk/yok → gösterge görünmez). İnternet yoksa son bilinen sayı gösterilir; üstüne ekleme yapılmaz.
- Biçim: yerel binlik ayırıcı ("3.439" tr, "3,439" en, "999").

---

## 14. Eksik ya da emin olunmayan noktalar

- Eski kodda "asıl uygulamanın" Velopack kurulum klasörü adı düz yazı `NinoApp` olarak duruyor. Ad temizliği sırasında
  değişmiş olabilir (asıl değer büyük olasılıkla eski adla kurulmuş bir kimlik). Yeni uygulamada bu ad `LegacyNames`'e
  (kodlu) taşınmalı; doğru değeri ana oturum doğrulamalı.
- Samsung'da "önceki sürümün cihaz adı" da bugün `Nino`; eskiden eski ad olabilir. Davranış bugünkü haliyle yazıldı.
- Velopack kanalı kodda açıkça verilmiyor; `win` Velopack'in varsayılanı ve dosya adlarından çıkarıldı.
- `release.yml`'deki toplu yayın işi kapalı; Windows dosyaları elle (`gh release create`) yükleniyor. Paket adları
  §2'deki gibi.
- Ayar dosyasında tek bozuk alanın bütün dosyayı sıfırlaması eski davranış; yeni uygulamanın alan alan hoşgörülü okuması
  önerildi (§ayarlar-modeli 2.3). Hangisinin seçileceği ana oturumun kararı.
- Güvenlik duvarı kurallarının Windows tarafı (COM ile okuma ayrıntıları, yönetici süreci) Mac'te sınanamaz; yalnız kural
  mantığı (§11.2, §11.4) testle sınanır.

---

## 15. Eski uygulamayla uyum doğrulaması (22 Kasım)

Yöntem: depodaki eski Windows kodunu (`windows/src`, yalnız Mac'te derlenen net10.0 projeleri; `secure.dat` yazıcısı
DPAPI yerine şeffaf koruyucuyla) çağıran ayrı bir deneme programı, eski kodun kendi yazım yollarıyla örnek dosyalar ve
8787 kablo baytları üretti; yeni kodun yazdığı dosyaları da eski kodla okuyup sonucu kaydetti. Eski koddan satır
alınmadı; yalnız çıktılar fikstür oldu: `apps/windows/tests/Nino.Core.Tests/Fixtures/Compat/old` (eski çıktı) ve
`…/Compat/new` (yeni kodun yazdığı + `oldread.json`: eski kodun onlarda gördüğü). Testler
`apps/windows/tests/Nino.Core.Tests/Compat/`. Fikstürler `.gitattributes`'ta `-text` (CRLF ve son satır sonu korunur).
`NINO_COMPAT_EXPORT=<klasör>` ile testler yeni kodun yazdıklarını oraya kopyalar (eski koda yeniden okutmak için).

Karşılaştırılanlar ve sonuç:

| Dosya / akış | Eski → yeni okuma | Yeni yazım |
|---|---|---|
| `settings.json` (dolu, varsayılan, eski sürüm, ek alanlı + sayısal enum) | aynı değerler | bayt bayt aynı |
| `secure.dat` içi JSON (bütün anahtarlar, `WakeCredential`, tarih `+00:00`) | aynı değerler | bayt bayt aynı; tek `Set` öbür baytlara dokunmaz |
| `history.json` | aynı | bayt bayt aynı |
| `translations\v1-*.jsonl` (+ 7 dosya adı) | aynı | bayt bayt aynı |
| `sorunlar.json` | aynı | **düzeltildi**, artık aynı |
| `otomatik-bildirim.json` | aynı (bekleyen, gün sayacı) | **düzeltildi**, artık aynı |
| `downloads.txt`, `auto-update-tried.txt`, `report-install.txt` | aynı | bayt bayt aynı |
| `pool\` (`state.json`, `pending.jsonl`, `outbox\`) | kuyruk sürer (kimlik, sıra no, parça) | alanlar ve değerler aynı; eski kod okur (kimlikler rastgele: bayt karşılaştırılmaz) |
| 8787 `/events` (her olay, geç bağlanma, OBS, kapı), `/hello`, 404, `OPTIONS`, ping | — | **düzeltildi**, `at` dışında bayt bayt aynı |
| `/obs` | — | başlıklar aynı; sayfa yeni (karşılaştırılmaz) |

Bulunan ve düzeltilen uyuşmazlıklar:
- 8787 dizge kaçışı ve `angle`/`alpha` yuvarlaması, boş `fill`/`ink` (ayrıntı: `tv-baglanti.md` §4.1–4.2).
- `sorunlar.json`: tarih `+00:00` ile yazılıyordu (eski `Z`), hesaplanan Türkçe ad dosyaya giriyordu
  (`saglik-bildirim-sor.md` §2).
- `otomatik-bildirim.json`: bekleyen gövde kaçışsız yazılıyordu (eski varsayılan kaçış; §6.3).

Bilerek farklı kalanlar (tarif böyle istiyor): bozuk `settings.json`/`secure.dat` üstüne yazmadan önce kenara alınır;
tanımsız enum sayıları varsayılana çevrilir; `secure.dat`'ta `WakeCredential` okunurken yok sayılır. Bu yolda
denenmeyenler: gerçek DPAPI şifrelemesi (yalnız Windows'ta), `pool.json` (eski satır havuzu) aktarımı,
`pool-translations\`, `packs-remote.json`, `kopyalandi.txt`, `parked\`/`rejected.jsonl`. Windows'ta
`subtitle-layout.json` (altyazı yeri) dosyası yoktur (§6); karşılaştırılacak bir şey yok.
