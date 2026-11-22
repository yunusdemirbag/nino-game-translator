# Nino Android: çeviri servisi ve yan özellikler (davranış tarifi)

Bu belge eski Android uygulamasının arka plan çeviri servisini ve onun çevresindeki yan özellikleri **davranış olarak**
anlatır. Yeni uygulama temiz-oda yöntemiyle baştan yazılacak; burada kodun yapısı değil, kullanıcının ve dış
dünyanın (TV, PS5, Xbox, sunucu) gördüğü davranış vardır. Adresler, istek gövdeleri, olay adları ve eşikler
davranışın parçasıdır. Gizli anahtar değerleri yazılmamıştır.

Kısaltmalar: **TV uygulaması** = TV'de çalışan Nino (altyazıyı gösterir). **Havuz sunucusu** = Nino'nun kendi sunucusu
(çeviri havuzu, sorun bildirimi, yardımcı). **Klip** = yalnız geliştirme yapısında PS5 yerine oynatılan kayıtlı video.

---

## 1. Çeviri servisinin yaşam döngüsü

### 1.1 Başlatma

Kullanıcı ana ekranda "çeviriyi başlat"a basınca sırayla şunlar olur:

1. Görüntü kaynağı yakalama kartıysa ve kamera izni yoksa önce kamera izni istenir. İzin verilmezse servis başlamaz;
   ana ekranda `capture_no_permission` uyarısı çıkar.
2. Android 13 ve üstünde bildirim izni yoksa istenir. Cevap beklenmez: servis yine başlar (izin verilmezse bildirim
   görünmez ama servis çalışır).
3. Ön plan servisi başlatılır.
4. Altyazının hedefi "bu telefon" ise ayrıca yatay, tam ekran telefon altyazı ekranı açılır.

Servis ilk komutu alınca:

- Bu oturumun görüntü kaynağı **bir kez** belirlenir: klip (geliştirme yapısında kuruluysa her şeyden önce gelir),
  yakalama kartı, Xbox ya da PS5 Remote Play. Oturum boyunca değişmez.
- Hemen ön plana geçer (bildirim, bkz. 1.3).
- Ön koşullar denetlenir. Biri eksikse servis hata metnini ana ekrana yazar ve kendini kapatır:
  - Xbox seçili ama Microsoft girişi yok ya da Xbox seçilmemiş: `error_xbox_sign_in`
  - PS5 yolu, ama PSN hesap kimliği ya da PS5 eşlemesi yok: `error_not_paired`
  - PS5 yolu, ama Remote Play yerel kitaplığı bu cihazda yüklenemedi: `error_native`
  - Klip ve yakalama kartında PSN, eşleme ve yerel kitaplık gerekmez.
- Kilitler alınır (bkz. 1.4), "çeviri sürüyor" bayrağı kalıcı ayarlara yazılır (bkz. 7A, önceki kapanış raporu).
- Durum `phase_preparing` olur, başlama anı kaydedilir, sağlık ölçümü sıfırlanır, sağlık izleme başlar.
- Telemetri: oturum başlangıç olayı (bkz. 9).
- Ağır kurulum (paketlerin açılması, çeviri modeli, altyazı sunucusu) **ana iş parçacığında yapılmaz**: zayıf
  telefonda "Nino yanıt vermiyor" uyarısı çıkıyordu. Kurulumda yakalanmayan her hata (bellek yetmemesi dahil)
  yakalanır: servis durdurulmuyorsa `error_native` yazılır ve servis kapanır;
  kurulum sürerken kullanıcı durdurduysa yalnız o ana kadar kurulanlar kapatılır.

Kurulumun sırası:

1. Oyun paketleri kitaplığı hazırlanır (uygulamayla gelenler + sunucudan inenler + kullanıcının içe aktardıkları;
   aynı kimlikte indirilen kazanır). Paketler yalnız Türkçe çeviride kullanılır. Ayardan kapalıysa hiç açılmaz.
   Paketleri açarken bellek yetmezse paketsiz sürülür; uygulama kapanmaz, PS5 bağlantısı kopmaz.
2. Çeviri dili oturum başında bir kez okunur. Türkçede terim sözlüğü yüklenir, öbür dillerde kullanılmaz.
3. Ücretsiz cihaz içi çevirmen (ML Kit) her zaman kurulur; kullanıcı anahtarlı bir motor seçtiyse (DeepL, Gemini,
   OpenAI, Claude) o önce gelir, hata verirse cihaz içi çevirmene düşülür. DeepL hedef dili desteklemiyorsa (Hintçe,
   Urduca…) motor yok sayılır, cihaz içi çevirmen çalışır.
4. Yerel altyazı sunucusu (TV'nin bağlandığı SSE sunucusu, port **8787**) açılır ve geçerli yazı stili gönderilir.
   Port kullanımdaysa `error_port` (port 8787) yazılır, servis sürer.
5. Ortak havuz ve çeviri havuzu kurulur (bkz. 3.5).
6. Ek alan, oyun içi telefon ve harita kartı okuyucuları kurulur (bkz. 3.6).
7. Ücretsiz modelin ilk indirilmesi başlar (~30 MB). Toplam 6 deneme; denemeler arası 10, 20, 30, 40, 50 sn.
   2. denemeden itibaren başarısızlıkta "Ücretsiz çeviri modeli inmedi. İnternetinizin çalıştığından emin olun." görünür; model inince uyarı kalkar. Paketler modeli beklemeden çalışır.
8. Görüntü kaynağı açılır. Bu sırada kullanıcı servisi durdurduysa kaynak hiç başlatılmaz.
9. TV'ye "çeviri başladı" olayı gönderilir (TV kısa bir balon gösterir; sonradan bağlanan TV de kısa süre içinde
   görür). Telefonda da 7 sn "Çeviri başladı" balonu için an kaydedilir.
10. Her 2 sn'de bir kaynaktan gelen toplam kare sayısı durum bilgisine ve sağlık ölçümüne yazılır.

### 1.2 Durdurma

- Bildirimdeki "Çeviriyi durdurun" düğmesi ya da uygulamadaki durdurma, servise "durdur" komutu gönderir; servis
  kendini kapatır. Servis yeniden başlatılmaz (sistem öldürürse geri gelmez; "yapışkan" değildir).
- Kapanırken: "çeviri sürüyor" bayrağı silinir, son oturum süresi kaydedilir, oturum bitiş olayı gönderilir,
  bütün parçalar kapatılır (oyun izleme, ayar dinleyicileri, havuz eşitlemesi; çeviri havuzu diske kaydedilir; ortak
  havuz kuyruğunda zamanı gelmiş parçalar son kez gönderilmeye çalışılır), sağlık izleme oturumu kapatılır (gerekirse
  otomatik sorun bildirimi gider, bkz. 6), kilitler bırakılır.
- Arayüz durumu sıfırlanır: çalışmıyor, aşama boş, telefon satırları boş, ek alanlar ve "ekranı çevir" sonuçları
  temiz, görüntü yok, oyun teması kapalı, bağlanamama nedeni silinir. Yakalama kartı uyarısı da kalkar; başka hata
  metni varsa kalır.

### 1.3 Ön plan bildirimi

- Kanal: kimliği `translation`, adı `notif_channel_translation`, önem düzeyi **düşük** (ses ve titreşim yok).
- Başlık: `notif_translation_title`.
- Metin (oturum başında seçilir, oturum boyunca değişmez):
  - PS5: `notif_translation_ps5`
  - Yakalama kartı: `notif_translation_capture`
  - Xbox: `notif_translation_xbox`
- Sürekli (kaydırılarak kapatılamaz). Dokununca ana ekran açılır. Tek eylem düğmesi: "Çeviriyi durdurun".
- Ön plan servis türü: ağdaki cihazlarla sürekli konuşan **bağlı cihaz** türü (Android 14+). Yakalama kartında,
  kamera izni verilmişse ayrıca **kamera** türü eklenir; izin yokken eklenmez (Android 14+ izinsiz kamera türüyle
  servisi açmaz).

### 1.4 Uyanık tutma ve ekranı açık tutma

- Servis çalışırken **kısmi uyanma kilidi** tutulur: ekran kapansa da işlemci kareleri işlemeye devam eder.
- **Wi-Fi kilidi** tutulur: Android 10+ düşük gecikme kipi, daha eskide yüksek performans kipi. Ekran kapalıyken Wi-Fi
  uyumaz.
- İki kilit servis kapanınca bırakılır.
- **Ekranı açık tutma**: Ayarlar'daki "ekran açık kalsın" (varsayılan **açık**) seçiliyse, çeviri çalışırken ana
  pencere ekranı kapatmaz. Çeviri durunca bu bırakılır. Telefon altyazı ekranı ayardan bağımsız olarak ekranı her
  zaman açık tutar.
- Ekran kapalıyken ya da uygulama arka plandayken okuma ve çeviri sürer.

---

## 2. Aşamalar ve arayüze akan durum bilgisi

Servis, ekranların dinlediği tek bir canlı durum yayınlar. Alanlar:

| Bilgi | Anlamı |
|---|---|
| Çalışıyor mu | Servis (ya da demo) açık. |
| Aşama metni | Kısa durum: aşağıdaki tablo. |
| Görüntü geliyor mu | Konsol görüntüsü şu an akıyor (bağlanırken ve kopukken hayır). |
| Bağlı TV sayısı | Altyazı sunucusuna bağlı TV uygulaması sayısı. |
| Son çeviriler | En yeni başta, en çok 20 satır (kaynak, çeviri, kökeni: paket/havuz/motor, çeviri süresi). |
| Telefondaki satır | Telefon ekranında şu an gösterilen altyazı ve onun üstünde soluk duran önceki satır. |
| Ek alanlar | Telefon ekranındaki küçük kutular (görev, bildirim vb.). |
| "Ekranı çevir" sonuçları ve düğme durumu | Boşta / çevriliyor / ekranda. |
| Kullanılan paket | Son paketten gelen satırın oyun adı; oturum boyunca kalır. |
| Hata | Ana ekranda uyarı kartı. |
| Bağlanamama nedeni | Konsola neden bağlanılamadığının son metni (aşağıdaki kurala bakın). |
| Alınan kare | Toplam kare sayısı. |
| Başlama anı | Süre göstergesi için. |
| Motor adı | "Ücretsiz", "DeepL", "Gemini", "OpenAI", "Claude". |
| Gösterilen satır ve paketten gelen satır sayısı | Oturum sayaçları. |
| Demo mu | Konsolsuz demo. |
| Oynanan oyun | Tanınan/seçilen oyun; yoksa boş. |
| Havuz öncelikli oyun | Tanınan oyun havuz öncelikliyse (şimdilik GTA 6); ana ekrandaki sahnenin teması buna göre. Demo ve klipte hep hayır. |
| Oyun sorma kartı açık mı | Oynanan oyunu soran kart. |
| "Çeviri başladı" anı | Telefonda 7 sn balon. |

### 2.1 Aşama metinleri

| Durum | Metin |
|---|---|
| Kurulum | `phase_preparing` |
| PS5'e bağlanıyor | `phase_connecting` |
| Yakalama kartı açılıyor | `capture_phase_opening` |
| Xbox'a bağlanıyor | `xbox_phase_connecting` |
| Görüntü geliyor | `phase_streaming` |
| PS5 başka Remote Play'de | `phase_in_use` |
| PS5 bulunamadı | Adres biliniyorsa `phase_not_found_host`, yoksa `phase_not_found` |
| Ağ hatası | `phase_network` |
| Eşleme geçersiz | `phase_registration_invalid` |
| Uzaktan Oynama kapalı | `phase_remote_play_disabled` |
| Oturum reddedildi | Kod varsa `phase_rejected_code`, yoksa `phase_rejected` (ikisi de başka PS Remote Play'in açık olabileceğini, kapatıp PS5'i yeniden başlatmayı söyler). |
| Görüntü yok | `phase_no_picture` |
| PS5 uyanmadı | `phase_asleep` |
| Giriş şifresi isteniyor / yanlış | `phase_passcode` / `phase_passcode_incorrect` |
| PS5 bağlantıyı reddetti | `phase_refused` |
| Kart yok / kamera izni yok / görüntü siyah | `capture_not_found`, "Kamera izni yok. …", `capture_black` |
| Diğer kopmalar | `phase_reconnecting` |
| Xbox hataları | Xbox oturumunun kendi metni, kullanıcının dilinde (bkz. 10.6). |

### 2.2 "Bağlanamama nedeni" kuralı

Oturum "koptu → bağlanıyor → koptu" diye dönerken aşama metni her turda değişir; neden metni ana ekranda bir görünüp
bir kaybolmasın diye ayrıca tutulur:

- Bağlanırken: önceki neden korunur.
- Görüntü gelince: silinir.
- Kopunca: yeni neden yazılır. İstisnalar: kullanıcının durdurması (önceki kalır), nedeni bilinmeyen genel kopma
  (önceki kalır; Xbox bu türle ayrıntılı metin verirse o yazılır), yakalama kartı sorunları (bunlar hata kartında
  görünür, burada tutulmaz; aynı metin iki kez çıkmasın).
- Yakalama kartı sorunları hata kartına yazılır; kart sorunu olmayan bir sonraki durumda (bağlanıyor dahil) bu kart
  kalkar.
- Durdurulunca ve yeni başlatmada silinir.

---

## 3. Okuma → çeviri → TV / telefon akışı ve zamanlaması

### 3.1 Kareden okumaya

- Her gelen karede:
  - Yazı tanıma **saniyede en çok 5 kez** çalışır (her okuma arası en az 200 ms) ve aynı anda yalnız bir okuma yapılır;
    okuma sürerken gelen kareler okunmaz.
  - Okunan alan: kullanıcının altyazı bölgesi. Oyunun altyazı şeridinin yeri öğrenildiyse yalnız o şerit okunur.
  - Karenin geliş anı (tekdüze saat) okumayla birlikte gider; gecikme buradan TV'ye gidene kadar ölçülür.
- **Değişmeyen bölge**: bölgenin imzası bir önceki okumayla aynıysa yeniden okunmaz, son okuma yeniden kullanılır.
  Ardışık en çok 20 kez (ayarlarda "hızlı altyazı algılama" açıksa en çok 2 kez); sonra zorla yeniden okunur. Satırın
  kararlılığı ve silinmesi saate bağlı olduğu için hat yine her turda beslenir.
- Harita ekranı açıkken altyazı okunmaz (yer adları altyazı sanılmasın).
- Havuz öncelikli oyunda (GTA 6) karede oyunun telefonu aranır; telefonun okunan alana giren kısmı okumadan önce
  siyaha boyanır ve telefona ait satırlar altyazıdan çıkarılır. Telefon yakın zamanda görüldüyse kısa bir süre daha
  boyanmaya devam eder. Karede renk bilgisi yoksa telefon aranmaz (siyah-beyazda altyazı sahnesi telefon sanılıyordu).
- Yarım ya da bozuk okuma hemen çevrilmez; aynı satırın en iyi okuması çevrilir.
- Görev şeridi çizgisi: havuz öncelikli oyunda ekranın %93,5'inin altı altyazı sayılmaz (öğrenilen çizgi daha
  yukarıdaysa o geçerli). Diğer oyunlarda öğrenilmiş çizgi kullanılır.
- Gösterilen her satırın kutusu, oyunun altyazı yerini öğrenmek için kaydedilir (oyun başına kalıcı). Havuz
  öncelikli oyunun yeri kendi adıyla tutulur; oyun yalnız paketten tahmin edildiyse son oynanan oyunun havuz
  öncelikli olup olmadığına bakılır.
- Çok büyük yazılar (tabela, reklam panosu) atlanır ve günlüğe yazılır.

### 3.2 Çeviri sırası

Bir satır için sırayla:

1. **Oyun paketi** (yalnız Türkçe, paketler açıksa, oyun havuz öncelikli değilse). Kullanıcı elle oyun seçtiyse
   satır yalnız o oyunun paketinde aranır; o oyunun paketi yoksa hiç aranmaz.
2. **Çeviri havuzunun yerel kopyası** (bütün dillerde; havuz kapalıysa boş).
3. Havuz öncelikli oyunda: havuz sunucusuna sorulur; gelmezse ücretsiz cihaz içi çevirmen. Kullanıcının anahtarlı
   motoru **çağrılmaz** (ortak havuz kapalı olsa da).
4. Diğer oyunlarda: seçili motor (hata verirse cihaz içi çevirmen).

- Zaten hedef dilde olan yazı çevirmene gitmez.
- Paketle eşleşmeyen satır: Türkçede ortak havuza önerilir; havuz açıksa (ya da oyun havuz öncelikliyse) havuz
  sunucusuna önceki birkaç satırın bağlamıyla sorulur. Daha iyi çeviri gelirse ve satır hâlâ ekrandaysa ekrandakinin
  yerine konur; aynı satır iki kez sorulmaz. Bu sorgular okumayı bekletmez.
- Yerine konan çeviri "son çeviriler" listesindeki ilk satırı günceller; sayaçlar değişmez.
- Konuşmacı adlarının gösterilmesi ayara bağlıdır.
- Çeviri hatası: `error_translation` hata kartı; sonraki başarılı çeviride kalkar.
- Her motorun kalıcı önbelleği vardır, dil başına ayrı tutulur: önceki oturumlarda çevrilen cümleler hemen gelir.

### 3.3 Satır gösterilince

- TV'ye (hedef TV ise) altyazı olayı gider; telefon ekranına da aynı olay işlenir.
- Arayüz: son çeviriler listesine eklenir, sayaçlar artar, paket adı güncellenir.
- Sağlık ölçümüne satır ve (paketten gelmediyse) çeviri süresi yazılır.
- Geçmişe eklenir (bkz. 11).
- Oyun tanıma beslenir (gerçek oyunda): paketten gelen ayırt edici eşleşmeler oyunu anlatır.
- Paket başına oturumda **bir kez** "paket kullanıldı" olayı gider.

### 3.4 Telefon ekranındaki satır

- Yeni satır öncekini üste (soluk) iter; aynı cümlenin uzamış/düzelmiş okuması öncekinin yerine geçer, üste yığılmaz.
- "Temizlendi" olayı iki satırı da siler.
- Satırın ekranda kalma süresi: satırın kendi süresi varsa en az 1,2 sn olmak üzere o süre; yoksa
  2 sn + karakter başına 60 ms, en çok 8 sn. Süre dolunca telefondaki satır kalkar. Ek alan ve "ekranı çevir"
  olayları bu süreye dokunmaz.
- Ek alan olayı telefonda kendi yerinde küçük kutuda görünür; boş metin kutuyu kaldırır.

### 3.5 Ortak havuz ve çeviri havuzu

- Klipte havuzlar kullanılmaz (oyun yazısı değildir). Yakalama kartı gerçek oyundur, kullanılır.
- Ortak havuz (Türkçe satır önerileri): satırlar telefonda kuyrukta bekler, sunucu onaylayınca silinir. Kuyruk 5 sn
  sonra başlayıp **dakikada bir** gönderilmeye çalışılır; ağ geri gelince hemen denenir.
- Çeviri havuzu: oturum başında ve oyun değişince **hemen**, sonra **dakikada bir** oyunun havuzdaki çevirileri
  indirilir ve aynı döngüde sunucuya "buradayım" denir.
- Çeviri sürerken kullanıcı ortak havuzu kapatırsa hemen hiçbir şey sorulmaz ve gönderilmez, satır kuyruğu silinir;
  açarsa yeniden başlar.
- Havuz adresi: havuz klasöründe deneme adresi yazılıysa o, yoksa canlı sunucu `https://nino-pool.y-demirbag2506.workers.dev`.
  Sorun bildirimi ve yardımcı da aynı adresi kullanır.
- Havuzun ayar yanıtındaki toplam indirme sayısı ana ekrandaki sayaca verilir (ayrı istek yapılmaz).

### 3.6 Ek alanlar, oyun içi telefon ve harita kartı

- **Ek alanlar** (Ayarlar › Altyazı alanı): saniyede bir, altyazıdan ayrı okunur; altyazıyı bekletmez. Aynı paketlerle
  ve aynı motorla çevrilir ama satırları ortak havuza önerilmez.
- **Oyun içi telefon ve harita kartı** yalnız havuz öncelikli oyunda (ya da oyun henüz tanınmadıysa/yalnız paketten
  tahmin edildiyse ve çeviri dili havuzun dillerindense) aranır. "Ekranı çevir" sonuçları ekrandayken aranmaz.
  - Çeviri sırası: havuzun hazır çevirisi → havuz sunucusu (bilinmeyen mesajlar tek istekte) → cihaz çevirmeni.
  - Telefon mesajlarının çevirisi dil başına kalıcı bir hafızada tutulur.
  - Türkçede telefon mesajları da ortak havuza önerilir; telefon uygulamalarının sabit Türkçeleri yalnız Türkçede.
  - Harita/menü açıkken ve kapandıktan sonra 8 sn telefon aranmaz.
  - Oyunun telefonu ya da GTA 6'ya özgü yazılar görülünce oyun GTA 6 sayılır (konsolun bildirdiği ya da kullanıcının
    seçtiği oyun her zaman önce gelir).
  - Telefon ve harita çevirileri TV'ye tek liste olarak, TV'deki altyazıyı silmeden, en çok 120 sn süreli "katman"
    olarak gider. Hiç yoksa TV'deki katman temizlenir.

### 3.7 "Ekranı çevir"

- Düğmeye basılınca (çeviri sürüyorsa): bir sonraki karenin tamamı bir kez okunur, yazı grupları tek istekte
  çevrilir, sonuçlar telefonda ve TV'de yazının kendi yerinde görünür. TV'ye önce stil, sonra 2,5 sn'lik
  "Ekran çevriliyor…" gider.
- Görüntü yoksa TV'ye 4 sn `screen_no_picture` gider.
- Sonuçlar kendi süresi kadar kalır, sonra kendiliğinden kalkar.
- Çevrilirken ya da sonuçlar ekrandayken yeniden basmak her şeyi kaldırır; eski işin geç gelen sonuçları yok sayılır.
  Kalkınca telefon/harita katmanı geri gelir.
- Yazı bulunmazsa 2,5 sn `screen_no_text`; hata olursa 6 sn `screen_failed`.
- Çeviri çalışmıyorsa düğme bir şey yapmaz.

### 3.8 Deneme altyazısı

Ayarlarda yazı boyu/rengi değiştirilince ya da "TV'de test et"e basılınca 8 sn'lik deneme altyazısı gönderilir
(`TranslationControl.sendTestSubtitle`). Çeviri sürüyorsa oturum gönderir (TV hedefinde TV'ye, telefon hedefinde
telefondaki satıra). **Yeni uygulamada** çeviri çalışmıyorken de, hedef TV ise TV bağlantısı kısa süre açılır: görünüm
gönderilir, kurulu Android TV'ye bağlanılır, bağlı bir TV en çok 6 sn beklenir, altyazı gösterilir ve süre bitince
bağlantı kapanır (bu arada çeviri başlarsa kapanmaz; art arda basışlar tek pencereyi uzatır). Hiçbir TV bağlanmazsa
ya da hedef telefonsa ve çeviri çalışmıyorsa kullanıcıya not gösterilir.

### 3.9 Çeviri sürerken ayar değişiklikleri

Hemen yansır, yeniden başlatma gerekmez: yazı stili (TV yeni görünüme geçer), altyazı hedefi TV/telefon, altyazı
bölgesi ve ek alanlar, ortak havuz açma/kapama, paket içe aktarma/silme (paketler yeniden okunur).

---

## 4. Oynanan oyun

- Kaynaklar: konsolun bildirdiği oyun, paketten tanınan, ekrandan tanınan, kullanıcının seçtiği.
- PS5 yolunda (Xbox ve yakalama kartında değil) görüntü gelirken konsola çalışan oyun sorulur: ilk soru 30 sn sonra,
  sonra **2 dakikada bir**. Görüntü kesilince konsolun bildirdiği oyun silinir.
- Her 15 sn'de bir denetlenir: oyun hâlâ bilinmiyorsa, çeviri en az **2 dakikadır** sürüyorsa, ayarlarda "oyunu sor"
  ve ortak havuz açıksa, oturumda bir kez oyun sorma kartı açılır. Oyun bir yoldan tanınınca kart
  kapanır. Kartın sorma düğmesi bu oturumda bir daha sormaz; değiştir düğmesi kartı elle açar.
- Kullanıcının seçimi konsolun adıyla saklanır; aynı konsolda sonraki oturumda kartın ilk önerisi olur. Öneriler
  kurulu paketlerin oyun adlarından ve son oynanandan gelir.
- Oyun değişince: havuzdaki çeviriler hemen iner, altyazı yerleşimi yeniden hesaplanır, paket sunucusuna (son bakış
  10 dakikadan eskiyse) o oyunun yeni paketi için bakılır; inerse paketler yeniden okunur.
- **Ekrandan tanıma** (ortak havuz açıksa, elle oyun seçilmemişse): karenin küçültülmüş gri kopyası JPEG (kalite 60)
  olarak havuz sunucusuna gönderilir, sunucu oyunun adını söyler. Oyun bilinmiyorsa tanımak için, biliniyorsa
  doğrulamak için seyrek aralıklarla yapılır: sunucu aynı oyunu söylerse bir şey değişmez, başka bir oyun söylerse oyun
  ona geçer, bir şey söyleyemezse eski oyun kalır.
- Havuz öncelikli oyun kararı her gösterilen satırda ve oyun değişince yeniden verilir. Oyun bu oturumda henüz
  tanınmadıysa son oynanan oyunun teması kalır (her açılışta GTA renkleri kayboluyordu). Hatırlanan değer yalnız
  gerçek oyundan yazılır.
- Klipte oyun aranmaz, sorulmaz, önceki oturumun seçimi paket aramasını sınırlamaz.

---

## 5. Sağlık ölçümü (Ayarlar › Sistem sağlığı)

Her oturumda şunlar ölçülür (oturum bitince son değerler kalır; yeni oturumda sıfırlanır; oturum dışında gelen
sayımlar yok sayılır):

- Görüntünün geldiği toplam süre (bağlanırken ve kopukken sayılmaz), hiç görüntü geldi mi.
- Kopma sayısı (görüntü gelirken kopma; kullanıcının durdurması sayılmaz).
- Bağlanamama sayısı (hiç görüntü gelmeden biten deneme).
- Son kopma nedeni (yalnız türün adı: `NOT_FOUND`, `CONSOLE_ASLEEP`… ; adres yok).
- Kare sayısı (yalnız görüntü gelirken; kaynak yeniden başlarsa sayaç kaybolmaz).
- Satır sayısı, son 50 çevirinin süresinin ortancası ve en uzunu (paket satırları süreye girmez).
- Şu an kopuk mu ve ne zamandan beri.
- Oturumda telefonun ağının kaç kez gittiği, TV'nin kaç kez koptuğu.

### 5.1 Eşikler

| Gösterge | İyi | Dikkat | Sorun |
|---|---|---|---|
| Görüntü (kare/sn; en az 20 sn görüntü gelmeden hesaplanmaz) | ≥ 24 | 12–24 | < 12 |
| Çeviri (ortanca) | ≤ 1500 ms | 1500–3000 ms | > 3000 ms |
| Bağlantı | Görüntü geldi | 3+ kopma | Koptu ve geri gelmedi; ya da hiç görüntü gelmeden 2+ bağlanamama |
| Ağ | Kablolu her zaman iyi | Wi-Fi/mobil: görüntünün durumu (ölçülmeden yeşil gösterilmez) | Çevrimdışı |

### 5.2 "Muhtemel sebep" sırası

Önemliden önemsize: telefon çevrimdışı → PS5 koptu ve geri gelmedi (ağ daha önce gitti mi bilgisiyle) ya da hiç
bağlanılamadı → telefonun ağı oyun sırasında gitti geldi → görüntü yavaş/duruyor (Wi-Fi'de mi, ağır mı) → görüntü iyi
ama sık kopuyor (3+, ağ kaybı yokken) → çeviri yavaş → TV koptu. Hiç ölçüm yoksa yalnız çevrimdışılık söylenir.

### 5.3 Özet satırı (bildirimlere giden)

Türkçe, tek satır: ağ türü, oturumda ağ kopması ve TV kopması, (kopuksa) PS5 kaç sn'dir kopuk, görüntü süresi,
kare/sn, kopma, bağlanamama, son kopma, satır, çeviri ortancası ve en uzunu.

---

## 6. Sağlık izleme ve otomatik sorun bildirimi

İzleme uygulama açılınca kurulur, servisten bağımsızdır (servis kapanınca da bildirimi gönderebilir). **Klipte hiç
çalışmaz.** PS5 kuralları yalnız PS5 Remote Play'de uygulanır (Xbox ve yakalama kartında değil).

### 6.1 Sorun kayıtları

Kayıt olduğu anda yazılır ve dosyada saklanır (en çok 40, en yeni sonda; yeniden açılışta kaybolmaz). Her kayıtta:
an, tür, neden adı, o ana kadarki görüntü süresi (dk), kare/sn, ağ türü, oyun. Altyazı metni, konsol adı ya da adres
**yoktur**. Destek satırı biçimi (dilden bağımsız Türkçe):
`22.11 21:04 PS5 bağlantısı koptu (NOT_FOUND) · 31 dk oynandı · ağ wifi · 28 kare/sn · GTA 6`.

Türler ve kurallar:

- **PS5 bağlantısı koptu**: görüntü gelirken kopma (kullanıcı durdurması değil).
- **PS5 dakikalardır geri gelmiyor**: kopmadan sonra **180 sn** içinde görüntü geri gelmezse; o anda otomatik
  bildirim de gönderilir. Görüntü gelirse zamanlayıcı iptal.
- **TV bağlantısı koptu**: altyazı TV'ye gidiyorken bağlı TV sayısı sıfıra iner ve **20 sn** boyunca geri gelmezse
  (TV uygulaması ~2 sn'de yeniden bağlanır; kısa kopmalar sayılmaz).
- **Ağ düştü** (`NETWORK_DROPPED`): ağ türü çevrimdışına geçince, oturumda; ardışık çevrimdışılar bir kez sayılır.
  Ağ kaybı haberi geldiğinde 1,5 sn sonra yeniden bakılır (Wi-Fi'den mobile geçişte de kayıp haberi gelir).

### 6.2 Otomatik bildirim

- Ayar: Ayarlar › Sorun Bildir › `report_auto`, varsayılan **açık**.
- Ne zaman: (a) PS5 180 sn geri gelmeyince hemen; (b) oturum biterken, bu oturumda kayıt olduysa ya da görüntü veya
  çeviri "sorun" düzeyindeyse. **Oturum başına en çok bir**, **günde en çok 3** (gün sayacı gönderimden önce artar).
- Ne gider: yalnız özet: kullanıcının bir şey yazmadığını, sorunu Nino'nun kendisinin fark ettiğini söyleyen otomatik giriş cümlesi + muhtemel sebep + son üç
  günün sorunlarından son 12'si + özet satırı + cihaz özeti (bkz. 8). Günlük, fotoğraf, altyazı metni, konsol adı ve
  ağ adresi **gitmez**. Bildirim türü alanı `auto`.
- Ağ hatasında saklanır ve sonraki açılışta yeniden gönderilir; sunucu reddederse (geçersiz, çok büyük, sınır)
  yeniden denenmez.

---

## 7. Sorun Bildir (elle)

- Adres: havuz sunucusu + `POST /v1/reports`, JSON, 30 sn zaman aşımı.
- Gövde:
  - `v`: 1, `install`: kurulum kimliği, `app`: uygulama sürümü, `platform`: `android`, `language`: çeviri dili.
  - `text`: açıklama (en çok 4000 karakter). Kullanıcı bir şey yazmadıysa `NinoServer.NO_TEXT` (`[Hataları gönder]`
    etiketiyle başlayan kısa not). Her durumda altına "— Nino'nun tespitleri —" bölümü (muhtemel sebep, son
    sorunlar, özet) eklenir. Toplam 4000'de kırpılır, yarım karakter bırakılmaz.
  - `contact`: isteğe bağlı iletişim (en çok 200; boşsa alan yok).
  - `log`: isteğe bağlı uygulama günlüğü (anahtar varsayılan **açık**; boşsa alan yok).
  - `device`: cihaz özeti (en çok 600; boşsa alan yok).
  - `images`: en çok 3 fotoğraf, her biri `{mime: "image/jpeg", data: base64}`.
  - Elle bildirimde `kind` alanı yoktur.
- Kullanıcı yazmadan da tek dokunuşla "Hataları gönder" diyebilir.
- Fotoğraflar: EXIF yönü düzeltilir, uzun kenar en çok 1600 px, JPEG; fotoğraf başına en çok 900 KB (önce kalite
  70 → 55 → 40, sonra boy ×0,75; 320 px'in altına inilmez). Gövde en çok 4 MB; aşarsa hiç gönderilmez.
- Günlük: uygulamanın kendi sistem günlüğünün son 3000 satırı, son 60 000 karakter; anahtar ve jeton gibi görünenler
  "[gizlendi]" yapılır (Bearer jetonları; adı key/token/secret/password/passcode/auth/authorization/cookie içeren
  alanların değeri; `AIza…` ve `sk-…` biçimli anahtarlar; 32+ hane onaltılık; 40+ karakterlik base64 benzeri dizeler).
- Sonuçlar: 2xx gönderildi (teşekkür, ekran kapanır), 400 geçersiz, 413 çok büyük, 429 günlük sınır, diğerleri ve ağ
  hatası "gönderilemedi". Sunucuda kuruluş başına günde 10 sınırı vardır.
- **Kurulum kimliği**: uygulamanın tek kurulum kimliği (UUID; veri-ve-ayarlar.md §1.3). Sorun Bildir, otomatik
  bildirim, yardımcı, havuz ve ölçüm aynı kimliği kullanır.

## 7A. Önceki kapanış raporu

- Android 11+: açılışta sistemin kaydettiği son 10 kapanışa bakılır; son raporlanandan yeni olanlar raporlanır.
- Raporlanan nedenler: sinyalle öldürülme, bellek yetmemesi, yerel (native) çökme, ANR, başlatma hatası, aşırı
  kaynak kullanımı. Java çökmesi (Crashlytics zaten görür), kullanıcının kapatması, güncelleme ve izin değişikliği
  raporlanmaz. Aynı kapanış iki kez raporlanmaz.
- Önceki açılışta "çeviri sürüyor" bayrağı kaldıysa, en yeni kapanış "çeviri sürerken" diye işaretlenir.
- Kullanım verisi açıksa Crashlytics'e ölümcül olmayan hata olarak gider (neden, çeviri sürerken mi, bellek
  kullanımı MB); ayrıca `app_exit` olayı (bkz. 9).

---

## 8. Cihaz özeti

Sistem sağlığında gösterilir; Sorun Bildir, otomatik bildirim ve yardımcıya `device` alanı olarak gider. Her gönderimde
yeniden okunur. Tek satır, `id: değer | id: değer`, en çok 600 karakter; değerlerdeki satır sonu boşluğa, `|` işareti
`/`'ye çevrilir; boş satır yazılmaz. Değerler çevrilmez.

- `app`: "sürüm (yapı no)".
- `device`: üretici + model.
- `system`: `tvinstall_brand_android`.
- `tv`: TV uygulamasının bu telefondan kurulduğu TV'nin markası (LG / Samsung / Android TV) ve TV uygulaması sürümü;
  bağlanan TV uygulaması modelini bildirdiyse model (TV'nin bağlantı adresindeki `model` parametresi; çözülür,
  tehlikeli işaretler atılır, en çok 60 karakter).
- `console`: "Yakalama kartı", "Xbox {model} · Remote Play" ya da "PS5 · Remote Play".
- `status`: son hata, yoksa çeviri sürüyorsa aşama + ", oyun: {ad|tanınmadı}". IP adresleri ve konsolun/TV'nin adı ve
  adresi "…" ile silinir.

Telefonun adı, ANDROID_ID, seri numarası, hesap, IP adresi ve kullanıcının cihazlara verdiği adlar **asla** okunmaz.

---

## 9. Telemetri (Firebase ve Meta)

### 9.1 Açma-kapama

- Tek anahtar: Profil › Kullanım verisi, varsayılan **açık**.
- Açıkken: Firebase Analytics ve Crashlytics açılır. Meta App Events yalnız açıkken **ve** karşılama ekranı
  geçildikten sonra açılır.
- Uygulama açılışında manifestte her şey kapalı başlar; ayara göre açılır. Firebase yapılandırma dosyası yoksa Firebase
  hiç açılmaz; Meta kimliği tanımlı değilse Meta hiç açılmaz. İkisi de sessizce atlanır.
- Reklam yoktur: reklam kimliği izinleri manifestten çıkarılır, reklam kimliği toplanmaz; Consent Mode'da reklam
  depolama, reklam kullanıcı verisi ve kişiselleştirme her zaman reddedilir, analitik depolama ayara göre.
- Kullanım verisi kapalıyken Crashlytics'e elle de bir şey gönderilmez.
- Crashlytics'e "iz satırları" düşülür (çeviri başlıyor, paket sayısı, oturum açılıyor, Xbox adımları, oyun tanındı).

### 9.2 Olaylar

| Olay | Parametreler | Ne zaman |
|---|---|---|
| `subtitle_session_start` | `target` (tv/phone), `engine`, `packs` (true/false), `source` (`remote_play` / `capture_card` / `xbox`) | Servis başlarken |
| `subtitle_session_stop` | `seconds`, `pack_lines`, `lines` | Servis kapanırken |
| `tv_connected` | `count` | Bağlı TV sayısı 0'dan yukarı çıkınca |
| `pack_hit` | `pack` (paket kimliği) | Oturumda paket başına bir kez |
| `onboarding_done` | `target` | Kurulum bitince |
| `app_exit` | `reason`, `during_translation` | Önceki kapanış raporlanınca |
| `no_picture` | `next`, `streak`, `frames` | PS5'ten görüntü gelmeyince (Remote Play tarafı) |
| ekran görüntüleme (Firebase standart) | ekran adı = gezinme rotasının ilk parçası | Her ekran değişiminde (yalnız Firebase) |

Firebase'in ayrılmış adları kullanılamadığı için oturum olayları `subtitle_` önekiyle adlandırılır. Mantıksal değerler
metin olarak gönderilir. **Meta'ya yalnız olayın adı gider**, parametre gitmez; ekran görüntüleme Meta'ya gitmez.

---

## 10. Xbox ev yayını (Beta)

Xbox'un ev akışından (xHome) görüntü alınır. Mikrofon hiç açılmaz, kumanda/dokunma girdisi gönderilmez. Protokol açık
kaynak Xbox kitaplıklarındaki (MIT) tarayıcı/Windows istemcisiyle birebir taklit edilir.

### 10.1 Microsoft girişi (cihaz kodu akışı)

1. `POST https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode`, form gövdesi: `client_id`,
   `scope=xboxlive.signin openid profile offline_access`. İstemci kimliği açık kaynak Xbox kimlik kitaplığının
   herkese açık Microsoft istemci kimliğidir: `1f907974-e22b-4810-a9de-d9647380c97e`.
2. Kullanıcıya kod gösterilir; kod panoya kopyalanır ve doğrulama adresi (varsayılan `https://www.microsoft.com/link`)
   tarayıcıda açılır. Tarayıcı yoksa adres metin olarak gösterilir. Koda dokununca yeniden kopyalanır/açılır.
3. Kod süresi (varsayılan 900 sn) dolana kadar, sunucunun verdiği aralıkla (varsayılan 5 sn, en az 1)
   `POST …/token` sorulur: `grant_type=urn:ietf:params:oauth:grant-type:device_code`, `client_id`, `device_code`.
   - `authorization_pending`: beklemeye devam. `slow_down`: aralık +5 sn. `expired_token`/`code_expired`: kod süresi
     doldu. `authorization_declined`/`access_denied`: reddedildi. 5xx: beklemeye devam. Diğer: hizmet hatası.
   - **Ağ hatası girişi bitirmez**: kullanıcı tarayıcıdayken Android arka plandaki isteği kesebilir; süre dolana kadar
     denemeye devam edilir.
   - Ekrandan çıkılırsa sorgu iptal edilir.
4. Başarıda kullanıcı jetonu saklanır: yanıtın kendisi + `expires_on = şimdi + expires_in` (ISO 8601). Kalıcı saklanan
   **tek** jeton budur; Android Keystore anahtarıyla şifreli depolanır. Biçim Windows köprüsünün sakladığı JSON ile
   aynıdır. Yenileme jetonu olmayan ya da bozuk kayıt "giriş yok" sayılır.
5. Çıkış: bütün jetonlar silinir.

### 10.2 Jeton zinciri

Bütün jetonlar bellekte tutulur, süresine **60 sn**'den az kalınca yenilenir.

1. **Microsoft erişim jetonu yenileme**: `POST …/oauth2/v2.0/token`, `client_id`, `grant_type=refresh_token`,
   `refresh_token`, `scope`. Yanıtta yenileme jetonu yoksa öncekisi korunur. 400 → yeniden giriş gerekir.
2. **Xbox Live kullanıcı jetonu**: `POST https://user.auth.xboxlive.com/user/authenticate`, JSON:
   `{"Properties":{"AuthMethod":"RPS","RpsTicket":"d=<erişim jetonu>","SiteName":"user.auth.xboxlive.com"},
   "RelyingParty":"http://auth.xboxlive.com","TokenType":"JWT"}`; başlıklar `x-xbl-contract-version: 1`,
   `Origin/Referer: https://www.xbox.com`. 401 → yeniden giriş.
3. **XSTS**: `POST https://xsts.auth.xboxlive.com/xsts/authorize`,
   `{"Properties":{"SandboxId":"RETAIL","UserTokens":[<kullanıcı jetonu>]},"RelyingParty":<RP>,"TokenType":"JWT"}`;
   tarayıcı kullanıcı ajanı ve `ms-cv: 0`. RP iki tanedir: `http://xboxlive.com` (konsol listesi) ve
   `http://gssv.xboxlive.com/` (yayın). Her RP'nin jetonu ayrı önbellekte. 401'de yanıttaki `XErr`
   2148916233/…235/…236/…237/…238 ise "hesabın Xbox profili yok / çocuk hesabı / ülke", diğerlerinde yeniden giriş.
   Jetondan `Token`, `NotAfter` ve `DisplayClaims.xui[0].uhs` (kullanıcı özeti) okunur. `NotAfter` saniyenin yedi
   ondalık hanesini taşıyabilir (`…T10:16:00.1234567Z`); tarih okuyucu bunu kabul etmeli.
4. **Ev yayını girişi**: `POST https://xhome.gssv-play-prod.xboxlive.com/v2/login/user`,
   `{"token":<gssv XSTS>,"offeringId":"xhome"}`, `x-gssv-client: XboxComBrowser`. Yanıttan varsayılan bölgenin
   (`offeringSettings.regions[].isDefault`, yoksa ilki) `baseUri`'si, `gsToken` ve `durationInSeconds`
   (yoksa 30 dk) alınır.
5. **Konsola aktarım jetonu**: `POST https://login.live.com/oauth20_token.srf`, `client_id`,
   `scope=service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN`,
   `grant_type=refresh_token`, `refresh_token`. 400 → yeniden giriş.

### 10.3 Konsol seçimi

`GET https://xccs.xboxlive.com/lists/devices?queryCurrentDevice=false&includeStorageDevices=true`; başlıklar
`Authorization: XBL3.0 x=<uhs>;<xboxlive XSTS>`, `x-xbl-contract-version: 4`, `skillplatform: RemoteManagement`.
Her konsoldan kimlik, ad, tür (`consoleType`), güç durumu okunur. Konsol yalnız `consoleStreamingEnabled` **ve**
`remoteManagementEnabled` açıksa "hazır" sayılır ve seçilebilir; ilk hazır konsol önceden seçilir. Seçim kalıcı
saklanır.

### 10.4 Yayın oturumu

Bütün ev yayını istekleri: `<baseUri><yol>`, başlıklar `Authorization: Bearer <gsToken>`,
`X-Gssv-Client: XboxComBrowser`, sabit bir Windows/Surface cihaz bilgisi (`X-MS-Device-Info`; uygulama
`Microsoft.GamingApp`, Windows 11, 1920×1080). Hata yanıtı: 401/403 → yeniden giriş; gövdede InUse/Busy → konsol
meşgul; 404 ya da NotFound/Offline → konsola ulaşılamıyor; diğer → hizmet hatası.

1. `POST /v5/sessions/home/play`: `serverId` = konsol kimliği, saat dilimi farkı (dk), `locale: en-US`,
   `nanoVersion: V3;WebrtcTransport.dll`, `sdkType: web`, `osName: windows`, isteğe bağlı veri toplama kapalı.
   Yanıttaki `sessionPath`'in son parçası oturum kimliğidir.
2. `GET /v5/sessions/home/<id>/state` **saniyede bir, en çok 90 kez**:
   - `ReadyToConnect` görülünce bir kez `POST …/connect` (`{"userToken": <aktarım jetonu>}`), sonra sormaya devam.
   - `Provisioned` → WebRTC el sıkışması.
   - `Failed` ya da (Provisioned değilken) dolu `errorDetails` → konsol yayını reddetti, **yeniden denenmez**. Boş
     nesne ya da bütün alanları boş/null nesne hata sayılmaz. Nedeni: InUse/Busy/AlreadyStreaming → meşgul; diğerleri
     → konsola ulaşılamıyor.
   - 90 soruda hazır olmazsa zaman aşımı.
3. **WebRTC**: STUN `stun.l.google.com:19302` ve `stun1.l.google.com:19302`, birleşik plan.
   - Önce sıralı veri kanalları açılır: `input` (protokol `1.0`), `chat` (`chatV1`), `control` (`controlV1`),
     `message` (`messageV1`). Sonra ses (gönder-al) ve görüntü (yalnız al) alıcıları. Yerel ses parçası eklenmez.
   - SDP teklifinde ilk `useinbandfec=1` → `useinbandfec=1; stereo=1`.
   - `POST /v5/sessions/home/<id>/sdp`: `messageType: offer`, `sdp`, kanal sürümleri (chat 1–1, control 1–3,
     input 1–8, message 1–1) ve sohbet sesi biçimi (opus/webm, 24 kHz, mono, 20 ms). Yanıt **değiş-tokuş**
     biçimindedir: POST'tan sonra aynı yola GET ile `exchangeResponse` dolana kadar 250 ms arayla en çok 30 kez
     sorulur; gelmezse zaman aşımı. Yanıttaki `sdp` uzak tanım olarak konur.
   - Yerel ICE adayları en çok 5 sn toplanır, `POST …/ice` (`messageType: iceCandidate`, aday listesi) ile aynı
     değiş-tokuşla gönderilir. Xbox'un adaylarından `2001` ile başlayan (Teredo) adresler için adresten çıkarılan
     IPv4 ile iki ek aday (port 9002 ve Teredo portu) öne eklenir. `end-of-candidates` atlanır.
   - Her WebRTC adımı en çok 10 sn beklenir.
4. **Kanal iletileri**:
   - `message` kanalı açılınca el sıkışma iletisi gönderilir (`type: Handshake`, `version: messageV1`).
   - `HandshakeAck` gelince: `control` kanalına yetkilendirme isteği ve "kumanda 0 eklendi" iletisi; `input`
     kanalına 15 baytlık istemci bilgisi paketi (tür 8, sıra 0, zaman damgası ms, en çok 2 dokunma noktası; little
     endian); `message` kanalına altı yapılandırma iletisi (sistem arayüzü, istemci kurulum kimliği, yön 0, dokunma
     kapalı, istemci yetenekleri, 1920×1080 boyutlar ve güvenli alan). Sonra kare onayı başlar.
   - **Kare onayı**: Xbox onay almazsa yayını ~40 sn'de keser. `HandshakeAck`'ten sonra çözülen her görüntü karesi
     kuyruğa girer (öncekiler sayılmaz) (en çok 600;
     taşarsa eskiler atılır). **16 ms'de bir** en çok 29 kare tek pakette `input` kanalına gider: tür 1, artan sıra
     no, zaman damgası, kare sayısı ve her kare için yedi u32 (karenin RTP damgası ×90 alt 32 bit, varış, varış,
     çözülme, çözülme, şimdi, şimdi; anlar oturum saatinin sıfırından ms).
   - `input` kanalı açılınca **30 sn'de bir** `POST …/keepalive`.
   - `input` kanalının kapanması ya da bağlantının FAILED/CLOSED olması bağlantıyı bitirir. Gelen ikili iletiler
     (titreşim hariç) ve metin iletileri günlüğe yazılır.
5. **İlk kare**: SDP ve ICE değiş-tokuşu bittikten sonra **20 sn** içinde kare gelmezse "konsola ulaşılamıyor" hatasıyla oturum yeniden
   açılır. İlk kare gelince durum "görüntü geliyor" olur.
6. Kareler: OCR saniyede 5 okuduğu için kareler en çok **66 ms'de bir** çözülmüş biçime çevrilip hatta verilir;
   parlaklık düzlemi ve (oyun içi telefonu bulmak için) renk düzlemleri.
7. **Ses**: Ayarlar › `settings_xbox_audio` (varsayılan **açık**) açıksa oyun sesi oyun/medya sesi olarak
   telefonda, stereo çalınır; kapalıysa ses susturulur. Mikrofon her durumda kapalı.

### 10.5 Yeniden deneme

- Kullanıcı durdurunca da, hata ya da kopmada da uzak oturum kapatılır (`DELETE /v5/sessions/home/<id>`). Hata ya da
  kopmada **5, 15, 45 sn** sonra baştan denenir; üç
  ardışık denemeden sonra durulur. Yayın en az **60 sn** ayakta kaldıysa sayaç sıfırlanır.
- Yeniden giriş gerektiren ve "Xbox profili yok" hataları hiç yeniden denenmez; konsolun reddi de denenmez.
- Denemeler bitince ya da konsol reddedince: "Xbox bağlantısı sona erdi: {neden}. Tekrar bağlanmak için Xbox'ı kapatıp
  açın."
- Her bağlantı bitişinde günlüğe ve (kullanıcı durdurmadıysa, oturumda bir kez) Crashlytics'e özet: neden, kare
  sayısı, gönderilen onay sayısı, ilk kareden sonra kaç sn.
- Önceki bağlantıdan geç gelen kareler yeni bağlantının ilk karesi sayılmaz.

### 10.6 Xbox hata metinleri

| Tür | Metin |
|---|---|
| Giriş gerekli / kod süresi doldu / reddedildi | `xbox_error_sign_in` |
| Xbox profili yok | `xbox_error_no_account` |
| Konsola ulaşılamıyor | `xbox_phase_unreachable` |
| Meşgul | `xbox_phase_busy` |
| Zaman aşımı | `xbox_phase_timeout` |
| Ağ | `xbox_phase_network` |
| Hizmet | `xbox_phase_service` |

Xbox'ta konsola çalışan oyun sorulmaz; oyun paketten/ekrandan tanınır. Sağlık izlemenin PS5 kuralları Xbox'ta
uygulanmaz.

---

## 11. Geçmiş

- Çevrilen son **200** satır, en yeni başta, oturumlar arası kalıcı (uygulama dosyalarında JSON: `version: 1`,
  `entries` listesi; her kayıtta id, UTC ISO tarih, kaynak, çeviri, köken `pack`/`engine`).
- Metinler 500 karakterde kırpılır; boş çeviri yazılmaz.
- Aynı satırın yeniden okuması (benzer kaynak metin) yeni kayıt açmaz, son kaydı günceller.
- Yazma arka planda, geçici dosyadan yerine konarak yapılır; bozuk dosya boş geçmiş sayılır.
- Düz metin kopyası: her satırda "[SS:DD:ss] çeviri" ve altında kaynak, satırlar arası boş satır.
- Temizlenebilir.

## 12. Canlı kare önizlemesi

Ayarlar › Altyazı alanı ekranı açıkken (yalnız o zaman), son karenin 320 px genişliğinde gri kopyası **saniyede bir**
üretilir. Çeviri hattını yavaşlatmaz; okunamayan kare atlanır.

---

## 13. "Nino'ya Sor" yardımcısı

- Adres: havuz sunucusu + `POST /v1/assistant`, JSON, **90 sn** zaman aşımı.
- Gövde: `v: 1`, `install` (Sorun Bildir ile aynı kurulum kimliği), `app`, `platform: android`, `language`,
  `messages`, isteğe bağlı `device` (cihaz özeti; yardımcı bildirim açarsa bildirime eklenir, modele gitmez).
- `messages`: son **24** mesaj; her biri `role` (`user`/`assistant`) ve `text` (en çok 2000 karakter). Fotoğraflar
  yalnız kullanıcı mesajlarında: en çok 3 fotoğraf, `images: [{mime: "image/jpeg", data: base64}]`. Yalnız son **2**
  fotoğraflı kullanıcı mesajı fotoğraflarıyla gider; eskilerin metnine `[screenshot]` yazısı eklenir. Metni ve
  fotoğrafı olmayan mesaj atlanır.
- Gövde en çok **6 MB**; aşarsa önce eski fotoğraflı mesaj, sonra hepsi `[screenshot]`'a indirilir; yine sığmazsa
  gönderilmez. Sohbetteki her fotoğraf 600 KB'ı geçmeyecek şekilde küçültülür.
- Sunucuya yalnız gönderilmiş kullanıcı mesajları, yardımcının gerçek yanıtları ve şimdiki mesaj gider (yerel hata
  balonları gitmez). Cihaz özeti her mesajda yeniden okunur.
- Yanıtlar:
  - 2xx ve `ok: true` ve dolu `reply` → yanıt; `report` doluysa yardımcı ekibe bildirim açmıştır (kimliği).
  - 503 `assistant_disabled` → sunucuda yardımcı kapalı. 429 `busy` → sunucunun günlük bütçesi doldu (yeniden
    denenebilir). Diğer 429 → bu kurulumun günlük sınırı. 413 → çok büyük. 400 → geçersiz. Ağ hatası, 502 ve
    diğerleri → yeniden denenebilir hata.
  - Yeniden denenebilir hatalarda mesaj "tekrar dene" ile sohbetin sonuna taşınabilir.
- Yanıt gösterimi: boş satır blokları ayırır; "1." ya da "1)" (en çok iki basamak) numaralı adım, "-", "•", "*"
  madde; adımın altındaki girintili satır o adıma eklenir; paragraf içi satır sonları korunur. Metindeki http(s)
  bağlantıları tıklanabilir (sondaki noktalama bağlantıya katılmaz).

---

## 14. Uygulama güncelleme denetimi

- Kaynak: GitHub son sürüm API'si `https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest`
  (`User-Agent: Nino-Android`, `Accept: application/vnd.github+json`, 8 sn bağlantı/okuma zaman aşımı).
- Taslak ve ön sürüm yayınlar yok sayılır; etiketin başındaki `v` atılır.
- Sıklık: uygulama **her öne geldiğinde** denetlenir, ama ağa **en çok 3 saatte bir** çıkılır (saat geri alındıysa
  hemen). Yanıt geldiyse (403/oran sınırı dahil) 3 saat beklenir; ağ hatasında bir dahaki öne gelişte yeniden
  denenir. Ayarlar › "Şimdi denetle" süreyi beklemez; başarısızsa kullanıcıya söylenir.
- Sürüm karşılaştırma anlamsal: sayılar sayı olarak (0.2.0 > 0.1.10 > 0.1.9), ön sürüm aynı numaralı asıl sürümden
  eski (0.1.0 > 0.1.0-beta.37), `+yapı` eki yok sayılır. Okunamayan sürümde kart asla gösterilmez.
- Yeni sürüm varsa ana ekranda sakin bir kart ve Ayarlar'da "Güncelleme" satırı. Kartın ✕'i kartı **yalnız bu
  çalışma için** gizler (eskiden kalıcı gizliyordu, kullanıcılar eski sürümde kalıyordu); Ayarlar satırı kalır.
- İndirme adresi: `https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk`.
- Google Play'den kurulmuş kopyada hiç denetlenmez, kart ve satır gösterilmez (Play günceller).
- Denetim hiçbir zaman kullanıcıyı rahatsız etmez: hatalar sessizdir.
- Ayrıca uygulama açılınca ve her TV bağlandığında TV'deki Nino'nun sürümüne bakılır; eskiyse ana ekran "TV
  uygulamasını güncelle" önerir.

## 15. Paket yenileme (uygulama düzeyi)

Açılışta hemen, sonra uygulama açık kaldıkça **günde bir** paket sunucusuna yeni/güncellenen paketler için bakılır.
Paket sunucusu adresi yapı ayarıdır; boşsa hiç bakılmaz. Oyun değişince son bakış 10 dakikadan eskiyse ayrıca
bakılır.

---

## 16. Demo modları

### 16.1 Kullanıcı demosu (yayın sürümünde)

- Konsolu olmayan ya da mağaza incelemesinde deneyen biri için. Karşılama ekranında "dene" düğmesi ve eşleme yokken
  ana ekrandaki "konsolsuz dene" ile açılır.
- Servis, ağ, konsol **kullanılmaz**; yalnız canlı durum beslenir. Ana ekran, tam ekran ve yan çevirme aynen çalışır.
- Durum: çalışıyor, görüntü geliyor, demo; sayaçlar ve liste sıfırlanır.
- 1,2 sn sonra başlar; döngüde örnek İngilizce satır ve seçili dildeki çevirisi gösterilir: 3,6 sn görünür, 0,9 sn
  boş kalır, sonraki satıra geçilir. Çeviri dilinin hazır örnek satırları varsa onlar, yoksa Arapçada Arapça, öbür
  dillerde Türkçe beş örnek satır (oyun diyalogu tadında).
- Durdurunca çalışmıyor/görüntü yok/demo değil olur.

### 16.2 Klip modu (yalnız geliştirme yapısı)

- Mağaza ekran görüntüleri ve ön plan servisi videosu için. Yayın yapısına girmez.
- adb ile, yalnız geliştirme yapısında bulunan, dışa açık, saydam bir demo etkinliği başlatılarak açılır/kapanır.
  Ekstralar: `demo` (mantıksal; true aç, false kapat), isteğe bağlı `clip` (yol), `name` (sahte konsol adı,
  varsayılan PS5), `speed` (ondalık hız). Etkinlik ayarı uygular, ana ekranı temiz bir görev olarak açar ve kapanır.
- Klip: verilen yol, yoksa uygulamanın dış dosya klasöründe, yoksa iç dosya klasöründe `demo-ps5.mp4`.
- Açılınca ana ekranın "bağlı" görünmesi için sahte PSN kimliği ve sahte PS5 eşlemesi (adres `demo.invalid`) yazılır;
  kapatılınca yalnız bu sahte eşleme silinir.
- Uygulama açılırken (her şeyden önce) mod açıksa PS5 yerine klip kaynağı kurulur. Klip "bağlanıyor" (1,5 sn) sonra
  "görüntü geliyor" bildirir; kareler gerçek zamanlı (hız 0,25–1; yavaş öykünücüde 0,5 önerilir), bitince baştan.
- Okuma, çeviri, altyazı ve ön plan bildirimi gerçekteki gibi çalışır. Farklar: havuzlara hiçbir şey gitmez, oyun
  aranmaz/sorulmaz, sağlık izleme ve otomatik bildirim çalışmaz, oyun teması hep kapalı.
- Geliştirme yapısında okunan bölge 3 sn'de bir önbellek klasörüne JPEG olarak kaydedilir ve okunan metin günlüğe
  yazılır.

---

## 17. İzinler ve manifest davranışı

| İzin | Neden |
|---|---|
| İnternet, ağ durumu, Wi-Fi durumu | PS5 Remote Play, TV altyazı sunucusu, Sony/Microsoft girişi, çevrimiçi çeviri, havuz. |
| Wi-Fi çoklu yayın değiştirme | TV arama (SSDP); ayrıca bağlı cihaz ön plan servisinin ön koşulu. |
| Uyanma kilidi | Ekran kapalıyken okuma. |
| Ön plan servisi + bağlı cihaz türü | Çeviri servisi. |
| Bildirim gönderme | Ön plan bildirimi (Android 13+ çalışma anında istenir). |
| Kamera + kamera türü ön plan servisi | HDMI yakalama kartı USB-C ile takılınca harici kamera görünür (Android 14+, her telefonda değil). Yalnız yakalama kartı seçiliyken çeviri başlarken istenir. Kamera donanımı zorunlu değildir. |
| Reklam kimliği izinleri | Kütüphanelerin eklediği reklam kimliği ve reklam atıf izinleri **çıkarılır**. |

Ayrıca:

- Yedekleme kapalı.
- Şifresiz HTTP'ye izin verilir (yerel ağdaki TV/PS5 ve deneme sunucusu için).
- Büyük bellek alanı istenir: uygulamayla gelen dokuz oyun paketi ~50 MB tutar; zayıf telefonda çeviri başlarken
  uygulama kapanıyordu.
- Ana ekran ve kurulum dikey kilitli; telefon altyazı ekranı yatay (sensörle iki yön).
- Ana etkinlik tek örnek açılır.
- Arayüz dili çeviri dilini izler (yalnız Türkçe ya da Arapça arayüz; telefon İngilizce olsa da). Android 12 ve
  öncesinde bu, her ekranın dil ayarı sarılarak yapılır.
- Meta SDK'nın kendiliğinden başlaması ve başlatıcısı kapatılır; uygulama ayara göre kendisi başlatır.

---

## Belirsizlikler

1. **Oturum bitiş olayındaki `lines` değeri** son çeviriler listesinin uzunluğundan alınıyor; liste 20'de
   kesildiği için gerçek satır sayısı değil, en çok 20. Yeni uygulamada gösterilen satır sayacının kullanılması
   gerekebilir; karar verilmeli.
2. **Klipte `source` parametresi** `remote_play` olarak gidiyor (klip için ayrı değer yok). Geliştirme yapısına özgü
   ama ölçümü kirletebilir.
3. **Bildirim metni PS5 için sabit "Türkçeye"** diyor; çeviri dili Arapça/Hintçe olsa da. Öbür dillerdeki karşılıklar
   incelenmedi (yalnız Türkçe kaynak metinler okundu).
4. **Bildirim izni reddedilirse** servis yine başlıyor; kullanıcıya bir şey söylenmiyor. Kasıtlı mı bilinmiyor.
5. **Ekranı açık tutma** yalnız çalışma durumu değişince yeniden değerlendiriliyor; çeviri sürerken ayarı değiştirmek
   o oturumda etki etmeyebilir.
6. **Ekrandan oyun tanıma zamanlaması** (8 sn sonra, olmazsa dakikada bir en çok 6 kez; tanınınca 5 dk sonra bir kez,
   sonra 20 dakikada bir doğrulama) yalnız açıklamalardan okundu; ilgili kural dosyası incelenmedi. Kare küçültme boyu
   gibi ayrıntılar da doğrulanmalı. Gönderildiği havuz ucu adı incelenmedi.
7. **Havuz sunucusunun çeviri, eşitleme, "buradayım", toplu çeviri ve satır önerisi uçlarının** adları ve gövdeleri bu
   belgenin kapsamındaki dosyalarda yok (havuz istemcisi ayrı). Ayrı bir belgede tarif edilmeli.
8. **Altyazı sunucusunun (SSE) olay biçimleri** ("started", stil, altyazı, ekran, katman, temizle), "çeviri başladı"
   balonunun sonradan bağlanan TV için geçerlilik süresi (açıklamada 20 sn) ve TV'nin bağlanma adresi bu belgede
   yalnız davranış düzeyinde geçiyor; ayrıntı kapsam dışındaki dosyada.
9. **Satır tutma/silme zamanlaması** (yarım okumanın ne kadar bekletildiği, altyazının TV'de ne zaman silindiği)
   okuma hattının dosyasında; burada incelenmedi.
10. **Xbox sabitleri**: kontrol kanalındaki yetkilendirme iletisinin `accessKey` değeri, el sıkışma ve yapılandırma
    iletilerindeki sabit kimlikler (GUID) ve istemci kurulum kimliği açık kaynak (MIT) Xbox oynatıcısının herkese açık
    sabitleridir; gizli olmasalar da "anahtar" adı taşıdıkları için buraya yazılmadı. Yeni uygulama bunları o
    oynatıcının kaynağından almalı. Microsoft istemci kimliği ve kapsamlar herkese açık olduğundan yazıldı.
11. **Xbox cihaz bilgisi başlığı** sabit bir Windows/Surface kimliği taklit ediyor; Microsoft bunu değiştirirse yayın
    açılmayabilir. İstemci sürüm numaraları (2203.1001.4.0, 8.5.2) eski kitaplıktan; güncelliği bilinmiyor.
12. **`no_picture` olayı** PS5 Remote Play tarafındaki dosyada üretiliyor; `next` ve `streak` parametrelerinin anlamı
    burada incelenmedi.
13. **Kullanım verisinin varsayılan açık olması** (opt-out) gizlilik politikası ve mağaza beyanlarıyla uyumlu olmalı;
    Meta yalnız karşılama ekranından sonra açılıyor. Karşılama ekranında kullanıcıya açıkça soruluyor mu bu belgede
    incelenmedi.
14. **Otomatik bildirimin gün sayacı** gönderim denemesinden önce artıyor; ağ hatasında saklanan bildirim sonraki
    açılışta gönderilse de o günün hakkından düşülmüş oluyor. Kasıtlı görünüyor ama doğrulanmalı.
15. **Yardımcıda fotoğraf küçültme** (600 KB sınırı) ekranda yapılıyor; uzun kenar ve kalite adımlarının Sorun
    Bildir'dekiyle aynı olduğu varsayıldı, doğrulanmadı.
16. **Önceki kapanış raporu** yalnız kullanım verisi açıkken Crashlytics'e gidiyor; `app_exit` olayı ise Firebase
    Analytics açıksa gidiyor (aynı anahtar). Meta'ya da adı yansıyor.
17. **Geçmişteki köken**: havuzdan gelen çeviriler de `engine` olarak yazılıyor (yalnız `pack` ayrı). Ayrı bir köken
    istenip istenmediğine karar verilmeli.
