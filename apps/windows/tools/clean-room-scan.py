#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Temiz oda taraması (Windows). Eski ağaçtaki metinlerle yeni Windows kodu ve tarifleri arasındaki ortak değerleri bulur.
# Eski dosyalar yalnız karşılaştırma için okunur; buradan yeni koda hiçbir şey yazılmaz.
#
# Eski taraf:
#   veri     core/Sources/NinoAppCore/Resources/{glossary-en-tr,ai-models}.json ve core/Tests/.../Fixtures altındaki
#            golden-vectors, fuzzy-vectors, pack-matches (sözlük terimleri ayrıca "sozluk" sayılır)
#   oldtest  windows/tests/**/*.cs dizge değişmezleri
#   oldsrc   windows/src/**/*.cs içindeki uzun, çok sözcüklü dizge değişmezleri (istem ve ileti parçaları)
#   ui       eski metin dosyaları: windows/src/Nino.Core/Resources/Windows.xcstrings ve eski Windows'un gömdüğü
#            mac/Nino/Resources/Localizable.xcstrings (anahtar + bütün dillerdeki değerler)
# Yeni taraf: apps/windows (bin/obj hariç; .json.gz fikstürleri açılarak) ve docs/yeni/windows.
#
# Kullanım: python3 apps/windows/tools/clean-room-scan.py [MIN=12] [--all] [--only=<yol öneki>]…
# Çıktı TSV: kategori, kaynak, değer, dosya. Öntanımlı olarak yalnız "düzeltilmeli" kategorileri yazılır
# (--all ile hepsi); kategori sayıları her zaman stderr'e yazılır. --only yalnız o önekle başlayan yeni dosyaları tarar.
#   düzeltilmeli: veri, sozluk, metin, arayuz (tarifler, testler, araçlar, catalog-where.json ve kalan her şey)
#   açık konu:    katalog (Text/Catalog/*.json değeri eski metin dosyasındakiyle aynı)
#                 kod     (src altındaki .cs dosyasında eski dizgeyle aynı değişmez)
#                 kod-test (testin doğruladığı değer src'deki böyle bir dizge; src değişince test de değişir)
#   kalabilir:    kod-izinli (kod/kod-test kaydı; değer docs/yeni/windows/temiz-oda.md "İzinli kod dizgeleri"
#                        listesinde: dış biçim, protokol, ürün adı, oyun sözcük tablosu)
#   kalabilir:    gta6  (kullanıcının ekran karelerindeki oyun metni, .lines.txt)
#                 uyum  (tests/**/Fixtures/Compat ve Compat testleri: eski uygulamanın yazdığı veri dosyaları, girdi
#                        ve ondan yeni kodla üretilen beklenen çıktı; içerik bilerek eskiyle aynıdır)
#                 genel (oyun adı, kimlik, adres, dosya yolu, tek sözcük, donanım adı, başka programların
#                        kendi çıktısı, kod kalıbı, oyunlarda sıradan iki-üç sözcüklü komut)
# Ayrıca metin katalogları eski metin dosyalarıyla karşılaştırılır (aşağıda, catalog_compare).
# Çıkış kodu: düzeltilmeli kategoride ya da katalog-aynı/katalog-4gram'da kayıt varsa 1.

import glob
import gzip
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)                      # apps/windows
REPO = os.path.dirname(os.path.dirname(APP))     # depo kökü
args = [a for a in sys.argv[1:] if not a.startswith('--')]
MIN = int(args[0]) if args else 12
SHOW_ALL = '--all' in sys.argv
ONLY = [a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--only=')]

FIX = 'core/Tests/NinoAppCoreTests/Fixtures/'
DATA = {
    'glossary': 'core/Sources/NinoAppCore/Resources/glossary-en-tr.json',
    'aimodels': 'core/Sources/NinoAppCore/Resources/ai-models.json',
    'golden': FIX + 'golden-vectors.json',
    'fuzzy': FIX + 'fuzzy-vectors.json',
    'pack': FIX + 'pack-matches.json',
}
UI_FILES = ['windows/src/Nino.Core/Resources/Windows.xcstrings', 'mac/Nino/Resources/Localizable.xcstrings']
FIXING = {'veri', 'sozluk', 'metin', 'arayuz'}
OPEN = {'katalog', 'kod', 'kod-test'}

# JSON şema adları ve bu dosyaların ortak alan adları: içerik değil, biçim.
SCHEMA = {'game', 'terms', 'keep', 'keepExact', 'phrases', 'lines', 'signatures', 'similarities', 'looseLabels',
          'thresholds', 'warmUp', 'cases', 'gemini', 'openai', 'claude', 'label', 'freeTier', 'effort', 'thinking',
          'requestsPerMinute'}


def leaves(o):
    if isinstance(o, dict):
        for k, v in o.items():
            yield str(k)
            yield from leaves(v)
    elif isinstance(o, list):
        for v in o:
            yield from leaves(v)
    elif isinstance(o, str):
        yield o


old = {}


def add(s, src):
    s = s.strip()
    if s:
        old.setdefault(s, set()).add(src)


for name, rel in DATA.items():
    for s in leaves(json.load(open(os.path.join(REPO, rel), encoding='utf-8'))):
        if s.strip() in SCHEMA:
            continue
        if name == 'glossary' or len(s.strip()) >= MIN:
            add(s, 'glossary' if name == 'glossary' else 'veri:' + name)

# C# dizge değişmezleri: "…", @"…", $"…{x}…", """…""". Yorumlar okunmaz.
LIT = re.compile(r'"""(.*?)"""|@"((?:[^"]|"")*)"|"((?:[^"\\\n]|\\.)*)"', re.S)
INTERP = re.compile(r'\{[^{}]*\}')


def literals(text):
    text = re.sub(r'//[^\n]*', '', text)
    for m in LIT.finditer(text):
        body = next(g for g in m.groups() if g is not None)
        for part in INTERP.split(body):
            part = part.replace('\\n', '\n').replace('\\"', '"')
            # Çok satırlı değişmez ("""…"""): satır satır da alınır.
            for piece in [part] + (part.split('\n') if '\n' in part else []):
                piece = piece.strip()
                if len(piece) >= MIN:
                    yield piece


for path in glob.glob(os.path.join(REPO, 'windows/tests/**/*.cs'), recursive=True):
    if '/obj/' in path or '/bin/' in path:
        continue
    for s in literals(open(path, encoding='utf-8', errors='ignore').read()):
        add(s, 'oldtest')
for path in glob.glob(os.path.join(REPO, 'windows/src/**/*.cs'), recursive=True):
    if '/obj/' in path or '/bin/' in path:
        continue
    for s in literals(open(path, encoding='utf-8', errors='ignore').read()):
        if s.count(' ') >= 3:
            add(s, 'oldsrc')

UI = set()
for rel in UI_FILES:
    d = json.load(open(os.path.join(REPO, rel), encoding='utf-8'))
    for key, entry in d.get('strings', {}).items():
        UI.add(key)
        for loc in (entry.get('localizations') or {}).values():
            for s in leaves(loc):
                if s not in ('translated', 'new', 'needs_review', 'stale'):
                    UI.add(s)
for s in UI:
    if len(s.strip()) >= MIN:
        add(s, 'ui')


def norm(s):
    return re.sub(r'[^0-9a-zçğıöşü]', '', s.lower())


# .lines.txt satırı: dört koordinat + sekme + metin. Yalnız metin alınır, satırlar art arda eklenir (bir cümle
# ekranda iki satıra bölünmüş olabilir).
GTA_TEXT = ''
GTA_LINES = []
for p in sorted(glob.glob(os.path.join(REPO, 'windows/**/*.lines.txt'), recursive=True)):
    for line in open(p, encoding='utf-8', errors='ignore'):
        GTA_LINES.append(norm(line.split('\t', 1)[-1]))
        GTA_TEXT += GTA_LINES[-1]

# Oyun adları ve kimlikleri, sabit düz adlar (oyunların kendi adları; çevrilmez, eski metin sayılmaz).
TITLES = {"Mafia: The Old Country", "Red Dead Redemption 2", "Marvel's Spider-Man 2", "Death Stranding 2: On the Beach",
          "Assassin's Creed Shadows", "Call of Duty: Modern Warfare", "Death Stranding Director's Cut",
          "Grand Theft Auto V", "Grand Theft Auto VI", "Modern Standard Arabic", "Unknown Session Request",
          "Unknown Session Request Error", "Greenlight - My consoles", "Microsoft Corporation",
          "Sony Interactive Entertainment", "Sony Interactive Entertainment Inc.", "Helsinki University",
          "Marvel's Wolverine"}
ALLOW_RE = re.compile(
    r'://|^[\w.-]+\.(com|tv|net|org|io|log|json|txt|apk|ipk|wgt|exe|dll|zip|msix|ps1|py|md|gz)\b|^\.?\.?[/\\]|^~/|'
    r'^%[A-Z]+%|^[A-Z]:\\|^[\W\d_]+$|^[A-Za-z0-9]+([-_.][A-Za-z0-9]+)+$|^[a-z]+(\.[a-zA-Z]+)+$|'
    r'^application/|^(GET|POST|PUT|DELETE) /|^[A-Za-z_]+=\S*$|^\{\s*"[^"]*"\s*:.*\}?$|^</?[a-zA-Z]+>$|'
    r'^-{1,2}[a-z][\w-]*( \S+)?$|^[a-z0-9_]+(/[a-z0-9_.{}-]+)+$|^\d\d:\d\d:\d\d,\d{3} --> ')
# Yeni koddaki popüler oyun listesi (oyunların kendi adları).
_games = open(os.path.join(APP, 'src/Nino.Core/Reading/Games.cs'), encoding='utf-8').read()
_m = re.search(r'Popular \{ get; \} = """(.*?)"""', _games, re.S)
if _m:
    TITLES |= {x.strip() for x in _m.group(1).split('\n') if x.strip()}
TITLE_KEYS = set()


def title_key(s):
    return ' '.join(re.sub(r"[^0-9a-z]+", ' ', s.lower().replace("'", '').replace('ō', 'o').replace('ö', 'o')
                           .replace('™', '').replace('®', '')).split())


GTA = re.compile(r"Lucia|Jason|Leonida|BUCKME|Buckme|Brian|Donnie|Kenton|Shirley|Vice City|\bCal\b|motel|scuba|"
                 r"parrotfish|wrecks|jet ski|Rydeme|amigo|\byuh\b|minimap|RESIDENTIAL|BOAT CHARTERS", re.I)
# Tek başına sıradan sözcük/ifade: eski sözlükte de geçiyor ama genel dil; bir oyunun ya da yazarın metni değil.
# Oyun türünün ortak sözcükleri ve her oyunda geçen iki-üç sözcüklü komutlar da öyle (bir yazara ait olamayacak kadar
# kısa ve kalıp): bunlar sözlükte ve test cümlelerinde bulunabilir.
COMMON = {'bekleme süresi', 'contact', 'incoming', 'kontrol noktası', 'checkpoint', 'cooldown', 'loading',
          'settings', 'mission', 'görev', 'ayarlar', 'harita', 'map', 'menu', 'menü', 'pause', 'duraklat',
          'genel', 'ileri', 'fast travel', 'hızlı seyahat', 'save point', 'kayıt noktası', 'side quest', 'yan görev',
          'skill tree', 'yetenek ağacı', 'quest log', 'görev günlüğü', 'health potion', 'can iksiri', 'get down',
          'yere yat', 'hold the line', 'hattı tutun', 'copy that', 'anlaşıldı', 'revive me', 'beni canlandır',
          'geri çekilin', 'fall back', 'önde düşman', 'enemy ahead', 'beceri ağacı',
          # İngilizcenin gündelik deyimleri (deyim değiştirme kuralının çıktısı)
          "i've got your back", 'took you long enough'}
# Başka programların kendi çıktısı (chiaki-ng günlük satırları, işletim sistemi soket hataları, Samsung/LG araçlarının
# iletileri, hizmetlerin hata gövdeleri): yeni kod bunları tanımak için arar; eski yazarın metni değil.
EXTERNAL = re.compile(
    # chiaki-ng'nin kendi günlük ve hata dizgeleri (Remote Play oturumu, kayıt, Takion/Senkusha)
    r'Session Request|Session request (successful|connect failed)|Failed to (send|receive|parse) session request|'
    r'^Regist |\bRegist (failed|search failed|eventually failed)|Send Buffer|^Senkusha|^Takion |'
    r'Reported Application Reason|^\[chiaki (info|warning|error)\] |FEC fail|IDR frame|^Version Mismatch$|'
    r'^0x[0-9a-fA-F]{8} \(Regist |'
    # işletim sistemi soket/ad çözümleme hataları (tam ifade)
    r'^connection reset by peer$|connection refused|^No such host( is known\.)?$|^Network is unreachable$|'
    r'^Host is down$|timed out (waiting|receiving)|'
    # hizmetlerin hata gövdeleri (tam ifade ya da durum kodu adları)
    r'^api key not valid|^API key not valid|^Too Many Requests$|^(PERMISSION_DENIED|RESOURCE_EXHAUSTED|'
    r'INVALID_ARGUMENT|UNAVAILABLE|UNAUTHENTICATED)$|^access_denied: |^invalid_grant: |'
    r'^code=AUTH_FAIL, message=Invalid access token$|^Can\'t connect to the server\.?$|'
    r'^CANNOT CONNECT TO THE SERVER$|^unknown model$|'
    # Sony giriş sayfasının kendi etiketi
    r'^Sign-In ID \(Email Address\)$|'
    # PS5'in kendi sistem yazıları (havuz süzgeci sunucuyla aynı listeyi arar)
    r'^press the ps button$|^turn off your console$|'
    # adb, sdb, Tizen ve webOS araçlarının komutları ve çıktıları
    r'^shell:(pm|appops|am) |^exec:cmd package |vd_appuninstall|^Push complete\.?$|Security error : |'
    r'^Remote closed channel$|before sending OKAY|app_id\[[\w.]+\] (download failed|install failed|installing)\[|'
    r'^install failed\[|Check certificate error : |^Author certificate not match$|same id and different certificate|'
    r'^error: (closed|transport connection closed)$|^cannot connect$|^No such file$|^Invalid package$|'
    r'\(errorCode -?\d+\)$|^Denied method call|^Installation failure|No space left on device$|"type":"Samsung SmartTV"|'
    r'^Security exception: uid |^Unable to find package: |^Error: Unknown operation string|'
    r'^Pull skipped or failed: not found$|^spend time for pkgcmd is \[\d+\]ms$|^cmd_ret:|^Security error$|'
    r'^download failed\[\d+\]$|^Service Unavailable$|^versionCode=\d+ minSdk=\d+$|'
    r'^sdb bağlantısı kurul|'
    # kabukta bekleme döngüsünün parçaları (TV'ye giden komut; sözcük değil komut sözdizimi)
    r'^while \[ |^sleep \d+ |^rm -f /|2>/dev/null && break|^\]; do grep -q -i|^echo merhaba; echo uyarı >&2; exit 3$|'
    # Samsung'un açık sertifika adları, PEM başlıkları, Sony OAuth kapsamı, HTTP durum satırı, 8787 SSE olay satırları
    r'^Samsung VD Author CA$|^VD DEVELOPER Public CA Class|^-----(BEGIN|END) [A-Z ]+-----$|^Proc-Type: 4,ENCRYPTED$|'
    r'scope=psn:|^psn:clientapp |^HTTP/1\.1 200 OK(\\r)?$|^event: [a-z]+$|^data: \{|'
    # Windows, Edge ve OBS'nin koyduğu adlar; eski sürümlerle aynı kalması gereken güvenlik duvarı kural adları
    r'^vEthernet \(|^Fullscreen Projector \(|^Nino - Local (TCP|UDP)$|^Xbox Cloud Gaming on Xbox\.com - Microsoft Edge$|'
    # Windows sürüm adı (işletim sisteminin verdiği)
    r'^Windows 1[01] \(\d+\)$|'
    # Üçüncü taraf çeviri modellerinin belgelenmiş istem kalıpları (TranslateGemma, MiLMMT); model böyle ister
    r'^English \(en\) to [A-Z][a-z]+ \([a-z]{2}\)$|^Translate this from English to( [A-Z][a-z]+:)?$|'
    r'^into [A-Z][a-z]+:$|'
    # Windows bileşeninin ve PS5 menüsünün kendi Türkçe adları (kullanıcının ekranında böyle yazar)
    r'^Windows (Güvenlik Duvarı|Firewall)$|^Ayarlar › Sistem › Uzaktan Oynama( › Cihazı Eşleştir)?$')
# Donanım, ağ bağdaştırıcısı ve cihaz modeli adları (üreticinin koyduğu ad).
HARDWARE = re.compile(
    r'^Realtek |^Intel\(R\) |^Killer\(R\) |^Qualcomm |^MediaTek |^Broadcom |^(Reading )?Elgato |^AVerMedia |'
    r'^Live Gamer |^Cam Link|^Integrated HDMI Capture$|^USB Video|^WireGuard Tunnel$|^TAP-Windows|^Hyper-V Virtual|'
    r'^VirtualBox Host-Only|^VMware |NVIDIA CUDA|^GeForce |^Radeon |^LENOVO |^HP Pavilion |^Dell |^ASUS |^Acer |'
    r'^MSI |^Microphone \(Realtek|^\[TV\] Samsung [A-Z]{2}\d|^Samsung [A-Z]{2}\d|^Xbox Series [XS]( · [\w ]+)?$|^Xbox Series / Xbox One|'
    r'^Anynet\+ \(HDMI-CEC\)$|^(Reading )?PS Remote Play$|'
    # Windows yazı tipi adları ve dil adları (işletim sisteminin/dilin kendi adı)
    r'^Segoe [\w ,]+$|^Bahasa (Indonesia|Melayu)$|'
    # BIOS/SMBIOS yer tutucuları (üreticinin boş bıraktığı alanlar)
    r'^to be filled by o\.?e\.?m\.?$|^Default string$', re.I)
# Tek sözcüklü, kısa ya da ürün adlarından oluşan arayüz değerleri (Windows, Remote Play, Xbox …) sıradan addır.
PRODUCT = re.compile(r'^(Nino|Windows|Remote Play|PlayStation|PS5|PS4|Xbox|Google TV|Android TV|LG webOS|'
                     r'Samsung Tizen|DeepL|Gemini|Groq|OpenAI|Claude|OPUS-MT|chiaki-ng|Greenlight|PSN)'
                     r'( (One|Pro|Network|Series [XS]|\d[\w.-]*))?'
                     # ürün adı + tek bir betimleyici ad (kaynağın, pencerenin adı; ileti değil)
                     r'( (penceresi|uygulaması|görüntüsü|bağlantısı|hesabı|kaynağı|window|app|picture|account))?$')


def category(s, src):
    if not TITLE_KEYS:
        TITLE_KEYS.update(title_key(t) for t in TITLES)
        TITLE_KEYS.update(title_key(t).replace('call of duty', 'cod') for t in TITLES)
        TITLE_KEYS.update(title_key(t).replace('the ', '', 1) for t in TITLES if t.lower().startswith('the '))
    if title_key(s) in TITLE_KEYS or s.strip().rstrip('™®') in TITLES:
        return 'genel'
    low = s.replace('İ', 'i').replace('I', 'ı' if re.search('[çğıöşü]', s) else 'i').lower()
    if s.lower() in COMMON or low in COMMON:
        return 'genel'
    if src == {'glossary'}:
        return 'sozluk'
    if any(x.startswith('veri:') for x in src) and not (src & {'oldtest', 'ui', 'oldsrc'}):
        if s in TITLES or ALLOW_RE.search(s):
            return 'genel'
        return 'veri'
    if s in TITLES or ALLOW_RE.search(s) or ' ' not in s.strip() or PRODUCT.match(s.strip()):
        return 'genel'
    if EXTERNAL.search(s) or HARDWARE.search(s):
        return 'genel'
    bare = norm(re.sub(r'^(TR|EN|English|Türkçe): ', '', s))
    # GTA 6 ekranındaki sohbet: başta yalnız konuşanın adı olabilir (telefonda balonun üstünde yazar).
    if GTA.search(s.split(':', 1)[0]) and ':' in s:
        bare = norm(s.split(':', 1)[1])
    if len(bare) >= 8 and bare in GTA_TEXT:
        return 'gta6'
    # Ekranda araya başka satır girmiş bir cümle: parçaları ayrı .lines.txt satırları.
    if len(bare) >= 20:
        rest = bare
        for ln in GTA_LINES:
            if len(ln) >= 8 and ln in rest:
                rest = rest.replace(ln, '', 1)
        if len(rest) <= 3:
            return 'gta6'
    # Ekran karesi olup .lines.txt'si olmayan GTA 6 görüntülerindeki kısa etiketler (harita, telefon başlığı).
    # Ad geçen ama cümle olan satır oyun metni sayılmaz: eski testin cümlesi olabilir.
    if GTA.search(s) and len(s.split()) <= 4 and not re.search(r'[!?,.]', s):
        return 'gta6'
    if 'ui' in src:
        return 'arayuz'
    return 'metin'


SRC_TEXT = ''
for r, ds, fs in os.walk(os.path.join(APP, 'src')):
    ds[:] = [x for x in ds if x not in ('bin', 'obj')]
    SRC_TEXT += ''.join(open(os.path.join(r, f), encoding='utf-8', errors='ignore').read() for f in fs if f.endswith('.cs'))


def composed_by_src(s):
    # src'nin parçalardan kurduğu çıktı (ör. "a" + ad + ", b: " + değer): her sözcüğü src'de ayrı sözcük olarak
    # geçer ve en az bir 8 karakterlik parçası src'de aynen vardır.
    words = re.findall(r'[^\W\d_]{3,}', s)
    if not words or not all(re.search(r'(?<!\w)' + re.escape(w) + r'(?!\w)', SRC_TEXT) for w in words):
        return False
    return any(s[i:i + 8] in SRC_TEXT for i in range(0, max(1, len(s) - 7)) if re.search(r'\w{3}', s[i:i + 8]))


# temiz-oda.md'deki "İzinli kod dizgeleri" bölümü: her satır "- `<değer>`: <gerekçe>" (⏎ satır sonu yerine).
CODE_ALLOW_HEAD = '## İzinli kod dizgeleri'
CODE_ALLOW = set()
_doc = os.path.join(REPO, 'docs/yeni/windows/temiz-oda.md')


def code_allow_section(text):
    if CODE_ALLOW_HEAD not in text:
        return ''
    rest = text.split(CODE_ALLOW_HEAD, 1)[1]
    return rest.split('\n## ', 1)[0]


if os.path.exists(_doc):
    for _m in re.finditer(r'^- `([^`]+)`:', code_allow_section(open(_doc, encoding='utf-8').read()), re.M):
        CODE_ALLOW.add(_m.group(1).replace('⏎', '\n'))


def place(cat, rel, s=''):
    c = place_raw(cat, rel, s)
    if c in ('kod', 'kod-test') and s in CODE_ALLOW:
        return 'kod-izinli'
    return c


def place_raw(cat, rel, s=''):
    if cat not in FIXING:
        return cat
    if '/Fixtures/Compat/' in rel or '/Nino.Core.Tests/Compat/' in rel:
        return 'uyum'
    # Testin doğruladığı değer src'deki bir .cs dizgesinin kendisi ya da parçası: src düzelince test de değişir.
    if rel.startswith('apps/windows/tests/') and s and (s in SRC_TEXT or composed_by_src(s)):
        return 'kod-test'
    if rel.startswith('apps/windows/src/Nino.Core/Text/Catalog/'):
        return 'katalog'
    if rel.startswith('apps/windows/src/') and rel.endswith('.cs'):
        return 'kod'
    return cat


SKIP_DIRS = {'bin', 'obj', '.vs', 'node_modules'}
EXT = ('.cs', '.md', '.json', '.txt', '.xaml', '.py', '.ps1', '.sh', '.csproj', '.props', '.slnx', '.c', '.h',
       '.js', '.cjs', '.html')
new = []
for root in [APP, os.path.join(REPO, 'docs/yeni/windows')]:
    for r, ds, fs in os.walk(root):
        ds[:] = [x for x in ds if x not in SKIP_DIRS]
        for fn in fs:
            p = os.path.join(r, fn)
            if p == os.path.abspath(__file__) or fn.endswith('.lines.txt'):
                continue
            if ONLY and not any(os.path.relpath(p, REPO).startswith(o) for o in ONLY):
                continue
            if fn.endswith('.json.gz'):
                new.append((p, gzip.open(p).read().decode('utf-8', 'ignore')))
            elif fn.endswith('.md'):
                # Tarifler satır sonunda bölünür: boşluklar tek boşluğa indirilir ki bölünmüş cümle de bulunsun.
                # temiz-oda.md'nin izinli kod dizgeleri listesi taranmaz (değerler bilerek eskiyle aynıdır).
                text = open(p, encoding='utf-8', errors='ignore').read()
                if os.path.abspath(p) == os.path.abspath(_doc):
                    text = text.replace(code_allow_section(text), '')
                new.append((p, re.sub(r'\s+', ' ', text)))
            elif fn.endswith(EXT):
                new.append((p, open(p, encoding='utf-8', errors='ignore').read()))

out = []
for s, src in old.items():
    if len(s) < 4:
        continue
    gloss_only = src == {'glossary'}
    if gloss_only and (' ' in s or len(s) >= 8):
        pat = re.compile(r'(?<![\w])' + re.escape(s) + r'(?![\w])', re.I)
    else:
        pat = None
    for p, t in new:
        if pat is not None:
            hit = pat.search(t) is not None
        elif gloss_only and len(s) < MIN:
            hit = ('"%s"' % s) in t or ("'%s'" % s) in t
        else:
            hit = s in t
        if hit:
            out.append((place(category(s, src), os.path.relpath(p, REPO), s), ','.join(sorted(src)),
                        s.replace('\n', '⏎'), os.path.relpath(p, REPO)))

# ---- Metin kataloğu karşılaştırması (veri-dosyalari-karari.md, "Metin karşılaştırması") ----
# Yeni Text/Catalog/<dil>.json değerleri, eski metin dosyalarının (UI_FILES) aynı dildeki değerleriyle karşılaştırılır
# (İngilizcede eski anahtarlar da kaynak metindir). Büyük/küçük harf, noktalama ve yer tutucular normalize edilir.
#   katalog-aynı   normalize hâli ≥12 karakter ve eski bir değerle aynı
#   katalog-4gram  eski bir değerle dört sözcüklük ardışık ortak dizi (Tay dilinde sözcük arası boşluk yok:
#                  boşluksuz 20 harflik ortak dizi, yaklaşık dört sözcük)
#   katalog-izinli docs/yeni/windows/temiz-oda.md "Kalan olgu ve adlar" listesindeki anahtar (zorunlu ad, marka)
import unicodedata

PLACEHOLDER = re.compile(r'%(\d+\$)?(lld|ld|d|@|s|f)|\{\d+\}')


def cnorm(t):
    t = PLACEHOLDER.sub(' § ', t).casefold()
    t = ''.join(' ' if unicodedata.category(ch)[0] in 'PSZC' and ch != '§' else ch for ch in t)
    return ' '.join(t.split())


def grams(t, lang):
    if lang == 'th':
        # Tay dili sözcük arasına boşluk koymaz; dört sözcük ortalama 16–24 harf eder: 20 harflik boşluksuz pencere.
        t = t.replace(' ', '')
        return {t[i:i + 20] for i in range(len(t) - 19)}
    w = [x for x in t.split() if x != '§']
    return {' '.join(w[i:i + 4]) for i in range(len(w) - 3)}


def catalog_compare():
    oldv = {}
    for rel in UI_FILES:
        d = json.load(open(os.path.join(REPO, rel), encoding='utf-8'))
        for key, entry in d.get('strings', {}).items():
            oldv.setdefault('en', set()).add(key)
            for lang, loc in (entry.get('localizations') or {}).items():
                for v in leaves(loc):
                    if v not in ('translated', 'new', 'needs_review', 'stale'):
                        oldv.setdefault(lang, set()).add(v)
    allowed = set()
    doc = os.path.join(REPO, 'docs/yeni/windows/temiz-oda.md')
    if os.path.exists(doc):
        text = open(doc, encoding='utf-8').read()
        part = text.split('## Kalan olgu ve adlar', 1)[-1] if '## Kalan olgu ve adlar' in text else ''
        for m in re.finditer(r'^- `([a-z]{2,3}|\*)` `([\w.]+)`', part, re.M):
            allowed.add((m.group(1), m.group(2)))
    rows = []
    cdir = os.path.join(APP, 'src/Nino.Core/Text/Catalog')
    for fn in sorted(os.listdir(cdir)):
        lang = fn[:-5]
        if ONLY and not any(os.path.relpath(os.path.join(cdir, fn), REPO).startswith(o) for o in ONLY):
            continue
        olds = [cnorm(v) for v in oldv.get(lang, ())]
        oldset = {o for o in olds if len(o) >= 12}
        oldgrams = set()
        for o in olds:
            oldgrams |= grams(o, lang)
        for key, value in json.load(open(os.path.join(cdir, fn), encoding='utf-8')).items():
            n = cnorm(value)
            if len(n) >= 12 and n in oldset:
                kind, what = 'katalog-aynı', value
            else:
                common = sorted(grams(n, lang) & oldgrams)
                if not common:
                    continue
                kind, what = 'katalog-4gram', ' | '.join(common[:3])
            if (lang, key) in allowed or ('*', key) in allowed:
                kind = 'katalog-izinli'
            rows.append((kind, lang, key, what.replace('\n', '⏎')))
    return rows


CAT_FIXING = {'katalog-aynı', 'katalog-4gram'}
crows = catalog_compare()
for r in crows:
    if SHOW_ALL or r[0] in CAT_FIXING:
        print('\t'.join(r))
ccounts = Counter(r[0] for r in crows)
per_lang = Counter(r[1] for r in crows if r[0] in CAT_FIXING)
print('katalog karşılaştırması: ' + ', '.join('%s=%d' % kv for kv in sorted(ccounts.items())) +
      ('; dil başına: ' + ', '.join('%s=%d' % kv for kv in sorted(per_lang.items())) if per_lang else ''),
      file=sys.stderr)
cat_bad = sum(v for k, v in ccounts.items() if k in CAT_FIXING)

out.sort(key=lambda x: (x[0] not in FIXING, x[0], x[3], x[2]))
for o in out:
    if SHOW_ALL or o[0] in FIXING:
        print('\t'.join(o))
counts = Counter(o[0] for o in out)
print('kategori sayıları: ' + ', '.join('%s=%d' % kv for kv in sorted(counts.items())), file=sys.stderr)
bad = sum(v for k, v in counts.items() if k in FIXING)
print('düzeltilmeli: %d (katalog: %d)' % (bad, cat_bad), file=sys.stderr)
sys.exit(1 if bad or cat_bad else 0)
