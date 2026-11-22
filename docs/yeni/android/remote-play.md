# Android: PS5 Remote Play ve yakalama kartı (davranış tarifi)

Bu belge eski Android uygulamasının **ne yaptığını** anlatır, nasıl yazıldığını anlatmaz. Temiz-oda yeniden yazımı
için hazırlandı: eski koddan sınıf adı, işlev adı ya da kod parçası yok. Adı geçenler yalnız şunlar: chiaki-ng'nin
kamuya açık C API'si, Android'in kendi API'leri ve kullanıcıya gösterilen metinlerin `strings.xml` anahtarları.

Karşılaştırma için yeni çekirdeğin tarifi: `NinoCore/docs/tarif/remote-play.md`. Önemli farklar en sondaki
"Çekirdek tarifiyle farklar" bölümünde.

---

## 1. Genel resim

- Telefon, ikinci (ücretsiz) bir PSN hesabıyla PS5'e Remote Play üzerinden bağlanır. Yalnız **görüntü** alınır.
  Ses kapalıdır, kumanda girdisi gönderilmez.
- Görüntü H.264 olarak gelir. Android MediaCodec onu **yüzey kullanmadan** (ByteBuffer çıkışıyla) çözer. Karenin
  parlaklık (Y) düzlemi, arkasına eklenen yarım çözünürlüklü renk bilgisiyle birlikte Kotlin tarafına verilir.
- Kare kaynağı tek bir arayüzün arkasında durur: başlat, kapat (bloklamaz), gelen kare sayısı. Bu arayüzü
  karşılayan kaynaklar: PS5 Remote Play, yakalama kartı, debug yapısındaki kayıtlı klip ve Xbox. Kaynaktan iki
  dinleyici beslenir: "kare geldi" ve "durum değişti".
- Durum üç türlüdür: **Bağlanıyor**, **Akıyor**, **Koptu (tür + isteğe bağlı ayrıntı)**.
- Çeviri hizmeti bir ön plan hizmetidir (Android 14+ için tür: `connectedDevice`, yakalama kartında kamera).
  Çeviri sürdükçe kısmi uyanıklık kilidi (`PARTIAL_WAKE_LOCK`) ve Wi-Fi kilidi tutulur. Wi-Fi kilidi Android 10+'da
  `WIFI_MODE_FULL_LOW_LATENCY`, öncesinde `WIFI_MODE_FULL_HIGH_PERF` kipindedir.

## 2. PS5 bulma (keşif)

- chiaki-ng'nin keşif protokolü kullanılır. Yalnız IPv4 kullanılır ve **yalnız PS5 yanıtları** alınır
  (`chiaki_discovery_host_is_ps5`).
- Arama **yayınla (broadcast) değil, tek tek adreslere** gönderilir:
  - Adres verilmişse yalnız o adrese sorulur.
  - Verilmemişse telefonun özel ağ adresinin /24 ağındaki 1–254 arası bütün adreslere (telefonun kendi adresi
    hariç) sorulur. Telefonun adresi şöyle seçilir: açık, geri döngü olmayan arayüzler alınır; `rmnet*` (hücresel)
    ve `tun*` (VPN) atlanır; `wlan*` önce gelir; ilk özel IPv4 adresi (10/8, 172.16–31, 192.168/16) kullanılır.
- Hedef port PS5 keşif portudur (`CHIAKI_DISCOVERY_PORT_PS5`). Paket `CHIAKI_DISCOVERY_CMD_SRCH`, protokol
  sürümü `CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5`.
- Yanıt kaçmasın diye arama paketi süre dolana kadar **her 500 ms'de bir** bütün hedeflere yeniden gönderilir.
  Bu sırada çağrı bloklar.
- Her yanıttan şunlar alınır: adres, ad (yoksa "PS5"), uyanık mı (`CHIAKI_DISCOVERY_HOST_STATE_READY`), çalışan
  uygulamanın kimliği ve adı (ana ekranda ya da dinlenmede boş). Aynı adresten gelen son yanıt geçerlidir (PS5
  uyanınca durumu değişir). En çok 32 PS5 tutulur. ASCII dışı karakterler `?` yapılır, satır sonları boşluğa
  çevrilir.
- Kullanılan süreler:
  - Eşleme ekranı: tüm ağ 2,5 sn aranır. Ekran açık kaldıkça arama yinelenir: bir şey bulunamadıysa 1,5 sn sonra,
    bulunduysa 6 sn sonra. Hiç bulunamazsa elle adres alanı açılır. "Yeniden ara" düğmesi aramayı baştan başlatır.
    İlk bulunan PS5 kendiliğinden seçilir.
  - Oturum öncesi: kayıtlı adres 2 sn aranır.
  - Adres değişmiş olabilir diye yapılan tarama: tüm ağ 3 sn aranır (bkz. §7).
  - Çalışan oyunu sorma: bağlıyken 2 dakikada bir (ilki 30 sn sonra), kayıtlı adres 2 sn aranır. Çalışan oyunun
    kimliği ve adı ortak çeviri havuzunda oyunu tanımak için kullanılır.
- Elle yazılan adres temizlenir: port, `http://` gibi önekler ve virgüllü yazım ayıklanır. Adres geçersizse
  `address_invalid` gösterilir.

## 3. Uyandırma

- Uyandırma `chiaki_discovery_wakeup(log, NULL, adres, kimlik, true)` ile yapılır (son değer `true`: PS5).
- Kimlik, kayıttan dönen **kayıt anahtarından** (`rp_regist_key`) türetilir: anahtar ilk sıfır bayta kadar ASCII
  metin olarak okunur ve **onaltılık işaretsiz 64 bit** sayı olarak çözülür. Çözülemezse uyandırma yapılmaz.
- Uyandırmadan sonra **2 sn arayla** PS5 yeniden aranır. Uyanık görünce oturum açılır. **20 sn** içinde uyanmazsa
  durum dinlenmeden uyanmadı kopması olur (`phase_asleep`) ve normal yeniden bağlanma takvimi işler.

## 4. PSN hesap kimliği

- Hesap kimliği **8 bayttır** (`CHIAKI_PSN_ACCOUNT_ID_SIZE`). Kayıt ve oturum bu uzunluk dışında bir değeri kabul
  etmez.
- Kimlik nasıl alınır (Android'de elle girme alanı yok):
  1. Sony'nin OAuth giriş sayfası uygulama içi tarayıcıda (WebView) açılır. İstemci kimliği, kapsam ve yönlendirme
     adresi chiaki-ng'nin kamuya açık PSN akışındakilerle aynıdır (`.../remoteplay/redirect` adresine
     `response_type=code`, `prompt=always`).
  2. Tarayıcı yönlendirme adresine gidince adresteki tek kullanımlık `code` alınır. Adreste `error`,
     `error_description` ya da `error_code` varsa hata metni oluşturulur.
  3. `code` belirteç (token) adresinde erişim belirtecine çevrilir (Basic yetkili POST). Ardından belirteç bilgisi
     okunur ve içinden `user_id` alınır.
  4. `user_id` ondalık bir sayıdır. İşaretsiz 64 bit olarak okunur ve **8 baytlık little-endian** diziye çevrilir.
- Biçim: bellekte ve kayıtta 8 ham bayt. Saklarken ve günlükte **base64** (satır kırmasız, `NO_WRAP`) olarak
  yazılır. Masaüstüyle aynı biçimdir; 8 bayt base64'te 12 karakter tutar.
- Belirteç saklanmaz. Hesap kimliği şifreli ayar deposunda tutulur (AndroidKeyStore'da AES-GCM 256 anahtar,
  12 bayt IV + şifreli metin, base64). Çözülen değer 8 bayt değilse yok sayılır.
- Google ile girişte `accounts.google.com` WebView'i reddeder. O durumda giriş telefonun tarayıcısına taşınır ve
  kullanıcıdan adres çubuğundaki yönlendirme adresini yapıştırması istenir. Yapıştırılan metnin içinden adres
  ayıklanır. Kod tek kullanımlık olduğu için iş bitince pano temizlenir.
- Giriş sayfasının bekçisi:
  - Ekran açılınca önceki oturumun çerezleri silinir; en çok 5 sn beklenir.
  - Sayfa yüklendikten sonra her saniye sayfadaki giriş alanı ve düğme sayısına bakılır.
  - 20 sn içinde dokunulabilir bir öğe çıkmazsa hata ekranı gelir. Sayfa yüklendi ama boşsa
    `psn_problem_blank`, hiç yüklenmediyse `psn_problem_timeout` gösterilir.
  - WebView hata kodları: bağlantı/IO hataları `psn_problem_offline`, zaman aşımı `psn_problem_timeout`, SSL
    `psn_problem_ssl`, ana çerçevede HTTP hatası `psn_problem_http`, oluşturucu çökmesi `psn_problem_crashed`,
    diğerleri `psn_problem_other`. Hata ekranında `psn_page_failed` ve `psn_page_failed_hint` görünür.
- Belirteç aşamasının hataları: 429 ya da "too many / rate limit" metni hız sınırıdır; 400, 401 ve 403 red;
  diğerleri HTTP hatası; ağ hatası; okunamayan yanıt. Kullanıcı bunları `psn_failed` (`psn_failed`)
  içinde, istisna metniyle görür. Bu türler için ayrı bir strings anahtarı yok.

## 5. Kayıt (eşleme, PIN)

- Kullanıcı PS5'te ikinci hesapla "Uzaktan Oynatma › Cihaz bağla" ekranındaki **8 haneli kodu** girer. Giriş
  kuralı:
  - Boşluk, `-`, `–`, `.` ve `_` atlanır.
  - Unicode ondalık rakamlar kabul edilir ve rakam değerine çevrilir. Başka bir karakter varsa kod geçersizdir.
  - Tam 8 hane yoksa kod geçersizdir.
  - Sonuç tamsayı olarak gönderilir.
  - Arayüzde kod kutularına yalnız rakam ve en çok 8 hane girilebilir.
- Kayıt ayarları (`ChiakiRegistInfo`): hedef `CHIAKI_TARGET_PS5_1`, adres, `broadcast=false`,
  `psn_online_id=NULL`, 8 baytlık hesap kimliği, `pin` = kod, `console_pin=0`, delik açma ve RUDP yok.
- `chiaki_regist_start` başlatılır ve bitiş olayı en çok **30 sn** beklenir. Süre dolarsa `chiaki_regist_stop`
  çağrılır, bitiş olayı beklenir, ardından `chiaki_regist_fini`.
- Başarıda şunlar saklanır: PS5'in takma adı (`server_nickname`, ASCII dışı `?`), `rp_regist_key` (kayıt
  anahtarı) ve `rp_key` ("morning"). Adresle birlikte şifreli depoya JSON olarak yazılır; ikili alanlar base64
  tutulur.
- Sonuç kodu: başarı; PS5 reddetti ya da hata; yanıt yok (iptal/zaman aşımı); başlatılamadı. Ayrıca libchiaki
  günlüğünden toplanan **PS5 red nedeni** gelir: "Reported Application Reason: 0x…" satırı onaltılık olarak okunur.
  En çok 8 hata satırı da gelir.
- Kullanıcıya gösterilen neden (önce PS5 kodu, sonra günlük satırları):

| Durum | Anahtar |
|---|---|
| 0x80108b02 (PSN kimliği geçersiz) | `regist_wrong_account` |
| 0x80108b09 (kayıt başarısız: kod yanlış) | `regist_wrong_code` |
| 0x80108b10 (kullanımda) | `regist_in_use` |
| 0x80108b11 (sürüm uyumsuz) | `regist_version` |
| 0x80108b15 (PS5'te Remote Play çöktü) | `regist_crashed` |
| başka bir PS5 kodu | `regist_failed` |
| günlükte `getaddrinfo` | `regist_bad_address` |
| günlükte arama/bağlanma satırları ("search response", "connect for search", "send search", "Regist search failed", "connect for request", "Regist connect failed") | `regist_no_answer` |
| günlükte yanıt okuma satırları ("response HTTP header", "receiving/receive response content") ya da zaman aşımı | `regist_no_reply` |
| diğer | `regist_failed` |

- Metin `pair_failed` ("Bağlanamadı: %1$s") içinde gösterilir. PS5 kodu varsa parantez içinde ayrıntı olarak
  eklenir; yoksa ilk hata satırı eklenir.
- **Yeniden deneme:** yalnız "PS5 yanıt vermedi" (arama aşaması) durumunda, 500 ms arayla, toplam en çok **3 deneme**
  yapılır. Kod PS5'e gitmeden biten aşamada yeniden denemek güvenlidir. Diğer hatalarda hemen durulur.

## 6. Oturum açma ayarları

`ChiakiConnectInfo` şöyle doldurulur:

| Ayar | Değer |
|---|---|
| `ps5` | true |
| `host` | kayıtlı adres |
| `regist_key`, `morning`, `psn_account_id` | kayıttan; hesap kimliği 8 bayt |
| görüntü profili | `chiaki_connect_video_profile_preset` ile istenen yükseklik ≥ 1080 ise **1080p**, değilse 720p; kare hızı **30** (`CHIAKI_VIDEO_FPS_PRESET_30`). Uygulama hep 1920×1080 ister, yani pratikte 1080p30. |
| kodek | `CHIAKI_CODEC_H264` (HEVC istenmez) |
| bit hızı | ayrıca verilmez, kütüphanenin hazır profilindeki değer kullanılır |
| `video_profile_auto_downgrade` | true |
| `enable_keyboard`, `enable_dualsense` | false |
| `audio_video_disabled` | `CHIAKI_AUDIO_DISABLED` (ses kapalı, görüntü açık) |
| `auto_regist` | false |
| `holepunch_session`, `rudp_sock` | yok (yalnız yerel ağ) |
| `packet_loss_max` | 0.05 |
| `enable_idr_on_fec_failure` | true |

- Sıra:
  1. `chiaki_session_init`
  2. `chiaki_session_set_event_cb`
  3. `chiaki_session_set_video_sample_cb`
  4. `chiaki_session_ctrl_set_display_sink`
  5. `chiaki_session_start`
- **Görüntüleme alıcısı zorunludur:** PS5 korumalı içerik bildirdiğinde ("bu görüntü yayınlanamaz / yeniden
  yayınlanabilir") kütüphanenin denetim iş parçacığı `cantdisplay_cb` geri çağrısını koşulsuz çağırır. Atanmazsa
  uygulama SIGSEGV ile çöker. Gelen bildirim yalnız günlüğe yazılır ve akış sürer.
- Çözücü, oturumdan **önce** kurulur. Kurulamazsa oturum başlatılmaz ve çözücünün açılamadığını
  söyleyen bir hata döner.
- Kapanış sırası: `chiaki_session_stop` → `chiaki_session_join` → `chiaki_session_fini` → çözücüyü kapat. Kapanış,
  oturumun kendi geri çağrısından değil, oturumu yöneten tek iş parçacıklı kuyruktan yapılır. Kapanış dönünce bir
  daha kare gelmez.

## 7. Bağlanma akışı ve yeniden bağlanma

Bütün oturum işleri **tek bir sıralı kuyrukta** yürür. Her başlatma ya da yeniden kurma bir "kuşak" numarasını
artırır. Eski kuşaktan gelen olay ve zamanlayıcılar yok sayılır.

1. Durum **Bağlanıyor** olur.
2. Kayıtlı adres 2 sn aranır.
   - Yanıt yoksa ve son 30 sn içinde tarama yapılmadıysa tüm ağ 3 sn taranır. Bulunanlardan **aynı adlı tek PS5**
     seçilir. Aynı adlı yoksa ve ağda yalnız bir PS5 varsa o seçilir. Birden çok aday varsa seçim yapılmaz. Adres
     değiştiyse yeni adres kalıcı olarak kaydedilir.
   - Arama hiç yanıt almadıysa yine de bağlanılmaya çalışılır, ama bu bilgi saklanır (bkz. "bulunamadı" kuralı).
3. PS5 dinlenmedeyse uyandırılır (§3). Uyanıksa oturum açılır.
4. `CHIAKI_EVENT_CONNECTED` gelince durum **Akıyor** olur, geri çekilme sayacı sıfırlanır ve görüntü bekçisi
   başlar (§9).
5. Oturum düşerse (`CHIAKI_EVENT_QUIT`) neden sınıflanır (§10). Durum yayınlanır ve yeniden bağlanma kurulur.

**Geri çekilme (backoff):** sırayla 2, 4, 8, 16, 30, 30… sn; üst sınır 30 sn. Bağlantı kurulunca, kullanıcı
başlatınca ya da elle yeniden bağlanınca sıfırlanır. Oturum başlatılamazsa da (init/start hatası) aynı takvimle
yeniden denenir.

**"Bulunamadı" kuralı:** son aramada PS5 yanıt vermediyse ve kopma nedeni "ağ" ya da "diğer" ise kullanıcıya
adresli bulunamadı metni gösterilir (`phase_not_found_host`).

**Yeniden denenmeyen durumlar:** oturum durdurulur, döngüye girilmez ve kullanıcı uyarılır.
- Kayıt geçersiz (`phase_registration_invalid`)
- PS5'te Uzaktan Oynama kapalı (`phase_remote_play_disabled`)
- Giriş şifresi yok ya da yanlış (`phase_passcode`, `phase_passcode_incorrect`)
- Art arda görüntüsüz oturumlar (`phase_no_picture`)

**Elle yeniden bağlanma** (ağ değişince kullanılmak üzere) işlemi şunları yapar: oturumu kapatır, geri çekilmeyi
ve bekçiyi sıfırlar, hemen bağlanır. (Belirsizlikler'e bakın: eski kodda bu işlemi çağıran yer bulunamadı.)

## 8. Giriş şifresi (passcode)

- PS5'te ikinci hesabın giriş şifresi açıksa PS5 `CHIAKI_EVENT_LOGIN_PIN_REQUEST` olayını gönderir. Olayın
  `pin_incorrect` alanı, önceki şifrenin yanlış olduğunu bildirir.
- Şifre Ayarlar'da saklanır (şifreli depo). Tam **4 ASCII rakam** olmalıdır; boşluklar kırpılır, başka bir değer
  "yok" sayılır.
- Kural:
  - İlk istekte kayıtlı şifre varsa ASCII baytlar olarak `chiaki_session_set_login_pin` ile gönderilir.
  - Şifre yoksa oturum kapatılır ve `phase_passcode` gösterilir.
  - `pin_incorrect` geldiyse aynı şifre **yeniden gönderilmez**. Oturum kapatılır ve `phase_passcode_incorrect`
    gösterilir.
- Şifre olay geri çağrısının içinden gönderilmez, kuyruğa atılır: kütüphane olayı kendi durum kilidini tutarken
  verir.

## 9. Görüntü bekçisi (watchdog)

Bağlıyken **saniyede bir** bakılır.

| Süre | Anlamı |
|---|---|
| **5 sn** | Bağlandıktan sonra ilk kare bu sürede gelmezse takılma sayılır. |
| **8 sn** | Görüntü gelmişken bu kadar süre yeni kare gelmezse takılma sayılır. IDR ile olağan toparlanma 1 sn'den kısa sürer. |
| **3 oturum** | Art arda bu kadar oturumda hiç görüntü gelmezse vazgeçilir. |

- Bekçinin gerekçesi: FEC onarımı tutmayınca kütüphane bir kez IDR (anahtar kare) ister. İstenen IDR de bozuk
  gelirse yeniden istemez. Bağlantı açık kalır ama hiç kare gelmez. Yeni oturum anahtar kareyle başlar.
- Takılma olunca:
  - Oturumda görüntü gelmişti: oturum kapatılır ve **aynı çözücü türüyle** yeniden kurulur. Ekranda
    `phase_reconnecting` görünür.
  - Oturumda hiç görüntü gelmedi: art arda görüntüsüz oturum sayacı artar. Sonraki oturum **öbür çözücü türüyle**
    (yazılım ↔ donanım) açılır. Sayaç tekse türler değiştirilir, çiftse üreticiye göre seçilen türle başlanır.
  - Sayaç 3'e ulaştı: durulur ve `phase_no_picture` gösterilir. Hata raporlama servisine de gönderilir.
- Kare gelince görüntüsüz oturum sayacı sıfırlanır. Kullanıcı başlatınca da sayaç sıfırlanır. Bağlı değilken gelen
  geç kare bekçiyi kurmaz. Oturum kapanınca bekçi "bağlı değil" durumuna geçer.
- Her takılma bir tanı olayı olarak kaydedilir: ne yapıldığı, sayaç ve kare sayısı.

## 10. Kopma nedenleri → kullanıcıya gösterilen

Kütüphanenin `ChiakiQuitReason` değeri önce kaba bir gruba ayrılır:

| chiaki nedeni | Grup |
|---|---|
| `STOPPED` | durduruldu (mesaj yok) |
| `SESSION_REQUEST_RP_IN_USE` | kullanımda |
| `SESSION_REQUEST_CONNECTION_REFUSED`, `CTRL_CONNECTION_REFUSED`, `PSN_REGIST_FAILED` | reddedildi |
| `STREAM_CONNECTION_REMOTE_DISCONNECTED`, `..._REMOTE_SHUTDOWN`, `CTRL_CONNECT_FAILED`, `STREAM_CONNECTION_UNKNOWN` | ağ |
| diğer | diğer (metin: `chiaki_quit_reason_string`) |

"Diğer" grubundaki nedenin metni "Session Request" içeriyorsa (ör. "Unknown Session Request Error") oturumun hata
satırlarına bakılır. Satırlar eskiden yeniye taranır ve son anlamlı satır kazanır:
- "Reported Application Reason: 0x…" satırı:
  - 0x80108b12 → Uzaktan Oynama kapalı (durulur)
  - 0x80108b09, 0x80108b02, 0x80108b26 → kayıt geçersiz (durulur)
  - başka bir kod → "reddetti", ayrıntıda `0x%08x` biçiminde kod; yeniden denenir
- "Session request connect failed eventually", "Failed to send session request" ya da "Failed to receive session
  request response" → ağ.
- Hiçbiri tutmazsa ve metin tam "Unknown Session Request Error" ise → "reddetti", kodsuz.

Gösterilen metinler:

| Durum | Anahtar |
|---|---|
| Bağlanıyor | `phase_connecting` (yakalama kartında `capture_phase_opening`) |
| Akıyor | `phase_streaming` |
| kullanımda | `phase_in_use` |
| bulunamadı (adresli / adressiz) | `phase_not_found_host` / `phase_not_found` |
| ağ | `phase_network` |
| kayıt geçersiz | `phase_registration_invalid` |
| Uzaktan Oynama kapalı | `phase_remote_play_disabled` |
| reddetti (kodlu / kodsuz) | `phase_rejected_code` / `phase_rejected` |
| görüntü yok (vazgeçildi) | `phase_no_picture` |
| dinlenmeden uyanmadı | `phase_asleep` |
| şifre yok / yanlış | `phase_passcode` / `phase_passcode_incorrect` |
| reddedildi (grup) | `phase_refused` |
| diğer, bekçi yeniden kurması | `phase_reconnecting` |
| yakalama kartı yok / izin yok / siyah | `capture_not_found` / `capture_no_permission` / `capture_black` |

Başlamadan önce yapılan denetimler:
- Eşleme ya da hesap kimliği yoksa `error_not_paired` gösterilir.
- Yerel kütüphane yüklenemezse `error_native` gösterilir. Kütüphanenin yüklenmesi, yükleme sırasında
  `chiaki_lib_init` çağrısının başarılı olmasına bağlıdır.

Bağlanamama nedeni, yeniden bağlanırken de ana ekranda kalır. Bir sorun bildirimi düzeneği de vardır: kopma 3 dk
sürerse kendiliğinden bildirim gönderilir. Bu düzenek yalnız durum türünün adını alır; adres ya da ekran metni
gönderilmez.

## 11. Görüntünün çözülmesi (MediaCodec)

**Giriş tarafı** kütüphanenin görüntü örneği geri çağrısıdır. Gelen veri sıkıştırılmış H.264 örneğidir.
- Çözücü ayarları:
  - MIME `video/avc`
  - Genişlik ve yükseklik: istenen boy (1920×1080)
  - Renk biçimi `COLOR_FormatYUV420Flexible` (0x7F420888)
  - `low-latency` = 1 (Android 11+; desteklemeyen cihaz yok sayar)
  - Yüzey yok. `configure` çağrısında yüzey verilmez; çıkış arabelleği `render=false` ile geri bırakılır.
- **Akış başlığı (SPS/PPS):** kütüphane başlığı profil başında **bir kez** verir ve geri çağrının dönüş değerine
  bakmaz. Bu yüzden başlık şöyle ele alınır:
  - Bir örneğin başlık olduğu, Annex-B başlangıç kodundan sonraki ilk NAL türünün 7 (SPS) olmasından anlaşılır.
  - Başlık **saklanır**. Her yeni çözücüye (türü değişen çözücü dahil) ilk örnekten önce verilir.
  - Başlık için giriş arabelleği 500 ms beklenir. Olağan örnekler için bu süre 10 ms'dir.
- Giriş arabelleği alınamazsa örnek atlanır ve geri çağrı "başarısız" döner. Kütüphane bunu bozuk kare sayıp
  anahtar kare ister. Boş arabellek gelirse çökmeden atlanır.
- Zaman damgası her örnekte 1 artar (gerçek zamanlı davranış).
- **Çözücü türü seçimi:**
  - Üretici Samsung ise **yazılım** çözücüyle başlanır (sırayla `c2.android.avc.decoder`, `OMX.google.h264.decoder`).
    Diğer üreticilerde varsayılan (donanım) çözücüyle başlanır.
  - Önceki oturumda görüntü gelmediyse bu seçimin tersiyle başlanır (§9).
  - Seçilen tür açılamazsa öbür tür denenir.
  - Donanım çözücü **art arda 30 hata** verirse ya da **okunamayan bir çıkış biçimi** bildirirse durdurulur ve
    yazılım çözücüyle yeniden kurulur. Yazılım çözücü de açılamazsa görüntü gelmez, süreç çökmez; bekçi oturumu
    yeniden kurar.
  - Bir kare başarıyla çıkınca hata sayacı sıfırlanır.

**Çıkış tarafı** ayrı bir iş parçacığında çalışır. Çıkış arabelleği 100 ms beklenir. Hata durumundaki çözücüde
işlemciyi yakmamak için 10 ms uyunur.
- Çıkış biçimi "biçim değişti" bildiriminde okunur. Bildirim gelmezse ilk karede okunur. Okunan değerler: renk
  biçimi, en, boy, `stride`, `slice-height`, `crop-left/top/right/bottom`. Kırpma yoksa tam kare alınır.
- Okunabilir sayılan, Y düzlemi ilk sırada ve doğrusal olan biçimler: 19 (I420), 20, 21 (NV12), 39, 0x7F420888,
  0x7FA30C04 (Qualcomm hizalı NV12), YV12 (0x32315659), NV21 (0x11) ve 0x23.
- Döşemeli ya da sıkıştırılmış satıcı biçimleri (ör. Qualcomm UBWC 0x7FA30C03, Samsung 0x7FC00002) okunmaz. Bu
  durumda kare atlanır ve yazılım çözücüye geçilir.
- Ek koşullar: `stride` ≥ en ve ≤ 16384; görünür alanın iki kenarı da en az 16 piksel.
- Arabellek, biçimin söylediğinden küçükse kare atlanır (bir kez günlüğe yazılır). Sınır dışı okuma hiç yapılmaz.
- **Kare çıktısı:**
  - Görünür Y bölgesi **sıkıştırılarak** (satır aralığı = en) uygulamanın sahip olduğu doğrudan bir ByteBuffer'a
    kopyalanır. Arabellek gerekirse büyütülür; bellek yetmezse kare atlanır.
  - Y'nin hemen arkasına yarım çözünürlüklü renk **NV12 sırasıyla** (U, V, U, V…; satır başına `2 × (en/2)` bayt)
    eklenir:
    - NV21'de U ve V yer değiştirilir.
    - I420 ve YV12'de düzlemler birleştirilir. YV12'de renk satırı 16'ya hizalıdır.
    - Esnek biçimlerde (0x7F420888, 0x23) NV12 varsayılır.
    - Renk kopyalanamazsa kare yine verilir; yalnız "renk var" bayrağı kapalı olur.
  - Dinleyiciye şunlar verilir: arabellek, en, boy, satır aralığı (= en), çözücünün renk biçimi ve "renk var"
    bayrağı.
  - Dinleyici **çözücünün çıkış iş parçacığında** çağrılır. Arabellek **yalnız çağrı süresince geçerlidir**; sonraki
    kare aynı arabelleğe yazılır. Dinleyici kısa sürmelidir.
  - Kare sayacı artırılır.
- **Durdurma güvenliği:**
  - Çözücü, çıkış arabelleği okunurken durdurulmaz.
  - Durdurma sırası: önce çıkış iş parçacığına "dur" denir, okuma kilidi alınır, çözücü durdurulur, iş parçacığı
    beklenir, sonra çözücü silinir.
  - Kilit sırası sabittir: önce çözücü kilidi, sonra çıkış kilidi.
- Neden yüzey ve ImageReader kullanılmıyor: bazı cihazlarda (Samsung, Xiaomi, Honor; Android 15–17) çözücü karesi
  işlemciden okunamıyordu. `Image.getPlanes()` yerel kodda SIGABRT ile süreci düşürüyordu ve bu hata Java'dan
  yakalanamıyordu.

## 12. Kareden OCR'a ve diğer kullanıcılara

- Kareler 30 kare/sn gelir. **Altyazı okuma, kare sayısıyla değil zamanla seyreltilir:**
  - Saniyede en çok **5** okuma yapılır, yani iki okuma arası en az 200 ms.
  - Bir okuma sürerken yeni okuma başlatılmaz.
  - Okunacak bölge kareden kopyalanır, okuma ayrı bir iş parçacığında yapılır.
  - Altyazının yeri öğrenildiyse yalnız o şerit okunur.
- Bölge kopyası NV21 olarak çıkar: Y alınır, renk nötr (128) yapılır. Kare biçimine uymayan bölge (arabellek
  küçük, satır aralığı enden küçük) atlanır.
- Ek alanlar saniyede bir, kendi iş parçacığında okunur.
- **Renkli kopya:** en çok 960×540 olur, oranlı küçültülür, en yakın nokta örneklenir. Renk dönüşümü BT.601,
  sınırlı aralık (16–235). Yalnız gerekince ve karede bir kez çıkarılır; oyundaki telefon ve harita kartını
  bulmakta kullanılır. Renk yoksa telefon aranmaz. Yazı tanıma bunu kullanmaz, tam çözünürlüklü parlaklığı okur.
- **Canlı önizleme** (Ayarlar › Altyazı alanı): yalnız açıkken çalışır. Saniyede bir, 320 piksel enli gri bir
  kopya üretir.
- Oyunu ekrandan tanıma için kareden küçük, gri bir kopya alınır ve zamanlaması ayrıdır.
- Kare sayısı 2 sn'de bir sağlık göstergesine yazılır (tanı amaçlı).

## 13. Yerel köprü (JNI): ne yapabilmeli

**Kotlin'den çağrılabilen işlemler** (hepsi arka planda çağrılır, bir kısmı bloklar):

| İşlem | Davranış |
|---|---|
| Başlat | Kütüphaneyi bir kez başlatır (`chiaki_lib_init`). Sonuç 0 değilse Remote Play "yok" sayılır. |
| Ara | Adres listesi ve süre alır, bloklar. Bulunan PS5'leri döndürür: adres, ad, uyanık, çalışan uygulama kimliği ve adı. |
| Uyandır | Adres ve 64 bit kimlik alır. Hata kodunu döndürür. |
| Kaydet | Adres, 8 bayt hesap kimliği ve 8 haneli kod alır. En çok yaklaşık 30 sn bloklar. Döndürdükleri: sonuç kodu, PS5 red kodu, hata satırları; başarıda takma ad, kayıt anahtarı, morning. |
| Oturum aç | Adres, kayıt anahtarı, morning, hesap kimliği, en/boy, kare dinleyicisi, "çözücü türünü ters çevir" bayrağı ve olay dinleyicisi alır. Bir oturum tutamacı döndürür; başarısızsa 0 ve hata metni. |
| Oturumu kapat | Durdurur ve iş parçacıklarını bekler. Dönünce bir daha olay ya da kare gelmez. Her oturum için bir kez çağrılır, geri çağrının içinden çağrılmaz. |
| Giriş şifresi gönder | ASCII rakamları alır, 0 başarıdır. Olay geri çağrısından değil, kuyruktan çağrılır. |
| Oturum hata satırları | Kütüphane günlüğünden toplanan hata satırları (en çok 8). |
| Oturum kare sayısı | Tanı amaçlı. |

**Yerelden geri gelen olaylar:**
- **Oturum olayı** (kütüphanenin iş parçacığından gelir; o iş parçacığı JVM'e bağlanıp ayrılır):
  - **bağlandı**
  - **giriş şifresi istendi** (+ "önceki yanlıştı" bayrağı)
  - **oturum bitti** (+ neden grubu: durduruldu / kullanımda / reddedildi / ağ / diğer, ve metin; "diğer"de
    kütüphanenin neden metni)
- **Kare** (çözücünün çıkış iş parçacığından gelir): arabellek, en, boy, satır aralığı, renk biçimi ve "renk var"
  bayrağı (§11).

**Günlük:**
- Hata, uyarı ve bilgi düzeyleri Android günlüğüne yazılır.
- Hata düzeyindeki satırlardan en çok 8'i biriktirilir. "Reported Application Reason: 0x…" satırındaki kod ayrıca
  saklanır; PS5 red nedeni olaya değil yalnız günlüğe yazılır.
- Java'ya giden bütün metinlerde ASCII dışı baytlar `?` yapılır, çünkü JNI'nin dize oluşturucusu geçersiz UTF-8'de
  bozulur.

## 14. chiaki-ng: kullanılan C API

- Genel: `chiaki_lib_init`, `chiaki_log_init`, `chiaki_error_string`, `chiaki_quit_reason_string`,
  `chiaki_time_now_monotonic_ms`, `chiaki_mutex_*`, `chiaki_cond_*` (`chiaki_cond_timedwait_pred`,
  `chiaki_cond_wait_pred`), `chiaki_thread_create`, `chiaki_thread_join`, `chiaki_thread_set_name`.
- Keşif: `chiaki_discovery_init`, `chiaki_discovery_thread_start`, `chiaki_discovery_send`,
  `chiaki_discovery_thread_stop`, `chiaki_discovery_fini`, `chiaki_discovery_host_is_ps5`,
  `chiaki_discovery_wakeup`.
- Kayıt: `chiaki_regist_start`, `chiaki_regist_stop`, `chiaki_regist_fini` (olay türleri
  `CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS/_CANCELED/_FAILED`).
- Oturum: `chiaki_connect_video_profile_preset`, `chiaki_session_init`, `chiaki_session_set_event_cb`,
  `chiaki_session_set_video_sample_cb`, `chiaki_session_ctrl_set_display_sink`, `chiaki_session_start`,
  `chiaki_session_set_login_pin`, `chiaki_session_stop`, `chiaki_session_join`, `chiaki_session_fini`.
- Kullanılan olaylar: `CHIAKI_EVENT_CONNECTED`, `CHIAKI_EVENT_LOGIN_PIN_REQUEST`, `CHIAKI_EVENT_QUIT`. Diğer olaylar
  yok sayılır.
- Görüntü geri çağrısının imzası: (arabellek, boy, kayıp kare sayısı, kare toparlandı mı, kullanıcı). Kayıp ve
  toparlanma bilgileri kullanılmaz.

## 15. Derleme (CMake / Gradle)

- chiaki-ng, depoda alt modül olarak durur (`third-party/chiaki-ng`, resmî depo; eski kodun işaret ettiği commit
  `0c4a45df…`). CMake ile alt dizin olarak eklenir; uygulamanın kendi hedefi dışındaki hedefler derlenmez.
  Uygulamanın paylaşımlı kütüphanesi `chiaki-lib`, `log`, `mediandk` ve `android` ile bağlanır.
- **Kapalı:** `CHIAKI_ENABLE_GUI`, `CHIAKI_ENABLE_CLI`, `CHIAKI_ENABLE_TESTS`, `CHIAKI_ENABLE_FFMPEG_DECODER`,
  `CHIAKI_ENABLE_PI_DECODER`, `CHIAKI_LIB_ENABLE_OPUS`, `CHIAKI_ENABLE_SPEEX`, `CHIAKI_ENABLE_SETSU`,
  `CHIAKI_ENABLE_STEAMDECK_NATIVE`, `CHIAKI_ENABLE_STEAM_SHORTCUT`, `CHIAKI_ENABLE_BOREALIS`, `BUILD_SHARED_LIBS`.
  curl'ün ek özellikleri de kapalıdır: `USE_NGHTTP2`, `USE_LIBIDN2`, `CURL_ZSTD`, `CURL_BROTLI`, `CURL_USE_LIBPSL`,
  `CURL_USE_LIBSSH2`, `USE_LIBRTMP`, `CURL_ZLIB` kapalı, `CURL_DISABLE_LDAP` açık.
- **Açık:** `CHIAKI_LIB_OPENSSL_EXTERNAL_PROJECT`, `CHIAKI_LIB_JSONC_EXTERNAL_PROJECT`,
  `CHIAKI_LIB_MINIUPNPC_EXTERNAL_PROJECT`. Android'de bu kütüphaneler sistemde olmadığı için chiaki-ng'nin kendi
  tarifleriyle kaynaktan, durağan derlenir. `CHIAKI_ENABLE_ANDROID` de açıktır; libevent'i devre dışı bırakır.
- `CHIAKI_ENABLE_ANDROID`, chiaki-ng'nin kendi Android uygulama hedefini de yapılandırmaya katar. O hedef oboe'yu
  arar. Hedef hiç derlenmediği için boş bir oboe paket tanımı verilir.
- Gradle tarafı:
  - NDK 27.0.12077973, CMake 3.22.1
  - Yalnız uygulamanın kendi yerel hedefi derlenir
  - `ANDROID_STL=c++_static`
  - nanopb kod üreteci için `protobuf` paketli bir Python yolu verilir
  - ABI varsayılan olarak yalnız `arm64-v8a`
  - minSdk 26
  - Yerel kısım bir bayrakla tümden atlanabilir; o zaman Remote Play "yok" olur.
- **16 KB sayfa:** Android 15+ ve Play şartı nedeniyle bağlayıcıya `max-page-size=16384` ve
  `common-page-size=16384` verilir, `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`. chiaki ve OpenSSL durağan bağlandığı
  için hizayı yalnız son bağlama belirler.
- Sembol görünürlüğü varsayılan olarak gizlidir; yalnız JNI girişleri dışa açılır.

### Eski projeye özel yamalar (amaçları)

- **Takion gönderim arabelleği yaması** (`chiaki-takion-send-after-close.patch`): kapanış sırasında akış
  bağlantısı "bağlantıyı kes" iletisini gönderirken Takion'un iş parçacığı çoktan bitmiş ve gönderim arabelleği
  serbest bırakılmış olabiliyordu. Bu da serbest bırakılmış belleğe yazma ve çökme demekti. Yama, arabelleğe
  "canlı" bayrağı ekler. Kapandıktan sonra gelen gönderimler sessizce reddedilir ve veri serbest bırakılır.
  Kapanışta işaretçi ve sayaçlar sıfırlanır.
- **nanopb sembol öneki** (`chiaki-nanopb-prefix.h`): yalnız Mac ve iOS derlemesinde kullanılır, Android'de
  kullanılmaz. Uygulamaya başka bir nanopb sürümü (iOS'ta Firebase'in 0.3'ü) bağlanınca bağlayıcı yanlış
  kodlayıcıyı seçiyordu ve oturum protobuf kodlama hatasıyla düşüyordu. Başlık, chiaki'nin derlediği nanopb'nin
  bütün dış sembollerine önek ekler.
- **Yama betiği** (`scripts/patch-chiaki.sh`): `.patch` dosyalarını alt modüle uygular; zaten uygulanmışsa atlar.
  Android'de varsayılan olarak çalışmaz. CI, Android derlemesinde bir Gradle bayrağıyla derlemeden önce çalıştırır.
  Yerel derlemede yamanın uygulanması geliştiriciye kalır.

## 16. Yakalama kartı (USB UVC / harici kamera)

- Kullanıcı kaynak olarak "Capture Card"ı seçerse PS5 Remote Play yerine bu kaynak kullanılır. PSN hesabı, eşleme
  ve yerel kütüphane gerekmez.
- Kart, Camera2'de **harici kamera** olarak görünür (`LENS_FACING_EXTERNAL`). Bu, USB-C OTG ile Android 14+'ta ve
  yalnız bazı telefonlarda olur.
  - Telefonun kendi ön ve arka kameraları **asla** seçilmez.
  - `YUV_420_888` çıkışı veren ilk harici kamera seçilir.
  - Manifestte kamera izni vardır; `camera` ve `camera.external` özellikleri zorunlu değildir.
- Kamera listesini okumak izin istemez. Kaynak ekranında kart takılı mı, hangi boyu verebiliyor gösterilir
  (`capture_found_title`, `capture_found_detail`, `capture_missing_title`, `capture_missing_detail`). Kamera izni
  yoksa kaydetmeden önce izin istenir.
- **Boy seçimi:**
  - 1920×1080 varsa o seçilir.
  - Yoksa 16:9 boylar arasından alanca 1080p'ye en yakını seçilir; eşitse büyüğü.
  - 16:9 boy yoksa herhangi bir boydan en yakını seçilir.
- Akış: `ImageReader` (`YUV_420_888`, 3 kare) ve `TEMPLATE_PREVIEW` ile sürekli istek. Her zaman **en son** kare
  alınır. Eski kare atılır ve kare işlendikten sonra hemen kapatılır.
  - Kareden Y düzlemi kırpma köşesinden başlatılarak verilir (satır aralığı kameranınki).
  - Renk düzlemleri de yarım çözünürlükte, kameranın satır ve piksel adımlarıyla verilir.
  - Kare yalnız çağrı süresince geçerlidir.
- **Durumlar:**
  - Açılırken **Bağlanıyor** (`capture_phase_opening`), ilk karede **Akıyor**.
  - Kart yok ya da açılamadı: `capture_not_found`.
  - İzin yok ya da güvenlik hatası: `capture_no_permission`.
  - **Siyah görüntü:** yarım saniyede bir, Y'den 32 pikselde bir örnek alınır. En parlak örnek bile 24'ün
    altındaysa kare siyah sayılır. **4 sn** siyah kalırsa `capture_black` gösterilir (HDCP açık ya da PS5 kapalı).
    Görüntü dönünce yeniden **Akıyor** olur.
  - Aynı durum art arda iki kez bildirilmez.
- **Takıp çıkarma:**
  - Kamera erişilebilirlik bildirimi dinlenir. Kart takılınca ya da başka bir uygulama kamerayı bırakınca kendiliğinden
    yeniden açılır.
  - Kart çıkarılınca ya da kamera hatası olunca kapatılır ve "kart yok" bildirilir.
  - Başarısız açılıştan sonra **2 sn** dolmadan yeniden denenmez. Kapanan kamera hemen "erişilebilir" görünür ve
    bu beklemeyle döngü önlenir. Hata olursa 2 sn sonra yeniden denenir.
- Bütün kamera işleri tek bir arka plan iş parçacığında yürür. Kapatma bloklamaz.

## 17. Çekirdek tarifiyle farklar

| Konu | Eski Android | Çekirdek tarifi |
|---|---|---|
| Çözünürlük | 1080p30 | 720p30 |
| Kodek | H.264 (HEVC istenmez) | H.264 ya da HEVC |
| Seyreltme | zamanla: en çok 5 okuma/sn, okuma sürerken atla | her 4. kare |
| Hesap kimliği | PSN girişiyle alınır (elle giriş yok) | kullanıcı girer |
| Bulma | /24 ağa tek tek adresli arama | kütüphane keşfi |
| Kopunca | kendiliğinden yeniden bağlanır | akış biter, uygulama yeniden bağlanmayı önerir |
| Şifreleme kütüphanesi | OpenSSL (chiaki dış projesi, durağan) | OpenSSL 3 |

- Ses kapalı, kumanda yok: ikisinde de aynı.
- Kare kuyruğu: eskide kare çağrı süresince geçerlidir ve tüketici yavaşsa bekletilmez, okuma atlanır. Çekirdekte
  "en yeni 1 kare" tamponu vardır. Sonuç benzerdir.

## Belirsizlikler

- **Ağ değişince yeniden bağlanma:** oturumda "elle yeniden bağlan" işlemi var, ama eski kodda onu çağıran yer
  bulunamadı. Ağ değişimi yalnız sağlık izleyicisine bildiriliyor. Kopma, olağan geri çekilmeyle mi toparlanıyor,
  yoksa başka bir yerden mi tetikleniyor, doğrulanmalı.
- **Bit hızı:** uygulama bit hızını ayrıca vermiyor; kullanılan değer, chiaki-ng'nin 1080p hazır profilindeki
  değerdir. Kesin sayı, kullanılacak chiaki-ng sürümünden okunmalı.
- **Esnek renk biçimleri:** 0x7F420888 ve 0x23'te renk düzeninin NV12 olduğu varsayılıyor. Yanlışsa renkler bozuk
  çıkar (bellek taşmaz). Bu, cihaz cihaz doğrulanmadı.
- **Samsung kuralı:** Samsung'da yazılım çözücüyle başlama kararı saha deneyimine dayanıyor, ölçülmüş bir gerekçesi
  yok. Diğer üreticiler (Honor, Xiaomi) için kural yok; yalnız hata sonrası geçiş var.
- **0x80108b26** (PS5 kaydı tanımıyor) yalnız oturum aşamasında "kayıt geçersiz" sayılıyor. Kayıt aşamasında karşılığı
  yok ve genel hataya düşüyor.
- **Yama durumu:** yerel Android derlemesinde Takion yamasının uygulanıp uygulanmadığı alt modülün o anki haline
  bağlı. Bu çalışma kopyasında alt modül çekilmemiş, kontrol edilemedi.
- **Çalışan oyunu sorma** keşif paketiyle yapılıyor. Bu, oturum açıkken ağda ek trafik demek; PS5'in buna her
  sürümde yanıt verip vermediği bilinmiyor.
- **PSN istemci bilgileri** chiaki-ng'nin kamuya açık değerleri. Sony bunları değiştirirse giriş bozulur; bir
  yedek yol yok.
- **Giriş şifresi:** 4 haneli kural PS5'in bugünkü davranışına göre. Şifre ilk istekten önce bilinmiyorsa
  kullanıcıya oturum sırasında sorulmuyor; doğrudan durup Ayarlar'a yönlendiriliyor.
