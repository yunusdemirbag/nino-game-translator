<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Android TV uygulaması: davranış tarifi

Bu belge, eski Android TV uygulamasının (sürüm 4.0.3, versionCode 40) ekranlarını ve davranışını anlatır. Yeni
uygulama (`apps/android-tv/`) koddan değil, bu tariften yazıldı. Ekran yazıları burada alıntılanmaz; yeni koddaki
metin anahtarlarıyla (`web/androidtv.js` WORDS, `res/values*/strings.xml`) anılır. Alıntılı ilk hâli depo dışında
arşivdedir.

## 1. Kimlik ve dağıtım

- Paket kimliği: `com.ninotranslator.tv`. Görünen ad: "Nino Game Translator". Yalnız TV (leanback zorunlu;
  dokunmatik ekran, canlı TV istenmez). Ana ekran simgesi ve TV afişi (banner) var.
- İki çeşit (flavor):
  - **sideload**: masaüstü uygulamasının ADB ile kurduğu APK. Katman modu var (başka uygulamaların üzerinde
    gösterme izni + ön plan servisi).
  - **play**: Google Play paketi. Katman modu yok (Play'in TV kuralı başka uygulamanın üstünü örtmeye izin
    vermiyor); yalnız İnternet izni.
- İmza anahtarları ortam değişkenlerinden gelir (`TV_KEYSTORE_*`, `TV_UPLOAD_KEYSTORE_*`); yoksa geliştirme
  anahtarı.
- Dil: Türkçe, İngilizce, Arapça (TV'nin diline göre; bilinmeyen dilde İngilizce).
- Ekran yatay, tam ekran, başlık çubuğu yok. Aynı anda tek pencere (`singleTask`).

## 2. Bağlantı (yeni: Nino Bağlantı Protokolü)

Eski uygulamada TV, bilgisayardaki Nino'ya 8787'den SSE ile bağlanan istemciydi; ağı tarar, adresi
başlatma parametresinden alırdı. **Yeni uygulamada TV sunucudur** (bkz. `~/Desktop/NinoCore/docs/tarif/protokol.md`):

- 47800/TCP'de HTTP + WebSocket dinler; `_nino._tcp` hizmetini TV'nin adıyla yayınlar (TXT: `v=1`, `id=…`).
- Göndericiyi beklemek için ağ taraması yok. Bekleme ekranında TV'nin adı ve IP adresi yazar (telefonda elle
  girilebilsin diye).
- Sunucu uygulama süreci boyunca tektir: uygulama içi görünüm, katman ve ana ekran aynı sunucuyu dinler. Uygulama
  arka plana geçince bağlantı sürer.
- Protokolde olmayan eski olaylar (`style`, `screen`, `region`, `started/stopped`, kutu yeri, kapak resmi,
  `displayMode`) yeni sürümde yoktur; sabit varsayılanlar kullanılır. Eksikler `ilerleme.md`'de listelenir.

## 3. Açılış akışı (sideload)

Masaüstü uygulaması uygulamayı ADB ile `MainActivity` olarak açabilir; `params` ve `displayMode` adlı ek
bilgileri yollayabilir. Yeni sürüm bunları kabul eder ama bağlantı için kullanmaz.

1. **İzin var** ("Diğer uygulamaların üzerinde göster"):
   - Katman servisi başlar (zaten çalışıyorsa dokunulmaz). TV'nin girişi **hiç değiştirilmez**.
   - Kumandayla (ana ekrandan) açıldıysa **Nino ana ekranı** gösterilir (§5.1).
   - Başka yoldan açıldıysa (masaüstü ADB ile) ekran gösterilmeden kapanır; katman sessizce hazır olur.
2. **İzin yok, kullanıcı daha önce izinsiz devam etmeyi seçtiyse** (`askSkip`): uygulama içi görünüm (§4).
3. **İzin yok**: **izin ekranı** (§5.2). Ekran açıkken 2 sn'de bir izin kontrol edilir; izin gelirse (ADB ya da
   ayarlardan dönüş) katman başlar ve ana ekrana geçilir.

## 4. Uygulama içi görünüm (play çeşidi ve izinsiz devam)

- Tam ekran HDMI girişi `TvView` ile gösterilir; üstünde şeffaf altyazı sayfası durur.
- HDMI sesi tam sesle açılır (bazı TV'lerde sıfırda başlıyor).
- Android 11+'da pencere `setPreferMinimalPostProcessing(true)` ile düşük gecikmeli görüntü ister (TV destekliyorsa oyun modu).
- Ekran yalnız HDMI görüntüsü oynarken açık tutulur; görüntü yokken TV ekran koruyucusuna geçebilir.
- **Giriş seçimi**: kayıtlı giriş (1–4) varsa o; yoksa PS5 aranır: önce HDMI-CEC cihaz adı ("PS5",
  "PlayStation"), sonra tek bağlı giriş; bulunamazsa HDMI 1. Girişler port sırasına göre numaralanır (CEC alt
  girişleri sayılmaz, kimliğin sonundaki sayıya göre sıralanır).
- Görüntü durumu: yükleniyor / hazır / oynuyor / giriş hatası / kaynak hatası.
- Giriş bağlantısı koparsa 5 kez, gittikçe seyrek (1,5 sn × deneme) yeniden açılır. Uygulama öne gelince son giriş
  yeniden açılır (bazı TV'ler arka planda bırakıyor).
- **Katmana kendiliğinden geçiş** (yalnız sideload, izin varsa):
  - Giriş açıldıktan sonra 10 sn hiç görüntü gelmezse ve girişte cihaz varsa → katman (kısa bildirim:
    `to_overlay_dark`).
  - Giriş açıldıktan sonraki 5 sn içinde uygulama arka plana itilirse (TV kendi HDMI oynatıcısını öne çekti) →
    katman.
  - Görüntü bir kez geldiyse sonradan kesilmesi katmana geçirmez. Arka plandayken süre sayılmaz.
- **Görüntü yok kutusu** (10 sn görüntü yok, katmana geçilemiyor): ekranın üstünde ortada koyu kutu; nedeni
  (`chooser_dark` / `chooser_empty`), giriş düğmeleri (`HDMI n · <CEC cihaz adı>` ya da `· chooser_plugged`), izin
  varsa katman düğmesi (`chooser_overlay_button`), kapatma (`chooser_close`). PS5 adlı giriş ya da açık olmayan
  bağlı giriş seçili gelir.
  Geri kapatır, 1–4 doğrudan seçer. TV girişleri hiç vermiyorsa yalnız açıklama gösterilir. Kapatılınca başka
  giriş seçilene kadar yeniden açılmaz.
- **Kumanda** (uygulama içinde):
  - 1–4: o HDMI girişi (kaydedilir), 0: kaydı unut ve PS5'i yeniden ara.
  - Yeşil ya da Tamam: bilgi paneli; Kırmızı: 4 sn'lik deneme altyazısı (oyunun üstünde görünüp görünmediğini
    soran kısa bir satır); Mavi: demo aç/kapat.
  - Panel açıkken ◀▶: HDMI girişi değiştirir. ▲▼: altyazıyı %3 yukarı/aşağı taşır (kaydedilir).
  - Geri: önce açık kutu/demo/panel kapanır, sonra uygulamadan çıkılır.
  - Kaynak (TV_INPUT) ve HDMI 1–4 tuşları sayfaya gitmez, TV'ye kalır. Kaynak tuşundan 0,7 sn sonra Nino hâlâ
    odaktaysa TV'nin canlı yayın ekranı açılır ve kaynak tuşuna yeniden basılması söylenir (`press_input_again`).
- Uygulama içi görünümde **bekleme ekranı** (gönderici yokken): kendi kendine oynayan demo (§6).

## 5. Sade Nino ekranları (sideload)

### 5.1 Ana ekran

- Koyu lacivert zemin (`#03060d`), iki büyük bulanık ışık: sol üstte mavi (`#1d4ed8`, 1100 px, 14 sn), sağ altta
  kırmızı (`#c8102e`, 900 px, daha soluk, 18 sn); yavaşça kayarlar.
- Ortada logo (200 px, köşe 46 px, mavi gölge), altında "Nino" (92 px, kalın) ve "GAME TRANSLATOR" (22 px, geniş
  harf aralığı, soluk).
- Durum satırı: renkli nokta + yazı. Bağlıyken yeşil (`linked`), değilken turuncu (`waiting`: telefonda ya da
  bilgisayarda Nino'nun açılması bekleniyor).
- Kart (1180 px, yarı saydam beyaz, köşe 36 px): başlık PS5'in hangi HDMI girişinde olduğu (`goTitle`; bilinmiyorsa
  girişin kumandayla seçilmesi; giriş PS5 dışında bir ad taşıyorsa ad da yazılır), açıklama kaynak tuşuyla o girişe
  geçilmesi ve çevirinin oyunun üstünde görüneceği (`goText`).
- Alt satır: Geri tuşunun çıkış olduğu ve uygulama sürümü (`foot`). Geri tuşu uygulamayı kapatır (katman sürer).

### 5.2 İzin ekranı

- Aynı zemin; logo ve yazılar küçülür (1080 piksele sığsın).
- Sarı başlık (`askTitle`: tek seferlik izin), açıklama (`askText`; USB hata ayıklama açıksa telefondan/bilgisayardan çeviriyi
  başlatınca izin kendiliğinden verilir; değilse aşağıdan seçin).
- İki düğme: TV ayarlarından izin (`askGrant`, seçili gelir) ve izinsiz devam (`askSkip`). ◀▶ seçer, Tamam açar.
  Altında ipucu (`askHint`):
  izinsiz devam edilirse oyun Nino'nun içinde gösterilir, bazı TV'lerde siyah kalabilir.
- `askGrant`: TV'nin katman izni ekranı; yoksa uygulama ayrıntıları; o da yoksa ayarın yolu uyarı olarak
  (`permission_settings_missing`).
- `askSkip`: seçim kaydedilir, uygulama içi görünüme geçilir.

### 5.3 Katman

- TV'nin kendi HDMI ekranının üstünde odak almayan, tam ekran şeffaf pencere (kumanda oyuna gider). Ön plan
  servisi bildirimi (`overlay_notice`).
- Yalnız altyazı çizilir; bekleme ekranı ve demo görünmez.
- Bağlantı yoksa (5 sn sonra) sağ üstte küçük kırmızımsı nokta (`#F28B82`, 14 px, %80).
- Nino kumandadan yeniden açılınca katman kapanmaz; ana ekran görünür.
- İzin geri alınmışsa ya da pencere açılamazsa servis kapanır, uygulama açılır.

## 6. Bekleme ekranı demosu (uygulama içi)

- Yağmurlu gece şehri sahnesi: koyu mavi gökyüzü, ay, bulutlar, projektör ışıkları, iki sıra bina silüeti (ışıklı
  pencereler), çatıda pelerinli kahraman silüeti, yağmur, kenarlarda kararma. Hafif kamera kayması.
- Sol üstte cam kart (güvenli alanda: üst 54, sol 96 px): logo, 3 adım (Nino'yu bir göndericide açmak, aynı Wi-Fi
  ağında olmak, gerisini Nino'nun yapması), üç zıplayan mavi nokta + bekleme yazısı, TV'nin adresi.
- Sağ üstte mavi "örnek" rozeti. (Bu ekran artık LG/Samsung'la ortak sayfadadır; metinleri apps/tv-web'dedir.)
- Döngü: oyunun İngilizce satırı alta çıkar, 0,9 sn sonra Türkçesi Nino altyazısı olarak üstüne biner (3 sn),
  0,9 sn ara. 7 satırlık örnek konuşma; iki hızlı satır önceki satırı üstte soluk bırakır.
- Gönderici bağlanınca demo durur.

## 7. Altyazı görünümü

- Yer: altta, ekranın %7 yukarısında, yanlardan %8 boşluk, ortalı. `position: top` gelirse üstte aynı boşlukla.
- Kutu: koyu lacivert yarı saydam zemin `rgba(6,12,30,0.74)`, arka plan bulanıklığı 18 px, köşe 18 px, gölge
  `0 10px 40px rgba(0,0,0,.35)`, iç boşluk 10/26 px. Yazı beyaz, 46 px, kalınlık 600, satır 1,3, üç katlı siyah
  gölge.
- Satırlar dengeli bölünür (uzun yazı iki satırda yakın uzunlukta).
- Hızlı konuşma: yeni satır öncekinden 1,5 sn içinde gelirse önceki satır üstte 37 px, %75 opak kalır; ondan önceki
  %60. 1,5 sn sonra 0,4 sn'de solarak kalkar. En çok üç satır. Aynı cümle tekrar gelirse üste çıkmaz.
- Süre: `durationMs` > 0 ise o süre (en az 1,2 sn); 0 ise `clear` gelene kadar. `clear` geldiğinde yazı okunacak
  kadar (2 sn + 60 ms × harf, en çok 5 sn) görünmediyse o süre dolunca kalkar.
- Bağlantı koparsa yazı hemen silinmez; 6 sn içinde geri gelmezse silinir. Protokol: 20 sn hiç mesaj yoksa ekran
  temizlenir.
- Arapça (sağdan sola) yazının yönü kendiliğinden belirlenir.
- Gelen metin yalnız düz yazıdır (HTML olarak yorumlanmaz).

## 8. Bilgi paneli (uygulama içi, Yeşil/Tamam)

- Sağ üstte (üst 54, sağ 96 px), 480 px, koyu cam kutu. Bağlantı durumuna göre renkli nokta ve başlık (bağlı /
  bekleniyor / koptu), HDMI numarası ve görüntü durumu, son gelen altyazı (yalnız bir altyazı geldikten sonra).
- Tuşla açılınca 8 sn sonra kendiliğinden kapanır.

## 9. Diğer

- Günlük anonim TV modeli bildirimi (eski: rastgele kimlik + marka + model + sürüm, 20 saatte bir). Yeni sürümde
  **yok**; kullanıcıya sorulacak (bkz. ilerleme.md).
- Uygulama arka plandayken altyazı bağlantısı sürer.
- Yazı tipi: TV'nin kendi yazı tipi (Roboto), Arapça için Noto Naskh/Sans Arabic.
