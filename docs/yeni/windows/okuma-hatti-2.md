# Windows okuma hattı: tarif (2. bölüm)

1. bölüm (`okuma-hatti.md`) ortak kuralları (§0), görüntüyü (§1), OCR çıktısının soyut biçimini (§2), Windows yazı
tanımasını (§3) ve altyazı hattını anlatır. Bu bölüm onların üstüne kurulur; "1. bölüm §n" diye atıf yapar.

---

## 1. Ek alanlar (sürekli okunan köşe yazıları)

Kullanıcı en çok 3 ek bölge tanımlayabilir (görev paneli, bilgi kutusu, telefon mesajı…). Her biri tuşla bir kez
okunabilir (§2) ya da **"sürekli oku"** seçiliyse tuşa basmadan saniyede bir okunur. Çevirisi TV'de kendi yerinde,
asıl yazının üstünde küçük bir kutuda durur.

### 1.1 Ayarlar (uyumluluk için alan adları birebir)

Ayar dosyası `settings.json` (veri klasöründe), varsayılan JSON ayarlarıyla yazılır: alan adları **aynen** (baş harfi
büyük), bir bölge nesnesinin alanları `Top`, `Bottom`, `Left`, `Right`; metin dönüştürücüsü işaretlenmemiş seçimler
**sayı** olarak saklanır.


- `ExtraRegion1`, `ExtraRegion2`, `ExtraRegion3`: bölge (üst, alt, sol, sağ); yoksa kapalı. Varsayılan hepsi kapalı.
- `ExtraTarget1..3`: tek seferlik çevirinin gösterileceği yer: TV, bilgisayar ya da ikisi. JSON'da **sayı**: 0 = TV (varsayılan), 1 = bilgisayar, 2 = ikisi.
- `ExtraLive1..3`: sürekli okunsun mu (varsayılan kapalı).
- `FreeAreaTarget`: serbest alan (§2.2) sonucunun yeri (aynı sayılar; varsayılan 0 = TV).
- **İzlenen alanlar:** 1'den 3'e, sürekli oku açık **ve** bölgesi olan her yuva için bir alan: kimlik `area1`, `area2`,
  `area3`; günlükteki adı "Area 1"… ; bölgesi. (Ayar dosyasının ayrıntısı ayarlar belgesinde.)
- **Hazır ek bölgeler** (üst, alt, sol, sağ):

| Hazır | Üst | Alt | Sol | Sağ |
|---|---|---|---|---|
| `reading.extraPreset.quest` | 0,03 | 0,30 | 0,66 | 0,98 |
| `reading.extraPreset.notification` | 0,58 | 0,88 | 0,02 | 0,30 |
| Telefon mesajı / e-posta (sağ alt) | 0,50 | 0,95 | 0,72 | 0,98 |

### 1.2 İzleyicinin kuralları

- Altyazı hattından **bağımsızdır:** kare verildiği anda çağırana döner; okuma ve çeviri arka planda yürür.
- Kendi okuyucusu vardır (1. bölüm §2.2); okumalar **derin değildir**.
- En çok **1000 ms**'de bir tur; önceki tur bitmediyse kare atlanır.
- İzi önceki turdakiyle aynı olan alan için yazı tanıma çalıştırılmaz.
- Çeviri için yazının **oturmuş** olması gerekir: ya bir tur boyunca iz aynı kalmıştır ya da iki ardışık okuma aynı
  anahtarı vermiştir.
- Anahtar aynı kaldıkça çeviri tekrarlanmaz; alan yazısız kalınca TV'deki kutusu silinir.
- Paket araması ve çeviri motoru altyazıyla aynıdır (paketler açıksa paket araması verilir), ama ek alan satırları ortak
  havuza **önerilmez**.
- İzleyici, hat varken, altyazı duraklatılmamışken ve en az bir izlenen alan varken bulunur; yoksa sıfırlanıp kaldırılır
  (kutuları TV'den kalkar).

### 1.3 Kare sunulunca

1. Alan yoksa ve hiçbir alanda gösterilen yazı yoksa hiçbir şey yapılmaz.
2. Son turdan beri 1000 ms geçmediyse dönülür.
3. Tur sürüyorsa dönülür. Değilse "meşgul" işaretlenir, son tur anı = şimdi, tur arka planda başlar; hata olursa
   günlüğe ek alan turunun hatası (iletisiyle) yazılır; bitince meşgul kalkar.

### 1.4 Tur

1. Turun başladığı oturum numarası alınır; tur sayısı artar.
2. Artık listede olmayan alanlardan gösterilen yazısı olanların kutusu kaldırılır (TV'ye o kimlikle boş metin, kutu yok);
   listede olmayan bütün alanların durumu silinir.
3. Her alan sırayla ziyaret edilir; ziyaret sonrası oturum değiştiyse tur biter.

**Alan ziyareti:**
1. Alan kesilir (1. bölüm §1), izi çıkarılır; alanın durumu yoksa kurulur.
2. Değişti mi = önceki iz yok ya da (eşik 16 ile) değişti. Yeni iz saklanır.
3. Değişmediyse: bekleyen aday varsa aday silinip **kesinleştirilir** (§1.5). Dön.
4. Okunur (derin değil). **Hata verirse** (bu, "alan boş" anlamına gelmez): iz, son okuma ve aday silinir; TV'deki kutuya dokunulmaz;
   iz silindiği için bir sonraki turda alan değişmiş sayılıp yeniden okunur ve eski aday bu hatalı turla kesinleşmez. Dön.
5. Oturum değiştiyse dön. Okuma sayısı artar; okuma süresi ölçüm dinleyicisine verilir.
6. Aday kurulur (§1.5). Adayın anahtarı son okumanın anahtarıyla aynıysa aday silinir ve bu aday kesinleştirilir; değilse
   son okuma = anahtar, aday = bu.

### 1.5 Aday ve kesinleştirme

**Aday kurma:** okumadan düğme ipuçları atılır, OCR çöpü temizlenir, **yazı olmayan** satırlar atılır (yazı: en az 2 harf
ve en az 2 harfli bir boşluk sözcüğü; "23m", "9", "+" değil), satırlar kutu üstüne göre dizilir (yeri yoksa 0). Parçalar
"ekranı çevir"in paragraf kuralıyla kurulur (§3.3). Kutu = satır kutularının birleşimi, alanın bölgesinden kareye
yerleştirilmiş (hiç kutu yoksa yok). Satır yüksekliği = satır kutu yüksekliği × bölge yüksekliği değerlerinin sıralı
listesinde **üst ortanca** (n/2. eleman); yoksa yok. Anahtar = parçaların boşlukla birleşmişinin sadeleştirilmişi.

**Kesinleştirme (aday, alan):**
1. Gösterilen anahtar adayınkiyle aynıysa: çizilen anahtar farklıysa ya da çizilen metin boşsa dön; kutu ve satır
   yüksekliği çizilenle aynıysa dön; değilse aynı çeviri yeni kutu/yükseklikle yeniden gönderilir (yeniden çevrilmez),
   çizilen kutu/yükseklik güncellenir. Dön.
2. Önceki gösterilen anahtar saklanır; gösterilen = adayın anahtarı.
3. Anahtar boşsa: TV'ye boş (kutu kalkar); çizilenler boşaltılır; günlüğe "ek alan <ad>: boşaldı". Dön.
4. Her parça için paket araması; bulunanlar sayılır. Bulunmayanlar **tek çağrıda, sırayla** çevirmene verilir (çevirmen
   destekliyorsa tek istek; değilse tek tek).
5. Çeviri hata verirse: oturum aynıysa ve gösterilen hâlâ bu adaysa gösterilen eski değerine döner ve aday yeniden bekler
   (sonraki turda iz değişmese de yeniden denenir); günlüğe "ek alan <ad>: (alıntı) çevrilemedi (hata)". Dön.
6. Oturum değiştiyse ya da gösterilen artık bu değilse dön.
7. Her parçanın metni = çevirisi (kırpılmış, boş değilse), yoksa kaynağı.
8. Bütün parçaların sadeleştirilmiş kaynak ve metni **0,90** ile benzerse (ad, sayı, zaten hedef dilde): TV'ye boş, çizilenler
   boşaltılır. Dön.
9. Köken: hepsi paketten → "paket", bazıları → "paket+motor", hiçbiri → "motor". Günlüğe "ek alan <ad>: (alıntı) →
   <köken>". TV'ye: kimlik, parçaların `\n` ile birleşmişi, kutu, satır yüksekliği. Çizilenler güncellenir.

**Sıfırlama** (çeviri durdu, hat yeniden kuruldu): oturum artar (süren tur bırakılır); gösterilen bir şey varsa TV'deki
bütün ek alan kutuları kaldırılır; durumlar ve son tur anı silinir. Bir şey gösterilmiyorsa TV'ye kaldırma gitmez (iki kez
sıfırlamak tek kaldırma verir).

### 1.6 Örnekler

Düz gri kareler (320 × 180; gri ton değişince iz değişir); alan "Görev" (kimlik `q`) ve "Telefon" (`p`) hazır bölgeleri;
okuyucu kutulu satırlar döndürür (sol 0,1, sağ 0,9, verilen üst ve yükseklik; varsayılan üst 0,2, yükseklik 0,1);
çevirmen "TR: " ekler. Turlar doğrudan çağrılır.

| Senaryo | Beklenen |
|---|---|
| "Check the old lighthouse", ton 10 — tur 1 | TV boş |
| tur 2 (aynı ton) | TV ["TR: Check the old lighthouse"]; kutunun solu/sağı Görev bölgesinin içinde |
| tur 3, 4 (aynı) | okuma 1 kez; çeviri 1 kez; TV 1 satır |
| Aynı metin, tur 3'te ton 60 ve satır (üst 0,45, yükseklik 0,2) | TV aynı çeviriyi ikinci kez, farklı kutu üstü ve satır yüksekliğiyle; çeviri yine 1 kez |
| "Speak with Mara" (10, 10) → "Wait for Mara at the mill" (90, 90) → okuma boş (200, 200) | TV ["TR: Speak with Mara", "TR: Wait for Mara at the mill", ""] |
| "Speak with Mara" 5 tur, tonlar 10, 60, 110, 160, 210 | 5 okuma; çeviri 1; TV 1 satır |
| "R2 Swing" ve (üst 0,5) "23m", iki tur | TV boş |
| Paket "New message" → "Yeni mesaj"; satırlar "New message" (üst 0,1), "Text me once you land." (üst 0,25) | TV ["Yeni mesaj\nTR: Text me once you land."]; çevirmene yalnız ikinci |
| "Are you nearby?" Görev+Telefon iki tur; sonra yalnız Görev | TV kimlikleri {p, q}; sonra son gönderim (p, ""); sıfırla → kaldırma 1; yine sıfırla → hâlâ 1 |
| "Speak with Mara" (10,10) gösterildi; "Wait for Mara at the mill", çevirmen 1 kez hata; (90, 90) | TV hâlâ ["TR: Speak with Mara"]; üçüncü (90) turda çeviri yeniden denenir: çeviriler [Speak…, Wait…, Wait…], TV [Speak…, Wait…] |
| Okuyucu 1 kez hata, "Check the old lighthouse"; ton 10 ile 2 tur | TV boş; 4 tur daha → toplam 2 okuma, 1 çeviri, TV 1 satır |
| "Speak with Mara" gösterildi; "Wait for Mara at the mill" (60) aday; okuma hatası (100); "Check the old lighthouse" (100) | TV hâlâ ["TR: Speak with Mara"]; bir tur daha (100) → çeviriler [Speak…, Check…], TV [Speak…, Check…] ("Wait…" hiç çevrilmez) |
| Okuyucu 1 kez hata, Görev+Telefon, ton 10: tur 1, tur 2 | tur 2 sonrası TV kimlikleri [p]; tur 3 → [p, q]; okuma 3 |
| Sahte saat; her 100 ms sunum (0…900), sonra 1000 | tur 1; 1000'de tur 2; TV ["TR: Check the old lighthouse"] |
| Okuyucu 10 kez hata; 0…2000 her 100 ms sunum | tur 3 (0, 1000, 2000); okuma 3; TV boş |
| Hiç alan yok, sunum | meşgul değil; okuma 0 |

Uygulama düzeyi: sürekli okunan alan tuşa basmadan okunur ve TV'ye `area1` kimliğiyle boş olmayan bir metin gider;
uygulama ayrı bir okuyucu kurar (altyazınınki ve izleyicininki: iki okuyucu); izleme durunca TV'ye "ek alanları kaldır"
olayı gider.

---

## 2. Tek seferlik bölge çevirisi

Ekranda uzun süre duran yazılar (görev listesi, bilgi kutusu) için: bölge izlenmez; yalnız kullanıcı tuşa bastığında bir
kez okunur ve çevrilir.

### 2.1 Okuma ve bloklar

1. Bölge kesilir; okuyucu **derin** okur (tek okuma olduğu için büyütülmüş yedekler de denensin); yalnız **düğme
   ipuçları** atılır (çöp temizliği, dev yazı vb. yok).
2. Satır yoksa sonuç yok ("yazı bulunamadı").
3. Kutu = okumanın kutusu bölgeden kareye yerleştirilmiş; yoksa bölgenin kendisi.
4. **Bloklar** (başlık, açıklama, maddeler ayrı çevrilsin). Tipik yükseklik = satır kutu yükseklikleri × alan yüksekliği
   (piksel) sıralı listesinin üst ortancası (yoksa 0). Satırlar **okuma sırasıyla** (yeniden dizilmeden) gezilir:
   - Satır kırpılır, **madde işareti** ayrılır: ilk karakter madde simgelerinden biriyse ve satır ≥ 2 karakterse
     (`◇ ◆ ◈ ◊ ♦ ♢ • ● ○ ◦ ▪ ■ □ ▫ ► ▶ ‣ ∙ · * - – — ✓ ✔ ✦ ❖ ◉ ⬥`) işaret atılır, kalan baştan kırpılır; `<>` ile
     başlıyorsa (◇ böyle okunur) o atılır; 2'den uzunsa, 2. karakter boşluksa, 1. karakter `o` ya da `0` ve 3. karakter
     büyük harfse ilk iki karakter atılır. Boş kalan satır atlanır.
   - Önceki satır ve süren blok varsa: satır maddeyse ya da **yeni blok başlıyorsa** süren blok (kendi madde bayrağıyla)
     kapanır, yenisi bu satırın madde bayrağıyla başlar; değilse araya boşluk konup eklenir. İlk satırda blok bayrağı
     satırınkidir.
   - **Yeni blok mu (üst, alt):** üst satır cümle bitirmiyorsa ve alt satırın (işaretsiz) ilk karakteri küçükse hayır
     (cümle iki satıra bölünmüş); üst cümle bitiriyorsa evet; kutulardan biri yoksa ya da tipik ≤ 0 ise hayır; aradaki
     boşluk (alt üst − üst alt, × alan yüksekliği) > tipik × 0,4 ise evet; üst satırın solu alttan (× alan genişliği)
     tipik × 0,5'ten fazla sağdaysa (alt satır soldan dışarı çıkıyor: girintili devamdan sonra yeni madde) evet; değilse
     hayır.
5. Her blok sırayla çevrilir; madde bloğunun çevirisinin başına "• " eklenir.
6. Sonuç: kaynak = blok metinleri `\n` ile; çeviri = çeviriler `\n` ile; kutu; **yapılı** = 1'den çok blok (TV satır satır,
   sola yaslı gösterir).
7. Gösterim süresi: `sıkıştır(4000 + çeviri_uzunluğu × 70, 6000, 25000)` ms.
8. Çevirmen kullanılamıyorsa çevirmen hatası yukarı iletilir.

| Satırlar (kutusuz) | Bloklar |
|---|---|
| "Check the old lighthouse on", "the northern cliffs" | ["Check the old lighthouse on the northern cliffs"] |
| "Check the old lighthouse.", "Give her two silver keys." | iki blok |
| kutulu: "Active job" (0–0,10), "Check the old lighthouse" (0,30–0,40), "on the cliffs" (0,42–0,52) | ["Active job", "Check the old lighthouse on the cliffs"] |

| Senaryo | Sonuç |
|---|---|
| Okuma boş | sonuç yok |
| "R2 Swing", "Check the old lighthouse." | kaynak "Check the old lighthouse.", çeviri "TR: Check the old lighthouse." |
| "Check the old lighthouse.", "Give her two silver keys." | çeviri "TR: Check the old lighthouse.\nTR: Give her two silver keys." |
| Bölge (üst 0,1, alt 0,5, sol 0,5, sağ 0,9), satır kutusu (0, 0, 1, 0,5) | kutu (0,5, 0,1, 0,9, 0,3) |
| Aynı bölge, kutusuz satır | kutu (0,5, 0,1, 0,9, 0,5) |
| Çevirmen "model indirilmedi" | çevirmen hatası |
| Gösterim: uzunluk 5 / 100 / 5000 | 6000 / 11000 / 25000 |

### 2.2 Uygulamada (tuşlar ve sonuçlar)

- **Ek bölge 1/2/3 (sayısal tuş takımı 1, 2, 3):** yuvanın bölgesi yoksa "ayarlanmadı"; son kare yoksa "çalışmıyor";
  hedef ayarına göre TV'ye (hedef bilgisayar değilse) ve/veya bilgisayar penceresine (hedef TV değilse) gider.
- **`shortcut.action.freeArea` tuşu (sayısal tuş takımı 5):** kullanıcının o an seçtiği alan bir kez okunur; sonuç `FreeAreaTarget` bilgisayar
  değilse TV'ye de gider; serbest alan penceresi sonucu her durumda kendisi gösterir.
- Ortak akış: çeviri çalışmıyorsa ya da okuyucu yoksa "çalışmıyor". Bir önceki istek bitmediyse "meşgul" (tuşa üst üste
  basılınca ikinci okuma başlamaz). Altyazı hattının okuyucusu kullanılır. Çevirmen hatası → çevirmen durumu güncellenir,
  "çevirmen kullanılamıyor"; başka hata → "başarısız".
- Yazı yoksa "bu alanda yazı bulunamadı" anlamında bir ileti: TV'ye (stil gönderilip)
  **2500 ms**, bölgenin kutusunda; bilgisayara 2500 ms. Sonuç "yazı yok".
- Yazı varsa: TV'ye stil, sonra çeviri gösterim süresiyle, sonucun kutusunda, yapılıysa "satır satır" bayrağıyla.
  Arayüzde son kaynak/çeviri güncellenir; bilgisayar hedefliyse pencereye çeviri ve süre verilir. Sonuç "gösterildi".
- Varsayılanlar: bütün ek bölgeler kapalı ve sürekli değil; hedefler TV; 3. yuvanın bölgesi ve hedefi ötekilerden ayrı
  saklanır.

---

## 3. Tüm ekranı çevirme (`shortcut.action.translateScreen`)

Tuşa basılınca o anki karenin bütün yazıları bir kez okunur, konumlarına göre kümelere ayrılır (menü, panel, kutu,
altyazı…) ve her küme ayrı çevrilir. TV her Türkçeyi ait olduğu İngilizce yazının yerine, aynı yazı boyuyla yerleştirir.
Arka planda sürekli çalışan bir şey değildir.

### 3.1 Okuma

Kare **900 pikselden kısaysa 2 kat büyütülür** (720p'de köşe yazıları birkaç piksel boyundadır), arka planda **derin
olmayan** okumayla okunur. Kutular orandır; büyütme sonucu değiştirmez.

### 3.2 Gruplar

1. Düğme ipuçları atılır, çöp temizlenir; **kutusu olan ve yazı olan** (§1.5) satırlar kalır; kutu üstüne göre dizilir
   (eşitlikte geliş sırası).
2. Her satır için, **son** gruptan geriye, son satırına "ait olduğu" ilk grup aranır.
   **Ait olmak (alt, üst):** yükseklikler a (üst) ve b (alt); büyüğü küçüğün 1,6 katından büyükse hayır (yazı boyu farklı);
   `alt.üst − üst.alt ≥ max(a, b) × 0,8` ya da alt satırın üstü üstünkinden yukarıdaysa hayır; yatay örtüşme > 0 ve dar
   olanın genişliğinin en az yarısı olmalı.
3. Bulunan grubun son satırı ile yeni satır arasında **sütun köprüsü** varsa (iki yönde de bakılır) grup bulunmamış
   sayılır. **Köprü (geniş, sütun):** süzülmüş satırlardan biri ("eş") için: eş sütunla yatayda örtüşmüyor
   (`min(sağlar) ≤ max(sollar)`); eş ile sütun dikeyde örtüşüyor (örtüşme > 0 ve küçük yüksekliğin en az yarısı); ve
   ((sütun genişe ait ve eş genişe ait) ya da (geniş sütuna ait ve geniş eşe ait)). (Geniş başlık ya da alt satır yan yana
   iki bağımsız sütunu birbirine bağlamasın.)
4. Grup bulunduysa satır eklenir, yoksa yeni grup.
5. İlk **30** grup alınır. Her grup: parçalar (§3.3), kutu = satır kutularının birleşimi, satır yüksekliği = satır
   yüksekliklerinin üst ortancası.

### 3.3 Parçalar (paragraflar)

Satırlar kırpılır; her satır son parçaya **eklenir** (araya boşluk) ancak "yeni parça başlıyorsa" yeni parça olur. **Yeni
parça:** son parça cümle bitiriyorsa; ya da satır büyük harfle başlıyorsa ve son parça en çok 3 (boşluk) sözcüklüyse ve
virgülle bitmiyorsa (kısa başlık/menü satırı).

### 3.4 Çeviri

- Çevirmen metinleri **birlikte** çevirebiliyorsa (yapay zekâ): bütün grupların parçaları tek listede tek istekle gider;
  sonuç gruplara sırayla dağıtılır (eksik sonuç yerine kaynak); iptal istendiyse durulur; en az bir öğe varsa ilerleme bir
  kez bildirilir.
- Değilse gruplar sırayla; her gruptan önce iptal denetlenir; parçalar tek tek çevrilir; her öğe eklendikçe o ana kadarki
  bütün öğelerle ilerleme bildirilir (TV çeviriler hazırlandıkça dolar).
- **Öğe kurma:** her parçanın metni = çeviri kırpılmış (boşsa kaynak); parçalardan **en az biri** kaynağından 0,90
  benzerlikle farklıysa öğe kurulur: kaynak = parçalar `\n` ile, çeviri = metinler `\n` ile, grup kutusu, satır yüksekliği.
  Değilse (ad, sayı, zaten Türkçe) grup gösterilmez.
- Çeviri `\n` içeriyorsa öğe "satır satır" gösterilir (TV sola yaslı). Öğenin isteğe bağlı görünüm alanları (kutusuz sade
  yazı, eğik, oyunun kutu rengi ve yazı rengi, açı, zemin saydamlığı, yan balon, yazısız zemin, harita kartı) telefon ve
  harita çevirilerinindir (telefon/harita belgesi); "ekranı çevir" bunları kullanmaz.
- Çevirmen kullanılamıyorsa çevirmen hatası yukarı iletilir.
- **TV'de kalma süresi:** `sıkıştır(8000 + bütün çevirilerin uzunluk toplamı × 50, 12000, 60000)` ms.

### 3.5 Örnekler

Satır kutusu (sol, üst, sağ, üst + 0,03) — yükseklik aksi söylenmedikçe 0,03.

| Satırlar | Beklenen |
|---|---|
| "Check the old lighthouse on" (0,05–0,30, üst 0,10), "the northern cliffs" (0,05–0,25, 0,135), "Pull the chain to raise the bridge." (0,40–0,60, 0,85), "New outfit available" (0,75–0,95, 0,60) | 3 grup: ["Check the old lighthouse on the northern cliffs"] (sol 0,05, alt 0,165, satır yüksekliği 0,03), ["New outfit available"], ["Pull the chain to raise the bridge."] |
| "Settings" (0,05–0,15, 0,05), "Return to title" (0,80–0,95, 0,05) | 2 grup |
| "Map" (0,30), "Inventory" (0,34), "Settings" (0,38), hepsi solda | 1 grup, parçalar ["Map", "Inventory", "Settings"] |
| "Chapter One" (0,30–0,70, üst 0,20, yükseklik 0,08), "The story starts at the harbor." (0,29, yükseklik 0,03) | 2 grup; ilkinin satır yüksekliği 0,08 |
| Başlık "Open contracts" (0,05–0,95, 0,10); sol sütun "Check the old lighthouse on" (0,05–0,43, 0,14), "the northern cliffs." (0,05–0,40, 0,18); sağ sütun "Deliver the letters to" (0,57–0,95, 0,14), "the eastern farm." (0,57–0,92, 0,18) — düz ya da ters sırada | 3 grup; başlık tek parça, alt kenarı 0,13; sol grup ["Check the old lighthouse on the northern cliffs."] (sağı < 0,5); sağ grup ["Deliver the letters to the eastern farm."] (solu > 0,5) |
| Aynı iki sütun ve altta tam genişlikli "Pick a starting point" (0,05–0,95, 0,22) — düz ya da ters | 3 grup; alt satır tek parça, üstü 0,22 |
| "Check the old lighthouse on" (0,05–0,95, 0,10) ve devam "the northern cliffs." (sol/sağ: 0,05–0,4 ya da 0,30–0,70 ya da 0,60–0,95; 0,14) | tek grup, ["Check the old lighthouse on the northern cliffs."] |
| "Next step" (0,05–0,43, 0,10) + iki sütun | 2 grup; biri ["Next step", "Check the old lighthouse on the northern cliffs."] |
| "Check the old lighthouse on" (0,05–0,95, 0,10), "the northern cliffs." (0,05–0,43, 0,14), "R2 Swing" (0,57–0,95, 0,14) | tek grup (atılan ipucu sütun sınırı yaratmaz) |
| "23m", "9", "R2 Swing", "HP 120/300" | tek grup ["HP 120/300"] |
| Kutusuz "Check the old lighthouse." | grup yok |

| Çeviri senaryosu | Beklenen |
|---|---|
| Başlık + iki sütun, sırayla "Çıktı 1/2/3" döndüren çevirmen | 3 öğe; kaynaklar ["Open contracts", "Check the old lighthouse on the northern cliffs.", "Deliver the letters to the eastern farm."]; çevirmene giden aynı sırada; çeviriler "Çıktı 1/2/3" |
| "Check the old lighthouse." (0,05–0,30, 0,10), "Give her two silver keys." (0,135), "Exit the cave" (0,60–0,90, 0,80); "TR: " çevirmen | 2 öğe; ilkinin çevirisi "TR: Check the old lighthouse.\nTR: Give her two silver keys." (satır satır), ikincisi değil; ilerleme [1, 2] |
| "MARA" ve "Close the hatch." ; çevirmen yalnız ikinciyi "Kapağı kapat." yapıyor | tek öğe "Kapağı kapat." |
| Çevirmen "model indirilmedi" | çevirmen hatası |
| Süre: çeviri uzunluğu 0 / 200 / 5000 | 12000 / 18000 / 60000 |

### 3.6 Uygulamada (sayısal tuş takımı 9)

1. Çeviri çalışmıyorsa ya da okuyucu yoksa → "çalışmıyor".
2. Son kare yoksa (PS5'ten henüz görüntü gelmedi): TV'ye "ekran alınamadı, PS5'ten henüz görüntü gelmedi" anlamında ileti
   **4000 ms** → "çalışmıyor" (tuş sessizce yok sayılmaz).
3. Ekran çevirisi sürüyorsa: iptal edilir, TV'deki ekran çevirileri ve altyazı kaldırılır → "kaldırıldı".
4. Ekran çevirileri hâlâ TV'deyse (kalma süresi dolmadıysa) kaldırılır → "kaldırıldı".
5. Değilse: TV'ye stil ve "ekran çevriliyor" anlamında ileti **2500 ms**. Çevirmen kurulur; her ilerlemede (iptal edilmediyse) TV'ye
   ekran çevirileri o anki öğelerle ve kalma süresiyle gönderilir, "ekran şu ana kadar TV'de" anı güncellenir.
6. Bitince TV'deki altyazı temizlenir (o ileti kalkar). Öğe yoksa "ekranda yazı bulunamadı" anlamında ileti **2500 ms** →
   "yazı yok"; varsa → "gösterildi".
7. İptal → "kaldırıldı". Çevirmen hatası → çevirmen durumu güncellenir; hata iletisi → "çevirmen kullanılamıyor". Başka
   hata → bağlantı günlüğüne yazılır; hata iletisi → "başarısız".
8. **Hata iletisi:** önce altyazı temizlenir; "ekran çevrilemedi" + neden, **6000 ms**. Neden: çevrimiçi çevirmenin son
   hatasının açıklaması (çevrimiçi motor ve yerel yapay zekâ sunucusuna göre; çeviri belgesi), ya da son satır dakikalık
   sınıra takıldıysa "motorun (adıyla) dakika sınırı doldu, biraz sonra yeniden denenmeli"; değilse çevirmen durumuna göre
   "ücretsiz çeviri indirilmemiş" / "ücretsiz çeviri açılamadı" / "beklenmeyen bir sorun, yeniden denenmeli" anlamları.
9. **Kaldırma:** "ekran TV'de" anı sıfırlanır, TV'ye "ekran çevirilerini kaldır" ve "temizle".
10. Çeviri durdurulunca süren ekran çevirisi iptal edilir; ekran çevirileri TV'deyse kaldırılır.

Uygulama testleri: çalışmazken → "çalışmıyor"; boş ekran → "yazı yok"; basış → "gösterildi", ikinci basış → "kaldırıldı",
üçüncü → yine "gösterildi"; bilgisayar penceresi tam bir "ekran" olayı alır (metni boş değil ve kaynakla aynı değil), ikinci
basışta "ekranı kaldır" olayı; görüntü yokken içinde "PS5" geçen bir altyazı olayı.

---

## 4. Hazır altyazı alanı seçimleri

- Ayar alanları: `Region` (üst, alt, sol, sağ) ve `AreaPreset`. Hazır seçim JSON'da **metin** olarak saklanır: `Bottom`,
  `Top`, `Full`, `Custom`. Eski ayar dosyalarında hazır seçim yoktur; bölgeden çıkarılır.

| Seçim | Üst | Alt | Sol | Sağ |
|---|---|---|---|---|
| Bottom (alt, varsayılan) | 0,62 | 0,97 | 0,14 | 0,86 |
| Top (üst) | 0,03 | 0,38 | 0,14 | 0,86 |
| Full (bütün kare) | 0 | 1 | 0 | 1 |
| Custom (özel) | kayıtlı bölge | | | |

- **Eşleştirme:** seçimler bu sırayla denenir; bölgenin dört kenarı bir seçiminkiyle **0,001** payla aynıysa o seçim,
  hiçbiri değilse `Custom`.
  - (0,62/0,97/0,14/0,86) → Bottom; (0,0305/0,3795/0,14/0,86) → Top; (0/1/0/1) → Full; (0,62/0,97/0,14/0,87) → Custom;
    (0,5/0,9/0,1/0,9) → Custom.
- **Dikey yüzde (Özel seçimdeki iki kaydırıcı: konum ve yükseklik):** konum = üst × 100, yükseklik = (alt − üst) ×
  100. (0,6/0,9) → 60 ve 30.
- **Dikey ayarla (konum %, yükseklik %):** yükseklik = sıkıştır(yükseklik/100, **0,05**, 1); üst = sıkıştır(konum/100, 0,
  1 − yükseklik); alt = üst + yükseklik; sol ve sağ değişmez.
  - (0,62/0,97/0,2/0,8) + (40, 25) → üst 0,4, alt 0,65, sol 0,2, sağ 0,8.
  - (50, 1) → yükseklik 0,05; (10, 150) → üst 0, alt 1; (90, 30) → üst 0,7, alt 1 (yukarı kayar); (−20, 30) → üst 0, alt 0,3.
- Bölge elle değişince (kaydırıcı ya da çerçeve) seçim `Custom` olur.

---

## 5. Bilgisayardaki altyazı penceresi: yığın ve sarma

Bilgisayardaki altyazı penceresi ve yayın penceresi, TV'ye giden satırları **TV uygulamasıyla aynı yığın
kurallarıyla** gösterir (TV'deki gösterim kuralları TV belgelerindedir; burada aynısı). Zaman saniye cinsinden dışarıdan
verilir.

### 5.1 Yığın

| Ad | Değer (sn) |
|---|---|
| Önceki satır, yeni satır bu süre içinde gelirse üstte kalır | 1,5 |
| Üste çıkan satırın solmadan önce durduğu süre | 1,5 |
| Solma | 0,4 |
| En kısa görünme (yerine satır gelmedikçe) | 1,2 |
| "Temizle"nin bekleyeceği en uzun okuma süresi | 5 |

Durum: şimdiki satır (kimlik, metin, satır satır mı, gösterilme, kalkış, en erken temizlenme), önceki ve iki önceki
(kimlik, metin, gösterilme; solma = gösterilme + 1,5; kalkış = solma + 0,4). Kimlikler artan. "Önceki satırı üste çıkar"
ayarı (`StackPrevious`, altyazı stilinde; varsayılan açık).

- **Göster (metin, süre ms, satır satır mı, şimdi, yerine koy mu):** önce süresi dolanlar atılır (şimdiki dolduysa hepsi;
  önceki/iki önceki dolduysa onlar).
  - Yerine koy ve şimdiki var ve yeni satır satır değil → üsttekiler olduğu gibi kalır (önceki çeviri üste çıkmaz).
  - Değilse ayar açık, şimdiki var, şimdiki < 1,5 sn önce gösterildi, ikisi de satır satır değil ve iki metin **aynı satır**
    değilse → şimdiki üste çıkar: önceki varsa ve henüz solmaya başlamadıysa ve şimdikiyle aynı satır değilse iki önceki
    olur (gösterilme şimdi); önceki = şimdiki (gösterilme şimdi).
  - Değilse önceki ve iki önceki silinir.
  - okuma = 2 + uzunluk × 0,06; görünme = süre > 0 ise max(1,2, süre/1000), değilse min(8, okuma); şimdiki = yeni (kalkış
    şimdi + görünme, en erken temizlenme şimdi + min(5, okuma)).
- **Temizle (şimdi):** süresi dolanlar atılır; şimdiki yoksa dön; en erken temizlenme geçtiyse hepsi kalkar; değilse kalkış
  = en erken temizlenme.
- **Gizle:** hepsi hemen kalkar (çeviri durdu).
- **Satırlar (şimdi):** şimdiki yoksa ya da kalktıysa boş; iki önceki ve önceki (kalkmadıysa; solma başladıysa "soluyor"),
  sonra şimdiki. Roller: iki önceki, önceki, şimdiki.
- **Sonraki değişim:** şimdikinin kalkışı ve üsttekilerin solma/kalkış anlarından şimdiden sonraki en küçüğü; yoksa yok.
- **Aynı satır (a, b):** her biri küçük harfe çevrilir, sözcüklere bölünür, sözcüklerden `. , ! ? ; : … " ' “ ” ‘ ’ « » ( ) [ ]
  - – —` atılır, boşlar atılır, tek boşlukla birleşir (x, y). Biri boşsa x = y mi. Boşluksuz halleri eşitse evet. Boşluksuz
  x, boşluksuz y'yi içeriyorsa: y birden çok sözcüklüyse ya da " x " içinde " y " tam sözcük olarak geçiyorsa evet (ve tersi).
  Değilse hayır.
- **Görünecek metin:** satır satırsa metin aynen (ölçek 1); değilse sarma (§5.2).
- Uygulamanın pencerelerinde satırların opaklığı: şimdiki 1, önceki 0,6, iki önceki 0,45; solma 0,4 sn'lik geçişle.

| Senaryo (süre ms; zaman sn) | Beklenen |
|---|---|
| Ayar kapalı: "Yere yat!" 4000 @0, "Kapıyı tut!" 4000 @0,5 | @0,6 ["Kapıyı tut!"] |
| "Kapıyı aç." 4000 @0 | @3,9 görünür; @4 boş |
| "Evet." 100 @0 | @1,1 görünür; @1,2 boş |
| "Evet." 0 @0 | @2,29 görünür; @2,31 boş (2 + 5 × 0,06) |
| "Birinci" @0, "İkinci" @0,5, "Üçüncü" @1 (8000) | @1 ["Birinci", "İkinci", "Üçüncü"], roller iki önceki/önceki/şimdiki; "Dördüncü" @1,5 → ["İkinci", "Üçüncü", "Dördüncü"] |
| "Birinci" @0, "İkinci" @2 | ["İkinci"] |
| "Birinci" @0, "İkinci" @1 | @2,4 üstteki solmuyor; @2,6 soluyor; @2,9 ["İkinci"]; sonraki değişim @1 → 2,5, @2,5 → 2,9, @2,9 → 9 |
| "Köprü" @0, "Köprü artık geçilmez durumda." @0,5 | ["Köprü artık geçilmez durumda."] |
| "Birinci" @0, "Yolumuz uzun" @0,5, "Daha yolumuz uzun, sabret." @0,8 yerine koy | ["Birinci", "Daha yolumuz uzun, sabret."] |
| "Birinci" @0, satır satır "GÖREV\n• Feneri yak" @0,5 | yalnız o, satır satır |
| "Kapıyı aç." 15000 @0, temizle @1 | @2,5 görünür; @2,61 boş |
| "Birinci" @0, "İkinci" @1 (15000), temizle @4 | @4 boş; sonraki değişim yok |
| İki satır, gizle | boş |
| ("No!", "Not now!"), ("Go!", "Going home."), ("No!", "I know!") @0 ve @0,5 | ikisi de görünür |

Aynı satır: ("Kapıyı aç!", "kapıyı aç.") evet; ("Köprü", "Köprü artık…") evet; ("Evet", "Hayır") hayır; ("Kapıyı aç!",
"Kapıyıaç") evet; ("Kapıyı a", "Kapıyı aç!") evet; ("No!", "Not now!") hayır.

### 5.2 Sarma

Uzun çeviri tek uzun satır olup taşmasın: satır başına en çok **42** karakter, en çok **3** satır, sözcük sınırından ve
dengeli; 3 satıra sığmayacaksa yazı biraz küçülür (ölçek en az **0,75**). Konuşan adı bölünmez, hep ilk satırdadır. (Mac,
Android, TV ve OBS sayfaları da aynı kuralı uygular.)

1. Uzunluk = Unicode görünür karakter (grafem) sayısı. ≤ 42 ise ya da metin `\n` içeriyorsa aynen, ölçek 1.
2. Sözcükler (boşluk); ilk 3 sözcükten `:` ya da `：` ile biten **ilk** sözcük bulunursa, sonraki sözcük varsa baştan o
   sonraki sözcüğe kadar hepsi tek parça olur (ad satır sonunda tek kalmaz). Parça < 2 ise aynen, ölçek 1.
3. ölçek = sıkıştır(126 / uzunluk, 0,75, 1); sınır = aşağı(42 / ölçek); satır = min(3, max(2, yukarı(uzunluk / sınır))),
   ve parça sayısını aşmaz.
4. **Dengeleme:** satır 2 ise ya da parça < 3 ise her tek kesim, değilse her iki kesim denenir. Satır genişliği =
   parçaların (UTF-16) uzunlukları toplamı + aradaki boşluklar. En uzun satırı en kısa olan seçilir; eşitlikte
   genişliklerin karelerinin toplamı küçük olan; yine eşitse ilk bulunan. Satırlar `\n` ile.

| Girdi | Sonuç |
|---|---|
| "Hadi, yola çıkalım." | aynen, ölçek 1 |
| "Fırtına dinmeden önce hepimizi bu adadan çıkaracak bir tekne bulmalıyız" | 2 satır, ölçek 1, satır uzunluk farkı ≤ 12, birleşince aynı metin |
| "kelime" × 30 (boşlukla) | 3 satır, 0,75 ≤ ölçek < 1 |
| "MARA: We have to cross the bridge before the river floods the road tonight, you got it?" | ilk satır "MARA: " ile başlar ve ondan uzundur |
| "Kervan sabah erkenden yola çıktı\nRehber de en arkada yavaş yavaş yürüdü" | aynen |
| Yığında satır satır işaretli 20 × "kelime" | ölçek 1, `\n` yok |

---

## 6. Oyunun tanınması

### 6.1 Oyun adı anahtarı

Sunucudaki anahtarla aynı olmalı (ortak havuz ve paket eşleşmesi buna dayanır):
1. Boşsa "".
2. `™ ® ©` boşluk olur; uyumluluk ayrıştırması (NFKD) ve kültürden bağımsız küçük harf.
3. Karakter karakter: birleşen işaretler atılır; `'`, `’`, `` ` `` atılır; `ı` → `i`; `&` → " and "; harf/rakam olmayan
   boşluk olur; harften rakama ya da rakamdan harfe geçişte araya boşluk girer ("gta6" → "gta 6").
4. Sözcüklere bölünür; Roma rakamları sayıya: ii 2, iii 3, iv 4, v 5, vi 6, vii 7, viii 8, ix 9, x 10, xi 11, xii 12,
   xiii 13, xiv 14, xv 15, xvi 16. Birden çok sözcük varsa baştaki "the" atılır.
5. Tam sözcük olarak sırayla: "grand theft auto" → "gta", "call of duty" → "cod", "red dead redemption" → "rdr", "ea sports
   fc" → "fc", "ea sports" → (silinir).
6. Boşluklar teke iner; en çok 80 karakter; kırpılır.

| Ad | Anahtar |
|---|---|
| Grand Theft Auto VI / GTA 6 / gta vi / GTA6 / Grand Theft Auto VI® | gta 6 |
| Assassin's Creed Shadows | assassins creed shadows |
| The Last of Us Part II Remastered | last of us part 2 remastered |
| Call of Duty: Black Ops 6 | cod black ops 6 |
| God of War Ragnarök | god of war ragnarok |
| (boş) | (boş) |

### 6.2 Çalışan oyun kaydı

Oyun = kimlik (isteğe bağlı) + ad (isteğe bağlı). **Kimlik:** kırpılıp büyük harfe çevrilmiş, 4 büyük harf + 5 rakam, isteğe
bağlı "_" + 2 rakam; değilse geçersiz. **Ad:** denetim ve biçim karakterleri boşluk olur, boşluklar teke iner, en çok 120
karakter, kırpılır; boşsa yok. "Kimlikle oyun": kimlik geçersizse oyun yok. "Adla oyun": ad yoksa oyun yok; kimlik
geçerliyse o da tutulur.

### 6.3 Oyun duyusu

Oyun dört yoldan bilinir; öncelik: **PS5'in bildirdiği** > **kullanıcının seçtiği** > **paketten tanınan** >
**ekrandan tanınan**. Bulunan oyun, ortak havuza gönderilen satırlarla birlikte gider.

- **Paketten tanıma:** her gösterilen satır için bir kayıt: satır **yalnız tek bir pakete özgü** anahtarla paketten geldiyse
  o paketin kimliği ve adı, değilse boş. Genel ortak paket (kimliği `pool-genel`) oyun değildir, boş sayılır. Son **20**
  kayıt tutulur. Kayıt boşsa "tanınmadı". Ad verildiyse o kimlik için saklanır. Kimlik şimdiki paket oyunuysa ya da son 20
  kayıtta **5**'ten az geçiyorsa "tanınmadı". Değilse oyun = adla oyun (saklanan ad ya da kimlik; kimlik `pool-` ile
  başlıyorsa kalan kısmın `-`'leri `_` yapılıp kimlik olarak okunur) → paket oyunu bu olur, "yeni tanındı".
- **PS5'in bildirdiği:** yazılır; PS5 bir ad bildiriyor ve kullanıcının seçtiği adla anahtarı farklıysa kullanıcının seçimi
  **silinir** (PS5 sonra bildirmeyi bırakınca eski seçim geri gelmesin). Aynı oyunsa seçim kalır.
- **Kullanıcının seçimi:** adla oyun (yoksa silinir); "soruldu" işaretlenir.
- **Ekrandan tanınan:** adla oyun (yoksa silinir).
- **Paket araması sınırı:** PS5 bir oyun bildirmiyorsa kullanıcının seçtiği oyunun adı; yoksa sınır yok.
- **Yeni oturum:** son kayıtlar, paket oyunu, PS5 oyunu silinir; "soruldu" kalkar. Kullanıcının seçimi ve ekrandan tanınan
  **kalır**.
- **Sorulmalı mı (`reading.gamePicker.title` kartı):** ayar açık, bu oturumda sorulmadı, hiçbir yoldan bilinmiyor ve çeviri
  en az **2 dakikadır** sürüyor. Kart gösterilince ya da `reading.gamePicker.dontAsk` düğmesine basılınca "soruldu".
- **Kaynak:** PS5 / kullanıcı / paket / ekran ya da yok.

| Senaryo | Beklenen |
|---|---|
| ("gta-v", "Grand Theft Auto V") ×4 (hep "tanınmadı"), boş ×10 | oyun yok; 5.'de "yeni tanındı", oyun (kimlik yok, "Grand Theft Auto V"), kaynak paket; 6.'da "tanınmadı" |
| Seçim "Ghost of Yōtei"; ("rdr-2", "Red Dead Redemption 2") ×5 | oyun Ghost of Yōtei, kaynak kullanıcı, sınır Ghost of Yōtei; PS5 "Mafia: The Old Country" → o, kaynak PS5, sınır yok; PS5 bırakınca → "Red Dead Redemption 2", sınır yok |
| Seçim "GTA 5"; PS5 "Grand Theft Auto V"; PS5 bırakır | oyun "GTA 5", sınır "GTA 5" |
| gta-v ×5 (tanındı); rdr-2 ×1 → hâlâ GTA V; rdr-2 ×3 daha → hâlâ; 1 daha → "yeni tanındı", RDR 2 |
| rdr-2 ×4 → yok; seçim "Grand Theft Auto V" → o; PS5 "Mafia…" → o |
| `pool-genel` ×10 → hep tanınmadı; ("pool-ppsa01234", "Grand Theft Auto VI") ×5 → (PPSA01234, "Grand Theft Auto VI") |
| Kimlik çıkarma: "pool-cusa00419-00" → CUSA00419_00; "pool-gta-6" → yok |
| Sorma: 1 dk → hayır; 2 dk ayar kapalı → hayır; 2 dk açık → evet; sonra işaretle → hayır; seçim "GTA 6", yeni oturum → oyun (yok, "GTA 6"), sorma hayır; PS5 (PPSA01234, Grand Theft Auto VI) → kimlik PPSA01234 |
| Ekrandan "Grand Theft Auto VI" → kaynak ekran; gta-v ×5 → paket; seçim "Elden Ring" → kullanıcı; PS5 "Astro Bot" → PS5; PS5 bırakır, seçim silinir, yeni oturum → yine "Grand Theft Auto VI" (ekran); ekran silinir → oyun ve kaynak yok |

### 6.4 Ekrandan tanıma zamanlaması (sunucuya kare sorma)

- Oyun bilinmiyorsa: çeviri başladıktan (ya da sıfırlamadan) sonra **8 sn**'den sonra ilk deneme, sonra her **60 sn**'den
  sonra, en çok **6** deneme.
- Oyun ekrandan tanındıysa (yedek doğrulama): **5 dk**'dan sonra ilk bakış, sonra her **20 dk**'dan sonra, en çok **12**.
- Oyun PS5'ten, kullanıcıdan ya da paketten biliniyorsa bakılmaz.
- Aynı anda tek istek; başlatılınca "sürüyor", bitince (sonuç ne olursa olsun) "bitti" denmelidir. Süre karşılaştırması
  **kesin büyük** (tam 8 sn olmaz, 9 sn olur).

Örnekler (sahte UTC saat): başlangıçta → hayır; +9 sn → evet; +120 sn (ilki sürüyor) → hayır; bitir → evet; sonra her
turda +59 hayır, +2 evet … 6 denemeye kadar; +1 saat → hayır. Bilinen oyunda: paket/PS5/kullanıcı → hep hayır; sıfırla;
+4 dk ekran → hayır; +2 → evet; +19 → hayır; +2 → evet; sonra her +21 dk evet (toplam 12); sonra +21 → hayır.

### 6.5 Ekrandaki işaretlerden GTA 6

Okumada yalnız GTA 6'da görülen yazılardan biri bulunursa sonuç "GTA 6" (anahtarı "Grand Theft Auto VI" ile aynı), yoksa yok:
1. Okuma bir **harita ekranıysa** (tuş listesi; telefon/harita belgesi) → GTA 6.
2. Her satır harita menüsü kırıntılarından temizlenip (telefon/harita belgesi) sadeleştirilir.
3. Bir satır hem "jason" hem "lucia" içeriyorsa → GTA 6.
4. Satırlardan biri tam "brief" ve biri tam "progress" ise ve (sözcüklerden biri "jason" ya da "lucia" ya da bir satır tam
   "map") → GTA 6.
5. Bir satır tam "whatup" (telefonun mesaj uygulaması) → GTA 6.

| Okuma | Sonuç |
|---|---|
| `gta6-harita-buckme` | GTA 6 |
| "JASON & LUCIA", "MAP", "BRIEF", "PROGRESS" | GTA 6 |
| "MAP", "BRIEF", "PROGRESS" | GTA 6 |
| "Reminders", "WhatUp" | GTA 6 |
| "Options", "Map", "Progress", "Quit Game" | yok |
| "Wait for me at the pier!" | yok |
| `gta6-altyazi-beyaz`, `gta6-telefon-brian-parlama` | yok |

Uygulamada telefon izleyicisi telefon ekranını görünce ve harita izleyicisi okumasında işaret bulunca oyun "ekrandan
tanındı" olur; PS5 ya da kullanıcı oyunu söylüyorsa, ya da aynı oyun önceden biliniyorsa değişiklik olmaz.

### 6.6 Oyun seçme kartının önerileri

- **Popüler oyunlar** (Mac, iPhone, Android'de aynı liste, bu sırayla): GTA 6, GTA 5, Red Dead Redemption 2, Ghost of
  Yōtei, Marvel's Spider-Man 2, Death Stranding 2: On the Beach, Elden Ring, Elden Ring Nightreign, Assassin's Creed
  Shadows, Call of Duty: Black Ops 7, Call of Duty: Black Ops 6, Battlefield 6, EA Sports FC 26, Mafia: The Old Country,
  The Last of Us Part II Remastered, God of War Ragnarök, Cyberpunk 2077, Hogwarts Legacy, Resident Evil Requiem, Silent
  Hill f, Metal Gear Solid Delta: Snake Eater, Borderlands 4, Kingdom Come: Deliverance II, Clair Obscur: Expedition 33,
  Final Fantasy VII Rebirth, Stellar Blade, Black Myth: Wukong, Baldur's Gate 3, Horizon Forbidden West, Alan Wake 2,
  Indiana Jones and the Great Circle, Dying Light: The Beast, Ghost of Tsushima, Star Wars Outlaws, The Witcher 3: Wild
  Hunt, Monster Hunter Wilds, Split Fiction, Hollow Knight: Silksong.
- Kısa adların uzun adı: "GTA 6" → "Grand Theft Auto VI", "GTA 5" → "Grand Theft Auto V".
- **Öneriler (arama, paketlerin oyunları, son oynanan, en çok 8):** son oynanan, paket oyunları (genel ortak paket hariç),
  popüler oyunlar; anahtarı boş olan ve daha önce görülen anahtarlar atlanır. Arama anahtarı boşsa ilk 8. Değilse: anahtarı
  aramanın anahtarını içerenler ya da uzun adı (küçük harfle) aramayı (kırpılmış, küçük harf) içerenler; önce anahtarı
  aramanın anahtarıyla başlayanlar, sonra ötekiler; ilk 8.
  - ("", ["Mafia: The Old Country"], son "Elden Ring") → ilk "Elden Ring", ikinci "Mafia: The Old Country".
  - "gta 6" → ilk "GTA 6"; "zzzz" → boş; "grand theft" → "GTA 6" içerir; boş aramada ilk öneri "GTA 6".

---

## 7. Mac ile farklar (Windows'u esas al)

Mac okuma hattı tarifinin bölüm başlıkları ve sayı tablolarıyla karşılaştırıldı. Sabitleyici ve gönderme sabitleri (2 okuma,
0,85, 800, 4000, 1500, 1000, 700, 5, 0,90; 800, 300, 4000, 2, 2500, 8, 15 000, kalkmış satır süresi) **aynıdır**.

| Konu | Mac | Windows |
|---|---|---|
| Tek kare kapısının takılma süresi | 45 000 ms (yedek okuyucuda 9000) | **15 000 ms**, yedek okuyucu yok |
| Görev şeridi çizgisi (0,935) | açık (havuz öncelikli oyunda) | kural çekirdekte var ama uygulama **vermiyor** |
| Öğrenilen altyazı şeridiyle bölgeyi daraltma | var | **yok** |
| Eşya/tabela etiketi kuralı (sayaçlı, simgeli, küçük harfsiz kısa satırlar) | var | **yok** (yalnız dev yazıdaki etiket ölçüsü) |
| Köşe okumaları, tuş ipuçları paneli, mesaj/arama kartı, buzlu zemin | var | **yok** |
| Kumanda simgesini görüntüden tanıma, simge metni düzeltme, sahne aydınlığı | var | **yok** |
| Yazı tanıma | Vision, güveni 0,5'in altındaki satır atılır | Windows.Media.Ocr (güven yok), 6 hazırlıklı seçim zinciri, otomatik seviye, geniş boşlukta satır bölme |
| Bozuk okuma / okuma puanı | OCR izi kuralı, OCR çöpü puanı | aynıları + Windows yazım denetimi (yalnız "en…" dillerinde, §3.5–3.6 1. bölüm) |

## 8. Testler: sahte parçalar ve `Fixtures`

### 8.1 Sahte parçalar (yeni testlerde aynısı kurulmalı)

- **Sahte saat:** 1 000 000'den başlar; testler elle ilerletir (çoğu senaryoda kare başına +50 ya da +100). Bazı testler
  saati 0'dan başlatır.
- **Sıralı okuyucu:** verilen metinleri sırayla (yalnız metin) döndürür, bitince boş; okumanın hangi iş parçacığında
  yapıldığını kaydeder.
- **Satır okuyucu:** her çağrıda verilen okumayı (kutulu satırlar) döndürür.
- **Engelleyen okuyucu:** okumaya girince haber verir, test bırakana kadar (en çok 10 sn) bekler.
- **Zamanlı okuyucu / çevirmen:** her okumada/çeviride sahte saati verilen ms kadar ilerletir.
- **Sahte çevirmen:** "TR: " + metin; istekleri kaydeder; istenirse hep belirli bir hata ya da ilk N çağrıda zaman aşımı
  verir.
- **Bekleyen çevirmen:** çevirileri test bırakana kadar bekletir (iptale uyar); tek tek bırakılabilir ya da hepsi açılır;
  açıldıktan sonra gelenler beklemez. Bir türü iptali dinlemez.
- **Sahte TV gönderici:** gönderilen metinleri, süreleri, kutuları, "yerine koy" bayraklarını ve "temizle" sayısını
  kaydeder.
- **Önbellekli çevirmen:** önbellekte varsa oradan (günlükte "önbellek"), yoksa "TR: "+metin ve önbelleğe yazar.
- **Ek alan sahteleri:** okuyucu (satırlar, okuma sayısı, ilk N okumada hata), çevirmen (çağrılar, ilk N'de hata), TV
  (kimlik, metin, kutu, satır yüksekliği; kaldırma sayısı).

### 8.2 `Fixtures` klasörü

Gerçek GTA 6 karelerinden çıkarılmış okumalar (hangi yazı tanıyıcıyla çıkarıldıkları bilinmiyor; satırların kırılışı ve
kutular gerçek bir tanıyıcı çıktısı gibidir). Görüntü yoktur; yalnız satırlar ve kutular vardır.
Dosyalar yeni test projesine **olduğu gibi kopyalanabilir**; yükleyici yeni ağaçtaki yeri bulacak şekilde ayarlanır (eski
yükleyici çalışma klasöründen yukarı doğru `…/Nino.Core.Tests/Fixtures` klasörünü ya da içinde `gta6-harita-buckme.lines.txt`
bulunan bir `Fixtures` klasörünü arar).

**Biçim** (`<ad>.lines.txt`, UTF-8): her satır = boşlukla ayrılmış dört sayı (sol üst sağ alt; **karenin tamamına** oran,
nokta ondalık, kültürden bağımsız okunur), bir **SEKME**, satırın metni. Sekme içermeyen satırlar yok sayılır. Satırlar
dosyadaki sırayla okumaya girer (okuma kurulurken boş metinler atılır).

| Dosya | İçerik | Kullanan testler |
|---|---|---|
| `gta6-altyazi-beyaz.lines.txt` | Beyaz altyazılı kare: sağda telefon mesajının satırları ("Remember, you get your hands…", "finder's fee. Door code is 7700.") ve altta ortalı altyazı "Yeah, okay. Just wait, you're gonna love it, we're gonna have fun." | oyun işaretleri (GTA 6 sayılmaz); telefon belgesindeki testler |
| `gta6-harita-balik.lines.txt` | Harita ekranı, "CATCH A BIGGER FISH" görev kartı, solda etkinlik menüsü, sağ altta tuş listesi (RECENTER, 2D VIEW R3, ADD MARKER, SET DESTINATION, CLOSE MENU) | harita kartı testleri (telefon/harita belgesi) |
| `gta6-harita-buckme.lines.txt` | Harita ekranı, "DEPOSIT CASH INTO BUCKME" kartı (iki cümle), solda görev listesi, tuş listesi | oyun işaretleri (GTA 6 sayılır); harita kartı; kartın yerleşimi |
| `gta6-telefon-brian-parlama.lines.txt` | Telefon sohbeti (Brian), parlak zemin, düz telefon | telefon testleri; oyun işaretleri (GTA 6 sayılmaz) |
| `gta6-telefon-egik-mavi.lines.txt` | Aynı sohbet, eğik tutulan telefon, mavi balonlar | telefon testleri |
| `gta6-telefon-lucia-foto.lines.txt` | Lucia ile sohbet, fotoğraflı mesaj, "@247Heaven" | telefon testleri |
| `gta6-telefon-yakin-alt.lines.txt` | Telefonun alt kısmına yakın üç satırlık mesaj | telefon testleri |

### 8.3 Ölçüm ve sağlamlık notları

- Bırakma testleri iş parçacığı havuzundan birini kasten meşgul eder; bu yüzden testlerin başında iş parçacığı havuzunun en az iş parçacığı
  sayısı 32'ye çıkarılır (paralel testler aç kalmasın). Takılmayı yakalayan süreler cömerttir (30 sn).
- Testler kullanıcının gerçek verisine dokunmaz; ağ yoktur.

---

## 9. Ekran dökümü aracı (geliştirme)

`Nino.exe --render-screens <klasör>`: uygulama normal açılmaz; her ekranın açık ve koyu tema görüntüsünü PNG dosyası
olarak yazar ve çıkar (görünüm, Windows'a bakmadan otomatik derlemede incelenebilsin). Bu okuma hattının parçası değildir; yine
de aynı dosyada durduğu için burada:

- Klasör kurulur; uygulama ilk pencere kapanınca kapanmasın diye "yalnız açıkça kapat" kipine alınır. Bir ekranın hatası
  ötekileri durdurmaz: hatalar klasördeki `errors.txt`'ye eklenir (arayüz iş parçacığının yakalanmamış hataları da).
- Her tema için (önce açık, sonra koyu; dosya ekleri `acik`, `koyu`): kurulumun "bitti" dışındaki her adımı
  `adim-<adım sırası + 1>-<adım adı>-<ek>.png`; ana ekran `ana-<ek>.png`; gerçek pencere (simgesiyle) `pencere-<ek>.png`;
  ayarlar penceresi `ayarlar-<ek>.png` (1000 piksel geniş); hakkında penceresi `hakkinda-<ek>.png` (460 × 640). Ana boyut
  tasarım değerlerindeki pencere genişliği ve yüksekliğidir.
- Her ekran sahte hizmetlerle (bulunan PS5 "PS5-123" 192.168.1.20, bulunan TV "[LG] webOS TV" 192.168.1.30, çeviri modeli
  yalnız İngilizceden destekli ve kurulu, okuyucu yok; "bitti" adımında kayıtlı hesap, konsol, TV ve TV anahtarı) kurulur;
  ekran dışarıda (−10000, −10000), kenarlıksız, görev çubuğunda görünmeyen bir pencereye pencere zemini ve yazı rengiyle
  konur, gösterilir, **600 ms** beklenir (yükleme sırasında başlayan işler yansısın), **2 kat** çözünürlükte (192 dpi)
  çizilip PNG olarak kaydedilir, pencere kapanır.

---

## 10. Emin olunmayan ya da başka belgeye kalan noktalar

- Paket araması işinin içeriği (önce oyun paketi, sonra havuz; havuz öncelikli oyunda yalnız havuz), "pakette yok" olayının
  havuza önerilmesi ve havuzdan sonradan çeviri istenmesi paketler/havuz belgesine aittir; burada yalnız hattın bu işi nasıl
  çağırdığı var.
- Telefon satırlarının süzülmesi (açık zeminde koyu yazı, telefon arayüzüne özgü yazılar, telefon izleme) ve harita ekranı
  kararı telefon/harita belgesindedir.
- Ayar dosyasının tamamı (öteki alanlar, eski kayıtların taşınması) ayarlar belgesindedir; burada yalnız okuma hattına
  dokunan alanlar var (`ExtraTarget*`/`FreeAreaTarget` sayı, `AreaPreset` metin).
- Windows OCR motorunun "en büyük görüntü boyutu" sabiti işletim sisteminden okunur; değeri burada yazılmadı.
- TV'ye giden mesajların JSON biçimi (altyazı, temizle, ekran, ek alan) TV bağlantısı belgesindedir.
