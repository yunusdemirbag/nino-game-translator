<!-- SPDX-License-Identifier: AGPL-3.0-only -->
## TV uygulamasını kurma: adım adım (her TV türü)

Altyazının TV'de, oyunun üstünde çıkması için TV'ye bir kez **Nino TV** uygulaması kurulur. Bunu siz yapmazsınız: Mac, Windows ya da telefondaki Nino kurar. Sizin işiniz TV'de bir kez **geliştirici modu**nu açmak. Geliştirici modu, TV'nin mağaza dışından uygulama almasına izin veren gizli bir ayardır. TV'ye zarar vermez.

**Başlamadan önce:** TV, PS5 ve Nino'nun açık olduğu cihaz **aynı Wi-Fi ağında** olmalı.

**Kurulumu nereden başlatırsınız:**
- **Mac / Windows:** kurulumun TV adımında markanızı seçin. Mac'te sonradan: **Ayarlar › Sıfırla › Kurulumu TV adımından yinele** (TV kayıtlı değilse **Televizyon** bölümünde **TV kurulumunu aç**). Windows'ta: **Ayarlar › Sıfırla › TV adımından yeniden kur**.
- **Android telefon:** **Profil › TV'ye Nino'yu Kur** (ya da **Ayarlar › TV tarafı › TV uygulamasını telefondan yükleyin**). Markayı seçin, düğme: **Kurup aç**.
- **iPhone:** **Ayarlar › TV uygulamasını bu telefonla yükle**. Düğme: **Yükle ve aç**.

---

### 1. Android TV / Google TV
(TCL, iFFALCON, Sony, Xiaomi, Toshiba, Grundig, Arçelik, Beko; Hisense, Philips ve Vestel'in yalnız Android TV / Google TV modelleri; Google TV'li Chromecast gibi kutular)

**1. "Hakkında" ekranını açın.** Kumandada **Ayarlar** (dişli) tuşuna basın. Bazı TV'lerde ev tuşuna basıp sağ üstteki dişliyi seçersiniz. Sonra TV'nize göre:
- **Google TV:** **Ayarlar › Sistem › Hakkında**
- **Android TV:** **Ayarlar › Cihaz Tercihleri › Hakkında** (Sony, Philips, Xiaomi)
- TCL ve iFFALCON: **Sistem › Hakkında**

**2. Yapı satırına 7 kez basın.** Hakkında ekranında aşağı inin. **Android TV işletim sistemi yapısı** satırını bulun. Adı **Android TV OS derlemesi** ya da **Build** da olabilir. Satırın üstündeyken kumandanın orta **OK (Tamam)** tuşuna art arda **7 kez** basın. Ekranın altında "Artık bir geliştiricisiniz" yazar. Yazmazsa birkaç kez daha basın.

**3. USB hata ayıklamayı açın.** Bir geri gelin. **Geliştirici seçenekleri** artık görünür: Google TV'de **Sistem** altında, Android TV'de **Cihaz Tercihleri** altında. İçine girin, **USB hata ayıklama**'yı açın. Uyarıya **Tamam** deyin. Listede **Ağ hata ayıklaması** ya da **ADB over network** varsa onu da açın. (Hata ayıklama: Nino'nun TV'ye Wi-Fi üzerinden uygulama kurmasını sağlayan ayar.)

**4. Nino'da kurulumu başlatın.** Telefonda TV'nizi listeden seçip **Kurup aç** / **Yükle ve aç**'a basın. Bilgisayarda Nino TV'yi ağda kendisi arar ("TV için ağ taranıyor…").

**5. TV'deki soruya izin verin.** Birkaç saniye içinde TV'de **"USB hata ayıklamasına izin verilsin mi?"** penceresi çıkar. **"Bu bilgisayardan (cihazdan) her zaman izin ver"** kutusunu işaretleyin, sonra **İzin ver**'e basın. Kumanda tepki vermezse: oklarla kutuya gelip OK'e, sonra **İzin ver**'e gelip OK'e basın.

**6. Bitti.** Nino TV kendiliğinden açılır. PS5'in hangi HDMI girişinde olduğunu gösterir. **USB hata ayıklamayı açık bırakın**; böylece güncellemeleri de Nino kendisi kurar.

**Kablosuz hata ayıklama (Android 11 ve üstü, Google TV):** Telefon bağlanamazsa telefonda **Bağlanma şekli › Kablosuz hata ayıklama**'yı seçin. TV'de **Geliştirici seçenekleri › Kablosuz hata ayıklama**'yı açıp içine girin. En üstteki **"IP adresi ve bağlantı noktası"** değerini (ör. 192.168.1.20:41235) telefona yazın. İlk seferde **"Cihazı eşleme kodu ile eşle"**'yi seçin. Penceredeki adresi, portu ve 6 haneli kodu girin. Pencere kapanmadan **Kurup aç**'a basın. Port her seferinde değişir. iPhone'da Nino'ya **Yerel Ağ** izni de gerekir (iPhone Ayarlar › Nino).

**Katman izni ("Diğer uygulamaların üzerinde göster"):** Altyazıyı oyunun üstüne çizmek için gerekir. Nino kurarken bu izni kendisi verir. Elle kurduysanız TV'de **"Tek seferlik bir izin lazım"** ekranı çıkar. İki düğme var: **TV ayarlarından izin ver** ve **İzinsiz sürdür**. Elle açmak için: **Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster › Nino**. İzinsiz sürdürürseniz oyun Nino'nun içinde açılır; bazı TV'lerde görüntü siyah kalabilir.

**Geliştirici seçeneklerine ulaşamıyorsanız (son çare, elle kurma):**
1. TV'nin tarayıcısında en üstteki adres çubuğuna `is.gd/ninotvapk` yazın.
2. İnen dosyayı açıp kurun.
3. TCL gibi TV'lerde yukarıdaki katman iznini de açın.
Bu yolla kurulan uygulama **kendiliğinden güncellenmez**. Güncellemek için bu adımları tekrarlayın ya da hata ayıklamayı açıp Nino'dan yeniden kurun.

**"Paket geçersiz" ya da "Uygulama yüklenmedi" çıkarsa:** Sebebi, TV'deki eski Nino'nun başka bir imzayla kurulmuş olması. (İmza: uygulamanın kimden geldiğini gösteren dijital mühür.) Android farklı imzalı uygulamanın üstüne kurmaz. Çözüm: TV'de **Ayarlar › Uygulamalar › Nino › Kaldır**, sonra yeni dosyayı yeniden kurun. Mac ya da Windows kuruyorsa bununla uğraşmazsınız, eskiyi kendisi kaldırır. Telefon bu durumu görür ve **"TV'deki kopyayı silip yeniden kur"** düğmesini gösterir (TV uygulamasının ayarları sıfırlanır). Silemezse: **Ayarlar › Uygulamalar › Tüm uygulamalar › Nino TV › Kaldır**, sonra yeniden kurun.

---

### 2. Samsung TV ve Samsung akıllı monitör (Tizen) — deneysel

**1. Geliştirici modu penceresini açın.** Kumandayla **Uygulamalar** ekranına gidin.
- **2022 ve sonrası modeller:** sayfanın **en altına** inin, **Uygulama Ayarları**'nı seçin. Rakamlar ilk sayfada hiçbir şey yapmaz.
- **Eski modeller:** Uygulamalar ekranında rakamları girin; en altta Uygulama Ayarları görüyorsanız oraya girin.

**2. 1 2 3 4 5 yazın.** Kumandada rakam tuşu yoksa **123** tuşuna basın; rakamlar ekranda çıkar, oradan seçin. Beşinci rakamdan sonra **Developer Mode** penceresi açılır.

**3. Developer mode'u On yapın.**

**4. Host PC IP'yi yazın.** (Host PC IP: TV'ye kurulum yapacak cihazın ağ adresi.) Nino'nun gösterdiği adresi **Host PC IP** kutusuna yazın, **OK**'i seçin. Her bölümü olduğu gibi yazın, başına sıfır koymayın (**001 değil 1**). Kutu değişmiyorsa önce **123** tuşuna basın. Adresin yeri:
- **Mac:** TV adımındaki **"TV için Nino uygulaması"** kartında, 3. adımda: "…Host PC IP kutusuna şu adresi girin: (adres)".
- **Windows:** **"TV'deki Nino"** kartında, 3. adımda: "Host PC IP kutusuna şu adresi girin: (adres)". Hata hâlinde: "Host PC IP için yazılacak adres: (adres)".
- **Android telefon:** **"Geliştirici modunu TV'de açın"** kutusunda, 3. adımın hemen altında **büyük mavi** rakamlarla.
- **iPhone:** **"TV'yi geliştirici moduna alın"** kutusunda, 3. adımın ("şu telefon adresini yazın…") hemen altında.
Telefonda adres yerine "Telefonun IP adresi alınamadı" yazıyorsa telefonun Wi-Fi'ı açık değildir.

**5. TV'yi tam yeniden başlatın.** Güç tuşunu **Samsung logosu görünene kadar** basılı tutun ya da TV'nin **gerçek elektrik fişini** bir dakika çekin. Kısa basmak yetmez; TV yalnız beklemeye geçer.

**6. Nino'da kurun.** İlk kurulumda bir kez **ücretsiz Samsung hesabıyla** oturum açarsınız. Tarayıcıda Samsung sayfası açılır ("Girişinizi bekliyoruz…"). Çıkmazsa **Sayfayı Tekrar Aç**'a basın; tarayıcı pop-up'ı durdurmuş olabilir, adres çubuğundaki simgeden izin verin. Hesabınız yoksa o sayfada ücretsiz açın.

**Pencere açılmıyorsa ("Pencere gelmiyor mu?", Mac):** Rakamları Uygulama Ayarları içinde girin. TV'yi tam yeniden başlatıp tekrar deneyin; bazı TV'lerde iki üç denemede açılır. TV'ye USB klavye takıp 12345 yazın; bazı TV'ler telefondaki SmartThings rakamlarını da kabul eder. Mac'te Uygulama Ayarları ekrandayken **"TV'de 1 2 3 4 5 girin"** düğmesine basın (her TV'de çalışmaz).

**Bağlan izni:** Bilgisayar ilk bağlanırken TV'de izin sorusu çıkar; kumandayla **İzin Ver**. Nino 60 saniye bekler. Yanlışlıkla reddettiyseniz: **Ayarlar › Genel › Harici Cihaz Yöneticisi › Cihaz Bağlantı Yöneticisi › Cihaz Listesi**'nden Nino'yu onaylayın, **Bağlan**'a tekrar basın.

**Mac eksik adımı kendisi gösterir** (mod açık mı, Host PC IP doğru mu, TV yeniden başlatıldı mı) ve adım tamamlanınca kendiliğinden ilerler. Olası uyarılar:
- **"Developer Mode açık, fakat TV baştan başlatılmadan kuruluma izin vermiyor."** → 5. adımı yapın.
- **"…adresin önünde fazladan sıfırlar var…"** → sıfırsız yazın.
- **"TV adresi tersine çevirip saklamış"** → TV dili Arapça gibi sağdan soldaysa olur. Developer mode'u Off, sonra On yapın; adresi sondan başa yazın.
- **127.0.0.1 yazıyorsa** → Nino'nun gösterdiği adresle değiştirin.
- **"Ayarları doğru göründüğü hâlde TV bağlantıyı kopardı."** → fişi çekin, bir dakika sonra takın, açıldıktan sonra bir dakika daha bekleyin.

**Diğer Samsung hataları:** "Tizen kodu 118 / -22" → listede Nino varsa kaldırın; yoksa **Ayarlar › Destek › Cihaz Bakımı › Kendi Kendine Tanılama › Smart Hub'ı Sıfırla** (indirdiğiniz başka uygulamaları da siler). Sertifika reddi, "TV'nin saati geri kaldı" ya da "Sunucu bakım altında" → TV internete bağlı olsun, **Ayarlar › Genel › Sistem Yöneticisi › Saat**'i düzeltin, TV'yi kapatıp açın. Kurulumdan sonra TV kendi kendine HDMI 1'e atlıyorsa: **Ayarlar › Tüm Ayarlar › Bağlantı › Harici Cihaz Yöneticisi**'nde **Anynet+ (HDMI-CEC)** ve **Otomatik Kaynak Değiştirme**'yi kapatın.

**Not:** Telefonla kurduysanız ve telefonun adresi değişirse Host PC IP adımını yeniden yapın.

---

### 3. LG TV (webOS) — deneysel

1. Bilgisayar ya da telefonda **webostv.developer.lge.com** sitesinde ücretsiz **LG geliştirici hesabı** açın.
2. TV'de **LG Content Store**'u açın, **Developer Mode** uygulamasını kurun. Uygulamayı açıp bu hesapla giriş yapın.
3. **Dev Mode Status**'u açın. TV kendiliğinden kapanıp açılır.
4. Developer Mode uygulamasını yeniden açın, **Key Server**'ı açın. Uygulama ekranda açık kalsın. Sol alt köşede 6 karakterli **Passphrase** (parola) görünür.
5. Bu kodu Nino'daki **Passphrase** kutusuna harf harf yazın. Mac ve Windows'ta **TV'ye Kur**'a, telefonda **Kurup aç** / **Yükle ve aç**'a basın. Parola yalnız ilk kurulumda sorulur.
6. **Süre:** Geliştirici modu en çok **1000 saat** açık kalır. Nino, TV aynı Wi-Fi'dayken bu süreyi kendisi uzatır; Mac kalan saati gösterir ("Geliştirici modunun bitmesine … saat var"). Uzun süre Nino'yu açmazsanız Developer Mode uygulamasında **EXTEND**'e basın. **Süre dolarsa TV uygulaması silinir**; adımları baştan yapın.

İlk bağlanışta TV izin sorar, kumandayla kabul edin (60 saniye). Hatalar: "Key Server kapalı" → Key Server'ı açıp uygulamayı ekranda bırakın. "Passphrase hatalı" → TV'dekiyle karşılaştırın. "TV anahtarı reddetti" → Key Server'ı açıp kodu yeniden girin. Telefonda "TV'den yanıt gelmedi" → TV açık mı, aynı Wi-Fi'da mı, Dev Mode Status açık mı bakın.

---

### 4. Sık takılınan yerler

- **TV listede çıkmıyor:** TV açık mı, aynı Wi-Fi'da mı bakın; **Yeniden Ara**'ya basın. Telefonda TV'nin adresini elle de yazabilirsiniz. TV'nin adresi: Samsung **Ayarlar › Genel › Ağ › Ağ Durumu**; LG **Ayarlar › Genel › Ağ › bağlı ağ**; Android TV **Ayarlar › Ağ ve İnternet › bağlı ağ › IP adresi**. Adresi yalnız rakamla yazın (ör. 192.168.1.20), başına http:// koymayın. Android TV'yi bilgisayar listede göstermez, kurarken kendisi arar.
- **Aynı Wi-Fi'da mı:** TV'nin bağlı olduğu ağı yukarıdaki menüde görürsünüz; telefonun Wi-Fi'ı da aynı ağ adında olmalı. Windows'ta güvenlik duvarı izin istediyse **Özel ağlar**'ı işaretleyip **İzin ver**'e basın; ağ türü "Özel" olsun.
- **"İzin verilsin mi?" penceresi çıkmıyor (Android TV):** USB hata ayıklamayı kapatıp açın, TV'yi kapatıp açın, kurulumu tekrar başlatın. Yanlışlıkla reddettiyseniz kurulumu tekrar başlatın; pencere yeniden çıkar.
- **Geliştirici modu kapanmış:** LG'de 1000 saat dolmuştur (3. bölüm). Android TV'de hata ayıklama kapalıysa kurulu uygulama çalışır, yalnız güncelleme gelmez. Samsung'da 2. bölümü tekrarlayın.
- **TV'de "Bağlanmayı Bekliyor" / "Bağlantı bekleniyor: Nino'yu telefonda ya da bilgisayarda açın":** TV hazır, Nino'yu bekliyor. Telefonda ya da bilgisayarda çeviriyi başlatın; ikisi birbirini kendiliğinden bulur. Ekranda bilgisayar istendiği yazsa da telefon yeter. Mac'te "TV uygulaması bekleniyor", Windows'ta "TV'de Nino'nun açılması bekleniyor" yazıyorsa TV'de Nino'yu açın.

---

### 5. Model ve yıl farkları

- **Android TV:** menü adları markaya göre değişir (1. bölüm). Ağ hata ayıklaması yalnız bazı TV'lerde var; kablosuz hata ayıklama Android 11 ve üstünde.
- **Samsung:** 2022 ve sonrası: rakamlar yalnız Uygulama Ayarları'nda. Eski modeller: Uygulamalar ekranında. 2016–2018 modelleri deneme aşamasında. Çok eski TV'de "bu kadar eski Samsung TV'lerde çalışmıyor" uyarısı çıkar. Samsung akıllı monitörler (M serisi) de aynı yolla kurulur.
- **LG:** deneysel; geliştirici modu süresi 1000 saat.
- **Çalışmayanlar:** Vidaa (çoğu Hisense), TiVo OS, Titan OS (yeni Philips), Axen, Android olmayan eski Vestel'ler ve Android olmayan TV kutuları. Bunlara uygulama kurulamaz. Altyazıyı telefonda ya da Mac/PC ekranında gösterin. (TV kutusu da çözmez: PS5 doğrudan TV'ye bağlıyken kutu altyazıyı oyunun üstüne koyamaz.)
