# Eski ve yeni Android uygulaması: emülatörde ekran karşılaştırması

Emülatör: `nino_phone` (Android 15, arm64, 1080×2400, 420 dpi), sistem dili İngilizce, çeviri dili Türkçe.
Eski: depodaki `nino-android` (yerel kütüphanesiz debug). Yeni: `apps/android` debug. Görüntüler oturumun geçici
klasöründe (depoya girmez; eski metinleri taşıdıkları için).

## Veri uyumu
- Eski uygulama kurulup kurulum bitirildi, deneme oturumu açıldı; yeni uygulama **üstüne** kuruldu: kurulum bitmiş
  sayıldı, doğrudan ana ekran açıldı, PS5 "bağlı değil", çıkış "TV", paketler "Ücretsiz" doğru okundu. ✅

## Ekran ekran (ilk tur, 22 Kasım)

| Ekran | Durum | Fark |
|---|---|---|
| Açılış animasyonu | ✅ | — |
| Karşılama 1–3 | ✅ | Metinler yeniden yazıldı (beklenen). İlk açılışta ikisi de İngilizce arayüzle açılıyor (eskide de böyle). |
| Konsol türü | 🟡 | Arayüz 2'de yazıldı, karşılaştırılacak |
| PSN girişi | 🟡 | Arayüz 2'de yazıldı, karşılaştırılacak |
| Altyazılar nerede | ✅ | — |
| Ana ekran (Salon) + tur | ✅ | Tur 1. adım metni "çubuğu kaydırın" diyor; Salon düzeninde "fişi takın" olmalı. Toplam indirme sayısı ilk açılışta görünmüyor. |
| Ana ekran (eski veriyle) | 🟡 | "Yeni sürüm hazır" kartı çıkıyor (eskide çıkmıyordu); metni "sen" diliyle, uygulama "siz" diliyle. |

## Tablet (nino_tablet, 1600×2560, 320 dpi)
- Eskisi tablette de dikey ve tam genişlik. Yeni ilk sürüm içeriği 600 dp'ye sığdırıyordu → kaldırıldı (tam genişlik). ✅
- Güncelleme kartı: yeni sürüm GitHub'daki 4.0.6'yı görüyor çünkü debug derlemesinin sürüm adı 0.1.0-beta.37;
  gerçek sürümde (4.x) yalnız daha yeni sürüm varsa çıkar. Eski debug'da sürüm adı sayı olmadığı için çıkmıyordu.

## Uçtan uca (emülatör, gerçek GTA 6 kareleri)
- `demo-frames` + DebugDemoActivity: altyazı karesi OCR → kurallar → ML Kit → 8787 `subtitle` olayı (kutu ve süreyle). ✅
- Oyun içi telefon karesi telefon paneli yerine altyazı olarak gitti; `screen` olayı yok → düzeltiliyor.

## Düzeltilecekler
1. ~~Tur 1. adım metni ana ekran düzenine göre seçilmeli.~~ ✅
2. Güncelleme kartı: eskideki koşula göre (yalnız GitHub'dan kurulan kopya) ve "siz" diliyle.
3. ~~Toplam indirme göstergesi ilk açılışta da gelmeli.~~ ✅
4. ~~Güncelleme kartı "siz" dili~~ ✅
5. ~~Hizmetin kullandığı aşama/hata/bildirim metinleri (`phase_*`, `error_*`, `notif_*`) strings.xml'e girmeli.~~ ✅
6. ~~Ayarlar'daki deneme altyazısı hizmete bir kanca üstünden gitmeli; paket içe aktarılınca hizmet paketleri yeniden okumalı.~~ ✅
7. ~~`support/` ile `service/` içindeki sağlık/cihaz özeti kodu birleşmeli.~~ ✅
8. Kalan 10 dil (ar, hi, id, th, vi, ur, bn, ms, fil, nl) yeniden yazılmalı.

## İkinci tur (22 Kasım, gece)
- Ayarlar, Profil, Paketler, Geçmiş, Nino'ya Sor, konsol, PSN: yerleşim ve bileşenler eskisiyle aynı. ✅
- Bilinçli farklar: Profil'de "Kullanım verisi" yok (ölçümün kapatma düğmesi yok, kullanıcı kararı); karşılamada paket
  sayfası yalnız hedef dil Türkçeyken; Ayarlar'daki "Cam düğme" önizlemesi bayraklı değil genel bir anahtar çizimi.
- Ayarlar'daki GTA 6 karosu oyun bilinmezken de Türkçede görünür (eskisi gibi). ✅
- Metinler: yeni metinlerin bir kısmı eskileriyle birebir aynı çıkmıştı (tariflerdeki alıntılardan). Hepsi aynı anlamla
  yeniden yazıldı; `apps/android/scripts/metin-benzerlik.py <depo>` ile denetlenir (birebir 0, %50+ örtüşme 0).

## Üçüncü tur (metin yenilemesinden sonra)
- Konsol türü, PSN tanıtımı, Altyazılar nerede, ana ekran + tur, Geçmiş (boş), Nino'ya Sor, Ayarlar (tüm sayfalar),
  Profil (tüm sayfalar): açıldı, düzen eskisiyle aynı, çökme yok. ✅
- Arapça: arayüz sağdan sola aynalanıyor (simgeler, robot düğmesi solda, karolar ters sırada), sayılar Arapça. ✅
- Felemenkçe (uzun metin): ana ekranda taşma yok. ✅
- Not: dil, ayar dosyası elle değiştirilince bir sonraki açılışta uygulanıyor (uygulama içindeki dil seçici hemen uygular).
- Eski TV istemcisi (tv-webos sayfası) yeni telefonun 8787'sine bağlandı; "çeviri başladı" balonu ve altyazı çizildi. ✅
- PS5 kütüphanesi emülatörde yüklendi (`Ready`), ağ araması çalıştı (emülatörde PS5 yok). ✅
