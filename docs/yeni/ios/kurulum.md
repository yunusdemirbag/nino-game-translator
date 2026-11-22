# Eski uygulamadan çıkarılmış tarif

**Kapsam:** iPhone/iPad uygulamasının ilk açılışı ve kurulum akışı (karşılama, konsol seçimi, PSN girişi, PS5 eşleme,
altyazının yeri, kullanım turu, yüzen `ask.title` düğmesi).

Bu belge eski iOS kodu okunarak yazıldı; kod kopyalanmadı. Yeni yazacak kişi eski kodu görmeden aynı ekranları ve aynı
davranışı bu tariften kurabilmeli. Ölçüler pt (nokta), renkler sRGB onaltılık. Ekrandaki metinler yalnız
yeni uygulamanın metin anahtarıyla anılır (`apps/ios/Nino/Resources/Localizable.xcstrings`); metnin kendisi oradadır.
Yeni katalogda karşılığı olmayan metinler yalnız anlamıyla, kısaca anlatılır.

> **Önemli:** `docs/screenshots/telefon/01–06` görüntüleri **eski bir tasarımdan** (koyu zemin, amber vurgu, farklı metinler).
> Doğru olan bu belgedeki tariftir (açık zemin, lacivert hap düğme). Farklar §12'de.

---

## 1. Ortak tasarım dili (kurulum ekranlarının kullandığı parçalar)

### 1.1 Ölçüler

| Ad | Değer |
|---|---|
| Ekran kenar boşluğu (screen) | 20 |
| Öğe arası (gap) | 12 |
| Karo iç boşluğu (tile) | 16 |
| Satır içi (inline) | 8 |
| İnce (hair) | 4 |
| Köşe: karo 22, kontrol 16, iç 8, etiket 6, hap = tam yuvarlak | |
| Birincil/ikincil düğme yüksekliği | en az **58** (tam genişlik) |
| Hayalet (yalnız yazı) düğme yüksekliği | en az 44, yatay iç boşluk 12, genişlik içerik kadar |
| Simge düğmesi | 44×44 |
| Giriş alanı / liste satırı | 52 |
| Etiket (pill) yüksekliği | 24 |

### 1.2 Renkler (açık tema; uygulama her zaman açık tema zorlar)

| Ad | Renk |
|---|---|
| Zemin degradesi | sol üst `#F7FAFF` → sağ alt `#E3ECFA`; üstüne iki yumuşak ışık: (x 0.1, y 0.08) merkezli vurgu mavisi %22 → saydam, yarıçap ekran genişliği×0.9; (x 0.95, y 0.95) merkezli `#00205B` %16 → saydam, yarıçap max(genişlik, yükseklik×0.5). Güvenli alanı da kaplar. |
| Yüzey (cam karo) | beyaz %85 |
| Yüzey‑2 | `#E6EDF8` |
| Kenar (cam) | beyaz %75 |
| Güçlü kenar | `#D3DEEF` |
| Yazı / mürekkep | `#0A1430` |
| İkincil yazı | `#55607A` |
| Üçüncül | `#8A93A8` |
| Vurgu (accent) | `#0070D1` |
| Hayalet düğme yazısı | `#0058A8` |
| Koyu lacivert (gölgeler) | `#00205B` |
| Başarı | `#1E6B45` |
| Uyarı (hata satırı) | `#9A4A08` |
| Tehlike | `#B3261E` |
| Canlı yeşil nokta (PS5 bulundu) | `#30C578` |
| Sahne üst / alt | `#151E36` / `#06080F` |
| `ob.free` etiketi yeşili | `#6EE7A8` |

Uygulamanın genel `tint` rengi vurgu mavisidir.

### 1.3 Yazı boyları

| Ad | Boy |
|---|---|
| Büyük başlık (ekran başlığı) | 32, kalın, harf aralığı −0.5, renk `#0A1430` |
| Başlık açıklaması | 16, normal, `#55607A` |
| Adım satırı (`setup.step`) | 13, yarı kalın, vurgu mavisi |
| display | 28 yarı kalın |
| title | 22 yarı kalın, rakamlar eş genişlikte |
| headline | 17 yarı kalın |
| body | 15 normal |
| caption | 13 orta |

### 1.4 Bileşenler (rolüne göre)

- **Ekran iskeleti** (her kurulum ekranı): dikey üç bölge.
  1. *Üst satır*: yatay 20 boşluk; üstten güvenli alan + 8 (iPad'de +20).
  2. *İçerik*: dikey kaydırılabilir (kaydırma çubuğu gizli); öğeler arası 12; yatay 20, üst 12, alt 20 boşluk.
  3. *Alt düğme bölgesi*: kaydırmaz, her zaman görünür; öğeler arası 12; yatay 20; alttan güvenli alan + 20 (iPad'de +40).
  Zemin §1.2 degradesi; navigasyon çubuğu gizli; varsayılan yazı rengi `#0A1430`.
- **Büyük başlık bloğu**: dikey, aralık 6 (adım satırı varsa en üstte) → büyük başlık → açıklama. Sola yaslı, tam genişlik,
  satırlar kırılır (kesilmez). Bir de "başlık bloğu" çeşidi var (konsol seçimi, alt sayfalar): aynı görünüm, aralık 4,
  açıklamanın üstünde +2.
- **Koyu sahne kartı**: köşe 28 (sürekli eğri), dolgu `#151E36` → `#06080F` yukarıdan aşağı; 1 pt kenar beyaz %22 → %3
  yukarıdan aşağı; gölge `#0A1430` %35, yarıçap 18, y +10. Tam genişlik; isteğe bağlı sabit yükseklik.
- **Camsı satır** (sahne içinde): yatay, aralık 12. Solda 40×40 daire (beyaz %10 dolgu) içinde 18 pt yarı kalın beyaz SF
  Symbol; ortada başlık (16 yarı kalın beyaz, tek satır, %70'e kadar küçülür) ve altında açıklama (13, beyaz %60, en çok
  2 satır), aralık 2; sağda en az 4 boşluk ve isteğe bağlı sağ öğe. İç boşluk yatay 14, dikey 12. Zemin beyaz %7, köşe 18,
  1 pt kenar beyaz %12.
- **`ob.free` etiketi**: 12 kalın, yazı `#6EE7A8`, zemin aynı renk %14, kenar aynı renk %35 (1 pt), hap; iç boşluk 10×5.
- **Karo**: beyaz %85 zemin, köşe 22, iç boşluk 16, içerik dikey (aralık 8) sola yaslı tam genişlik. Kenar beyaz %75
  1 pt; *seçili* ise vurgu mavisi 1.5 pt. Gölge `#00205B` %10, yarıçap 14, y +6.
- **Bilgi karosu**: karo içinde üstte simge (15 pt yarı kalın, 18×18 çerçeve, ikincil renk) + headline başlık yan yana
  (aralık 8), altında caption açıklama (ikincil renk). Seçili vurgusu olabilir.
- **İki sütunlu ızgara (bento)**: iki eşit sütun, aralık 12; bir satırdaki karolar aynı yükseklikte (en uzun olan).
- **Hata/uyarı notu**: ünlem üçgeni simgesi (`exclamationmark.triangle.fill`) + metin, caption, renk `#9A4A08`
  (bazı yerlerde ikincil renk tonu verilir), satırlar kırılır.
- **Durum etiketi (noktalı)**: 8×8 yeşil (`#1E6B45`) nokta + caption metin, aralık 8, zeminsiz, yazı `#0A1430`.
- **Etiket (noktasız)**: caption, 24 yükseklik, yatay 8, köşe 6, zemin Yüzey‑2, yazı ikincil.
- **Simge düğmesi**: 44×44, 17 pt yarı kalın simge, zemin beyaz %85, köşe 16, kenar beyaz %75, gölge `#00205B` %8
  yarıçap 8 y +3. Erişilebilirlik etiketi verilir (`common.back`).
- **Düğmeler** (hepsi tam hap, yazı headline 17 yarı kalın, simge+yazı birlikte):
  - *Birincil*: tam genişlik, en az 58 yüksek, yatay 20; dolgu `#1B2747` → `#0A1430` yukarıdan aşağı; 1 pt kenar beyaz
    %14; gölge `#0A1430` %28, yarıçap 14, y +8; yazı beyaz. Basılıyken dolgu %85 opak.
  - *İkincil*: tam genişlik, beyaz %90 dolgu, kenar `#D3DEEF`, yazı `#0A1430`.
  - *Hayalet*: zeminsiz, yazı `#0058A8`, içerik genişliğinde.
  - Ortak: basılıyken %97 ölçek (0.12 sn easeOut); devre dışıyken %40 opaklık.
- **Sayfa noktaları**: yatay, aralık 8; her nokta 8 yüksek hap; seçili olan 22 geniş ve `#0A1430`, diğerleri 8 geniş ve
  `#0A1430` %18. Değişim 0.2 sn easeOut. Erişilebilirlikten gizli.
- **Segmentli seçici**: Yüzey‑2 zemin, köşe 16, iç boşluk 4, seçenekler eşit genişlik, aralık 4, her biri en az 36 yüksek;
  seçili olan beyaz zemin (köşe 8, gölge `#00205B` %10 yarıçap 4 y +2), body yarı kalın, yazı koyu; diğerleri orta kalın,
  ikincil. Seçim değişince hafif dokunsal "seçim" titreşimi.
- **Giriş alanı**: 52 yüksek, yatay 16, headline boyu normal kalınlık, beyaz %90 zemin, köşe 16, kenar `#D3DEEF`.
- **Satır ayracı**: 1 pt, `#D3DEEF` %70.
- **Alttan açılan küçük sayfa ("içeriğe oturan sayfa")**: yüksekliği içeriğin ölçülen yüksekliği kadardır (sabit orta/büyük
  değil); içerik değişince sayfa da uyar; üstte tutamaç görünür; sayfa zemini beyaz %85; içerik 20 boşlukla, dikey aralık 12,
  sola yaslı.
- **Logo**: uygulamanın logo görseli; verilen kutuya (ör. 36×36) sığar, görsel kutunun 1.21 katı çizilir (PNG'nin saydam
  kenar payı yüzünden), erişilebilirlikten gizli.

### 1.5 iPhone / iPad farkı

Eski kod `horizontalSizeClass` **kullanmıyor**; ayrım cihaz türüne göre (iPad mi, değil mi) yapılıyor:

| | iPhone | iPad |
|---|---|---|
| İçerik genişliği | tam genişlik (20 kenar boşluğuyla) | en çok **680** genişlikte ortalanmış sütun (üst satır, içerik ve alt bölge ayrı ayrı) |
| Üst satırın üst boşluğu | güvenli alan + 8 | güvenli alan + 20 |
| Alt bölgenin alt boşluğu | güvenli alan + 20 | güvenli alan + 40 |
| Kullanım turu kartı | tam genişlik − 40 | en çok 680, ortada |

Yeni yazımda aynı sonucu `horizontalSizeClass == .regular` ile almak serbest; ama iPad'de bölünmüş ekranda dar pencere
eski uygulamada da 680 sütun kuralını uygular (cihaza bakıyor).

---

## 2. Kök görünüm: hangi koşulda hangi ekran

### 2.1 Kalıcı değerler

| Yer | Anahtar | Anlamı |
|---|---|---|
| UserDefaults | `welcomeSeen` (Bool) | Karşılama görüldü |
| UserDefaults | `setupSkipped` (Bool) | Kurulum atlandı (`common.skipfornow`) |
| UserDefaults | konsol türü anahtarı (Xbox modülünün `platform` anahtarı; değer `playstation`/`xbox`) | Seçilen konsol |
| UserDefaults | `coachTourDone` (Bool) | Kullanım turu bitti |
| Anahtarlık | hesap kimliği (8 bayt), kayıtlı PS5, TV, TV anahtarı, `setupComplete` (Bool) | |

### 2.2 Kurulum adımı (`step`)

Sıralı beş durum: **welcome → psnLogin → console → output → done**.

Açılışta başlangıç adımı:
1. `setupComplete == true` **ve** (`setupSkipped` **veya** hem hesap kimliği hem kayıtlı PS5 var) → **done**.
2. Ya da Xbox seçili, Microsoft jetonu ve seçili Xbox kayıtlı ve `setupComplete == true` → **done**.
3. Değilse `setupSkipped` ise → **output** (altyazının yeri).
4. Değilse → **welcome**.

`step` **done** olduğu an `setupComplete = true` Anahtarlığa yazılır.

`platformChosen` (konsol türü seçildi mi) açılışta: kayıtlı konsol türü varsa **veya** hesap kimliği varsa **veya** kayıtlı
PS5 varsa true (eski PS5 kurulumları PlayStation sayılır, yeniden sorulmaz). Konsol türü yoksa PlayStation varsayılır.

### 2.3 Ekran seçimi

Öncelik sırası:
1. `welcomeSeen == false` → **Karşılama** (§3).
2. Değilse `step != done` → **Kurulum** (aşağıdaki tablo).
3. Değilse → **Ana ekran** (navigasyon yığını, §2.5).

Kurulum içinde:

| step | Koşul | Ekran | Geri | Atlama (`common.skipfornow`) | Bitince |
|---|---|---|---|---|---|
| welcome / psnLogin | `platformChosen == false` | Konsol seçimi (§4) | `welcomeSeen = false` (karşılamaya döner) | yok | (Konsol seçimi kendisi `platformChosen = true` yapar; ekran kendiliğinden değişir) |
| welcome / psnLogin | Xbox | Microsoft girişi (§4.2) | `platformChosen = false` | `skipSetup` | step welcome ise bir ilerlet, sonra bir daha ilerlet |
| welcome / psnLogin | PlayStation | PSN girişi (§5) | `platformChosen = false` | `skipSetup` | aynı: welcome ise ilerlet, sonra ilerlet (→ console) |
| console | Xbox | Xbox seçimi (§4.2) | `back()` | `skipSetup` | `advance()`; Microsoft girişi düğmesi → `back()` |
| console | PlayStation | PS5 eşleme (§6) | `back()` | `skipSetup` | `advance()` |
| output (ve done) | — | Altyazının yeri (§7), kurulum kipinde | `back()` | yok | `advance()` → done → ana ekran |

Not: Karşılamadan çıkış `welcomeSeen = true` yapar ve step **welcome** ise onu bir ilerletir (psnLogin). Bu `ob.skip` ile
de, son sayfadaki `ob.start` ile de aynıdır; `skipSetup` **değildir**.

### 2.4 Kök görünüme uygulanan ortak ayarlar

- Renk şeması her zaman **açık**.
- Genel vurgu rengi `#0070D1`.
- **Arayüz dili çeviri dilini izler, anında**: ortam dili (`locale`) çeviri dilinin arayüz diline, yazı yönü de o dile göre
  (Arapça, Urduca → sağdan sola; diğerleri soldan sağa) ayarlanır.
- Açılışta ve çeviri dili her değiştiğinde `AppleLanguages` = [arayüz dili] yazılır; böylece sistem yerelleştirmesini kullanan
  metinler de **bir sonraki açılışta** aynı dilde olur.
- İlk açılışta (kayıtlı ayar yoksa) çeviri dili, telefonun ilk tercih dili listedeki 11 dilden biriyse o, değilse Türkçe
  (`fil` → `tl`). Diller ve sırası: tr Türkçe, ar العربية, hi हिन्दी, id Bahasa Indonesia, th ไทย, vi Tiếng Việt, ur اردو,
  bn বাংলা, ms Bahasa Melayu, tl Filipino, nl Nederlands.

**İki metin sistemi var; ayrı tutulmalı:**
- *Home tablosu* anahtarları (`ob.*`, `psn.*`, `pair.*`, `target.*`, `setup.step`, `demo.try`, `common.done`): seçili arayüz
  dilinin `.lproj` paketinden, o dilde yoksa ana paketten okunur; **çeviri dili değişince anında** değişir.
- *Sistem yerelleştirmesi* (İngilizce cümle anahtarlı katalog): ancak bir sonraki açılışta değişir.
- Hiç çevrilmeyen, olduğu gibi gösterilenler: Beta etiketi, marka adları (PlayStation Network, PS5, LG, Samsung,
  Android TV) ve bunların "·" ile dizildiği satır.

### 2.5 Ana ekran navigasyonu (Route listesi)

Ana ekran bir navigasyon yığınıdır; köke Ana ekran konur, şu sayfalar itilir:

| Route | Açılan |
|---|---|
| settings | Ayarlar |
| profile | Profil (Cihazlarım) |
| packs | Paketler |
| target | Altyazının yeri (§7) **kurulum dışı kipte**; bitince bir geri |
| platform | Konsol seçimi; geri = bir geri; bitince bir geri, ardından Xbox seçildiyse ve (Microsoft girişi yok veya Xbox seçilmemiş) ise `ps5` itilir |
| ps5 (Xbox, giriş yok) | Microsoft girişi; bitince bir geri + `ps5` it |
| ps5 (Xbox, giriş var) | Xbox seçimi; Microsoft girişi düğmesi = Xbox çıkışı; bitince bir geri |
| ps5 (PlayStation, hesap kimliği yok) | PSN girişi (atlama düğmesi yok); bitince bir geri + `ps5` it (kurulum atlandıysa önce giriş, sonra eşleme) |
| ps5 (PlayStation) | PS5 eşleme (atlama düğmesi yok); bitince bir geri |
| psn | PSN girişi; bitince bir geri |
| about | Hakkında |
| history | Geçmiş |
| tvInstall | TV uygulaması kurulumu; bitince yığın boşaltılır |
| tvUpdate | TV uygulaması güncellemesi (güncellemeyi kendiliğinden başlatır); bitince yığın boşaltılır |

Kullanım turu (§8) ana ekran yığınının üstüne katman olarak çizilir.

### 2.6 Yüzen `ask.title` düğmesi

- Yer: sağ alt köşe (sağdan sola dilde sol alt); sağ/son kenardan 20.
- Alt boşluk: **ana ekranda 12**; karşılamada ve kurulumda **152** (= 52 + 44 + 20 + 3×12): alttaki büyük düğmenin ve onun
  üstündeki ikinci satırın (`psn.why` / `demo.try`) üstünde durur.
- Görünürlük: karşılamada ve kurulumda her zaman; ana ekranda yalnız yığın boşken (alt sayfa açık değilken) **ve** kullanım
  turu bitmişken.
- Giriş/çıkış geçişi: ölçek + saydamlık.
- Görünüm: 62×62 daire, beyaz %95 dolgu, beyaz %75 kenar, gölge `#00205B` %22 yarıçap 14 y +6. İçinde 46 pt robot yüzü
  görseli; yüz 1.6 sn'de bir yukarı-aşağı süzülür (boyun ±%5'i, easeInOut, ileri-geri, sonsuz), 4–5 sn'de bir rastgele
  ~150 ms göz kırpar. "Hareketi azalt" açıksa ikisi de yok. Basılıyken %92 ölçek (yay animasyonu, tepki 0.25, sönüm 0.7).
- Erişilebilirlik etiketi: `ask.title`.
- Dokununca sohbet sayfası alttan açılır (bu belgenin kapsamı dışında).
- Çeviri başladığında robotun soluna 7 sn'lik siyah %70 hap balon çıkar (15 kalın beyaz, iç boşluk 16×11); metni
  çevirinin başladığını haber veren ve iyi oyunlar dileyen kısa bir cümledir (yeni katalogda anahtarı yok). Bu kurulumda
  görülmez.

### 2.7 Uygulama ömrü (kurulumla ilgili)

- Öne gelince ekran-açık-tut tercihi yeniden uygulanır ve modele "etkinleşti (arka plandan mı döndü)" bildirilir.
- Arka plana gidince modele bildirilir (bu sırada kopan bağlantılar hata sayılmaz).
- PS5 ile bağlantı kopunca giden yerel bildirim: başlık `notify.ps5.lost`; gövde `notify.stopped`; sesli; uygulama öndeyken
  gönderilmez; hep aynı kimlikle gönderilir (birikmez).

---

## 3. Karşılama (3 sayfa)

### 3.1 Düzen (yukarıdan aşağı)

**Üst satır** (44 yükseklik, her dilde soldan sağa dizilir):
- Solda logo 36×36.
- Boşluk.
- Dil seçici (§3.4).
- Atlama hayalet düğmesi — `ob.skip`. Karşılamayı bitirir (§2.3 notu).
- Öğeler arası 10.

**İçerik**: yatay kaydırmalı 3 sayfa (sayfa göstergesi gizli; parmakla kaydırılabilir), en az 610 yükseklik. Her sayfa:
dikey, aralık 22, üstten 4 boşluk:
1. Koyu sahne kartı, **380** yükseklik, içinde sayfanın sahnesi.
2. Büyük başlık bloğu (adım satırı yok): başlık + açıklama.
3. Esnek boşluk.

**Alt bölge**:
1. Sayfa noktaları (3 nokta, seçili olan geçerli sayfa).
2. Birincil düğme: sayfa 0 ve 1'de `ob.continue` (bir sonraki sayfaya animasyonlu geçer); sayfa 2'de
   `ob.start` (karşılamayı bitirir).

### 3.2 Sayfa metinleri

| Sayfa | Başlık | Açıklama |
|---|---|---|
| 1 | `ob.p1.title` | `ob.p1.body` |
| 2 | `ob.p2.title` | `ob.p2.body` |
| 3 | `ob.p3.title` | `ob.p3.body` |

### 3.3 Sahneler

**Sayfa 1 — canlı altyazı örneği** (her dilde soldan sağa yerleşir, altyazı metni kendi yönünde):
- Sol üstte (16 içeride) örnek rozeti: `ob.sample`; 12 kalın, harf aralığı 1.2, beyaz %85; iç boşluk 12×7;
  zemin beyaz %10 hap; kenar beyaz %18 1 pt.
- Ortada dikey (aralık 14, yatay 20 boşluk, üst/alt esnek): İngilizce kaynak (15, beyaz %50, ortalı) → aşağı ok simgesi
  (14 yarı kalın, beyaz %35) → çeviri (26 kalın beyaz, ortalı, iç boşluk 18×12, siyah %55 zemin, köşe 16).
- **2.8 sn'de bir** sıradaki örneğe geçer (sıra saatten hesaplanır: geçen süre / 2.8, örnek sayısına göre mod); geçiş
  0.35 sn easeInOut saydamlık.
- Örnekler (İngilizce → Türkçe / Arapça); Türkçe ve Arapça dışındaki dillerde çekirdekteki o dilin üç örnek satırı
  kullanılır:
  1. Are you listening to me? → Beni dinliyor musun? / هل تستمع إليّ؟
  2. The bridge is out. Find another way. → Köprü yıkılmış. Başka bir yol bul. / الجسر مهدوم. ابحث عن طريق آخر.
  3. Stay close and watch your step. → Yakınımda kal, adımına dikkat et. / ابقَ قريبًا مني وانتبه لخطواتك.
  4. Wait for my signal at the old station. → Eski istasyonda işaretimi bekle. / انتظر إشارتي عند المحطة القديمة.
  5. No one moves until I say so. → Ben söyleyene kadar kimse kımıldamıyor. / لا أحد يتحرك حتى أقول ذلك.
  6. Relax, I know exactly what I'm doing. → Rahat ol, ne yaptığımı çok iyi biliyorum. / اهدأ، أعرف تمامًا ما أفعله.
- Seçili çeviri dili değişirse örnekler anında o dile geçer.

**Sayfa 2 — hazır paketler**: 18 iç boşluk, dikey aralık 10, üç camsı satır; simge `gamecontroller.fill`, sağda
`ob.free` etiketi. Açıklama `ob.p2.lines` (yer tutucuya binlik satır sayısı girer):
- Grand Theft Auto V — 190
- Red Dead Redemption 2 — 195
- Mafia — 18

**Sayfa 3 — ekranlar**: 18 iç boşluk, dikey aralık 12.
- Üstte yan yana iki eşit kutu (aralık 12). Her kutu: en az 170 yüksek, iç boşluk 16, zemin beyaz %7, köşe 20, kenar
  beyaz %12; içinde dikey (aralık 10, sola yaslı): 48×48 daire (beyaz %10) içinde 22 pt yarı kalın beyaz simge → esnek
  boşluk → başlık 22 kalın beyaz (tek satır, %70'e kadar küçülür) → açıklama 13 beyaz %60 (2 satır).
  - Sol: simge `tv`, `ob.p3.tv`, `ob.p3.tv.detail`.
  - Sağ: simge `iphone`, `ob.p3.phone`, `ob.p3.phone.detail`.
- Altta camsı satır: simge `wifi`, `ob.p3.wifi`, `ob.p3.wifi.detail`.

### 3.4 Dil seçici (üst satırda)

- Hap: seçili dilin bayrak emojisi (20 pt) + aşağı ok (12 yarı kalın, %70 opak), aralık 6; yatay iç boşluk 14; en az 40
  yüksek; zemin vurgu mavisi %10; kenar vurgu mavisi %80, 1.5 pt.
- Dokununca açılır menü: her dil "bayrak  yerel ad" satırı, seçili olan işaretli, Türkçe en üstte (§2.4 sırası).
- Seçim 0.2 sn easeOut ile değişir; arayüz dili ve yön anında değişir (Arapça seçilirse ekran sağdan sola döner, ama
  üst satır ve 1. sahne soldan sağa kalır).
- Erişilebilirlik etiketi: seçili dilin yerel adı.

### 3.5 Durumlar

Yükleniyor/hata durumu yok. Yüzen robot düğmesi görünür (§2.6).

---

## 4. Konsol seçimi (PlatformScreen) ve Xbox kısaca

### 4.1 Konsol seçimi

**Üst satır**: geri verilmişse solda geri simge düğmesi (`chevron.left`, `common.back`); ilerleme çubuğu **yok**.

**İçerik** (yukarıdan aşağı):
1. Başlık bloğu: `console.title`; açıklama `console.choose.body`.
2. Seçenek karosu — PlayStation: başlık "PlayStation 5" (marka adı, çevrilmez); alt metin `console.ps5.detail`.
3. Seçenek karosu — Xbox: başlık "Xbox" + yanında Beta etiketi; alt metin `console.xbox.detail`.
4. Yalnız Xbox seçiliyken not (ikincil renk tonunda): `xbox.beta.note`.

Seçenek karosu: tüm karo dokunulabilir; seçili olan karo mavi çerçeveli. İçinde yatay (aralık 12): `gamecontroller.fill`
simgesi (seçiliyse vurgu mavisi, değilse ikincil) → dikey (aralık 4): başlık satırı (headline + gerekiyorsa etiket, aralık
8) ve caption alt metin (ikincil) → esnek boşluk.

**Alt bölge**: birincil `common.next`: seçimi kaydeder (konsol türü UserDefaults'a, `platformChosen = true`) ve
"bitti" geri çağrısını çalıştırır.

Ekran açılınca seçim, modeldeki mevcut konsol türüyle başlar (varsayılan PlayStation).

### 4.2 Xbox ekranları (özet)

- **Microsoft girişi**: ilerleme başlığı adım 1, atlama düğmesi (`common.skipfornow`) var. Başlık `xbox.signin.button`,
  adım satırı `setup.step` (1), açıklama `xbox.signin.body`, ayrıca `xbox.signin.hint`. Beta etiketi. Cihaz kodu akışı:
  düğmeye basınca Microsoft'tan kod alınır, kod panoya kopyalanır ve doğrulama adresi (microsoft.com/link) tarayıcıda
  açılır; ekranda `xbox.code.label` altında büyük (display, vurgu mavisi) kod — dokununca kopyalar (`xbox.code.copied`,
  yeşil; erişilebilirlik ipucu `xbox.code.copy`) — ve altı çizili adres; üç adımlık açıklama `xbox.code.steps`;
  `xbox.signin.waiting` ile dönen gösterge. Arka planda yoklama başarılı olunca "bitti". Alt: kod varken hayalet
  `xbox.code.open`; birincil `xbox.signin.button` (çalışırken devre dışı). Hata: `xbox.signin.failed` (neden metinleri:
  `xbox.error.code`, `xbox.error.noprofile`, `xbox.error.offline`, `xbox.error.unexpected`). Ekrandan çıkınca bekleyen
  yoklama iptal.
- **Xbox seçimi**: ilerleme adım 2, atlama düğmesi var. Başlık `xbox.choose.title`, adım `setup.step` (2), açıklama
  `xbox.choose.body`. Hesaptaki Xbox'lar bulut hizmetinden listelenir (`xbox.choose.searching`; hiç yoksa
  `xbox.choose.none`), her biri seçilebilir karo (uzak oynatma açıksa yeşil tik ve `xbox.choose.ready`; kapalıysa kırmızı
  uyarı `xbox.choose.off` ve seçilemez). İlk uygun olan önceden seçilir. Alt: hayalet `common.searchagain`, birincil
  `xbox.choose.use` (seçim yoksa devre dışı) — giriş süresi dolduysa yerine `xbox.signin.button`.

---

## 5. PSN girişi (kurulum adım 1/3)

### 5.1 Düzen

**Üst satır — kurulum başlığı** (44 yükseklik, yatay aralık 12):
- Geri verilmişse geri simge düğmesi.
- 3 parçalı ilerleme çubuğu: eşit genişlikte 3 hap, her biri 4 yüksek, aralık 4; adım numarasına kadar olanlar vurgu
  mavisi, sonrakiler `#D3DEEF`. Burada 1. dolu.
- Atlama verilmişse sağda hayalet düğme `common.skipfornow` (içerik genişliğinde, sıkışmaz).
  Yalnız kurulumda görünür; ana ekrandan açılınca yok.

**İçerik**:
1. Büyük başlık bloğu: adım `setup.step` (1); başlık `psn.title`; açıklama `psn.body`.
2. Koyu sahne kartı (yükseklik içerik kadar), üstten +6; içinde 16 iç boşlukla, dikey aralık 10, üç camsı satır:
   - `person.badge.plus` — `psn.free` / `psn.free.detail`
   - `gamecontroller.fill` — `psn.play` / `psn.play.detail`
   - `lock.shield.fill` — `psn.password` / `psn.password.detail`
3. Uyarı notu (kol uyarısı, uyarı renginde): `psn.controller.warning`.
4. Hesap kimliği kayıtlıysa noktalı durum etiketi: `psn.signedin`.
5. Çalışırken (kimlik alınıyor): vurgu mavisi dönen gösterge.
6. Hata varsa uyarı notu (metin §5.4).

**Alt bölge**:
1. Yatay satır: solda hayalet `psn.why` (tek satır, %75'e kadar küçülür) → esnek boşluk → sağda
   demo düğmesi (`demo.try`; hayalet, `sparkles` simgesi + yazı, tek satır %75'e kadar
   küçülür, yerleşim önceliği yüksek; erişilebilirlik kimliği `tryWithoutPS5`).
2. Hesap kimliği **varsa**: ikincil `psn.again` (giriş sayfasını açar) ve altında birincil `ob.continue` ("bitti").
   Hesap kimliği **yoksa**: birincil `psn.signin` (giriş sayfasını açar; çalışırken devre dışı).

### 5.2 Sayfalar

- **Giriş sayfası** (alttan, tam sayfa, tutamaç görünür): navigasyon çubuklu; ortada başlık "PlayStation Network"
  (çevrilmez, satır içi küçük başlık); solda iptal düğmesi `common.cancel` (sayfayı kapatır). İçerik §5.3'teki web
  görünümü. Açılırken "yönlendirme alındı" bayrağı sıfırlanır.
- **Sayfa kapanınca**: yönlendirme alınmadan kapandıysa (iptal düğmesi dahil, aşağı kaydırma dahil) hata =
  `psn.error.windowclosed`.
- Web sayfasının yüklenme sorunları (HTTP ≥400, ağ hatası) iOS'ta **yok sayılır** (geri çağrısı boş).
- **`psn.why` sayfası**: içeriğe oturan küçük sayfa; büyük başlık bloğu: başlık `psn.why`, açıklama `psn.why.body`.
- **Demo (`demo.try`)**: tam ekran örtü; ana ekranın demo hâli (üstte logo ve `common.close`; kısa yollar yok). Açılınca demo başlar,
  kapanınca durur.

### 5.3 Yönlendirme yakalanınca

1. Bayrak "yönlendirme alındı" = true, giriş sayfası kapanır, "çalışıyor" = true, hata temizlenir.
2. Modelin PSN girişi tamamlama işlevi çağrılır (§9.1).
3. Başarılıysa **kendiliğinden "bitti"** (ilerler; kullanıcı devam düğmesine basmaz). Hata ise hata metni gösterilir.
4. Her iki durumda "çalışıyor" = false.

### 5.4 Hata metinleri (PSN)

Ekranda: hata metni; ayrıntı varsa sonuna " (ayrıntı)" eklenir.

| Durum | Metin anahtarı |
|---|---|
| Yönlendirmede ne kod ne hata (ya da beklenmeyen başka hata; ayrıntı = sistem açıklaması) | `signin.error.incomplete` |
| Sony reddetti (yönlendirmede `error`, ya da token isteği 400/401/403, ya da token yanıtında `error`) | `psn.error.notcompleted` |
| Çok fazla deneme (HTTP 429 veya hata metninde "too many"/"too_many"/"rate limit") | `psn.error.ratelimit` |
| Diğer HTTP hatası | `psn.error.server` |
| Ağ hatası / zaman aşımı | `psn.error.network` |
| Yanıt okunamadı (JSON değil, `user_id` yok/sayı değil) | `psn.error.badresponse` |
| Pencere kapandı | `psn.error.windowclosed` |

Not: PSN hataları model tarafında ayrıntısız (detail = yok) iletilir; yalnız "beklenmeyen başka hata"da ayrıntı eklenir.

---

## 6. PS5 eşleme (kurulum adım 2/3)

### 6.1 Düzen

**Üst satır**: kurulum başlığı, ilerleme 2/3 dolu; geri ve (kurulumdaysa) `common.skipfornow`.

**İçerik**:
1. Büyük başlık bloğu: `setup.step` (2); `pair.title`; `pair.body`.
2. Koyu sahne kartı (üstten +6), 14 iç boşlukla tek camsı satır, simge `gamecontroller.fill`:
   - Başlık / açıklama:
     - Elle adres yazılmamış ve PS5 bulunmuş: `pair.found` (yer tutucuya PS5 adı) / `pair.samewifi` (yer tutucuya IP
       adresi).
     - Elle adres yazılmışsa: "PS5" / yazılan adres.
     - Hiçbiri: `pair.searching` / `pair.searching.detail`.
   - Sağ öğe: adres belli ve şu an aranmıyorsa 10×10 `#30C578` yeşil nokta; değilse yeniden arama düğmesi (§6.5).
3. Kod karosu:
   - Üstte caption ikincil `pair.code`.
   - 8 kutu yan yana, aralık 6, eşit genişlik, her biri en az 52 yüksek; içinde rakam (title boyu); zemin Yüzey‑2, köşe 8;
     kenar: sıradaki boş kutu **ve** alan odaklıysa vurgu mavisi 2 pt, değilse ikincil renk %40, 1.5 pt.
   - Kutuların arkasında görünmez (opaklık 0.01) sayı klavyeli metin alanı; tek kullanımlık kod içerik türü (SMS/sistem
     önerisi gelebilir). Girdi her değişimde yalnız rakamlara süzülür ve 8 haneye kesilir. Kutu alanının tamamına dokununca
     alan odaklanır.
   - Altında: hata varsa uyarı notu (hata metni); yoksa caption ikincil `pair.code.note`.
4. Eşlenirken: dönen gösterge + caption ikincil `pair.connecting`.

**Alt bölge**:
1. Yatay satır: hayalet `pair.notfound` (manuel sayfayı açar) → esnek → demo düğmesi `demo.try`.
2. Birincil `pair.button`: eşlemeyi başlatır. Devre dışı: eşleniyorsa **veya** kod 8 hane değilse
   **veya** adres boşsa.

### 6.2 Kullanılacak adres

Elle yazılan adres (baş/son boşluk kırpılmış) boş değilse o; değilse bulunan ilk PS5'in adresi; o da yoksa boş.

### 6.3 Arama döngüsü

- Ekran açılınca hemen bir arama.
- Sonra ekran açık kaldıkça döngü: bekle (**PS5 bulunamadıysa 2 sn, bulunduysa 6 sn**) → bulunamadıysa normal arama;
  bulunduysa **sessiz tazeleme**.
- Normal arama: zaten aranıyorsa çık; "aranıyor" = true; listeyi sonuçla değiştir; "aranıyor" = false.
- Sessiz tazeleme: aranıyorsa ya da eşleniyorsa yapılmaz; "aranıyor" göstergesi açılmaz; sonuç boş değilse listeyi
  günceller (adresi değişen PS5 güncellenir), boşsa eskisini tutar.
- Ekrandan çıkınca döngü iptal.

### 6.4 PS5'i elle bulma sayfası (`pair.help.title`)

İçeriğe oturan küçük sayfa:
1. Başlık bloğu: `pair.help.title` (dikkat: alttaki bağlantının anahtarı `pair.notfound`'dan farklı); açıklama
   `pair.help.body`.
2. Giriş alanı, yer tutucu `ip.placeholder`; ondalık klavye. Yazılan
   değer doğrudan "elle adres" olur (burada doğrulama yok).
3. İkincil `common.searchagain` (normal arama).
4. Birincil `common.done.alt` (sayfayı kapatır).

### 6.5 Yeniden arama düğmesi (PS5 ve TV ekranlarında ortak)

- Aranırken: aynı yerde 44×44 çerçevede vurgu mavisi dönen gösterge.
- Aranmıyorken: simge düğmesi `arrow.clockwise`, simge rengi vurgu mavisi, erişilebilirlik etiketi
  `common.searchagain`.

### 6.6 Eşleme

"çalışıyor" = true, hata temizlenir → modelin kayıt işlevi (§9.3) → başarılıysa "bitti"; hata ise hata metni kod karosunda
gösterilir → "çalışıyor" = false. Zaten çalışıyorsa ikinci basış yok sayılır.

---

## 7. Altyazının yeri (kurulum adım 3/3 / Ayarlar'daki altyazı hedefi satırı)

İki kipte kullanılır: **kurulum** (varsayılan) ve **kurulum dışı** (ana ekrandan "target" route'u).

### 7.1 Düzen

**Üst satır**:
- Kurulumda: kurulum başlığı, ilerleme 3/3 dolu, geri; **atlama düğmesi yok**.
- Kurulum dışı: geri başlığı — geri simge düğmesi (önceki sayfaya döner) + title boyunda `target.title.alt`; aralık 12;
  44 yükseklik.

**İçerik**:
1. Büyük başlık bloğu: adım (yalnız kurulumda) `setup.step` (3); `target.title`; `target.body`.
2. **TV karosu** — seçili vurgusu: çıkış TV'yi içeriyorsa **ve** eşlenmiş TV varsa.
   - Başlık satırı (yatay, aralık 12): `tv` simgesi + headline `target.tv` → esnek → liste boş değilse yeniden arama
     düğmesi.
   - Her TV için: satır ayracı + TV satırı (dokunulabilir düğme; bir TV eşlenirken hepsi devre dışı).
   - Liste boşsa: yatay satır: caption ikincil metin — aranırken `tv.searching`, değilse `tv.error.notfound` → esnek →
     yeniden arama düğmesi.
3. İki sütunlu ızgara, iki bilgi karosu:
   - Sol (düğme): simge `iphone`, `target.phone`, açıklama `tv.none`. Çıkış "telefon" ise seçili vurgulu. Dokununca
     çıkış = telefon.
   - Sağ (düğme): simge `questionmark.circle`, `tv.notlisted`, açıklama `tv.supported`. Dokununca manuel sayfa (§7.4).
4. Tam genişlik bilgi karosu (düğme): simge `arrow.down.app`, `tv.install.fromphone`, açıklama üç marka adının "·" ile
   dizildiği satır (çevrilmez). Son eşlemede TV uygulaması açılamadıysa seçili vurgulu.
   Dokununca TV uygulaması kurulum sayfası (§7.5).
5. Hata varsa uyarı notu.

**Alt bölge**: birincil — kurulumda `ob.continue`, kurulum dışında `common.done` (dikkat: §6.4'teki `common.done.alt`
değil). Devre dışı: eşlenmiş TV yoksa **ve** çıkış telefon değilse.

### 7.2 TV listesi

- Liste = arama sonucu; ayrıca kayıtlı ve eşlenmiş bir TV varsa ve listede aynı adres+marka yoksa **en başa** eklenir.
- Ekran açılınca bir kez aranır; TV kurulum sayfası kapanınca yeniden aranır. Otomatik yineleme yok.
- Arama yalnız **LG ve Samsung** TV'leri bulur (ikisi aynı anda aranır, sonuçlar birleştirilir). Android TV aramada
  çıkmaz; yalnız manuel sayfadan eklenir.

### 7.3 TV satırı

- "Seçili": eşlenmiş TV var, aynı adres ve marka, çıkış TV'yi içeriyor.
- "Hazır mı": bu ekranda eşlenip sonuç alındıysa o sonuç (açılabildi = hazır); değilse seçiliyse "TV uygulaması eksik" bayrağının
  tersi; değilse bilinmiyor.
- Düzen (yatay, aralık 12, en az 52 yükseklik, tüm satır dokunulabilir):
  - Seçiliyse `checkmark.circle.fill` vurgu mavisi; değilse `circle` ikincil.
  - Dikey (aralık 4): headline TV adı; caption ikincil marka + hazırsa " · " + `tv.status.installed`,
    hazır değilse " · " + `tv.status.noapp`, bilinmiyorsa yalnız marka. Marka adları: LG, Samsung, Android TV.
  - Esnek boşluk.
  - Sağ: bu TV eşleniyorsa dönen gösterge; hazırsa noktalı durum etiketi `status.ready`; hazır değilse noktasız
    etiket `tv.status.notinstalled`; bilinmiyorsa hiçbir şey.
- Dokununca eşleme (§9.6): "eşlenen TV" = bu TV, hata temizlenir; başarılıysa "hazır" sonucu = TV uygulaması açılabildi mi;
  hata ise **her durumda tek metin**: `tv.error.connect`.

### 7.4 Listede olmayan TV sayfası (`tv.notlisted`)

İçeriğe oturan küçük sayfa:
1. Başlık bloğu: `tv.notlisted`; açıklama `tv.supported.body`.
2. Segmentli seçici: LG | Samsung | Android TV (varsayılan LG).
3. Android TV dışındaysa: IP giriş alanı (yer tutucu `ip.placeholder`, ondalık klavye) ve varsa altında
   adres hatası notu.
4. Bağlantı `tv.supported` (caption, vurgu mavisi) — projenin kurulum rehberinin TV uygulaması bölümünü
   tarayıcıda açar.
5. Birincil `common.connect`. Devre dışı: Android TV değilse ve alan boşsa.
   - Android TV: adres boş; ad "Android TV".
   - Diğerleri: adres temizlenir (§7.6). Geçersizse sayfa **açık kalır** ve not `ip.error.invalid` çıkar. Geçerliyse
     ad = adres.
   - Not temizlenir, sayfa kapanır, eşleme başlar.

### 7.5 TV uygulaması kurulum sayfası

Alttan sayfa olarak TV kurulum ekranı açılır (bu belgenin kapsamı dışında). O ekran "bitti" deyince sayfa kapanır ve kurulum
dışı kipte **ya da** kurulumda adım ilerleyebiliyorsa (eşlenmiş TV var ya da çıkış telefon) bu ekranın "bitti"si de çalışır.
Sayfa her kapanışta TV araması yapılır.

### 7.6 Elle adresin temizlenmesi (ortak kural)

Baş/son boşluk atılır; virgüller noktaya çevrilir (Türkçe sayı klavyesinde nokta yok); "xxx://" öneki atılır; ilk `/`, `?`
veya `#`'den sonrası atılır; tek `:` varsa ve sonrası yalnız rakamsa port atılır (sonrası boş/rakam dışıysa geçersiz); birden
çok `:` (IPv6) geçersiz; sondaki nokta atılır; boşsa geçersiz. Yalnız rakam ve noktaysa: tam 4 parça, her biri 1–3 hane ve
0–255 olmalı (öndeki sıfırlar atılarak yazılır). Değilse ağ adı olarak kabul: en çok 253 karakter, en az bir harf, her etiket
1–63 karakter, yalnız ASCII harf/rakam/tire, tireyle başlayıp bitmez; küçük harfe çevrilir.

---

## 8. Kullanım turu (CoachTour)

### 8.1 Ne zaman

Ana ekranda, `coachTourDone` false **ve** yığın boş (alt sayfa yok) **ve** çeviri çalışmıyorken ana ekranın üstüne tam ekran
(güvenli alanlar dahil) katman olarak çizilir. Bitince/atlanınca `coachTourDone = true` (animasyonlu, saydamlıkla kaybolur).
Tur sürerken yüzen robot gizlidir.

### 8.2 Hedefler (ana ekrandaki öğeler kendi çerçevelerini bildirir)

| Sıra | Hedef öğe | Başlık | Metin |
|---|---|---|---|
| 1 | Salon sahnesi / çeviriyi başlatan büyük alan | `home.start.here` | `home.start.hint` |
| 2 | Altyazı çıkışı kısa yolu | `settings.target` | `settings.target.detail` |
| 3 | Paketler kısa yolu | `settings.packs` | `settings.packs.detail` |
| 4 | Üst satırdaki profil düğmesi | `settings.profile.title` | `settings.profile.detail` |

Her hedef öğe, ana ekranda kendi sınır dikdörtgenini bir "tur çapası" tercihi olarak yukarı iletir (hedef → dikdörtgen
sözlüğü, birleştirilir; aynı hedef tekrar gelirse sonuncusu geçerli). Tur bu dikdörtgenleri kendi koordinatına çevirir.

### 8.3 Görünüm

- Tüm ekran siyah %72 karartma.
- Hedefin dikdörtgeni her yandan 6 büyütülür; karartmada bu dikdörtgen kadar, köşesi 16 yuvarlak bir **delik** açılır
  (karartma o bölgeden oyulur).
- Deliğin çevresinde vurgu **mavisi** (`#0070D1`) 2 pt düz halka (parıltı yok).
- Hedef bulunamazsa delik/halka yok, kart dikey ortada.
- **Kart konumu**: yatayda ortada. Hedefin ortası ekranın alt yarısındaysa kart ortası = max(140, hedef üstü − 120); üst
  yarısındaysa min(ekran yüksekliği − 140, hedef altı + 120).
- **Kart**: genişlik = ekran − 2×20 (iPad'de en çok 680); iç boşluk 16; zemin Yüzey‑2 (`#E6EDF8`), köşe 22, kenar beyaz %75.
  İçerik dikey, aralık 12:
  1. Satır: "n / 4" (caption, eş genişlikli rakam, ikincil) → esnek → hayalet `common.skip` (turu bitirir).
  2. Dikey aralık 4: başlık (title 22) ve metin (body 15, ikincil, satırlar kırılır).
  3. Satır: sayfa noktaları (4 nokta) → esnek → birincil düğme, **120 genişlik**: son adımda `common.done.alt` (turu
     bitirir), diğerlerinde `common.next` (animasyonlu bir sonraki adıma).
- Katman bütünüyle saydamlık geçişiyle girer/çıkar.

---

## 9. Modelin kurulum işlevleri

### 9.1 PSN girişini tamamlama (girdi: yakalanan yönlendirme adresi)

1. Adresten hesap kimliği alınır (§10).
2. Başarılı: 8 baytlık hesap kimliği modelde tutulur ve Anahtarlığa yazılır; günlüğe "PSN girişi tamam".
3. PSN hatası: günlüğe yazılır, §5.4 tablosundaki karşılığı **ayrıntısız** fırlatılır.
4. Başka hata: `signin.error.incomplete` + ayrıntı = hatanın açıklaması.

### 9.2 PS5 bulma

- Yerel ağda PS5 keşfi (Remote Play keşif yayını), varsayılan 3 sn bekleme.
- Sonuç boşsa **bir kez daha** aranır (ilk aramada iOS "Yerel Ağ" izni sorar; izin verilene kadar paketler düşer).
- Sonuç günlüğe yazılır. Dönen her öğede en az ad ve IP adresi vardır.

### 9.3 PS5 kaydı / eşleme (girdi: adres, PIN metni)

1. Adres kırpılır; boşsa → `pair.error.notfound`.
2. PIN okunur: boşluk, `-`, `–`, `.`, `_` atlanır; her diğer karakter tek kod noktalı ondalık rakam olmalı (başka yazı
   sistemlerinin rakamları da kabul); tam 8 hane olmalı. Değilse → `pair.error.codelength`.
3. Hesap kimliği yoksa → `psn.error.signinfirst` (kurulum atlandıktan sonra geri gelinip eşlenmeye çalışılırsa bu çıkar.)
4. PS5'e 8 haneli kod ve hesap kimliğiyle Remote Play kaydı yapılır. Başarılıysa kayıtlı konsol (adres, ad, kayıt anahtarı,
   oturum anahtarı) modelde tutulur ve Anahtarlığa yazılır.
5. Kayıt hatası türlerine göre metin (ayrıntı varsa sonuna " (ayrıntı)"):

| Tür | Metin anahtarı ya da anlamı |
|---|---|
| Yanlış hesap | `pair.error.wrongAccount` |
| Yanlış/süresi dolmuş kod | `pair.error.wrongCode` |
| PS5 yanıt vermedi | `session.error.noanswer` |
| İstek alındı, zamanında yanıt yok / iptal | `pair.error.late` |
| Başka cihazda kullanımda | `pair.error.inUse` |
| Remote Play hizmeti çöktü | `pair.error.crashed` |
| Sürüm uyumsuz | `pair.error.version` |
| Adreste PS5 yok | `pair.error.notatAddress` |
| iOS yerel ağı engelledi | Yeni katalogda anahtarı yok: iOS'un ev ağını engellediğini söyleyen, Yerel Ağ iznini açıp yeni kodu girmeyi öğütleyen kısa not |
| Diğer / beklenmeyen | `pair.error.badcode` |

### 9.4 Adım ilerleme

- **ilerleyebilir mi**: welcome → her zaman; psnLogin → PlayStation'da hesap kimliği var / Xbox'ta Microsoft girişi var;
  console → PS5 kayıtlı / Xbox seçili; output → eşlenmiş TV (TV + kayıtlı TV anahtarı) var **veya** çıkış telefon;
  done → hayır.
- **ilerle**: ilerleyebiliyorsa bir sonraki adıma geçer; değilse hiçbir şey olmaz (sessiz).
- **geri**: önceki adım varsa ona geçer (welcome'dan geri yok).

### 9.5 Kurulumu atlama (`skipSetup`, `common.skipfornow`)

`setupSkipped = true` kalıcı yazılır; adım doğrudan **output**'a atlar. Altyazının yeri seçilip devam düğmesine basılınca **done**
olur ve PS5'siz ana ekran açılır. Sonraki açılışlarda da (setupComplete yazıldığı için) ana ekran açılır. Ana ekrandaki PS5
kısa yolu, hesap kimliği yoksa önce PSN girişini açar. Altyazı adımında geri basılırsa PS5 eşleme ekranına dönülür (hesap
kimliği yoksa eşleme §9.3'ün 3. maddesiyle hata verir).

### 9.6 TV bulma ve eşleme

- **Bulma**: LG (SSDP/webOS) ve Samsung aramaları eşzamanlı; sonuçlar birleşir.
- **Eşleme** (girdi: TV — ad, adres, marka):
  1. Telefonun altyazı sunucusu başlatılır (ilk denemede verilen port alınamazsa sunucu rastgele portla yeniden kurulur).
  2. Sunucu adresi: `http://<telefonun TV'ye en yakın yerel IP'si>:<port>` (TV adresi boşsa 192.168.1.1'e göre seçilir; IP
     bulunamazsa 127.0.0.1).
  3. Markaya göre:
     - Android TV: bağlanılmaz; anahtar boş, "açıldı" = evet (TV uygulaması telefonu ağda kendisi bulur).
     - Samsung: kayıtlı jetonla bağlanılır (TV ekranında izin istenir), yeni jeton alınır; Nino'nun Samsung uygulaması
       `server` parametresiyle açılmaya çalışılır; açılamazsa "açıldı" = hayır.
     - LG: kayıtlı istemci anahtarıyla bağlanılır (TV'de onay istenir), yeni anahtar alınır; Nino'nun webOS uygulaması
       `server` parametresiyle açılmaya çalışılır.
  4. Başarılıysa TV kaydedilir; anahtar kaydedilir (Samsung boş jeton dönerse eskisi korunur); "TV anahtarı kayıtlı" = evet;
     "TV uygulaması eksik" = açılamadı mı; çıkış telefon ise **TV'ye çevrilir**.
  5. Bağlantı hatası ekranda tek metne dönüşür (§7.3).

### 9.7 Konsol türü seçimi

Konsol türünü ayarlar, `platformChosen = true` yapar, UserDefaults'a yazar.

### 9.8 Kurulumun sıfırlanması (Ayarlar'dan; bilgi için)

Çeviri durur; hesap kimliği, PS5, TV, TV anahtarı, setupComplete, PS5 şifresi (passcode) silinir; Xbox seçimi ve girişi silinir;
konsol türü silinir (PlayStation, `platformChosen = false`); "TV uygulaması eksik" = hayır; `setupSkipped` silinir; adım =
welcome. (`welcomeSeen` silinmez; karşılama yeniden gösterilmez, konsol seçimiyle başlar.)

---

## 10. PSN giriş sayfası ve hesap kimliği (protokol)

### 10.1 Web görünümü

- Kalıcı olmayan (çerezsiz, oturuma özel) web veri deposuyla yeni bir web görünümü; her açılışta temiz giriş.
- Açılınca şu adres yüklenir:
  `https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize` ve sorgu parametreleri (bu sırayla):

| Parametre | Değer |
|---|---|
| service_entity | `urn:service-entity:psn` |
| response_type | `code` |
| client_id | `ba495a24-818c-472b-b12d-ff231c1b5745` |
| redirect_uri | `https://remoteplay.dl.playstation.net/remoteplay/redirect` |
| scope | `psn:clientapp referenceDataService:countryConfig.read pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update` |
| request_locale | `en_US` |
| ui | `pr` |
| service_logo | `ps` |
| layout_type | `popup` |
| smcid | `remoteplay` |
| prompt | `always` |
| PlatformPrivacyWs1 | `minimal` |

(İstemci kimliği ve gizlisi, açık kaynak Remote Play istemcilerinin herkese açık kullandığı değerlerdir.)

### 10.2 Yönlendirmenin yakalanması

- Her gezinme isteğinde adres kontrol edilir: adres `https://remoteplay.dl.playstation.net/remoteplay/redirect` ile
  **başlıyor** ve sorguda `code` **veya** boş olmayan `error` varsa → (yalnız ilk seferde) yönlendirme bildirilir ve
  gezinme **iptal** edilir. Diğer her şey izinli.
- Ana çerçeve yanıtı HTTP ≥400 ise "sorun: HTTP <kod>" bildirilir (günlüğe de yazılır), değilse "sorun yok". Yükleme
  hataları bildirilir; ama kendi iptalimizden doğan "iptal edildi" (URL hata alanı, iptal kodu) ve "çerçeve yüklemesi
  kesildi" (WebKit hata alanı, kod 102) hataları ve yönlendirme alındıktan sonraki hatalar **yok sayılır**. (iOS ekranı bu
  sorun bildirimlerini kullanmıyor.)

### 10.3 Yönlendirmeden hesap kimliğine

1. Yönlendirmede boş olmayan `code` varsa → token adımı.
2. Yoksa `error` varsa → hata metni: `error` + (varsa) ": " + `error_description` (içindeki `+` boşluğa çevrilir) + (varsa)
   " (" + `error_code` + ")". Metin "too many"/"too_many"/"rate limit" içeriyorsa (küçük harfle) **çok fazla deneme**,
   değilse **reddedildi**.
3. İkisi de yoksa → **kod yok**.

**Token isteği**:
- `POST https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token`
- Başlıklar: `Authorization: Basic base64("<client_id>:<client_secret>")`, gizli = `mvaiZkRsAsI1IBkY`;
  `Content-Type: application/x-www-form-urlencoded`.
- Gövde (URL kodlu form): `grant_type=authorization_code`, `code=<kod>`, `scope=<yukarıdaki scope>`,
  `redirect_uri=<yönlendirme öneki>`.
- Yanıtta `access_token` yoksa: Sony hata alanı (`error` …) varsa reddedildi/çok fazla deneme (aynı kural), yoksa
  **okunamadı**.

**Hesap bilgisi isteği**:
- `GET https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token/<access_token>` (token adresine yol parçası olarak
  eklenir), aynı Basic başlıkla.
- Yanıttaki `user_id` (ondalık sayı metni) 64 bit işaretsiz sayıya çevrilir, **8 bayt little‑endian** olarak hesap
  kimliğidir. Yoksa ya da sayı değilse **okunamadı**. Token hiçbir yerde saklanmaz.

**Ağ ve HTTP kuralları**:
- Oturum: geçici (ephemeral), çerez kabul etmez ve göndermez, istek zaman aşımı 30 sn.
- Ağ hatası → **ağ** (açıklamasıyla).
- 2xx dışı yanıt: gövde JSON ise Sony hatası (`error`, `error_description`, `error_code`; sayı da olabilir) ayrıntı olur;
  değilse gövde metninin ilk 200 karakteri. Durum 429 ya da ayrıntı "çok fazla" içeriyorsa **çok fazla deneme**; 400/401/403
  **reddedildi**; diğerleri **HTTP hatası**.
- 2xx ama JSON nesnesi değil → **okunamadı**.

---

## 11. Akış özeti

```
İlk açılış
  └─ Karşılama (3 sayfa) ── ob.skip / ob.start ──▶ welcomeSeen=true, step=psnLogin
        └─ Konsol seçimi ── common.next ──▶ platformChosen=true
              ├─ PlayStation: PSN girişi ── Sony sayfası ── kimlik alındı ──▶ (otomatik) PS5 eşleme
              │        └─ PS5 eşleme ── 8 hane + pair.button ──▶ Altyazının yeri ── ob.continue ──▶ Ana ekran + Kullanım turu
              └─ Xbox: Microsoft girişi (cihaz kodu) ──▶ Xbox seçimi ──▶ Altyazının yeri ──▶ Ana ekran
  common.skipfornow (PSN/PS5/Xbox adımlarında) ──▶ setupSkipped=true, Altyazının yeri ──▶ PS5'siz ana ekran
  Geri: PSN/Microsoft → Konsol seçimi → Karşılama
```

---

## 12. Ekran görüntüleriyle karşılaştırma

`docs/screenshots/telefon/01–06` eski bir tasarım sürümünden. Yapı büyük ölçüde aynı, ama görünüm ve metinler değişmiş.
Görüntülerdeki eski metinler burada alıntılanmaz; yalnız ne tür bir öğe olduğu yazılır.
**Bu tarif koda göre yazıldı ve geçerli olan odur.**

| Görüntü | Görüntüde | Güncel kod (bu tarif) |
|---|---|---|
| Tümü | Koyu zemin, amber/sarı vurgu ve birincil düğme, parıltılı kenarlar | Açık buz mavisi zemin, vurgu `#0070D1`, birincil düğme koyu lacivert hap |
| 01 karşılama 1 | Üstte simge ve ücretsiz etiketi; sahnede PS5 bağlantısı ve hazır çeviri rozetleri; kolu bırakmamaktan söz eden eski bir metin | Üstte logo + dil seçici + `ob.skip`; sahnede `ob.sample` rozeti ve 2.8 sn'de değişen satır; metinler §3.2 |
| 02 karşılama 2 | GTA geniş, RDR ve Mafia iki kare; üstte geri ve atlama | Üç camsı satır alt alta, her birinde `ob.free`; üstte geri yok |
| 03 PSN | Bilgiler iki+bir karo hâlinde, eski başlıklarla; altta yalnız ikinci hesap sorusu | Bilgiler koyu sahnede üç camsı satır; `psn.controller.warning` notu; alt satırda `demo.try`; üstte `common.skipfornow`; adım satırı mavi |
| 04 PS5 | Eski başlık, kod etiketi ve düğme metinleri | `pair.title`, `pair.code`, düğme `pair.button`; PS5 satırı koyu sahnede; `demo.try` |
| 05 hedef | Eski başlık; ikinci TV'de bilgisayarla kurma etiketi; bir satırda eski marka adıyla "kurulu" yazıyor | `target.title`; doğru durum metni `tv.status.installed`; kurulu değilse `tv.status.notinstalled` etiketi; ayrıca `tv.install.fromphone` karosu ve satır başında seçim dairesi |
| 06 tur | Amber halka ve parıltı, kart koyu, adım sayacı rozet içinde | Mavi 2 pt düz halka, kart `#E6EDF8`, sayaç düz caption metni; yüzen robot tur sürerken gizli |

Ayrıca görüntülerde yer almayan ama kodda olanlar: dil seçici, konsol seçimi ekranı, atlama düğmesi
(`common.skipfornow`), demo düğmesi (`demo.try`), TV kurulum karosu, yüzen `ask.title` robotu.

---

## 13. Kapsam dışı bırakılanlar (başka tariflerde)

Ana ekranın kendisi, TV uygulaması kurma/güncelleme ekranı, demo (`demo.try`) ekranının içi, `ask.title` sohbeti,
Ayarlar/Profil/Paketler/Geçmiş/Hakkında, Xbox akışının protokol ayrıntıları.
