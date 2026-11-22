<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (C) 2026 Nino contributors -->

# Windows: TV bulma, eşleştirme, açık tutma ve TV uygulamasının kurulumu

Bu belge bir **tarif**tir: eski Windows uygulamasının LG (webOS), Samsung (Tizen) ve Android TV ile konuşan bütün
parçalarını kod olmadan anlatır. Yeni kod: ağ ve LG kısmı `apps/windows/src/Nino.Core/`, Samsung ve Android TV kurulumu
`apps/windows/src/Nino.TvInstall/`, Mac'e gömülen yardımcı `apps/windows/src/Nino.TvHelper/`, akış ve durum makinesi
`apps/windows/src/Nino.Shell/`. Altyazı sunucusu (8787) ve yeni protokol `tv-baglanti.md`'de.

Mac karşılığı (aynı davranışın Mac tarifi, metinlerin Türkçeleri dahil):
`git show claude/yeni-mac-c9961f:docs/yeni/mac/tv-kurulumu.md`. Aşağıda "Mac §N" bu belgeye gönderir. Windows Mac'ten
farklıysa Windows esastır; farklar §14'te.

Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamları MIT lisanslı açık
kaynak bir Samsung kurucusundan (Jellyfin2Samsung / Samsung-Jellyfin-Installer) uyarlanmıştır; yeni dosyaların başında
bu kaynak satırı korunur. sdb bağlantısı, Tizen kurulumu ve paket imzalama MIT lisanslı **TizenSdb.Core 1.1.9**
NuGet paketiyle yapılır; LG SSH'ı **SSH.NET 2026.0.0** ile (ikisi de eski projede kullanılan sürümler).

---

## 0. Ortak sabitler ve saklananlar

- Kimlikler: LG uygulaması `com.ninotranslator.tv`; Samsung uygulaması `NinoTVApps.Nino`, paket kimliği `NinoTVApps`;
  Android paketi `com.ninotranslator.tv`, ana etkinlik `.MainActivity`.
- TV uygulaması paketleri uygulama klasörünün içindeki `tv-app` klasöründedir (geliştirici derlemesinde olmayabilir):
  - LG: ilk `*.ipk`. Sürüm adından: `_` ile bölünür, en az 3 parça ve `.ipk` uzantısı varsa ikinci parça
    (`com.ninotranslator.tv_0.6.1_all.ipk` → `0.6.1`; `notes.txt` → yok).
  - Samsung: ilk `*.wgt`; Android: ilk `*.apk`. Sürüm: uzantısız adın **son** `_`'ından sonrası; `_` yoksa, başta ya da
    sondaysa yok (`nino-androidtv_0.7.0.apk` → `0.7.0`, `nino-samsung_0.7.0.wgt` → `0.7.0`, `nino.apk` → yok). Sürüm
    okunamazsa paket yok sayılır.
  - Paket yoksa o marka için "Nino kurabilir mi" = hayır; TV adımında (LG dışı) "rehberle kur" bölümü görünür.
- **İki sürüm karşılaştırıcısı** var, ikisi de "a, b'den yeni mi":
  - **Katı**: iki taraf da standart sürüm biçiminde (2–4 sayısal parça) okunabilmeli, okunamazsa "yeni değil".
    `0.10.0 > 0.9.9` evet; `0.6.1 > 0.6.1` hayır; `0.6.0 > 0.6.1` hayır. LG kurulum kararında ve uygulama
    katmanındaki "bu bilgisayarın kurduğu sürüm eskidi mi" (Samsung/Android) kararında kullanılır.
  - **Esnek**: `.` ve `-` ile bölünür, sayı olmayan parça 0, eksik parça 0. `0.10.0 > 0.9.9` evet, `0.7.0 > 0.7.0`
    hayır, `0.7 > 0.7.0` hayır, `5.0 > 4.0` evet, `5.0 > 6.5` hayır. Samsung/Android kurucularının içinde (TV'deki sürümle
    karşılaştırma, Tizen sürüm kapısı) kullanılır.
- **Güvenli depo** (`%LOCALAPPDATA%\Nino\secure.dat`, DPAPI; ayrıntı `kimlikler-veri.md`). Anahtarlar:
  - `tv`: `{"Name":"…","Host":"…","Brand":<sayı>}` — marka sayı olarak yazılır: 0 LG, 1 Samsung, 2 Android TV. Eski
    kayıtta `Brand` yoksa LG (test: `{"Name":"LG TV","Host":"1.2.3.4"}` → LG). Android TV'nin adresi boş olabilir.
  - `tvKey`: LG client-key ya da Samsung jetonu (Android'de boş dize).
  - `tvDevKey`: LG geliştirici anahtarı (parolasız PEM metni).
  - `tvAppVersion`: Samsung/Android'e Nino'nun kurduğu (ya da TV'de gördüğü) sürüm. LG'de sürüm TV'den okunur.
  - `devSessionRenewed.<adres>`: LG geliştirici modunun son uzatıldığı an (zaman damgası, saat dilimli); adres
    kırpılmış ve küçük harfli.
  - `samsungClientName`: Samsung'a gönderilen istemci adı (bugün hep "Nino"; §4.3).
- Kalıcı klasörler (`%LOCALAPPDATA%\Nino\` altında): `samsung\` (TV başına sertifika klasörleri), `adb\` (ADB anahtarı),
  `tvinstall.log` (Samsung kurulum günlüğü, kullanıcıya hata metninde gösterilen yol).
- "TV'yi sıfırla" (kurulumu TV adımından yeniden başlat) `tv`, `tvKey`, `tvDevKey`, `tvAppVersion` ve "kurulum bitti"
  işaretini siler, TV uygulaması durumunu "bilinmiyor"a çeker, çıktı "yalnız bilgisayar" ise TV'ye döndürür, TV adımına
  gider. Tam sıfırlama bunlara ek olarak hesap/PS5 anahtarlarını da siler.

---

## 1. Bilgisayarın kendi adresi (TV'ye verilen adres ve Samsung'daki Host PC IP)

### 1.1 Bağdaştırıcı listeleri
- **Özel adresler listesi** (tarama ve SSDP için): açık (çalışır durumda), geri döngü olmayan bağdaştırıcıların IPv4
  adreslerinden özel olanlar. Linux'ta adı `docker`, `br-`, `veth`, `virbr` ile başlayan köprüler atlanır (Windows'ta
  bu süzgeç yok). Liste okunamazsa boş.
- **Bağdaştırıcı adres listesi** (adres seçimi için): açık, geri döngü olmayan her bağdaştırıcının her IPv4 adresi;
  her kayıtta bağdaştırıcının adı, açıklaması, türü, adres, alt ağ maskesi (yoksa 0.0.0.0) ve "varsayılan ağ geçidi
  var mı" (0.0.0.0 olmayan bir IPv4 ağ geçidi).
- **Özel adres**: 10.x, 172.16–31.x, 192.168.x (dört baytlı olmalı). Test: 192.168.0.10, 172.20.1.1, 10.1.2.3 özel;
  8.8.8.8 ve 172.32.0.1 değil.

### 1.2 Sanal bağdaştırıcı
Türü tünel ya da PPP olan, **ya da** "ad + boşluk + açıklama" küçük harfle şunlardan birini içeren bağdaştırıcı sanaldır:
`virtual`, `vethernet`, `hyper-v`, `virtualbox`, `vmware`, `vmnet`, `wsl`, `docker`, `tailscale`, `zerotier`,
`wireguard`, `wintun`, `tap-`, `tap ` (sonda boşlukla), `openvpn`, `vpn`, `hamachi`, `radmin`, `nordlynx`,
`forticlient`, `fortinet`, `anyconnect`, `globalprotect`, `pangp`, `npcap`, `loopback`, `bluetooth`, `teredo`, `isatap`.
VPN/sanal makine/WSL bağdaştırıcıları da özel adres taşır ama TV onlara ulaşamaz; Samsung'un Host PC IP alanına böyle
bir adres yazılınca TV bağlantıyı keser.

Test: ("vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter") sanal; ("Ethernet 2", "VirtualBox Host-Only Ethernet
Adapter") sanal; ("ProtonVPN", "WireGuard Tunnel") sanal; ("Wi-Fi", "Intel(R) Wi-Fi 6 AX201 160MHz", kablosuz) değil;
("Ethernet", "Realtek PCIe GbE Family Controller") değil.

### 1.3 TV'ye giden yolun kaynak adresi
TV adresine (port **8001**) bir UDP soketi hedefe bağlanır (paket yollanmaz) ve yerel adres okunur; işletim sistemi TCP'de de bu bağdaştırıcıyı kullanır. IPv4 olmayan hedefte ya da hata olursa yok. Test: geri döngüye (127.0.0.1) giden yolun
kaynağı 127.0.0.1.

### 1.4 Seçim
Girdi: bağdaştırıcı listesi, TV adresi (yakın; yoksa boş), yolun kaynak adresi (yoksa boş).
1. Kaynak adres IPv4 ise, geri döngü değilse, 0.0.0.0 değilse ve (liste boşsa ya da listedeki bir bağdaştırıcının
   adresiyse) → o.
2. Değilse "gerçek" = sanal olmayanlar. TV adresi IPv4 ise: gerçeklerden TV ile **aynı alt ağda** olanlar (maske 4 bayt
   ve sıfır değil; adres & maske = TV & maske), ağ geçidi olan önce; yoksa herhangi bir bağdaştırıcıdan aynı alt ağda
   olan → o.
3. Değilse sırayla ilk bulunan: ağ geçidi olan ve özel adresli gerçek; özel adresli gerçek; herhangi bir gerçek; özel
   adresli herhangi biri; herhangi biri. Hiçbiri yoksa yok.

Örnekler (test; maske hep 255.255.255.0): Wi-Fi 192.168.1.34 (ağ geçitli), Hyper-V 172.24.80.1, VirtualBox 192.168.56.1,
VPN 10.2.0.2 (ağ geçitli), Kablo 192.168.1.35 (ağ geçitli):
- [Hyper-V, VirtualBox, VPN, Wi-Fi], TV 192.168.1.171, yol yok → 192.168.1.34.
- aynı liste, TV yok → 192.168.1.34; [VPN, Hyper-V, Wi-Fi], TV 10.0.0.9 → 192.168.1.34.
- [Wi-Fi, Kablo], TV 192.168.1.171, yol 192.168.1.35 → 192.168.1.35.
- [Hyper-V, Wi-Fi], TV 192.168.1.171, yol 172.24.80.1 → 172.24.80.1 (Hyper-V dış anahtarında asıl adres sanal adlı bağdaştırıcıda durur).
- [Hyper-V, Wi-Fi], TV 192.168.1.171, yol yok / 127.0.0.1 / 0.0.0.0 / 10.9.9.9 (listede yok) → 192.168.1.34.
- [VPN], TV yok → 10.2.0.2; [], TV yok → yok.

Uygulama katmanında "bu bilgisayarın adresi (yakın X)": X IPv4'e çevrilebiliyorsa yolun kaynağı hesaplanır, sonra seçim.
TV'ye verilen sunucu adresi `http://<adres ya da 127.0.0.1>:<altyazı sunucusu portu>`. Samsung kartındaki Host PC IP
satırı ve hata metinleri bu adresi (yakın = kayıtlı TV adresi; boşsa yakınsız) gösterir. Ağ değişince (Wi-Fi değişti,
VPN açıldı) kart yeniden çizilip adres yeniden hesaplanır.

### 1.5 Ağ taraması yardımcıları
- **Tarama hedefleri**: her yerel adres için aynı /24'teki `.1`–`.254` (kendi son baytı hariç), tekrarsız, ekleme
  sırasıyla. Test: 192.168.1.40 → 253 hedef, `.1` ve `.254` var, `.40` yok; 10.0.0.5 ve 10.0.0.6 → tekrar yok.
- **Portu açık adresler**: özel adres listesinin hedefleri, aynı anda en çok **64**, her biri verilen zaman aşımıyla TCP
  bağlanma; bağlananlar son bayta göre sıralı döner. İptal edilirse iptal hatası.

---

## 2. TV bulma

TV adımında LG ve Samsung araması **birlikte** başlar, sonuçlar (önce LG, sonra Samsung) birleştirilir. Her satırda
`tv.search.row` (ad, adres) ve **Bağlan** düğmesi. Hiç TV yoksa: `tv.search.notFound`. `tv.search.again` düğmesi aramayı
tekrarlar (arama sürerken kapalı).

### 2.1 SSDP (ortak)
- UDP IPv4 soketi. İstek metni (ASCII):
  `M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: <hedef>\r\n\r\n`,
  hedef 239.255.255.250:1900.
- **İki tur**: özel adres listesi boşsa varsayılan yoldan gönderilir; doluysa her özel adres için çok noktaya yayın
  arayüzü o adrese ayarlanıp gönderilir (o bağdaştırıcıdan gönderilemezse geçilir). Varsayılan bağdaştırıcı VPN ya da
  sanal ağ olabileceği için.
- Sonra zaman aşımına (varsayılan **3 sn**) kadar gelen yanıtlar okunur. Yanıt satırları `\r\n` ile bölünür, ad (büyük
  harfe çevrilmiş) : değer. `LOCATION` saklanır; `ST` ya da `NT` hedefe **tam eşitse** eşleşir. Eşleşir ve LOCATION
  mutlak adresse o adresin ana makinesi alınır.
- Adresler tekrarsızlaştırılır, sıralanır (sıradan karşılaştırma).

Test: `HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.153:1990/abc/description.xml\r\nST: urn:lge-com:service:webos-second-screen:1\r\nSERVER: WebOS/4.4.0 UPnP/1.0\r\n\r\n`
→ 192.168.1.153; `ST: urn:other` → yok.

### 2.2 LG
- Hedef `urn:lge-com:service:webos-second-screen:1`.
- Ad: `http://<adres>:1990/` (2 sn) metninde `<friendlyName>` ile `</friendlyName>` arası (ör. "[LG] webOS TV UK7550");
  okunamazsa "LG TV". Marka LG.
- Windows'ta SSDP sessizse **yedek tarama yoktur** (Mac'te /24 taraması var; §14).

### 2.3 Samsung
- Hedef `urn:samsung.com:device:RemoteControlReceiver:1`.
- Ad: `http://<adres>:8001/api/v2/` (2 sn) cevabında `device.name` (`&quot;` → `"`); okunamazsa "Samsung TV".
- SSDP hiç TV vermediyse yedek: portu **8001** açık adresler (700 ms), her birinin `device.name`'i okunabiliyorsa
  Samsung TV olarak eklenir.
- Test: `{"device":{"name":"[TV] Samsung QN70F"}}` → "[TV] Samsung QN70F"; `{}` → yok.

### 2.4 Android TV
Aranmaz. TV adımındaki Android TV satırı (açıklama: `setup.tv.androidTvHint`) **Seç** düğmesiyle ad "Android TV", adres boş, marka Android TV olan kaydı eşleştirir.

### 2.5 "TV'm yok"
"TV yok mu? bilgisayar ekranında göster" satırı (açıklama: altyazı oyunun ya da PS Remote Play'in üstünde bir pencerede
görünür, TV sonra bağlanabilir) seçilince TV kurulmaz, çıktı "yalnız bilgisayar" olur, sonraki adıma geçilir.

### 2.6 Adres değişirse (konum izleyici)
Kayıtlı TV'ye bağlanmak başarısız olunca: son aramadan bu yana **30 sn** geçtiyse (ya da hiç aranmadıysa) aynı markadaki
TV'ler yeniden aranır (LG için §2.2, Samsung için §2.3); geçmediyse ilk hata olduğu gibi döner (TV kapalıyken ağ her
denemede taranmaz). Aramada yeni adres:
1. Bulunanlardan aynı markada olanlar alınır (başka markaya geçilmez).
2. Kayıtlı adres hâlâ listede varsa → yer değişmemiş (ilk hata döner).
3. Aynı adlı **tek** TV varsa o; değilse bulunan **tek** TV varsa (adı farklı olsa da) o; yoksa tahmin edilmez (ilk hata).
Yeni adres bulunursa ona bağlanılır (hata olursa o hata döner), başarılıysa konum güncellenir ve uygulamaya bildirilir;
uygulama TV kaydını yeni adresle saklar. Sonraki bağlantılar yeni adresi kullanır.

Örnekler (test; kayıtlı "Salon" 192.168.1.153):
- Kayıtlı adres çalışıyor → hiç aranmaz.
- İlk bağlantı hata, arama [Salon 192.168.1.230] → denenen adresler [.153, .230], uygulamaya .230 bildirilir; sonraki
  bağlantı doğrudan .230.
- Bağlantı hep hata, 5 deneme, aralık 30 sn → 1 arama.
- [Yatak odası .40, Salon .230] → Salon .230. [LG TV .230] (tek, adı farklı) → o. [A .40, B .41] → yok. [Salon .153] →
  yok. Kayıtlı LG, bulunan [Salon .2 Samsung] → yok.

---

## 3. Eşleştirme ("Bağlan")

Önce altyazı sunucusu açılır (`tv-baglanti.md` §1). Bekleme yazısı: Samsung'da `tv.pair.waitingSamsung` (TV'deki izin kutusunun kumandayla onaylanması; 60 sn bekleme), diğerlerinde `tv.pair.waiting`. Eşleşme sürerken liste kapalı.
Altında iki sabit ipucu: Windows ağ izni sorarsa Özel ağlar için izin verin; TV bağlanamazsa `firewall.settings.title`
Nino'yu engelliyor olabilir, Ayarlar › `firewall.settings.title`'ndan izin verin ve bu ağı Windows'ta Özel yapın.

### 3.1 LG: SSAP (WebSocket)
- Uçlar sırayla: `wss://<adres>:3001`, `ws://<adres>:3000` (eski webOS yalnız 3000'i açar). 3001'in kendinden imzalı
  sertifikası kabul edilir (bağlantı yalnız TV'nin adresine gider).
- Her uç için: bağlanma **5 sn** zaman aşımı; bağlanınca kayıt iletisi gönderilir (yalnız **metin** çerçevesi; LG ikili
  çerçeveyi reddeder):
  `{"type":"register","id":"register_0","payload":{"forcePairing":false,"pairingType":"PROMPT","manifest":{"manifestVersion":1,"appVersion":"1.0","permissions":["LAUNCH","LAUNCH_WEBAPP","APP_TO_APP","READ_RUNNING_APPS","READ_INSTALLED_APPS"]},"client-key":"<varsa>"}}`
  (`client-key` yalnız saklı anahtar varsa).
- Onay beklenir (**60 sn**): gelen ileti `type` `registered` → `payload.client-key` (yoksa hata "bad response");
  `error` → hata (iletinin `error` alanı, yoksa "register"); başka (`response`: TV soruyu gösterdi) → beklemeye devam.
  Süre dolarsa hata "timeout". Kapanma çerçevesi → hata "closed". Gelen iletiler parça parça gelebilir, birleştirilir
  (16 KB tampon).
- Kayıt aşamasında **protokol hatası** (yukarıdakiler) olursa diğer uç denenmez, hata hemen döner. Bağlanma/ağ hatası
  olursa (iptal istenmediyse) diğer uç denenir. Hiçbiri olmazsa hata "cannot connect".
- İstek: tek seferde bir istek (kilit). Kimlik `req_1`, `req_2`… (bağlantı başına artan).
  `{"type":"request","id":"<id>","uri":"<uri>","payload":<varsa>}` gönderilir; aynı kimlikli yanıt gelene kadar diğer
  iletiler atlanır; yanıt `type:"error"` ise hata (`error` alanı, yoksa uri); değilse `payload` (yoksa boş nesne).
- Uygulama açma: `ssap://system.launcher/launch`, yük `{"id":"com.ninotranslator.tv","params":{"server":"<adres>"}}`;
  yanıtta `returnValue` false ise hata (`errorText`, yoksa "launch").
- Önplandaki uygulama: `ssap://com.webos.applicationManager/getForegroundAppInfo`, yanıtın `appId`'si (yoksa boş).
- Eşleşmede: bağlan (client-key al), sonra uygulamayı aç. Açma başarısızsa eşleşme yine başarılıdır uygulamanın
  açılamadığı not edilir (çoğu zaman bu, TV'de kurulu olmadığı anlamına gelir).

### 3.2 Samsung: uzaktan kumanda WebSocket'i
- Adres: `wss://<adres>:8002/api/v2/channels/samsung.remote.control?name=<istemci adının UTF-8 base64'ü>` ve jeton varsa
  `&token=<jeton>`. Base64 URL kodlanmaz. "Nino" → `Tmlubw==`. Test:
  `wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=Tmlubw==` ve jetonla `…?name=Tmlubw==&token=123`.
- 8002'nin kendinden imzalı sertifikası kabul edilir. Bağlanma + onay toplam **60 sn**.
- Gelen her ileti (parçalar birleştirilir): JSON değilse ya da `event` tanınmıyorsa atlanır; `ms.channel.connect` →
  onay, jeton `data.token` (yoksa boş dize); `ms.channel.unauthorized` → hata "rejected"; `ms.channel.timeOut` → hata
  "cannot connect" (TV'deki izin kutusu yanıtsız kaldı; 60 sn boşuna beklenmez); kapanma çerçevesi → "cannot connect".
  Test: `{"event":"ms.channel.connect","data":{"token":"55"}}` → "55"; `…"data":{}}` → ""; `ms.channel.ready` → atla;
  `not json` → atla.
- Uygulama açma iletisi (metin çerçevesi):
  `{"method":"ms.channel.emit","params":{"event":"ed.apps.launch","to":"host","data":{"appId":"NinoTVApps.Nino","action_type":"DEEP_LINK","metaTag":"<parametrelerin JSON metni>"}}}`
  (`metaTag` = `{"server":"http://…"}` dizgesi). Bağlantı yoksa hata.
- Önplandaki uygulama: Samsung söylemez; bağlantı açıksa boş dize, değilse hata.
- Eşleşmede: bağlan, jeton al; aç (hata yutulur — TV uygulaması bilgisayarı kendi başına da arayabilir); eşleşme hep "açıldı"
  sayılır.
- İstemci adı: güvenli depodaki `samsungClientName` doluysa o; değilse saklı jeton varsa "önceki ad", yoksa "Nino";
  "Nino" seçilip depodakinden farklıysa depoya yazılır. Bugün "önceki ad" da "Nino"dur (ad değişirse TV izni yeniden
  sorabileceği için bu kural korunur; yeni kodda hep "Nino" vermek aynı sonucu verir ama depo anahtarı okunmaya devam
  etmeli).

### 3.3 Android TV
Bilgisayar TV'yi denetlemez: eşleşme anında başarılı, anahtar boş dize, "açıldı" sayılır. TV uygulaması bilgisayarı
kendisi bulur (eski TV uygulaması 8787'yi tarar; yeni protokol için `tv-baglanti.md` §11.3).

### 3.4 Eşleşince (uygulama)
1. Marka değiştiyse ya da (Android dışında) adres değiştiyse `tvAppVersion` silinir.
2. TV kaydı ve anahtar saklanır. Anahtar = jeton kuralı: TV yeni (boş olmayan) jeton verdiyse o, boş verdiyse saklı olan
   korunur (boş jeton yazılırsa TV her bağlantıda yeniden izin sorar). Test: (saklı "55", gelen "") → "55"; ("55","77")
   → "77"; (yok, "") → "".
3. "Uygulama açılamadı" işareti saklanır (TV uygulaması kartının kararlarında kullanılır, §5.2).
4. Çıktı "yalnız bilgisayar" ise "TV" yapılır.
5. LG'de TV uygulaması durumu **beklenerek** denetlenir (§5); Samsung ve Android'de arka planda (giriş/onay dakikalar
   sürebilir; eşleşme beklemez).

### 3.5 Eşleşme hata metinleri (Windows)
- Samsung, hata "rejected": `tv.pair.error.samsungRejected`.
- Samsung, süre doldu (iptal) ya da sdb'nin "cannot connect" yanıtı: `tv.pair.error.samsungTimeout`.
- Samsung, başka hata: `tv.pair.error.noResponse`.
- LG: SSAP hatası ve sebebi "cannot connect" değilse `tv.pair.error.noResponse` + boşluk + parantez içinde sebep (ör.
  "(timeout)"); diğer her hata yalnız `tv.pair.error.noResponse`.

---

## 4. TV uygulamasını açık tutma (bekçi)

Çeviri başlarken, altyazı TV'de gösteriliyorsa ve TV eşleşmişse bekçi kurulur ve **5 sn** aralıkla çalışır; kurulunca
TV uygulaması durumu da arka planda denetlenir (§5). Çeviri durunca ya da altyazı TV'den kaldırılınca bekçi durur; TV'ye
yeniden verilince yeniden kurulur. Açılış parametreleri: `{"server":"<sunucu adresi>"}` (yeni protokolde `link` de;
`tv-baglanti.md` §11.4).

Döngü: bir tur çalışır, sonra aralık kadar bekler; turlar üst üste binmez (kilit). Tur hiçbir zaman hata fırlatmaz.

### 4.1 LG kipi
- Bağlantı yoksa: konum izleyiciyle (§2.6) bağlan, uygulamayı aç, turu bitir.
- Bağlantı varsa: önplandaki uygulamayı sor; kimlik `com.webos.app.hdmi` ile başlıyorsa, `com.webos.app.externalinput`
  ile başlıyorsa ya da tam `com.webos.app.livetv` ise (TV kendi girişine/yayınına geçmiş) uygulamayı yeniden aç.
  Kullanıcının kendi açtığı uygulamalar (Netflix gibi) kapatılmaz.
- Herhangi bir hatada bağlantı bırakılır; sonraki tur yeniden bağlanır.

Test: önplan sırası [bizimki, hdmi2, bizimki, netflix], 4 tur → 2 açma (ilk bağlanış + hdmi2), son açma parametresi
`server=http://1.2.3.4:8787`. TV ilk turda kapalı (bağlanma hatası) → açma yok; ikinci tur → bağlan + aç; sonra önplan
sorusu hata → bağlantı bırakılır; sonraki tur yeniden bağlanıp açar (toplam 3 bağlanma denemesi, 2 açma).

### 4.2 Samsung kipi
Samsung öndeki uygulamayı bildirmediğinden sürekli bağlantı tutulmaz (sık bağlantı TV'de "uzaktan kumanda bağlandı"
bildirimi çıkarıp PS5 kolunu düşürüyordu):
- TV uygulaması altyazı sunucusuna bağlıysa (bağlı TV sayısı > 0) hiçbir şey yapma.
- Son açma denemesinden bu yana **30 sn** geçmediyse bir şey yapma.
- Değilse: deneme anını yaz, konum izleyiciyle bağlan, uygulamayı aç, bağlantıyı hemen kapat. Hata yutulur.
- Bağlanırken saklı jeton kullanılır; TV yeni jeton verirse (§3.4 kuralıyla) saklanır ve sonraki bağlantı onu kullanır.
  Test: tutucu "" ile başlar; gelen "" → bir şey saklanmaz; "88" → saklanır, güncel "88"; yine "88" ve "" → değişmez;
  saklananlar yalnız ["88"].
Test: uygulama bağlı değil → 1 bağlanma + 1 açma + bağlantı kapatıldı; hemen ikinci tur → yeni bağlanma yok; uygulama
bağlı, 5 tur → yeni bağlanma yok; uygulama koptu ve 30 sn (testte 200 ms) geçti → bir açma daha.

### 4.3 Android TV
Bekçi hiçbir şey yapmaz.

### 4.4 Yeniden bağlan / durdur
"Yeniden bağlan" (bilgisayar uykudan uyanınca ya da TV uygulaması yeni kurulunca): açık bağlantı kapatılır, Samsung'un
son deneme anı silinir; sonraki tur hemen yeniden bağlanıp açar. "Durdur": döngü iptal, bağlantı kapatılır.

---

## 5. TV uygulaması durumu (kart) ve akışı

### 5.1 Durumlar
Durum = tür + isteğe bağlı sürüm, hata, giriş adresi, sebep, (Host PC uyuşmazlığında) TV'deki Host PC IP ve bu
bilgisayarın adresi. Türler: **bilinmiyor** (kart yok), **çalışıyor** (`tvApp.status.installing`), **güncel** ("TV
uygulaması hazır (sürüm X).") , **geliştirici modu kapalı**, **parola gerekiyor** (LG), **başarısız**, **giriş**
(Samsung, tarayıcıda), **TV'de onay** (Android).

Denetim aynı anda bir kez çalışır (sürerken gelen ikinci çağrı hemen döner). TV kaydı yoksa bir şey yapılmaz. Kart TV
adımına girildiğinde, eşleşmiş TV varsa ve durum "bilinmiyor"sa denetim başlar (yarıda kalmış kurulum yeniden bakılsın).

Kart kendiliğinden ilerler: durum "geliştirici modu kapalı" iken ya da (Samsung'da) hata "Host PC uyuşmazlığı" iken
**3 sn**'de bir denetim yeniden çalışır; başka durumda bu zamanlayıcı durur.

### 5.2 LG akışı
1. LG paketi yoksa çık.
2. Geliştirici modunun açık olup olmadığı (§6.1).
3. Bu arada durum "çalışıyor"a geçtiyse (kullanıcı parola alanından kurulumu başlattı) çık; kart geri dönmesin.
4. Kapalıysa: eşleşmede "uygulama açılamadı" işaretlendiyse "geliştirici modu kapalı", değilse "bilinmiyor".
5. Açık ama saklı geliştirici anahtarı yoksa: "uygulama açılamadı" ise "parola gerekiyor", değilse "bilinmiyor".
6. Anahtar varsa kurulum akışı (§5.3).

**"TV'ye Kur" düğmesi** (parola alanı boş değilse): durum "çalışıyor"; anahtar Key Server'dan parolayla alınır (§6.2;
parola kırpılır), `tvDevKey` olarak saklanır, kurulum akışı. Anahtar alınamazsa "parola gerekiyor" + o hata.

### 5.3 LG kurulum akışı
1. Durum "çalışıyor".
2. TV'deki sürüm okunur (§6.4). Varsa ve paket katı karşılaştırıcıyla daha yeni değilse: "güncel (TV'deki sürüm)",
   süre uzatma (§6.6), bitti.
3. Değilse kur (§6.5): "güncel (paket sürümü)", "uygulama açılamadı" işareti kalkar, süre uzatma, TV uygulamasını aç
   (§5.7).
4. Hata "anahtar reddedildi" ise: saklı geliştirici anahtarı silinir (geliştirici modu kapatılıp açılınca TV anahtarı yeniler), durum "parola gerekiyor" (hatasız). Diğer hatalarda "başarısız" + hata; sebep yalnız hata "kurulamadı" ya da
   "yer yok" ise ve ayrıntı boş değilse (kırpılmış) eklenir.

### 5.4 Samsung akışı
1. Samsung paketi yoksa çık. "Hatırlanan güncel" = saklı `tvAppVersion` var ve paket ondan (katı) yeni değil.
2. Ön denetim: TV'nin 8001 bilgisi (§7.1) ve bu bilgisayarın adresi (yakın = TV).
3. Geliştirici modunun açık sayılması = 8001 "kapalı" demiyorsa (bilinmiyor da açık sayılır) **ve** kurulum kapısı (TCP 26101, 2 sn)
   açıksa. Kapalıysa: hatırlanan güncelse "güncel (saklı sürüm ya da paket sürümü)", değilse "geliştirici modu kapalı".
4. Host PC uyuşmazlığı (§7.1; iki adres de biliniyor ve farklı): hatırlanan güncelse "güncel", değilse "başarısız" +
   hata **Host PC uyuşmazlığı** + TV'deki adres + bu bilgisayarın adresi. Kurulum denenmez (TV el sıkışmada keser).
5. Değilse: hatırlanan güncelse durum sessizce "güncel" kalır, değilse "çalışıyor". "Samsung denetimi sürüyor" işareti
   açılır; kurucu çalıştırılır (§7.2; olaylar §5.6).
6. Başarı: sürüm (boşsa paket sürümü) saklanır, "güncel (sürüm)"; gerçekten kurulduysa TV uygulamasını aç (§5.7).
7. Hata "ulaşılamadı" ve hatırlanan güncelse: "güncel" (çalışan uygulama kurulamamış gibi gösterilmez). Diğer
   hatalarda "başarısız" + hata + ayrıntı **her zaman** (boş değilse).
8. İşaret kapanır.

### 5.5 Android akışı
1. Android paketi yoksa çık.
2. Kayıtlı adres boşsa ya da TCP 5555 (1 sn) kapalıysa: hatırlanan güncelse "güncel" ve dur (hata ayıklama kapalı
   olabilir, sorun değil); değilse ağ taranır (§8.3), ilk bulunan adres alınır; hiç yoksa "geliştirici modu kapalı".
3. Durum "çalışıyor"; kurucu (§8.2). Başarıda TV kaydı bulunan adresle güncellenip saklanır, sürüm saklanır, "güncel".
4. Hata: "başarısız" + hata (sebep §5.3'teki kuralla).
(Not: Windows, Android'de "TV uygulaması zaten bağlı" kontrolünü yapmaz; adres ulaşılabilir ve TV uygulaması güncelse
kurucu dokunmadan döner, §8.2.)

### 5.6 Kurulum olayları (Samsung ve Android)
Olaylar ana iş parçacığına aktarılır. Kurulum bitmiş, Samsung denetimi de sürmüyor ve durum "çalışıyor/giriş/onay"
değilse **geç gelen olay yok sayılır**. Değilse:
- Giriş (adresle) → durum "giriş" + adres; adres varsayılan tarayıcıda açılır.
- TV'de onay → "TV'de onay".
- Adım ilerlemesi ve durum "giriş" ise → "çalışıyor".
- Adım ilerlemesi, durum "çalışıyor" değil ve adım `signin`, `certificate`, `signing`, `installing`, `uninstalling`
  değerlerinden biriyse → "çalışıyor" (sessiz sürüm denetimi gerçek kuruluma döndü). `reading` kartı değiştirmez.

### 5.7 Kurulumdan sonra uygulamayı açma
Bekçi çalışıyorsa ona "yeniden bağlan" denir. Değilse eşleşme yeniden yapılır (saklı anahtarla, sunucu adresiyle);
hata yutulur.

### 5.8 Kartın içeriği (Windows)
Görünürlük: durum "bilinmiyor" değilse. Bölümler:
- LG adımları (geliştirici modu kapalı + LG): Mac §5.1'deki üç adım.
- Samsung adımları (Samsung ve [geliştirici modu kapalı **ya da** başarısız + hata "ulaşılamadı"/"Host PC uyuşmazlığı"]):
  pencere adımları 1 (eski/bilinmeyen model metni: "Uygulamalar'ı açın, sayfanın en altında Uygulama Ayarları varsa
  seçin"), 2 (1 2 3 4 5 yazın…), 3 (Host PC IP olarak bu bilgisayarın adresini yazın; `%@` yerine adres, yoksa "?"),
  4 (TV'yi yeniden başlatın…) ve ipucu "Sonra ücretsiz Samsung hesabıyla bir kez giriş yaparsınız…". Metinler Mac §5.2
  "Pencere adımları" ile aynı. Windows'ta model yılına göre ilk adım ayrımı, pencere açılmazsa yardım bölümü ve beş
  rakamı TV'ye gönderen düğme yoktur.
- Android adımları (geliştirici modu kapalı + Android): Mac §5.3'teki üç adım, `tvApp.android.searching`, menü adları ipucu,
  "Bunun yerine USB bellekle kur" bağlantısı
  (sitenin Android TV rehberi: `SiteLinks.TvApp(…, androidTv: true)`; Mac'teki bağlantıdan
  farklı). Kart ayrıntıları ve aralıklar `kurulum.md` §8.1 ile aynıdır (orada uyumlu yazılmış).
- Parola alanı: durum "parola gerekiyor" **ya da** (geliştirici modu kapalı + LG). İpucu, "Passphrase" alanı, **TV'ye
  Kur**.
- Giriş hâli: "Sayfayı yeniden aç" (aynı adresi tarayıcıda açar) ve "Bağlantıyı kopyala" (adresi panoya yazar; pano
  kilitliyse sessiz; başarılıysa düğme "Kopyalandı" olur, durum değişince eski adına döner); pop-up ipucu.
- **Tekrar dene**: durum "başarısız" iken; denetimi yeniden çalıştırır.
- Durum yazısı: çalışıyor / güncel (sürüm) / geliştirici modu kapalı (markaya göre: LG "Geliştirici modu açılınca Nino
  kurabilir", Samsung "…Nino kurar", Android "…hata ayıklama açılınca Nino ağ üzerinden kurar") / parola gerekiyor
  (`tvApp.status.passphraseNeeded`) / giriş / onay. Metinler Mac §5.
- Ayrıntı yazısı: giriş hâlinde iki ipucu yan yana; onay hâlinde `tvApp.detail.approveOnTv`; güncel + LG: kalan saat biliniyorsa
  `tvApp.detail.lgHoursLeft`, değilse `tvApp.detail.lgAutoExtend`; güncel +
  Samsung: Anynet+ ipucu (§10).
- Sorun yazısı: §10.

---

## 6. LG: geliştirici modu ile kurulum

### 6.1 Geliştirici modunun açık olup olmadığı
TCP **9922** (SSH) **ya da** **9991** (Key Server) her biri **2 sn** içinde bağlantı kabul ediyorsa açık (ikisi aynı anda
denenir). Yalnız SSH'a bakılınca, TV'de Key Server ve parola ekrandayken SSH gecikmeli yanıt verdiğinde parola alanı hiç
çıkmıyordu.

### 6.2 Anahtarı alma (Key Server)
1. `http://<adres>:9991/webos_rsa` **5 sn** zaman aşımıyla indirilir. Herhangi bir hata → **Key Server kapalı**.
2. İnen metin "eski şifreli PEM" ise (içinde `Proc-Type: 4,ENCRYPTED` geçiyorsa) uygulamanın içinde çözülür (§6.3; dış
   araç ve dosya izinlerine bağlı kalınmaz). Parola kırpılır. "Parola yanlış" çıkarsa ve parola büyük harfe çevrilince
   farklıysa büyük harfli hâli de denenir (TV parolayı büyük harfle gösterir).
3. Değilse (yedek yol) sistemin `ssh-keygen`'i kullanılır: anahtar geçici klasörde rastgele adlı yeni bir dosyaya
   yazılır (Windows dışında baştan yalnız sahibine açık, 0600; dosya zaten varsa hata), `ssh-keygen -q -p -P <parola>
   -N "" -f <dosya>` çalıştırılır (pencere açmadan, çıktı + hata çıktısı birlikte toplanır). Çıkış kodu 0 değilse:
   çıktıda (harf duyarsız) "passphrase" ve ("incorrect" ya da "bad") geçiyorsa **parola yanlış**, değilse
   **kurulamadı** (ayrıntı: çıktı). Başarıda dosya okunur. Dosya her durumda silinir. `ssh-keygen` başlatılamazsa
   **araç eksik**. Araç yeri: Windows'ta `<Sistem klasörü>\OpenSSH\ssh-keygen.exe`, başka yerde `/usr/bin/ssh-keygen`.
4. Çözülen anahtar metni uygulamada `tvDevKey` olarak saklanır.

### 6.3 Eski şifreli PEM'i çözme
1. Başlık `-----BEGIN <TÜR> PRIVATE KEY-----` (tür büyük harf ve boşluk; ör. "RSA") ve `DEK-Info: <şifre>,<onaltılık IV>`
   satırı aranır; biri yoksa **kurulamadı** ("PEM başlığı okunamadı").
2. Gövde: DEK-Info satırından sonra `-----END`'e kadar, boşluklar atılarak base64. `-----END` yoksa **kurulamadı**
   ("PEM sonu bulunamadı").
3. Şifre (büyük harfe çevrilmiş): `DES-EDE3-CBC` (anahtar 24 bayt), `AES-128-CBC` (16), `AES-192-CBC` (24),
   `AES-256-CBC` (32). Başkası → **kurulamadı** ("Desteklenmeyen şifre: X").
4. Anahtar türetme (OpenSSL'in eski yöntemi, MD5, tek tur): tuz = IV'nin ilk 8 baytı; D₀ boş; Dᵢ = MD5(Dᵢ₋₁ ‖ parola
   (UTF-8) ‖ tuz); D₁‖D₂‖… istenen uzunluğa kadar birleştirilip kesilir.
5. CBC, PKCS#7 dolgu, IV = DEK-Info'daki IV ile çözülür. Çözme (dolgu) hatası → **parola yanlış**.
6. Çözülen veri DER dizisine benzemeli: en az 4 bayt, ilk bayt `0x30`; uzunluk kısa biçimde (ikinci bayt < 0x80) ya da
   uzun biçimde (1–3 uzunluk baytı); başlık + uzunluk toplam boya tam eşit. Değilse **parola yanlış** (dolgu tesadüfen
   tutmuş).
7. Çıktı: `-----BEGIN <TÜR> PRIVATE KEY-----\n` + base64 64'erli satırlar (her satır `\n` ile) +
   `-----END <TÜR> PRIVATE KEY-----\n`. İçinde "ENCRYPTED" geçmez.

Test verisi: `openssl genrsa -aes128 -passout pass:2FEEB2 1024` ve `openssl genrsa -des3 -passout pass:2FEEB2 1024`
(eski PEM biçiminde; OpenSSL 3'te `-traditional` gerekir) ile iki anahtar üret. Beklenen: ikisi de "eski şifreli" sayılır;
"2FEEB2" ile çözülür, çıktı `-----BEGIN RSA PRIVATE KEY-----\n` ile başlar, DER'i `openssl rsa -in … -passin
pass:2FEEB2 -outform DER` çıktısıyla bayt bayt aynıdır, 1024 bitlik RSA olarak okunur; "2FEEB3" ile **parola yanlış**.
`-----BEGIN OPENSSH PRIVATE KEY-----` metni "eski şifreli" değildir.

### 6.4 SSH kabuğu ve TV'deki sürüm
- SSH: kullanıcı `prisoner`, port **9922**, yalnız özel anahtarla kimlik doğrulama; bağlanma zaman aşımı **6 sn**
  (iptal 6+2 sn); komut zaman aşımı varsayılan 2 dk, kurulumda kullanılan kabukta **5 dk**. TV'nin ana makine anahtarı
  denetlenmez (her fabrika ayarında değişir). Eski `ssh-rsa` imzası kabul edilmeli (LG'nin SSH'ı yalnız onu konuşabilir).
- Anahtar her komutta geçici bir dosyaya yazılır (geçici klasör, rastgele ad), komut bitince silinir.
- Hata eşlemesi: anahtar dosyası okunamazsa **anahtar reddedildi** ("anahtar okunamadı: …"); kimlik doğrulama reddi →
  **anahtar reddedildi**; bağlanırken soket/SSH/zaman aşımı/iptal → **ulaşılamadı**; komut sırasında soket/SSH hatası →
  **ulaşılamadı**.
- Komut: girdi dosyası verildiyse dosya komutun girişine akıtılıp giriş kapatılır (`cat > dosya` dosyanın bittiğini
  böyle anlar). Sonuç: çıkış kodu (yoksa −1) ve çıktı = standart çıktı + hata çıktısı. Sonunda bağlantı kesilir.
- Testler (gerçek sunucu yoksa yalnız ilk ikisi): kapalı porta (127.0.0.1:1) → **ulaşılamadı**; anahtar olmayan düz metinli
  anahtar dosyası → **anahtar reddedildi**; (gerçek SSH sunucusuyla, ortam değişkeniyle verilir) `echo merhaba; echo uyarı
  >&2; exit 3` → kod 3, çıktı "merhaba\nuyarı\n"; 300 000 baytlık dosya `cat >` ile gönderilip `wc -c` 300000; tanınmayan
  anahtar → **anahtar reddedildi**.
- TV'deki sürüm: `cat /media/developer/apps/usr/palm/applications/com.ninotranslator.tv/appinfo.json` çıktısında
  `"version"\s*:\s*"…"` deseninin değeri; yoksa (ör. "No such file", kod 1) kurulu değil. SSH hatası çağırana gider.

### 6.5 Kurma
Uzak paket yolu: `/media/developer/temp/<paket dosya adı>`.
1. **Yükleme** (girdi = paket dosyası): `mkdir -p /media/developer/temp && rm -f /media/developer/temp/com.ninotranslator.tv_*.ipk /media/developer/temp/nino.ipk && cat > '<uzak>'`.
   Kod 0 değilse hata: "yükleme çıkış kodu N: <kısa çıktı>".
2. **Boyut denetimi**: `wc -c < '<uzak>'`; çıktı sayıya çevrilebiliyor ve yerel boyuttan farklıysa **kurulamadı**
   `tv.install.detail.packageIncomplete` (TV'deki ve yerel bayt sayısı) (kurulum denenmez). Çevrilemezse denetim atlanır.
3. **Kurulum komutu** (bekleme W = kurulum zaman aşımı saniye, tavan, en az 1; varsayılan **180**). Parçalar `; ` ile
   birleşir:
   ```text
   rm -f /media/developer/temp/nino-install.log
   sleep <W+30> </dev/null 2>/dev/null | /usr/bin/luna-send-pub -i 'luna://com.webos.appInstallService/dev/install' '{"id":"com.ares.defaultName","ipkUrl":"<uzak>","subscribe":true}' >/media/developer/temp/nino-install.log 2>&1 & L=$!
   i=0
   while [ $i -lt <W> ]; do grep -q -i -e '"state" *: *"installed' -e 'failed' -e '"returnValue" *: *false' -e '"state" *: *"success' /media/developer/temp/nino-install.log 2>/dev/null && break; kill -0 $L 2>/dev/null || break; sleep 1; i=$((i+1)); done
   cat /media/developer/temp/nino-install.log
   kill $L 2>/dev/null
   rm -f /media/developer/temp/nino-install.log
   ```
   Abonelik, giriş açık kaldıkça (sleep'ten beslenir) sürer; `-n 1` gibi ilk yanıtta çıkan biçim **kullanılmaz** (bazı
   webOS'lar abonelik kapanınca kurulumu yarıda bırakıyor). Test (W=180): `while [ $i -lt 180 ]` ve
   `sleep 210 </dev/null 2>/dev/null |` geçer, `kill $L` geçer, `-n 1` geçmez.
4. **Yanıt okuma** (satır satır): satır kırpılıp bekleyen metne eklenir; boşsa geç; `{` ile başlamıyorsa (luna-send'in
   kendi yazısı, ör. "Error: …") bekleyen sıfırlanır; JSON olarak okunamıyorsa (yarım) sonraki satırla birleşir;
   okununca bekleyen sıfırlanır ve: `returnValue` false → **hata**, sebep `errorText` ya da `errorMessage` + varsa
   " (errorCode N)"; `details.state` "failed" içeriyorsa (harf duyarsız) → **hata**, sebep `details.reason` ya da
   `details.errorText` ya da durum + `details.errorCode` (yoksa kök `errorCode`); durum "installed" içeriyorsa ya da
   "success" ile başlıyorsa → **kuruldu**. Hiçbiri yoksa sonuç belirsiz. Sayı alanları metin olarak okunur.
   Testler:
   - `{"returnValue":true,"subscribed":true}` + `{"details":{"state":"installing"},"returnValue":true}` → belirsiz;
     sonuna `{"details":{"state":"installed"},"returnValue":true}` → kuruldu; `{"details":{"state":"SUCCESS"}}` → kuruldu.
   - `…{"details":{"state":"install failed","reason":"Installation failure","errorCode":-5},"returnValue":true}` → hata,
     sebep "Installation failure (errorCode -5)".
   - `{"returnValue":false,"errorCode":-1,"errorText":"Denied method call"}` → hata, "Denied method call (errorCode -1)".
   - `Error: busy\n{"details":\n{"state":"installed"}}\n` → kuruldu.
5. Hata ise: uzak paket silinir, hata = sebep (boşsa "kurulum başarısız: <kısa çıktı>").
6. **Doğrulama**: sınır = TV "kuruldu" dediyse **30 sn**, belirsizse **60 sn**. **2 sn** arayla TV'deki sürüm okunur;
   beklenen sürüme eşitse uzak paket silinir, başarı. Süre dolarsa: "kuruldu" denmişse paket silinir (belirsizse
   silinmez: kurulum TV'de sürüyor olabilir, sonraki deneme temizler); **kurulamadı** `tv.install.detail.versionNotSeen` (sürüm, yanıt kodu, kısa çıktı).
7. Kısa çıktı: en çok 500 karakter (kırpılmış, aşarsa sonuna "…"). Silme komutu `rm -f '<uzak>'`; hatası yutulur.
8. Hata türü: hata metni ya da kanıt (komut çıktısı) yer sorunu söylüyorsa **yer yok**, değilse **kurulamadı**. Yer
   sorunu deseni (harf duyarsız): `no space`, `not enough (free )space|storage`, `insufficient (free )space|storage`,
   `out of space`, `storage (is )full`, `disk (is )full`, `ENOSPC`, `lack of space|storage`.

Testler (sahte kabukla; paket 10 bayt, bekleme ve doğrulama sınırları 200 ms, yoklama 1 ms):
- Sürüm okumaları "0.4.0", "0.4.0", sonra "0.6.1" → başarı. 1. çağrı girdiyle yükleme (`cat > '<uzak>'` ve
  `rm -f /media/developer/temp/com.ninotranslator.tv_*.ipk`), 2. `wc -c < '<uzak>'`, 3. kurulum (`luna://com.webos.appInstallService/dev/install`
  ve `"ipkUrl":"<uzak>"`), son çağrı `rm -f '<uzak>'`; ilkinden sonraki çağrıların girdisi yok.
- Kurulum yanıtı `{"returnValue":true}` + `{"details":{"state":"FAILED_IPK_INSTALL","reason":"Invalid package"},"returnValue":true}`
  → **kurulamadı**, ayrıntı "Invalid package", son çağrı paketi siler, sürüm hiç okunmaz.
- Yanıt "install failed" + "Not enough space" → **yer yok**; yükleme kodu 1 ve "cat: write error: No space left on
  device" → **yer yok**.
- "installed" yanıtı ve sürüm "0.6.1" → başarı, paket silinir.
- Sürüm hep "0.4.0" → **kurulamadı**; ilk çağrıdan sonra `rm -f '` ile başlayan çağrı yok.
- `wc -c` "7" → **kurulamadı**, iletide "7/10", kurulum çağrılmaz.
- Yükleme kodu 1 "disk full" → hata, kurulum çağrılmaz.
- Kabuk bağlanırken **anahtar reddedildi** → sürüm okuma bu hatayı aynen fırlatır.

### 6.6 Geliştirici modu süresini uzatma
LG geliştirici modu 1000 saattir. Kurulum ya da sürüm denetimi başarılı olunca, bu TV için son uzatmadan bu yana **20
saat**ten fazla geçtiyse (kayıt yoksa geçmiş sayılır):
1. SSH ile `cat /var/luna/preferences/devmode_enabled` (oturum jetonu), kırpılır; boşsa ya da boşluk içeriyorsa dur.
2. `https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=<jeton, URL kodlu>` (HTTP zaman aşımı 15 sn);
   yanıtta "success" (harf duyarsız) yoksa dur.
3. `https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=<jeton>` yanıtında `\d{1,4}:\d{2}:\d{2}`
   deseninin ilk parçası = kalan saat. Bulunursa kartta gösterilir ve an `devSessionRenewed.<adres>` olarak saklanır;
   bulunamazsa saklanmaz.
4. Her türlü HTTP/SSH hatası sessizce "bilinmiyor" döner.
Test: `{"result":"success","errorCode":"200","errorMsg":"999:58:40"}` → 999; `{"result":"fail"}` → yok;
uzatma adresi (jeton "ab12") `https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=ab12`.

---

## 7. Samsung: geliştirici modu ile kurulum

### 7.1 Ön denetim (8001)
- `http://<adres>:8001/api/v2/` (2 sn). Okunamazsa bilgi yok (kurulum yine denenir).
- `device.developerMode`: metin ya da sayı; kırpılır; boşsa bilinmiyor; "1" ya da "true" (harf duyarsız) → açık, başka
  → kapalı. `device` nesne değilse ya da alan yoksa bilinmiyor.
- `device.developerIP` (Host PC IP): boşsa ya da "0.0.0.0" ise yok.
- **Uyuşmazlık**: TV'deki Host PC IP ve bu bilgisayarın adresi **ikisi de** biliniyor ve (kırpılmış, harf duyarlı)
  farklı. Biri bilinmiyorsa uyuşmazlık sayılmaz.
Testler: `{"device":{"name":"[TV] Samsung Q60","developerMode":"1","developerIP":"192.168.1.50","ip":"192.168.1.20"},"type":"Samsung SmartTV"}`
→ açık, 192.168.1.50. `{"device":{"developerMode":"0","developerIP":"0.0.0.0"}}` → kapalı, yok. `{"device":{"developerIP":""}}`
→ yok. `{"device":{"name":"TV"}}` → bilinmiyor. `<html>` → bilinmiyor. `{"device":[]}` → IP yok.
`{"device":{"developerMode":1}}` → açık. Uyuşmazlık: (.50, .34) evet; (.34, .34) hayır; (yok, .34) hayır; (.50, yok) hayır.

### 7.2 Kurucu (adım adım)
Girdi: TV adresi, sertifika klasörlerinin kökü, paket (.wgt) yolu, paket sürümü (yoksa TV'ye bakmadan kurar). Çıktı:
TV'deki sürüm ve "gerçekten kuruldu mu". İlerleme adımları: `reading`, `signin`, `certificate`, `signing`, `installing`,
`uninstalling`. Her adım günlüğe yazılır (§7.7); jeton ve parolalar yazılmaz.

Günlükte başlangıç satırı (`--- ` önekli; TV adresi ve paket adı), sonunda başarı ya da "TV'de zaten bu sürüm var,
kurulum gerekmedi" anlamında satır; hatada kod ve ayrıntı, iptalde iptal satırı, beklenmeyende tam hata.

1. **sdb bağlantısı** (port **26101**):
   - Adres IP değilse **ulaşılamadı** `tv.install.detail.invalidAddress`.
   - Günlüğe: bu bilgisayarın TV'ye giden kaynak adresi (§1.3 yöntemi, port 26101), TV'deki Host PC IP ve geliştirici modu
     (8001'den; okunamazsa "?"). İkisi biliniyor ve farklıysa iki adresi de
     veren ve TV'nin bağlantıyı keseceğini söyleyen bir uyarı satırı.
   - Denemeler: hemen, **2 sn** sonra, **5 sn** sonra (TV yeniden başladıktan hemen sonra ve bazı 2024+ modellerde ilk
     el sıkışma kesilebiliyor). Her denemede yeni bağlantı; başarıda "sdb bağlantısı kuruldu (… , N. denemede)",
     hatada "sdb bağlantısı kurulamadı (i/3): …". Üçü de olmazsa **ulaşılamadı**
     "sdb <adres>:26101: <son hata> (bu bilgisayar <adres|?>, TV'deki Host PC IP <adres|?>)".
2. `reading`. TV yetenekleri okunur: `platform_version` (Tizen sürümü, kırpılmış) ve `sdk_toolpath` (boşsa
   `/opt/usr/apps/tmp`). Günlüğe yazılır.
3. **Tizen kapısı** (esnek karşılaştırıcı): sürüm boş değil ve **3.0**'dan eskiyse **çok eski** "Tizen X". 5.0'dan eskiyse
   günlüğe "2017–2018 TV'si, destek deneysel". Test: 2.4 ve 2.3.1 çok eski; 3.0, 4.0, 4.0.0, 5.0, 6.5, 9.0, "" değil.
4. **TV'deki sürüm**: `0 vd_applist` (§7.4). Sürüm verildiyse ve TV'de sürüm var ve paket ondan yeni değilse →
   (TV'deki sürüm, kurulmadı), bitti. Okunamazsa günlüğe yazılır, yok sayılır.
5. **DUID**: `0 getduid`, çıktının ilk satırı kırpılır; `^[A-Za-z0-9_\-+=/]{8,}$` ise DUID. Değilse **500 ms** bekleyip
   tekrar, en çok **3** deneme; olmazsa **ulaşılamadı** `tv.install.detail.duidUnreadable` (yanıt ya da boş).
   Test: "CJCHTFRXVXQDQ" DUID; "" ve "error: closed" değil.
6. **Sertifika klasörü**: kök / (DUID'de harf, rakam, `_`, `-` dışındaki her karakter `_` yapılmış). Kayıtlı sertifika
   durumu günlüğe yazılır (§7.3). Geçerli değilse ya da bu TV'nin değilse:
   - Giriş işlevi verilmemişse **giriş olmadı** `tv.install.detail.signInRequired`.
   - `signin`; günlüğe girişin beklendiği ve tarayıcının açıldığı; giriş (§7.5); `certificate`;
     sertifikalar alınır (§7.6); yeni durum günlüğe.
7. **Cihaz profili** (Tizen 3.0–4.0, yani sürüm boş değil, çok eski değil ve 4.0'dan yeni değil): klasördeki
   `device-profile.xml` TV'ye `<sdk_toolpath>/device-profile.xml` olarak gönderilir. Dosya yoksa ya da gönderilemezse
   günlüğe yazılıp geçilir (TV reddederse nedeni kurulum çıktısında yazar). Test: 3.0, 4.0, 4.0.0 profil ister; 5.0,
   6.5, 9.0, "", 2.4 istemez.
8. `signing`. Geçici klasörde **10 dakikadan eski** `nino-*.wgt` dosyaları silinir (temizlik; hata yutulur). Paket
   geçici klasöre `nino-<rastgele>.wgt` adıyla kopyalanır (asıl dosyaya dokunulmaz) ve yazar + dağıtıcı sertifikasıyla
   **yeniden imzalanır** (TizenSdb'nin imzalayıcısı; imzalı pakette `author-signature.xml` ve `signature1.xml` olur).
9. `installing`. Kurulum ve kurtarma (§7.4). Sonuç "sertifika reddedildi" ise sertifika klasörü bir kenara konur (§7.3)
   ve günlüğe sertifikanın bırakıldığı, sonraki denemede yenisinin alınacağı yazılıp hata fırlatılır.
10. Geçici paket silinir: en çok 3 deneme, aralarda bellek temizliği (kitaplık dosyayı açık bırakıyor, Windows açık
    dosyayı sildirmiyor); yine silinemezse kalır (sonraki kurulum temizler). Olmayan dosya sorun değil.
11. TV'deki sürüm yeniden okunur; sürüm verildiyse, TV'de sürüm var ve paket ondan yeniyse **kurulamadı** `tv.install.detail.stillOldVersion` (X = TV'deki sürüm, Y = kurulması gereken).
12. Uygulama açılır: `0 was_execute NinoTVApps.Nino` (eski `execute` bazı TV'lerde yok); hata yutulur, günlüğe yazılır.
13. Sonuç: (yeni sürüm, yoksa paket sürümü, yoksa "", kuruldu).

"Kayıtlı geçerli sertifika var mı" ayrı bir sorgu olarak da bulunur (bağlan, DUID oku, geçerli ve bu TV'nin mi).

### 7.3 Sertifika klasörü
Dosyalar: `author.p12`, `distributor.p12`, `password.txt` (kırpılarak okunur), `duid.txt`, `device-profile.xml`.
- **Var**: iki p12 var ve parola boş değil.
- **Geçerli** (an t): var ve her iki sertifika için başlangıç ≤ t + 1 gün **ve** bitiş ≥ t + 1 gün (başlangıçtaki bir
  günlük pay: bilgisayarın saati biraz geride diye yeni alınan sertifika her denemede tekrar istenmesin diye). Okunamazsa
  geçersiz. Sertifikalar macOS'ta kalıcı olmayan anahtar kümesi seçeneği olmadan, başka yerde geçici anahtar kümesiyle
  açılır (macOS o seçeneği desteklemez; aksi halde Mac'te ikinci kurulumdan itibaren hep hata).
- **Bu TV'nin mi**: `duid.txt` yoksa evet (eski kurulum, klasör adına güvenilir); varsa kırpılmış içerik DUID'e eşitse
  evet; okuma hatasında hayır.
- **Durum yazısı** (günlük): yoksa "yok"; değilse "<başka TV için|geçerli|süresi dolmuş>; yazar <başlangıç yyyy-MM-dd
  HH:mm>–<bitiş yyyy-MM-dd> UTC, dağıtıcı …, dağıtıcıyı veren <veren adı>"; okunamazsa "okunamadı (…)".
- **Bir kenara koyma**: klasör `<klasör>.rejected-<yyyyMMddHHmmss UTC>` adına taşınır (silinmez, incelenebilsin);
  taşınamazsa silinir; o da olmazsa bırakılır.
Testler: başlangıcı 10 dk sonra, bitişi 1 yıl sonra → şimdi geçerli, 2 yıl sonra geçersiz; `duid.txt` "AAAAAAAAAAAAA" →
o DUID için evet, "BBBBBBBBBBBBB" için hayır ve durum "başka TV için" içerir, kendi DUID'inde "geçerli"; bir kenara
koyunca klasör yok, yeni okumada "var değil", üst klasörde tek bir `DUID1234.rejected-*`; dosyasız klasör var değil ve
geçersiz.

### 7.4 sdb kabuk komutları ve kurulum çıktısı
- Kurulu uygulamalar: `0 vd_applist`. Çıktı bloklardan oluşur; `=` içermeyen ve `----` içeren satır blok ayırıcıdır.
  Alan satırı deseni: baştaki boşluk/tireler, `anahtar` (harf ve `_`), `=`, değer (sondaki boşluk/tireler atılır).
  Bir blokta `app_tizen_id` ya da `app_id` (kırpılmış, harf duyarsız) `NinoTVApps.Nino` ya da `NinoTVApps` ise ve
  `app_version` boş değilse o sürüm (ilk bulunan).
  Test: Jellyfin bloğu (`app_tizen_id = AprZAARz4r.Jellyfin`, `app_version = 1.2.3`) ve Nino bloğu (`app_tizen_id =
  NinoTVApps.Nino`, `app_version = 0.9.7`), satırlar `\t-------------app_title  =  Nino----…` biçiminde → "0.9.7";
  Nino kimliği başka olunca yok; "closed" ve boş → yok.
- Kurulum: imzalı paket TizenSdb'nin kurucusuyla gönderilip `vd_appinstall` ile kurulur (araç klasörü =
  `sdk_toolpath`). Kurucu sonucu konsola yazdığı için kurulum süresince **konsol çıktısı yakalanır** (aynı anda tek
  yakalama; genel kilit); kurucu hata fırlatırsa çıktıya "install failed: <tür>: <ileti>" satırı eklenir. Bütün çıktı
  günlüğe "vd_appinstall çıktısı:" ile yazılır.
- **Sınıflama** (harf duyarsız; ilk tutan):
  1. Başarısız sayılmazsa → **yok**. Başarısız = `install failed`, `val[fail]`, `not enough space`,
     `download failed[116]` ya da bağlantı kopması işaretlerinden biri. Yalın "failed" aranmaz.
  2. Bağlantı koptu: `transport connection`, `connection reset by peer`, `broken pipe`.
  3. Uygun değil: `install failed[118, -4]`, `install failed[118, -19]`, `install failed[118019]`.
  4. Yer yok: `download failed[116]`, `not enough space`.
  5. Sertifika kodu = `install failed[118, -12]`, `[118012]`, `[118, -11]`, `[118011]`. Sertifika kodu + `Check
     certificate error` var + `same id and different certificate` **yok** ise: `not valid yet` varsa **TV saati
     geride**, yoksa **sertifika reddedildi**.
  6. Sertifika kodu ya da `Author certificate not match` → **başka sertifikalı eski kopya**.
  7. `install failed[118, -22]` ya da `[118022]` → **eski kayıt engelliyor**.
  8. Diğer → **başka hata**.
- Kurtarma: ilk çıktı sorunsuzsa bitti. Sorun "eski kopya", "eski kayıt" ya da "başka hata" ise (eski kopyayı kaldırmak
  işe yarayabilir): `uninstalling`; `0 vd_appuninstall NinoTVApps` ve `0 vd_appuninstall NinoTVApps.Nino` (her biri
  hata verse de; sonuçlar kaldırma sonucu olarak günlüğe); bir kez daha kurulur; yine sorunluysa o sorunun hatası.
  Diğer sorunlarda (bağlantı, yer, sertifika reddi, saat, uygun değil) kaldırma denenmez, hata hemen.
- Hata eşlemesi: bağlantı → **bağlantı kesildi**; yer → **yer yok**; eski kopya → **sertifika uyuşmazlığı**; sertifika
  reddi → **sertifika reddedildi**; saat → **TV saati geride**; eski kayıt → **paket engelli**; uygun değil ve diğer →
  **kurulamadı**.
- **Kullanıcıya ayrıntı (özet)**: çıktı boşsa `tv.install.detail.noTvResponse`; değilse boş olmayan kırpılmış satırlardan "fail",
  "error", "reason", "not match", "space" içerenler (tekrarsız, en çok 3) ` | ` ile; yoksa son 3 satır; en çok 400
  karakter (+ "…").
Testler (çıktı → sınıf):
- `Push complete.\napp_id[NinoTVApps.Nino] installing[100]\nspend time for pkgcmd is [1234]ms\ncmd_ret:0` → yok
- `app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Package with the same id and different certificate has been already installed.:<-12>\ncmd_ret:0` → eski kopya
- `app_id[NinoTVApps.Nino] install failed[118, -11], reason: Author certificate not match :` → eski kopya
- `install failed[118012]` → eski kopya
- `app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Invalid format of certificate in signature.:<-2>` → sertifika reddi
- `install failed[118, -12] Check certificate error : :Certificate in signature is expired.:<-6>` → sertifika reddi
- `install failed[118, -12] Check certificate error : :Certificate in signature is not valid yet.:<-7>` → TV saati geride
- `app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was given:<2>` → eski kayıt
- `install failed[118022]` → eski kayıt; `app_id[NinoTVApps.Nino] download failed[116]` → yer yok
- `install failed[118, -4] operation not allowed` → uygun değil; `error: transport connection closed` → bağlantı
- `install failed: IOException: Remote closed channel before sending OKAY` → başka; `app_id[NinoTVApps.Nino] install failed[118]` → başka
- `Pull skipped or failed: not found\ninstalling[100]` → başarısız sayılmaz; "" → yok.
- Özet: "Push complete.\n<eski kayıt çıktısı>\ncmd_ret:0" → "install failed[118, -22]" ve "Security error" içerir, "Push
  complete" içermez; " " → `tv.install.detail.noTvResponse`.
Kurtarma testleri: (eski kopya, sorunsuz) → 2 kurulum, komutlar tam olarak [`0 vd_appuninstall NinoTVApps`,
`0 vd_appuninstall NinoTVApps.Nino`], günlükte ilk ve ikinci çıktı; sorunsuz → 1 kurulum, komut yok; (Author mismatch ×2)
→ sertifika uyuşmazlığı, ayrıntıda "Author certificate not match", 2 kurulum; (eski kayıt ×2) → paket engelli, ayrıntıda
"118, -22", 2 komut; sertifika reddi / saat / `download failed[116]` / `connection reset by peer` → sırasıyla sertifika
reddi / saat / yer / bağlantı, komut yok, 1 kurulum; kaldırma "Remote closed channel" hatası verse de 2. kurulum yapılır
ve hata günlükte.

### 7.5 Samsung hesabıyla giriş
- Adres: `https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h&redirect_uri=<URL kodlu "http://localhost:4794/signin/callback">&state=accountcheckdogeneratedstatetext&tokenType=TOKEN`.
- Dinleyici: **4794** portu, IPv6 + IPv4 birlikte (tarayıcı localhost'u ::1'e çözebilir). Açılamazsa **giriş olmadı**
  `tv.install.detail.signInPortBusy`.
- Adres "tarayıcıda aç" işlevine verilir (Windows uygulamasında olay → kart "giriş" + tarayıcı; yardımcıda `login`
  olayı). Süre: **10 dk**.
- Her bağlantı: başlıklar `\r\n\r\n`'e kadar okunur (1 MB'ı aşarsa ya da kapanırsa boş istek), `Content-Length` kadar
  gövde. Geri dönüş = `POST` ve yol `/signin/callback` ile başlıyor. Gövde `&` ile bölünür: `state` URL kodu çözülür
  (`+` boşluk), `code` yüzde kodu çözülür (`+` korunur). `state` sabite eşit değilse ya da `code` boşsa hesap yok.
  `code` JSON: `access_token` ve `userId` boş olmayan dizgeler zorunlu, `inputEmailID` isteğe bağlı (yoksa boş). Hesap
  varsa **200** ve iki dilli (Türkçe/İngilizce), girişin bittiğini ve sekmenin
  kapatılabileceğini söyleyen kısa bir sayfa (`text/html; charset=utf-8`, `Connection: close`) ve giriş biter. Geri dönüş ama
  hesap yoksa **400** "Not found" ve sebep saklanır; başka istek **404** "Not found"; beklemeye devam.
- Süre dolarsa **giriş olmadı** `tv.install.detail.signInTimeout` (+ sebep varsa "; " + `tv.install.detail.signInNoAccount`). Sebep: gövdedeki alan adları virgülle; `error`, `error_description`, `error_code`, `state`
  değerleriyle; jetonun kendisi asla yazılmaz; en çok 200 karakter.
Testler: gövde `code=<URL kodlu {"access_token":"tok","userId":"u1","inputEmailID":"a@b.c","token_type":"bearer"}>&state=accountcheckdogeneratedstatetext`
→ (tok, u1, a@b.c); state "baska" → yok; `code=bozuk` → yok. Sebep
`code=%7B%22access_token%22%3A%22gizli%22%7D&state=accountcheckdogeneratedstatetext&error=access_denied` → "error=access_denied"
ve "code" içerir, "gizli" içermez. Canlı test: dinleyici açıkken `GET /favicon.ico` → 404; ardından form gövdeli
`POST /signin/callback` → 200 ve giriş o hesapla biter.

### 7.6 Sertifika alma
- Bir **2048 bit RSA** anahtarı üretilir; iki istek de bu anahtarla, SHA-256 + PKCS#1 imzalı PEM CSR:
  - Yazar: konu `CN=Nino`.
  - Dağıtıcı: konu `CN=TizenSDK` (+ e-posta boş değilse e-posta adresi alanı); uzantı **2.5.29.17** (konu alternatif
    adı), kritik değil, DER: SEQUENCE içinde iki bağlam etiketli [6] IA5String: `URN:tizen:packageid=` ve
    `URN:tizen:deviceid=<DUID>` — **büyük harfler korunur** (hazır kitaplık yardımcıları şemayı küçük harfe çevirdiği
    için elle yazılır). Test: DUID "ABCDEF0123456789" → tam bu iki değer, konu `CN=TizenSDK` içerir.
- İstekler (çok parçalı form; alanlar: `access_token`, `user_id`, `platform=VD`; dağıtıcıda ayrıca
  `privilege_level=public`, `developer_type=Individual`; dosya alanı `csr`, dosya adı `author.csr` / `distributor.csr`),
  HTTP zaman aşımı 1 dk, sırayla:
  1. `https://svdca.samsungqbe.com/apis/v3/authors` (yazar CSR) → yazar sertifikası.
  2. `https://svdca.samsungqbe.com/apis/v1/distributors` (dağıtıcı CSR) → cihaz profili (Tizen 4 ve öncesi için;
     saklanır).
  3. `https://svdca.samsungqbe.com/apis/v3/distributors` (dağıtıcı CSR) → dağıtıcı sertifikası.
- Hatalar: ağ hatası / zaman aşımı (iptal değil) → **sertifika verilmedi** `tv.install.detail.certServerUnreachable` (ayrıntı: hata); başarısız durum kodu → **sertifika verilmedi** `tv.install.detail.certServerError` (ayrıntı: "<yol>: <kod> <açıklama> <sunucu hatası>"). Her yanıt günlüğe "Sertifika sunucusu <yol>: <kod> <açıklama>, N bayt".
- **Sunucu hatası metni**: JSON nesnesiyse `code`, `errorCode`, `error`, `message`, `errorMessage`, `error_description`
  alanlarından dizge/sayı olanlar "ad=değer" virgülle; yoksa kırpılmış metin (en çok 300 + "…"). Test:
  `{"code":"AUTH_FAIL","message":"Invalid access token"}` → "code=AUTH_FAIL, message=Invalid access token";
  " Service Unavailable " → "Service Unavailable".
- Gelen sertifika: metinde `-----BEGIN CERTIFICATE-----` varsa PEM, değilse DER. Okunamazsa (Samsung başarılı yanıtın
  içinde hata döndürebiliyor) **sertifika verilmedi** "Samsung <yazar|dağıtıcı> sertifikası vermedi: <sunucu hatası>".
  Test: `{"message":"cert service paused"}` → bu hata, ayrıntıda "cert service paused".
- Yazılanlar: parola = 16 rastgele baytın büyük harf onaltılık yazımı (32 karakter); `author.p12` ve `distributor.p12`
  = sertifika + özel anahtar + (varsa) onu veren Samsung ara sertifikası; şifreleme 3DES (PKCS#12 PBE), özet SHA-1,
  **2048** tur (her platformun okuyabildiği biçim). `device-profile.xml` (2. yanıtın baytları), `password.txt`,
  `duid.txt`.
- **Ara sertifikalar** (Tizen Studio'dan, değiştirilmeden; gömülü kaynak, mantıksal ad `SamsungCa.<ad>.pem`), arama
  sırası:
  1. `vd_tizen_dev_author_ca.pem` — "Samsung VD Author CA" (veren: Tizen Developers Root Class), 2025-06-19 – 2040-06-19
  2. `author_ca.pem` — "Samsung Author CA Class" (veren: Tizen Developers Root Class), 2015-02-10 – 2030-02-06
  3. `vd_tizen_dev_public2.pem` — "VD DEVELOPER Public CA Class" (veren: VD DEVELOPER Public Root Class), 2025-06-17 – 2029-06-16
  4. `public2.pem` — "VD DEVELOPER Public CA Class" (aynı ad), 2014-12-19 – 2029-12-15
  Konusu sertifikanın verenine **tam eşit** ve kendinden imzalı olmayan ilk ara sertifika eklenir (aynı adlı iki
  sertifikadan listede önce geleni). Dosyalar eski projenin `windows/src/Nino.TvInstall/Samsung/ca/` klasöründen aynen
  kopyalanabilir. Test: gömülü listede "Samsung VD Author CA" ve "VD DEVELOPER Public CA Class" konuları var.

### 7.7 Kurulum günlüğü
Satır: `[yyyy-MM-dd HH:mm:ss] <ileti, sondaki boşluklar atılmış>\n` (yerel saat). Yazmadan önce dosya **1 MB**'ı
(1 048 576 bayt) geçtiyse eski yarısı silinir: metnin ortasından sonraki ilk satır sonundan itibaren kalır. Klasör
yoksa oluşturulur. Yazılamazsa kurulum sürer. Yol verilmemişse hiçbir şey yazılmaz. Bütün süreçte tek kilit.
Test: "ilk satır" yazılır, dosyaya 1 MB + 10 bayt dolgu eklenir, "son satır" yazılır → dosyada "son satır" var, "ilk
satır" yok, boy < 1 MB + 1000.

---

## 8. Android TV: ADB ile kurulum

### 8.1 ADB protokolü (ağ üzerinden, Google aracı dağıtılmadan)
- Komutlar (küçük sonlu 32 bit): CNXN `0x4e584e43`, AUTH `0x48545541`, OPEN `0x4e45504f`, OKAY `0x59414b4f`,
  CLSE `0x45534c43`, WRTE `0x45545257`. AUTH türleri: jeton 1, imza 2, açık anahtar 3. Sürüm `0x01000001`. Önerilen en
  büyük yük **256 KB** (262144); TV söylemezse 4096.
- Paket: 24 baytlık başlık (hepsi küçük sonlu): komut, arg0, arg1, veri uzunluğu, veri sağlaması (baytların toplamı,
  32 bit), sihir = komut XOR `0xffffffff`; ardından veri. Okurken sihir tutmazsa ya da uzunluk **1 MB**'tan büyükse
  "ADB paketi bozuk" (G/Ç hatası).
- Bağlanma: TCP, gecikmesiz (Nagle kapalı), **5 sn** zaman aşımı; olmazsa **ulaşılamadı**.
- El sıkışma: `CNXN(sürüm, 262144, "host::\0")` gönderilir. Okuma süresi **10 sn**. Döngü:
  - CNXN gelirse: en büyük yük = min(262144, arg1 sıfırsa 4096, değilse arg1); bitti.
  - AUTH jeton gelirse ve henüz imzalanmadıysa: 20 baytlık jeton **yeniden özetlenmeden** SHA-1 özeti yerine konup
    RSA PKCS#1 v1.5 ile imzalanır; `AUTH(2, 0, imza)`.
  - AUTH jeton yine gelirse (TV imzayı tanımadı: bu bilgisayarı ilk kez görüyor): `AUTH(3, 0, base64(açık anahtar) +
    " nino@Nino" + "\0")` (ASCII; sondaki ad TV'deki izin verilen cihazlar listesine girer). "Onay bekleniyor" olur, okuma
    süresi şimdiden itibaren **onay süresi**ne (varsayılan **90 sn**) uzatılır, "TV'de onay" olayı bildirilir.
  - Başka paket → **ulaşılamadı** "unexpected packet <8 haneli onaltılık>".
  - Okuma zaman aşımı/G/Ç/akış sonu (iptal değilse): onay bekleniyorsa **onay verilmedi**, değilse **ulaşılamadı**.
- **Açık anahtar biçimi** (Android'in kendi RSA biçimi, 524 bayt): 32 bit kelime sayısı = 64; 32 bit n0inv =
  2³² − (n mod 2³²)⁻¹ mod 2³²; n (256 bayt, küçük sonlu); rr = (2^(64·32))² mod n (256 bayt, küçük sonlu); 32 bit üs.
  Yalnız 2048 bitlik anahtar; değilse hata. Test: uzunluk 524, ilk kelime 64, 8. bayttan itibaren 256 bayt modülüs,
  n0inv × n[0] ≡ 0xFFFFFFFF (mod 2³²), 520. bayttaki üs 65537.
- **Hizmet çalıştırma** (ör. `shell:…`, `exec:…`): yerel kimlik bağlantı başına 1'den artar. `OPEN(yerel, 0, hizmet +
  "\0")` (UTF-8). Paket işleme: OKAY ve arg1 = yerel → uzak kimlik = arg0 (açıldı); WRTE ve arg1 = yerel → veri
  çıktıya eklenir, `OKAY(yerel, arg0)` dönülür; CLSE ve (arg1 = yerel ya da 0) → kapandı; diğerleri yok sayılır.
  Açılış beklenir (OKAY ya da CLSE). Kapandı ve uzak kimlik 0 ise **kurulamadı** "<hizmet> açılamadı".
  Girdi varsa: en büyük yük boyutunda parçalar okunur, her biri `WRTE(yerel, uzak, parça)`; bir sonraki parçadan önce
  OKAY (arg1 = yerel) beklenir, arada gelen paketler işlenir; kapanırsa durulur. Sonra kapanana kadar okunur;
  `CLSE(yerel, uzak)` gönderilir (G/Ç hatası yutulur). Çıktı UTF-8 metin.
Testler (sahte adbd ile): yeni bilgisayar → onay olayı çağrılır, `shell:echo` "Success\n" döner, TV'ye giden açık
anahtar metni boşlukla iki parça: base64'ü çözülünce açık anahtar biçimine eşit, ikinci parça "nino@Nino"; önceden
güvenilen anahtar → onay sorulmaz, açık anahtar gönderilmez; TV onaylamayıp kapatırsa (onay süresi 5 sn) → **onay
verilmedi**; kapalı port → **ulaşılamadı**; 10 000 rastgele bayt `exec:cmd package install -r -S 10000` ile parça parça
gönderilir, TV aynı baytları alır, yanıt "Success\n".

### 8.2 Kurucu
Tek bağlantıda yapılır (TV onayı en çok bir kez sorulur). Port **5555**.
1. Bağlan (anahtar §8.4; onay olayı bağlı).
2. `shell:dumpsys package com.ninotranslator.tv` → `versionName=(\S+)` (yoksa kurulu değil). Test:
   "Packages:\n    versionCode=1 minSdk=24\n    versionName=0.7.0\n" → 0.7.0; "Unable to find package: …" → yok.
3. Kuruluysa ve paket ondan (esnek) yeni değilse: katman izni verilir (§8.2.1); `shell:pidof com.ninotranslator.tv`
   boşsa (çalışmıyor) `shell:am start -n com.ninotranslator.tv/.MainActivity`; zaten çalışıyorsa **dokunulmaz** (her
   başlatmada öne açmak oyundaki kullanıcıyı Nino ekranına atıyordu). Sonuç (kurulu sürüm, kurulmadı).
4. Değilse: kuruluysa önce `shell:pm uninstall com.ninotranslator.tv` (eski sürüm ayarları ve kalıntılarıyla tamamen
   kalkar). APK kurulur: `exec:cmd package install -r -S <bayt sayısı>` hizmetine dosya akıtılır (Android 7+; dosya TV'ye
   ayrıca kopyalanmaz). Çıktıda `INSTALL_FAILED_UPDATE_INCOMPATIBLE` ya da `INSTALL_FAILED_VERSION_DOWNGRADE` varsa
   kaldırılıp bir kez daha. Çıktıda `Success` yoksa **kurulamadı** (çıktı kırpılmış). Katman izni; `am start …`.
   Sonuç (paket sürümü, kuruldu).
- **Play Store yolu kullanılmaz** (§9).

#### 8.2.1 Katman izni ("diğer uygulamaların üzerinde göster")
Katman kipinde altyazı TV'nin HDMI görüntüsünün üstünde duran saydam pencereye çizilir; Android TV'lerin çoğunun menüsünde bu ayar bulunmaz. `shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow`; çıktı hata gibi değilse verildi.
Değilse `shell:pm grant com.ninotranslator.tv android.permission.SYSTEM_ALERT_WINDOW`. İptal dışındaki her hata "verilmedi"
sayılır; kurulum yine başarılıdır. "Hata gibi" = (harf duyarsız) `Error`, `Exception`, `Unknown` ya da `not allowed`
içerir; boş çıktı başarıdır. Test: "" başarı; "Error: Unknown operation string: NINO_TEST" hata; "Security exception: uid 2000
does not have android.permission.MANAGE_APP_OPS_MODES" hata.
Testler: TV'de 0.7.0 ve paket 0.7.0 → (0.7.0, kurulmadı) ve `shell:appops set …` çağrılmış; kurulu değil + paket
0.9.11 → (0.9.11, kuruldu), appops çağrısı `am start`'tan önce, `pm grant` yok; appops "Error: Unknown operation
string…" dönünce `shell:pm grant com.ninotranslator.tv android.permission.SYSTEM_ALERT_WINDOW` çağrılır ve kurulum
yine başarılı.

### 8.3 Bulma
- Ulaşılabilir mi: TCP 5555, varsayılan **1 sn**.
- Tarama: bu bilgisayarın özel IPv4 adresleri (açık, geri döngü olmayan bağdaştırıcılar; burada sanal/konteyner süzgeci
  yok) için §1.5 hedefleri; aynı anda 64, her biri **700 ms**; bulunanlar son bayta göre sıralı. Test: 192.168.1.20 →
  253 hedef, kendisi yok, `.1` var.

### 8.4 ADB anahtarı
Klasördeki `adbkey` dosyası (PKCS#8 PEM, "BEGIN PRIVATE KEY"). Varsa ve 2048 bitse kullanılır; yoksa, bozuksa ya da boyu
farklıysa yeni 2048 bit anahtar üretilip yazılır (Windows dışında 0600). TV onayı bu anahtara verilir; değişirse TV
yeniden sorar. Test: aynı klasörden iki kez okununca modülüs aynı.

---

## 9. Play Store yönlendirme (tanımlı, kullanılmıyor)

Kurucuda bir "Play'den kur" yolu tanımlıdır ama **hiçbir akış onu çağırmaz**; Windows uygulaması bağlamaz, yardımcı
bağlasa da kurulum adımı yolu çalıştırmaz, `play` ilerleme olayı hiç gönderilmez. Sebep: Play'deki
`com.ninotranslator.tv` sayfası Nino'nun TV uygulaması değil; Nino TV hep yanındaki APK ile kurulur. Yeni kodda bu yol
**yazılmayabilir**; yazılırsa kapalı kalmalı. Tanımlı davranış (bilgi için):
- Play sayfası `https://play.google.com/store/apps/details?id=com.ninotranslator.tv` 8 sn içinde **200** dönüyorsa
  "listede". TV'de Play Store var = `shell:pm list packages com.android.vending` çıktısında kırpılmış satır tam
  `package:com.android.vending`. Play'den kurulmuş = dumpsys'te `installerPackageName=com.android.vending`.
- Yol: listede değilse yok. Play'den kurulmamışsa Play Store aranır, yoksa yok. `shell:am start -a
  android.intent.action.VIEW -d market://details?id=com.ninotranslator.tv`; çıktıda "Error" varsa yok. "Play açıldı"
  olayı (arayüz kullanıcıdan TV'deki Play sayfasında kurma düğmesine basmasını ister). **4 dk** boyunca 3 sn'de bir dumpsys; sürüm görünür ve öncekinden farklıysa
  katman izni + `am start`, o sürüm. Süre dolarsa yok (APK ile kurulur).

---

## 10. Hata kodları ve kullanıcı metinleri

### 10.1 Ortak hata listesi
Uygulama katmanının hata türleri: **ulaşılamadı**, **Key Server kapalı**, **parola yanlış**, **anahtar reddedildi**,
**kurulamadı**, **araç eksik**, **çok eski**, **giriş olmadı**, **sertifika verilmedi**, **onay verilmedi**, **yer yok**,
**sertifika uyuşmazlığı**, **sertifika reddedildi**, **TV saati geride**, **paket engelli**, **bağlantı kesildi**,
**Host PC uyuşmazlığı**. Her hatanın isteğe bağlı ayrıntısı günlüğe yazılır; kullanıcıya gösterilip gösterilmeyeceği
§5'teki kurallara bağlıdır.

Eşlemeler:
- Samsung kurucu → ortak: ulaşılamadı → ulaşılamadı; giriş olmadı → giriş olmadı; sertifika verilmedi → aynı; çok eski
  → aynı; yer yok, sertifika uyuşmazlığı, sertifika reddedildi, TV saati geride, paket engelli, bağlantı kesildi → aynı;
  diğer → kurulamadı. Ayrıntı korunur. Samsung kurulumunda beklenmeyen hata → kurulamadı "<tür>: <ileti>" (günlüğe de).
- Android kurucu → ortak: ulaşılamadı, onay verilmedi, diğer → kurulamadı; ayrıntı = hatanın ileti metni
  ("<Kod>: <ayrıntı>" biçiminde). Beklenmeyen hata → kurulamadı (ileti).
- Hata uygulamanın başlangıç günlüğüne de ("LG TV kurulumu", "Samsung TV kurulumu", "Android TV kurulumu") yazılır.
- LG paketi yokken kurulum istenirse → kurulamadı `tv.install.detail.noLgPackage`.

### 10.2 Ana iletiler
Mac §7 tablosundaki iletilerle (İngilizce anahtar ve Türkçesi) **aynı**dır; farklar:
- **Kurulamadı**: Windows her zaman `tvApp.error.installFailed` metnini kullanır (sebep olmasa da; Mac sebepsizde kısa
  metni gösterir). Tanınmayan hata da bu metne düşer.
- **Araç eksik** (yalnız Windows): `tvApp.error.toolMissing`.
- **Host PC uyuşmazlığı** (yalnız Windows; Mac'te denetim kartı var): `tvApp.error.hostPcMismatch`. %1 = durumdaki TV adresi (yoksa "?"), %2 = durumdaki bilgisayar adresi, yoksa güncel adres, yoksa "?".
  Bu hatada metne **başka hiçbir satır eklenmez**.

### 10.3 Metnin kuruluşu (sorun yazısı)
Durumda hata yoksa boş. Değilse:
1. Ana ileti (marka ve hataya göre; ulaşılamadı Samsung'da `tvApp.error.unreachableSamsung`, diğerlerinde
   `tv.install.detail.noTvResponse` ile başlayan ileti).
2. Samsung + ulaşılamadı + bilgisayar adresi biliniyorsa: boş satır + `tvApp.problem.hostPcIp`.
3. Sebep varsa: boş satır + (Samsung'da `tvApp.problem.detailsSamsung`, diğerlerinde `tvApp.problem.detailsTv`; sebep %@ yerine).
4. Samsung değilse burada biter.
5. Samsung + (kurulamadı ya da sertifika reddedildi): boş satır + `tvApp.problem.serverMaintenance`.
6. Samsung + (ulaşılamadı, kurulamadı ya da sertifika reddedildi): boş satır + `tvApp.problem.restartSamsung`.
7. Samsung + bağlantı kesildi: boş satır + Anynet+ ipucu `tvApp.detail.anynet`.
8. Samsung (hepsi): boş satır + `status.sendLogFile` (%@ = `%LOCALAPPDATA%\Nino\tvinstall.log`).
Metinlerdeki yer tutucular Mac biçimindedir (`%@`, `%1$@`, `%2$@`); yeni kodda kendi biçimini kullan.

### 10.4 TV adımındaki ek metinler
- "Rehberle kur" (paket yok, LG dışı): "`tvApp.title`'nı bu TV'ye rehberle kurup açın; bilgisayarı kendisi bulur."
  + **Rehberi aç** →
  sitenin kurulum rehberi: `SiteLinks.TvApp` (Türkçe `#kurulum`, Android TV `#android-tv-elle`, Arapça `ar/kurulum`, diğer diller `#english`).
  TV adımının yerleşimi `kurulum.md` §8'de.
- Seçili TV'nin adı "bağlandı" satırında gösterilir.

---

## 11. Mac'e gömülen TV yardımcısı (komut satırı sözleşmesi — BİREBİR)

Mac uygulaması Samsung ve Android TV kurulumu için bu yardımcıyı çağırır (Mac tarafı: Mac §8). Tek dosyalık, önceden
derlenmiş (.NET yerel AOT, değişmez küresel ayarlar, kısmi kırpma; XML imzası ve TizenSdb derlemeleri kırpılmaz). Çıktı
adı **`nino-tv-helper`**. Kurulum kitaplığını kullanır; Windows uygulaması aynı kitaplığı doğrudan kullanır.

### 11.1 Komutlar
- `android-scan` → ağ taraması (§8.3), sonuç `found`. Çıkış 0.
- `android-install --host IP --package APK --version V --key-dir DİZİN` → Android kurucu (§8.2); onay olayı `approve`.
  Play yolu bağlıdır ama kurucu onu çağırmaz (§9). Sonuç `done`. Çıkış 0.
- `samsung-install --host IP --package WGT --version V --profiles DİZİN [--log DOSYA]` → Samsung kurucu (§7.2). HTTP
  zaman aşımı 1 dk; ilerleme `progress`; giriş: dinleyici yardımcıda açılır, adres `login` olayıyla Mac'e verilir
  (tarayıcıyı Mac açar), günlüğe adresin Mac uygulamasına gönderildiği; giriş süresi 10 dk.
  TV'deki sürüm yeniyse kurmaz. Sonuç `done`. Çıkış 0.
- `self-test` → yayın derlemesinde imzanın AOT ile çalıştığını sınar: geçici klasörde 2048 bit anahtar ve kendinden
  imzalı sertifika (konu "CN=Nino self-test", dün–yarın geçerli), 3DES/SHA-1/2048 PKCS#12 (parola "x"); `author.p12`,
  `distributor.p12`, `password.txt`="x" olarak kopyalanır ve sertifika klasörü 23 saat önceki ana göre geçerli
  okunmalı (değilse hata "kayıtlı sertifika okunamadı"); içinde `config.xml` (`<widget/>`) olan bir `.wgt` yeniden
  imzalanır, `author-signature.xml` ve `signature1.xml` oluşmalı (değilse "imza dosyaları oluşmadı"); klasör silinir.
  Başarıda `{"event":"done","version":"self-test","installed":false}`, çıkış 0.
- Başka/eksik komut: hata çıktısına tek satırlık kullanım yardımı yazılır: program adı ve komutlar ` | ` ile ayrılarak, her biri seçenekleriyle (`android-scan`; `android-install --host IP --package APK --version V --key-dir DİZİN`; `samsung-install --host IP --package WGT --version V --profiles DİZİN [--log DOSYA]`; `self-test`), **çıkış 2**, olay yok.
- Seçenek değeri: seçenek adından sonraki argüman. Gerekli seçenek eksikse beklenmeyen hata yolu (aşağıda): `error`
  `InstallFailed`, ileti "ArgumentException: --host eksik" gibi, çıkış 1.
- `--log DOSYA` her komutta okunur; verilmezse günlük yazılmaz.

### 11.2 Çıktı
Standart çıktıya her satır bir JSON nesnesi; satır anında boşaltılır; satırlar karışmasın diye kilitli. Olaylar
**gerçek standart çıktıya** yazılır (Samsung kurulumunda konsol çıktısı yakalandığı için konsolun "geçerli yazıcısı"
kullanılmamalı). Alan sırası: önce `event`, sonra verildiği sırayla.
- `{"event":"progress","step":"<reading|signin|certificate|signing|installing|uninstalling>"}` (tanımlı ama hiç
  gönderilmeyen `play`)
- `{"event":"login","url":"https://…"}`
- `{"event":"approve"}`
- `{"event":"done","version":"0.7.0","installed":true}` (`installed` gerçekten kurulup kurulmadığı)
- `{"event":"found","hosts":["192.168.1.40"]}`
- `{"event":"error","code":"<Kod>","message":"…"}`, çıkış **1**:
  - Android hatası: kod `Unreachable` | `NotApproved` | `InstallFailed`; ileti = hatanın tam ileti metni (ayrıntı
    varsa "Kod: ayrıntı", yoksa kod).
  - Samsung hatası: kod `Unreachable` | `LoginFailed` | `CertificateFailed` | `TooOld` | `InstallFailed` |
    `NotEnoughSpace` | `CertificateMismatch` | `CertificateRejected` | `TvClockWrong` | `PackageBlocked` |
    `ConnectionLost`; ileti = **yalnız ayrıntı** (yoksa kod).
  - Beklenmeyen hata (iptal dışı): günlüğe "Yardımcıda beklenmeyen hata: <tam hata>", kod `InstallFailed`, ileti
    "<tür adı>: <ileti>".
- İptal: olay yazılmaz (süreç hata koduyla biter).

### 11.3 İptal
- Ctrl+C (konsol kesme) iptal eder (süreç hemen ölmez, iş iptal edilir).
- Standart giriş **her zaman** sonuna kadar okunup atılır (ayrı görevde); giriş kapanınca yalnız `--exit-with-input`
  verilmişse iptal edilir (Mac uygulaması kapanınca yardımcı da kapansın). Mac her çağrıya bu bayrağı ekler.

---

## 12. Salon sahnesindeki TV (ana ekran, yalnız TV kısmı)

Ana ekranın "salon" görünümünde TV ekranının içi (canlı altyazı önizlemesi) 588 noktalık mantıksal bir ekran için çizilir ve görseldeki ekrana ölçeklenir (oran = ekran genişliği / 588). Görseller 1672×941 piksel. Ölçüler (sol, üst,
genişlik, yükseklik; piksel):
- PS5'li salon (`living-room.png`): ekran (149, 40, 1151, 595), TV çerçevesi (139, 27, 1171, 621).
- Xbox'lı salon (`living-room-xbox.png`): ekran (136, 40, 1185, 596), TV çerçevesi (121, 26, 1214, 630).
Sehpa, priz, fiş ve kablo hesabı ana ekran tarifinde.

---

## 13. Platforma bağlı kısımlar (Windows)

- **ssh-keygen** yedeği: Windows'un isteğe bağlı "OpenSSH İstemcisi" özelliği, `<Sistem klasörü>\OpenSSH\ssh-keygen.exe`.
  Süreç pencere açmadan (gizli konsol), standart çıktı/hata yönlendirilerek başlatılır; başlatılamazsa **araç eksik**.
  Ana yol (uygulama içinde PEM çözme) bu araca gerek bırakmaz.
- Geçici dosyalar (LG anahtarı her SSH komutunda, ssh-keygen dosyası, Samsung `nino-*.wgt`): `%TEMP%`. Windows'ta LG
  anahtarının geçici dosyası düz yazılır (0600 kavramı yok); her durumda komut bitince silinir.
- Açık dosya silinemediği için geçici paket silme 3 deneme + bellek temizliğiyle (§7.2 adım 10).
- Kalıcı veri `%LOCALAPPDATA%\Nino\` (`samsung\`, `adb\`, `tvinstall.log`); TV kaydı ve anahtarlar DPAPI'li
  `secure.dat`'ta.
- Tarayıcıda açma (Samsung hesabıyla giriş, rehberler) varsayılan tarayıcıyla (kabuk yürütmesi). Panoya yazma; pano başka
  uygulamada kilitliyse sessiz geçilir.
- Ağ değişimi bildirimi (Windows'un "ağ adresi değişti" olayı): kart yeniden çizilir, Host PC IP yeniden hesaplanır.
- `firewall.settings.title`: TV adımındaki iki ipucu (§3) ve çeviri sürerken 60 sn TV bağlanmazsa kural denetimi
  (güvenlik duvarı tarifi).
- sdb, imzalama ve Tizen kurucu: TizenSdb.Core 1.1.9 (`SdbTcpDevice`: bağlan, yetenekler, kabuk komutu, dosya gönder;
  Tizen kurucu: paketi gönderip kurar; `.wgt` yeniden imzalayıcı). SSH: SSH.NET 2026.0.0. Kitaplık API'leri eski ad
  değildir; yeni kod da çağırır.

## 14. Mac ile farklar (Windows esas)

Windows'ta **olmayanlar** (Mac'te var): LG'de SSDP sessizken /24 yedek taraması ve `:3000` "Hello world" denetimi;
Samsung'da model yılına göre ilk pencere adımı, pencere açılmazsa yardım bölümü ve beş rakamı TV'ye gönderen düğme;
Host PC IP'nin başında sıfır / ters yazılmış / 127.0.0.1 ayrımları ve uyarıya rağmen deneme düğmesi; "TV yeniden başlatılmamış"
(26101 kapalı ama mod açık) ayrı adımı ve üç satırlı denetim kartı; Samsung "koptu" hâlinde kurulumu kendiliğinden yeniden
deneme; Android'de "TV uygulaması zaten bağlıysa dokunma" ön kontrolü; Mac App Store ek satırı. Windows'ta **fazla**
olanlar: ssh-keygen yedeği ve **araç eksik** hatası (Mac yalnız ssh-keygen kullanır, uygulama içi PEM çözme Windows'ta
ana yoldur), tek cümlelik **Host PC uyuşmazlığı** iletisi, Samsung eşleşmesinde "60 saniye" bekleme yazısı ve ayrıntılı
eşleşme hata metinleri (§3.5), güvenlik duvarı ipuçları. LG SSH Windows'ta uygulama içi kitaplıkla (Mac dış `ssh`
aracıyla) yapılır.
