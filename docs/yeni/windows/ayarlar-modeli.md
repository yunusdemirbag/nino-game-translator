# Windows: ayar modeli (`settings.json`)

Bu belge eski Windows uygulamasının kalıcı ayar dosyasını alan alan anlatır. Yeni uygulama bu dosyayı **aynı adla,
aynı alan adlarıyla ve aynı değer yazımlarıyla** okuyup yazmalı: kullanıcı eski sürümden yeniye (ve gerekirse geri)
geçince ayarları kaybolmamalı. Dosyanın yeri ve öbür veri dosyaları `kimlikler-veri.md`'de.

Mac'ten en büyük fark: Mac'te alan adları küçük harfle başlar (`targetLanguage`), Windows'ta **büyük harfle** başlar
(`TargetLanguage`). Bazı enum'lar Windows'ta yazı, bazıları **sayı** olarak durur. İki biçim birbirine çevrilmez; her
uygulama kendi dosyasını okur.

## 1. Dosya

- Yol: `%LOCALAPPDATA%\Nino\settings.json` (veri klasörü taşınamadıysa eski klasörde aynı ad).
- İçerik: tek bir JSON nesnesi, tek satır (girintisiz), UTF-8, BOM yok.
- Alan adları: aşağıdaki tablodaki gibi büyük harfle başlar (PascalCase). Okurken **büyük/küçük harf duyarlıdır**:
  `output` gibi küçük harfle yazılmış alan tanınmaz, yok sayılır (varsayılan kalır).
- Türkçe ve öbür ASCII dışı harfler yazarken `ç` gibi kaçışla yazılır (okurken iki yazım da kabul edilir).
  `"`, `<`, `>`, `&`, `+`, `'` de kaçışla (`"` vb.) yazılır. Yeni uygulama kaçışsız da yazabilir; eski uygulama
  ikisini de okur.
- Bilinmeyen alanlar okurken yok sayılır.

## 2. Okuma kuralı (dosyadan)

1. Dosya **yoksa** (ilk açılış): bütün alanlar varsayılan, yalnız `TargetLanguage` Windows'un arayüz diline göre
   seçilir: dilin iki harflik kodu (Filipince "fil…" ise `tl`) desteklenen çeviri dillerinden biriyse o, değilse `tr`.
   Örnekler: `ar`→`ar`, `tr`→`tr`, `en`→`tr`, boş→`tr`, `vi`→`vi`, `fil`→`tl`, `fi`→`tr`.
2. Dosya varsa bütün nesne okunur. Eksik alan varsayılanını alır; fazladan alan yok sayılır.
3. Dosya okunamazsa (G/Ç hatası, izin) ya da JSON'da **herhangi bir** hata varsa (bozuk metin, bir alanın tipi yanlış,
   yazıyla tutulan bir enum'da tanınmayan ad, `AreaPreset: null` gibi boş değer) dosyanın **tamamı** yok sayılır ve
   bütün alanlar varsayılan olur. Bu durumda `TargetLanguage` sistem diline göre değil, düz `tr` olur. (Mac'ten farkı:
   Mac yalnız hatalı alanı varsayılana düşürür. Yeni Windows uygulaması da alan alan hoşgörülü okursa daha iyi olur;
   ama eski dosyaların hiçbirini kaybetmemek için en azından eskinin okuduğu her dosyayı aynı sonuçla okumalı.)
4. Sayıyla tutulan enum'larda tanımsız sayı da (ör. `FrameSource: 7`) hata vermeden okunur; o değer hiçbir seçime
   uymadığı için davranışta "PS5 değil" gibi tuhaflık yapar. Yeni uygulama tanımsız sayıyı varsayılana çevirmeli.
5. Yazıyla tutulan enum'lar okurken büyük/küçük harf duyarsızdır (`"computer"` → Computer) ve sayı da kabul eder.
6. `Hotkeys: null` okunursa liste "yok" olur; kısayol tablosu bunu "hepsi varsayılan" sayar.

## 3. Açılışta denetleyicinin yaptığı düzeltmeler (okuduktan hemen sonra)

Sırayla:

1. **Model listesi:** `GeminiModel`, `OpenAiModel`, `ClaudeModel` gömülü model listesinde (`ai-models.json`, bkz.
   `kimlikler-veri.md` §9.4) yoksa o hizmetin listedeki **ilk** modeli olur. `LocalAiModel` kırpılır; boşsa
   `translategemma:4b` olur; dolu her ad olduğu gibi kalır. (Mac'teki "`qwen2.5:7b` → `translategemma:4b`" geçişi
   Windows'ta **yok**.)
2. **İşlemci iş parçacığı:** `CpuTranslationThreads` bu bilgisayara göre düzeltilir (§5).
3. **Çıktı:** `Output` = `Both` ve `VideoSource` ≠ `Card` ise `Tv` yapılır. (Kart yolunda "ikisi de" anlamlıdır:
   oyun bu bilgisayarda da gösterilir; korunur.) `Computer` ("TV'm yok") korunur.
4. Bu düzeltmelerden biri değer değiştirdiyse dosya **hemen** yeniden yazılır.
5. Ardından seçili işlemci sayısı ve çeviri aygıtı (CPU/GPU) yerel çeviri motoruna bildirilir.

## 4. Yazma kuralı

- Ayar her değiştiğinde (ayarlar ekranı, Num 7, pencere taşınması…) bütün nesne baştan yazılır. Sıra:
  1. `CpuTranslationThreads` yeniden düzeltilir (§5).
  2. İki görüntü kaynağı ayarı tek seçim gibi davranır: `FrameSource` değişip PS5 dışı bir şey olduysa ve `VideoSource` da PS5
     dışıysa `VideoSource` = `Ps5` yapılır; tersine `VideoSource` değişip PS5 dışı olduysa ve `FrameSource` PS5 dışıysa
     `FrameSource` = `Ps5` yapılır.
  3. `VideoSource` PS5'e döndüyse ve `FrameSource` da PS5 ise ve `Output` ≠ `Tv` ise `Output` = `Tv` yapılır.
  4. Değer öncekinin aynısıysa hiçbir şey yapılmaz. Değilse dosyaya yazılır, TV'ye güncel altyazı stili gönderilir,
     çıktı değiştiyse çıktıya bağlı işler yenilenir.
- Dosya doğrudan üzerine yazılır (geçici dosya kullanılmaz). Yazılamazsa (antivirüs ya da eşitleme kilidi) ayar
  bellekte geçerli kalır, hata `hata.log`'a "Ayarlar kaydedilemedi" diye yazılır, iş yarıda kalmaz; bir sonraki kayıt
  yeniden dener. Yeni uygulama yazarken geçici dosya + yer değiştirme kullanabilir (daha güvenli), ad aynı kalmalı.
- Klasör yoksa önce oluşturulur.

## 5. İşlemci iş parçacığı seçenekleri

- Sunulan seçimler: 2, 4, 8, 12; bunlardan bilgisayarın mantıksal işlemci sayısını aşmayanlar. Mantıksal işlemci 2'den
  azsa tek seçim 1.
- Düzeltme: sunulanlar içinde istenen değere eşit ya da küçük olanların en büyüğü; hiçbiri yoksa sunulanların ilki.
- "Kapasiteye yakın" uyarısı: seçilen × 4 ≥ mantıksal işlemci × 3.
- Örnekler (mantıksal işlemci → seçenekler; istenen → sonuç):

| İşlemci | Seçenekler | 1→ | 2→ | 12→ | 0→ |
|---|---|---|---|---|---|
| 1 | 1 | 1 | 1 | 1 | 1 |
| 2, 3 | 2 | 2 | 2 | 2 | 2 |
| 4, 6 | 2, 4 | 2 | 2 | 4 | 2 |
| 8 | 2, 4, 8 | 2 | 2 | 8 | 2 |
| 12, 16, 20, 32 | 2, 4, 8, 12 | 2 | 2 | 12 | 2 |

  Ek: (8 işlemci, 12 istendi) → 8; (20 işlemci, 8 istendi) → 8. Kapasite: (8 seçili, 8 işlemci) yakın; (12, 20) değil.

## 6. Alanlar

Sıra, eski uygulamanın yazdığı sıradır (okurken önemsiz). "Yazım" sütunu dosyadaki değer biçimidir.

| Alan | Tip / yazım | Olası değerler | Varsayılan | Anlam |
|---|---|---|---|---|
| `Region` | Bölge nesnesi (§7) | | üst 0.62, alt 0.97, sol 0.14, sağ 0.86 | Altyazının okunduğu bölge |
| `AreaPreset` | yazı | `Bottom`, `Top`, `Full`, `Custom` | Dosyada yoksa `Region`'dan çıkarılır (§7) | Bölgenin hazır seçimi. Her yazımda dosyaya konur. `null` yazılırsa dosyanın tamamı bozuk sayılır |
| `ExtraRegion1`, `ExtraRegion2`, `ExtraRegion3` | Bölge nesnesi ya da `null` | | `null` (kapalı) | Ek bölgeler (görev paneli, bilgi kutusu, ekran ortası). Kısayolla bir kez okunup çevrilir |
| `ExtraTarget1..3` | **sayı** | 0 = TV, 1 = bilgisayar, 2 = ikisi de | 0 | Ek bölge çevirisinin gösterileceği yer |
| `ExtraLive1..3` | Bool | | `false` | Ek bölge tuşa basmadan sürekli (saniyede bir) okunsun. Sürekli okunan bölgenin kimliği `area1`/`area2`/`area3`, adı `Area 1`… |
| `FreeAreaTarget` | **sayı** | 0/1/2 (yukarıdaki gibi) | 0 | `FreeArea` kısayolunun (Num 5) çevirisinin sonucu nerede |
| `Style` | Stil nesnesi (§8) | | | TV'deki altyazı görünümü |
| `MisreadWaitMs` | tam sayı (ms) | Ayarlar 0–2 sn kaydırıcısı (saniye × 1000, yuvarlanır); kullanılırken 0–2000'e sıkıştırılır | 800 | Gelişmiş: bozuk okunan satır daha iyi okuma için en çok bu kadar bekletilir (0: beklenmez) |
| `PartialWaitMs` | tam sayı (ms) | aynı | 300 | Gelişmiş: kısmen görünen satırın bütünü için azami bekleme |
| `SourceLanguage` | yazı | pratikte `en` | `en` | Oyunun dili |
| `TargetLanguage` | yazı | `tr`, `ar`, `hi`, `id`, `th`, `vi`, `ur`, `bn`, `ms`, `tl`, `nl` | §2 | Çeviri dili. Filipince `tl` |
| `TranslationDevice` | yazı | `Cpu`, `Gpu` | `Cpu` | Ücretsiz yerel çevirinin aygıtı. GPU yalnız NVIDIA CUDA |
| `CpuTranslationThreads` | tam sayı | §5 | 2 | Yerel çevirinin işlemci iş parçacığı sayısı |
| `FastSubtitleDetection` | Bool | | `false` | Değişmeyen altyazı bölgesinde tam okumayı en çok iki kare yeniden kullan |
| `OnlineTranslation` | Bool | | `false` | Açıksa `OnlineEngine` kullanılır (anahtarı kayıtlıysa) |
| `OnlineEngine` | yazı | `Free`, `DeepL`, `Gemini`, `OpenAi`, `Claude`, `Local` | `DeepL` | Seçili çevrimiçi motor. Seçili motor = `OnlineTranslation` açık ve bu alan `Free` değilse bu alan, yoksa ücretsiz motor. "Ücretsiz"e geçmek yalnız `OnlineTranslation`'ı kapatır, bu alana dokunmaz |
| `GeminiModel` | yazı | `gemini-3.5-flash-lite`, `gemini-3.6-flash` | `gemini-3.5-flash-lite` | §3.1 |
| `OpenAiModel` | yazı | `gpt-6-luna`, `gpt-6.1-terra` | `gpt-6-luna` | Mac'teki adı `openAIModel`; Windows'ta `OpenAiModel` |
| `ClaudeModel` | yazı | `claude-haiku-5-5`, `claude-sonnet-5-5` | `claude-haiku-5-5` | |
| `LocalAiBaseUrl` | yazı (adres) | Ollama `http://localhost:11434/v1`, LM Studio `http://localhost:1234/v1`, ya da kullanıcının yazdığı | Ollama adresi | Yerel model sunucusu. Adres geçersizse yerel sunucu "yok" sayılır |
| `LocalAiModel` | yazı | serbest | `translategemma:4b` | §3.1 |
| `Output` | yazı | `Tv`, `Computer`, `Both` | `Tv` | Altyazı nerede. Kullanıcı seçmez; "TV'm yok" seçildiyse `Computer`. `Both` §3.3 |
| `OverlayClickThrough` | Bool | | `false` | Bilgisayardaki altyazı penceresi tıklamayı alttaki pencereye geçirir (Num 7 açıp kapatır) |
| `VideoSource` | yazı | `Ps5`, `Window`, `Card` | `Ps5` | Görüntü nereden gelir: PS5'e doğrudan / bu bilgisayardaki oyun penceresi / HDMI yakalama kartı |
| `GameConsole` | yazı | `Ps5`, `Xbox` | `Ps5` | Pencere yolunda hangi pencerenin aranacağı |
| `Overlay` | nesne ya da `null` | `{"Left": sayı, "Top": sayı, "Width": sayı}` (WPF birimi, bütün ekranları kapsayan düzlemde) | `null` (ana ekranın altında ortada açılır) | Bilgisayardaki altyazı penceresinin son yeri ve genişliği; pencere taşınınca/genişletilince yazılır |
| `GamePacks` | Bool | | `true` | Paketlerdeki hazır Türkçe kullanılsın (yalnız İngilizce→Türkçe) |
| `SharePool` | Bool | | `true` | Pakette olmayan İngilizce satırlar paylaşılan havuza yollansın, havuz çevirileri kullanılsın |
| `AutoReport` | Bool | | `true` | PS5 kopması, ağ gitmesi gibi sorunlar kendiliğinden bildirilsin (yalnız özet) |
| `Appearance` | yazı | `Dark`, `Light`, `System` | `System` | Pencere görünümü |
| `HomeStyle` | yazı | `LivingRoom`, `Toggle` | `LivingRoom` | Ana ekran: salon sahnesi ya da cam anahtar |
| `AskGame` | Bool | | `true` | Oyun paketten anlaşılamazsa çevirinin başlamasından iki dakika geçince tek sefer sorulsun |
| `ShowSpeakerNames` | Bool | | `true` | Konuşan adı ("ARTHUR: …") çeviride kalsın |
| `FrameSource` | **sayı** | 0 = PS5, 1 = Remote Play penceresi, 2 = seçilen pencere (OBS projektörü vb.) | 0 | Eski görüntü kaynağı seçimi; §4'teki kuralla `VideoSource`'la birlikte tek seçim gibi davranır. 1 ya da 2 ise (ve konsol Xbox değilse) kurulum PS5 eşleşmesi olmadan "bitti" sayılır |
| `XboxLegacyFrameRate` | Bool | | `false` | Xbox karelerini eski 200 ms aralıkla al (varsayılan 66 ms) |
| `CaptureWindow` | nesne ya da `null` | `{"ProcessName": yazı, "Title": yazı}` | `null` | Açıkça seçilen pencere. Süreç kimliği/tutamağı saklanmaz; ikisi de eşleşmeli; bulunamazsa başka kaynağa geçilmez |
| `RemotePlayApp` | **sayı** | 0 = otomatik, 1 = Sony PS Remote Play, 2 = chiaki-ng | 0 | Pencereden okurken hangi Remote Play uygulaması |
| `Hotkeys` | dizi (§9) | | `[]` | Yalnız varsayılandan farklı kısayollar |

Dosyada **olmayan**, hesaplanan değerler (yazılmaz): seçili motor, yerel sunucu nesnesi, stilin "oyun boyuna uy"
sonucu.

Mac'te olup Windows ayar dosyasında **olmayan** alanlar: `extraAreas` (Windows'ta üç sabit ek bölge alanı var),
`translateCorners`, `xboxAudioOnDevice`, `style.theme`, `dubbing`.

### Varsayılanlarla yazılmış dosya (eski uygulamanın ilk kaydı, okunaklı olsun diye girintili)

```json
{
  "Region": {"Top": 0.62, "Bottom": 0.97, "Left": 0.14, "Right": 0.86},
  "AreaPreset": "Bottom",
  "ExtraRegion1": null, "ExtraRegion2": null, "ExtraRegion3": null,
  "ExtraTarget1": 0, "ExtraTarget2": 0, "ExtraTarget3": 0,
  "ExtraLive1": false, "ExtraLive2": false, "ExtraLive3": false,
  "FreeAreaTarget": 0,
  "Style": {"FontSize": 46, "BottomPercent": 7, "Placement": "Cover", "Background": 100, "Bold": false,
            "TextColor": "White", "DisplayMode": "InApp", "StackPrevious": true, "BackgroundShape": "Fit",
            "Font": "Condensed", "Watermark": true, "AutoSize": null},
  "MisreadWaitMs": 800, "PartialWaitMs": 300,
  "SourceLanguage": "en", "TargetLanguage": "tr",
  "TranslationDevice": "Cpu", "CpuTranslationThreads": 2, "FastSubtitleDetection": false,
  "OnlineTranslation": false, "OnlineEngine": "DeepL",
  "GeminiModel": "gemini-3.5-flash-lite", "OpenAiModel": "gpt-6-luna", "ClaudeModel": "claude-haiku-5-5",
  "LocalAiBaseUrl": "http://localhost:11434/v1", "LocalAiModel": "translategemma:4b",
  "Output": "Tv", "OverlayClickThrough": false, "VideoSource": "Ps5", "GameConsole": "Ps5", "Overlay": null,
  "GamePacks": true, "SharePool": true, "AutoReport": true, "Appearance": "System", "HomeStyle": "LivingRoom",
  "AskGame": true, "ShowSpeakerNames": true, "FrameSource": 0, "XboxLegacyFrameRate": false,
  "CaptureWindow": null, "RemotePlayApp": 0, "Hotkeys": []
}
```

Dolu örnek parçalar (eski uygulamanın gerçek yazımı): `"ExtraRegion1":{"Top":0.1,"Bottom":0.2,"Left":0.3,"Right":0.4}`,
`"ExtraTarget1":2`, `"Overlay":{"Left":1,"Top":2,"Width":3}`, `"FrameSource":2`,
`"CaptureWindow":{"ProcessName":"obs64","Title":"Projector"}`, `"RemotePlayApp":2`,
`"Hotkeys":[{"Action":"Screen","Slot":1,"Key":{"Modifiers":"Alt, Control","VirtualKey":65}},{"Action":"FreeArea","Slot":0,"Key":null}]`.

## 7. Bölge ve hazır seçimler

- Bölge nesnesi: `{"Top", "Bottom", "Left", "Right"}`, hepsi 0–1 arası ondalık; karenin üstünden ve solundan oran.
  Varsayılan (0.62, 0.97, 0.14, 0.86). Nesnede eksik kenar varsayılanını alır.
- Hazır seçimler (üst, alt, sol, sağ): `Bottom` (0.62, 0.97, 0.14, 0.86), `Top` (0.03, 0.38, 0.14, 0.86),
  `Full` (0, 1, 0, 1), `Custom` (kayıtlı bölge kalır).
- `AreaPreset` dosyada yoksa: bölge bir hazır seçimle her kenarda 0.001 payla aynıysa o seçim, değilse `Custom`.
  Örnek: yalnız `{"Region":{"Top":0.03,"Bottom":0.38,"Left":0.14,"Right":0.86}}` olan eski dosya → `Top`.
- Hazır seçim uygulanınca bölge seçimin bölgesi olur (`Custom`'da kayıtlı bölge kalır). Bölge elle değişince (kaydırıcı
  ya da çerçeve) seçim `Custom` olur.
- "Dikey konum / yükseklik" kaydırıcıları: konum = üst × 100, yükseklik = (alt − üst) × 100. Yeni değer verilirken
  yükseklik en az %5, en çok %100; üst 0 ile (1 − yükseklik) arasına sıkıştırılır (gerekirse bölge yukarı kayar); sol
  ve sağa dokunulmaz.
- Ek bölge hazır seçimleri (sürekli okumada önerilen yerler): görev (0.03, 0.30, 0.66, 0.98), bildirim
  (0.58, 0.88, 0.02, 0.30), telefon (0.50, 0.95, 0.72, 0.98).

## 8. Altyazı stili (`Style`)

| Alan | Yazım | Değerler | Varsayılan |
|---|---|---|---|
| `FontSize` | tam sayı | arayüz 36 / 46 / 58 / 72 sunar; her tam sayı okunur | 46 |
| `BottomPercent` | tam sayı | sabit yerleşimde alttan uzaklık, % | 7 |
| `Placement` | yazı | `Cover` (İngilizcenin üstünü örter), `Above`, `Below`, `Fixed` | `Cover` |
| `Background` | tam sayı | 0–100 zemin koyuluğu (0: zemin yok) | 100 |
| `Bold` | Bool | | `false` |
| `TextColor` | yazı | `White`, `Yellow` | `White` |
| `DisplayMode` | yazı | `InApp`, `Overlay` (yalnız Android TV kullanır) | `InApp` |
| `StackPrevious` | Bool | önceki satır kısa süre soluk kalsın | `true` |
| `BackgroundShape` | yazı | `Fit`, `Band` | `Fit` |
| `Font` | yazı | `Condensed`, `Modern`, `Rounded`, `System` | `Condensed` |
| `Watermark` | Bool | TV'nin sol altındaki Nino işareti | `true` |
| `AutoSize` | Bool ya da `null` | TV yazı boyunu oyunun altyazısına uydursun | `null` |

- `AutoSize` `null` ise (eski kayıt): `FontSize` 46 ise "uydur" açık, değilse kapalı sayılır. Örnek: yalnız
  `{"Style":{"FontSize":30}}` → öbür alanlar varsayılan, uydurma kapalı.
- TV'ye giderken yazı tipi küçük harfle gider (`condensed`); TV mesaj biçimi TV bağlantısı tarifinde.
- Mac'teki "cover + zemin < 60 → 100" düzeltmesi Windows'ta yok.

## 9. Kısayollar (`Hotkeys`)

Her işin iki yuvası (tuşu) vardır: yuva 0 sayı tuş takımı (Num), yuva 1 Ctrl+Shift+üst sıra rakamı.

| İş (dosyadaki ad) | Rakam | Ne yapar |
|---|---|---|
| `ExtraRegion1` | 1 | Birinci ek bölgeyi tek seferlik okuyup çevirir |
| `ExtraRegion2` | 2 | 2. ek bölge |
| `ExtraRegion3` | 3 | 3. ek bölge |
| `FreeArea` | 5 | Görüntüyü dondur, serbest alan seçtir |
| `Snapshot` | 8 | Ayar ekranındaki resmi oyunun güncel karesiyle değiştir |
| `PauseSubtitles` | 0 | Sürekli altyazı çevirisini duraklat / sürdür |
| `Screen` | 9 | Ekranın bütününü tek sefer çevir; ikinci basış çevirileri kaldırır |
| `ClickThrough` | 7 | `OverlayClickThrough` ayarını tersine çevirir (pencere tıklamayı alttakine geçirsin mi) |

- Varsayılan tuş: yuva 0 → değiştiricisiz, sanal tuş kodu 0x60 + rakam (Num 0–9); yuva 1 → Ctrl+Shift, sanal tuş
  0x30 + rakam.
- **Tablo sırası** (tutma sırası ve kimlik sırası): önce bütün yuva 0'lar, sonra bütün yuva 1'ler; her yuvada iş sırası
  1, 2, 3, 5, 8, 0, 9, 7 (yukarıdaki tablo sırası).
- Dosyadaki öğe: `{"Action": iş adı (yazı), "Slot": 0|1, "Key": {"Modifiers": yazı, "VirtualKey": sayı} | null}`.
  `Key: null` o yuvanın kapatıldığı demektir. `Modifiers` bayraklı enum'un yazımıdır: `None`, `Alt`, `Control`,
  `Shift` ya da virgül+boşlukla birleşik (`"Alt, Control"`, `"Control, Shift"`). Değerleri Win32 ile aynı: Alt 1,
  Control 2, Shift 4.
- Dosyada **yalnız varsayılandan farklı** yuvalar durur; dosyada yoksa (eski kayıt) hepsi varsayılan.
- Bir yuvanın tuşu: aynı iş+yuva için listedeki **son** öğe; öğe yoksa varsayılan.
- **Çözümleme** (tutulacak kısayollar): tablo sırasıyla her yuvanın tuşu alınır; tuş kapalıysa, geçersizse (§9.1) ya da
  daha önce başka bir yuvaya verildiyse atlanır.
- **Atama** (Ayarlar'da tuş seçme): bütün iş×yuva tuşları çıkarılır, seçilen yuvaya yeni tuş (ya da kapalı) konur; yeni
  tuş başka bir yuvada da varsa o yuva kapatılır; başka işten alındıysa "yerinden edilen iş" bildirilir. Sonuçta
  varsayılandan farklı olan yuvalar listesi döner (dosyaya o yazılır).
- Ekrandaki ad: "Ctrl", "Alt", "Shift" (bu sırayla, olanlar) + tuşun adı, `+` ile: "Ctrl+Shift+9", "Alt+F2", "Num 9".
  Adı olmayan tuş "0xNN".

### 9.1 Tuş geçerliliği

Tuş adları (adı olmayan tuş kısayol olamaz): rakamlar 0x30–0x39 ("0".."9"), harfler 0x41–0x5A ("A".."Z"), Num 0–9
(0x60–0x69, "Num 0".."Num 9"), 0x6A "Num *", 0x6B "Num +", 0x6D "Num -", 0x6E "Num .", 0x6F "Num /",
F1–F24 (0x70–0x87, "F1".."F24") **F12 (0x7B) hariç** (hata ayıklayıcıya ayrılmış), 0x13 "Pause", 0x91 "Scroll Lock",
0x2D "Insert", 0x24 "Home", 0x23 "End", 0x21 "Page Up", 0x22 "Page Down", oklar 0x25 "←", 0x26 "↑", 0x27 "→", 0x28 "↓".

Kural sırası:
1. Adı yoksa → "desteklenmeyen tuş".
2. Ctrl ve Alt birlikteyse → "AltGr" (Türkçe Q ve çoğu Avrupa klavyesinde AltGr = Ctrl+Alt; #, $, {, [ yazdırmaz olur).
3. Alt + F4 → "Windows'un kendi işi".
4. Tek başına olabilen tuşlar (sayı tuş takımı 0x60–0x6F, F tuşları 0x70–0x87, Pause, Scroll Lock) → geçerli.
5. Öbürleri (harf, rakam, ok, gezinme) yalnız Ctrl+Shift, Alt ya da Alt+Shift ile geçerli; değilse "değiştirici gerek".

Örnekler: Num 9 geçerli; F2 geçerli; F12 desteklenmez; Esc (0x1B) desteklenmez; T değiştirici gerek; Shift+T değiştirici
gerek; Ctrl+C değiştirici gerek; Alt+T, Alt+Shift+T, Ctrl+Shift+T geçerli; Ctrl+Alt+3 AltGr; Alt+F4 ayrılmış.
Çözümleme örneği: `[Screen yuva 1 = A (değiştiricisiz), FreeArea yuva 1 = Num 9]` → A geçersiz olduğu için atlanır;
Num 9 zaten Screen'in yuva 0'ına verildiği için FreeArea'nın yuva 1'i atlanır; hiçbir tuş iki kez tutulmaz.
Gidiş-dönüş örneği: Screen yuva 0 = Alt+Shift+S, Screen yuva 1 kapalı → dosyada `"Screen"` adı geçer, geri okununca
Screen'in tek çalışan tuşu Alt+Shift+S.

Kısayolların sisteme nasıl tutturulduğu `kimlikler-veri.md` §12'de.
