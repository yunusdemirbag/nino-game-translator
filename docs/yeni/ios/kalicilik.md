# Nino iOS: kalıcı veri sözleşmesi

Bu belge, yeni iPhone/iPad uygulamasının (paket kimliği `com.ninotranslator.ios`) mevcut kullanıcının kayıtlarını
**aynen** okuyabilmesi için gereken her şeyi anlatır. Kaynak, şu anki uygulamanın davranışıdır (`nino-ios/`, `core/`,
`remoteplay/`). Kod kopyalanmaz; burada yalnız biçimler, adlar ve kurallar vardır.

Genel kurallar:

- "Zorunlu" alan: kayıtta yoksa ya da tipi yanlışsa o nesnenin tamamı açılamaz.
- "Hoşgörülü" alan: yoksa ya da tipi/değeri tanınmıyorsa varsayılan kullanılır, nesnenin geri kalanı açılır.
- JSON'daki anahtar sırası sabit değildir; varsayılan kodlayıcı `/` karakterini `\/` diye yazar. Testler baytları
  değil, **açılmış değerleri** karşılaştırmalıdır.
- `Data` alanları JSON'da standart base64 metnidir (dolgulu, `+` ve `/` ile).
- Tarihler (yalnız dosyalarda) ISO 8601, saniye hassasiyetinde, UTC: `"2026-11-22T14:03:05Z"`.

---

## 1. Anahtar Zinciri (Keychain)

### 1.1 Hizmet adı ve öğe biçimi

| Özellik | Değer |
|---|---|
| Sınıf | Genel parola (`kSecClassGenericPassword`) |
| Hizmet (`kSecAttrService`) | `com.ninotranslator.ios` |
| Hesap (`kSecAttrAccount`) | Aşağıdaki tablodaki anahtar adı (StoreKey) |
| Değer (`kSecValueData`) | Değerin **JSON kodlaması** (UTF-8 baytlar) |
| Erişim grubu | Verilmez (uygulamanın varsayılan grubu; yetki dosyası boş) |
| Erişilebilirlik | Verilmez (sistemin varsayılanı) |
| iCloud eşitleme | Yok |

Not: Mac uygulaması aynı kodu `com.ninotranslator.mac` hizmet adıyla kullanır; iOS için önemi yok.

**Okunabilirlik koşulu:** erişim grubu verilmediği için öğeler uygulamanın varsayılan grubundadır (takım öneki +
paket kimliği). Yeni sürüm aynı paket kimliğiyle **ve aynı geliştirici takımıyla (takım öneki)** imzalanmazsa eski
öğeleri göremez; yalnız paket kimliğinin aynı olması yetmez. Yeni yetki dosyasına başka bir erişim grubu eklenirse
ilk grup değişebilir; okuma ve yazmada grup açıkça verilmeli ya da yetki dosyası boş bırakılmalıdır.

Yazma kuralı: aynı hizmet + hesap için önce eski öğe silinir, sonra yenisi eklenir (güncelleme yok, sil-ekle).

**Değer biçimi önemli:** değerler her zaman `JSONEncoder` ile kodlanır, düz bayt değildir. Yani:

| Swift tipi | Anahtar Zinciri'ndeki baytlar (UTF-8) |
|---|---|
| `String` `abc` | `"abc"` (çift tırnaklı JSON metni; içindeki `"` ve `/` kaçışlı) |
| `Bool` true | `true` |
| `Data` (ör. 8 bayt) | `"AAECAwQFBgc="` (tırnaklı base64) |
| Yapı (ör. `RegisteredConsole`) | JSON nesnesi `{...}` |

Okurken: baytlar JSON olarak çözülür. Çözülemezse değer "yok" sayılır (hata gösterilmez).

### 1.2 Eski hizmetten taşıma

Eski sürümler iOS'ta başka bir hizmet adı kullanıyordu. Bu ad kodda açık yazılmaz; `LegacyNames.keychainService`
içinde kodlanmış durur (yeni uygulama da aynı yöntemi kullanmalı, adı belgeye ya da koda düz yazmamalı).

Okuma sırası (her anahtar için ayrı ayrı, tembel):

1. Yeni hizmette (`com.ninotranslator.ios`) o hesap var mı? Varsa onu kullan, bitti.
2. Yoksa eski hizmette (`LegacyNames.keychainService`) aynı hesap adıyla ara.
3. Bulunduysa: yeni hizmete aynı baytlarla yaz. Yazma başarılıysa eski öğeyi sil. Yazma başarısızsa eskisi kalır,
   değer yine de bu sefer kullanılır.
4. İkisinde de yoksa değer yok.

Toplu taşıma yapılmaz; hangi anahtar okunursa o taşınır. Silme (`remove`) yalnız yeni hizmete uygulanır.

### 1.3 Hesap adları (StoreKey) — iOS'ta kullanılanlar

| Hesap adı | Tip | Ne | Kim yazar / siler |
|---|---|---|---|
| `accountId` | `Data` (8 bayt) | Remote Play için kullanılan ikinci hesabın sayısal kimliği | PSN girişinde yazılır; kurulum sıfırlanınca silinir |
| `console` | `RegisteredConsole` (bkz. 3.1) | Eşlenen PS5 | Eşleşmede yazılır; PS5 başka adreste bulununca güncellenir; sıfırlamada silinir |
| `tv` | `LGTV` (bkz. 3.2) | Altyazının gideceği TV | TV eşleşmesinde ve TV yeni adreste bulununca; sıfırlamada silinir |
| `tvKey` | `String` | LG: client-key; Samsung: jeton; Android TV: boş metin `""` | Eşleşmede yazılır (Samsung boş jeton dönerse eskisi korunur); sıfırlamada silinir |
| `setupComplete` | `Bool` | Kurulum bitti (`true`) | Adım "bitti"ye geçince ve telefondan TV kurulumu bitince; sıfırlamada silinir |
| `loginPasscode` | `String` (tam 4 rakam) | İkinci hesabın PS5'teki oturum şifresi | Ayarlar'dan; geçersiz şifre yazılmaz; sıfırlamada silinir |
| `deepLKey` | `String` | DeepL anahtarı | Anahtar denenip kabul edilince |
| `geminiKey` | `String` | Gemini anahtarı | 〃 |
| `openAIKey` | `String` | OpenAI anahtarı | 〃 |
| `claudeKey` | `String` | Claude anahtarı | 〃 |
| `localAIKey` | `String` | Yerel model sunucusunun anahtarı | 〃 |
| `xboxUserToken` | `String` (içinde JSON metni) | Microsoft kullanıcı jetonu (bkz. 3.4) | Jeton her yenilendiğinde; çıkışta silinir |
| `xboxConsole` | `XboxConsole` (bkz. 3.3) | Seçilen Xbox | Xbox seçilince; sıfırlamada silinir |

Dikkat edilecekler:

- `tvKey` varlığı önemlidir, içeriği değil: "TV var" kararı `tv` kayıtlı **ve** `tvKey` okunabiliyor (boş metin de olur)
  demektir. Android TV'de `""` kaydı bu yüzden gereklidir.
- `loginPasscode` okunurken boşluklar kırpılır; tam 4 ASCII rakam değilse "yok" sayılır.
- Anahtar (`*Key`) kayıtlı mı kararı: değer okunabiliyor ve boş değil.

### 1.4 StoreKey'de olan ama iOS'ta kullanılmayanlar

`tvDevKey`, `tvAppVersion`, `devSessionRenewed`, `devSessionRenewed.<adres>`, `settings` (iOS'ta Anahtar
Zinciri'nde değil, UserDefaults'ta; bkz. 2), `streamBackground`. Bunlar Mac uygulamasınındır; iOS bunları okumaz.

### 1.5 Anahtar Zinciri'nin başka kullanımı (Android TV kurulumu)

Telefondan Android TV'ye kurulum yapılırken adb'nin TLS kimliği için Anahtar Zinciri'ne bir **anahtar**
(`kSecClassKey`, etiket `Nino adb`, uygulama etiketi `com.ninotranslator.adb.<sertifika dosyasının adı>`, erişim
"ilk kilit açılışından sonra, yalnız bu cihaz") ve bir **sertifika** (`kSecClassCertificate`, etiket `Nino adb`)
eklenir. Bunlar her kurulumda dosyadaki anahtardan yeniden eklenir (zaten varsa sorun değil); taşınması gerekmez.

---

## 2. UserDefaults (`UserDefaults.standard`)

| Anahtar | Tip | Varsayılan (yoksa) | Ne |
|---|---|---|---|
| `settings` | `Data` (UserSettings'in JSON'u, bkz. 4) | Yok → ilk açılış ayarları | Bütün ayarlar; her değişiklikte tamamı yeniden yazılır |
| `welcomeSeen` | `Bool` | `false` | Karşılama ekranı görüldü (`@AppStorage`) |
| `platform` | `String`: `playstation` / `xbox` | Yok | Seçilen konsol türü; sıfırlamada silinir |
| `setupSkipped` | `Bool` | `false` | Kurulumda adım atlandı (`common.skipfornow`); sıfırlamada silinir |
| `disabledPacks` | `[String]` (sıralı) | `[]` | Paketler ekranında kapatılan paket kimlikleri |
| `notifyDisconnect` | `Bool` | `true` (anahtar yoksa) | Bağlantı kesilince bildirim anahtarı (`settings.notify.drop`; `@AppStorage` + model okur) |
| `notifyPackUpdates` | `Bool` | `true` | Profil'deki yeni paket bildirimi anahtarı (`settings.notifications` altında). **Yalnız saklanıyor, hiçbir kod okumuyor.** |
| `coachTourDone` | `Bool` | `false` | Ana ekrandaki tanıtım turu bitti |
| `lastSessionSeconds` | `Int` | `0` (0 = gösterme) | Son çeviri oturumunun süresi (saniye) |
| `ninoLastGamePoolFirst` | `Bool` | `false` | Son tanınan oyun "havuz öncelikli" miydi (GTA 6) |
| `lastGames` | `[String: String]` (sözlük) | `{}` | Konsol adı → kullanıcının o konsolda elle seçtiği son oyun adı. Anahtar: PS5'in adı (yoksa adresi); Xbox'ta Xbox'ın adı (yoksa `Xbox`) |
| `tvAppInstalled` | `Data` (`InstalledTVApp`'ın JSON'u, bkz. 3.5) | Yok | Telefonun Nino'yu TV'ye kurduğu ya da sürümünü okuduğu son TV |
| `lgSessionRenewedAt.<adres>` | `Date` (plist tarihi) | Yok | LG geliştirici modu süresinin son uzatıldığı an; adres kırpılır ve küçük harfe çevrilir |
| `ninoDownloadTotal` | `Int` | `0` (0 = gösterme) | Ana ekrandaki toplam indirme sayısının (`scene.downloads`) son bilinen değeri |
| `AppleLanguages` | `[String]` (tek öğe) | Sistem | Arayüz dili; her açılışta ve çeviri dili değişince yazılır (bkz. davranis.md, arayüz dili) |

Yalnız hata ayıklama / geliştirme için okunan, uygulamanın kendisinin yazmadığı anahtarlar:

| Anahtar | Tip | Ne |
|---|---|---|
| `ninoPoolURL` | `String` (http/https adres) | Ortak havuz sunucusunun adresini değiştirir (ortam değişkeni `NINO_POOL_URL` önce gelir) |
| `packsURL` | `String` | Paket güncelleyicinin adresi (çekirdekteki eski güncelleyici; iOS'un paket deposu bunu kullanmaz) |
| `poolURL` | `String` | Eski havuz istemcisinin adresi (iOS akışında kullanılmıyor) |

**Saklanmayan, türetilen durumlar:** `platformChosen` (konsol türü seçildi mi) ve açılıştaki kurulum adımı (Step)
hiçbir yerde saklanmaz; her açılışta `platform`, `accountId`, `console`, `setupSkipped`, `setupComplete`, Xbox jetonu ve
`xboxConsole` kayıtlarından hesaplanır. Kurallar `davranis.md` 2.1'de.

Hata ayıklamadaki deneme karesi kipi (`NINO_TEST_FRAME`) gerçek UserDefaults'a dokunmaz; `nino-test-frame` adlı ayrı
bir takım (suite) kullanır ve her açılışta onu siler. Bu takım taşınmaz.

---

## 3. Kayıtlı tiplerin JSON şekli

### 3.1 `RegisteredConsole` (Anahtar Zinciri `console`)

| Alan | Tip | Zorunlu | Not |
|---|---|---|---|
| `host` | String | evet | PS5'in IPv4 adresi. Eski kayıtlarda `0.0.0.0` ya da boş olabilir (o zaman PS5 adıyla aranır) |
| `name` | String | evet | PS5'in adı (ör. `PS5-123`) |
| `registKey` | Data (base64) | evet | 16 bayt kayıt anahtarı: ASCII onaltılık metin, sonu sıfır baytla doldurulmuş |
| `morning` | Data (base64) | evet | 16 bayt oturum anahtarı |

```json
{"host":"192.168.1.103","name":"PS5-002","registKey":"MWEyYjNjNGQAAAAAAAAAAA==","morning":"AAECAwQFBgcICQoLDA0ODw=="}
```

`registKey` örneğindeki baytlar `1a2b3c4d` + 8 sıfır bayttır (uyandırma kimliği bu onaltılık sayıdır).

### 3.2 `LGTV` (Anahtar Zinciri `tv`) — adı LG olsa da bütün markalar

| Alan | Tip | Zorunlu | Not |
|---|---|---|---|
| `name` | String | evet | Görünen ad |
| `host` | String | evet | TV'nin adresi |
| `brand` | String: `lg` / `samsung` / `androidTV` | hayır | Yoksa `lg` (eski kayıtlar). Tanınmayan değer: **nesne açılmaz** |

```json
{"name":"Salon TV","host":"192.168.1.50","brand":"lg"}
{"name":"Salon TV","host":"192.168.1.50"}
```

### 3.3 `XboxConsole` (Anahtar Zinciri `xboxConsole`)

Hepsi zorunlu (`powerState` da; varsayılanı olsa da kayıtta bulunmalı).

| Alan | Tip | Not |
|---|---|---|
| `id` | String | Microsoft'un konsol kimliği |
| `name` | String | Konsolun adı |
| `model` | String | Konsol türü (ör. `XboxSeriesX`) |
| `streamingEnabled` | Bool | Ev yayını ve uzaktan yönetim açık mı |
| `powerState` | String | Ör. `On`, `ConnectedStandby`, boş |

```json
{"id":"F4000ABCDEF12345","name":"Salon Xbox","model":"XboxSeriesX","streamingEnabled":true,"powerState":"On"}
```

### 3.4 `xboxUserToken` (Anahtar Zinciri, String)

Değer bir metindir; metnin içi Microsoft'un jeton yanıtının JSON'udur (eğik çizgiler kaçışsız yazılmış). Anahtar
Zinciri'ndeki baytlar bu metnin bir kez daha JSON metni olarak kodlanmış hâlidir (dış tırnaklar, içte `\"`).

İç JSON'da en az şunlar bulunur; geri kalan alanlar Microsoft'tan geldiği gibi saklanır:

| Alan | Tip | Not |
|---|---|---|
| `access_token` | String | |
| `refresh_token` | String | **Boşsa ya da yoksa jeton yok sayılır** (girişsiz) |
| `expires_in` | Sayı | Saniye |
| `expires_on` | String | ISO 8601, kesirli saniyeli (`2026-11-22T15:03:05.123Z`); okunurken 7 haneye kadar kesir kabul edilir |

Anahtar Zinciri'ndeki bayt örneği:

```text
"{\"token_type\":\"bearer\",\"access_token\":\"EwB...\",\"refresh_token\":\"M.C5...\",\"expires_in\":3600,\"expires_on\":\"2026-11-22T15:03:05.123Z\"}"
```

### 3.5 `InstalledTVApp` (UserDefaults `tvAppInstalled`, Data)

| Alan | Tip | Zorunlu | Not |
|---|---|---|---|
| `brand` | `lg` / `samsung` / `androidTV` | evet | |
| `host` | String | evet | |
| `port` | Sayı (UInt16) | hayır | Yalnız Android TV'nin ADB portu; yoksa alan hiç yazılmaz |
| `version` | String | evet | TV'deki uygulamanın sürümü (ör. `0.9.18`) |

```json
{"brand":"androidTV","host":"192.168.0.110","port":5555,"version":"0.9.18"}
```

### 3.6 Taşınmayan, yalnız bellekte duranlar

`TVAppUpdate` (güncelleme önerisi), `TVPairing`, oturum durumu, son satırlar listesi kalıcı değildir.

---

## 4. `UserSettings` (UserDefaults `settings`)

### 4.1 Açılış kuralı

1. `settings` verisi yoksa ya da JSON olarak **açılamazsa** (zorunlu bir alanın tipi yanlışsa da): ilk açılış ayarları
   kullanılır: hepsi varsayılan, yalnız `targetLanguage` = sistemin ilk tercih dili hedef dil listesindeyse o, değilse
   `tr` (Filipince `fil…` → `tl`).
2. Açılınca alanlar aşağıdaki kurallarla doldurulur.
3. Ardından "model temizliği" yapılır: `geminiModel`, `openAIModel`, `claudeModel` listedeki (`ai-models.json`)
   kimliklerden biri değilse listenin ilkine döner; `localAIModel` boşsa varsayılana döner (dolu her ad kabul).
4. Açılış sonrası değerler UserDefaults'a **hemen yazılmaz**; ilk ayar değişikliğinde tamamı yeniden yazılır.

### 4.2 Alanlar

"Kural" sütunu: Z = zorunlu tip (yanlış tip bütün ayarı sıfırlar; alan yoksa varsayılan), H = hoşgörülü (yanlış tip
ya da bilinmeyen değer → varsayılan).

| Alan | Tip | Varsayılan | Kural | Not |
|---|---|---|---|---|
| `region` | CropRegion | `{top .62, bottom .97, left .14, right .86}` | Z | Altyazının arandığı bölge |
| `areaPreset` | `bottom`/`top`/`full`/`custom` | `bottom` | H | Yoksa ya da okunamazsa **bölgeden çıkarılır** (4.4) |
| `extraAreas` | [ExtraArea] | `[]` | H (bütün dizi) | Tek öğe bozuksa **bütün dizi** `[]` olur; en çok 3 öğe alınır, fazlası atılır |
| `style` | SubtitleStyle | (4.3) | Z | |
| `sourceLanguage` | String | `en` | Z | |
| `targetLanguage` | String | `tr` | Z | Eski kayıtta yoksa `tr` (sistem dili değil) |
| `onlineTranslation` | Bool | `false` | Z | |
| `onlineEngine` | `deepl`/`gemini`/`openai`/`claude`/`local` | `deepl` | H | `free` yazılıysa `deepl` olur |
| `geminiModel` | String | listenin ilki (şu an `gemini-3.5-flash-lite`) | Z | |
| `openAIModel` | String | listenin ilki (şu an `gpt-6-luna`) | Z | |
| `claudeModel` | String | listenin ilki (şu an `claude-haiku-5-5`) | Z | |
| `localAIBaseURL` | String | `http://localhost:11434/v1` | Z | |
| `localAIModel` | String | `translategemma:4b` | Z | Değer `qwen2.5:7b` ise varsayılana çevrilir |
| `output` | `tv`/`computer`/`both` | `tv` | H | `both` okunursa `tv` olur. `computer` = TV yok (`tv.none`), altyazı telefonda |
| `overlayClickThrough` | Bool | `false` | Z | Mac içindir |
| `videoSource` | `ps5`/`window`/`card` | `ps5` | H | Mac içindir |
| `gameConsole` | `ps5`/`xbox` | `ps5` | H | Mac içindir (iOS'ta konsol türü UserDefaults `platform`'dadır) |
| `gamePacks` | Bool | `true` | Z | |
| `sharePool` | Bool | `true` | Z | Ortak havuz |
| `autoReport` | Bool | `true` | H | Otomatik sorun bildirimi |
| `translateCorners` | Bool | `true` | H | Köşe / ipucu / telefon çevirisi |
| `askGame` | Bool | `true` | Z | Oyun tanınmazsa sor |
| `showSpeakerNames` | Bool | `true` | Z | |
| `fastSubtitleDetection` | Bool | `false` | Z | |
| `xboxAudioOnDevice` | Bool | `true` | Z | |
| `appearance` | `dark`/`light`/`system` | `system` | H | iOS arayüzü bunu kullanmaz (hep açık renk) |
| `homeStyle` | `livingRoom`/`toggle` | `livingRoom` | H | |
| `frameSource` | `ps5`/`remotePlayWindow` | `ps5` | H | Uyumluluk için saklanır |
| `remotePlayApp` | `automatic`/`sony`/`chiaki` | `automatic` | H | Mac içindir |

Bilinmeyen fazladan alanlar yok sayılır. Yazılırken bütün alanlar yazılır (Mac'e özgü olanlar dahil); yeni uygulama da
bunları **korumalı** (okumadığı alanları silmemeli), çünkü ileride geri dönüşte ya da paylaşılan biçimde lazım olabilir.

### 4.3 İç içe tipler

**CropRegion** (bütün alanlar zorunlu; biri eksikse içinde bulunduğu nesne açılamaz — `region` için bu, bütün
ayarların sıfırlanması demektir):

| Alan | Tip | Varsayılan | Anlam |
|---|---|---|---|
| `top` | Double | 0.62 | Üst kenar, karenin yüksekliğine oranla (0–1, üstten) |
| `bottom` | Double | 0.97 | Alt kenar |
| `left` | Double | 0.14 | Sol kenar, genişliğe oranla (soldan) |
| `right` | Double | 0.86 | Sağ kenar |

**AreaPreset** hazır bölgeleri:

| Değer | Bölge (top, bottom, left, right) |
|---|---|
| `bottom` | 0.62, 0.97, 0.14, 0.86 |
| `top` | 0.03, 0.38, 0.14, 0.86 |
| `full` | 0, 1, 0, 1 |
| `custom` | Kayıtlı `region` olduğu gibi |

**ExtraArea** (her alan isteğe bağlı ama tipi yanlışsa öğe — ve dolayısıyla bütün dizi — düşer):

| Alan | Tip | Yoksa |
|---|---|---|
| `id` | String | Yeni rastgele UUID (büyük harfli UUID metni) |
| `name` | String | `""` |
| `region` | CropRegion | Görev hazır bölgesi (0.03, 0.30, 0.66, 0.98) |
| `enabled` | Bool | `true` |

Ek alan hazır bölgeleri: görev (0.03, 0.30, 0.66, 0.98), bildirim (0.58, 0.88, 0.02, 0.30), telefon
(0.50, 0.95, 0.72, 0.98).

**SubtitleStyle**:

| Alan | Tip | Varsayılan | Kural | Değerler |
|---|---|---|---|---|
| `fontSize` | Int | 46 | Z | 36, 46, 58, 72 önerilir |
| `bottomPercent` | Int | 7 | Z | Sabit yerleşimde alttan uzaklık (%) |
| `placement` | String | `cover` | H | `cover`, `above`, `below`, `fixed` |
| `background` | Int | 100 | Z | Zemin koyuluğu % (0–100; TV'ye 0–100 aralığına sıkıştırılıp gider) |
| `backgroundShape` | String | `fit` | H | `fit`, `band` |
| `bold` | Bool | false | Z | |
| `textColor` | String | `white` | H | `white`, `yellow` |
| `displayMode` | String | `inApp` | H | `inApp`, `overlay` (yalnız Android TV) |
| `stackPrevious` | Bool | true | Z | |
| `theme` | String | `classic` | H | `classic`, `cinema`, `minimal`, `glass`, `contrast`, `outline` |
| `autoSize` | Bool | true | H | |
| `font` | String | `condensed` | H | `system`, `modern`, `condensed`, `rounded` |
| `watermark` | Bool | true | H | |

Açılış sonrası kural: `placement` = `cover` ve `background` < 60 ise `background` = 100 yapılır.

### 4.4 Eski kayıtların açılması (özet)

| Durum | Sonuç |
|---|---|
| `areaPreset` yok | `region` hazır bölgelerden biriyle 0.001 payla aynıysa o, değilse `custom` |
| `extraAreas` yok / bozuk | `[]` |
| `extraAreas` 3'ten fazla | İlk 3 |
| `onlineEngine` = `free` | `deepl` |
| `localAIModel` = `qwen2.5:7b` | `translategemma:4b` |
| `output` = `both` | `tv` |
| `style.placement` = `cover` ve `style.background` < 60 | `background` = 100 |
| Bulut modeli listede yok | Listenin ilk modeli |
| `targetLanguage` yok | `tr` |
| Zorunlu alanın tipi yanlış (ör. `"gamePacks":"yes"`) | **Bütün ayar** ilk açılış ayarlarına döner |

### 4.5 Örnekler

Tam ayar (varsayılanlar; kodlayıcının yazdığı gibi `/` kaçışlı):

```json
{"region":{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86},"areaPreset":"bottom","extraAreas":[],
 "style":{"fontSize":46,"bottomPercent":7,"placement":"cover","background":100,"backgroundShape":"fit","bold":false,
          "textColor":"white","displayMode":"inApp","stackPrevious":true,"theme":"classic","autoSize":true,
          "font":"condensed","watermark":true},
 "sourceLanguage":"en","targetLanguage":"tr","onlineTranslation":false,"onlineEngine":"deepl",
 "geminiModel":"gemini-3.5-flash-lite","openAIModel":"gpt-6-luna","claudeModel":"claude-haiku-5-5",
 "localAIBaseURL":"http:\/\/localhost:11434\/v1","localAIModel":"translategemma:4b","output":"tv",
 "overlayClickThrough":false,"videoSource":"ps5","gameConsole":"ps5","gamePacks":true,"sharePool":true,
 "autoReport":true,"translateCorners":true,"askGame":true,"showSpeakerNames":true,"fastSubtitleDetection":false,
 "xboxAudioOnDevice":true,"appearance":"system","homeStyle":"livingRoom","frameSource":"ps5","remotePlayApp":"automatic"}
```

Eski, kısa kayıt (açılınca: `areaPreset` = `custom`, `output` = `tv`, `style` eksikleri varsayılan, `background` 100):

```json
{"region":{"top":0.55,"bottom":0.95,"left":0.1,"right":0.9},"sourceLanguage":"en","targetLanguage":"ar",
 "output":"both","style":{"fontSize":58,"placement":"cover","background":30}}
```

Ek alanlı kayıt:

```json
{"region":{"top":0.62,"bottom":0.97,"left":0.14,"right":0.86},
 "extraAreas":[{"id":"7C1D2E3F-0000-4000-8000-000000000001","name":"Görev",
                "region":{"top":0.03,"bottom":0.3,"left":0.66,"right":0.98},"enabled":true}],
 "onlineTranslation":true,"onlineEngine":"gemini","geminiModel":"eski-model-adi"}
```

(Açılınca `geminiModel` listede olmadığı için listenin ilkine döner.)

Bütün ayarı sıfırlayan kayıt (zorunlu alanın tipi yanlış):

```json
{"targetLanguage":"tr","gamePacks":"evet"}
```

---

## 5. Dosyalar

### 5.1 Klasörler (iOS)

Uygulamanın kendi kapsayıcısında:

| Klasör | Yol |
|---|---|
| Veri | `Library/Application Support/Nino/` |
| Günlük | `Library/Logs/Nino/` |

**Eski klasörün taşınması** (açılışta, hiçbir dosya açılmadan önce, bir kez; testlerde yapılmaz). Eski ad
`LegacyNames.folder`'dadır. Her iki kök (Application Support ve Logs) için ayrı ayrı:

| Yeni klasör | Eski klasör | Yapılan |
|---|---|---|
| Var ve dolu | Ne olursa | Yeni kullanılır, eskiye dokunulmaz, birleştirilmez |
| Var ama boş (`.DS_Store` dışında bir şey yok) | Var | Boş yeni klasör silinir, eskisi yeni ada taşınır |
| Yok | Var | Eskisi tek yeniden adlandırmayla yeni ada taşınır |
| Yok | Yok | Yeni klasör oluşturulur |
| Taşıma başarısız | — | Bu çalıştırmada eski klasör kullanılır, yeni klasör oluşturulmaz; sonraki açılışta yeniden denenir |

iOS'ta kopyalama yolu yoktur (yalnız taşıma).

**Tuzak:** Bazı dosyalar yolu `AppFolder` üzerinden alır (geçmiş, sözlük), bazıları doğrudan
`Application Support/Nino` yazar (havuz, önbellekler, paketler, TV anahtarları, sorun kaydı). Taşıma başarısız olursa
ikisi farklı klasörlere düşer. Yeni uygulama tek yerden yol kurmalı; taşıma başarısızsa ne yapacağını açıkça seçmeli.

### 5.2 `Application Support/Nino/` içeriği

Ad büyük-küçük harfiyle birlikte sözleşmedir. **Dikkat:** aynı klasörde hem `Translations` hem `translations`
vardır. iPhone'un dosya sistemi büyük-küçük harfe duyarlıdır, bunlar iki ayrı klasördür; simülatör (Mac diski)
genelde duyarsızdır ve ikisi aynı klasöre düşer. Testlerde bu fark gözden kaçabilir.

| Yol | Biçim | Önemi | Not |
|---|---|---|---|
| `history.json` | JSON (5.3) | **Taşınmalı** | Son 200 çeviri |
| `Packs/files/<kimlik>.json.gz` | gzip'li paket JSON'u (5.4) | Yeniden indirilebilir | Sunucudan inen paketler |
| `Packs/manifest.json` | JSON | Yeniden indirilebilir | Son paket listesi (5.4) |
| `Packs/refreshed` | Boş dosya; değiştirilme tarihi = son bakış | Yeniden üretilir | |
| `Packs/imported/<kimlik>.json` | Paket JSON'u (gzip'siz) | **Taşınmalı** | Kullanıcının içe aktardığı topluluk paketleri; sunucuda yok |
| `pool/state.json` | JSON | **Taşınmalı (kimlik)** | `install` alanı uygulamanın rastgele kuruluş kimliği (küçük harfli UUID); sorun bildirimleri de bunu kullanır |
| `pool/pending.jsonl`, `pool/outbox/`, `pool/parked/`, `pool/rejected.jsonl` | Satır kuyruğu | Atılabilir | Ortak havuza gönderilmeyi bekleyen İngilizce satırlar |
| `pool.json` | Eski kuyruk | Atılabilir | Varsa içindeki gönderilmemiş satırlar bir kez yeni kuyruğa aktarılır |
| `translations/install` | Düz metin, tek satır UUID | Taşınmalı | Çeviri havuzunun kuruluş kimliği (geçerli UUID değilse yenisi üretilir) |
| `translations/translations-<dil>.json` | JSON `{"language":…,"texts":{İngilizce: çeviri},"cursors":{oyun: {"since":0,"after":"","checked":0}}}` | Yeniden indirilebilir | Sunucudan inen hazır çeviriler |
| `Translations/v1-<motor>-en-<dil>.jsonl` ya da `Translations/v1h-<sha256>.jsonl` | Her satır `["kaynak","çeviri"]` | Önbellek | Motor adı sade değilse (ör. `gemini:model`) dosya adı motor+dil çiftinin SHA-256'sıdır |
| `phone-memory-<dil>.json` | `{İngilizce mesaj: çeviri}` | Önbellek | Oyundaki telefon mesajlarının çevirileri |
| `Glossary/` | Kullanıcı sözlüğü klasörü | Taşınmalı (varsa) | Ücretsiz çevirinin kullanıcı terimleri |
| `sorunlar.json` | JSON dizisi (en çok 40 kayıt) | Atılabilir | Oturum sorunları (5.5) |
| `otomatik-bildirim.json` | JSON `{"day":"…","sent":0,"pending":{…}}` | Atılabilir | Otomatik bildirimin günlük sayacı ve gönderilemeyen bildirim |
| `tv/lg/<adres>.key` | Ham bayt | **Taşınmalı** | LG geliştirici modu SSH anahtarı (adresteki harf/rakam/`._-` dışı `_`); yedeğe girmez |
| `tv/samsung/<duid>/key.der`, `author.cer`, `distributor.cer`, `device-profile.xml`, `duid.txt` | İkili / metin | **Taşınmalı** | Samsung imza profili (Samsung hesabıyla yeniden alınabilir ama zahmetli) |
| `tv/adb/adbkey`, `tv/sdb/adbkey` | Anahtar dosyası | Taşınmalı | Android TV ve Samsung bağlantı anahtarları; değişirse TV yeniden onay ister |
| `tv/tvinstall.log` | Düz metin | Günlük | TV kurulum günlüğü (`yyyy-MM-dd HH:mm:ss satır`) |

### 5.3 `history.json`

```json
{"version":1,"entries":[
  {"id":12,"date":"2026-11-22T21:14:03Z","source":"Stay close.","translation":"Yakın dur.","origin":"pack"},
  {"id":11,"date":"2026-11-22T21:13:58Z","source":"Who's there?","translation":"Kim var orada?","origin":"engine"}]}
```

| Alan | Tip | Not |
|---|---|---|
| `version` | Int | Şu an 1. Değerine bakılmaz ama **anahtar bulunmalıdır**; yoksa dosyanın tamamı açılmaz |
| `entries` | Dizi | **En yenisi başta**. Anahtar bulunmalıdır; her kaydın bütün alanları zorunludur |
| `id` | Int | Artan sayı; açılışta sonraki kimlik = en büyük kimlik + 1 |
| `date` | ISO 8601 (saniyeli, `Z`) | |
| `source`, `translation` | String | En çok 500 karakter |
| `origin` | `pack` / `engine` | Bilinmeyen değer: **dosyanın tamamı açılmaz** (boş geçmiş) |

Dosya yoksa ya da bozuksa geçmiş boş başlar (hata gösterilmez). İlk 200 kayıt alınır. Yazma: her değişiklikte arka
planda, yerine koyarak (atomik). Windows'taki geçmişle aynı biçimdir.

### 5.4 Paket dosyaları

Paket (gzip'li ya da düz JSON):

```json
{"format":1,"id":"elden-ring","title":"Elden Ring","entries":{"3f2a9c0d1e4b5a67":"Yakın dur."}}
```

Örnekteki anahtar uydurmadır. Anahtar, İngilizce satırın sadeleştirilmiş hâlinin SHA-256'sının ilk 8 baytıdır (16 küçük
onaltılık); gerçek giriş/çıkış örnekleri `core/Tests/NinoAppCoreTests/Fixtures/golden-vectors.json` dosyasındadır
(Windows ile ortak), testler oradan beslenmelidir. Sadeleştirme:
`<…>` etiketleri (en çok 40 karakter) boşluk olur → NFKC → küçük harf → NFD ile işaretler atılır → harf/rakam dışı
boşluk → boşluklar teklenir ve kırpılır. Paketlerde İngilizce metin yoktur.

`Packs/manifest.json`:

```json
{"packs":[{"id":"elden-ring","title":"Elden Ring","version":"7","sha256":"<64 hex>","size":120345,"entries":5400}]}
```

`version` sayı ya da metin olabilir; `title` yoksa kimlik; `size`/`entries` isteğe bağlı.

Uygulamayla gelen paketler uygulama paketinin içindedir (`packs` kaynak klasörü); taşınmaz. Okuma önceliği:
uygulamayla gelen < sunucudan inen (aynı kimlik öncekinin yerine geçer) < içe aktarılan.

### 5.5 `sorunlar.json` kaydı

```json
[{"id":"0B8E4C2A-5D61-4F3B-9A7E-2C1D0E9F8A11","date":"2026-11-22T21:10:00Z","kind":"ps5Dropped","reason":"network","streamedMinutes":12.5,
  "lossPerMinute":0.4,"stallsPerMinute":0,"network":"wifi","game":"GTA VI"}]
```

`kind`: `ps5Dropped`, `ps5Unreachable`, `networkLost`, `tvDropped`.

### 5.6 Günlükler (`Library/Logs/Nino/`)

| Dosya | Durum |
|---|---|
| `remoteplay.log` | Açılışta etkinleştirilir (testlerde ve deneme karesinde değil). 1 MB'yi geçince eski yarısı silinir. Satır biçimi `yyyy-MM-dd HH:mm:ss metin` |
| `altyazi.log` | Çekirdekte var ama **iOS uygulaması etkinleştirmiyor**; iOS'ta yazılmaz |

Günlükler taşınmak zorunda değildir.

---

## 6. Yeni uygulama için kontrol listesi

1. Anahtar Zinciri: aynı hizmet adı, aynı hesap adları, değerleri JSON olarak oku/yaz; eski hizmetten anahtar başına
   tembel taşıma.
2. UserDefaults: 2. bölümdeki anahtarları aynı adlarla oku; `settings`'i Data olarak, 4. bölümdeki kurallarla aç.
3. Ayarları açarken Z/H ayrımını koru (yoksa eski kullanıcının ayarı ya sıfırlanır ya da bozuk açılır).
4. Klasör: `Application Support/Nino` ve `Library/Logs/Nino`; eski klasör taşıma tablosu.
5. Taşınması gerekenler: `history.json`, `Packs/imported/`, `pool/state.json` (kuruluş kimliği),
   `translations/install`, `Glossary/`, `tv/` altındaki anahtarlar.
6. Testler: bu belgedeki örnek JSON'larla "açılınca şu değer" testleri; bayt karşılaştırması yapma.
