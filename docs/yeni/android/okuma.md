# Eski Android okuma hattı: tariften farklar ve ek davranışlar

Bu belge, eski Android uygulamasının okuma hattının ne yaptığını anlatır. Karşılaştırma
`NinoCore/docs/tarif/okuma-hatti.md` tarifiyle yapıldı. Tariften ayrılan her yer **Fark:** diye
işaretlendi. Tarifte hiç geçmeyen davranışlar "Ek" başlıkları altında duruyor. Sayılar eski koddan
olduğu gibi alındı.

En büyük genel fark şu:

- **Fark:** Eski hatta zaman **saatle (milisaniye)** ölçülür, kare sayısıyla ölçülmez. Testlerde
  saat elle ilerletilir. Okuma en çok saniyede 5 kare yapıldığı için 200 ms yaklaşık 1 okuma eder
  (bkz. Belirsizlikler).

---

## 1. Kare ve okuma sıklığı

- Kare, Remote Play'den (ya da yakalama kartından) gelir. Kullanılan kısım parlaklık (gri) düzlemidir.
  Renk düzlemi yalnız telefon ve harita için kullanılır.
- **Ek:** Yazı tanıma saniyede **en çok 5 kare** okur (telefon ısınmasın diye). Bir okuma sürerken
  yeni kare okunmaz, o kare atlanır.
- **Ek (değişmeyen bölge):** Okunan bölgeden kaba bir iz çıkarılır: her 8. satırın her 8. pikseli,
  parlaklığın üst 4 biti. İz bir önceki kareyle aynıysa yazı tanıma çalışmaz, son okuma hatta yeniden
  verilir. Bu en çok **20 kare** tekrarlanır. "Hızlı altyazı algılama" ayarı açıksa sınır **2 kare**dir
  (ayar varsayılan olarak kapalı). Sonra bölge yeniden okunur.
- **Ek:** Ayrıca bölgenin 64×12 boyutunda küçük gri izi çıkarılır: her hücrenin ortasındaki piksel
  örneklenir. Sabitleyici bunu "yazı hâlâ yerinde mi" sorusu için kullanır (bkz. 5). İki iz arasında
  bir örnek **16'dan** fazla değişmişse iz "değişti" sayılır. İstenirse yalnız satırın kutusunun
  örttüğü örneklere bakılır.

## 2. OCR

- **Fark:** Okuyucu Google ML Kit'in cihaz üstü Latin modelidir ve varsayılan ayarlarla çalışır. Dil
  seçimi, "doğru mod" ya da dil düzeltmesi diye bir ayar yoktur.
- **Fark:** ML Kit'in güven değeri **kullanılmaz**. Satırda yalnız yazı ve kutu vardır, kutu da
  bilinmeyebilir. Tarifteki 0.40 güven süzgecinin karşılığı yoktur.
- Kırpma şöyle yapılır:
  - Yalnız altyazı bölgesi kopyalanır.
  - Sol ve üst kenar ile en ve boy **çift sayıya** yuvarlanır.
  - En ya da boy **16 pikselden** küçükse okuma yapılmaz.
  - Renk düzlemleri nötr 128 ile doldurulur. Böylece görüntü gri olur, beyaz ve sarı altyazı aynı
    okunur.
- **Ölçek:** Küçültme ya da büyütme yapılmaz. Bölge, karenin kendi çözünürlüğünde okunur.
- Bir okuma için en çok **5 sn** beklenir.
- Satır kutuları **okunan bölgeye göre** oran olarak (0–1) verilir. Başlangıç noktası sol üst köşedir.
  Hat, kutuyu gerektiğinde karenin oranlarına çevirir.
- ML Kit blokları her zaman yukarıdan aşağı vermez. Bu yüzden satırlar üst kenarlarına göre sıralanır.
- Boş satırlar atılır.

## 3. Altyazı bölgesi

- **Fark (varsayılan):** Üst 0.62, alt 0.97, sol 0.14, sağ 0.86. Yani `x 0.14, y 0.62, genişlik 0.72,
  yükseklik 0.35`. Tarifte `x 0.10, genişlik 0.80, yükseklik 0.36` yazıyor.
- **Ek (hazır seçimler):**
  - Alt: varsayılan bölge.
  - Üst: üst 0.03, alt 0.38, sol 0.14, sağ 0.86.
  - Tam ekran: 0–1.
  - Özel: kullanıcının ayarladığı bölge.
  - Kayıtlı bölge bir hazır seçime en çok 0.001 farkla eşitse o seçim sayılır.
- **Ek:** Bölgenin en küçük eni ve boyu 0.05'tir. Bölge taşınırken ve boyutlandırılırken karenin
  dışına çıkamaz.
- **Fark (süzgeç):** "Merkezi bölgenin dışında kalan satır atılır" kuralı yoktur. Zaten yalnız bölge
  kırpılıp okunur.
- **Ek (altyazının yerini öğrenme):** Her oyun için, gösterilen altyazının kutusu kaydedilir.
  - Kayıt bir dosyada durur.
  - Oyun başına en çok **60** örnek tutulur.
  - Alt kenarı **0.80'den** yukarıda kalan kutu örnek sayılmaz.
  - **8 örnekten** sonra o oyunun altyazı şeridi bilinir. Şeridin üstü, üst kenarların %10'luk
    dilimidir. Altı, alt kenarların %90'lık dilimidir.
  - Öğrenilince okunan bölgenin üstü **şeridin üstü − 0.05** çizgisine indirilir. Bu yalnız daraltır,
    genişletmez. Geriye **0.06'dan** ince bir şerit kalacaksa ayardaki bölge olduğu gibi okunur.
- **Ek (görev şeridi çizgisi):** Karede bu çizginin altında başlayan satır altyazı sayılmaz.
  - Öğrenilmemişse çizgi **0.895**'tir.
  - Öğrenilmişse çizgi şöyle hesaplanır: şeridin altı + en az 0.012 ya da kutu boylarının ortancası.
    Sonuç en az şeridin üstü + 0.03 olur, en az da 0.895 olur.
  - Çizgi **0.97 ve üstü** çıkarsa sınır kalkar.
  - GTA 6'da çizgi en çok **0.935**'tir.
  - İstisna: konuşan adıyla başlayan satır hep kalır ("ENZO: …"). Onun hemen altındaki devam satırı
    da kalır: üst kenarı konuşanın altından en çok 0.02 ya da kendi boyunun 1.5 katı kadar aşağıda
    olmalı.

## 4. Gürültü süzgeci ve satırların birleşmesi

Her okumaya sırayla şu adımlar uygulanır:

1. **Harf sayısı:** 2'den az harfi olan satır atılır. Bu tarifle aynıdır.
   - **Fark:** "Harfler boşluk dışı karakterlerin yarısından azsa atılır" kuralı yoktur.
   - **Fark:** Arayüz yazısı listesi (`options, menu, skip …`) yoktur. Onun yerine aşağıdaki kurallar
     çalışır.
2. **Görev şeridi çizgisi:** Bkz. 3.
3. **Eskiyen satır (Ek):**
   - Aynı yazı (sadeleştirilmiş hâli) **9 sn** ya da daha uzun süredir duruyorsa ve aynı okumada daha yeni
     bir satır da varsa, eski satır atılır.
   - Satırların hepsi eskiyse ya da hiçbiri eski değilse okumaya dokunulmaz.
   - Süre satırın ilk görüldüğü okumadan başlar. Bir okumada görünmeyen satırın süresi sıfırlanır.
   - Süzgeç her okumada çalışır (bölge değişmediği için eski okuma yeniden kullanıldığında ve harita açıkken de).
4. **Dev satır (Ek):** Satırın boyu karenin tamamına göre ölçülür.
   - Boyu **0.13'ü** aşan satır her zaman atılır.
   - Boyu **0.075'i** aşan satır, etiket gibiyse atılır. Etiket gibi: en çok 4 sözcük ve `. , ! ? …`
     işaretlerinin hiçbiri yok.
   - Yeri bilinmeyen satıra dokunulmaz.
   - Atılan yazı günlüğe bir kez yazılır. Son 32 yazı hatırlanır.
5. **Kumanda ipucu (Ek):** Bir satır şu durumlarda kumanda ipucu sayılır ve atılır:
   - İlk parçası bir tuş ve en çok 5 sözcük var. Tuşlar: R1/R2/R3/L1/L2/L3, options, touchpad, ✕ ○ □ △
     ve benzer simgeler.
   - Son parçası tuş, en çok 4 sözcük var ve cümle sonu işareti yok.
   - X ya da O ile başlıyor, 2–4 parça var, ikincisi büyük harfle başlıyor ve cümle bitmiyor.
   - Press/hold/tap/push/use/mash/release ile başlıyor, 2–10 parça var ve ikinci parça tuş ya da X/O.
   - Başta 1–3 tek karakterlik kırıntı, ardından noktalamasız BÜYÜK HARFLİ 1–3 sözcük var
     ("A e DRINKS").
   - Bir zarfla başlıyor (slowly, quickly, gently, carefully, rapidly, repeatedly, continuously,
     briefly), 3–16 parça var, üçüncü parçadan sonra "to" geçiyor ve cümle bitmiyor.
   - En çok 16 parça var, içinde gerçek bir tuş simgesi ve "to" geçiyor, cümle bitmiyor.
6. **Yol tarifi (Ek):** Satırda yalnız yön ve mesafe varsa atılır.
   - Örnekler: "Turn Left 120 ft 98 ft", "Keep Left O ft 2 ft".
   - Mesafesiz tek komutlar da atılır: "Turn left", "Make a U-turn", "Keep Right."
   - Mesafe sayıdır ya da O/o okunan sıfırdır. Birimi ft, mi, yd, km ya da m olur.
   - Arkasında söz olan cümle altyazı kalır: "Turn right after the bridge, alright?"
7. **Sözcük çöpü temizliği (Ek):**
   - İçinde simge olan ya da harfle rakamın iç içe geçtiği parça atılır. Simgeler: `$ @ # % ^ * _ = | \ ~
     < > { } ¢ £ ¥ § © ® ° ± µ ¶ ¤`. Örnekler: "ou$3e", "waters2aljd".
   - Çöpten önce en az 3 harflik gerçek bir sözcük varsa o sözcük kalır: "waters2aljd" → "waters".
   - Olağan karışımlar korunur: PS5, R2, 2nd, 100m, x3, 3.5kg, 10:30pm, $500.
   - Tek başına "l" ya da "|" "I" yapılır. "l'm", "l'll", "l've", "l'd" da "I'm" gibi düzeltilir. Tek
     "I" yalnız şu durumlarda kalır: ardından küçük harfle başlayan bir sözcük geliyor ya da kendisi `?`
     veya `!` ile bitiyor. Yoksa altyazı kutusunun kenarı sayılıp atılır.
   - Yalnız `? ! . , ; :` işaretlerinden oluşan parça kendinden önceki sözcüğe yapıştırılır. Satır
     başındaysa ya da cümle zaten bitmişse atılır. Üç nokta korunur.
   - Atılan çöpün ardındaki noktalama önceki sözcüğe eklenir.
   - Satırın başına bir göstergenin sayısı yapışmışsa o sayı atılır ("9? We'll lose…"). Bunun için en
     az 3 parça olmalı ve ikinci parça büyük harfle başlamalı.
8. **Yan yana parçalar (Ek):** Aynı satırda okunan parçalar soldan sağa tek satır olur.
   - Dikeyde örtüşme, küçük parçanın boyunun en az %60'ı olmalı.
   - Aradaki yatay boşluk bölge genişliğinin en çok **0.05**'i olmalı.
   - Böylece renkli konuşan adı cümlesiyle birleşir.
9. **Altyazı bloğunu seçme (Ek):** Satırlar alt alta bloklara ayrılır.
   - Bir satır bir bloğa şu koşullarla katılır: önceki satırdan sonraki boşluk satır boyunun 0.8
     katından az, yatay örtüşme dar olanın en az yarısı.
   - Menü gibi bloklar elenir: en az 3 satır, her satır en çok 3 sözcük, hiçbir satır cümle gibi
     bitmiyor.
   - Ortası ekran ortasına en çok **0.12** uzaklıkta olan bloklardan **en alttaki** seçilir.
   - Ortalı blok yoksa en az 3 sözcüklü bloklardan en alttaki seçilir. O da yoksa okuma boş sayılır.
10. **Dev blok (Ek):** Blok 5'ten fazla satırlıysa ya da karenin **0.26**'sından fazla yükseklik
    kaplıyorsa altyazı değildir. Okuma boş sayılır (afiş, not, belge).

- **Fark (birleştirme):** Kalan satırlar boşlukla değil **alt satırla** birleştirilir. Sabitleyici ve
  karşılaştırmalar satır satır çalışır, örneğin "bir satırı eksik okunan altyazı" kuralı.
- **Fark:** Sabitleyicide sadeleştirilmiş hâli **3 karakterden kısa** olan okuma boş kare sayılır.
- Harita ekranı açıkken (bkz. 9) okuma hiç verilmez, hat boş okuma alır.

## 5. Sabitleyici

| Ayar | Eski değer | Tarif |
|---|---|---|
| Kararlılık | **2 okuma** | 3 kare |
| Benzerlik | 0.85 | 0.85 |
| Kalkma | **800 ms** boş | 2 kare |
| Yeri değişmeyen yazıyı tutma | **4000 ms** | yok |
| Geri dönen satır | **1500 ms** içinde, son **5** satır | son 32 altyazı |
| Başarısız çeviriyi yeniden deneme | **1000 ms** sonra | yok |
| Çöp gibi okunan satır | 2 okuma **ve 700 ms** | yok |

- **Benzerlik:** Tarifle aynıdır. Yazı küçük harfe çevrilir, harf ve rakam dışı her şey boşluk olur,
  sonra Levenshtein oranı hesaplanır. Boş yazı hiçbir yazıya benzemez.
- **Fark (hemen gönderme):** Satır cümle sonu işaretiyle bitiyorsa **ilk okumada** gönderilir. Bu
  işaretler `. ! ? …`; kapanan tırnaklar ve parantezler yok sayılır.
  - Örnek: "Nobody saw us leave." ilk okumada gider. "Nobody saw us leave" ancak ikinci okumada gider.
- **Fark (çöp okuma):** Okuma çöp gibiyse, yani harflerinin altıda birinden fazlası bozuk sözcüklerdeyse,
  noktayla bitse bile beklemeden gitmez. 2 okuma ve en az 700 ms aynı kalmalıdır. Bozuk sözcük
  şunlardan biridir: karışık büyük/küçük harf, simge, köşeli ya da normal parantez, 3 ya da daha uzun
  ünlüsüz sözcük. "Hmm", "Shh", "Brr", "Psst", "Zzz" gibi ünlemler bozuk sayılmaz.
- **Fark (olaylar):** Tarifteki "başladı / bitti" çifti yoktur. Sabitleyici bir okumaya dört yanıttan
  birini verir: hiçbir şey, çevir, temizle, geri getir.
  - Yazı değişince eski altyazı için ayrı bir "bitti" çıkmaz. Yeni yazı doğrudan "çevir" olur.
  - "Temizle" yalnız bölge **boş** okunduğunda çıkar. Boşluk 800 ms sürmeli ya da satırın yeri
    değişmemişse 4000 ms dolmalı.
  - Başka bir yazı okunması kalkma sayacını artırmaz.
- **Ek (yazı yerinde mi):** Okuma boş döner ama satırın kutusundaki iz son okumadan beri değişmemişse,
  yazı tanıma yazıyı kaçırmıştır. Satır silinmez. Yine de en çok 4000 ms tutulur.
  - Örnek: parlak zeminde beyaz yazı saniyelerce okunamıyordu.
  - Satırın yeri değişince her zamanki 800 ms sayılmaya başlar.
- **Fark (boş kare ve aday):** Boş okuma adayı **hemen sıfırlar**. Tarif ise boş karenin adayı
  bozmadığını söylüyor.
- **Fark (aynı altyazı):** Ekrandaki satırın yeniden okuması, tarifteki karakter benzerliğinden daha
  geniş kurallarla tanınır. Sırayla:
  1. Okuma, gönderilende olmayan bir olumsuzluk sözcüğü ya da sayı taşıyorsa **başka cümledir**.
     - Olumsuzluklar: not, no, never, cannot, dont, cant, wont… Kesmesi okunmamış "won t" de sayılır.
     - Harfle karıştırılan rakamlar harfe çevrilip öyle bakılır: "n0t" "not" sayılır.
     - Yalnız **eklenen** işaret sayılır. İşareti düşüren okuma OCR kaybıdır.
     - Örnekler:
       - "I can't do that." / "I can do that." → başka cümle.
       - "Meet me at 6." / "Meet me at 5." → başka cümle.
       - "I dont know." / "I don't know." → aynı.
       - "1 can do that." / "I can do that." → aynı.
  2. Okuma, gönderilenin başına ya da sonuna sözcük eklenmiş hâliyse **yenidir**. Bu tarifteki uzantı
     istisnasıdır, ama sözcük düzeyinde ve sonuna eklenmeyi de kapsar.
  3. Karakter benzerliği 0.85 ya da üstüyse aynıdır.
  4. Baştan ya da sondan kesilmiş okuma, yalnız tam satırları eksikse aynıdır. Yarım satır eksikse
     başka cümledir.
  5. Okuma en az 4 sözcüklüyse ve sözcüklerinin en az %85'i gönderilende varsa aynıdır.
  6. İki taraf da en az 6 sözcüklüyse ve sözcük sayılarının oranı en az 0.75 ise, ortak sözcükler uzun
     olanın en az %75'iyse aynıdır.
  - Tek harfli sözcükler ve sayılar karşılaştırmaya katılmaz.
- **Ek (daha kötü yeniden okuma):** Okuma, gönderilen cümlenin bozuk ve ondan daha iyi olmayan bir
  okumasıysa yeni satır sayılmaz.
  - Bunun için en az 5 sözcük gerekir, büyüme ya da anlam ekleme olmamalıdır.
  - Sözcük dizisi benzerliği en az 0.65 ya da karakter benzerliği en az 0.75 olmalıdır.
  - Puanı gönderilenin puanı + 4'ten küçük olmalıdır. Puan şöyle hesaplanır: temiz sözcüğün her harfi
    +1, bozuk sözcüğün her harfi −2.
  - Daha çok sözcük okuyan okuma yeniden çevrilir.
- **Fark (geri dönen yazı):** Kalkan satır **1500 ms** içinde geri gelirse yeniden çevrilmez, "geri
  getir" çıkar. TV eski çeviriyi gösterir.
  - Bu, başka bir satırla yer değiştirmiş satır için de geçerlidir: A → B → A yine geri getirilir.
  - Liste son **5** satırla sınırlıdır.
  - Süre geçtiyse satır yeniden çevrilir.
  - Tarifteki "son 32'den biriyse önbellekten ver" kuralı eski hatta çeviri katmanındadır, bkz. 6.
- **Fark (uzayan yazı):** Tarifteki "devam" olayı yoktur. Uzayan yazı yeni satırdır, ama TV'ye
  "öncekinin yerine koy" bilgisiyle gider. Bunun için yeni satır öncekinin büyümesi ya da düzeltmesi
  olmalı:
  - Büyüme her iki yönde sayılır.
  - Karakter benzerliği en az 0.8 olabilir.
  - Ya da en az 5 sözcüklü iki okumada sözcük dizisi benzerliği en az 0.65 ya da ortak sözcük oranı en
    az 0.7 olabilir.
- **Ek (çevirisi başarısız olan satır):** Satır unutulur ve ekranda kaldığı sürece en erken 1000 ms
  sonra yeniden çevrilir.
- **Ek (zaten Türkçe olan yazı):** Çeviri kaynağına 0.90 ve üstü benziyorsa TV'ye gitmez.
  - Paketten gelen satır her zaman gösterilir. Tek istisna, kaynakta Türkçe harf (ğışçöü) varsa: bu
    PS5'in kendi ekranıdır.

## 6. Bekletme ve çeviri sırası (Ek; tarifte yok)

Telefonda "yarım ya da bozuk okumayı bekletme" açıktır:

- **Bozuk okuma** pakette bulunamazsa **800 ms** bekletilir. Bozuk okuma şunlardan biridir:
  - ASCII dışında, `’ ‘ “ ” — – …` olmayan bir karakter var.
  - Sözcük ortasında harf olmayan bir karakter var. Kesme ve tire bunun dışındadır.
  - Harfle rakam bitişik.
  - a, A, I, o, O dışında tek harfli bir sözcük var.
  - 14'ten uzun bir sözcük var.
- **Yarım olabilecek temiz okuma** **300 ms** bekletilir. Yarım olabilecek okuma: bir satırı küçük
  harfle başlıyor ya da cümle sonu işareti yok.
- Tam ve temiz cümle ya da pakette bulunan satır beklemeden gider.
- Bekleme sırasında aynı satırın daha iyi (puanı yüksek) okuması gelirse onun yerine geçer. Süre
  baştan başlamaz.
  - Eskide olup yenide olmayan temiz satırlar korunur. Böylece iki satırlık altyazının kaçan ikinci
    satırı kaybolmaz.
  - Olumsuzluk ya da sayı düzeltmesi bekleyenin yerini alır.
  - Araya giren ilgisiz bozuk okuma yok sayılır.
  - Bölge boşalırsa bekleyen temiz satır çevrilir, bozuk okuma atılır.
- **Yeniden okuma sayılan okumalar:**
  - Biri bozuksa ortak sözcükler yeter. Kısa olanın en az yarısı ve en az 2 sözcük ortak olmalı.
  - Sözcük sayısı aynıysa ve karakter benzerliği en az 0.75 ise yeniden okumadır.
  - Farklı sözcüklerin hepsi bozuk ve en çok yarısı farklıysa yeniden okumadır.
  - Eskinin aralıklı alt dizisi olan okuma yeniden okumadır.
  - Eskinin kesik bir parçası olan ve cümle sonu taşımayan okuma yeniden okumadır.
- Az önce çevrilen satırın daha iyi olmayan yeniden okuması **4000 ms** içinde yeni satır sayılmaz.
- **Sıra:**
  - Aynı anda tek çeviri sürer.
  - Sırada en çok **2** satır bekler; fazlası en eskiden atılır.
  - Bekleyen satırın düzelmiş okuması gelirse eski okuma sıradan çıkar.
  - Süren çeviri yeni satırın yarım hâliyse sonucu gösterilmez.
- **Geç sonuç:** Ekrandan **2500 ms'den** önce kalkmış satırın çevirisi gösterilmez.
  - Satır kalkmış ve sırada yeni bir satır bekliyorsa süren çeviri iptal edilir.
  - Daha yeni bir satır gösterildiyse de iptal edilir.
- **Gösterim süresi:**
  - Ekrandaki satır 15000 ms gösterilir.
  - Kalkmış satırın geç gelen çevirisi `en çok 8000, 2000 + harf × 60` ms gösterilir.
- Son **8** satırın çevirisi hatırlanır. Geri getirilen satır buradan verilir.
- Sunucudan sonradan daha iyi bir çeviri gelirse ve satır hâlâ ekrandaysa çeviri yerinde değişir.
  Paketten gelen satıra dokunulmaz.

## 7. Cümle bölücü

- Cümle sonu: `. ! ?` ya da `…` (dizileri de olur), ardından isteğe bağlı kapanış ve boşluk. Kapanış
  işaretleri `" ' ” ’ ) ]` olur, en çok 10 tane. Bu tarifle aynıdır.
- Sonraki karakter küçük harfse bölünmez. Bu da tarifle aynıdır.
- **Fark (kısaltmalar):** Liste tariftekinden uzundur: mr, mrs, ms, dr, st, jr, sr, prof, **mt**, vs,
  etc, e.g, i.e, **lt, sgt, capt, gen, col**.
  - Ayrıca tek büyük harfli baş harften sonra bölünmez: "J. R. R."
- **Ek (satırlar):**
  - Konuşmacı etiketiyle ya da diyalog tiresiyle başlayan satır yeni bir konuşmadır. Diğer satırlar
    önceki satıra boşlukla eklenir.
  - Konuşmalar arasına satır sonu ayracı konur.
  - Tire ve etiket çevrilmez, olduğu gibi kalır.
  - Harfsiz parça çevrilmez.
- **Fark (tireler):** Tire yalnız satır ya da konuşma başında ayrı tutulur. Aynı satırdaki ikinci tire
  ("- Run! - Where?") cümlenin içinde kalır.
- **Ek (konuşmacı etiketi):** Cümle başında en çok 3 sözcüklü ad ve iki nokta durur. Ad ya tümü büyük
  harftir (rakam olabilir: "ATREUS:"), ya da her sözcüğü büyük harfle başlar ("Mimir Head:").
- **Ek (büyük harfli cümle):** Tümü büyük harfli ve en az iki sözcüklü cümle cümle düzenine çevrilir:
  "THE BRIDGE WILL NOT LAST." → "The bridge will not last."
  - Cümle başı, "I" ve etiketlerden öğrenilen adlar büyük harfle kalır.
  - Model büyük harfli sözcükleri ad sanıp çevirmiyordu, bu yüzden eklendi.
- Paket aramasında sırayla şunlar denenir:
  1. Satırın tamamı.
  2. Etiketsiz ya da tiresiz hâli.
  3. Her satır ayrı.
  4. Her cümle ayrı. Parçaların hepsi bulunmalı.
  - Hiçbiri tutmazsa aynı sıra bulanık aramayla bir kez daha denenir.
  - Köşe yazısı gibi satırlar atlanabilir: en çok 4 sözcük; "•" içerir ya da her sözcüğü büyük harfle
    başlar.

## 8. Konuşmacı öneki

- Biçim: en çok 3 sözcük, her sözcük büyük harfle başlar, rakam yoktur. Ardından `:` ya da tam
  genişlikli `：` gelir. İki noktadan önce bir boşluk olabilir.
- Ad en çok **24** karakterdir.
- Tek sözcüklü başlıklar ad sayılmaz: note, warning, tip, hint, objective(s), quest, goal, new,
  reward(s), location, chapter, mission, task, tutorial, update, info, status, level, controls, press,
  hold, tap, remember, example, question, answer, result(s), time, listen, look, wait, okay, ok, well,
  so, yes, no, now, then, and, but.
- Gövdede harf olmalı ve gövde "/" ile başlamamalı.
- Örnekler:
  - "MARA: The boat is leaving." → ad MARA, cümle "The boat is leaving."
  - "Mr. Okafor：Sit down." → ad "Mr. Okafor".
  - "OLD MAN : Hm." → ad "OLD MAN".
  - "Mara:\nThe boat is leaving." → gövde "The boat is leaving."
  - Ad sayılmayanlar: "7:45 at the harbor.", "Ratio 16:9", "HTTPS://example.com", "Tip: the door is
    locked.", "We warned you: run!", "Much Too Long A Title: here", "Maximilianus Wetherington: Yo.",
    "MARA:".
- Çeviriye yalnız cümle gider.
- Paket araması iki adımlıdır: konuşan adıyla birlikte tam satır, o yoksa adı atılmış cümle.
- Gösterirken ad yeniden başa eklenir: "MARA: Tekne kalkıyor." Bunu `settings_speaker_names` ayarı
  yönetir; ayar varsayılan olarak açık.
- Ayar kapalıysa İngilizcede ad olan satır başlarındaki ad atılır:
  - "MARA: Yes.\nJONAH: No." → "Evet.\nHayır."
  - "Hedef: Kampa dön." gibi Türkçe başlık kalır.

## 9. Oyundaki telefon (Ek; yalnız GTA 6)

Şu durumlarda açıktır: oyun GTA 6 olarak biliniyorsa, ya da oyun bilinmiyor ya da yalnız paketten
tahmin ediliyor ve çeviri dili havuz öncelikliyse (Türkçe). Karede renk bilgisi yoksa çalışmaz.

**Telefonu bulma:**

- Kare **240×135** boyutuna küçültülür.
- Her satırda telefon genişliğinde (karenin **0.12–0.30**'u) beyaz şerit aranır.
  - Beyaz nokta: en koyu kanal en az **118**, kanallar arası fark en çok **45**.
  - Yazının ince çizgileri (≤3 nokta) şeridi bölmez.
- Şeritlerin sol kenarı bir doğru olmalıdır. Eğimler 0 ile ±0.30 arasında 0.02 adımla denenir. Bir aday
  için en az 8 oy gerekir, en çok **32** aday sınanır.
- Telefon sayılmak için:
  - En az 8 satır uymalı.
  - Satırların **%70'inde** iki yan koyu olmalı (en koyu kanal **< 90**). Ya da satırların %85'inde iki
    yan beyaz olmamalı ve %35'inde koyu çerçeve olmalı.
  - Yükseklik karenin **0.38–0.86**'sı olmalı.
  - Boy/en oranı (16:9'a göre) **1.2–2.6** olmalı.
  - Ortası x olarak **0.30–0.80** arasında olmalı.
  - Üst kenar en az 0.04 olmalı.
- Karanlık karede: ortadaki %95'lik dilimin parlaklığı 40 ile 118 arasındaysa görüntü 225'e
  aydınlatılıp yeniden aranır.
- Koyu temalı uygulamada şart tersine çevrilir:
  - Ekran: en koyu kanal + fark ≤ **75**.
  - Gövde: ≥ **85**.
  - Satırların en az %15'inde beyaz yazı noktası olmalı (≥ 110).
  - Alt kenar 0.96'yı geçmemeli.
- Telefon bulunamayan karede son yerinde aynı tür ekran duruyorsa telefon orada sayılır. Bunun için
  ekranın en az %45'i (koyu ekranda **%50**) aynı türde olmalı. Bu en çok **3 sn** sürer.
- Telefon uygulamasının sözcükleri görülüp telefon bulunamadıysa yeri tahmin edilir: genişlik 0.21,
  ekranın 0.20–0.82'si.

**Altyazıdan atılanlar** (telefon açıkken, ya da son **5 sn** içinde görüldüyse):

- Telefonun altyazı bölgesine giren kısmı okumadan önce siyaha boyanır.
  - Telefonun alt kenarı en çok 0.15 uzatılır, ama 0.84'ün altına inmez.
- Telefonun içinde kalan satırlar atılır (0.02 payla).
- GTA 6'da her zaman atılanlar:
  - Sağ alt köşedeki satırlar: sol kenarı ≥ **0.66** ve üstü ≥ **0.74** (mesaj kartı).
  - Ortası ekran ortasından **0.12'den** uzak satırlar.
  - Açık zeminde koyu yazı (mesaj balonu).
  - Telefon uygulamasına özgü yazılar ("Change Destination", "Book Ryde ($82)", BuckMe, Ryde…).
- Oyun bilinmese ve telefon görülmese de: satırın tamamı bilinen bir uygulama yazısıysa ("Change Destination",
  "Book Ryde ($82)", "Choose Ryde"…; yalnız tam eşleşme) atılır.
- Telefon açıkken **0.8** çizgisinin üstündeki satırlar altyazı değildir.
- Telefonda son **30 sn** içinde görülen mesajların parçası olan, 3 ya da daha çok sözcüklü satırlar
  atılır.

**Mesajları okuma ve gösterme:**

- Okuma sıklığı: panel boşken **0.6 sn'de**, Türkçeler ekrandayken **1 sn'de** bir.
- Telefonun ekranı ayrı kopyalanıp ayrı okunur.
- Harita ya da menü açıkken, ve kapandıktan sonra 8 sn, telefon aranmaz.
- **Sohbet** şöyle tanınır:
  - En üstte, ekranın ortasında (genişliğin 0.12'si payla) bir ad olmalı.
  - Altında aynı hizada satır olmamalı.
  - En az bir mesaj cümle olmalı.
  - "Back", "Done" gibi düğmeler ad sayılmaz.
- **Sohbet listesi** çevrilmez. Liste: en az 3 kez "ad + hemen altında önizleme" ya da "…" ile kesilmiş
  önizlemeler.
- **Mesajlar:**
  - Başlık şeridi ekranın üst **%7**'sidir. Başlığın 0.012 altına kadar kesik satırlar atılır.
  - Alt kenarda yarım görünen satırlar atılır.
  - Aynı hizada ve yakın satırlar tek mesaj olur.
  - "New message", "Typing", "Delivered" gibi etiketler mesaj değildir. Eşya ya da yer adları da
    mesaj değildir.
  - Gruptaki gönderen adı ("Cal") atılır.
- Bilinmeyen mesaj, bir önceki okumada da aynı metinle görüldüyse çevrilir. Böylece kaydırma sırasında
  yarım satır çevrilmez.
- Bilinenler hemen gösterilir. Sıra:
  1. Sabit sözlük (BuckMe, Ryde, fitness yazıları).
  2. Havuz.
  3. Kalıcı hafıza. 5000 kaydı aşınca boşaltılır.
  4. Oturum hafızası.
- Ekranın dibinde bitmemiş, çok satırlı son mesaj çevrilmez. Ekranın üstünde baştan kesik, küçük harfle
  başlayan ilk mesaj da çevrilmez.
- Çeviri sırası:
  - Mesajlar önce tek istekte havuza sorulur. İstek, ilk bilinmeyenden önceki 4 mesajı bağlam olarak
    taşır.
  - Kalanlar cihazda çevrilir. Her mesaj önceki 3 mesajla bağlam olarak gider. Aynı anda en çok 2
    çeviri sürer, her biri en çok 60 sn.
  - Art arda tekrar eden sözcükler teke indirilir. Simgeler ve HTML varlıkları atılır.
- Panelin değişmesi:
  - Sohbet başlığı değişirse panel hemen kalkar.
  - Aynı ya da benzer mesajlar paneli değiştirmez. Benzer sayılan: aynı, biri ötekinin başı ya da sonu,
    ya da %75 benzer.
  - Yeni mesajlar ancak iki okumada görülünce paneli değiştirir.
  - Mesajlar 0.02'den fazla kaydıysa panel silinir.
  - Sohbet listesine dönülürse, harita ya da menü açılırsa panel hemen kalkar.
  - Telefon bulunamaz ya da ekranı okunamazsa bütün ekran öğeleriyle ortak kalkma histerezisi geçerlidir:
    panel ancak art arda **3** kaçırılan okuma (okuma sıklığında), ilk kaçırmadan beri en az **4 sn** ve
    telefonun son bulunduğu ekran dikdörtgeni görüntüsel olarak değiştiyse (64×12 iz örneklerinin en az %5'i)
    kalkar. Tek kaçırılan okuma paneli silmez; görüntü aynı kaldıkça panel durur.
- Gösterim:
  - **Sohbette** Türkçeler telefonun boş yanında dikey bir panelde durur. Panelin genişliği **0.27**,
    telefona uzaklığı 0.035.
  - Gelen mesajlar solda, giden mesajlar sağda durur. Giden mesaj: telefonda sağa yaslı (girinti >
    0.2 genişlik) ya da belirgin mavi.
  - Balonlar mesajların renginde, saydamlıkları 0.95. Zeminin saydamlığı 0.6. Panelin üstünde
    gönderenin adı yazar.
  - **Uygulamada** (BuckMe, Rydeme) her satırın Türkçesi uygulamanın renginde, satırın hizasında bir
    baloncukta durur.
- Telefon elde sallanırsa yazı yeniden okunmaz:
  - Yalnız telefonun yeri en sık **150 ms'de** bir bulunur.
  - Kayma 0.08'den küçük ve 0.009/0.012'den büyükse, ve aynı yönde iki ölçüm geldiyse balonlar
    kaydırılır.
  - Telefon 0.05'ten az kaydıysa panel yerinde kalır.
- Mesajlarda harita tuşları ("RECENTER") görülürse bu harita ekranıdır, panel kalkar.

## 10. Harita kartı (Ek; yalnız GTA 6)

- Karenin üst 0.03'ünden alt 0.95'ine kadarki kısmı kendi okuyucusuyla okunur.
  - Normalde **2 sn'de** bir okunur.
  - Harita açıkken ve kapandıktan sonraki 10 sn boyunca **1.5 sn'de** bir okunur.
- **Harita ekranı** şöyle tanınır: tuş listesinden en az 2 farklı yazı görülmeli.
  - Tuşlar: recenter, 2d view, 3d view, add marker, remove marker, set destination, remove destination,
    close menu.
  - İşaretçi görünümünde ayrıca: view on map, markers, cinematic.
  - Görüldükten sonra harita **5 sn** açık sayılır. Bu sürede altyazı okunmaz.
- **Kart** şöyle bulunur:
  - Sol 0.30'un dışında kalan satırlar alınır. Uzaklık etiketleri ("1.53 km") ve baştaki simgeler
    temizlenir.
  - En az 3 sözcük ve 6 küçük harf taşıyan ilk cümle satırı kartın başıdır.
  - Altındaki hizalı cümle satırları da karta katılır.
  - Hemen üstteki büyük harfli satır başlıktır ("BUY FLOWERS").
- Kart gösterilmez:
  - Türkçe harf varsa (PS5 bildirimi).
  - Başlıksız ve 6 sözcükten kısaysa.
  - Başlıksız ve sağ üstteyse (sol > 0.6, üst < 0.32).
  - Üst kenarı 0.1'in üstündeyse.
- Çeviri:
  - Başlık ve cümleler tek istekte havuza sorulur, kalanlar cihazda aynı anda çevrilir (en çok 60 sn).
  - Başlık hedef dilin büyük harfiyle yazılır.
  - Dükkân ya da mekân adı olan başlık çevrilmez ("RIDEOUT CUSTOMS").
  - Bilinen yanlış çeviriler küçük bir düzeltme listesiyle düzeltilir (para ve madde adlarındaki yaygın yanlışlar).
- Hafıza:
  - Kart hafızası en çok 200 karttır.
  - Çeviri sürerken imleç başka karta geçerse en son kart çevrilir.
  - Aynı kartın yarım okuması tam okumanın yerine geçmez.
- Yer:
  - Türkçe, kartın koyu çerçevesinin hemen altına yazılır, yer yoksa üstüne. O da yetmezse yazı küçülür.
  - Çerçeve parlaklığı 130'dan düşük noktalar izlenerek bulunur.
- Kalkma: telefon paneliyle ortak histerezis (§9): 3 kaçırılan okuma + en az 4 sn + kartın bölgesi görüntüsel
  olarak değişti. Başka kart gelince hemen değişir.

## 11. Görev ve ek alanlar (Ek)

- Altyazı bölgesinin yanında en çok **3** ek alan tanımlanabilir. Bunlar ayrı ve **1 sn'de** bir okunur.
  Hazır seçimler:
  - Görev (sağ üst): üst 0.03, alt 0.30, sol 0.66, sağ 0.98.
  - Bildirim (sol alt): üst 0.58, alt 0.88, sol 0.02, sağ 0.30.
  - Telefon mesajı (sağ alt): üst 0.50, alt 0.95, sol 0.72, sağ 0.98.
- Bir alanın izi değişmediyse alan yeniden okunmaz. Yazı kararlı olunca çevrilir: iz bir tur boyunca
  aynı kalmalı ya da arka arkaya iki okuma aynı sonucu vermeli.
- Okuma hatası alanı boş saymaz. Eski kutu kalır.
- Satırlar şu kurallarla süzülür:
  - Kumanda ipuçları ve çöpler atılır.
  - En az 2 harf ve 2 harfli bir sözcük olmalı.
  - Satırlar parçalara birleşir. Önceki parça cümleyi bitirdiyse ya da kısa bir başlıksa (en çok 3
    sözcük, virgülsüz) ve yeni satır büyük harfle başlıyorsa yeni parça başlar.
- Çevirisi aslıyla 0.90 ve üstü benzeyen alan gösterilmez.
- Aynı yazı ikinci kez çevrilmez. Alanda yazı kalmayınca o alanın kutusu ekrandan silinir.

## 12. Ekranı çevir (Ek)

- Düğmeye basılınca sıradaki karenin **tamamı** bir kez okunur. Bunun için ayrı bir okuyucu kullanılır.
- Satırlar şöyle süzülür: kumanda ipuçları ve çöpler atılır. En az 2 harf ve 2 harfli bir sözcük
  olmalıdır.
- Satırlar yerlerine göre gruplanır. Bir satır üstündeki satırın grubuna şu koşullarla katılır:
  - Aradaki boşluk satır boyunun 0.8 katından az.
  - Yatay örtüşme dar olanın en az yarısı.
  - Boylar en çok 1.6 kat farklı.
  - İki ayrı sütunu birleştiren geniş satır gruba katılmaz.
- En çok **30** grup çevrilir.
- Yapay zekâ çevirmeninde bütün parçalar tek istekte gider. Değilse gruplar sırayla çevrilip
  hazırlandıkça gösterilir.
- Çevirisi aslıyla 0.90 ve üstü benzeyen grup gösterilmez.
- Sonuçlar ekranda `en az 12000, en çok 60000, 8000 + harf × 50` ms kalır.
- Düğmeye yeniden basmak sonuçları kaldırır. Ekran çevirisi açıkken telefon ve harita okunmaz.

## 13. Oyun algılama (Ek)

- **Öncelik:**
  1. PS5'in bildirdiği oyun.
  2. Kullanıcının seçtiği oyun.
  3. Paketten tanınan oyun.
  4. Ekrandan tanınan oyun.
- PS5 başka bir oyun bildirirse kullanıcının seçimi silinir.
- **PS5 kimliği** dört büyük harf + beş rakamdan oluşur, isteğe bağlı "_00" eki olabilir. Ad en çok
  120 karakterdir; denetim karakterleri atılır.
- **Paketten:** Son **20** gösterilen satırdan en az **5**'i yalnız tek bir pakette bulunan anahtarla
  geldiyse oyun o pakettir. Ortak "genel" paket sayılmaz.
- **Ekran yazısından (GTA 6):**
  - Harita tuş listesi görülürse.
  - "jason" ve "lucia" aynı satırdaysa.
  - "brief" ve "progress" ile birlikte jason, lucia ya da map görülürse.
  - "whatup" görülürse.
  - Oyunun telefonu okunursa.
- **Sunucuya kare sorma:** Oyun bilinmiyorsa kare 768 genişliğe küçültülür ve gri JPEG (kalite 60)
  olarak sunucuya gönderilir.
  - İlk deneme 8 sn sonra yapılır, sonra dakikada bir, en çok 6 kez.
  - Ekrandan tanındıktan sonra 5 dk sonra bir kez doğrulanır, sonra 20 dakikada bir, en çok 12 kez.
  - Yalnız ortak havuz açıksa yapılır.
- Oyun 2 dakika sonra hâlâ bilinmiyorsa oyun sorma kartıyla bir kez sorulur.
- Oyun adı karşılaştırma için sadeleştirilir:
  - Aksanlar atılır, Roma rakamları sayıya çevrilir.
  - Uzun adlar kısaltılır: "grand theft auto" → "gta".
  - Harf ve rakam ayrılır: "Grand Theft Auto VI" = "GTA 6".

## 14. Satır kaydırma (Ek)

- Telefondaki altyazı ekranında bir satır en çok **42** harf, en çok **3** satır olur.
- Bölme sözcük sınırından ve dengeli yapılır: en uzun satırı en kısa yapan seçenek seçilir, eşitlikte
  kareler toplamı küçük olan.
- 3 satıra sığmazsa yazı en çok **0.75**'e kadar küçülür.
- 42 harften kısa ya da zaten satır sonu içeren yazıya dokunulmaz.
- Konuşan adı ("ARTHUR:") sonraki sözcükle birlikte tutulur. Böylece hep ilk satırdadır ve satır
  sonunda tek kalmaz.
- Telefon ekranındaki satır bildirilen süre kadar kalır. Bu süre en az **1200 ms**'dir. Süre
  bildirilmezse `en çok 8000, 2000 + harf × 60` ms kalır.

## 15. Girdi → beklenen çıktı örnekleri (eski testlerden)

Örneklerin süreleri saatle verildi. "Okuma" bir yazı tanıma sonucudur.

1. "Nobody saw us leave" → 1. okuma: hiçbir şey. 2. okuma: çevir. 3. okuma: hiçbir şey.
2. "Nobody saw us leave." / "Wait!" / "Who are you?" / "I know…" / "\"Run.\"" → 1. okumada çevir. Aynı
   okuma tekrar gelirse hiçbir şey.
3. "The bridge will not last" iki kez, sonra "The bridqe will not last" iki kez → yalnız bir çeviri.
4. Göstergede "24 / 120" ile boş okuma 20 kez gidip geliyor → hiç çeviri yok.
5. Daktilo efekti: "Nobody", "Nobody saw us", "Nobody saw us leave the camp, kid." → son okumada bir
   çeviri, sonra hiçbir şey.
6. "Hello there" iki kez, sonra boş okumalar → 799 ms'de hiçbir şey, 800 ms'de temizle, sonra yine
   hiçbir şey.
7. "Hold the gate" ekranda. 50 ms aralıkla 10 boş okuma, ardından 4 dolu okuma; bu üç kez tekrarlanıyor
   → ne temizle ne yeni çeviri çıkar.
8. "Hold the gate." temizlendi. 1500 ms içinde "Hold the gate" iki kez → ikinci okumada geri getir
   ("Hold the gate.").
9. Aynı durumda 1501 ms sonra "Hold the gate." → yeniden çevir.
10. "Hold the gate." → "Run!" → "Hold the gate." → "Run!", her biri 100 ms arayla → çevir, çevir, geri
    getir, geri getir.
11. "I can carry that for you later." çevrildi, sonra "I can't carry that for you later." → ikisi de
    çevrilir.
12. "Through the frozen pass, Kai rode,\nwishing the storm would let him rest." çevrildi, sonra "Through
    the frozen pass O rode," iki kez → hiçbir şey. Ardından "We should rest here." → çevir.
13. Yol tarifi atılır: "Turn Left 120 ft 98 ft", "Keep Left O ft 2 ft", "Turn left", "Make a U-turn".
    Kalır: "Turn right after the bridge, alright?", "Keep walking, the camp is close.", "Turn it down!"
14. Kaydırma: "Gitmeliyiz, hemen." → olduğu gibi, ölçek 1. Uzun cümle → 2 satır, satır uzunlukları
    arasında en çok 12 harf fark. Çok uzun cümle → 3 satır ve ölçek 0.75 ile 1 arasında.

---

## Belirsizlikler

- **Süre mi kare mi:** Eski hat tamamen saatle çalışıyor. Tarif kare sayıyor. Okuma en çok saniyede 5
  kare olduğundan şu karşılıklar yaklaşıktır:
  - 800 ms ≈ 4 okuma.
  - 4000 ms ≈ 20 okuma.
  - 1500 ms ≈ 7–8 okuma.
  Değişmeyen bölgede okuma yeniden kullanıldığı için gerçek okuma sayısı daha da az olabilir. Yeni
  çekirdekte bu değerlerin kareye nasıl çevrileceğine karar verilmeli.
- **Kararlılık 2 mi 3 mü:** Eski hat 2 okumada ve cümle sonu işaretinde 1 okumada gönderiyor. Tarif 3
  kare istiyor. Hız farkı fark edilir olabilir.
- **ML Kit güveni:** Eski kod güven değerini hiç kullanmıyor. Tarifteki 0.40 süzgeci ML Kit'le nasıl
  çalışacak, ölçülmedi.
- **Karenin çözünürlüğü:** Kodda 1280×720 ve 960×540 geçiyor ama Remote Play karesinin gerçek boyutu
  belgelenmemiş. OCR'de ölçek yapılmadığı için okuma kalitesi bu boyuta bağlı.
- **"Bitti" olayı:** Eski hatta yazı değişince ayrı bir "bitti" yok, yalnız boş bölgede "temizle" var.
  Tarifin "önce bitti, sonra başladı" sırası TV tarafında kutunun yanıp sönmesine yol açabilir; bu
  denenmedi.
- **Geri dönen yazı:** Eski hatta pencere 1500 ms ve 5 satır. Tarifte 32 altyazılık tekrar listesi var.
  İkisinin aynı işi mi gördüğü, yoksa ikisinin de mi gerektiği belli değil.
- **Bekletme katmanı:** 800/300/4000 ms beklemeleri ve çeviri sırası tarifte yok. Bunlar okuma hattına
  mı, çeviri katmanına mı ait, karar verilmeli.
- **GTA 6'ya özgü özellikler:** Telefon, harita kartı, oyun işaretleri ve 0.935 çizgisi yalnız GTA 6
  için yazılmış. Eşiklerin çoğu tek bir oyunda, gerçek karelerle ayarlanmış. Yeni çekirdeğe genel
  özellik olarak mı, oyun eklentisi olarak mı alınacağı açık değil.
- **Varsayılan bölge:** Eski Android varsayılanı (0.14–0.86 × 0.62–0.97) masaüstüyle aynı olduğunu
  söylüyor, tariften farklı. Hangisinin doğru olduğu doğrulanmalı.
- **Arayüz yazısı listesi:** Tarifteki liste eski hatta yok. Eski hat aynı işi blok seçimi, menü tanıma
  ve kumanda ipucu kurallarıyla yapıyor. Tek başına sözcük listesinin yeterli olup olmadığı belli
  değil.
- **Satır birleştirme:** Tarif satırları boşlukla birleştiriyor. Eski hat alt satırla birleştirip satır
  bilgisini "eksik satır" ve "bekleyende kalan satırı koru" kurallarında kullanıyor. Boşlukla
  birleştirilirse bu kurallar çalışmaz.

## Uygulama notları

Yeni Android'de tarifin belirsiz bıraktığı yerler için seçilen değerler. Hepsi gerçek GTA 6 kareleriyle
(`core/Tests/NinoAppCoreTests/Fixtures/gta6-*.jpg`, 22 kare) `RealGta6FramesTest` içinde sınanır. Tarifte sayısı
yazan eşikler (beyaz 118/45, koyu yan 90, %70/%85/%35, boy 0.38–0.86, oran 1.2–2.6, orta 0.30–0.80, koyu ekran 75,
gövde 85, yazı 110, %45/%50 tutma) değişmedi.

- **Telefon şeridi (9):** Ekranın yanındaki açık gövde ya da açık zemin, ince koyu bir kenarla ayrılıp ≤3 noktalık
  boşluk kuralıyla şeride katılabiliyor. Bu yüzden birleşen öbeğin her alt parçasının başı ve sonu da şerit sayılır.
- **Sağ kenar:** Sağ kenar sol kenara koşut sayılır. Adayın satırlarında en sık görülen en seçilir. Satırın şeridi
  en az bu en kadar olmalıdır (parlama ya da açık zemin taşabilir). Kutu sol doğru ve bu enle çizilir.
- **Oran:** Boy/en oranında en, satırın (ekranın) enidir. Eğik telefonda kutunun eni kullanılmaz.
- **Kesintisiz ekran:** Uyan satırlar en çok karenin %20'si kadar boşlukla öbeklenir; en büyük öbek alınır ve en az
  %30'u dolu olmalıdır. Perde ve pencere gibi araya başka şey giren beyazlar telefon sayılmaz. Mavi balon ve
  fotoğraf satırları boşluk bırakır.
- **32 aday:** Adaylar oy yerine bulunan ekran satırı sayısına göre sıralanır, ilk 32'si sınanır.
- **Koyu çerçeve:** Ekranın hemen dışında 1–3 nokta içinde en koyu kanalı 90'dan düşük nokta.
- **Gölgedeki telefon (ek):** Aydınlık sahnede (parlaklık dilimi > 117) gölgedeki telefonun ekranı 100–115 kalıyor.
  Beyaz arama bulamazsa kare 1.3 kat aydınlatılıp beyaz arama yinelenir (koyu temadan önce).
- **Koyu tema gövdesi:** Gövde ≥ 85, ekranın kenarından 1–10 nokta ve üst/alt 3 satır içinde aranır (ekranın siyah
  kenarlığı ve gölge gövdeyi kapatıyor). Beyaz yazı da komşu satırlarda aranır (240×135 karede ince yazı satır
  atlıyor).
- **Son yerde tutma:** %50 kuralı korundu. Rydeme'nin alt penceresi açıkken (`telefon-koyu-altpencere`) koyu ekran
  ~%42'ye iniyor; bu karede telefon tutulmuyor.
- **Mavi balon:** Balonun rengi kutudaki noktaların parlak yarısının ortalamasıdır (yazı atılır). "Belirgin mavi":
  mavi ≥ 100, maviden kırmızı farkı ≥ 10, yeşil farkı ≥ 8 (oyundaki giden balon açık lavanta: fark 12–37).
- **Harita kartı çerçevesi (10):** Yazı kutusunun 2 nokta altından ve üstünden, satırın %60'ı 130'dan koyu ve başlangıç
  satırının ortancasından en çok 20 farklı kaldıkça ilerlenir. İşaretçi görünümünde kartın altı da koyu sahne
  olduğu için benzerlik şartı gerekiyor.
- **Görev karesi (11):** `gta6-gorev-pembe` karesinde hedef yazısı ("Go to Jason's room") ekranın alt ortasında
  (y ≈ 0.95), üç hazır ek alanın hiçbirinde değil. 0.895 görev şeridi çizgisinin altında kaldığı için altyazı
  sayılmaz; okunması için özel ek alan gerekir.
- **`gta6-altyazi-beyaz`:** Bu karede telefon da var (ekran x ≈ 0.66–0.91) ve bulunuyor. Altyazı telefonun dışında
  ve altında kaldığı için okunur, telefonun içindeki satırlar atılır.
- **Hizmet:** Havuz kurulamadığında ya da klipte (havuz yok) "dil havuz öncelikli mi" sorusu varsayılan havuz
  ayarıyla (`PoolConfig`: GTA 6, `tr`) cevaplanır. Böylece oyun bilinmiyorken ve hedef Türkçeyken telefon ve harita
  okunur. Klipte oyun teması ve oyun tanıma kapalı kalır (servis.md 16.2); yalnız "oyun bilinmiyor" kuralları
  (telefonun içi, 0.8 çizgisi, son mesajlar, boyama) çalışır. Deneme kaynağı kareleri video aralığında YUV 4:2:0
  olarak verir (renk olmadan telefon aranmaz).
- **Sıra (hizmet):** Kare önce telefon aramasına, sonra altyazı okumasına verilir; yeni sahnenin ilk okumasında
  telefon yazısı altyazıya kaçmasın (emülatörde `telefon-altin-kapi` karesinin mesajı altyazı olarak gidiyordu).
- **Harita kartı ve telefon:** Açık telefonun içindeki satırlar (0.02 payla; alt kenar boyamadaki gibi en çok 0.84'e uzatılır) harita kartı aranırken atılır.
- **Sohbet listesi önce:** Liste kuralı uygulama adından önce bakılır; önizlemesinde "BuckMe" geçen sohbet listesi
  uygulama ekranı sayılıp satır satır çevrilmez.
- **Klipte uygulama yazıları:** Oyun bilinmiyorken (klipte oyun hiç tanınmaz) "her zaman atılanlar" çalışmaz. Ama
  bilinen uygulama satırları ("Change Destination", "Book Ryde ($82)", "Choose Ryde", "Standard Ryde", "Trip Details",
  BuckMe, Rydeme) satırın **tamamı** olarak okunursa oyun bilinmese ve telefon görülmese de atılır (fiyat eki yok
  sayılır; bu sözcükleri yalnız içeren cümle atılmaz). Böylece telefon bulunamayan karede (`telefon-koyu-altpencere`)
  "Change Destination" altyazıya kaçmaz (`RealGta6FramesTest`).
- **Klipte harita → telefon:** Harita görüldükten sonra 13 sn (açık 5 + 8) telefon aranmaz (tarif). Kliplerde harita
  karelerinin hemen ardından gelen telefon karesinde (`telefon-altin-kapi`) bu sürede telefon yazısı altyazı olarak
  okunabiliyor; tarif değiştirilmedi.
