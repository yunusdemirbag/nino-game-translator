# Mac: güncelleme, indirme sayacı, admin modu, debug kareleri, kısayollar, dağıtım farkları

Bu belge yeni Mac uygulaması için bir **tarif**tir: görünüş ve davranış. Kod içermez. Metinler
yeni uygulamanın anahtarlarıyla verilir: anahtarlar noktalı adlardır (ör. `settings.done`) ve alanlarına göre ayrı
xcstrings dosyalarında durur (Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport); anahtarın yanında
metnin kendisi değil, ne dediği kısaca anlatılır.

---

## 1. Dağıtım kanalları

Aynı kaynaktan iki ayrı Mac uygulaması çıkar:

| | GitHub / DMG sürümü | Mac App Store'daki sürüm |
|---|---|---|
| Paket kimliği | `com.ninotranslator.mac` | `com.ninotranslator.ios` (iPhone/iPad ile tek App Store kaydı) |
| App Sandbox | kapalı | açık |
| Güncelleme | Sparkle ile kendisi | App Store yapar; Sparkle pakete hiç girmez |
| Derleme bayrağı | yok | `APP_STORE` |
| Yetkiler | kamera + ses girişi (yakalama kartı için) | sandbox + kullanıcının seçtiği dosyayı okuma + ağ istemcisi + ağ sunucusu (altyazı sunucusu 8787, Remote Play UDP, Samsung girişinin dönüşü) + kamera + ses girişi |

Davranış farkları:
- **Güncelleme** (bkz. bölüm 2): App Store sürümü de GitHub'daki son sürüme bakar ve şeridi gösterir, ama düğme
  tarayıcıda indirme dosyasını (yoksa sürüm sayfasını) açar; kendisi indirip kurmaz. Arka planda indirme yok.
- **TV uygulaması kurulamazsa** App Store sürümünde hata metnine ek satır:
  `tv.install.error.appStoreHint` (mağazadan gelen kopya TV tarafını kuramadığında, kurulumu bir defalığına DMG
  kopyasıyla yapmayı, ondan sonra mağaza kopyasının tek başına yettiğini anlatan satır).
- Gömülü yardımcı programlar App Store sürümünde sandbox'ı miras alacak şekilde imzalanır.
- Eski sürümden veri taşıma yalnız DMG sürümünde yapılır (App Store sürümünde paylaşılan klasöre bakılmaz).
- GitHub sürümlerinin sayfası: `https://github.com/yunusdemirbag/nino-game-translator/releases/latest`.

---

## 2. Güncelleme

### Denetim (her iki sürüm)
- Kaynak: GitHub API'deki son sürüm, `https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest`.
  Başlıklar: `Accept: application/vnd.github+json`, `User-Agent: Nino-Mac`. Zaman aşımı 15 sn.
- Okunan alanlar: `tag_name` (baştaki `v` atılır), `html_url` (sürüm notları sayfası), `assets` içinde adı
  `Nino-Mac.zip` olanın `browser_download_url`'i.
- Sürüm karşılaştırması sayısaldır, noktayla ayrılmış parça parça (`0.1.10` > `0.1.9`; eksik parça 0).
- Ne zaman bakılır: ana ekran açıkken yarım saatte bir istenir, ama ağa **en çok saatte bir** çıkılır. Yenile/denetle
  düğmeleri bu sınırı atlar (hemen bakar).
- Durumlar: boşta, denetleniyor, güncel, başarısız. Ağ hatası ya da 200 dışı cevap → "başarısız".
  Daha yeni sürüm yoksa "güncel" ve "yeni sürüm" bilgisi silinir.
- Test ortamında hiç ağa çıkılmaz (ekran görüntülerine şerit girmesin).

### İndirme ve kurma (yalnız GitHub/DMG sürümü, Sparkle)
- Sparkle ayarları (uygulamanın bilgi dosyasında):
  - Yayın akışı: `https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/appcast.xml`
  - Nino'nun kendi EdDSA açık anahtarı (`SUPublicEDKey`); güncelleme bu anahtarla imzalı olmalı. Özel anahtar depoda değil.
  - Otomatik denetim açık, otomatik güncelleme açık, kendiliğinden güncellemeye izin var, denetim aralığı 3600 sn.
  - Test sürecinde güncelleyici başlatılmaz.
- Yeni sürüm bulununca **sorulmadan** arka planda indirilir ("indiriliyor" durumu). 180 sn içinde inmezse "indiriliyor"
  durumu düşer; kullanıcı o zaman düğmeye basınca Sparkle'ın kendi penceresi açılır (indirir, imzayı doğrular, kurar,
  yeniden açar).
- İnince **kurulmaya hazır** durumuna geçilir ve:
  - Nino boştaysa (çeviri sürmüyor ve kurulum bitmiş) **hemen kurulur ve yeniden açılır**.
  - Çeviri sürüyorsa ya da kurulum sihirbazındaysa bekler; çeviri durdurulduktan **2 sn sonra** kurulur.
  - Kullanıcı hazır hap düğmesine (`home.update.readyRestart`) basarsa çeviri sürse bile hemen kurulur. Çeviri sürüyorsa önce "yeniden açılınca
    sürdür" işareti (zaman damgası) yazılır ve oturum düzgün kapatılır; yeni sürüm açılınca, işaret 120 sn'den yeni ise
    çeviri kendiliğinden başlar.
- Ayarlar ipucu metni "yeni sürüm bir sonraki açılışta gelir" diyor; gerçek davranış yukarıdaki gibidir (boştaysa
  hemen). Yeni uygulamada metin davranışla uyumlu yazılmalı.

### Görünüşler

#### a) Ana ekran şeridi
- Yeni sürüm biliniyorsa ana ekranın en üstünde (salon sahnesinin üstünde) en çok 640 pt genişlikte cam zeminli kart:
  solda vurgu renginde dolu aşağı ok dairesi (22 pt), yanında kalın `home.update.bannerTitle` (Nino'nun daha yenisinin beklediğini bildiren kısa
  başlık), altında gri `Nino <sürüm>`; sağda birincil `home.update.download` (Download / İndir).
- İndirme düğmesine basınca: hazırsa kur ve yeniden aç; iniyorsa hiçbir şey; inemediyse Sparkle penceresi. App Store'da tarayıcı.

#### b) Alt şeridin ortasındaki durum
Ana ekranın en altındaki ince şeridin ortasında, durumuna göre:
- **Hazır:** vurgu mavisi hap düğme, dönen ok simgesi + `home.update.readyRestart` (güncellemenin indiğini bildirip yeniden başlatmaya çağıran
  hap metni; EN ve TR metni aynı anlamda).
- **İniyor:** küçük dönen gösterge + gri `home.update.downloading %@` (Downloading %@… / %@ indiriliyor…)
- **Yeni sürüm var, inmiyor:** mavi hap, aşağı ok + `home.update.newVersion %@` (yeni sürüm numarasını gösterip güncellemeye çağıran hap metni).
- **Diğer:** gri küçük yazı; güncelse önünde onay işareti. Metin: denetlenirken `home.update.checking` (Checking… / Denetleniyor…), güncelse
  `home.update.upToDate` (Up to date / Güncel), aksi hâlde `home.update.check` (Check for updates; TR metni güncellemelere
  bakmaya çağıran kısa satır). Yanında 22 pt yuvarlak yenile
  düğmesi (açık gri zemin, fareyle koyulaşır); denetlenirken simge sürekli döner ve düğme pasif. İpucu: yine
  `home.update.check`.

#### c) Ayarlar › Güncellemeler
- Ayarlar listesinde `settings.section.updates` (Updates / Güncellemeler) satırı (yeşil zeminli aşağı ok dairesi simgesi).
- Kart içinde: 44 pt logo, kalın `Nino Game Translator`, gri `settings.updates.version %@` (Version %@ / Sürüm %@); sağda ikincil düğme
  `settings.updates.check` (Check for updates; TR metni güncellemelere bakmaya çağırır) (denetlenirken
  `settings.updates.checking` (Checking… / Denetleniyor…) ve pasif).
- Yeni sürüm varsa: vurgu renkli parıltı simgesi, kalın `settings.updates.ready %@` (Nino %@ is ready. / Nino %@ hazır.), ikincil
  `settings.updates.whatsNew` (What's new / Yenilikler) (sürüm notları sayfasını tarayıcıda açar), birincil
  `settings.updates.download` (Download / İndir); altında ipucu `settings.updates.installHint` (yeni sürümün inip
  kurulacağını, uygulamanın kapanıp açılacağını ve ayarların korunacağını anlatır)
- Yoksa: güncelse yeşil onaylı `settings.updates.upToDate` (You're on the latest version.; TR metni en son sürümün
  kullanıldığını söyler); başarısızsa kırmızı `settings.updates.failed` (denetimin olmadığını söyleyip ağa
  bakmayı öneren satır).
- En altta ipucu: `settings.updates.auto` (yeni sürümleri kendiliğinden aradığını, görünmeden kurduğunu ve yenisinin
  uygulama tekrar açılınca devreye girdiğini anlatır).

---

## 3. Toplam indirme sayacı

### Veri
- Havuz sunucusunun **canlı** adresine (`https://nino-pool.y-demirbag2506.workers.dev`) `GET v1/config`; cevaptaki
  `downloads` tam sayısı (GitHub'daki uygulama dosyalarının indirme toplamı; sunucu yarım saatte bir yeniler).
  Adres değiştirme ayarı burada **kullanılmaz**, hep canlı sunucu.
- İstek kullanıcıya dair hiçbir bilgi taşımaz. Önbellek kullanılmaz, zaman aşımı 10 sn, yalnız 200 kabul.
- Sayı 0 ya da yoksa geçersiz sayılır.
- En çok **10 dakikada bir** sorulur; salon sahnesi açıkken açılışta ve sonra 10 dk'da bir.
- Son geçerli sayı kalıcı saklanır (`ninoDownloadTotal`); ağ yoksa o gösterilmeye devam eder. Hiç alınamadıysa sayaç
  görünmez. Sayı olduğu gibi gösterilir, üstüne ekleme yapılmaz.

### Görünüş (salon sahnesindeki TV'nin sağ üst köşesi)
- Oyunlardaki para göstergesi gibi: sağa yaslı iki satır. Üstte küçük beyaz büyük harf `home.tv.totalDownloads`
  (Total downloads / Toplam indirme; büyük harfe çevrilerek) (hafif harf aralığı), altında iri yeşil sayı (açık yeşil, binlik ayraçlı, eşit genişlikte rakam).
  İkisi de kalın siyah dış çizgili. Yazı tipi sistemdeki Impact, yoksa sistemin en kalın yazısı.
- Bütün gösterge hafif sağa eğik. Arapça arayüzde eğim ve harf aralığı yok (harfler bozulmasın).
- **Fiş takılı değilken:** TV ekranı siyah, ortada gri, büyük harf, aralıklı monospace yazı
  `home.tv.dragPlug` (başlamak için fişin prize çekilmesini isteyen çağrı; büyük harfe çevrilerek); sayaç sağ üstte sabit.
  Açılış gösterisi sırasında sayı önce görünmez, gösteri bitince çıkar.
- **Fiş takılınca (çeviri açık):** sol üstte kırmızı canlı nokta + `home.tv.live` (LIVE / CANLI) hapı, sağ üstte sayaç **sayarak** gelir:
  1, 2, 3 tek tek (280 ms arayla), sonra ~1,55 sn içinde hızlanarak toplam sayıya fırlar; sonda "görev tamam" yazısı
  gibi sayı %32 büyüyüp yeşil parlar ve yaylı biçimde yerine oturur (~2,4 sn toplam). "Hareketi azalt" açıksa ya da
  sayı 3 veya küçükse sayma yok, doğrudan sayı.

---

## 4. İndirme yardımcısı (genel)

- Tek dosya indirmesi, ilerlemesi izlenebilir: ilerleme her **2 MB**'de bir (ve sonda) bildirilir.
- İnen dosya geçici klasöre benzersiz adla taşınır. 2xx dışı cevap ya da ağ hatası → indirmenin
  bitmediğini söyleyip internet bağlantısına bakıp yeniden denemeyi isteyen hata. Yardımcı yalnız Greenlight için
  kullanıldığından yeni metin `capture.greenlight.error.download` (Greenlight didn't finish downloading. Check your internet
  connection, then try again. / Greenlight'ın indirilmesi tamamlanamadı. İnternet bağlantınıza bakıp yeniden deneyin.).
- İş iptal edilince indirme de iptal olur.
- Kullanıldığı yer: Xbox yayın uygulamasının (Greenlight) kurulumu.

---

## 5. Genel kısayollar

- Mac'teki pencere arkada olsa bile çalışır (kullanıcı kumandayla oynarken). Erişilebilirlik izni istemez (sistemin eski
  kısayol kayıt yolu). Başka bir uygulama aynı tuşu tutuyorsa sessizce atlanır.
- Kısayollar **yalnız gerektiğinde tutulur**; böylece çeviri kapalıyken tuşlar diğer uygulamalarda olağan işini görür.

### ⌥⌘T: Ekranı çevir
- Yalnız çeviri sürerken tutulur; çeviri durunca bırakılır ve süren iş iptal edilir.
- Basınca: oyunun son karesindeki tüm metin tek seferde okunur, her metin öbeği ayrı ayrı çevrilip TV'de bulunduğu
  noktada gösterilir (yapay zekâ motorunda bütün yazılar tek istekte). Gösterim süresi yazı miktarına göre hesaplanır.
- Akış ve mesajlar (TV'ye altyazı olarak gider):
  - Henüz kare yoksa: `support.screen.noPicture` (konsoldan daha kare gelmediği için okumanın yapılamadığını söyler) (4 sn)
  - Başlarken: `support.screen.translating` (çevirinin sürdüğünü bildirir) (2,5 sn)
  - Yazı yoksa: `support.screen.noText` (karede okunacak metin bulunmadığını söyler) (2,5 sn)
  - Hata: `support.screen.failed %@` (işin bozulduğunu ve nedenini `%@` ile verir)
- İş sürerken yeniden basmak işi iptal eder ve çevirileri kaldırır; çeviriler ekrandayken basmak onları kaldırır.
- Ana ekranda (klasik düzen) bilgi karosu: etiketi karonun bir kısayolu anlattığını söyleyen tek kelime (yeni metinlerde
  karşılığı yok), değer `settings.area.translateScreen` (EN metni ekranı çevirme işini ⌥⌘T ile adlandırır / Ekranı çevir (⌥⌘T)).
  Ayarlarda kart başlığı aynı anahtar; ipucu `settings.area.translateScreenHint` (oyun sırasında ⌥⌘T'nin o anki karenin tüm metnini
  tek seferde çevirip TV'de yerinde gösterdiğini, ikinci basışın çevirileri sildiğini anlatır)

### ⌥⌘L: Tıklamalar geçsin
- Yalnız çeviri sürerken **ve** altyazı bilgisayar ekranındayken tutulur.
- Altyazı penceresinin `settings.connection.clickThrough` (Clicks pass through / Tıklamalar geçsin) ayarını açar/kapatır.
- İpucu: `settings.connection.clickHint` (açıkken farenin arkadaki pencereye geçtiğini, kapatmanın ⌥⌘L ya da menü
  çubuğu simgesiyle olduğunu anlatır)

### Uygulama içi kısayollar ve menü çubuğu
- ⌘, → Ayarlar (kurulum bitmeden pasif). Uygulama menüsünde `home.menu.about` (About Nino; TR metni uygulamanın tam adıyla
  Hakkında öğesi).
- Ayarlar sayfasında ⌘[ geri; sohbet ve ayar sayfalarında Esc kapatır.
- Altyazı bilgisayar ekranındayken menü çubuğunda Nino simgesi (altyazı balonu) belirir: (yakalama kartı kullanılıyorsa
  durum satırı ve `home.menu.gameFullScreen` (oyunu tüm ekrana yayan komut) ⌃⌘F),
  `home.menu.clickThrough` (Let clicks pass through / Tıklamalar geçsin) seçeneği, `home.overlay.adjust` (EN metni altyazı
  penceresini ayarlama komutu / Altyazı penceresini ayarla), `home.menu.openNino` (Open Nino / Nino'yu aç).

---

## 6. Admin modu (yalnız geliştiricinin Mac'i)

### Nasıl açılır
- **Debug derlemesinde her zaman açık.**
- Yayın derlemesinde yalnız kullanıcı ayarıyla: `defaults write com.ninotranslator.mac ninoAdminMode -bool true`.
  Kullanıcılarda kapalıdır; arayüzde açma düğmesi yoktur.

### Açıkken ne değişir
1. **Rozet:** ana ekranın başlığının hemen altında turuncu hap, beyaz yarı kalın yazı: **Debug admin modu aktif**
   (çevrilmeyen sabit Türkçe metin).
2. **Kendiliğinden başlama:** her açılışta kurulum bitmişse çeviri kendiliğinden başlar (en çok ~10 sn başlatılabilir
   olmasını bekler). Günlüğe "admin modu: çeviri kendiliğinden başlıyor".
3. **TV'yi uyandırma:** başladıktan 8 sn sonra TV seçili ama TV uygulaması bağlı değilse TV uygulaması TV'de (bu
   bilgisayarın adresiyle) yeniden açılır (Android TV'de yenilenir, diğerlerinde kurulum sonrası açma yolu).
4. **Debug kareleri ve ses kaydı:** bölüm 7.
5. **Telefon izi:** oyun içi telefon okumasının durumu her değiştiğinde günlüğe "telefon izi: …" satırı (aynı durum
   tekrar yazılmaz).

### Debug derlemesine özel önizleme (admin modundan ayrı)
- Yalnız Debug derlemede okunan ortam değişkenleri: `NINO_PREVIEW_STATE` (ör. `live`, `connecting`, `splash`),
  `NINO_PREVIEW_LIVE`, `NINO_PREVIEW_HOME` (ana ekran türü). Ekranları gerçek bağlantı olmadan göstermek için; canlı
  durumda çeviri diline göre örnek satır gösterilir.
- Açılış argümanı `-NinoPreviewStep <n>`: kurulumun n'inci adımını açar (7 = ana ekran).
- Yayın derlemesinde bunların hiçbiri okunmaz.

---

## 7. Debug kareleri (admin modu)

Klasör: uygulamanın günlük klasörü altında `frames/` (`~/Library/Logs/Nino/frames/`).

### Çizimli kareler (çeviri sürerken)
- Her gelen karede en çok **2 sn'de bir** arka planda bir kare işlenir:
  - Okuma bölgesi: **sarı kesikli** dikdörtgen (3 px, 12/8 kesik).
  - Köşe bölgeleri: **mavi kesikli** iki dikdörtgen: sol üst (genişliğin %0–40'ı, yüksekliğin %0–36'sı) ve alt şerit
    (genişlik %8–92, yükseklik %88,5–99,5).
  - Son okunan yazının kutusu: **kırmızı düz** dikdörtgen (4 px).
  - Üstte 90 px yüksekliğinde %70 siyah şerit, içinde iki satır kalın beyaz 26 pt yazı:
    `OKUNAN: <okunan metin>` ve `ÇEVİRİ: <son çeviri>`.
- Yazılan dosyalar (JPEG):
  - `latest.jpg` (her seferinde üzerine yazılır, kalite 0,7),
  - `f-<zaman>.jpg` çizimli kare (kalite 0,7),
  - `r-<zaman>.jpg` çizimsiz ham kare (kalite 0,92; simge tanımayı denemek için).
  - Zaman ISO 8601, `:` yerine `-`.
- `f-` ve `r-` türlerinin her birinden en çok **120** dosya tutulur; eskiler silinir.

### Video ve ses kaydı
- `frames/video/KAYIT` adlı dosya **varken** kayıt açıktır (yarım saniyede bir kontrol edilir; dosyayı elle koyup
  silmek kaydı açar/kapatır).
- Görüntü: saniyede 10 ham kare `frames/video/v-<epoch ms>.jpg` (kalite 0,85).
- Ses: admin modunda PS5'in sesi tam kalitede istenir; kayıt açıkken 48 kHz iki kanallı 32 bit float örnekler
  `frames/video/ses.f32` dosyasına art arda eklenir. İlk örneğin zamanı (epoch ms) `frames/video/ses-baslangic.txt`'ye
  yazılır (görüntüyle eşlemek için). Kayıt kapanınca dosya kapatılır.
