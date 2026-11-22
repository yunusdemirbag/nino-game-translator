# Eski Android uygulamasında çeviri: tariften farklar ve ek davranışlar

Kaynak: eski Android uygulamasının çeviri, havuz ve paket tarafı, gömülü paketler, `glossary-en-tr.json`,
`ai-models.json` ve eski testler. Karşılaştırılan tarifler: `NinoCore/docs/tarif/ceviri.md` ve `paket.md`.
Tariften her ayrılık **Fark:** diye işaretli. Sayılar koddaki gibidir.

---

## 1. Çeviri sırası (bir altyazı satırı için)

Okuma hattından gelen satır şu sırayla çevrilir:

1. **Zaten hedef dilde mi?** Hedef Arapça ya da Urducaysa ve satırda Arap harfi varsa; hedef Tayca, Hintçe ya da
   Bengalceyse ve satırda o dilin yazısı varsa satır çevirmene hiç gitmez, olduğu gibi döner (PS5'in kendi menüsü).
2. **Oyun paketi** (yalnız hedef Türkçeyken, paketler ayarı açıkken ve oyun "havuz öncelikli" değilken). Önce tam
   anahtar, olmazsa bulanık arama (bkz. bölüm 9).
3. **Ortak havuzun telefona inmiş çevirileri** (bütün hedef dillerde; havuz kapalıysa bu bellek boştur).
4. **Havuz öncelikli oyun mu?** (varsayılan GTA 6). Öyleyse satır sunucuya sorulur, en çok 1.500 ms beklenir; gelmezse
   yalnız cihaz içi çeviri yapılır, kullanıcının anahtarlı çevirmeni hiç çağrılmaz (bkz. bölüm 6.5).
5. **Seçili çevirmen**: kullanıcı anahtarlı bir çevrimiçi çevirmen seçtiyse ve anahtar girdiyse o (önce kendi
   önbelleği), yoksa cihaz içi çevirmen (önce kendi önbelleği).
6. Çevrimiçi çevirmen hata verirse, dinlenmedeyse ya da dakikalık hakkı bittiyse satır **cihaz içi çevirmene** düşer.
7. Çeviri bitince paket ve havuz belleğine **bir kez daha** bakılır: çeviri sürerken havuzdan çeviri inmişse
   çevirmenin sonucu yerine o gösterilir.
8. Pakette bulunmayan satır arka planda ayrıca sunucuya sorulur (havuz açıksa ya da oyun havuz öncelikliyse). Daha
   sonra gelen sunucu çevirisi, satır hâlâ ekrandaysa ekrandakinin yerine konur ("yükseltme"). Paketten gelen satıra
   dokunulmaz.

- **Fark:** Tarifte sıra önbellek → paket → çevirmen zinciri. Eski uygulamada ortak bir "yerel önbellek" adımı en başta
  değil: önce paket, sonra havuz belleği gelir; önbellek her çevirmenin içindedir ve yalnız o çevirmenin sonuçlarını
  tutar.
- **Fark:** Tarifte birden çok ücretsiz sağlayıcının sırayla denendiği bir zincir var. Eski uygulamada zincir yok: tek
  seçili çevirmen + hata olunca cihaz içi çevirmen. Ücretsiz HTTP çevirmeni de yok; tek ücretsiz çevirmen cihaz içi
  çeviri. İnternetten gelen ücretsiz çeviri yalnız Nino'nun havuz sunucusundan gelir.
- **Fark:** Tarifte hiçbir çevirmen çeviremezse İngilizce metin "çevrilemedi" işaretiyle döner. Eski uygulamada cihaz
  içi çevirmen de hata verirse satır hiç gösterilmez, ana ekranda "çeviri hatası" uyarısı çıkar; satır ekranda kaldıkça
  yeniden denenir (aynı satırın yeni okuması "az önce çevrildi" sayılmaz).
- **Fark:** Tarifteki "tekrar okunan satır hep önbellekten gelir" kuralı yerine, eski uygulamada okuma hattı son 8
  satırı ve çevirisini aklında tutar; ekrana geri dönen satır çevirmene gitmeden aynı çeviriyle gösterilir.
- **Ek:** Ayrıca okunan ek alanlar (görev yazısı vb.), oyun içi telefon, harita kartı ve "ekranı çevir" düğmesi aynı
  çevirmenleri ayrı bir bağlamla kullanır; böylece altyazının "önceki satır" bağlamına karışmazlar. Ek alanların
  satırları havuza önerilmez.

## 2. Hedef diller

Seçilebilen 11 dil: `tr` Türkçe (hep ilk), `ar` Arapça, `hi` Hintçe, `id` Endonezce, `th` Tayca, `vi` Vietnamca,
`ur` Urduca, `bn` Bengalce, `ms` Malayca, `tl` Filipince (Fince "fi" ile karışmasın diye Tagalogca koduyla), `nl`
Felemenkçe. Dil kodu ayarın ilk iki harfidir.

- İlk açılışta: kurulumu bitmiş eski kurulumda Türkçe; yeni kurulumda telefonun dili listedeyse o, değilse Türkçe.
  Android'in eski kodları da tanınır: Endonezce "in", Filipince "fil".
- Arayüz dili çeviri dilini izler (Android 13 ve sonrası; Filipincede "fil", listede olmayan dilde İngilizce).
- Arapça ve Urducada çeviri sağdan sola gösterilir: Arap harfli her paragrafın başına sağdan sola işareti (U+200F)
  konur.
- **Yalnız Türkçede çalışanlar:** sözlük, oyun paketleri, Türkçe son düzeltmeler, kısa satırın bağlamla çevrilmesi,
  ortak havuza satır gönderme, çevrimiçi çevirmende "sen" hitabı tercihi. Öbür dillerde cihaz içi çevirmen satırı
  cümle cümle düz çevirir, konuşmacı etiketi ve tireler olduğu gibi kalır.
- Havuz sunucusunun çevirileri (indirme ve sorma) bütün dillerde çalışır.
- Anahtarlı çevrimiçi çevirmenlerden biri yalnız şu hedefleri destekler: `tr ar id th vi nl`. Öbür dillerde o çevirmen
  seçili olsa da cihaz içi çevirmen kullanılır.
- **Fark:** Tarif yalnız `en → tr` çiftinden söz ediyor; eski uygulama 11 hedef dil destekliyor.

## 3. Cihaz içi çevirmen (Android'in cihaz içi çeviri kitaplığı)

- İngilizceden seçili hedef dile. Model yaklaşık 30 MB, ilk kullanımda bir kez iner, sonra internetsiz çalışır. Ücretsiz.
- Model indirme: çeviri başlarken arka planda; yalnız Wi-Fi şartı yok (hücresel veride de iner). Bir indirme denemesi en
  çok 300 sn bekler. Olmazsa en çok 6 deneme yapılır; denemeler arası bekleme deneme sırası × 10 sn (10, 20, 30, 40,
  50 sn). İkinci başarısız denemeden sonra ana ekranda "model inemedi" uyarısı çıkar, model inince kalkar.
- Her çeviri en çok 10 sn bekler; aşılırsa hata.
- Önbellekteki motor adı `mlkit-p3` (sondaki 3, Türkçe metin hattının kural sürümü; kurallar değişince sürüm artar,
  eski önbellek kullanılmaz).
- **Fark:** Tarifte cihaz içi sağlayıcı Apple'ın çerçevesi ve adı `device`. Android'de bu iş Google'ın cihaz içi çeviri
  kitaplığıyla yapılıyor.
- **Fark:** Tarifte cihaz içi çevirmen yer tutucuları (`⟦0⟧`) koruyor. Android'de terim koruması yer tutucu işaretiyle
  değil, uydurma özel adlarla yapılıyor (bkz. bölüm 5).
- **Fark:** Tarifte cihaz içi çevirmen zincirin başında, ayarla kapatılabilir. Android'de her zaman vardır; seçili
  çevrimiçi çevirmen yoksa tek çevirmen, varsa yedek çevirmendir. Ayrı bir açma/kapama ayarı yok.

### 3.1 Türkçe metin hattı (cihaz içi çeviri, yalnız Türkçe)

Satır şu adımlardan geçer:

1. Satır cümlelere ve parçalara bölünür. Konuşmacı etiketi ("ATREUS:", "Kratos:", en çok üç sözcük) ve diyalog tireleri
   çevrilmez. "Note:", "Objective:" gibi tek sözcüklü başlıklar (listesi kodda) ad sayılmaz, çevrilir. Etiketli ya da
   tireli satır yeni konuşma sayılır; öbür satır sonları sarmadır, birleştirilir. Cümle sonu `. ! ? …` (ardından kapanış
   tırnağı/ayraç ve boşluk); ardından küçük harf geliyorsa ya da kısaltmaysa ("Mr.", "Dr.", tek büyük harf vb.) cümle
   bitmez.
2. Etiketlerden öğrenilen adlar ve sözlükteki büyük harfli terimlerin sözcükleri "büyük harfle kalacak adlar" listesine
   girer.
3. **Büyük harf düzeni:** satır tümü büyük harfliyse, en az 2 harf ve bir boşluk varsa cümle düzenine çevrilir
   (cümle başı, "I" ve bilinen adlar büyük kalır).
4. **Sözlükteki hazır satırlar:** sözlüğün `lines` bölümünde satırın hazır Türkçesi varsa çevirmene gitmez.
5. **Sözlükteki argo düzeltmeleri** (`phrases`, düzenli ifade) ve kodda sabit 9 oyun deyimi (askerî/oyun argosu) düz
   İngilizce karşılıklarına çevrilir; liste yeni uygulamanın kendi verisidir. Eşleşmenin baş harfi büyükse karşılığınınki
   de büyük olur.
6. **Terim koruma** (bölüm 5), çeviri, terimlerin geri konması, son düzeltmeler (bölüm 4).
7. **Kısa satır bağlamı:** harf içeren sözcük sayısı 1-3 olan cümle (4'ün altı) önceki cümleyle birlikte çevrilir.
   Önceki cümle aynı satırdaki önceki cümle, yoksa bir önceki gösterilen satırın son cümlesidir; o satır 20.000 ms'den
   eskiyse bağlam yoktur. Aynı satır yeniden okunursa aynı bağlam verilir. Bağlam ile cümle arasına ` *** ` ayracı
   konur, çeviriden ayracın sonrası alınır. Ayraç tam bir kez geçmiyorsa, yanında başka yıldız varsa, iki yandan biri
   harf içermiyorsa ya da alınan kısım kaynak uzunluğunun 3 katı + 20 karakterden uzunsa bağlamlı sonuç atılır ve cümle
   tek başına çevrilir.
8. **Hitap birliği:** satırın cümlelerinden birinde "sen", "seni", "sana", "senin", "sende", "senden", "seninle",
   "senle" geçiyorsa, "siz"li sözcük geçmeyen öbür cümlelerdeki bilinen "siz"li emirler "sen"li olur (ör. "durun" → "dur";
   listede 33 emir). Çoğul da olabilen emirler bilerek yok.

- **Ek:** Bu adımların hiçbiri tarifte yok (cümle bölme, etiket koruma, büyük harf düzeni, deyimler, kısa satır
  bağlamı, hitap birliği).

### 3.2 Öbür hedef diller

Cümle cümle çevrilir; her cümle büyük harf düzeninden geçer. Önbelleğe hem satırın tamamı hem her cümle yazılır.
Sözlük, deyimler ve son düzeltmeler yoktur.

## 4. Türkçe son düzeltme

Eski uygulamanın kuralları (yalnız Türkçede, yalnız harf içeren çeviride):

- Tırnaklar kaynağa uyar: kaynakta kıvrık çift tırnak varsa çevirideki düz tırnak kıvrığa çevrilir (açılış/kapanış
  yerine göre), yoksa kıvrık tırnak düze; tek tırnak ve kesme için de aynısı.
- Noktalamadan (`, . ! ? ; : …`) önceki boşluk/sekme/bölünmez boşluk silinir.
- Art arda boşluklar teke iner, baş ve son kırpılır.
- **Son işaret:** yalnız kaynak "ifadeli" bir işaretle (`!`, `?`, `…` ya da `...`) bitiyorsa ve çeviri işaretsiz ya da
  `.` ile bitiyorsa çevirinin sonu kaynağınkiyle değiştirilir. Kaynakta son işaret tırnağın içindeyse ve çeviride
  değilse (ya da tersi) dokunulmaz.

- **Fark:** Tarifteki `…` → `...` çevirisi, `..` → `.`, dört nokta → üç nokta, virgül/noktalı virgülden sonra boşluk
  ekleme ve ilk harfi Türkçe kurala göre büyütme kuralları eski uygulamada yok.
- **Fark:** Tarifte kaynak `.` ile bitip çeviri işaretsizse `.` eklenir. Eski uygulama yalnız `! ? … ...` sonlarını
  korur, nokta eklemez.
- **Ek:** Tırnak uyumu ve hitap birliği (3.1/8) tarifte yok.
- **Ek:** Terimin Türkçe eki yeniden kurulur (bölüm 5).

## 5. Sözlük ve terim koruma

### 5.1 Sözlük dosyası

Uygulamayla gelen `glossary-en-tr.json` + telefondaki `files/glossary/` klasöründeki `*.json` dosyaları (ada göre
sırayla). Bozuk dosya atlanır. Birleştirmede aynı terimde sonraki dosya kazanır. **Yalnız hedef Türkçeyken** kullanılır.

Biçim (bütün alanlar isteğe bağlı):

| Alan | Anlamı |
|---|---|
| `game` | Görünen ad (gömülüde "Ortak"). Kurallarda kullanılmaz. |
| `terms` | İngilizce terim → sabit Türkçe karşılık. Gömülüde 26 terim (oyun eşyası ve silah adları). |
| `keep` | Olduğu gibi kalacak adlar (gömülüde boş). |
| `keepExact` | Yalnız yazıldığı gibi (büyük/küçük harf aynı) geçince olduğu gibi kalan adlar (gömülüde bir adet: sıradan sözcük de olan bir ad). |
| `phrases` | Düzenli ifade → düz İngilizce; çeviriden önce uygulanır, tam sözcük sınırında, büyük/küçük harf fark etmez. Gömülüde 10 kural (asker argosu → düz İngilizce). Bozuk ifade atlanır. Bayt sırasıyla uygulanır. |
| `lines` | Kısa satırın hazır Türkçesi (gömülüde 67 satır; kısa savaş ünlemleri). Satır çevirmene gitmez. Anahtar: küçük harf, kıvrık kesme düz, tek boşluk, baştaki ve sondaki harf/rakam dışı karakterler atılır. Türkçede son işaret yoksa kaynağın sonundaki `. ! ? …` eklenir. |

Terim kuralları: boşluklar teklenir; harf içermeyen ya da 80 karakterden uzun terim alınmaz; Türkçesi boş terim alınmaz.
Arama büyük/küçük harfe bakmaz (`keepExact` hariç), yalnız tam sözcükte (önü ve arkası harf/rakam değil), uzun terim
önce; çakışan kısa terim alınmaz.

Sözlüğün bir izi (FNV-1a 32 bit, terimler sıralı; `phrases` ve `lines` de varsa girer; "g" + 8 hex) önbellek anahtarına
girer: sözlük değişince terimli satırlar yeniden çevrilir.

- **Fark:** Tarifte terimler paketin `terms` listesi + kullanıcının listesinden gelir. Eski paketlerde `terms` yok; terim
  listesi yalnız sözlük dosyalarından gelir. `keepExact`, `phrases`, `lines` tarifte yok.

### 5.2 Koruma yöntemi (cihaz içi çeviri)

- Terim çeviriden önce uydurma bir özel adla değiştirilir. Sırayla 8 ad: Zarmon, Velkor, Dorvan, Kelmar, Tolvar,
  Brandur, Halvor, Feldor (Türkçe ve İngilizcede sözcük değil, i/I içermez, ünsüzle biter, kalın ünlülü). Kaynakta (ya
  da bağlamda) zaten geçen ad kullanılmaz. Adlar biterse kalan terimler korunmaz, çevirmen kendi çevirir. Yani bir
  satırda en çok 8 terim korunur.
- Çeviriden sonra ad bulunur (kesmeli "Zarmon'a", "Zarmon 'a" ya da bitişik "Zarmona"), yerine Türkçe terim konur ve
  çevirmenin koyduğu ek terime göre yeniden kurulur: ünlü uyumu, kaynaştırma (Freya'ya), ünsüz benzeşmesi (Kratos'ta),
  özel adda kesme, cins adda bitişik yazım ve yumuşama (p→b, ç→c, k→ğ, "nk"→"ng"; tek heceli sözcük yumuşamaz),
  çok sözcüklü ve dar ünlüyle biten terimde tamlama eki (ör. iki sözcüklü bir silah adının belirtme hâli). 12 harften uzun ya da harf dışı
  karakterli "ek" dokunulmadan kesmeyle eklenir. Ünlüsüz kısaltma (XP, HP) ince ünlüyle biter sayılır.
- Ad cümle başındaysa terimin ilk harfi Türkçe kuralla büyütülür.
- Kaynakta kıvrık kesme varsa ek de kıvrık kesmeyle ayrılır.
- Bir ad çeviride kaybolduysa ya da beklenmeyen bir ad çıktıdaysa sonuç güvenilmez sayılır: önce bağlamsız tek başına
  çeviri denenir, o da olmazsa terim korumasız çeviri kullanılır.
- Satırın tamamı sözlükte hazır satır değilse, terim korunsa da çevirmene gider.

- **Fark:** Tarifte yer tutucu `⟦0⟧`, `⟦1⟧`…; Android'de uydurma adlar ve Türkçe ek kurma.
- **Fark:** Tarifte yer tutucu kaybolunca sıradaki sağlayıcıya geçilir. Android'de aynı çevirmen korumasız yeniden
  çağrılır.
- **Fark:** Tarifteki "yalnız terimden oluşan cümle çevirmene gitmez, terim karşılığıyla döner" kuralı yok. Yakın
  davranış yalnız sözlüğün `lines` bölümüyle var.

### 5.3 Koruma yöntemi (anahtarlı çevrimiçi çevirmenlerden biri)

Bu çevirmende terim Türkçesiyle değiştirilip `<x>…</x>` içine alınır, metin XML için kaçışlanır ve istek "etiket
çevrilmesin" seçeneğiyle gider; dönüşte etiketler ve kaçışlar geri açılır. Bir cümlede terim varsa istekteki bütün
cümleler kaçışlanır.

## 6. Ortak havuz (Nino havuz sunucusu)

Sunucu adresi: `https://nino-pool.y-demirbag2506.workers.dev`. Telefondaki `files/pool/endpoint.txt` dosyası `http://`
ya da `https://` ile başlayan bir adres içeriyorsa (deneme sunucusu) o kullanılır. Bütün havuz isteklerinde tanıtım
başlığı: `User-Agent: nino-pool/1 (android; <uygulama sürümü>)` (sunucunun önündeki koruma tanımadığı Java
istemcilerini engelliyordu).

Ayar: "Ortak havuz" (varsayılan **açık**). Klipten (deneme görüntüsünden) okunan satırlar hiçbir zaman gönderilmez;
yakalama kartı gerçek oyun sayılır.

### 6.1 Sunucu ayarı — `GET /v1/config`

En çok 600 sn'de bir sorulur. Cevaptan okunanlar:

- `translate.enabled` (varsayılan true), `translate.syncSeconds` (180), `translate.contextLines` (4),
  `translate.maxLines` (12), `translate.deadlineMs` (900; okunur ama kullanılmaz).
- `poolFirst.games` (varsayılan `grand-theft-auto-vi`, `gta-vi`, `gta-6`, `gta6`), `poolFirst.deadlineMs` (varsayılan
  1500), `poolFirst.langs` (varsayılan yalnız `tr`; `*` bütün diller). Eski sunucu bu bölümü göndermezse varsayılanlar
  kalır.
- `downloads`: ana ekrandaki "toplam indirme" sayısı (bkz. 6.8).

Sunucu `translate.enabled` false derse havuzdan hiçbir şey sorulmaz ve inmez; havuz öncelikli oyun da kapanır.

### 6.2 Toplu indirme — `GET /v1/translations`

- Sorgu: `lang=<dil>&since=<sayı>` + varsa `&game=<oyun kimliği>` + varsa `&after=<imleç>`. Oyun bilinmiyorsa `game`
  yok (bütün oyunlar).
- Cevap: `{"items": [[anahtar, çeviri, güncellenme], …], "next": {"since": …, "after": …} | null}`. 3 öğeden kısa
  satır atlanır. `next` varsa sonraki sayfa, yoksa `since` en yeni güncellenme zamanı olur. Bir indirmede en çok 50
  sayfa.
- Ne zaman: çeviri başlarken hemen (zorla), sonra her 60 sn'de bir zamanlayıcı çalışır; aynı oyun için en erken
  `max(30, syncSeconds)` sn'de bir indirilir. Oyun değişince hemen yeniden başlar. Aynı anda tek indirme.
- İndirme sürerken dil değişir ya da havuz kapatılırsa gelen çeviriler kullanılmaz.
- Disk: `files/translation-pool/translations-<dil>.json` = `{"language", "texts": {anahtar: çeviri}, "cursors": {oyun:
  {"since", "after", "checked"}}}`. Dil başına en çok 400.000 çeviri yazılır. Geçici dosyaya yazılıp yerine konur.
- Anahtar oyun paketleriyle aynı 16 haneli anahtardır (bölüm 8.2).

### 6.3 Anında çeviri — `POST /v1/translate`

- Gövde: `{"v": 1, "install", "app", "platform": "android", "lang", "game", "lines": [satır], "context": [son
  contextLines satır]}`.
- Cevap: `{"game": <sunucunun tanıdığı oyun> | null, "translations": [{"text": çeviri | null}]}`. `text` null ya da boşsa
  çeviri yok.
- Sorulmadan önce: satır temizlenir ve havuza uygun olmalı (6.6'daki süzgeç), anahtarı olmalı, havuz belleğinde
  olmamalı. Aynı dil + anahtar için aynı anda tek istek; ikinci soran ilkini bekler.
- Gelen çeviri havuz belleğine yazılır (cevap gelirken havuz kapatıldıysa, havuz öncelikli oyun hariç, yazılmaz ve
  gösterilmez).
- Bağlam: son 30.000 ms içindeki, en çok 4 satır (aynı satır hariç).
- Sunucunun cevaptaki `game` alanı 600 sn geçerli sayılır: uygulama oyunu bilmese de sunucu havuz öncelikli bir oyunu
  tanıdıysa o oyun havuz öncelikli olur.

### 6.4 Çok satırlı soru (oyun içi telefon, harita kartı)

Aynı `POST /v1/translate`, `lines` içinde birden çok satır. Tek istekte en çok `maxLines` satır (1-12 arasına
sıkıştırılır), fazlası parçalanır, parçalar paralel gider. Bilinenler istek atmadan döner. Toplam bekleme en çok
10.000 ms; gelmeyenler cihaz içi çeviriye düşer, istek sürer, geç gelen çeviri belleğe yazılır.

### 6.5 Havuz öncelikli oyun

- Oyun kimliği listedeki parçalardan birini içeriyorsa ve hedef dil `poolFirst.langs`'ta varsa oyun havuz önceliklidir.
  Sunucu kapalıysa ya da adres yoksa değildir.
- Bu oyunda satır sunucuya sorulur, en çok `poolFirst.deadlineMs` (100-10.000 ms arasına sıkıştırılır; varsayılan 1500)
  beklenir. Gelmezse, hata ya da boş gelirse yalnız cihaz içi çevirmen kullanılır. Kullanıcının anahtarlı çevirmeni,
  oyun paketleri ve "ekranı çevir"deki toplu istek bu oyunda kullanılmaz.
- **Ortak havuz ayarı kapalı olsa da** bu oyunda satır sunucuya sorulur (kullanıcı kararı).
- Geç gelen cevap belleğe yazılır; satır ekrandaysa yerine konur.
- Oyun içi telefon ve harita kartı okuması yalnız havuz öncelikli oyunda çalışır.

### 6.6 Satır gönderme kuyruğu — `POST /v1/batches`

Pakette bulunmayan İngilizce satırlar (ve oyun içi telefon mesajları) yeni paket yapılsın diye sunucuya gönderilir.
**Yalnız hedef Türkçeyken**, ortak havuz açıkken ve gerçek oyunda.

- **Süzgeç:** satır temizlenir (denetim karakterleri, sıfır genişlikli karakterler, satır/paragraf ayırıcıları boşluk
  olur; boşluklar teklenir). Kabul: en az bir harf; en çok 500 kod noktası; OCR çöpü değil (OCR temizliği satırın
  sadeleştirilmiş hâlini değiştiriyorsa ya da harf sayısı ×2 görünür karakter sayısından azsa çöp); Türkçe değil (ğ Ğ ş
  Ş ı İ harflerinden biri ya da ü Ü ö Ö ç Ç harflerinden en az 2'si); PS5 sistem yazısı değil (aksansız, küçük harfli,
  tam sözcük olarak: "signed in", "signed out", "earned a trophy", "trophy unlocked", "screenshot saved", "video clip
  saved", "joined the party", "left the party", "is now online", "remote play", "controller disconnected", "press the ps
  button", "playstation network", "download complete", "update available", "oturum acti", "oturum kapatti", "lutfen
  bekleyin", "yeniden baslat"). Bazı bildirimler PSN adı taşıdığı için bunlar hiç gitmez.
- **Kuyruk:** her satır görüldüğü an `files/pool/pending.jsonl` sonuna eklenir: `{"s": sıra, "t": metin, "g": oyun |
  null, "e": oturum | null, "a": saniye}`. Yarım kalmış son satır açılışta kesilir. Bekleyenler 32 MiB'ı geçerse yeni
  satır atılır ve sayılır.
- **Gönderim zamanı:** 5 sn sonra başlayıp her 60 sn'de bir bakılır; en az 200 satır biriktiyse ya da en eski satır
  120.000 ms beklediyse gönderilir. Ağ geri gelince bekleme sıfırlanıp hemen denenir.
- **Parça:** bekleyenler (oyun, oturum, metin) üçlüsüne göre birleştirilip sayılır, 200 farklı satırlık parçalara
  bölünür, `files/pool/outbox/` klasörüne yazılır. Gövde: `{"v": 1, "batch": <rastgele kimlik>, "install", "app",
  "platform", "lines": [{"text", "game", "session", "count", "first", "last"}], "upTo": <son sıra no>}`. En çok 1000
  parça bekler.
- **Cevap:** 2xx ve `{"ok": true, "batch": <aynı kimlik>}` ise parça silinir (kimlik tutmazsa yanlış sunucu sayılır,
  silinmez). 413: parça ikiye bölünür (tek satırsa kenara alınır). 429/503: `Retry-After` kadar (yoksa 60 sn; 1 sn - 1
  gün arası) beklenir. 400/422: parça `files/pool/parked/` klasörüne alınır, uygulama sürümü değişince yeniden denenir.
  Öbür hatalar ve ağ hatası: artan bekleme 30 sn × 2^(hata-1), en çok 1 saat, ±%20 rastgele sapma.
- Aynı kimlikli parça yeniden gönderilirse sunucu ikinci kez saymaz.
- Ortak havuz kapatılınca kuyruk, bekleyen ve kenara alınmış parçaların hepsi silinir.
- Eski sürümden kalan `files/line-pool.json` kuyruğu bir kez aktarılır, dosya `.imported` uzantısıyla kenara konur.
- Durum dosyası `files/pool/state.json`: `install`, `frozenThrough`, `failures`, `nextAttempt`, `serverRetryAt`, `app`,
  `dropped`.
- Bağlantı: 15 sn bağlanma, 30 sn okuma.

### 6.7 Oyunu ekrandan tanıma — `POST /v1/identify`

- Oyun bilinmiyorsa (PS5 söylemiyor, paketten de tanınmadı) Remote Play karesinin gri, en çok 768 piksel genişliğe
  küçültülmüş hâli JPEG (kalite 60) olarak gönderilir. En çok 450 × 1024 bayt.
- Gövde: `{"v": 1, "install", "app", "platform", "image": <base64 JPEG>}`; cevap `{"game": ad | null}`.
- Zamanlama: 8 sn sonra, olmazsa 60 sn'de bir, en çok 6 deneme. Tanındıktan sonra 5 dk sonra bir kez, sonra 20 dk'da
  bir doğrulama (en çok 12).
- Yalnız ortak havuz açıkken ve oyun paket aramasından belli değilken.

### 6.8 Varlık ve sayaç

- `GET /v1/ping?install=&platform=&app=&game=&lang=`: çeviri sürerken 60 sn'de bir (indirmeyle aynı döngüde); cevap
  önemsiz. Havuz kapalıysa gönderilmez.
- Toplam indirme sayacı: `/v1/config` cevabındaki `downloads` (pozitif tam sayı). Çeviri sürerken havuz zaten bu cevabı
  okuduğu için ayrı istek yok; çeviri kapalıyken ana ekran açıkken en çok 600.000 ms'de bir sorulur (10 sn bağlanma/okuma).
  Son bilinen sayı kalıcı saklanır; hiç alınamadıysa sayaç görünmez.

### 6.9 Ağ süreleri (havuz istemcisi)

Bağlanma 15 sn; POST okuma 20 sn; oyun tanıma ve GET okuma 30 sn.

### 6.10 Gizlilik

- Kimlik: kuruluma özgü rastgele UUID. Eski uygulamada anında çeviri/indirme/ping/tanıma için
  `files/translation-pool/install` dosyasındaki UUID, satır kuyruğu için `state.json`'daki ayrı bir UUID kullanılıyordu.
  **Yeni uygulamada tek kimlik** vardır: havuz, satır kuyruğu, sorun bildirimi, Nino'ya Sor ve ölçüm aynı UUID'yi
  kullanır (seçim kuralı veri-ve-ayarlar.md §1.3). Ayrıca her çalışmada yeni bir oturum UUID'si satırlarla gider.
- Giden veri: satırın metni, oyun kimliği, dil, uygulama sürümü, platform; tanımada bir gri ekran karesi. Hesap, ad,
  cihaz bilgisi gitmez.
- PS5 bildirimleri (PSN adı taşıyabilir) ve Türkçe arayüz yazısı süzgeçle gönderilmez.
- Ortak havuz kapalıyken hiçbir şey gönderilmez ve indirilmez; **tek istisna** havuz öncelikli oyunda anında çeviri
  sorusu.

- **Ek:** Ortak havuzun tamamı (6.1-6.10) tarifte yok.

## 7. Anahtarlı çevrimiçi çevirmenler (isteğe bağlı)

Varsayılan çevirmen "ücretsiz" (cihaz içi). Kullanıcı Ayarlar'dan dört hizmetten birini seçip kendi anahtarını girebilir.
Anahtarlar telefonda, Android Keystore'daki donanım destekli AES-GCM anahtarıyla şifrelenip saklanır (uygulama silinince
gider). Anahtar kaydedilmeden önce denenir: geçerli, kotası dolmuş ya da modeli reddedilmiş anahtar kabul edilir;
geçersiz ya da ulaşılamayan anahtar kaydedilmez.

- **Fark:** Tarifte sağlayıcı ayarlarla tarif edilen genel HTTP şablonudur ve kodda hiçbir hizmetin adı/adresi yoktur.
  Eski uygulamada dört hizmetin adresi, istek ve cevap biçimi kodda sabittir; genel şablon yok.

### 7.1 Ortak kurallar

- Satır cümlelere bölünür; konuşmacı etiketleri çevrilmez; önbellekteki cümleler gönderilmez; eksik cümleler büyük harf
  düzeninden geçip **tek istekte** gönderilir. Satırın tamamı da önbelleğe yazılır.
- Hata (ağ, JSON, HTTP hatası) → satır cihaz içi çevirmene düşer, hizmet **60 sn** denenmez, ana ekranda anahtar
  durumu uyarısı çıkar. Başarılı istekte uyarı kalkar.
- Dakikalık istek sınırı aşımı (aşağıda) → uyarı gösterilmez, satır sessizce cihaz içi çevirmene düşer, hizmet en az 1,
  en çok 20 sn (hizmet bekleme süresi söylediyse o kadar) dinlenir.
- **Fark:** Tarifte art arda 3 hata/zaman aşımı → 60 sn dinlenme. Eski uygulamada **tek** hata yeter. Boş/aynı sonuç
  hizmeti dinlenmeye almaz (tarifteki gibi) ama aynı sonuç ayrıca ele alınır (aşağıda).
- Hata durumları: geçersiz anahtar, kota doldu, model reddedildi, ulaşılamıyor.

### 7.2 Çeviri hizmeti 1 (anahtar `:fx` ile bitiyorsa ücretsiz plan)

- Adres: ücretsiz anahtarda `https://api-free.deepl.com/v2/`, öbüründe `https://api.deepl.com/v2/` + `translate`.
- Başlık: `Authorization: DeepL-Auth-Key <anahtar>`, `Content-Type: application/json`.
- Gövde: `{"text": [cümleler], "source_lang": "EN", "target_lang": <dil kodu büyük harf>, "context": <son 3 satır,
  satır sonuyla>, "formality": "prefer_less" (yalnız Türkçe), "preserve_formatting": true}` + terim varsa
  `"tag_handling": "xml", "ignore_tags": ["x"]`.
- Cevap: `{"translations": [{"text"}]}`; sayı cümle sayısına eşit olmalı.
- Zaman aşımı 4000 ms. Hata: 401/403 geçersiz anahtar, 456 kota doldu, öbürü ulaşılamıyor.
- Anahtar denemesi: `GET …/usage` (6000 ms); `character_count >= character_limit` ise kota doldu.
- Önbellek motor adı `deepl`. Sözlük terimi içeren satırın anahtarına sözlüğün izi girer.
- Bağlam ücretlendirilmez.

### 7.3 Yapay zekâ hizmetleri (üç hizmet)

Modeller uygulamayla gelen `ai-models.json`'dan gelir (biçim bölüm 12). Ayardaki model listede yoksa ilk model.

| Hizmet | Adres | Anahtar başlığı | Gövde |
|---|---|---|---|
| A | `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` | `x-goog-api-key` | `systemInstruction.parts[].text`, `contents[{role:"user", parts[{text}]}]`, `generationConfig.maxOutputTokens`, varsa `generationConfig.thinkingConfig.thinkingLevel` |
| B | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | `model`, `messages` (rol `developer` + `user`), `max_completion_tokens`, varsa `reasoning_effort` |
| C | `https://api.anthropic.com/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `model`, `max_tokens`, `system`, `messages[{role:"user"}]`, varsa `output_config.effort`, varsa `thinking.type` |

- Cevaptan metin: A'da ilk adayın `parts` içindeki "düşünce" olmayan metinler birleşir; B'de ilk seçeneğin mesajı;
  C'de `type: "text"` blokları birleşir. Boşsa ulaşılamıyor sayılır.
- Kullanıcı mesajı: oyun biliniyorsa "Game: <ad>"; bağlam varsa önceki satırlar ("English: …" ve biliniyorsa çevirisi)
  "yalnız bağlam için" notuyla; sonra cümleleri JSON dizisi olarak çevirmesi ve aynı sırada aynı sayıda dize içeren
  yalnız bir JSON dizisi dönmesi istenir.
- Sistem yönergesi dile göre üç türlü: Türkçe (doğal, konuşma dili, "sen" hitabı, adlar ve etiketler aynen, satır sonları
  korunur, yalnız çeviri), Arapça (Modern Standart Arapça, kısa, adlar Latin harfle, Arapça noktalama ve Batı rakamları,
  kol tuşu simgeleri aynen) ve öbür diller için genel (Arapçanın benzeri, noktalama kuralı yok).
- Bağlam: son 3 satır ve gösterilen çevirileri.
- Çıktı sınırı 1024 jeton; istek zaman aşımı 5000 ms; anahtar denemesi 15000 ms, deneme satırı
  "KRATOS: We go now. Stay close, boy.".
- Cevap çözme: son `</think>` sonrası alınır; modelin sızdırdığı bitiş/rol işaretleri silinir; kod çiti atılır; dizideki
  sondaki fazla virgül silinir; ilk öğesi tırnaklı dizi JSON olarak okunur (sayı tutmazsa hata); tırnaksız dizi satır
  sonu, cümle sonu işaretinden sonraki virgül, düz virgül sırasıyla bölünüp sayı tutarsa alınır; tek cümlede düz metin de
  kabul edilir.
- **Geri verilen cümle:** model cümleyi çevirmeden döndürdüyse (normalize edilmiş benzerlik 0.90 ve üstü) cümle bir kez
  cihaz içi çevirmenle denenir; o farklı çevirirse onu kullanır (bu sonuç yapay zekânın önbelleğine yazılmaz), o da
  aynıysa modelin cevabı yazılır.
- Hata: 401/403 geçersiz; 402/429 kota; 400 + "api_key_invalid"/"api key not valid" geçersiz; 400 + "credit balance"/
  "insufficient_quota" kota; öbür 400/404 model reddedildi; geri kalanı ulaşılamıyor.
- **Dakikalık sınır (A):** 429 cevabının `error.details[]` içindeki kota ihlallerinde kimlik "PerMinute" içeriyor ve
  hiçbiri "PerDay" içermiyorsa dakikalık sınırdır; `retryDelay` ("37s") bekleme, istek kotasının `quotaValue` değeri
  yeni dakikalık sınır olur (yalnız düşürür). Günlük sınır kullanıcıya kota dolu durumu olarak gösterilir.
- **Dakikalık hak:** modelin `requestsPerMinute` değeri varsa kayan 60.000 ms'lik pencerede en çok o kadar istek
  gönderilir; hak bittiyse istek hiç gönderilmez, satır cihaz içi çevirmene gider. Hak uygulama genelinde model başına
  ortaktır.
- Önbellek motor adı `<hizmet>:<model>`; oyun biliniyorsa anahtar "oyun + ayırıcı + metin" olur.
- **Ekranı çevir:** ekrandaki bütün yazılar tek istekte (en çok 40 parça bir istekte), çıktı sınırı 8192 jeton, 30.000
  ms zaman aşımı. Dakikalık hak bitmiş olsa da gönderilir (kullanıcı düğmeye bastı) ama sayılır. Hata olursa kalanlar
  cihaz içi çevirmenle çevrilir.
- **Ek:** Dakikalık hak, geri verilen cümlenin yeniden denenmesi ve oyun adlı önbellek tarifte yok.

## 8. Önbellek

- Her çevirmenin ve hedef dilin kendi dosyası: `files/Translations/v1-<motor>-en-<dil>.jsonl`. Motor adı yalnız küçük
  harf, rakam ve `-` içermiyorsa (ör. `gemini:<model>`) dosya adı `v1h-<SHA-256(motor \0 en \0 dil) hex>.jsonl` olur
  (Mac ve Windows ile aynı).
- Her satır bir JSON dizisi: `["anahtar", "çeviri"]`. Yarım satır atlanır.
- Bellekte en çok **20.000** kayıt; aşılınca en uzun süre kullanılmayanlardan, fazlalık + sınırın onda biri kadarı atılır.
- Her yeni kayıt **hemen** dosyanın sonuna eklenir. Dosya satırı sınırın 2 katına ulaşınca dosya bellektekilerle yeniden
  yazılır; açılışta dosya satırı kayıt sayısı + sınırın yarısını geçiyorsa da yeniden yazılır.
- Disk hatası çeviriyi durdurmaz; önbellek bellekte çalışır.
- Aynı dosya uygulama içinde tek kez açılır.
- **Fark:** Tarifte sınır 50.000, kayıtta kaynak/çeviri/kaynak türü/tarih var, 20 kayıtta bir ya da `flush` ile yazılır.
  Eski uygulamada sınır 20.000, kayıtta yalnız anahtar ve çeviri var, her kayıt anında yazılır.
- **Fark:** Tarifteki ortak anahtar (küçük harf, boşluk teklenmiş, kıvrık tırnak düz) önbellekte kullanılmaz. Önbellek
  anahtarı ham metindir; cihaz içi Türkçe hatta bağlam ve sözlük izi de anahtara girer: "[sözlük izi + ayırıcı] +
  [bağlam + ayırıcı] + cümle" (ayırıcı U+001F). Paket ve havuz ise 8.2'deki anahtarı kullanır.

### 8.2 Paket ve havuz anahtarı

Satırın sadeleştirilmiş hâlinin SHA-256 özetinin ilk 8 baytı, 16 haneli küçük harf hex. Sadeleştirme:

1. En çok 40 karakterlik `<…>` biçim etiketleri (içinde `<` ya da `>` yok) boşluk olur.
2. NFKC.
3. Küçük harf (dil kuralı olmadan; "İ" → "i" + üst nokta, nokta sonraki adımda düşer).
4. NFD, birleşen işaretler atılır.
5. Harf ve rakam dışındaki her şey boşluk olur.
6. Boşluklar teklenir, baş ve son kırpılır.

Satırda harf ya da rakam yoksa anahtar yok. Mac, Windows ve paket hazırlayan betikle birebir aynı; ortak deneme verisi
`core/Tests/NinoAppCoreTests/Fixtures/golden-vectors.json`.

- **Fark:** Tarifte anahtar küçük harfli düz metin ve noktalama korunur (`Run.` ile `Run?` farklı). Eski anahtarda
  noktalama ve aksanlar atılır, metin özetlenir; `Run.` ile `Run?` aynı anahtardır.

## 9. Oyun paketi

### 9.1 Dosya biçimi

Uzantı `.json.gz` (gzip) ya da `.json`. Gzip baştaki `1f 8b` baytlarından anlaşılır. UTF-8 JSON nesnesi.

```
{
  "format": 2,
  "id": "gta-v",
  "title": "Grand Theft Auto V",
  "source": "serbest metin: çevirinin kaynağı",
  "entries":  { "<16 hex anahtar>": "<Türkçe>", … },
  "segments": { "<16 hex anahtar>": "<Türkçe>", … },
  "fuzzy": { "version": 1, "count": <sayı>, "mask": "<base64>", "lengths": "<base64>", "blooms": "<base64>" }
}
```

| Alan | Zorunlu | Anlamı |
|---|---|---|
| `format` | hayır | 1 ya da 2. Başka bir sayıysa paket yüklenmez. Yoksa kabul edilir. |
| `id` | hayır | Paket kimliği; yoksa dosya adı (uzantısız). Karakter denetimi yok. |
| `title` | hayır | Görünen ad; yoksa kimlik. |
| `source` | hayır | Çevirinin kaynağı (yalnız bilgi). |
| `entries` | evet | Tam satırlar: anahtar → Türkçe. Boşsa ya da hiç geçerli satır yoksa paket yüklenmez. |
| `segments` | hayır (biçim 2) | Oyunun ayrı gösterdiği parçalar ve çok cümleli satırların cümleleri; aynı düzen. Tam satırdan sonra aranır. |
| `fuzzy` | hayır (biçim 2) | Bulanık arama imzaları (9.4). Bozuksa atılır, paket tam eşlemeyle çalışır. |

- **Düz biçim:** kökte `entries` yoksa kökteki bütün dize alanları anahtar → Türkçe sayılır; kimlik ve ad dosya adından
  gelir.
- Anahtar 16 haneli hex değilse satır atlanır (büyük harf hex kabul, küçültülür). Türkçe metindeki biçim etiketleri
  (`<b>`, `</>` vb.) silinir, boşluklar teklenir; boş kalan satır tutulmaz ama bulanık imza sırası için sayılır.
- Aynı anahtar iki kez varsa **sonraki** kazanır.
- Bilinmeyen alanlar atlanır. Dosya akış hâlinde okunur (büyük paketler: GTA V ~190 bin satır).
- Gömülü 9 paket (hepsi biçim 2): assassins-creed-shadows, call-of-duty-modern-warfare-2019, death-stranding-2,
  death-stranding-directors-cut, elden-ring, gta-v, mafia-the-old-country, marvels-spider-man-2, red-dead-redemption-2.
  `fuzzy.count` = `entries` + `segments` sayısı (ör. Assassin's Creed Shadows: 39.615 + 28.977 = 68.592).

- **Fark:** Tarifte uzantı `.ninopack.json`, düz JSON; `nino`, `game.{id,title,version}`, `languages`, `terms`,
  `lines[{source, target, speaker}]` alanları; İngilizce kaynak dosyada açık durur. Eski pakette İngilizce metin yok,
  yalnız özet anahtar var; `terms`, `languages`, `speaker`, sürüm yok.
- **Fark:** Tarifte aynı anahtarda **ilki** kalır, ikincisi uyarı olur. Eski pakette sonraki kazanır, uyarı sayılmaz.
- **Fark:** Tarifteki `unsupportedVersion` / `badGameID` doğrulamaları yok; boş satırlar uyarı olarak sayılmaz.
- **Fark:** Paketler yalnız Türkçedir; hedef dil başka olunca hiç aranmaz.

### 9.2 Kütüphane

Yükleme sırası: uygulamayla gelenler (ada göre), sonra sunucudan inenler (`files/packs-remote/`), sonra içe
aktarılanlar (`files/packs-imported/`). Aynı kimlik sonra gelirse öncekinin yerine geçer. Arama sondan başa yapılır:
önce bütün paketlerin tam satırları, sonra bütün paketlerin parçaları (bir oyunun tam satırı başka oyunun parçasına
yenilmez).

- Ayarlar: paketler açık/kapalı (varsayılan açık), tek tek kapatılan paket kimlikleri.
- Elle seçilen oyun varsa yalnız o oyunun paketinde aranır (ad ya da kimlik eşleşmesi); paketi yoksa hiç aranmaz
  (kısa genel satırlar başka oyunların paketinden yanlış çeviri getiriyordu).
- Paket yüklenirken bellek yetmezse paketsiz devam edilir.
- Yalnız tek pakette bulunan satırlar oynanan oyunu tahmin etmek için kullanılır.
- **Fark:** Tarifte aynı `game.id`'de `game.version` büyük olan kalır. Eski uygulamada sıraya göre sonraki kalır
  (indirilen gömülünün, içe aktarılan ikisinin yerine geçer).

### 9.3 Paket araması (satır nasıl parçalanıp aranır)

Sırayla ve iki tur:

1. Satırın tamamı. Başında konuşmacı etiketi ya da diyalog tiresi varsa önce onsuz gövdesi aranır (etiket çeviriye
   olduğu gibi eklenir), sonra tamamı, sonra OCR'ın bozduğu etiketin atıldığı gövdesi ("-GAETANO:", "M]:", ilk 32
   karakterde `:` ya da `•` ve önündeki sözcükte küçük harf yok; ya da iki noktasız en çok üç büyük harfli sözcük +
   büyük harfle başlayan küçük harfli sözcük).
2. Birden çok satırsa her satır ayrı. Bulunmayan satır "köşe yazısı" ise (en çok 4 sözcük; `•` içerir ya da her sözcük
   büyük harfle başlar ve yalnız harf/rakam) atlanır; öbür bulunmayan satır aramayı bozar.
3. Birden çok cümleyse her cümle ayrı (etiket, tire, ayraçlar kalır).

Parçalı aramada bütün parçalar bulunmalı. Bu tur tam anahtarla hiçbir yoldan tutmazsa aynı sıra ikinci kez denenir;
bu kez her parça önce tam, sonra bulanık aranır. Konuşan adı ayarına göre çevirinin başına ad eklenir ya da atılır.

- Paketteki satırın Türkçesi İngilizcesiyle aynı olsa da gösterilir; yalnız satırda Türkçe harf varsa (PS5'in kendi
  ekranı) ve dengeleyici "aynı" diyorsa atlanır.
- **Ek:** Etiketsiz arama, satır satır, cümle cümle ve köşe yazısı atlama tarifte yok.

### 9.4 Bulanık eşleme

Yalnız "oynanan oyunun" paketinde yapılır: son tam eşleşmenin geldiği paket (ya da elle seçilen oyunun paketi). Hiç tam
eşleşme olmadıysa bulanık arama yapılmaz. İki adım:

**Adım 1 — tek OCR düzeltmesi.** Sadeleştirilmiş satır 6-48 kod noktasıysa, tek düzeltmeyle olabilecek bütün hâller
tam anahtarla aranır: karışan harf dizisi değişir (rn↔m, cl↔d, vv→w, ri↔n, li→h, l↔i, 1→l, 1→i, 0→o, 5→s, j→i, c↔e,
a↔o, h↔b, f↔t, u↔v, y↔v, q↔g), bir harf düşer, sözcük ikiye bölünür ya da iki sözcük birleşir. Bulunan hâllerin hepsi
aynı Türkçeye çıkmalı, yoksa sonuç yok.

**Adım 2 — imza.** Satır harfleri boşluksuz, OCR'ın karıştırdığı harfler birleşmiş (l/1/ı/j → i, 0 → o, 5 → s, æ → a,
ø/œ → o, ß → s) hâle getirilir; her farklı üçlü FNV-1a 64 ile özetlenip Bloom kümesine düşer (üçlü başına 3 bit
hesabı: 64 bitten başlayıp uzunluk × 3 > bit oldukça iki katına, en çok 256 bit). Uzunluk en çok 255 sayılır.

- En kısa satır: 16 harf.
- Benzerlik (0-100): iki yönlü, rastlantıdan arındırılmış kapsamanın küçüğü.
- Kabul eşiği: satırda OCR izi yoksa 24 harften kısada 90, 256'dan kısada 80; OCR izi varsa 24'ten kısada 70, 40'tan
  kısada 60, öbürlerinde 55.
- OCR izi: ASCII dışı harf/işaret (tipografik tırnak, tire ve üç nokta hariç), sözcük içinde harf olmayan işaret
  (kesme ve tire hariç), harf-rakam yan yana, a/A/I/o/O dışında tek harfli sözcük, 14'ten uzun sözcük.
- Aday boyu: satırın ±%25'i (|aday − satır| × 4 ≤ satır).
- Rakip payı 5: en iyi adaydan 5 puandan az geride, Türkçesi farklı bir aday varsa sonuç yok. Eşitlikte işaretsiz sayı
  olarak büyük anahtar seçilir.
- **Tek yönlü kapsama** (yalnız iki yönlü hiçbir aday eşiği geçmediyse ve rakip belirsizliği yoksa; satır en az 22
  harf): aday boyu satırın 11/20'si ile 5/2'si arası, en az 22 harf, satırla aynı boy değil. Kısa tarafın bitlerinin en
  az %90'ı ortak olmalı (hızlı eleme). Kısa tarafın en az 90'ı uzun tarafta; uzun tarafın en az 25'i (yarım okuma) ya da
  55'i (fazlalıklı okuma) kısa tarafta; puan = iç kapsama − 10.
- **Yan cümle denetimi** (fazlalıklı okumada): okuma birden çok cümle/yan cümleyse en az 6 harfli her birinin
  üçlülerinin en az %30'u adayda olmalı; köşe yazısına benzeyen yan cümle atlanır, ilk yan cümlenin başındaki ve
  sonuncunun sonundaki en çok 3 büyük harfli sözcük atılmış hâli de denenir.
- İmza dosyası: `mask` paketteki bütün anahtarlar işaretsiz sayı sırasıyla dizildiğinde imzalı olanların bit maskesi;
  `lengths` imzalı her satırın harf sayısı (bayt); `blooms` ardışık Bloom baytları (küçük uçlu). `version` 1 değilse,
  `count` anahtar sayısını tutmuyorsa ya da boylar tutmuyorsa imzalar atılır. Mac, Windows ve paket betiğiyle aynı;
  ortak deneme verisi `fuzzy-vectors.json`.

- **Fark:** Tarifte: benzerlik anahtarı en az 12 karakter, en az yarı yarıya ortak kelime, boy %80-%125, son işaret aynı
  türde, benzerlik 0.90 ve üstü, eşitlikte paketteki ilk satır. Eski uygulamada yukarıdaki üçlü/Bloom yöntemi, uzunluğa
  ve OCR izine göre değişen eşikler, ±%25 boy, rakip payı, tek yönlü kapsama ve tek OCR düzeltmesi adımı var; kelime
  oranı ve son işaret şartı yok.
- **Fark:** Tarifte bulanık eşleme her pakette; eski uygulamada yalnız oynanan oyunun paketinde.

## 10. Paket indirme ve güncelleme

> **Yeni uygulamada:** paketler uygulamaya gömülmez, havuzdan iner: adres havuz sunucusudur (`pool/endpoint.txt`
> kuralı; derleme ayarındaki `packs.url` kullanılmaz), `GET <havuz>/v1/packs?lang=tr` liste ve
> `GET <havuz>/v1/packs/<id>?lang=tr` paket. Hiç paket inmemişse kütüphane boştur, çeviri paketsiz sürer; eski sürümün
> `files/packs-remote/` içine indirdikleri okunmaya devam eder. Sözlük (`glossary-en-tr.json`) ve model listesi
> (`ai-models.json`) Nino'nun kendi dosyalarıdır (eski uygulamadan kopyalanmadı).

- Paket sunucusunun adresi derleme ayarından gelir: `secrets.properties` içindeki `packs.url` ya da ortam değişkeni
  `PACKS_URL`. Boşsa indirme kapalıdır, yalnız gömülü paketler kullanılır.
- `GET <adres>/v1/packs` → `{"packs": [{"id", "title", "version", "sha256", "size", "entries"}]}`. Liste eksik, null ya da
  bozuksa hata sayılır (boş liste sayılırsa inmiş paketler silinirdi).
- `GET <adres>/v1/packs/<id>` → paketin gzip baytları.
- Ne zaman: uygulama açılışında hemen; uygulama açık kaldıkça 24 saatte bir; PS5'te yeni oyun tanınınca son bakış 10
  dakikadan eskiyse hemen (inen paket çalışan çeviride hemen yeniden okunur). Sunucuda her gece havuzdan `pool-*`
  paketleri üretilir.
- Sürümü ve SHA-256'sı değişmeyen ve diskteki dosyası doğrulanan paket yeniden indirilmez.
- İnen dosyanın SHA-256'sı listeyle tutmalı; önce geçici dosyaya (`<id>.download`) yazılır, sonra
  `files/packs-remote/<id>.json.gz` olur.
- İnemeyen ya da doğrulanamayan paket: eski sürümü varsa o kalır (bir sonraki bakışta yeniden denensin diye sürümü −1
  yazılır) ve son bakış zamanı ilerletilmez.
- Sunucudan kalkan paket telefondan silinir.
- Durum dosyası `files/packs-remote/packs.state`: `{"checked": ms, "packs": [{"id", "title", "version", "sha256"}]}`.
- Paket ekranı sunucuda olup henüz inmemiş paketleri de gösterir. Ayarlardan "indirilen paketleri sil" var.
- Bağlantı 15 sn, okuma 60 sn.
- **Ek:** İndirme tarifte yok (tarifte kütüphane yalnız klasördeki dosyaları okur).

## 11. Paket içe aktarma (Ayarlar › Oyun paketleri)

Topluluğun çeviri dosyası telefonda pakete çevrilir; dosya sunucuya ya da havuza gitmez.

- Dosya türü uzantıdan: `json`, `txt`, `srt`; başkası desteklenmez. En çok 64 MiB. Katı UTF-8 (baştaki BOM atlanır).
- **JSON** (katı okuyucu, en çok 512 iç içe düzey, kök nesne olmalı):
  - `{"format": 1, "entries": {<16 hex>: Türkçe}, "title" | "game"}`: hazır anahtarlı paket. `format` 1 değilse
    desteklenmez; `format` yokken `entries` varsa da desteklenmez.
  - `{"subtitles": {İngilizce: Türkçe}, "game" | "title"}`.
  - Düz `{İngilizce: Türkçe}`.
  - Aynı adlı üyelerde sonuncusu alınır.
- **TXT:** her satır `İngilizce<TAB>Türkçe` ya da `İngilizce = Türkçe`; `#` ile başlayan satır yorum; boş satır atlanır;
  öbürü geçersiz sayılır.
- **SRT:** boş satırla ayrılmış ve tam 4 satırlı bloklar: sıra numarası, `00:00:00,000 --> 00:00:00,000` biçiminde
  zaman (başlangıç bitişten küçük), İngilizce, Türkçe. Öbür bloklar geçersiz.
- İngilizce taraf 8.2'deki anahtara çevrilir; yalnız anahtar ve Türkçe saklanır. Anahtarı olmayan ya da Türkçesi boş
  satır geçersiz sayılır. Aynı satır aynı Türkçeyle tekrar ederse "yinelenen" sayılır; aynı anahtara farklı Türkçe gelirse
  satır hiç alınmaz ve "çakışma" sayılır.
- Önizlemede önerilen ad, kullanılabilir satırlar ve geçersiz/yinelenen/çakışan sayıları gösterilir.
- Kaydetme: ad zorunlu; satır yoksa olmaz. Kimlik `community-<ad>`: ASCII harfler küçültülür, rakamlar kalır, öbür
  karakterler tek tire olur, en çok 80 karakter; ad boşalırsa `community-game`. Dosya
  `files/packs-imported/<kimlik>.json` (biçim 1: `format`, `id`, `title`, `entries`). Aynı kimlik varsa kullanıcı
  "değiştir" demedikçe hata; önce geçici dosyaya yazılıp yerine konur. İçe aktarılan ya da silinen paket çalışan
  çeviride hemen yeniden okunur.
- **Ek:** İçe aktarma tarifte yok.

## 12. Gömülü yardımcı dosyaların biçimi

> **Yeni uygulamada:** paketler gömülmez, havuzdan iner (bölüm 10); `assets/` içinde yalnız Nino'nun kendi
> sözlüğü (`glossary-en-tr.json`) ve model listesi (`ai-models.json`) vardır. İkisi de bu uygulama için yeniden
> yazıldı; eski uygulamanın dosyaları kullanılmaz.

### `ai-models.json`

Kök nesne; `_comment` gibi dizi olmayan alanlar atlanır. Hizmet adı (`gemini`, `openai`, `claude`) → model dizisi. İlk
model varsayılan. Model alanları: `id`, `label` (arayüz metni anahtarı), isteğe bağlı `effort`, `thinking`, `freeTier`
(ücretsiz anahtarla kullanılabilir), `requestsPerMinute` (uygulamanın dakikada gönderdiği en çok istek). Şu anki değerler:
A hizmetinde iki model (dakikada 15 ve 10 istek, ikisi de ücretsiz katmanda; ikincisi düşünme düzeyi "LOW"); B'de iki
model (`effort: "none"`); C'de iki model (`effort: "low"`, `thinking` "disabled" ve "between_tools").

### `glossary-en-tr.json`

Bölüm 5.1.

## Belirsizlikler

1. **Satır gönderme süzgeci iki türlü.** Kodda daha sıkı bir süzgeç (yarım okuma, büyük harfli arayüz yazısı, OCR'ın
   bozduğu Türkçe arayüz sözcükleri, daha uzun sistem yazısı listesi; Mac, Windows ve sunucuyla "aynı") ve onu kullanan
   eski bir gönderme sınıfı var ama o sınıf artık hiç kullanılmıyor. Çalışan kuyruk yalnız 6.6'daki daha gevşek süzgeci
   uyguluyor. Yeni uygulamada hangisinin geçerli olacağı belli değil.
2. **Havuz sunucusunun çevirmeni.** Koddaki açıklamalar sunucunun belli bir ücretli yapay zekâyla çevirdiğini söylüyor;
   kullanıcı notlarına göre 20 Kasım'dan beri sunucuda ücretsiz hizmet zinciri var. Uygulama tarafı bundan etkilenmiyor
   ama "sunucu o an çevirir" varsayımı ve 1.500 ms bekleme yeni zincirde gerçekçi mi bilinmiyor.
3. ~~**İki ayrı kurulum kimliği** (6.10)~~: yeni uygulamada çözüldü, tek kimlik (veri-ve-ayarlar.md §1.3).
4. **`translate.deadlineMs`** (varsayılan 900) sunucudan okunuyor ama hiçbir yerde kullanılmıyor; havuz öncelikli
   bekleme `poolFirst.deadlineMs`'ten geliyor.
5. **Paket sunucusunun gerçek adresi** depoda yok (derleme sırrı; `secrets.properties` bu kopyada bulunmuyor). Örnek
   dosyada yalnız biçimi var.
6. **Önbellek anahtarı uyumu.** Tarif önbellek ile paketin aynı anahtarı kullanmasını istiyor; eski uygulamada önbellek
   ham metinle, paket ve havuz özet anahtarla çalışıyor. Eski önbellek dosyaları (`files/Translations/`) yeni
   uygulamaya taşınacaksa anahtarın yeniden hesaplanması gerekir; bağlamlı ve sözlük izli anahtarlar düz metne
   dönüştürülemez.
7. **Paket biçimi geçişi.** Tarifteki `.ninopack.json` İngilizce metni açık tutuyor; eski paketlerde yalnız özet var,
   İngilizce metin geri çıkarılamaz (bulanık imzalar da bilerek geri çıkarılamaz). Yeni çekirdek eski `.json.gz`
   paketlerini okuyacak mı, yoksa paketler yeniden mi üretilecek, karar gerekiyor. Ayrıca gömülü paketlerden birinin
   `source` alanında, CLAUDE.md'ye göre hiçbir yerde geçmemesi gereken eski bir proje adı yazıyor; yayımlanmadan önce
   temizlenmeli.
8. **Tarifteki "çevrilemedi" durumu.** Eski uygulama bu durumda satırı göstermiyor, yeniden deniyor; yeni çekirdekte
   İngilizce gösterilecek mi, gösterilmeyecek mi kararı okuma hattı tarifine bağlı.
9. **Ekranı çevir, telefon, harita** çevirisinin ayrıntıları (parça bölme, gösterme süreleri) bu belgede yok; yalnız
   çeviri kaynaklarının sırası yazıldı.
10. **Cihaz içi çeviri modeli indirme koşulu.** Kodda "yalnız Wi-Fi" seçeneği var ama hiç açılmıyor; ayarda böyle bir
    seçenek de görülmedi.
