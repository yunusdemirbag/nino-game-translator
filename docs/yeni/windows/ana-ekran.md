# Windows uygulaması: ana pencere ve ana ekran

Bu belge uygulamanın açılışını, tek ana pencereyi (kabuk), yüzen "Nino'ya Sor" robotunu, ana ekranı ve ana ekranın iki
arayüzünü (salon sahnesi, cam anahtar) anlatır. Ortak renkler, yazılar ve bileşenler `tasarim-dili.md`'de; burada
adlarıyla anılır (ör. "ikincil düğme", "kart", accent). Kurulum sihirbazı `kurulum.md`'de. Ölçüler px (WPF aygıttan
bağımsız pikseli). Salon sahnesinde ölçüler **sahne pikseli**dir (görselin 1672 × 941'lik pikseli; sahne sonra
pencereye sığacak kadar küçültülür).

Metinler: anlamı Türkçe ve İngilizce verilir; kendi anahtarını ve cümleni yaz. Bazı Türkçe metinlerin anlamı İngilizce
anahtarından farklıdır; bu durumda ikisi de belirtilir ve **ikisi de korunur** (Türkçe arayüzde Türkçe anlam, diğer
dillerde İngilizce anlam).

Denetleyici (uygulamanın durum ve eylem kaynağı) başka belgede. Burada yalnız ekranın ondan ne okuduğu ve neyi
çağırdığı, kendi sözcüklerimle yazılır.

---

## 1. Açılış sırası

1. Uygulama, yanında olması gereken dosyaları denetler. Eksik varsa eksik listesini gösteren bir hata penceresiyle
   açılmaz (bu denetim uygulamanın kendi türlerine dokunmadan, ayrı bir adımda yapılır ki eksik bir kitaplık denetimi
   çökertmesin).
2. Beklenmeyen hataları yakalayan gözcü kurulur (ekran döküm kipinde kurulmaz, bkz. §12).
3. Asıl açılış (herhangi bir hata, hatayı anlatan pencereyle sonlanır):
   1. Remote Play tanılama günlüğü başlar.
   2. Sağdan sola kuralı kurulur (`tasarim-dili.md` §11), ilk pencereden önce.
   3. Denetleyici gerçek hizmetler, DPAPI'li gizli depo, dosya ayar deposu ve uyku önleyiciyle kurulur; işleri arayüz
      iş parçacığına sıraya koyarak gönderir. Samsung sertifika giriş sayfası gibi sayfalar varsayılan tarayıcıda açılır.
   4. Ayarlardaki görünüm ilk pencere açılmadan uygulanır; Windows teması izlenmeye başlar; ayarlar değişince görünüm
      yeniden uygulanır (`tasarim-dili.md` §6).
   5. Ana pencere kurulur, uygulamanın ana penceresi yapılır, yönü verilir, gösterilir.
4. Ana pencere kapanınca uygulama kapanır.

Mac'teki uygulama açılış animasyonu (pencerenin üstünde oynayan) Windows'ta **yok**; açılış gösterisi yalnız salon
sahnesindeki fişin bir an çekik durup yaylanarak takılmasıdır (§4.9).

## 2. Ana pencere (kabuk)

### 2.1 Pencere

- Başlık "Nino", simge `Nino.ico`.
- Boyut 1040 × 720; en az da 1040 × 720; en çok sınırı yok. Ekranın ortasında açılır. Sistemin normal pencere çerçevesi
  (başlık çubuğu dahil).
- Zemin `background`, ana yazı rengi textPrimary.
- İçerik tek ızgara: altta ekran yeri (kurulum ya da ana ekran), üstünde robot düğmesi ve "çeviri başladı" balonu
  (ızgarada üst üste).

### 2.2 Hangi ekran

- Kurulum adımı "bitti" ise ana ekran, değilse kurulum sihirbazı.
- İlk açılışta zorla kurulur; sonra yalnız "ana ekran mı" değeri değişince yeniden kurulur (adım değişse de sihirbaz
  içinde kalınıyorsa kabuk ekranı yenilemez; sihirbaz kendi içini değiştirir).
- Ana ekrandayken robot **sol altta**: soldan 36, alttan 84. Sihirbazda **sağ altta**: sağdan 44, alttan 100 (Devam
  düğmesinin üst tarafında; kaydırma çubuğuna değmez). Ana ekranda sağ altta salonun fişi ve kablosu durduğu için
  robot sola geçer.
- Sihirbaza geçince balon hemen gizlenir.

### 2.3 "Çeviri başladı" balonu

- Çeviri "kapalı"dan "açık"a geçtiğinde ve kurulum bitmişse gösterilir; 7 sn sonra 0,4 sn'de söner. Çeviri durunca
  0,25 sn'de söner. Yeniden gösterilirse (süre dolmadan) zamanlayıcı baştan başlar; sönme bitince ancak yeniden
  gösterilmediyse gizlenir.
- Yer: sola ve alta yaslı; soldan 36 + 60 + 12 = 108, alttan 84 + 6 = 90 (robotun sağında, dikeyde ortasına yakın).
- Görünüş: tam kapsül (köşe 999), zemin siyah %55 (#8C000000), 1 px beyaz %14 kenar (#24FFFFFF), iç boşluk yatay 20,
  dikey 13. Yazı 17 px kalın beyaz, tek satır. Temadan bağımsız.
- Metin: metin anahtarı `home.toast.translationStarted` (çevirinin açıldığını söyleyen kısa, sevinçli selam).
- Belirme: opaklık 0→1 0,3 sn ve soldan 24 px kayma 0,4 sn, ikisi kübik ease-out. Sönme: ikinci dereceden ease-out.
  Hareketi azalt açıksa anında görünür/gizlenir.
- Tıklamaları engellemez, odak almaz. Ekran okuyucuya metniyle ve "nazik canlı bölge" olarak bildirilir.

### 2.4 "Nino'ya Sor" robot düğmesi

- 60 × 60 düğme; el imleci; sistemin odak işareti yok. İpucu balonu ve ekran okuyucu adı/yardım metni "Nino'ya Sor"
  (EN "Ask Nino").
- İçi: beyaz %96 daire (#F5FFFFFF), 1 px #1F0B1633 kenar, gölge (renk #0B1633, 16 bulanıklık, 3 px aşağı, opaklık
  0,22). Ortasında 44 × 44 robot görseli, üstten 2 px aşağıda, süzülür. Klavye odağında dairenin 4 px dışında 2 px
  accentText halka.
- Üzerine gelince yüz 1,07 katına, basılıyken 0,95 katına büyür/küçülür; bırakınca üstündeyse 1,07, değilse 1. Geçiş
  140 ms, ikinci dereceden eğri. Hareketi azalt açıksa anında.
- Tıklayınca "Nino'ya Sor" penceresi açılır (ayrı belge). Hem ana ekranda hem sihirbazda görünür.
- **Robot görseli:** göz açık ve göz kırpan iki kare. Her 4–5 sn'de bir (4000 ms + 0–999 ms rastgele) 150 ms göz kırpar.
  Süzülme: yükseklik × 0,05 (en az 2) kadar yukarı-aşağı, 1,6 sn'lik yarım tur, sinüs ease-in-out, gidip gelerek sonsuz.
  "Düşünürken" (sohbette cevap beklenirken) 0,45 sn'lik süzülme ve ayrıca −6° ↔ +6° 0,6 sn sallanma; dönme merkezi
  görselin (0,5; 0,9) noktası. Ekrandan kalkınca açık göze döner, hareketler durur. Hareketi azalt açıksa hiç kıpırdamaz,
  göz kırpmaz. Aynalanmaz.

### 2.5 Pencereye bağlı diğer işler

- **Genel kısayollar:** pencerenin tutamacı oluşunca kurulur. Tuş tablosu ayarlardan gelir (varsayılan tuşlar ve
  eşleme ayarlar belgesinde: sayısal tuş takımının 0, 1, 2, 3, 5, 7, 8, 9 tuşları ve Ctrl+Shift+rakam). Kısayollar **yalnız çeviri sürerken**
  ve Ayarlar'da yeni tuş beklenmiyorken tutulur. Çeviri durumu, kısayol beklemesi ya da ayarlar değişince yeniden
  uygulanır. İşler: bölge 1/2/3'ü çevir, altyazıyı duraklat/sürdür, görüntü yenile (anlık görüntü iste), serbest alan
  penceresini aç, ekranı çevir, tıklamalar geçsin aç/kapat.
- **Bilgisayarda gösterilecek çeviriler** küçük, üstte duran bir kutuda çıkar (ayrı belge); denetleyici sonuç verdikçe.
- **Bilgisayardaki altyazı penceresi** pencere açılırken bağlanır (ayrı belge). Kurulamazsa hata günlüğe yazılır,
  kullanıcıya bunu anlatan bir uyarı gösterilir, uygulama onsuz açılır.
- **Uykudan uyanma:** sistem "sürdürüldü" olayında denetleyiciye "sistem uyandı" bildirilir (bağlantılar hemen yenilenir).
- **Kapanırken:** sonuç kutusu bağı, altyazı penceresi, kısayollar, uyku olayı bırakılır; denetleyici kapatılır.

### 2.6 Sahipli pencereler

Ayarlar, Geçmiş ve Hakkında: ana pencerenin üstünde duran ama onu kilitlemeyen (kipsiz), sahibi ana pencere olan tek
pencereler. Aynı türden görünür bir pencere zaten açıksa yenisi açılmaz; küçültülmüşse normale döndürülüp öne getirilir.
Sahibi kapanınca onlar da kapanır.

---

## 3. Ana ekranın iskeleti

Pencerenin içinde, dört yandan 24 boşlukla, yukarıdan aşağı üç parça: başlık, orta alan, alt şerit. (Robot ve balon
kabuktadır, §2.)

### 3.1 Başlık (altında 16 boşluk)

- Solda yatay: 36 × 36 logo kutusu (`tasarim-dili.md` §8.16, köşe 8,1) + 12 boşluk + "Nino" (bölüm başlığı stili, 22
  yarı kalın), dikeyde ortalı.
- Sağda yatay iki **ikincil düğme**, yatay iç boşluk 16:
  1. Geçmiş: simge U+E81C (20 px) + 8 boşluk + "Geçmiş" (EN "History"). Sağında 8 boşluk. İpucu
     "Geçmiş". Tıklayınca Geçmiş penceresi (sahipli, §2.6).
  2. Ayarlar: simge U+E713 (20 px) + 8 + "Ayarlar" (EN "Settings"). İpucu "Ayarlar". Tıklayınca Ayarlar penceresi.
- Mac'teki 36'lık yuvarlak cam simge düğmeleri, sürüm hapı ve güncelleme durumu başlıkta yok.

### 3.2 Alt şerit (en altta)

- Üstünde 12 boşluk; 1 px border renkli üst çizgi; çizginin altında 10 iç boşluk.
- **Sağda** tek bağlantı (çerçevesiz, yalnız yazı, odak almaz, el imleci): "Çeviri" (textSecondary) + boşluk + o an
  kullanılan çeviri kaynağının adı (yarı kalın, textPrimary) + boşluk + "›" (textSecondary). Tıklayınca **Ayarlar
  penceresi** bölüm belirtilmeden açılır (Mac'teki gibi doğrudan Çeviri bölümüne değil; Ayarlar kendi varsayılan bölümüyle açılır). Kaynak adı denetleyiciden gelir:
  GTA 6 tanınınca `home.footer.gta6Active`, değilse seçili motorun adı.
- **Solda** yatay:
  - Kaynak noktası 7 × 7 (sağında 7 boşluk) + yazı: ad (yarı kalın) + boşluk + değer (textSecondary).
    - Ad: oyun penceresi okunuyorsa `home.footer.gameWindow`; yakalama kartı kullanılıyorsa `status.card.defaultName`;
      değilse konsolun adı (denetleyiciden; `status.console.titlePs5` ya da `status.console.titleXbox`).
    - Değer: görüntü kaynağı PS5, konsol Xbox değil, kare kaynağı PS5, çeviri kapalı ve eşli bir PS5 varsa
      `home.footer.ps5Ready` (%@ = PS5'in adı; ad boşsa "PS5"). Yoksa denetleyicinin görüntü kaynağı durum metni.
    - Nokta: görüntü kaynağının tonu (iyi → success, uyarı → warning, boşta → textSecondary).
  - TV noktası 7 × 7 (solunda 22, sağında 7 boşluk) + yazı: "TV" (yarı kalın) + boşluk + değer (textSecondary). El
    imleci.
    - Nokta ve yazı yalnız altyazı TV'de gösteriliyorsa görünür.
    - TV kuruluysa değer TV durum metni, nokta TV'nin tonu. TV yoksa değer `home.footer.connectTv`, nokta warning.
    - Yazıya tıklanınca (fare bırakılınca), TV kurulu değilse kurulum sihirbazının **TV adımı** açılır; kuruluysa bir
      şey olmaz.
- Şerit şunlardan biri değişince yenilenir: ayarlar, kaynağın durum metni/tonu, TV metni/tonu, çeviri açık mı, oturum
  durumu, konsol adı, çeviri kaynağı metni.

### 3.3 Orta alan

- Dikey kaydırılabilir (çubuk gerektiğinde görünür; odak almaz). İçi en az görünen alan kadar yüksek iki satırlı ızgara:
  1. Esnek satır: seçili arayüz (salon ya da cam anahtar), yatay ve dikey ortalı, üst/alt 8 boşluk.
  2. Doğal yükseklikte satır: uyarı kartları yığını, en çok 640 geniş, yatay ortalı (§3.4).
- Arayüz seçimi: ayarlardaki ana ekran biçimi (varsayılan "Salon"; ayar dosyasında `"HomeStyle":"LivingRoom"` ya da
  `"Toggle"`; alanı olmayan eski dosyada Salon). Salonsa ayrıca sahnenin Xbox'lı mı olduğu: ayarlardaki oyun konsolu
  Xbox ise ya da kurulumda Xbox seçildiyse. (biçim, Xbox'lı mı) ikilisi değişince arayüz yeniden kurulur, aynıysa
  dokunulmaz. Ayarlar ya da konsol türü değişince denetlenir.

### 3.4 Uyarı kartları (yukarıdan aşağı)

Hepsi kart (`tasarim-dili.md` §8.9). İlki üstten 8, diğerleri üstten 16 boşlukla. Görünmeyen kart yer kaplamaz.

1. **Yeni sürüm** — yeni bir sürüm biliniyorsa.
   - Başlık: `home.card.update.title` (%@ = sürüm), yarı kalın, accentText, alt satıra kayar.
   - Güncellenirken: üstten 12 boşlukla ilerleme çubuğu (0–1, denetleyicinin ilerlemesi).
   - Hata varsa: üstten 8, danger renkli hata yazısı.
   - Birincil düğme (üstten 12, sola yaslı): uygulama kendini güncelleyebiliyorsa `home.card.update.updateNow`,
     yoksa `translation.model.download`. Güncellenirken devre dışı. Tıklayınca güncellemeyi kur.
2. **Oyun kartı** — yalnız çeviri sürerken.
   - Normal hâl: solda alt alta `home.card.game.label` (küçük etiket) ve 4 boşlukla oyunun adı (karo başlığı,
     sığmazsa "…" ile kısalır; oyun bilinmiyorsa `home.card.game.unknown`). Sağda dikeyde ortalı ikincil düğme
     (yatay iç boşluk 16): oyun bilinmiyorsa `setup.select`, biliniyorsa `common.change`. Tıklayınca
     denetleyiciden oyunu sormasını iste.
   - Soru hâli (denetleyici oyunu soruyorsa; ne zaman kendiliğinden sorduğu denetleyici belgesinde, eskisinde oyun
     yoklaması 2 dakikada birdir): normal satır gizlenir.
     - Üst satır: `reading.gamePicker.title` (karo başlığı, alt satıra kayar), sağda ikincil
       `reading.gamePicker.dontAsk` (yatay iç boşluk 12) → soruyu kapat.
     - İpucu (üstten 8, alttan 12): pakette olmayan satırların oyunun adıyla ortak havuza gittiği, böylece oyunun çevirisinin herkes için daha çabuk tamamlandığı.
     - `home.card.game.search` (küçük etiket, alttan 4) ve altında metin alanı (ekran okuyucu adı da aynı metin).
     - Öneri listesi (üstten 8): denetleyicinin yazılana göre verdiği önerilerden en çok 5'i. Her biri tam genişlikte
       hayalet düğme (üst/alt 2 boşluk); içinde oyun adı (sığmazsa "…"), ad son oynanan oyunsa en sağda
       `home.card.game.lastPlayed` (küçük etiket). Tıklayınca o oyunu seç.
     - Yazılan boş değilse ve hiçbir önerinin normalleştirilmiş adı yazılanınkiyle aynı değilse: ikincil düğme (üstten
       8, yatay iç boşluk 16) `home.card.game.useTyped` (%@ = yazılan) → yazılanı seç. (Normalleştirme kuralı denetleyici/havuz belgesinde.)
     - Metin alanında Enter, yazılan (kırpılmış) boş değilse onu seçer.
     - Her tuşta öneriler yenilenir. Soru hâlinden çıkınca arama alanı boşaltılır.
3. **Güvenlik duvarı kartı** (§3.5).
4. **Çeviri modeli eksik** — model kurulu değilse.
   - Başlık: `home.card.model.title`, yarı kalın, warning.
   - İndirilirken (üstten 12): `home.card.model.downloading` ipucu (alttan 8) ve ilerleme çubuğu.
   - İndirilmiyorken: ikincil `home.card.model.download`, üstten 12 → model indirmeyi başlat.
5. **Dil desteklenmiyor** — çevirmen durumu "desteklenmeyen dil" ise (Tayca, Urduca gibi ücretsiz modeli olmayan
   diller).
   - Başlık: ücretsiz çevirinin bu dili henüz desteklemediği (warning, yarı kalın).
   - İpucu (üstten 8, alttan 12): Ayarlar › Çeviri'den Gemini'nin (ücretsiz) seçilmesi.
   - İkincil `common.settings` → Ayarlar penceresi.
6. **GPU kullanılamadı** — GPU'dan CPU'ya düşüldüyse: tek satır warning yazı, `home.card.gpu.warning`.
7. **Ücretsiz motor açılamadı** — çevirmen durumu "motor başlamadı" ise.
   - Başlık: ücretsiz çeviri motorunun bu bilgisayarda açılamadığı (warning, yarı kalın).
   - İpucu: Ayarlar › Çeviri'den Gemini (ücretsiz) ya da DeepL seçilmesi.
   - İkincil `common.settings`.
8. **Çevrimiçi motor çeviremiyor** — yalnız çeviri sürerken ve denetleyici bir çevrimiçi motor sorunu bildiriyorsa.
   - Başlık: `home.card.online.title` (%@ = motor adı), warning yarı kalın.
   - Altında ipucu (üstten 8): sorunun açıklaması (denetleyici verir; motor ve yerel yapay zekâ sunucusu ayarına göre) +
     boşluk + `home.card.online.fallback`.
9. **Yazı tanıma dili eksik** — oyun dilinin Windows yazı tanıma paketi yoksa.
   - Başlık: oyun dilinin yazı tanıma özelliğinin bu bilgisayarda yüklü olmadığı (warning, yarı kalın).
   - İpucu (üstten 8, alttan 12): bu olmadan Windows'un altyazıyı sistem diliyle okuyup çevirinin anlamsızlaştığı; bir
     kez kurmanın yettiği, Windows'un izin isteyeceği.
   - Alt satıra kayan sıra: ikincil `home.card.ocr.install` (sağ 8, alt 8) ve ikincil
     `home.card.ocr.openLanguageSettings` (alt 8).
   - Kurma düğmesi: düğme devre dışı olur; yönetici izniyle gizli bir PowerShell açılır ve oyun dilinin
     (ayarlardaki kaynak dil kodu) henüz kurulmamış ilk "Language.OCR~~~<kod>-*" Windows yeteneği çevrimiçi kurulur;
     bitmesi beklenir. Çeviri sürüyorsa çeviri durdurulup yeniden başlatılır (yeni paketle okusun). Kullanıcı izni
     reddederse sessizce vazgeçilir. Sonunda düğme yeniden açılır.
   - Dil ayarları düğmesi: Windows'un dil ve bölge ayar sayfası (`ms-settings:regionlanguage`).

Kartlar şunlar değişince yenilenir: çeviri açık mı, çevirmen durumu, model kurulu mu, çevrimiçi sorun, başlatılabilir
mi, başlıyor mu. Model indirme durumu/ilerlemesi, GPU uyarısı ve yazı tanıma eksikliği doğrudan bağlıdır.

### 3.5 Güvenlik duvarı kartı (ana ekranda ve PS5 adımında aynı)

Denetleyicinin güvenlik duvarı önerisi "yok" ise görünmez.

- Başlık (warning, yarı kalın): öneri "izin hazır" ise `firewall.card.titleReady`; değilse
  `firewall.card.titleBlocked`.
- İpucu (üstten 8), ilk uyan:
  1. Ağ "Ortak" profildeyse: `firewall.card.hintPublicNetwork`.
  2. Bekleniyorsa: `firewall.card.hintWaiting`.
  3. Başarısızsa: `firewall.card.hintFailed`.
  4. İzin hazır ve çeviri sürüyorsa: `status.common.reconnecting`.
  5. İzin hazır (çeviri yok): `firewall.card.hintReadyPairing`.
  6. Çeviri sürüyor ve konsol Xbox: `firewall.card.hintXbox`.
  7. Çeviri sürüyor: `firewall.card.hintRunning`.
  8. Diğer (PS5 eşleştirmesi): `firewall.card.hintPairing`.
- İkincil düğme (üstten 12): `firewall.card.allow`;
  öneri "öner", "başarısız" ya da "bekleniyor" iken görünür, "bekleniyor"da devre dışı. Tıklayınca denetleyiciden
  güvenlik duvarı izni iste.

### 3.6 Ana ekranın zamanlı işleri

- Ana ekran açılınca bir kez güncelleme denetlenir.
- Ekrandayken her 5 sn'de denetleyiciden bağlantıları denetlemesi istenir (güvenlik duvarı kartının önerisi bu denetimden
  gelir: çeviri sürerken PS5'e ya da TV'ye bağlanılamıyorsa). Ekrandan kalkınca durur.

---

## 4. Salon sahnesi (birinci arayüz, varsayılan)

Sahnede bir oturma odası çizimi: duvardaki TV'nin altında bir sehpa, yanında konsol ve bir priz. Fişi prize takmak
(tıklayarak ya da sürükleyerek) çeviriyi başlatır: mavi LED'ler yanar, TV'de önce Nino açılışı, sonra altyazı görünür;
fişi çekmek çeviriyi durdurur. Fiş takılı değilken TV ekranında ne yapılacağını anlatan yazı durur ve priz yanıp söner.
TV ekranının sağ üst köşesinde toplam indirme sayısı gösterilir.

### 4.1 İki düzen (sahne pikseli)

| Değer | PS5'li | Xbox'lı |
|---|---|---|
| Görsel | `living-room.png` | `living-room-xbox.png` (1671 geniş, 1672 × 941'e gerilir) |
| TV ekranı (x, y, g, y) | 149, 40, 1151, 595 | 136, 40, 1185, 596 |
| TV çerçevesi | 139, 27, 1171, 621 | 121, 26, 1214, 630 |
| Sehpa | 49, 713, 1502, 160 | 43, 733, 1580, 167 |
| Priz merkezi | 1564, 378 | 1561, 381 |
| Kablonun başı | 1550, 734 | 1572, 722 |
| Görseldeki kablonun son parçası | (1490,706) (1522,706) (1535,709) (1545,716) (1552,727) | yok |
| Kablonun çıkış yönü | (0,5; 0,87) | (1; 0,1) |
| Fişin dinlenme yeri | 1600, 885 | 1646, 912 |
| Sol kaydırma | 72 | 6 |
| Ekran ölçeği | 1151/588 ≈ 1,957 | 1185/588 ≈ 2,015 |

- Sahne 1672 × 941. Prizin kenarı 86. Kablo kalınlığı 8. Kablonun serbest boyu 330. Fişin prize tam dönmüş olduğu
  uzaklık 120. TV içinin tasarlandığı mantıksal ekran genişliği 588 (Mac'teki nokta ölçüsü); **ekran ölçeği** = ekran
  genişliği / 588.
- **Sol kaydırma** = en az 0, 2 × (1672/2 − sehpanın yatay ortası). Sahnenin soluna bu kadar boşluk eklenir ki
  ortalanan tuvalde sehpa pencerenin ortasına gelsin (görselin sağında priz ve konsol var).
- Hangi düzen: ayarlardaki konsol Xbox ya da kurulumda Xbox seçilmişse Xbox'lı.

### 4.2 Ölçekleme

Dış tuval (1672 + kaydırma) × 941; asıl sahne bu tuvalde soldan "kaydırma" kadar içeride. Tuval, en-boy oranı
korunarak alana sığdırılır, **yalnız küçültülür** (asla büyütülmez). Sahnenin tamamı soldan sağa kalır (Arapçada
aynalanmaz). Bütün sahnenin ipucu balonu: `home.livingRoom.tooltip`.

Mac'teki sahnenin altındaki ipucu satırı (fişi çekme / önce PS5'i bağlama ipuçları) Windows'ta **yok**.

### 4.3 Katmanlar (alttan üste, sahne içinde)

1. LED katmanı (§4.6), opaklık 0 ya da 1, tıklanmaz.
2. Priz ışığı (§4.7), tıklanmaz. Salon görselinin altında kalır (priz görsele çizilidir); ışık prizin çevresinden görünür.
3. Salon görseli, 1672 × 941'e gerilerek (oran korunmadan doldurur).
4. TV ekranı yerinde siyah dikdörtgen.
5. TV ekranı yeri (ekran dikdörtgeni boyunda, kenardan taşanı kırpar): bekleme ekranı, açılış ya da canlı ekran (§5).
6. İndirme göstergesi yeri (ekran boyunda, kırpar, tıklanmaz) (§5.4).
7. Prizin tıklama alanı: 120 × 120, prizin merkezinde, saydam, el imleci. Fare bırakılınca çeviriyi aç/kapat (§4.10).
8. Kablo (§4.8).
9. Yalnız Xbox'ta (görselde kablo yok): kablonun başında küçük fiş başı, 14 × 12, köşe 3, #141414, kablonun başına
   ortalı, tıklanmaz.
10. Fiş (§4.8): 120 × 140 saydam zeminli tuval, el imleci; sürüklenir ve tıklanır.

### 4.4 Fişin durumu

- Fiş prizde olmalı = (çeviri açık ya da açılıyor) ve açılış beklemesi bitti (§4.9).
- Bu değer değişince:
  - LED katmanı 800 ms'de yeni opaklığa (1 ya da 0) geçer (hareketi azalt'a bakmaz).
  - Takıldıysa TV açılışı baştan oynayacak (açılış henüz bitmedi sayılır, eski açılış atılır); çekildiyse açılış bitmiş
    sayılır.
  - Priz ışığı animasyonla güncellenir.
  - Süren yay hareketi durdurulur. Açılış gösterisinden geliyorsa, fiş takılıyorsa, hareketi azalt kapalıysa ve
    sürükleme yoksa fiş yaylanarak prize gider; değilse fiş doğrudan yeni yerinde çizilir (normal aç/kapat'ta yay
    yoktur; fiş atlar).
- Her durum değişikliğinde (denetleyicinin herhangi bir bildirimi, arayüz iş parçacığında) LED renkleri ve TV ekranı da
  yenilenir.

### 4.5 Toplam indirme sayısının yenilenmesi

Sahne ekrana gelince bir kez, sonra her 600 sn'de denetleyiciden indirme sayısını yenilemesi istenir; ekrandan kalkınca
durur. Sayı alınamazsa son bilinen sayı kalır; hiç yoksa gösterge çizilmez.

### 4.6 LED ışıkları

Dört bulanık yuvarlak dikdörtgen (WPF bulanıklık yarıçapı Mac'tekinin iki katı yazılır):

| Işık | Boyut | Yer (sol üst) | Köşe | Bulanıklık |
|---|---|---|---|---|
| Geniş (TV arkası) | TV çerçevesi + 40, + 40 | çerçeve − 20, − 20 | 30 | 90 |
| Dar (TV kenarı) | çerçeve + 10, + 10 | çerçeve − 5, − 5 | 10 | 24 |
| Sehpa altı | sehpa genişliği − 60, 40 yüksek | sehpa x + 30, sehpanın altı − 14 | 20 | 50 |
| İnce şerit | sehpa genişliği − 90, 8 yüksek | sehpa x + 45, sehpanın altı − 4 | 4 | 8 |

Renkler:
- Her zamanki: geniş ve sehpa altı #1F5CFF; dar #4D8CFF; şerit #73A6FF.
- Havuz öncelikli oyun tanınınca (GTA 6; denetleyici söyler): soldan sağa üç duraklı (0, 0,5, 1) degradeler. Geniş ve
  sehpa altı: (255, 61, 158) → (189, 128, 245) → (77, 199, 255). Dar ve şerit: (255, 133, 199) → (214, 179, 255) →
  (148, 224, 255). Boyutlar aynı, yalnız dolgu değişir. Renk ancak bu değer değişince yeniden atanır.

### 4.7 Priz ışığı

İki katman, prizin merkezine ortalı:
- Geniş: (86 + 26) = 112 kare, köşe 16, (77, 168, 255), bulanıklık 36.
- Dar: 94 kare, köşe 12, (158, 214, 255), bulanıklık 10.

Davranış:
- Fiş çıkıkken nabız: geniş 0,3 ↔ 0,95, dar 0,45 ↔ 1; 0,95 sn sinüs ease-in-out, gidip gelerek sonsuz. Hareketi azalt
  açıksa nabız yok: geniş 0,95, dar 1 sabit.
- Bütün ışık katmanı: fiş takılıysa 0'a, değilse 1'e; animasyonlu güncellemede ve hareketi azalt kapalıysa 500 ms'de,
  değilse anında. Söndükten sonra (fiş takılı kaldıysa) nabızlar durdurulur.
- İlk kurulumda animasyonsuz.

### 4.8 Fiş ve kablo

**Fişin yeri:** (takılıysa priz, değilse dinlenme yeri) + sürükleme farkı. Fiş tuvali 120 × 140; tuvalin (60, 70)
noktası fişin yerine gelir.

**Oturmuş fiş** (takılı ve sürükleme yok): tuvalde (31, 41)'de 58 × 58 yuvarlak kapak; dolgu sol üstten sağ alta
#3D3D3D → #0A0A0A; 1,5 px beyaz %18 (#2EFFFFFF) kenar; gölge 12 bulanıklık, 4 px, sağ alta (varsayılan yön), opaklık
0,45.

**Çıkık fiş:** parçalar bir grupta, grup fişin dönüş açısı kadar (60, 70) çevresinde döner; tıklama alanı dönmez:
- Kablo boğazı: 13 × 14, köşe 5, #0F0F0F, (53,5; 26).
- Gövde: 36 × 50, köşe 9, soldan sağa #383838 → #0A0A0A, 1 px beyaz %14 (#24FFFFFF) kenar, (42, 40).
- İki uç: 6 × 24, köşe 3, soldan sağa #EBEBEB → #999999, x = 47 ve 67, y = 90.
- Gölge dönmeyen dış katmanda: 8 bulanıklık, 3 px, tam aşağı, opaklık 0,3 (hep aşağı düşer).

**Dönüş açısı** (radyan; 0 = uçlar aşağı, saat yönü artı): d0 = prizle dinlenme yeri arası, d = prizle fiş arası.
d0 > 120 ve d > 1 değilse 0. Değilse t = sınırla((d0 − d)/(d0 − 120), 0, 1), yumuşak t' = t²(3 − 2t), hedef açı =
atan2(−(prizX − fişX), prizY − fişY); açı = t' × hedef. Uçların yönü (−sin θ, cos θ). Çizimde dereceye çevrilir.

**Kablo:** #0F0F0F, kalınlık 8, uçları ve dönüşleri yuvarlak; gölge 6 bulanıklık, 2 px aşağı, opaklık 0,25;
tıklanmaz. Yol: "baş noktaları"nın ilkinden başlar, diğerlerine düz çizgiyle gider, son baş noktasından iki denetim
noktalı eğriyle uca varır. Baş noktaları = görseldeki kablonun son parçası (PS5), yoksa yalnız kablonun başı (Xbox).
Başlangıç s = son baş noktası.
- Oturmuşken: uç = (fişX, fişY + 30); d1 = s + çıkış × 90; d2 = (uçX + 10, uçY + 170).
- Çıkıkken: u = uçların yönü; fişin arkası a = fiş − u × 40; sarkma = en az 0, (330 − |a − s|) × 0,45;
  d1 = s + çıkış × 70 + (0, sarkma); d2 = a − u × 80 + (0, sarkma); uç = a.

**Testlerden örnekler** (yeni testlere aynen):
- PS5, fiş dinlenirken (1600, 885): baş noktaları yukarıdaki beş nokta; uç (1600, 845); d1.x = 1552 + 35, d1.y = 727 +
  0,87×70 + sarkma (sarkma > 0); d2 = (1600, 845 − 80 + sarkma).
- Xbox, dinlenirken (1646, 912): baş [(1572, 722)]; uç (1646, 872); d1 = (1642, 729 + sarkma).
- Oturmuş PS5: uç (1564, 408), d1 (1597, 805,3), d2 (1574, 578), baş noktası sayısı 5. Oturmuş Xbox: uç (1561, 411),
  d1 (1662, 731).
- Fiş prizin 100 altında: uç = (fişX, fişY + 40), d2 = (fişX, fişY + 120 + sarkma). Priz − 300 solunda (gergin): sarkma
  0, d1.y = s.y + çıkış.y × 70.
- Dönüş: dinlenme yerinde 0; (1640, 930)'da (uzaklaşınca) 0; (1564, 470)'te uçlar ≈ (0, −1); (1460, 378)'de −sin θ ≈ 1;
  (1585, 640)'ta |θ| 0,2 ile π − 0,2 arasında. Her iki düzende prizden (−60, +80) uzaklıktaki fişin uçları tam prize
  bakar (6 hane).
- Kaydırma PS5 72, Xbox 6; ölçek 1151/588 ve 1185/588.

### 4.9 Açılış gösterisi

Uygulama her açıldığında **bir kez** (süreç boyunca tek bayrak): sahne ekrana gelince fiş 900 ms (hareketi azalt açıksa
1 ms) çekik bekler, çeviri kendiliğinden başlamış olsa da. Sonra durum yenilenir ve fiş takılıysa prize yaylanarak gider.
Sahne sonradan yeniden kurulunca (ayarlardan dönüş, konsol değişimi) gösteri yeniden oynamaz.

**Yay:** başlangıç farkı f = dinlenme − priz; tepki 0,55 sn, sönüm 0,7, süre 0,9 sn. ω = 2π/0,55, ωd = ω√(1 − 0,49).
Her ~16 ms'de kalan = e^(−0,7ωt)·(cos ωd·t + 0,7ω/ωd·sin ωd·t); fark = f × kalan; fiş ve kablo çizilir. t ≥ 0,9'da
durur, fark sıfırlanır, oturmuş fiş çizilir. Yol boyunca fiş gövdesiyle (çıkık çizimle) görünür.

### 4.10 Tıklama ve sürükleme

- Fişe basılınca: süren yay durur, başlangıç noktası alınır, fark sıfırlanır, fare yakalanır.
- Basılıyken hareket: fark = (şimdiki − başlangıç) / ölçek; ölçek = tuvalin ekrandaki genişliği / (1672 + kaydırma)
  (0 ise 1). Fiş ve kablo çizilir.
- Bırakınca: yakalama bırakılır; bitiş = (takılıysa priz, değilse dinlenme) + fark; fark sıfırlanır; fiş eski yerinde
  çizilir.
  - Fark < 6 ise tıklama sayılır → aç/kapat.
  - Değilse "prize yakın" = |bitiş − priz| < 140. Bu, fişin şimdiki durumundan farklıysa aç/kapat; aynıysa fiş geri
    yerine döner.
- Prize tıklamak da (120 × 120 alan) aç/kapat'tır.

### 4.11 Aç/kapat (iki arayüzde ortak)

- Çeviri açılıyorsa: açılış bitene kadar 50 ms aralıkla beklenir; bitince açıksa durdurulur (hazırlık sırasında verilen
  kapatma kaybolmaz).
- Açıksa durdur. Başlatılabiliyorsa başlat. Başlatılamıyorsa kurulum sihirbazını aç: yakalama kartıyla altyazı TV'ye
  gidiyorsa kurulmamış tek şey TV olabilir → **TV adımı**; değilse **konsol adımı**.
- Beklenmeyen hata: günlüğe yazılır, hatayı anlatan uyarı gösterilir.

---

## 5. TV ekranının içi (salon ve cam anahtarda ortak)

### 5.1 Hangi ekran (salon)

- Fiş takılı değil → bekleme ekranı.
- Takılı, açılış bitmedi → Nino açılışı (§5.3; her takışta yeniden kurulur).
- Takılı, açılış bitti → canlı ekran (§5.2); satır yazılır, gün batımı fonu havuz öncelikli oyunda görünür.
- Aynı ekran zaten gösteriliyorsa değiştirilmez.

**Bekleme ekranı:** siyah zemin; ortada `home.tv.idle`, **arayüz dilinin kurallarıyla büyük harfe** çevrilmiş (Türkçede "i" → "İ"); yazı "Consolas, Courier New", yarı
kalın, 13 × ekran ölçeği, beyaz %40 (#66FFFFFF), alt satıra kayar, ortalı, yatayda 40 × ölçek kenar boşluğu.

### 5.2 Canlı ekran

Boyut verilir (salonda ekran dikdörtgeni, cam anahtarda 580 × 326); h = yükseklik, g = genişlik, f = yazı boyu
(salonda 46, cam anahtarda 30).

- Zemin: sol üstten sağ alta #171F3D → #26172E.
- (Salonda) en arkada gün batımı fonu: yukarıdan aşağı (26, 20, 87) 0'da, (117, 41, 158) 0,40'ta, (237, 74, 153)
  0,74'te, (255, 140, 122) 1'de; üstünde siyah #47000000 (≈ %28). Güneş, bulanıklık yok. Nino'nun kendi çizimi; oyunun
  görseli kullanılmaz. Yalnız havuz öncelikli oyunda (GTA 6) görünür.
- CANLI rozeti: sol üstte h × 0,05 boşlukla; zemin siyah %40, köşe h × 0,04, iç boşluk yatay h × 0,03, dikey h × 0,012.
  İçinde h × 0,025'lik bayrak kırmızısı nokta (sağında h × 0,02) ve `home.tv.live`, beyaz kalın, h × 0,035. Nokta
  1 sn'de opaklık 1 → 0,3, gidip gelerek sonsuz (hareketi azalt'a bakmaz).
- Satır: altta ortalı kutu; kutunun köşesi f × 0,2, iç boşluk yatay f × 0,5 dikey f × 0,2, kenar boşluğu yanlarda
  g × 0,06, altta h × 0,08; en çok g × 0,88 geniş. İçinde yazı f boyunda, alt satıra kayar, ortalı.
- **Satır metni:** oturum "yayın" aşamasında değilse kaynağın durum metni (altyazı değil). Yayındaysa ve son
  çeviri boşsa `home.tv.waitingNextSubtitle` (altyazı değil). Değilse son çeviri
  (altyazı).
- **Satırın yazılması:** gösterilecek (sağdan sola işaretli) metin aynıysa dokunulmaz. Değilse metin ve yönü
  (`tasarim-dili.md` §11) yazılır. Altyazıysa yazı beyaz, yarı kalın, kutu zemini siyah #B0000000 (≈ %69); değilse
  yazı beyaz %67 (#AAFFFFFF), normal, kutu saydam. Her değişimde kutu 300 ms'de 0 → 1 belirir.

### 5.3 Nino açılışı (salon, fiş takılınca)

Ölçüler ölçeksiz sahne pikselidir (ekran ölçeği uygulanmaz).

- Zemin: merkezden dışa ışınsal #10265C → #040816.
- Işık: 360 × 360 daire, #551F5CFF (LED mavisi %33), bulanıklık 80; dikeyde ortalı, alttan 120 boşluk (yukarı kayık).
- Logo: `logo.png` 230 × 230, dikeyde ortalı, alttan 120; ölçek merkezden 0,72 → 1, 900 ms, geri yaylanan eğri
  (genlik 0,3, ease-out); opaklık 0 → 1, 700 ms.
- Yazılar: dikeyde ortalı, üstten 300 boşluk; "Nino" 64 kalın beyaz, ortalı; altında `home.tv.splashTagline`, 26, beyaz %67, ortalı. Opaklık 0 → 1, 600 ms, 650 ms gecikmeyle.
- Çıkış: bütün açılış 2350 ms gecikmeyle 450 ms'de 1 → 0. Bitince, hâlâ aynı açılış gösteriliyorsa açılış bitti sayılır
  ve canlı ekran gösterilir (toplam ≈ 2,8 sn).
- Hareketi azalt'a bakmaz.

### 5.4 Toplam indirme göstergesi (salon)

- Yer: TV ekranının sağ üstü, üstten ve sağdan 18 × ölçek; dikey yığın, sağa yaslı; tıklanmaz.
- Başlık: `home.tv.totalDownloads`, arayüz diliyle büyük harf; 11 × ölçek, beyaz; çerçeve kalınlığı
  1 × ölçek.
- Sayı: binlik ayırıcılı tamsayı (**sistemin bölge biçimiyle**, arayüz dilinin değil; ör. 3439 → "3.439" ya da
  "3,439"); 27 × ölçek, indirme yeşili #7BE87B; üstten 1 × ölçek; çerçeve 1,5 × ölçek.
- Yazı tipi: sistemde "Impact" varsa o, normal ağırlık (kendisi kalın); yoksa "Segoe UI", en kalın (Black). Liste
  okunamazsa ikincisi. Oyunun logosu ya da yazı tipi kullanılmaz.
- Siyah çerçeve (w = çerçeve kalınlığı, ölçek s): yazının siyah kopyaları; önce derinlik (dd = w + s): dx ∈ {−w, 0, w}
  için (dx, w + dd) ve (dx, w + dd/2)'de siyah %90; sonra sekiz yöne (±w, 0, ±w kombinasyonları, (0,0) hariç) tam siyah;
  en üstte renkli yazı.
- Eğim: başlıkta Arap harfi yoksa bütün gösterge x' = x − 0,12·y + 3·s dönüşümüyle eğilir; Arap harfli başlıkta eğim yok.
  (Mac'teki harf aralığı 0,8 Windows'ta yok.)
- Görünürlük: açılış beklemesinde gizli; fiş takılı değilken ya da TV açılışı bittikten sonra görünür; açılış
  sırasında gizli. Sayı yoksa hiç çizilmez.
- Gösterge, sayı ya da "canlı ekranda mı" değişince yeniden kurulur. **Sayma gösterisi**: canlı ekrana yeni girilmişse
  (ya da sayı canlı ekrandayken ilk kez gelmişse), hareketi azalt kapalıysa ve sayı > 3 ise:
  1. Rakamlar sabit genişlikli yapılır. 1, 2, 3 tek tek, her biri 280 ms.
  2. Sonra 1550 ms boyunca ~16 ms'de bir: p = (geçen − 840)/1550 (en çok 1); gösterilen = en büyüğü(3,
     yuvarla(p^2,6 × toplam)). Bütün katmanlar (çerçeve, derinlik, renkli yazı) birlikte güncellenir.
  3. p = 1'de toplam gösterilir ve vuruş: sayı sağ-orta noktasından büyür; ölçek 220 ms'de 1,32 (geri yaylanan, genlik
     0,5, ease-out), 260 ms'ye kadar 1,32, 710 ms'de 1 (geri yaylanan, genlik 0,3, ease-out). Aynı anda yeşil ışık
     (gölge 0 uzaklık, bulanıklık 28): opaklık 220 ms'de 0,95 (ikinci derece ease-out), 260'a kadar 0,95, 710'da 0.
     Bitince ışık katmanı kaldırılır. Animasyonlar bitince başlangıç değerine döner.
  - Gösterge ekrandan kalkarsa sayaç durur.

### 5.5 Kaynak sayısının biçimi (testlerden)

Sunucu cevabı `{"ok":true,"downloads":3439}` → 3439. `{"ok":true}`, `{"downloads":0}`, bozuk metin,
`{"downloads":"3439"}`, `{"downloads":-5}`, `{"downloads":12.5}`, `[3439]`, boş → sayı yok. Ayrıntı ve saklama
(`3439` düz metin dosyası) havuz belgesinde.

---

## 6. Cam anahtar (ikinci arayüz)

Ortada cam görünümlü bir anahtar. Kapalıyken soğuk mavi-gri; açılınca küre sağ uca gider ve iz bayrak kırmızısı olur,
kürenin içinde ay-yıldız belirir; çeviri sürerken üst tarafta canlı TV durur. Tamamı soldan sağa kalır. Dikey yığın, yatay ve
dikey ortalı.

### 6.1 Canlı TV (yalnız "açık"ken görünür; altında 24 boşluk)

- Çerçeve: #0D0D12, köşe 18, iç boşluk 7. İçinde köşe 12 istenmiş, kırpılan bir kap ve onun içinde 580 × 326 canlı ekran
  (§5.2, yazı 30). Not: WPF'te kırpma dikdörtgen kaldığı için ekranın köşeleri pratikte keskindir; aynısı korunabilir.
  Gün batımı fonu ve indirme göstergesi burada yok.
- Altında ayak: 34 × 14 #1F1F26 boyun, altında 150 × 6 köşe 3 #1F1F26 taban (ortalı).
- Altında kaynak satırı: son altyazının İngilizce aslı; italik, ortalı, üstten 10, tek satır "…" ile kısalır, en çok 580,
  textSecondary.

### 6.2 Anahtar (400 × 92, ortalı, el imleci)

Katmanlar (alttan üste):
1. Taban: köşe 46; yukarıdan aşağı #788CB3 → #4D5C85; 1 px beyaz %45 (#73FFFFFF) kenar; gölge renk #4D5C85,
   bulanıklık 30, 8 px sağ alta, opaklık 0,3.
2. Kırmızı iz: köşe 46; yukarıdan aşağı #E30A17 → #A80514; opaklık 0 (kapalı) / 1 (açık); gölge bayrak kırmızısı,
   bulanıklık 40, 6 px, opaklık 0,6.
3. Parlaklık: köşe 46, 3 px içeride; yukarıdan aşağı beyaz %35 (#59FFFFFF) → saydam; tıklanmaz.
4. Kapalı yazısı: sağa yaslı, sağdan 30, dikeyde ortalı, tıklanmaz; başlık 22 yarı kalın beyaz, alt yazı 12 beyaz %80
   (#CCFFFFFF), ikisi sağa yaslı.
5. Açık yazısı: sola yaslı, soldan 34, dikeyde ortalı, opaklık 0 başlar, tıklanmaz; `home.toggle.turkish` 26 kalın
   beyaz, altında `home.toggle.subtitlesOn` 12 beyaz %85 (#D9FFFFFF).
6. Küre: 116 × 116, sola yaslı, soldan −12 (iz yüksekliğinden taşan payın yarısı), dikeyde ortalı, yatay kaydırmalı,
   tıklanmaz. İçi (ortalı, alttan üste):
   - Renkli disk: kürenin %62'si (≈ 71,9); kapalı #5C6E99, açık bayrak kırmızısı (renk anında değişir).
   - Güç simgesi U+E7E8, 30 px, beyaz (kapalıda görünür).
   - Ay-yıldız: kürenin %45'i (≈ 52,2) kare, opaklık 0 başlar (§6.3).
   - Buzlu cam: tam daire, beyaz %19 (#30FFFFFF).
   - Kenar ışığı: tam daire çizgisi 2 px, sol üstten sağ alta beyaz %95 (#F2FFFFFF) → beyaz %38 (#60FFFFFF).
   - Parlama: genişlik kürenin %55'i, yükseklik %28'i, sol üstte (soldan K × 0,1, üstten K × 0,08); yukarıdan aşağı beyaz
     %65 (#A6FFFFFF) → saydam.
   - Kürenin gölgesi: bulanıklık 18, 8 px sağ alta, opaklık 0,2.
- Anahtarın herhangi bir yerine tıklayıp bırakınca aç/kapat (§4.11).

### 6.3 Ay-yıldız çizimi (boy b, kare)

- Ay: merkezi (0,42b; b/2), yarıçapı r = 0,42b olan beyaz daireden, merkezi (0,42b + 0,32r; b/2), yarıçapı 0,8r olan
  dairenin çıkarılmasıyla oluşan hilal.
- Yıldız: merkez (0,8b; b/2), dış yarıçap 0,17b, iç yarıçap dış × 0,382; on nokta, i. nokta açısı π + i·π/5 (ilk köşe
  sola, aya bakar), çift i dış, tek i iç yarıçap; beyaz.

### 6.4 Açıklama (yalnız "kapalı"yken)

`home.toggle.description` (Nino'nun ne yaptığını anlatan tek cümle); textSecondary, ortalı, alt satıra kayar, en çok 440 geniş, üstten 28.

### 6.5 Durum ve geçiş

- "Açık" = çeviri açık ya da açılıyor. Denetleyicinin her bildiriminde yeniden uygulanır; yalnız açık/kapalı değiştiyse
  animasyonlu.
- Geçiş 550 ms (animasyonsuzda 0): küre 0 ↔ 308 px (400 − 92) kayar, geri yaylanan eğri (genlik 0,25, ease-out);
  kırmızı iz, açık yazısı, ay-yıldız 0 ↔ 1; kapalı yazısı ve güç simgesi tersi. Hareketi azalt'a bakmaz.
- Kapalı yazısının başlığı: açılıyorsa `status.common.connecting`, başlatılabiliyorsa `home.toggle.turnOn`, değilse
  `home.toggle.connectPs5`. Alt yazı: başlatılabiliyor ya da açılıyorsa `home.toggle.turkishSubtitles`, değilse
  `home.toggle.tapToSetUp`. (Not: "açılıyor" da "açık" sayıldığı için bağlanıyor başlığı pratikte görünmez; eskisi böyle.)
- Açıkken canlı TV görünür, açıklama gizlenir; satır yazılır (§5.2) ve kaynak satırına son İngilizce kaynak konur.

---

## 7. Ana ekranın okuduğu durumlar ve çağırdığı eylemler

**Okunanlar:** ayarlar (ana ekran biçimi, konsol, görüntü/kare kaynağı, çevrimiçi motor, yerel yapay zekâ sunucusu,
kaynak dil, kısayollar, görünüm); kurulum adımı; çeviri açık mı / açılıyor mu / başlatılabilir mi; konsol türü Xbox mu;
oyun penceresi mi / yakalama kartı mı kullanılıyor; altyazı TV'de mi gösteriliyor; TV kurulu mu; eşli PS5 (adıyla);
görüntü kaynağı durum metni ve tonu; TV durum metni ve tonu; konsolun adı; oturum aşaması; son çeviri; son İngilizce
kaynak; havuz öncelikli oyun tanındı mı; toplam indirme sayısı; çeviri kaynağı metni; güncelleme sürümü / güncelleniyor
mu / ilerleme / hata / kendini güncelleyebilir mi; oynanan oyun, son oynanan oyun, oyun soruluyor mu, oyun önerileri;
güvenlik duvarı önerisi; model kurulu mu / iniyor mu / ilerleme; çevirmen durumu; çevrimiçi sorun ve açıklaması; GPU
düşüş uyarısı; yazı tanıma eksik mi; kısayol beklemesi.

**Çağrılanlar:** başlat, durdur; kurulum adımını değiştir (TV ya da konsol adımı); güncellemeyi denetle / kur; model
indirmeyi başlat; oyunu sor / seç / soruyu kapat; güvenlik duvarı izni iste; bağlantıları denetle; indirme sayısını
yenile; bölge çevir, ekranı çevir, altyazıyı duraklat, anlık görüntü iste, tıklama geçirme aç/kapat; sistem uyandı.

## 8. Windows'a özgü (platform) kısımlar

| Yetenek | Ne için | Ayar |
|---|---|---|
| Genel kısayol kaydı (pencere tutamacıyla) | Çeviri sürerken kısayollar | yalnız çeviri sürerken ve kısayol beklenmiyorken |
| Güç olayı "sürdürüldü" | Uykudan uyanınca bağlantıları yenile | |
| PowerShell, yönetici izniyle ("runas"), gizli pencere | Yazı tanıma paketini kurmak | profilsiz; "Language.OCR~~~<dil>-*" yeteneğinin kurulmamış ilkini çevrimiçi ekle |
| `ms-settings:regionlanguage` | Dil ayarları | kabukla açılır |
| Fare yakalama | Fişi sürüklerken | bırakınca serbest |
| Bulanıklık ve gölge efektleri | LED, priz ışığı, fiş, kablo, anahtar, robot | WPF bulanıklık yarıçapı Mac'in iki katı |

## 9. Açık/koyu tema ve sağdan sola

- Tema yalnız kabuk ve iskeleti (zemin, başlık, düğmeler, şerit, kartlar, robotun odak halkası) etkiler. Salon sahnesi,
  cam anahtar, TV içi, robot dairesi ve balon temadan bağımsızdır (aynı renkler).
- Sağdan sola arayüzde iskelet (başlık, şerit, kartlar) aynalanır; salon, cam anahtar, robot görseli ve TV satırının
  yönü aynalanmaz (`tasarim-dili.md` §11). Robotun ve balonun "sol/sağ" yerleşimi pencerenin akış yönüne göredir
  (sağdan sola düzende görünürde yer değiştirir).

## 10. Mac'te olup Windows ana ekranında olmayanlar

Uygulama menüsü ve menü çubuğu öğesi; pencere açılış animasyonu; başlıkta yuvarlak simge düğmeleri ve sürüm/güncelleme
hapı (Windows'ta güncelleme bir kart); sahnenin altındaki ipucu satırı; kullanıcının kendi oyun kapak görseli; indirme
başlığının harf aralığı; alt şeritteki "Çeviri" bağlantısının doğrudan Çeviri bölümünü açması; Xbox bağlantı
yardımcısı düğmesi. Windows'ta olup Mac ana ekranında olmayanlar: model / dil / motor / çevrimiçi motor / GPU / yazı
tanıma / güvenlik duvarı uyarı kartları, oynanan oyun kartı (Mac'te de var ama Windows'ta kart biçiminde).

## 11. Eski ile karşılaştırma aracı (ekran dökümü)

Eski uygulama `Nino.exe --render-screens <klasör>` ile açılınca pencere göstermeden bütün ekranları PNG'ye döküp kapanır.
"Pencere pencere aynı" denetimi için yenisinde de aynı araç olmalı (aynı dosya adlarıyla), iki çıktı yan yana
karşılaştırılır:

- Önce açık, sonra koyu tema; sonek `acik` / `koyu`.
- Kurulumun her adımı (bitti hariç): `adim-<sıra>-<AdımınİngilizceAdı>-<sonek>.png`, sıra 1'den (Welcome, SecondAccount,
  PsnLogin, Console, Tv, Translation, Test, BetterTranslation), 1040 × 720.
- `ana-<sonek>.png`: ana ekran, 1040 × 720. `pencere-<sonek>.png`: gerçek ana pencerenin içeriği (simgesiyle), 1040 ×
  720. `ayarlar-<sonek>.png`: 1000 × 720. `hakkinda-<sonek>.png`: 460 × 640.
- Görüntüler 2 kat çözünürlükte (192 dpi) çizilir; zemine pencere zemini ve ana yazı rengi konur; ekran dışında
  (−10000, −10000) çerçevesiz, görev çubuğunda görünmeyen bir pencerede gösterilip 600 ms beklenir (yüklenirken
  başlayan aramalar yansısın).
- Sahte hizmetlerle çalışır: bulunan PS5 "PS5-123" @ 192.168.1.20, bulunan TV "[LG] webOS TV" @ 192.168.1.30, vb.
  Kurulum "bitti" olarak saklanmışsa ana ekran.
- Bir ekranın hatası diğerlerini durdurmaz; hatalar klasördeki `errors.txt`'ye eklenir.
