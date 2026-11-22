# Oyun okuma hattı (zamanlı, zengin)

Kod: `Sources/NinoCore/GameReading/`. Bütün türler `GameReading` adının altındadır
(`GameReading.Reader`, `GameReading.Box` …), başka klasörlerle ad çakışmasın diye.

Bu hat, `Reading/` altındaki kare sayan hattın **yanında** durur; onu değiştirmez.
Farkı: süreler **milisaniye saatiyle** ölçülür, satırların kutuları korunur ve oyuna
özgü süzgeçler, öğrenilen altyazı yeri, köşe yazıları, ipuçları ve kartlar vardır.

```
kare → kapı → plan (iz) → OCR → süzgeç sırası → sabitleyici → bekletme → olay
                    ↘ ek alanlar, köşeler, ipuçları, kartlar → ekran öğeleri
```

## 0. Ortak

- **Kutu** (`Box`): sol, üst, sağ, alt; 0–1, sol üstten. Alan içi kutu kareye
  `kare = alan_sol + kutu × alan_genişliği` ile taşınır (üst/alt aynı yolla).
- **Saat** (`Clock`): ms. Gerçeği `SystemClock`, testlerde `ManualClock` elle ilerler.
- **Anahtar ve benzerlik:** NinoCore'un `TextSimilarity.key` ve oranı kullanılır. Eşik 0,85.
- **Cümle sonu:** sondaki `" ' ” ’ » ) ]` atıldıktan sonra son karakter `. ! ? …`.
- **Kare** (`Frame`): kesme ve iz alma yapabilen her şey. Gerçeği `ImageFrame` (CGImage),
  testler sahte kare kullanır. **Okuyucu** (`TextReader`) kareden bir alanı okur ve alan
  içi satır kutuları verir. Vision okuyucusu NinoCore'un `VisionTextRecognizer`'ını sarar.

## 1. Kapı

Aynı anda tek kare. Kapı doluysa yeni kare atlanır. Her giriş artan numara alır; yalnız
o numaranın çıkışı kapıyı açar. 45 000 ms'yi geçen okuma "takıldı" sayılır: kapı
sıfırlanır, eski numaranın geç çıkışı bir şeyi değiştirmez. Yedek okuyucu devredeyken
sınır 9 000 ms.

## 2. Bölge

Hazır seçimler: alt (0,62–0,97 / 0,14–0,86), üst (0,03–0,38), tam kare. Kayıt bir
hazır seçime 0,001 payla eşitse o seçimdir, değilse özel. En küçük boy 0,05; taşma
olmaz. Öğrenilen şerit varsa okuma üstü `şerit_üst − 0,05` (bölge üstünden büyük ve
bölge altından en az 0,06 yukarıdaysa).

## 3. Plan

İz 64 × 12 gri. Bir noktası 16'dan çok değişirse "değişti" (istenirse yalnız bir kutunun
hücreleri). İz aynıysa son okuma 20 kez (hızlı algılamada 2) yeniden kullanılır. Derin
okuma yalnız boş sayacı 3'e bölünürken istenir; dolu okuma sayacı 1 yapar.

Sabit görüntüde altyazı kaçmasın diye (yalnız altyazı satırı değişir, arka plan durur):

- İz bir önceki kareyle değil **son gerçek okumanın iziyle** karşılaştırılır (yavaş solma
  kare kare eşiğin altında kalsa da birikir).
- **Altyazı bandında** eşik 8: bant ekrandaki satırın kutusu, yoksa öğrenilen şerit (ikisi de
  alan içi, tam genişlik, üstüne ve altına `max(0,05, boy × 0,5)` pay); ikisi de yoksa bütün alan.
- **Süre sınırı:** son gerçek okumadan 1 500 ms geçtiyse iz aynı görünse de okunur. Kare sayısı
  sınırı (20 / 2) da sürer; hangisi önce dolarsa. Böylece kare hızı düşükken (makine yüklü,
  yerel model) de her yeni satır en geç 1,5 sn'de okunur.

## 4. OCR

- Güveni 0,5'in altındaki satır atılır, metin kırpılır, üstten sıralanır.
- Simge düzeltmesi: `13)`/`L3]` → `L3`, `(R3` → `R3`, `(C1` → `L1`; yan yana aynı simge teke iner.
- Parça birleştirme: boylar birbirinin yarısından büyük, dikey orta farkı büyük boyun
  %45'inden az, yatay boşluk (en/boy oranıyla) −0,01 ile 4 × boy arası. Boşluk 0,9 × boydan
  genişse simge aranır; testlerde yer tutucu `●` konur.
- Derin okuma: ilk okuma boşsa önce ortadaki %40 şerit 2 kat, sonra bütün alan 2 kat;
  sırayla, ilk bulunan kullanılır.
- **Bekçi:** okumalar tek sıradan geçer; 4 sn beklenir; tutan okuma 8 sn'den kısaysa
  kare "meşgul" atlanır, uzunsa yedek okuyucuya geçilir; yedek yoksa işlemci kipine
  geçilir ve 45 sn'yi aşan okuma "takıldı" bildirir.
- Sahne aydınlığı: alan 160 × 40'a küçültülür, 9 × 19 noktanın parlaklık ortancası / 255.

### 4.4 Satır içindeki tuş simgesi (`ButtonIcons`)

GTA 6 görev şeridinde `Hold [D-pad] to interact with your partner`: Vision simgeyi hiç okumaz (`Hold to interact …`)
ya da kırıntı okur (`Hold OC` + `) to interact …`, `Hold ® to`); sözcük kutuları da eşit bölünmüş gelir (kullanılamaz).
Çeviri `… için tuşu basılı tut` olur, bindirme simgeyi örter. Kural: **tuş görünüyorsa TV'de de görünür.**

- **Arama (görüntüden):** satırın kutusu üstüne/altına 0,45, yanlarına 1,8 satır boyu payla kesilir, satır boyu 32
  piksele getirilir; zeminden (ortanca parlaklık) 60'tan çok ayrılan pikseller bağlı bileşenlere ayrılır. Simge:
  boyu `≥ 1,15 × 32` ve harflerin ortanca boyunun `≥ 1,6` katı (yazı bandının üstüne ve altına taşar), en/boy
  0,6–1,6, kesilen alanın kenarına değmeyen bileşen (halka/çerçeve); içindekiler ona katılır. Önündeki sözcük sayısı
  soldaki sözcük kümelerinden (harf arası < 0,2 × 32); küme sayısı metindeki sözcüklerle tutmazsa konumdan oranla.
  Aynı sıradaki satır parçaları önce birleşir; simgenin yanındaki kırıntılar (≤ 3 karakter, `® & ( ) O C 0 …`) atılır.
- **Tanıma (renk/şekil, model yok):** 21 × 21 küçültmede D-pad = halka + dört kol (kollar köşegenlerden ≥ 30 açık);
  bir kol ötekilerden ≥ 35 açıksa yönü (`dpad-right`), değilse `dpad`. Renkli yüz tuşu: doygun piksellerin ¾'ü tek
  renkse yeşil `triangle`, kırmızı `circle`, mavi `cross`, pembe `square`. Tanınmayan simge kendi zeminiyle kesilir
  (en uzun kenar ≤ 48 piksel, PNG ≤ 8 KB; aşarsa 36/28/20).
- **Metindeki tuşlar:** Vision'ın yazı olarak okuduğu `L1–R3`, `✕ ○ □ △`, `↑ ↓ ← →`, `✜`, `OPTIONS`, `TOUCHPAD`
  (parantezli de) da yer tutucu olur (`Hold L2 to …` → `Hold ⟦T1⟧ to …`, ad `L2`).
- **Yer tutucu:** `⟦T1⟧` … soldan sağa, üstten alta, en çok 8. Okuma hattının metnine dokunulmaz (ipucu süzgeci,
  kararlılık eskisi gibi); yer tutucu çevirmene gitmeden hemen önce konur (`ButtonIcons.prepare(satırlar, görüntü)`):
  köşe/görev şeridi ve ipucu (Mac `ScreenOverlays`), altyazı (`SubtitleSession`; satır yer tutucuyla tek parça
  çevrilir). Önbellek/havuz anahtarı yer tutuculu metindir (aynı cümle başka tuşla gelirse aynı çeviri); simge ayrı
  taşınır (protokol.md "Tuş simgeleri").
- **Çeviride kaybolursa** (`IconPlaceholders.ensure`): Türkçede tuşu anlatan genel sözcüğün (`tuşu`, `tuşuna`,
  `düğmeyi` …) yerine, yoksa ilk fiilin (`bas…`, `tıkla`, `dokun`, `çek`, `kaydır`, `çevir`, `kullan`) önüne, o da
  yoksa satır sonuna (noktalamadan önce). Başka dillerde genel sözcüğün (`button`, `Taste`, `touche` …) yerine, yoksa
  satır başına. Yapay zekâ isteminde "⟦T1⟧'i olduğu gibi koru" kuralı var; terim koruyucu (`⟦0⟧`) ve vurgu işareti
  (`Accent.mark`) `⟦T1⟧`'e dokunmaz.
- `ButtonIconRecognizer` (`IconRecognizer`): parça birleştirmedeki boşlukta aynı tanıyıcı, okunur işaret verir
  (`→`, `✕`); hat varsayılanı hâlâ `GapIcon.none`.

## 5–6. Süzgeçler ve sıraları

Kurallar `Filters.swift`'te tek tek, sıra `FilterChain.swift`'te. Sıra:
harfsiz → (telefon üstü) → (mesaj köşesi) → (açık zeminde koyu yazı) → (telefon yazıları)
→ görev çizgisi → eski duran yazı (9 sn) → dev satırlar → (orta şart) → ipucu → yol
tarifi → çöp temizliği → eşya etiketi → iki kenar → aynı sıra birleştirme → blok seçimi
→ (kart ikinci bakış) → menü bayrağı → (küçük harfli blok) → (mesaj listesi) → (arama /
mesaj kartı) → dev blok → ipuçları çıkışı → kutu ortalama → sabitleyici.

Parantezdekiler telefon oyununda ya da kart açıkken çalışır. Telefonun yeri ve telefon
yazıları `PhoneContext` ile dışarıdan verilir (telefon/harita tarifi ayrı tur).

**Küçük harfli blok (devam satırı):** telefon oyununda küçük harfle başlayan blok atılır (mesaj
kırıntısı); **ancak** ekrandaki altyazı (ya da en çok 1,5 sn önce kalkan) cümleyi bitirmemişse
(`And after what we went through,`) ve blok aynı şeritte (dikey ortalar ≤ 0,08) ve ortadaysa
(≤ 0,12) onun devamıdır ve okunur (`we deserve to get paid.`). Ekrandaki altyazının kendisi de (gösterilmiş küçük
harfli satırın sonraki okumaları) atılmaz; yoksa satır erkenden kalkıyordu. Bunların dışında: telefon açık/yakında
görüldüyse ya da blok ortada değilse hemen atılır; **değilse bekletilir** (`bekliyor: küçük harfle başlayan satır`),
sonraki kare iz aynı da olsa yeniden okunur ve aynı metin 400 ms okunursa altyazıdır (`they'll have that here.`,
menüden sonra gelen `sell whatever…`). Satır belirirken yalnız sonu okunan kısmi okuma (`breakfast.`) kararlı
olmadığından geçmez, tam satır (`Come on. Let's get some breakfast.`) gelince o okunur (23 Kasım 00:19; test
`GameReadingBreakfastTests`, kareler `Resources/gta6-breakfast`). Aynı kutuda, aynı anda çıkıp kalkan
ikinci konuşanın gri satırı (`Uh-huh.`) blokla birlikte **tek altyazı** olarak gider: oyun ikisini
birlikte gösterip birlikte kaldırır; ayrı satır yapılırsa biri ötekinin yerine geçip kaybolur.

### Yalnız altyazı (`subtitlesOnly`, varsayılan kapalı)

"Yalnız altyazıyı çevir" açıkken ana bloğa karışan görev, ipucu, sekme ve menü satırları atılır;
yalnız konuşma altyazısı kalır. Kapalıyken hiçbir şey değişmez. Telefon oyununda (GTA 6) çalışmaz,
onun kendi kuralları var. Sırada "dev satırlar"dan sonra, "orta şart"tan önce gelir; ipuçları ve
kartlar süzülmemiş satırlardan çıkmaya devam eder. Kurallar dil bağımsızdır (konum, simge, biçim).
Kod: `GameSubtitlesOnly.swift`.

1. **Tuş:** satırda kumanda tuşu varsa atılır (`✕ ○ □ △`, `L1–R3`, `TOUCHPAD`, `OPTIONS`, simge
   yer tutucusu `[1]`). Konuşan etiketli satıra da uygulanır.
2. **Konuşan etiketli satır** (`AD: …`, §10) bundan sonraki kurallardan korunur.
3. **Simge:** harf, rakam, tırnak, ayraç, tire, üç nokta, `*` ya da nota (`♪`) dışında bir işaretle
   başlayan ve cümle bitirmeyen satır atılır (`◆ Find the hidden key`). Cümle bitiren satırın
   başındaki işaret OCR kırıntısı sayılır (`• And shut … up.` kalır).
4. **Orta:** satırın **sırası** (dikey örtüşmesi ≥ %60 olan parçalarla birlikte) karenin ortasından
   0,15'ten uzaksa atılır. Uzun satırın sol parçası tek başına ölçülmez.
5. **Şeridin üstü:** öğrenilen şerit varsa altı `şerit_üst − 0,08`'den yukarıda kalan satır atılır.
   Şerit yoksa bu kural yok.
6. **Sekme/menü bloğu:** blok (§5.10 bloklama) satırlarının **hepsi** sekme adı biçimindeyse atılır:
   1–3 sözcük, `. , ! ? … : ; "` yok, ya tamamı büyük harf (`MAP`, `SKILLS`) ya da ≥ 2 sözcük ve
   her biri büyük harfle başlıyor (`Main Quest`). Tek sözcüklü `Hey` sayılmaz; cümlenin devamı olan
   `Old Town Gate` blok içinde konuşma satırıyla birlikte olduğu için kalır.

Testler gerçek altyazı listesiyle (tireli, etiketli, `[Laughs]`, `...`, `♪`, iki parçalı uzun satır)
açık/kapalı aynı sonucu verdiğini doğrular. Mac'te ayar `MacSettings.subtitlesOnly` (eski kayıtta
yoksa kapalı); çeviri sürerken `Reader.setSubtitlesOnly(_:)`.

## 7. Sabitleyici

Tepkiler: yok, çevir(metin), temizle, geri getir(ilk metin). Kararlılık 2 okuma (cümle
bitiren satır ilk okumada), çöp gibi okuma 2 okuma **ve** 700 ms. Boşlukta satırın yeri
değiştiyse 800 ms, değişmediyse en çok 4 000 ms tutulur. 1 500 ms içinde dönen satır
geri getirilir; çevirisi başarısız satır 1 000 ms sonra yeniden denenir. "Aynı altyazı",
"daha kötü yeniden okuma", "uzama", "düzeltme" ve "anlam işareti" (olumsuzluk, yeni sayı)
kuralları `Similarity.swift`'tedir.

## 8. Bekletme ve sıra

- Bekletme (`SendGate`): bozuk okuma 800 ms, tam olmayan 300 ms, tam 0; paketteki satır
  hemen. Bekleyen varken gelen daha iyi okuma onun yerine geçer (süre baştan başlamaz),
  eksik temiz satırlar korunur; 4 sn içinde az önce gönderilenin yeniden okuması atılır.
- Sıra (`TranslationQueue`, çevirmenden bağımsız): aynı anda tek çeviri, bekleyen en çok 2
  (en eski düşer), 2 500 ms'den eski kalkmış satır gösterilmez, ekrandaki satırın TV süresi
  15 000 ms, kalkmışın `min(8 000, 2 000 + 60 × harf)`, "yerine koy" düzeltmede açık,
  kaynağa ≥ 0,90 benzeyen çeviri gösterilmez. Paket satırı hemen gösterilir. Taban çizgisi
  şartı: kutunun altı çizginin üstündeyse pakette yoksa gösterilmez, paketteyse en az 3
  sözcüklüyse gösterilir.

## 9. Öğrenilen altyazı yeri

Oyun başına en çok 60 örnek (üst, alt; alt ≥ 0,80), JSON dosyasında. Şerit ≥ 8 örnek
(üstlerin %10'u, altların %90'ı). Görev çizgisi: şerit yoksa 0,895; varsa
`şerit_alt + max(0,012, ortanca_boy)`, ≥ 0,97 ise yok, değilse en az `şerit_üst + 0,03`
ve 0,895. Taban çizgisi ≥ 12 örnek, altların %70'i ortancaya 0,03'ten yakınsa `ortanca − 0,07`.
Havuz öncelikli oyunda anahtar `gta-6`, görev çizgisi en çok 0,935.

## 10. Konuşan adı ve parçalar

Ad: en çok 3 büyük harfli sözcük + `:`/`：`, ≤ 24 karakter, rakamsız, tek sözcükse başlık
listesinde değil. Gösterimde ad başa eklenir ya da (ayar kapalı) atılır. Çevirmene giden
parçalar: etiket ve tire olduğu gibi kalır, cümleler ayrı. Küçük harfsiz cümle cümle
düzenine çevrilir; etiketlerden öğrenilen adlar büyük harfle kalır. (Oyun deyimleri
`Providers/GameIdioms`'tadır.)

## 11–14. Ekran öğeleri

- **Ek alanlar:** en çok 3 alan, en çok 1 000 ms'de bir tur; iz aynıysa OCR yok; iki okuma
  aynı anahtarı verince çevrilir; önce paket, kalanı çevirmen.
- **Köşeler:** sol üst (0–0,40 / 0–0,48), görev şeridi (çizgi–0,995), menü araması (üç turda
  bir; menü son 10 sn'de görüldüyse her turda). Aralık 1,5 sn (menüde 0,6). Menü ekranı tanınınca
  5 sn menü bayrağı (bayrak açıkken ana okuma boşaltılır).
- **Menüden çıkış:** bayrak açıkken menü araması menüyü görmezse (okuma hata vermeden) bir **ıska**
  sayılır. Menü arama alanının izi son tanınan menü karesine göre büyük ölçüde değiştiyse (40'tan
  çok farklı hücrelerin payı ≥ %25) bayrak ilk ıskada, değişmediyse ikinci ardışık ıskada kalkar;
  5 sn beklenmez. Tanıma arada bir tutmazsa (1920 karede menü araması 0,667 ölçekte sol sütunu
  kaçırabiliyor) tek ıska bayrağı kaldırmaz. Eskiden bayrak menü kapandıktan sonra da 5 sn açık
  kalıyor, menüden hemen sonraki ara sahne altyazıları boşaltılıyordu (GTA 6, 22 Kasım 23:41;
  test `GameReadingMenuExitTests`, gerçek kareler `Resources/gta6-menu-exit`).
  Kararlılık, 4 boş okuma, 40 çevirilik hafıza, PS5'in Türkçe ekranında 15 sn sessizlik.
- **İpuçları:** görev çizgisinin altındakiler atılır; gezinme sözcükleri çevrilmez; anahtar
  değişmedikçe yeniden çevrilmez; yerleşim üste, titremeden.
- **Kartlar:** mesaj kartı (ad + gövde), mesaj listesi, arama kartı (durum Türkçe), alıcı satırı.

Hepsi kare başına tek bir **ekran öğeleri** listesi olarak çıkar (`ScreenElement`: tür,
kutu, metin, görünüm). Telefon ve harita öğeleri ileride aynı listeye eklenecek.

### Ekran öğesi gönderici (`ScreenItemSender`, Mac ve iOS ortak)

`ElementsBoard.list` TV'ye bu yardımcıyla gider; saat dışarıdan verilir.

- Liste değişince `screen` (boşsa `screen-clear`). Değişmeyen ve ekranda duran liste
  `layerDurationMs / 2`'de (60 sn) bir yeniden gönderilir; TV'deki 120 sn dolmaz.
- **Kalkma histerezisi** (yalnız harita kartı): öğe listeden düşünce TV'de tutulur; ancak türü
  en az 3 ardışık gözlemde görülmezse, son görülmeden ≥ 4 sn geçtiyse ve oyundaki kaynak
  bölgesinin küçük gri imzası (24 × 12 parlaklık, ortalama fark > 10) değiştiyse kalkar. Yalnız
  türün gözlendiği turlar (menü araması) kaçırma sayılır; harita açıkken kısmi okuma kartı
  silmez. Aynı türden başka öğe gelirse hemen değişir; `drop` (menü gerçekten kapandı, telefon
  oyunu bitti) hemen kaldırır. Sıfırlamada TV'de öğe varsa `screen-clear`.

## Teşhis notları (okuma neden atlandı, satır neden atıldı)

`Reader.process` her karede `Output.notes` verir: okunan yazının neden altyazı olmadığı. Nedenler:
`atlandı: menü`, `atlandı: okuyucu meşgul` (bekçi), `geç okundu: sabit görüntü (n ms)` (iz aynı
göründüğü için yeni satır süre sınırıyla okundu), `atıldı: küçük harfle başlayan blok`, `mesaj
listesi`, `arama kartı`, `arama kartındaki ad`, `mesaj kartı`, `mesaj kartının tekrarı`, `dev blok`,
`eski duran yazı`, `yalnız-altyazı (tuş ipucu | simgeli satır | ortada değil | şeridin üstünde |
sekme/menü)`, `bekliyor: küçük harfle başlayan satır`, `atlandı: okuma hatası` (yazı tanıma hata verdi, kare boş
sayıldı). Konuşmaya benzeyen satır (≥ 2 sözcük, küçük harf) sessiz bir süzgeçte kaybolursa adımın adı yazılır:
`atıldı: telefonun üstünde | açık zeminde koyu yazı | telefon uygulaması yazısı | telefon açıkken yukarıda |
telefonda görülen yazı | görev çizgisinin altında | dev satır | ortada değil | ipucu/etiket/blok seçimi | harfsiz |
sağ alt köşe (kart tanınmadı | mesaj kartı)`. Not yalnız satırı gerçekten atan adıma yazılır (adımdan önce konuşmaya
benzeyen satır vardı, sonra yok).

**Varsayılan alan ve sağ alt kartlar:** varsayılan alt alan 0,14–0,86 × 0,62–0,97; sağ alt mesaj/bildirim kartları
(GTA 6 BuckMe, ~0,70–0,99) sağdan kesilir ve kart tanınmaz. Kullanıcının kendi geniş alanında (0,066–0,98 ×
0,567–1) sorun yok. Varsayılan değiştirilmedi (bütün oyunlarda alana tabela/HUD girer); kaçırma ölçerin "ekran
öğeleri" bölümü bu kaçakları gösterir. Öneri: telefon oyununda (GTA 6) varsayılan alanın sağ kenarı 0,99. Not metni en çok 60 karakterdir; anahtar ya da kişisel veri içermez.

`SkipJournal` notları günlük satırına çevirir: bir nedenin ilk karesi metniyle yazılır
(`atlandı: menü "You know, if Cal…"`); aynı neden art arda gelirse yazılmaz; neden değişince ya da
2 sn gelmeyince n > 1 ise o akışın özeti ilk metniyle yazılır (`özet: atlandı: menü "You know, if Cal…" ×23,
4,8 sn`); özet yalnız o metnin akışıdır, sonraki satırlar için bir şey söylemez (eskiden `… sürdü ×2` sonraki satırın
atıldığı sanılıyordu). Mac bunu `altyazi.log`'a
yazar (`SubtitleSession`).

## Kaçırma ölçer

`MissMeter` (Mac: `nino-debug kacan 23:00-23:45 [--adim 500] [--cikti klasör]`) hata ayıklama kaydındaki PS5
videolarını (AVFoundation; kayıt yalnız okunur) kare kare tarar:

1. **Bastırma kuralları kapalı okuma:** alt şerit (0,05–0,95 / 0,60–0,98) her karede OCR; süzgeç zinciri
   (§5–6, `FilterChain.chain`) bloğu seçer; menü bayrağı, telefon kuralları, yalnız-altyazı, eski yazı ve tekrar
   süzgeci yok. Menü ekranı (menü araması ya da harita ekranı tanınan) kareler sayılmaz.
2. **Diyalog:** blok alt şeritte (üst ≥ 0,62), ortada (±0,15), küçük harf içeren ve en az iki sözcüklü (ya da `OK.`
   gibi kısa cevap); tamamı büyük harfli (tabela, menü, HUD), ipucu ve eşya etiketi sayılmaz. Kayıtçının kendi
   yazısı (`OKUNAN:`/`ÇEVİRİ:` şeridi) atılır. Aynı satır 3 sn içinde yeniden görülürse (benzerlik ≥ 0,8 ya da biri
   ötekini içeriyor) tek satırdır.
3. **Karşılaştırma:** satır, görüldüğü aralığın 3 sn öncesi – 4 sn sonrası içindeki günlük okumasıyla (`#n okundu`,
   çok satırlı okumanın her parçası) eşleşirse okunmuş sayılır (içerme ya da benzerlik ≥ 0,7).
4. **Neden:** kaçan satırın ±1 sn'sindeki günlük notları (`atlandı:`/`atıldı:`, §"Teşhis notları") ve kurallar açık
   iki yeniden oynatma: o gecenin kuralları (`menuClearsOnExit = false`, `lowercaseContinuation = false`) kaçanın
   nedenini, bu sürüm yakalama oranını verir (sahte saat, kare arası `--adim` ms).

5. **Ekran öğeleri** (ayrı bölüm): menü arama alanının (tam kare) okumasında altyazı bandı dışında kalan, en az iki
   sözcüklü (2+ harf) bloklar yerleriyle (`sol üst`, `sağ`, `sağ alt`, `sol`, `üst`, `orta`, harita ekranında
   `harita`) toplanır; sayılar değişse de aynı öğedir (`Turn Left 102 m`). Günlük öğelerin çevirisini yazdığı için
   eşleme yalnız zamanladır: görüldüğü aralıkta herhangi bir `Ekran öğeleri (…)`, `harita kartı:` ya da `telefon:`
   satırı varsa karşılığı var sayılır. Kaba ölçüdür (tabela, yol tarifi de sayılır); kaçan bildirim/mesaj kartını
   ve seçim menüsünü göstermek içindir.

Sınırlar: kayıt ~1 kare/sn ve 960×540; üstünde okuma kutusu (sarı kesikli) ve okunan/çeviri şeridi çizili. Bir
saniyeden kısa satırlar kaçabilir, sayı alt sınırdır. Rapor `kacan.md`.

## 15–17. Görünüm yardımcıları

- **Buzlu zemin:** kutu x 0,04 / y 0,035 genişler, en çok 360 piksel, Gauss bulanıklığı
  `max(8, boy_px × 0,55)`, parlaklık −0,12, doygunluk 1,15, karşıtlık 0,9, JPEG 0,55 base64.
- **Ekranı çevir grupları:** boy farkı ≤ 1,6 kat, boşluk < 0,8 × boy, yarı örtüşme; simgeler
  `[1]` yer tutucularıyla korunur; süre `min(60 000, max(12 000, 8 000 + 50 × harf))`.
- **Yığın:** en çok üç satır (iki önceki, önceki, şimdiki), 1,5 sn üste çıkma, en kısa 1,2 sn,
  temizle en çok 5 sn bekler. **Sarma:** satırda 42 harf, en çok 3 satır, ölçek ≥ 0,75.

## Sonra

- Görev şeridindeki vurgu rengi (§12.6): arayüzü var, tanıyıcı yok. (Tuş simgesi §4.4'te.)
- Telefon bulma, telefon maskesi, harita kartı: `PhoneContext` arayüzü hazır, tarif ayrı.
- Yedek okuyucu süreci: bekçi "yedeğe geç" der; süreci uygulama kurar.

## Tariften sapmalar

- Parça birleştirmede boşluğa simge: tanıyıcı yoksa **hiçbir şey** konmaz (`GapIcon.none`); testler
  `.placeholder("●")` verir. Gerçek oyunda `●` altyazıya girip ipucu sanılmasın diye.
- Eşya etiketi: `:` ya da üç nokta içeren satır etiket sayılmaz (`TOMAS: ...` tablodaki "hayır" ile
  tutarlı olsun diye; kuralların yazılı sırası bunu vermiyordu).
- İpucu kırıntısı: 2 harfli tam sözcük (`am`) kırıntı sayılmaz (`I am SHAKING` "hayır").
- Menü ekranı: dükkân sözcükleri en az **2 satırda** geçmeli; `map/brief/progress` tek satırda en az ikisi.
- Ekranı çevir gruplamasında "iki sütunu bağlamama" kuralı yok; ipuçlarında simgede bölme ve
  altyazının altına koyma yok (tek öğe, üste, ortalı, titremesiz).
- Yığında üstteki satırlar, şimdiki satır 1,5 sn tam göründükten sonra 0,4 sn'de birlikte solar.
- Yeni altyazı öncekinin yerine geçerken ayrıca "bitti" olayı çıkmaz (TV'de yerine konur).

- **Canlı okuma kalitesi (GTA 6, 22 Kasım):**
  - Çöp temizliğinde `I` okuyuşları: `i`/`i'm` → `I`/`I'm`, `'II` → `'ll`, `lm`/`Im` → `I'm`,
    `lcan`/`Ican` → `I can` (yalnız `I`'dan sonra gelen bilinen sözcüklerle), `III-` + `I'll` → `I'll-`.
  - Zincirde çöp temizliğinden sonra satır başındaki madde imi/iğne okuyuşu atılır (`• « / * ·` vb.;
    tire hariç). Telefon oyununda blokta **tek** tireyle başlayan satırın tiresi de atılır (GTA'da
    tireli konuşma yok; tire göstergenin iğnesidir). Telefon oyununda baştaki tabela yazısı
    (1–3 BÜYÜK ya da bozuk düzenli sözcük, ≥ 5 harf, biri ≥ 4 harf, ardından `Hey,` gibi sözcük ve
    ≥ 3 sözcüklük konuşma) atılır.
  - Parça birleştirme (OCR ve aynı sıra): tabela gibi parça (1–3 sözcük, noktalamasız, küçük harfsiz ya
    da `ToWAr` gibi bozuk düzenli) konuşma satırına (küçük harf, ≥ 3 sözcük) katılmaz.
  - Blok seçiminden sonra: cümle biten satırın altında küçük harfle başlayan satır (üç nokta hariç)
    solu okunamamış satırın kuyruğudur; o ve altı atılır, tam okuma uzama olarak gelir.
  - Sabitleyici: okuma ekrandaki satırın **son okunuşunun** aynısı ya da daha kötü yeniden okumasıysa
    (ve gönderilenle ilgiliyse) yeni satır değildir. Daha kötü okuma son okunuşun yerine geçmez.
    Cümle biten satırın ardından gelen, onunla ilgili **bozuk biçimli** okuma (küçük harf/işaretle başlıyor
    ya da `up. man` gibi nokta ardından küçük harf) da yeni satır değildir.
  - "Aynı altyazı"nın sözcük örtüşmesi kuralları ve "daha kötü yeniden okuma", **temiz ve tam** okunmuş
    (büyük harfle başlıyor, cümle bitiriyor, bozuk değil) okuma farklı sözcükle başlıyor ve yeni bir sözcük
    ekliyorsa uygulanmaz: `And shut the damn dog up.` → `Shut the damn dog up, man!` yeni satırdır (düzeltme
    olarak yerine konur).
  - Kısa cevap: büyük harfle başlayan 2 harf + `. ! ?` (`OK.`, `No.`, `Go!`) sabitleyicide boş sayılmaz.
    Eşya etiketinde 1–2 sözcüklük `.` ile biten satır da `!`/`?` gibi etiket sayılmaz (etiketler noktalamasız).

## Giriş noktası (Mac)

```swift
let store = GameReading.PlacementStore(url: veriKlasörü.appendingPathComponent("altyazi-yeri.json"))
var cfg = GameReading.Reader.Configuration(gameKey: GameReading.Placement.gameKey(poolPriority: false, packGame: paketOyunu))
cfg.region = GameReading.Region(kayıtlıKutu)
let guarded = GameReading.GuardedTextReader(primary: GameReading.VisionTextReader(), clock: saat)
let reader = GameReading.Reader(textReader: guarded, clock: saat, configuration: cfg,
                                placementStore: store, isInPack: { paket.contains($0) })

// her kare
let out = await reader.process(GameReading.ImageFrame(cgImage))
for e in out.events {
    switch e {
    case .subtitleStarted(let s), .subtitleUpdated(let s), .subtitleCorrected(let s):
        sıra.enqueue(s.request(packTranslation: paket[s.text]), now: saat.nowMs) // → .translate / .show
    case .subtitleRestored(let s): sıra.lineRestored(id: s.id)
    case .subtitleEnded(let id): sıra.lineRemoved(id: id, now: saat.nowMs)
    case .hints, .messageCard, .callCard: break // Hints / CardPresenter + ElementsBoard
    default: break
    }
}
// köşe turu (ayrı görev): await reader.readCorners(kare) → CornerTracker
// ek alanlar (ayrı görev): await alanlar.round(kare, areas: ayarlar.ekAlanlar)
```

`TranslationQueue.translate` eylemini çevirmen (Providers) yapar, sonucu `finished(id:translation:now:)`
ile döner; `.failed` gelirse `reader.translationFailed(id:)`. TV'ye `ElementsBoard.list` katman olarak gider.
