# Nino Android: kalıcı veri ve ayarlar (veri biçimi tarifi)

Bu belge, Android telefon uygulamasının (paket kimliği `com.ninotranslator.mobile`) cihazda neyi, nerede ve hangi
biçimde sakladığını anlatır. Yeni uygulama aynı paket kimliğiyle kurulacağı için bu adlar ve biçimler **kalıcı veri
sözleşmesidir**: anahtar, dosya ve klasör adları burada yazıldığı gibi (büyük/küçük harf dahil) okunmalıdır.

Genel notlar:

- Bütün SharedPreferences dosyaları özel kipte (`MODE_PRIVATE`) açılır; diskte `shared_prefs/<ad>.xml` olarak durur.
- Uygulama yedeklemeye kapalıdır (manifestte yedekleme izni yok). Bu yüzden Android'in bulut yedeğinden geri yüklenen
  veri beklenmez; Keystore anahtarı da zaten yedeğe girmez.
- "filesDir" = `/data/data/com.ninotranslator.mobile/files`, "noBackupFilesDir" = `.../no_backup`, "cacheDir" = `.../cache`.
- Yazma alışkanlığı: JSON dosyalarının çoğu önce `<dosya>.tmp` adına yazılır, sonra asıl adın yerine konur. Yarım kalmış
  `.tmp` dosyaları okunmaz; yeni uygulama bunları görmezden gelebilir ya da silebilir.
- Enum değerleri (ör. `REMOTE_PLAY`) diske **büyük harfli adlarıyla** yazılır. Tanınmayan değer okununca varsayılan
  kullanılır.

---

## 1. SharedPreferences dosyaları

Toplam dört dosya (yayın sürümünde) + bir dosya (yalnız hata ayıklama sürümünde):

| Dosya | İçerik |
|---|---|
| `settings` | Bütün kullanıcı ayarları ve uygulama durumu (şifresiz). |
| `secrets` | Şifreli değerler (PSN hesabı, PS5 kaydı, API anahtarları, Xbox jetonu, PS5 giriş şifresi). |
| `report` | Sorun bildirimi için kurulum kimliği (yedek). |
| `app_update` | Telefon uygulamasının yeni sürüm denetimi. |
| `demo` | Yalnız debug derlemesi: deneme kipi (yayında yok). |

### 1.1 `settings`

Türler: B = boolean, I = int, L = long, S = string, SS = string kümesi (string set).

#### Kurulum ve akış durumu

| Anahtar | Tür | Varsayılan | Anlamı ve geçerli değerler |
|---|---|---|---|
| `welcomeSeen` | B | false | Tanıtım (3 sayfa) görüldü. Kurulum akışının ilk adımı buna bakar. |
| `tourShown` | B | false | Ana ekran turu (4 adım) gösterildi. |
| `consoleAsked` | B | false | Kurulumda konsol türü (PS5/Xbox) soruldu. |
| `platform` | S | yok | `PLAYSTATION` ya da `XBOX`; boş seçimde anahtar silinir. **Değeri okunmaz**, yalnız var olup olmadığına bakılır (bkz. §5.1). |
| `setupSkipped` | B | false | Kurulumda PSN girişi/PS5 eşlemesi `skip_for_now` ile atlandı. |
| `onboarded` | B | false | Kurulum bitti (hedef seçildi ya da telefondan TV uygulaması kuruldu). |
| `videoSource` | S | `REMOTE_PLAY` | Görüntü kaynağı: `REMOTE_PLAY`, `CAPTURE_CARD`, `XBOX`. Konsol türünün tek doğru kaynağı budur. |
| `target` | S | `TV` | Altyazının gösterildiği yer: `TV` ya da `PHONE`. |
| `tvName` | S | yok | Hedef seçiminde görülen ilk TV'nin adı (ana ekranda "Altyazı · Salon TV" gibi gösterilir). |
| `homeStyleV4` | S | `LIVING_ROOM` | Ana ekran arayüzü: `LIVING_ROOM` (salon, fiş) ya da `TOGGLE` (cam düğme). |
| `homeStyle` | S | — | **Eski anahtar, bilerek okunmaz.** V4'ten önce kaydedilen seçim; herkes bir kez salona geçsin diye yok sayılır. |

#### Dil ve çeviri

| Anahtar | Tür | Varsayılan | Anlamı ve geçerli değerler |
|---|---|---|---|
| `targetLanguage` | S | özel (aşağıda) | Çeviri dili, iki harfli küçük kod: `tr`, `ar`, `hi`, `id`, `th`, `vi`, `ur`, `bn`, `ms`, `tl`, `nl`. Kaydederken ilk iki harf küçültülerek yazılır. Filipince `tl` olarak tutulur (`fil` değil). |
| `engine` | S | `FREE` | Çeviri motoru: `FREE` (cihaz üstü ücretsiz), `DEEPL`, `GEMINI`, `OPENAI`, `CLAUDE`. |
| `aiModel` | S | yok | Seçilen yapay zekâ modelinin kimliği (uygulamayla gelen `ai-models.json` listesindeki `id`). Listede yoksa o sağlayıcının ilk modeli kullanılır. Arayüzde bunu yazan bir yer bulunmadı (bkz. Belirsizlikler). |
| `packsEnabled` | B | true | Oyun paketleri açık mı (ana ekran ve ayarlarda gösterilir). |
| `disabledPacks` | SS | boş | Kapatılan paket kimlikleri (paket dosyasının adından `.json`/`.gz` atılmış hâli, ör. `pool-genel`). |
| `sharePool` | B | true | Ortak havuza katkı (okunan İngilizce satırların sunucuya gönderilmesi ve havuzdan çeviri alınması). |
| `askGame` | B | true | Oyun paketle tanınmazsa çeviri başladıktan ~2 dk sonra oynanan oyun bir kez sorulsun. |
| `showSpeakerNames` | B | true | Altyazıdaki konuşan adı ("ARTHUR: …") çeviride gösterilsin. |
| `fastSubtitleDetection` | B | false | Değişmeyen altyazı bölgesi 20 yerine en çok 2 kare yeniden kullanılır. |
| `lastGame.<konsol adı>` | S | yok | O konsolda son seçilen oyunun adı. `<konsol adı>`: PS5'in adı (ad boşsa adresi), Xbox'ın adı (boşsa `Xbox`). Anahtar dinamiktir; birden çok olabilir. |
| `ninoLastGamePoolFirst` | B | false | Son tanınan oyun "havuz öncelikli" miydi (GTA 6). Yeni oturumda oyun tanınana kadar tema ve altyazı yeri buna göre seçilir. |

#### Altyazı görünümü (TV ve telefon)

| Anahtar | Tür | Varsayılan | Anlamı ve geçerli değerler |
|---|---|---|---|
| `subtitleScale` | I | 100 | Yazı ölçeği, yüzde; okurken ve yazarken 40–160'a sıkıştırılır. Arayüzde %10 adımlarla. |
| `tvAutoSize` | B | özel | TV yazı boyunu oyunun altyazısına uydursun mu. **Anahtar yoksa** değeri: `subtitleScale == 100` ve `tvFontSize == 46` ise true, değilse false. |
| `tvFontSize` | I | 46 | TV'deki temel yazı boyu: 36, 46, 58, 72. TV'ye giden boy = round(tvFontSize × subtitleScale / 100). Güncel arayüzde yazan yer yok; eski kayıtlarda bulunabilir. |
| `phoneTextSize` | I | 34 | Telefon ekranındaki altyazının yazı boyu (sp). Güncel kodda okunan/yazan yer bulunmadı (eski kalıntı). |
| `textColor` | S | `WHITE` | `WHITE` ya da `YELLOW`. |
| `subtitleFont` | S | `condensed` | **Küçük harfli** ad yazılır: `condensed`, `modern`, `rounded`, `system`. Okurken büyük/küçük harf fark etmez; büyük harfli enum adı (`CONDENSED` vb.) da kabul edilir; tanınmayan değer `condensed` olur. |
| `tvBackground` | I | 72 | TV'deki altyazı kutusunun koyuluğu, yüzde 0–100 (sıkıştırılır). |
| `tvBackgroundShape` | S | `FIT` | `FIT` (yazı kadar) ya da `BAND` (tam genişlik bant). |
| `stackPrevious` | B | true | Hızlı konuşmada önceki satırlar üstte kısa süre soluk kalsın. |
| `tvWatermark` | B | true | TV'nin sol altındaki küçük Nino işareti. |
| `tvDisplayMode` | S | `IN_APP` | Android TV'de PS5 görüntüsü: `IN_APP` (uygulama içinde) ya da `OVERLAY` (TV kendi HDMI girişini gösterir, altyazı katmanda). |
| `tvPlacement` | S | `COVER` | Çevirinin yeri: `COVER` (İngilizcenin üstünü örter), `ABOVE`, `BELOW`, `FIXED`. |
| `tvBottomPercent` | I | 7 | `FIXED` iken ekranın altından yükseklik, yüzde 0–85 (sıkıştırılır). |
| `keepScreenOn` | B | true | Çeviri sürerken telefon ekranı açık kalsın. |

#### Okunan bölgeler

| Anahtar | Tür | Varsayılan | Biçim |
|---|---|---|---|
| `region` | S (JSON) | `{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86}` | Altyazının arandığı bölge. JSON nesnesi, dört alan da ondalık sayı ve görüntüye oranla 0–1: `top`, `bottom`, `left`, `right`. Eksik alan ya da bozuk JSON → varsayılan bölge. |
| `areaPreset` | S | özel | `BOTTOM`, `TOP`, `FULL`, `CUSTOM`. **Anahtar yoksa** kayıtlı `region` hazır seçimlerden biriyle (±0,001) aynıysa o, değilse `CUSTOM`. |
| `extraAreas` | S (JSON) | `[]` | Altyazının yanında okunan ek alanlar (görev, bildirim, telefon), **en çok 3**. JSON dizisi; her öğe: `id` (UUID metni; boşsa okurken yenisi üretilir), `name` (metin), `region` (yukarıdaki dört alanlı nesne; yoksa "görev" hazır bölgesi), `enabled` (boolean, yoksa true). 3'ten fazlası okunmaz/yazılmaz. |

Hazır bölgeler (yeni uygulama aynı sayıları kullanmalı ki `areaPreset` türetmesi tutsun):

- `BOTTOM`: 0.62 / 0.97 / 0.14 / 0.86 (top/bottom/left/right; varsayılan bölge)
- `TOP`: 0.03 / 0.38 / 0.14 / 0.86
- `FULL`: 0 / 1 / 0 / 1
- Ek alan hazırları: görev 0.03/0.30/0.66/0.98, bildirim 0.58/0.88/0.02/0.30, telefon 0.50/0.95/0.72/0.98.

#### Xbox

| Anahtar | Tür | Varsayılan | Biçim |
|---|---|---|---|
| `xboxConsole` | S (JSON) | yok | Seçilen Xbox: `id` (zorunlu), `name`, `model`, `streamingEnabled` (boolean), `powerState` (metin, ör. `On`). Seçim kalkınca anahtar silinir. |
| `xboxAudioOnDevice` | B | true | Xbox ev yayınında oyunun sesi telefonda çalınsın. |

(Microsoft jetonu `secrets` dosyasındadır, §1.2.)

#### TV uygulaması kurulumu

| Anahtar | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `experimental.tvInstallBrand` | S | yok | Kurulum ekranında son seçilen marka: `LG`, `SAMSUNG`, `ANDROID_TV`. |
| `tvApp.brand` | S | yok | Bu telefonun TV uygulamasını kurduğu TV'nin markası (aynı üç değer). |
| `tvApp.host` | S | yok | O TV'nin adresi (IP). Boşsa kayıt yok sayılır. |
| `tvApp.port` | I | 0 | O TV'nin bağlantı portu (Android TV'de ADB portu; 0 = bilinmiyor/varsayılan). |
| `tvApp.version` | S | yok | TV'de görülen Nino TV sürümü. |
| `tvApp.lgSessionRenewed.<adres>` | L | yok | LG geliştirici modu oturumunun son uzatıldığı an (Unix ms). `<adres>` boşlukları atılmış, küçük harfe çevrilmiş TV adresi. Uzatma en erken 20 saatte bir yapılır. |

`tvApp.*` dörtlüsü birlikte yazılır ve birlikte silinir; `tvApp.brand` ya da `tvApp.host` eksikse kurulu TV yok sayılır.

#### Bildirim, ölçüm ve sağlık

| Anahtar | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `notify.disconnect` | B | true | Bağlantı koptuğunda bildirim tercihi. |
| `notify.packs` | B | true | Yeni paket geldiğinde bildirim tercihi. |
| `usageData` | B | true | Profil › Kullanım verisi (Firebase istatistik ve çökme raporu, Meta olayları). |
| `autoReport` | B | true | Sorunları kullanıcı yazmadan otomatik bildir. |
| `translating` | B | false | Çeviri hizmeti çalışıyor. Açılışta okunup hemen false yapılır; true kaldıysa önceki süreç çeviri sırasında ölmüştür. |
| `lastExitReportAt` | L | 0 | Raporlanan son önceki-kapanış kaydının zaman damgası (sistemin süreç çıkış kaydındaki ms). |
| `lastSessionMs` | L | 0 | Son çeviri oturumunun **süresi** (ms; bitiş − başlangıç). |
| `ninoDownloadTotal` | I | 0 | Son bilinen toplam indirme sayısı (ana ekrandaki TV'de). 0 = hiç alınmadı, gösterge gizli. |

### 1.2 `secrets` (şifreli)

Bu dosyadaki her değer Android Keystore anahtarıyla şifrelenmiş bir metindir (biçim §2). Değer boş ya da null
yazılmak istenirse anahtar **silinir**. Çözülemeyen değer (anahtar kayıp, bozuk veri) "yok" sayılır ve kullanıcıdan
yeniden istenir.

Düz metin (şifre çözüldükten sonraki) biçimleri:

| Anahtar | Düz metin biçimi |
|---|---|
| `accountId` | PSN hesap kimliği: **8 baytın** base64 metni (satır sonu yok, standart alfabe). Çözülen bayt sayısı 8 değilse yok sayılır. |
| `console` | Kayıtlı PS5, JSON nesnesi: `host` (IP metni), `name` (PS5'in adı), `registKey` (base64), `morning` (base64). Hepsi zorunlu; biri eksikse kayıt yok sayılır. `registKey`'in içi sıfır baytla biten ASCII onaltılık bir sayıdır (uyandırma kimliği olarak da kullanılır). PS5 ağda adres değiştirince `host` kendiliğinden güncellenip yeniden yazılır. |
| `loginPasscode` | İkinci hesabın PS5 giriş şifresi: tam **4 rakam**. Boşluklar atılır; 4 rakam değilse silinir. |
| `xboxUserToken` | Microsoft kullanıcı jetonu, JSON nesnesi (Microsoft jeton yanıtının olduğu gibi kopyası + bir ek alan): `access_token`, `refresh_token`, `expires_on` (ISO 8601 UTC an, ör. `2026-11-22T18:04:05.123Z`; yazılırken "şimdi + expires_in" olarak eklenir), ayrıca yanıtta ne geldiyse (`token_type`, `expires_in`, `scope`, `user_id` …). `refresh_token` boşsa kayıt geçersiz sayılır (yeniden giriş). Yenileme yanıtında `refresh_token` gelmezse önceki korunur. |
| `key.DEEPL` | DeepL API anahtarı (başı/sonu kırpılmış). `:fx` ile biten anahtar ücretsiz DeepL adresine gider. |
| `key.GEMINI` | Gemini API anahtarı. |
| `key.OPENAI` | OpenAI API anahtarı. |
| `key.CLAUDE` | Claude API anahtarı. |

(`key.FREE` hiç yazılmaz. Anahtar adı = `key.` + motorun büyük harfli adı.)

### 1.3 `report`

| Anahtar | Tür | Anlamı |
|---|---|---|
| `install` | S | Kurulum kimliğinin yedeği (küçük harfli UUID metni). |

**Tek kurulum kimliği (yeni uygulama):** havuz (`translation-pool`), satır kuyruğu (`pool/state.json`), sorun
bildirimi, otomatik bildirim, Nino'ya Sor, ölçüm ve TV bağlantısı aynı UUID'yi kullanır. Uygulama açılışında bir kez
seçilir: önce `files/pool/state.json` içindeki `install`, sonra bu anahtar, sonra `files/translation-pool/install`;
geçerli bir UUID olan ilki korunur (büyük harfliyse küçültülür). Hiçbiri UUID değilse yeni rastgele UUID üretilir.
Seçilen kimlik üç yere de yazılır (`state.json`'ın öbür alanları korunur). Eski uygulamada sorun bildirimi 8–64
karakterlik herhangi bir kimliği kabul ediyordu; yeni uygulamada UUID olmayan kimlik değiştirilir (ölçüm sunucusu
UUID ister).

### 1.4 `app_update`

Yalnız GitHub'dan kurulan kopyada kullanılır; Play Store'dan kurulmuşsa denetim yapılmaz.

| Anahtar | Tür | Anlamı |
|---|---|---|
| `checked_at` | L | GitHub'a son bakılan an (Unix ms). Yanıt geldiyse (403 dahil) güncellenir; 3 saat dolmadan yeniden bakılmaz. Değer 0 ya da gelecekte ise hemen bakılır. |
| `latest` | S | Bilinen en son yayın sürümü, başındaki `v` atılmış (ör. `0.2.6`). Taslak/ön sürüm yayınları yazılmaz. |
| `dismissed` | S | **Eski anahtar.** Eski sürümlerde ✕ ile kalıcı gizlenen sürüm. Artık okunmaz; ✕'e basılınca silinir. Gizleme yalnız uygulama açık kaldıkça (bellekte) sürer. |

### 1.5 `demo` (yalnız debug derlemesi)

`enabled` (B, false), `speed` (float, 1.0; 0.25–1'e sıkıştırılır), `clip` (S, klip dosya yolu). Ayrıca demo kipi
sahte bir PS5 kaydı yazar; adresi `demo.invalid`'dir. Yayın sürümü bu dosyayı hiç açmaz.

---

## 2. Android Keystore

| Takma ad (alias) | Durum | Kullanım |
|---|---|---|
| `nino-secrets` | Güncel | `secrets` dosyasındaki bütün değerlerin şifrelenmesi. |
| Eski sürümün takma adı (aşağıda) | Eski | Aynı iş; eski kurulumlarda değerler bununla şifrelidir. |

Eski takma ad, proje kuralı gereği belgede düz yazılmaz; kaynak koddaki "eski adlar" dosyasında base64 olarak durur:
`Y291Y2hzdWJzLXNlY3JldHM=` (UTF-8 base64 çözülünce takma ad elde edilir). Yeni uygulamada da yalnız o dosyada,
kodlanmış hâlde durmalıdır.

Anahtarın özellikleri:

- Tür: AES, 256 bit, Android Keystore sağlayıcısında üretilir (dışarı çıkarılamaz).
- Amaç: şifreleme + çözme. Blok kipi GCM, dolgu yok (`AES/GCM/NoPadding`).
- Kullanıcı doğrulaması (parmak izi vb.) istenmez; StrongBox özellikle istenmez; anahtar ekran kilidine bağlı değildir.
- IV her şifrelemede Keystore tarafından rastgele üretilir (12 bayt). Kimlik doğrulama etiketi 128 bit.

Saklanan değerin biçimi (her `secrets` anahtarı için):

```
base64( IV[12 bayt] || şifreli metin || GCM etiketi[16 bayt] )
```

- base64 standart alfabe, **satır sonu yok** (NO_WRAP), dolgulu (`=`).
- Düz metin UTF-8'dir. Ek doğrulanmış veri (AAD) kullanılmaz.
- Çözme: ilk 12 bayt IV, kalanı şifreli metin+etiket, etiket uzunluğu 128 bit.

Anahtar seçim kuralı (veri taşımanın kalbi): önce `nino-secrets` aranır; yoksa eski takma ad aranır ve **bulunursa
olduğu gibi kullanılmaya devam edilir** (anahtar çıkarılamadığı için yeniden şifreleme yapılmaz; eski kurulumda yeni
değerler de eski anahtarla şifrelenir). İkisi de yoksa `nino-secrets` adıyla yeni anahtar üretilir. Silme işleminde
`secrets` dosyası tamamen boşaltılır ve iki takma ad da Keystore'dan silinir.

Keystore'da başka takma ad yoktur. TV kurulumunda kullanılan RSA anahtarları Keystore'da değil, dosyadadır (§3.3).

---

## 3. Dosyalar

### 3.1 `filesDir` (`files/`)

| Yol | Biçim ve anlamı |
|---|---|
| `history.json` | Çevrilen son altyazılar ("Geçmiş" ekranı). JSON: `{"version":1,"entries":[…]}`; en yenisi başta, **en çok 200** öğe. Öğe: `id` (int, artan), `date` (UTC metin `yyyy-MM-ddTHH:mm:ssZ`, saniye hassasiyeti), `source` (İngilizce), `translation`, `origin` (`pack` ya da `engine`; başka değer `engine` sayılır). Metinler en çok 500 karakter. Bozuk dosya = boş geçmiş. Mac/iPhone/Windows ile aynı biçim. |
| `packs-remote/` | Sunucudan inen oyun paketleri (yeni uygulamada paketler gömülmez, yalnız havuzdan iner; sözlük ve model listesi Nino'nun kendi dosyaları). `<paket id>.json.gz` (gzip'li paket JSON'u) + `packs.state` (JSON: `checked` = son bakış Unix ms, `packs` = dizi; öğe `id`, `title`, `version` (long; −1 = indirme başarısız, eski sürüm kullanılıyor), `sha256` (küçük harf onaltılık)). Geçici: `<id>.download`, `packs.state.tmp`. Paketler SHA-256 ile doğrulanır; liste dosyasında olmayan `.json.gz` yüklenmez. |
| `packs-imported/` | Kullanıcının içe aktardığı topluluk paketleri. `<id>.json`, `id` = `community-<ad-slug>`. JSON: `format` (1), `id`, `title`, `entries` (nesne: İngilizce satır → çeviri). Nokta ile başlayan dosyalar (`.<uuid>.tmp`) yok sayılır. |
| `pool/` | Ortak havuz kuyruğu (aşağıda ayrıntı). |
| `translation-pool/` | Havuzdan gelen çevirilerin yerel kopyası (aşağıda). |
| `Translations/` | Çeviri önbelleği (büyük T ile). Aşağıda. |
| `glossary/` | İsteğe bağlı kullanıcı terim sözlükleri, `*.json` (uygulama bu klasöre kendisi yazmaz; yalnız okur). Biçim: `{"game":"…","terms":{"İngilizce":"Çeviri"},"keep":["Ad"],"keepExact":["Ad"]}` (+ isteğe bağlı `phrases`, `lines` nesneleri). |
| `subtitle-layout.json` | Her oyunun altyazısının ekrandaki yeri (öğrenilen şerit). JSON nesnesi: anahtar oyun anahtarı (paket kimliği, ör. `rdr2`; bilinmiyorsa `genel`; GTA 6/havuz öncelikli oyunda `gta-6`), değer `[[üst, alt], …]` dizisi (0–1 oranları), oyun başına en çok 60 örnek, en yenisi sonda. |
| `phone-memory-<dil>.json` | Oyun içi telefon mesajlarının çeviri hafızası, çeviri diline özel (`<dil>` = `tr`, `ar` …). Düz JSON nesnesi: anahtar → çeviri metni. Belli bir sayıyı aşınca boşaltılır. |
| `health/sorunlar.json` | Son sorunlar (PS5 koptu, ağ gitti, TV koptu…), **en çok 40**, JSON dizisi. Öğe: `id` (UUID), `date` (Unix ms), `kind` (`ps5Dropped`, `ps5Unreachable`, `networkLost`, `tvDropped`), `network` (metin), isteğe bağlı `reason`, `streamedMinutes` (ondalık), `framesPerSecond` (ondalık), `game`. Tanınmayan `kind` atlanır. |
| `health/otomatik-bildirim.json` | Otomatik sorun bildirimi sayacı: `day` (`yyyy-MM-dd`, yerel gün), `sent` (o gün gönderilen, en çok 3), `pending` (gönderilemeyen bildirimin hazır JSON gövdesi, metin olarak; yoksa boş). |
| `tvinstall.log` | TV kurulum günlüğü, düz metin, her satır `yyyy-MM-dd HH:mm:ss <ileti>`. 512 KB'ı geçince silinip baştan başlar. |
| `line-pool.json` | **Eski sürümün havuz kuyruğu** (bkz. §4). |
| `line-pool.json.imported` | Eski kuyruk içe alındıktan sonra kenara konmuş hâli. |
| `demo-ps5.mp4` | Yalnız debug demo kipi. |

#### `pool/` (ortak havuz satır kuyruğu)

| Yol | Biçim |
|---|---|
| `pool/state.json` | JSON: `install` (tek kurulum kimliği, UUID; §1.3), `frozenThrough` (long), `failures` (int), `nextAttempt` (long ms), `serverRetryAt` (long ms), `app` (son çalışan uygulama sürümü), `dropped` (int). |
| `pool/state.broken-<unix saniye>.json` | Okunamayan durum dosyasının kenara konmuş hâli. |
| `pool/pending.jsonl` | Bekleyen satırlar, her satır bir JSON nesnesi: `s` (sıra no, long), `t` (temizlenmiş İngilizce metin), `g` (oyun kimliği ya da null), `e` (oturum kimliği ya da null), `a` (Unix **saniye**, ondalık). |
| `pool/outbox/*.json` | Gönderilmeye hazır paketler. Dosya adı `<15 haneli ms>-<4 haneli sıra>-<batch uuid>.json`. İçerik: `v` (1), `batch`, `install`, `app`, `platform` (`android`), `lines` (dizi: `text`, `game`, `session`, `count`, `first`, `last`), `upTo` (long). |
| `pool/parked/*.json` | Sunucunun reddettiği/ertelediği paketler (aynı biçim); uygulama sürümü değişince `outbox/`a geri taşınır. |
| `pool/endpoint.txt` | İsteğe bağlı, deneme sunucusu adresi (`http://…` ya da `https://…`). Yoksa canlı havuz sunucusu kullanılır. Sorun bildirimi, indirme sayacı ve çeviri havuzu da bu adresi kullanır. Uygulama bu dosyayı yazmaz. |

#### `translation-pool/`

| Yol | Biçim |
|---|---|
| `translation-pool/install` | Düz metin, küçük harfli 36 karakterlik UUID. Yeni uygulamada tek kurulum kimliğinin kopyası (§1.3). |
| `translation-pool/translations-<dil>.json` | JSON: `language`, `texts` (nesne: kaynak anahtar → çeviri), `cursors` (nesne: oyun → `{since: long, after: metin, checked: ondalık}`). Dil başına en çok 400 000 çeviri. |

#### `Translations/` (çeviri önbelleği)

Mac/iPhone/Windows ile aynı biçim. Her motor + kaynak dil + hedef dil için ayrı dosya. Dosya her satırı
`["kaynak","çeviri"]` olan iki öğeli JSON dizisinden oluşan, sonuna eklenen bir kayıttır (`.jsonl`). Bellekte en çok
20 000 kayıt; dosya iki katına uzayınca yeniden yazılır (`<ad>.tmp` üzerinden).

Dosya adı kuralı:

- Motor, kaynak ve hedef dilin hepsi yalnız `a-z`, `0-9`, `-` içeriyorsa: `v1-<motor>-<kaynak>-<hedef>.jsonl`
  (her parçada harf/rakam/`_` dışı karakter `_` olur). Ör. ücretsiz motor: `v1-mlkit_p<N>-en-tr.jsonl`
  (`<N>` ücretsiz çeviri hattının sürüm numarası; numara değişince eski dosya kullanılmaz), DeepL: `v1-deepl-en-tr.jsonl`.
- Değilse (ör. yapay zekâ motoru `gemini:<model id>` gibi `:` ya da `.` içerir):
  `v1h-<SHA-256 onaltılık>.jsonl`; özet, `motor + \u0000 + kaynak + \u0000 + hedef` metninin UTF-8 baytlarından alınır.
- Kaynak dil hep `en`, hedef dil `targetLanguage`'in iki harfli kodu.

### 3.2 `cacheDir` (`cache/`)

| Yol | Anlamı |
|---|---|
| `nino-androidtv.apk` | Android TV'ye kurmak için uygulama içinden çıkarılan APK'nın geçici kopyası. Her seferinde yeniden yazılır. |
| `last-region.jpg` | Son okunan bölgenin JPEG görüntüsü (kalite 80; sorun bildirimine eklenmek için). |

Bunlar silinebilir; kalıcı veri değildir.

### 3.3 `noBackupFilesDir` (`no_backup/`)

TV'lere kurulum için kullanılan anahtarlar ve sertifikalar (şifresiz dosya, Keystore'da değil):

| Yol | Biçim |
|---|---|
| `adb/adbkey` | Android TV'ye ADB bağlantısı için RSA 2048 özel anahtar, PKCS#8 DER (ham bayt). Yoksa üretilir. TV bu anahtarı bir kez onaylar; kaybolursa TV'de yeniden onay gerekir. |
| `sdb/adbkey` | Samsung TV'ye SDB bağlantısı için aynı biçimde ayrı RSA anahtarı. |
| `samsung/<DUID>/` | Bir Samsung TV için imza profili. `<DUID>` harf/rakam/`_`/`-` dışı karakterler `_` yapılmış TV kimliği. İçinde: `key.pk8` (RSA özel anahtar, PKCS#8 DER), `author.cer` ve `distributor.cer` (X.509 DER), `device-profile.xml`, `duid.txt` (sertifikanın alındığı TV'nin DUID'i). Üç ana dosya varsa profil var sayılır. |
| `samsung/<DUID>.rejected-<yyyyMMddHHmmss>/` | TV'nin reddettiği sertifika profili (kenara konmuş). |
| `lg/<adres>.key` | LG geliştirici modunun Key Server'ından alınıp çözülmüş SSH anahtarı (ham bayt), TV adresine göre. `<adres>` harf/rakam/`.`/`_`/`-` dışı karakterler `_` yapılmış TV adresi. |

### 3.4 Uygulamanın dosya olarak tutmadığı ama cihazda kalan veriler

- **WebView verisi** (çerezler, localStorage, IndexedDB): PSN girişi ve Samsung hesabı girişi uygulama içi
  WebView'da yapılır. PSN giriş ekranı her açıldığında bütün WebView çerezleri ve sayfa depoları silinir. Kalıcı
  bir PSN oturumu ya da jetonu saklanmaz: girişten yalnız 8 baytlık hesap kimliği alınıp `secrets/accountId`'ye yazılır.
- **Uygulama dili**: Android 13+ sistemde uygulama başına dil olarak saklanır (sistem tutar, bizim dosyamızda değil).
- Firebase ve Meta kütüphanelerinin kendi SharedPreferences/dosyaları (bize ait değil, okunması gerekmez).
- Bildirim kanalı kimliği: `translation` (çeviri sürerken gösterilen ön plan bildirimi).

---

## 4. Eski sürümden veri taşıma kuralları

1. **Keystore anahtarı**: güncel takma ad `nino-secrets` yoksa eski takma ad (`Y291Y2hzdWJzLXNlY3JldHM=`, base64)
   kullanılır, yeniden adlandırılmaz, yeniden şifreleme yapılmaz (§2). Yeni uygulama bu sırayı aynen korumalı; aksi
   hâlde eski kurulumların PSN kimliği, PS5 kaydı ve API anahtarları okunamaz hâle gelir.
2. **`line-pool.json`** (eski havuz kuyruğu): havuz açıksa ve dosya varsa bir kez okunur. Biçim:
   `{"queue":[{"text":"…","firstSeen":"yyyy-MM-ddTHH:mm:ssZ"}, …]}`. Uygun satırlar `pool/pending.jsonl`'e eklenir
   (`g` ve `e` null, `a` = `firstSeen` saniye; okunamazsa şimdi). Sonra dosya `line-pool.json.imported` adına taşınır.
3. **`homeStyle`** (eski ana ekran seçimi): bilerek okunmaz; yerine `homeStyleV4` kullanılır.
4. **`app_update/dismissed`**: okunmaz, karttaki ✕'e basılınca silinir.
5. **`targetLanguage` yoksa**: kurulumu bitmiş (`onboarded` = true) eski kurulumlar `tr`; yeni kurulumda telefonun
   dili listedeyse o, değilse `tr`. Değer ilk okumada `settings`'e yazılır. Telefon dili `in` (eski Endonezce kodu)
   ise `id`, `fil…` ise `tl` sayılır.
6. **`tvAutoSize` yoksa**: daha önce yazı boyunu değiştirmiş kullanıcı (ölçek ≠ 100 ya da tvFontSize ≠ 46) için
   kapalı, değilse açık başlar.
7. **`areaPreset` yoksa**: kayıtlı `region`'dan türetilir.
8. **`subtitleFont`**: eski kayıtlardaki büyük harfli enum adları da kabul edilir; yoksa `condensed`.
9. **Konsol türü**: eski kurulumlar PlayStation sayılır (§5.1). `platform` anahtarı yalnız "var mı" diye okunur.
10. **Çeviri önbelleği**: basit motor adlarında eski düz dosya adı korunur; yalnız özel karakterli motor adları özetli
    (`v1h-…`) ada geçer. Ücretsiz motorun sürüm numarası değişince eski önbellek dosyası okunmaz (silinmez).
11. Eski sürümün klasör/kimlik adlarından başka taşınan bir şey kodda bulunmadı: "eski adlar" dosyasında yalnız
    Keystore takma adı var.

---

## 5. Ayarların ilişkileri

### 5.1 Konsol türü ve görüntü kaynağı

- Tek doğru kaynak `videoSource`'tur. Konsol türü şöyle türetilir: `videoSource` = `XBOX` ise Xbox; değilse
  `consoleAsked` true, `videoSource` = `CAPTURE_CARD` ya da `platform` anahtarı **var** ise PlayStation; hiçbiri değilse
  "seçilmedi" (kurulumda sorulur). Seçilmediyse uygulamanın geri kalanı PlayStation varsayar.
- Konsol türü seçilince: `consoleAsked` = (seçim var mı), `platform` yazılır (boş seçimde silinir); Xbox seçildiyse
  `videoSource` = `XBOX`; Xbox dışı seçilir ve kaynak `XBOX` ise `videoSource` = `REMOTE_PLAY`.
- Yakalama kartı (`CAPTURE_CARD`) seçiliyken PSN girişi ve PS5 eşlemesi gerekmez; kurulum o adımları atlar. Bu
  kipte "Xbox ile okunuyor" sayılmaz (görüntü karttan gelir).
- Xbox'a hazır olmak = `xboxConsole` dolu **ve** `secrets/xboxUserToken` geçerli.

### 5.2 Kurulum akışının sırası (hangi ekranın açılacağı)

Sırayla ilk eksik adım açılır:

1. `welcomeSeen` false → tanıtım.
2. Konsol türü seçilmemiş **ve** `onboarded` false **ve** `accountId` yok **ve** `console` yok **ve** `setupSkipped`
   false → konsol türü sorusu.
3. Xbox ise: Microsoft girişi yoksa (ve atlanmadıysa) giriş; `xboxConsole` yoksa (ve atlanmadıysa) Xbox seçimi;
   sonra `onboarded` false ise hedef seçimi, değilse ana ekran.
4. PlayStation ise: `accountId` yok, atlanmamış ve yakalama kartı değilse → PSN girişi; `console` yok (aynı
   koşullar) → PS5 eşlemesi; `onboarded` false → hedef (TV/telefon) seçimi; yoksa ana ekran.

Hedef seçimi bitince `target`, `tvName` (ağda görülen ilk TV'nin adı) ve `onboarded` = true yazılır. Telefondan TV
uygulaması kurulunca da `tvApp.*` yazılır, `target` = `TV` ve `onboarded` = true olur.

### 5.3 Çeviri dili ve arayüz dili

- Arayüz dili ayrı bir ayar değildir: **çeviri dilini izler**. `targetLanguage`'den arayüz etiketi türetilir:
  `tl` → `fil`; listedeki diğer kodlar olduğu gibi (`tr`, `ar`, `hi`, `id`, `th`, `vi`, `ur`, `bn`, `ms`, `nl`);
  listede olmayan → `en`. Telefonun sistem dili İngilizce olsa da arayüz bu dilde açılır.
- Android 13 ve üstü: uygulama açılışında ve `targetLanguage` her değiştiğinde sistemin uygulama başına dil ayarı bu
  etikete çekilir (zaten aynıysa dokunulmaz). Açık ekranlar kendiliğinden yeniden çizilir. Uygulamanın dil listesi
  (`locales_config`): tr, en, ar, hi, id, th, vi, ur, bn, ms, fil, nl.
- Android 12 ve altı: her etkinliğin bağlamı bu dilin yereliyle sarılır; değer doğrudan `settings` dosyasındaki
  `targetLanguage`'ten okunur. Not: bu yolda anahtar yoksa telefon dilinden türetilen değer kullanılır ama **yazılmaz**
  ve `onboarded` kuralı uygulanmaz (bkz. Belirsizlikler).
- Sağdan sola: `ar` ve `ur`'de yön sağdan sola olur.
- Çeviri dili değişince dile bağlı dosyalar değişir: çeviri önbelleği dosyası, `phone-memory-<dil>.json`,
  `translation-pool/translations-<dil>.json`. Sözlük, oyun paketleri ve Türkçe düzeltmeler yalnız `tr`'de çalışır.
  DeepL `hi`, `ur`, `bn`, `ms`, `tl` dillerini desteklemez.
- Yeni dil "bir sonraki çeviri oturumunda" kullanılır (arayüz notu).

### 5.4 Altyazı görünümü

- TV'ye giden yazı boyu = round(`tvFontSize` × `subtitleScale` / 100), ölçek 40–160'a sıkıştırılmış.
- `tvAutoSize` açıkken TV ölçeği yok sayar. Kullanıcı ölçek kaydırıcısını oynatınca `tvAutoSize` otomatik **false**
  yapılır.
- `tvPlacement` = `COVER` iken `tvBackground` 60'ın altındaysa TV'ye 100 (tam opak) gider; diğer kiplerde değer
  olduğu gibi gider. Kayıtlı değer değişmez, yalnız giden değer düzeltilir.
- `tvBottomPercent` yalnız `FIXED` kipinde anlamlıdır.
- Çeviri sürerken şu anahtarlardan biri değişince TV'ye hemen yeni görünüm gider: `subtitleScale`, `textColor`,
  `subtitleFont`, `tvFontSize`, `tvBackground`, `tvBackgroundShape`, `stackPrevious`, `tvDisplayMode`, `tvPlacement`,
  `tvBottomPercent`, `tvAutoSize`, `tvWatermark`.

### 5.5 Çeviri sürerken anında etki eden diğer değişiklikler

- `region` ya da `extraAreas` değişince yeni bölge hemen okunmaya başlanır.
- `target` değişince altyazı hemen yeni hedefe (TV/telefon) yönlendirilir.
- `sharePool` kapatılınca: `pool/` içindeki bekleyen kuyruk (`pending.jsonl`, `outbox/`, `parked/`) **silinir**, çeviri
  havuzu kapanır (bellekteki çeviriler önce `translations-<dil>.json`'a yazılır). Açılınca yeniden başlar.
- Hazır bölge seçilince (`BOTTOM`/`TOP`/`FULL`) hem `region` hem `areaPreset` yazılır; elle bölge çizilince `region`
  ve `areaPreset` = `CUSTOM` yazılır. `CUSTOM` seçilince kayıtlı bölge korunur.

### 5.6 Ölçüm

- Firebase istatistik ve çökme raporu = `usageData`.
- Meta olayları = `usageData` **ve** `welcomeSeen` (karşılama geçilmeden Meta olayı gönderilmez).
- Açılışta ve `usageData` değişince yeniden uygulanır.

### 5.7 Motor ve anahtar

- `engine` = `FREE` dışındaysa `secrets/key.<MOTOR>` gerekir; yoksa ücretsiz motora düşülür.
- Anahtar ancak sağlayıcıda denenip kabul edilince yazılır. "Kaldır" anahtarı siler.
- Yapay zekâ motorlarında model `aiModel`'den, yoksa listenin ilkinden seçilir; önbellek dosyası motor+model'e özeldir.

### 5.8 Açılışta yapılan durum işleri

- `translating` okunur ve false yapılır; önceki kapanış çeviri sırasında olduysa raporlamada belirtilir.
  `lastExitReportAt`'tan yeni süreç çıkış kayıtları raporlanır ve bu değer güncellenir.
- Paket deposu hemen, sonra uygulama açık kaldıkça günde bir yenilenir; PS5'te yeni oyun tanınınca son bakış 10
  dakikadan eskiyse yine bakılır.
- Telefon uygulaması güncellemesine uygulama her öne geldiğinde bakılır (ağa en çok 3 saatte bir).
- `health/otomatik-bildirim.json`'daki gönderilemeyen bildirim yeniden denenir.

---

## Belirsizlikler

1. **`aiModel`**: okunuyor ama arayüzde yazan bir yer bulunmadı. Eski kayıtlarda var olabilir; yeni uygulama okuyup
   modeli seçtirmeli mi, karar verilmeli.
2. **`phoneTextSize`** ve **`tvFontSize`**: güncel arayüzde yazan yer yok. `tvFontSize` hâlâ TV boyunu hesaplamada ve
   `tvAutoSize` türetmesinde kullanılıyor; `phoneTextSize` hiç kullanılmıyor görünüyor.
3. **`packsEnabled`**, **`notify.disconnect`**, **`notify.packs`**: arayüzde açılıp kapanıyor ama çeviri hizmetinde
   bunlara bakan bir yer bulunmadı (paketler kapalıyken de kullanılıyor olabilir, bildirim tercihleri uygulanmıyor
   olabilir). Yeni uygulamada anlamları netleştirilmeli.
4. **`platform`**: değeri hiç okunmuyor, yalnız varlığı önemli. Eski bir sürümde `XBOX` yazılmış ama `videoSource`
   `XBOX` olmayan bir kurulum PlayStation sayılır.
5. **Android 12 ve altı arayüz dili**: anahtar yoksa telefon dilinden türetilen değer kullanılıyor, ama ayarın
   kendisi `onboarded` kuralıyla (eski kurulum → `tr`) farklı değer üretebilir; ilk açılışta çok kısa bir an iki
   değer ayrışabilir. Ayar ilk okunduğunda yazıldığı için sonraki açılışlarda tutarlıdır.
6. **Keystore silme**: `secrets`'i ve iki takma adı birden silen işlem kodda var ama arayüzden çağıran bir yer
   bulunmadı (ör. "çıkış yap" ya da "sıfırla" yok gibi). PSN hesabı/PS5 kaydı tek tek silinmiyor olabilir.
7. **`lastGame.<konsol adı>`**: anahtar konsolun görünen adına bağlı; PS5 adı değişirse eski kayıt öksüz kalır.
   Yakalama kartında konsol adı bilinmediği için bu kayıt hiç yazılmıyor olabilir.
8. **`phone-memory-<dil>.json`** içindeki anahtarın tam biçimi (normalleştirilmiş mesaj metni mi, başka bir anahtar mı)
   ve "boşaltma" eşiği ayrıntılı incelenmedi; dosya düz anahtar→çeviri nesnesidir.
9. **`translation-pool/translations-<dil>.json`** içindeki `texts` anahtarlarının biçimi (sunucunun verdiği
   normalleştirilmiş satır mı) ayrıntılı incelenmedi.
10. **`subtitle-layout.json`** oyun anahtarı paket kimliğinden geliyor; paket kimlikleri değişirse öğrenilen yer
    kaybolur.
11. **Xbox jetonu**: `xboxUserToken` içinde Microsoft yanıtından gelen ek alanların tam listesi sağlayıcıya bağlı;
    yeni uygulama yalnız `access_token`, `refresh_token`, `expires_on`'a güvenmeli.
12. Uygulamayla gelen dosyalar (assets: `packs/`, `glossary-en-tr.json`, `ai-models.json`, `tv/…`) kullanıcı verisi
    değildir; burada yalnız adları geçtiği yerlerde anıldı. **Yeni uygulamada:** paketler gömülmez, havuzdan iner
    (`files/packs-remote/`, ceviri.md §10); sözlük ve model listesi Nino'nun kendi dosyalarıdır.
