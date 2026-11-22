# Windows: Ayarlar penceresi (tarif)

Bu belge Windows uygulamasındaki **Ayarlar** penceresinin görünüşünü ve davranışını anlatır; kod yoktur. Yeni yazan
kişi yalnız bu belgeyle pencereyi bölüm bölüm yeniden çizebilmelidir. Ayarlar'dan açılan yan pencereler (Hakkında,
`settings.about.reportProblem`, Nino'ya Sor, Oyun paketi içe aktarma, capture card rehberi) ve Ayarlar içindeki `settings.section.systemHealth` sayfası
`yan-pencereler.md`'dedir.

Mac karşılığı: `git show claude/yeni-mac-c9961f:docs/yeni/mac/ayarlar.md`. **Windows'un düzeni Mac'ten farklıdır**:
Mac'te liste → bölüm sayfası (iPhone Ayarları gibi) gezintisi var; Windows'ta solda sabit kenar çubuğu, sağda seçili
bölüm vardır. Windows'ta gizli bölüm yoktur (Arayüz, Dil, oyun paketleri, altyazı alanı görünür), altyazı görünümünde
canlı önizleme ve tema kartları **yoktur**, ayrıca Windows'a özgü Kısayollar, görüntü kaynağı ve Güvenlik Duvarı
bölümleri/kartları vardır.

## 0. Ortak kurallar

### Metinler
- Anahtar metnin İngilizcesidir (Mac'in yerelleştirme dosyası + Windows'a özgü ek dosya). Tablolarda "EN" sütunu
  anlamı verir, "TR" sütunu Türkçe anlamı. Kelimesi kelimesine kopyalamak gerekmez; anlam aynı kalmalıdır.
- `%@`, `%lld`, `%d`, `%1$@` yer tutuculardır. "verbatim" yazanlar çevrilmez.
- Kısayol geçen metinler kullanıcının seçtiği tuşlarla doldurulur (bkz. §9.4 "kısayol metni").

### Görsel dil (adlar `tasarim-dili` belgesindeki tokenlardır; burada görünüşleriyle)
- Pencere zemini = `background` rengi (koyu `#050A1A`, açık `#EEF3FB`). Ana yazı rengi `textPrimary`
  (koyu `#F2F5FB`, açık `#0A1430`), ikincil `textSecondary` (koyu `#9DA9C6`, açık `#55607A`).
- **Kart**: zemin `surface` (koyu `#0E1733`, açık `#FFFFFF`), 1 px `tileBorder` kenar (koyu `#22305A`, açık `#DCE5F3`),
  köşe 22, iç boşluk 16. Başlığı varsa en üstte başlık yazısı (17, yarı kalın, satır yüksekliği 22), altında 12 boşluk.
  "Etkin" türünde kenar `accent` olur.
- **Bölüm başlığı (büyük)**: 28, yarı kalın, ekran yazı tipi (Segoe UI Variable Display), satır 34.
- **Pencere başlığı (orta)**: 22, yarı kalın, ekran yazı tipi, satır 28.
- **Gövde**: 15 normal, Segoe UI Variable Text, satır 20. **İpucu**: 13 orta kalınlık, `textSecondary`, satır 17.
  **Küçük yazı (caption)**: 13 orta, `textSecondary`, satır 16. **Hata yazısı**: ipucu boyunda, `warning` rengi
  (koyu `#F5AE62`, açık `#9A4A08`). **Tamam yazısı**: gövde, yarı kalın, `success` rengi (koyu `#5FD39A`, açık `#1E6B45`).
  **Başlık yazısı (headline)**: 17 yarı kalın.
- **Düğmeler** (köşe 14, en az 40 yükseklik, yatay iç boşluk 20, yazı 15 yarı kalın, el imleci, gölge yok):
  - birincil: düz `accent` zemin (koyu `#2D8CFF`, açık `#0070D1`), beyaz yazı, basılıyken `accentHi`;
  - ikincil (varsayılan düğme): `surface2` zemin (koyu `#16224A`, açık `#E6EDF8`), 1 px `border` kenar
    (koyu `#2A3A68`, açık `#D3DEEF`), ana yazı rengi;
  - hayalet: saydam, `accentText` yazı (koyu `#7DB8FF`, açık `#0058A8`), yatay iç boşluk 12.
  - Düğmeler kendiliğinden **sola yaslıdır** (yatayda yayılmaz).
- **Anahtar (toggle)**: 52×32 hap; kapalıyken `border` renkli iz ve ana yazı renginde 24'lük topuz solda; açıkken iz
  `accent`, topuz beyaz ve sağda. Yazısı varsa izin sağında 12 boşlukla. Klavye odağında izin kenarı `accentText`.
  Pasifken %40 saydam. (Windows'ta bütün "onay kutuları" bu anahtar görünümündedir.)
- **Bölmeli seçici (segment)**: dış kutu `surface2` zemin, köşe 14, iç boşluk 2; her parça en az 36 yükseklik, iç kutu
  köşe 10, iç boşluk 12×6, yazı 15 orta kalınlık `textSecondary`; seçiliyken parçanın zemini `border` rengi, yazı ana
  renk ve yarı kalın; klavye odağında 1 px `accentText` kenar. Dar sütunda yazı iki satıra iner (kesilmez).
- **Açılır liste**: `surface2` alan, 1 px `border`, köşe 14; açılan liste `surface` zeminli.
- **Kaydırıcı**: tıklanan yere atlar (fareyle basılan nokta değer olur).
- **Hap**: 24 yükseklik, yatay iç boşluk 8, köşe 6, `surface2` zemin, caption yazısı `textSecondary`.

### Açık / koyu tema
Bütün renkler tokenlardan gelir ve görünüm değişince **anında** yenilenir (pencere kapanıp açılmadan). Sabit kodlu
(temadan bağımsız) renkler ayrıca yazılmıştır (ör. Arayüz önizlemeleri, bölge çerçevesinin dolgusu).

### Sağdan sola (arayüz Arapça)
Arayüz dili sağdan sola ise her pencere yüklenirken, kendi yönü açıkça verilmemişse sağdan sola yapılır: kenar çubuğu
sağa geçer, ızgaralar aynalanır, metinler sağa yaslanır. Aynalanmaması gerekenler (oyun görüntüsü önizlemesi ve bölge
çerçevesi, dil bayrağı satırları, capture card önizleme çerçevesi) soldan sağa tutulur.

### "Yükleniyor" kuralı
Pencere açılırken denetimler kayıtlı ayarlarla doldurulur; bu sırada denetimlerin değişme olayları **ayar yazmaz**.
Kodun bir denetimi kendisi değiştirdiği her yerde de (ör. bir anahtarı kapatmak, listeyi yeniden doldurmak) aynı
"yükleniyor" bayrağı geçici olarak açılır, sonra eski hâline döner.

### Ayar yazılınca ne olur (her bölüm için geçerli)
Denetimlerin hemen hepsi kullanıcı ayarını **anında** değiştirir; "Kaydet" düğmesi yoktur. Ayar nesnesinin tamamı
yenisiyle değiştirilir ve denetleyici şunları yapar (sıra önemli):

1. CPU iş parçacığı sayısı geçerli seçeneğe çekilir (§4.4).
2. **İki görüntü kaynağı tek seçim gibi davranır:** `settings.source.readFrom` (§10, `FrameSource`) PS5 dışı bir değere
   değiştiyse ve `settings.connection.gamePictureFrom` (§2, `VideoSource`) PS5 değilse, `VideoSource` PS5'e döner. Tersine `VideoSource`
   PS5 dışına değiştiyse ve `FrameSource` PS5 değilse, `FrameSource` PS5'e döner.
3. `VideoSource` PS5'e döndüyse ve `FrameSource` da PS5 ise, altyazı yeri (`Output`) TV değilse TV olur.
4. Değer gerçekten değişmediyse hiçbir şey yapılmaz. Değiştiyse: ayar dosyasına yazılır; **altyazı görünümü TV'ye
   hemen gönderilir** (her ayar değişikliğinde, görünüm değişmese de).
5. `Output` değiştiyse: TV'ye gönderim açılır/kapanır; altyazı artık bilgisayarda gösterilmiyorsa bilgisayardaki altyazı
   penceresinin ayar kipi kapanır ve penceredeki her şey hemen gizlenir; çeviri sürüyorsa ekranın uyku ayarı yeniden
   değerlendirilir, TV'ye gidiyorsa TV bağlantı bekçisi başlar, gitmiyorsa durur.
6. Kart yolunda çeviri sürerken yalnız `Output` değiştiyse çeviri durdurulup yeniden başlatılır.
7. `VideoSource` değiştiyse: 5. madde yeniden uygulanır; çeviri sürüyorsa durdurulup yeni kaynakla başlatılır.
8. Çeviri dili değiştiyse çeviri havuzu o dile geçer. Paket ayarı açıldı/kapandıysa ve hat varsa paketler yeniden
   bağlanır. Konuşan adı ayarı hatta hemen geçer. Bekleme süreleri (§4.6) değiştiyse hatta hemen uygulanır.
9. Ortak havuz ayarı değiştiyse havuz gönderimi ve çeviri havuzu açılır/kapanır; hat varsa paketler yeniden bağlanır ve
   çeviri eşitlemesi yeniden başlar.
10. Çeviri aygıtı değiştiyse "GPU kullanılamadı" uyarısı silinir ve aygıt değiştirilir. İş parçacığı sayısı değiştiyse
    çevirmene bildirilir.
11. Ek bölge gözcüsü yeniden kurulur (§7).
12. Çeviri sürerken görüntü kaynağı, (pencerede) Remote Play uygulaması, (OBS/pencere kaynağında) seçili pencere ya da
    (Xbox'ta) eski kare hızı değiştiyse çeviri durdurulup yeniden başlatılır.
13. Motor, model, yerel sunucu adresi/model adı, çeviri aygıtı ya da iş parçacığı değiştiyse, ya da oyun/çeviri dili
    değiştiyse: çeviri durmuşsa çevirmen durumu yenilenir; çeviri sürüyorsa (bunlara ek olarak "değişmeyen alanı daha
    sık oku" değiştiyse de) çevirmen durumu yenilenir ve çeviri hattı yeniden kurulur (çeviri durmaz).

---

## 1. Pencere

- Başlık: `common.settings`. Boyut **1000 × 720**, en küçük **860 × 560**, boyutlanabilir, görev çubuğunda
  görünmez, sahibinin (ana pencere) ortasında açılır.
- Açılış: ana ekrandaki dişli düğmesi. **Tek pencere kuralı** (Ayarlar, Geçmiş, Hakkında, `settings.about.reportProblem`, Nino'ya Sor
  için aynı): aynı türden görünür bir pencere zaten açıksa yenisi açılmaz; küçültülmüşse normale döner ve öne getirilir.
  Değilse yeni pencere sahibine bağlanır ve **kalıcı olmayan** (sahibini kilitlemeyen) biçimde gösterilir. Bağlı olduğu pencere kapanınca o da kapanır.
- Açılışta seçili bölüm: listenin ilki (**Arayüz**). Belirli bir bölümde açma yolu yoktur.
- Düzen: dört yandan 24 iç boşluk; iki satır.
  - Üst satır (esnek): **kenar çubuğu + içerik**.
  - Alt satır: sağa yaslı birincil `common.done` düğmesi (üstten 16 boşluk, en az 120 genişlik). Bitti hem
    varsayılan hem vazgeç düğmesidir: **Enter** ve **Esc** pencereyi kapatır (kısayol kaydı sırasında hariç, §8).
- **Kenar çubuğu**: solda 240 genişlikte, boyu boyunca uzayan bir kart; kartın iç boşluğu yatay 12, dikey 20. İçinde
  en üstte pencere başlığı yazısıyla `common.settings` (iki yandan 12, altta 12 boşluk), altında dikey kaydırılabilir
  bölüm listesi (bölümler sığmayınca — 125–150 % ölçekte — sondakiler kesilmesin diye).
  - Bölüm satırı: en az 40 yükseklik, yatay iç boşluk 12, alt 4 boşluk, köşe 14, saydam zemin ve saydam 1 px kenar;
    yazı 15, `textSecondary`. Fare üstündeyken zemin `surface2`. Seçiliyken zemin `surface2`, yazı ana renk ve yarı
    kalın. Klavye odağında kenar `accentText`.
  - Klavye: Sekme tuşu listeye bir kez girer; listede ok tuşları döngüsel gezer.
- **İçerik alanı**: kenar çubuğunun sağında 16 boşlukla, dikey kaydırılabilir (gerekirse); içerik sağda 12 boşluk
  bırakır. Her bölüm yukarıdan aşağı: büyük bölüm başlığı (altta 16 boşluk), sonra kartlar (kartlar arası 16).

**Bölüm sırası** (kenar çubuğunda yukarıdan aşağı):

| # | Metin anahtarı | Ne zaman görünür |
|---|---|---|
| 1 | `settings.section.interface` | her zaman |
| 2 | `settings.section.connection` | her zaman |
| 3 | `settings.section.subtitleAppearance` | her zaman |
| 4 | `home.footer.translation` | her zaman |
| 5 | `pack.settings.title` | her zaman |
| 6 | `settings.section.language` | her zaman (kartının görünürlüğüne bağlı; kart hiç gizlenmez) |
| 7 | `settings.section.subtitleArea` | her zaman |
| 8 | `settings.section.shortcuts` | her zaman |
| 9 | `settings.section.obs` | her zaman |
| 10 | `settings.section.pictureSource` | her zaman (içi konsola göre değişir) |
| 11 | `settings.section.passcode` | yalnız konsol türü PlayStation iken (Xbox'ta gizli) |
| 12 | `settings.section.systemHealth` | her zaman |
| 13 | `settings.section.about` | her zaman |
| 14 | `common.reset` | her zaman |

Pencere açıkken denetleyicinin "ayarlar", "TV'ye gidiyor", "bilgisayarda gösteriliyor", "son kare" ve "kurulu
paketler" değişikliklerini dinler (aşağıda yeri geldikçe); kapanınca dinlemeyi bırakır.

---

## 2. Arayüz

### 2.1 `settings.home.title` kartı (başlıklı)
İki eşit sütun, iki büyük düğme (ikincil düğme görünümü; iç boşluk 10; içerik yatayda yayılır). Soldakinin sağında 8,
sağdakinin solunda 8 boşluk.

Her düğmenin içi yukarıdan aşağı:
1. 130 yüksekliğinde önizleme kutusu: zemin sabit lacivert `#0A1433`, köşe 10.
   - **Salon**: içinde 12 iç boşlukla salon sahnesinin resmi (oran korunarak sığdırılır, yüksek kaliteli ölçekleme).
   - `settings.home.toggle.name`: ortada 150×40 bir hap (köşe 20, dolgu `#5C6E99`), üstünde solda 50×50 bir daire (dolgu `#5C6E99`,
     1.5 kalınlıkta %80 beyaz kenar; hapın sol kenarından 5 dışarı taşar, üstten ve alttan 5 taşar).
2. Ad (yarı kalın, üstte 8 boşluk).
3. Açıklama (küçük yazı, satır kaydırmalı).

| Değer | Ad (metin anahtarı) | Açıklama (metin anahtarı) |
|---|---|---|
| `LivingRoom` | `settings.home.livingRoom.name` | `home.livingRoom.tooltip` |
| `Toggle` | `settings.home.toggle.name` | `settings.home.toggle.description` |

- Seçili olanın kenarı **2 px `accent`**, diğerinin **1 px `border`**.
- Basınca ayar alanı `HomeStyle` yazılır (`"LivingRoom"` ya da `"Toggle"`; varsayılan `LivingRoom`) ve kenarlar
  yenilenir; ana ekran yeni arayüze geçer.

### 2.2 Görünüm kartı (başlıksız)
Yatay sıra: `settings.appearance.label` yazısı (sağda 16 boşluk) + açılır liste (en az 200 genişlik):

| Değer | Metin anahtarı |
|---|---|
| `Dark` | `settings.appearance.dark` |
| `Light` | `settings.appearance.light` |
| `System` | `settings.appearance.system` |

- Ayar alanı `Appearance` (varsayılan `System`; eski ayar dosyalarında alan yoksa da `System`).
- Seçim **anında** uygulanır: bütün açık pencerelerin renkleri değişir. `settings.appearance.system` seçiliyken Windows'un uygulama teması
  okunur (kişiselleştirme kayıt defterindeki "uygulamalar açık tema kullanır" değeri 0 ise koyu) ve Windows teması
  değişince uygulama da kendiliğinden değişir. Aynı görünüm ikinci kez uygulanmaz.

---

## 3. Bağlantı

Yalnız bir kart: **altyazı çıkışı kartı**, *ayrıntılı* hâliyle. Aynı kart ana ekranda da kullanılır (orada açıklamalar
kısa kalır, capture card önizlemesi yoktur). Kart görsel ağaca girince denetleyiciyi dinlemeye başlar, çıkınca bırakır;
"ayarlar", "altyazı penceresi ayar kipinde" ve "çeviri sürüyor" değişince kendini baştan çizer.

Kartın içi yukarıdan aşağı:

1. Küçük yazı `settings.connection.console` (altta 8), altında yatayda yayılan bölmeli seçici (altta 12): **PS5** | **Xbox**
   (verbatim, eşit genişlikte).
   - Seçili olan: ayar `GameConsole` (`Ps5`/`Xbox`).
   - Basınca: aynı konsolsa hiçbir şey; Xbox'a geçilirken `VideoSource` PS5 ise `Window` yapılır (Xbox'a doğrudan
     bağlanma yok; capture card seçiliyse o kalır). İkisi birlikte tek ayar yazımıyla değişir.
2. Küçük yazı `settings.connection.gamePictureFrom` (altta 8), yatayda yayılan seçici (altta 12):
   **PS5** (Xbox'ta gizli) | `settings.connection.source.remotePlayWindow` (Xbox'ta `settings.connection.source.xboxWindow`) |
   `cardGuide.preview.deviceLabel`.
   - Seçili olan: oyun penceresi kullanılıyorsa pencere, capture card kullanılıyorsa capture card, yoksa PS5.
   - Basınca ayar `VideoSource` (`Ps5` / `Window` / `Card`) yazılır (bkz. §0 kuralları 2, 3, 7).
3. Kaynak ipucu (ipucu yazısı, altta 12). Ayarlar'da her zaman görünür (ana ekranda yalnız pencere ya da PS5 iken):

   | Durum | Metin anahtarı |
   |---|---|
   | `cardGuide.preview.deviceLabel` | `settings.connection.hint.captureCard` |
   | PS5 | `settings.connection.hint.ps5` |
   | `settings.connection.source.xboxWindow` | `setup.welcome.shortcutXboxTooltip` |
   | `settings.connection.source.remotePlayWindow` | `settings.connection.hint.remotePlayWindow` |

   Windows'ta Xbox metninde üçüncü taraf istemci adı geçmez (Mac'tekinden farklı).
4. **Yalnız capture card seçiliyken**: küçük yazı `settings.connection.showSubtitlesOn` (altta 8) ve yayılan
   seçici **TV** | `settings.connection.output.computer` | `reading.target.both` → ayar `Output` (`Tv`/`Computer`/`Both`).
   PS5 yolunda altyazıyı daima TV uygulaması gösterir, oyun penceresi yolunda her zaman bilgisayardadır; bu yüzden seçim
   yalnız capture card'da gösterilir.
5. **Kart bölmesi** (üstte 12; yalnız capture card seçiliyken):
   - Düzen ipucu (ipucu, altta 12): altyazı TV'ye gidiyorsa `settings.connection.cardLayout.tv`, değilse `settings.connection.cardLayout.computer`.
   - **Canlı önizleme** (altta 12): yalnız ayrıntılı kartta ve **çeviri sürmüyorken**; 170 yüksekliğinde capture card
     denetimi (`yan-pencereler.md` §8.1). Çeviri başlayınca önizleme kaldırılır (kart aynı anda tek okuyucuya açılır).
   - `cardGuide.window.title` düğmesi (ikincil, yatay iç boşluk 16): solda 16 boyunda simge (Segoe
     Fluent "liste" simgesi U+E8FD), 8 boşluk, yazı. Fare üstündeyken ipucu `settings.connection.connectionGuide.tooltip`.
     Çeviri sürerken basılamaz. Basınca önce bu kartın önizlemesi kaldırılır, sonra rehber penceresi **kalıcı
     (modal)** açılır (`yan-pencereler.md` §8.3); kapanınca kart yeniden çizilir.
6. **Bilgisayar bölmesi** (üstte 12; altyazı bilgisayarda gösteriliyorsa):
   - Ayrıntılı kartta ipucu (altta 12): `settings.connection.computerHint`
   - Yan yana (dar yerde alt alta kayar): anahtar `settings.connection.clickThrough` (sağda 16, altta 8) →
     ayar `OverlayClickThrough` (varsayılan kapalı); ikincil düğme `settings.connection.adjustSubtitleWindow` (yatay iç boşluk 16, altta 8) → altyazı penceresi ayar kipine girer (`yan-pencereler.md` §5.6). Ayar
     kipindeyken düğme soluk.
   - Tıklama ipucu (ayrıntılı kartta ya da anahtar açıkken): kısayol cümlesi `settings.connection.clickThroughHint` —
     %@ = `shortcut.action.clickThrough` işinin tuşları (varsayılan "Num 7 ya da Ctrl+Shift+7").

"Bilgisayarda gösteriliyor" ve "TV'ye gidiyor" koşulları (Windows):
- **TV'ye gidiyor** = (oyun penceresi kullanılmıyor **ya da** Xbox penceresi kullanılıyor) **ve** `Output` ≠ `Computer`.
- **Bilgisayarda gösteriliyor** = (oyun penceresi kullanılıyor **ve** Xbox penceresi değil) **ya da** `Output` ≠ `Tv`.

Varsayılanlar: konsol PS5, `VideoSource` PS5, `Output` TV, tıklamalar geçsin kapalı. Kayıtlı ayarda `Output` = `Both`
ise açılışta TV'ye çevrilir; `Computer` ("TV'm yok") olduğu gibi kalır (test: eski `reading.target.both` → TV, "Bilgisayar" kalır,
yeni ayar TV).

---

## 4. `settings.section.subtitleAppearance`

### 4.1 Görünüm kartı
Kartın başlığı **doğrudan ayara bakar**: `Output` = `Tv` ise `settings.area.target.tv`, değilse `settings.section.subtitleAppearance`. Başlık, ayarlar ya da TV/bilgisayar koşulları değişince yenilenir. Ayar alanlarının hepsi `Style`
nesnesinin içindedir.

Satırlar yukarıdan aşağı (boşluklar satırın altındaki boşluktur):

| # | Satır | Denetim | Aralık / seçenekler | Varsayılan | Alan | Görünme koşulu |
|---|---|---|---|---|---|---|
| 1 | `settings.subtitle.autoSize` | anahtar (alt 4) | — | açık* | `AutoSize` | her zaman |
| 1a | ipucu (alt 12) | — | — | — | — | her zaman |
| 2 | `settings.subtitle.textSize.label` (alt 8) | kaydırıcı satırı (alt 16) | **16…90**, adım 1, tam sayıya oturur; küçük adım 1, büyük adım 4 | 46 | `FontSize` | her zaman |
| 3 | `settings.subtitle.placement.label` (alt 8) | açılır liste (alt 8) | Cover · Above · Below · Fixed | Cover | `Placement` | altyazı TV'ye gidiyorsa |
| 3a | ipucu "çeviri oyunun altyazısını izler" (alt 16) | — | — | — | — | TV'ye gidiyor ve Sabit değilse |
| 3b | `settings.subtitle.position.label` (alt 8) + kaydırıcı satırı + ipucu (üst 12, alt 16) | kaydırıcı | **0…85** (tam sayıya yuvarlanır, oturma yok) | 7 | `BottomPercent` | TV'ye gidiyor ve Sabit ise |
| 4 | bilgisayar ipucu + `settings.connection.adjustSubtitleWindow` (bölme altı 16) | ipucu + ikincil düğme (üst 8) | — | — | — | altyazı bilgisayarda gösteriliyorsa |
| 5 | `settings.subtitle.background.label` (alt 8) | kaydırıcı satırı (alt 16) | 0…100 (tam sayıya yuvarlanır) | 100 | `Background` | her zaman |
| 6 | `settings.subtitle.backgroundShape.label` (alt 8) | açılır liste (alt 8) + ipucu (alt 16) | Fit · Band | Fit | `BackgroundShape` | her zaman |
| 7 | `settings.subtitle.bold` | anahtar (alt 16) | — | kapalı | `Bold` | her zaman |
| 8 | `settings.subtitle.stackPrevious` | anahtar (alt 4) + ipucu (alt 16) | — | açık | `StackPrevious` | her zaman |
| 9 | `settings.subtitle.font.label` (alt 8) | açılır liste (alt 16) | Condensed · Modern · Rounded · System | Condensed | `Font` | her zaman |
| 10 | `settings.subtitle.textColor.label` (alt 8) | açılır liste (alt 16) | White · Yellow | White | `TextColor` | her zaman |
| 11 | `settings.subtitle.displayMode.label` (alt 8) | açılır liste (alt 8) + ipucu (alt 16) | InApp · Overlay | InApp | `DisplayMode` | TV'ye gidiyor **ve** kayıtlı TV'nin markası Android TV ise |
| 12 | `settings.subtitle.watermark` | anahtar (alt 4) + ipucu (alt 16) | — | açık | `Watermark` | her zaman |
| 13 | `setup.try.sendSample` | ikincil düğme | — | — | — | her zaman |

\* `AutoSize` ayarda üç durumludur (yok / açık / kapalı). Alan **yoksa** (eski kayıt) "uydur" açık sayılır **yalnız**
yazı boyu varsayılan 46 ise; başka boy kaydedilmişse kapalı sayılır.

**Kaydırıcı satırı**: dört sütun: sol uç yazısı (ipucu, dikeyde ortalı) | kaydırıcı (iki yandan 12 boşluk, esnek) |
sağ uç yazısı (ipucu) | (yalnız yazı boyunda) 40 genişliğinde sağa yaslı değer yazısı (tam sayı). Uç yazıları:
yazı boyunda `settings.subtitle.textSize.small`–`settings.subtitle.textSize.large`, konumda alt–üst
(`reading.areaPreset.bottom`–`reading.areaPreset.top`), arka planda `common.none`–`settings.subtitle.background.solid`.

Seçenek metinleri:

| Alan değeri | Metin anahtarı |
|---|---|
| Placement `Cover` | `settings.subtitle.placement.cover` |
| `Above` | `settings.subtitle.placement.above` |
| `Below` | `settings.subtitle.placement.below` |
| `Fixed` | `settings.subtitle.placement.fixed` |
| BackgroundShape `Fit` | `settings.subtitle.backgroundShape.fit` |
| `Band` | `settings.subtitle.backgroundShape.band` |
| Font `Condensed` | `settings.subtitle.font.condensed` |
| `Modern` | `settings.subtitle.font.modern` |
| `Rounded` | `settings.subtitle.font.rounded` |
| `System` | `settings.subtitle.font.system` |
| TextColor `White` / `Yellow` | `settings.subtitle.textColor.white` / `settings.subtitle.textColor.yellow` |
| DisplayMode `InApp` | `settings.subtitle.displayMode.inApp` |
| `Overlay` | `settings.subtitle.displayMode.overlay` |

İpuçlarının anlamı:

| Yer | Metin anahtarı |
|---|---|
| 1a | `settings.subtitle.autoSizeHint` |
| 3a | `settings.subtitle.placementFollowsHint` |
| 3b | `settings.subtitle.positionHint` |
| 4 | `settings.connection.adjustSubtitleWindow` düğmesine yönlendiren kısa açıklama (bilgisayarda pencere sürüklenerek taşınır) |
| 6 | `settings.subtitle.backgroundShapeHint` |
| 8 | `settings.subtitle.stackPreviousHint` |
| 11 | `settings.subtitle.displayModeHint` |
| 12 | `settings.subtitle.watermarkHint` |

Davranış:
- **Her değişiklik anında** `Style`'ı yazar → ayar kaydedilir ve görünüm TV'ye (ve bilgisayardaki altyazı penceresine)
  hemen gider (§0).
- **Yazı boyu** kaydırıcısı değişince: değer yazısı güncellenir; `FontSize` = yuvarlanmış değer **ve** `AutoSize` =
  kapalı yazılır; "uydur" anahtarı açıksa olay üretmeden kapatılır. (Boyu değiştirmek uydurmayı kapatır; yoksa TV seçilen boyutu dikkate almıyordu.)
- "Uydur" anahtarı değişince `AutoSize` = anahtarın durumu (yazı boyu kaydırıcısı kilitlenmez; Mac'te soluklaşır,
  Windows'ta etkin kalır).
- **Deneme altyazısı**: Yazı boyu, `settings.subtitle.position.label` ve Arka plan kaydırıcılarına **fareyle basıldığı an** (sürükleme
  başlarken, değer değişmeden önce) ve `setup.try.sendSample` düğmesinde gönderilir:
  önce görünüm TV'ye gider, sonra 8000 ms süreli satır `source.testSubtitle`
  (`status.testSubtitle`). Yeri: oyunda en son görülen altyazının kutusu; hiç
  görülmediyse sol 0.30, sağ 0.70, üst = okuma bölgesinin alt kenarı − 0.10, alt = okuma bölgesinin alt kenarı − 0.03
  (kenarlara oranla). Satır TV'ye (TV'ye gönderim açıksa), bilgisayardaki altyazı penceresine (yalnız altyazı
  bilgisayarda gösteriliyorsa) ve **her durumda** yayın penceresine gider (testler: bilgisayar çıkışında pencereye tek
  olay, metin ve 8000 ms; yalnız TV'de pencereye hiç olay yok; yayın penceresi yalnız TV'de de alır).
- **Yerleşim** değişince: Sabit ise konum bölmesi görünür, "izler" ipucu gizlenir; değilse tersi.
- **Örtme + saydam zemin kuralı** TV'ye giden görünüm iletisinde uygulanır, kayıtta değil: yerleşim "örterek" ve arka
  plan %60'tan azsa TV'ye arka plan 100 gönderilir. Kayıtlı değer ve bilgisayardaki pencere kullanıcının değerini
  kullanır.
- **Yazı tipi listesi**: her seçenek kendi yazı tipiyle çizilir — Aksiyon gömülü "Nino Action" (Barlow Condensed'in
  yeniden adlandırılmış yüzleri; WPF "Condensed" sözcüğünü ayıklayıp onu Barlow'un yüzü saymasın diye), Modern gömülü
  Barlow, Yuvarlak gömülü Nunito (değişken dosya WPF'te en ince çizildiği için yarı kalın ve kalın yüzler sabit dosya),
  Sade arayüzün kendi yazı tipi. Bu yazı tiplerinde olmayan harfler için yedek sıra: Segoe UI, Segoe UI Historic,
  Nirmala UI, Leelawadee UI.
- `settings.subtitle.displayMode.label` yalnız Android TV uygulamasını etkiler; satır kayıtlı TV Android TV değilse hiç görünmez.
- **`settings.connection.adjustSubtitleWindow`**: bilgisayardaki altyazı penceresini ayar kipine sokar. Bilgisayardaki pencerenin
  yeri bu karttan değil, pencereyi sürükleyerek ayarlanır; bu yüzden Yerleşim/Konum satırları yalnız TV'ye gidiyorsa
  görünür (yoksa kullanıcılar bilgisayardaki konum ayarının bozuk olduğunu sanıyordu).

Mac'ten farklar: canlı önizleme ve 6 tema kartı **yok**; yazı boyu aralığı 16…90 (Mac 20…80); satır sırası farklı
(Kalın → Önceki satırlar → Yazı tipi → Renk → `settings.subtitle.displayMode.label` → Filigran → Deneme düğmesi); deneme altyazısı için ayrı
düğme var.

### 4.2 Windows güvenlik duvarı kartı (üstte 16)
Görünüm kartının altında. Başta **gizlidir**.

- Pencere açılırken arka planda güvenlik duvarı durumu sorulur: (kural var mı, bilgisayarın ağı "Ortak" mı).
  Güvenlik duvarı hizmeti yoksa (desteklenmiyor) yanıt "yok"tur ve kart **hiç görünmez**.
- Görünürse: başlık `firewall.settings.title`; içinde:
  - Durum ipucu: kural varsa `firewall.settings.ready`; yoksa `firewall.settings.configure`
  - Ağ Ortak ise (üstte 8) `warning` renkli ipucu: `firewall.card.hintPublicNetwork`
  - Kural yoksa (üstte 12, sola yaslı) ikincil düğme `firewall.card.allow`. Basınca: düğme soluk → yönetici izniyle kural eklenir (Windows'un izin sorusu çıkar) → düğme
    yeniden etkin → durum yeniden sorulur ve kart yeniden çizilir (kural eklendiyse düğme kaybolur).
- Durum yalnız pencere açılırken ve düğmeden sonra sorulur (kendiliğinden yenilenmez).
- Kural okunamazsa "kural yok" sayılır (okunamayan izin varmış gibi gösterilmez). İzin eklenirken çeviri sürerken PS5'e ve TV'ye bağlanma hemen tekrarlanır. Kuralın kendisi (adı, kapsamı, profil) platform belgesindedir.

---

## 5. Çeviri

### 5.1 Motor kartı (başlıksız)
Yukarıdan aşağı:

1. Yatay sıra (altta 12): `translation.engine.title` (sağda 16) + açılır liste (en az 240):

   | Değer | Görünen | Not |
   |---|---|---|
   | `Free` | `translation.engine.free` | |
   | `DeepL` | DeepL | verbatim |
   | `Gemini` | Google Gemini | verbatim |
   | `OpenAi` | OpenAI | verbatim |
   | `Claude` | Anthropic Claude | verbatim |
   | `Local` | `settings.translation.engine.local` | |

   Seçili motor = (`OnlineTranslation` açık **ve** `OnlineEngine` ≠ Free) ise `OnlineEngine`, değilse Free.
   Seçince: Free → `OnlineTranslation` kapanır (`OnlineEngine` hatırlanır); diğerleri → `OnlineTranslation` açık ve
   `OnlineEngine` = seçilen. Varsayılan: kapalı, hatırlanan motor DeepL.
2. Motor ipucu (ipucu, satır kaydırmalı):

   | Motor | Metin anahtarı |
   |---|---|
   | Free | `settings.translation.engineHint.free` |
   | DeepL | `settings.translation.engineHint.deepl` |
   | Gemini | `settings.translation.engineHint.gemini` |
   | OpenAI | `settings.translation.engineHint.openai` |
   | Claude | `settings.translation.engineHint.claude` |
   | Local | `settings.translation.engineHint.local` |

3. `setup.better.deviceTitle` (üstte 16, altta 8) + açılır liste (240 genişlik, sola yaslı):
   `setup.better.deviceCpu` (`Cpu`) | `setup.better.deviceGpu` (`Gpu`) → `TranslationDevice`
   (varsayılan `Cpu`; eski kayıtta yoksa CPU).
4. **CPU iş parçacığı bölmesi** (üstte 12; yalnız CPU seçiliyken): `settings.translation.cpuThreads` (altta 8) + açılır liste (120 genişlik) → `CpuTranslationThreads`; seçilen sayı ilişkin seçenek "yoğun"
   ise altında (üstte 8) `warning` renkli uyarı `settings.translation.cpuThreadsWarning` — bkz. §5.4.
5. İpucu (üstte 8): `settings.translation.deviceHint` (ilk GPU seçiminde ~565 MB CUDA dosyası indirilir, diskte ~790 MB;
   olmazsa CPU).
6. `warning` renkli satır (üstte 8), **yalnız denetleyici "GPU'ya düşülemedi" uyarısını taşırken**: `settings.translation.gpuFallback`. Aygıt değişince
   uyarı silinir.
7. "Yalnız İngilizce" ipucu (üstte 8), motor Free değil **ve** oyunun dili İngilizce değilse: `settings.translation.englishOnlyHint`.
8. **Ücretsiz Gemini önerisi** (üstte 12; yalnız Free seçiliyken): sağda ikincil `setup.better.getFreeKey`
   (solunda 12), solda dikeyde ortalı `settings.translation.geminiOffer`. Basınca: motor Gemini yapılır (ayar yazılır), liste olay üretmeden Gemini'ye çekilir,
   bölüm yeniden çizilir (anahtar alanı görünür), tarayıcıda `https://aistudio.google.com/apikey` açılır.
9. **Gemini notları** (yalnız Gemini seçiliyken), iki ipucu (her biri üstte 8): gizlilik (`setup.better.privacyHint`) ve sınır (`setup.better.limitHint`).
10. **Anahtar bölmesi** (üstte 12; Free'de gizli) — §5.2.

### 5.2 Anahtar bölmesi

Yukarıdan aşağı:

- **Model sırası** (altta 12; yalnız Gemini/OpenAI/Claude): "Model" (sağda 16) + açılır liste (en az 240). Seçenekler
  ortak model listesinden (`ai-models.json`; hizmet başına; ilk öğe varsayılan) gelir, görünen ad listedeki etiketin
  yerelleştirmesidir; model adı elle yazılamaz. Seçili: kayıtlı model kimliği listede yoksa varsayılan. Değişince
  `GeminiModel` / `OpenAiModel` / `ClaudeModel` yazılır.
- **Yerel model bölmesi** (altta 12; yalnız Local):
  - İki satırlı ızgara: `translation.local.address` (sağda 16, altta 8) + metin kutusu (altta 8); "Model name /
    Model adı" + metin kutusu. Kutular `LocalAiBaseUrl` (varsayılan `http://localhost:11434/v1`) ve `LocalAiModel`
    (varsayılan `translategemma:4b`) ile dolar.
  - **Kaydetme**: kutudan odak çıkınca ya da Enter'a basınca (her tuşta değil). İkisi de baştaki/sondaki boşluktan
    arındırılır; kayıtlıdan farklıysa ikisi birden yazılır ve durum/hata satırları gizlenir. Her seferinde adres
    doğrulanır.
  - Yan yana iki ikincil düğme (üstte 8): `settings.translation.useOllama` → adres `http://localhost:11434/v1`;
    `settings.translation.useLmStudio` (solunda 8) → `http://localhost:1234/v1`; ikisi de kutuya yazıp kaydeder.
  - Adres hatası (hata yazısı, üstte 8): adres geçersizse `settings.translation.addressInvalid` — örnek Ollama adresi. Geçersizken **Kaydet/Dene düğmeleri soluk**.
    Adres doğrulaması: boşsa ya da boşluk içeriyorsa geçersiz; "://" yoksa başına "http://" eklenir; sondaki "/"
    atılır; sonda "/chat/completions" varsa atılır; şema http/https olmalı ve makine adı boş olmamalı; sorgu ve parça
    atılır; yol boş ya da "/" ise "/v1" eklenir. Örnekler: `localhost:11434` → `http://localhost:11434/v1`;
    `http://x:1234/v1/chat/completions` → `http://x:1234/v1`; `ftp://x` → geçersiz; `http://a b` → geçersiz.
  - Uzun ipucu (üstte 8): model adının sunucunun gösterdiği gibi yazılacağı; Ollama'da önce `ollama pull
    translategemma:4b` (16 GB+ bellekte `translategemma:12b` daha iyi), Xiaomi MiLMMT
    (`ollama pull hf.co/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M`), indirilenler `ollama list`; LM Studio'da modeli
    yükleyip yerel sunucuyu başlatmak (komutlar verbatim).
  - `translation.key.saved` durumunda değilse (üstte 12) `translation.key.optional` yazısı.
- **Yeni anahtar** (anahtar kayıtlı değilse):
  - Yan yana: gizli giriş kutusu (320 genişlik) + ikincil `setup.better.saveAndTest` (solunda 12; yerel modelde
    yazısı `translation.local.testConnection`).
  - "Anahtarsız" ipucu (üstte 8; DeepL ve yerel modelde gizli): `settings.translation.noKeyHint`
  - Bağlantı (üstte 8): Local → `translation.local.downloadOllama` (`https://ollama.com/download`); Gemini/OpenAI/
    Claude → `settings.translation.getApiKey` (Gemini `https://aistudio.google.com/apikey`, OpenAI
    `https://platform.openai.com/api-keys`, Claude `https://platform.claude.com/settings/keys`); DeepL →
    `settings.translation.getDeeplKey` (`https://www.deepl.com/pro-api`). Tıklayınca varsayılan tarayıcıda.
- **Kayıtlı anahtar** (kayıtlıysa): solda Tamam yazısı `translation.key.saved`; sağda `settings.translation.removeKey` (solunda 8) ve `settings.translation.test` (DeepL'de gizli; yerel modelde `translation.local.testConnection`).
- Durum satırı (ipucu, üstte 8) ve hata satırı (hata yazısı, üstte 8); ikisinden en çok biri görünür. Motor değişince
  ikisi de gizlenir.

Davranış:
- `setup.better.saveAndTest` (Gemini/OpenAI/Claude): düğme soluk → yazılan anahtar (kırpılmış) seçili modelle örnek satır
  çevrilerek denenir. Sonuç "geçerli", "kota bitti" ya da "model reddedildi" ise anahtar şifreli depoya yazılır ve o
  motor seçilir (zaten seçiliyse ve çeviri sürüyorsa hat yeni anahtarla kurulur). Kaydedildiyse kutu boşalır. Bölüm
  yeniden çizilir, sonuç gösterilir. Bitince düğme etkin.
- `setup.better.saveAndTest` (DeepL): anahtar kotası sorgulanarak denenir; "geçerli" ya da "kota bitti" ise kaydedilir ve DeepL
  seçilir; kutu boşalır; DeepL sonucu gösterilir.
- `translation.local.testConnection` (yerel, yeni anahtar bölmesinde): önce adres/model kaydedilir; düğme soluk ve yazısı
  `setup.better.testing`; yazılan anahtarla (boşsa kayıtlı anahtarla) sunucuya örnek satır gönderilir; yazılan
  anahtar kabul edildiyse ("geçerli/kota/model reddi") kaydedilir. Adres geçersizse istek gönderilmeden "ulaşılamadı"
  sayılır. Bitince düğme yazısı yine `translation.local.testConnection`, etkinliği adresin geçerliliğine bağlı.
- **Dene** (kayıtlı anahtar): yerelde önce adres/model kaydedilir; düğme soluk ve `setup.better.testing`; kayıtlı anahtar ve
  modelle örnek satır; sonra eski yazısına döner.
- `settings.translation.removeKey`: anahtar silinir. Bulut motorunda: o motor seçiliyse motor Free'ye döner. Yerelde: motor seçili
  kalır (anahtar isteğe bağlı), çeviri sürüyorsa hat anahtarsız yeniden kurulur. Bölüm yeniden çizilir.
- DeepL seçiliyken ve anahtar kayıtlıysa bölüm her çizildiğinde bu ayki kullanım kendiliğinden sorgulanıp gösterilir.
- Anahtarlar ayar dosyasında değil **şifreli depoda** durur (anahtar adları: `deepLKey`, `geminiKey`, `openAIKey`,
  `claudeKey`, `localAIKey`); arayüze hiç geri okunmaz, yalnız "kayıtlı mı" bilinir.

Sonuç metinleri:

| Durum | Metin anahtarı | Tür |
|---|---|---|
| AI geçerli | `setup.better.workingSample` | durum |
| AI anahtar reddi | `status.online.invalidKey` | hata |
| AI kota | `settings.translation.result.aiQuota` | hata |
| AI model reddi | `status.online.modelRejected` | hata |
| AI ulaşılamadı | `translation.error.unreachable` | hata |
| DeepL geçerli | `translation.deepl.usage` | durum |
| DeepL kota | `settings.translation.result.deeplQuota` | durum |
| DeepL ret | `status.online.invalidKey` | hata |
| DeepL ulaşılamadı | `translation.error.unreachable` | hata |
| Yerel anahtar reddi | `settings.translation.result.localKeyRejected` | hata |
| Yerel kota (meşgul) | `translation.error.local.busy` | hata |
| Yerel model yok (LM Studio, kapı 1234) | `settings.translation.result.lmStudioNoModel` | hata |
| Yerel model yok (diğer) | `settings.translation.result.localNoModel` | hata |
| Yerel ulaşılamadı, Ollama (kapı 11434) | `status.online.local.ollamaDown` | hata |
| Yerel ulaşılamadı, LM Studio | `settings.translation.result.lmStudioUnreachable` | hata |
| Yerel ulaşılamadı, diğer kapı | `settings.translation.result.localUnreachable` | hata |

AI metinlerinde %@ = marka adı (Gemini, OpenAI, Claude; `status.online.localModelName` çevrilir). Yerel metinlerde adres kısa biçimdir
(`http://localhost:11434`), model kullanıcının yazdığı ad. Sunucu türü adresin kapısından tahmin edilir.

### 5.3 DeepL düğme ayrıntısı
DeepL'de "Dene" düğmesi yoktur (kotası zaten her açılışta gösterilir) ve "anahtarsız" ipucu gizlidir.

### 5.4 CPU iş parçacığı seçenekleri
- Seçenekler: mantıksal işlemci sayısı 2'den azsa yalnız **1**; değilse **2, 4, 8, 12** içinden işlemci sayısını
  geçmeyenler.
- Kayıtlı değer, seçeneklerden kayıtlıyı geçmeyen en büyüğüne çekilir; hiçbiri yoksa ilk seçenek. Varsayılan 2.
- "Yoğun" uyarısı: seçilen × 4 ≥ işlemci sayısı × 3.
- Örnekler: 8 işlemci → seçenekler 2/4/8; 8 seçiliyse uyarı (32 ≥ 24), 4'te yok. 16 işlemci, kayıtlı 10 → 8.
  1 işlemci → [1]. 4 işlemci, kayıtlı 12 → 4 (uyarı: 16 ≥ 12).
- Ayar her yazıldığında da bu çekme uygulanır (§0, 1).

### 5.5 Gelişmiş kartı (başlık `settings.translation.advanced`, üstte 16)
1. Anahtar `settings.translation.fastDetection` → `FastSubtitleDetection`
   (varsayılan kapalı). İpucu (üstte 6, altta 16): `settings.translation.fastDetectionHint` (… 20 yerine 2 kare sonra yeniden oku. Daha fazla CPU kullanır.)
2. İpucu (altta 16): `settings.translation.waitsHint`
3. `settings.translation.misreadWait` (altta 8); satır: kaydırıcı (0…1, adım 0.1, oturur) +
   sağda en az 56 genişliğinde sağa yaslı değer "0,8 sn" (geçerli kültürün ondalık ayracıyla bir ondalık + boşluk +
   "sec/sn"). → `MisreadWaitMs` = değer × 1000 (yuvarlanmış). Varsayılan 800. İpucu (altta 16): GTA V ölçümü (0 sn'ye göre
   hatalı okumadan çıkan çeviri oranı: 0,2 sn %77, 0,4 sn %49, 0,6 sn %41, 0,8 sn (önerilen) %34, 1,0 sn %31).
4. `settings.translation.partialWait`: aynı satır → `PartialWaitMs` (varsayılan 300). İpucu:
   cümle sonu olmayan (ör. renkli sözcüklü görev yazısı) satırın tamamı en çok bu kadar beklenir; etkisi küçük;
   önerilen 0,3 sn.
5. İkincil `settings.restoreDefaults` (sola yaslı): kaydırıcıları 0,8 ve 0,3'e çeker (onların
   değişme olayları ayarı yazar).

---

## 6. `pack.settings.title`

Bölüm başlığı satırı (altta 8): solda büyük başlık `pack.settings.title`; sağda hap `settings.packs.pill` (kurulu paket yoksa gizli).

1. İkincil yazı (gövde, `textSecondary`, altta 16): `settings.packs.description`
2. İkincil düğme `settings.packs.import` (sola yaslı, altta 16) — §6.2.
3. **Paket listesi**: iki eşit sütunlu ızgara (dış kenar −8 yatay, altta 8; karolar arası 8+8). İçerik:
   - Çeviri dili Türkçe değilse en başta ipucu (8 boşluk): `settings.packs.turkishOnly`
   - Paket yoksa ipucu: `settings.packs.none`
   - Her paket bir **karo** (kart, dışta 8): solda **monogram** (52×52, `surface2` zemin, köşe 10, içinde ortalı, yarı
     kalın, 13 boyunda, kaydırmasız baş harfler; sağında 16), sağda dikeyde ortalı ad (başlık yazısı) ve altında (üstte
     4) satır sayısı `settings.packs.lines` (küçük yazı; sayı geçerli kültürle binlik ayraçlı).
   - Baş harf kuralı: başlık boşluk, `:`, `-`, `(`, `)` ile sözcüklere bölünür; ilk karakteri harf ya da rakam olan
     ilk üç sözcüğün ilk karakterleri büyük harfle birleştirilir. Örnekler (kendi örneklerimiz): "Grand Theft Auto V" → "GTA";
     "Hollow Knight: Silksong" → "HKS"; "Ghost of Yōtei" → "GOY"; "Hades 2" → "H2".
   - Liste, kurulu paketler değişince ve çeviri dili değişince yeniden çizilir.
4. **Seçenekler kartı** (iç boşluk yatay 20, dikey 4). Dört satır, aralarında kenardan kenara ince ayraç. Her satır: en az
   44 yükseklik, dikey dış 8; sağda anahtar (solunda 16; yazısız; ekran okuyucu adı satır başlığıyla aynı), solda
   başlık yazısı ve (varsa) altında ipucu (üstte 4).

   | Başlık (metin anahtarı) | İpucu (metin anahtarı) | Alan | Varsayılan |
   |---|---|---|---|
   | `settings.packs.useGamePacks` | — | `GamePacks` | açık |
   | `settings.packs.sharePool` | `settings.packs.sharePoolHint` | `SharePool` | açık |
   | `settings.packs.askGame` | `settings.packs.askGameHint` | `AskGame` | açık |
   | `settings.packs.speakerNames` | `settings.packs.speakerNamesHint` | `ShowSpeakerNames` | açık |

   Etkileri §0'da (paketler hatta yeniden bağlanır, havuz açılır/kapanır, konuşan adı hemen geçer). Oyun sorma kartı
   Mac `ninoya-sor.md` §7 ile aynı mantıktadır.

### 6.2 Paket içe aktarma akışı
1. Dosya seçici: başlık `pack.import.title`, süzgeç `settings.packs.importFilter`
   (yalnız bu üç uzantı). Vazgeçilirse bitti.
2. İçe aktar düğmesi soluk; dosya **arka planda** okunur: 64 MB'tan büyükse "geçersiz veri" sayılır; değilse içerik
   ayrıştırılır (biçimler, sayımlar ve kimlik kuralı Mac `havuz-paketler.md` §5 ile aynı). Bitince düğme etkin.
3. Hata pencereleri (Windows ileti kutusu; başlık = dosya seçicinin başlığı; hata simgesi; Tamam):
   - biçim/kodlama hatası ya da çok büyük: `settings.packs.importInvalid`
   - okuma/izin hatası: `settings.packs.importUnreadable`
   - Bu arada Ayarlar kapandıysa ileti gösterilmez.
4. Başarıyla ayrıştırıldıysa (ve Ayarlar hâlâ açıksa) `pack.import.title` penceresi kalıcı (modal) açılır
   (`yan-pencereler.md` §3). "Yüklendi" ile kapanırsa denetleyici paket kütüphanesini yeniden yükler (liste ve hap
   güncellenir).

---

## 7. Dil

Tek kart (başlıksız):

1. **Oyunun dili satırı** (altta 12): `settings.language.gameLanguage` (sağda 16) + açılır liste. Seçenekler bu sırayla
   **English, Japanese, German, French, Spanish** (adlar yerelleştirilir: İngilizce, Japonca, Almanca, Fransızca,
   İspanyolca; kodlar `en, ja, de, fr, es`), ama yalnız çeviri hizmetinin o dilden **şu anki çeviri diline**
   çevirebildikleri (pencere açılırken bir kez hesaplanır). Liste tek öğeliyse **satır hiç görünmez**. → `SourceLanguage`
   (varsayılan `en`).
2. **Çeviri dili satırı**: `setup.welcome.translationLanguage` (sağda 16) + açılır liste. Her öğe soldan sağa bir
   satır: 22×15 bayrak + 10 boşluk + dilin kendi adı (verbatim). Sıra ve kodlar: Türkçe `tr`, العربية `ar`, हिन्दी `hi`,
   Bahasa Indonesia `id`, ไทย `th`, Tiếng Việt `vi`, اردو `ur`, বাংলা `bn`, Bahasa Melayu `ms`, Filipino `tl`,
   Nederlands `nl`. → `TargetLanguage` (varsayılan `tr`).
3. İpucu (üstte 12; çeviri dili Türkçe değilse): `settings.language.nonTurkishHint` (paketler ve terim listesi yalnız
   Türkçede; Windows'ta Tayca, Urduca, Bengalce, Malayca, Filipince dillerinde yapay zekâ motoru gerekir, Gemini ücretsiz).

Çeviri dili değişince oyun paketleri listesi de yenilenir (Türkçe değilse uyarı satırı). Dilin hattaki etkisi §0'da.

**Bayraklar** (Windows bayrak emojilerini iki harf olarak çizdiğinden şekille çizilir; 22×15, köşe 2.5 kırpılmış; koordinatlar
sol üstten, birim nokta):
- `tr` (ve bilinmeyen): kırmızı `#E30A17` zemin; hilal: (4.2, 3.7)'de 7.6 çaplı beyaz daire, üstüne 0.8 katı çaplı
  zemin renkli daire 0.22×çap sağa kaydırılıp dikeyde ortalanarak; beyaz yıldız merkez (13.4, 7.5), yarıçap 2.1.
- `ar`: yeşil `#006C35`; beyaz dikdörtgenler 12×1.2 @(5,4.2), 9×1.2 @(6.5,6.6), 13×1 @(4.5,10.2), 1×2.4 @(15.5,9.5).
- `hi`: üç yatay şerit turuncu `#FF9933` / beyaz / yeşil `#138808`; ortada (9,5.5)'te 4 çaplı, 0.9 kalınlıkta lacivert
  `#000080` halka.
- `id`: iki şerit kırmızı `#CE1126` / beyaz.
- `th`: kırmızı `#A51931` zemin; beyaz 22×2.5 @y2.5, lacivert `#2D2A4A` 22×5 @y5, beyaz 22×2.5 @y10.
- `vi`: kırmızı `#DA251D`; sarı yıldız merkez (11, 7.8), yarıçap 4.2.
- `ur`: koyu yeşil `#01411C`; solda beyaz 5.5×15 şerit; hilal (9.2, 3.6) çap 7.4; beyaz yıldız (16.4, 5.6) r 1.6.
- `bn`: yeşil `#006A4E`; kırmızı `#F42A41` 8.4 çaplı daire @(5.6, 3.3).
- `ms`: beyaz zemin; 14 eşit şeritten çift sıradakiler kırmızı `#CC0001`; sol üstte lacivert `#010066` 11×8.6; sarı
  `#FFCC00` hilal (1.6,1.6) çap 5.4 ve sarı yıldız (7.8,4.3) r 1.5.
- `tl`: iki şerit mavi `#0038A8` / kırmızı `#CE1126`; soldan beyaz üçgen (0,0)-(11,7.5)-(0,15); sarı `#FCD116` 3 çaplı
  daire @(2.6, 6).
- `nl`: üç şerit kırmızı `#AE1C28` / beyaz / mavi `#21468B`.
- Şeritler eşit yükseklikte, aralık kalmasın diye her biri 0.2 fazla. Yıldız beş köşeli: 10 nokta, çift sıradakiler
  yarıçapta, tekler 0.42 katında, ilk nokta tam üstte.

---

## 8. `settings.section.subtitleArea`

Bölüm başlığı + iki/üç kart.

### 8.1 Alan kartı (başlıksız)
Yukarıdan aşağı:

1. Bölmeli seçici (sola yaslı, altta 12): `settings.area.subtitles` | `settings.area.area1` | `settings.area.area2` |
   `settings.area.area3`. Açılışta Altyazı seçili. Seçim yalnız neyin düzenlendiğini değiştirir (ayar yazmaz).
2. **Hazır bölge bölmesi** (altta 12; yalnız Altyazı'da): `settings.area.preset.label` (altta 8) + seçici `settings.area.preset.bottom` | `settings.area.preset.top` | `reading.areaPreset.full` | `reading.areaPreset.custom` (`AreaPreset`:
   `Bottom`/`Top`/`Full`/`Custom`). Özel seçiliyken altında (üstte 12) ızgara:
   - `settings.area.verticalPosition` + kaydırıcı (0…95; küçük adım 1, büyük 5; iki yandan 12) + 56 genişliğinde sağa
     yaslı, eş aralıklı rakamlı değer "%35" (EN "35%");
   - 8 boşluk;
   - `reading.area.height` + kaydırıcı (5…100) + değer.
3. Anahtar `settings.area.useThisArea` (altta 12; yalnız Alan 1–3).
4. **Sürekli okuma bölmesi** (altta 12; yalnız Alan 1–3): anahtar `settings.area.keepReading`;
   ipucu (üstte 6) `settings.area.keepReadingHint`;
   kayan sıra (üstte 10) üç ikincil düğme (aralarında 8): `reading.extraPreset.quest`, `reading.extraPreset.notification`, `settings.area.corner.phone`.
5. **Sonuç yeri bölmesi** (altta 12; yalnız Alan 1–3): `settings.area.showResult` (altta 8) + seçici `settings.area.target.tv` | `settings.area.target.pc` | `settings.area.target.both` (`Tv`/`Pc`/`Both`).
6. **Bölge seçici** (§8.4).
7. İkincil düğme (sola yaslı, üstte 12): `settings.area.refreshPicture` — %@ `shortcut.action.refreshPicture`
   işinin tuşları. Basınca önizleme son kareyle yenilenir (çerçeve olduğu gibi kalır).
8. Alan ipucu (ipucu, üstte 12):
   - Altyazı: `settings.area.subtitleHint`
   - Alan n: kısayol cümlesi `settings.area.extraHint`
     (%@ = "Bölge n'i çevir" işinin tuşları).

Ayar alanları ve kayıtlı biçim: altyazı bölgesi `Region` {`Top`,`Bottom`,`Left`,`Right`} (kenarlara oranla 0–1;
varsayılan 0.62 / 0.97 / 0.14 / 0.86), `AreaPreset` (eski kayıtta yoksa bölgeden çıkarılır: bölge bir hazır seçimle
±0.001 içinde aynıysa o, değilse Özel). Ek bölgeler `ExtraRegion1..3` (yok = kapalı; varsayılan kapalı), sonuç yerleri
`ExtraTarget1..3` (varsayılan `Tv`), sürekli okuma `ExtraLive1..3` (varsayılan kapalı).

Hazır bölgeler (üst, alt, sol, sağ): Alt = varsayılan bölge (0.62, 0.97, 0.14, 0.86); Üst = (0.03, 0.38, 0.14, 0.86);
Tam ekran = (0, 1, 0, 1); Özel = kayıtlı bölge.
Ek bölge köşe hazırları: Görev = (0.03, 0.30, 0.66, 0.98); Bildirim = (0.58, 0.88, 0.02, 0.30);
Telefon = (0.50, 0.95, 0.72, 0.98).
Ek bölge kapalıyken çerçevenin gösterdiği (ve `settings.area.resetArea` düğmesinin döndüğü) başlangıç bölgeleri: Alan 1 = (0.05, 0.28,
0.60, 0.97) sağ üst; Alan 2 = (0.72, 0.95, 0.60, 0.97) sağ alt; Alan 3 = (0.35, 0.65, 0.30, 0.70) orta.

Davranış:
- **Seçici Altyazı'ya geçince**: Kullan/sürekli/sonuç bölmeleri gizlenir, hazır bölge bölmesi görünür ve kayıtlıyla
  işaretlenir; bölge seçici etkin, "sıfırla" bölgesi varsayılan bölge, çerçeve kayıtlı bölgeyi gösterir (olay üretmeden).
- **Alan n'e geçince**: "Kullan" anahtarı, bölge açıksa açık; sürekli okuma ve sonuç yeri kayıtlıyla işaretlenir; bölge
  seçici **yalnız bölge açıksa etkin**; "sıfırla" bölgesi o alanın başlangıç bölgesi; çerçeve kayıtlı bölgeyi ya da
  başlangıç bölgesini gösterir; ipucu o alanın kısayoluyla.
- **Hazır bölge seçilince** (yalnız Altyazı'da): `AreaPreset` = seçilen ve `Region` = seçimin bölgesi (Özel'de kayıtlı
  bölge kalır); çerçeve yeni bölgeyi gösterir; işaretler ve kaydırıcılar yenilenir.
- Özel'de kaydırıcılar bölgenin **üst kenarını** ve **yüksekliğini** yüzde gösterir (yuvarlanıp aralığa kırpılarak).
  Biri değişince: değer yazıları güncellenir; yeni bölge = sol/sağ aynı, yükseklik = max(%5, değer)/100 (en çok 1), üst =
  değer/100 en az 0 en çok 1 − yükseklik (gerekirse yukarı kayar); `AreaPreset` = Özel ve `Region` = yeni bölge;
  çerçeve güncellenir. Örnek: üst %90, yükseklik %20 → üst 0.80, alt 1.00.
- **Çerçeve elle değişince** (bölge seçici olayı): Altyazı'da `Region` = yeni bölge ve `AreaPreset` = (yeni bölge bir
  hazır seçimle aynıysa o, değilse Özel) — `settings.area.resetArea` düğmesine basmak bu yüzden `settings.area.preset.bottom` seçimini yeniden işaretler; işaretler
  yenilenir. Alan n'de `ExtraRegion n` = yeni bölge.
- **`settings.area.useThisArea`**: açılınca seçici etkinleşir ve `ExtraRegion n` = çerçevenin şu anki bölgesi; kapanınca seçici
  soluk ve `ExtraRegion n` = yok.
- **`settings.area.keepReading`** → `ExtraLive n`. Sürekli okunan bölgeler = açık **ve** sürekli okuması seçili olanlar
  (kimlik "area1/2/3", ad "Area n"); bunlar çeviri sürerken ayrı bir okuyucuyla yaklaşık saniyede bir okunur, çevirisi
  bilgisayardaki pencerede "bölge" olayıyla (ve TV'de) görünür; çeviri durunca "bölgeleri temizle" olayı gider (testler).
- **Köşe hazır düğmesi**: "Kullan" olay üretmeden açılır, seçici etkin, çerçeve köşeye gelir, `ExtraRegion n` = köşe
  bölgesi.
- **Sonuç yeri** → `ExtraTarget n`.

Testlerden örnekler: yeni ayarda ek bölgeler yok ve sürekli okunmuyor; Alan 1 = Görev + sürekli, Alan 2 açık ama sürekli
değil, Alan 3 sürekli ama bölgesi yok → sürekli okunan tek bölge "area1" (Görev bölgesi). Alan 2'ye (0.1,0.3,0.6,0.95)
verilince Alan 1 yok kalır, Alan 2 o bölge; yok verilince kapanır. Alan 3 + İkisinde de ayrı saklanır, Alan 1 TV kalır.

### 8.2 Önizlemenin yenilenmesi
- Pencere açılırken önizlemeye son kare konur (çeviri sürmüyorsa yer tutucu yazı).
- Son kare değiştikçe: **altyazı alanı bölümü seçiliyse**, çerçeve fareyle sürüklenmiyorsa ve son yenilemeden en az
  **1000 ms** geçtiyse önizleme yeni kareyle yenilenir.
- "Görüntüyü yenile" kısayolu (varsayılan Num 8 / Ctrl+Shift+8) basılınca (yalnız çeviri sürerken çalışır) önizleme
  hemen son kareyle yenilenir.

### 8.3 `shortcut.action.translateScreen` kartı ve `shortcut.action.freeArea` kartı
- **`shortcut.action.translateScreen` kartı** (üstte 16): başlık `settings.area.translateScreenTitle`; ipucu kısayol cümlesi
  `settings.area.translateScreenHint`
- **`shortcut.action.freeArea` kartı** (üstte 16): başlık `settings.area.freeAreaTitle`; içinde:
  - ipucu (altta 12): `settings.area.freeAreaHint`
  - `settings.area.showResult` (altta 8) + seçici TV'de | Bilgisayarda | İkisinde de (altta 12) →
    `FreeAreaTarget` (varsayılan `Tv`);
  - ipucu (altta 8): `settings.area.pauseHint`
    (`settings.area.pauseHint`)
  - ipucu: `settings.area.shortcutsHint` (Kısayollar yalnız çeviri açıkken çalışır… Num Lock açık
    olmalı… Ayarlar › Kısayollar'dan değiştirebilirsiniz.)
- Başlık başında kısayol yoksa parantez içinde `shortcut.none`; cümlede kısayol yoksa cümlenin tamamı yerine `shortcut.noneSentence`
- Bütün kısayollu metinler ayarlar her değiştiğinde yeniden yazılır.

### 8.4 Bölge seçici (oyun görüntüsü üstünde çerçeve)
Soldan sağa tutulur (Arapçada aynalanmaz).

- Yapı: köşesi 10 olan, `background` zeminli, taşanı kırpan bir kutu; içinde önizleme alanı. Altında (üstte 12) ikincil
  düğme `settings.area.resetArea` → bölge "sıfırla bölgesi" olur **ve olay üretir** (yani kaydedilir).
- Önizleme alanının boyu: genişlik ÷ görüntünün en/boy oranı, en az 120 (oran: kare varsa kareden, yoksa 16:9;
  başlangıç boyu 281). Pencere büyüdükçe önizleme büyür.
- Kare yoksa ortada, 24 iç boşluklu, ortalı, kaydırmalı küçük yazı: `settings.area.previewPlaceholder` Kare varsa (BGRA, 96 dpi) alanı tam dolduracak şekilde
  gerilerek çizilir.
- Çerçeve: 2 kalınlıkta `accent` kenar, dolgu sabit turuncu-sarı RGB(245,184,61) %14 (alfa 36/255); dört köşede
  10×10 `accent` dolgulu kare tutamak (köşenin tam ortasında).
- Fare (sol düğme; basınca fare yakalanır):
  - **Kenar yakalama**: imleç çerçevenin her yandan 10 büyütülmüş hâlinin içindeyse ve bir kenara ≤ 10 uzaktaysa o kenar
    (yatayda önce sol, değilse sağ; dikeyde önce üst, değilse alt; köşede iki kenar) → **boyutlandırma**.
  - Çerçevenin içi → **taşıma**; dışarısı → **yeni çizim**.
  - Basılı değilken imleç: sol/sağ kenar ↔ yatay ok; üst/alt ↕; sol-üst ya da sağ-alt köşe ⤡; sağ-üst ya da sol-alt ⤢;
    içeride dört yönlü; dışarıda artı.
  - Sürüklerken koordinatlar 0–1'e kırpılır. Çizim: başlangıç ve şimdiki noktanın kapsadığı dikdörtgen. Taşıma: boyut
    aynı, sol/üst 0 ile 1 − boyut arasında. Boyutlandırma: tutulan kenar fareyi izler ama karşı kenara **en az 0.03**
    yaklaşır.
  - Bırakınca: çizimde genişlik ya da yükseklik 0.03'ten küçükse önceki bölge geri gelir (tıklamak bölgeyi bozmaz).
    Bölge başlangıçtakinden farklıysa **bölge değişti olayı** gelir. Fare yakalaması kaybolursa sürükleme biter.
- Kodla bölge göstermenin iki yolu vardır: olaylı (kaydeder) ve olaysız (bölüm değişirken ayar yazılmasın diye).
- "Sürükleniyor" durumu dışarıdan okunur (önizleme bu sırada yenilenmez).

---

## 9. Kısayollar

### 9.1 Kart
- İpucu (altta 16): `settings.shortcuts.intro` (Her işin iki kısayolu var… Bir kısayola tıklayıp
  yeni tuşlara basın. Geri silme tuşu kaldırır, Esc vazgeçer.)
- Üç sütunlu ızgara (esnek | otomatik | otomatik). Her iş bir satır, bu sırayla:

  | Sıra | İş | Ad (metin anahtarı) | Rakam |
  |---|---|---|---|
  | 1 | Screen | `shortcut.action.translateScreen` | 9 |
  | 2 | FreeArea | `shortcut.action.freeArea` | 5 |
  | 3 | ExtraRegion1 | `shortcut.action.translateArea1` | 1 |
  | 4 | ExtraRegion2 | `shortcut.action.translateArea2` | 2 |
  | 5 | ExtraRegion3 | `shortcut.action.translateArea3` | 3 |
  | 6 | PauseSubtitles | `shortcut.action.pauseResume` | 0 |
  | 7 | ClickThrough | `settings.shortcuts.action.clickThrough` | 7 |
  | 8 | Snapshot | `shortcut.action.refreshPicture` | 8 |

  Satır: ad (dikeyde ortalı, kaydırmalı, sağda 16, altta 8) + iki ikincil düğme (en az 160 genişlik; ikincinin solunda
  8; altta 8). Düğme yazısı o yuvanın tuşunun adı ya da `settings.shortcuts.notSet`.
- Bilgi satırı (ipucu, üstte 12) ve hata satırı (hata yazısı, üstte 12), ikisi de başta gizli.
- İkincil `settings.restoreDefaults` (sola yaslı, üstte 16).
- İpucu (üstte 12): `settings.shortcuts.workOnlyWhileTranslating`

### 9.2 Tuş kaydı
- Bir düğmeye tıklayınca: başka bir kayıt sürüyorsa o bırakılır; bilgi ve hata satırları gizlenir; bu yuva "bekliyor"
  olur, düğme yazısı `settings.shortcuts.pressKeys`, **genel kısayollar bırakılır** (çeviri sürerken basılan tuş
  işi çalıştırmasın, buraya gelsin) ve düğme klavye odağını alır.
- Bekleyen düğmeye yeniden tıklamak ya da düğmenin klavye odağını kaybetmesi kaydı bırakır. Pencere kapanırken de
  bırakılır. Bırakınca düğme kayıtlı tuşu gösterir, genel kısayollar yeniden tutulur.
- Bekleme sırasında pencereye gelen **her tuş** (önizleme aşamasında) yutulur (Esc ve Enter pencereyi kapatmaz).
  Alt'lı tuşlarda gerçek tuş sistem tuşundan, IME işlenmiş tuşta asıl tuştan alınır.
  - Yalnız bir değiştirici (Ctrl, Shift, Alt, Win; sol/sağ) basıldıysa beklemeye devam.
  - Değiştiricisiz **Esc** → kayıt bırakılır (değişiklik yok).
  - Değiştiricisiz **Geri silme** ya da **Delete** → o yuva **kapatılır** (tuş yok).
  - Win tuşu basılıysa → `settings.shortcuts.error.reserved` hatası, beklemeye devam.
  - Değilse tuş (Ctrl/Alt/Shift + sanal tuş kodu) doğrulanır (§9.3). Sorun varsa hata satırında nedeni yazar, beklemeye
    devam. Yoksa atanır.
- **Atama**: önce tuş, genel kısayollar bırakılmışken Windows'a bir kez kaydettirilerek denenir; alınamıyorsa başka
  uygulama tutuyordur ("meşgul"). Tablo güncellenir (§9.3), ayar `Hotkeys` yazılır, kısayollar yeniden tutulur, bütün
  kısayol metinleri ve düğmeler yenilenir. Tuş başka bir işten alındıysa bilgi satırında `settings.shortcuts.movedHere`
  — tuş adı ve eski işin adı. Meşgulse hata satırında `settings.shortcuts.busy` — atama yine yapılır.
- `settings.restoreDefaults`: kayıt bırakılır, satırlar gizlenir, `Hotkeys` = boş liste (hepsi varsayılan).

Doğrulama hataları:

| Sorun | Metin anahtarı |
|---|---|
| değiştirici gerekir | `settings.shortcuts.error.needsModifier` |
| AltGr | `settings.shortcuts.error.altGr` |
| ayrılmış | `settings.shortcuts.error.reserved` |
| desteklenmeyen tuş | `settings.shortcuts.error.unsupported` |

### 9.3 Kısayol tablosu (ayar biçimi ve kurallar)
- Her işin iki yuvası: **0** = Num rakamı (değiştiricisiz sayı tuş takımı), **1** = Ctrl+Shift+üst sıra rakamı. Rakamlar
  yukarıdaki tabloda. Ctrl+Alt bilerek kullanılmaz (Türkçe Q'da AltGr; #, $, {, [ yazdırmazdı); Win tuşu kullanılmaz.
- Değiştirici değerleri Windows'un kısayol bayraklarıyla aynı: Alt = 1, Control = 2, Shift = 4.
- Ayar `Hotkeys`: yalnız varsayılandan **farklı** yuvalar saklanır, her biri {`Action` (iş adı metin), `Slot` (0/1),
  `Key` ({`Modifiers` (ad(lar) metin), `VirtualKey` (sayı)} ya da `null` = kapalı)}. Bir yuva için listede birden çok
  kayıt varsa sonuncusu geçer. Eski dosyada alan yoksa hepsi varsayılan.
- **Tutulacak tablo**: önce bütün 0. yuvalar, sonra bütün 1. yuvalar; her yuvada işler şu sırayla: Bölge1, Bölge2,
  Bölge3, `shortcut.action.freeArea`, Görüntüyü yenile, Duraklat, `shortcut.action.translateScreen`, `settings.connection.clickThrough` (kısayol kimlikleri bu sıradan
  gelir; Num tuşlarının kimlikleri eskisi gibi kalır). Kapalı, geçersiz ya da daha önce başka işe verilmiş tuş atlanır.
  Bir işin "çalışan tuşları" bu tablodaki tuşlarıdır (yuva sırasıyla).
- **Atama**: işin o yuvasına tuş verilir (ya da kapatılır). Tuş başka bir yuvada kullanılıyorsa oradan kaldırılır;
  başka bir işten alındıysa o iş "yerinden edilen" olarak bildirilir. Sonuç listesinde yalnız varsayılandan farklı
  yuvalar kalır.
- **Doğrulama** (sırayla): tuşun adı yoksa → desteklenmeyen; Ctrl ve Alt birlikteyse → AltGr; F4 + Alt → ayrılmış;
  tek başına olabilen tuşlar (sayı tuş takımı 0x60–0x6F, F1–F24 (F12 hariç), Pause, Scroll Lock) → geçerli; diğerleri
  (harf, rakam, Insert/Home/End/PgUp/PgDn, oklar) yalnız Ctrl+Shift, Alt ya da Alt+Shift ile geçerli, değilse →
  değiştirici gerekir.
- **Tuş adları**: rakam ve harfler kendisi; "Num 0".."Num 9", "Num *", "Num +", "Num -", "Num .", "Num /"; "F1".."F24"
  (F12'nin adı yok: hata ayıklayıcıya ayrılmış); "Pause", "Scroll Lock", "Insert", "Home", "End", "Page Up", "Page
  Down", "←", "↑", "→", "↓". Görünen ad: değiştiriciler "Ctrl", "Alt", "Shift" sırasıyla, "+" ile, sonda tuş adı
  (ör. "Ctrl+Shift+9", "Alt+F2", "Alt+Shift+S").

Testlerden örnekler:
- Varsayılan: her işin biri değiştiricisiz, biri Ctrl+Shift iki tuşu; "Num 9" ve "Ctrl+Shift+9" `shortcut.action.translateScreen`; aynı tuş
  iki kez yok; ilk 8 kayıt değiştiricisiz.
- `shortcut.action.translateScreen` yuva 0 = Alt+F2 → yerinden edilen yok; çalışan tuşlar [Alt+F2, Ctrl+Shift+9]; Num 9 hiçbir iş yapmaz.
- `shortcut.action.translateScreen` yuva 0 = Num 5 → yerinden edilen `shortcut.action.freeArea`; `FreeArea` işinin yuva 0'ı kapalı, çalışan tuşu yalnız
  Ctrl+Shift+5.
- `settings.connection.clickThrough` yuva 1 kapatılınca tek tuşu kalır; yeniden varsayılan verilince liste boşalır.
- Elle bozulmuş dosya (`shortcut.action.translateScreen` yuva 1 = değiştiricisiz "A"; `shortcut.action.freeArea` yuva 1 = Num 9) → "A" atlanır; Num 9
  `shortcut.action.translateScreen`'de kalır (önce gelen kazanır).
- Doğrulama: Num 9 ✓, F2 ✓, F12 ✗(desteklenmeyen), Esc ✗(desteklenmeyen), T ✗(değiştirici), Shift+T ✗, Ctrl+C ✗,
  Alt+T ✓, Alt+Shift+T ✓, Ctrl+Shift+T ✓, Ctrl+Alt+3 ✗(AltGr), Alt+F4 ✗(ayrılmış).

### 9.4 Kısayol metni
- Bir işin "tuşları" metni: çalışan tuş yoksa yok; bir tane ise onun adı; iki ise `shortcut.keysTwo`.
- Başlık kalıbı: tuşlar yoksa yerine `shortcut.none` yazılır. Cümle kalıbı: tuşlar yoksa bütün cümle yerine
  `shortcut.noneSentence` gelir.

### 9.5 Kısayolların çalışması
Genel kısayollar yalnız **çeviri sürerken** ve kayıt beklenmiyorken Windows'a kaydettirilir (arka planda da çalışır);
tablo ayarlardan her değişiklikte yeniden kurulur. İşler: Bölge n'i çevir → o ek bölgeyi bir kez oku/çevir; Duraklat →
canlı altyazıyı duraklat/sürdür; Görüntüyü yenile → Ayarlar'daki önizlemeyi yenile; `shortcut.action.freeArea` → serbest alan
penceresi (`yan-pencereler.md` §6); `shortcut.action.translateScreen` → ekranı çevir/kaldır; `settings.connection.clickThrough` → `OverlayClickThrough`'u
tersine çevir.

---

## 10. OBS katmanı

### 10.1 OBS kartı (başlıksız)
1. İpucu (altta 12): `settings.obs.hint` (Yayını capture card ile mi
   yapıyorsunuz? OBS'de bu adresle bir Tarayıcı kaynağı ekleyin (genişlik 1920, yükseklik 1080)…)
2. Sıra: sağda ikincil `common.copy` (solunda 12), solda kalan genişliği dolduran salt okunur metin kutusu
   (Consolas yazı tipi, dikeyde ortalı): `http://localhost:<kapı>/obs` (kapı altyazı sunucusunun gerçekte açıldığı kapı;
   normalde 8787).
3. İpucu (üstte 12): `settings.obs.otherComputerHint`
4. **Ağ adresi bölmesi** (yalnız bilgisayarın yerel ağ adresi bulunabiliyorsa): ipucu (üstte 12, altta 8) `settings.obs.networkAddressHint` + aynı düzende Kopyala düğmesi ve `http://<yerel IP>:<kapı>/obs`.
- Kopyala: metin panoya yazılır, düğmenin yazısı `common.copied` olur (geri dönmez). Pano başka uygulamada
  kilitliyse sessizce geçilir.

### 10.2 Yayın için pencere kartı (başlık `settings.obs.streamWindow`, üstte 16)
1. İpucu (altta 12): saydam tarayıcı kaynağı olmayan yayın uygulamaları (TikTok LIVE Studio, Streamlabs vb.) için yayın
   penceresini açıp Pencere yakalama ile eklemek (pencerenin adı `source.streamWindow.title`) ve zeminini Chroma key ile
   silmek.
2. Sıra (altta 12): `settings.subtitle.background.label` (sağda 12) + açılır liste (180 genişlik): `source.streamWindow.background.green` | `source.streamWindow.background.black` | `source.streamWindow.background.magenta`. Bu seçim **ayar dosyasında değil** şifreli depoda `streamBackground` anahtarında küçük
   harfli adla durur (`green`/`black`/`magenta`); okunamazsa yeşil. RGB: yeşil 00FF00, siyah 000000, mor FF00FF.
   Değişince kaydedilir; aynı değerse hiçbir şey.
3. İkincil `settings.obs.openStreamWindow` → yayın penceresi açılır (ayrı belge).
4. İpucu (üstte 12): pencereyi yayın boyunca açık ve önü kapanmadan tutmak; çeviri sürerken altyazılar yalnız TV'de
   gösterilse de bu pencerede görünür.

---

## 11. `settings.section.pictureSource`

### 11.1 PlayStation kartı (konsol türü PlayStation iken)
1. Sıra: `settings.source.readFrom` (sağda 16) + açılır liste (en az 260):
   `settings.source.frame.ps5` (`Ps5`) | `settings.source.frame.remotePlayWindow` (`RemotePlayWindow`) | `settings.source.frame.captureWindow`
   (`CaptureWindow`) → `FrameSource` (varsayılan `Ps5`). Bkz. §0 kural 2 ve 12.
2. **Uygulama sırası** (üstte 12; yalnız pencere): `settings.source.remotePlayApp.label` (sağda 16) +
   liste (en az 260): `settings.source.remotePlayApp.automatic` (`Automatic`) | **PS Remote Play** (Sony'nin uygulaması, verbatim ad; `Sony`) |
   **chiaki-ng** (`Chiaki`) → `RemotePlayApp` (varsayılan `Automatic`).
3. Pencere ipucu (üstte 12; yalnız pencere): `settings.source.windowHint`
4. **OBS/oyun penceresi bölmesi** (üstte 12; yalnız `CaptureWindow`):
   - ipucu (altta 8): `settings.source.captureWindowHint`
   - sıra: sağda ikincil `settings.source.refreshWindows` (solunda 10), solda liste (en az 250). Öğeler
     "‹pencere başlığı› (‹süreç adı›)". Kayıtlı pencere şu an açık değilse listenin başına `settings.source.windowNotOpen`
     (%1 başlık, %2 süreç) öğesi eklenir ve seçili gösterilir. Kayıtlı olanla aynı (süreç adı **ve**
     başlık eşit) öğe seçili.
   - Liste boşsa ipucu (üstte 8): `settings.source.noWindows`
   - Liste bölme her görünür olduğunda ve düğmeyle yenilenir; yenilerken seçim olayı ayar yazmaz. Seçim → `CaptureWindow`
     = {`ProcessName`, `Title`} (tanıtıcı ya da süreç kimliği saklanmaz). Pencere yoksa kaynak değiştirilmez.
5. **Kurulum satırları** (yalnız pencere; ilki üstte 12, ikincisi 8): solda Sony'nin PS Remote Play'i / chiaki-ng (ikisi de verbatim ad), sağda
   kuruluysa ipucu `translation.model.installed`, değilse ikincil düğme `setup.psnAccount.downloadRemotePlay`
   (`https://remoteplay.dl.playstation.net/remoteplay/`) ya da `setup.psnAccount.downloadChiaki`
   (`https://github.com/chiaki-ng/chiaki-ng/releases/latest`); tarayıcıda açılır. "Kurulu mu" bilgisi platform
   belgesindedir.
6. PS5 ipucu (üstte 12; yalnız PS5): `settings.source.ps5Hint`
7. **Hesap bağla satırı** (üstte 12): `FrameSource` = PS5 **ve** (PSN hesabı **ya da** eşleşmiş PS5 yoksa). Solda (sağda
   170 boşluk bırakarak) `settings.source.notLinked`, sağda ikincil
   `settings.source.linkAccount` → kurulum sihirbazı "ikinci hesap" adımına alınır ve Ayarlar **kapanır** (sihirbaz
   ana pencerede görünür).
- Bölmelerin görünürlüğü kaynak seçilince yenilenir.

### 11.2 Xbox kartı (konsol türü Xbox iken; PlayStation kartı gizli)
Anahtar `settings.source.xboxLegacyFrameRate` → `XboxLegacyFrameRate`
(varsayılan kapalı); ipucu (üstte 6): `settings.source.xboxLegacyFrameRateHint` Çeviri sürerken değişirse çeviri yeniden başlar (§0, 12).

Not: "konsol türü" (PlayStation/Xbox, sihirbazda seçilen ve şifreli depoda tutulan) Bağlantı bölümündeki `GameConsole`
ayarından ayrıdır; bu sayfa ve `settings.section.passcode` bölümü konsol türüne bakar.

---

## 12. `settings.section.passcode` (yalnız PlayStation)

Tek kart:
- İpucu (altta 12): `settings.passcode.hint` (şifre bu bilgisayarda şifreli saklanır)
- **Kayıtlı değilse**: yan yana gizli giriş kutusu (160 genişlik, en çok 4 karakter) + ikincil `common.save`
  (solunda 12). Kaydet her zaman basılabilir.
- **Kayıtlıysa**: solda Tamam yazısı `settings.passcode.saved`, sağda ikincil `settings.passcode.remove`.
- Hata satırı (hata yazısı, üstte 8, başta gizli): `settings.passcode.error`
- Kaydet: değer kırpılır; **tam 4 karakter ve hepsi '0'–'9'** değilse kaydedilmez ve hata görünür. Geçerliyse şifreli
  depoya (`loginPasscode`) yazılır, hata gizlenir, kutu boşalır, görünüm kayıtlı hâle geçer. Şifre arayüze hiç geri
  okunmaz.
- Kaldır: depodan silinir, görünüm kayıtlı değil hâline döner.
- Etki: bir sonraki PS5 bağlantısında PS5 şifre isterse Nino gönderir (Remote Play belgesi).

Mac farkı: Mac'te alan boşken Kaydet soluk; Windows'ta değil.

---

## 13. `settings.section.systemHealth`
Bölüm başlığı altında `settings.section.systemHealth` sayfası (`yan-pencereler.md` §4). Sayfa yalnız bu bölüm görünürken kendini
yeniler.

## 14. `settings.section.about`
Tek kart, kayan sıra, üç ikincil düğme (aralarında 12):
- `settings.section.about` → Hakkında penceresi (sahibi Ayarlar).
- `settings.about.reportProblem` → `settings.about.reportProblem` penceresi (sahibi Ayarlar).
- `home.robot.askNino` → Nino'ya Sor penceresi (sahibi **her zaman ana pencere**: Ayarlar kapanınca sohbet
  kapanmasın).

## 15. Sıfırla
Tek kart:
- İkincil renkli gövde yazısı (altta 16): `settings.reset.description`
- Kayan sıra: ikincil `settings.reset.fromTv` (yatay iç boşluk 16, sağda 12) ve
  ikincil `settings.reset.everything` (yatay iç boşluk 16, yazı `danger` rengi: koyu `#FF8A80`, açık `#B3261E`).

Davranış:
- **TV'den itibaren**: çeviri durur; şifreli depodan `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete` silinir;
  TV bilgisi ve TV uygulaması durumu unutulur; `Output` = Computer ("TV'm yok") ise TV yapılır; sihirbaz **TV adımına**
  geçer; Ayarlar kapanır. PS5 hesabı ve eşleşmesi kalır (test).
- `settings.reset.everything`: önce Windows onay kutusu (uyarı simgesi, Tamam/İptal, varsayılan İptal): başlık
  `settings.reset.confirmTitle`, ileti `settings.reset.confirmMessage`. Tamam değilse bitti.
  Tamamsa: çeviri durur; Xbox oturumu unutulur; şifreli depodan `accountId`, `console`, `consoleKind`,
  `consoleKindLocked`, `xboxToken`, `xboxConsole`, `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete`,
  `loginPasscode` silinir; konsol türü PlayStation'a döner; capture card kurulumu biter; sihirbaz **Hoş geldin**
  adımından başlar; Ayarlar kapanır. Kullanıcı ayarları (ayar dosyası) ve çeviri anahtarları **silinmez**.

---

## 16. Klavye ve erişilebilirlik özeti
- Enter / Esc: Bitti (pencereyi kapatır). Kısayol kaydı sırasında bütün tuşlar kayda gider.
- Yerel model kutularında Enter, yazılanı kaydeder. Eski kodda Bitti varsayılan düğme olduğundan aynı Enter pencereyi de
  kapatabiliyordu (doğrulanmadı); yeni yazımda bu kutularda Enter yalnız kaydetsin, pencereyi kapatmasın.
- Sekme ile kenar çubuğuna bir kez girilir, oklar bölümler arasında döner; sonra içerikteki denetimlere geçilir.
- Yazısız anahtarların (oyun paketleri kartı) ekran okuyucu adı satır başlığıdır. İçe aktarma penceresinin hata satırı
  "kibar" canlı bölgedir.

## 17. Platforma bağlı kısımlar (Windows yetenekleri)
- **Tema**: kişiselleştirme kayıt defteri değeri (uygulamalar açık tema kullanır) ve sistem tercih değişikliği olayı
  (genel kategori) — `settings.appearance.system` için.
- **Genel kısayollar**: Windows kısayol kaydı (pencere tanıtıcısına bağlı); "meşgul" denemesi aynı kayıtla yapılır.
  Değiştirici bayrakları Windows'unkilerle aynı (Alt 1, Ctrl 2, Shift 4); sanal tuş kodları Windows VK kodları.
- **Güvenlik Duvarı**: kural var mı, ağ profili Ortak mı, yönetici izniyle kural ekleme (ayrıntı platform belgesinde).
- **Pencere listesi** (OBS/oyun penceresi kaynağı) ve "Remote Play uygulaması kurulu mu": platform hizmetleri.
- **Dosya seçici** (içe aktarma), **ileti kutuları** (onay/hata), **pano** (kilitliyse sessizce geçilir), **varsayılan
  tarayıcıda açma** (kabuk ile).
- **Şifreli depo** (DPAPI, `secure.dat`): anahtarlar, PS5 şifresi, yayın zemini, kurulum kayıtları.
