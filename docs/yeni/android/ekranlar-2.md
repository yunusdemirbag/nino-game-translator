# Nino Android: ekranlar (2. bölüm)

Bu belge yalnız davranışı ve görünüşü tarif eder. Ortak bileşenlerin (üst çubuk, karo, satır listesi, birincil /
ikincil / hayalet / yıkıcı düğme, not karosu, alan, segmentli seçim, durum etiketi, anahtar, kaydırıcı, koyu sahne kartı,
camsı satır, seçilebilir cam kutu, iletişim kutusu) kendi görünüşü `ekranlar-1.md`'de. Burada yalnız bu ekranlarda
hangisinin nerede, hangi sırayla durduğu yazıyor.

Metinler yalnız anahtar adıyla anılır; metnin kendisi yeni uygulamanın `apps/android/app/src/main/res/values/strings.xml` dosyasındadır (o dosyada yoksa yanında anlamı yazılır). `%1$s`, `%1$d` yer tutucudur.

## Ortak kurallar

- Renkler (açık tema): zemin #EEF3FB, ikinci yüzey #E6EDF8, yükseltilmiş yüzey #FFFFFF, yazı #0A1430, ikincil yazı
  #55607A, vurgu (mavi) #0070D1, vurgu yazısı #0058A8, vurgu üstü yazı #FFFFFF, güçlü kenar #D3DEEF, koyu mavi ("pro")
  #00205B, başarı #1E6B45, uyarı #9A4A08, tehlike #B3261E.
- Boşluklar: ekran kenarı 20 dp, öğeler arası 12 dp, iç boşluk 8 dp, ince boşluk 4 dp. Simge düğmesi 44 dp.
- Ekranların çoğu aynı iskelette: üstte üst çubuk (geri oku, isteğe bağlı başlık ve sağda eylem), ortada kayan içerik
  (öğeler alt alta, 12 dp arayla), isteğe bağlı altta sabit düğme alanı.
- Telefon / tablet: bu bölümdeki ekranların hiçbirinde ayrı bir tablet düzeni yok; iskelet ne yapıyorsa o (bkz.
  ekranlar-1). Tablette yalnız ekran döndürülünce durumların kaybolmaması önemli (PSN tarayıcı girişi ve Microsoft
  girişi bunu ayrıca korur, aşağıda yazıyor).
- Yüzen "Nino'ya Sor" düğmesi (beyaz cam daire içinde robot) ana ekranda ve kurulum ekranlarında sağ altta durur;
  görünüşü "Nino'ya Sor" başlığında.

---

## Profil

Ana ekrandan açılır. Hesap yoktur; bu ekran cihazlar ve tercihlerdir.

Üst çubuk: geri, başlık `profile`, sağda ayarlar simgesi (dişli; Ayarlar'ı açar, erişilebilirlik adı
`settings`).

Yukarıdan aşağı:

1. **İki sütun, eşit yükseklikte iki durum karosu:**
   - Sol: TV simgesi, başlık "PS5" (gömülü metin), değer eşli PS5'in adı ya da `profile_not_paired`.
     PS5 eşliyse sağ üst köşede `main_paired` durum etiketi. Dokununca PS5 eşleme akışı açılır.
   - Sağ: kişi simgesi, başlık `profile_psn`, değer `profile_psn_linked_short` ya da
     `profile_psn_missing`. Dokununca PSN girişi ekranı açılır.
2. **TV ve hedef karosu** (tam genişlik, dokunulur → Altyazı hedefi ekranı):
   - Küçük etiket `profile_tvs`.
   - Büyük başlık: hedef TV ise TV'nin adı (yoksa `main_target_tv`), telefon ise `main_target_phone`.
   - Altında küçük ikincil yazı: ekran açılınca ağda TV aranır. Aranırken `target_searching`;
     bulunamazsa `target_tvs_none`; bulunursa virgülle
     "Ad (Marka)" listesi (marka adları: "LG", "Samsung", "Android TV").
3. **Tek satırlık liste:** `tv_install_button`, altında `tv_install_row_note`. Dokununca TV uygulaması kurulum ekranı.
4. **Bildirimler listesi** (iki satır, sağda anahtar):
   - `notify_disconnect`: PS5 bağlantısı koptuğunda bildirim gönderilsin mi.
   - `notify_packs`: yeni oyun paketi çıkınca bildirim gönderilsin mi.
5. **Tercihler listesi** (sağda anahtar ya da dokunulan satır):
   - `settings_pool` / `settings_pool_short`:
     okunan İngilizce satırları ortak çeviri havuzuna anonim gönder.
   - `settings_ask_game` / `settings_ask_game_short`
   - `settings_speaker_names` / `settings_speaker_names_short`
   - `settings_fast_reading` / `settings_fast_reading_short`
   - `profile_usage` (kullanım verisi başlığı) / `profile_usage_note` (hata ve kullanım istatistiklerini anlatan not): kapatılınca
     kullanım ölçümü ve hata raporu hemen durur.
   - `profile_privacy`: tarayıcıda `url_privacy` = https://github.com/yunusdemirbag/nino-game-translator#gizlilik açılır.
   - `profile_help`: tarayıcıda `url_help` = https://github.com/yunusdemirbag/nino-game-translator/issues açılır.
   - `assistant_title`: Nino'ya Sor ekranı.
   - `report_title`: Sorun Bildir ekranı.
6. **Alt not** (küçük, ikincil): `profile_no_account`

Anahtarlar dokunulduğu an ayarı kaydeder; kaydet düğmesi yok.

---

## Ayarlar

Ana ekrandan ya da Profil'in dişlisinden açılır. Üst çubuk: geri, başlık `settings`. Hepsi tek kayan sütun.
Her değişiklik anında kaydedilir.

1. **Görüntü kaynağı satırı:** `settings_video_source`, değeri seçili kaynağın kısa adı
   (Remote Play / Xbox / Yakalama kartı; bu adlar Kaynak ekranının metinleri). Dokununca Görüntü Kaynağı ekranı. Kaynak
   seçilip dönülünce Xbox seçildiyse ve giriş yoksa Microsoft girişi, giriş var ama Xbox seçilmemişse Xbox seçimi
   kendiliğinden açılır.
2. **Arayüz karosu:** etiket `nino_interface`. Yan yana iki eşit seçenek kutusu (köşe yuvarlak; seçili olan
   2 dp mavi #0070D1 kenarlı, seçili olmayan 1 dp #D3DEEF kenarlı; iç boşluk 10 dp):
   - Üstte 64 dp yüksekliğinde küçük ana ekran önizlemesi (salon çizimi / cam düğme çizimi),
   - Altında ad: `nino_home_living_room` ya da `nino_home_toggle` (seçiliyse mavi yazı).
   - Karonun altında seçime göre ipucu: `nino_home_living_room_hint` ya da `nino_home_toggle_hint`
   - Anlamı: ana ekranın hangi tasarımla açılacağı.
3. **Çeviri dili karosu:** etiket `nino_translation_language`; bayraklı açılır dil menüsü (Türkçe en
   üstte; menünün kendisi başka belgede); altında `nino_translation_language_note`. Yeni dil bir sonraki çeviri oturumunda geçerli olur.
4. **Sistem sağlığı satırı:** `nino_system_health` / `nino_system_health_detail` → Sistem sağlığı ekranı.
5. **GTA 6 karosu** (yalnız şu an oynanan oyun GTA 6 ve çeviri dili Türkçe olup Nino'nun ortak çevirisi etkinken
   görünür): etiket "GTA 6" (gömülü), ikinci yüzey renginde hap içinde `nino_gta6_active` durum
   etiketi, altında `nino_gta6_note`. Bilgi amaçlıdır, düğmesi yok.
6. **Çeviri motoru karosu:**
   - Etiket: GTA 6 karosu görünüyorsa `settings_engine_other_games`, yoksa `settings_engine`.
   - Dört parçalı segment: `engine_free_short`, "DeepL", "Gemini", `engine_other`.
   - "Diğer" seçiliyken altında ikinci segment: "OpenAI" | "Claude". "Diğer"e basınca en son seçilen (Claude
     seçiliyse Claude, değilse OpenAI) gelir.
   - Ücretsiz dışında bir motor seçiliyse:
     - Satır: solda etiket `settings_key_for` (motor adıyla), sağda anahtar kayıtlıysa
       `settings_key_saved` etiketi.
     - Kayıtlıysa yalnız hayalet düğme `settings_key_remove` (basınca o motorun anahtarı silinir).
     - Kayıtlı değilse: gizli yazılan alan `settings_key` ve ikincil düğme `settings_key_save` (alan boşken ya da denenirken pasif; denenirken yazısı `settings_key_checking`).
       Anahtar kaydedilmeden önce o hizmete gerçekten denenir; yalnız kabul edilirse güvenli depoya yazılır, alan
       boşalır ve "kayıtlı" görünür. Reddedilirse not karosu `settings_key_rejected` (alana yeni bir şey yazınca kaybolur). Deneme bitmeden motor değiştirilirse sonuç
       yalnız kaydı etkiler, ekrandaki durumu değil.
   - Karonun altında `settings_engine_note`
7. **Altyazı görünümü karosu** (en büyük karo), yukarıdan aşağı:
   - Satır: etiket `settings_text_size`, sağda büyük "%100" gibi ölçek yüzdesi.
   - Satır: `settings_auto_size` + anahtar (varsayılan açık). Açıkken altında
     `settings_auto_size_note`
   - Boy kaydırıcısı: %40–%160, %10 adımlı (13 durak; durak noktaları görünmez). Kaydırıcı rengi: tutamak #0A1430,
     dolu iz #0070D1, boş iz #D3DEEF. Oynatınca otomatik boy kendiliğinden kapanır.
   - Önizleme yazısı `settings_preview`: altyazı yazı stiliyle, boyu ölçeğe göre büyüyüp
     küçülür, seçili yazı tipinde; renk sarı seçiliyse vurgu yazısı rengi, beyaz seçiliyse ana yazı rengi.
   - Satır: etiket `settings_color`, sağda 32 dp'lik iki yuvarlak renk örneği (beyaz/ana yazı rengi ve
     sarı/vurgu rengi). Seçili olanın 2 dp kenarı mavi, diğerinin #D3DEEF.
   - Etiket `settings_font`; altında 2'li satırlar halinde dört yazı tipi kutusu (en az 48 dp yükseklik,
     seçili 2 dp mavi kenar; her ad kendi yazı tipiyle, yarı kalın, tek satır, taşarsa "…"). Adlar yazı tipi
     seçeneklerinin kendi metinleri (bu bölümün dışında).
   - Satır: etiket `settings_background`, sağda yüzde. Kaydırıcı %5 adımlı, %0–100. "Örtsün"
     yerleşimi seçiliyse kaydırıcı %60'tan başlar (TV'ye %60 altı gitmez) ve gösterilen yüzde TV'ye gidecek gerçek değer.
   - Etiket `settings_background_area`; segment `settings_background_fit` |
     `settings_background_band`. Altında `settings_background_note`
   - (Yalnız hedef TV ise) etiket `settings_placement`; dört parçalı segment
     `settings_placement_cover` | `settings_placement_above` | `settings_placement_below` | `settings_placement_fixed`.
     - "Sabit" seçiliyse: satır `settings_position_height` + sağda yüzde; kaydırıcı %0–85
       (adımsız). Kaydırıcı bırakılınca TV'ye örnek altyazı gönderilir: `test_subtitle_text`. Altında `settings_placement_fixed_note`
     - Diğerlerinde altında `settings_placement_note`
   - Satır `settings_stack_previous` + anahtar; altında
     `settings_stack_previous_note`
   - (Yalnız hedef TV ise) etiket `settings_display_mode`; segment
     `settings_display_mode_in_app` | `settings_display_mode_overlay`; altında
     `settings_display_mode_note`
   - Satır `settings_tv_watermark` + anahtar; altında `settings_tv_watermark_note`
   - Satır `settings_screen_on` + anahtar (çeviri sürerken telefon ekranı kararmasın).
8. **Altyazı alanı karosu:** etiket `area_title`; dört parçalı segment `area_bottom` |
   `area_top` | `area_full` | `area_custom`. Altında 16:9, köşeleri yuvarlak,
   siyah zeminli önizleme: çeviri sürüyorsa son oyun karesi, sürmüyorsa ortada `area_preview_empty`. Önizlemede seçili bölge çerçeve olarak çizilir; içinden sürüklenince kayar, sağ alt
   köşesinin 32 dp yakınından sürüklenince büyür/küçülür; elle değiştirmek seçimi "Özel"e çevirir. "Özel"deyken iki
   kaydırıcı (etiketi solda, yüzdesi sağda): `area_position` ve `area_height`. En altta
   `area_drag_note`
9. **Ek alanlar karosu:** etiket `extra_title`, not `extra_note`
   - Her ek alan ikinci yüzey renginde yuvarlak bir kutu: üst satırda ad alanı `extra_name`, açık/kapalı
     anahtarı, çöp kutusu simgesi (`extra_remove`); altında üç parçalı segment `extra_quest` |
     `extra_notification` | `extra_phone` (hazır konumlar; elle oynanmışsa hiçbiri seçili
     değil); altında aynı sürüklenebilir önizleme (alan kapalıysa %50 saydam).
   - Üçten az alan varsa ikincil düğme `extra_add`; basınca açılır menü: `extra_quest_title`, `extra_notification_title`, `extra_phone_title`. Seçilen
     hazır konumla ve kısa adla yeni alan eklenir.
10. **PS5 giriş şifresi karosu:** satır `settings_passcode` + 4 hane girilmişse sağda "kayıtlı";
    gizli sayısal alan `settings_passcode_field` (yalnız rakam, en çok 4); not `settings_passcode_note`. Yazdıkça kaydedilir; boşaltınca silinir.
11. **Satır listesi:**
    - `settings_packs`, sağda hap `main_packs_on` / `main_packs_off` → Paketler ekranı.
    - `settings_target`, değer TV adı / "TV" / "Bu telefon" → Altyazı hedefi ekranı.
    - Konsol satırı: Xbox kaynağı seçiliyse "Xbox" (gömülü) + seçili Xbox'ın adı ya da "Bağlı değil"; değilse
      `settings_ps5` + PS5'in adı ya da "Bağlı değil". Dokununca eşleme / konsol akışı.
    - (Yalnız Xbox) `settings_xbox_audio` / `settings_xbox_audio_short` + anahtar.
    - `assistant_title` / `assistant_row_note`.
    - `report_title` / `report_row_note`.
    - **Güncelleme satırı** (yalnız uygulama Play Store'dan kurulmamışsa; Play kendisi günceller): başlık
      `update_row_title`.
      - Yeni sürüm biliniyorsa değer `update_row_newer`, sağda hayalet düğme
        `update_row_download` → tarayıcıda https://github.com/yunusdemirbag/nino-game-translator/releases/latest/download/Nino-Telefon.apk.
        (Ana ekrandaki güncelleme kartı kapatılmış olsa da burada görünür.)
      - Yoksa değer `update_row_current`; denetlenirken `update_row_checking` (düğme
        gizlenir); GitHub'a ulaşılamadıysa `xbox_error_offline`; sağda hayalet düğme `update_row_check` (otomatik denetim aralığını —
        3 saat — beklemeden hemen bakar).
    - `settings_about`, değer uygulama sürümü (ör. "4.0.0") → tarayıcıda `url_source` = https://github.com/yunusdemirbag/nino-game-translator.
12. **Microsoft çıkışı karosu** (yalnız Xbox seçiliyken ve giriş yapılmışken): tek satır `xbox_sign_out`. Basınca Microsoft oturumu silinir, karo kaybolur.
13. **TV uygulaması karosu:** etiket `settings_tv_app`; satır `tvinstall_entry`, değeri: TV'deki uygulama eskiyse `tvapp_update_short`; değilse bu
    telefonun kurduğu TV "Marka · sürüm" (ör. "Samsung · 4.0.0"); hiç kurulmadıysa boş. → TV kurulum ekranı.
14. **Deneme düğmesi:** ikincil düğme `settings_test_subtitle`. Çeviri çalışıyorsa TV'ye (ya da
    telefon altyazı ekranına) `test_subtitle_text` gönderilir. **Yeni uygulamada** çeviri çalışmıyorken de hedef TV ise
    TV bağlantısı kısa süre açılıp gönderilir (servis.md 3.8). Hiçbir yere gidemezse (TV 6 sn içinde bağlanmadı ya da
    hedef telefon ve çeviri kapalı) altında ikincil renkli not karosu `settings_test_needs_start`
15. **Telif satırı** (küçük, ikincil, üstünde 8 dp boşluk): `settings_copyright`. Bu, lisansın istediği tek atıf
    satırıdır; değeri NOTICE dosyasındaki atıfla aynı tutulur (bu belgede eski adı tekrar yazılmıyor).

---

## PSN girişi (Kurulum · Adım 1/3)

Kurulumun ilk adımı; Profil'deki PSN karosundan da açılır. Üç hal var: Giriş tanıtımı, Uygulama içi giriş, Tarayıcıda
giriş. Hangi halde olduğu, uygulama arka planda kapatılıp geri açılsa da korunur (özellikle Tarayıcıda giriş: kullanıcı
tarayıcıdan döndüğünde yapıştırma ekranı yerinde olmalı). Sistem geri tuşu Uygulama içi ve Tarayıcı hallerinde tanıtıma
döner.

### 1. Tanıtım hali

- Üst çubuk: geri (kurulumun ilk ekranında yok), sağda hayalet düğme `skip_for_now` (yalnız
  kurulumda; PS5'siz de uygulama gezilebilsin).
- Başlık bloğu: üstte küçük adım yazısı `setup_step` (1), başlık `psn_title`, gövde `psn_body`
- Koyu sahne kartı (270 dp yükseklik), içinde üç camsı satır (simge + başlık + açıklama):
  - kişi simgesi: `psn_free` / `psn_free_note`
  - oynat simgesi: `psn_you_play` / `psn_you_play_note`
  - kilit simgesi: `psn_password_safe` / `psn_password_safe_note`
- Not karosu `psn_main_account`
- Önceki deneme hata verdiyse: not karosu `psn_failed` (hata ayrıntısıyla) ve altında
  hayalet düğme `psn_browser` (Tarayıcı haline geçer).
- Alt alan: hayalet düğme `psn_why` → bilgi kutusu: başlık aynı, gövde `psn_why_body`, düğme `ok`. Birincil düğme `psn_open` → Uygulama içi giriş.
- Tanıtım görünür görünmez uygulama içi tarayıcının eski verisi (tüm çerezler, sayfa depoları: localStorage,
  IndexedDB, service worker) silinmeye başlanır. Böylece kullanıcı düğmeye basana kadar temizlik biter; her giriş temiz
  oturumla açılır.

### 2. Uygulama içi giriş hali

- Tam ekran, zemin #EEF3FB. Üstte üst çubuk: başlık `psn_open`, sağda kapat (×) → tanıtıma döner.
- Altında, yükleme %100 olmadıkça ve hata yokken, tam genişlikte ince ilerleme çubuğu (dolu kısım #0070D1, iz açık kenar rengi).
- Ortada tüm alanı kaplayan uygulama içi tarayıcı. Sayfa zemini Sony'nin koyu rengi **#121314** (Sony'nin popup
  sayfası yazıyı beyaz çizer, zemini saydam bırakır; açık zeminde bembeyaz görünür). Tarayıcı tüm alanı kaplamalı
  (içeriğe göre boyutlanırsa Sony sayfası 0 yükseklikte kalır).
- Sayfa görünür olana kadar tarayıcının üstünde zemin renginde örtü: ortada mavi dönen çember, `psn_loading`, altında ortalı `psn_loading_hint`
- En altta (hata yokken) her zaman bir satır: solda hayalet `psn_browser`, sağda ikincil renkli
  hayalet `close`. Sayfa hiç gelmese de bu iki çıkış görünür.
- **Açılan adres** (GET):
  `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?` ile şu parametreler (sırasıyla, adres kodlamalı):
  `service_entity=urn:service-entity:psn`, `response_type=code`, `client_id=ba495a24-818c-472b-b12d-ff231c1b5745`,
  `redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect`,
  `scope=psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update`,
  `request_locale=en_US`, `ui=pr`, `service_logo=ps`, `layout_type=popup`, `smcid=remoteplay`, `prompt=always`,
  `PlatformPrivacyWs1=minimal`.
- Tarayıcı ayarları: JavaScript ve DOM depolama açık; çerezler ve **üçüncü taraf çerezleri** kabul (Sony girişi
  sonyentertainmentnetwork.com, sony.com ve playstation.com arasında gezer).
- Yükleme sırası: çerez silme bitince sayfa açılır; silme en çok **5 sn** beklenir, dönmezse sayfa yine açılır. Silme
  "tarayıcı kurulu değil / güncelleniyor" hatası verirse doğrudan "çöktü" hatası gösterilir.
- **Yakalama:** ana çerçevede `https://remoteplay.dl.playstation.net/remoteplay/redirect` ile başlayan bir adrese
  gidilmek istendiği an (hem gezinme isteğinde hem sayfa başlarken, çünkü bazı yönlendirmeler yalnız birinde görünür)
  yükleme durdurulur, adres alınır, sayfa yerine yine "bağlanılıyor" örtüsü gösterilir. Bir kez yakalanır.
- **Google:** ana çerçeve `accounts.google.com` alanına giderse (Google uygulama içi tarayıcıda girişi reddeder)
  sayfa açılmadan giriş Tarayıcı haline taşınır ve orada Google notu gösterilir.
- **Hazır mı denetimi:** sayfa görünür olduğunda ya da bittiğinde her **1 sn**'de bir sayfadaki dokunulabilir öğe
  sayısına bakılır (gizli olmayan giriş kutuları ve düğmeler). En az bir tane çıkınca sayfa "hazır" sayılır.
- **Zaman aşımı:** ekran açıldığı andan **20 sn** içinde sayfa hazır olmazsa ve yönlendirme yakalanmamışsa hata:
  sayfa en az bir kez bitmişse "boş kaldı", hiç bitmemişse "çok uzun sürdü". Sayaç tarayıcının olaylarına bağlı
  değildir; tarayıcı hiç kurulmasa da çalışır.
- **Hata halleri** (ilk hata kalır): ana sayfa ağ hatası (çevrimdışı/zaman aşımı/diğer), ana sayfa HTTP hatası,
  SSL hatası (her zaman reddedilir), sayfa sürecinin çökmesi ya da bellek yetmemesi (uygulama kapanmaz), tarayıcının
  hiç açılamaması. Alt kaynakların HTTP hataları yok sayılır.
- **Hata görünümü** (tarayıcının üstünde zemin renginde, dikey ortalı):
  - Başlık `psn_page_failed`, gövde nedene göre + parantez içinde teknik ayrıntı:
    - çevrimdışı `psn_problem_offline`
    - zaman aşımı `psn_problem_timeout`
    - SSL `psn_problem_ssl`
    - HTTP `psn_problem_http`
    - boş `psn_problem_blank`
    - çöktü `psn_problem_crashed`
    - diğer `psn_problem_other`
  - İkincil renkli not `psn_page_failed_hint`
  - Birincil `psn_retry`: tarayıcıyı baştan kurar (çerezleri yeniden siler, sayaçları sıfırlar).
  - Ortalı hayalet `psn_browser`.

### 3. Tarayıcıda giriş hali

- Aynı yetkilendirme adresi telefonun varsayılan tarayıcısında açılır (tarayıcı yoksa sessizce bir şey olmaz).
- Üst çubuk: geri → tanıtım.
- Başlık `psn_browser_title`, gövde `psn_browser_body`
- Google yüzünden gelindiyse ikincil renkli not `psn_browser_google`
- Adres alanı `psn_browser_field` (adres klavyesi). Yazılan metinde yönlendirme adresi yoksa not
  `psn_browser_wrong`
- Metinden adres çıkarma: metnin içinde `https://remoteplay.dl.playstation.net/remoteplay/redirect` aranır (önünde
  arkasında başka yazı olabilir), oradan boşluk, `"`, `<`, `>` görülene kadar alınır. Adreste boş olmayan `code`
  parametresi ya da Sony'nin `error` parametresi varsa geçerli sayılır.
- Alt alan: hayalet `psn_browser_reopen`, birincil `next` (geçerli adres yoksa pasif).
  (Not: gövde metni İleri düğmesinden söz ediyor, düğmede `next` yazıyor.)
- **Panodan otomatik alma:** uygulama penceresi her odak kazandığında (tarayıcıdan dönünce) pano okunur; içinde geçerli
  yönlendirme adresi varsa ve en son denenen adresle aynı değilse alana yazılır ve giriş kendiliğinden tamamlanır.

### Girişin tamamlanması (her iki yol)

- Yönlendirme adresindeki `code` alınır. Adreste `code` yoksa `error`, `error_description` (+ işaretleri boşluk),
  `error_code` birleştirilip hata olarak gösterilir ("too many", "too_many", "rate limit" geçiyorsa "çok sık deneme"
  sayılır).
- Kod, Sony'nin token adresine (`https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token`) POST ile
  `grant_type=authorization_code`, `code`, aynı `scope` ve `redirect_uri` gönderilerek erişim jetonuna çevrilir (Remote
  Play istemcisinin kimliğiyle Basic yetkilendirme; çerezsiz, 30 sn zaman aşımı). Sonra aynı adresin sonuna jeton
  eklenerek (GET) `user_id` okunur. Ondalık `user_id` 8 baytlık küçük-uçlu (little-endian) hesap kimliğine çevrilip
  saklanır. Jeton saklanmaz.
- Kod tek kullanımlıktır: panoda hâlâ aynı adres duruyorsa pano temizlenir (Android 9+).
- Başarı: kurulumda sonraki adıma geçilir; ana ekrandan gelinmiş ve PS5 henüz eşli değilse doğrudan PS5 eşleme ekranı
  açılır (PSN ekranı geri yığından çıkarılır).
- Hata: tanıtıma dönülür, `psn_failed` notu ve "Tarayıcıda açın" düğmesi görünür.

---

## Konsol seçimi

Kurulumun ilk sorusu; Ayarlar'dan da açılır.

- Üst çubuk: geri (varsa).
- Başlık `console_title`, gövde `console_body`
- Koyu sahne kartı (250 dp), içinde yan yana 10 dp arayla iki seçilebilir cam kutu:
  - oyun kolu simgesi (SportsEsports), "PS5", `console_ps5_detail`
  - gamepad simgesi, "Xbox", `console_xbox_detail`
- Altında 15 sp / 21 sp satır aralıklı ikincil yazı: seçime göre `console_ps5_body` ya da `console_xbox_body`
- Xbox seçiliyse ikincil renkli not `xbox_beta_note`
- Alt: birincil `next` → seçim kaydedilir, sonraki adım (PS5 → PSN girişi, Xbox → Microsoft girişi).
- Varsayılan seçim PlayStation.

---

## Microsoft girişi (Xbox, Adım 1/3)

Cihaz kodu yöntemi; Microsoft sayfası uygulama içinde açılmaz.

- Üst çubuk: geri ve sağda "Şimdilik Atla" (ikisi de süren girişi iptal eder).
- Başlık bloğu: `setup_step` (1), `xbox_login_title`, `xbox_login_body`
- Hap `beta`.
- Daha önce giriş yapılmışsa ve kod yoksa durum etiketi `xbox_login_done`.
- Kod yok ve beklenmiyorsa gövde `xbox_login_how`
- Alt: birincil `xbox_login_button` (iş sürerken pasif). Kod varken üstünde hayalet
  `xbox_login_open`.
- Düğmeye basınca: Microsoft'tan cihaz kodu istenir; kod panoya kopyalanır (kısa bildirim `xbox_login_copied`), doğrulama adresi tarayıcıda açılır. Tarayıcı yoksa not `xbox_login_failed` ile
  `xbox_login_no_browser`
- Kod karosu: etiket `xbox_login_code`, büyük mavi kod (dokununca kopyalar),
  altında altı çizili mavi adres ("https://" atılmış; dokununca kodu kopyalar ve adresi açar), küçük yazı
  `xbox_login_steps`. Beklerken altında `xbox_login_waiting`.
- Bekleme ekrandan bağımsızdır: tablet döndürülse ya da uygulama yeniden kurulsa da kodun süresi bitene kadar sürer.
  Onay gelince sonraki adıma geçilir (ana ekrandan gelinmiş ve Xbox seçilmemişse doğrudan Xbox seçimi).
- Hatalar (not karosu `xbox_login_failed`):
  - giriş gerekli/reddedildi `xbox_error_sign_in`
  - kod süresi doldu `xbox_login_expired`
  - Xbox profili yok `xbox_error_no_account`
  - ağ `xbox_error_offline`
  - diğer `xbox_error_unexpected`

## Xbox seçimi (Adım 2/3)

- Üst çubuk: geri, "Şimdilik Atla".
- Başlık bloğu: `setup_step` (2), `xbox_consoles_title`, `xbox_consoles_body`
- Yüklenirken karo içinde `xbox_consoles_searching`.
- Liste boş ve hata yoksa ikincil not `xbox_consoles_empty`
- Her Xbox bir karo (seçiliyse etkin/mavi kenarlı karo): solda uzaktan oynatma açıksa yeşil onay, kapalıysa turuncu
  uyarı simgesi; ad (boşsa model); altında `xbox_console_ready` ya da `xbox_console_off`. Yalnız uzaktan oynatması açık olan seçilebilir. Önceden
  seçili yoksa ilk uygun olan seçili gelir.
- Hata varsa not karosu (yukarıdaki Xbox hata metinleri).
- Alt: hayalet `xbox_consoles_refresh` (listeyi yeniden çeker). Giriş gerekiyorsa birincil
  `xbox_login_button` → Microsoft girişi; değilse birincil `xbox_console_choose` (uygun seçim
  yoksa pasif) → kaydedilir, sonraki adım.

---

## Sistem sağlığı

Ayarlar'dan açılır. Üst çubuk: geri, başlık "Sistem sağlığı". Veriler her saniye yenilenir.

Durum renkleri (nokta): iyi #2EA043, uyarı #E3A008, sorun #D93025, bilinmiyor #B0B8C8.

1. **Sebep karosu** (en üstte):
   - Görünen bir sebep varsa: solda 14 dp kırmızı nokta, başlık ilk sebebin adı, altında ne yapılacağı (normal
     yazı), sonra diğer sebepler "• ad" olarak küçük ikincil yazı. Sebepler önem sırasıyla gelir.
   - Sebep yok, oturum sürüyor ve görüntü geliyorsa: 14 dp yeşil nokta + `health_all_fine`.
   - İkisi de değilse karo yok.
   - Sebep başlıkları / öğütleri:
     - `health_cause_offline` / `health_advice_offline`
     - PS5 koptu, telefonun ağı gittikten sonra: `health_cause_ps5_after_network` / `health_advice_ps5_after_network`
     - PS5 uyudu: `health_cause_ps5_asleep` / `health_advice_ps5_asleep`
     - Remote Play başka cihazda: `health_cause_ps5_in_use` / `health_advice_ps5_in_use`
     - PS5 koptu, geri gelmedi: `health_cause_ps5_lost` / `health_advice_ps5_lost`
     - Hiç bağlanamadı: `health_cause_ps5_never` / `health_advice_ps5_never`
     - Telefonun ağı gitti: `health_cause_network_dropped` / `health_advice_network_dropped`
     - Görüntü kaybı (Wi-Fi'de): `health_cause_picture_wifi` / `health_advice_picture_wifi`
     - Görüntü kaybı (diğer): `health_cause_picture` / `health_advice_picture`
     - Sık kopma: `health_cause_drops` / `health_advice_drops`
     - Yavaş çeviri: `health_cause_slow` / `health_advice_slow` (saniye bir ondalıkla)
     - TV koptu: `health_cause_tv` / `health_advice_tv`
2. **Genel durum karosu:** 14 dp nokta (satırlardaki en kötü durumun rengi) + başlık:
   ölçüm yoksa `nino_health_measured_on_start`; sorun `nino_health_problem`; uyarı `nino_health_warning`; iyi `nino_health_good`;
   diğer `nino_health_measuring`. Altında `nino_health_intro`
3. **Ölçüm satırları listesi:** her satırda solda 10 dp renkli nokta, başlık (sol) ve değer (sağ, ikincil), gerekirse
   altında küçük öğüt.
   - `nino_health_network`: "Wi-Fi" / `nino_net_wired` / `nino_net_cellular` /
     `nino_net_offline` / `nino_net_other`. Renk: kablo hep iyi, bağlı değil sorun,
     diğerleri görüntünün rengini alır (ölçülmeden yeşil olmaz). Öğüt: bağlı değilse `nino_net_offline_advice`; mobil veride `nino_net_cellular_advice`; uyarı/sorunsa `nino_net_weak_advice`
   - `nino_health_ps5`: kopuksa `health_disconnected_for` (en az 1); hiç kopmadan akmışsa `nino_connected`; koptuysa `nino_dropped_times`; bağlanamadıysa `nino_could_not_connect`; yoksa "—". Renk: ölçüm yok bilinmiyor; kopuk ya da
     hiç akmadan 2+ başarısız bağlanma sorun; 3+ kopma uyarı; akmışsa iyi. Öğüt: sorun `nino_ps5_problem_advice`; uyarı `nino_ps5_warning_advice`
   - `nino_health_picture`: `nino_fps` (tam sayı); oturum sürüyor ama görüntü akmıyorsa
     `health_no_picture`; yoksa "—". Renk: 12 altı sorun, 24 altı uyarı, üstü iyi.
     Öğüt (uyarı/sorun) `nino_picture_advice`
   - `nino_health_translation`: ortanca süre `nino_seconds` (bir ondalık); ölçüm yoksa "—";
     satır var ama hepsi paketten geldiyse `health_all_ready`; hiç satır
     yoksa `health_no_subtitle_yet`. Renk: 1,5 sn üstü uyarı, 3 sn üstü sorun. Öğüt
     `nino_translation_advice`
   - (Yalnız hedef TV ise) "TV" (gömülü): TV bağlıysa "Bağlı" (iyi); çeviri sürüyorsa `nino_waiting`
     (görüntü akmışsa uyarı, öğüt `nino_tv_advice`);
     yoksa "—".
4. **Son sorunlar karosu** (yalnız kayıt varsa; uygulama yeniden açılsa da kalır): başlık `health_recent`; en yenisi üstte en çok 8 satır: solda kısa tarih-saat (ikincil), sağda ad: `health_incident_ps5_dropped`, `health_incident_ps5_unreachable`,
   `health_incident_network`, `health_incident_tv`. Altında
   otomatik bildirim açıksa `health_recent_auto`, kapalıysa `health_recent_manual`
5. **Ayrıntılar karosu** (karonun tamamı dokunulur, açar/kapatır): başlık `nino_health_details`, sağda
   mavi küçük `nino_show` / `nino_hide`; altında `nino_health_send_note`. Açıkken 12 sp eş aralıklı (monospace) metin:
   ```
   Nino Android <sürüm>
   cihaz: <üretici> <model>, Android <sürüm>
   çıkış: <tv|phone>, bağlı TV: <sayı>, motor: <free|deepl|gemini|openai|claude>
   oturum: <sürüyor|bitti>
   <sağlık özeti>
   ```
   ve ikincil düğme `nino_health_share` (sistem paylaşım menüsü, düz metin).
6. **Cihaz bilgileri karosu:** başlık `device_info_title`, not `device_info_note`. Satırlar
   (solda ikincil ad, sağa yaslı değer; bilinmeyen satır gösterilmez): `device_info_app`,
   `device_info_device`, `device_info_system`, `device_info_tv`,
   `device_info_console`, `device_info_status`. Durum, TV, oyun değiştikçe yenilenir.
   İkincil düğme `device_info_copy` → özet panoya; 2 sn boyunca yazısı `history_copied`.

---

## Geçmiş

Ana ekrandan açılır. Bu ve önceki oturumlarda çevrilen satırlar, en yenisi üstte.

- Üst çubuk: geri, başlık `history`.
- Üstte küçük not `history_note` (200).
- Boşsa gövde `history_empty`
- Doluysa satır listesi; her satır:
  - üstte küçük eş aralıklı yazı "saat:dk:sn · kaynak": kaynak `history_pack` (koyu mavi #00205B) ya da
    `history_engine` (ikincil renk),
  - çeviri (normal yazı),
  - altında İngilizce asıl (küçük, ikincil).
  - Basılı tutunca "çeviri\nasıl" panoya kopyalanır (görsel geri bildirim yok).
- Alt alan (yalnız satır varsa), yan yana eşit iki düğme: ikincil `history_copy_all` (basınca
  yazısı "Kopyalandı" olur, liste değişince geri döner) ve yıkıcı `history_clear`.
- Temizle onayı: kutu başlığı `history_clear_title`, gövde `history_clear_body`, onay düğmesi "Temizle" (kırmızı #B3261E), vazgeç `cancel`. Kutu
  zemini #E6EDF8.
- Liste yeni satır geldikçe kendiliğinden yenilenir.

---

## Sorun Bildir

Ayarlar, Profil ve Nino'ya Sor'dan açılır. Üst çubuk: geri, başlık `report_title`.

1. **Bulgular karosu:** başlık `report_findings`. Son üç günde sorun yoksa küçük yazı
   `report_findings_none`; varsa bir özet cümlesi ve en yenisi üstte en çok 6 madde "• ss:dd  sorun adı"
   (sorun adları Sistem sağlığındaki gibi). Karonun altında tam genişlik birincil `report_send_problems`: açıklama yazmadan hemen gönderir.
2. Küçük etiket `report_more_optional`.
3. 5 satırlık alan `report_description` (en çok 4000 karakter).
4. **Fotoğraf karosu:** etiket `report_photos`; yan yana 84 dp kare
   küçük resimler (köşe yuvarlak, kırpılmış); her birinin sağ üstünde 24 dp beyaz daire içinde × (`report_remove_photo`). Üçten azsa sonda 84 dp kesik değil düz 1 dp #D3DEEF kenarlı kutu, ortasında + simgesi
   (`report_add_photo`) → Android'in fotoğraf seçicisi (izin istemez, yalnız görüntü, kalan yer kadar).
   Fotoğraflar gönderime uygun boya küçültülür.
5. Alan `report_contact` (en çok 200 karakter).
6. Tek satırlık liste: `report_include_log` / `report_include_log_note` + anahtar (varsayılan açık; bu ekrana özgü, kaydedilmez). Günlükte
   anahtar, jeton, parola benzeri değerler "[gizlendi]" ile değiştirilir.
7. Tek satırlık liste: `report_auto` / `report_auto_note` + anahtar (varsayılan açık; kalıcı ayar).
8. Hata varsa not karosu.
9. Alt not `report_privacy`

- Alt alan: tam genişlik birincil `report_send` (gönderilirken `report_sending`;
  gönderirken ya da fotoğraf yüklenirken pasif).
- Gönderilen: kurulum kimliği, uygulama sürümü, çeviri dili, açıklama (boşsa Nino'nun tespitleri metni doldurur),
  iletişim, isteğe bağlı günlük, fotoğraflar, cihaz özeti. Adres: Nino havuz sunucusu + `/v1/reports` (POST).
- Sonuç: başarılıysa uzun kısa bildirim `report_thanks` ve ekran kapanır.
  Hatalarda not: çok sık `report_rate_limited`; çok büyük `report_too_large`; reddedildi
  `report_invalid`; diğer `report_failed`

---

## Nino'ya Sor

Kurulum yardımcısı sohbeti. Ayarlar, Profil ve yüzen düğmeden açılır.

### Yüzen düğme

60 dp daire, yükseltilmiş yüzey %94 opak, 1 dp #D3DEEF kenar, koyu mavi tonlu yumuşak gölge (14 dp). İçinde 46 dp
robot, yavaşça yukarı aşağı süzülür (1,6 sn, gidip gelir, 3 dp) ve ~4,5 sn'de bir 150 ms göz kırpar. Azaltılmış hareket
açıksa durur. Ana ekranda alt kenardan 96 dp, kurulum ekranlarında 92 dp yukarıda, sağdan 20 dp. Erişilebilirlik adı
`assistant_title`.

### Çeviri başladı balonu

Çeviri başlayınca robotun yanında 7 sn: `translation_started_notice`. Kalın beyaz 14 sp yazı, %55 siyah hap zemin (yatay 14, dikey 8 dp). Sağdan kayarak gelir, 0,6 sn'de solarak
gider. Ekran dönünce ya da geri gelince yeniden çıkmaz (başlangıç anından 7 sn geçtiyse görünmez).

### Sohbet ekranı

- Tam ekran, zemin #EEF3FB. Üst satır: geri oku, 44 dp göz kırpan robot, iki satır başlık `assistant_name` ve
  küçük `assistant_subtitle`; mesaj varsa sağda not simgesi `assistant_new_chat`
  (yanıt beklenirken etkisiz; sohbeti siler).
- Kayan liste (yeni öğe gelince en alta kayar):
  - Hep ilk: Nino balonu `assistant_greeting`
  - Sohbet boşsa altında (soldan 36 dp içeride, satıra sığmazsa alta kayan) öneri hapları: beyaz zemin, 1 dp #D3DEEF
    kenar, mavi küçük yazı, iç boşluk 14×9 dp: `assistant_chip_1`, `assistant_chip_2`, `assistant_chip_3`, `assistant_chip_4`.
    Dokununca o metin gönderilir.
  - **Nino balonu:** solda altta 28 dp robot (durgun), en çok 300 dp genişlik, beyaz zemin, 1 dp #D3DEEF kenar, köşeler
    18/18/18 dp, sol alt 6 dp; iç boşluk 14×10 dp. Yanıt bloklara ayrılır: paragraflar; numaralı adımlar (21 dp mavi
    yuvarlak rozet, içinde beyaz kalın 12 sp numara; iki haneliyse yanlara 4 dp; kayan satırlar rozetin altına değil
    yazının hizasına gelir; sağdan sola dillerde rozet sağda); noktalı maddeler (6 dp mavi nokta). Bloklar arası 10 dp,
    art arda madde/adım arası 8 dp. Yazıdaki http(s) bağlantıları altı çizili mavi ve dokunulabilir. Yanıt bir sorun
    bildirimi de oluşturduysa altında yeşil hap `assistant_report_sent` (yeşil #1E6B45
    yazı, %10 yeşil zemin).
  - **Kullanıcı balonu:** sağa yaslı; fotoğraf varsa üstte 84 dp, 14 dp köşeli küçük resimler (`assistant_screenshot`); yazı balonu en çok 300 dp, mavi #0070D1 zemin, beyaz yazı, köşeler 18/18/6(sağ alt)/18.
    Altında durum: yeniden denenebilir hatada dokunulur satır kırmızı `assistant_not_sent` + yenile
    simgesi + mavi `assistant_retry` (mesaj sona taşınıp yeniden gönderilir, hata balonu silinir);
    yeniden denenemeyen hatada yalnız ikincil "Gönderilemedi".
  - **Uyarı balonu** (Nino balonu görünüşünde, sunucuya gitmez):
    - kapalı `assistant_disabled`
      + altında mavi hap düğme "Sorun Bildir" → Sorun Bildir ekranı (yeniden denenemez)
    - çok sık `assistant_rate_limited` (yeniden denenemez)
    - yoğun `assistant_busy` (yeniden denenebilir)
    - ağ `assistant_network` (yeniden denenebilir)
    - çok büyük `assistant_too_large` (yeniden denenemez)
    - geçersiz `assistant_invalid` (yeniden denenemez)
  - **Yazıyor balonu** (yanıt beklenirken en sonda): robot süzülür, içinde 7 dp üç nokta sırayla 4 dp yükselir (1,2 sn
    döngü; yükselen daha koyu). Azaltılmış harekette durgun. Erişilebilirlik `assistant_typing`.
- **Yazma alanı** (en altta, yükseltilmiş yüzey %70 opak zemin):
  - Eklenen fotoğraflar 64 dp, 12 dp köşeli küçük resimler; sağ üstte 22 dp × düğmesi.
  - Fotoğraf açılamadıysa turuncu küçük yazı `report_photo_failed`
  - Satır: solda 44 dp fotoğraf ekle simgesi (`assistant_attach`; mavi, 3 fotoğrafta gri ve
    pasif); ortada en çok 5 satırlık, 22 dp köşeli, beyaz zeminli alan, ipucu `assistant_hint`
    (odakta mavi kenar); sağda 44 dp yuvarlak gönder düğmesi (`assistant_send`): gönderilebilirse mavi zemin
    beyaz ok, değilse #E6EDF8 zemin gri ok. Gönderilebilir: yanıt beklenmiyor, fotoğraf yüklenmiyor, yazı ya da fotoğraf var.
- Sınırlar: mesaj en çok 2000 karakter, en çok 3 fotoğraf, her fotoğraf en çok ~600 KB'a küçültülür.
- Sunucuya: kurulum kimliği, sürüm, çeviri dili, cihaz özeti (her mesajda yeniden okunur) ve sohbet geçmişi (yalnız
  gönderilmiş kullanıcı mesajları + Nino'nun gerçek yanıtları + şimdiki mesaj; uyarı balonları gitmez). Adres: Nino
  havuz sunucusu + `/v1/assistant` (POST). Gövde çok büyükse önce kısaltılmaya çalışılır, olmazsa "çok büyük".
- Sohbet uygulama açık kaldıkça sürer (ekrandan çıkıp dönünce yerinde); uygulama yeniden açılınca sıfırlanır. Ekrandan
  çıkılsa da bekleyen yanıt gelir.

---

## TV uygulaması kurulumu

Ayarlar, Profil, Altyazı hedefi ekranı ve ana ekrandaki `tvapp_update_button` kartından açılır. Telefon, Nino TV
uygulamasını bilgisayarsız, Wi-Fi üzerinden kurar/günceller.

### Ortak

- Marka seçimi, öncelik sırasıyla: güncelleme kartından gelinen TV'nin markası → bu telefonun en son kurduğu TV'nin
  markası → son seçilen marka. Hiçbiri yoksa ara ekran: üst çubukta geri, başlık `tvinstall_title`, gövde `tvinstall_any_body`, karo içinde canlı durum
  etiketi `tvinstall_searching`. Ağda bulunan ilk Android TV olmayan TV'nin markası, yoksa ilk
  TV'nin markası, hiç yoksa Samsung seçilir.
- Marka segmenti (kurulum sürerken gizlenir): `tvinstall_brand_samsung` | `tvinstall_brand_lg` |
  `tvinstall_brand_android`. Seçim kalıcı kaydedilir.
- Güncelleme kartından gelindiyse o TV seçili gelir ve kurulum kendiliğinden başlar (LG'de yalnız anahtar kayıtlıysa;
  Android TV'de adres doluysa).
- Her markada ekran düzeni: üst çubukta geri → başlık `tvinstall_title` + markaya özel gövde → marka segmenti →
  ikincil not (destek) → "Ağdaki … TV'ler" etiketi → TV listesi → (elle adres alanı) → markaya özel alanlar → adımlar
  karosu → küçük not → durum karosu.
- TV listesi: aranırken karo içinde "TV'ler aranıyor…"; boşsa karo içinde markanın "bulunamadı" metni; her TV bir karo
  (seçiliyse etkin/mavi kenarlı): solda ev simgesi, ad, altında küçük ikincil satır, altında durum etiketi (yeşil/
  olumsuz), seçiliyse sağ üstte 20 dp mavi onay dairesi. Kurulum sürerken seçim değişmez.
- Kurulum durumu:
  - Sürerken: karo içinde canlı durum etiketi, adım metni: `tvinstall_step_pairing`,
    `tvinstall_step_approve`, `tvinstall_step_key`,
    `tvinstall_step_play`, `tvinstall_step_connecting`,
    `tvinstall_step_reading`, `tvinstall_step_signin`,
    `tvinstall_step_certificate`, `tvinstall_step_signing`, `tvinstall_step_installing`,
    `tvinstall_step_uninstalling`, `tvinstall_step_launching`.
  - Bitti: etkin karo; yeşil onay simgesi + başlık `tvinstall_done` ya da
    `tvinstall_up_to_date`; altında `tvinstall_next`. Kurulan TV (marka, adres, port, sürüm) kaydedilir.
  - Hata: not karosu (öğüt + gerekirse "\n\n" + ayrıntı) ve hayalet düğme `tvinstall_share_log` (günlüğün son 60.000 karakteri düz metin olarak paylaşılır, konu "Nino tvinstall.log").
- Alt düğmeler: bittiyse birincil `tvinstall_go_home` (kurulum sürecindeyse kurulumu bitirip ana
  ekrana, değilse bir geri); değilse birincil `tvinstall_button`, hatadan sonra `tvinstall_retry` (sürerken ya da adres boşken pasif). Samsung ve LG'de, liste görünüyor ve iş sürmüyorsa üstünde
  hayalet `tvinstall_not_found` (elle adres alanını açar). Liste boş gelirse elle alan kendiliğinden açılır.
- Ortak hata metinleri: `tvinstall_err_space`, `tvinstall_err_connection`, `tvinstall_err_package_missing`, `tvinstall_err_failed`, `tvinstall_details`.

### Samsung

- Gövde `tvinstall_body`; not `tvinstall_supported`; etiket `tvinstall_tvs`; boş `tvinstall_none`
- Arama: önce yerel ağ duyurusu (SSDP); her TV'nin 8001 portundaki bilgi sayfası okunur. Hiç yoksa telefonun /24
  ağındaki 254 adresin 8001 portu (aynı anda 32, 700 ms zaman aşımı) taranır; adı yoksa "Samsung TV".
- TV karosu alt satırı "model · IP"; durum etiketi: geliştirici modu kapalı `tvinstall_dev_off`; açık ama Host PC IP başka cihazınsa `tvinstall_dev_other_ip`; doğruysa
  yeşil `tvinstall_dev_on`. Bilgi yoksa etiket yok.
- Elle alan `tvinstall_address`.
- Adımlar karosu: başlık `tvinstall_steps_title`; `tvinstall_step1`; `tvinstall_step2`; `tvinstall_step3`; ardından büyük mavi yazıyla telefonun Wi-Fi IPv4 adresi (VPN hariç; Wi-Fi yoksa kablolu) ya da
  `tvinstall_phone_ip_unknown`; `tvinstall_step4`
- Not `tvinstall_signin_note`
- **Samsung girişi ekranı** (kurulum giriş isteyince bu ekranın yerine geçer): tam ekran; üst çubuk başlık
  `tvinstall_signin_title`, kapat (×), sağda hayalet `tvinstall_signin_browser`
  (aynı adresi telefon tarayıcısında açar). Altında uygulama içi tarayıcı (zemin #EEF3FB, JavaScript ve DOM depolama
  açık, https sayfadan http'ye gönderime izin, çerez ve üçüncü taraf çerez kabul, tarayıcı kimliğinden "; wv" parçası
  çıkarılır). Açılan adres:
  `https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h&redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback&state=accountcheckdogeneratedstatetext&tokenType=TOKEN`.
  Samsung girişten sonra jetonu `http://localhost:4794/signin/callback` adresine POST eder (gövde `code=<JSON>&state=…`;
  JSON'da access_token, userId, inputEmailID); telefonda 127.0.0.1:4794'te dinleyen küçük sunucu karşılar. Tarayıcıdan
  da aynı yere gelir. En çok 10 dk beklenir. Geri / kapat girişi bırakır (kurulum giriş hatasıyla biter).
- Samsung hata öğütleri: erişilemedi `tvinstall_err_unreachable`; çok eski `tvinstall_err_too_old`; giriş `tvinstall_err_login`; sertifika `tvinstall_err_certificate`; alan, bağlantı (ortak); imza uyuşmazlığı
  `tvinstall_err_mismatch`; sertifika reddi `tvinstall_err_rejected`; saat `tvinstall_err_clock`; engelli paket `tvinstall_err_blocked` (uzun Smart
  Hub sıfırlama metni; anahtarla alın); diğer "kurulamadı". Kurulum başarısız ya da sertifika reddinde ayrıca sona
  `tvinstall_maintenance` eklenir.

### LG (webOS)

- Gövde `tvinstall_lg_body`; not `tvinstall_lg_supported`; etiket `tvinstall_lg_tvs`; boş `tvinstall_lg_none`
- Arama: SSDP ile LG'ler; her birinde geliştirici modu portu (9922) açık mı bakılır. İlk geliştirici modu açık olan
  (yoksa ilk) seçilir. Karo alt satırı IP; durum etiketi "Geliştirici modu açık / kapalı".
- Elle adres girilirse temizlenir ("192.168.1.5:3000", "http://…", virgüllü yazım düzeltilir); IP değilse not
  `address_invalid`
- Parola alanı (yazılan büyük harfe çevrilir, boşluklar atılır): anahtar kayıtlı değilse `tvinstall_lg_passphrase`, kayıtlıysa `tvinstall_lg_passphrase_saved`. "Kur ve aç" yalnız parola yazılmışsa ya da o TV için anahtar kayıtlıysa etkin.
- Akış: kayıtlı anahtar yoksa TV'nin Key Server'ından anahtar indirilir, parola ile çözülür ve TV başına saklanır.
  Kayıtlı anahtar TV'ce reddedilirse (geliştirici modu yeniden açılınca TV yeni anahtar üretir) eskisi silinir ve parola
  yazıldıysa yenisi alınır. Kurulumdan sonra geliştirici modu süresi günde en çok bir kez uzatılır.
- Adımlar karosu: `tvinstall_lg_steps_title`; `tvinstall_lg_step1`; `tvinstall_lg_step2`; `tvinstall_lg_step3`; `tvinstall_lg_step4`
- Not `tvinstall_lg_session_note`
- LG hata öğütleri: `tvinstall_lg_err_unreachable`; `tvinstall_lg_err_key_server`;
  `tvinstall_lg_err_passphrase` (bu hatada ayrıntı
  gösterilmez); `tvinstall_lg_err_key_refused`; alan, bağlantı, paket yok, kurulamadı (ortak). Ayrıntı `tvinstall_lg_tv_says` ile eklenir.

### Android TV / Google TV

- Gövde `tvinstall_android_body`; not `tvinstall_android_supported`; etiket `tvinstall_android_tvs`; boş `tvinstall_android_none`
- Arama: SSDP/DIAL'da görünen Android TV'ler + telefonun /24 ağında 5555 portu açık olanlar (aynı anda 32). Birleştirilir,
  portu açık olanlar üstte; adı bilinmiyorsa "Android TV". İlk portu açık olan seçili gelir. Karo alt satırı IP; durum
  etiketi `tvinstall_android_debug_on` (yeşil) ya da `tvinstall_android_debug_off`. Liste dışı adres için "TV'm listede yok" düğmesi yok; adres alanı hep görünür.
- Etiket `tvinstall_android_mode`; segment `tvinstall_android_mode_network` |
  `tvinstall_android_mode_wireless` (sürerken değişmez).
- Adres alanı: ağ yolunda `tvinstall_android_address` (port yazılmazsa 5555); kablosuzda
  `tvinstall_android_address_wireless` (port zorunlu; yoksa hata
  `tvinstall_android_need_port`).
- Kablosuzda ek alanlar: `tvinstall_android_pair_address` ve
  `tvinstall_android_pair_code` (yalnız rakam, en çok 6, gizli
  sayısal). Kod yazıldı ama eşleme portu yoksa hata `tvinstall_android_need_pair_port`. Kod varsa önce eşlenir, sonra bağlanılır.
- Adımlar karosu: `tvinstall_android_steps_title`; `tvinstall_android_step1`; ağ yolunda `tvinstall_android_step2` ve
  `tvinstall_android_step3`; kablosuzda `tvinstall_android_wireless_step2` ve
  `tvinstall_android_wireless_step3`
- Kurulum her zaman uygulamanın içinde gelen APK ile yapılır (Play sayfası açılmaz).
- Android TV hata öğütleri: `tvinstall_android_err_unreachable`; `tvinstall_android_err_not_approved`; `tvinstall_android_err_not_paired`; `tvinstall_android_err_pairing`; değiştirme gerekli: TV'deki kopya Play'den
  kurulmuşsa `tvinstall_android_err_play_copy`, değilse `tvinstall_android_err_other_copy` (ikisi de uzun; anahtarla
  alın) — bu durumda ayrıntı gösterilmez ve not karosunun altında tam genişlik yıkıcı düğme
  `tvinstall_android_replace` çıkar (TV'deki kopyayı kaldırıp kurar; TV uygulamasının
  ayarları silinir; yalnız kullanıcı basarsa). Kaldırıp kurma denendiği halde imza yine tutmazsa
  `tvinstall_android_err_remove_manually` (ayrıntısız).
  Alan, bağlantı, paket yok, kurulamadı ortak.

### Ana ekrandaki güncelleme kartı (bu ekranın girişi)

TV'deki uygulama telefondakinden eskiyse ana ekranda etkin karo: başlık `tvapp_update_title`, gövde `tvapp_update_body` (marka, TV'deki sürüm, telefondaki sürüm), tam genişlik birincil
`tvapp_update_button` → bu ekran, o TV seçili, kurulum kendiliğinden başlar.

---

## Paketi içe aktar (Oyun paketleri ekranının bir bölümü)

Oyun paketleri ekranının içinde duran bölüm (ekranın geri kalanı başka belgede).

- Başlık `packs_imported_title`, küçük not `packs_import_note`
- İçe aktarılmış paket varsa satır listesi: başlık paketin adı, değer satır sayısı (`lines_count`;
  1000 ve üstü yuvarlanarak `lines_thousands`), sağda kırmızı hayalet `packs_delete`.
- Hata varsa not karosu.
- İkincil düğme `packs_import` (okunurken pasif) → sistemin dosya seçicisi (depolama izni
  istenmez; seçilebilen türler: JSON, düz metin, SRT türleri, her metin türü, bilinmeyen ikili). Dosya en çok 64 MB;
  büyükse belleğe alınmadan reddedilir.
  - Biçim hatası / çok büyük: `packs_import_format_error`
  - Okuma hatası: `packs_import_read_error`
- **Önizleme kutusu:** başlık `packs_import_heading`; içinde:
  - Alan `packs_import_game_title` (dosyadaki ad, yoksa uzantısız dosya adı ile dolu gelir).
  - Sayı satırları (solda ikincil ad, sağda yerel biçimli sayı): `packs_import_usable`,
    `packs_import_invalid`, `packs_import_duplicate`,
    `packs_import_conflict`.
  - Kullanılabilir satır yoksa turuncu `packs_import_empty`
  - Yükleme hatası kırmızı `packs_import_install_error`
  - Yüklenirken ortada ince mavi dönen çember.
  - Düğmeler: `packs_import_install` (satır yoksa, ad boşsa ya da yüklenirken pasif ve gri; etkinken
    mavi), `cancel` (yüklenirken pasif). Kutunun dışına dokununca (yüklenmiyorsa) kapanır.
  - Aynı kimlikte paket zaten varsa ikinci kutu: başlık `packs_import_replace_title`,
    gövde `packs_import_replace_body`, onay kırmızı `packs_import_replace`, "Vazgeç".
  - Başarıda kutu kapanır, paket listesi yenilenir, çeviri servisi yeni paketi görür.
- **Silme onayı:** başlık `packs_delete_title`, gövde `packs_delete_body`, onay kırmızı "Sil", "Vazgeç".
- Tüm kutuların zemini #E6EDF8.

---

## Gezinme özeti

- Ana ekran → Profil, Ayarlar, Geçmiş, TV kurulumu (güncelleme kartı).
- Profil → Ayarlar (dişli), PS5 eşleme, PSN girişi, Altyazı hedefi, TV kurulumu, Nino'ya Sor, Sorun Bildir, gizlilik ve
  yardım (tarayıcı).
- Ayarlar → Görüntü Kaynağı, Sistem sağlığı, Oyun paketleri, Altyazı hedefi, PS5/Xbox eşleme, Nino'ya Sor, Sorun Bildir,
  Hakkında (tarayıcı), TV kurulumu.
- Nino'ya Sor → Sorun Bildir ("kapalı" uyarısındaki düğme).
- Kurulum sırası (PS5): Konsol seçimi → PSN girişi (1/3) → PS5 eşleme → Altyazı hedefi. Xbox: Konsol seçimi →
  Microsoft girişi (1/3) → Xbox seçimi (2/3) → Altyazı hedefi.

---

## Belirsizlikler

1. **PSN tarayıcı ekranında İleri / Devam uyuşmazlığı:** gövde metni İleri düğmesine dokunmayı söylüyor, düğmede `next` yazıyor. Yeni sürümde biri düzeltilmeli.
2. **PSN token isteğinin istemci sırrı:** bu belgede yazılmadı. Token isteği Remote Play istemcisinin kimliği ve sırrıyla
   Basic yetkilendirme kullanıyor; değeri PSN bağlantısını tarif eden belgede (ya da masaüstü uygulamalarıyla aynı
   kaynaktan) alınmalı.
3. **LG oturum notu çelişkili:** `tvinstall_lg_session_note` telefonun bu süreyi uzatmadığını söylüyor, oysa `tvinstall_lg_supported`
   süreyi Nino'nun kendisinin uzattığını söylüyor ve telefon gerçekten kurulumdan sonra günde bir uzatıyor.
   Not metni güncellenmeli.
4. **`settings_copyright`:** lisans gereği tek atıf satırı; değer NOTICE ile aynı olmalı. Yeni uygulamada bu satır
   Hakkında'ya taşınabilir ama metin değişmemeli.
5. **Güncelleme satırındaki çevrimdışı metni** Xbox'un hata metnini (`xbox_error_offline`) ödünç alıyor; yeni sürümde
   kendi anahtarı olması daha temiz.
6. **Rapor ekranındaki `report_include_log`** her açılışta yeniden açık gelir (kaydedilmiyor). Bilerek mi, belli değil.
7. **Çeviri dili menüsü, yazı tipi adları, görüntü kaynağı adları, PS5 eşleme ve Altyazı hedefi ekranları** bu bölümün
   dışında; yalnız buradan nasıl açıldıkları yazıldı.
8. **Sistem sağlığı sebeplerinin hangi koşulda çıktığı** (ör. kaç kopmada "sık kopuyor", görüntü kaybının ölçüsü)
   sağlık hesabının içinde; burada yalnız renk eşikleri (12/24 kare/sn, 1,5/3 sn çeviri, 3 kopma, 2 başarısız bağlanma)
   yazıldı.
9. **Koyu tema:** eski uygulamada koyu tema yok (renk takımı tek, açık). Yeni sürümde istenirse ayrıca tasarlanmalı.
10. **Samsung engelli paket ve Android TV kopya hata metinleri** çok uzun olduğu için tam yazılmadı; anahtarlarıyla
    strings.xml'den aynen alınmalı.
