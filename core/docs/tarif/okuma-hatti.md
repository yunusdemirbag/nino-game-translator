# Okuma hattı

Okuma hattı, gelen oyun karelerinden altyazıyı çıkarır. Her kare için şu
sırayla çalışır:

```
kare → OCR → bölge süzgeci → gürültü süzgeci → satırları birleştir
     → sabitleyici → cümle bölücü → olay (başladı / bitti)
```

Hattın hiçbir parçası saate bakmaz. Zaman, **kare sayısıyla** ölçülür. Bu
sayede testler her seferinde aynı sonucu verir.

## 1. Kare

- Kare, Remote Play'den gelen tek bir görüntüdür (`CGImage`).
- Remote Play bağlantısı çekirdeğin işi değildir. Çekirdek yalnız kareyi alır.

## 2. OCR (yazı okuma)

- OCR bir arayüzün arkasındadır: `TextRecognizer`. Kare verilir, okunan
  satırlar döner.
- Her satırda üç şey vardır: yazı, güven (0–1) ve kutu.
- Kutu, karenin oranı olarak verilir (0–1). **Nino'da başlangıç noktası sol
  üst köşedir.** Apple Vision sol alt köşeyi kullanır; Vision okuyucusu kutuyu
  çevirerek verir.
- Gerçek okuyucu Apple Vision ile çalışır: doğru (accurate) mod, İngilizce,
  dil düzeltmesi açık, yalnız altyazı bölgesi okunur.
- Testlerde sahte okuyucu kullanılır: sırayla önceden yazılmış satırları
  döndürür.

## 3. Bölge süzgeci

- Altyazı bölgesi ayarlanabilir bir dikdörtgendir. Bir algılama yapılmaz.
- Varsayılan: altta ve ortada. `x 0.10, y 0.62, genişlik 0.80, yükseklik 0.36`
  (sol üstten).
- Kutusunun merkezi bölgenin dışında kalan satır atılır.

## 4. Gürültü süzgeci

Bir satır şu durumlarda atılır:

- Güveni alt sınırın altındaysa (varsayılan **0.40**).
- İçinde **2'den az harf** varsa. Örnek: `A`, `3`, `>>`, `—`.
- Harfler, boşluk dışı karakterlerin yarısından azsa. Örnek: `[X] 12/40`.
- Yazının tamamı bilinen bir arayüz yazısıysa (büyük/küçük harf fark etmez).
  Varsayılan liste: `options, menu, skip, pause, back, select, confirm,
  continue, loading, settings, map, inventory`. Liste ayarlanabilir.

Kısa ama gerçek satırlar **kalır**: `No.`, `Go!`, `Hm?`.
Bilinen kayıp: tek harflik `I.` gibi satırlar atılır.

Kalan satırlar yukarıdan aşağıya sıralanır ve aralarına bir boşluk konarak tek
yazı yapılır. Fazla boşluklar teke indirilir. Hiç satır kalmazsa kare **boş**
sayılır.

## 5. Sabitleyici

Sabitleyici her karede bir yazı (ya da boş) alır ve olay üretir.

Ayarlar (varsayılan):

| Ayar | Değer | Anlamı |
|---|---|---|
| `stableFrames` | 3 | Yeni altyazı için kaç kare benzer yazı gerekir |
| `missingFrames` | 2 | Altyazının bitmesi için kaç kare görünmemesi gerekir |
| `similarity` | 0.85 | İki yazının "aynı" sayılma eşiği |

**Benzerlik:** Yazılar küçük harfe çevrilir, harf ve rakam dışı her şey
boşluk olur, boşluklar teke iner. Sonra düzenleme uzaklığı (Levenshtein) ile
`1 - uzaklık / uzun olanın boyu` hesaplanır. Eşik ve üstü benzer sayılır. Böylece
OCR'nin tek harflik oynaması (`Hello there` / `Hel1o there`) sayacı sıfırlamaz.

**İstisna:** Biri ötekinin uzantısıysa (anahtarlar farklı ve biri ötekiyle
başlıyorsa) benzerlik ne olursa olsun **aynı sayılmaz**. Böylece büyüyen yazı
OCR oynamasıyla karışmaz: `Hello there, my friend.` → `... Go.` yeni altyazıdır.
Bilinen kayıp: OCR son harfi bir karede düşürürse o kare farklı sayılır.

**Kurallar:**

1. **Aday:** Boş olmayan yazı adaydan farklıysa yeni aday olur, sayaç 1 olur.
   Adaya benzerse sayaç artar ve aday metni son okunanla güncellenir.
2. **Başladı:** Sayaç `stableFrames`'e ulaşınca altyazı **başladı** olayı
   çıkar. Aynı altyazı ekrandayken bir daha olay çıkmaz.
3. **Bitti:** Ekrandaki altyazıya benzemeyen her kare (boş ya da başka yazı)
   "görünmedi" sayacını artırır. Benzer bir kare sayacı sıfırlar. Sayaç
   `missingFrames`'e ulaşınca **bitti** olayı çıkar. Tek bir boş kare
   altyazıyı bitirmez.
4. **Boş kare adayı bozmaz:** Boş kare aday sayacını artırmaz ama sıfırlamaz.
   Art arda `missingFrames` boş kare gelirse aday silinir.
5. **Yazı değişirse:** Eski altyazı önce biter (kural 3), yeni yazı ayrıca
   sabitlenince başlar (kural 2). Aynı karede ikisi olursa önce **bitti**, sonra
   **başladı** gelir.
6. **Harf harf beliren yazı:** Yazı büyürken her kare farklıdır, sayaç
   dolmaz. Büyüme durunca sabitlenir ve bir kez başlar.
7. **Uzayan yazı:** Yeni altyazı, hemen önceki altyazının metniyle başlıyorsa
   ve önceki altyazı en fazla `stableFrames + missingFrames` kare önce bittiyse
   (ör. `Hello there.` → `Hello there. How are you?`) "devam" sayılır. Yeni
   cümleler listesine yalnız eklenen cümleler girer.
8. **Geri dönen yazı:** Biten bir yazı sonra yeniden sabitlenirse yeniden
   **başladı** olur (TV'de tekrar görünsün diye). Son 32 altyazıdan birine
   benziyorsa (aynı benzerlik kuralı) `isRepeat = true` olur. Çeviri katmanı bunu önbellekten verir, yeniden
   çevirmez.

## 6. Cümle bölücü

Uzun yazılar cümlelere bölünür. Bölme kuralı:

- Cümle sonu: `.`, `!`, `?`, `…` ya da bunların dizisi (`...`, `?!`).
- Sonrasında kapanan tırnak ya da parantez varsa (`"`, `”`, `'`, `’`, `)`,
  `]`) onlar da cümleye dahildir.
- Bölme için cümle sonundan sonra **boşluk** gelmeli ve sonraki karakter
  **küçük harf olmamalı**. Böylece:
  - `Wait... what?` bölünmez, `Wait... What?` bölünür.
  - `3.5 meters` bölünmez (noktadan sonra boşluk yok).
- Kısaltmalardan sonra bölünmez: `Mr. Mrs. Ms. Dr. St. Jr. Sr. Prof. vs.
  etc. e.g. i.e.` (büyük/küçük harf fark etmez).
- Konuşmacı tireleri (`- Run! - Where?`) ayrı cümle olur, tire korunur.
- Her cümlenin başı ve sonu kırpılır, boş cümle çıkmaz.

## 7. Olay

```
Subtitle
  id            artan sayı (1'den başlar)
  text          tam yazı
  sentences     tüm cümleler
  newSentences  çevrilmesi gereken yeni cümleler
  isRepeat      yakın zamanda görülmüş mü
  isContinuation önceki altyazının uzantısı mı
  startFrame    sabitlendiği kare sırası

SubtitleEvent = started(Subtitle) | ended(Subtitle)
```

Hat tek bir iş parçacığında, sırayla kullanılır.
