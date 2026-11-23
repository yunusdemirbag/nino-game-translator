<!-- Üretilen dosya: nino-pool/scripts/build-sss.mjs (kaynak nino-pool/assistant/sss.json). Elle değiştirmeyin. -->
# Nino: Sık Sorulan Sorular

Bu sayfa, uygulamadaki Nino'ya Sor robotuna en çok sorulan soruların cevaplarıdır (en sık sorulandan aşağı doğru). Cevaplar güncel uygulamaların (V4.5) menü adlarıyla yazıldı. Burada bulamazsan uygulamada Nino'ya Sor'a yaz ya da Ayarlar'daki Sorun Bildir'i kullan.

Diğer diller: [Nino: Frequently Asked Questions](SSS.en.md) · [Nino: الأسئلة الشائعة](SSS.ar.md)

## İçindekiler

- [TV türleri](#tv-türleri)
- [PS5 bağlantısı](#ps5-bağlantısı)
- [Altyazı](#altyazı)
- [Xbox bağlantısı](#xbox-bağlantısı)
- [Çeviri kalitesi / API](#çeviri-kalitesi--api)
- [Uygulama sorunları](#uygulama-sorunları)
- [Kurulum (genel)](#kurulum-genel)
- [Oyun desteği](#oyun-desteği)
- [Gizlilik / hesap](#gizlilik--hesap)
- [İstekler](#i̇stekler)

## TV türleri

### Samsung TV'ye Nino TV uygulaması kurulmuyor ya da bağlanmıyor, ne yapmalıyım?

Samsung'da kurulum çoğunlukla şu yerlerde takılır:

1. Host PC IP: TV'deki Developer Mode penceresinde Host PC IP kutusuna Nino'nun gösterdiği adresi yaz. Bu adres TV'nin değil, kurulumu yapan telefonun ya da bilgisayarın adresidir. Başına sıfır koyma (001 değil 1). Kutu değişmiyorsa önce 123 tuşuna bas.

2. Adres Nino'da şurada yazar: Mac'te TV için Nino uygulaması kartında, Windows'ta TV'deki Nino kartında, Android'de büyük mavi rakamlarla, iPhone'da TV'yi geliştirici moduna alın kutusunda.

3. Tam yeniden başlat: güç tuşunu Samsung logosu görünene kadar basılı tut ya da TV'nin fişini bir dakika çek. Kısa basmak yetmez.

4. İlk bağlanışta TV izin sorar, kumandayla İzin Ver de. Yanlışlıkla reddettiysen Ayarlar › Genel › Harici Cihaz Yöneticisi › Cihaz Bağlantı Yöneticisi › Cihaz Listesi'nden Nino'yu onayla.

5. İlk kurulumda bir kez ücretsiz Samsung hesabıyla giriş istenir. Sayfa açılmazsa Sayfayı Tekrar Aç'a bas.

6. Tizen kodu 118 görürsen listede Nino varsa kaldır. Yoksa Ayarlar › Destek › Cihaz Bakımı › Kendi Kendine Tanılama › Smart Hub'ı Sıfırla (indirdiğin başka uygulamaları da siler).

7. Telefonla kurduysan ve telefonun adresi değiştiyse Host PC IP adımını yeniden yap.

Ekranda tam olarak hangi uyarı yazıyor?

### LG TV'ye Nino kurulurken hata alıyorum (Passphrase, anahtar, yanıt yok), ne yapmalıyım?

LG kurulumunda en sık takılan yerler. Key Server, TV'nin Nino'ya kurulum anahtarını verdiği ayardır; Passphrase de bu anahtarın parolasıdır.

1. TV'de Developer Mode uygulaması açık ve ekranda kalsın. Dev Mode Status ve Key Server ikisi de açık olsun.

2. Developer Mode uygulamasına webostv.developer.lge.com'da açtığın ücretsiz LG geliştirici hesabıyla giriş yap.

3. Passphrase, uygulamanın sol alt köşesindeki 6 karakterlik koddur. Nino'ya harf harf yaz ve TV'dekiyle karşılaştır; O harfi ile sıfır gibi benzer karakterlere dikkat et.

4. Key Server kapalı uyarısında Key Server'ı açıp uygulamayı ekranda bırak.

5. TV anahtarı reddetti uyarısında Key Server'ı yeniden aç ve kodu yeniden gir.

6. TV'den yanıt gelmedi uyarısında TV açık mı, aynı Wi-Fi'da mı, Dev Mode Status açık mı bak.

7. İlk bağlanışta TV izin sorar; 60 saniye içinde kumandayla kabul et.

8. Düğme Mac ve Windows'ta TV'ye Kur, iPhone'da Yükle ve aç, Android'de Kurup aç.

9. Bunlardan farklı bir uyarı çıkıyorsa ekran görüntüsünü Sorunu Bildir ile gönder (Mac'te Hata Bildir, Windows'ta Bir sorun bildir, Android'de Sorunu Anlat); ekibimiz bakar.

Ekranda hangi uyarı çıkıyor?

### Android TV'ye kurulum başlamıyor ya da Nino TV'yi bulamıyor, ne yapmalıyım?

Android TV'ye kurulum başlamıyorsa şunlara bak:

1. TV'de USB hata ayıklama açık olsun. Bu ayar, Nino'nun TV'ye Wi-Fi üzerinden uygulama kurmasını sağlar. Yeri: Ayarlar › Sistem (ya da Cihaz Tercihleri) › Geliştirici seçenekleri › USB hata ayıklama. Listede Ağ hata ayıklaması varsa onu da aç.

2. TV, PS5 ve Nino'nun cihazı aynı Wi-Fi ağında olsun. Windows'ta güvenlik duvarı izin isterse Özel ağlar'ı işaretleyip İzin ver de.

3. Kurulumu başlat: Mac'te Ayarlar › Bağlantı › Televizyon › TV kurulumunu aç, Windows'ta TV Bağlayın, iPhone'da Ayarlar › TV uygulamasını bu telefonla yükle › Yükle ve aç, Android'de Profil › TV'ye Nino'yu Kur › Kurup aç. Bilgisayar Android TV'yi listede göstermez, kurarken ağda kendisi arar.

4. Birkaç saniye içinde TV'de USB hata ayıklama izni sorulur. Her zaman izin ver kutusunu işaretleyip İzin ver'e bas.

5. Telefon bağlanamazsa kablosuz yolu dene: TV'de Geliştirici seçenekleri › Kablosuz hata ayıklama › Cihazı eşleme kodu ile eşle. Ekrandaki adresi, portu ve 6 haneli kodu telefona yaz, pencere kapanmadan kur düğmesine bas. iPhone'da Nino'ya Yerel Ağ izni de gerekir (iPhone Ayarlar › Nino).

6. Paket geçersiz ya da Uygulama yüklenmedi görürsen TV'de Ayarlar › Uygulamalar › Nino TV › Kaldır, sonra yeniden kur.

Kur düğmesine basınca ekranda ne yazıyor?

### TV kutusuyla (Xiaomi Mi Box, Android kutu) Nino'yu kullanabilir miyim?

Google TV ya da Android TV kutularına Nino TV, Android TV ile aynı yolla kurulur: kutuda geliştirici seçeneklerini ve USB hata ayıklamayı (Nino'nun kutuya Wi-Fi üzerinden kurulum yapmasını sağlayan ayar) açarsın, telefondaki ya da bilgisayardaki Nino kurar.

Yalnız bir sınır var: kutu ekranda kendi görüntüsünü gösterir. PS5 doğrudan TV'nin HDMI girişine bağlıysa ve TV o girişteyse kutu altyazıyı oyunun üstüne koyamaz. TV kutuları henüz az denendi.

1. Altyazıyı oyunun üstünde istiyorsan TV'nin kendisi Android TV, Samsung ya da LG olmalı.

2. Değilse altyazıyı telefonda göster: kurulumdaki altyazı ekranında telefonu seç ve telefonu TV'nin yanına koy.

3. Bilgisayar varsa altyazıyı bilgisayar ekranında da gösterebilirsin.

PS5 ile kutu aynı TV'nin farklı girişlerine mi bağlı?

### Android TV'de 'Tek seferlik bir izin lazım' ekranı çıkıyor ya da izin penceresi hiç gelmiyor, ne yapmalıyım?

Tek seferlik izin ekranı katman iznini ister. Katman izni, Nino'nun altyazıyı oyun görüntüsünün üstüne çizmesine izin veren ayardır. USB hata ayıklama ise Nino'nun TV'ye Wi-Fi üzerinden kurulum yapmasını sağlayan ayardır.

1. En kolayı: TV'de USB hata ayıklama açıksa çeviriyi telefondan ya da bilgisayardan başlat; Nino izni kendisi verir.

2. Elle vermek için TV'de Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster › Nino'yu aç. İzin ekranındaki TV ayarı düğmesi de seni oraya götürür; Nino açılınca ekran kendiliğinden ilerler.

3. TV'de bu ayar yoksa İzin vermeden devam et'i seç. Oyun Nino'nun içinde açılır; bazı TV'lerde görüntü siyah kalabilir.

4. Kurulumda USB hata ayıklama izni penceresi hiç çıkmıyorsa USB hata ayıklamayı kapatıp aç, TV'yi kapatıp aç ve kurulumu yeniden başlat. Yanlışlıkla reddettiysen kurulumu tekrar başlatman yeter.

5. Google Play'den kurulan TV sürümü katman çizemez; telefondan ya da bilgisayardan kurulan sürüm çizer.

Bu adımlardan sonra TV'de oyun görüntüsü geliyor mu?

### TV'de yapı satırı yok ya da 7 kez basınca geliştirici seçenekleri açılmıyor, ne yapmalıyım?

Yapı satırı bulunamıyorsa ya da 7 kez basınca bir şey olmuyorsa:

1. Doğru ekranda ol: Google TV'de Ayarlar › Sistem › Hakkında, Android TV'de Ayarlar › Cihaz Tercihleri › Hakkında, TCL ve iFFALCON'da Sistem › Hakkında.

2. Satırın adı Android TV işletim sistemi yapısı, Android TV OS derlemesi ya da Build olabilir. Satırın üstündeyken kumandanın orta OK tuşuna art arda 7 kez bas; yazı çıkmazsa birkaç kez daha bas.

3. Bu satır hiç yoksa TV büyük ihtimalle Android TV değildir. Vidaa, TiVo OS, Titan OS ve Android olmayan Vestel'lere uygulama kurulamaz.

4. Android TV olduğu hâlde geliştirici seçeneklerine ulaşamıyorsan son çare elle kurmaktır: TV'nin tarayıcısında adres çubuğuna is.gd/ninotvapk yaz, inen dosyayı açıp kur. Sonra Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster › Nino iznini aç. Bu yolla kurulan uygulama kendiliğinden güncellenmez.

5. Hiçbiri olmazsa altyazıyı telefonda ya da bilgisayar ekranında göster.

TV'nin Hakkında ekranında hangi satırlar var?

### TV'm Vidaa, TiVo ya da LG olmayan bir webOS kullanıyor; Nino TV kurulur mu?

Nino TV uygulaması yalnız Android TV / Google TV, Samsung ve LG TV'lere kurulur. Vidaa (çoğu Hisense), TiVo OS, Titan OS (yeni Philips), Axen ve Android olmayan Vestel'lere uygulama kurulamaz. LG kurulumu için TV'nin LG Content Store'unda Developer Mode uygulaması bulunmalıdır.

Böyle bir TV'de Nino'yu şöyle kullanabilirsin:

1. Altyazıyı telefonda göster: kurulumdaki altyazı ekranında telefonu seç ve telefonu TV'nin yanına koy. Android'de telefonu yan çevirirsen altyazı tam ekran olur.

2. Bilgisayar varsa altyazıyı bilgisayar ekranında göster.


TV'nin ayarlarında işletim sisteminin adı ne yazıyor?

### Samsung TV'de 1 2 3 4 5 yazınca Developer Mode penceresi açılmıyor, ne yapmalıyım?

Developer Mode penceresi açılmıyorsa:

1. 2022 ve sonrası modellerde rakamlar ilk sayfada işe yaramaz. Uygulamalar ekranında sayfanın en altına in, Uygulama Ayarları'nı seç ve rakamları orada yaz. Eski modellerde rakamlar doğrudan Uygulamalar ekranında yazılır.

2. Kumandada rakam tuşu yoksa 123 tuşuna bas; rakamlar ekranda çıkar, 1 2 3 4 5'i oradan seç.

3. Olmazsa TV'yi tam yeniden başlat (güç tuşunu Samsung logosu görünene kadar basılı tut) ve tekrar dene; bazı TV'lerde iki üç denemede açılır.

4. TV'ye USB klavye takıp 12345 yazabilirsin; bazı TV'ler telefondaki SmartThings uygulamasının rakamlarını da kabul eder.

5. Mac'te Uygulama Ayarları ekrandayken Nino'daki TV'de 1 2 3 4 5 girin düğmesine bas; her TV'de çalışmaz.

Uygulama Ayarları ekranını bulabildin mi?

### Nino açılınca TV'de oyun görüntüsü gidiyor ya da ekran siyah kalıyor, ne yapmalıyım?

TV'de oyun görüntüsü gelmiyorsa ya da ekran siyahsa sırayla dene. HDR ve HDCP, PS5'in görüntü ayarlarıdır; HDCP görüntüyü kopyalanmaya karşı korur ve bazı cihazlarda görüntünün siyah gelmesine yol açar.

1. PS5'te HDR'yi kapat: Ayarlar › Ekran ve Video › Video Çıkışı.

2. Olmazsa HDCP'yi kapat: Ayarlar › Sistem › HDMI › HDCP'yi Etkinleştir.

3. Android TV'de katman iznini (altyazıyı oyunun üstüne çizme izni) ver: TV'de Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster › Nino. Altyazının görünüşü ayarında Android TV gösterim modunu katman yapabilirsin.

4. LG'de TV'nin kaynak menüsünden HDMI'ya geçme, Nino kapanır. PS5 girişini Nino'nun içinden, kumandada 1–4 tuşlarıyla seç.

5. Yine olmazsa TV'deki Kapat ve TV girişine geç düğmesine bas; altyazıyı telefonda ya da bilgisayarda izle.

Hangi marka TV'de oluyor?

### TV'de Nino açılıp hemen kapanıyor ya da açılınca doğrudan HDMI'ya geçiyor, ne yapmalıyım?

TV'de Nino açılıp kapanıyorsa ya da hemen HDMI'ya atlıyorsa TV'ye göre şunlara bak:

1. Samsung: TV'de Ayarlar › Tüm Ayarlar › Bağlantı › Harici Cihaz Yöneticisi'nde Anynet+ (HDMI-CEC) ve Otomatik Kaynak Değiştirme'yi kapat.

2. LG: TV'nin kaynak menüsünden HDMI'ya geçme, Nino kapanır. PS5 girişini Nino'nun içinden, kumandada 1–4 tuşlarıyla seç.

3. Android TV: görüntü Nino'nun içine gelmezse Nino kendiliğinden katmana geçer ve TV'nin HDMI ekranı açılır; altyazı bu ekranın üstüne çizilir. Bunun için katman izni, yani altyazıyı oyunun üstüne çizme izni gerekir (Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster).

4. TV uygulaması eskiyse telefondaki ya da bilgisayardaki Nino'dan TV'ye yeniden kur.

Hangi marka TV'de oluyor?

### PS5'im akıllı olmayan bir monitöre bağlı; altyazıyı nasıl görürüm?

Akıllı olmayan monitöre TV uygulaması kurulamaz, ama altyazıyı başka yerde görebilirsin:

1. Telefonda: kurulumdaki altyazı ekranında telefonu seç (Android'de Telefon ekranında, iPhone'da Bu iPhone'da) ve telefonu monitörün yanına koy.

2. Bilgisayarda: Nino altyazıyı bilgisayar ekranında, oyun görüntüsünün üstünde gösterebilir. Mac'te Ayarlar › Bağlantı › Altyazının görüneceği yer'den Bilgisayar'ı seç.

3. Capture card, konsolun HDMI görüntüsünü bilgisayara aktaran küçük bir cihazdır. Varsa görüntü karttan bilgisayara gelir; Remote Play ve ikinci hesap gerekmez. Kartı PS5 ile monitör arasına bağla ve Mac ya da Windows'ta görüntü kaynağını Capture Card yap. PS5'te HDCP'yi Etkinleştir kapalı olmalı.

4. Monitör Samsung Smart Monitor gibi akıllıysa ona Nino TV kurulur ve altyazı oyunun üstünde çıkar.

Hangisi sana uygun?

## PS5 bağlantısı

### Nino'da PS5 'Bağlanıyor' yazısında kalıyor, ne yapmalıyım?

Bağlanıyor yazısında kalıyorsa Nino PS5'e ulaşamıyor ya da PS5 oturumu açmıyor. Sırayla dene:

1. PS5 açık ya da dinlenme modunda olsun. Dinlenmedeyse PS5'te İnternete bağlı kal açık olmalı.

2. PS5 ile Nino'nun açık olduğu cihaz aynı Wi-Fi ağında olsun.

3. İkinci hesapla PS5'te Ayarlar › Sistem › Uzaktan Oynatma açık olsun.

4. Başka bir cihazda PS Remote Play açıksa kapat.

5. PS5 oturum açma şifresi kullanıyorsan şifreyi Nino'nun ayarlarındaki PS5 oturum şifresi bölümüne yaz.

6. Olmazsa PS Remote Play'i kapat, PS5'i kapatıp aç ve Nino'da fişi yeniden tak.

7. Ekranda PS5'in eşlemeyi geçersiz saydığı yazıyorsa yeniden eşle: ikinci hesapla PS5'te Ayarlar › Sistem › Uzaktan Oynatma › Cihazı Eşleştir.

8. iPhone'da Nino ekranda açık kalsın; telefonu kilitleme.

Bağlanıyor yazısının altında bir neden yazıyor mu?

### Oyun sırasında PS5 bağlantısı sürekli kopuyor, ne yapmalıyım?

Oyun sırasında bağlantı kopuyorsa şunları dene:

1. Başka bir cihazda PS Remote Play açıksa kapat; PS5 aynı anda iki Remote Play bağlantısı tutmaz.

2. PS5'te ikinci hesapla değil kendi (ana) hesabınla oyna.

3. iPhone'da Nino ekranda açık kalsın. Telefonu kilitleme, başka uygulamaya geçme, mümkünse şarja tak. iOS arka plana geçen uygulamayı durdurur.

4. Wi-Fi zayıfsa telefonu ya da bilgisayarı modeme yakın tut.

5. PS5 dinlenme modundaysa İnternete bağlı kal açık olsun.

6. Nino bağlantı koptuğunda yeniden denemeyi kendisi sürdürür. Kopma sık tekrarlıyorsa Sorunu Bildir ile yaz (Mac'te Hata Bildir, Windows'ta Bir sorun bildir, Android'de Sorunu Anlat); cihaz bilgileri kendiliğinden eklenir.

Kopma hangi cihazda oluyor?

### PS5 bağlantıyı reddediyor ya da eşlemeyi kabul etmiyor (hata kodu çıkıyor), ne yapmalıyım?

PS5 bağlantıyı reddediyorsa ya da eşlemeyi kabul etmiyorsa sırayla dene:

1. Yeni kod al: ikinci hesapla PS5'te Ayarlar › Sistem › Uzaktan Oynatma › Cihazı Eşleştir. Kod 8 rakamdır ve 5 dakika geçerlidir; ekranda göründüğü sırayla hemen Nino'ya yaz.

2. Konsol bu hesabı tanımıyor yazıyorsa ikinci hesapla PS5'te hiç oturum açılmamıştır. PS5'te Kullanıcı Ekle ile bu hesapla bir kez giriş yap, sonra kodu al.

3. Nino'da giriş yaptığın Sony hesabı, PS5'te kodu aldığın ikinci hesap olmalı.

4. İkinci hesapta Uzaktan Oynatma açık olsun.

5. Remote Play şu an başka bir cihazda yazıyorsa öteki cihazdaki Remote Play'i kapat.

6. Olmazsa PS Remote Play'i kapat, PS5'i kapatıp aç ve yeniden eşle.

Hata kodunun yanında hangi yazı çıkıyor?

### PS5 ekranında 'Uzaktan Oynama bağlandı' bildirimi gitmiyor, nasıl kapatırım?

Bu bildirim Nino'nun bağlandığı ikinci hesabın ayarından kapatılır:

1. PS5'te ikinci hesaba geç: PS düğmesi › profil resmi › Kullanıcı Değiştir.

2. İkinci hesaptayken Ayarlar › Sistem › Uzaktan Oynatma'ya gir ve en alttaki Uzaktan Oynama Bağlantı Durumunu Gizle'yi aç.

3. Kendi hesabına dön ve oyunu aç.

Bildirim kayboldu mu?

### Nino çalışırken kol oyunda çalışmıyor ya da karakter hareket etmiyor, ne yapmalıyım?

Kol oyunda çalışmıyorsa PS5'te büyük ihtimalle Nino'nun ikinci hesabı seçili:

1. Kolu açınca PS5'te kendi (ana) hesabını seç. İkinci hesap yalnız Nino içindir; onunla oynarsan kol oyunda çalışmaz.

2. Hesap değiştirmek için PS düğmesi › profil resmin › Kullanıcı Değiştir.

3. Oyunu kendi hesabınla aç, sonra Nino'da fişi prize tak.

Kendi hesabına geçince kol çalıştı mı?

### İkinci hesapla Sony girişinde hata alıyorum (ör. CE-110032), ne yapmalıyım?

Bu hata kodu Sony'nin giriş sayfasından geliyor; anlamı için elimde kesin bilgi yok. Deneyebileceğin yollar:

1. Giriş, oyun oynadığın hesaptan farklı, ücretsiz ikinci PSN hesabıyla yapılır. Bu hesapla PS5'te bir kez oturum açılmış olmalı.

2. Uygulamanın içindeki sayfa açılmazsa tarayıcı yolunu kullan: Android'de Tarayıcıda aç, Windows'ta Tarayıcıda oturum aç ya da Kimliği elle yaz.

3. Olmazsa ekran görüntüsüyle Sorunu Bildir'den yaz; ekibimiz bakar.

Hangi cihazda giriş yapıyorsun?

### Nino PS5'i bulamıyor ya da 'PS5 yanıt vermiyor' diyor, ne yapmalıyım?

Nino PS5'e ulaşamıyorsa şunlara bak:

1. PS5 açık ya da dinlenme modunda olsun; dinlenmedeyse İnternete bağlı kal açık olmalı.

2. PS5 ile Nino'nun cihazı aynı Wi-Fi ağında olsun.

3. Mac'te Sistem Ayarları › Gizlilik ve Güvenlik › Yerel Ağ'da Nino'ya izin ver.

4. PS5 listede yoksa Mac'te Yeniden ara ya da IP adresi ile bağlan, Android'de Tekrar Tara, iPhone'da PS5 Görünmüyor mu düğmesini kullan.

5. Nino bağlantıyı denemeyi kendisi sürdürür; PS5'in ağ adresi değiştiyse yeni adresi yaz.

PS5 ile Nino'nun cihazı aynı ağa mı bağlı?

## Altyazı

### Çeviri telefonda ya da bilgisayarda görünüyor ama TV'de çıkmıyor, ne yapmalıyım?

Çeviri telefonda ya da bilgisayarda çıkıyorsa okuma tamam; sorun TV'ye gönderimde. Sırayla bakalım:

1. TV'de Nino TV uygulaması açık olsun. TV ile Nino'nun açık olduğu cihaz aynı Wi-Fi ağında olsun.

2. Altyazının yeri TV olsun: Mac'te Ayarlar › Bağlantı › Altyazının görüneceği yer (TV ya da İkisi de), iPhone'da Ayarlar › Altyazı nerede. Android'de ana ekranda TV'yi seç.

3. Deneme yazısı yolla: iPhone'da Ayarlar › Deneme Altyazısı Yolla, Android'de Ayarlar › TV'de dene. Deneme TV'de çıkmıyorsa sorun TV bağlantısındadır.

4. Samsung kendi kendine HDMI'ya geçiyorsa: TV'de Ayarlar › Tüm Ayarlar › Bağlantı › Harici Cihaz Yöneticisi'nde Anynet+ (HDMI-CEC) ve Otomatik Kaynak Değiştirme'yi kapat.

5. LG'de TV'nin kaynak menüsünden HDMI'ya geçme, Nino kapanır. PS5 girişini Nino'nun içinden, kumandada 1–4 tuşlarıyla seç.

6. Android TV'de katman izni gerekir. Katman izni, Nino'nun altyazıyı oyun görüntüsünün üstüne çizmesine izin veren ayardır. TV'de Ayarlar › Uygulamalar › Özel uygulama erişimi › Diğer uygulamaların üzerinde göster › Nino'yu aç.

7. TV uygulaması eskiyse telefondaki ya da bilgisayardaki Nino'dan TV'ye yeniden kur. Android'de ana ekranda TV uygulamasını yenile düğmesi çıkar.

Deneme yazısı TV'de görünüyor mu?

### TV'de 'Bağlanmayı Bekliyor' ya da 'Nino'yu bekliyor' yazısı gitmiyor, ne yapmalıyım?

Bu yazı TV'nin hazır olduğunu, yalnız telefonu ya da bilgisayarı henüz görmediğini söyler:

1. Telefonda ya da bilgisayarda Nino'yu aç ve ana ekrandaki fişi prize tak; çeviri başlasın. TV'de bilgisayar yazsa da telefon yeter.

2. TV ile Nino'nun cihazı aynı Wi-Fi ağında olsun. Ağ adını TV'nin ağ ayarında ve telefonda karşılaştır.

3. Bilgisayarda Nino'nun yalnız bir kopyası açık olsun.

4. Windows'ta güvenlik duvarı izin istediyse Özel ağlar'ı işaretleyip İzin ver'e bas; ağ türü Özel olsun.

5. Mac'te TV uygulaması bekleniyor, Windows'ta TV'de Nino'nun açılması bekleniyor yazıyorsa TV'de Nino'yu aç.

6. Hâlâ olmuyorsa TV bağlantısını baştan kur: Mac'te Ayarlar › Sıfırla › Kurulumu TV adımından yinele, Windows'ta Ayarlar › Sıfırla › TV adımından yeniden kur. PS5 eşleşmesi silinmez.

TV ile telefon aynı ağ adına mı bağlı?

### Her şey bağlı görünüyor ama altyazı hiç gelmiyor ya da bir kez gelip duruyor, ne yapmalıyım?

Altyazı hiç gelmiyorsa ya da bir kez gelip duruyorsa:

1. Oyunun kendi İngilizce altyazısı açık olsun; Nino ekrandaki bu yazıyı okur, sesi değil.

2. Nino'nun ana ekranındaki fiş prize takılı olsun. Bu, uygulamadaki çizilmiş fiştir; PS5'in gerçek fişine dokunma.

3. Nino ilk birkaç altyazıda oyunun altyazı yerini öğrenir; konuşmalı bir sahnede biraz bekle.

4. Bilgisayarda Nino'nun yalnız bir kopyası açık olsun.

5. Telefon, bilgisayar, TV ve konsol aynı Wi-Fi ağında olsun.

Nino'nun ekranında oyun görüntüsü geliyor mu?

### Altyazının boyutunu, arka planını ya da TV'deki Nino işaretini nasıl değiştiririm?

Altyazının görünüşünü Nino'nun ayarlarından değiştirirsin: Mac, Windows ve Android'de Ayarlar › Altyazının görünüşü, iPhone'da Ayarlar › Altyazı görünüşü.

1. Yazı boyutu ve renk (beyaz ya da sarı) buradadır.

2. Arka plan Yok'tan Opak'a ayarlanır. Yok seçilince siyah kutu kalkar.

3. Yazı tipi: Aksiyon (GTA gibi), Modern, Yuvarlak ya da Sade. iPhone'da Sade yerine Standart, Android'de Yuvarlak yerine Yumuşak köşeli yazar.

4. TV'deki küçük Nino işaretini kapatmak için Mac ve iPhone'da TV'de Nino işaretini göster, Windows'ta TV'de küçük Nino işaretini göster, Android'de Nino işaretini TV ekranında göster seçeneğini kapat. Altyazılar sürer.

5. Android'de TV'de oyunun altyazı boyuna uydur açıksa TV'deki boy oyunun yazısına uyar.

6. TV'deki yazı hiç değişmiyorsa TV uygulaması eskidir; telefondaki ya da bilgisayardaki Nino'dan TV'ye yeniden kur.

İstediğin ayarı bulabildin mi?

### Nino altyazı yerine tuş ipuçlarını ya da ekrandaki her şeyi çeviriyor, ne yapmalıyım?

Nino ilk birkaç altyazıda oyunun altyazı yerini öğrenir; öğrendikten sonra yalnız o bölgeyi okur. Yol tarifleri ve tuş ipuçları altyazı sayılmaz.

1. Oyunun İngilizce altyazısı açık olsun ve konuşmalı bir sahnede biraz bekle; Nino yeri öğrenir.

2. Uygulamayı güncel tut; eski sürümlerde tabelalar ve tuş ipuçları daha sık çevriliyordu.

3. Okunacak alanı daraltmak için iPhone'da Ayarlar › Altyazı bölgesi, Windows'ta Ayarlar › Altyazının yeri bölümüne bak.

4. Büyük siyah kutu rahatsız ediyorsa Altyazının görünüşü'nde arka planı Yok yap.

Konuşmalı sahnede altyazı çevrilmeye başladı mı?

## Xbox bağlantısı

### Nino Xbox'a bağlanmıyor ya da Xbox listede çıkmıyor, ne yapmalıyım?

Xbox'a bağlanmıyorsa şunlara bak:

1. Xbox'ta Ayarlar › Cihazlar ve bağlantılar › Uzak özellikler açık olsun. Güç modu Uyku olsun ki Nino Xbox'ı uzaktan bulabilsin.

2. Nino'da Microsoft ile giriş yaparken Xbox'ta oturum açık olan aynı hesabı kullan. Kod microsoft.com/link sayfasına yazılır.

3. Xbox ile Nino'nun cihazı aynı Wi-Fi ağında olsun.

4. Mac'te Xbox'ı önce Greenlight'ta ya da tarayıcıda xbox.com/play'de, Windows'ta Xbox uygulamasındaki Uzaktan oynat'ta aç. Nino o pencereyi okur; pencere bağlanmazsa önce onu çözmek gerekir.

5. Bağlanıp kopuyorsa Xbox'ta Ayarlar › Genel › TV ve ekran seçenekleri'nden çözünürlüğü 1080p yap.

Xbox, Nino'nun listesinde görünüyor mu?

### Xbox'ta 'uzaktan yürütme başlatıldı' deyip hemen duruyor ya da bağlantı sürekli kopuyor, ne yapmalıyım?

Xbox'ta uzaktan oynatma başlayıp duruyorsa ya da sürekli kopuyorsa:

1. Xbox'ta Ayarlar › Genel › TV ve ekran seçenekleri'nden çözünürlüğü 1080p yap. Bu, bazı kullanıcılarda sorunu çözdü.

2. Xbox ile telefon ya da bilgisayar aynı Wi-Fi ağında olsun; Wi-Fi zayıfsa telefonu modeme yakın tut.

3. Xbox'ta Uzak özellikler açık, güç modu Uyku olsun.

4. iPhone'da Nino ekranda açık kalsın; telefonu kilitleme.

Çözünürlüğü değiştirdikten sonra kopma sürüyor mu?

### Xbox'la kullanırken oyunun sesi telefondan geliyor, ne yapmalıyım?

Bu Xbox'ın kendi davranışı: uzaktan oynatmada sesi bağlanan cihaza verir. Çözüm yolları:

1. Sesi telefondan ya da bilgisayardan dinle; kulaklık ya da soundbar bağlayabilirsin.

2. Android telefondaki Nino'da Xbox sesi için ayrı bir ayar var; ayarlarda Xbox sesiyle ilgili seçeneğe bak.

3. Capture card kullan: konsolun sesi TV'de kalır.

Hangi telefonu kullanıyorsun?

## Çeviri kalitesi / API

### iPhone'da dil paketi indirilemiyor ya da 'çeviriler indirilemedi' yazıyor, ne yapmalıyım?

Bu ekran için elimde henüz kesin adımlar yok, yanlış yönlendirmek istemem. Bilinenler şunlar:

1. GTA 6'nın çevirisi Nino'nun ortak çeviri havuzundan gelir; bu oyun için paket indirmen gerekmez.

2. Diğer oyunlarda iPhone, Apple'ın ücretsiz cihaz içi çevirisini kullanır; bu çeviri iOS 26 ve üstünü ister. Daha eski iOS'ta Ayarlar › Çeviri hizmeti'nden ücretsiz bir Gemini anahtarı ekle; uygulama adım adım gösterir.

3. Sorunu ekran görüntüsüyle Ayarlar › Sorunu Bildir'den gönder; ekibimiz bakar.

Ekran görüntüsünü gönderebilir misin?

## Uygulama sorunları

### Windows'ta Nino açılmıyor, hata veriyor ya da güncellenmiyor, ne yapmalıyım?

Windows'taki duruma göre şunlara bak:

1. Windows bilgisayarınızı korudu uyarısı çıkarsa Ek bilgi'ye, sonra Yine de çalıştır'a bas.

2. Nino başlatılamadı, dosyalar eksik yazıyorsa dosyaları büyük ihtimalle antivirüs karantinaya almıştır. Antivirüste Nino'ya izin ver ve Nino'yu yeniden kur.

3. Beklenmeyen bir hata penceresi çıkıyorsa pencere bir günlük dosyasının yerini yazar (%LOCALAPPDATA%\Nino\hata.log). Bu dosyayı Ayarlar › Nino Hakkında › Bir sorun bildir ile gönder.

4. Güncelleme için ana ekranda Hemen güncelle'ye bas. Çeviri sürerken güncelleme kurulmaz. Zip olarak indirilen kopya kendini güncelleyemez; kurulum dosyasıyla kur.

5. Güvenlik duvarı izin isterse Özel ağlar'ı işaretleyip İzin ver de; yoksa Nino PS5'i ve TV'yi göremez.

Ekranda tam olarak hangi uyarı çıkıyor?

### iPhone'da ekran kapanınca ya da bir süre sonra çeviri duruyor, ne yapmalıyım?

iOS, kilitlenen ya da arka plana geçen uygulamayı durdurur; bu Apple'ın kuralıdır ve hiçbir uygulama aşamaz. Çeviri sürerken Nino ekranı kendisi açık tutar ve parlaklığı kısar.

1. Telefonu kilitleme ve başka uygulamaya geçme.

2. Telefonu şarja takılı bırak.

3. Ekranın açık kalmasını istemiyorsan bilgisayardaki ya da Android telefondaki Nino'yu kullan; Android'de Nino arka planda da çalışır.

Telefon kilitlenmeden de duruyor mu?

## Kurulum (genel)

### Nino'yu nasıl sıfırlarım ya da baştan kurarım?

Bilgisayarda Nino'yu baştan kurmak için uygulamayı silmene gerek yok; Sıfırla bölümünü kullan:

1. Mac'te: menüden Ayarlar › Sıfırla. Yalnız TV'yi baştan kurmak için Kurulumu TV adımından yinele, her şeyi baştan başlatmak için Tümünü sıfırla.

2. Windows'ta: sağ üstteki Ayarlar › Sıfırla. Yalnız TV için TV adımından yeniden kur, her şey için Tümünü sıfırla.

3. TV adımından yeniden kurmak PS5 eşleşmesini silmez. Tümünü sıfırla her şeyi siler; sonra Nino ilk açılıştaki gibi seni adım adım yönlendirir.

4. Telefonda sıfırlamak istiyorsan nerede takıldığını Sorunu Bildir ile yaz (Android'de Sorunu Anlat).

Hangi cihazda sıfırlamak istiyorsun?

### Kurulumu bitirdim, şimdi ne yapacağım?

Kurulum bittiyse her oynayışında yalnız şunları yaparsın:

1. PS5'te kolu açınca kendi (ana) hesabını seç ve oyunu aç. Oyunun İngilizce altyazısı açık olsun.

2. TV'de Nino TV uygulaması açık olsun.

3. Nino'nun ana ekranındaki fişi prize sürükle ya da fişe dokun. Bu, uygulamadaki çizilmiş fiştir; PS5'in gerçek fişine dokunma.

4. Çeviri başlayınca TV'de Nino: Altyazılar Çevriliyor yazar ve altyazılar oyunun üstünde akar. Durdurmak için fişi çek.

Fişi taktıktan sonra TV'de altyazı çıktı mı?

## Oyun desteği

### Nino hangi oyunlarda çalışır; altyazısı olmayan ya da telefondaki oyunları çevirir mi?

Nino, PS5 ve Xbox Series X|S'teki oyunlarda ekranda görünen İngilizce yazıyı okur ve çevirir. Bu yüzden oyunun adından çok altyazısı önemlidir:

1. Oyunun ayarlarından İngilizce altyazıyı aç. Altyazısı olmayan konuşmaları Nino çeviremez, çünkü sesi değil ekrandaki yazıyı okur.

2. GTA 6'nın çevirisi Nino'nun ortak çeviri havuzundan gelir; anahtar gerekmez, ücret yoktur.

3. Diğer oyunlar seçtiğin çeviri motoruyla çevrilir. Daha iyi çeviri için ücretsiz bir Gemini anahtarı ekleyebilirsin.

4. Telefonda ya da tablette oynanan mobil oyunlar, PS4, Nintendo Switch ve Steam Deck desteklenmez.

Hangi oyunu oynamak istiyorsun?

### GTA 6 çevirisi nasıl çalışıyor; GTA 6 paketi neden listede yok?

GTA 6 için ayrı bir paket indirmen gerekmez:

1. GTA 6'daki İngilizce satırlar Nino'nun sunucusunda bir kez yüksek kaliteli yapay zekâyla çevrilir ve aynı satırı gören herkese anında gider. Buna ortak çeviri havuzu diyoruz.

2. Bu oyunda senin Gemini, DeepL, ChatGPT ya da başka anahtarın kullanılmaz; masraf olmaz.

3. Oyunu Nino ekrandan ve altyazılardan kendisi tanır; seçmen gerekmez.

4. Sunucuya ulaşılamazsa cihazın ücretsiz çevirisi gösterilir.

GTA 6'da altyazılar çevriliyor mu?

## Gizlilik / hesap

### Nino'daki PSN ya da Xbox hesabından nasıl çıkış yaparım?

Nino'nun kendi hesabı yoktur; ayarlar yalnız cihazında kalır. PSN ve Microsoft girişini Sony'nin ve Microsoft'un kendi sayfasında yaparsın, şifren Nino'ya gelmez.

1. Mac ve Windows'ta Ayarlar › Sıfırla › Tümünü sıfırla, Nino'yu ilk açılıştaki hâline döndürür.

2. Telefonda tek başına bir çıkış düğmesi için elimde kesin bilgi yok. İstersen Sorunu Bildir ile yaz (Android'de Sorunu Anlat), ekibimiz yol göstersin.

Hangi cihazda çıkış yapmak istiyorsun?

## İstekler

### Nino PS4'te çalışır mı?

Şu an Nino PS4'ü desteklemiyor; PS5 ve Xbox Series X|S ile çalışıyor. İsteğini not aldık.

PS5 ya da Xbox'ın varsa kurulumda adım adım yardım edeyim mi?

### Nino dublaj (sesli Türkçe) yapabiliyor mu?

Dublaj için elimde güncel ve kesin bilgi yok; yanlış bir şey söylemek istemem. Nino'nun bilinen işi, oyundaki İngilizce yazıyı okuyup çevirmek ve altyazı olarak göstermek. İsteğini ekibe iletmek için Sorunu Bildir'den yazabilirsin.

Altyazı kurulumunda yardım edeyim mi?

