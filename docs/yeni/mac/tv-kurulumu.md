# Mac: TV bulma, eşleştirme ve TV uygulamasını kurma

Bu belge yeni Mac uygulaması için bir **tarif**tir: LG, Samsung ve Android TV'de neyin nasıl yapıldığını, kullanıcıya ne
gösterildiğini ve hangi hatada ne dendiğini anlatır. Kod içermez. Metinler yeni uygulamanın anahtarıyla verilir:
anahtarlar noktalı adlardır (ör. `setup.tvApp.title`) ve alan alan xcstrings dosyalarında durur (burada çoğu `Setup.xcstrings` ve
`TVSetup.xcstrings`); anahtarın yanında metnin kendisi değil, ne dediğini özetleyen kısa bir anlatım durur (metinler xcstrings'te; yalnız birkaç kısa düğme adı aynen yazılır). Ekranın çerçevesi ve TV adımının seçim kartları `kurulum.md` §7'de; burada akışlar, ağ işleri ve TV uygulaması
kartı var.

Ortak sabitler:
- LG TV uygulamasının kimliği `com.ninotranslator.tv`; Samsung'unki `NinoTVApps.Nino`; Android paketi
  `com.ninotranslator.tv`.
- TV uygulaması paketleri Mac uygulamasının içinde `tv-app` klasöründe gelir: LG `.ipk`, Samsung `.wgt`, Android `.apk`.
  Sürüm dosya adından okunur (LG: `com.ninotranslator.tv_<sürüm>_all.ipk`; öbürleri `nino-…_<sürüm>.<uzantı>` gibi
  son alt çizgiden sonraki parça). Paket yoksa "Nino kurabilir mi" hayırdır.
- Sürüm karşılaştırması sayısal (0.10 > 0.9).
- TV uygulamasına her açılışta `server` parametresi verilir: `http://<Mac'in TV'ye bakan adresi>:<altyazı sunucusu
  portu>`. Mac'in adresi bulunamazsa `127.0.0.1`.
- Saklananlar (Anahtarlık): TV (ad, adres, marka; marka yoksa LG sayılır), TV eşleşme anahtarı (LG client-key ya da
  Samsung jetonu), LG geliştirici anahtarı (Key Server'dan), Samsung/Android'e Nino'nun kurduğu TV uygulaması sürümü.
  LG geliştirici modu süresinin son uzatıldığı an UserDefaults'ta TV adresine göre (küçük harf, boşluksuz) tutulur.
- Kurulum günlüğü: `~/Library/Logs/Nino/tvinstall.log`, satırlar "[yyyy-MM-dd HH:mm:ss] …" (en_US saat biçimi).
  Hata iletilerinde kullanıcıya gösterilen yol budur (sandbox'ta kapsayıcının içindeki yol).

---

## 1. Mac'in adresi (TV'ye verilen ve Samsung'da Host PC IP)

1. Önce TV'ye giden yolun kaynak adresi: TV adresine (port 8001) bir UDP soketi "bağlanır" (paket gönderilmez) ve yerel
   uç okunur. 0.0.0.0, 127.x değilse ve açık bir bağdaştırıcının adresiyse o kullanılır.
2. Olmazsa: TV ile aynı alt ağdaki gerçek bağdaştırıcı; yoksa Wi-Fi/Ethernet (`en*`) üzerindeki özel adres; yoksa
   herhangi bir gerçek bağdaştırıcı; en son sanal bağdaştırıcılar.
3. Sanal sayılanlar: noktadan noktaya bağdaştırıcılar ve adı `utun`, `ipsec`, `ppp`, `gif`, `stf`, `vmnet`, `vboxnet`,
   `bridge`, `feth`, `tap`, `tun`, `awdl`, `llw`, `anpi`, `zt`, `pdp_ip` ile başlayanlar (VPN, sanal makine…). TV
   bunlara ulaşamaz.
4. Özel adres: 10.x, 172.16–31.x, 192.168.x.

## 2. TV bulma

### LG (webOS)
- SSDP araması: `M-SEARCH * HTTP/1.1`, `HOST: 239.255.255.250:1900`, `MAN: "ssdp:discover"`, `MX: 2`,
  `ST: urn:lge-com:service:webos-second-screen:1`. İstek her özel ağ bağdaştırıcısından ayrı ayrı (çok noktaya yayın
  arayüzü seçilerek) iki kez gönderilir; 3 sn yanıt toplanır. Yanıtta `ST`/`NT` bu hedefse `LOCATION`'daki adres alınır.
- Ad: `http://<adres>:1990/` cihaz tanımındaki `<friendlyName>`; okunamazsa "LG TV".
- SSDP yanıtı gelmezse yedek tarama: Mac'in her ev ağının /24 bölümündeki bütün adresler (kendisi hariç), aynı anda en
  çok 64, her biri ~0,8 sn zaman aşımıyla. Bir adres LG sayılır: `:1990/` cihaz tanımında `<device` ve "lg
  electronics" ya da "webos" geçiyorsa **ya da** `:3000/` düz HTTP'ye tam "Hello world" diyorsa. Aynı anda her adrese
  ayrı (tek adresli) SSDP isteği de gönderilir (2,5 sn).
- Sonuç adres sırasına göre dizilir.

### Samsung (Tizen)
- SSDP araması aynı biçimde, `ST: urn:samsung.com:device:RemoteControlReceiver:1`, 3 sn.
- Ad: `http://<adres>:8001/api/v2/` yanıtında `device.name` (`&quot;` tırnağa çevrilir); yoksa "Samsung TV".
- SSDP sessizse aynı /24 taraması; 8001'de ad veren adres Samsung'dur.

### Android TV
- Ağda aranmaz. Seçilince adı markanın kendi adı (Android TV), adresi boş bir TV kaydı oluşur; adres kurulum sırasında yardımcının
  taramasıyla bulunur (§6).

TV adımında LG ve Samsung araması birlikte çalışır, sonuçlar birleştirilir.

### Adres değişirse
Bağlantı başarısız olunca (en çok 30 sn'de bir) aynı markadaki TV'ler yeniden aranır. Kayıtlı adres listede yoksa:
aynı adlı tek TV varsa o, yoksa bulunan tek TV varsa o yeni adres sayılır, saklanır. Birden çok tanımadık TV varsa
tahmin edilmez.

## 3. Eşleştirme (TV adımındaki "Bağlan")

Önce altyazı sunucusu açılır. Kayıtlı eşleşme anahtarı varsa gönderilir.

### LG: SSAP
- WebSocket önce `wss://<adres>:3001`, olmazsa `ws://<adres>:3000` (eski webOS). 3001'in kendinden imzalı sertifikası
  yalnız bu TV'nin adresi için kabul edilir. Çerezsiz oturum.
- İlk ileti (5 sn içinde gönderilemezse o uç bırakılır): `{"type":"register","id":"register_0","payload":
  {"forcePairing":false,"pairingType":"PROMPT","manifest":{"manifestVersion":1,"appVersion":"1.0","permissions":
  ["LAUNCH","LAUNCH_WEBAPP","APP_TO_APP","READ_RUNNING_APPS","READ_INSTALLED_APPS"]},"client-key":"<varsa>"}}`.
- TV ekranında izin sorar; en çok **60 sn** beklenir. `type:"registered"` gelirse `payload.client-key` saklanır;
  `type:"error"` ret; süre dolarsa ret ("timeout"). Ret dışındaki hatada sonraki uç denenir; ikisi de olmazsa "bağlanamadı".
- Sonra uygulama açılır: `ssap://system.launcher/launch`, `{"id":"com.ninotranslator.tv","params":{"server":"…"}}`.
  `returnValue:false` ise açılamadı sayılır (uygulama kurulu değil demektir).
- Sonra (LG'de beklenerek) TV uygulaması durumu denetlenir (§5).

### Samsung: uzaktan kumanda WebSocket'i
- `wss://<adres>:8002/api/v2/channels/samsung.remote.control?name=<uygulama adı Nino'nun base64'ü>` ve varsa `&token=<jeton>`.
  8002'nin kendinden imzalı sertifikası yalnız bu adres için kabul edilir.
- Gelen iletiler: `event:"ms.channel.connect"` → onay (jeton `data.token`, boş olabilir); `ms.channel.unauthorized` →
  **reddedildi**; `ms.channel.timeOut` → izin kutusu yanıtsız kaldı (**bağlanamadı**). En çok **60 sn** beklenir.
- Jeton kuralı: TV yeni jeton verdiyse o saklanır; boş verdiyse eldeki korunur (boş jeton yazılırsa TV her bağlantıda
  yeniden izin sorar).
- Uygulama açma iletisi: `{"method":"ms.channel.emit","params":{"event":"ed.apps.launch","to":"host","data":
  {"appId":"NinoTVApps.Nino","action_type":"DEEP_LINK","metaTag":"{\"server\":\"…\"}"}}}` (parametreler JSON metni).
- TV uygulaması durumu arka planda denetlenir (Samsung girişi dakikalar sürebilir; eşleşme beklemez).

### Android TV
- Bilgisayar TV'yi denetlemez; eşleşme anında başarılı sayılır. TV uygulaması bilgisayarı kendisi bulur. Durum denetimi
  arka planda (§6).

### Eşleşince
- TV ve anahtar saklanır. Marka ya da (Android dışında) adres değiştiyse saklı TV uygulaması sürümü silinir.
- "TV'm yok" seçiliyse çıktı TV'ye geçer.
- Hata iletileri `kurulum.md` §7'de.

## 4. TV uygulamasını açık tutma (çeviri sürerken)

- LG: 5 sn'de bir bakılır. Bağlantı yoksa kurulur ve uygulama açılır. Varsa önplandaki uygulama sorulur
  (`ssap://com.webos.applicationManager/getForegroundAppInfo`); `com.webos.app.hdmi…`, `com.webos.app.externalinput…`
  ya da `com.webos.app.livetv` ise (TV kendi girişine geçmiş) uygulama yeniden açılır. Netflix gibi bilerek açılanlara
  dokunulmaz. Hata olursa bağlantı bırakılır, sonraki turda yeniden kurulur.
- Samsung: önplandaki uygulamayı söylemediği için sürekli bağlantı tutulmaz. Yalnız TV uygulaması altyazı sunucusuna
  bağlı değilken ve en çok 30 sn'de bir: bağlan, uygulamayı aç, hemen kapat. (Sık bağlantı TV'de "uzaktan kumanda
  bağlandı" bildirimi çıkarıp PS5 kolunu düşürüyordu.)
- Android TV: hiçbir şey yapılmaz.
- Mac uykudan uyanınca bağlantı hemen yenilenir.

---

## 5. TV uygulaması kartı (TV adımında)

Başlığı her hâlde `setup.tvApp.title` (Nino TV app / **Nino TV uygulaması**) olan cam kart. Hâller:

| Hâl | Görünüş |
|---|---|
| Bilinmiyor / yapılacak yok | kart yok |
| Çalışıyor | gösterge + `setup.tvApp.installing` (TV uygulamasının şu an kurulduğunu söyleyen kısa satır) |
| Güncel | bitti etiketi `setup.tvApp.ready %@` (TV uygulamasının hazır olduğunu ve sürüm numarasını söyleyen satır) + markaya göre ipucu (aşağıda) |
| Mod kapalı (geliştirici modu ya da hata ayıklama açılmamış) | markaya göre adımlar (§5.1–5.3) |
| Parola gerekiyor (LG) | §5.1 parola kartı |
| Tarayıcıda Samsung girişi | §5.2 giriş kartı |
| Android onayı (TV ekranında izin sorusu açık) | §5.3 onay kartı |
| Hata | hata metni (§7) + ikincil `setup.tvApp.tryAgain` (Try Again / **Tekrar Dene**) |
| Samsung, TV bağlantıyı kesti | Samsung denetim kartı "koptu" hâliyle (§5.2) |
| Samsung, Host PC IP yanlış | Samsung denetim kartı (§5.2) |

"Güncel" ipuçları:
- LG, kalan süre biliniyorsa: `setup.tvApp.lg.hoursLeft %lld` (geliştirici modunda kaç saat kaldığını `%lld` ile verir
  ve Nino'nun bu süreyi her kullanımda kendiliğinden yenilediğini ekler); bilinmiyorsa `setup.tvApp.lg.extends` (yalnız
  süre yenileme kısmını söyler, saat vermez).
- Samsung: `setup.tvApp.samsung.anynet` (Nino'nun TV uygulaması ekrandayken TV kendi kendine HDMI 1'e veya farklı bir
  girişe atlıyorsa, Anynet+ ile otomatik kaynak değiştirmenin kapatılmasını söyler; yer olarak Samsung'un External
  Device Manager menüsünü gösterir; Türkçesi TV'nin Türkçe menü adlarını kullanır).

Kendiliğinden ilerleme: "mod kapalı" hâlinde 3 sn'de bir; Samsung "koptu" ve "adres yanlış" hâllerinde
3 sn'de bir TV'ye yeniden sorulur. Adım tamamlanınca kart kendisi ilerler.

### 5.1 LG

**Mod kapalı (LG geliştirici modu açılmamış):**
- `setup.tvApp.lg.notInstalled` (TV'de uygulamanın bulunmadığını ve mod açıldığı an Nino'nun onu yükleyebileceğini
  söyler)
- İpuçları, sırayla `setup.tvApp.lg.step1`, `setup.tvApp.lg.step2`, `setup.tvApp.lg.step3`:
  1. LG'nin geliştirici sitesinde (webostv.developer.lge.com) parasız bir hesap oluşturma adımı.
  2. TV'nin uygulama mağazasından (LG Content Store) Developer Mode uygulamasını kurup o hesapla giriş yapma adımı.
  3. Developer Mode uygulamasındaki Dev Mode Status anahtarını açma adımı; ardından TV'nin kapanıp açılacağını, bu ekranın da kendiliğinden
     ilerleyeceğini ekler.
- Parola alanı burada da görünür (Nino geliştirici modunu göremese de kullanıcı takılmasın).

**Parola kartı:** `setup.tvApp.lg.lastStep` (geliştirici modunun açık olduğunu ve kurulum için tek bir adım kaldığını
söyleyen, iki noktayla biten giriş cümlesi), ardından parola alanı.

**Parola alanı:** ipucu `setup.tvApp.lg.passphraseHint` (TV'deki Developer Mode uygulamasında Key Server'ın açılmasını,
uygulamanın ekranda kalmasını ve orada görünen Passphrase'in bu alana girilmesini ister); alanın yer tutucusu anahtarsızdır: TV'deki
uygulamanın kullandığı İngilizce terim olduğu için iki dilde de çevrilmeden sabit yazılır. Birincil düğme
`setup.tvApp.lg.install` (kurulumu başlatan düğme) (alan boşken kapalı); altında son denemenin hatası.

**Akış:**
1. Mod açık mı: SSH (9922) **ya da** Key Server (9991) 2 sn içinde TCP kabul ediyorsa açık.
2. Kapalıysa: uygulama açılamamışsa "mod kapalı", açılmışsa kart yok.
3. Açık ama saklı geliştirici anahtarı yoksa: uygulama açılamamışsa "parola gerekiyor", açılmışsa kart yok.
4. "TV'ye Kur": `http://<adres>:9991/webos_rsa` (5 sn) indirilir; 200 değilse **Key Server kapalı**. İnen şifreli
   anahtar geçici bir dosyaya (yalnız sahibine açık, 0600) yazılır ve sistemin `ssh-keygen` aracıyla parolası
   kaldırılır (parola = yazılan Passphrase, yeni parola boş). Araç başarısızsa **parola yanlış**. Anahtar saklanır.
5. Kurulum (anahtar her komutta geçici 0600 dosyadan verilir, sonra silinir): SSH `prisoner@<adres>` port 9922,
   yalnız bu anahtarla, toplu kip, 6 sn bağlantı zaman aşımı, ana makine anahtarı denetlenmez (her fabrika ayarında
   değişir), eski `ssh-rsa` türüne izin verilir. SSH 255 ile biterse: çıktıda "Permission denied" → **anahtar
   reddedildi**, değilse **ulaşılamadı**.
   - TV'deki sürüm: `/media/developer/apps/usr/palm/applications/com.ninotranslator.tv/appinfo.json` içindeki
     `"version"`. Gelen paket daha yeni değilse güncel sayılır, kurulmaz.
   - Yükleme: `/media/developer/temp` oluşturulur, önceki `com.ninotranslator.tv_*.ipk` ve `nino.ipk` silinir, paket
     kendi adıyla oraya akıtılır.
   - Kurma: `luna-send-pub -i 'luna://com.webos.appInstallService/dev/install'` ile
     `{"id":"com.ares.defaultName","ipkUrl":"<paket>","subscribe":true}`; abonelik açık kalsın diye girişi uzun bir
     `sleep`'ten beslenir; yanıtlar geçici bir günlük dosyasına yazılır. En çok 180 sn, saniyede bir dosyada
     "installed", "success", "failed" ya da `"returnValue": false` aranır; bulununca ya da süre dolunca yanıtlar
     okunur, süreç kapatılır.
   - Yanıt okuma: satırlar JSON'a birleştirilir. `returnValue:false` → hata (`errorText`/`errorMessage` + `errorCode`);
     `details.state` içinde "failed" → hata (`details.reason`/`errorText` + kod); "installed" ya da "success…" → başarı.
   - Doğrulama: sürüm `appinfo.json`'da görünene dek 2 sn arayla beklenir (TV "installed" dediyse 30 sn, sonuç yoksa
     60 sn). Görünürse paket silinir, başarı. Görünmezse hata ayrıntısı `tv.lg.versionNotVisible` (beklenen sürümün (%1$@) TV'de
     belirmediğini söyler ve ardından TV'nin kurulum yanıtını (%2$@) ekler).
   - Hata metninde yer sorunu geçiyorsa ("no space", "not enough space/storage", "insufficient…", "out of space",
     "storage full", "disk full", "ENOSPC", "lack of space") **yer yok**, değilse **kurulamadı**; TV'nin verdiği sebep
     karta eklenir (en çok 500 karakter).
   - Anahtar reddedilirse saklı anahtar silinir, kart parola hâline döner (geliştirici modu yeniden açılınca TV yeni
     anahtar üretir).
6. Kurulunca uygulama yeniden açılır (bekçi varsa ona "yeniden bağlan" denir; yoksa eşleşmedeki gibi açma iletisi).
7. **Süre uzatma:** LG geliştirici modu 1000 saattir. Kurulum/denetim başarılıysa ve son uzatmadan 20 saatten fazla
   geçtiyse: TV'den `/var/luna/preferences/devmode_enabled` (oturum jetonu) okunur; boşluk içermiyorsa
   `https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=<jeton>` çağrılır, yanıtta "success" varsa
   `…/CheckDevModeSession.dev?sessionToken=<jeton>` yanıtındaki `ss:dd:sn` biçimli kalan sürenin saati kartta
   gösterilir ve an saklanır. Başarısızlık sessizdir.

### 5.2 Samsung

Kurulum gömülü yardımcıyla yapılır (§8). Önce **denetim**:

- `http://<adres>:8001/api/v2/` okunur (kısa zaman aşımı): `device.developerMode` ("1"/"true" açık, "0" kapalı,
  yoksa bilinmez), `device.developerIP` (boş ya da "0.0.0.0" ise yok), `device.model` (ör. "23_KANTSU2E_QLED" → 2023;
  ilk iki hane 15–60 arasıysa).
- Kurulum kapısı açık mı: TCP **26101** (2 sn).
- Mac'in adresi: §1.

**Eksik adım** (ilk tutan):
1. 8001 yanıtı yok ve kapı kapalı → TV yanıt vermiyor.
2. 8001'e göre geliştirici modu kapalı (8001 söylemezse kapıya bakılır) → mod kapalı.
3. Host PC IP dolu ve: 127.0.0.1 → "loopback"; Mac'in adresinden farklı → dört parçası sıfırlar atılınca aynıysa
   "başında sıfır", ters sırasıysa "ters", değilse "yanlış adres". (Parça 1–3 rakam, 0–255.)
4. Kapı kapalı → TV yeniden başlatılmamış.
5. Hiçbiri → kurulum denenebilir.

**Akış:**
- TV yanıt vermiyor / mod kapalı / yeniden başlatılmamış: TV'ye sorulamaz; Nino bu TV'ye daha önce güncel sürümü
  kurduysa kart "güncel", değilse "mod kapalı" (denetim kartı).
- Adres sorunlarında kurulum denenmez (TV el sıkışmada bağlantıyı keser); daha önce güncel kurulduysa "güncel",
  değilse "Host PC IP yanlış" kartı; durum değişince günlüğe TV'nin Host PC IP alanındaki değer ile Mac'in TV'ye
  giden adresini yan yana yazan ve kurulumun denenmediğini belirten bir satır düşülür. `setup.samsung.tryAnyway` (Try Anyway /
  **Yine de Dene**) bir kez adresi yok sayar (günlüğe de yazılır).
- Sorun yoksa: güncel biliniyorsa kart sessizce "güncel" kalır, değilse "çalışıyor"; yardımcı `samsung-install`
  çalıştırılır. Sonuç sürümü saklanır, kart "güncel"; gerçekten kurulduysa uygulama açılır.
- Daha önce güncel kurulmuşken TV bağlantıyı kabul etmezse (ulaşılamadı) kart "güncel" kalır (çalışan uygulama
  "kurulamadı" diye gösterilmez).
- Yardımcı tarayıcı girişi isterse adres tarayıcıda **öne getirilerek** açılır, kart "giriş" hâline geçer.
  Açılamazsa günlüğe yazılır.
- Yardımcının ilerleme adımlarından biri `signin`, `certificate`, `signing`, `installing`, `uninstalling`, `play` ise
  kart "çalışıyor"a geçer (sessiz sürüm denetimi gerçek kuruluma döndü). Kurulum bittikten sonra gelen geç olaylar
  sonucu ezmez.
- "Koptu" hâlinde 3 sn'de bir yalnız denetim yapılır (kurulum değil): eksik adım belli olduysa ya da kurulum kapısı
  kapalıyken açıldıysa (TV yeniden başladı) kurulum kendiliğinden yeniden denenir.

**Denetim kartı.** Üstte (TV yanıt veriyorsa) üç satır; her satır simge + açıklama yazısı: tamam →
success `checkmark.circle.fill`; eksik → warning `exclamationmark.circle.fill`; sırası gelmedi → gri `circle` ve gri
yazı.
1. Mod: açık → `setup.samsung.row.modeOn` (modun açık olduğunu söyleyen kısa satır) (tamam); kapalı →
   `setup.samsung.row.modeOff` (modun kapalı olduğunu söyleyen kısa satır) (eksik).
2. Adres: mod kapalıysa sırası gelmedi. Adres sorunlarından biriyse eksik; eşleşiyorsa tamam; bilinmiyorsa sırası
   gelmedi. Metin: mod açık, TV'de adres var ve eşleşmiyorsa `setup.samsung.address.mismatch %@ %@` (önce TV'nin Host PC IP
   alanında kayıtlı değeri, sonra doğrusunu yan yana veren satır);
   değilse `setup.samsung.address.ok %@` (Host PC IP alanında doğru adresin, yani bu Mac'inkinin durduğunu, adresi parantez içinde vererek söyleyen satır).
3. Yeniden başlatma: mod kapalıysa sırası gelmedi; kapı açıksa tamam, metin `setup.samsung.restart.ok` (TV'nin yeniden
   başladığını ve kuruluma hazır olduğunu söyleyen satır); "yeniden başlatılmamış" sorunuysa eksik; metin
   `setup.samsung.restart` (ayar değiştikten sonra TV'nin baştan açılmış olması gerektiğini söyleyen satır).

Altında yalnız eksik adımın anlatımı:
- TV yanıt vermiyor: gösterge + `setup.samsung.noAnswer` (TV'den yanıt beklendiğini söyleyen satır; Türkçesi **TV'nin
  yanıtı bekleniyor…**) + ipucu `setup.samsung.noAnswer.hint` (iki şey söyler: TV çalışır durumda ve Mac'le tek ağda
  olmalı; ekran kendisi sürer).
- Mod kapalı: `setup.samsung.modeOff` (mod açılır açılmaz yüklemeyi Nino'nun üstleneceğini söyler) + pencere
  adımları + ipucu `setup.samsung.modeOff.account` (sonraki adımda parasız bir Samsung hesabıyla tek seferlik oturum
  açılacağını; Samsung'un uygulamayı o TV'ye göre imzalamak için bunu istediğini anlatır)
- Yanlış adres (hata): `setup.samsung.wrongAddress %@ %@` (Host PC IP alanında farklı bir değer durduğu
  için bu bilgisayarın kabul edilmediğini söyler, önce TV'deki adresi, sonra olması gereken adresi verir) + pencere
  adımları + ikincil `setup.samsung.tryAnyway` (Try Anyway / **Yine de Dene**).
- Başında sıfır: `setup.samsung.leadingZeros %@ %@` (TV'deki adresin bölümlerinin başına sıfır konduğu için kabul
  edilmediğini söyler, önce TV'deki yazımı, sonra sıfırsız doğru yazımı verir) + adımlar + `setup.samsung.tryAnyway`.
- Ters: `setup.samsung.reversed %@ %@` (TV adresi ters sırada kaydetmiş; TV arayüzü sağdan sola okunan bir dildeyse bunun
  olduğunu, Developer mode'u kapatıp açarak adresi tersten yazmasını, böylece TV'nin onu doğru sırada saklayacağını
  anlatır; önce TV'deki, sonra doğru adres) + adımlar + `setup.samsung.tryAnyway`.
- 127.0.0.1: `setup.samsung.loopback %@` (Host PC IP alanında 127.0.0.1 durduğunu, bunun TV'nin kendi içindeki
  kurucular için olduğunu, Nino'nun ise bu bilgisayardan kurduğunu, adresin verilen adrese çevrilmesini söyler) +
  adımlar (`setup.samsung.tryAnyway` yok).
- Yeniden başlatılmamış: hata `setup.samsung.notRestarted` (modun açık olduğunu, ama TV ayardan sonra tam olarak
  yeniden başlamadığı için kurulumu kabul etmediğini söyleyen cümle) + ipucu `setup.samsung.notRestarted.hint` (iki yol verir: kumandada güç tuşunu, ekranda Samsung logosu
  çıkana dek bırakmamak ya da TV'yi bir dakikalığına prizden ayırmak; tuşa kısaca dokunmanın TV'yi yalnız uykuya
  aldığını ve ekranın kendisi süreceğini de ekler)
- Koptu (eksik adım yok): Host PC IP eşleşiyorsa hata `setup.samsung.dropped` (ayarlar yerinde görünmesine karşın
  TV'nin bağlantıyı kopardığını söyler; TV'yi bir dakika prizden ayırıp yeniden takmayı ve TV açılınca bir dakika
  daha vermeyi önerir; TV dönünce Nino'nun kendiliğinden bir daha deneyeceğini ekler); değilse hata
  `setup.samsung.notAccepted` (Mac'in TV tarafından içeri alınmadığını söyler; Developer Mode penceresindeki Host PC IP
  alanının bu Mac'in adresini taşıdığına bakıp TV'yi kapatıp açmayı ister) + `setup.samsung.macAddress %@` (bu
  bilgisayarın adresini, Host PC IP'ye yazılacak değer diye veren satır) + `setup.samsung.restartHold` (Samsung TV'de güç tuşuna kısaca
  dokunmanın yalnız uykuya aldığını; tam kapatıp açmak için tuşun ekran kararana dek yaklaşık 2 saniye tutulması
  gerektiğini anlatır). Sebep varsa `setup.samsung.details` (Details: / **Ayrıntılar:**) + sebep; `setup.sendLog %@`
  (sorun tekrarlanırsa `%@` ile verilen dosyanın bize yollanmasını ister) (kurulum günlüğü) ve
  `setup.tvApp.tryAgain` (Try Again / **Tekrar Dene**).
- Henüz bilgi yok: gösterge + `setup.samsung.checking` (Checking the TV… / **TV denetleniyor…**)

**Pencere adımları** (ipucu satırları). Birinci satır model yılına göre:
- 2022 ve sonrası: `setup.samsung.window.step1.new` (TV'de Apps / Uygulamalar sayfasını açıp en dibe kadar inmeyi ve
  App Settings / Uygulama Ayarları'nı seçmeyi anlatır).
- Eski ya da bilinmiyor: `setup.samsung.window.step1.old` (iki dilde de Uygulamalar'ı açtırır; sayfanın dibinde
  Uygulama Ayarları görünüyorsa oraya girilmesini söyler).
- `setup.samsung.window.step2` (üç şey söyler: 1'den 5'e kadar rakamları sırayla girmek; kumandada rakamlar
  bulunmuyorsa 123 tuşuyla ekranda seçmek; son rakamla Developer Mode penceresinin çıkması).
- `setup.samsung.window.step3 %@` (iki dilde de: Developer mode anahtarını On konumuna almak, `%@` ile verilen Mac adresini Host PC IP
  kutusuna, her bölümü başında sıfır olmadan yazmak, OK'i seçmek; adres değiştirilemiyorsa önce kumandanın
  123 tuşuna basmak).
- `setup.samsung.window.step4` (dördüncü adım: TV'yi kapatıp açmak; yol olarak güç tuşunu, ekranda Samsung logosu çıkana dek
  tutmayı ya da bir dakika prizden ayırmayı verir; ekranın kendisi süreceğini ekler)
- Açılır bölüm `setup.samsung.window.notOpening` (The window doesn't open?; Türkçesi pencerenin açılmadığını soran kısa
  başlık) (açıklama), içinde (üstten 8, aralık 8) `setup.samsung.window.tip1`…`tip4`:
  - tip1: rakamların Uygulamalar'ın açılış sayfasında değil, dipteki Uygulama Ayarları ekranında girilmesi
    gerektiği; 2022 ve sonrası modellerde açılış sayfasında hiçbir şey olmadığı.
  - tip2: TV'yi güç tuşunu logo görünene dek basılı tutarak baştan açıp bir daha denemek; kimi modellerde
    pencerenin ancak birkaç (iki-üç) denemeden sonra çıkması.
  - tip3: 12345'i TV'ye takılı bir USB klavyeyle girmek; kimi modellerde telefonun SmartThings uygulamasındaki
    rakamların da iş gördüğü.
  - tip4: rakamları Nino'nun göndermesi: Uygulama Ayarları TV ekranındayken alttaki düğmeye basmak; TV önce bir izin
    sorusu çıkarabilir; her modelde işe yaramaz.
  - İkincil `setup.samsung.typeCode` (TV'ye 1'den 5'e kadar rakamları gönderen düğme) (gönderirken kapalı +
    gösterge). Sonra: `setup.samsung.typeCode.sent` (rakamların gittiğini; pencere çıkmadıysa öteki yollara
    bakılmasını söyler) ya da `setup.samsung.typeCode.unreachable` (TV'ye erişilemediğini; çalıştığına bakıp bir daha
    denenmesini söyler).
  - Davranış: kumanda WebSocket'ine bağlanılır (izin kutusu çıkabilir), 700 ms beklenir, `KEY_1`…`KEY_5` sırayla
    gönderilir: her tuş için `{"method":"ms.remote.control","params":{"Cmd":"Press","DataOfCmd":"KEY_n","Option":
    "false","TypeOfRemote":"SendRemoteKey"}}`, 90 ms sonra aynısı `"Release"`, tuşlar arası 280 ms. Dönen jeton
    saklanır. Sonuç günlüğe yazılır.

**Giriş kartı** (yardımcı Samsung girişi istedi):
- `setup.tvApp.samsung.signIn` (Samsung hesap sayfasının tarayıcıda açıldığını ve oturumun orada tamamlanmasını
  söyler; sayfa gözükmüyorsa tarayıcıya geçmeyi ya da `setup.tvApp.samsung.signIn.reopen` düğmesini önerir)
- İpuçları: `setup.tvApp.samsung.signIn.why` (Samsung'un uygulamayı kullanıcının ücretsiz hesabıyla o TV'ye özel
  imzaladığını söyleyen satır) / `setup.tvApp.samsung.signIn.noAccount` (hesabı olmayanın aynı sayfada ücretsiz hesap
  açabileceğini ve tarayıcı yerel ağdaki cihazlara erişim izni sorarsa izin vermesini söyleyen satır) /
  `setup.tvApp.samsung.signIn.popup` (oturum penceresi gelmiyorsa tarayıcının onu pop-up sayıp durdurmuş
  olabileceğini; adres çubuğunun yanındaki simgeyle sayfaya izin verip yeniden açma düğmesine basılmasını söyler)
- Satır: gösterge + `setup.tvApp.samsung.signIn.waiting` (girişin beklendiğini söyleyen satır; Türkçesi **Giriş
  bekleniyor…**), sağda ikincil `setup.tvApp.samsung.signIn.reopen` (sayfayı bir daha açan düğme) ve
  `setup.tvApp.samsung.signIn.copy` (Copy the Link / **Bağlantıyı Kopyala**) (adresi panoya yazar).

### 5.3 Android TV

**Mod kapalı** (ağda ADB'si açık TV bulunamadı):
- `setup.tvApp.android.notInstalled` (TV'de uygulamanın bulunmadığını; hata ayıklama açıldıktan sonra Nino'nun onu ağdan
  kendisinin yükleyeceğini söyler)
- İpuçları:
  - `setup.tvApp.android.step1` (TV ayarlarında Hakkında sayfasına giden yolu verir: Android TV'de Device
    Preferences altından, Google TV'de System altından; Türkçesi TV'nin Türkçe menü adlarını kullanır).
  - `setup.tvApp.android.step2` (Hakkında sayfasındaki yapı numarası satırında, TV geliştirici kipine geçildiğini
    bildirene dek Tamam'a 7 defa basma adımı)
  - `setup.tvApp.android.step3` (bir üst menüye (Google TV'de System) dönüp Developer options içinde USB debugging'i
    açma adımı; Network debugging de listelenmişse onun da açılmasını ister)
- Gösterge + `setup.tvApp.android.looking` (TV'nin ağda arandığını söyleyen satır; Türkçesi **TV ağda aranıyor…**)
- İpucu `setup.tvApp.android.menuHint` (menü adlarının üreticiye göre biraz farklı olabileceğini; uygulama TV'de
  zaten varsa bu adımın atlanabileceğini söyler)
- Bağlantı `setup.tvApp.android.usb` (ağ yerine USB bellekle kurma yolunu sunan bağlantı adı) (`https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/KURULUM.md#5-tv-uygulamas%C4%B1n%C4%B1-kurma`).

**Onay kartı:** `setup.tvApp.android.approve` (TV'ye bakılmasını, TV'nin, Mac'ten gelecek hata ayıklama bağlantısına izin
verilip verilmeyeceğini sorduğunu söyleyen satır) + ipucu `setup.tvApp.android.approveHint` (TV'deki sorunun içinde bu Mac'e
kalıcı izin veren kutunun işaretlenip onaylanmasını; sonra yüklemenin kendiliğinden süreceğini anlatır)
+ gösterge `setup.tvApp.android.waiting` (TV'nin yanıtının beklendiğini söyleyen satır)

## 6. Android TV kurulum akışı

1. TV uygulaması altyazı sunucusuna zaten bağlıysa ve sürüm güncelse dokunulmaz ("güncel"). (Her başlatmada yeniden
   açmak oyundaki kullanıcıyı TV'de Nino ekranına atıyordu.)
2. Saklı adres varsa TCP 5555 (2 sn) denenir.
3. Ulaşılamazsa: Nino güncel sürümü daha önce kurduysa "güncel" (hata ayıklama kapalı olabilir, sorun değil). Değilse
   yardımcı `android-scan` ile ağ taranır; ilk bulunan adres alınır; hiç yoksa "mod kapalı".
4. Kart "çalışıyor"; yardımcı `android-install` çalıştırılır. TV'de onay istenirse kart "onay" hâline geçer.
5. Başarıda TV kaydı bulunan adresle güncellenir, sürüm saklanır, kart "güncel".

Yardımcının Android'de yaptıkları (tek ADB bağlantısında, TV onayı en çok bir kez): kurulu sürüm `dumpsys package`
ile okunur. Güncelse "diğer uygulamaların üzerinde göster" izni verilir (`SYSTEM_ALERT_WINDOW`; bazı TV'lerde katman
kipi için gerekir, verilemezse kurulum yine başarılı) ve uygulama çalışmıyorsa (`pidof` boş) açılır. Eskiyse önce
tamamen kaldırılır (`pm uninstall`), APK kurulur, izin verilir, `am start -n com.ninotranslator.tv/.MainActivity` ile
açılır. Play Store yolu kullanılmaz; TV uygulaması her zaman yanındaki APK ile kurulur. ADB anahtarı Nino'nun destek
klasöründeki `adb` alt klasöründe kalıcıdır (TV onayı bir kez sorulsun).

## 7. Kurulum hata iletileri

Kartta önce ana ileti, sonra (varsa) boş satır + sebep: Samsung'da `tv.install.detailsLabel` (Details: /
**Ayrıntılar:**), öbürlerinde `tv.install.tvSaysLabel` (The TV replied: / **TV'nin yanıtı:**). Mac App Store sürümünde
"kurulamadı" hatasına ayrıca: `tv.install.error.appStoreHint` (mağaza sürümü TV uygulamasını yükleyemezse ilk yüklemenin
GitHub'daki DMG sürümüyle bir kez yapılmasını; sonrasında mağaza sürümünün tek başına yettiğini söyler)

| Hata | Anahtar | Ne söyler |
|---|---|---|
| Key Server kapalı | `tv.install.error.keyServerOff` | Key Server'ın kapalı olduğunu; Developer Mode uygulamasında açılıp uygulamanın TV'de ekranda bırakılmasını ister. |
| Parola yanlış | `tv.install.error.wrongPassphrase` | Girilen passphrase'in tutmadığını; TV'de görünenle harf harf karşılaştırılmasını ister. |
| Anahtar reddedildi | `tv.install.error.keyRejected` | TV'nin anahtarı geri çevirdiğini; Key Server açılıp passphrase'in yeniden girilmesini ister. |
| Ulaşılamadı (Samsung) | `tv.install.error.unreachableSamsung` | Mac'e TV'nin kapıyı açmadığını; Developer Mode penceresindeki Host PC IP alanının bu Mac'in adresini taşıdığına bakıp TV'yi kapatıp açmayı ister. |
| Ulaşılamadı (öbürleri) | `tv.install.error.unreachable` | TV'den ses çıkmadığını; açık ve Mac'le tek ağda olduğuna bakılmasını ister. |
| Kurulamadı, sebep var | `tv.install.error.failedWithReason` | Yüklemenin olmadığını; bir daha denenmesini, yine olmazsa altta yazan sebebin bize iletilmesini ister. |
| Kurulamadı | `tv.install.error.failed` | Yüklemenin olmadığını ve bir daha denenmesini söyler. |
| Yer yok | `tv.install.error.noSpace` | TV belleğinin dolduğunu; kullanılmayan bir uygulama TV'den kaldırılıp yeniden denenmesini ister. |
| Çok eski (Samsung) | `tv.install.error.tooOld` | Bu Samsung modelinin Nino TV uygulamasını çalıştıramayacak kadar eski olduğunu; desteğin 2017 ve sonrası modellerde olduğunu söyler. |
| Giriş olmadı | `tv.install.error.loginFailed` | Samsung oturumunun yarım kaldığını; yeniden deneyip açılan sayfada oturumun sonuna dek götürülmesini ister. |
| Sertifika verilmedi | `tv.install.error.certificateFailed` | Samsung'un imza sertifikasını vermediğini; birkaç dakika sonra yeniden denenmesini ister. |
| Onay verilmedi (Android) | `tv.install.error.notApproved` | TV'de hata ayıklama izninin verilmediğini; yeniden deneyip TV'deki soruda izin verilmesini ister. |
| Başka sertifikalı eski kopya | `tv.install.error.certificateMismatch` | TV'de, farklı bir Mac ya da PC'de imzalanmış ve silinemeyen eski bir Nino TV kopyası durduğunu; TV'nin uygulama listesinden Nino'yu silip yeniden denemeyi ister. |
| Sertifika reddedildi | `tv.install.error.certificateRejected` | TV'nin imza sertifikasını reddettiğini; TV'nin çevrimiçi olmasına (sertifikayı Samsung'a doğrulatır) ve tarih-saatinin doğruluğuna bakılmasını: Settings › General › System Manager › Time. Sonra yeniden denenmesini ister; Nino taze bir sertifika isteyeceğinden Samsung oturumunun bir kez daha açılacağını ekler. |
| TV saati geride | `tv.install.error.tvClockWrong` | TV saatinin geri kaldığını, bu yüzden yeni sertifikanın TV'ye göre daha başlamadığını; tarih-saatin düzeltilmesini (aynı Time menüsü) veya birkaç dakika beklenip yeniden denenmesini ister. |
| Eski kayıt engelliyor (118, -22) | `tv.install.error.packageBlocked` | Görünmese de önceki bir Nino'nun TV'de kayıtlı kaldığı için yenisinin alınmadığını söyler (Tizen'in 118, -22 kodu); Nino listede varsa oradan silmeyi, yoksa Smart Hub'ı sıfırlamayı önerir: Settings › Support › Device Care › Self Diagnosis › Reset Smart Hub. Menü adlarının modele göre değişebileceğini söyler ve bunun indirilen öbür uygulamaları da sildiğini uyarır. |
| Bağlantı koptu | `tv.install.error.connectionLost` | Yükleme sürerken TV bağlantısının koptuğunu; TV'yi çalışır ve Mac'le tek ağda tutup yeniden denemeyi ister. |

Samsung'da ek satırlar (her biri boş satırla):
- "Kurulamadı" ve "sertifika reddedildi": `tv.install.samsung.maintenanceHint` (TV sunucu bakımı uyarısı gösteriyorsa
  bunun Samsung'a erişemediği anlamına geldiğini; internet bağlantısına ve tarih-saate bakıp TV'yi kapatıp açmayı ve
  yeniden denemeyi ister)
- "Ulaşılamadı", "kurulamadı", "sertifika reddedildi": 2 saniye basılı tutma ipucu `tv.install.samsung.holdPowerHint`
  (Samsung TV'yi gerçekten kapatıp açmak için güç tuşunun TV sönene dek yaklaşık 2 saniye tutulması gerektiğini; kısa
  dokunuşun yalnız uykuya aldığını söyler)
- "Bağlantı koptu": Anynet+ ipucu `tv.install.samsung.anynetHint` (§5'teki `setup.tvApp.samsung.anynet` ile aynı
  anlam; EN'de "input" yerine "source", TR'de "sürekli" yerine "durmadan" der).
- Her Samsung hatasının sonunda: `tv.install.sendLog` (sorun tekrarlanırsa dosyanın bize yollanmasını ister),
  `%@` kurulum günlüğünün yolu.

## 8. Gömülü yardımcı (`nino-tv-helper`)

> **Yeni Mac uygulamasında (22 Kasım):** yardımcı ayrı bir süreç değil, uygulamanın içinde Swift ile yazıldı
> (`NinoMacKit/TVSetup/Helper/`). Komutlar ve JSON olaylar aşağıdakiyle aynı; `TVHelperClient` onu
> `InProcessHelperProcessRunner` üzerinden "süreç" gibi çalıştırır. Durum:
> - **Android TV: tamam.** Kendi ADB istemcisi (TCP 5555, RSA 2048 + Security.framework, AUTH imzası jetonun SHA-1
>   özeti sayılarak; açık anahtar AOSP `android_pubkey` biçiminde). Anahtar `adb/adbkey` (PKCS#8 PEM, 0600; eski
>   dosya okunur, PKCS#1 de kabul edilir). Kurulum `exec:cmd package install -r -S <boyut>`, `cmd` özelliği yoksa
>   sync ile `/data/local/tmp/nino-tv.apk` + `pm install -r`. Tarama yalnız TCP yoklaması (el sıkışma yok, ağdaki her
>   cihazda onay kutusu çıkmasın); bu yüzden model adı taramada bilinmez, kurulumda CNXN afişinden günlüğe yazılır.
> - **Samsung: henüz yazılmadı, kart gizli.** `samsung-install` temiz bir `InstallFailed` olayı verir ve `live()`
>   ortamında `.wgt` yok sayılır (`InProcessTVHelper.supportsSamsung = false`). Önceki not "sertifikayı almanın
>   belgelenmiş yolu bulunamadı" diyordu; yol artık eski yardımcıdan okunup **§9 Samsung kurulumu: iç işleyiş**'e
>   yazıldı (giriş adresi, sertifika uç noktaları, sdb bayt düzeni, imza XML'i, hata sınıfları). Yazım oradan yapılır.

- Mac uygulamasının içinde yardımcı çalıştırılabilir olarak gelir (kaynağı Windows tarafındaki kurulum kitaplığı;
  .NET, önceden derlenmiş). Yoksa hata: kurulamadı, ayrıntı `tv.helper.missing` (nino-tv-helper'ın uygulama paketinde bulunmadığını; Nino'nun baştan
  indirilip kurulmasını ister) ve
  günlüğe yazılır.
- Her çağrıya `--exit-with-input` eklenir; standart girişi Mac uygulaması tutar. Uygulama kapanınca ya da iş iptal
  edilince giriş kapatılır ve süreç sonlandırılır; yardımcı girişi kapanınca kendini iptal eder.
- Kalıcı dosyaları Nino'nun destek klasöründe: `samsung/` (sertifikalar), `adb/` (ADB anahtarı).

**Komutlar:**
- `android-scan` → ağın /24 bölümlerinde TCP 5555'i açık adresler (aynı anda 64, 700 ms). Çıktı:
  `{"event":"found","hosts":["192.168.1.40"]}`. Hata olursa boş liste sayılır.
- `android-install --host IP --package APK --version V --key-dir DİZİN`
- `samsung-install --host IP --package WGT --version V --profiles DİZİN [--log DOSYA]` (Mac günlük olarak
  `tvinstall.log`'u verir).
- `self-test` (yayın derlemesinde imzalamanın çalıştığını sınar). Bilinmeyen komutta kullanım metni, çıkış 2.

**Çıktı:** her satır tek JSON olay:
- `{"event":"progress","step":"<adım>"}` — Samsung adımları `reading`, `signin`, `certificate`, `signing`,
  `installing`, `uninstalling`. `play` (Android'de Play Store sayfası açıldı) tanımlı ama bugün gönderilmiyor, çünkü
  Play yolu kullanılmıyor (§6); Mac yine de tanır.
- `{"event":"login","url":"https://…"}` — tarayıcıda açılacak Samsung giriş adresi (yardımcı dönüşü kendisi dinler,
  en çok 10 dk).
- `{"event":"approve"}` — Android TV ekranında hata ayıklama onayı soruluyor.
- `{"event":"done","version":"0.7.0","installed":true}` — bitti; `installed` gerçekten kurulup kurulmadığı (TV'deki
  sürüm zaten yeniyse `false`, sürüm TV'deki).
- `{"event":"error","code":"<Kod>","message":"…"}` — kodlar: `Unreachable`, `NotApproved`, `LoginFailed`,
  `CertificateFailed`, `TooOld`, `InstallFailed`, `NotEnoughSpace`, `CertificateMismatch`, `CertificateRejected`,
  `TvClockWrong`, `PackageBlocked`, `ConnectionLost`. Tanınmayan kod "kurulamadı" sayılır. `message` sebep olarak
  kartta gösterilir (boşsa kodun kendisi). Beklenmeyen hatada kod `InstallFailed`, ileti "<tür>: <ileti>". Çıkış 1.

**Okuma kuralları:** satırlar çıktı kapanana kadar sırayla okunur; ilk `done`/`found` sonuç, ilk `error` hata olur
(günlüğe "<komut>: <hata>: <ayrıntı>"). Sonuç gelmeden süreç biterse (en çok 5 sn çıkış beklenir) hata "kurulamadı",
ayrıntı `tv.helper.endedWithoutResult` (nino-tv-helper stopped without a result (exit code %1$@): %2$@ /
**nino-tv-helper sonuç vermeden durdu (çıkış kodu %1$@): %2$@**); `%1$@` çıkış kodu ya da süreç kapanmadıysa
`tv.helper.didNotExit` (did not exit / **kapanmadı**), `%2$@` hata çıktısının son 3 satırı (en çok 400 karakter). Hata çıktısının son 16 KB'ı günlüğe yazılır. Sonuç yalnız bir kez bildirilir.

Samsung kurulumunun iç işleyişi (sdb ile TV'ye bağlanma, Tizen sürümü ve DUID okuma, Samsung hesabıyla yazar/dağıtıcı
sertifikası alma, paketi imzalama, kurma ve kurtarma) yardımcının işidir; Mac uygulamasının geri kalanı yalnız yukarıdaki
olayları görür. Ayrıntısı §9'da.

## 9. Samsung kurulumu: iç işleyiş

Bu bölüm, `samsung-install` komutunun içini anlatır: geliştirici modu açık bir Samsung (Tizen) TV'ye `.wgt` paketini
ağ üzerinden kurmak. Yalnız bu tariften yazılabilsin diye her adımda adres, bayt düzeni, alanlar ve hata eşlemesi
verildi. Örnekler kodda ve testlerde görülen biçimdedir; `<…>` yer tutucudur (jeton, DUID, parola yazılmaz).

**Kanıt düzeyi.** Masaüstü (Windows/Mac yardımcısı) sdb ile imzayı hazır, MIT lisanslı bir .NET kitaplığından
kullanıyordu; o kitaplığın içi yalnız içindeki metinlerden (dizgi sırası) görülebildi. Bayt düzeyindeki tarif, eski
telefon uygulamalarının (Android/iOS) o kitaplıktan yaptığı ve testlerle doğrulanan taşımalara dayanır. Masaüstünün
kendi kodu (giriş, sertifika, sınıflama, kurtarma, dosyalar) doğrudan okundu. Emin olunamayan üç nokta
**doğrulanmadı** diye işaretli. Telefon ile masaüstünün ayrıldığı yerler ayrıca yazıldı.

### 9.1 Sıra

1. Adres denetimi ve sdb bağlantısı (§9.2, §9.3). İlerleme olayı: bağlantıdan sonra `reading`.
2. `capability` ile Tizen sürümü ve araç klasörü (§9.4). Çok eskiyse `TooOld`.
3. `0 vd_applist` ile TV'deki Nino sürümü. İstenen sürüm TV'dekinden yeni değilse iş biter:
   `done` olayı, `installed: false`, `version` TV'deki sürümdür.
4. `0 getduid` ile DUID; DUID'e bağlı profil klasörü (§9.5).
5. Geçerli sertifika yoksa: `signin` olayı, Samsung girişi (§9.6), `certificate` olayı, sertifika alma (§9.7).
6. Tizen 3.0–4.0 ise cihaz profili TV'ye gönderilir (§9.8).
7. `signing` olayı, paketin geçici bir kopyası imzalanır (§9.9).
8. `installing` olayı, kopya gönderilip kurulur. Gerekirse `uninstalling` olayı, eski kopya kaldırılıp bir kez daha
   denenir (§9.10).
9. Sürüm yeniden okunur, uygulama açılır, `done` olayı (`installed: true`).

Her adım ve TV'nin bütün yanıtları kurulum günlüğüne yazılır. Samsung jetonu ve parolalar yazılmaz. Başında
`--- Samsung kurulumu başlıyor: TV <adres>, paket <dosya adı>`, sonunda `Kurulum tamam.` ya da
`TV'de <sürüm> sürümü var; kurulum gerekmedi.` ya da `HATA <Kod>: <ayrıntı>` / `Kurulum iptal edildi.` yazılır.

### 9.2 Bağlanmadan önce

- TV adresi bir IP olmalıdır. Değilse `Unreachable`, ayrıntı `geçersiz TV adresi: <adres>`.
- Mac'in TV'ye giden kaynak adresi: TV'nin 26101 portuna bir UDP soketi "bağlanır" (paket gitmez) ve yerel uç okunur.
- `GET http://<TV>:8001/api/v2/` (2 sn zaman aşımı) yanıtından `device.developerMode` ve `device.developerIP` okunur.
  Değer dizgi değilse ham JSON metni alınır; `"0.0.0.0"` adres yok sayılır. Örnek:
  `{"device":{"developerMode":"1","developerIP":"192.168.1.50"}}`. Yanıt yoksa ikisi de bilinmez.
- Günlüğe tek satırda üç değer yazılır: Mac'in TV'ye giden adresi (LocalEndPoint), TV'nin bildirdiği Host PC IP
  (developerIP) ve geliştirici modu değeri. İki adres farklıysa ayrıca bir `UYARI: …` satırı düşülür, ama
  bağlantı yine denenir.
- Kurulum kapısı yoklaması (kart için, §5.2): TCP 26101'e 2 sn içinde bağlanılabiliyorsa "açık" sayılır.

### 9.3 sdb: TV ile konuşma (TCP 26101)

sdb, ADB'nin Tizen'deki karşılığıdır. Çerçeve düzeni ADB ile aynıdır. Farkı şudur: sürüm `0x01000000`'dır ve denetim
toplamı her zaman hesaplanıp denetlenir. Yeni Mac'teki ADB çerçeve kodu bu iki farkla kullanılabilir.

**Çerçeve.** 24 baytlık başlık, ardından veri. Başlıktaki her alan 32 bit, küçük-endian ve işaretsizdir:

| Bayt | Alan | Değer |
|---|---|---|
| 0–3 | komut | aşağıdaki tablo |
| 4–7 | arg0 | komuta göre |
| 8–11 | arg1 | komuta göre |
| 12–15 | veri uzunluğu | bayt sayısı |
| 16–19 | denetim toplamı | verideki baytların işaretsiz toplamı (taşma 32 bitte sarar) |
| 20–23 | sihirli sayı | `komut XOR 0xFFFFFFFF` |

| Komut | Sayı | ASCII |
|---|---|---|
| CNXN | `0x4E584E43` | "CNXN" |
| AUTH | `0x48545541` | "AUTH" |
| OPEN | `0x4E45504F` | "OPEN" |
| OKAY | `0x59414B4F` | "OKAY" |
| WRTE | `0x45545257` | "WRTE" |
| CLSE | `0x45534C43` | "CLSE" |

Okurken üç denetim yapılır. Uzunluk 0 ile 16 MB arasında olmalıdır. Sihirli sayı tutmalıdır; tutmazsa
`Invalid magic in frame` hatası verilir. Denetim toplamı da tutmalıdır. Biri bozuksa bağlantı hatası sayılır. Akış
erken biterse hata "TV bağlantıyı kapattı" olur.

Örnek: ilk CNXN çerçevesinin 24 baytlık başlığı (onaltılık, testte sabit):
`434e584e 00000001 00100000 14000000 8b070000 bcb1a7b1`, ardından 20 bayt `host::sdb-net-client`.

**El sıkışma.**
1. `CNXN(arg0 = 0x01000000, arg1 = 4096, veri = "host::sdb-net-client")` gönderilir. Verinin sonunda NUL yoktur.
2. Yanıtlar döngüde okunur:
   - `CNXN`: el sıkışma biter. `arg1 > 0` ise en büyük parça `min(4096, arg1)` olur. Veri, TV'nin afişidir (günlük
     için).
   - `AUTH` ve `arg0 = 1` (jeton): `AUTH(2, 0, imza)` gönderilir. İmza, jetonun RSA PKCS#1 v1.5 SHA-1 imzasıdır; jeton
     önce SHA-1 ile özetlenir. Bu, Samsung sdbd'sinin beklediğidir; Android'in adbd'si jetonu özetlemeden imzalar,
     bu yüzden ikisi farklıdır.
   - `AUTH` ve `arg0 = 3`: `AUTH(3, 0, açık anahtar)` gönderilir. Açık anahtar şu metnin ASCII baytlarıdır:
     `base64(anahtar yapısı) + " " + "<kullanıcı>@<cihaz>" + NUL`.
   - Başka bir `AUTH` türü gelirse hata `Unknown AUTH type`. Başka bir komut gelirse hata
     `Expected CNXN or AUTH`.
3. Açık anahtar yapısı (524 bayt, küçük-endian) şu alanlardan oluşur:
   - 32 bitlik sözcük sayısı: 64.
   - `n0inv`: `2^32 − (n⁻¹ mod 2^32)`.
   - Modül `n`: 256 bayt.
   - `R² = (2^2048)² mod n`: 256 bayt.
   - 32 bitlik üs.

   Bu, Android'in `android_pubkey` biçimidir. Mac'in ADB istemcisindekiyle aynıdır.
4. Anahtar 2048 bit RSA'dır ve kalıcı tutulur. Çoğu Samsung TV kimlik doğrulama istemez. Masaüstü kitaplığı anahtarı
   kullanıcı klasöründe `.sdb/adbkey` adıyla tutuyor gibi görünür (**doğrulanmadı**). Yeni Mac'te anahtar Nino'nun destek
   klasöründe tutulmalıdır.

Soket ayarları (telefon): bağlantı zaman aşımı 10 sn, okuma zaman aşımı 120 sn, TCP_NODELAY açık. Samsung sdbd'si yeni
bağlantıyı el sıkışmanın ortasında bazen keser; bu yüzden bağlantı yeniden denenir:
- Masaüstünde 3 deneme yapılır; denemelerden önceki beklemeler 0, 2 ve 5 sn'dir. Her başarısızlık günlüğe
  `sdb bağlantısı kurulamadı (i/3): <ileti>` olarak yazılır.
- Telefonda 3 deneme yapılır, aralarda 400 ms beklenir.
- Hepsi başarısızsa sonuç `Unreachable` olur. Ayrıntı:
  `sdb <TV>:26101: <son ileti>`, ardından parantez içinde bu Mac'in adresi ve TV'nin bildirdiği Host PC IP (bilinmeyen
  değer yerine `?`).

**Kanal.** Bir anda tek kanal açık tutmak yeterlidir, çünkü komutlar sırayla çalışır.
- Yerel kimlikler 98'den başlar ('a' + 1) ve her kanalda bir artar.
- Açma: `OPEN(yerel, 0, hizmet adı ASCII + NUL)` gönderilir. Ardından `arg1 = yerel` olan `OKAY` beklenir ve
  `uzak = arg0` alınır. Önce `CLSE` gelirse hata "TV kanalı açmadı".
- Gelen çerçeveler şöyle işlenir:
  - `OKAY` (arg1 = yerel): uzak kimlik henüz yoksa onu verir; varsa son yazılan parçanın onayıdır.
  - `WRTE` (arg1 = yerel): veri sıraya eklenir ve hemen `OKAY(yerel, arg0)` gönderilir. TV, kanalın `OKAY`'inden önce
    de yazabilir; o zaman uzak kimlik `arg0`'dan alınır.
  - Başka kanala gelen `WRTE`: `CLSE(arg1, arg0)` ile reddedilir.
  - `CLSE` (arg1 = yerel): kanal kapanmış sayılır ve `CLSE(yerel, arg0)` ile karşılık verilir.
  - TV'den gelen `OPEN`: `CLSE(arg1, arg0)` ile reddedilir.
  - Başka bir komut: yok sayılır.
- Yazma: veri en büyük parça boyunda bölünür. Her parça için `WRTE(yerel, uzak, parça)` gönderilir ve `OKAY` gelmeden
  sonrakine geçilmez. Kanal araya kapanırsa hata verilir.
- Okuma: kanal kapanana kadar gelen bütün parçalar birleştirilir.
- Kapatma: kanal açıksa `CLSE(yerel, uzak)` gönderilir.

**Hizmetler.**
- `shell:<komut>` + NUL: çıktının tamamı UTF-8 metin olarak alınır. Kullanılan komutlar (hepsi `0 ` önekli):
  `0 getduid`, `0 vd_applist`, `0 vd_appinstall <uygulama kimliği> <uzak yol>`, `0 vd_appuninstall <kimlik>`,
  `0 was_execute <uygulama kimliği>`.
- `capability:` + NUL: yanıtın ilk 2 baytı atlanır. Kalanı `anahtar:değer` satırlarıdır. Her satır `:`'den bölünür
  ve boş parçalar atılır. Tam 2 parça kalan satırlar alınır; aynı anahtar ikinci kez gelirse ilki geçerli kalır, yani
  değeri `:` içeren satırlar düşer. Örnek yanıt (testten):
  `8csecure_protocol:enabled\nplatform_version:6.5\nsdk_toolpath:/home/owner/share/tmp/sdk_tools\n` sonucu
  `platform_version=6.5`, `sdk_toolpath=/home/owner/share/tmp/sdk_tools` olur.
- `sync:` + NUL: dosya gönderme.
  - Paket biçimi: 4 ASCII harf, 32 bitlik küçük-endian uzunluk, ardından veri.
  - Gönderme sırası:
    1. `SEND` + uzak yol (UTF-8). Görülen biçim yalnız yoldur; ADB'deki `,mod` eki yoktur.
    2. Verinin 64 KB'lık parçaları, her biri bir `DATA` paketiyle.
    3. `DONE`; uzunluğu 4, verisi 32 bitlik küçük-endian değiştirilme zamanı (Unix saniyesi).

    Her paket kanala yukarıdaki yazma kuralıyla yazılır, yani gerekirse birkaç `WRTE` parçasına bölünür.
  - Sonra 8 baytlık başlıklar okunur:
    - `OKAY`: gönderme bitti.
    - `FAIL`: hata `sdb sync: FAIL: <metin>`; metin boşsa `unknown`.
    - Başka kimlik: atlanıp okumaya devam edilir.
    - Kanal erken kapanırsa hata verilir.

### 9.4 TV bilgisi, sürüm ve DUID

- `capability`'den `platform_version` (Tizen sürümü, kırpılır) ve `sdk_toolpath` (yoksa ya da boşsa
  `/opt/usr/apps/tmp`) alınır. Günlüğe `TV: Tizen <sürüm|?>, sdk_toolpath <yol>` yazılır.
- En eski desteklenen sürüm masaüstünde **3.0**'dır (kart metni "2017 ve sonrası" buna göredir). Daha eskiyse
  `TooOld`, ayrıntı `Tizen <sürüm>`. Telefon 2.4'ü kabul ediyordu; Mac için 3.0 geçerlidir. Sürüm okunamadıysa (boş)
  kurulum denenir. Sürüm 5.0'dan eskiyse günlüğe "2017–2018 TV'si, destek deneysel" yazılır.
- Sürüm 3.0–4.0 arasındaysa (ikisi dahil) cihaz profili gerekir (§9.8).
- **TV'deki Nino:** `0 vd_applist` çıktısı uygulama bloklarından oluşur.
  - `=` içermeyen ama `----` içeren satır blok sınırıdır.
  - Alan satırı şu biçimdedir: başta boşluk ya da tire olabilir, sonra anahtar (`[A-Za-z_]+`), `=`, değer. Değerin
    sonundaki boşluk ve tireler kırpılır.
  - Bir blokta `app_tizen_id` ya da `app_id` büyük/küçük harf ayırt edilmeden `NinoTVApps.Nino` veya `NinoTVApps` ise,
    o bloğun `app_version`'ı sürümdür. İlk eşleşen blok geçerlidir.
  - Okunamazsa ya da Nino yoksa sürüm yok sayılır. Günlüğe `vd_applist: Nino <sürüm>|Nino yok (<n> karakter)` yazılır.

  Örnek (testten; satırların başı sekmedir):
  ```
  	-------------app_title  =  Nino----------------------------
  	-------------app_tizen_id  =  NinoTVApps.Nino----------------
  	-------------app_version  =  0.9.7-----------------------------
  	------------------------------------------------------------------------
  ```
- İstenen sürüm TV'dekinden yeni değilse (sayısal karşılaştırma; `.` ve `-`'den bölünür, sayı olmayan parça 0 sayılır)
  kurulmaz. Masaüstü bu durumda uygulamayı açmaz; telefon açıyordu.
- **DUID:** `0 getduid` en çok 3 kez denenir, aralarda 500 ms beklenir. Çıktının ilk satırı kırpılır ve
  `^[A-Za-z0-9_\-+=/]{8,}$` kalıbına uymalıdır (örnek biçim: `CJCHTFRXVXQDQ`; `error: closed` gibi yanıtlar uymaz).
  Olmazsa `Unreachable`, ayrıntı `TV kimliği (DUID) okunamadı; TV'nin yanıtı: <son yanıt|boş>`.

### 9.5 Kayıtlı sertifika

- Profil klasörü: `<profiles>/<DUID>`. DUID'de `[A-Za-z0-9_-]` dışındaki her karakter `_` olur (`AB/CD=` → `AB_CD_`).
- Profil şu durumda "var" sayılır: `author.p12` ve `distributor.p12` var, `password.txt` boş değil (kırpılarak okunur).
- Profil şu durumda "geçerli" sayılır: iki sertifikanın da başlangıcı en geç `şimdi + 1 gün`, bitişi en erken
  `şimdi + 1 gün` olmalıdır (UTC). Başlangıçtaki bir günlük pay, bilgisayarın saati Samsung'unkinden biraz geride
  olunca yeni alınmış sertifikanın sürekli yeniden istenmemesi içindir. Dosya açılamıyorsa profil geçersizdir.
- `duid.txt` yoksa ya da içeriği (kırpılmış) bu DUID'e eşitse profil bu TV'nindir.
- Günlüğe şu satır yazılır: `Kayıtlı sertifika: <yok | geçerli | süresi dolmuş | başka TV'nin>; yazar <başlangıç>–<bitiş>
  UTC, dağıtıcı …, dağıtıcıyı veren <issuer>`.
- Mac'te not: p12 macOS'ta "geçici anahtar kümesi" seçeneğiyle açılamaz; masaüstünde bu yüzden ikinci kurulumdan
  itibaren her kurulum genel hatayla durmuştu. Dosyayı yalnız tarihlerine bakmak için açan kod, macOS'un desteklediği
  normal yolu kullanmalıdır.
- Profil geçersizse ya da başka TV'ninse giriş gerekir. Giriş yapılamıyorsa (komut giriş sunmuyorsa) sonuç
  `LoginFailed`, ayrıntı `giriş gerekiyor`.

### 9.6 Samsung hesabıyla giriş

Sabitler Samsung'un Tizen Studio sertifika eklentisinin kullandığı herkese açık değerlerdir:
- Giriş kapısı: `https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate`
- `clientId=v285zxnl3h`
- `state=accountcheckdogeneratedstatetext`
- Dönüş adresi: `http://localhost:4794/signin/callback`

Açılacak tam adres (dönüş adresi yüzde kodlu):
```
https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h&redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback&state=accountcheckdogeneratedstatetext&tokenType=TOKEN
```

1. Önce dinleyici açılır: TCP **4794**, IPv6 "her adres" ve çift yığın. Tarayıcı `localhost`'u `::1`'e de
   çözebildiği için IPv4 ve IPv6 birlikte dinlenir. Port açılamazsa `LoginFailed`, ayrıntı
   `giriş dönüşü için localhost:4794 açılamadı (başka bir Nino kurulumu açık olabilir): <ileti>`.
2. Sonra `{"event":"login","url":"<yukarıdaki adres>"}` olayı verilir; tarayıcıyı Mac uygulaması açar (§5.2).
3. Bağlantılar döngüde kabul edilir. Her istekte:
   - Başlık `\r\n\r\n` görülene kadar okunur (en çok 1 MB). İstek satırından yöntem ve yol, `Content-Length`'ten gövde
     uzunluğu alınır.
   - Yöntem `POST` ve yol `/signin/callback` ile başlıyorsa bu dönüştür. Gövde form biçimindedir:
     `code=<yüzde kodlu JSON>&state=<state>`. `state` form kodundan çözülür, `code` yüzde kodundan çözülür.
   - `state` sabite eşit değilse ya da `code` boşsa hesap yok sayılır.
   - JSON'dan `access_token` ve `userId` dizgileri (ikisi zorunlu, boş olamaz) ve `inputEmailID` (e-posta,
     isteğe bağlı) alınır. Örnek (testten):
     `code=%7B%22access_token%22%3A%22<jeton>%22%2C%22userId%22%3A%22<kimlik>%22%2C%22inputEmailID%22%3A%22<e-posta>%22%2C%22token_type%22%3A%22bearer%22%7D&state=accountcheckdogeneratedstatetext`
   - Yanıt `HTTP/1.1`, `Content-Type: text/html; charset=utf-8`, `Content-Length`, `Connection: close` başlıklarıyla
     verilir:
     - Hesap alındıysa `200 OK` ve iki dilli (Türkçe/İngilizce) kısa bir sayfa:
       girişin tamamlandığını ve sekmenin kapatılıp uygulamaya dönülebileceğini söyler.
     - Dönüş geldi ama hesap yoksa `400 Bad Request`.
     - Başka bir istekse `404 Not Found`. Bu iki durumda gövde `Not found` olur.
4. Hesap gelince dinleyici kapanır. Hesap, sertifika istekleri için şu üç değerdir: `access_token`, `userId`,
   `inputEmailID`.
5. Zaman aşımı **10 dakikadır**. Dolarsa `LoginFailed`, ayrıntı `Samsung girişi 10 dakikada bitmedi`. Önceden hesapsız
   bir dönüş geldiyse sona `; dönüşte hesap yoktu (<özet>)` eklenir. Özet, gövdedeki alan
   adlarının listesidir. Yalnız `error`, `error_description`, `error_code` ve `state` alanlarının değerleri yazılır;
   jeton yazılmaz. Özet en çok 200 karakterdir.

Mac sandbox'ında bu dinleyici için gelen bağlantı izni gerekir.

### 9.7 Yazar ve dağıtıcı sertifikası

**Anahtar ve istekler.** Bir tane RSA 2048 anahtar üretilir; iki istek de bu anahtarla, SHA-256 + RSA PKCS#1 v1.5
ile imzalanır. İstekler PKCS#10 biçimindedir ve PEM olarak gönderilir: `-----BEGIN CERTIFICATE REQUEST-----`, 64
karakterlik base64 satırları, `-----END CERTIFICATE REQUEST-----` (ASCII).
- **Yazar isteği:** konu `CN=Nino`; öznitelik yoktur (boş `[0]`).
- **Dağıtıcı isteği:**
  - Konu `CN=TizenSDK`. E-posta boş değilse arkasına `emailAddress=<inputEmailID>` eklenir (OID
    `1.2.840.113549.1.9.1`, IA5String).
  - Uzantı isteği özniteliği (OID `1.2.840.113549.1.9.14`) içinde tek bir uzantı vardır: Subject Alternative Name (OID
    `2.5.29.17`, kritik değil).
  - Bu uzantıda iki URI ad bulunur (bağlama özgü etiket 6, IA5String, DER baytı `0x86`):
    - `URN:tizen:packageid=` (sonu boş)
    - `URN:tizen:deviceid=<DUID>`
  - Harfler olduğu gibi yazılmalıdır (`URN`, büyük harf). Hazır SAN oluşturucular şemayı küçük harfe çevirebildiği
    için ASN.1 elle yazılır. TV imzayı yalnız kendi DUID'i bu sertifikada yazılıysa kabul eder.
  - CN'nin dizgi türü: telefon UTF8String kullanıyordu, masaüstü platformun varsayılanını. İkisi de kullanıldı.

**İstekler.** Üç istek bu sırayla `POST` edilir, gövde `multipart/form-data` (zaman aşımı 1 dk):

| Sıra | Adres | İstek dosyası | Yanıt |
|---|---|---|---|
| 1 | `https://svdca.samsungqbe.com/apis/v3/authors` | yazar (`author.csr`) | yazar sertifikası |
| 2 | `https://svdca.samsungqbe.com/apis/v1/distributors` | dağıtıcı (`distributor.csr`) | cihaz profili, olduğu gibi `device-profile.xml` olarak saklanır (denetlenmez) |
| 3 | `https://svdca.samsungqbe.com/apis/v3/distributors` | dağıtıcı (`distributor.csr`) | dağıtıcı sertifikası |

Gövdedeki alanların sırası şöyledir:
1. `access_token` = giriş jetonu
2. `user_id` = `userId`
3. `platform` = `VD`
4. Yalnız dağıtıcı isteklerinde: `privilege_level` = `public`, `developer_type` = `Individual`
5. Son olarak dosya alanı `csr`. Dosya adı `author.csr` ya da `distributor.csr`, içeriği PEM baytları.

Metin parçalarının türü `text/plain; charset=utf-8`'dir. Dosya parçasının türünü masaüstü hiç yazmıyordu, telefon
`application/octet-stream` yazıyordu. Örnek gövde (sınır rastgele):
```
--<sınır>
Content-Disposition: form-data; name="access_token"
Content-Type: text/plain; charset=utf-8

<jeton>
--<sınır>
Content-Disposition: form-data; name="user_id"
Content-Type: text/plain; charset=utf-8

<userId>
--<sınır>
Content-Disposition: form-data; name="platform"
Content-Type: text/plain; charset=utf-8

VD
--<sınır>
… (dağıtıcıda privilege_level=public, developer_type=Individual)
--<sınır>
Content-Disposition: form-data; name="csr"; filename="distributor.csr"
Content-Type: application/octet-stream

-----BEGIN CERTIFICATE REQUEST-----
…
-----END CERTIFICATE REQUEST-----
--<sınır>--
```

**Yanıtlar ve hatalar.** Her yanıt günlüğe `Sertifika sunucusu <yol>: <durum> <neden>, <n> bayt` olarak yazılır.
- Ağ hatası ya da zaman aşımı: `CertificateFailed`, ayrıntı
  `Samsung'un sertifika sunucusuna (svdca.samsungqbe.com) ulaşılamadı: <ileti>`.
- 2xx dışı durum: `CertificateFailed`, ayrıntı `Samsung sertifika sunucusu <yol>: <durum> <neden> <metin>`. Metin şöyle
  çıkarılır: gövde JSON nesnesiyse `code`, `errorCode`, `error`, `message`, `errorMessage`, `error_description`
  alanlarından dizgi ya da sayı olanlar `ad=değer` biçiminde virgülle birleştirilir. JSON değilse gövdenin ilk 300
  karakteri alınır, sona `…` eklenir.
- 2xx ama sertifika değil: Samsung bazen başarılı yanıtın içinde hata metni döndürür. Gövde `-----BEGIN CERTIFICATE-----`
  içeriyorsa PEM, içermiyorsa DER okunur. Okunamazsa `CertificateFailed`, ayrıntı
  `Samsung <yazar|dağıtıcı> sertifikası vermedi: <metin>`.

**PKCS#12.** Her sertifika için bir dosya yazılır: yaprak sertifika ve özel anahtar, ardından onu veren Samsung ara
sertifikası. Ara sertifika gömülü dört Samsung sertifikasından seçilir (Tizen Studio'daki dosyalar, değiştirilmeden
veri olarak taşınır). Sıra sabittir; konusu yaprağın veren adına eşit olan ve kendi kendini vermemiş **ilk** sertifika
alınır. İki dosyanın konusu aynı olduğu için sıra önemlidir:

| Sıra | Dosya | Konu CN | Veren CN | Bitiş |
|---|---|---|---|---|
| 1 | `vd_tizen_dev_author_ca.pem` | Samsung VD Author CA | Tizen Developers Root Class | 2040-06-19 |
| 2 | `author_ca.pem` | Samsung Author CA Class | Tizen Developers Root Class | 2030-02-06 |
| 3 | `vd_tizen_dev_public2.pem` | VD DEVELOPER Public CA Class | VD DEVELOPER Public Root Class | 2029-06-16 |
| 4 | `public2.pem` | VD DEVELOPER Public CA Class | VD DEVELOPER Public Root Class | 2029-12-15 |

Kök sertifika dosyaya konmaz. Şifreleme her platformun okuyabildiği biçimdir: PBE, 3DES (3 anahtar, PKCS#12), SHA-1,
2048 tur. Parola 16 rastgele baytın büyük harfli onaltılık yazımıdır (32 karakter). Yazılan dosyalar (§9.12):
`author.p12`, `distributor.p12`, `device-profile.xml`, `password.txt`, `duid.txt`. Günlüğe `Yeni sertifika: …` satırı
düşülür.

### 9.8 Cihaz profili (yalnız Tizen 3.0–4.0)

Bu adım Tizen Studio'daki "Permit to install applications" adımının karşılığıdır. Profil klasöründeki
`device-profile.xml`, sync ile `<sdk_toolpath>/device-profile.xml` yoluna gönderilir. Dosya yoksa ya da gönderilemezse
yalnız günlüğe yazılır ve kurulum yine denenir; TV reddederse sebebi kurulum çıktısında görünür.

### 9.9 Paketi imzalama

Uygulamayla gelen `.wgt` dosyasına dokunulmaz. Geçici klasörde `nino-<rastgele>.wgt` adıyla bir kopyası açılır ve
imzalanır. Geçici klasörde 10 dakikadan eski `nino-*.wgt` artıkları önce silinir. Kopya iş bitince silinir (3 deneme).

İmza W3C Widget Signature biçimindedir. Yazar imzası `author.p12`, dağıtıcı imzası `distributor.p12` ile atılır; ikisi
de aynı anahtardır.
- **İmzalanacak dosyalar:** zip'teki girdiler, zip'teki sıralarıyla. Klasör girdileri ve adı (küçük harfe çevrilmiş
  olarak) `author-signature.xml` ya da `signature1.xml` ile biten girdiler dışarıda kalır; eski imzalar böylece atılır.
- **`author-signature.xml`:** `Id="AuthorSignature"`, rol `author`; referanslar dosyaların hepsidir.
- **`signature1.xml`:** `Id="DistributorSignature"`, rol `distributor`; referanslar önce yeni
  `author-signature.xml`, sonra dosyalardır.
- **Algoritmalar:** her dosyanın özeti, ham baytlarının SHA-512'sinin base64'üdür. İmza RSA-SHA512'dir (PKCS#1 v1.5).
  SignedInfo, exclusive C14N ile kanonikleştirilir; `#prop` nesnesi C14N 1.1 dönüşümünden geçer.
- **Yeni zip:** önce `author-signature.xml`, sonra `signature1.xml`, sonra dosyalar eski sıralarıyla. Bu telefonun
  sırasıdır; masaüstündeki girdi sırası **doğrulanmadı**, ama TV sıraya bakmaz, çünkü referanslar ada göredir.

Dosya yapısı aşağıdadır. XML bildirimi, girinti ve boşluk yoktur; burada okunsun diye satırlara bölündü. Her öğe açık
kapanışlıdır.
```
<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" Id="AuthorSignature">
 <SignedInfo>
  <CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"></CanonicalizationMethod>
  <SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"></SignatureMethod>
  <Reference URI="config.xml">
   <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha512"></DigestMethod>
   <DigestValue>base64(SHA-512(dosya))</DigestValue>
  </Reference>
  … (her dosya için bir Reference)
  <Reference URI="#prop">
   <Transforms><Transform Algorithm="http://www.w3.org/2006/12/xml-c14n11"></Transform></Transforms>
   <DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha512"></DigestMethod>
   <DigestValue>base64(SHA-512(kanonik Object))</DigestValue>
  </Reference>
 </SignedInfo>
 <SignatureValue>base64(RSA-SHA512(kanonik SignedInfo))</SignatureValue>
 <KeyInfo><X509Data>
  <X509Certificate>\n<yaprak DER base64, 76 karakterlik satırlar, \n ile>\n</X509Certificate>
  <X509Certificate>\n<ara sertifika, aynı biçim>\n</X509Certificate>
 </X509Data></KeyInfo>
 <Object Id="prop">
  <SignatureProperties xmlns:dsp="http://www.w3.org/2009/xmldsig-properties">
   <SignatureProperty Id="profile" Target="#AuthorSignature"><dsp:Profile URI="http://www.w3.org/ns/widgets-digsig#profile"></dsp:Profile></SignatureProperty>
   <SignatureProperty Id="role" Target="#AuthorSignature"><dsp:Role URI="http://www.w3.org/ns/widgets-digsig#role-author"></dsp:Role></SignatureProperty>
   <SignatureProperty Id="identifier" Target="#AuthorSignature"><dsp:Identifier></dsp:Identifier></SignatureProperty>
  </SignatureProperties>
 </Object>
</Signature>
```
Dağıtıcı dosyasında `Id`, bütün `Target`'lar `#DistributorSignature` ve rol `…#role-distributor` olur.

- **Kanonik biçimler:** yapı sabit olduğu için XML imza kitaplığı gerekmez, kanonik biçim doğrudan yazılabilir. Dosyaya
  da aynı metin yazılır.
  - İmzalanan SignedInfo, dosyadakinin aynısıdır; yalnız kök öğe
    `<SignedInfo xmlns="http://www.w3.org/2000/09/xmldsig#">` olur.
  - Özeti alınan nesne de aynısıdır; kök öğe `<Object xmlns="http://www.w3.org/2000/09/xmldsig#" Id="prop">` olur.
- **Öznitelik kaçışları** (URI, Id, Target): `&`→`&amp;`, `<`→`&lt;`, `"`→`&quot;`, sekme→`&#x9;`,
  satır sonu→`&#xA;`, CR→`&#xD;`. Dosya adları yüzde kodlanmaz; adın kendisi yazılır.
- Telefon imzası birim testinde bağımsız bir XML imza doğrulayıcısıyla denetlenmiş, TV'de de kabul edilmişti.

### 9.10 TV'ye kurma, kurtarma, açma

**Bir kurulum denemesi.**
1. İmzalı paket sync ile `<sdk_toolpath>/<ad>.wgt` yoluna gönderilir. Telefon adı `nino-<8 onaltılık rastgele>.wgt`
   koyuyordu; masaüstü kitaplığının koyduğu ad **doğrulanmadı** (yerel kopyanın adı olabilir). Ad önemli değildir,
   yeter ki `sdk_toolpath` içinde olsun.
2. Ardından `0 vd_appinstall NinoTVApps.Nino <uzak yol>` çalıştırılır. Uygulama kimliği `config.xml`'deki
   `<tizen:application id="NinoTVApps.Nino" package="NinoTVApps" …>`'den gelir.
3. Çıktı tek metinde toplanır: önce `Push complete.`, sonra komutun bütün çıktısı. Gönderme ya da komut hata verirse
   metne `install failed: <tür>: <ileti>` satırı eklenir; tanı her zaman bu metinden yapılır, çünkü TV başarısız
   kurulumda da komutu başarılı bitirir.
4. Kitaplıkta bir `0 rmfile` komutu da var; ama ne zaman ve hangi argümanla çağrıldığı **doğrulanmadı**, telefonlar onu
   hiç çağırmıyordu. Gönderilen dosya TV'de kalabilir.

Örnek çıktılar (testlerden):
- Başarılı: `Push complete.\napp_id[NinoTVApps.Nino] installing[100]\nspend time for pkgcmd is [1234]ms\ncmd_ret:0`
- Başka sertifikayla kurulmuş kopya: `app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate
  error : :Package with the same id and different certificate has been already installed.:<-12>`
- Yazar uyuşmuyor: `app_id[NinoTVApps.Nino] install failed[118, -11], reason: Author certificate not match :`
- Sertifika reddi: `install failed[118, -12]\nreason: Check certificate error : :Invalid format of certificate in
  signature.:<-2>` (ya da `…is expired.:<-6>`)
- Saat geride: `install failed[118, -12] Check certificate error : :Certificate in signature is not valid yet.:<-7>`
- Engel: `app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was
  given:<2>`
- Yer yok: `app_id[NinoTVApps.Nino] download failed[116]`

**Sınıflama.** Bütün aramalar büyük/küçük harf ayırt etmez.
- Çıktı şu durumlardan birinde **başarısız** sayılır: `install failed`, `val[fail]`, `not enough space`,
  `download failed[116]` geçiyorsa ya da bağlantı kopma işareti varsa. Yalın `failed` aranmaz; örneğin `Pull skipped
  or failed: …` başarısızlık değildir. Başarısız değilse sonuç **başarılı**dır.
- Başarısızsa ilk tutan kural geçerlidir:

1. `transport connection`, `connection reset by peer` ya da `broken pipe` → bağlantı koptu (`ConnectionLost`).
2. `install failed[118, -4]`, `install failed[118, -19]` ya da `install failed[118019]` → uygun değil (`InstallFailed`).
3. `download failed[116]` ya da `not enough space` → yer yok (`NotEnoughSpace`).
4. Sertifika kodu: `install failed[118, -12]`, `[118012]`, `[118, -11]` ya da `[118011]`. Kod varsa ve çıktıda
   `Check certificate error` geçip `same id and different certificate` geçmiyorsa, sorun sertifikanın kendisidir:
   `not valid yet` geçiyorsa saat geride (`TvClockWrong`), geçmiyorsa sertifika reddedildi (`CertificateRejected`).
5. Kalan sertifika kodu ya da `Author certificate not match` → başka sertifikalı kopya (`CertificateMismatch`).
6. `install failed[118, -22]` ya da `[118022]` → paket kimliği engelli (`PackageBlocked`).
7. Hiçbiri → diğer (`InstallFailed`).

**Kurtarma.**
- Sonuç 5, 6 ya da 7 ise (başka sertifikalı kopya, engel, diğer) `uninstalling` olayı verilir ve iki kaldırma
  çalıştırılır: `0 vd_appuninstall NinoTVApps` ve `0 vd_appuninstall NinoTVApps.Nino`. TV sürümüne göre biri paket,
  biri uygulama kimliğini bekler. Hatası yutulur, çıktısı günlüğe yazılır.
- Sonra kurulum **bir kez** daha denenir. Yine başarısızsa ikinci çıktının sınıfıyla hata verilir.
- Öbür sınıflarda yeniden denenmez; hata hemen verilir.
- Hata ayrıntısı (kullanıcıya gösterilen):
  - Çıktı boşsa `TV yanıt vermedi`.
  - Değilse çıktının boş olmayan, kırpılmış satırlarından `fail`, `error`, `reason`, `not match` ya da `space` içeren
    ilk 3 farklı satır ` | ` ile birleştirilir. Böyle satır yoksa son 3 satır alınır. En çok 400 karakter, fazlası
    `…` ile kesilir. Bütün çıktı ayrıca günlüğe yazılır.
- `CertificateRejected` olursa profil klasörü silinmez, kenara konur: `<klasör>.rejected-<yyyyMMddHHmmss UTC>` adıyla
  taşınır, olmazsa silinir. Bir sonraki deneme Samsung'dan yeni sertifika ister.

**Bitiş.**
1. Kurulumdan sonra `0 vd_applist` yeniden okunur. TV'deki sürüm istenenden hâlâ eskiyse `InstallFailed`, ayrıntı
   `TV kurulumu bitirdi ama TV'de hâlâ <eski> sürümü var (<yeni> kurulmalıydı)`.
2. Sonra `0 was_execute NinoTVApps.Nino` ile uygulama açılır. Bazı TV'lerde eski `execute` komutu yoktur, bu yüzden
   `was_execute` kullanılır. Açılamazsa yalnız günlüğe yazılır; kurulum yine başarılıdır.
3. Sonuç `done` olayıdır: `version` TV'deki yeni sürüm (okunamadıysa istenen sürüm), `installed: true`.

### 9.11 Hata kodları (özet)

| Kod | Ne zaman | Ayrıntı |
|---|---|---|
| `Unreachable` | Adres IP değil; sdb bağlantısı 3 denemede kurulamadı; DUID okunamadı | §9.2–§9.4'teki metinler |
| `LoginFailed` | Giriş yok/gerekli; port 4794 açılamadı; 10 dk doldu | §9.5, §9.6 |
| `CertificateFailed` | Sunucuya ulaşılamadı; 2xx dışı yanıt; sertifika okunamadı | §9.7 |
| `TooOld` | Tizen < 3.0 | `Tizen <sürüm>` |
| `NotEnoughSpace` | sınıf 3 | çıktı özeti |
| `CertificateMismatch` | sınıf 5, kaldırıp yeniden denemek de olmadı | çıktı özeti |
| `CertificateRejected` | sınıf 4 (geçersiz/süresi geçmiş); profil kenara konur | çıktı özeti |
| `TvClockWrong` | sınıf 4, "not valid yet" | çıktı özeti |
| `PackageBlocked` | sınıf 6, yeniden deneme de olmadı | çıktı özeti |
| `ConnectionLost` | sınıf 1 | çıktı özeti |
| `InstallFailed` | sınıf 2 ve 7; kurulumdan sonra sürüm eski; beklenmeyen hata (`<tür>: <ileti>`) | çıktı özeti |

Telefon, adımların arasındaki her giriş/çıkış hatasını `ConnectionLost` sayıyordu; masaüstü bunları beklenmeyen hata
(`InstallFailed`) olarak veriyordu. İptal edilen iş hata olayı vermez. Kartın metinleri §7'dedir.

### 9.12 Kalıcı dosyalar

Nino'nun destek klasöründeki `samsung/` klasörü, yardımcının `--profiles` argümanıdır:
```
samsung/
  <güvenli DUID>/
    author.p12          yaprak + anahtar + ara sertifika, parolayla (3DES)
    distributor.p12     aynı biçim
    password.txt        iki p12'nin parolası (32 onaltılık karakter)
    duid.txt            sertifikanın alındığı DUID
    device-profile.xml  v1 dağıtıcı yanıtı, olduğu gibi
  <güvenli DUID>.rejected-<yyyyMMddHHmmss>/   TV'nin reddettiği eski profil (inceleme için)
```
Eski Mac ve Windows sürümleri bu biçimi yazdı. Yeni Mac bu biçimi okuyabilirse kullanıcı aynı TV'ye yeniden girişsiz
kurar. Telefon başka bir biçim kullanıyordu: parolasız `key.pk8` (PKCS#8) ile `author.cer` ve `distributor.cer` (DER);
iki biçim birbirinin yerine geçmez. Kurulum günlüğü belgenin başındaki `tvinstall.log`'dur. sdb kimlik anahtarı (§9.3) ayrı
tutulur.
