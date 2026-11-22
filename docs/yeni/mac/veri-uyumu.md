# Veri uyumu: eski Mac uygulamasının verisi

Amaç: yeni Mac uygulaması, kullanıcının bugünkü Nino kurulumundaki hiçbir veriyi kaybetmeden açılsın.
Bu belge eski uygulamanın **nereye, hangi biçimde** yazdığını anlatır. Kod yok; yalnız adlar, biçimler, değerler.

Kaynak: eski Mac uygulaması, eski çekirdek, eski Remote Play katmanı, TV sayfası
ve kullanıcının gerçek verisi (22 Kasım 2026, yalnız okundu).

Genel kural: **okurken hoşgörülü ol, yazarken eski biçimi bozma.** Eski uygulama her alanı "varsa oku, yoksa
varsayılan" diye okur; bilinmeyen alanı yok sayar. Yeni uygulama da öyle yapmalı.

---

## 1. UserDefaults (alan adı `com.ninotranslator.mac`)

### 1.1 Anahtar listesi

| Anahtar | Tip | Ne tutar | Not |
|---|---|---|---|
| `settings` | Data (UTF-8 JSON) | Bütün kullanıcı ayarları (bkz. 1.2) | Her ayar değişikliğinde baştan yazılır |
| `ninoAdminMode` | Bool | Geliştiricinin "debug admin modu" | Yalnız elle açılır (`defaults write … -bool true`). Açıkken: çeviri her açılışta kendiliğinden başlar, debug kareleri kaydedilir, telefonun adım adım kaydı tutulur. Geliştirici derlemesinde hep açık sayılır |
| `ninoLastGamePoolFirst` | Bool | Son oynanan oyun "havuz öncelikli" miydi (bugün GTA 6) | Oyun henüz tanınmadan açılışta havuz çevirisinin kullanılıp kullanılmayacağına karar verir |
| `NinoCaptureCardID` | String | Seçilen HDMI yakalama kartının aygıt kimliği | Yoksa ilk uygun kart |
| `streamBackground` | String | "Yayın penceresi"nin zemin rengi | `green` (varsayılan), `black`, `magenta`. Bilinmeyen değer → `green` |
| `ninoResumeAfterRelaunch` | Double (Unix saniye) | "Kendimi yeniden açıyorum, çeviriyi sürdür" işareti | Takılma ya da güncelleme yeniden açılışında yazılır; açılışta okunup **hemen silinir**. 120 sn'den eskiyse yok sayılır |
| `ninoDownloadTotal` | Integer | Ana ekrandaki "toplam indirme" sayısının son bilinen değeri | Sunucudan (`/v1/config`) gelen değer daha büyükse güncellenir; sunucuya ulaşılamazsa bu gösterilir |
| `lastGames` | Dictionary [String: String] | PS5 adı → o PS5'te elle seçilen son oyunun adı | Ana ekrandaki oynanan oyun kartında kullanıcı seçince yazılır |
| `devSessionRenewed.<tv adresi>` | Date (plist tarihi) | LG geliştirici modu süresinin bu TV için son uzatıldığı an | **Anahtarlıkta değil, burada.** Adres küçük harf ve kırpılmış. 20 saatten eskiyse süre yeniden uzatılır |
| `AppleLanguages` | [String] | Arayüz dili | Çeviri dili değişince arayüz dili de ona çekilir (ör. `["ar"]`). Sistem anahtarı; yeni uygulama da aynı davranışı sürdürmeli |
| `NinoFreeNav` | Bool | Tasarım denemesi: kurulum adımları beklemeden gezilir | **Yalnız geliştirici derlemesinde** okunur; yayın sürümü yok sayar |
| `NinoPreviewStep` | Integer | Tasarım denemesi: açılışta doğrudan bu kurulum adımı (1'den başlar; 7 = ana ekran) | Yalnız geliştirici derlemesi |
| `NinoGameWindowApp` | String | Oyun penceresi olarak başka bir uygulamayı hedefle (deneme) | Yalnız geliştirici derlemesi |
| `NinoGameWindowTopInset` | Double | Oyun penceresinin başlık çubuğu yüksekliği (nokta, varsayılan 28) | Her derlemede okunur |
| `ninoPoolURL` | String (URL) | Havuz sunucusu adresini değiştirir | Ortam değişkeni `NINO_POOL_URL` daha önce gelir; ikisi de yoksa yerleşik adres |
| `poolURL` | String (URL) | Eski satır havuzu adresi | Eski ortak havuz kodu; ortam değişkeni `NINO_LINEPOOL_URL` önce gelir |
| `packsURL` | String (URL) | Oyun paketi sunucusu adresi | Sıra: ortam `NINO_PACKS_URL` → bu anahtar → uygulama bilgisindeki `CSPacksBaseURL`. Hiçbiri yoksa paket güncelleme kapalı |
| `SUHasLaunchedBefore`, `SULastCheckTime`, `SUUpdateGroupIdentifier`, `SUAutomaticallyUpdate` … | çeşitli | Sparkle güncelleyicisinin kendi kayıtları | Yeni uygulama da Sparkle kullanacağı için olduğu gibi kalır |
| `NSWindow Frame …`, `NSStatusItem …` | String/Bool | macOS'un pencere konumu kayıtları | Anahtar adı pencere türüne bağlı; yeni uygulamada farklı olur, sorun değil |

Kullanıcının gerçek kaydında şu an var olanlar: `settings`, `ninoAdminMode` (açık), `ninoDownloadTotal`,
`ninoLastGamePoolFirst` (açık), Sparkle ve pencere anahtarları.

### 1.2 `settings` blobu: tüm alanlar

JSON nesnesi. Her alan isteğe bağlı; eksikse varsayılan kullanılır, tip yanlışsa (enum dizgesi tanınmazsa)
o alan varsayılana düşer, **blobun geri kalanı yine okunur**.

| Alan | Tip | Olası değerler | Varsayılan | Anlam |
|---|---|---|---|---|
| `region` | nesne (bkz. Bölge) | | üst 0.62, alt 0.97, sol 0.14, sağ 0.86 | Altyazının okunduğu bölge |
| `areaPreset` | dizge | `bottom`, `top`, `full`, `custom` | Yoksa bölgeden çıkarılır (hazır seçimle 0.001 payla aynıysa o, değilse `custom`) | Bölgenin hazır seçimi |
| `extraAreas` | dizi (bkz. Ek alan) | en çok 3 öğe | `[]` | Sürekli okunan ek alanlar |
| `style` | nesne (bkz. Stil) | | | TV'deki altyazı görünümü |
| `sourceLanguage` | dizge | `en` (pratikte), başka kod olabilir | `en` | Oyunun dili |
| `targetLanguage` | dizge | `tr`, `ar`, `hi`, `id`, `th`, `vi`, `ur`, `bn`, `ms`, `tl`, `nl` | İlk açılışta sistem dili listedeyse o, değilse `tr` | Çeviri dili. Filipince `tl` koduyla tutulur (arayüzde `fil`). `ar` ve `ur` sağdan sola |
| `onlineTranslation` | Bool | | `false` | Açıksa `onlineEngine` kullanılır |
| `onlineEngine` | dizge | `deepl`, `gemini`, `openai`, `claude`, `local` (ayrıca `free` görülebilir) | `deepl` | Seçili çevrimiçi motor. `free` okunursa `deepl` yapılır |
| `geminiModel` | dizge | listedeki kimlikler (`gemini-3.5-flash-lite`, `gemini-3.6-flash`) | listenin ilki | |
| `openAIModel` | dizge | `gpt-6-luna`, `gpt-6.1-terra` | listenin ilki | |
| `claudeModel` | dizge | `claude-haiku-5-5`, `claude-sonnet-5-5` | listenin ilki | |
| `localAIBaseURL` | dizge (URL) | Ollama `http://localhost:11434/v1`, LM Studio `http://localhost:1234/v1` | Ollama adresi | Yerel model sunucusu |
| `localAIModel` | dizge | serbest (kullanıcı yazar) | `translategemma:4b` | Eski varsayılan `qwen2.5:7b` okunursa yeni varsayılana çevrilir |
| `output` | dizge | `tv`, `computer`, `both` | `tv` | Altyazı nerede. `both` okunursa `tv` yapılır. `computer` = "TV'm yok" |
| `overlayClickThrough` | Bool | | `false` | Bilgisayardaki altyazı penceresi tıklamayı alttaki pencereye geçirir |
| `videoSource` | dizge | `ps5`, `window`, `card` | `ps5` | Görüntünün kaynağı: PS5'e doğrudan bağlantı / Mac'te çalışan Remote Play penceresi / HDMI yakalama kartı |
| `gameConsole` | dizge | `ps5`, `xbox` | `ps5` | |
| `gamePacks` | Bool | | `true` | Oyun paketleri kullanılsın |
| `sharePool` | Bool | | `true` | Ortak havuza satır gönder ve havuz çevirilerini kullan |
| `autoReport` | Bool | | `true` | Kopma gibi sorunlar kendiliğinden bildirilsin |
| `translateCorners` | Bool | | `true` | Sol üstteki ipucu/görev kutusu da çevrilsin |
| `askGame` | Bool | | `true` | Oyun tanınmazsa iki dakika sonra sor |
| `showSpeakerNames` | Bool | | `true` | Konuşan adı ("ARTHUR: …") çeviride kalsın |
| `fastSubtitleDetection` | Bool | | `false` | Değişmeyen bölgeyi en çok iki kare yeniden kullan |
| `xboxAudioOnDevice` | Bool | | `true` | Xbox ev yayınında ses cihazda çalsın (yalnız telefon) |
| `appearance` | dizge | `dark`, `light`, `system` | `system` | |
| `homeStyle` | dizge | `livingRoom`, `toggle` | `livingRoom` | Ana ekran arayüzü: salon sahnesi ya da cam anahtar |
| `frameSource` | dizge | `ps5`, `remotePlayWindow` | `ps5` | Eski sürümden kalan; asıl kaynak `videoSource`. Saklanmalı; `remotePlayWindow` ise kurulum PS5 eşleşmesi olmadan "bitti" sayılır |
| `remotePlayApp` | dizge | `automatic`, `sony`, `chiaki` | `automatic` | Pencereden okurken hangi Remote Play istemcisi |
| `dubbing` | nesne | bkz. aşağıda | | **Kaldırılmış özellik.** Eski bloblarda durur; okunurken yok sayılır, blob yeniden yazılınca düşer |

**Bölge** (`region` ve ek alanların `region`'u): `{"top", "bottom", "left", "right"}`, hepsi 0–1 arası ondalık,
karenin üstünden ve solundan oran. Hazır seçimler:

| Seçim | üst | alt | sol | sağ |
|---|---|---|---|---|
| `bottom` | 0.62 | 0.97 | 0.14 | 0.86 |
| `top` | 0.03 | 0.38 | 0.14 | 0.86 |
| `full` | 0 | 1 | 0 | 1 |

En küçük yükseklik/genişlik 0.05.

**Ek alan** (`extraAreas` öğesi): `{"id": dizge, "name": dizge, "region": Bölge, "enabled": Bool}`.
- `id` TV'deki kutunun kimliği (UUID dizgesi); yoksa yenisi üretilir. Değişmemeli: TV kutuyu bununla tanır.
- `name` kullanıcının verdiği ad ("Görev", "Telefon"); yoksa boş.
- `region` yoksa "görev" hazır bölgesi.
- `enabled` yoksa `true`. Kapalı alan okunmaz ama silinmez.
- Hazır bölgeler: görev (0.03, 0.30, 0.66, 0.98), bildirim (0.58, 0.88, 0.02, 0.30), telefon (0.50, 0.95, 0.72, 0.98)
  (üst, alt, sol, sağ sırasıyla).
- Dizide 3'ten fazlası varsa ilk 3'ü alınır.

**Stil** (`style`):

| Alan | Tip | Değerler | Varsayılan |
|---|---|---|---|
| `fontSize` | tam sayı | Arayüz 36/46/58/72 sunar ama **her tam sayı kabul edilir** (kullanıcıda 30) | 46 |
| `bottomPercent` | tam sayı | Sabit yerleşimde alttan uzaklık, % | 7 |
| `placement` | dizge | `cover` (İngilizcenin üstünü örter), `above`, `below`, `fixed` | `cover` |
| `background` | tam sayı | 0–100 zemin koyuluğu | 100 |
| `backgroundShape` | dizge | `fit`, `band` | `fit` |
| `bold` | Bool | | `false` |
| `textColor` | dizge | `white`, `yellow` | `white` |
| `displayMode` | dizge | `inApp`, `overlay` (yalnız Android TV kullanır) | `inApp` |
| `stackPrevious` | Bool | Önceki satır kısa süre soluk kalsın | `true` |
| `theme` | dizge | `classic`, `cinema`, `minimal`, `glass`, `contrast`, `outline` | `classic` |
| `autoSize` | Bool | Yazı boyu oyunun altyazısına göre | `true` |
| `font` | dizge | `system`, `modern`, `condensed`, `rounded` | `condensed` |
| `watermark` | Bool | TV'de sol alttaki Nino rozeti | `true` |

Okuma kuralı: `placement` = `cover` ve `background` < 60 ise `background` 100 yapılır.
Tema seçilince renk/kalınlık/zemin şöyle ayarlanır (boyut ve yer kullanıcıda kalır):
classic beyaz/ince/100, cinema sarı/kalın/0, minimal beyaz/ince/0, glass beyaz/ince/62, contrast beyaz/kalın/100,
outline beyaz/kalın/0.

**Dublaj** (eski bloblarda; yalnız tanımak için): `{"enabled": Bool, "output": "tv"|"computer",
"cast": {"narrator": ses, "partner": ses, "assignments": {ad: ses}}}`. Ses değerleri `female_1..3`, `male_1..3`.
Kullanıcının blobunda kapalı.

### 1.3 Okurken yapılan düzeltmeler (eski uygulama böyle yapıyor; yeni de yapmalı)

1. Blob hiç yoksa: varsayılanlar + çeviri dili sistem diline göre (listede yoksa `tr`).
2. `output: both` → `tv`.
3. `onlineEngine: free` → `deepl`.
4. `localAIModel: qwen2.5:7b` → `translategemma:4b`.
5. Model kimliği listede yoksa o sağlayıcının varsayılanına döner; bir şey değiştiyse blob hemen geri yazılır.
6. `extraAreas` en çok 3.
7. `cover` + zemin < 60 → zemin 100.
8. Bilinmeyen alanlar (`dubbing` gibi) yok sayılır. Eski uygulama yeniden yazınca bunlar düşer; yeni uygulama
   istersen saklayabilir ama gerek yok.

Kullanıcının gerçek blobunda dikkat: `autoReport` ve `style.watermark` **yok** (varsayılan alınır), `fontSize` 30,
`areaPreset` `custom`, `extraAreas` boş, `onlineTranslation` kapalı ama `onlineEngine` `local`.

### 1.4 Yazma kuralı

- Ayar her değiştiğinde bütün nesne JSON olarak yeniden kodlanıp `settings` anahtarına Data olarak yazılır.
- Hemen ardından TV'ye güncel `style` gönderilir.
- Eski uygulama da yeni uygulama da aynı anahtara yazacaksa (aynı paket kimliği), yeni uygulama eski alanları
  **adıyla ve değer dizgeleriyle** korumalı; yoksa kullanıcı eski sürüme dönünce ayarlarını kaybeder.

---

## 2. Anahtarlık (Keychain)

Tür: genel parola (generic password). **Hizmet adı: `com.ninotranslator.mac`** (Mac'in hizmet adı hiç değişmedi;
eski adlardan taşıma yalnız iPhone/iPad'de var). iPhone/iPad: `com.ninotranslator.ios`.

**Değer biçimi:** her kayıt, değerin **JSON kodlanmış hali**dir. Yani:
- dizge → tırnaklı JSON dizgesi (`"abc"`, tırnaklar dahil),
- Bool → çıplak `true` / `false`,
- bayt dizisi (Data) → tırnaklı base64 dizgesi,
- nesne → JSON nesnesi; içindeki bayt alanları base64 dizgesi.

Yazarken önce aynı hesap silinir, sonra eklenir (erişim özelliği verilmez; macOS varsayılanı).

| Hesap (account) | Değer | Yazılma anı |
|---|---|---|
| `accountId` | Data, 8 bayt → base64 dizgesi | PSN girişi bitince (ikinci PSN hesabının kimliği) |
| `console` | PS5 kaydı nesnesi (aşağıda) | PS5 eşleşmesi bitince; PS5 adresi değişince yeni adresle yeniden |
| `tv` | TV nesnesi (aşağıda) | TV eşleşince; TV adresi değişince |
| `tvKey` | dizge | LG: SSAP istemci anahtarı. Samsung: uzaktan kumanda jetonu. Android TV: boş olabilir. **Boş yeni jeton eskisinin üstüne yazılmaz** |
| `tvDevKey` | dizge | LG geliştirici modu oturum anahtarı (TV'ye uygulama kurmak için) |
| `tvAppVersion` | dizge | Samsung ve Android TV'ye kurulan TV uygulamasının sürümü (LG'de sürüm TV'den okunur). TV markası ya da adresi değişince silinir |
| `loginPasscode` | dizge, 4 hane | PS5'te ikinci hesaba girerken sorulan şifre (isteğe bağlı) |
| `setupComplete` | Bool | Kurulum sihirbazı bitti |
| `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey` | dizge | Kullanıcının kendi çeviri anahtarları |
| `localAIKey` | dizge | Yerel model sunucusunun isteğe bağlı anahtarı |

**PS5 kaydı** (`console`):
`{"host": dizge, "name": dizge, "registKey": base64, "morning": base64}`
- `host`: PS5'in IP adresi (0.0.0.0 ya da yayın adresi asla saklanmaz).
- `name`: PS5'in ağdaki adı.
- `registKey`: 16 bayt. İçeriği ASCII onaltılık rakamlar, sonu sıfır baytla doldurulmuş. Uyandırma kimliği bu
  onaltılık metnin sayı değeridir.
- `morning`: 16 baytlık oturum anahtarı.
- **Yok:** PS5'in ana bilgisayar kimliği (host id), MAC adresi, hedef sürüm. Eski uygulama hedefi PS5 kabul eder.

**TV** (`tv`): `{"name": dizge, "host": dizge, "brand": "lg"|"samsung"|"androidTV"}`.
`brand` yoksa `lg` sayılır (eski kayıtlar).

**Hesap kimliği** (`accountId`): 8 baytlık PSN hesap kimliği, base64.

**Sıfırlama davranışı:**
- "Her şeyi sıfırla": `accountId`, `console`, `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete`,
  `loginPasscode` silinir (çeviri anahtarları kalır).
- "TV'yi değiştir": `tv`, `tvKey`, `tvDevKey`, `tvAppVersion`, `setupComplete` silinir.
- PSN'den çıkış: yalnız `accountId`.

Kullanıcının Anahtarlığında bugün `com.ninotranslator.mac` altında `accountId`, `console`, `setupComplete`, `tv`,
`tvAppVersion`, `tvKey` var; çeviri anahtarı yok. Ayrıca `com.ninotranslator.mac.fresh` hizmetinde bir
`setupComplete` kaydı var: depoda bu adı yazan kod bulunamadı (kaynağı bilinmiyor; muhtemelen eski bir deneme
kopyası). Yeni uygulama bunu okumamalı.

**Erişim uyarısı:** Anahtarlık kaydı, onu oluşturan uygulamanın imzasına bağlıdır. Yeni uygulama aynı paket
kimliği (`com.ninotranslator.mac`) ve aynı geliştirici imzasıyla (aynı takım) imzalanmazsa macOS her kayıt için
parola sorar ya da okuma başarısız olur. Yeni uygulamanın geliştirici derlemesi (`.dev` kimliği, `.dev` hizmeti)
gerçek kayıtları zaten görmez.

---

## 3. Veri klasörü: `~/Library/Application Support/Nino`

(Mac App Store sürümünde aynı yol uygulamanın kabının içinde.)

| Yol | Biçim | Kim yazar / ne için |
|---|---|---|
| `history.json` | `{"version": 1, "entries": [...]}`; öğe: `{"id": tam sayı, "date": ISO-8601 dizge, "source": İngilizce, "translation": çeviri, "origin": "pack"\|"engine"}` | Çeviri geçmişi. En yeni başta, en çok 200 satır, metin başına en çok 500 karakter. Benzer kaynak art arda gelirse yeni kayıt açılmaz, ilki güncellenir. Anahtar sırası sabit değil (`version` sonda olabilir) |
| `subtitle-layout.json` | `{"samples": {"<oyun kimliği>": [{"top": 0–1, "bottom": 0–1}, ...]}}` | **Öğrenilmiş altyazı yeri.** Oyun başına en çok 60 kutu; 8 örnekten sonra o oyunun altyazı şeridi bilinir. Oyun tanınmazken anahtar `genel`. Kaybolursa okuma kalitesi düşer; mutlaka korunmalı |
| `phone-memory-<dil>.json` | Düz nesne: `{ "<sadeleştirilmiş İngilizce mesaj>": "<çeviri>" }` | Telefon (GTA 6) mesajlarının çevirileri; Nino yeniden açılınca telefon baştan çevrilmesin. Dil başına ayrı dosya (`phone-memory-tr.json`). Anahtar küçük harfli, noktalaması atılmış metin |
| `sorunlar.json` | Dizi; öğe: `{"id": UUID, "date": ISO-8601, "kind": "ps5Dropped"\|"ps5Unreachable"\|"networkLost"\|"tvDropped", "reason": dizge?, "streamedMinutes": ondalık?, "lossPerMinute"?, "stallsPerMinute"?, "network": dizge ("wifi", "ethernet", "offline"…), "game": dizge?}` | Sorun geçmişi (Sistem sağlığı ekranı). En çok 40 kayıt |
| `otomatik-bildirim.json` | `{"day": "yyyy-mm-dd", "sent": sayı, "pending": bildirim gövdesi?}` | Otomatik sorun bildirimi sayacı: günde en çok 3; gönderilemeyen bekler |
| `pool/` | klasör | Ortak havuz istemcisi (bkz. 3.1) |
| `pool.json` → `pool.json.imported` | `{"install", "queue": [{"text", "firstSeen"?, "titleId"?, "game"?}], "sent": ["<16 hex anahtar>", ...], "retryAfter"?}` | Eski satır havuzunun kuyruğu. Bir kez `pool/` kuyruğuna aktarılır, sonra `.imported` adıyla kenara konur. Yeni uygulama dokunmasın |
| `Translations/` | klasör | Çeviri önbellekleri ve havuz çevirileri (bkz. 3.2) |
| `packs/` | `*.json.gz` ya da `*.json` | Sunucudan inen ve kullanıcının bıraktığı oyun paketleri (bkz. 3.3). Kullanıcıda şu an yok |
| `packs-remote.json` | `{"checked": Unix saniye, "packs": [{"id", "title", "version": tam sayı (-1 = inemedi), "sha256"}]}` | Paket güncelleyicinin durumu. Kullanıcıda yok (paket sunucusu yapılandırılmamış) |
| `Glossary/` | `*.json`, ad sırasıyla okunur | Kullanıcının terim sözlükleri (bkz. 3.4). Kullanıcıda yok |
| `Covers/` | `<oyun kimliği>.png` (jpg, jpeg, heic, webp de) | Salon sahnesinde oyuna özel arka plan görseli. GTA 6 için `gta-6` adı da aranır. Kullanıcıda boş |
| `adb/adbkey` | ADB özel anahtarı | Android TV'ye kurulum yapan gömülü yardımcının anahtarı. TV bu anahtarı "yetkili" olarak hatırlıyor; **silinirse TV yeniden izin sorar** |
| `samsung/` | yardımcının dosyaları | Samsung TV'ye kurulum yapan yardımcının sertifika/profil klasörü. Kullanıcıda yok |
| `dubbing/` | ses modeli önbelleği | Kaldırılmış dublajdan kalan. Yeni uygulama yok saysın (silmesin; kullanıcı kararı) |
| `kopyalandi.txt` | düz metin | "Bu klasörün verisi eski klasörden kopyalandı" notu (bkz. 3.5) |

### 3.1 `pool/` (ortak havuz)

| Dosya | Biçim |
|---|---|
| `state.json` | `{"install": UUID (küçük harf), "frozenThrough": sıra no, "failures": sayı, "nextAttempt": Unix sn, "serverRetryAt": Unix sn, "app": "uygulama sürümü", "dropped": sayı}`. Okunamazsa `state.broken-<unix>.json` adıyla kenara alınır |
| `pending.jsonl` | Her satır bir görülme: `{"s": sıra no, "t": metin, "g": oyun kimliği?, "e": kaynak etiketi?, "a": Unix sn}` |
| `outbox/*.json` | Gönderilmeyi bekleyen parça: `{"v": 1, "batch": UUID, "install", "app", "platform": "mac", "lines": [{"text", "game"?, "session"?, "count", "first", "last"}], "upTo": sıra no}`. Ad sırasıyla gönderilir |
| `parked/*.json` | Sunucunun kabul etmediği parçalar; uygulama sürümü değişince `outbox/`'a geri alınır |
| `rejected.jsonl` | Reddedilen satırlar: `{"reason", "text"}` |

`install` kimliği kuruluma özgüdür, sunucuda hız sınırı için kullanılır. Yeni uygulama **aynı kimliği sürdürmeli**.

### 3.2 `Translations/` (çeviri önbelleği ve havuz çevirileri)

Dikkat: kod bu klasörü iki ayrı yazımla açıyor: önbellek `Translations`, havuz çevirileri `translations`.
macOS diski büyük/küçük harf ayırmadığı için **ikisi aynı klasördür** ve dosyalar karışık durur. Büyük/küçük harf
ayıran bir diskte (nadir) iki ayrı klasör olur. Yeni uygulama iki yazımı da aramalı.

| Dosya | Biçim |
|---|---|
| `v1-<motor>-<kaynak>-<hedef>.jsonl` | Çeviri önbelleği. Her satır iki öğeli JSON dizisi: `["kaynak metin", "çeviri"]`. Sona eklenir; aynı kaynak birden çok kez geçebilir, **sonuncusu geçerli**. Bellekte en çok 20 000 kayıt, dosya 40 000 satırı geçince bellektekilerle yeniden yazılır |
| `v1h-<sha256>.jsonl` | Aynısı; motor adında küçük harf/rakam/tire dışı karakter varsa ad, `motor \0 kaynak \0 hedef` metninin SHA-256'sı olur |
| `translations-<dil>.json` | Havuzdan inen çeviriler: `{"language": "tr", "texts": {"<16 hex anahtar>": "çeviri"}, "cursors": {"<oyun kimliği ya da boş>": {"since": ms, "after": dizge, "checked": Unix sn}}}`. Kullanıcıda ~250 000 satır, ~17 MB |
| `install` | Tek satır UUID: havuz çevirisi istemcisinin kurulum kimliği |

Motor adları (dosya adındaki `<motor>`):
- `apple-p3`: cihaz üstü çeviri; `p` sonrası sayı ücretsiz çeviri kurallarının sürümü. Kurallar değişince sayı artar
  ve eski dosya kullanılmaz olur (dosya yine durur; `apple-p2` gibi eskileri kullanıcıda var).
- `deepl`.
- `gemini_<model>`, `local_<sunucu>_<model>` gibi: yapay zekâ motorları; noktalama `_` olur.

Önbellek anahtarı (satırın ilk öğesi): cümlenin kendisi; kısa satır önceki cümleyle birlikte çevrildiyse
`bağlam \u001F cümle`, sözlük terimi içeriyorsa başına sözlüğün izi + `\u001F` eklenir.

**Havuz/paket anahtarı (16 hex):** İngilizce satır şöyle sadeleştirilir: `<…>` biçim etiketleri (en çok 40 karakter)
boşluk olur → uyumluluk ayrıştırması (NFKC) → küçük harf → kanonik ayrıştırma (NFD) ve tüm aksan işaretleri atılır →
harf ve rakam dışındaki her şey boşluk → boşluklar teklenir, kırpılır. Sonucun UTF-8 SHA-256 özetinin **ilk 8 baytı**,
küçük harf onaltılık (16 karakter). Harf/rakam yoksa anahtar yok. Aynı anahtar paketlerde, havuz sunucusunda,
Windows ve Android'de de kullanılır.

### 3.3 Oyun paketleri (eski biçim)

- Dosya gzip'li ya da düz JSON: `{"format": 1|2, "id": "<oyun kimliği>", "title": "<ad>", "entries": {"<anahtar>": "çeviri"}}`.
  Biçim 2'de ayrıca `segments` (aynı düzen; çok cümleli satırların parçaları) ve `fuzzy` (bulanık eşleme imzaları).
- Yalnız `{anahtar: çeviri}` nesnesi de kabul edilir; o zaman kimlik ve ad dosya adından (`mafia.json.gz` → `mafia`).
- **Paketlerde İngilizce metin yok**, yalnız 3.2'deki 16 hex anahtar.
- Sıra: uygulamayla gelen paketler (`Resources/packs`, 9 oyun) → `packs/` (inenler, aynı kimlikte yerleşiğin yerine
  geçer) → içe aktarılan topluluk paketleri (Mac'te kullanılmıyor). Sonra okunan kazanır.
- Paket güncelleyici kullanıcının elle bıraktığı (durum dosyasında olmayan ya da sonradan değişmiş) dosyaya dokunmaz.

### 3.4 Terim sözlüğü

`{"game": "<ad>", "terms": {"İngilizce": "Türkçe"}, "keep": ["Ad"], "keepExact": ["Ad"], "phrases": {"düzenli ifade": "düz İngilizce"}, "lines": {"Taking fire!": "Ateş altındayım!"}}`.
Uygulamayla gelen genel sözlüğün üstüne kullanıcı dosyaları ad sırasıyla eklenir; aynı terimde sonraki kazanır.

### 3.5 Eski klasörden taşıma kuralları

Eski sürümler başka bir klasör adı kullanıyordu (adı `LegacyNames` dosyasında kodlu). Açılışta, **hiçbir dosya
açılmadan önce** bir kez karar verilir:

1. Yeni klasör (`Nino`) varsa ve içinde `.DS_Store` dışında bir şey varsa o kullanılır; eski klasöre dokunulmaz,
   birleştirilmez.
2. Yeni klasör boşsa yok sayılır (taşımadan önce silinir).
3. İkisi de yoksa yenisi oluşturulur.
4. Yalnız eski klasör varsa:
   - Eski uygulama bu Mac'te kuruluysa ya da açıksa (paket kimliğiyle ve olağan kurulum yerlerinde aranır; ikisi de
     `LegacyNames`'te kodlu): eski klasör **taşınmaz, kopyalanır.** Önce yanında `Nino.kopya-<UUID>` geçici
     klasörüne kopyalanır, bitince tek adımda `Nino` yapılır, içine `kopyalandi.txt` notu bırakılır. Tek dosya
     kopyalanamazsa geçici klasör silinir, bu açılışta eski klasör kullanılır. Yarıda kalmış eski geçici klasörler
     silinir.
   - Değilse: eski klasör tek bir yeniden adlandırmayla `Nino` olur.
   - Nino'nun başka bir kopyası açıksa hiçbir şey yapılmaz, bu açılışta eski klasör kullanılır, iş sonraki açılışa kalır.
   - Taşıma başarısızsa eski klasör kullanılır ve yeni klasör oluşturulmaz (yoksa sonraki açılış boş klasörü seçerdi).
5. Günlük klasörü de aynı kurallarla taşınır, ama eski uygulamayla ortaksa **kopyalanmaz**, yeni günlük klasörü boş açılır.
6. Testlerde ve App Store sürümünde (eski uygulama kabın içine erişemez) taşıma/kopya yapılmaz.
7. Ne olduysa (taşındı, kopyalandı, hata) açılışta `remoteplay.log`'a yazılır.

Kullanıcının klasörü kopyalanmış (not dosyası var). Yeni uygulama aynı klasörü (`Nino`) kullanacaksa bu adımı
yeniden yapmasına gerek yok; ama hiç Nino klasörü olmayan eski kullanıcılar için kural gerekli.

---

## 4. Günlükler: `~/Library/Logs/Nino`

| Dosya | Ne |
|---|---|
| `altyazi.log` (+ `altyazi.log.1`) | Okunan satırlar ve akıbetleri, görüntü duraklamaları, olaylar. 1 MB'ı geçince `.1`'e döner |
| `remoteplay.log` | PS5 bağlantısı, eşleşme, Remote Play kütüphanesinin satırları, açılış notları. 1 MB sınırı |
| `tvinstall.log` | TV uygulaması kurulumunun adımları |
| `takilma-<ISO tarih, ":" yerine "-">.txt` | Okuma takılınca alınan 2 sn'lik süreç örneği; son 5 dosya tutulur |
| `frames/f-<ISO tarih>.jpg` | Admin modunda 2 sn'de bir PS5 karesi + okuma bölgesi + son kutu + son çeviri |
| `frames/video/` | Bu klasörde `KAYIT` dosyası varsa saniyede 10 ham kare `v-<ms>.jpg`, ses `ses.f32` (48 kHz, 2 kanal float), başlangıç anı `ses-baslangic.txt` |

Sorun bildirirken `remoteplay.log`, `altyazi.log`, `tvinstall.log` sonları eklenir.

---

## 5. Eski TV bağlantısı (8787, SSE)

### 5.1 Roller ve bulma

- **Mac sunucudur, TV istemcidir.** Mac TCP **8787**'de düz HTTP dinler (TLS yok). Port doluysa birkaç kez
  yeniden dener (önceki süreç portu geç bırakabiliyor), olmazsa rastgele port. TV yalnız 8787'yi taradığı için
  rastgele port pratikte TV'ye ulaşmaz.
- TCP canlılık denetimi açık (10 sn boşta, 5 sn arayla, 3 deneme); Nagle kapalı.
- LG ve Samsung'da Mac, TV uygulamasını kendisi başlatır ve parametre olarak `{"server": "http://<Mac'in TV'ye yakın IP'si>:8787"}`
  verir (LG uygulama kimliği `com.ninotranslator.tv`, Samsung `NinoTVApps.Nino`). TV gelen adresi saklar.
  Parametrelerde `hdmi` (1–4) de olabilir.
- Android TV'de Mac TV'yi denetlemez; TV uygulaması Mac'i kendi bulur.
- TV kayıtlı adrese art arda 3 kez ulaşamazsa ağı tarar: kendi alt ağının ve kayıtlı adresin alt ağının 1–254
  adreslerine `GET /hello` (aynı anda 24, 1.2 sn zaman aşımı); cevapta `nino` geçen ilk adrese bağlanır.

### 5.2 HTTP yolları

| İstek | Cevap |
|---|---|
| `OPTIONS *` | 204 |
| `GET /hello` | 200, `{"app":"nino"}` |
| `GET /events` | SSE akışı (aşağıda). Sorgu: `model=<TV markası/modeli>` (Mac yalnız harf, rakam, boşluk, `.-_()` bırakır, en çok 60 karakter; Sistem sağlığında gösterilir), `app=<TV uygulaması sürümü>`, `viewer=obs` (OBS katmanı: olayları alır ama "TV bağlı" sayılmaz) |
| `GET /obs` | OBS "Tarayıcı kaynağı" sayfası (HTML) |
| `GET <yayınlanmış dosya>` | Eskiden dublaj sesleri (`/speech/<n>.wav`, `/voices/…`); dublaj kalktı |
| diğer | 404 |

Her cevapta `Access-Control-Allow-Origin: *`; tek seferlik cevaplar `Connection: close`.

### 5.3 SSE akışı

Başlık: `Content-Type: text/event-stream; charset=utf-8`, `Cache-Control: no-cache`, `Connection: keep-alive`.
Gövde `retry: 2000` ile başlar. Bağlanır bağlanmaz:
- son gönderilen `style` olayı (varsa),
- çeviri son 20 sn içinde başladıysa ve izleyici OBS değilse `started` olayı.

Her olay: `event: <ad>\ndata: <JSON, anahtarlar sıralı>\n\n`. 15 sn'de bir canlı tutma çerçevesi:
`: ping` yorumu + `event: ping` / `data: {}`. TV ping gördükten sonra 31 sn hiçbir şey gelmezse yeniden bağlanır.

"Altyazı olayları" (`subtitle`, `clear`, `screen`, `screen-clear`, `style`, `region`, `region-clear`):
altyazı TV'de gösterilmeyecekse (`output: computer`) TV'lere gitmez, OBS'ye gider. `started`/`stopped`/`ping` her zaman gider.

### 5.4 Olaylar ve JSON gövdeleri

Ondalıklar en çok 4 basamağa yuvarlanır, kutular 0–1 arasına kırpılır. Kutu = `{"left", "top", "right", "bottom"}`
(karenin oranı, üstten/soldan).

| Olay | Gövde | TV ne yapar |
|---|---|---|
| `style` | `fontSize`, `bottomPercent`, `placement`, `background` (0–100), `backgroundShape`, `bold`, `textColor`, `displayMode`, `stackPrevious`, `theme`, `autoSize`, `font`, `watermark` (değerler 1.2'deki Stil ile aynı) | Görünümü uygular. Bilinmeyen alanı eski TV'ler yok sayar |
| `subtitle` | `text` (çeviri; konuşan adı ve satır sonları içinde), `duration` (ms; varsayılan 15000), `at` (Mac saati, Unix ms), `box`? (İngilizce altyazının yeri), `replace`? (true: önceki satırın düzelmiş okuması, yığma, yerine koy), `light`? (0–1 sahne aydınlığı, 2 basamak; zemin koyuluğu buna göre), `cover`? (base64 JPEG: altyazının arkasının bulanık hali, buzlu zemin) | Altyazıyı gösterir; `stackPrevious` açıksa önceki satır soluk üstte kalır |
| `clear` | `{}` | Altyazıyı kaldırır |
| `started` | `{}` | 7 sn "çeviri başladı" balonu ve rozet |
| `stopped` | `{}` | Rozet, altyazı, ekran ve bölge kutuları hemen kalkar |
| `screen` | `{"duration": ms, "items": [öğe], "overlay"?: true}` | Ekran çevirisi sonuçları ya da sürekli örtüler. `overlay: true` iken TV o an görünen altyazıyı silmez |
| `screen-clear` | `{}` | Ekran örtülerini kaldırır (altyazıya dokunmaz) |
| `region` | `{"id": ek alan kimliği, "text": çeviri (boşsa kutu kalkar), "box"?, "line"?: satır yüksekliği}` | Ek alan kutusu |
| `region-clear` | `{}` | Bütün ek alan kutuları kalkar |
| `ping` | `{}` | Canlılık |

`screen` öğesi: `{"box", "line": satır yüksekliği, "text": çeviri}` ve isteğe bağlı bayraklar:
- `paragraphs: true` çok parçalı (satır sonlu),
- `plain: true` kutusuz, gölgeli sade yazı (görevin altındaki çeviri, telefon araması),
- `italic: true` eğik (telefon araması: "… aranıyor"),
- `fill: "#rrggbb"` + `ink: "#rrggbb"`: oyunun kendi kutusunun zemin ve yazı rengi; çeviri o kutunun tam üstüne aynı görünümle yazılır (telefon mesaj balonları),
- `angle`: derece, saat yönü artı, 1 basamak (yalnız |açı| ≥ 0.3 ise),
- `alpha`: zemin saydamlığı 0–1, 2 basamak,
- `side: true` balon oyunun kutusunun yanında (daha yuvarlak, gölgeli),
- `frost: true` buzlu kart (arkası bulanık, açık zemin),
- `backdrop: true` üstünde yazı olmayan zemin (oyun telefonundaki mesaj ekranının arka planı),
- `card: true` harita görev kartının çevirisi (koyu zemin, üstte pembe çizgi, ilk satır başlık).

Sürekli örtüler tek liste halinde, `overlay: true` ve `duration: 120000` ile gönderilir; sıra: köşe yazıları →
düğme/ipucu yazıları → mesaj kartı → telefon → harita kartı. Liste boşalınca `screen-clear`.
Görev yazısının çevirisi ekrandayken `subtitle` kutusu 0.03 yukarı alınır (alt kenar 0.012 yukarı).

### 5.5 OBS katmanı

`GET /obs` sayfası kendi içinden `/events?viewer=obs`'ye bağlanır. Sayfa sorgu parametreleri: `size` (1080p'de
piksel yazı boyu), `bottom` (alttan %), `bg` (sayı: kutu koyuluğu 0–100; ya da `green`/`black`/`magenta`: bütün sayfanın
zemini, chroma key için). "Yayın penceresi" aynı zemin renklerini kullanır (`streamBackground`).

---

## 6. Yeni NinoCore protokolüyle farklar

NinoCore (`~/Desktop/NinoCore/docs/tarif/protokol.md`): TV dinler (TCP **47800**, HTTP + WebSocket `/nino/ws`,
Bonjour `_nino._tcp`), gönderici bağlanır, `hello`/`welcome` el sıkışması, `show`/`clear`/`ping`/`pong`/`error`.

| Konu | Eski | Yeni |
|---|---|---|
| Kim dinler | Mac (8787) | TV (47800) |
| Taşıma | SSE (tek yön, Mac → TV) | WebSocket (iki yön) + tek seferlik HTTP POST |
| Bulma | TV ağı tarar (`/hello`); LG/Samsung'a adres parametreyle verilir | Bonjour ya da elle IP, `GET /nino/info` |
| Sürüm | yok (bilinmeyen olay yok sayılır) | `version`, `versions`, el sıkışma |
| Canlılık | Mac 15 sn'de `ping`, TV 31 sn sessizlikte yeniden bağlanır | Gönderici 5 sn'de `ping`, 15 sn'de kopuk sayar; TV 20 sn sessizlikte ekranı temizler |
| Çoklu istemci | Bir Mac, birçok TV + OBS aynı anda | TV tek gönderici kabul eder (`replaced`) |
| Altyazı kimliği | yok (`replace` bayrağı) | `id` zorunlu, `clear` kimlikli |
| Süre | `duration` (varsayılan 15 sn) | `durationMs` (0 = `clear`'a kadar) |
| Mesaj sınırı | yok (`cover` görseli büyük olabilir) | 16 KB |

**Yeni protokolde eksik olanlar** (eski TV deneyimini sürdürmek için eklenmesi ya da ayrı karar verilmesi gerekenler):

1. `style` olayının tamamı (13 alan: boyut, yer, zemin, şekil, kalınlık, renk, görüntü kipi, yığma, tema, otomatik boy, yazı tipi, rozet). Yenide yalnız `position: bottom|top` var.
2. `box`: İngilizce altyazının ekrandaki yeri (örtme kipi buna dayanır).
3. `replace` (düzelmiş okuma yerine koyma) ve önceki satırı yığma.
4. `light` (akıllı koyuluk) ve `cover` (buzlu zemin görseli; 16 KB sınırına sığmaz).
5. `at` (gönderme anı).
6. `started` / `stopped` (rozet ve balon).
7. `screen` / `screen-clear` ve öğe bayrakları (`plain`, `italic`, `fill`, `ink`, `angle`, `alpha`, `side`, `frost`, `backdrop`, `card`, `paragraphs`, `line`, `overlay`): ekranı çevir, köşe yazıları, telefon, harita kartı, mesaj kartı.
8. `region` / `region-clear`: ek alanlar.
9. TV'nin modelini ve uygulama sürümünü Mac'e söylemesi (`model`, `app`) — yenide `info` yalnız ad ve kimlik veriyor.
10. OBS/izleyici bağlantısı ve `/obs` sayfası (TV olmayan, sayılmayan izleyici).
11. Birden çok TV'ye aynı anda gönderme.
12. "Altyazı yalnız bilgisayarda" iken TV'ye altyazı gitmemesi ama durum olaylarının gitmesi.

**Sonuç:** Kullanıcıların TV'lerinde kurulu uygulamalar yalnız eski düzeni konuşur. Yeni Mac uygulaması, yeni TV
uygulamaları her yere dağıtılana kadar **eski 8787 SSE sunucusunu da** açmalı (iki protokol yan yana), ya da
TV uygulamaları önce güncellenmeli.

---

## 7. NinoCore'un kendi düzeniyle çakışma noktaları

NinoCore: `Application Support/Nino/settings.json`, `cache/translations.json`, `packs/*.ninopack.json`, `logs/`;
Anahtarlık hizmeti `com.ninotranslator.secrets`, hesap `provider.<ad>.key`; PS5 kaydı hesap `remoteplay.<hostID>`.

| Nokta | Çakışma | Öneri |
|---|---|---|
| Kök klasör | İkisi de `Application Support/Nino`. Eski dosyalarla aynı klasörü paylaşırlar; ad çakışması yok ama `packs/` ortak | Kök paylaşılabilir; yeni dosyalar için ayrı alt klasör düşün |
| `packs/` | Eski `*.json.gz` (hash anahtarlı, İngilizcesiz) ile yeni `*.ninopack.json` (İngilizce metinli) **aynı klasörde**. Yeni kütüphane yalnız `.ninopack.json` okur, eskileri görmez; eski paket güncelleyici aynı klasöre yazar | Yeni uygulama eski paket biçimini ayrıca okumalı (dönüştürülemez: İngilizce metin yok) |
| Paket/önbellek anahtarı | Eski: sadeleştirilmiş metnin SHA-256'sının ilk 8 baytı (noktalama ve aksan atılır). Yeni: küçük harf + boşluk + tırnak düzeltme, noktalama korunur, metin olarak | Eski paketler, ~250 bin havuz çevirisi ve sunucu bu anahtarı kullanıyor; yeni çekirdeğe eski anahtarla arama eklenmeli |
| Ayarlar | Eski: UserDefaults `settings` blobu. Yeni: `settings.json` (`reading`/`translation`/`display`). Dosya çakışması yok | İlk açılışta blobdan `settings.json` üretilir; blob silinmez (eski sürüme dönüş) |
| Bölge biçimi | Eski `top/bottom/left/right`; yeni `x/y/width/height`. Varsayılanlar da farklı (eski 0.62–0.97 × 0.14–0.86; yeni x 0.10, y 0.62, genişlik 0.80, yükseklik 0.36) | Çeviri: x = left, y = top, width = right − left, height = bottom − top |
| Çeviri önbelleği | Eski: `Translations/` altında motor başına JSONL; yeni: `cache/translations.json` tek dosya (anahtar, kaynak, metin, köken, tarih) | Eski dosyalar bir kez içe alınabilir ya da okunur bırakılır; anahtar farkına dikkat |
| Günlükler | Eski `~/Library/Logs/Nino`; yeni `Application Support/Nino/logs` | Sorun bildirimi ve destek iki yerin hangisine bakacağını bilmeli; tek yer seçilmeli |
| Anahtarlık hizmeti | Eski `com.ninotranslator.mac`; yeni `com.ninotranslator.secrets` | Çeviri anahtarları ilk açılışta taşınmalı (değer JSON tırnaklı dizge → düz dizge) |
| Anahtar adları | `deepLKey`, `geminiKey`, `openAIKey`, `claudeKey`, `localAIKey` | `provider.<ad>.key`'e eşlenmeli |
| Değer sarımı | Eski: JSON kodlanmış (tırnaklı dizge, base64 Data) | Yeni: düz dizge; PS5 kaydı base64(JSON) |
| PS5 kaydı | Eski: `host`, `name`, `registKey`, `morning`. Yeni: `hostID`, `nickname`, `isPS5`, `target`, `registKey`, `rpKey`, `serverMAC` | `morning` → `rpKey`, `name` → `nickname`, `isPS5` = true; `hostID` ve `serverMAC` PS5 ağda bulunarak (keşif cevabı) tamamlanmalı; `target` PS5 kabul edilmeli. `host` (IP) yenide yok, ayrıca saklanmalı |
| PSN hesap kimliği | Eski: `accountId` (Data, base64). Yeni çekirdekte saklama yeri yok (base64 girdi bekliyor) | Eski kayıttan okunup kullanılmalı |
| TV kaydı | Eski `tv` + `tvKey` + `tvDevKey`; yeni `display.host/port/lastDisplayID` | LG/Samsung denetim anahtarları yenide yok; TV kurulum yardımcısı için korunmalı |
| Port | Eski 8787 (Mac), yeni 47800 (TV) | Çakışmaz; ikisi birlikte çalışabilir |

---

## 8. En önemli uyum riskleri (sıralı)

1. **TV protokolü tersine döndü.** Kurulu TV uygulamaları yalnız "Mac 8787'de SSE sunar" düzenini bilir; NinoCore'da
   TV dinler (47800, WebSocket). Eski sunucu açılmazsa hiçbir TV'de altyazı görünmez.
2. **Anahtar algoritması farklı.** Eski paketler ve havuz çevirileri SHA-256 tabanlı 16 hex anahtar kullanır; yeni
   çekirdeğin anahtarı başka. Ayrıca eski paketlerde İngilizce yok, dönüştürülemez.
3. **PS5 kaydı eksik alanlı ve farklı yerde.** Eski kayıtta host id, MAC, hedef yok; hizmet, hesap adı ve sarım farklı.
   Yanlış eşlenirse kullanıcı PS5'i yeniden eşleştirmek zorunda kalır (ikinci hesap girişi dahil).
4. **Anahtarlık erişimi imzaya bağlı.** Aynı paket kimliği ve aynı takım imzası yoksa eski kayıtlar sorulur ya da okunamaz.
5. **Öğrenilmiş veriler sessizce kaybolabilir:** `subtitle-layout.json` (altyazı yeri), `phone-memory-*.json`,
   `history.json`, `pool/state.json`'daki kurulum kimliği, `adb/adbkey` (Android TV izni). Bunlar NinoCore düzeninde
   yok; yeni uygulama okumazsa kullanıcı "her şey sıfırlandı" görür.
