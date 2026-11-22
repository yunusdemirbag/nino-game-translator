# Telefon paneli ve harita kartı

Kod: `Sources/NinoCore/Phone/`. Türler `GameReading` adının altındadır. Sayılar Mac'inkidir
(ortak eski kopyadan farklı olanlar `PhoneWatcher.Settings` ve `MapCardPresenter` içinde ayarlanabilir).

```
kare ─┬─ PhoneWatcher.round  (0,6 / 1,0 sn, yalnız işlemci OCR) → telefon ekranı → hafıza/çeviri → balonlar
      ├─ PhoneWatcher.context (Reader'a: telefon kutusu, son yazılar, uygulama yazısı)
      └─ köşe turu menü araması → oyun tanıma + MapCardWatcher → harita kartı
                                          ↘ ElementsBoard (.phone, .map)
```

## 1. Ne zaman

- "Köşeleri çevir" açık ve kaynak dil `en` olmalı; oyun **havuz öncelikli** olmalı (bugün GTA 6).
- Oyun kesin biliniyorsa (PS5, kullanıcı, ekran) o oyunun durumu; yalnız paketten tahminse oyun
  ya da hedef dil havuz öncelikliyse; hiç bilinmiyorsa son oturumdaki oyun ya da hedef dil.
- Okuma aralığı: panel yokken 600 ms, varken 1 000 ms; okuma sürerken yenisi başlamaz.
- Menü/harita bayrağı son 8 sn'de açıktıysa ya da harita kartı ekrandaysa telefon aranmaz, panel kalkar.

## 2. Oyunu ekrandan tanıma

Menü aramasının satırlarında (simge kırıntısı atılmış, küçük harf): harita ekranı; bir satırda
`jason` ve `lucia`; `brief` + `progress` + (`jason`/`lucia` ya da satır `map`); satır `whatup`.
Telefonda sohbet/uygulama okunursa da GTA 6. PS5'in ya da kullanıcının söylediği oyunu ezmez.

## 3. Telefonu bulma

Ekran dikey, açık, iki yanı koyu çerçeveli bir paralelkenardır (eğim = bir kare boyu inince sol
kenarın kayması; açı `atan(−eğim × 16/9)`).

1. **Açık ekran:** 240 × 135 kare; beyaz = `min ≥ 118`, `max − min ≤ 45`; koyu = `min < 90`.
   Satır şeritleri (≤ 3 noktalık yazı boşluğu bölmez, uçtaki ≤ 2 noktalık parlak kırıntı atılır),
   eğim oylaması (0 … ±0,30), en çok 16 aday; satır uyumu, parçalama, çerçeve, kenar uzatma,
   biçim `(yükseklik × 9)/(genişlik × 16)` 1,2–2,6, yer sınırları.
2. **Kararmış ekran:** ortadaki düşük değerlerin %95'lik dilimi 40–117 ise `225/dilim` ile açılıp yeniden.
3. **Koyu tema:** ekran `düşük + yayılma ≤ 75`, gövde `≥ 85`; giysi elemesi (parlak yazı noktaları).
4. **Şekil:** dikdörtgen bulucusu (yalnız panel; altyazı hattı kullanmaz) — ancak sohbet çıkarsa telefon.

**Takip:** bulunamazsa son bulunuştan 3 sn içinde ve aynı yerde aynı tür ekran (≥ %45) duruyorsa
telefon orada. **Yazılardan tahmin:** telefon uygulaması yazısı görülür de telefon yoksa (ya da
2 sn'den eskiyse) yer yazıların kutusundan çıkarılır.

**Renk:** kare bir kez 960 × 540; nokta rengi 3 × 3 ortalaması. Kararmış açık ekranda renkler
`238/ekran` ile aydınlatılır.

## 4–5. Okuma ve ekran türü

Telefon kutusu kesilip okunur. Harita tuşu okunursa panel kalkar.

- **Sohbet listesi / mesaj listesi:** çevrilmez.
- **Başlık:** en üst şeritte, ad gibi, ortalı, altında aynı girintide satır yok → **sohbet**.
- **Mesajlar:** aynı sıradaki parçalar birleşir, kesik ilk/son satır atılır, paragraf kuralı,
  durum satırları ve ek adları atılır, grup sohbetinde gönderen adı atılır.
- **Sohbet** = başlık + en az bir cümle. Değilse **uygulama satırları** (baştaki simge atılır,
  devam satırı birleşir, `By …` yazar satırı ayrı; hepsi BÜYÜK kısa etiketse telefon değil).

## 6. Kararlılık, hafıza, çeviri

- Okuma anahtarı mesaj anahtarı + `@` + `⌊(mesaj_üstü − ekran_üstü) × 60⌋`; aynıysa bir şey olmaz.
- Kaydırma, sohbet değişimi panelı hemen kaldırır; aynı mesajlar paneli yeniden kurmaz; yeni
  mesajlar ancak iki okumada görülünce güncellenir; bilinmeyen mesaj iki okumada aynı metinle
  görülmeden çeviriye gitmez (yalnız metne bakılır).
- Kesik son/ilk mesaj atılır; hafızadan bulma (≥ 5 sözcükte baş/son eşleşmesi).
- Türkçe sırası: telefon sözlüğü → havuz → kalıcı hafıza → oturum hafızası.
- Çeviri: bilinmeyenler havuza bildirilir; havuz tek istekte (bağlam önceki ≤ 4 mesaj); kalanlar
  cihazda en çok 2 aynı anda. Sonuç simge/HTML varlığı temizliği, tekrar sözcük teke iner.
  Her çeviri kalıcı hafızaya (en çok 5 000; aşılınca en eskiler silinir).
- **Hafıza dosyası:** `phone-memory-<dil>.json`, düz nesne `{"sadeleştirilmiş İngilizce": "çeviri"}`.

## 7. Altyazı hattına verilen

`PhoneWatcher.context` (`PhoneTracker`): telefon kutusu (5 sn tutulur, şekil yolu yok), son
yazılar, son 30 sn'de yazı, son 10 sn'de görüldü, telefon uygulaması yazısı tanıyıcısı.
Telefon oyunu kapalıysa `.none`.

## 8. Yerleşim

- **Balon rengi:** yazının solundaki iç paydan kenar, kutunun parlak %40'ından zemin; yazı rengi
  zemine göre. Çevirisi aslıyla aynıysa balon yok.
- **Sohbet paneli:** telefonun boş tarafında 0,27 genişlikte zemin + mesaj hizasında balonlar
  (giden sağa, gelen sola); en alttaki logo payını aşarsa hepsi yukarı kayar.
- **Uygulama balonları:** uygulamanın rengi (ya da beyaz uygulamada yazı rengi), ortak yazı boyu,
  telefona yaslı.
- **Kıpırdamama:** 0,05'ten az kayan telefonda eski yer; aynı yazının kutusu korunur; panel
  varken 100 ms'de bir yalnız yer bulunur, iki ölçüm aynı yöndeyse balonlar kaydırılır.

## 9. Harita kartı

- **Harita ekranı:** tuş satırlarından en az ikisi (`recenter`, `2d view` …). Menü sayılır.
  Tuş adının ardındaki kısa tuş simgesi okuması (`RECENTER L3`, `ADD MARKER C`) atılarak eşlenir.
- **Kart:** sağdaki cümle satırları, başlık (büyük harf, hemen üstte), üst şerit (görev adı: başlığın hemen üstünde,
  cümlelerle aynı solda, büyük harf; `header`, kimliğe girmez), hedef satırı; uzaklık etiketi ve simge kırıntıları
  atılır (satır başındaki uzaklık silinince sol kenar silinen karakter payı kadar kayar); başlığın solu ilk cümlenin
  solundan en çok 0,01 solda olabilir. Cümleler satır birleşimiyle kurulur.
- **Soldaki kart:** önce yalnız sağ taraf (satır x > 0,30) aranır (soldaki menü listesi `Declasse Yosemite 1500` cümle
  sanılmasın). Kart yoksa bütün ekran aranır, ama kart yalnız yapısıyla kabul edilir: büyük harfli başlık hemen üstte,
  her cümle nokta/ünlem/soruyla biter, en az 6 sözcük (duraklatma menüsü MAP sekmesindeki sol üst görev kartı
  `BREAKFAST RUN`, 23:49 karesi `breakfast-run-23-49.jpg`). Üst sekme şeridi (`JASON & LUCIA / MAP …`) karta girmez.
- **Çerçeve:** 640 × 360 karede koyu alan yazı kutusundan dışa doğru izlenir; bulunan kenar ilk açık örneğe kadar.
- **Gösterme:** Türkçe harfli, cümlesiz, başlıksız ve < 6 sözcüklü, PS5 bildirimi, sekme şeridi
  kartları gösterilmez; yarım okuma ekrandakini değiştirmez; hafıza 200 kart; çeviri sürerken yalnız
  en son kart bekler; sonuç anahtar ve menü bayrağı hâlâ aynıysa gösterilir.
- **Çeviri:** üst şerit + başlık + cümleler; havuz, sonra cihaz; başlık Türkçe büyük harf; terim düzeltmesi;
  mekân adı olan başlık çevrilmez; çevirmen değiştirmeden döndürdüğü başlık (özel ad) özgün büyük harfiyle kalır.
- **Yerleşim:** ~~kartın altında (yer yoksa üstünde)~~ — 22 Kasım'dan beri kartın koyu panelini tam ve 0,003 fazlasıyla
  örter (üst şerit + başlık + cümleler + alt satırlar; yer değiştirmez). Panel kenarı görüntüden bulunamazsa yazı
  kutusu her yandan 0,6 satır paylı. Görüntü çerçevesi yazı kutusunu solda en çok 0,014, üstte 0,02, sağda/altta
  0,035 aşar. Yazı küçülmez: sığmazsa kutu aşağı uzar (yalnız ekran altına varınca satır küçülür). Öğe "kart" biçiminde.
- **Kart değişimi:** başka başlıklı kart gelince eski kart çeviri beklenmeden kalkar: `MapCardWatcher.see` hemen
  `.remove` ve `switched` verir (Mac göndericiye `drop: [.map]` der, histerezis tutmaz), çeviriyi `finish` yapar.
  "3 kez görme" yalnız aynı kartın (başlık ve yeri aynı) farklı okumasına uygulanır.

## 10. Telefon araması

`Cards.call` + `Cards.layout(call)` (`okuma-hatti` §14): `Ad aranıyor…` kartın üstünde, sade,
eğik. `CallPresenter` her karede arama kartını izler; durum boşsa ya da 3 sn görülmezse kalkar.

## 11. GTA 6'ya özel kurallar

Yalnız telefon oyununda: telefon paneli; altyazıda telefon maskesi ve telefon süzgeçleri; mesaj
köşesi kart; ortadan 0,12 uzak altyazı yok; küçük harfli blok yok; mesaj listesi/arama kartı yok;
`gta-6` yer anahtarı, görev çizgisi ≤ 0,935, taban çizgisi; görev şeridinde pembe vurgu;
`A e DRINKS` ve balık ipuçları; menü sekmesi, harita ekranı ve kartı; ekrandan tanıma; telefon
uygulamaları (WhatUp, Ryde/Rydeme, BuckMe, Vice City Horn, Leonida Journal, fitness).
Liste `GameReading.GTA6Rules.all` içindedir.

## Tariften sapmalar

- Hafıza sınırı aşılınca hangi kayıtların silineceği yazılı değildi: en eski eklenenler silinir
  (dosyadan yüklenenler ad sırasıyla en eski sayılır).
- Telefon uygulaması yazısında "sözlükte tam var" kuralı da en az 2 sözcük ister (`Focus`, `Cost` tek başına sayılmaz).
- Cihaz çevirisi "aynı anda en çok 2": ikişerli gruplar hâlinde (kayan pencere değil).
- Harita kartının gerçek kareleri: `Tests/NinoCoreTests/Resources/gta6-map/` (GTA 6, 1280 genişlik;
  PAY 'N' SPRAY → WHS → AVERY PAWN). Gerçek Vision ile okunur; kart TV'de kesintisiz kalmalı.
- Kartın TV'den kalkması `ScreenItemSender` histerezisiyle (oyun-okuma.md §11–14): izleyici kartı
  tek okumada bırakabilir, TV'deki öğe 3 kaçırma + 4 sn + bölge değişimi olmadan kalkmaz.
- Harita kartı yalnız telefon oyununda ve harita tuşları son 10 sn'de görüldüyse aranır ("harita ekranında").
- Harita kartı: hafızadan gösterilen kart süren çevirinin sonucunu geçersiz kılar (sonuç gösterilmez).
- `ElementsBoard.list` türü ada göre sıralar (`map` `phone`'dan önce); TV sırası tarifte
  telefon → harita idi. Sıra değiştirilmedi.
- Görev şeridindeki pembe vurgu (§10 madde 8): `GameReading.Accent` satır kutusundaki pembe sütunlardan vurgulu
  sözcüğü bulur; çeviride karşılığı vurgulu ifadenin ayrı çevirisiyle kök eşlemesiyle (`liman` ~ `Limanlara`) aranır ve
  `⟦…⟧` ile işaretlenir (protokol.md "screen"); bulunmazsa vurgusuz. Cümleyi işaretli (`[[docks]]`) çevirtmek
  denenmedi: çeviri paket/havuz/önbellekten metinle geçer, işaretli metin havuzu ve önbelleği kirletirdi.
- Harita kartının alt satırları (`FEATURES`, `SECURITY … LOW`, `TAKE VALUE … $100 - $1,000`) karta dahildir ve çevrilir
  (etiket ve harfli değer; rakamlı değer olduğu gibi). Satır `GÜVENLİK: DÜŞÜK` biçiminde yazılır.
- Haritadaki büyük yer adı (`Port Gellhorn`) okumada ilk cümle satırına yapışabilir; satır başlıktan belirgin solda
  başlıyorsa baştaki büyük harfli sözcükler (en çok 3) atılır. Aynı kartın (başlık ve yeri aynı) gösterilenden farklı,
  onu uzatmayan okuması ancak üst üste 3 kez görülünce yerine geçer (iki okuma arasında titreme).
- Gerçek kare: `Tests/NinoCoreTests/Resources/gta6-map/liquor-14-18-08.jpg` (UNCLE JACK'S LIQUOR, "Go to the docks").
- Gerçek kareler: `moses-declasse-22-56.jpg`, `moses-karin-22-56.jpg` (Robberies › Steal Vehicles for Moses; pinin
  `1.62 km` yazısı başlığa yapışıyordu). Karelerde hata ayıklama sürümünün cyan okuma kutusu çizili.
- Şekil yolu (`VisionRectangleDetector`) ve gerçek Vision okuması testsiz; çizilmiş karelerle yalnız §3.1, §3.3, §3.4 sınanır.

## Giriş noktası (Mac)

```swift
let tr: GameReading.PhoneTranslator = …          // havuz (known/askPool/report) + cihaz çevirmeni
let phone = GameReading.PhoneWatcher(textReader: GameReading.CPUTextReader(), clock: saat,
                                     memory: .init(directory: veriKlasörü, language: hedefDil),
                                     translator: tr, rectangles: GameReading.VisionRectangleDetector())
let karar = GameReading.PhoneGame.decide(cornersEnabled:…, sourceLanguage:…, targetLanguage:…,
                                         game: .certain(ps5Oyunu) / .packGuess(…) / .unknown,
                                         lastGameWasPoolPriority: kayıt)
var cfg = …; GameReading.GTA6Rules.apply(karar.on, packGame: paketOyunu, to: &cfg)
let reader = GameReading.Reader(textReader: guarded, clock: saat, configuration: cfg, phone: phone, …)
await phone.setPhoneGame(karar.on)
let harita = GameReading.MapCardWatcher(translator: tr, clock: saat)
_ = await harita.setPhoneGame(karar.on)
// karar değişince (ör. ekrandan GTA 6 tanındı): await reader.setPhoneGame(on, packGame:), phone/harita.setPhoneGame(on)
var oyun = GameReading.GameSense(reported: ps5Oyunu)

// ayrı görev, her kare:
if let u = await phone.round(kare) {
    if let els = u.elements { pano.removeAll(kind: .phone); els.forEach { pano.set($0) } }
    if u.phoneTextSeen, oyun.notePhoneRead() { /* görev çizgisini yeniden hesapla */ }
}
if let u = await phone.trackPhone(kare), let els = u.elements { pano.removeAll(kind: .phone); els.forEach { pano.set($0) } }

// köşe turundan sonra:
let ev = await reader.readCorners(kare)            // .menuOpened → await phone.noteMenu(at: saat.nowMs)
guard await reader.lastMenuSearchAt == saat.nowMs-yakın else { … }   // menü araması bu turda yapıldıysa
let satırlar = await reader.lastMenuSearchLines
// köşe satırlarında telefon uygulaması yazısı: await phone.noteLines(köşeSatırları, frame: kare)
if oyun.observeScreen(satırlar.map(\.text)) { /* oyun GTA 6: kararı yeniden ver */ }
let hızlı = await harita.see(satırlar, image: kare.image, menuOpen: await reader.menuOpen)
uygula(hızlı.changes)                                    // .set → pano.set(e); .remove → pano.remove(kind: .map, id: "kart")
if hızlı.switched, !pano.has(.map) { gönder(drop: [.map]) }   // eski kart hemen kalkar
uygula(await harita.finish())                            // çeviri (ya da tek adımda: harita.observe)
await phone.setMapCardShown(await harita.isShowing)
// mesaj kartı: CardPresenter.observe(kart, phoneSeenRecently: await phone.phoneSeen(withinMs: 10_000), now:)
// köşe ipucu: await phone.phoneBox(withinMs: 3_000) içindeki satırlar ipucu sayılmaz
// arama: Event.callCard(call) → CallPresenter.observe(call, now:) → .set / .remove (kind .callCard)
```
