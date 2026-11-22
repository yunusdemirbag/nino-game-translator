# Windows: yan pencereler (tarif)

Ayarlar penceresinin dışındaki bütün küçük pencereler ve Ayarlar'a gömülen `settings.section.systemHealth` sayfası. Kod yoktur. Görsel
dil, metin kuralları, açık/koyu tema ve sağdan sola kuralları `ayarlar.md` §0'dadır (kart, ipucu, düğme türleri, anahtar,
bölmeli seçici vb. orada tarif edildi; renk değerleri de). Mac karşılıkları:
`git show claude/yeni-mac-c9961f:docs/yeni/mac/gecmis-hakkinda-saglik.md` ve `.../ninoya-sor.md`. Mac belgesinde
doğru yazan ortak mantık (eşikler, sunucu sözleşmesi, metin biçimleme) burada "Mac §x ile aynı" diye geçer; farklar ve
Windows'a özgü her şey yazılmıştır.

İçindekiler: 0 ortak · 1 Hakkında · 2 Geçmiş · 3 Oyun paketi içe aktarma · 4 `settings.section.systemHealth` · 5 Bilgisayardaki altyazı
penceresi · 6 `shortcut.action.freeArea` · 7 Bilgisayar sonuç kutusu · 8 capture card denetimi ve rehberi · 9 Nino'ya Sor ·
10 `settings.about.reportProblem` · 11 Güvenlik duvarı uyarı kartı · 12 Kullanılmayan "Baştan kur" seçim penceresi · 13 Platform.

---

## 0. Ortak

### 0.1 Tek pencere kuralı
Ayarlar, Geçmiş, Hakkında, `settings.about.reportProblem` ve Nino'ya Sor: aynı türden görünür bir pencere açıksa yenisi açılmaz; o
küçültülmüşse normale döner ve öne getirilir. Değilse yeni pencere sahibine bağlanır ve **kalıcı olmayan** (sahibini
kilitlemeyen) biçimde gösterilir; sahibi kapanınca kendisi de kapanır. Hepsi görev çubuğunda görünmez, sahibinin
ortasında açılır, zemini pencere zemini rengi, yazısı ana yazı rengidir.

### 0.2 Fotoğraflar (`settings.about.reportProblem` ve Nino'ya Sor ortak)
- Kabul edilen uzantılar (küçük harfe çevrilerek): png, jpg, jpeg, heic, heif, webp, bmp, gif, tif, tiff. Dosya
  seçicinin süzgeci aynı liste, adı `common.photo.filterName`, çoklu seçim.
- Yollar: dosya seçici; pencereye **sürükle-bırak** (yalnız dosya; metin kutuları dosyayı kendileri almasın diye önizleme
  aşamasında karşılanır; yer kalmadıysa ya da gönderiliyorsa bırakma "yok" imleciyle reddedilir; uzantısı uymayan
  dosyalar sessizce atlanır); **Ctrl+V**: panoda görüntü ya da dosya listesi varsa **ve** (odak bir metin kutusunda
  değilse ya da panoda metin yoksa) fotoğraf olarak eklenir; aksi hâlde normal metin yapıştırma. (Excel/OneNote gibi panoya hem metin hem resim yazanlarda metin kutusundayken metin yapışır.) Panoda dosya listesi varsa listedeki uygun dosyalar,
  yoksa panodaki görüntü alınır.
- Ekleme sırayla yapılır: görüntü arayüz iş parçacığında açılır, JPEG'e **arka planda** çevrilir; sınır (3) dolunca
  durulur. JPEG'e çevirme: (en uzun kenar, kalite) çiftleri sırayla denenir — kenar 1600, 1280, 1024, 800, 640; her
  kenarda kalite 70, 55, 40 — hedef boyuta (`settings.about.reportProblem` 900 KB, Nino'ya Sor 600 KB) sığan **ilk** sonuç alınır; hiçbiri
  sığmazsa o görüntü "açılamadı" sayılır.
- Herhangi biri açılamazsa (biçim, okuma, izin, pano hatası) en sonda tek hata: `common.photo.openFailed`. Yeni ekleme başlarken önceki hata gizlenir.

### 0.3 Yer tutucu yazılı metin kutusu
Temadaki metin kutusunun yer tutucusu yoktur; kutunun üstüne tıklamayı geçiren bir yazı konur: `textSecondary`, %75
saydam, kutunun iç boşluğuna göre hizalı (çok satırlı kutuda üstte, tek satırda dikeyde ortada). Kutu boşken görünür.

---

## 1. Hakkında penceresi

- Başlık `settings.section.about`; genişlik **460**, yükseklik içeriğe göre, boyutlanmaz. Açılış:
  Ayarlar › Hakkında › `settings.section.about` düğmesi (sahibi Ayarlar). Tek pencere kuralı.
- İçerik 32 iç boşluklu, yukarıdan aşağı, ortalı:
  1. 88×88 logo (yüksek kaliteli ölçekleme); üstünde aynı boyda, köşesi 19.9, 1 px `border` renkli çerçeve (koyu temada
     logonun kenarı zeminden ayrılsın).
  2. **Nino Game Translator** (verbatim; pencere başlığı yazısı, üstte 12).
  3. Sürüm (ipucu, üstte 4, altta 12): uygulamanın bilgi sürümü, "+" ve sonrası atılmış (ör. "0.1.0-beta.38"; derleme
     sürümü ön sürüm ekini taşımadığı için o kullanılmaz). Güncelleme denetimi de aynı değeri kullanır.
  4. İkincil gövde, ortalı: "Nino © 2026 Yunus Demirbağ" (verbatim).
  5. İkincil gövde, ortalı, kaydırmalı (üstte 4, altta 8): AGPL türetme bildirimi `about.basedOn` (%1 üst proje, %2
     sahibi; bütün dillerde aynı İngilizce metin). Üst projenin ve sahibinin adı bu belgede bilerek yazılmamıştır;
     depodaki `NOTICE` dosyasından alınır (eski ad LegacyNames'te). Bu satır yalnız burada ve NOTICE'ta geçer.
  6. Gövde, ortalı: `about.license`
  7. İkincil gövde (üstte 12): `about.remotePlayCredit`
  8. İkincil gövde, kaydırmalı (üstte 4): `about.xboxCredit`
  9. İkincil gövde, kaydırmalı (üstte 4): `about.modelCredit`
  10. Bağlantı satırı (üstte 12, ortalı): `about.sourceCode` (`https://github.com/yunusdemirbag/nino-game-translator`)
      · "  ·  " · **chiaki-ng** (`https://github.com/chiaki-ng/chiaki-ng`) · "  ·  " · **Greenlight**
      (`https://github.com/unknownskl/greenlight`). Tıklayınca varsayılan tarayıcı.
  11. Küçük yazı, ortalı (üstte 16): Sony marka uyarısı `about.sonyTrademark`.
  12. Küçük yazı, ortalı, kaydırmalı (üstte 4): Microsoft marka uyarısı `about.microsoftTrademark`.
  13. Birincil `common.close` (ortalı, üstte 20); Enter ve Esc ile de kapanır.
- Mac farkı: Windows'ta emek veren kartı ve "Built on" numaralı kartı yoktur; Xbox/Greenlight ve OPUS-MT satırları vardır.

---

## 2. Geçmiş penceresi

- Başlık `home.header.history`; **640 × 640**, en küçük **480 × 400**, boyutlanabilir. Açılış: ana ekrandaki geçmiş
  düğmesi. Tek pencere kuralı.
- Düzen (24 iç boşluk), üç satır:
  1. Üst (altta 16): büyük bölüm başlığı `home.header.history`; ipucu (üstte 4): `history.subtitle` — sayı 200.
  2. Orta (esnek): kart. İçinde:
     - Liste boşsa üstte ipucu: `history.empty`
     - Doluysa dikey kaydırılabilir liste (yatay kaydırma yok), **en yenisi üstte**. Satır: altta 1 px `border` çizgi,
       dikey iç boşluk 12. Sağda üstte ikincil `common.copy` (solunda 12, yatay iç boşluk 12). Solda:
       - küçük yazı, eş aralıklı rakamlar: "SS:dd:ss  ·  ‹kaynak›" — saat yerel saatle 24 saatlik; kaynak `history.source.pack`
         ya da `translation.engine.title`;
       - çeviri (başlık yazısı, üstte 4);
       - asıl İngilizce (küçük yazı, üstte 4).
  3. Alt (üstte 16): solda ikincil `history.copyAll` (sağında 8) ve ikincil `history.clear`; sağda
     birincil `common.close` (Esc ile de; Enter varsayılan değil). Liste boşken ilk ikisi soluk.
- Davranış:
  - Pencere açıkken geçmiş değişirse liste hemen yeniden çizilir (yeni satırlar üste eklenir).
  - Satırın `common.copy` düğmesi: panoya "çeviri + yeni satır + asıl metin"; başarılıysa o düğme `common.copied` olur.
  - `history.copyAll`: bütün satırlar düz metin: her kayıt "[SS:dd:ss] çeviri" + yeni satır + asıl metin; kayıtlar
    arası boş satır (iki yeni satır); saat yerel. Düğme `common.copied` olur (liste yeniden çizilince eski adına döner).
  - Pano başka uygulamada kilitliyse kopyalama sessizce olmaz, pencere açık kalır.
  - `history.clear`: **onay sorulmadan** geçmiş (bellekteki ve dosyadaki) silinir. (Mac'te onay penceresi var; Windows'ta yok.)
  - Geçmiş en çok 200 satır tutar, bir satırın en uzun kaydedilen hâli 500 karakter; kayıt biçimi `havuz-paketler`/veri
    belgesindedir.

---

## 3. Oyun paketi içe aktarma penceresi

- Ayarlar › oyun paketleri › `settings.packs.import` ile dosya ayrıştırıldıktan sonra **kalıcı (modal)** açılır (sahibi
  Ayarlar). Başlık `pack.import.title`; genişlik 460, yükseklik içeriğe göre, boyutlanmaz.
  Açılınca odak oyun adı kutusundadır.
- İçerik (24 iç boşluk), yukarıdan aşağı:
  1. `packImport.gameTitle` (başlık yazısı, altta 8) + metin kutusu. Başlangıç değeri: dosyanın önerdiği başlık
     (JSON'daki `title`/`game`), yoksa dosya adının uzantısız hâli.
  2. Sayı tablosu (üstte 16): iki sütun (esnek etiket | sağa yaslı, eş aralıklı rakamlı değer; satırlar arası 6):
     `packImport.usable` · `packImport.invalid` · `packImport.duplicates` · `packImport.conflicts`. Sayılar geçerli kültürle binlik ayraçlı.
  3. Hata satırı (hata yazısı, üstte 12, başta gizli; ekran okuyucuya "kibar" canlı bölge).
  4. Sağa yaslı düğmeler (üstte 16): ikincil `common.cancel` (Esc; sağında 8) ve birincil `packImport.install` (Enter; başta soluk).
- `packImport.usable` 0 ise hemen hata: `packImport.noUsable`
- `packImport.install` etkin = kullanılabilir satır > 0 **ve** ad boşluktan ibaret değil (ad her değiştiğinde yeniden bakılır).
- Yükle:
  1. Ad kırpılır; boşsa ya da satır yoksa bir şey yapılmaz. Hata gizlenir.
  2. Hedef klasör kullanıcı paket klasörü (`%LOCALAPPDATA%\Nino\packs`). Seçilen dosya hedef dosyanın kendisiyse (aynı
     kimlik → aynı yol) hata: `pack.import.error.sameFile`.
  3. Hedef `‹kimlik›.json` (kimlik kuralı Mac `havuz-paketler.md` §5: `community-…`). Dosya varsa onay kutusu (uyarı
     simgesi, Evet/Hayır, varsayılan Hayır): başlık `packImport.replace.title`, ileti `pack.import.replaceMessage`. Hayır → bitti.
  4. Paket yazılır (önce aynı klasörde gizli geçici dosyaya, sonra yerine). Başarılıysa pencere "tamam" sonucuyla
     kapanır (Ayarlar paketleri yeniden yükler).
  5. Yazarken "kaynak = hedef" çıkarsa 2'deki hata; dosya/izin/veri hatasında `packImport.installFailed`. Pencere açık kalır.

---

## 4. `settings.section.systemHealth` sayfası (Ayarlar › `settings.section.systemHealth`)

Ayarlar'ın bu bölümüne gömülü bir sayfa. Görsel ağaçtayken **2 saniyede bir** yenilenir (yüklenince hemen bir kez),
çıkınca durur. Her yenilemede sağlık ölçümlerinin anlık kopyası ve bilgisayarın ağ türü alınır.

Kartlar yukarıdan aşağı (aralarında 16):
1. **Muhtemel sebep kartı** (başlıksız)
2. **Denetimler kartı** (başlıksız)
3. `health.recent.title` kartı
4. `tvApp.title` kartı (kurulum sihirbazındaki kartın aynısı; TV kurulumu belgesi)
5. `common.details` kartı (açılır-kapanır)
6. `device.title` kartı

### 4.1 Muhtemel sebep kartı
Sebep listesi ve sırası Mac §3.1 ile aynıdır. Sebep varsa: ilk sebebin başlığı başlık yazısıyla, başında "⚠  " (uyarı
işareti + iki boşluk); altında (üstte 6) gövde yazısıyla ne yapılacağı; sonra diğer sebepler "• ‹başlık›" (`textSecondary`,
üstte 4). Sebep yoksa ve çeviri sürüyor + görüntü şu an geliyorsa başlık yazısıyla "✓  " + `health.allGood`. Değilse kart gizli. (Mac'teki ayrı renkli simge yerine Windows'ta metnin başındaki işaret kullanılır.)
Sebep metinleri Windows'ta "Mac" demez, bilgisayar der (bkz. §4.2).

### 4.2 Denetimler kartı
- Üstte ipucu (`textSecondary`, altta 12): hiç ölçüm yoksa `health.checks.hint.noData`; ölçüm var ama ölçüm oturumu bitmişse `health.checks.hint.lastSession`; değilse gizli.
- Satırlar, aralarında ayraç (dikey 8). **Satır**: üst sırada solda ad (yarı kalın), sağda 8×8 renkli nokta + 6 boşluk +
  yarı kalın seviye adı (seviye renginde); altında değer (`textSecondary`, kaydırmalı); seviye **uyarı ya da sorun** ise
  altında (üstte 4) ana renkte ne yapılacağı. (Mac'teki satır başı simgesi Windows'ta yoktur.)
- Seviyeler ve renkleri: ölçülmedi `textSecondary` `health.level.unknown`; iyi `success` `health.level.good`;
  uyarı `warning` `health.level.warning`; sorun `danger` `health.level.problem`. Eşikler Mac §3 ile aynı.

| Satır | Ad | Değer | Ne yapılacağı |
|---|---|---|---|
| Ağ | `health.check.network.name` (Windows'a özgü metin; Mac metnine dönüşüm uygulanmaz, Türkçe ek bozulmasın) | `health.check.network.wired` / `.wifi` / `.other` / `.offline`; ölçülüyorsa denetleniyor | ağ yoksa `health.check.network.advice.offline`; değilse `health.check.network.advice.loss` |
| `health.check.ps5.name` | `health.check.ps5.name` | Mac §3.2 ile aynı | son kopma sebebine göre Mac §3.2 tablosu |
| `health.check.picture.name` | `health.check.picture.name` | Mac §3.2 ile aynı | `health.check.picture.advice` |
| `health.check.speed.name` | `health.check.speed.name` | Mac §3.2 ile aynı | çevrimiçi çeviri etkinse **ya da** seçili çevrimiçi motor Yerel model ise `health.check.speed.advice.freeEngine`; değilse `health.check.speed.advice.closeApps` |
| TV | TV (verbatim) | TV'ye gitmiyorsa `health.check.tv.notSent`; çeviri kapalıysa `health.check.notStarted`; bağlı TV uygulaması > 0 ise `status.common.connected`, değilse `status.common.notConnected` | `health.check.tv.advice` |

  TV seviyesi: çeviri sürmüyor ya da altyazı TV'ye gitmiyorsa ölçülmedi; bağlı TV uygulaması varsa iyi; yoksa sorun.
  Windows'ta Mac'teki `tvApp.title` satırı ve "yerel ağ izni" uyarı bloğu bu kartta **yoktur** (TV uygulaması
  ayrı kartta).
- **Mac metinlerinden fark**: eski kod Mac'le ortak metinlerde "Mac" sözcüğünü "PC"ye çeviriyor, USB-C Ethernet
  adaptörü önerisini siliyordu. Yeni katalog bunları baştan Windows'a göre yazar (`health.*` anahtarları); dönüşüm yok,
  görünen sonuç aynı.
- Değer biçimleri (Mac §3.2 ile aynı): kopuk → `health.check.ps5.disconnectedFor` (en az 1); hiç
  bağlanamadı → `health.check.ps5.neverConnected`; kopma yok → `health.check.ps5.noDrops`; değilse `health.check.ps5.drops`. Görüntü:
  ölçüm yok `health.check.notStarted`, görüntü gelmiyor `health.check.picture.noPicture`, değer yok
  `health.check.picture.measuring`, değilse `health.check.picture.rate` (dakikada kayıp paket, tam sayı; donma, bir
  ondalık). Çeviri: ölçüm yok `health.check.notStarted`; ortanca yok ve satır > 0 `health.check.speed.allInstant`; satır
  yok `health.check.speed.noSubtitles`; değilse `health.check.speed.perLine` (ortanca/1000, bir ondalık sn; çeviri sayısı). Sayılar geçerli kültürün ondalık ayracıyla yazılır.

### 4.3 `health.recent.title` kartı
- Başlık `health.recent.title`; yalnız kayıtlı sorun varsa görünür. Kayıtlar Nino yeniden açılsa da kalır.
- En son **8** sorun, en yenisi üstte. Satır (altta 6): solda 150 genişlikte `textSecondary` tarih (yerel, kısa tarih +
  kısa saat; geçerli kültür), 12 boşluk, sorunun kısa adı (`health.problem.*`).
- Altında (üstte 6) `textSecondary` ipucu: otomatik bildirim açıksa `health.recent.autoOn`, kapalıysa
  `health.recent.autoOff`.

### 4.4 Ayrıntılar kartı
- Açılır-kapanır başlık `common.details` (yarı kalın); kapalı başlar. Açılınca düğmede `common.copied` yazıyorsa
  eski adına döner.
- İçinde (üstte 12): salt okunur metin kutusu — Consolas 12, yükseklik 260, satır kaydırma yok, iki yönde kaydırma.
  Klavye odağı kutudayken metin **yenilenmez** (seçim bozulmasın).
- Altında (üstte 12) yan yana: ikincil `health.details.copy` (sağında 8; panoya yazar, `common.copied`
  olur; pano kilitliyse sessizce geçer) ve ikincil `health.details.saveZip`.
- Hata satırı (`warning` renkli, başta gizli). En altta (üstte 8) `textSecondary` ipucu
  `health.details.privacy`.
- **Metin** (Türkçe, sabit, destek için; satır satır; etiket sözcüklerini yeni yazım seçer, sıra ve alanlar şunlar):
  1. Nino + derleme sürümü, Windows + işletim sistemi sürümü, mantıksal işlemci sayısı + çekirdek sözü
  2. motor (çevrimiçi çeviri etkinse motor adı, değilse ücretsiz sözü), çeviri (sürüyor/durdu), PS5 oturum evresi
  3. TV markası (ya da yok sözü), bağlı TV uygulaması sayısı, TV uygulamasının türü [sürümü] [hatası]
  4. Ölçüm özeti (`saglik-bildirim-sor.md` §1.3)
  5. boş satır, uzun tirelerle çevrili `altyazi.log` başlığı (dosya adı + "son satırlar" anlamı), altyazı günlüğünün son 40 satırı
  6. boş satır, aynı biçimde `tvinstall.log` başlığı, TV kurulum günlüğünün son 8 satırı
  Günlük dosyası yoksa ya da okunamazsa "-". Dosyanın en çok son 64 KB'si okunur (dosya başkası yazarken de açılır);
  boş satırlar atılır.
- **Zip**: altyazı günlüğünün klasöründeki (veri klasörü) adında ".log" geçen bütün dosyalar + ayrıntı metni
  "ayrintilar.txt" adıyla bir zip'e konur. Zip kullanıcının **İndirilenler** klasörüne (yoksa oluşturulur)
  "Nino-kayitlar-YYYY-AA-GG-SS-dd-ss.zip" adıyla yazılır ve Gezgin'de seçili gösterilir. Hata olursa `health.details.saveFailed`
  (%@ = sistem hata metni). Mac farkı: geçici klasöre düşme yolu yok.

### 4.5 `device.title` kartı (üstte 16)
- Başlık `device.title`. İpucu (`textSecondary`, altta 12): `device.hint`
- Satırlar, aralarında ayraç (dikey 8): solda 190 genişlikte yarı kalın, kaydırmalı etiket (sağında 12), sağda
  `textSecondary` kaydırmalı değer. Satır kimlikleri ve etiketleri: `app` `device.label.app` · `device` `device.label.device` · `system`
  `device.label.system` · `tv` TV · `console` `settings.connection.console` · diğerleri `device.label.status`. Değerlerin içeriği cihaz raporu belgesindedir (Mac §3.5 ile aynı ilkeler; değerler
  Türkçe ve sabit, TV'nin kullanıcı adı yazılmaz).
- Satırlar yalnız özet metni değiştiyse yeniden kurulur.
- İkincil `device.copy` (sola yaslı, üstte 12): özet metni panoya; `common.copied` olur
  ve **3 saniye** sonra (bir sonraki 2 sn'lik yenilemede) eski adına döner.

---

## 5. Bilgisayardaki altyazı penceresi

Mac karşılığı ekrandaki saydam altyazı penceresi. Ana pencere kurulurken **bir kez** oluşturulur, ana pencere kapanınca
kaldırılır. Kurulamazsa uygulama onsuz açılır (§5.8).

### 5.1 Pencere özellikleri
- Kenarsız, boyutlanmaz (boyutu kod verir), **saydam zeminli**, **her pencerenin üstünde**, görev çubuğunda yok,
  gösterilince odağı almaz, odaklanamaz. Başlığı "Nino".
- Ek pencere stilleri: **etkinleşmez** + **araç penceresi** (Alt+Tab'da görünmez). `settings.connection.clickThrough` açıkken ve ayar
  kipinde değilken **tıklamaları geçiren** stil de eklenir, değilse kaldırılır.
- Soldan sağa tutulur (tutamaklar ve taşıma aynalanmaz); satırın yönü satırın kendisinden seçilir (Arap harfi varsa
  sağdan sola, konuşmacı adıyla başlasa da).
- **Ekran kopyasından gizleme**: oyun penceresinden okunurken (kaynak oyun penceresi **ve** çeviri sürüyor) pencere ekran
  kopyalarına hiç girmez (Windows 10 2004+ "yakalamadan hariç tut" görüntü yakınlığı; değilse "yok"). Nino ekranın o
  alanını kopyalarsa kendi çevirisini yeniden okumasın. PS5 kaynağında yayın programları altyazıyı görür.

### 5.2 Ölçek ve boy
- **Ölçek** = ana ekran yüksekliği / 1080, 0.5–4 arasına kırpılır; yükseklik okunamazsa (0, NaN) 1. Örnek: 2160 → 2.
- **Yazı boyu** = ayardaki boy, 12–200 arasına kırpılır; ≤ 0 ise 46.
- **Pencere yüksekliği** = yuvarla(yazı boyu × ölçek × 8.1 + 140 × ölçek) (en çok üç satır ve kayma payı). Örnek: 46,
  ölçek 1 → 513. Boy 0 ya da −5 → 46'nınkiyle aynı.
- Ayarlar değişince yükseklik yeniden hesaplanır; **alt kenar yerinde kalır** (üst kenar kayar).

### 5.3 Yer
- **Kayıtlı yer** (`Overlay` = {`Left`,`Top`,`Width`}, WPF birimi, tüm ekranları kapsayan düzlemde; yoksa `null`):
  değerleri sonlu ve genişlik > 0 ise genişlik [320, max(320, tüm ekranların genişliği)] aralığına kırpılır; pencere tüm
  ekranlar alanında yatayda en az min(80, genişlik), dikeyde en az min(80, yükseklik) görünüyorsa o yer kullanılır.
- Değilse **varsayılan**: genişlik = max(320, yuvarla(çalışma alanı genişliği × 0.7)); yatayda ortalı; üst = çalışma
  alanı altı − çalışma alanı yüksekliği × 0.04 − pencere yüksekliği. Çalışma alanı okunamazsa tüm ekranlar, o da
  okunamazsa 0,0,1280×720; yükseklik geçersizse 46/ölçek 1'in yüksekliği.
- Testlerden (ekran 1920×1080, çalışma alanı 1920×1032, yükseklik 500): kayıt yok → genişlik 1344, sol 288, üst
  1032 − 41.28 − 500 = 490.72. (100, 400, 1000) kalır. NaN/sonsuz/0/−50/NaN genişlik → varsayılan. Sol 2100, sol −3000,
  üst 1060, üst −480 (ekran dışı) → varsayılan. Solda ikinci ekran (−1920, 0, 3840×1080) ile (−1600, 500, 1200) kalır.
  Genişlik 99999 → 1920; 10 → 320. Ekran bilgisi boş/NaN olsa da sonlu ve ≥ 320 genişlikte bir yer çıkar.
- **Oyunun üstüne oturma**: kaynak oyun penceresi **ya da** capture card ise ve oyunun ekrandaki alanı biliniyorsa ve ayar
  kipinde değilse pencere oyunun alt kısmına oturur: genişlik = yuvarla(oyun genişliği × 0.9), yatayda oyuna ortalı, alt
  kenar = oyun altı − oyun yüksekliği × 0.03. Oyun alanı ekran pikseli gelir, sistem DPI'ı / 96'ya bölünerek WPF birimine
  çevrilir. Kayıtlı yer değişmez; koşul bitince (oyun penceresi kapandı, ayar kipine girildi) kayıtlı yere dönülür.
- **Sürükleme**: tıklamalar geçmiyorsa pencerenin herhangi bir yerinden (tutamak ve düğmeler hariç) sol düğmeyle taşınır;
  bırakınca yer kaydedilir.
- **Kaydetme**: sol, üst, genişlik sonlu ve genişlik > 0 ise yuvarlanarak `Overlay`'e yazılır; değilse yazılmaz (JSON'a
  NaN yazılamaz). Örnek: (10.2, 20.6, 799.7) → (10, 21, 800). Kayıt sıradan ayar yazımıdır (TV'ye görünüm de gider).

### 5.4 Olaylar
Pencere denetleyicinin "bilgisayar olayları"nı dinler: TV'ye giden altyazı olaylarının aynısı, yalnız altyazı bilgisayarda
gösteriliyorsa gelir. Satır yığını TV uygulamasıyla aynı yığın kuralıdır (çekirdek "altyazı yığını": şimdiki satır,
önceki satırlar, solma 0.4 sn). Her olayda yığının önceki satırları koruma seçeneği (`style.stackPrevious` karşılığı) ayardan alınır.

| Olay | Ne olur |
|---|---|
| Altyazı | "ekranı çevir süresi" sıfırlanır; satır yığına eklenir (süre, paragraf, "öncekinin düzeltilmişi mi" bilgisiyle) |
| `shortcut.action.translateScreen` | metin paragraf olarak yığına eklenir; "ekranı çevir süresi" = şimdi + süre |
| `shortcut.action.translateScreen` temizle | "ekranı çevir süresi" henüz dolmadıysa yığın gizlenir; süre sıfırlanır |
| Bölge (ek alan) | kimliği yoksa yok sayılır; o kimliğin kutusu kaldırılır; metin boş değilse (metin, oyundaki yeri) ile yeniden eklenir |
| Bölgeleri temizle | bütün bölge kutuları kalkar |
| Temizle | "ekranı çevir süresi" dolduysa yığın temizlenir (dolmadıysa `status.screenTranslate.working` yazısının ardından gelen temizlik çevirileri silmesin diye yok sayılır) |
| Gizle (çeviri durduysa ya da altyazı bilgisayar ekranından çıktıysa) | yığın gizlenir, bölgeler silinir |

Her olaydan sonra yeniden çizilir. Ayarlar değişince (yazı boyu/renk/zemin) kutular yeniden kurulur; tıklama geçirme,
yükseklik ve oyun üstü yer yeniden uygulanır.

### 5.5 Çizim
- Kök: üst üste üç katman — ayar katmanı (§5.6), **satırlar** (alta yaslı; iç boşluk yatay 24×ölçek, alt 8×ölçek) ve
  **bölge kutuları** (üste yaslı; yatay 24×ölçek, üst 8×ölçek; tıklamayı geçirir).
- Görünen satırlar yığından alınır. Ayar kipindeyse ve satır yoksa tek örnek satır gösterilir: `overlay.sample`
  şimdiki satır rolünde.
- **Satır kutusu** (her satır kimliği için bir kez kurulur; solma animasyonu yeniden başlamasın diye saklanır):
  - yazı boyu = max(1, yazı boyu × ölçek × (şimdiki satırsa 1, değilse 0.8) × satırın sarma küçültmesi) — uzun çeviri en
    çok 3 dengeli satıra bölünür, sığmazsa biraz küçülür (çekirdek sarma kuralı; kutuya sarılmış metin yazılır);
  - zemin siyah, saydamlık = (arka plan %, 0–100) / 100 × (şimdiki 1, değilse 0.83) — kullanıcının değeri, "örtme
    kuralı" uygulanmaz;
  - "bant" şeklinde köşe 0, iki yana −24×ölçek taşar, yatayda yayılır (İngilizce yazıyı yanlardan da örter); değilse köşe
    10×ölçek, yatayda ortalı;
  - iç boşluk: şimdiki 26×10 (×ölçek), diğerleri 20×6 (×ölçek); üstte 14×ölçek boşluk;
  - saydamlık rolüne göre: şimdiki 1, önceki 0.6, daha eskiler 0.45;
  - yazı: kalın ayarı açıksa kalın, değilse yarı kalın; renk beyaz ya da sarı `#FFE135`; kaydırmalı; paragrafsa sola,
    değilse ortaya yaslı; satır yüksekliği boy × 1.3; siyah, tam opak, aşağı yönlü gölge (derinlik 2×ölçek, bulanıklık
    4×ölçek); seçili altyazı yazı tipi (Sade'de pencerenin yazı tipi).
  - Satır "soluyor" olarak işaretlenince (ilk kez) saydamlığı 0.4 sn'de 0'a iner.
- **Bölge kutusu** (ek alan çevirisi; üstten sırayla, oyundaki yerinin üst kenarına göre): yazı boyu = max(12, yazı boyu
  × ölçek × 0.55); zemin siyah %85 (alfa 0xD9); köşe 8×ölçek; iç boşluk 14×6 (×ölçek); altta 10×ölçek; yatay hiza: oyundaki
  yazının yatay ortası < 0.4 ise sola, > 0.6 ise sağa, değilse ortaya (yeri yoksa ortada); yarı kalın, aynı renk ve yazı
  tipi, satır yüksekliği × 1.25, kaydırmalı.
- **Görünürlük**: altyazı bilgisayarda gösteriliyorsa **ve** (satır ya da bölge kutusu varsa) gösterilir, değilse
  gizlenir. Altyazı yokken pencere gizlidir.
- **Zamanlayıcı**: yığının bir sonraki değişme anına (en az 0.01 sn sonra) kurulur, dolunca yeniden çizilir.

### 5.6 Ayar kipi (`settings.connection.adjustSubtitleWindow`)
Ayarlar'daki ya da Bağlantı kartındaki düğme denetleyicideki "ayar kipi"ni açar. Kipteyken:
- Tıklamalar geçmez (stil kaldırılır); pencere oyunun üstüne oturmaz, kayıtlı yerindedir.
- Ayar katmanı görünür: pencereyi dolduran, %35 siyah dolgulu (alfa 0x59), 2 kalınlıkta `accent` renkli (tema yoksa
  `#FFC83D`), 4-3 kesikli, köşesi 14 dikdörtgen; üstte ortada (12 dış boşluk) sıra: beyaz yarı kalın `overlay.adjust.hint` + solunda 12 boşlukla
  birincil `common.done` (basınca ayar kipi kapanır).
- Sol ve sağ kenarda dikeyde ortalı, 6×48, köşesi 3, `accent` dolgulu tutamak (kenardan 6 içeride; yatay boyutlandırma
  imleci). Sürükleyince **ortası yerinde kalarak iki yana eşit** büyür/küçülür: yeni genişlik = (genişlik + 2 × kayma)
  [sağ tutamakta kayma sağa artı, solda sola artı], en az 320, en çok tüm ekranların genişliği (okunamazsa sınırsız;
  genişlik sonlu değilse 320); sol = orta − genişlik/2. Bırakınca yer kaydedilir. Örnekler: (1000, sınır 200) → 320;
  NaN → 320; 5000 (sınır 1920) → 1920; 900 (sınır NaN) → 900.
- Altyazı bilgisayarda gösterilmez olunca ayar kipi kendiliğinden kapanır.

### 5.7 `settings.connection.clickThrough` kısayolu
Varsayılan Num 7 / Ctrl+Shift+7 ayarı tersine çevirir (yalnız çeviri sürerken). Test: iki kez çağrılınca açık → kapalı.

### 5.8 Hata koruması
Penceredeki her iş (zamanlayıcı, tutamak, sürükleme, olay, ayar değişikliği, gizleme, "Bitti") korumalı yapılır: hata
olursa hata günlüğüne (`hata.log`) yazılır, pencere gizlenir, bu oturumda bir daha hiçbir iş yapılmaz, kullanıcıya
**bir kez** ileti gösterilir; uygulama açık kalır, çeviri (TV'ye, OBS'ye) devam eder. İleti `overlay.error.message` + boş satır + "‹hata türü›: ‹hata iletisi›".

---

## 6. `shortcut.action.freeArea` penceresi

`shortcut.action.freeArea` kısayolu (varsayılan Num 5 / Ctrl+Shift+5; yalnız çeviri sürerken) açar.

- Açılış: pencere zaten açıksa öne getirilir. Son kare yoksa hiçbir şey olmaz. Açılırken **son kare dondurulur** (pencere
  açıkken yeni kareler gelmez).
- Pencere: kenarsız, boyutlanmaz, **ekranı kaplar** (büyütülmüş), her şeyin üstünde, görev çubuğunda yok, zemini siyah,
  imleç artı. Soldan sağa tutulur. Başlığı "Nino".
- İçerik: kare boyunda bir tuval (kare piksel boyutu), oran korunarak ekrana sığdırılır (kenarlarda siyah boşluk kalabilir).
  Tuvalde kare resmi (BGRA, 96 dpi), seçim çerçevesi ve sonuç kutusu. Üstte ortada (üstten 12) ipucu: beyaz, %70 siyah
  zeminli (alfa 0xB3), 16×8 iç boşluk, 15 boyunda: `freeArea.hint`
- **Seçim çerçevesi**: `accent` kenar, kalınlık max(2, kare yüksekliği / 360), dolgu RGB(245,184,61) alfa 40.
- **Sonuç kutusu**: siyah %90 zemin (alfa 0xE6), köşe = kare yüksekliği × 0.012, iç boşluk = kare yüksekliği × 0.018;
  yazı beyaz, boy max(16, kare yüksekliği × 0.032), kaydırmalı, en çok kare genişliğinin yarısı. Yeri: seçimin altına
  (boşluk = kare yüksekliği × 0.012); taşarsa seçimin üstüne; sonra dikeyde [0, kare yüksekliği − kutu] ve yatayda
  [0, kare genişliği − kutu] aralığına kırpılır; sol kenar seçimin sol kenarı.
- Fare:
  - Sol basış: başlangıç noktası (tuval koordinatı, kareye kırpılmış) alınır; sonuç kutusu gizlenir; çerçeve görünür;
    fare yakalanır. Sürükledikçe çerçeve başlangıçla şimdiki nokta arasında.
  - Bırakınca: dikdörtgen genişliği karenin %1'inden ya da yüksekliği %1'inden küçükse seçim iptal (çerçeve gizlenir).
    Değilse yeni sıra numarası alınır, kutuda `freeArea.translating` yazar, alan (üst, alt, sol, sağ oranları) donmuş
    karede bir kez okunup çevrilir. Sonuç gelince bu arada yeni seçim yapıldıysa ya da pencere kapandıysa yok sayılır.
  - Sonuçlar: gösterildi → çeviri; yazı yok → `status.area.noText`; meşgul (önceki
    istek bitmedi) → `freeArea.translating`; diğer → `freeArea.failed`
  - Sonuç **TV'ye de** gönderilir, `settings.area.showResult` ayarı (`FreeAreaTarget`) Bilgisayar değilse. Pencere her durumda
    sonucu kendisi gösterir.
  - Gösterildiyse ve ayar **yalnız TV** ise 700 ms sonra (sıra numarası değişmediyse) pencere kendiliğinden kapanır.
  - Kapatmadan başka alanlar da seçilebilir.
- Kapanma: sağ tık; **Esc** — basma olayı yutulur ve pencere tuş **bırakılınca** kapanır (tuş basılı kalıp tekrarlansa
  bile arkadaki Ayarlar penceresine ulaşıp onu da kapatmasın).
- Testler: çeviri durmuşken alan çevirisi "çeviri sürmüyor" ve sonuçsuz; çeviri sürerken boş karede "yazı yok"; yeni
  ayarda sonuç yeri TV.

---

## 7. Bilgisayar sonuç kutusu

Ek bölgenin (Alan 1–3) çevirisinin sonuç yeri `settings.area.target.pc` ya da `settings.area.target.both` ise denetleyici (metin, süre ms) ile
bildirir ve bu kutu gösterilir.

- Yeni kutu gelince önceki kapanır (tek kutu).
- Kenarsız, saydam zeminli, her şeyin üstünde, görev çubuğunda yok, gösterilince odak almaz; boyutu içeriğe göre, en çok
  çalışma alanı genişliğinin %70'i; el imleci.
- İçerik: siyah %93 zemin (alfa 0xEE), köşe 12, iç boşluk 20×14; yazı beyaz 24, kaydırmalı, yönü metne göre (Arapça sağdan
  sola).
- Yer: ölçüldükten sonra çalışma alanında yatayda ortalı, alt kenarı çalışma alanının altından 40 yukarıda.
- Tıklanınca ya da süre dolunca kapanır; süre en az 1500 ms.
- Testler: sonuç yeri Bilgisayar olan Alan 3 boş karede okununca kutuya `status.area.noText` gelir; sonuç yeri TV
  olan alan kutuyu hiç tetiklemez.

---

## 8. Kart (capture card) denetimi ve rehberi

### 8.1 Kart denetimi (canlı önizleme)
Ayarlar › Bağlantı'da (170 yükseklik) ve rehberin son sayfasında (220) kullanılır.

- **Önizleme çerçevesi**: siyah, verilen yükseklikte, köşe 14 (köşeden taşmasın diye 14 yarıçapla kırpılır), soldan sağa.
  İçinde üst üste: canlı görüntü yüzeyi, ortada yer tutucu, sol üstte durum hapı.
  - Yer tutucu: ortalı simge (30 boyunda; Segoe Fluent "Connect" U+E703, izin yoksa "Lock" U+E72E) ve altında (16,8,16,0
    boşluk) yarı kalın, ortalı, kaydırmalı yazı; ikisi de %85 beyaz.
  - Durum hapı: %50 siyah zemin, köşe 12, yükseklik 24, yatay iç boşluk 10, dış 10; içinde 7×7 nokta (sağında 6) + beyaz 11
    yarı kalın yazı.
- Altında: ayrıntı satırı (üstte 12; simge 16 + ipucu yazısı, ikisi de durum renginde), ikincil `cardGuide.preview.openCameraSettings` (üstte 12; Windows'un kamera gizlilik sayfasını açar), aygıt sırası (üstte 12): `cardGuide.preview.deviceLabel`
  (sağında 12) + liste (en az 260): `cardGuide.preview.automatic` + bulunan aygıt adları.
- Durumlar ve gösterilenler (çeviri sürmüyorken):

  | Durum | Ton (nokta rengi) | Hap yazısı | Yer tutucu | Ayrıntı |
  |---|---|---|---|---|
  | Okunuyor | iyi (`success`) | aygıt adı | gizli (görüntü var) | `cardGuide.preview.workingDetail` |
  | Siyah görüntü | uyarı (`warning`) | aygıt adı | gizli (siyah da olsa görüntü var) | `cardGuide.preview.blackDetail` |
  | `cardGuide.preview.noPermissionPill` | uyarı | `cardGuide.preview.noPermissionPill` | kilit + `cardGuide.preview.noPermissionPlaceholder` | ⚠ `cardGuide.preview.noPermissionDetail` + `cardGuide.preview.openCameraSettings` düğmesi |
  | Kart yok | uyarı | `cardGuide.preview.noCardPill` | kablo + `cardGuide.preview.searchingPlaceholder` | `cardGuide.preview.noCardDetail` |
  | Durdu | boşta (`textSecondary`) | `cardGuide.preview.noCardPill` | kablo + `cardGuide.preview.searchingPlaceholder` | yok |

  Simgeler: onay U+E73E, uyarı U+E7BA.
- **Çeviri sürerken ya da başlarken**: önizleme kartı hemen bırakır (kart aynı anda tek okuyucuya açılır); yer tutucu
  `cardGuide.preview.offWhileTranslating`; hap = denetleyicideki kart
  adı ya da `cardGuide.preview.deviceLabel`; ayrıntı ve izin düğmesi gizli; aygıt sırası soluk. Çeviri bitince önizleme kendiliğinden
  yeniden başlar.
- Aygıt sırası yalnız 1'den çok aygıt varsa görünür. Liste her aygıt değişikliğinde yeniden doldurulur; seçili = kayıtlı
  tercih (yoksa Otomatik). Seçim → tercih edilen kart (şifreli depoda `captureCardId`, bu bilgisayara özgü; Otomatik =
  silinir); önizleme açıksa yüzey temizlenir ve yeni tercihle yenilenir.
- Önizleme denetim görsel ağaca girince başlar (meşgul değilse), çıkınca durur.

### 8.2 Rehber (üç sayfa)
Kurulum sihirbazında (PS5 adımları yerine) ve Ayarlar'dan açılan pencerede kullanılır.

- Düzen: altta düğme sırası (üstte 16): ortada sayfa noktaları, solda hayalet **geri** düğmesi (en az 120 genişlik, 44
  yükseklik), sağda birincil **ileri** düğmesi (en az 200, 44; varsayılan düğme — Enter). Üstte kart (iç boşluk 0) içinde
  dikey kaydırılabilir, 32 iç boşluklu sayfa alanı.
- Noktalar: 3 tane, yükseklik 7, köşe 3.5, aralarında 7; geçerli sayfa 24 genişlik, diğerleri 7; geçerli ve öncekiler
  `accent`, sonrakiler `border`. Ekran okuyucu: `setup.stepCounter`.
- Düğme yazıları: geri = ilk sayfada ve pencerede `common.cancel`, değilse `common.back`; ileri = son sayfada
  `common.done`, değilse `common.continue`.
- Sayfa geçişi: yeni sayfa 28 birim yandan (Arapçada öteki yandan) 320 ms'de yavaşlayarak kayar ve 260 ms'de belirir.
- Geri: ilk sayfa değilse önceki sayfa; ilk sayfada pencerede pencereyi kapatır, sihirbazda capture card kurulumundan
  çıkar. İleri: son sayfa değilse sonraki; son sayfada "kurulum bitti" (TV seçimiyle) — §8.4 — ve (pencerede) kapanır.
- Başlangıç seçimi ("TV'ye mi"): capture card zaten seçiliyse ve altyazı TV'ye gidiyorsa TV, değilse bilgisayar.
- Sayfa düzeni: büyük başlık (28), altında (üstte 12) en çok 620 genişlikte ikincil açıklama, altında (üstte 20) içerik.

**Sayfa 1** — `cardGuide.page1.title`; açıklama: `cardGuide.page1.description`
İki seçim karosu (ikincisi üstte 12), tıklanabilir ve klavyeyle seçilebilir:
- Karo: kart; seçiliyse "etkin" (kenar `accent`). Solda 22'lik halka simgesi (seçili U+EC61 `accent`, değilse U+EA3A
  `textSecondary`; sağında 16), sağda başlık (başlık yazısı), açıklama (ipucu, üstte 6), kablo şeması (üstte 12): simge
  kutuları (36×30, köşe 8, `accentSoft` zemin (koyu `#132A55`, açık `#DDEBFA`), içinde 16'lık `accentText` simge) arasında
  küçük yazıyla "→" (Arapçada "←"), yanlarda 8 boşluk.
- `cardGuide.page1.monitorTitle` — `cardGuide.page1.monitorDescription`. Şema: kol (U+E7FC)
  → kablo (U+E703) → dizüstü (U+E7F8) → monitör (U+E7F4).
- `cardGuide.page1.tvTitle` — `cardGuide.page1.tvDescription`. Şema: kol → kablo →
  TV (U+E7F4).
- Seçili olmayana basınca seçim değişir ve sayfa (animasyonsuz) yeniden çizilir. Ekran okuyucu: adı başlık, durum
  `cardGuide.page1.selected`.

**Sayfa 2** — `cardGuide.page2.title`; açıklama: `cardGuide.page2.description`
Numaralı satırlar (28'lik `surface2` daire içinde 13 yarı kalın numara, sağında 12 boşlukla gövde yazısı; satır altı 16):
1. `cardGuide.page2.step1`
2. `cardGuide.page2.step2`
3. `cardGuide.page2.step3`
Sonra bilgi satırı (üstte 8, altta 12; "Info" U+E946 simgesi + `textSecondary`): `cardGuide.page2.netflixInfo` ve kulaklık
satırı ("Headphone" U+E7F6): `cardGuide.page2.headsetInfo`.

**Sayfa 3** — `cardGuide.page3.title`; açıklama TV seçiliyse `cardGuide.page3.descriptionTv`, değilse `cardGuide.page3.descriptionScreen`. İçerik: 220 yükseklikte capture card denetimi (§8.1).

### 8.3 Rehber penceresi (Ayarlar'dan)
Başlık `cardGuide.window.title`; **760 × 760**, en küçük **620 × 560**; görev çubuğunda yok; sahibi
Ayarlar'ın ortasında; **kalıcı (modal)**. İçerik 24 iç boşluklu rehber; rehber bitince ya da vazgeçilince kapanır.

### 8.4 Rehber bitince
Ayar tek yazımla: `VideoSource` = capture card, `Output` = TV seçildiyse TV, değilse Bilgisayar. Ayarlar'dan açılan
rehberde başka bir şey olmaz. Sihirbazda: capture card kurulumu biter; TV seçildiyse ve TV eşleşmemişse TV adımına, değilse
(model kuruluysa) deneme adımına, model yoksa çeviri (model) adımına geçilir.

---

## 9. Nino'ya Sor penceresi

Mac `ninoya-sor.md` §1 (robot), §3 (sohbet, biçimleme), §4 (sunucu) ile aynı mantık; Windows farkları aşağıda.

### 9.1 Pencere
- Başlık `home.robot.askNino`; **440 × 680**, en küçük **360 × 460**, boyutlanabilir; görev çubuğunda yok; tek
  pencere kuralı; **sahibi her zaman ana pencere** (Ayarlar'dan açılsa da; Ayarlar kapanınca sohbet kapanmasın).
- Açılış: ana ekranın ve kurulum sihirbazının yüzen robot düğmesi; Ayarlar › Hakkında › Nino'ya Sor.
- Açılınca sohbet çizilir ve odak yazı kutusuna gelir. Sohbet uygulama çalıştıkça bellekte tutulur (pencere kapatılıp
  açılınca kalır), uygulama kapanınca silinir.
- Düzen: üstte başlık şeridi, altta yazma alanı, ortada (kalan yer) dikey kaydırılabilir mesaj listesi.

### 9.2 Başlık şeridi
- İç boşluk sol 16, üst/alt 12, sağ 12; altta 1 px `border` çizgi.
- Solda 44×44 robot (göz kırpar; cevap beklenirken "düşünüyor"), 12 boşluk, iki satır: **Nino** (başlık yazısı) ve küçük
  yazı `ask.subtitle`.
- Sağda hayalet düğme `ask.newChat` (yatay iç boşluk 12; içinde `accentText` renkli 14'lük artı simgesi U+E710,
  8 boşluk, yazı; ipucu ve ekran okuyucu adı aynı). **Her zaman görünür** (Mac'te yalnız mesaj varken). Basınca sohbet
  sıfırlanır (bekleyen istek sonucu yeni sohbete karışmaz), ekler ve yazı kutusu temizlenir, odak yazı kutusuna.
- Windows'ta ayrı "Kapat" düğmesi ve `settings.about.reportProblem` modu yoktur (pencerenin kendi kapatma düğmesi).

### 9.3 Mesajlar
- Liste iç boşluğu yanlarda 16, üstte 16, altta 8. Her çizimde liste baştan kurulur (birkaç düzine balon) ve arka planda
  en alta kaydırılır.
- Sıra: (1) her zaman robotun **selamı** (Mac §3 ile aynı metin, arayüz dilinde; sunucuya gitmez); (2) sohbet boşsa ve
  beklenmiyorsa **öneri hapları**; (3) kayıtlar; (4) bekleniyorsa "yazıyor" satırı.
- **Balon**: iç boşluk 14×10; köşeler 18, konuşma kuyruğu tarafındaki alt köşe 6 (kullanıcıda sağ alt, robotta sol alt);
  kullanıcı balonu sağa yaslı, `accent` zemin, beyaz yazı; robot balonu sola yaslı, `surface2` zemin, ana yazı rengi. Balonun
  en büyük genişliği max(220, liste genişliği × 0.78 − 40); pencere boyutu değişince yenilenir.
- **Robot satırı**: solda 28×28 robot (göz kırpmaz; "yazıyor"da düşünür), altta hizalı, sağında 8, altında 2 boşluk; yanında
  balon ve (varsa) balonun altında rozet. Satırlar arası 12.
- **Kullanıcı balonu**: solda 48 boşluk, altta 12. Fotoğraf varsa üstte 96×96, köşesi 10 kırpılmış küçük resimler (doldurarak
  kırpılır; aralarında sağda ve altta 6; JPEG en çok 192 piksel genişlikte çözülür ve önbelleğe alınır); yazı da varsa
  resimlerin altında 8 boşluk; yazı kaydırmalı. (Windows'ta gönderilemedi işareti ve soluk balon yoktur; bunun yerine
  hata balonunda `common.retry`.)
- **Robot metninin biçimi** (blok kuralları Mac §3 "Robot balonu" ile aynı): paragraflar; numaralı adımlar (21'lik `accent`
  daire rozet, içinde beyaz 11.5 kalın numara; iki basamaklıysa yatay 4 iç boşluklu hap; sağında 8); maddeler (21×21 alanın
  ortasında 6'lık `accent` nokta); asılı girinti (iki sütunlu ızgara; ilk satır rozetle ortalansın diye yazı 1 aşağıda);
  bloklar arası 10, ardışık iki liste öğesi arası 8, ilk blok 0; http(s) bağlantıları `accentText` renkli, ipucunda adres,
  tıklayınca varsayılan tarayıcı. Sağdan sola dillerde ızgara aynalanır, rozet sağa geçer.
- **Bildirim rozeti** (robot cevabı bildirim açtıysa; üstte 6): tam yuvarlak hap, `successSoft` zemin (koyu
  `#123527`, açık `#DDF1E6`), iç boşluk 10×3, yazı `success` 12 yarı kalın `ask.reportSent`.
- **Öneri hapları**: soldan 36 içeriden, kayan sıra (altta 12); ikincil düğme, en az 34 yükseklik, yatay iç boşluk 14, aralarında
  sağda ve altta 8; yazı `accentText`. Dört öneri Mac §3 ile aynı; basınca **arayüz dilindeki** metni hemen soru olarak
  gönderilir (yazı kutusu ve ekler olduğu gibi kalır).
- **Uyarı balonu** (yerel, sunucuya gitmez; robot satırında):

  | Sonuç | Metin anahtarı | Düğme |
  |---|---|---|
  | yardımcı kapalı (503 + `assistant_disabled`) | `ask.alert.disabled` | birincil `settings.about.reportProblem` → `settings.about.reportProblem` penceresi (sahibi bu pencere) |
  | bugün çok soruldu (429, diğer) | `ask.alert.dailyLimit` | — |
  | yoğun (429 + `busy`) | `ask.alert.busy` | — |
  | reddedildi (400 ya da 413) | `ask.alert.rejected` | — |
  | başarısız (ağ, zaman aşımı, adres yok, diğer kodlar, 200 ama boş cevap) | `ask.alert.failed` | son kayıtsa ve beklenmiyorsa ikincil `common.retry` |

  Düğme: en az 34 yükseklik, yatay iç boşluk 16, üstte 10. `common.retry` son uyarı balonunu kaldırır ve aynı sohbeti
  yeniden gönderir. Yalnız "başarısız" yeniden denenebilir (Windows'ta "yoğun" yeniden denenmez; Mac'ten farklı).
  Windows'ta ayrı "çok büyük" sonucu yoktur (413 = reddedildi).
- **"Yazıyor" satırı**: robot düşünür; balonda üç nokta (7×7, `textSecondary`, aralarında 5, yanlarda 2 ve dikey 5 iç
  boşluk; başlangıç saydamlığı 0.35); hareket azaltılmadıysa her nokta 0.25↔1 saydamlık arasında 420 ms'de gidip gelir,
  sonsuz, aralarında 160 ms gecikme. Ekran okuyucu için görünmez `ask.typing` yazısı.
- **Ekran okuyucu**: son eklenen robot cevabı ya da uyarısının ilk yazısı "kibar" canlı bölge yapılır; adı "Nino: ‹metin›";
  yüklenince "canlı bölge değişti" duyurulur. "Yazıyor" satırı da duyurulur.

### 9.4 Yazma alanı
- Üstte 1 px `border` çizgi; iç boşluk 12×10. Yukarıdan aşağı: ek sırası, hata satırı, giriş sırası, not.
- **Ek sırası** (altta 4; ek yoksa gizli): her ek 56×56, köşe 10 kırpılmış küçük resim (sağında 8, altında 6); sağ üstünde
  (3,3 içeriden) 22×22 ikincil "✕" düğmesi (yazı 10; ipucu ve ad `common.photo.remove`).
- **Hata satırı** (hata yazısı, altta 8; başta gizli): fotoğraf hatası (§0.2).
- **Giriş sırası**, üç sütun:
  1. Ek düğmesi (simge düğmesi 40×40; 16'lık ataç simgesi U+E723; alta hizalı; ipucu `ask.attachTooltip`; ad `ask.attach`). 3 ek varken soluk.
     Basınca dosya seçici (başlık `ask.attach`).
  2. Yazı kutusu (yanlarda 8): çok satırlı, kaydırmalı, en çok 2000 karakter, en çok 132 yükseklik (sonra kayar), iç
     boşluk 14×9; yer tutucu `ask.placeholder`. **Enter gönderir, Shift+Enter yeni satır.**
  3. Gönder düğmesi: birincil, 40×40, iç boşluk 0, alta hizalı; içinde 16'lık beyaz "gönder" simgesi U+E724 (Arapça
     arayüzde yatayda aynalanır); ipucu ve ad `common.send`. Etkin = cevap beklenmiyor **ve** (yazı boşluktan ibaret
     değil **ya da** en az bir ek var).
- **Not** (küçük yazı, ortalı, üstte 8): `ask.disclaimer`
- Gönderme (düğme ya da Enter): beklenmiyorsa ve gönderilebilirse yazı ve ekler alınır, kutu ve ekler temizlenir, hata
  gizlenir, mesaj sohbete eklenir (kırpılmış metin, en çok 3 JPEG) ve gönderilir.
- Fotoğraf: §0.2; hedef boyut **600 KB**; mesaj başına en çok 3.

### 9.5 Sunucu
Mac §4 ile aynı sözleşme; Windows farkları: platform `"windows"`; HTTP zaman aşımı **60 sn**; adres havuz adresinin
kökü + `/v1/assistant` (havuz adresi yoksa "başarısız"); dil = **arayüz dili** kodu; cihaz özeti her mesajda yeniden
alınır; kuruluş kimliği havuzun kimliği, yoksa veri klasöründeki `report-install.txt` dosyasındaki (`settings.about.reportProblem`'le aynı).
İstek kurma kuralları (son 24 mesaj, 2000 karakter, yalnız fotoğraflı son iki kullanıcı mesajında fotoğraf, 6 MB gövde
sınırı) Mac §4 ile aynıdır.

---

## 10. `settings.about.reportProblem` penceresi

Mac `gecmis-hakkinda-saglik.md` §4 ile aynı içerik ve sunucu; **Windows'ta ayrı bir pencere**dir ve düzeni farklıdır.

### 10.1 Pencere
- Başlık `settings.about.reportProblem`; genişlik **540**, yükseklik içeriğe göre, boyutlanmaz; görev çubuğunda yok;
  tek pencere kuralı. Açılış: Ayarlar › Hakkında › `settings.about.reportProblem` (sahibi Ayarlar); Nino'ya Sor'daki "yardımcı kapalı"
  balonunun düğmesi (sahibi sohbet penceresi).
- İçerik dikey kaydırılabilir; en çok **çalışma alanı yüksekliği − 80** (küçük ekranda düğmeler taşmasın). Form 28 iç
  boşluklu. Açılınca odak açıklama kutusunda.
- **Taslak saklanmaz**: pencere kapanınca yazılanlar ve fotoğraflar kaybolur (Mac'ten farklı).

### 10.2 Form (yukarıdan aşağı)
1. Başlık `settings.about.reportProblem` (pencere başlığı yazısı, altta 16).
2. **`report.noticed.title` kutusu**: 1 px `border` kenarlı, köşe 12, iç boşluk 16 (kart değil, zeminsiz çerçeve).
   - Başlık `report.noticed.title` (başlık yazısı, altta 8).
   - Son **3 günün** sorunlarından en son **6**'sı (en yenisi üstte) ve sağlık özetindeki muhtemel sebebin başlığı.
   - İkisi de yoksa ipucu (üstte 4): `report.noticed.empty`
   - Sebep varsa yarı kalın, kaydırmalı satır; her sorun "• ‹yerel kısa saat›  ‹kısa ad›" (`textSecondary`, üstte 4).
   - Sağa yaslı birincil `report.sendProblems` (en az 120, üstte 12). Basmak "Gönder" ile aynıdır (açıklama
     boş olabilir). Gönderirken soluk.
3. `report.moreTitle` (başlık yazısı, üstte 20, altta 8).
4. Açıklama kutusu: çok satırlı (Enter yeni satır), kaydırmalı, yükseklik 140, en çok **4000** karakter, iç boşluk 12×10,
   yazı yukarıdan başlar; yer tutucu `report.descriptionPlaceholder`. Ekran okuyucu adı yer tutucuyla aynı.
5. Fotoğraf alanı (üstte 16): kayan sıra; her fotoğraf 88×88, köşe 12 kırpılmış, 1 px `border` kenar, doldurarak kırpılır;
   sağ üstünde (4,4 içeriden) 26×26 ikincil "✕" (yazı 12; ipucu/ad `common.photo.remove`). 3'ten azsa sonda ekleme düğmesi:
   88×88 ikincil, ortada 28 boyunda "+", ipucu/ad `report.addPhoto` → dosya seçici (başlık `report.addPhoto`).
   Aralar sağda ve altta 8. Altında ipucu (üstte 4): `report.photosHint`
6. İletişim kutusu (üstte 16): tek satır, en çok **200** karakter; yer tutucu `report.contactPlaceholder`.
7. Günlük satırı (üstte 16): solda başlık `report.includeLog.title` (başlık yazısı) + ipucu `report.includeLog.hint`; sağda anahtar (solunda 16; **varsayılan açık**).
8. Otomatik bildirim satırı (üstte 16): başlık `report.autoReport.title` + ipucu
   `report.autoReport.hint`; sağda anahtar = ayar `AutoReport` (varsayılan açık; değişince hemen ayara yazılır).
9. Gizlilik notu (küçük yazı, üstte 16): `report.privacy`
10. Hata satırı (hata yazısı, üstte 12; başta gizli).
11. Gönderim çubuğu (üstte 12; yalnız gönderirken): 3 yükseklikte belirsiz ilerleme çubuğu.
12. Sağa yaslı düğmeler (üstte 20): ikincil `common.cancel` (en az 100, sağında 12; Esc) ve birincil `common.send`
    (en az 120; **varsayılan değil**: Enter açıklamada yeni satır açar).

### 10.3 Gönderme
- Gönderilebilir = gönderilmiyor (açıklama boş olabilir). Gönder düğmesi bu kurala göre her yazıda yenilenir.
- Basınca: hata gizlenir; sunucu adresi = havuz adresinin kökü + `/v1/reports` (havuz adresi veri klasöründeki havuz
  ayarından; yoksa hemen "gönderilemedi" hatası). Gönderiliyor kipi: Gönder yazısı `report.sending` ve soluk,
  `report.sendProblems` soluk, açıklama ve iletişim salt okunur, günlük anahtarı ve fotoğraf ekleme soluk, ilerleme çubuğu
  görünür, imleç "uygulama başlıyor" imleci; sürükle-bırak ve Ctrl+V fotoğrafı reddedilir.
- İçerik: metin = kullanıcının yazdığı + Nino'nun tespitleri (muhtemel sebep, son sorunlar, sağlık özeti; elle gönderim);
  iletişim; günlük açıksa günlükler; fotoğrafların JPEG'leri; uygulama sürümü (§1'deki); `setup.welcome.translationLanguage`; havuz kuruluş
  kimliği (yoksa `report-install.txt`); cihaz özeti. Gövde biçimi Mac §4 ve çekirdek bildirim belgesiyle aynı; platform
  `"windows"`. Zaman aşımı 60 sn. Metin 4000'e, iletişim 200'e kırpılır; en çok 3 fotoğraf.
- **Günlükler** (her birinin **sonundan** payı kadar; toplam en çok 60 000 karakter): hata günlüğü (`hata.log`) 10 000,
  `remoteplay.log` 18 000, altyazı günlüğü (`altyazi.log`) 24 000, TV kurulum günlüğü (`tvinstall.log`) 8 000 — hepsi veri
  klasöründe. Günlükler ve gövde arka planda hazırlanır.
- Sonuç (gönderim bitince gönderiliyor kipi kapanır; pencere bu arada kapandıysa sonuç gösterilmez):

  | Sonuç | Kullanıcıya |
  |---|---|
  | gönderildi (200) | teşekkür ekranı (aşağıda) |
  | günlük sınır (429) | `report.error.dailyLimit` |
  | çok büyük (413) | `report.error.tooLarge` |
  | reddedildi (400) | `report.error.rejected` |
  | diğer / ağ hatası | `report.error.failed` |

  Hata durumunda form olduğu gibi kalır, yeniden denenebilir.
- **Teşekkür ekranı**: pencerenin bütün içeriği değişir (iç boşluk 28, üst 36): ortada 40 boyunda `success` renkli "✓";
  ortalı, kaydırmalı başlık yazısı `report.thanks` (üstte 8, altta 20); ortalı birincil `common.close`
  (en az 120; Enter ve Esc). **2.5 sn** sonra pencere kendiliğinden kapanır.

---

## 11. Güvenlik duvarı uyarı kartı (ana ekran ve PS5 eşleştirme adımı)

Ayarlar'daki kalıcı kart (`ayarlar.md` §4.2) değil; yalnız bağlantı sorunluyken çıkan kart. Kart başta gizli; görsel
ağaca girince denetleyicinin "güvenlik duvarı uyarısı" durumunu dinler (değişince arayüz iş parçacığında yeniden çizer).

- Görünüm: kart; içinde yarı kalın, `warning` renkli, kaydırmalı başlık; ipucu (üstte 8); sola yaslı ikincil `firewall.card.allow`
  düğmesi (üstte 12).
- Durumlar: **yok** (kart gizli), **öneri** (kural eksik; düğme), **bekleniyor** (Windows izni soruluyor; düğme soluk),
  **izin verildi** (kısa onay), **başarısız** (kural eklenemedi; düğme yeniden), **ortak ağ** (kural var ama ağ Ortak; düğme
  yok).
- Başlık: izin verildiyse `firewall.card.titleReady`, değilse `firewall.card.titleBlocked`.
- İpucu: ortak ağ → `firewall.card.hintPublicNetwork`; bekleniyor → `firewall.card.hintWaiting`; başarısız →
  `firewall.card.hintFailed`; izin verildi + çeviri sürüyor → `status.common.reconnecting`; izin verildi
  (eşleştirmede) → `firewall.card.hintReadyPairing`; diğer + çeviri sürüyor + Xbox → `firewall.card.hintXbox`; diğer + çeviri sürüyor → `firewall.card.hintRunning`; diğer (eşleştirme) → `firewall.card.hintPairing`.
- Düğme: kural yönetici izniyle eklenir (durum "bekleniyor" → "izin verildi" ya da "başarısız"); bekleniyorken yeniden
  basılamaz. Eklendiyse ve çeviri sürerken PS5'e ve TV'ye bağlanma hemen tekrarlanır.
- Ne zaman önerilir (testlerden):
  - Eşleştirme "başarısız" ya da ağ hatasıyla düşerse, kural yoksa **öneri**; kural varsa ve ağ Ortak ise **ortak ağ**;
    kural varsa ve ağ Özel ise hiçbir şey. Yanlış hesap ya da yanlış adres hatasında hiç bakılmaz. Güvenlik duvarı hizmeti
    yoksa hiçbir şey ve düğme işe yaramaz (false).
  - İzin verilince **izin verildi**; sihirbaz başka adıma geçince **yok**.
  - Çeviri sürerken: PS5 ağ yüzünden koptu/bağlanıyor ve **20 sn**'yi geçti → (kural yoksa) **öneri** (19 sn'de değil,
    21'de evet). TV uygulaması **60 sn** bağlanmadı → **öneri** (50'de değil, 61'de evet); kural var + ağ Ortak → **ortak
    ağ**; kural var + Özel → yok. PS5 uykudaysa öneri yok ve kurala bakılmaz. Kural varsa bir kez bakılır, öneri yok.
  - PS5 ve TV bağlanınca kart kalkar. İzin verildikten sonra bağlantı hâlâ gelmese de "izin verildi" kalır, yeniden
    önerilmez. Çeviri durunca **yok**.
  - Altyazı TV'de görünmüyorsa TV'nin bağlı olmaması öneriye yol açmaz.
  - Kuralların okunamaması "kural yok" sayılır; yazma hatası "başarısız".

---

## 12. Kullanılmayan "Baştan kur" seçim penceresi
Eski kodda `settings.section.systemHealth` dosyasında bir seçim penceresi vardır ama **hiçbir yerden açılmaz** (Sıfırla artık Ayarlar'da
ayrı bölüm). Yeni yazımda gerekmez. Bilgi için: başlık sıfırlama onayının başlığıyla aynı anlamda bir soru, ileti Sıfırla bölümündeki
açıklamayla aynı (en çok 460 genişlik, altta 20), sağa yaslı düğmeler: Vazgeç (Esc) · tehlike renkli yazılı `settings.reset.everything` · birincil `settings.reset.fromTv`; kalıcı (modal), içeriğe göre boyut, 24 iç boşluk.

---

## 13. Platforma bağlı kısımlar (Windows yetenekleri)
- **Pencere stilleri** (altyazı penceresi): genişletilmiş pencere stili okuma/yazma ile "etkinleşmez" (0x08000000), "araç
  penceresi" (0x80) ve tıklama geçirme için "saydam" (0x20) bayrakları; ekran kopyasından hariç tutma için görüntü
  yakınlığı 0x11 (Windows 10 2004+), kapatmak için 0. Sistem DPI'ı (oyun alanı pikselini WPF birimine çevirmek için).
- **Ekran bilgileri**: ana ekran yüksekliği (ölçek), çalışma alanı, tüm ekranları kapsayan sanal ekran (yer ve sınırlar).
- **Yakalama aygıtı**: kart Windows'ta kamera aygıtıdır; aygıt listesi, durum (okunuyor/siyah/izin yok/yok/durdu), canlı
  görüntü yüzeyi platform hizmetinde; kamera gizlilik ayarları sayfası `ms-settings:privacy-webcam` kabukla açılır.
- **Pano**: metin yazma (kilitliyse sessizce geçilir), görüntü/dosya listesi okuma (fotoğraf yapıştırma).
- **Sürükle-bırak**: dosya bırakma (önizleme aşamasında).
- **Dosya seçici**, **ileti kutuları** (onay ve hata), **varsayılan tarayıcıda açma** (kabuk), **Gezgin'de seçili gösterme**
  (`explorer /select,"‹yol›"`), kullanıcının İndirilenler klasörü (profil klasörü altında `Downloads`).
- **Zip yazma** (günlükler), paylaşımlı okuma ile açık günlük dosyalarını okuma.
- **Ekran okuyucu**: canlı bölge duyurusu (Nino'ya Sor), otomasyon adları (yazısız düğmeler, kutular).
- **Hareketi azalt**: Windows'un "istemci alanı animasyonu" sistem tercihi kapalıysa hareket azaltılmış sayılır (Nino'ya
  Sor noktaları durur, robot göz kırpmaz). Robotun göz kırpma aralığı 4000 + rastgele 0–1000 ms.
