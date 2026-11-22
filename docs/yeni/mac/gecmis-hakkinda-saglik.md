# Mac: Geçmiş, Hakkında, Sistem sağlığı, Sorun Bildir (tarif)

Bu belge dört ekranın **görünüşünü ve davranışını** anlatır; kod yoktur. Ortak bileşenler (Kart, İpucu, Tamam etiketi,
Hata yazısı, Karo, Karo simgesi, Durum noktası, Cam yüzey, düğme türleri, renk/ölçü adları) `tasarim-dili.md`'dedir; burada yalnız hangisi kullanıldığı yazar.
Ayarlar penceresinin genel düzeni için bkz. `ayarlar.md`.

Metin kuralı: her ekran metni noktalı bir anahtarla (ör. `sheets.common.done`) bölge bölge xcstrings dosyalarında durur
(Home, Settings, Setup, Sheets, TVSetup, Console, Capture, AppSupport). Bu belgede anahtarın yanına kısa metinler İngilizce ve
Türkçe yazılır; uzun metinlerin yerine ne dedikleri anlatılır ve öbür dil sütununa "(aynı anlamda)" konur. Tablolarda
sütunlar "Anahtar | EN | TR". "verbatim" denen metinler (uygulama adı, kişi ve proje adları,
telif bildirimleri, destek metinleri) çevrilmez ve anahtarı yoktur.

---

## 1. Geçmiş

### Açılış
Ana ekranın sağ üstündeki yuvarlak saat düğmesi (simge clock.arrow.circlepath, ipucu `home.history`: History / Geçmiş)
ana pencerenin üstünde **sayfa** olarak açar.

### Düzen
- Genişlik 640 pt; yükseklik ana pencere yüksekliğinden iki "screen" boşluğu eksik. İç boşluk "screen". Öğeler arası "gap".
- Üstte büyük başlık `sheets.history.title` (en büyük başlık yazısı).
- İpucu `sheets.history.hint %lld` (sayı sabit sınırdan gelir: 200).
- **Liste boşsa:** ortada (üstte ve altta esnek boşluk) ipucu `sheets.history.empty`.
- **Doluysa:** karo içinde kaydırılabilir liste; en yenisi üstte; satırlar arasında ince çizgi.
- Altta yan yana: ikincil `sheets.history.copyAll` (basınca `sheets.common.copied` olur), tehlikeli `sheets.history.clear`,
  esnek boşluk, sağda büyük birincil `sheets.common.done` (Return). Liste boşken ilk ikisi soluk.

### Satır
- Dikey iç boşluk "m". Solda üç satır (hepsi seçilip kopyalanabilir yazı):
  1. Küçük ikincil, eş aralıklı rakamlarla: `saat:dakika:saniye · kaynak` — kaynak `sheets.history.originPack` ya da
     `sheets.history.originEngine`.
  2. Çeviri (gövde yazısı, satır kaydırmalı).
  3. Asıl (İngilizce) metin (küçük, ikincil).
- Sağda çerçevesiz küçük kopyala düğmesi (simge doc.on.doc; basılınca checkmark). Üstüne gelince ipucu
  `sheets.history.copy` / `sheets.common.copied`. Panoya "çeviri + yeni satır + asıl metin" yazar.

### Davranış
- Her çevrilen satır geçmişe eklenir ve arka planda küçük bir dosyaya yazılır (sırayla; en son hâl kalır). Bu ve önceki
  oturumların satırları görünür; en çok 200 satır tutulur.
- `sheets.history.copyAll`: bütün satırları düz metin olarak panoya yazar.
- `sheets.history.clear`: onay penceresi `sheets.history.clearTitle` + mesaj `sheets.history.clearMessage` + kırmızı
  `sheets.history.clear`. Onaylanınca liste ve dosya boşalır.

| Anahtar | EN | TR |
|---|---|---|
| `sheets.history.title` | History | Geçmiş |
| `sheets.history.hint %lld` | (Mac'in en son çevrilen `%lld` satırı sakladığını söyler) | (aynı anlamda) |
| `sheets.history.empty` | (listenin boş olduğunu, şimdiki ve geçmiş oturumlarda çevrilenlerin buraya geleceğini söyler) | (aynı anlamda) |
| `sheets.history.copyAll` | Copy all | Hepsini kopyala |
| `sheets.common.copied` | Copied | Kopyalandı |
| `sheets.history.clear` | Clear | Temizle |
| `sheets.common.done` | Done | Bitti |
| `sheets.history.clearTitle` | Clear the history? | Geçmiş silinsin mi? |
| `sheets.history.clearMessage` | Every saved line is deleted from this Mac. | Kayıtlı bütün satırlar bu Mac'ten silinir. |
| `sheets.history.copy` | Copy | Kopyala |
| `sheets.history.originPack` | Pack | Paket |
| `sheets.history.originEngine` | Translation engine | Çeviri motoru |

---

## 2. Hakkında

### Açılış iki yoldan
1. Menü çubuğu › uygulama menüsü › `home.menu.about` (About Nino; Türkçede uygulamanın tam adıyla kurulan Hakkında
   öğesi), sistemin standart Hakkında öğesinin yerine: ayrı bir sayfa açılır, genişlik 520 pt, iç boşluk "xxl". İçerik +
   altta birincil `sheets.common.close` (Close / Kapat; Return).
2. Ayarlar › `settings.section.about` (About Nino; Türkçesi menüdekiyle aynı): aynı içerik, bölüm başlığının altında
   (Kapat düğmesi yok; Ayarlar'ın `sheets.common.done` düğmesi kapatır).

### İçerik (yukarıdan aşağı, ortalı, aralar "l")
1. **Logo bloğu:** 96 pt logo (vurgu renginin %35'iyle 18 pt yarıçaplı parıltı); "Nino Game Translator" (verbatim,
   30 pt kalın yuvarlak); altında görünen sürüm satırı (verbatim, çevrilmez, küçük ikincil).
2. **Emek veren kartı** (cam yüzey, kart köşesi, ince cam kenar): iki satır, arada soldan 52 pt girintili çizgi.
   - Satır: 28×28 pt simge kutusu (köşe 8, açık vurgudan koyu laciverte 0.0/0.19/0.52 yukarıdan aşağı geçiş, beyaz
     13 pt simge), yanında ikincil rol adı, sağda kalın kişi adı. Yatay iç boşluk "l", en az 50 pt.
   - `sheets.about.role.developer` (Developer / Geliştiren; simge hammer.fill): Yunus Demirbağ.
   - `sheets.about.role.supporters` (Supporters / Destekleyenler; simge heart.fill): M. Akif Demirbağ.
3. **Altyapı kartı** (cam yüzey, iç boşluk "l", sola yaslı). Proje başlıkları ve telif bildirimleri verbatim; başlık ve
   açıklama cümleleri yerelleştirilir:
   - Başlık `sheets.about.builtOn` (Built on / Üzerine kurulu; küçük, yarı kalın, ikincil).
   - Üç numaralı halka; her biri: 24 pt daire içinde beyaz numara (aynı mavi geçiş), yanında başlık (küçük yarı kalın;
     bağlantı varsa vurgu renkli, tıklanabilir) ve altında tek cümle (en küçük yazı, ikincil):
     1. "Chiaki — Florian Märkl (2018)" → https://git.sr.ht/~thestr4ng3r/chiaki — `sheets.about.credit.chiaki`
        (kaynağı açık ilk Remote Play istemcisi olduğunu ve Nino'nun konsol bağlantısının ona dayandığını söyler)
     2. "chiaki-ng — Street Pea and contributors" → https://github.com/streetpea/chiaki-ng —
        `sheets.about.credit.chiakiNg` (Chiaki'nin hâlâ bakılan sürdürücüsü olduğunu ve Nino'nun konsol
        bağlantısında onu kullandığını söyler)
     3. "Nino — Yunus Demirbağ" (bağlantısız) — `sheets.about.credit.nino` (bunların üstüne Nino'nun kattıklarını sayar: Mac, TV ve
        telefon uygulamaları, ekrandan altyazı okuma ve çeviri)
   - En altta lisans satırı (en küçük yazı, ikincil, tek paragraf). Yapısı: önce `sheets.about.license` (iki dilde de uygulamanın GNU
     AGPL-3.0 ile, parasız ve kaynağı açık dağıtıldığını söyler), ardından çevrilmeyen telif bildirimleri: "Nino © 2026 Yunus Demirbağ.", ‹ÜST PROJE›'nin (© 2026
     ‹ÜST PROJENİN SAHİBİ›) üzerine kurulduğu bildirimi ve "Chiaki © Florian Märkl and contributors."
     ‹ÜST PROJE› ve ‹ÜST PROJENİN SAHİBİ› adları bu belgede bilerek yazılmamıştır; depodaki `NOTICE` dosyasından alınır
     (AGPL gereği zorunlu telif bildirimi; yalnız NOTICE'ta ve bu satırda geçer).
4. **Marka uyarısı** (en küçük yazı, ikincil, ortalı, çevrilir): `sheets.about.trademark`.

| Anahtar | EN | TR |
|---|---|---|
| `home.menu.about` | About Nino | (uygulamanın tam adıyla Hakkında) |
| `sheets.common.close` | Close | Kapat |
| `sheets.about.role.developer` | Developer | Geliştiren |
| `sheets.about.role.supporters` | Supporters | Destekleyenler |
| `sheets.about.builtOn` | Built on | Üzerine kurulu |
| `sheets.about.trademark` | (Nino'nun Sony ile ilişkisi olmadığını ve PlayStation ile PS5 adlarının Sony'ye ait tescilli markalar olduğunu söyler) | (aynı anlamda) |

---

## 3. Sistem sağlığı (Ayarlar › `settings.section.health`: System health / Sistem sağlığı)

### Genel
- Sayfa **iki saniyede bir** kendini yeniler: o anki sağlık ölçümlerinin bir kopyası alınır ve bütün kartlar ondan
  çizilir (ölçümler arka planda birikir; ekran her pakette yenilenmez).
- Mac'in ağ türü sürekli izlenir: `sheets.health.network.wired` (Cable / Kablo), `sheets.health.network.wifi` (Wi-Fi),
  `sheets.health.network.other` (Other connection / Başka bağlantı), `sheets.health.network.offline` (No network / Ağ
  yok), (henüz bilinmiyor) `sheets.health.network.unknown` (Checking… / Denetleniyor…).
  Bunun için izin istenmez; Wi-Fi adı ve sinyali bilerek okunmaz (konum izni gerektirir).
- Kartlar sırayla: **Muhtemel sebep** → **Denetimler** → **Son sorunlar** → **Nino TV uygulaması** → **Cihaz bilgileri** →
  **Ayrıntılar**.

### Seviyeler
Her denetim dört seviyeden birindedir; renkli nokta + yarı kalın etiket:

| Seviye | Renk | Anahtar | EN | TR |
|---|---|---|---|---|
| ölçülmedi | ikincil (gri) | `sheets.health.level.notMeasured` | Not measured yet | Henüz ölçülmedi |
| iyi | başarı (yeşil) | `sheets.health.level.good` | Good | İyi |
| uyarı | uyarı (sarı) | `sheets.health.level.fair` | Could be better | Daha iyi olabilir |
| sorun | tehlike (kırmızı) | `sheets.health.level.problem` | Problem | Sorun var |

Eşikler:
- **PS5 görüntüsü:** dakikada kayıp paket ≥100 ya da donma ≥4 → sorun; kayıp ≥10 ya da donma ≥2.5 → uyarı; değilse iyi.
  Ölçüm yoksa ölçülmedi.
- **PS5 bağlantısı:** ölçüm yok → ölçülmedi; çeviri sürüyor ama bağlantı kesilip dönmedi → sorun; hiç
  bağlanılamadı ve en az 2 deneme → sorun (1 denemede ölçülmedi); akışta ≥3 kopma → uyarı; değilse iyi.
- **Çeviri hızı** (satır başına ortanca süre): ≥3000 ms sorun, ≥1500 ms uyarı, değilse iyi; ölçüm yoksa ölçülmedi.
- **Mac'in ağ türü:** kablo → iyi; ağ yok → sorun; bilinmiyor → ölçülmedi; Wi-Fi / başka → PS5 görüntüsünün seviyesiyle
  aynı (ölçülmeden yeşil gösterilmez).
- **TV:** çeviri sürmüyor ya da altyazı TV'ye gitmiyorsa ölçülmedi; bağlı TV uygulaması varsa iyi, yoksa sorun.

### 3.1 Muhtemel sebep kartı (en üstte)
- Sebep listesi önemliden önemsize hesaplanır (aşağıdaki tablo). **İlk sebep varsa:** kart içinde solda 22 pt sarı
  uyarı üçgeni; sağda kalın başlık (sebebin adı), altında gövde boyunda ne yapılacağı, altında diğer sebepler "• ad"
  biçiminde küçük ikincil satırlar.
- **Sebep yoksa** ve çeviri sürüyor + görüntü geliyorsa: kart içinde yeşil onay + kalın `sheets.health.allGood`
  (All looks good / Her şey yolunda).
- İkisi de değilse kart görünmez.

**Sebeplerin sırası ve koşulu** (ölçüm hiç yoksa yalnız "ağ yok" sebebi çıkabilir):
1. Mac ağa bağlı değil.
2. Çeviri sürüyor, PS5 kesildi ve dönmedi (Mac'in ağı varken). Oturumda Mac'in ağı da gittiyse "ağ gidince koptu"
   biçimi; değilse kopma sebebine göre: PS5 uykuda / başka cihazda Remote Play açıldı / genel.
   — ya da — hiç bağlanılamadı ve en az 2 deneme yapıldı.
3. Oturumda Mac'in ağı kesilip geri geldi (şu an ağ var, PS5 kopuk değil) — kaç kez olduğu yazar.
4. PS5 görüntüsü uyarı ya da sorun seviyesinde — Mac Wi-Fi'de (ya da başka bağlantıda) mı, kabloda mı diye iki biçim.
5. PS5 kopuk değil, akışta ≥3 kopma var, görüntü iyi ve ağ hiç gitmedi — kaç kez.
6. Çeviri hızı uyarı ya da sorun — ortanca süre saniye olarak (bir ondalık).
7. Oturumda TV uygulaması koptu — kaç kez.

Her sebebin iki anahtarı vardır: `sheets.health.cause.<ad>.title` (başlık) ve `sheets.health.cause.<ad>.action`
(ne yapılacağı; sayı alanlar `%d` / `%@` ile).

| Sebep | Başlık anahtarı (anlamı; EN ve TR aynı) | Ne yapılacağı anahtarı (anlamı; EN ve TR aynı) |
|---|---|---|
| ağ yok | `sheets.health.cause.noNetwork.title` (Mac'in hiçbir ağa bağlı olmadığını söyler) | `sheets.health.cause.noNetwork.action` (Mac'i konsolun kullandığı modeme bağlamayı ister; Nino'nun bağlantıyı kendisi tazeleyeceğini ekler) |
| ağ gidince koptu | `sheets.health.cause.afterNetworkLoss.title` (Mac'in ağı kesilince konsol bağlantısının da düştüğünü söyler) | `sheets.health.cause.afterNetworkLoss.action` (Mac'teki kablosuz bağlantının kısa bir an kesildiğini ve konsol bağlantısının buna dayanamadığını anlatır; Mac'i kabloyla modeme takmayı ya da modemin yanında 5 GHz bandında kullanmayı önerir) |
| PS5 uykuda | `sheets.health.cause.asleep.title` (konsolun kapandığını ya da dinlenme kipine girdiğini söyler) | `sheets.health.cause.asleep.action` (konsolu açmayı ister; dinlenme kipinde de erişilebilmesi için konsolun güç tasarrufu ayarlarındaki internet bağlantısını koruyan seçeneği (EN: “Stay connected to the internet”; TR: “İnternete bağlı kal”) açmayı önerir) |
| başka cihazda | `sheets.health.cause.elsewhere.title` (Remote Play'in başka bir aygıtta başlatıldığını söyler) | `sheets.health.cause.elsewhere.action` (öbür telefon, tablet ya da bilgisayardaki Remote Play'i kapatmayı ister; Nino'nun bağlantıyı kendisi tazeleyeceğini ekler) |
| genel kopma | `sheets.health.cause.dropped.title` (konsol bağlantısının kesilip dönmediğini söyler) | `sheets.health.cause.dropped.action` (konsolun ağdan cevap vermediğini söyler; konsolla Mac'in tek bir modemde olduğuna bakmayı, sürerse modemi kapatıp açmayı ya da konsolu kabloya geçirmeyi önerir; Nino'nun denemeye devam ettiğini ekler) |
| hiç bağlanamadı | `sheets.health.cause.couldNotConnect.title` (Nino'nun konsola hiç ulaşamadığını söyler) | `sheets.health.cause.couldNotConnect.action` (konsolun açık ve Mac'le tek ağda olduğuna bakıp çeviriyi tekrar başlatmayı ister) |
| ağ gitti geldi | `sheets.health.cause.networkDropped.title` (oyun sürerken Mac'in ağının kesildiğini söyler) | `sheets.health.cause.networkDropped.action %d` (Mac'in ağının kaç kez kesildiğini söyler; Mac'i kabloyla modeme takmayı ya da modeme yaklaştırmayı ister) |
| görüntü kaybı (Wi-Fi) | `sheets.health.cause.pictureLossWifi.title` (Wi-Fi yüzünden konsol görüntüsünün eksik geldiğini söyler) | `sheets.health.cause.pictureLossWifi.action` (Mac'teki kablosuz bağlantıda paket yitirildiğini, bu yüzden görüntünün donup altyazıların atlandığını anlatır; Mac'i kabloyla modeme takmayı (USB-C Ethernet çevirici de yeter) ya da modemin yanında 5 GHz bandına geçmeyi önerir) |
| görüntü kaybı (kablo) | `sheets.health.cause.pictureLossWired.title` (konsol görüntüsünün ağda veri yitirdiğini söyler) | `sheets.health.cause.pictureLossWired.action` (konsolu da kabloya geçirmeyi, zaten kablodaysa modemi kapatıp açmayı ister) |
| sık kopma | `sheets.health.cause.frequentDrops.title` (konsol bağlantısının sık sık kesildiğini söyler) | `sheets.health.cause.frequentDrops.action %d` (bağlantının kaç kez kesildiğini söyler; konsolu da Mac'i de kabloyla modeme takmayı ister) |
| yavaş çeviri | `sheets.health.cause.slow.title` (çevirinin yavaşladığını, sebebin internet ya da çeviri servisi olabileceğini söyler) | `sheets.health.cause.slow.action %@` (her satırın `%@` saniyede çevrildiğini söyler; önce internete bakmayı, sorun yoksa Nino ayarlarının çeviri bölümünden parasız motora geçmeyi önerir) |
| TV koptu | `sheets.health.cause.tvDropped.title` (TV uygulamasıyla Mac arasındaki bağın kesildiğini söyler) | `sheets.health.cause.tvDropped.action %d` (TV'nin `%d` kez düştüğünü söyler; TV'de Nino'yu açık bırakmayı ve TV'nin Mac'le tek ağda olduğuna bakmayı ister) |

Not: Mac metinleri her zaman "bu Mac" biçimindedir.

### 3.2 Denetimler kartı
- Üstte durum ipucu: hiç ölçüm yoksa `sheets.health.checks.noData`; ölçüm var ama çeviri durduysa
  `sheets.health.checks.lastSession`.
- Sonra satırlar, aralarında çizgi. **Satır:** solda karo simgesi (ortak bileşen), sağda: üst satırda yarı kalın ad,
  esnek boşluk, renkli nokta, seviye etiketi (ölçülmediyse ikincil renk, değilse seviye rengi); altında ikincil değer
  metni; seviye **uyarı ya da sorun** ise altında normal renkte ne yapılacağı. Ekran okuyucu için satır tek öğedir.

| Satır | Simge | Ad anahtarı (EN / TR) | Değer metni | Ne yapılacağı |
|---|---|---|---|---|
| Ağ | kabloda cable.connector, değilse wifi | `sheets.health.row.network` (Mac'in ağını adlandıran satır adı) | ağ türü adı | ağ yoksa `sheets.health.advice.noNetwork`; değilse `sheets.health.advice.networkLoss` |
| PS5 bağlantısı | gamecontroller | `sheets.health.row.console` (PS5 connection / PS5 bağlantısı) | aşağıda | son kopma sebebine göre (aşağıda) |
| PS5 görüntüsü | play.rectangle | `sheets.health.row.video` (PS5 picture / PS5 görüntüsü) | aşağıda | `sheets.health.advice.video` |
| Çeviri hızı | globe | `sheets.health.row.speed` (Translation speed / Çeviri hızı) | aşağıda | çevrimiçi motor veya yerel model kullanılıyorsa `sheets.health.advice.speedEngine`; değilse `sheets.health.advice.speedMac` |
| TV | tv | `sheets.health.row.tv` (TV / TV) | TV'ye gitmiyorsa `sheets.health.value.tvNotUsed`; çeviri kapalıysa `sheets.health.value.notStarted`; değilse `sheets.health.value.connected` / `sheets.health.value.notConnected` | `sheets.health.advice.tv` |
| Nino TV uygulaması | square.and.arrow.down.on.square | `sheets.health.row.tvApp` (Nino TV app / Nino TV uygulaması) | kurulum durumuna göre (aşağıda) | aşağıda |

PS5 bağlantısı satırının altında, Mac'te Nino'nun **yerel ağa izni yok gibi görünüyorsa** ayrıca uyarı bloğu: sarı üçgen simgeli,
yarı kalın, uyarı renginde metin `sheets.health.localNetwork` ve altında ikincil `sheets.health.openSystemSettings`
düğmesi (Gizlilik › Yerel Ağ sayfasını açar). Bu uyarı yalnız güçlü işarette ve çeviri sürerken görünür.

**PS5 bağlantısı değeri:** ölçüm yok → `sheets.health.value.notStarted`; kesilip dönmedi →
`sheets.health.value.downFor %d` (en az 1 dk); hiç bağlanamadı → `sheets.health.value.couldNotConnect %d`; kopma yok →
`sheets.health.value.noDrops`; değilse `sheets.health.value.drops %d`.

**PS5 bağlantısı tavsiyesi** (son kopma sebebine göre):

| Sebep | Anahtar | EN | TR |
|---|---|---|---|
| PS5 uykuda | `sheets.health.consoleAdvice.asleep` | (konsolun kapalı veya dinlenme kipinde olduğunu söyler; açmayı ya da dinlenme ayarlarında “Stay connected to the internet” seçeneğini açmayı ister) | (aynı anlamda) |
| başka cihazda kullanılıyor | `sheets.health.consoleAdvice.inUseElsewhere` | (Remote Play'in başka bir aygıtta çalıştığını söyleyip orada kapatmayı ister) | (aynı anlamda) |
| giriş şifresi | `sheets.health.consoleAdvice.passcode` | (ikinci hesabın konsolda oturum şifresi olduğunu, şifrenin konsoldan kaldırılmasını ister) | (aynı anlamda) |
| Remote Play kapalı | `sheets.health.consoleAdvice.remotePlayDisabled` | (konsolda Remote Play'in kapalı olduğunu söyler; konsolun kendi menüsündeki açma anahtarını (EN: Settings › System › Remote Play; TR: Ayarlar › Sistem › Uzaktan Oynatma) gösterip çeviriyi tekrar başlatmayı ister) | (aynı anlamda) |
| eşleşme geçersiz / reddedildi | `sheets.health.consoleAdvice.pairingInvalid` | (konsolun Mac'i geri çevirdiğini söyler; eşlemeyi Nino ayarlarının sıfırlama bölümünden tekrarlamayı ister) | (aynı anlamda) |
| bulunamadı | `sheets.health.consoleAdvice.notFound` | (konsolun ağdan cevap vermediğini söyler; açık veya dinlenme kipinde ve Mac'le tek ağda olduğuna bakmayı ister) | (aynı anlamda) |
| diğer | `sheets.health.consoleAdvice.other` | (bağlantının tekrar tekrar kesildiğini söyler; konsolu da Mac'i de kabloyla modeme takmayı ister) | (aynı anlamda) |

(Not: yeniden eşleme ayrı `settings.section.reset` (Reset / Sıfırla) bölümündedir; "eşleşme geçersiz" tavsiyesi de bu
yolu, Ayarlar › Sıfırla'yı gösterir.)

**PS5 görüntüsü değeri:** ölçüm yok → `sheets.health.value.notStarted`; görüntü gelmiyor → `sheets.health.value.noPicture`;
değer henüz yok → `sheets.health.value.measuring`; değilse `sheets.health.value.video %@ %@` (kayıp tam sayı, donma bir
ondalık).

**Çeviri hızı değeri:** ölçüm yok → `sheets.health.value.notStarted`; satır var ama hepsi hazır çeviriden →
`sheets.health.value.allReady %d`; satır yok → `sheets.health.value.noSubtitle`; değilse
`sheets.health.value.speed %@ %d` (bir ondalık).

**Nino TV uygulaması satırı** (yapılacak bir şey yoksa satır hiç görünmez: bilinmiyor, kuruluyor, giriş, parola bekleniyor):

| Durum | Seviye | Değer | Ne yapılacağı |
|---|---|---|---|
| güncel | iyi | `sheets.health.tvApp.installed %@` | — |
| TV'deki izin sorusu yanıt bekliyor | uyarı | `sheets.health.tvApp.approval` | `sheets.health.tvApp.approvalAdvice` |
| geliştirici modu kapalı | uyarı | `sheets.health.tvApp.notInstalled` | `sheets.health.tvApp.developerModeAdvice` |
| kurulum hatası | sorun | `sheets.health.tvApp.failed` | TV uygulaması kartındaki hata metni (bkz. `tv-kurulumu.md` §5) |
| Host PC IP uyuşmuyor | uyarı | `sheets.health.tvApp.notInstalled` | `sheets.health.tvApp.hostIPAdvice %@ %@` |

### 3.3 Son sorunlar kartı
- Başlık `sheets.health.recentProblems`. Yalnız kayıtlı sorun varsa görünür. Nino yeniden açılsa da kayıtlar kalır.
- En son 8 sorun, en yenisi üstte. Satır: solda 150 pt genişlikte tarih (kısaltılmış tarih + kısa saat, ikincil),
  yanında sorunun kısa adı.
- Altında ipucu: otomatik bildirim açıksa `sheets.health.autoOn`; kapalıysa `sheets.health.autoOff`.

Sorun türleri ve kısa adları:

| Tür | Ne zaman kaydedilir | Anahtar | EN | TR |
|---|---|---|---|---|
| PS5 koptu | çeviri sürerken, görüntü gelirken PS5 ile bağlantı kesildi | `sheets.health.problem.ps5Dropped` | (PS5 bağlantısının koptuğunu söyleyen kısa ad) | (aynı anlamda kısa ad) |
| PS5 dakikalarca gelmedi | kopmadan sonra 180 sn içinde geri gelmedi (çeviri hâlâ açık) | `sheets.health.problem.ps5Unreachable` | (aynı anlamda) | (PS5'in dakikalarca dönmediğini söyleyen kısa ad) |
| ağ gitti | çeviri sürerken Mac'in ağı "ağ yok"a düştü | `sheets.health.problem.networkLost` | (Mac'in ağını yitirdiğini söyleyen kısa ad) | (aynı anlamda) |
| TV koptu | çeviri sürerken ve altyazı TV'ye giderken bağlı TV sayısı 0'a indi ve 20 sn geri gelmedi | `sheets.health.problem.tvDropped` | TV disconnected | TV bağlantısı koptu |

Her kayıt günlüğe de bir satır olarak yazılır; kayıtta o anki ölçüm özeti, ağ türü ve (biliniyorsa) oyunun adı durur.

**Otomatik bildirim** (ayar açıksa; varsayılan açık):
- `sheets.health.problem.ps5Unreachable` kaydı olunca hemen gönderilir.
- Oturum bitince: o oturumda sorun kaydedildiyse ya da görüntü/çeviri seviyesi "sorun" ise gönderilir.
- **Oturum başına en çok bir kez.** İçeriği yalnız özet: Nino'nun tespitleri (muhtemel sebep, son 3 günün sorunları,
  ölçüm özeti), cihaz özeti, uygulama sürümü, platform, çeviri dili, kurulum kimliği. Günlük ve altyazı metni gitmez.
- Gönderilemezse sonra yeniden denenir; uygulama açılışında önceki açılıştan kalan bildirim gönderilir. Günlük sınır var.

### 3.4 Nino TV uygulaması kartı
TV uygulamasının kurulum adımları ve hatası (`setup.tvApp.tryAgain` (Try Again / Tekrar Dene) vb.) için kurulum
sihirbazındaki kartın aynısı burada da gösterilir (bkz. `tv-kurulumu.md` §5). Yapılacak bir şey yoksa görünmez.

### 3.5 Cihaz bilgileri kartı
- Başlık `sheets.device.title` (Device info / Cihaz bilgileri). Satırlar: solda 150 pt ikincil etiket, sağda seçilebilir değer.
- Satırlar ve değerleri (değerler **destek içindir, Türkçe ve sabit kalır**, ekran dili değişse de):
  - `sheets.device.appVersion`: sürüm + varsa " (yapı numarası)".
  - `sheets.device.model`, `sheets.device.system`: Mac'in modeli ve macOS sürümü.
  - `sheets.device.tv`: yalnız TV kayıtlıysa. Parçalar " · " ile: marka (LG webOS / Samsung Tizen / Android TV); TV uygulaması
    modelini söylediyse model; Samsung'da biliniyorsa "<yıl> model"; TV uygulaması durumu ("TV uygulaması <sürüm>",
    "TV uygulaması kuruluyor", "geliştirici modu kapalı", "parola bekleniyor", "kurulum hatası <kod> (<sebep>)",
    "Samsung girişi bekleniyor", TV'deki izin sorusunun yanıt beklediğini söyleyen değer, "Host PC IP uyuşmuyor"; bilinmiyorsa yok); son olarak "bağlı" ya
    da "bağlı değil". **TV'nin kullanıcı tarafından verilen adı yazılmaz** (kişisel olabilir).
  - `sheets.device.console`: konsol (PS5 / Xbox), " · ", sonra bağlantı yolu: "Remote Play (Nino bağlanıyor)" / "oyun penceresi" / "yakalama kartı".
  - `sheets.device.status`: "çeviri açık"/"çeviri kapalı" + ", oyun: " + tanınan oyunun adı ve nereden tanındığı ya da
    "tanınmadı"; görüntü kaynağı PS5 ise ", PS5: <oturum durumu>".
- Altında ikincil `sheets.device.copy` (basınca `sheets.common.copied`): satırların düz metin özetini panoya yazar.
- İpucu `sheets.device.hint`: sorun bildirimlerine eklendiği, ad/seri no/adres içermediği.
- Aynı özet Sorun Bildir'e ve Nino'ya Sor bildirimlerine de eklenir.

| Anahtar | EN | TR |
|---|---|---|
| `sheets.device.title` | Device info | Cihaz bilgileri |
| `sheets.device.appVersion` | App version | Uygulama sürümü |
| `sheets.device.model` | Device model | Cihaz modeli |
| `sheets.device.system` | Operating system | İşletim sistemi |
| `sheets.device.tv` | TV | TV |
| `sheets.device.console` | Console | Konsol |
| `sheets.device.status` | Current status | Şu anki durum |
| `sheets.device.copy` | Copy device info | (cihaz bilgilerini panoya kopyalayan düğme) |
| `sheets.device.hint` | (bu bilgilerin bildirimlere eklendiğini, böylece kurulumun sorulmadan görüldüğünü; ad, seri no ve adres taşımadığını söyler) | (aynı anlamda) |

### 3.6 Ayrıntılar kartı
- Açılır-kapanır grup; etiket `sheets.health.details` (Details / Ayrıntılar; başlık yazısı). **Başlığın tamamı**
  tıklanınca açılıp kapanır (yalnız ok değil). Kapalı başlar. Açılıp kapanınca `sheets.common.copied` durumu sıfırlanır.
- İçinde: 260 pt yükseklikte kaydırılabilir kutu (ikincil yüzey zemin, küçük köşe), içinde 11 pt eş aralıklı, seçilebilir
  düz metin. Altında ikincil `sheets.health.copyDetails` (→ `sheets.common.copied`) ve ikincil `sheets.health.saveZip`. Hata
  olursa hata yazısı. En altta ipucu `sheets.health.zipHint` (zip'te ne var, ne yok).
- **Metin (Türkçe, sabit, destek için):** satır satır:
  1. "Nino <sürüm>, macOS <sürüm metni>, <işlemci adı>, <bellek> GB"
  2. "motor: <çevrimiçi motor kimliği ya da 'ücretsiz'>, çeviri: <sürüyor/durdu>, PS5: <oturum durumu>"
  3. "TV: <marka ya da 'yok'>, bağlı TV uygulaması <sayı>, TV uygulaması: <durum>" — durumlar: bilinmiyor, kuruluyor,
     kurulu <sürüm>, geliştirici modu kapalı, parola bekleniyor, hata <kod> (<sebep>), Samsung girişi bekleniyor, TV'deki izin
     sorusunun beklendiği durum, Host PC IP uyuşmuyor (TV'de <adres>, bu Mac <adres>).
  4. (Samsung denetimi yapıldıysa) "Samsung denetimi: geliştirici modu açık/kapalı/?, TV'de yazan Host PC IP …, Mac'in kendi adresi …,
     kurulum kapısı açık/kapalı, eksik adım: …/yok".
  5. Ölçüm özeti (altı satır): ağ türü, oturumdaki ağ ve TV kopmaları, PS5 kaç sn'dir kopuk; akış süresi, bağlanma
     denemesi, bağlanma, akışta kopma; son kopma sebebi; yeniden gönderim, tampon taşması (dakikada kayıp); görüntü
     durması (dakikada), bozuk kare; altyazı satırı, çeviri sayısı, ortanca ve en uzun süre.
  6. Boş satır, "— altyazi.log (son satırlar) —", altyazı günlüğünün son 40 satırı.
  7. Boş satır, "— tvinstall.log (son satırlar) —", TV kurulum günlüğünün son 8 satırı.
  Günlük dosyası yoksa yerine "-". Dosyanın en çok son 64 KB'si okunur.
- `sheets.health.saveZip`: günlük tamponu boşaltılır; günlük klasöründeki adında ".log" geçen dosyalar
  (altyazı, Remote Play ve TV kurulum günlükleri ve ".1" yedekleri) + yukarıdaki metin "ayrintilar.txt" adıyla geçici bir
  klasöre kopyalanır ve zip'lenir. **Aynı klasördeki ses kayıtları ve görüntü kareleri girmez** (zip çok büyüyordu). Zip
  adı "Nino-kayitlar-<tarih-saat, ':' yerine '-'>.zip". Önce İndirilenler'e, olmazsa geçici klasöre konur ve Finder'da
  seçili gösterilir. Olmazsa hata: `sheets.health.zipError` + parantez içinde sistemin hata metni.

| Anahtar | EN | TR |
|---|---|---|
| `sheets.health.details` | Details | Ayrıntılar |
| `sheets.health.copyDetails` | Copy details | Ayrıntıları kopyala |
| `sheets.health.saveZip` | (günlükleri zip dosyası olarak kaydeden düğme) | (aynı anlamda) |
| `sheets.health.zipHint` | (bir aksaklıkta zip'in yardım edene yollanmasını ister; içinde okunan altyazıların, konsolun adının ve ev ağındaki adresinin olduğunu, parola, anahtar ve hesap bilgisinin olmadığını söyler) | (aynı anlamda) |
| `sheets.health.zipError` | Couldn't save the logs. | (kayıtların kaydedilemediğini söyleyen hata) |

### 3.7 Sistem sağlığının diğer metinleri

| Anahtar | EN | TR |
|---|---|---|
| `sheets.health.checks.noData` | (çeviriyi açıp birkaç dakika oynamayı ister; ölçümün oyun sırasında yapıldığını söyler) | (aynı anlamda) |
| `sheets.health.checks.lastSession` | (gösterilenlerin bir önceki oturuma ait olduğunu, yeni ölçümün çeviri açılınca başlayacağını söyler) | (aynı anlamda) |
| `sheets.health.advice.noNetwork` | (Mac'in hiçbir ağda olmadığını söyler; konsolun kullandığı modeme bağlamayı ister) | (aynı anlamda) |
| `sheets.health.advice.networkLoss` | (konsol görüntüsünde veri yitirildiğini söyler; Mac'i kabloyla modeme takmayı (USB-C Ethernet çevirici de yeter), olmazsa modeme yaklaşıp 5 GHz bandına geçmeyi önerir) | (aynı anlamda) |
| `sheets.health.advice.video` | (görüntü donukken altyazının okunamadığını söyler; konsolu da Mac'i de kabloyla modeme takmayı ister) | (aynı anlamda) |
| `sheets.health.advice.speedEngine` | (çevirinin yavaşladığını söyler; Nino ayarlarının çeviri bölümünden parasız motora geçip farkı görmeyi önerir) | (aynı anlamda) |
| `sheets.health.advice.speedMac` | (çevirinin yavaşladığını söyler; Mac'te çalışan ağır programları kapatıp yeniden denemeyi önerir) | (aynı anlamda) |
| `sheets.health.advice.tv` | (TV uygulamasının bağlanmadığını söyler; TV'de Nino'yu açmayı ve TV'nin Mac'le tek ağda olduğuna bakmayı ister) | (aynı anlamda) |
| `sheets.health.network.wired` · `.wifi` · `.other` · `.offline` · `.unknown` | Cable · Wi-Fi · Other connection · No network · Checking… | Kablo · Wi-Fi · Başka bağlantı · Ağ yok · Denetleniyor… |
| `sheets.health.value.notStarted` | Not started | Başlamadı |
| `sheets.health.value.downFor %d` | (`%d` dakikadır bağlantı olmadığını ve Nino'nun denemeye devam ettiğini söyler) | (aynı anlamda) |
| `sheets.health.value.couldNotConnect %d` | Couldn't connect (%d tries) | (kaç denemede bağlanılamadığını söyler) |
| `sheets.health.value.noDrops` | Connected, no drops | Bağlı, hiç kopmadı |
| `sheets.health.value.drops %d` | (oynarken kaç kez koptuğunu söyler) | (aynı anlamda) |
| `sheets.health.value.noPicture` | (PS5'e bağlı olmadığı için görüntü olmadığını söyler) | (aynı anlamda) |
| `sheets.health.value.measuring` | Measuring… | Ölçülüyor… |
| `sheets.health.value.video %@ %@` | (dakikadaki kayıp paket (`%1$@`) ve donma (`%2$@`) sayısı) | (aynı anlamda) |
| `sheets.health.value.allReady %d` | (satır sayısı; hepsinin hazır çeviriden anında geldiğini söyler) | (aynı anlamda) |
| `sheets.health.value.noSubtitle` | No subtitles on screen yet | Ekranda henüz altyazı çıkmadı |
| `sheets.health.value.speed %@ %d` | (satır başına saniye ve satır sayısı) | (aynı anlamda) |
| `sheets.health.value.tvNotUsed` | Subtitles aren't going to a TV | Altyazı TV'ye gitmiyor |
| `sheets.health.value.connected` · `sheets.health.value.notConnected` | Connected · Not connected | Bağlı · Bağlı değil |
| `sheets.health.tvApp.installed %@` | (kurulu sürümü parantez içinde gösterir) | Kurulu (sürüm %@) |
| `sheets.health.tvApp.approval` | Waiting for you on the TV | TV'de onayınız bekleniyor |
| `sheets.health.tvApp.notInstalled` · `sheets.health.tvApp.failed` | Not installed · Couldn't be installed | Kurulu değil · Kurulamadı |
| `sheets.health.tvApp.approvalAdvice` | (TV ekranındaki izin sorusunda bu bilgisayara hep izin veren kutuyu işaretleyip onay düğmesini seçmeyi ister) | (aynı anlamda) |
| `sheets.health.tvApp.developerModeAdvice` | (TV'de geliştirici modunun açılmasını ister; yolunu Nino ayarlarının TV bölümünün gösterdiğini söyler) | (aynı anlamda) |
| `sheets.health.tvApp.hostIPAdvice %@ %@` | (TV'de yazan Host PC IP değerinin başka bir adres (`%1$@`) olduğunu, bu yüzden TV'nin bu bilgisayarı geri çevirdiğini söyler; adresin `%2$@` yapılmasını ister) | (aynı anlamda) |
| `sheets.health.allGood` | All looks good | Her şey yolunda |
| `sheets.health.recentProblems` | Recent problems | Son sorunlar |
| `sheets.health.autoOn` | (bunların kendiliğinden bize ulaştığını, yalnız özet gittiğini, günlük ve altyazının gitmediğini, ayrıca bildirmeye gerek olmadığını söyler) | (aynı anlamda) |
| `sheets.health.autoOff` | (otomatik bildirimin kapalı olduğunu, sorunların Sorun Bildir'den gönderilebileceğini söyler) | (aynı anlamda) |
| `sheets.health.localNetwork` | (Nino'nun yerel ağa erişemiyor olabileceğini söyler; macOS'un Yerel Ağ izin sayfasında Nino'yu açıp uygulamayı yeniden açmayı ister) | (aynı anlamda) |
| `sheets.health.openSystemSettings` | Go to System Settings | Sistem Ayarları'na git |

---

## 4. Sorun Bildir (Ayarlar › `settings.section.report`: Report a problem / Sorun Bildir)

### Taslak
Form bilgileri **uygulama açık kaldıkça** saklanır: Ayarlar kapatılıp açılınca yazılan metin, fotoğraflar ve iletişim
bilgisi kaybolmaz. Açıklama yazılmadan da gönderilebilir.

### Düzen (yukarıdan aşağı, aralar "gap")
1. **Kart:** başlık `sheets.report.noticed` (başlık yazısı).
   - Son **3 günün** sorunlarından en son 6'sı (en yenisi üstte) ve sistem sağlığındaki "muhtemel sebep" başlığı.
   - İkisi de yoksa ipucu `sheets.report.nothingNoticed`.
   - Varsa: muhtemel sebep yarı kalın gövde; altında her sorun "• <kısa saat>  <kısa ad>" küçük ikincil.
   - Sağa yaslı birincil `sheets.report.sendProblems` (gönderilemez durumdayken soluk). Basmak aşağıdaki Gönder ile aynıdır.
2. **Kart:** başlık `sheets.report.tellMore`; altında çok satırlı yazı alanı (en az 140 pt, cam yüzey, "control" köşe,
   ince cam kenar; boşken üstünde ikincil yer tutucu `sheets.report.placeholder`). Gönderirken soluk. Yazı değişince
   önceki gönderme hatası silinir.
3. **Kart:** başlık `sheets.report.photos`, sağında "<adet>/3" (ikincil).
   - Küçük resimler yan yana, her biri 112×84 pt, köşe 12, cam kenar; sağ üstte beyaz/yarı siyah çarpı dairesi (18 pt;
     ekran okuyucu: `sheets.photo.remove`) basınca kaldırır. Resim okunamazsa açık vurgu renkli boş kutu.
   - 3'ten azsa ekleme kutusu: 112×84 pt, 1 pt kesikli (5-4) cam kenar, ortada simge (hazırlanırken hourglass, değilse
     photo.badge.plus, 22 pt) ve `sheets.report.addPhoto`. Basınca çoklu seçimli resim seçici açılır.
   - Dosya seçiciden seçilen dosyalardan 60 MB'tan büyük olanlar belleğe alınmaz (yanlışlıkla seçilen video gibi).
   - Sürükle-bırak: Finder'dan dosya ya da başka uygulamadan resim bırakılabilir; üstüne gelinince kutu vurgu renkli ve
     2 pt kenarlı olur. Kalan yer kadar öğe alınır. (Bu yolda boyut sınırı yoktur.)
   - Resimler arka planda küçültülür (en uzun kenar 1600 piksel) ve JPEG'e çevrilir.
   - Resim olmayan dosya eklenirse hata yazısı `sheets.photo.unreadable`.
4. **Kart:** başlık `sheets.report.contactTitle`; tek satır alan (yer tutucu `sheets.report.contactPlaceholder`);
   çizgi; satır: solda yarı kalın `sheets.report.includeLog` + altında ipucu `sheets.report.includeLogHint`, sağda
   anahtar (varsayılan **açık**).
5. Gönderme hatası varsa hata yazısı.
6. Satır: gönderiliyorsa küçük dönen gösterge + `sheets.report.sending`; sağda birincil `sheets.report.send`.
7. **Kart:** başlık-solda-anahtar-sağda `sheets.report.auto` (varsayılan açık; uygulama ayarıdır, kaydedilir) +
   ipucu `sheets.report.autoHint`.
8. En altta en küçük ikincil yazı `sheets.report.footer`: neyin gönderildiği, parola yazılmaması.

### Gönder davranışı
- Gönderilebilir: (açıklama boş olabilir) ve şu an hazırlanmıyor / gönderilmiyor / gönderilmedi.
- Basınca: günlük tamponları boşaltılır; kurulum kimliği alınır; şunlar Nino'nun sunucusuna gider: metin (kullanıcının
  yazdığı + Nino'nun tespitleri: muhtemel sebep, son 3 günün sorunları, ölçüm özeti), fotoğraflar, iletişim bilgisi,
  uygulama sürümü, platform "mac", çeviri dili, cihaz özeti, ve anahtar açıksa günlükler (Remote Play, altyazı ve TV
  kurulum günlüklerinin son kısmı; başında "Nino <sürüm>, macOS <sürüm>" satırı).
- Başarılı olunca bütün form yerine tek kart: 30 pt yeşil onay + `sheets.report.thanks`. **1.6 sn** sonra form
  sıfırlanır (metin, fotoğraflar, iletişim boşalır; günlük anahtarı yeniden açık) ve Ayarlar listesine dönülür.
- Hata metinleri:

| Durum | Anahtar | EN | TR |
|---|---|---|---|
| günlük sınır | `sheets.report.error.dailyLimit` | (bugünlük bildirim hakkının dolduğunu, ertesi gün denemeyi ister) | (aynı anlamda) |
| internet yok / adres yok | `sheets.report.error.offline` | (bildirimin gitmediğini söyler; ağa bakıp tekrar denemeyi ister) | (aynı anlamda) |
| çok büyük | `sheets.report.error.tooLarge` | (bildirimin fazla büyük olduğunu söyler; bir resmi çıkarıp tekrar denemeyi ister) | (aynı anlamda) |
| reddedildi / sunucu hatası | `sheets.report.error.server` | (bildirimin gitmediğini söyler; bir süre sonra tekrar denemeyi ister) | (aynı anlamda) |

### Metinler

| Anahtar | EN | TR |
|---|---|---|
| `sheets.report.title` | Report a Problem | Sorun Bildir |
| `sheets.report.noticed` | What Nino noticed | (Nino'nun kendiliğinden gördüğü sorunların kart başlığı) |
| `sheets.report.nothingNoticed` | (aynı anlamda) | (son zamanlarda sorun görülmediğini, yine de gönderilebileceğini, bağlantı ayrıntılarını Nino'nun ekleyeceğini söyler) |
| `sheets.report.sendProblems` | Send problems | Sorunları gönder |
| `sheets.report.tellMore` | Anything you'd like to tell us? (optional) | (isteğe bağlı açıklama alanının başlığı; anlatmak istenen bir şey olup olmadığını sorar) |
| `sheets.report.placeholder` | (neyin olduğunu, hangi oyun olduğunu ve ne beklendiğini soran yer tutucu) | (aynı anlamda) |
| `sheets.report.photos` | (fotoğraf ve ekran görüntüsü kartının başlığı) | Fotoğraf ya da ekran görüntüsü |
| `sheets.report.addPhoto` | Add or drop here | Ekleyin ya da sürükleyin |
| `sheets.photo.remove` | Remove photo | Fotoğrafı kaldır |
| `sheets.photo.unreadable` | Nino couldn't open this file as a picture. | Nino bu dosyayı resim olarak açamadı. |
| `sheets.report.contactTitle` | (isteğe bağlı iletişim alanının başlığı) | Size nasıl ulaşalım? (isteğe bağlı) |
| `sheets.report.contactPlaceholder` | (e-posta, Instagram ya da X adresi isteyen yer tutucu) | E-posta, Instagram ya da X |
| `sheets.report.includeLog` | Include app log | (uygulama günlüğünün eklenmesini açan anahtarın etiketi) |
| `sheets.report.includeLogHint` | (günlüğün sorunu bulmaya yardım ettiğini, parola ve anahtar içermediğini söyler) | Sorunu bulmamızı kolaylaştırır. Parola ya da anahtar eklenmez. |
| `sheets.report.sending` | Sending… | Gönderiliyor… |
| `sheets.report.send` | Send | Gönder |
| `sheets.report.auto` | (sorunların kendiliğinden bildirilmesini açan anahtarın etiketi) | Sorunları kendiliğinden bildir |
| `sheets.report.autoHint` | (aynı anlamda) | (kopmalarda Nino'nun kendisinin kısa bir özet gönderdiğini; olanın ne ve ne zaman olduğu, ağın türü, cihazla TV'nin modeli; günlüklerin, altyazıların, adların ve adreslerin gitmediğini söyler) |
| `sheets.report.footer` | (açıklamanın, resimlerin ve açıksa günlüğün sorunu çözmek için Nino sunucusuna gittiğini söyler; parola yazılmamasını ister) | (aynı anlamda) |
| `sheets.report.thanks` | Thank you! We got your report. | Teşekkürler! Bildiriminiz bize ulaştı. |
