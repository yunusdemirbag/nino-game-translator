#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Yeni ve eski Android strings.xml metinlerini karsilastirir.
Kullanim: metin_benzerlik.py <depo> [--min 25] [--lang tr,en] [--json cikti.json] [--quiet]

--min N   : N karakterden kisa metinler sayilmaz (varsayilan 25).
4-gram ortusme yalniz 25+ karakterlik metinlerde bakilir; 8-24 arasi icin yalniz birebir.
Kisa ve cok genel UI sozcukleri (GENEL listesi) birebir ayni kalabilir; ayri raporlanir.
"""
import sys, re, json, unicodedata
import xml.etree.ElementTree as ET

SKIPPED = []
LANGS = ['tr', 'en', 'ar', 'bn', 'hi', 'in', 'ms', 'nl', 'th', 'tl', 'b+fil', 'ur', 'vi']
def resdir(lang):
    return 'values' if lang == 'tr' else f'values-{lang}'

# Ayni kalabilen en cok uc sozcukluk genel UI sozcukleri, urun adlari, cihaz menu adlari.
# Anahtar: strings.xml'deki ad (dil bagimsiz). Yalniz 8-24 karakterlik metinlere uygulanir.
GENEL = {
    'settings', 'next', 'next_continue', 'selected', 'nino_interface',       # Ayarlar / Devam / Secili / Arayuz
    'packs_free', 'engine_free_short', 'nino_packs',                          # Ucretsiz / Paketler
    'capture_card', 'tvinstall_brand_android', 'tvinstall_android_mode_wireless',  # urun / cihaz menu adlari
    'home_connecting', 'subtitle_waiting', 'nino_connected', 'nino_waiting',  # Baglaniyor / Bagli / Bekleniyor
    'profile_not_paired', 'home_not_paired', 'profile_psn_missing', 'nino_net_offline',  # Bagli degil
    'update_row_download', 'app_update_button', 'settings_about',             # Indir / Guncelle / Hakkinda
    'history_copied', 'report_sending', 'extra_notification', 'area_height',  # Kopyalandi / Gonderiliyor / Bildirim / Yukseklik
    'assistant_screenshot', 'nino_net_cellular', 'device_info_system', 'settings_font',  # cihaz menu adlari
    'psn_retry', 'assistant_retry', 'tvinstall_retry',                        # Yeniden dene
    'home_full_screen', 'area_full', 'nino_fps',                              # Tam ekran / kare/sn
}

def load(path):
    out = {}
    root = ET.parse(path).getroot()
    for el in root:
        name = el.get('name')
        if el.get('translatable') == 'false':
            SKIPPED.append(name); continue
        if el.tag == 'string':
            out[name] = ''.join(el.itertext())
        elif el.tag == 'plurals':
            for it in el:
                out[f"{name}#{it.get('quantity')}"] = ''.join(it.itertext())
        elif el.tag == 'string-array':
            for i, it in enumerate(el):
                out[f"{name}[{i}]"] = ''.join(it.itertext())
    return out

def norm(s):
    s = s.replace('\\n', ' ').replace("\\'", "'").replace('\\"', '"')
    s = re.sub(r'%\d*\$?[sdf]', ' ', s)
    s = unicodedata.normalize('NFC', s).lower()
    s = s.replace('i̇', 'i')
    # Isaret (M*) ve bicim (Cf: ZWJ/ZWNJ) karakterleri korunur: Hint/Tay yazilarinda unlu isaretleri sozcugu bolmesin.
    s = ''.join(c if (c.isalnum() or c.isspace() or unicodedata.category(c)[0] == 'M' or unicodedata.category(c) == 'Cf') else ' ' for c in s)
    return ' '.join(s.split())

# Bosluksuz yazilan diller: sozcuk yerine 6 karakterlik parcalar karsilastirilir.
NOSPACE = {'th'}
def grams(s, n=4, lang=None):
    if lang in NOSPACE:
        t = norm(s).replace(' ', '')
        return {t[i:i+6] for i in range(len(t)-5)}
    w = norm(s).split()
    return {tuple(w[i:i+n]) for i in range(len(w)-n+1)}

def main():
    repo = sys.argv[1]
    mn = 25
    if '--min' in sys.argv: mn = int(sys.argv[sys.argv.index('--min')+1])
    jout = sys.argv[sys.argv.index('--json')+1] if '--json' in sys.argv else None
    result = {}
    langs = LANGS
    if '--lang' in sys.argv: langs = sys.argv[sys.argv.index('--lang')+1].split(',')
    quiet = '--quiet' in sys.argv
    table = []
    for lang in langs:
        d = resdir(lang)
        new = load(f"{repo}/apps/android/app/src/main/res/{d}/strings.xml")
        old = load(f"{repo}/nino-android/app/src/main/res/{d}/strings.xml")
        oldvals = list(old.values())
        oldset = set(oldvals)
        oldnorm = {norm(v) for v in oldvals}
        # Istisna anahtarlarin eski metinleri (cihaz menu adlari vb.) uzun metinlerin icinde gecebilir; sayilmaz.
        oldgenel = {old[k] for k in GENEL if k in old}
        oldgrams = [(v, grams(v, lang=lang)) for v in oldvals if v not in oldgenel]
        exact, normed, gram, genel = [], [], [], []
        for k, v in new.items():
            if len(v) < mn: continue
            short = len(v) < 25
            hit = v in oldset or norm(v) in oldnorm
            # Bosluksuz Tayca'da kisa sinir 40, hece hece yazilan Vietnamcada sozcuk siniri 4.
            kisa_genel = len(v) < (40 if lang in NOSPACE else 25)
            if kisa_genel and hit and k in GENEL and len(norm(v).split()) <= (4 if lang == 'vi' else 3):
                genel.append((k, v)); continue
            if v in oldset: exact.append((k, v)); continue
            if norm(v) in oldnorm: normed.append((k, v)); continue
            if short: continue
            g = grams(v, lang=lang)
            if not g: continue
            best, bo = 0, None
            for ov, og in oldgrams:
                if not og or (lang in NOSPACE and len(og) < 20): continue  # kisa eski metin her seye "uymasin"
                r = len(g & og) / min(len(g), len(og))
                if r > best: best, bo = r, ov
            if best >= 0.5: gram.append((k, v, round(best, 2), bo))
        result[lang] = {'exact': exact, 'norm': normed, 'gram': gram, 'genel': genel}
        table.append((lang, len(exact), len(normed), len(gram), len(genel)))
        print(f"== {lang}: birebir={len(exact)} normallestirilmis={len(normed)} 4gram>=%50={len(gram)} istisna={len(genel)}")
        if quiet: continue
        for k, v in genel: print(f"  [I] {k}: {v[:110]}")
        for k, v in exact: print(f"  [B] {k}: {v[:110]}")
        for k, v in normed: print(f"  [N] {k}: {v[:110]}")
        for k, v, r, o in gram: print(f"  [G {r}] {k}: {v[:110]}")
    print(f"   (translatable=false atlanan: {len(set(SKIPPED))})")
    print(f"   istisna listesi ({len(GENEL)} anahtar): {', '.join(sorted(GENEL))}")
    print("dil     birebir  norm  4gram  istisna")
    for l, a, b, c, e in table: print(f"{l:7} {a:7} {b:5} {c:6} {e:8}")
    if jout:
        json.dump(result, open(jout, 'w'), ensure_ascii=False, indent=1)

main()
