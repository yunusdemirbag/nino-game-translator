# Temiz oda: 4.5.0 son tarama (22 Kasım 2026)

Nino 4.5'in bütün kodu yeniden yazıldı. Yayından önce birleşik dal, yeniden yazımdan önceki son ortak commit'in
(`cbc149d2`) ağacıyla karşılaştırıldı. Eski ağaç yalnız karşılaştırma için açıldı; ondan hiçbir şey kopyalanmadı.

## Ne tarandı

1. **Ad araması** (içerik ve dosya adları, büyük/küçük harf duyarsız): eski projenin adı, eski yazarın ve eski
   katkıcıların adları, eski Apple takım kimliği, eski kuruluş adı, eski paket kimliği öneki. Ayrıca bunların base64
   biçimleri. **Sonuç: okunur hâlde sıfır.** Base64 hâli yalnız veri taşıma dosyalarında (`LegacyNames`), onların
   testlerinde ve bu adın yeniden girmesini engelleyen denetim betiğinde durur (ana oturum kararı: eski klasörlerden
   kullanıcı verisini taşımak için gerekli).
2. **Birebir satırlar:** boşluğu sadeleştirilmiş, en az 45 karakterlik kod/metin satırları.
3. **Dizge değişmezleri:** en az 16 karakterlik, boşluk içeren dizgeler.
4. **4 kelimelik örtüşme:** en az 6 kelimelik her metin biriminin (arayüz dizgesi, belge satırı) 4'lü kelime
   dizilerinin en az %60'ı eski metinlerde geçiyorsa.
5. **Görseller:** bütün PNG/JPG/WebP/ICO/SVG/GIF dosyaları eski ağaçla bayt bayt karşılaştırıldı; eşleşen her dosyanın
   eski sürümünün yazarına bakıldı. Eski yazara ait tek dosya (Samsung TV ikonu) Nino logosuyla değiştirildi. Kalan
   eşleşmeler kullanıcının kendi logosu, görselleri ve GTA 6 ekran kareleri.

Eşleşen eski satırın yazarı `git blame` ile bulundu; kullanıcının eski ağaçta kendisinin yazdığı satırlar (148)
sorun sayılmadı.

## Sonuç

| | Bulgu |
|---|---|
| İlk tarama (uygulama, belge, sunucu) | 782 gözden geçirilecek madde |
| Yeni sözlerle yazılan | ~470 madde (arayüz metinleri bütün dillerde, yorumlar, belgeler, örnek ve test cümleleri, gizlilik, çeviri istemleri) |
| Kalan, tek tek bakılıp bilerek bırakılan | 411 |
| Okunur eski ad | 0 |

Bırakılan maddeler değiştirilemeyecek türdendir:

- **Protokol ve sistem metinleri:** PSN/Xbox/Samsung/LG uç adresleri ve kapsamları, HTTP başlıkları, SSDP, XML-DSig
  ad alanları, Android izin adları, SF Symbol adları, `meta` etiketleri.
- **Başka programların çıktısı** (Nino bunları okuyup tanır): chiaki-ng günlük satırları, `sdb`/`adb`/`pm` yanıtları,
  Samsung/LG/Google hata metinleri.
- **Gerçek cihaz menü adları:** PS5, Android TV, Samsung ve LG ayar yolları; kullanıcının ekranda gördüğüyle aynı
  olmalı.
- **Oyun metni:** kullanıcının GTA 6 ekran karelerindeki satırlar, oyun adları.
- **Komutlar, yollar, düzenli ifadeler, derleme satırları** ve dört kelimeden kısa genel ifadeler.

Uygulama bazında gerekçeler: `docs/yeni/mac/temiz-oda.md` (Mac ve NinoCore) ile her uygulamanın kendi temiz oda
notları. Madde madde liste ve tarama betikleri depo dışında, ortak not klasöründe (`temiz-oda-son/`); eski
metinleri içerdiği için depoya alınmadı.

## Açık kalan

- Windows `obs.html` (OBS sayfası) CSS/JS satırlarının bir kısmı eski sayfayla örtüşüyor (yalnız renk/ölçü ve
  kalıp kod; karar gereği renk ve ölçü değerleri aynı kalabilir). İstenirse ayrıca yeniden düzenlenir.
