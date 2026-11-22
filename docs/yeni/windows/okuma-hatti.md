# Windows okuma hattı: tarif (1. bölüm)

Bu belge, Windows uygulamasının PS5 karesinden TV'ye giden altyazı satırına kadar yaptığı her şeyi **davranış olarak**
anlatır: sıra, eşik, sayı, kural, örnek. Kod yoktur. Yeni kodu yazan, eski koda hiç bakmadan bu belgeyle aynı davranışı
kurabilmeli ve buradaki örneklerle testlerini yazabilmelidir.

- **1. bölüm (bu dosya):** ortak kurallar, görüntü, OCR çıktısının soyut biçimi, Windows yazı tanıması ve yazım denetimi,
  kare girişi, okuma planı, satır süzgeçleri, sabitleyici, metin karşılaştırma kuralları, çeviriye gönderme (bekletme,
  sıra, geç sonuç, paket), konuşan adı, oyun deyimleri, ölçümler.
- **2. bölüm (`okuma-hatti-2.md`):** ek alanlar (sürekli okunan köşe yazıları), tek seferlik bölge çevirisi, "ekranı
  çevir", altyazı alanı hazır seçimleri, bilgisayardaki altyazı penceresinin yığını ve sarma, oyunun tanınması, Mac'le
  farklar, testlerin sahte parçaları ve `Fixtures` klasörü, ekran dökümü aracı, emin olunmayan noktalar.

Başka konuların ayrıntısı kendi belgelerindedir; burada yalnız kesiştikleri yer anlatılır: telefon paneli ve harita
kartı (telefon/harita belgesi), paket ve havuz araması (paketler/havuz belgesi), çeviri motorları (çeviri belgesi), TV'ye
giden mesajların biçimi (TV bağlantısı belgesi), ayar dosyası (ayarlar belgesi).

---

## 0. Ortak kurallar

- **Koordinat:** Her kutu oran olarak verilir (0–1), başlangıç sol üst köşe. Kutu dört sayıdır: **sol, üst, sağ, alt**.
  Bir kutu ya karenin tamamına ya da okunan alana göredir; hangisi olduğu her yerde ayrıca söylenir.
- **Alan içi → kare (yerleştirme):** Alanın (sol A_s, üst A_ü, sağ A_r, alt A_a) içindeki kutu kareye şöyle taşınır:
  `kare_sol = A_s + kutu_sol × (A_r − A_s)`, `kare_üst = A_ü + kutu_üst × (A_a − A_ü)`, sağ ve alt aynı yolla.
- **Birleşim:** İki kutunun birleşimi: sollarının ve üstlerinin küçüğü, sağlarının ve altlarının büyüğü.
- **Bölge kaydı (ayarlardaki altyazı bölgesi) alan sırası:** **üst, alt, sol, sağ** (dikkat: kutudan farklı sıra).
  Varsayılanı üst **0,62**, alt **0,97**, sol **0,14**, sağ **0,86**.
- **Saat:** Bütün süreler **milisaniye saatiyle** ölçülür (işletim sisteminin açılıştan beri geçen milisaniyesi,
  64 bit). Hattın, sabitleyicinin ve ek alan izleyicisinin saati dışarıdan verilebilir; testler sahte saatle çalışır.
- **Sözcük bölme:** Aksi söylenmedikçe "sözcükler" metnin boşluk karakterlerinden (boşluk, sekme, satır sonu…)
  bölünüp boş parçaların atılmasıdır.
- **Kültürden bağımsızlık:** Küçük/büyük harfe çevirme her yerde **kültürden bağımsız** yapılır. Türkçe Windows'ta
  "I" ile "ı" sorunu çıkmamalı (bkz. yol tarifi örneği §7.2).
- **Sadeleştirme (anahtar):** Metin kültürden bağımsız küçük harfe çevrilir; her karakter harf (büyük, küçük, başlık,
  niteleyici, diğer harf), birleşen işaret (boşluksuz, boşluklu, çevreleyen) ya da sayı (ondalık rakam, harf sayı, diğer
  sayı) ise kalır, değilse boşluk olur; boşluklar teke iner, baş/son boşluk gider.
  - `Mara: We are NOT out of rope, kid.` → `mara we are not out of rope kid`
- **Satır satır sadeleştirme:** `\r\n` → `\n`; her satır ayrı sadeleştirilir; boş kalan satırlar atılır; satırlar `\n`
  ile birleşir.
- **Benzerlik oranı:** `1 − karakter_düzenleme_uzaklığı / uzun_olanın_uzunluğu` (ekleme, silme, değiştirme birer). İki
  metin birebir aynıysa benzerdir (boş değilse). Biri boşsa benzer değildir. Varsayılan eşik **0,85**; oran eşiğe eşit ya
  da büyükse benzer.
  - `the boat will not wait` ~ `the boal will not wait` → benzer
  - `we are out of rope` ~ `the boat will not wait` → benzer değil
  - `""` ~ `abc` → benzer değil
- **Cümle sonu:** Metin kırpılır, sondaki `" ' ” ’ » ) ]` karakterleri atılır; kalan boş değilse ve son karakteri
  `. ! ? …` ise satır cümleyi bitirir.
- **Altyazı günlüğü:** Hat, olayları tek satırlık günlük kayıtlarına yazar (kararları değiştirmez; hızlı olmalı, kilit
  altında çağrılır). Kayıtların **sözcükleri serbesttir**; bu belgede her kayıt [köşeli parantez içinde olayın anlamı ve
  taşıdığı veri] olarak verilir. İsteğe bağlı kayıtlar istek numarasıyla (`#N`) başlar.
- **Alıntı (günlük için):** Satır sonlarında bölünen parçalar kırpılıp boşlar atılır, ` / ` ile birleşir; 120 Unicode
  karakterini aşarsa ilk 119'u ve `…` alınır; çift tırnak içine konur. Günlük satırlarındaki bütün metin alıntıları
  böyledir.

---

## 1. Görüntü (kare) biçimi

- Kare **BGRA** baytlarıdır (piksel başına 4 bayt: mavi, yeşil, kırmızı, saydamlık), genişlik, yükseklik ve satır adımı
  (bir satırın bayt uzunluğu) ile. Hat içinde üretilen her kare sıkıdır (satır adımı = genişlik × 4).
- **Yerel tampondan kopya:** Akıştan gelen bellek, geri çağrı döndükten sonra kullanılamaz; bu yüzden hemen kopyalanır: her satırı kendi satır
  adımıyla okunup sıkı bir kareye kopyalanır.
- **Boş kare:** Bütün baytları 0 olan kare (testlerde 64 × 64 boş kare çok kullanılır).
- **Kırpma (piksel):** İstenen x, y önce 0…genişlik / 0…yükseklik arasına sıkıştırılır; genişlik 0…(genişlik − x),
  yükseklik 0…(yükseklik − y) arasına. Sonuç yeni, sıkı bir karedir.
- **Bölgeyi kesme (oran → piksel):** sol = aşağı yuvarla(genişlik × sol), üst = aşağı yuvarla(yükseklik × üst),
  sağ = yukarı yuvarla(genişlik × sağ), alt = yukarı yuvarla(yükseklik × alt); sonra yukarıdaki kırpma.
  - 1920 × 1080 karede varsayılan bölge → 1382–1384 piksel geniş, 378–379 piksel yüksek.
  - 10 × 10 karede sağ alt pikselin mavisi 200 ise, (üst 0,5 / alt 1 / sol 0,5 / sağ 1) kesiminin sağ alt pikselinin
    mavisi de 200'dür.
- **Büyütme (×n, iki doğrusal):** Hedef piksel (tx, ty) için kaynak konumu `sy = min((ty + 0,5) / n − 0,5,
  yükseklik − 1)`, eksiyse 0; `y0 = tam kısmı`, `y1 = min(y0 + 1, yükseklik − 1)`, `fy = sy − y0`; x için de aynısı.
  Dört kanalın her biri ayrı: üst = P(x0,y0) + (P(x1,y0) − P(x0,y0)) × fx, alt aynı yolla y1'de, sonuç =
  üst + (alt − üst) × fy, **en yakın çifte yuvarlanarak** (yarım değerler çift sayıya) bayta.
- **Maskeleme (telefon):** Kesilmiş alanın, verilen kare kutusuna (kareye oranla) düşen kısmı siyaha boyanır. Kutu her
  yandan **0,01** genişletilir, alanın oranlarına çevrilir; alanın dışında kalıyorsa (sağ ≤ 0, sol ≥ 1, alt ≤ 0,
  üst ≥ 1) alan olduğu gibi döner; alan genişliği ya da yüksekliği 0 ya da eksiyse de öyle. Değilse alanın kopyasında
  x0 = aşağı yuvarla(max(0, sol) × genişlik), x1 = yukarı yuvarla(min(1, sağ) × genişlik), y için de aynısı;
  o dikdörtgendeki pikseller B=G=R=0, saydamlık 255 olur.
- **Bölge izi (yazı tanımadan karşılaştırma):** **64 sütun × 12 satır** = 768 gri bayt. Satır y (0…11) için kaynak satır
  `y × yükseklik / 12` (tam sayı bölme), sütun x (0…63) için kaynak sütun `x × genişlik / 64` (tam sayı bölme); değer
  `(mavi + 2 × yeşil + kırmızı) / 4` (tam sayı). Genişlik ya da yükseklik 0 ise iz 768 sıfırdır.
  - 640 × 120, bütün baytları 50 olan karenin izi 768 uzunluktadır; aynı kare aynı izi, bütün baytları 200 olan kare
    başka izi verir.

---

## 2. OCR çıktısının soyut biçimi (bütün platformlar aynı)

Okuma hattı yazı tanımanın çıktısını tek bir soyut biçimle alır. Windows bunu Windows.Media.Ocr ile (§3), Linux
Tesseract ile doldurur; hattın geri kalanı hangi okuyucunun çalıştığını bilmez.

### 2.1 Satır ve okuma

- **Satır:** metin + **kutu** (isteğe bağlı) + **güven** (isteğe bağlı).
  - Kutu, okuyucuya **verilen görüntünün** kenarlarına oranla (0–1, sol üst başlangıç) sol, üst, sağ, alttır. Okuyucu yer
    vermiyorsa kutu yoktur.
  - Güven 0–1 arası bir sayıdır. Windows'un yazı tanıması güven **vermez** (yok); Tesseract verebilir.
- **Okuma:** satırların yukarıdan aşağı sıralı listesi. Okuma kurulurken metni boş ya da yalnız boşluk olan satırlar
  **atılır**. Boş okuma: hiç satır yok.
- **Okumanın metni:** satır metinleri `\n` ile birleşmiş hali.
- **Okumanın kutusu:** yeri bilinen bütün satır kutularının birleşimi; hiçbir satırın yeri bilinmiyorsa yok.
- **Okumanın güveni:** güveni bilinen satırların ortalaması; hiçbiri bilinmiyorsa yok.
  - (Hold 0,9) (the gate 0,7) (now, yok) → 0,8. Düğme ipucu ve çöp temizliğinden sonra da 0,8 kalır.
- **Yalnız metin veren okuyucu:** Metin `\r\n` → `\n` ile satırlara bölünür, her satır kırpılır, **kutusuz ve güvensiz**
  satır olur. Kutusuz satırlar bütün yer kurallarından (dev yazı, kesik satır, blok seçimi, ortalama, telefon…) **muaf**
  geçer. Hat testlerinin çoğu böyle okuyucularla yazılmıştır.
- **Yerleştirme:** Okumanın bütün satır kutuları bir alanın içinden dış çerçeveye taşınabilir (§0 formülü); kutusuz
  satırlar kutusuz kalır.

### 2.2 Okuyucu arayüzü

Okuyucunun üç işi vardır:

1. **Metin oku (görüntü):** düz metin.
2. **Metin oku (görüntü, derin mi):** varsayılanı (1)'dir; derin bayrağı yok sayılır.
3. **Satırları oku (görüntü, derin mi):** okuma (§2.1). Varsayılanı: (2)'nin metninden yalnız-metin okuması.

"Derin" okuma: görüntüde hiç satır bulunmazsa büyütülmüş yedek okumalar da denensin mi (§2.3). Derin değilse yalnız bir
okuma yapılır (işlemciyi çok daha az yorar).

Uygulama **ayrı okuyucu örnekleri** kurar: altyazı hattının okuyucusu (aynı örnek tek seferlik bölge çevirisinde ve
"ekranı çevir"de de kullanılır), ek alan izleyicisinin kendi okuyucusu (aynı motor iki okumayı birden yapamaz; ek alan
altyazıyı bekletmesin) ve telefon/harita için **tek geçişli** okuyucular (hazırlık yok, büyütme yok, seviye yok: kare
olduğu gibi bir kez okunur).

### 2.3 Derin okuma (çekirdekte, platformdan bağımsız)

Boş bölgede "Go!" gibi kısa satırlar geniş alanda sık sık hiç bulunmaz. Derin okumada:

1. Görüntü bir kez okunur; en az bir satır varsa o döner.
2. Yoksa **iki yedek okuma aynı anda** (paralel) yapılır:
   - **Orta şerit:** genişliğin %40'ı, ortada. `şerit_genişliği = genişlik × 0,4`, `sol = (genişlik − şerit) / 2`,
     `x = aşağı yuvarla(sol)`, `w = yukarı yuvarla(sol + şerit) − x`. Şerit (tüm yükseklik) kesilir, **2 kat** büyütülür,
     okunur; bulunan kutular şeridin değil, **görüntünün tamamının** oranlarıyla verilir (şerit kutusu
     `(x/genişlik, 0, (x+w)/genişlik, 1)` içinden yerleştirilir).
   - **Bütün görüntü 2 kat büyütülmüş** okunur.
3. İkisi de satır bulursa **şeridinki** seçilir; yalnız biri bulursa o; hiçbiri bulmazsa boş okuma.

Örnekler (64 × 64 görüntü):
- Şerit: x = 19, w = 26; büyütülmüş şerit 52 piksel geniş. Şeritte (0, 0,5, 1, 1) kutulu "Go!" bulunursa sonuç kutusu
  sol 19/64, sağ 45/64, üst 0,5.
- Tam okuma boş, şerit okuması "Go!" → "Go!".
- Tam boş, 128 genişlikli (bütün büyütülmüş) okuma "G0!", şerit "Go!" → "Go!".
- Tam okuma "Shut the vent" bulursa okuyucu **bir kez** çağrılır.
- İki yedek okuma birbirini bekleyen bir engelle buluşabilmeli (yani gerçekten aynı anda çalışmalı).

---

## 3. Windows'a özgü: yazı tanıma (Windows.Media.Ocr)

Bu bölüm platforma bağlıdır; Linux okuyucusu §2'deki arayüzü kendi yoluyla doldurur. Hazırlık zinciri ve seçim
mantığı Windows okuyucusunun içindedir (çekirdekte değil).

### 3.1 Motorun kurulması

- Oyun dilinin etiketiyle (ör. "en") motor kurulmaya çalışılır; olmazsa **kullanıcının profil dillerinden** kurulur
  (Latin alfabeli diller İngilizceyi de okuyabilir). İkisi de olmazsa okuyucu yoktur (uygulama "OCR dili eksik"
  durumuna geçer; hat kurulmaz).
- Ayrıca "bu dilin OCR paketi yüklü mü" sorulabilir; yüklü değilse ayarlar ekranı eklenmesini önerir. Okuyucu kurulsa
  bile dil paketi yoksa "OCR eksik" bayrağı açık kalır.
- **Tek motor, tek okuma:** Bir motor aynı anda iki okuma yapamaz ("başka bir okuma sürüyor" hatası). Her okuyucu
  örneği kendi motorunu bir kilitle sıraya sokar; derin okumanın paralel iki yedeği de bu kilitte sıralanır.
- Okuma eşzamanlı beklenir (yazı tanımanın zaman uyumsuz işlemi başlatılır ve sonucu beklenir).

### 3.2 Tek bir okuma

- Görüntü **40 pikselden** dar ya da kısaysa, ya da motorun izin verdiği en büyük boyutu aşıyorsa okuma yapılmaz, boş
  okuma döner.
- Görüntü BGRA 8 bit, "önceden çarpılmış saydamlık" biçimli bir yazılım bit eşlemine kopyalanıp okunur.
- Motorun her satırı sözcük kutularıyla gelir. Satır şöyle **bölünür:** satır yüksekliği = sözcük kutularının en yüksek
  olanı; ardışık iki sözcük arasındaki boşluk (sonrakinin solu − öncekinin sağı, piksel) **satır yüksekliğinin 4 katını ve
  görüntü genişliğinin %12'sini birlikte aşıyorsa** orada ayrı satır başlar (soldaki menü ile sağdaki gösterge).
  - (boşluk 900, yükseklik 30, genişlik 1920) → ayrı
  - (150, 30, 1920) ve (200, 30, 1920) → ayrı değil (okunamayan sözcüklerin bıraktığı boşluk)
  - (120, 20, 1920) → ayrı değil
- Her parçanın kutusu, sözcük kutularının birleşimidir, görüntü genişliği/yüksekliğine bölünmüş oran olarak.
- Parçanın metni: satır hiç bölünmediyse **motorun verdiği satır metni** (sözcük arasında boşluk kullanmayan
  dillerde metin bölünmesin); bölündüyse parçanın sözcükleri tek boşlukla. Kırpılır. Güven yok.
- Satırlar kutularının üst kenarına göre sıralanır (yeri olmayan 0 sayılır; eşitlikte geliş sırası korunur).

### 3.3 Hazırlıklar (görüntü süzgeçleri)

Hepsi siyah-beyaz bir görüntü üretir: "yazı" sayılan piksel **siyah (0)**, geri kalan **beyaz (255)**, saydamlık 255.
Parlaklık (luma) her yerde `(3 × kırmızı + 6 × yeşil + mavi) / 10` tam sayı bölmesiyle.

- **Otomatik seviye:** Parlaklık çubuk grafiği çıkarılır. `sınır = genişlik × yükseklik × 0,005`. 255'ten aşağı
  inerek sayılar toplanır; toplam sınıra ulaştığı ilk değer "tepe"dir (hiç ulaşmazsa 0). Tepe **235 ve üstü** ya da
  **60'ın altı** ise görüntü değişmez. Değilse `oran = 250 / tepe`; her renk kanalı `min(255, tam_kısım(değer × oran))`
  olur, saydamlık 255. (Karanlık ya da soluk görüntüde beyaz altyazı 120–180'de kalıyor, beyaz yazı süzgeçleri devreye hiç girmiyordu.)
- **Beyaz yazı (simetrik):** Parlak piksel: en küçük kanal ≥ **200** ve (en büyük − en küçük) ≤ **45**. Koyu piksel:
  parlaklık < **110**. Parlak bir pikselin çevresindeki kare pencerede (her yöne **5** piksel, kenarlarda kırpılmış) en
  az bir koyu piksel varsa o piksel yazıdır. (Pencere sayımı toplamlı tabloyla tek adımda yapılır.)
  - Örnek (60 × 20, yarıçap 3): x 0–29 parlak kum (230), x 40–43 koyu kenar (20), x 44–47 beyaz harf (250). Sonuç:
    x=5 beyaz (zemin), x=45 siyah (harf), x=41 beyaz (kenar).
- **Gölgeli yazı (yarıçap r, en az parlaklık p, en çok yayılım s, koyu sınırı k, renkli mi):** Parlak piksel: (en küçük
  kanal ≥ p ve en büyük − en küçük ≤ s) ya da (renkli açıksa ve en büyük kanal ≥ 170 ve en büyük − en küçük ≥ 60 ve
  parlaklık ≥ 120). Koyu: parlaklık < k. Pencere **yalnız sağ-alta** bakar: x…x+r, y…y+r (kenarda kırpılmış). Açık
  zeminde harflerin sol üst köşesindeki zemin yazı gibi görünmesin diye.

Hazırlık listesi, sırasıyla (ad: ayarlar):

| Sıra | Bu belgedeki adı | Süzgeç |
|---|---|---|
| 1 | G1 | gölgeli, r 5, p 200, s 60, k 80 |
| 2 | G2 | gölgeli, r 4, p 200, s 45, k 80 |
| 3 | B (beyaz) | beyaz yazı (r 5, 200 / 45 / 110) |
| 4 | G3 | gölgeli, r 3, p 150, s 45, k 110 |
| 5 | GR (renkli) | gölgeli, r 5, p 200, s 60, k 80, renkli (renkli sözcük süzgeci kapatılabilir; açık varsayılan) |
| 6 | H (ham) | süzgeçsiz (yalnız otomatik seviyeli görüntü) |

Adlar yalnız ölçüm kayıtları içindir ve serbesttir; sıra ve ayarlar önemlidir.

### 3.4 Hangi okumanın seçildiği

Okuyucunun iki isteğe bağlı yardımcısı vardır:
- **Bilinen satır mı:** metin paketteki bir satırla **birebir** eşleşiyor mu (bulanık arama değil). Uygulama, oyun
  paketleri kütüphanesi varsa her zaman verir (ayardaki "paketler" açık olmasa da).
- **Sözlük puanı:** Windows yazım denetimi puanı (§3.6). Yalnız oyun dili "en" ile başlıyorsa ve yazım denetleyicisi
  bu bilgisayarda çalışıyorsa verilir.

Sayaçlar (okuyucu örneği başına): **ıska** (art arda pakette bulunamayan okuma) ve **seyrek sayaç**.

Adımlar (normal, derin olmayan okuma ya da derin okumanın ilk tam okuması):

1. Görüntü 40 pikselden küçükse doğrudan tek okuma (boş döner).
2. Otomatik seviye uygulanır (kapatılabilir; açık varsayılan).
3. **Tam zincir mi:** yedek okuma değilse ve (sözlük puanı varsa ya da (bilinen satır yardımcısı varsa ve (ıska < **30**
   ya da seyrek sayacı bir artırılınca **8**'e tam bölünüyorsa))). Seyrek sayaç yalnız ıska 30'a ulaşınca artar.
4. Tam zincirde hazırlıklar sırayla okunur:
   - Bilinen satır yardımcısı varsa ve henüz seçim yoksa, okuma **eşleşiyor mu** bakılır: okumada birden çok satır varsa
     önce satırların boşlukla birleşmişi; sonra 2 karakterden uzun (kırpılmış) her satır tek tek. Eşleşirse bu okuma
     seçilir; sözlük puanı **yoksa** zincir burada durur (varsa sürer: sonraki hazırlık, örneğin renkli
     sözcüğü okuyan, eksiği tamamlayabilir).
   - "Yazı var" bayrağı: kırpılmış metni en az 3 karakter olan bir okuma görüldüyse.
   - 3. hazırlıktan (B) sonra hâlâ yazı görülmediyse bölge boştur, zincir durur.
5. Paket eşleşmesiyle seçim yapıldıysa ve sözlük puanı varsa: denenen okumalardan sadeleştirilmiş metni, seçilenin
   sadeleştirilmiş metni + boşlukla **başlayan**, daha uzun ve sözlük puanı daha yüksek olan okuma seçilenin yerini
   alır (sırayla, her seferinde puan güncellenerek). ("Go to" paketteyken "Go to Copper Ridge.")
6. Seçim yoksa ve sözlük puanı varsa ve denenenlerden en az birinin kırpılmış metni ≥ 3 karakterse: en yüksek sözlük
   puanlı okuma seçilir (3 karakterden kısalar en düşük puanlı sayılır; eşitlikte listede önce gelen). Bilinen satır
   yardımcısı varsa ıska bir artar.
7. Hâlâ seçim yoksa **eski seçim:** ham okuma (yoksa şimdi okunur) ile beyaz yazı okuması (yoksa şimdi okunur)
   karşılaştırılır; beyazın OCR çöpü puanı (§9.2) hamınkinden **büyükse** beyaz, değilse ham. Tam zincir çalıştıysa ve
   seçilenin kırpılmış metni ≥ 3 karakterse ıska bir artar.
8. Seçim paket eşleşmesinden geldiyse (6. adımdan değil) ıska sıfırlanır.

Ölçüm için her karede denenen okumaların (ad, metin) listesi ve (ad, okuma) listesi dinleyicilere verilebilir.

**Derin okumada** (§2.3) ilk tam okuma yukarıdaki adımlarla, büyütülmüş iki yedek okuma ise **zincirsiz** yapılır
(yalnız otomatik seviye + 7. adımdaki eski seçim).

**Tek geçişli okuyucu** (telefon/harita): hiçbir adım yok, görüntü olduğu gibi bir kez okunur (40 piksel ve en büyük
boyut sınırı yine geçerli).

"Metin oku" işi Windows okuyucusunda her zaman derin okumadır; satırlar tek boşlukla birleşir.

### 3.5 Okuyucunun uygulamada kurulması

Altyazı hattı her kurulduğunda (dil değişince de) okuyucu yeniden kurulur ve **dört genel ayar birlikte** yeniden
belirlenir: dil "en" ile başlıyorsa ve yazım denetleyicisi çalışıyorsa hepsi açık, değilse hepsi kapalı:
1. hattın ek "okuma bozuk mu" ölçüsü = yazım denetiminin bozuk okuma kararı,
2. hattın okuma puanı = yazım denetimi puanı,
3. paketler kapalıyken de bekletme ("paketsiz bekletme") varsayılanı açık,
4. okuyucunun sözlük puanı = yazım denetimi puanı.

(Denetleyici yalnız İngilizce bilir; İngilizce olmayan oyunda bütün satırları hatalı sayar, her satırı bekletir ve
yanlış okumayı seçtirirdi.)

### 3.6 Windows yazım denetimi

Windows'un kendi yazım denetleyicisi (Office'inki değil; Windows 8 ve sonrası), COM ile:
- Fabrika sınıfı `7AB36653-1796-484B-BDFA-E74F1DB7C1DC`; fabrika arayüzü `8E018A9D-2415-4677-BF08-794EA61F94BB`
  (desteklenen diller, dil destekleniyor mu, denetleyici kur); denetleyici arayüzü `B6FD0B71-E2BC-4653-8D05-F197E412770B`
  (dil etiketi, metni denetle); yazım hatası sayacı arayüzü `803E3BD4-2828-4410-8290-418D1D73C762` (sonraki).
- Dil **en-US**; desteklenmiyorsa denetleyici yoktur.
- Denetleyici **ilk sorguda bir kez** kurulur; arayüz (STA) iş parçacığında sorulduysa kurulum çok iş parçacıklı (MTA) bir
  arka plan işinde yapılır (yoksa okuma iş parçacıklarının her sorgusu arayüz iş parçacığına sıralanır, kilitlenme olur).
  Kurulum hata verirse denetleyici yoktur.
- **Sözlükte mi:** sözcük denetlenir; hata sayacından "sonraki" istendiğinde "hata yok" (S_FALSE, 1) dönerse sözlükte
  sayılır. Denetleyici yoksa ya da çağrı hata verirse **her sözcük sözlükte** sayılır. Sonuçlar sıra duyarlı bir
  önbellekte tutulur; önbellek 20 000 kaydı geçince boşaltılır. Bütün sorgular tek kilitle sıralanır. COM nesneleri her
  sorgudan sonra bırakılır.
- **Çalışıyor mu:** "hello" sorulur, sonra denetleyici kurulmuş mu bakılır.
- **Sokak ağzı listesi** (büyük/küçük harf duyarsız, sözlükte sayılır): gonna, wanna, gotta, kinda, sorta, lemme, gimme,
  ya, yo, nah, yeah, yep, nope, ain't, homie, homies, y'all, dunno, outta, lotta, cuz, 'cause, em, 'em, huh, uh, um, hmm,
  mm, ok, okay, whaddya, c'mon, ma'am, bro, dude, fuckin, motherfucker, motherfuckers, dumbass.
- **Sözcük deseni:** bir ASCII harf, ardından ASCII harfler ya da kesme (`'` ve `’`). Bulunan sözcüğün baş/son kesmeleri
  atılır.
- **Sözcük doğru mu (genel):** 2 harften kısa → doğru. Büyük harfle başlayıp gerisi küçük ya da tamamı büyükse → doğru
  (özel ad, bağırış: "Vinewood", "MICHAEL"). Sokak ağzındaysa ya da "in" ile bitip +"g" hali sokak ağzındaysa → doğru.
  "in" ile bitip +"g" hali sözlükteyse → doğru ("somethin'", "starin'"). Yoksa sözlükte mi.
- **Okuma bozuk mu:** her satırda desenle bulunan her sözcük için: satırın **ilk** sözcüğü ve en az 2 harfliyse küçük
  harfli hali "doğru mu (genel)" ya da kendisi sözlükte mi (satır başındaki büyük harf ad belirtisi değildir: "Arfgfit man" bozuktur);
  diğer sözcükler "doğru mu (genel)". Bir tanesi bile değilse okuma bozuktur.
- **Puan:** her satırın her boşlukla ayrılmış parçası için (satırın ilk parçası "satır başı" işaretli):
  1. Çekirdek = parçanın başından/sonundan `. , ! ? ; : " ' “ ” ‘ ’ ( ) [ ] … - — –` atılmış hali. Boşsa 0.
  2. Temiz mi: her karakter harf, `'`, `’` ya da `-`; her karakter ASCII ya da `’`; ve çekirdekteki her desen sözcüğü
     için: satır başı parçanın en baştaki sözcüğü ve en az 2 harfliyse (küçük hali sözlükte ya da kendisi sözlükte ya
     da küçük hali "doğru mu (genel)"), değilse "doğru mu (genel)".
  3. Harf yoksa: rakam varsa 0 ("24" olağan), yoksa −2 × çekirdek uzunluğu ("•" çöp).
  4. Temiz değilse: −2 × max(harf sayısı, çekirdek uzunluğu).
  5. Çekirdekte 2+ harfli, büyük harfle başlayan ve **gerçekten sözlükte olmayan** bir sözcük varsa 0 (özel ad ya da
     "Dihnnr" gibi bozuk okuma ceza almaz ama puan da kazanmaz). "Gerçekten sözlükte": küçük hali sokak ağzında, ya da
     kendisi ya da küçük hali sözlükte, ya da "in" ile bitip küçük+"g" hali sokak ağzında/sözlükte.
  6. Yoksa harf sayısı.
  Puanlar toplanır; böylece eksik sözcüklü okuma, tam okumanın gerisinde kalır.

---

## 4. Kare girişi ve tek kare kapısı

### 4.1 Her yeni karede (uygulama denetleyicisi)

Kare akış iş parçacığından gelir; bu işten hiçbir hata dışarı kaçmamalıdır (kaçarsa süreç kapanır). Sırayla:

1. Karenin geliş anı alınır (hattın saatiyle aynı saat).
2. Arayüz iş parçacığına: son kare saklanır (ek bölge, serbest alan, ekranı çevir bunu kullanır); oyun ekrandan tanınmalı
   mı bakılır (2. bölüm §6).
3. Altyazı çevirisi **duraklatıldıysa** burada durulur (kare yalnız saklanmış olur).
4. Hat yoksa (OCR dili yok) durulur.
5. Ek alan izleyicisine kare sunulur (sürekli okunan ek bölgeler; 2. bölüm §1). Beklenmez.
6. Telefon/harita oyunu etkinse (telefon/harita belgesi): okuyucular yoksa kurulmaları bir kez arayüz iş parçacığına
   istenir; harita ve telefon izleyicilerine kare sunulur; yan çeviriler gösteriliyorsa ve son gönderimden 60 000 ms
   geçtiyse yeniden gönderilir (TV bunları 2 dakikada kaldırır).
7. **Tek kare kapısı** (§4.2) denenir: "takıldı" ise günlüğe [okuma takıldı; geçen ms; hat yeniden kuruluyor]
   yazılır, hat arayüz iş parçacığında yeniden kurulur, kare atlanır. "Meşgul" ise kare atlanır.
8. Kare hatta verilir (altyazı bölgesi ve geliş anıyla); bitince (hata olsa da) kapıdan çıkılır.

### 4.2 Tek kare kapısı

Okuma hattına aynı anda **yalnız bir kare** girer; önceki kare işleniyorsa yeni kare atlanır (kareler birikmez).

- Her giriş artan bir numara alır (taşma sarar). Çıkış yalnız o numara hâlâ içerideyse kapıyı açar.
- Sıfırlama (çeviri durdu, hat yeniden kuruldu, yeni "Başlat") içerideki girişi unutur; eski okumanın geç çıkışı
  **hiçbir şey değiştirmez**.
- Bir okuma **15 000 ms** ya da daha uzun sürüyorsa sonraki giriş denemesi "takıldı (geçen süre)" döner ve kapı
  sıfırlanır; çağıran hattı yeniden kurar. (Zayıf işlemcide tam karenin derin okuması bile birkaç saniyeyi geçmez; daha uzunu
  arızadır.) Mac'te bu süre 45 000 ms'dir; Windows'ta 15 000.
- Kapı çok iş parçacıklıdır; kilitlidir. "Meşgul mü" sorulabilir.

Örnekler:
- t=0 giriş → içeri (1); t=100 giriş → meşgul; 1 çıkar; t=200 giriş → içeri.
- t=0 giriş (1), sıfırla, t=50 giriş → içeri (2); 1'in çıkışı → kapı hâlâ meşgul; t=60 giriş → meşgul.
- Süre 1000 ms iken: t=0 giriş; t=999 → meşgul; t=1000 → takıldı (1000 ms); t=1001 → içeri.

### 4.3 Hattın kurulması (uygulama)

Hat kurulurken: eski hat sıfırlanır, ek alan izleyicisi ve telefon/harita okuyucuları kaldırılır, kapı sıfırlanır,
okuyucu kurulur (§3.5), "OCR eksik" bayrağı güncellenir; okuyucu yoksa hat kurulmaz. Okuma planı (§5) "hızlı altyazı
algılama" ayarına göre (`FastSubtitleDetection`: açıksa en çok 2, kapalıysa 20 yeniden kullanım) kurulur. Hatta verilenler:
konuşan adı ayarı (`ShowSpeakerNames`), paket araması (paketler/havuz belgesi), bekleme süreleri (`MisreadWaitMs` ve
`PartialWaitMs`, ikisi de 0–2000'e sıkıştırılır; varsayılanları 800 ve 300), telefon bağlantıları (telefon/harita
belgesi), harita açık mı, görev şeridi çizgisi (**Windows'ta kapalı**, §6 adım 7). Olaylar: ölçüm hazır → sağlık
kaydına çeviri süresi ve ana ekrandaki ölçüm satırı (§13); çift gösterildi → oyun tanıma (yalnız satır paketten ve tek
bir pakete özgü anahtarla geldiyse o pakete bir oy), son kaynak/çeviri, son altyazı kutusu, geçmiş; çeviri sonucu →
çevirmen durumu; pakette yok → ortak havuza öneri (paketler/havuz belgesi).

Uygulama örnekleri: çeviri sürerken oyun dili "en"den "ja"ya değişince hat yeniden kurulur (okuyucu sırasıyla "en" ve "ja"
için istenmiştir; etkin kaynak dil "ja" olur). Oyun dilinin OCR paketi yoksa (okuyucu sistem diliyle kurulsa bile) ya da
hiç OCR yoksa "OCR eksik" bayrağı açıktır ve ana ekran uyarır.

---

## 5. Okuma planı (ne zaman OCR yapılır)

Oyun süresinin büyük kısmında altyazı bölgesi ya boştur ya da aynı kalır; bu yüzden her kare okunmaz.

- **Değişti mi (iki iz):** uzunlukları farklıysa değişmiştir. Herhangi bir örneğin farkı **eşikten büyükse** (eşik
  **16**; video gürültüsü bunu aşmaz, bir harf eklenmesi aşar) değişmiştir.
- **Yalnız bir kutunun içinde değişti mi:** Kutu (bölgeye oranla) verilirse ve iz 64'ün katı uzunluktaysa yalnız kutunun
  örttüğü örneklere bakılır: satır sayısı = uzunluk / 64; sol = sıkıştır(aşağı(sol × 64), 0, 63), sağ = sıkıştır(yukarı
  (sağ × 64), sol + 1, 64), üst = sıkıştır(aşağı(üst × satır), 0, satır − 1), alt = sıkıştır(yukarı(alt × satır),
  üst + 1, satır). Kutu yoksa, satır 0 ise ya da uzunluk 64'ün katı değilse bütün iz karşılaştırılır.
  - Kutu (0,3 / 0,6 / 0,7 / 0,85), her yeri 120 olan iz: [0] ve [8×64+10] 250 yapılınca bütün izde değişti, kutuda
    değişmedi. [8×64+30] = 180 → kutuda değişti; 130 → değişmedi.
- **Plan (her kare):** önceki iz saklanır, yenisi yazılır.
  - Önceki iz varsa, üst üste yeniden kullanım sayısı sınırdan küçükse ve iz değişmediyse: **son okuma kullanılır**,
    sayaç bir artar.
  - Yoksa sayaç sıfırlanır ve okuma yapılır; **derin** okuma yalnız "boş okuma sayacı" **3**'e tam bölünüyorsa istenir.
- **Kayıt (her gerçek okumadan sonra):** okunan metin saklanır. Metin boşsa boş sayacı bir artar, değilse **1** olur
  (yazı az önce kaybolduysa büyütülmüş okuma bir sonraki boş karede başlamaz). Başlangıçta boş sayacı 0'dır (ilk okuma derin).
- **Sıfırlama:** önceki iz, son metin, sayaçlar silinir.
- **Uygulamanın planı:** eşik 16, yeniden kullanım sınırı 20 (hızlı algılamada **2**), derin her 3'te bir.
- **"Her zaman" planı** (hattın varsayılanı, testler): eşik −1 (her fark değişiklik), yeniden kullanım 0, her boş karede
  derin.

Örnekler (16 baytlık iz, her yeri 40):
- İlk kare → oku, derin.
- Oku, "Hello there" kaydet, aynı iz → son okuma ("Hello there") kullanılır.
- "" kaydet, bir örnek +8 → yeniden kullanılır ("").
- "Hel" kaydet, bir örnek +40 → oku, derin değil.
- Sınır 2, derin her 2'de: oku, "a line" kaydet; aynı iz → kullan, kullan, sonra → oku (derin değil).
- Hızlı algılama (sınır 2): oku, "" kaydet; aynı → kullan, kullan, sonra → oku.
- Her kare değişen iz, hep "" kaydediliyor, derin her 3'te: derin bayrakları `evet, hayır, hayır, evet, hayır, hayır`.
- Sıfırlamadan sonra ilk kare → oku, derin.
- "Her zaman" planında aynı iz bile okunur, derin.

---

## 6. Her karede hattın sırası

Hat bir kareyi (kare, altyazı bölgesi, isteğe bağlı geliş anı; verilmezse şimdi) işlerken çağıranı bekletmez: okuma
arka planda yapılır, çeviri beklenmez (çeviri devam ederken yeni satırlar da okunmaya devam eder).

1. Kilit altında: işlemin başladığı **oturum numarası** alınır. Oturumun ilk karesiyse günlüğe [ilk kare; oturum
   başından geçen ms].
2. Telefon aranacak mı sorulur (yalnız telefon/harita oyununda açık). Telefon son **5000 ms** içinde görüldüyse "az önce
   görülen telefon" o kutudur (geçiş animasyonunda bir iki kare bulunamıyor).
3. **Arka planda** (iş parçacığı havuzunda):
   1. Bölge kesilir (§1).
   2. Telefon aranıyorsa: karede telefon izlenir (telefon/harita belgesi); bulunursa kutusu ve anı saklanır. Bulunan ya
      da az önce görülen telefon kutusunun altı `max(alt, min(alt + 0,15, 0,84))`'e uzatılır (altyazının başladığı
      0,84'e inmez) ve kesilen alanda o kısım siyaha boyanır (§1 maskeleme).
   3. (Maskelenmiş) alanın izi çıkarılır.
   4. Kilit altında plan sorulur (§5). "Son okumayı kullan" ise son okuma ve son okumanın süresi döner.
   5. Değilse okuyucu "satırları oku (alan, plan derin mi)" ile okur; süre ölçülür; kilit altında plana kaydedilir,
      son okuma ve süresi saklanır.
   6. Herhangi bir hata olursa: boş okuma, süre yok (plana **kaydedilmez**); o ana kadar çıkan iz/telefon bilgisi korunur.
4. Kilit altında: oturum numarası değiştiyse (bu arada hat sıfırlandı) günlüğe [sıfırlamadan önce başlamış okuma atıldı]
   yazılır ve bu kare **hiçbir iz bırakmadan** biter.
5. Alan kutusu = bölgenin (sol, üst, sağ, alt) kutusu.
6. **Telefon satırları** atılır (telefon/harita belgesi; hata olursa okuma olduğu gibi kalır). Özetle: telefon açıksa
   telefon ekranının içine (her yandan 0,02 payla) düşen satırlar; telefon aranıyorsa açık zeminde koyu yazılı satırlar
   (mesaj balonu) ve telefon uygulamasına özgü yazılar (bunlar görülünce telefonun yeri bu yazılardan da öğretilir);
   telefon açıksa ya da telefonda az önce görülen mesajlar varsa ortası karenin **0,8**'inden yukarıda olan satırlar;
   telefonda az önce görülen mesajlardan birinin içinde geçen (sadeleştirilmiş), **3 ve daha çok sözcüklü** satırlar.
7. **Görev şeridi çizgisi:** çizgi verilmişse, karede üst kenarı çizginin altında başlayan satırlar atılır. Konuşan adıyla
   açılan satır ile onun hemen altındaki devam satırı (üstü konuşan satırın üstünden aşağıda ve konuşan satırın altından
   `max(0,02, satır_yüksekliği × 1,5)`'ten az uzakta) kalır. Havuz öncelikli oyunun çizgisi **0,935**'tir. **Windows
   uygulaması bu çizgiyi vermez (kapalı):** Windows'ta görev şeridini ayrıca çeviren bir bölüm yok; şerit atılırsa hiç
   çevrilmez. Kural çekirdekte durur ve sınanır.
8. **Dev satırlar** atılır (§7.6). Atılan satırların metni ` / ` ile birleşip not edilir.
9. Telefon aranıyorsa yalnız **ortalanmış satırlar** kalır (§7.8).
10. Sırayla: düğme ipuçları (§7.1) → yol tarifleri (§7.2) → OCR çöpü temizliği (§7.3; çöpten ibaret satır kalkar) →
    iki kenara değen satırlar (§7.4) → aynı sıradaki parçaların birleşmesi (§7.5) → altyazı bloğu seçimi (§7.7).
11. Harita ekranı açıksa okuma boşaltılır.
12. Blok, altyazı olamayacak kadar yüksek ya da çok satırlıysa (§7.6) "dev blok" olarak not edilir, okuma boşaltılır.
13. Kilit altında:
    - Dev satır notu bir önceki dev notundan farklıysa günlüğe [dev yazı atlandı; atılan satırların alıntısı];
      dev blok varsa ve metni son dev notundan farklıysa [dev blok atlandı; alıntı; satır sayısı] (iki not aynı "son dev
      not" değerini paylaşır; ekranda duran tabela her karede yazılmaz).
    - Oturumda ilk kez boş olmayan okuma geldiyse [ilk yazı; oturum başından geçen ms; alıntı].
    - Bu karenin okuma bilgisi saklanır: geliş anı, okuma süresi, okumanın güveni.
    - **Sabitleyiciye** (§8) okumanın metni, alanın izi ve okumanın **alana göre** kutusu verilir; bir tepki alınır.
    - Sabitleyici bir not bıraktıysa ve önceki nottan farklıysa günlüğe yazılır: kötü yeniden okumanın yok sayıldığı ya da çöp okumanın kararlaşmadan ekrandan kalktığı (ikisinde de okumanın alıntısıyla).
    - Kutu = okumanın kutusu kareye yerleştirilip **ekrana göre ortalanmış** (§7.9) hali (okumanın kutusu yoksa yok).
    - **Önceden çeviri:** tepki "hiçbir şey" ise, çevirmen önceden çeviriyi destekliyorsa ve kırpılmış metin en az **6**
      karakter ve en son önceden istenenden farklıysa: konuşan adı varsa yalnız cümlesi, yoksa metnin kendisi için
      önceden çeviri başlatılır.
    - Bekletilen okuma varsa §11.4'teki dallar (tepkiyi değiştirebilir).
    - Tepkiye göre: **temizle** → son temizlik anı = şimdi, ekrandaki satır kalktı (§11.1), TV'ye "temizle", günlüğe
      [satır kalktı, ekran temizlendi]; **çevir** → çevir ya da beklet (§11.3); **geri getir** → ekrandaki satır kalktı, geri
      getir (§11.7).
    - Süren çevirinin bırakılması gerekip gerekmediğine bakılır (§11.6).
14. Kilit dışında, sırayla: önce bekleyenden çıkan "önce bunu çevir" işi, sonra bu karenin işi (paket gösterimi
    olayları, havuz önerisi) çalıştırılır; en sonda (hata olsa da) bırakılan çevirinin iptal sinyali verilir (iptal,
    kendi kilidiyle; o arada yok edilmişse sessizce geçilir). Olay işleyicileri ve iptal hiçbir zaman hattın kilidi
    altında çağrılmaz.

---

## 7. Satır süzgeçleri

### 7.1 Düğme ipuçları

Oyunun kumanda ipuçları ("R2 Swing", "△ Pick up", "Press ✕ to jump") altyazı değildir; çevrilmez, yerleri altyazının
yerine katılmaz.

Veri:
- **Düğmeler** (büyük/küçük harf duyarsız): R1 R2 R3 L1 L2 L3 OPTIONS TOUCHPAD ✕ × ⨯ ✖ ○ ◯ ● □ ▢ ◻ ■ △ ▲ ⨂
- **Harfe benzeyenler** (duyarlı, yalnız kalıpta düğme): X, O
- **Eylemler** (duyarsız): press hold tap push use mash release
- **Zarflar** (küçük harfle tam eşleşme): slowly quickly gently carefully rapidly repeatedly continuously briefly
- **Güçlü düğmeler** (parça büyük harfe çevrilip tam eşleşme): R1 R2 R3 L1 L2 L3 TOUCHPAD ✕ ○ ◯ □ △ ▲
- **Ayırıcılar:** boşluk, sekme, `+`, `/`. **Parantezler** (parçanın iki ucundan atılır): `( ) [ ] { } < > 「 」`

Kural, sırayla (ilk tutan karar verir):
1. **Simge kalıbı:** satır, baştaki boşluktan sonra **1–3 kez** "boşluk olmayan **tek** karakter + boşluk", ardından
   ASCII büyük harfle (A–Z) başlayan ve en az 2 tane daha A–Z ya da `'` taşıyan bir sözcük, ardından (boşlukla) en çok 2
   tane A–Z ile başlayıp en az 1 tane daha A–Z ya da `'` taşıyan sözcük, sonra yalnız boşluk. (Büyük/küçük ayrımı açık:
   "I am FREEZING" altyazıdır.) → ipucu.
2. Satır ayırıcılardan parçalanır, her parçanın uçlarındaki parantezler atılır, boşlar atılır. Parça yoksa ipucu değil.
   "Sözcük sayısı" = düğme olmayan ve en az bir harf içeren parçalar.
3. İlk parça düğmeyse → sözcük sayısı ≤ 5 ise ipucu.
4. Son parça düğmeyse ve sözcük ≤ 4 ve satır cümleyi bitirmiyorsa → ipucu ("CAMERA VIEW R3 + L3").
5. İlk parça X ya da O ise ve parça sayısı 2–4 ve ikinci parça büyük harfle başlıyor ve satır cümle bitirmiyorsa → ipucu.
6. İlk parça eylemse ve parça sayısı 2–10 ve ikinci parça düğme ya da X/O ise → ipucu.
7. İlk parça (küçük harfli) zarfsa ve parça sayısı 3–16 ve **üçüncü parçadan itibaren** bir "to" varsa ve cümle
   bitirmiyorsa → ipucu (simge okunamasa da).
8. Parça sayısı ≤ 16 ve parçalardan biri güçlü düğmeyse ve parçalardan biri (küçük harfle) "to" ise ve cümle bitirmiyorsa
   → ipucu.
9. Değilse ipucu değil.

Örnekler:

| Satır | İpucu mu |
|---|---|
| CAMERA VIEW R3 + L3 | evet |
| ZOOM IN [L2] + [R2] | evet |
| Pass me the R2. | hayır |
| A e DRINKS | evet |
| B : OPEN MAP | evet |
| GET DOWN! | hayır |
| I am FREEZING | hayır |
| Hey, you found Cal's keys. | hayır |
| Gently turn ○ to steady the rod then press R2 when the line pulls | evet |
| Gently turn t to steady the rod then press R2 when the line pulls | evet |
| Quickly spin to pull the line while it's slack | evet |
| Spin ○ to drop anchor | evet |
| ○ to drop anchor | evet |
| Gently, we need to rest. | hayır |
| Quickly, back to the dock | hayır |
| I need to sleep now | hayır |
| Take the L2 ramp, then right. | hayır |
| R2 Swing | evet |
| L2 + R2 Storm Blade | evet |

Hat örneği: okumalar `R2 Swing`, `R2 Swing`, `Shut the vent\nR2 Swing`, `Shut the vent\nR2 Swing` (her kare okunur,
çeviri her karede beklenir) → TV'ye yalnız `TR: Shut the vent`.

### 7.2 Yol tarifleri

Navigasyonun dönüş/mesafe satırları (ör. "Turn Right 215 ft 248 ft") konuşma sayılmaz; ne çevrilir ne gösterilir. Kurallar kültürden
bağımsız ve büyük/küçük harf duyarsızdır. Satır kırpılır.

- **Başta izin verilen kırıntı:** boşluk ve `- – — ' " ‘ ’ . , · •` karakterleri.
- **Mesafe:** sayı (rakamlar, isteğe bağlı `.`/`,` ve rakamlar) ya da tek "O"/"o" (okuma hatasıyla 0), isteğe bağlı
  boşluk, sonra `ft`, `mi`, `yd`, `km` ya da `m` ve sözcük sınırı. Tek komut kalıbında birim de büyük/küçük harf
  duyarsızdır; yön + mesafe kalıbının mesafe aramasında ise birim **küçük harf** olmalıdır.
- **Tek komut kalıbı** (tutarsa tarif): kırıntı, isteğe bağlı "make a"/"make an", sonra `u-turn` (tire ve boşluk
  isteğe bağlı: "uturn", "u turn", "u-turn") / `turn` / `keep` / `bear`, isteğe bağlı boşluk + left/right, sıfır ya da
  daha çok "boşluk + mesafe", isteğe bağlı boşluk, isteğe bağlı tek `.` ya da `!`, satır sonu.
- **Yön + mesafe kalıbı:** kırıntı, `u-turn`/`turn`/`keep`, boşluk, left/right, sözcük sınırı; kalan kısımda en az bir
  mesafe olmalı; mesafeler boşlukla değiştirilince kalan harf/rakam sayısı **en çok 2** olmalı.

| Satır | Tarif mi |
|---|---|
| Turn Right 215 ft 248 ft | evet |
| Keep Left O ft 7 ft | evet |
| U-Turn Left 9 ft 31 ft | evet |
| Turn Left 512 ft— | evet |
| -turn Left 120 ft 95 ft | evet |
| Turn Right i 140 ft 152 ft | evet |
| Keep Right 1.6 km | evet |
| Turn left / Turn Right / Keep left / Keep Right. | evet |
| Make a u turn / Uturn Right | evet |
| Turn right at the bridge, yeah? | hayır |
| Turn left by the gas station, okay? | hayır |
| Keep moving, the shore is close. | hayır |
| Turn it off! / Keep it quiet! | hayır |
| Keep right and stay close, 30 ft or less | hayır |
| I told you turn right, 80 ft back by the pier. | hayır |

Türkçe sistem kültürü açıkken de `TURN RIGHT 215 ft`, `turn right 215 ft`, `U-TURN LEFT 9 ft` tariftir.

Okumadan atılma: (`Turn Right 215 ft`, `Where is this road taking us?`) → yalnız ikincisi kalır.
Hat örneği: `Turn Right 215 ft 248 ft` ×2, `Is this the right road?\nKeep Left O ft 7 ft` ×2 → TV'ye yalnız
`TR: Is this the right road?`; çevirmene "ft" içeren hiçbir metin gitmez.

### 7.3 OCR çöpü temizliği (satır içi)

Süslü yazı tipinde ya da kararsız görüntüde tanıyıcı, bazı sözcükleri anlamsız harf-rakam-simge dizilerine dönüştürür. Satır içinde
temizlenir; temizlikten sonra boş kalan satır okumadan kalkar (okuma kurulurken boş satır atılır).

Veri:
- **Simgeler:** `$ @ # % ^ * _ = | \ ~ < > { } ¢ £ ¥ § © ® ° ± µ ¶ ¤`
- **Kenar karakteri:** simge olmayan ve (noktalama ya da sembol sınıfında olan ya da `" ' “ ” ‘ ’ « » ( ) [ ]`'den biri)
  olan karakter. Her parça baştaki kenar karakterleri (baş), çekirdek ve sondaki kenar karakterleri (son) diye ayrılır.
- **Olağan harf-rakam karışımları:** çekirdek `-`'den bölünür; rakam içeren her parça şunlardan birine tam uymalı:
  (a) 1–4 ASCII harf + 1–4 rakam ("PS5", "R2", "MK2"); (b) rakamlar + şu eklerden biri: st nd rd th s k K m km kg cm mm p
  x fps hp HP XP xp v V D d ("2nd", "100m", "4K", "60fps", "1980s"); (c) x/X + 1–3 rakam ("x2"); (d) rakamlar, `.` ya da
  `,`, rakamlar, 0–3 ASCII harf ("9.5kg"); (e) 1–2 rakam, `:` ya da `.`, 2 rakam, isteğe bağlı am/pm/AM/PM ("3:00pm").
- **Sözcüğün kendisi (çekirdek temizliği):** harf yoksa çekirdek aynen ("24", "$500", "…"). Simge yok ve rakam yoksa
  aynen. Simge yok ve olağan karışımsa aynen. Değilse baştaki harf/`'`/`’`/`-` dizisi alınır; bu dizide en az **3 harf**
  varsa o kalır ("waters2aljd" → "waters"), yoksa sözcük **tamamen çöptür**.

Adımlar (her boşlukla ayrılmış parça için, soldan sağa):
1. **Yanlış okunmuş "I":** çekirdek `l` ya da `|` ile başlıyor ve (tek karakter ise "I"; ya da 2. karakter `'`/`’` ve
   geri kalanı `m`, `ll`, `ve`, `d` ise "I" + kalanı). Bulunduysa: kısaltmaysa ("I'm"…) ya da sonraki parçanın ilk harfi
   küçükse ya da parçanın sonu `?`/`!` içeriyorsa baş + düzeltilmiş + son eklenir; yoksa parça (sonu dahil) atılır
   (altyazı kutusunun kenarı olabilir).
2. **Başıboş noktalama:** çekirdek boşsa ve parça yalnız `? ! . , ; :` karakterlerinden oluşuyorsa (ama 2+ tane yalnız
   nokta, yani "...", gerçek noktalamadır, bu adıma girmez): önceki eklenen parça varsa ve onun son karakteri
   `. ? ! … , ; :` değilse parça ona **yapıştırılır** ("going ?!" → "going?!"); değilse atılır.
3. Çekirdek temizliği sonuç verirse baş + sonuç + son eklenir. Sözcük çöpse ve sonu boş değilse ve önceden eklenen parça
   varsa sonu ona yapıştırılır ("ou$3e," → virgül önceki sözcüğe).
4. En sonda: en az 3 parça kaldıysa ve ilk parça "rakamlar, isteğe bağlı m/km/ft/yd, isteğe bağlı tek `. ? ! : ;`"
   kalıbına tam uyuyorsa ve ikinci parça büyük harfle başlıyorsa ilk parça atılır (yandaki göstergenin sayısı satıra
   yapışmış).
5. Parçalar tek boşlukla birleşir.

| Girdi | Çıktı |
|---|---|
| Over the frozen hills, Mira x$7q rode, looking for a fire to warm her hands. | Over the frozen hills, Mira rode, looking for a fire to warm her hands. |
| Over the frozen hills7bq O rode, Looking for a fire. | Over the frozen hills O rode, Looking for a fire. |
| She ran 4q, without a word. | She ran, without a word. |
| ?! What are you doing here? | What are you doing here? |
| What are you doing here ?! | What are you doing here?! |
| Climb the wall, Nora. ?! | Climb the wall, Nora. |
| Stop, ?! Captain Reyes needs you. | Stop, Captain Reyes needs you. |
| . Climb the wall. | Climb the wall. |
| \| Climb the wall, Nora. | Climb the wall, Nora. |
| Climb the wall, Nora. \| | Climb the wall, Nora. |
| Leave it. l | Leave it. |
| l can't swim, Captain Reyes. | I can't swim, Captain Reyes. |
| \| don't know. | I don't know. |
| l'm sure of it, l heard them. | I'm sure of it, I heard them. |
| \|'ll wait by the door. | I'll wait by the door. |
| She and l've met him once. | She and I've met him once. |
| Who am l? | Who am I? |
| Who sent you, \|? | Who sent you, I? |
| I can't see, l! | I can't see, I! |
| Drop it. l. | Drop it. |
| 7? The snow will cover them. | The snow will cover them. |
| 250. Nora and Eli... | Nora and Eli... |
| 40m MARA: Over there! Duck now! | MARA: Over there! Duck now! |
| 300 boats sank | 300 boats sank |

Değişmeden kalanlar: `Plug in the PS5 first.`, `Keep BB8-X1 close.`, `It costs $750.`, `Call me at 9:30am.`,
`The 3rd bridge is 200m north.`, `Play at 30fps, 8K.`, `Score x2!`, `Year 1984.`, `I won't — hold on…`, `"Mara!" he shouted.`,
`Mk3 bow, 2.5kg.`, `L2 + R2 Storm Blade`, `Huh?! The lights went out again!`, `- Who? - Nobody.`, `Hold on... why?`,
`I... I can't say.`, `"Hide!" she said.`, `So, you're Nora?`, `... and then she vanished.`, `Hold on ... why?`, `I said no!`,
`Drop it, I said.`, `Press R to run.`

Okuma örneği: (`We go now.`, `x$7q 4q`) temizlenince yalnız `We go now.` kalır.

### 7.4 İki kenara değen satır

Kutusu okunan alanı soldan sağa baştan sona kaplayan satır (sol ≤ **0,015** ve sağ ≥ **0,985**, alana göre) kesiktir,
altyazı değildir (yasal uyarı, PS5 menüsündeki kayan yazı). Tek kenara değen satır kalır. Kutusuz satır kalır.
- (0,0 → 1,0) uzun anlamsız satır → atılır; (0,06 → 0,94) → kalır; (0,0 → 0,7) → kalır.

### 7.5 Aynı sıradaki parçaların birleşmesi

Renkli konuşan adı ("Mara:") cümleden ayrı okunabilir. Okumada en az 2 satır varsa ve **bütün** satırların kutusu
varsa:
1. Satırlar kutu soluna göre sıralanır (soldan sağa).
2. Her satır için, şimdiye kadar kurulan sıralardan **aynı sırada** olan ilki aranır: dikey örtüşme
   (`min(altlar) − max(üstler)`) iki yükseklikten küçüğünün en az **%60**'ı olmalı (küçük yükseklik 0 ya da eksiyse
   değil) ve yeni parçanın solu sıranın sağından en çok **0,05** (alan genişliğine oranla) uzakta olmalı.
3. Bulunursa: metin "sıra + boşluk + parça", kutu birleşim, güven (ikisi de varsa küçüğü, yoksa olanı). Bulunmazsa yeni
   sıra.
4. Sıralar kutu üstüne göre dizilir.
Bir satırın bile kutusu yoksa ya da 2'den az satır varsa okuma aynen kalır.

Örnek: ("Grab the rope." 0,40–0,70 / üst 0,501–alt 0,60), ("MARA:" 0,30–0,385 / 0,50–0,60), ("9" 0,95–0,97 /
0,50–0,60) → satırlar `MARA: Grab the rope.` ve `9`.

### 7.6 Dev yazı ve dev blok

Ölçüler **karenin tamamına göredir:** satır yüksekliği = kutu yüksekliği (alana göre) × alanın kare yüksekliği.

- **Altyazı satırı sınırı:** **0,075**. **Cümle satırı sınırı:** **0,13**.
- **Etiket gibi satır:** harf içeren sözcük sayısı ≤ 4 ve satırda `. , ! ? …` yok.
  - "OHM BOY", "BOAT CHARTERS TO LON" → etiket; "We made it!", "You finished half of the diving course" → değil.
- **Satır atılır:** yüksekliği max(0,075, 0,13) = 0,13'ten büyükse; ya da 0,075'ten büyük ve etiket gibiyse. Kutusuz satır
  kalır.
- **Dev blok:** blokta **5**'ten çok satır varsa; ya da blok kutusunun yüksekliği × alan yüksekliği **0,26**'dan büyükse.
  Kutusu yoksa (ve satır sayısı sınırı aşmıyorsa) dev değildir.

Örnekler (alan: sol 0,06, üst 0,56, sağ 0,98, alt 1 → yükseklik 0,44):
- (0,60–0,69) ve (0,70–0,79) iki altyazı satırı → ikisi de kalır; blok dev değil.
- "Welcome to Leonida" (0,05–0,35; ≈ karenin %13'ü, etiket) atılır, "Why are we stopping?" (0,80–0,88) kalır.
- Dar alan (üst 0,85, alt 0,95): (0,2–0,7) yükseklikli "Keep your lamp lit." kalır (karede 0,05); aynı satır tam karede
  (0–1) okunsaydı 0,5 olurdu, atılır.
- Kutusuz satır hiç atılmaz; dev blok sayılmaz.
- 7 satır (her biri 0,09 yüksek, 0,12 aralıklı) → dev blok; ilk 3'ü → değil.
- İki satır (0,05–0,15 ve 0,65–0,75) → kutu 0,70 × 0,44 = 0,308 > 0,26 → dev blok.
- "Who did this? 00060000" (0,60–0,80, karede 0,088, cümle gibi) → kalır. Aynı yükseklikte "Boat Charters" (etiket)
  → atılır.

Hat örneği: alan (üst 0,6, alt 1,0, sol 0,1, sağ 0,9); "Welcome to Leonida" (0,05–0,45) ve "Shut the vent." (0,8–0,9),
3 kare → Leonida hiç gönderilmez; günlükte "Welcome to Leonida" alıntılı **tek** [dev yazı atlandı] kaydı vardır.

### 7.7 Altyazı bloğu seçimi

Alanda altyazının yanında menü ve köşe göstergeleri de okunur. Okumada satır yoksa ya da bir satırın bile kutusu yoksa
okuma aynen döner. Değilse (alan = okunan alanın karedeki kutusu):

1. Satırlar kutu üstüne göre dizilir; her satırın kutusu kareye yerleştirilir.
2. Her satır, **son** eklenen bloktan geriye doğru, ait olduğu ilk bloğa katılır; hiçbirine ait değilse yeni blok olur.
   **Ait olmak:** bloğun son satırına göre: yükseklik = ikisinin büyüğü; `satır_üstü − son_alt ≥ yükseklik × 0,8` ya da
   satırın üstü son satırın üstünden yukarıdaysa ait değil; yatay örtüşme > 0 ve dar olanın genişliğinin en az yarısı
   olmalı.
3. **Menü blokları** elenir: en az 3 satırlı ve her satırı en çok 3 sözcüklü (boşluk sözcükleri) ve hiçbiri cümle
   bitirmeyen blok.
4. **Ortalanmış** bloklar (blok kutusunun karedeki ortası ile 0,5 arasındaki fark ≤ **0,12**) varsa: aralarından
   alt kenarı (alana göre kutu altı) en büyük olan seçilir.
5. Yoksa en az **3 sözcüklü** bloklardan alt kenarı en büyük olan; o da yoksa boş okuma.

Örnekler (alan sol 0, üst 0,6, sağ 1, alt 1; satır yüksekliği 0,07):
- Solda alt alta menü (MAP, HELP, PROGRESS, PLAYER, STORY, ONLINE, SOCIAL CLUB, SETTINGS), sağ altta "PHOTO MODE" →
  boş.
- "The snow will cover them if we don't hurry." (0,25–0,75, üst 0,7), "9" (0,02–0,04), "PHOTO MODE" (0,85–0,97, üst 0,9)
  → yalnız altyazı; kutusu (0,25, 0,7, 0,75, 0,77).
- "Nora and Eli... they both got away." (0,3–0,7, üst 0,6) ve "We should rest here." (0,4–0,6, üst 0,68) → iki satır
  birlikte.
- Solda tek "Guard: Nobody gets past this door." (0,05–0,5) → okunur (ortalanmış değil ama 3+ sözcük).
- Kutusuz `MAP\nHELP` → aynen (aynı nesne).

### 7.8 Ortalanmış satırlar (telefon/harita oyununda)

Telefon aranırken (havuz öncelikli oyun, GTA 6) konuşma altyazısı hep ortalıdır. Kutusunun karedeki ortası 0,5'ten
**0,12**'den fazla uzak satır atılır (ör. dükkândaki yazı, köşedeki bildirim kartı). Kutusuz satır kalır. Hiçbir satır
atılmadıysa okuma aynen döner.
- Alan (sol 0,14, üst 0,62, sağ 0,86, alt 0,97); "The tide is coming in fast." (0,35–0,65 → karede ortası 0,5) kalır; "Dock Fees
  Due" (0,80–0,95 → ortası ≈ 0,77) atılır.

Görev şeridi örneği (§6 adım 7; aynı alan; çizgi 0,935): "Give me two minutes." (üst 0,70) kalır; "Go to the marina office"
(üst 0,905 → karede 0,935) atılır. "CAL: Grab the cooler," (0,86–0,90) ve "the fish won't wait." (0,905–0,945) → ikisi de
kalır.

### 7.9 Kutunun ekrana göre ortalanması

TV'ye giden altyazı kutusu: kutunun ortası 0,3'ten büyük ve 0,7'den küçükse sol = max(0, min(sol, 1 − sağ)), sağ =
min(1, max(sağ, 1 − sol)) olur (ortaya göre simetrik genişler; bir ucu okunamayan satırın İngilizcesi yanda kalmasın).
Ortası 0,3 ya da daha az, 0,7 ya da daha çoksa dokunulmaz.
- (0,45, 0,85, 0,75, 0,9) → sol 0,25, sağ 0,75, üst 0,85.
- (0,02, 0,1, 0,2, 0,15) → aynen.

Hat örneği: alan (üst 0,6, alt 1,0, sol 0,1, sağ 0,9), satır (0,25, 0,5, 0,75, 0,6) → TV kutusu sol 0,3, üst 0,8,
sağ 0,7, alt 0,84.

---

## 8. Sabitleyici

Kare kare gelen metni izler; altyazı kararlı olunca "çevir", ekrandan kalkınca "temizle", az önce kalkan satır geri
gelince "geri getir" der. Bir satırı ikinci kez göndermez. Bütün kararlar kare sayısıyla değil geçen süreyle verilir.

### 8.1 Sayılar

| Ad | Değer |
|---|---|
| Benzerlik eşiği (aday) | 0,85 |
| Kararlı kare sayısı | 2 |
| Boş kalınca silme süresi | 800 ms |
| Yeri değişmeyen satırı en çok tutma | 4000 ms |
| Geri gelme penceresi | 1500 ms |
| Başarısız çeviriyi yeniden deneme | en erken 1000 ms sonra |
| Çöp okumanın kararlı kalma süresi | 700 ms |
| Kalkan satır geçmişi | son 5 |

**Temiz hızlı yol kipi:** çevirmen önceden çeviriyi destekliyorsa açılır (Windows'ta çevrimiçi çevirmenler; Linux'ta
Tesseract'la da). Açıkken noktalamayla biten satır ilk karede yalnız **temiz** okunduysa gider ve satır **ilk okunan
hâliyle** gönderilir (çevirisi o metinle önceden başlatılmıştı).

**Temiz okuma:** sözcük yoksa temiz değil. Her sözcük uçlarından `. , ! ? … : ; " ' “ ” ‘ ’ ( )` atılınca boş
kalmamalı; yalnız harf, rakam, `'`, `’`, `-` içermeli; 1–2 harfli tamamen harf sözcükler şu listede olmalı (büyük/küçük
duyarsız): a i o an am as at be by do go ha he hi if in is it me mr ms mrs dr st my no of oh ok on or so to tv uh um up us
we ya ye.

| Satır | Temiz mi |
|---|---|
| Nora: I got it. | evet |
| Sea-Wolf: Fire away! | evet |
| Walk over to the market run by Mrs. Hale... | evet |
| q qe & ue need it. | hayır |
| A _ there's a spare boat if you want. | hayır |
| 7 Kx and keep the change for now. | hayır |
| Sea-Wolf **: can't believe you found this! | hayır |

### 8.2 Durum

Aday (sadeleştirilmiş ve ham ilk okunuşu), aday sayısı, adayın ilk görüldüğü an; **gönderilen** satır (satır satır
sadeleştirilmiş hali ve ham hali); boşluğun başladığı an; "gitti" anı (boş okuma sırasında satırın bulunduğu yerin
başka göründüğü ilk an); son görülme (ekrandaki satırın son okunduğu karenin izi ve satırın alandaki kutusu); kalkan satır geçmişi (satırlar,
ham, kalkış anı); unutulan satır ve en erken yeniden deneme anı; bekleyen çöp aday (günlük için); not.

### 8.3 Her besleme (metin, iz, kutu)

Not her beslemede silinir. Metin sadeleştirilir.

1. **Boş kare:** sadeleştirilmiş metin **3 karakterden kısaysa** (gürültü, tek simge):
   - bekleyen çöp aday varsa "çöp bırakıldı" notu; aday ve sayısı sıfırlanır; boşluk başladıysa anı korunur yoksa şimdi.
   - Gönderilen satır yoksa → hiçbir şey.
   - "Gitti" anı yoksa ve satırın yeri **değişmemiş görünmüyorsa** "gitti" = şimdi. Değişmemiş görünmek: iz ve son
     görülme var ve son görülme izi ile bu iz, son görülme kutusunun içinde eşik 16 ile değişmemiş (§5).
   - (gitti varsa ve şimdi − gitti ≥ 800) ya da (şimdi − boşluk başı ≥ 4000) → ekrandaki satır geçmişe yazılır (§8.4),
     **temizle**. Değilse hiçbir şey.
2. Metin doluysa boşluk ve gitti anları silinir.
3. **Aday:** metin aday ile benzerse (0,85) sayı bir artar; temiz hızlı yol kipindeyse ve bu okuma adayın ham haline
   göre **anlam işareti ekliyorsa** (§10.5), aday bu okumayla değişir (sayı ve başlangıç anı korunur). Benzer değilse
   bekleyen çöp aday not edilir, aday bu okuma olur, sayı 1, başlangıç şimdi.
4. **Hazır mı:** okuma çöp gibiyse (§9.3) sayı ≥ 2 **ve** şimdi − aday başlangıcı ≥ 700; değilse sayı ≥ 2 ya da (satır
   cümle bitiriyor ve (kip kapalı ya da okuma temiz)).
5. Okuma gönderilen satırın **aynı altyazısıysa** (§10.1) son görülme güncellenir (iz ve kutu ikisi de varsa, yoksa
   silinir) → hiçbir şey.
6. Hazır değilse: çöp gibiyse bekleyen çöp aday = bu ham okuma → hiçbir şey.
7. Bekleyen çöp aday silinir.
8. Gönderilen ham satır varsa ve bu okuma onun **kötü yeniden okumasıysa** (§10.3): "kötü yeniden okuma" notu, son
   görülme güncellenir → hiçbir şey.
9. **Geri gelme:** geçmişte kalkışından bu yana ≤ 1500 ms geçmiş ve okuma onun aynı altyazısı olan **en son** kayıt
   varsa: geçmişten çıkarılır; ekrandaki satır (varsa) geçmişe yazılır; gönderilen = o kayıt; son görülme güncellenir →
   **geri getir** (kaydın ilk gönderilen ham metniyle).
10. Unutulan satır varsa, şimdi < yeniden deneme anı ve okuma onun aynı altyazısıysa → hiçbir şey.
11. Ekrandaki satır geçmişe yazılır; unutulan silinir; gönderilen ham = (kip açıksa adayın ilk ham hali, değilse bu
    okuma kırpılmış), gönderilen = onun satır satır sadeleştirilmişi; son görülme güncellenir → **çevir** (gönderilen
    ham metinle).

### 8.4 Yardımcı işler

- **Geçmişe yazma:** gönderilen satır varsa (satırlar, ham, şimdi) geçmişe eklenir, 5'i aşarsa en eski atılır;
  gönderilen ve son görülme silinir.
- **Gönderilmeli mi (zaten hedef dilde mi):** kaynak ile çevirinin sadeleştirilmişleri **0,90** ile benzer değilse
  gönderilir. ("Kayıt Bitti Devam Et" → aynısı: gönderilmez; "Save game" → "Oyunu kaydet": gönderilir.)
- **Gönderileni unut** (çeviri başarısız): gönderilen varsa unutulan = o; yeniden deneme anı = şimdi + 1000; gönderilen,
  son görülme, aday, bekleyen çöp silinir. Satır ekranda kaldıkça yeniden kararlı olup çevrilir, ama saniyede en çok bir
  kez.
- **Sıfırla:** aday, çöp, not, boşluk, gitti, son görülme, geçmiş, unutulan silinir. Gönderilen satır varsa silinir ve
  **temizle** döner, yoksa hiçbir şey.

### 8.5 Örnekler (saat 1 000 000'den başlar; belirtilmedikçe ilerlemez)

| Besleme sırası | Tepkiler |
|---|---|
| "We are out of rope" ×3 | yok, çevir("We are out of rope"), yok |
| "Over the frozen hills, Mira rode,\nlooking for a fire to warm her hands." ; "Over the frozen hills O rode," ×2 ; "Let's make camp now." | çevir(ilk), yok, yok, çevir("Let's make camp now.") |
| "Fnd yuor kyes." ; "Find your keys." | yok, çevir("Find your keys.") |
| "- Wht) so, you rmbr. damn, I d" ×5 (her biri sonrası +100) ; +700 ; aynı | yok ×5, çevir(aynı) |
| "We are out of" ×2 ; "We are out of rope for this." | yok, çevir("We are out of"), çevir(tamamı) |
| Tam = "Look, I only came down here to ask if there's somethin' I can bring you." ; Kötü = "Look, I came down here to ask if there somethinl I can bring ya." : Tam, Kötü, Tam, Kötü | çevir(Tam), yok, yok, yok |
| Kötü, Tam, Kötü | çevir(Kötü), çevir(Tam), yok |
| "We are out of rope." / "Wait!" / "Who sent you?" / "I know…" / "\"Run.\"" (her biri ×2) | çevir, yok |
| "The boat will not wait" ×2 ; "The boal will not wait" ×2 | …, yok, yok |
| 20 kez sırayla "24 / 120" ve "" | hiç çevir yok |
| "We are" ; "We are out of" ; "We are out of rope for this, kid." ×2 | …, çevir(son), yok |
| "Hello there" ×2 ; "" ; +799 "" ; +1 "" ; "" | …, yok, yok, temizle, yok |
| "Shut the vent" ; çevir ; sonra 3 kez (10 × [+50, ""] ve 4 × [+50, "Shut the vent"]) | hepsi yok |
| "Shut the vent." ; "" ; +800 "" ; +1500 "Shut the vent" ×2 ; "Shut the vent." ; "" ; +800 "" | çevir, yok, temizle, yok, **geri getir("Shut the vent.")**, yok, yok, temizle |
| "Shut the vent." ; "" ; +800 "" (temizle) ; +1501 "Shut the vent." | çevir("Shut the vent.") (yeniden çevrilir) |
| "Shut the vent." ; +100 "Run!" ; +100 "Shut the vent." ; +100 "Run!" | çevir, çevir, geri getir("Shut the vent."), geri getir("Run!") |
| ilk / +50 ikinci: ("Where is the rope?", "Where is the rope, kid?"), (tersi), ("We have to reach the harbor before the tide turns.", "…tide turns, kid.") | çevir, çevir |
| kip açık: "xa Hey, I know exactly who sent you after me." ; "Hey, I know exactly who sent you after me." ×2 | yok, çevir("xa Hey, I know…") (ilk hali), yok |
| kip açık: "q qe & ue need it." ; "Listen, friend, now you could help me out..." | yok, çevir(ikinci) |
| kip açık: "you two... how'd you two like a few extra coins?" | çevir |
| sıfırla (boşken) ; "Hello there" ×2 ; sıfırla ; sıfırla | yok, …, temizle, yok |
| "Shut the vent" ×2 (çevir) ; unut ; 19 × [+50, "Shut the vent"] ; +50 "Shut the vent" | 19 kez yok, sonra çevir |
| "Shut the vent" ×2 ; unut ; "Run!" | çevir("Run!") (bekleme yalnız başarısız satır için) |
| ("I can fix that for you tonight.", "I can't fix that for you tonight."), ("She said that she would sell us the boat.", "…would never sell…"), ("Find me at the station at 7.", "…at 8.") | çevir(ilk), çevir(düzeltme) |
| kip açık: aynı tablodaki 1. ve 3. çift (can/can't, 7/8) ; düzeltme bir kez daha | çevir, çevir, yok |
| "I have 5 arrows left." ; "1 have 5 arrows left." ; "I have 1 arrow left." ; "1 have 1 arrow left." | çevir, yok, çevir, yok |

**Yer ve iz örnekleri** (iz: 64 × 12, her yeri 120; yer: alan kutusu (0,3, 0,6, 0,7, 0,85); "altyazı noktası" iz
satır 8 sütun 30):
- "Shut the vent." (iz, yer) → çevir. Sonra 3000 ms boyunca her 50 ms'de boş okuma, iz [0]=250, [5]=10, altyazı noktası
  +10 (kutu içinde eşik altı) → hep yok. "Shut the vent." okununca → yok. Sonra yine 3000 ms aynı izle boş → hep yok
  (süre baştan sayılır).
- Boş okuma ve altyazı noktası +60 (yer değişti): +799'da yok, +800'de temizle.
- 2000 ms sonra boş (aynı iz) → yok; +1000 ms altyazı noktası −60 → yok; +799 aynı iz → yok; +1 → temizle.
- Yer hiç değişmiyor: boş → yok; +3999 → yok; +1 → temizle (4000 ms sınırı).
- Yer ya da iz yoksa (iz var kutu yok; ya da iz yok kutu var): boş, +800 boş → temizle.

---

## 9. OCR çöpü ölçüleri

### 9.1 Ortak

Parça (boşlukla ayrılmış) §7.3'teki gibi baş/çekirdek/son diye ayrılır; çekirdeğin **harfleri** alınır; harfi yoksa
parça sayılmaz.

**Düzgün parça:** çekirdek temizliği çekirdeği değiştirmiyor (§7.3), **olağan büyük/küçük harf** düzeninde, çekirdekte
`[ ] ( )` yok ve **ünlüsüz** değil.
- **Olağan büyük/küçük:** harflerin hepsi büyük ya da ilkinden sonrakilerin hepsi küçük; ya da ilkinden sonra tam bir
  büyük harf var ve en az 2 küçük harf var ("McDonald", "iPhone").
- **Ünlüsüz:** en az 3 harf, hepsi büyük harf değil, küçük hallerinde `a e i o u y ä ö ü ı à á â è é ê ì í î ò ó ô ù ú
  û`'den hiçbiri yok ve art arda tekrarlar teke indirilmiş küçük hali şu ünlemlerden biri değil: hm, m, sh, br, gr, pst,
  pft, tsk, hrm, z, pht ("Hmm", "Shh", "Brr", "Psst", "Mmm" geçerli).

### 9.2 OCR çöpü puanı

Düzgün parça harf sayısı kadar artı, değilse 2 × harf sayısı eksi. Aynı karenin iki okumasından iyisini seçmeye yarar.
- "MARA: Hold on for me!" > "- MARAiVJütt'h!"
- "We met at McKenzie's place." > 0
- "T his the[lil Should be fine now." < "This should be fine now."
- "Get to the roof now." > "Gtt to the roof now."
- "Hmm!", "Shh!", "Brr!", "Psst!", "Mmm!" > 0

### 9.3 Çöp gibi mi

Düzgün parçaların harfleri "iyi", diğerlerinin "kötü" toplanır; `kötü × 6 > iyi + kötü` ise çöp gibidir.

| Metin | Çöp gibi |
|---|---|
| Fnd yuor kyes. | evet |
| - MARAiVJütt'h! | evet |
| Wrrk thng. | evet |
| Shut the vent. | hayır |
| The CIA and the NSA files. | hayır |
| Hmm, I don't like the sound of that. | hayır |
| Find your keys. | hayır |

### 9.4 OCR izi (paket bekletmesi için "bozuk okuma" kuralı)

Hattın "okuma bozuk mu" ölçüsü = **OCR izi** ya da (varsa) Windows yazım denetiminin bozuk okuma kararı (§3.6). OCR izi
(paket araması tarafındaki ortak kural; paketler belgesinde de geçer):
1. Metinde 127'den büyük bir karakter varsa ve `’ ‘ “ ” — – …`'den biri değilse → bozuk.
2. Her boşluk sözcüğü için: uçlarından `. , ! ? ; : ' " ( ) [ ] - … “ ” ’ ‘` atılır; boşsa geç.
   - İç konumda (ilk ve son harici) iki yanı harf olup kendisi harf, `'`, `’`, `-` olmayan karakter → bozuk.
   - Yan yana harf-rakam ya da rakam-harf → bozuk.
   - Tek karakterli harf sözcük ve a, A, I, o, O değilse → bozuk.
   - 14 karakterden uzun → bozuk.
3. Değilse bozuk değil.

---

## 10. Metin karşılaştırma kuralları

Her yerde "temiz sözcükler" = sadeleştirilmiş metnin boşluk sözcüklerinden **1 karakterden uzun** ve **hiç sayı
karakteri içermeyen**ler (tek harfler ve rakamlı sözcükler karşılaştırmaya girmez). "Baştan uyar" / "sondan uyar": sözcük
dizisinin ilk/son k sözcüğü diğer diziye birebir eşit.

### 10.1 Aynı altyazı mı (yeniden okuma, gönderilene karşı)

Girdi: sadeleştirilmiş okuma ve gönderilen (satır satır sadeleştirilmiş olabilir).
1. Gönderilenin satırları boşlukla birleşir ("düz").
2. Okuma düze göre **anlam işareti ekliyorsa** (§10.5) → hayır.
3. x = okumanın temiz sözcükleri, y = düzün. y boş değil, x daha uzun ve (x, y ile başlıyor ya da y ile bitiyor) →
   hayır (uzayan metin yenidir).
4. Okuma ile düz karakterce benzer (0,85) → evet.
5. x boş değil, x daha kısa ve (y, x ile başlıyor ya da bitiyor) → yalnız **tam satırlar** okunduysa evet: gönderilenin
   satırlarının temiz sözcük sayıları baştan (y x ile başlıyorsa) ya da sondan toplanır; toplam x'in sayısına tam
   eşitlenirse evet, aşarsa ya da biterse hayır.
6. Ortak sözcükler (çoklu küme: her eşleşen sözcük bir kez tüketilir) sayılır. x ≥ 4 sözcük, x ≤ y ve ortak ≥ x × 0,85
   → evet.
7. Kısa = min, uzun = max (x, y sayıları). Kısa < 6 ya da kısa/uzun < 0,75 → hayır.
8. ortak / uzun ≥ 0,75 → evet, değilse hayır.

| Okuma | Gönderilen | Sonuç |
|---|---|---|
| Over the frozen hills, 7bq Mira rode, Looking 4q fire to warm her hands now. | Over the frozen hills, Mira x$7q rode, looking for a fire to warm her hands. | aynı (karakterce benzer değil) |
| (çöp temizlenmiş) Over the frozen hills7bq O rode, | iki satır: "Over the frozen hills, Mira rode," / "looking for a fire to warm her hands." | aynı |
| Over the frozen hills, Mira rode, | (aynı iki satır) | aynı |
| looking for a fire to warm her hands. | (aynı iki satır) | aynı |
| (iki satırın tamamı) | yalnız ilk satır | farklı |
| Where is the rope? / Where is the rope, kid? (iki yönde de) | | farklı |
| We have to reach the harbor before the tide turns, kid. | We have to reach the harbor before the tide turns. | farklı |
| Kid, we have to reach the harbor before the tide turns. | (aynı) | farklı |
| we must find the key | We must find the key before the guards wake up (tek satır) | farklı |
| we must find the key | We must find the key / before the guards wake up (iki satır) | aynı |
| we are out of rope | the boat will not wait | farklı |
| we are out of rope for this kid and you know it | we are out of rope | farklı |
| where is the lamp | where is the dog | farklı |
| you must not go there | i asked you to wait by the front door | farklı |
| we must find the key before the guards wake up | the key is too rusty for us to use today | farklı |
| I can't fix that for you tonight. | I can fix that for you tonight. | farklı |
| She said that she would never sell us the boat. | She said that she would sell us the boat. | farklı |
| She is not waiting at the dock. | She is waiting at the dock. | farklı |
| Find me at the station at 8. | Find me at the station at 7. | farklı |
| I can’t fix that for you tonight. | I can't fix that for you tonight. | aynı |
| I dont see where to go. | I don't see where to go. | aynı |
| She is n0t waiting at the dock. | She is not waiting at the dock. | aynı |

### 10.2 Düzeltme mi (TV "yerine koy" kararı)

Yeni metin, eskisinin büyümüş ya da düzeltilmiş hâli mi (girdi ham metinlerdir):
1. İkisi sadeleştirilir; biri boşsa hayır.
2. Biri ötekinin **uzaması** (§10.4) ise evet (iki yönde de).
3. Sadeleştirilmişler 0,8 ile benzerse evet.
4. Temiz sözcükler; kısa olanın sayısı < 5 ise hayır.
5. Sözcük dizileri arasındaki düzenleme oranı (sözcük düzeyinde benzerlik oranı) ≥ 0,65 → evet.
6. Ortak sözcük (çoklu küme) / uzun ≥ 0,7 → evet.

| Yeni | Eski | Düzeltme mi |
|---|---|---|
| We are out of rope for this. | We are out of | evet |
| We are out of | We are out of rope for this. | evet |
| of rope for this, kid. | We are out of rope for this, kid. | evet |
| The boat will not wait! | The boal will not wait | evet |
| Over the frozen hills she rode, looking for a fire to warm her hands. | Over the frozen hills O rode, Looking for a fira to warm her hands | evet |
| Run to the cave! | We are out of rope for this. | hayır |
| Where is the lamp? | Where is the dog? | hayır |
| No. | Yes. | hayır |
| I asked you to wait by the front door. | You must not go there. | hayır |

### 10.3 Kötü yeniden okuma mı

Yeni okuma, gönderilmiş cümlenin daha kötü (ya da eşit) bir bozuk kopyası mı:
1. Sadeleştir, temiz sözcükler x (okuma), y (gönderilen). x < 5 sözcük ya da y boş ya da biri ötekinin uzaması ya da okuma
   anlam işareti ekliyor → hayır.
2. "Okuyor": sözcük düzeyinde benzerlik ≥ 0,65 ya da sadeleştirilmişler 0,75 ile benzer.
3. Okuyorsa ve okumanın OCR çöpü puanı < gönderilenin puanı + 4 ise evet. (Burada her zaman §9.2 puanı kullanılır,
   sözlük değil.)

Örnek: Tam/Kötü çifti (§8.5) → Kötü, Tam'ın kötü yeniden okumasıdır; Tam, Kötü'nün değildir (puanı belirgin yüksek).

### 10.4 Uzama

Yeni metin, eskinin sonuna (ya da satırın başı okunmamışsa başına) sözcük eklenmiş hali mi: sadeleştirilmiş sözcük
dizileri (bütün sözcükler, temiz değil); eski boşsa ya da yeni daha uzun değilse hayır; yeni eskiyle başlıyorsa evet;
eski en az 2 sözcükse ve yeni eskiyle bitiyorsa evet.

| Yeni | Eski | Uzama |
|---|---|---|
| We are out of rope. | We are out | evet |
| We are out | We are out of rope. | hayır |
| We are out of rope. | We are out of rope. | hayır |
| Then we sail north. | Then | evet |
| Then we sail north. | north | hayır |
| Then we sail north. | sail north | evet |

### 10.5 Anlam işareti ekliyor mu

Bir olumsuzluk sözcüğü ya da bir sayı, harf farkı olarak küçük ama anlam olarak büyüktür. Yalnız yeni okumada
**fazladan** görülen işaret sayılır (eksilen işaret genelde tanıyıcının kaçırdığıdır).

- **Olumsuzluklar:** not no never nothing nobody none nowhere neither nor cannot dont doesnt didnt cant wont isnt arent
  wasnt werent aint couldnt shouldnt wouldnt havent hasnt hadnt mustnt neednt
- **Rakam→harf katlaması:** 0→o, 1→i, 3→e, 4→a, 5→s, 7→t, 8→b.
- **Aynı glif sözcüğü:** iki sözcük eşit; ya da ilki tamamen ASCII rakam ve katlanmışı ikinciye eşit ("1" ~ "i").

Adımlar:
1. İki metin sadeleştirilip sözcüklere bölünür (okuma: w, gönderilen: s).
2. Her dizide işaretler: tamamen ASCII rakam sözcük → sayı listesine; değilse rakam içeriyorsa katlanır; olumsuzluk
   listesindeyse ya da sözcük "t" ise ve önceki sözcüğün katlanmışı + "t" olumsuzluksa ("can t", "won t") → olumsuzluk
   sayısı bir artar.
3. Okumanın olumsuzluk sayısı fazlaysa → evet.
4. Okumada sayı yoksa → hayır.
5. Aynı glif hizalaması: diziler eşit uzunluktaysa her konumda farklı ama aynı glif sözcükse okumanın o sözcüğü sayı
   listesinden (bir tane) çıkarılır. Değilse baştan aynı glif olduğu sürece ilerlenir (farklıysa çıkarılır), sonra
   sondan geriye (baştaki bölümü geçmeden) aynı yapılır.
6. Kalan her sayı gönderilenin sayı listesinden çıkarılamıyorsa → evet. Yoksa hayır.

| Okuma | Gönderilen | Ekliyor mu |
|---|---|---|
| I can't fix that. | I can fix that. | evet |
| I can fix that. | I can't fix that. | hayır |
| Find me at 8. | Find me at 7. | evet |
| Find me at | Find me at 7. | hayır |
| She is n0t home. | She is home. | evet |
| I dont know. | I don't know. | hayır |
| Grab a t shirt. | Grab a shirt. | hayır |
| Grab a wool t shirt. | Grab a wool shirt. | hayır |
| I won t go. | I will go. | evet |
| They haven t eaten. | They have eaten. | evet |
| Take 3 and 3. | Take 3. | evet |
| Take 3. | Take 3 and 3. | hayır |
| That costs $750 now. | That costs $750. | hayır |
| 1 can fix that. | I can fix that. | hayır |

Sayı değişikliği (hepsinde: ekliyor = evet, aynı altyazı = hayır, kötü yeniden okuma = hayır):
`I have 1 arrow left.` / `I have 5 arrows left.`; `I have 1 arrow left.` / `I have 5 arrow left.`;
`1 have 1 arrow left.` / `I have 5 arrows left.`; `I need 1 more rope.` / `I need more ropes.`;
`We got 1 and 1 back.` / `We got 1 back.`; `We got 1 and 1 back.` / `We got 1 and 5 back.`;
`O, we have 0 coins left.` / `O, we have 5 coins left.`; `I have 10 coins left.` / `I have 5 coins left.`;
`I have 1 coin left.` / `I have\n5 coins left.`

Harf-rakam gürültüsü (hepsinde ekliyor = hayır): `1 can fix that.` / `I can fix that.`; `0, we should head out.` /
`O, we should head out.`; `Now 1 can fix that.` / `Now I can fix that.`; `Ycs 1 can fix thal.` / `Yes I can fix that.`;
`Yes 1 can fix that.` / `Well I can fix that.`; `1 can fix that now.` / `I can fix that.`; `Now 1 can fix that.` /
`I can fix that.`; `1 have 1 coin left.` / `I have 1 coin left.`; `1 said 1 can fix that.` / `I said I can fix that.`;
`1 have 5 coins left.` / `I have 5 coins left.`

---

## 11. Çeviriye gönderme: bekletme, sıra, geç sonuç, paket

### 11.1 Sayılar ve durum

| Ad | Değer |
|---|---|
| Geç sonuç sınırı (satır kalktıktan sonra) | 2500 ms |
| Sırada bekleyebilecek satır | 2 |
| Bozuk okuma bekletmesi (varsayılan; ayar 0–2000) | 800 ms |
| Yarım görünen temiz satır bekletmesi (varsayılan; ayar 0–2000) | 300 ms |
| Az önce çevrilenin yeniden okuması sayılma penceresi | 4000 ms |
| Hatırlanan (kaynak → çeviri) çifti | 8 |
| Ekranda duran satırın gösterim süresi | 15 000 ms |
| Kalkmış satırın geç gelen çevirisinin gösterim süresi | min(8000, 2000 + uzunluk × 60) ms |

Durum: bekletilen okuma (kaynak, kutu, başlangıç anı, en çok bekleme, puan, okunduğu kare bilgisi); son gönderilen
(motora ya da pakete giden kaynak, puanı, anı); son temizlik anı (başta "hiç"); son istenen ve son gösterilen istek
numaraları; süren istek ve iptal sinyali; sıradakiler; **ekrandaki satırın** istek numarası (bölge boşalınca yok);
hatırlanan çiftler (numara, kaynak, çeviri ya da "zaten hedef dilde" için yok); oturum numarası; son okuma ve süresi;
son önceden çeviri metni; son gösterilen çift, kutu, köken ("paket", "motor", "havuz"), ölçümler, son hata; paket isabet
sayısı.

**İstek:** numara (artan), kaynak, kutu, oturum, konuşan adı ayrımı (§12), kalkış anı (ekrandaysa yok), "yerine
uzamış okuması geldi" bayrağı, "bırakıldı" bayrağı, okunduğu kare bilgisi (geliş anı, OCR süresi, güven).

**Ekrandaki satır kalktı:** ekrandaki satırın numarası varsa, o numaralı süren/sıradaki isteklerin kalkış anı (yoksa)
şimdi olur; ekrandaki satır yok olur.

**Ölçüler:** okumanın puanı = (varsa) sözlük puanı, yoksa §9.2. Okuma bozuk mu = §9.4. Bekletme etkin mi = paket araması
verildiyse ya da "paketsiz bekletme" açıksa (Windows'ta yazım denetimi varken açık; §3.5).

**Paket araması (hat içi):** Paket araması verilmemişse yok. Bekletilen okuma varken, aranan metin bekletilenin **paket
parçası** (§11.2) ise ve bütün satırları bekletilen tarafından örtülüyorsa ve puanı bekletileninkinden büyük değilse →
yok (bekleyen tam metnin parçası üstün sayılmasın). Değilse metnin kendisiyle aranır; bulunmazsa konuşan adı varsa
adsız cümleyle aranır. (Arama işinin içeriği, ör. önce oyun paketi sonra havuz, paketler/havuz belgesindedir.)

### 11.2 Yardımcı kurallar

- **Tam görünüyor:** boş olmayan her satırın ilk harfi büyük ve satır cümle bitiriyor (harfi olmayan satır tam değil).
- **Paketteki parça (kaynak, önceki):** kaynak tam görünüyorsa hayır. Sadeleştirilmiş kaynak boş değil, öncekinden kısa ve
  " önceki " içinde " kaynak " (sözcük sınırlarıyla) geçiyorsa evet.
- **İlgili (a, b):** sadeleştirilmiş sözcükler; biri boşsa hayır; ortak (çoklu küme); kısa olanın sayısı ≤ 1 ise ortak ≥ 1;
  değilse ortak ≥ 2 ve ortak × 2 ≥ kısa.
- **Yeniden okuması mı (yeni, eski):**
  1. Yeni anlam işareti ekliyorsa hayır (düzeltmedir).
  2. Sadeleştirilmiş yeni ≥ 4 karakter, sözcük sayıları eşit ve 0,75 ile benzer → evet.
  3. Sözcük sayıları eşit ve ≥ 2: farklı konumlar ≥ 1, farklı sayısı × 2 ≤ sözcük sayısı ve farklı yeni sözcüklerin hepsi
     bozuk okuma → evet ("Okay? Brrkmn." / "Okay? Fine.").
  4. Biri bozuk okumaysa → ilgili mi.
  5. Yeni boş ya da eskiden uzunsa → hayır.
  6. Yeni ≥ 2 sözcük, eskiden kısa ve sözcükleri eskide aynı sırada ama **bitişik olmayan** biçimde geçiyorsa (açgözlü
     eşleme; ilk ve son eşleşme arası yeni sözcük sayısından geniş) → evet ("Go to Ridge." / "Go to Copper Ridge.").
  7. Yeni cümle bitiriyorsa ve (küçük harfle başlayıp eskiden kısa) değilse → hayır. ("Küçük harfle başlamak":
     kırpılmış ilk karakter büyük harf değil.)
  8. Yeni sözcükler eskinin içinde **bitişik** geçiyorsa → evet; yoksa hayır.
- **Örtülü (satır, önceki):** sadeleştirilmiş satır boşsa evet; satır, önceki metnin (satır sonları boşluk olarak)
  yeniden okumasıysa evet; önceki metnin satırlarından biri sadeleştirilmişçe aynıysa ya da satır onun yeniden okumasıysa
  evet.
- **Bütün satırlar örtülü:** boş olmayan satırlar var ve hepsi örtülü. (Örnek: önce "He's a bum!", sonra "He's a bum!\nOh my God!" okunursa
  ikinci satır örtülü değildir, okuma yeni sayılır.)
- **Eksik satırları koru (daha iyi, eski):** eskinin boş olmayan, bozuk olmayan, daha iyide örtülü olmayan ve daha iyinin
  hiçbir satırının "anlam ekleyen ve 0,85 benzer" düzeltmesi olmayan satırları; varsa daha iyinin sonu kırpılıp `\n` ve
  bu satırlar (`\n` ile) eklenir.
- **Bekleme süresi (kaynak):** bekletme etkin değilse 0; bozuksa bozuk okuma bekletmesi (eksi değilse); tam görünüyorsa
  0; değilse yarım satır bekletmesi.
- **Sıradakinin yerini alır (yeni, sıradaki):** yeni, sıradakinin düzeltmesi (§10.2) ve sıradaki yeninin uzaması değil
  (kısa okuma, uzun olanı sıradan düşüremez).
- **Gösterileni düzeltiyor:** son gösterilen çift varsa ve yeni kaynak onun kaynağının düzeltmesiyse (TV yerine koyar).

### 11.3 Çevir ya da beklet (sabitleyici "çevir" dediğinde)

1. **Sıradaki tam okuma geri geldi mi** (§11.8): öyleyse dur.
2. Bekletme etkin değilse: ekrandaki satır kalktı, sıraya koy (§11.5).
3. Pakette var mı bakılır.
4. **Az önce çevrilenin tekrarı:** son gönderilen varsa ve (pakette değilse ya da (son gönderim son temizlikten sonraysa
   ve kaynak son gönderilenin paket parçasıysa)) ve son gönderimden < 4000 ms geçtiyse ve bütün satırları son gönderilen
   tarafından örtülüyorsa ve puanı son gönderilenin puanından büyük değilse: son gönderilenin anı şimdi olur, günlüğe
   [yeniden okuma yok sayıldı; alıntı] yazılır, dur. (Bu denetim bekleme yaratmaz; bütün bekleme süreleri
   0 iken de devrededir.)
5. Ekrandaki satır kalktı.
6. Paketteyse sıraya koy.
7. Bekleme süresi ≤ 0 ise sıraya koy.
8. Değilse **beklet:** (kaynak, kutu, şimdi, süre, puan, bu karenin okuma bilgisi); günlüğe [bekletiliyor; en çok ms; alıntı].

### 11.4 Bekletilen okuma varken her kare (tepki işlenmeden önce)

**Tepki "çevir" ise** (kaynak = tepkinin metni; süre = max(bekletilenin süresi, kaynağın bekleme süresi)):
1. Kaynak pakette bulunuyorsa: bekletilen atılır [bekleyen atıldı, yerine paket satırı; alıntı]; tepki aynen işlenir.
2. Kaynak bekletilene göre **anlam işareti ekliyor** ve sadeleştirilmişleri 0,85 benzerse (olumsuzluk/sayı düzeltmesi,
   puan eşit olsa da): bekletilen = (eksik satırları koru(kaynak, bekletilen), yeni kutu ya da eski, **aynı başlangıç**,
   süre, yeni puan, aynı kare bilgisi); tepki "hiçbir şey" olur; ekrandaki satır kalktı; şimdi − başlangıç ≥ süre ise
   bekletme biter ve birleşik metin sıraya konur.
3. (Kaynak bekletilenin yeniden okuması ya da tersi) ve şimdi − başlangıç < süre ise: kaynağın puanı bekletileninkinden
   büyükse bekletilen = (eksik satırları koru(kaynak, bekletilen), …, aynı başlangıç, süre, birleşiğin puanı); tepki
   "hiçbir şey"; ekrandaki satır kalktı.
4. Bekletilen bozuk okumaysa: atılır [bozuk bekleyen atıldı, başka satır geldi; alıntı]; tepki aynen işlenir.
5. Kaynak bozuksa ve şimdi − başlangıç < bekletilenin **kendi** süresi ise: tepki "hiçbir şey" (araya giren bozuk ve
   ilgisiz okuma bekleyeni bozmaz).
6. Değilse: bekletilen temizdi, önce o sıraya konur ("önce bunu çevir" işi); sonra tepki aynen işlenir.

**Tepki "temizle" ya da "geri getir" ise:** bekletme biter; bekletilen bozuk değilse "önce bunu çevir" olarak sıraya
konur, bozuksa [bozuk bekleyen atıldı, beklerken kalktı; alıntı].

**Tepki "hiçbir şey" ise:**
1. Okumanın kırpılmış metni ≥ 3 karakter ve pakette bulunuyorsa: bekletme biter; yeni istek (yeni numara, kaynak =
   kırpılmış okuma, kutu = yeni ya da bekletilenin, kare bilgisi = bekletilenin, yoksa bu karenin); ekrandaki satır =
   bu istek; paketten göster (§11.9).
2. Değilse: kırpılmış metin ≥ 3, bekletilenle ilgili ve puanı bekletileninkinden büyükse bekletilen = (eksik satırları
   koru(metin, bekletilen), kutu, aynı başlangıç, **aynı süre**, birleşiğin puanı). Sonra şimdi − başlangıç ≥ süre ise
   bekletme biter, (güncel) bekletilen sıraya konur.

### 11.5 Sıraya koyma

1. Yeni istek (numara bir artar; kare bilgisi verilmediyse bu karenin, o da yoksa (şimdi, yok, yok)); ekrandaki satır =
   bu istek; son gönderilen = (kaynak, puanı, şimdi).
2. Pakette bulunuyorsa paketten göster (§11.9) ve dur.
3. Süren istek yoksa: günlüğe [#N; alıntı; çeviriye gitti]; bu istek süren olur, çeviri pompası başlar (§11.6).
4. Varsa: günlüğe [#N; alıntı; sıraya girdi; süren #M]. Sıradakilerden yerini aldıkları ("sıradakinin yerini
   alır") çıkarılır, her biri için [eski #; atıldı, yerini düzelmiş okuma #N aldı]. İstek sona eklenir. Sıra 2'yi aşarsa en
   eskiler atılır [#; atıldı, sıra dolu]. Süren istek "uzamış" ya da "bırakıldı" değilse, aynı oturumdaysa ve yeni kaynak
   onun **uzamasıysa** (daktilo efekti): [süren #; bırakıldı, uzamış okuma #N geldi], süren "uzamış" işaretlenir ve iptali
   **hemen** istenir (iptal bu adımın sonuna konur, çünkü iptal pompayı hemen ilerletebilir ve yeni satırın o anda sırada
   bulunması gerekir).
5. Kilit dışında "pakette yok" olayı (kaynak) verilir (paket araması verilmemişse de: havuz önerisi için).

### 11.6 Çeviri pompası, sonuç ve bırakma

**Pompa:** süren isteği çevirir; bitince (hata da olsa) sıradakine geçer:
1. Yeni iptal sinyali kurulur ve saklanır; çeviri (§11.6 sonuç) beklenir; herhangi bir hata yutulur (olay işleyicisi hata
   verse de sıra takılmasın).
2. Saklanan iptal sinyali silinir, sinyal yok edilir (iptal ile yok etme aynı anda çalışmasın diye sinyalin kendi
   kilidiyle).
3. Kilit altında: başka oturumdan kalan sıradakiler [#; atıldı, oturum bitti] ve kalktığından 2500 ms'den uzun süre geçmiş
   sıradakiler [#; atıldı, çevrilmeden kalktı; kaç ms önce] atılır. Sıra boşsa süren yok olur, pompa durur; değilse
   ilki çıkarılıp süren olur.

**Bütün çevirileri bekle:** pompa işi bitene kadar (yenisi başlarsa onu da) beklenir.

**Bir isteğin çevirisi:**
1. Çevirmene giden = konuşan adı varsa cümle, yoksa kaynak. Başlangıç anı alınır. (Önbellekten mi geldi, hangi motor
   çevirdi yalnız günlük için ölçülür: "motor yeni çevirdi (adıyla)", "hepsi önbellekten" ya da bilinmiyorsa "motor
   (genel ad)"; bu bilgi aşağıda [köken] diye geçer.)
2. **Hata:** kilit altında: istek başka oturumdansa ya da "uzamış"/"bırakıldı" ise sessizce bit (hata sayılmaz, olay da
   verilmez). Değilse günlüğe [#N; hata; geçen ms; çevirmen durumu ya da hata türünün adı; satır ekrandaysa
   "ekranda kaldıkça yeniden denenecek" notu]; son hata = çevirmen durumu (çevirmen hatası değilse yok). İstek ekrandaki satırsa: sabitleyiciye
   "gönderileni unut" (§8.4), son gönderilen bu kaynaksa silinir (aksi hâlde aynı satır "yeni çevrildi" sanılıp bir daha denenmezdi).
   Kilit dışında "çeviri sonucu" olayı (son hata). Bit.
3. **Başarı:** çeviri konuşan adına göre sunulur (§12). Kilit altında: başka oturum ya da "bırakıldı" ise günlüğe
   [#N; köken; ms; atıldı; neden: bırakıldı ya da oturum bitti], bit. Değilse son hata silinir. Kilit dışında "çeviri sonucu
   (başarılı)" olayı.
4. Kilit altında yine aynı denetim. Kaynak **şimdi** pakette bulunuyorsa (çeviri sürerken havuza gelmiş) onun metni
   kullanılır. (Örnek: bekleyen çevirmen, "Shut the vent" ×4 beklemeden, saat +150; istek gidince paket aramasına
   "Shut the vent" → "Menfezi kapat" eklenir; çevirmen açılınca TV yalnız ["Menfezi kapat"].)
   Gönderilmeli mi = §8.4 (çevirmene giden metin ile çeviri cümlesi, **konuşan adı olmadan**). Çift
   hatırlanır (gönderilmeyecekse çeviri yok).
5. İsteğin numarası ≤ son gösterilen ise, ya da gönderilmeyecekse, ya da "uzamış" ise: günlüğe [#N; köken; ms; atıldı;
   neden: zaten hedef dilde / uzamış okuma geldi / daha yeni satır #M gösterildi], bit.
6. Ekranda mı = numara ekrandaki satır mı. Ekranda değilse ve kalkışından 2500 ms'den uzun geçtiyse: [#N; köken; ms; geç kaldı;
   satır kaç ms önce kalktı; gösterilmedi], bit.
7. Günlüğe [#N; köken; ms; gösterildi; ekranda değilse "satır kalkmıştı" notu]. Son gösterilen = numara. TV'ye gönder: metin, süre (ekranda
   ise 15 000, değilse min(8000, 2000 + uzunluk × 60)), kutu, "yerine koy" = gösterileni düzeltiyor. Son çift, kutu,
   köken "motor"; ölçümler (§13, çeviri başlangıç–bitiş ile).
8. Kilit dışında önce "ölçüm hazır", sonra "çift gösterildi" olayları.

**Gösterilemeyecek süren çevirinin bırakılması (her kare sonunda, kilit altında):** süren istek yoksa, başka oturumdansa,
"uzamış" ya da "bırakıldı" ise ya da iptal sinyali yoksa bir şey yapılmaz. "Geçildi" = numarası son gösterilenden küçük;
"süresi doldu" = numarası son gösterilenden büyük, ekrandaki satır değil ve kalkışından 2500 ms'den **uzun** geçti.
İkisi de değilse bir şey yapılmaz. "Süresi doldu" ise ayrıca **geçerli bir sıradaki** (aynı oturum, işaretsiz, kalkışından
2500 ms'den uzun geçmemiş) olmalı. Bırakılır: "bırakıldı" işaretlenir; son gönderilen bu kaynaksa silinir (eski kaynak
geri gelirse yeniden çevrilebilsin); günlüğe [#N; bırakıldı; neden: daha yeni satır gösterildi ya da süresi
doldu ve yeni satır bekliyor]; iptal sinyali kilit dışında verilir. İptali dinlemeyen çevirmenin sonucu da "bırakıldı"
olduğu için gösterilmez; pompa ancak o çağrı bitince sıradakine geçer (aynı anda iki çeviri başlamaz).

### 11.7 Geri getirme (sabitleyici "geri getir" dediğinde)

1. Sıradaki tam okuma geri geldi mi (§11.8): öyleyse dur.
2. Son gönderilen varsa ve kaynak onunla ilgiliyse ya da bütün satırları onun tarafından örtülüyorsa: kaynağın puanı
   daha yüksekse son gönderilen = (kaynak, puan, şimdi), değilse yalnız anı şimdi olur. Bekletme etkinse: hatırlanan
   çiftlerde son gönderilenin kaynağı varsa, son gönderilen kaynaktan farklıysa, kaynağın bütün satırları onun tarafından
   örtülüyorsa ve kaynağın puanı **daha düşükse** (tam satırın yarım okuması geri geldi): ekrandaki satır = o çiftin
   numarası; günlüğe [#N geri geldi, yarım okumasıyla; alıntı]; çevirisi varsa TV'ye 15 000 ms, bu karenin kutusu, **yerine koy**
   ile gönderilir; son çift = (tam kaynak, çeviri), son kutu; dur.
3. Hatırlanan çiftlerde kaynak birebir varsa: ekrandaki satır = o numara; [#N geri geldi; alıntı]; çeviri yoksa (zaten hedef
   dilde) dur; varsa TV'ye 15 000 ms, kutu, "yerine koy" = gösterileni düzeltiyor; son çift ve kutu; dur. (Olay
   verilmez; ölçüm yapılmaz.)
4. Süren ya da sıradaki istekte bu kaynak (aynı oturum, işaretsiz) varsa: kalkış anı silinir, ekrandaki satır = o; dur.
5. Değilse çevir ya da beklet (§11.3).

### 11.8 Sıradaki tam okumanın geri gelmesi

Kaynakla **birebir aynı** olan en son sıradaki istek varsa, kalkış anı varsa ve son temizlikten sonraysa: ondan sonra
sıraya giren ve kaynağın uzaması olan (yani kaynağın kısalmış okumaları) sıradakiler varsa bunlar atılır [#; atıldı, tam okuma #N
geri geldi], ekrandaki satır kalktı, tam isteğin kalkış anı silinir, ekrandaki satır = o, son gönderilen =
(kaynak, puan, şimdi) → "evet, işlendi". Gerçek bir boş bölge (temizlik) bu birleşmeyi aşmaz.

### 11.9 Paketten gösterme

1. Bütün sıradakiler atılır [#; atıldı, sonraki satır #N paketten]; paket isabet sayısı bir artar.
2. Çeviri = paketin metni, konuşan adına göre sunulmuş (§12).
3. Kaynakta Türkçe harf (`ğ ı ş ç ö ü Ğ İ Ş Ç Ö Ü`) var mı. **Gönderilmeli mi** = (kaynak ile sunulan çeviri 0,90 benzer
   değil) **ya da Türkçe harf yok**. (Paket kaynakları İngilizce olduğundan, karşılığı kaynakla aynı yazılsa bile — ad, ünlem — gösterilir;
   yalnız kaynakta Türkçe harf geçiyorsa, yani konsolun kendi Türkçe yazısıysa ve karşılık aynıysa gösterilmez.)
4. Çift hatırlanır (gösterilmeyecekse çevirisiz). Günlük kökeni: paketin adı biliniyorsa "paket + ad", değilse yalnız "paket".
5. Gösterilmeyecekse günlüğe [#N; alıntı; paket kökeni; zaten hedef dilde, gösterilmedi], dur (son gösterilen değişmez; süren çeviri
   bırakılmaz).
6. Günlüğe [#N; alıntı; paket kökeni]. Son gösterilen = numara. TV'ye 15 000 ms, isteğin kutusu, "yerine koy" = gösterileni
   düzeltiyor. Son çift, kutu, köken "paket". Ölçüm (çeviri süresi yok, köken paket). Kilit dışında "ölçüm hazır", sonra
   "çift gösterildi".

### 11.10 Havuzdan daha iyi çeviri

Sunucunun çeviri havuzundan sonradan (daha iyi) bir çeviri gelirse (kaynak, çeviri):
- Çeviri boşsa, kaynak hatırlanan çiftlerde yoksa ya da çiftin çevirisi yoksa (zaten hedef dilde) bir şey yapılmaz.
- Sunulan çeviri (konuşan adına göre) çiftteki ile aynıysa bir şey yapılmaz. Değilse çift güncellenir (sonraki geri
  gelişlerde bu kullanılır).
- Çiftin numarası **hem** ekrandaki satır **hem** son gösterilen değilse, ya da son köken "paket" ise, ya da son çiftin
  kaynağı bu değilse yalnız hatırlanır.
- Değilse: günlüğe [#N; havuzdan daha iyi çeviri yerine kondu]; TV'ye 15 000 ms, son kutu, **yerine koy**; son
  çift, köken "havuz"; kilit dışında "çift gösterildi" (ölçüm yok).

### 11.11 Hatırlama ve sıfırlama

- **Çift hatırlama:** aynı kaynaklı çiftler silinir, yenisi sona eklenir; 8'i aşarsa en eski atılır.
- **Sıfırla** (okuma durdu, hat yeniden kuruldu): günlüğe [hat sıfırlandı; bu hatta paketten gelen satır sayısı]; oturum başı = şimdi; ilk
  kare/ilk yazı/not/dev not bilgileri silinir; **oturum numarası artar**; ekrandaki satır, sıra, bekletilen, son
  gönderilen silinir; son temizlik "hiç"; süren çeviriye iptal; çiftler, son okuma ve süresi, kare bilgisi silinir; plan
  sıfırlanır; sabitleyici sıfırlanır, "temizle" dönerse TV'ye "temizle". (Son gösterilen/istenen numaraları, paket isabet
  sayısı ve son önceden çeviri metni sıfırlanmaz.) Sıfırlamadan sonra biten eski okuma ve eski çeviriler hiçbir şey
  göstermez.

### 11.12 Hat örnekleri

Aksi söylenmedikçe: okuyucu sırayla verilen metinleri döndürür (yalnız metin, kutusuz), sonra boş; 64 × 64 boş kare,
varsayılan bölge; her kare okunur ("her zaman" planı); sahte çevirmen "TR: " + metin döndürür; her kareden sonra
çeviriler beklenir; saat verilmişse 1 000 000'den başlar ve her kareden sonra +50.

| Senaryo | Beklenen |
|---|---|
| "Shut the vent" ×3 | TV: ["TR: Shut the vent"]; son çiftin kaynağı "Shut the vent" |
| Okuma çağıranın iş parçacığında yapılmaz | okuyucunun iş parçacığı çağıranınkinden farklı |
| Çevirmen "model indirilmedi" hatası, "Shut the vent" ×2 | TV boş; son hata = model indirilmedi |
| "Shut the vent" ×25, çevirmen ilk çağrıda zaman aşımı | TV: ["TR: Shut the vent"] (satır ekrandayken yeniden denendi) |
| "Shut the vent" ×40, hep "model indirilmedi" | çevirmene 2–3 istek (saniyede en çok bir) |
| "Shut the vent" ×2, "" ×2, "Shut the vent" ×1 | temizle yok; TV tek satır |
| "Shut the vent" ×3, "" ×15, ×3, "" ×10, ×3 | temizle yok; TV tek satır; çevirmene tek istek |
| "Shut the vent" ×2, "" ×17 | 18 kareden sonra temizle 0; 19. karede 1 |
| "Shut the vent." ×2, "" ×20, "Shut the vent." ×2 | temizle 1; TV: iki kez "TR: Shut the vent." (ikisi de 15 000 ms); çevirmene 1 istek; "çift gösterildi" 1 kez |
| "Shut the vent." ×2, "" ×50, ×2 | çevirmene 2 istek |
| "Where is the rope, kid?" ×3, "Where is the rope?" ×3 | ikisi de gösterilir |
| Bekleyen çevirmen; "Shut the vent", "Shut the vent", "Run", "Run" (beklemeden) ; çevirmen açılır | istekler ["Shut the vent", "Run"] |
| Bekleyen çevirmen; "Shut the vent.", "Run!" ; önce ilki, sonra ikincisi bırakılır | TV: ["TR: Shut the vent.", "TR: Run!"] |
| Bekleyen çevirmen; "Shut the vent.", "Run!", "Get down!" sırayla bırakılır | üç istek, üç gösterim, sırayla |
| Bekleyen; "Shut the vent.", "Run!", "Get down!", "Now!" ; açılır | istekler ["Shut the vent.", "Get down!", "Now!"] (sıra doldu, "Run!" atlandı) |
| Bekleyen; üç satır; saat +2000; sırayla bırakılır | üçü de gösterilir; süreler [min(8000,2000+uzunluk×60) ("TR: Shut the vent."), aynısı ("TR: Run!"), 15 000] |
| Bekleyen; "Run to" ×2, "Run to the cave!" ×2 ; yalnız tamamı bırakılır | istekler ["Run to", "Run to the cave!"]; TV: ["TR: Run to the cave!"] |
| "Run to" ×2, "Run to the cave!" ×2, "Duck down now!" ×2 | TV üç satır; "yerine koy" [hayır, evet, hayır] |
| Bekleyen; "Shut the vent.", "Run!" ; saat +2600 ; ikisi bırakılır | TV: ["TR: Run!"] |
| Bekleyen; "Shut the vent." ×1, "" ×17 (temizle 1) ; açılır | TV: ["TR: Shut the vent."], süre 2000 + 18 × 60 = 3080 |
| Aynısı, ama açmadan önce saat +2600 | TV boş |
| Bekleyen; "Shut the vent" ×2 ; sıfırla ; açılır | TV boş |
| Engelleyen okuyucu ("Shut the vent."): okuma başlar, sıfırla, okuma biter | çevirmene istek yok, TV boş |
| Engelleyen okuyucu, sıfırlamadan biter | çevirmene ["Shut the vent."] |
| Alan (üst 0,6 alt 1,0 sol 0,1 sağ 0,9), kutulu satır (0,25, 0,5, 0,75, 0,6) | TV kutusu (0,3, 0,8, 0,7, 0,84) |
| Günlük: "Shut the vent." ×2, "Run!" ×2; paket: "Run!" → "Koş!"; paket adı "mafia"; sonra sıfırla | TV ["TR: Shut the vent.", "Koş!"]; günlükte tam 6 kayıt, bu sırayla: [ilk kare], [ilk yazı; alıntı "Shut the vent." en sonda], [#1; alıntı "Shut the vent."; çeviriye], [#1; köken motor (genel ad); ms; gösterildi], [#2; alıntı "Run!"; paket kökeni, ad mafia], [hat sıfırlandı; paketten 1] |
| Önbellekli çevirmen ("Shut the vent." önbellekte), "Shut the vent.", "Run now." | günlükte #1 için köken "hepsi önbellekten", #2 için köken "motor yeni çevirdi" ve motorun adı |

**Parlak zemin örnekleri** (gerçek plan ve gerçek iz; 640 × 360 kare, her yeri 230; varsayılan bölgede üst %40'ın
parlaklığı ayarlanabilir; altyazı varken alanın (0,3, 0,6, 0,7, 0,8) kısmı 2 piksel 255 / 2 piksel 0 çizgili; okuyucu
karede 0 değerli bayt varsa ve "kaçır" kapalıysa ("Shut the vent.", o kutu) döner; saat +50):
- 3 kare altyazı → TV ["TR: Shut the vent."]. "Kaçır" açık, üst %40 parlaklığı 120, 40 kare → temizle 0. "Kaçır" kapalı,
  parlaklık 200, 3 kare → temizle 0, TV hâlâ tek satır, çevirmene tek istek.
- 3 kare altyazı, sonra altyazısız 16 kare (800 / 50) → temizle 0; 1 kare daha → temizle 1.

**Paket ve bekletme örnekleri** (paket araması: anahtarı "get down" olan satır → "Yere yat!"; saat 0'dan):

| Senaryo | Beklenen |
|---|---|
| "Get down!" ×3 | TV ["Yere yat!"]; çevirmen hiç çağrılmaz; "çift gösterildi" (Get down!, Yere yat!); "pakette yok" hiç; köken "paket"; isabet 1 |
| "Shut the vent" ×4 (2 kare +100, 2 kare +200) | ilk iki kareden sonra TV boş (2. karede bekletildi); sonra TV ["TR: Shut the vent"]; "pakette yok" ["Shut the vent"]; köken "motor" |
| Bozuk ölçü: "vv" ya da "é" içeren; "Gét dovvn!", "Get dovvn!", "Get down!", "Get down!" (+100) | TV ["Yere yat!"]; çevirmen hiç çağrılmaz |
| Bozuk ölçü: "tt" içeren; "Shutt the vent" ×12 (+100) | 7 kareden sonra TV boş; 3 kare daha → ["TR: Shutt the vent"] (100 ms'de bekletildi, 900'de gitti) |
| Paketsiz bekletme açık, puan = uzunluk, hiçbiri bozuk değil: "the vent" ×2, "Shut the vent!" ×4 | TV ["TR: Shut the vent!"]; çevirmene yalnız o |
| Aynı ayarlar: "Follow the truck." ×6, "Follow the" ×6 | çevirmene yalnız "Follow the truck." |
| "I swear, you never listen!" ×4, "You never listen!" ×4 | ikisi de çevrilir |
| Puan: "brrkmn" içeren 4, diğer 8; bozuk: "brrkmn" içeren: "Okay? Fine." ×4, "Okay? Brrkmn." ×4 | yalnız "Okay? Fine." (bekleme süreleri 0 iken de) |
| "But we can always build another raft." ×4, "can always build another raft." ×4 | yalnız ilki |
| Puan hep 10: ilk kare yanlış ("…at 7." / "I can fix…" / "…would sell…"), sonra doğru ×6 | iki istek: [yanlış, doğru] |
| Puan 10: "I can't fix that for you tonight." ×3, "I can fix that…" ×3 | yalnız ilki |
| Puan 10: noktasız yanlış ("I can fix that for you tonight" / "Find me at the station at 7") ×2 ya da ×4, doğru ×8 | 4 kareden sonra istek yok; 5. karede yalnız doğru (son tarih 100 + 300 = 400'de, ileri atılmaz); sonra başka istek yok |
| Paketsiz bekletme, "Shut the vent!" ×2, ilk kare (+10) | hemen TV ["TR: Shut the vent!"] (tam cümle beklemez) |
| Paket araması yok, "Get back!" ×2 | TV ["TR: Get back!"]; "pakette yok" ["Get back!"] |
| Bekleyen çevirmen, "Shut the vent" ×2, "Get down!" ×2 (beklemeden) | TV ["Yere yat!"]; çevirmen açılınca da değişmez |

**Paketteki parça örnekleri** (puan = uzunluk; bozuk yok; bekleme 0; saat +100):
- Bekleyen çevirmen; tam ×4, parça ×4; paket yalnız parçayı bilir ("Parça çevirisi") — çiftler: ("I'm the captain
  now.", "now."), ("That he totally blacked out.", "blacked"), ("Yo Cal, hop in, hop in!", "hop in!") → 8 kare
  boyunca TV boş; saat +3000, açılınca TV ["TR: <tam>"], istek yalnız tam, isabet 0.
- Gerçek çevirmen; bozuk ölçü yalnız tam metin; "I'm the captain now." ×4, "now." ×8; paket "now." → "Şimdi" →
  sıfırdan sayılan 9. kare (saat 900 = 100 + 800 ms) işlendikten sonra tam metin çevrilmiş olmalı (bekleme süresi
  parça yüzünden uzamaz); istekler yalnız tam; TV ["TR: <tam>"].
- Paket yalnız "sonraki"yi bilir ("Yeni replik"): ("I swear, you never listen!", "You never listen!", boşluk yok),
  ("I'm the captain now.", "now.", arada 12 boş kare), ("That he totally blacked out.", "Get down!", yok),
  ("I have five arrows.", "I have one arrow.", yok): tam ×4, (boşluk), sonraki ×4 → sondan üçüncü karede TV'de
  "Yeni replik" vardır, son gönderilen odur, "sonraki" çevirmene gitmez.

**Sıra düzeltme örnekleri** (paketsiz bekletme açık, bekleme 0; çevirmen açılana kadar bekler; ilk kare "Shut the vent."
süren çeviriyi tutar; saat +100):
- Tam = "Wow? Diving off cliffs, swimming with sharks? Man, that is insane.", Kısa = "Wow? Diving off cliffs,
  swimming with sharks?": "Shut the vent.", Tam, Kısa (ve isteğe bağlı Tam yeniden) → Tam mutlaka istenir, çevirisi TV'ye
  gider; Tam geri geldiyse istekler yalnız ["Shut the vent.", Tam].
- Ayrı kısa satırlar ikisini de korur: ("Go! Stay here.", "Go!"), ("I swear, you never listen!", "You never listen!"),
  ("Keep watch until I return.", "Get down!") → istekler ["Shut the vent.", ilk, ikinci].
- Düzeltme eskinin yerini alır: ("We have 5 hours left.", "We have 1 hour left."), ("Find me at 07:10.", "Find me at
  07:20."), ("I can fix that for you tonight.", "I can't fix that for you tonight."), ("We have room to spare.", "We
  have no room to spare."), ("We are out of...", "We are out of rope.") → istekler ["Shut the vent.", düzeltme].
- Tam, sonra Kısa ×18, sonra Tam → ["Shut the vent.", Tam].
- Tam, Kısa, boş ×12, Tam → ["Shut the vent.", Tam, Kısa] (gerçek boşluk birleşmeyi aşmaz).

**Bırakma örnekleri** (eski = "Shut the vent.", yeni = "Run!"; her kare saati elle ayarlanır, çeviriler beklenmez;
çevirmen iptali dinler ya da dinlemez):
- eski@0, yeni@100, yeni@2601 → ilk çağrının iptali istendi, sonucu tamamlanmadı; açılınca TV ["TR: Run!"]; son hata yok.
- eski@0, yeni@100, yeni@2100 ya da @2600 → iptal yok; TV ["TR: Shut the vent.", "TR: Run!"].
- eski@0, eski@10000 → iptal yok (ekranda duran satır ne kadar sürerse sürsün bırakılmaz).
- eski@0, yeni@100, eski@1000 → iptal yok; TV'de "TR: Shut the vent." var.
- eski@0, 100…2000 arası her 100'de boş, boş@10000 → iptal yok (bekleyen yeni satır yok).
- eski@0, yeni@100, 200…2000 boş, boş@10000 → iptal yok (sıradaki de süresini aşmış).
- İptali dinlemeyen: eski@0, yeni@100, yeni@3000 → iptal istendi ama tek çağrı var (aynı anda ikinci çeviri yok); açılınca
  çağrılar [eski, yeni], TV ["TR: Run!"].
- Paket yeni → "Koş!", yarım bekletme 0: eski@0, yeni@100 → ilk çağrının iptali istendi; TV ["Koş!"]; son hata yok.
- eski@0, yeni@100, yeni@2700, eski@2800 → çağrılar [eski, yeni, eski]; TV ["TR: Run!", "TR: Shut the vent."].
- Paket yeni → "Koş!": eski@0, yeni@100, eski@200 → çağrılar [eski, eski]; TV ["Koş!", "TR: Shut the vent."].
- Paket "Menfezi kapat!" → aynısı: eski@0, "Menfezi kapat!"@100 → TV boş, iptal yok; açılınca TV ["TR: Shut the vent."].
- Paket yeni → yeninin kendisi: yeni@0 → TV ["Run!"] (Türkçe harf yok, gösterilir).
- Paket ancak sonradan hazır ("Get down" → "Yere yat!"): eski@0, "Get down"@100, @150 (bekletildi), paket hazır, @200 →
  TV ["Yere yat!"], ilk çağrının iptali istendi; eski@250; açılınca çağrılar [eski, eski], TV ["Yere yat!", "TR: Shut the
  vent."].
- İptal geri çağrısı sırasında hattın kilidi serbest olmalı (o sırada "bütün çevirileri bekle" çağrılabilmeli).
- İptali dinlemeyen, bırakılan çağrı hata verirse: "çeviri sonucu" olayı hiç verilmez, son hata yok; sonra açılınca TV
  ["TR: Run!"] ve tek bir "başarılı" olayı.
- Eski satırın sonucu gösterilirken (çift gösterildi işleyicisi bekletiliyor) yeni@2700 gelirse eski bırakılmaz; sonuç
  TV ["TR: Shut the vent.", "TR: Run!"].

**Havuz örnekleri** (paket araması verilmiş; saat +150):
- "Shut the vent" ×8; 4 kareden sonra TV ["TR: Shut the vent"]; havuzdan "Menfezi kapat" → TV ["TR: Shut the vent",
  "Menfezi kapat"], son gönderim "yerine koy", köken "havuz", son çift ve son "çift gösterildi" (Shut the vent, Menfezi kapat).
  Aynısı yeniden gelirse gönderilmez.
- "Shut the vent" ×4, "" ×20; sonra havuz → TV değişmez, köken "motor".
- "Shut the vent" ×4, "Head for the hills" ×4; havuz "Shut the vent" için → TV değişmez.
- Paket satırı "Get down!" ×3 → havuz "Eğil!" → TV ["Yere yat!"], köken "paket".

---

## 12. Konuşan adı ve oyun deyimleri

### 12.1 Konuşan adı

Altyazının başındaki ad ("MARA: Grab the rope.") çeviriye gitmez; paket önce adlı satırla, sonra adsız cümleyle
aranır; ekranda ad, ayara göre yeniden başa konur ya da hiç yazılmaz.

**Ayırma:** metin kırpılır. Baştan: büyük harfle (Unicode büyük harf) başlayıp harf, `'`, `’`, `.`, `-` ile süren bir
sözcük; en çok 2 tane daha, her biri **tek boşlukla** ayrılıp aynı biçimde; isteğe bağlı tek boşluk; `:` ya da tam
genişlikli `：`; ardından boşluklar (satır sonu dahil). Uymazsa ad yok. Ad **24** karakterden uzunsa yok. Ad tek
sözcükse ve (küçük harfle) şu listedeyse yok: note warning tip hint objective objectives quest goal new reward rewards
location chapter mission task tutorial update info status level controls press hold tap remember example question answer
result results time listen look wait okay ok well so yes no now then and but. Kalan cümle (kırpılmış) harf içermiyorsa ya
da `/` ile başlıyorsa yok.

| Metin | Ad / cümle |
|---|---|
| MARA: Grab the rope. | MARA / Grab the rope. |
| Eli: I know the way. | Eli / I know the way. |
| Mr. Hale：Stay back. | Mr. Hale / Stay back. |
| OLD WOMAN : Hm. | OLD WOMAN |
| MARA:We run. | cümle "We run." |
| Mara:\nGrab the rope. | cümle "Grab the rope." |
| 11:45 at the pier. / See you at 11:45. / HTTPS://example.com / Ratio 16:9 / Note: the bridge is closed. / I said it: back off! / Four Words Long Name: here / Maximilianus Wolfensteiner: Hi. / MARA: | ad yok |

**Sunma (çeviri, kaynak, adı göster):** kaynağın adı varsa ve çevirinin (ayrıştırılan) adı ondan farklıysa çevirinin
başına "Ad: " eklenir. Göster açıksa bu döner. Kapalıysa: kaynağın her satırının ve bütününün adları toplanır; sonucun
her satırı, bu adlardan biriyle başlıyorsa yalnız cümlesi kalır; satırlar `\n` ile birleşir.

| Çeviri | Kaynak | Göster | Sonuç |
|---|---|---|---|
| İpi tut. | MARA: Grab the rope. | açık | MARA: İpi tut. |
| İpi tut. | MARA: Grab the rope. | kapalı | İpi tut. |
| MARA: İpi tut. | MARA: Grab the rope. | açık | MARA: İpi tut. |
| MARA: Evet.\nELI: Hayır. | MARA: Yes.\nELI: No. | kapalı | Evet.\nHayır. |
| Hedef: Köprüyü geç. | Objective: Cross the bridge. | kapalı | Hedef: Köprüyü geç. |

### 12.2 Oyun deyimleri (çevirmenden önce)

Yerel modelin harfiyen çevirip anlamını bozduğu bazı asker/oyun deyimleri, çevirmene gitmeden önce sade
İngilizce karşılıklarıyla değiştirilir (bu iş çeviri
motorlarının girişindedir; çeviri belgesi). Sözcük sınırlarıyla, büyük/küçük harf duyarsız, kültürden bağımsız; eşleşen
metnin ilk harfi büyükse karşılığının ilk harfi de büyük yapılır. Deyim tablosu kodda durur
(`apps/windows/src/Nino.Core/Translation/TextPreparation.cs`): 9 satır, sırası önemlidir (uzun kalıp kısa kalıptan önce).
İçeriği: "dost birlik" anlamındaki asker sözcüğü, "arkanı kolluyorum" ve "arkana bak" anlamındaki "six" deyimleri,
"dikkat" anlamındaki ünlem, "geç kaldın" sitemi, "düşman geliyor" anlamındaki "company" deyimi, "hazırlan" komutu,
"kolay hedef" benzetmesi ve "içeri giriyoruz" anlamındaki hareket deyimi; her birinin karşılığı sade İngilizcedir.

Örnekler: tablodaki bir deyimi cümle başında içeren satırda karşılığı da büyük harfle başlar; deyim cümlenin içindeyse
küçük harfle girer; deyimin harfleri başka bir sözcüğün parçasıysa (sözcük sınırı yok) değişmez. Değişmeyen örnekler:
`The friendliest bar on the coast.` / `Six boats, all behind the pier.` / `Stand down!`

---

## 13. Ölçümler (ana ekrandaki küçük satır)

TV'ye giden her yeni satır için: yazı tanıma süresi, çeviri süresi, karenin gelişinden TV'ye gönderilişine kadar geçen
süre, güven, köken (paket ya da motor). Hepsi gerçek ölçümdür, aynı milisaniye saatiyle.

- OCR süresi: okumanın süresi (eksiyse 0; bilinmiyorsa yok). Kare yeniden okunmadıysa son gerçek okumanın süresi.
- Çeviri süresi: bitiş − başlangıç (eksiyse 0); paketten gelen satırda yok.
- Toplam: gönderim anı − karenin geliş anı (eksiyse 0). Bekleme de gecikmeye girer (bekletilen satır ilk okunduğu kareden
  sayılır).
- Güven: 0–1'e sıkıştırılıp × 100, sıfırdan uzağa yuvarlanmış tam sayı yüzde; okuyucu vermiyorsa yok (Windows'ta hep
  yok).
- Ekrandaki parçalar, sırayla (bilinmeyen değer yazılmaz): OCR süresi; paketse "hazır paketten geldi" anlamında bir
  parça, değilse çeviri süresi; toplam gecikme; güven yüzdesi. Süreler ms birimiyle. Parçalar tek satırda ` · ` ile
  ayrılır; sözcükler arayüz dilindedir (kendi metin anahtarlarınla yaz).

| Ölçüm girdisi (geliş, OCR, çeviri, gönderim, güven, köken) | Sonuç |
|---|---|
| 1000, 40, (1100–1400), 1520, yok, motor | OCR 40, çeviri 300, toplam 520 → üç parça: OCR 40, çeviri 300, gecikme 520 |
| 2000, −5, (1500–1400), 1000 | hepsi 0 |
| güven 0,934 / 0,936 / 1,2 / −0,1 | 93 / 94 / 100 / 0 |
| 1000, 35, yok, 1060, paket | üç parça: OCR 35, "hazır paket", gecikme 60 |
| güven 93 eklenmiş | dördüncü parça: güven %93 |
| yalnız toplam 250 | tek parça: gecikme 250 |

Hat örnekleri (saat her kare geldiğinde önce +50; kare o anla verilir):
- Okuma 40 ms, kuyruk 180 ms, çeviri 300 ms, "Shut the vent" ×3 → tek ölçüm: motor, OCR 40, çeviri 300, toplam 520,
  güven yok; son ölçüm aynı; olay sırası önce ölçüm sonra çift.
- Okuma 25 ms, paket "Get down!" → "Yere yat!", ×3 → (25, yok, 25, yok, paket), özet üç parça:
  OCR 25, hazır paket, gecikme 25.
- Kutusuz ama güveni 0,91 olan satır → güven 91.
- Geliş anı verilmezse (okuma 40, çeviri 300) → toplam 340.
