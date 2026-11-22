# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Nino'nun kendi paket deneme verisini üretir (Kotlin kodundan bağımsız, yalnız ceviri.md 8.2 / 9.1 / 9.4 tarifinden).
# Çalıştırma: python3 -I make_fixtures.py  (çıktılar bu klasöre yazılır; gzip zaman damgası 0, çıktı sabittir)
import base64
import gzip
import hashlib
import io
import json
import os
import re
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
TAG = re.compile(r"<[^<>]{0,40}>")


def is_letter(ch):
    return unicodedata.category(ch).startswith("L")


def is_digit(ch):
    return unicodedata.category(ch) == "Nd"


def is_mark(ch):
    return unicodedata.category(ch) in ("Mn", "Mc", "Me")


# ---- 8.2 paket anahtarı ----

def canonical(text):
    s = TAG.sub(" ", text)
    s = unicodedata.normalize("NFKC", s)
    s = s.lower()
    s = unicodedata.normalize("NFD", s)
    out = []
    space = True
    for ch in s:
        if is_mark(ch):
            continue
        if is_letter(ch) or is_digit(ch):
            out.append(ch)
            space = False
        elif not space:
            out.append(" ")
            space = True
    r = "".join(out)
    return r[:-1] if r.endswith(" ") else r


def key_int(text):
    c = canonical(text)
    if not c:
        return None
    return int.from_bytes(hashlib.sha256(c.encode("utf-8")).digest()[:8], "big")


def key_hex(text):
    k = key_int(text)
    return None if k is None else "%016x" % k


# ---- 9.4 bulanık imza ----

FOLD = {"l": "i", "1": "i", "ı": "i", "j": "i", "0": "o", "5": "s", "æ": "a", "ø": "o", "œ": "o", "ß": "s"}


def fold(text):
    s = TAG.sub(" ", text)
    s = unicodedata.normalize("NFKC", s).lower()
    s = unicodedata.normalize("NFD", s)
    out = []
    for ch in s:
        if ch in FOLD:
            out.append(FOLD[ch])
        elif is_letter(ch):
            out.append(ch)
    return "".join(out)


def length_of(folded):
    return min(255, len(folded))


def bits_for(length):
    b = 64
    while length * 3 > b and b < 256:
        b *= 2
    return b


def fnv1a64(data):
    h = 0xCBF29CE484222325
    for x in data:
        h ^= x
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def bloom(folded, bits=None):
    if bits is None:
        bits = bits_for(length_of(folded))
    v = bytearray(bits // 8)
    for i in range(len(folded) - 2):
        b = fnv1a64(folded[i:i + 3].encode("utf-8")) % bits
        v[b // 8] |= 1 << (b % 8)
    return bytes(v)


def fold_to(bl, bits):
    n = bits // 8
    out = bytearray(n)
    for i, x in enumerate(bl):
        out[i % n] |= x
    return bytes(out)


def popcount(bl):
    return sum(bin(x).count("1") for x in bl)


def coverage(inter, x, y, bits):
    expected = x * y / bits
    d = x - expected
    if d <= 0:
        return 0.0
    return 100.0 * (inter - expected) / d


def similarity(a_text, b_text):
    a = bloom(fold(a_text))
    b = bloom(fold(b_text))
    bits = min(len(a), len(b)) * 8
    x = fold_to(a, bits)
    y = fold_to(b, bits)
    inter = popcount(bytes(p & q for p, q in zip(x, y)))
    px, py = popcount(x), popcount(y)
    return min(coverage(inter, px, py, bits), coverage(inter, py, px, bits))


# ---- deneme verisi (Nino'nun kendi satırları) ----

KEY_INPUTS = [
    "Hello there.",
    "Run.",
    "Run?",
    "  RUN!!  ",
    "Don’t move — I mean it.",
    "<i>Stay</i> <b>close</b>, kid.",
    "Café au lait, s'il vous plaît.",
    "İSTANBUL'a gidiyoruz, ışıklar sönük.",
    "ﬁnal ＡＲＥＮＡ 2049",
    "Level 3: The Docks",
    "...",
    "<br>",
    "",
    "Tab\there\nnew line",
    "Ağaç, çiçek, şehir, göl, üzüm.",
    "Naïve résumé, déjà vu.",
    "a < b and c > d",
]

SIGNATURE_INPUTS = [
    "We meet at the old lighthouse.",
    "Stay low, keep quiet.",
    "The harbor lights went out right after midnight, and nobody saw the boat leave.",
    "Wh0 left the 1antern by the d00r?",
    "Çok güzel bir gün, değil mi?",
    "Short line",
    "Straße, Æsir, Øresund, Œuvre — all folded letters here.",
    "<i>Whisper</i> softly, the guards are sleeping now.",
    "ﬁve ﬁsh ﬂoat in the ﬁord tonight",
    "GAETANO: Pass me the rope.",
    "x1y2z3 mixed readings everywhere",
]

SIMILARITY_PAIRS = [
    ("We meet at the old lighthouse tonight.", "We meet at the old lighthouse tonight."),
    ("We meet at the old lighthouse tonight.", "We rneet at the oId Iighthouse tonight."),
    ("The harbor lights went out right after midnight, and nobody saw the boat leave.",
     "The harb0r lights went out rigbt after midnigt, and nobudy saw the boat leave"),
    ("The harbor lights went out right after midnight, and nobody saw the boat leave.",
     "Purple elephants keep dancing in the warm summer rain."),
    ("Stay low, keep quiet and follow me.", "Stay low, keep quiet."),
]

# Paket A: biçim 2, tam satırlar + parçalar + bulanık imzalar.
HARBOR = {
    "id": "harbor-lights",
    "title": "Harbor Lights",
    "entries": [
        ("The harbor lights went out right after midnight, and nobody saw the boat leave.",
         "Liman ışıkları gece yarısından hemen sonra söndü ve kimse teknenin ayrıldığını görmedi."),
        ("We meet at the old lighthouse.", "Eski deniz fenerinde buluşuyoruz."),
        ("Stay low, keep quiet.", "Eğil ve sessiz ol."),
        ("Come here.", "Buraya gel."),
        ("Now!", "Hemen!"),
        ("Pass me the rope.", "Halatı uzat."),
        ("The tide is turning, we have to sail before the coast guard closes the bay.",
         "Gelgit dönüyor, sahil güvenlik koyu kapatmadan yola çıkmalıyız."),
    ],
    "segments": [
        ("Hold on tight.", "Sıkı tutun."),
        ("The fog is rolling in from the north and the engine sounds wrong.",
         "Sis kuzeyden geliyor ve motorun sesi hiç iyi değil."),
    ],
}

# Paket B: biçim 1 (havuz biçimi), bulanık imza yok.
GARDEN = {
    "id": "garden-of-ash",
    "title": "Garden of Ash",
    "entries": [
        ("The roots remember everything.", "Kökler her şeyi hatırlar."),
        ("Stay low, keep quiet.", "Alçal, ses çıkarma."),
        ("Light the brazier and wait for dawn.", "Mangalı yak ve şafağı bekle."),
    ],
}


def gz(data):
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, filename="") as f:
        f.write(data)
    return buf.getvalue()


def write_pack(spec, fmt, with_fuzzy):
    entries = {key_hex(en): tr for en, tr in spec["entries"]}
    segments = {key_hex(en): tr for en, tr in spec.get("segments", [])}
    body = {"format": fmt, "id": spec["id"], "title": spec["title"]}
    if fmt == 1:
        body["lang"] = "tr"
    body["entries"] = entries
    if segments:
        body["segments"] = segments
    if with_fuzzy:
        lines = spec["entries"] + spec.get("segments", [])
        by_key = {key_int(en): en for en, _ in lines}
        ordered = sorted(by_key)
        mask = bytearray((len(ordered) + 7) // 8)
        lengths = bytearray()
        blooms = bytearray()
        for i, k in enumerate(ordered):
            f = fold(by_key[k])
            n = length_of(f)
            if n < 16:
                continue
            mask[i // 8] |= 1 << (i % 8)
            lengths.append(n)
            blooms += bloom(f)
        b64 = lambda b: base64.b64encode(bytes(b)).decode("ascii")
        body["fuzzy"] = {"version": 1, "count": len(ordered), "mask": b64(mask), "lengths": b64(lengths), "blooms": b64(blooms)}
    data = json.dumps(body, ensure_ascii=False, indent=1).encode("utf-8")
    with open(os.path.join(HERE, spec["id"] + ".json.gz"), "wb") as f:
        f.write(gz(data))


def main():
    keys = [{"input": s, "canon": canonical(s), "key": key_hex(s) or ""} for s in KEY_INPUTS]
    sigs = []
    for s in SIGNATURE_INPUTS:
        f = fold(s)
        n = length_of(f)
        item = {"input": s, "folded": f}
        if n < 16:
            item["length"] = None
        else:
            item.update({"length": n, "bits": bits_for(n), "bloom": bloom(f).hex()})
        sigs.append(item)
    sims = [{"query": a, "entry": b, "similarity": similarity(a, b)} for a, b in SIMILARITY_PAIRS]
    with open(os.path.join(HERE, "key-vectors.json"), "w", encoding="utf-8") as f:
        json.dump(keys, f, ensure_ascii=False, indent=1)
        f.write("\n")
    with open(os.path.join(HERE, "fuzzy-vectors.json"), "w", encoding="utf-8") as f:
        json.dump({"signatures": sigs, "similarities": sims}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    write_pack(HARBOR, 2, True)
    write_pack(GARDEN, 1, False)


if __name__ == "__main__":
    main()
