#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Nino.Core testlerinin ortak vektörlerini ve uygulamanın genel sözlüğünü üretir. C# kodundan bağımsız, yalnız
# tariflerden (docs/yeni/windows/havuz-paketler.md §1–§3, ceviri.md §3 ve §5) yazılmış ikinci bir başvuru
# uygulamasıdır: iki uygulama aynı sonucu vermezse biri tariften sapmıştır.
#
# Üretilenler:
#   tests/Nino.Core.Tests/Fixtures/golden-vectors.json   satır anahtarı (§1)
#   tests/Nino.Core.Tests/Fixtures/fuzzy-vectors.json    bulanık imza, benzerlik, bozuk etiket, eşikler (§2.4.1, §3)
#   tests/Nino.Core.Tests/Fixtures/pack-wrapped.json.gz  sarılı biçim 1 deneme paketi (§2.1)
#   tests/Nino.Core.Tests/Fixtures/pack-bare.json.gz     düz biçim deneme paketi (§2.1)
#   tests/Nino.Core.Tests/Fixtures/pack-sample.json.gz   biçim 2 deneme paketi: segments + fuzzy dizini (§2.1, §3.3)
#   tests/Nino.Core.Tests/Fixtures/pack-matches.json     pack-sample ile ekran okuması → beklenen sonuç (§2.4, §3)
#   src/Nino.Core/Resources/glossary-en-tr.json          genel sözlük (ceviri.md §5.6 biçimi)
#
# Kullanım: python3 apps/windows/tools/gen-vectors.py   (çıktı her çalıştırmada bayt bayt aynıdır)
# Bütün cümleler ve çeviriler bu dosya için yazıldı; hiçbir oyundan alınmadı.

import gzip
import hashlib
import io
import json
import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES = os.path.join(ROOT, "tests", "Nino.Core.Tests", "Fixtures")
GLOSSARY_PATH = os.path.join(ROOT, "src", "Nino.Core", "Resources", "glossary-en-tr.json")

# ---------------------------------------------------------------------------------------------------------------------
# §1 Satır anahtarı
# ---------------------------------------------------------------------------------------------------------------------


def strip_tags(text, replacement):
    """§1.1 adım 1: '<' + en çok 40 kod noktası ('<' ve '>' olmadan) + '>' → replacement."""
    if "<" not in text:
        return text
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "<":
            end = None
            for inner in range(0, 41):
                j = i + 1 + inner
                if j >= n:
                    break
                if text[j] == ">":
                    end = j
                    break
                if text[j] == "<":
                    break
            if end is not None:
                out.append(replacement)
                i = end + 1
                continue
        out.append(c)
        i += 1
    return "".join(out)


KEEP_CATEGORIES = {"Lu", "Ll", "Lt", "Lm", "Lo", "Nd", "Nl", "No"}
DROP_CATEGORIES = {"Mn", "Mc", "Me"}


def canon(text):
    s = strip_tags(text, " ")
    s = unicodedata.normalize("NFKC", s)
    s = s.replace("İ", "i̇")
    s = s.lower()
    s = unicodedata.normalize("NFD", s)
    out = []
    pending = False
    for c in s:
        cat = unicodedata.category(c)
        if cat in DROP_CATEGORIES:
            continue
        if cat in KEEP_CATEGORIES:
            if pending and out:
                out.append(" ")
            pending = False
            out.append(c)
        else:
            pending = True
    return "".join(out)


def hash_canon(c):
    return hashlib.sha256(c.encode("utf-8")).digest()[:8].hex()


def line_key(text):
    c = canon(text)
    return hash_canon(c) if c else None


# ---------------------------------------------------------------------------------------------------------------------
# §3.2 Katlama, imza, Bloom; §3.4 benzerlik, OCR izi, eşikler
# ---------------------------------------------------------------------------------------------------------------------

FOLD_MAP = {"l": "i", "1": "i", "ı": "i", "j": "i", "0": "o", "5": "s",
            "æ": "a", "ø": "o", "œ": "o", "ß": "s"}
MIN_LENGTH = 16
MARGIN = 5


def fold(text):
    return "".join(FOLD_MAP.get(c, c) for c in canon(text) if c != " ")


def bits_for(length):
    bits = 64
    while bits < 256 and length * 3 > bits:
        bits *= 2
    return bits


def trigrams(folded):
    seen = []
    have = set()
    for i in range(len(folded) - 2):
        h = 0xcbf29ce484222325
        for b in folded[i:i + 3].encode("utf-8"):
            h ^= b
            h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
        if h not in have:
            have.add(h)
            seen.append(h)
    return seen


def bloom(hashes, bits):
    words = [0] * (bits // 64)
    for h in hashes:
        b = h & (bits - 1)
        words[b >> 6] |= 1 << (b & 63)
    return words


def bloom_bytes(words):
    return b"".join(w.to_bytes(8, "little") for w in words)


def signature(text):
    """(L, bits, words) ya da None."""
    f = fold(text)
    if len(f) < MIN_LENGTH:
        return None
    length = min(len(f), 255)
    bits = bits_for(length)
    return length, bits, bloom(trigrams(f), bits)


def popcount(words):
    return sum(bin(w).count("1") for w in words)


def common_bits(a, b):
    return sum(bin(x & y).count("1") for x, y in zip(a, b))


def coverages(query, entry):
    """(sorgunun kapsanması, adayın kapsanması)."""
    bits = len(query) * 64
    s, a = popcount(query), popcount(entry)
    if s == 0 or a == 0:
        return 0.0, 0.0
    ds, da = s / bits, a / bits
    if ds >= 1 or da >= 1:
        return 0.0, 0.0
    common = common_bits(query, entry)
    return 100 * ((common / s - da) / (1 - da)), 100 * ((common / a - ds) / (1 - ds))


def similarity(query, entry):
    return min(coverages(query, entry))


TYPOGRAPHIC = set("’‘“”—–…")
WORD_TRIM = set(".,!?;:'\"()[]-…“”’‘")


def is_letter(c):
    return unicodedata.category(c).startswith("L")


def is_digit(c):
    return ord(c) <= 0xFFFF and unicodedata.decimal(c, None) is not None


def looks_damaged(text):
    for c in text:
        if ord(c) > 127 and c not in TYPOGRAPHIC:
            return True
    for raw in text.split():
        start, end = 0, len(raw)
        while start < end and raw[start] in WORD_TRIM:
            start += 1
        while end > start and raw[end - 1] in WORD_TRIM:
            end -= 1
        w = raw[start:end]
        if not w:
            continue
        if len(w) > 14:
            return True
        if len(w) == 1 and is_letter(w) and w not in "aAIoO":
            return True
        for i, c in enumerate(w):
            if 0 < i < len(w) - 1 and not is_letter(c) and c not in "'’-" \
                    and is_letter(w[i - 1]) and is_letter(w[i + 1]):
                return True
            if i > 0:
                p = w[i - 1]
                if (is_letter(p) and is_digit(c)) or (is_digit(p) and is_letter(c)):
                    return True
    return False


THRESHOLDS = {"clean": [[24, 90], [256, 80]], "damaged": [[24, 70], [40, 60], [256, 55]]}


def threshold(length, damaged):
    for below, value in THRESHOLDS["damaged" if damaged else "clean"]:
        if length < below:
            return float(value)
    return float(THRESHOLDS["damaged" if damaged else "clean"][-1][1])


# ---------------------------------------------------------------------------------------------------------------------
# §2.4.1 Bozuk konuşmacı etiketi, köşe yazısı
# ---------------------------------------------------------------------------------------------------------------------


def name_like(word, min_letters):
    letters = [c for c in word if is_letter(c)]
    return len(letters) >= min_letters and not any(unicodedata.category(c) == "Ll" for c in letters)


def loose_label(text):
    n = len(text)
    for i in range(1, min(n, 33)):
        if text[i] not in ":•":
            continue
        words = text[:i].split()
        if not words or not name_like(words[-1], 1):
            continue
        j = i + 1
        while j < n and not (is_letter(text[j]) or is_digit(text[j])):
            j += 1
        body = text[j:].strip()
        if not any(is_letter(c) for c in body):
            return None
        return text[:i + 1].strip() + " ", body
    pos = 0
    while pos < n and not is_letter(text[pos]):
        pos += 1
    for _ in range(3):
        end = text.find(" ", pos)
        if end < 0:
            return None
        word = text[pos:end]
        if not word or unicodedata.category(word[0]) != "Lu" or not name_like(word, 2):
            return None
        pos = end
        while pos < n and text[pos] == " ":
            pos += 1
        if pos + 1 < n and unicodedata.category(text[pos]) == "Lu" and unicodedata.category(text[pos + 1]) == "Ll":
            return text[:pos].strip() + " ", text[pos:].strip()
    return None


def corner_word(w):
    return w != "" and unicodedata.category(w[0]) == "Lu" and all(is_letter(c) or is_digit(c) for c in w)


def is_corner_text(line):
    words = [w for w in line.split(" ") if w]
    if not 1 <= len(words) <= 4:
        return False
    return "•" in line or all(corner_word(w) for w in words)


# ---------------------------------------------------------------------------------------------------------------------
# ceviri.md §3 Altyazı bölücüsü (yalnız paket araması için gereken kadar)
# ---------------------------------------------------------------------------------------------------------------------

NOT_NAMES = set("note warning tip hint objective objectives quest goal new reward rewards location chapter mission task "
                "tutorial update info status level controls press hold tap remember example question answer result "
                "results time listen look wait okay ok well so yes no now then and but".split())
CAPS_CHARS = set("'’.-")
DASHES = set("-–—")


def _caps_word(w, first):
    if not w or unicodedata.category(w[0]) != "Lu":
        return False
    if first and len(w) < 2:
        return False
    return all(unicodedata.category(c) == "Lu" or is_digit(c) or c in CAPS_CHARS for c in w[1:])


def _title_word(w, first):
    if not w or unicodedata.category(w[0]) != "Lu":
        return False
    rest = w[1:]
    if first and (not rest or unicodedata.category(rest[0]) != "Ll"):
        return False
    return all(is_letter(c) or c in CAPS_CHARS for c in rest)


def speaker_label(text):
    """Baştaki 'ad: ' etiketi (ad + ':' + tek boşluk) ya da None. Metin boşlukları teklenmiş olmalı."""
    colon = text.find(":")
    if colon <= 0 or colon + 1 >= len(text) or text[colon + 1] != " ":
        return None
    name = text[:colon]
    words = name.split(" ")
    if not 1 <= len(words) <= 3 or any(w == "" for w in words):
        return None
    ok = all(_caps_word(w, i == 0) for i, w in enumerate(words)) or \
        all(_title_word(w, i == 0) for i, w in enumerate(words))
    if not ok:
        return None
    if len(words) == 1 and name.lower() in NOT_NAMES:
        return None
    return name + ": "


ENDERS = set(".!?…")
CLOSERS = set("\"'”’)]")
ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "mt", "vs", "etc", "e.g", "i.e", "lt", "sgt",
                 "capt", "gen", "col"}


def _sentences(block):
    out = []
    start = 0
    i, n = 0, len(block)
    while i < n:
        if block[i] in ENDERS:
            j = i
            while j < n and block[j] in ENDERS:
                j += 1
            while j < n and block[j] in CLOSERS:
                j += 1
            if j < n and block[j] == " ":
                k = j
                while k < n and block[k] == " ":
                    k += 1
                cut = True
                if k < n and unicodedata.category(block[k]) == "Ll":
                    cut = False
                head = block[start:j]
                if cut and head.endswith("."):
                    last = head.split(" ")[-1][:-1]
                    if (len(last) == 1 and unicodedata.category(last) == "Lu") or last.lower() in ABBREVIATIONS:
                        cut = False
                if cut and k < n:
                    out.append(block[start:j])
                    start = k
                i = k
                continue
            i = j
            continue
        i += 1
    out.append(block[start:])
    return [s for s in out if s]


def split_subtitle(text):
    """[(metin, çevrilecek mi)] parçaları."""
    lines = [l.strip() for l in text.replace("\r\n", "\n").split("\n")]
    lines = [l for l in lines if l]
    blocks = []
    for line in lines:
        collapsed = " ".join(line.split())
        starts = speaker_label(collapsed) is not None or collapsed[0] in DASHES
        if starts or not blocks:
            blocks.append(collapsed)
        else:
            blocks[-1] = blocks[-1] + " " + collapsed
    pieces = []
    for bi, block in enumerate(blocks):
        if bi > 0:
            pieces.append(("\n", False))
        block = " ".join(block.split())
        if block and block[0] in DASHES:
            d = 0
            while d < len(block) and block[d] in DASHES:
                d += 1
            pieces.append((block[:d] + " ", False))
            block = block[d:].lstrip(" ")
        for si, sentence in enumerate(_sentences(block)):
            if si > 0:
                pieces.append((" ", False))
            label = speaker_label(sentence)
            body = sentence
            if label is not None:
                pieces.append((label, False))
                body = sentence[len(label):]
            if body:
                pieces.append((body, any(is_letter(c) for c in body)))
    return pieces


# ---------------------------------------------------------------------------------------------------------------------
# §3.6 Yan cümleler
# ---------------------------------------------------------------------------------------------------------------------

CLAUSE_MARKS = set(".!?…,;:")
SOFT_MARKS = set(",;:…")


def split_clauses(text):
    parts = []
    start = 0
    i, n = 0, len(text)
    while i < n:
        if text[i] in CLAUSE_MARKS:
            j = i
            while j < n and text[j] in CLAUSE_MARKS:
                j += 1
            group = text[i:j]
            while j < n and text[j] in CLOSERS:
                j += 1
            end = j
            had_space = False
            while j < n and text[j] == " ":
                j += 1
                had_space = True
            soft = any(c in SOFT_MARKS for c in group)
            dots = group.count(".")
            if had_space and j < n and (soft or dots > 1 or unicodedata.category(text[j]) == "Lu"):
                parts.append(text[start:end])
                start = j
            i = j
            continue
        i += 1
    parts.append(text[start:])
    parts = [p.strip() for p in parts]
    parts = [p for p in parts if p]
    merged = []
    carry = None
    for p in parts:
        current = p if carry is None else carry + " " + p
        if len(fold(current)) < 6:
            carry = current
            continue
        merged.append(current)
        carry = None
    if carry is not None:
        if merged:
            merged[-1] = merged[-1] + " " + carry
        else:
            merged.append(carry)
    return merged


def _clause_options(parts):
    checked = []
    for idx, part in enumerate(parts):
        if is_corner_text(part):
            continue
        words = [w for w in part.split(" ") if w]
        options = [part]
        if idx == 0:
            for k in range(1, 4):
                if k < len(words) and all(corner_word(w) for w in words[:k]):
                    options.append(" ".join(words[k:]))
        if idx == len(parts) - 1:
            for k in range(1, 4):
                if k < len(words) and all(corner_word(w) for w in words[-k:]):
                    options.append(" ".join(words[:-k]))
        if any(len(fold(o)) < 6 for o in options):
            continue
        checked.append([trigrams(fold(o)) for o in options])
    return checked


def clauses_covered(query_text, entry_words):
    parts = split_clauses(query_text)
    if len(parts) < 2:
        return True
    bits = len(entry_words) * 64
    d = popcount(entry_words) / bits
    if d >= 1:
        return False
    for options in _clause_options(parts):
        passed = False
        for tri in options:
            ob = bloom(tri, bits)
            c = popcount(ob)
            if c == 0:
                passed = True
                break
            if 100 * ((common_bits(ob, entry_words) / c - d) / (1 - d)) >= 30:
                passed = True
                break
        if not passed:
            return False
    return True


# ---------------------------------------------------------------------------------------------------------------------
# §2–§3 Paket, kütüphane, arama
# ---------------------------------------------------------------------------------------------------------------------

CONFUSIONS = [("rn", "m"), ("m", "rn"), ("cl", "d"), ("d", "cl"), ("vv", "w"), ("ri", "n"), ("n", "ri"), ("li", "h"),
              ("l", "i"), ("i", "l"), ("1", "l"), ("1", "i"), ("0", "o"), ("5", "s"), ("j", "i"), ("c", "e"),
              ("e", "c"), ("a", "o"), ("o", "a"), ("h", "b"), ("b", "h"), ("f", "t"), ("t", "f"), ("u", "v"),
              ("v", "u"), ("y", "v"), ("v", "y"), ("q", "g"), ("g", "q")]


def clean_turkish(text):
    if "<" not in text:
        return text.strip()
    return " ".join(strip_tags(text, "").split()).strip()


class Pack:
    """Paketin bellekteki hâli; İngilizcesi bilinen anahtarlardan bulanık dizin kurar."""

    def __init__(self, pack_id, title, entries, segments, english, fuzzy=True):
        self.id, self.title = pack_id, title
        self.entries = {k: clean_turkish(v) for k, v in entries.items() if clean_turkish(v)}
        self.segments = {k: clean_turkish(v) for k, v in segments.items() if clean_turkish(v)}
        self.keys = sorted(set(entries) | set(segments), key=lambda k: int(k, 16))
        self.fuzzy = []
        if fuzzy:
            for k in self.keys:
                sig = signature(english[k])
                if sig is not None:
                    self.fuzzy.append((sig[0], int(k, 16), k, sig[2]))
            self.fuzzy.sort(key=lambda r: (r[0], r[1]))
        self.has_fuzzy = fuzzy
        self.english = english

    def own(self, key):
        return self.entries.get(key, self.segments.get(key))

    def fuzzy_json(self):
        mask = bytearray((len(self.keys) + 7) // 8)
        lengths = bytearray()
        blooms = bytearray()
        for i, k in enumerate(self.keys):
            sig = signature(self.english[k])
            if sig is None:
                continue
            mask[i >> 3] |= 1 << (i & 7)
            lengths.append(sig[0])
            blooms += bloom_bytes(sig[2])
        import base64
        return {"version": 1, "count": len(self.keys), "mask": base64.b64encode(bytes(mask)).decode(),
                "lengths": base64.b64encode(bytes(lengths)).decode(),
                "blooms": base64.b64encode(bytes(blooms)).decode()}


class Library:
    """Tek ya da birkaç paketin birleşimi; elle seçim yok (testlerde kullanılmıyor)."""

    def __init__(self, packs):
        self.packs = packs
        self.merged = {}
        for p in packs:
            self.merged.update(p.segments)
        for p in packs:
            self.merged.update(p.entries)
        self.scope = None

    def find_exact(self, text):
        key = line_key(text)
        if key is None or key not in self.merged:
            return None
        holders = [p for p in self.packs if key in p.keys]
        if len(holders) == 1:
            self.scope = holders[0]
        elif len(holders) > 1 and self.scope not in holders:
            self.scope = holders[0]
        return self.merged[key]

    def find_nearest(self, text):
        pack = self.scope
        if pack is None:
            return None
        found = single_edit(text, pack, self.merged.get)
        if found is not None:
            return found
        if not pack.has_fuzzy:
            return None
        key = nearest_key(text, pack, self.merged.get)
        return None if key is None else self.merged.get(key)

    def lookup(self, text):
        return pack_lookup(text, self.find_exact, self.find_nearest)


def single_edit(text, pack, turkish_of):
    c = canon(text)
    runes = list(c)
    if not 6 <= len(runes) <= 48:
        return None
    variants = set()
    for i in range(len(runes)):
        head = "".join(runes[:i])
        rest = "".join(runes[i:])
        for read, actual in CONFUSIONS:
            if rest.startswith(read):
                variants.add(head + actual + rest[len(read):])
        variants.add(head + "".join(runes[i + 1:]))
        if i > 0 and runes[i] != " " and runes[i - 1] != " ":
            variants.add(head + " " + rest)
    variants.discard(c)
    found = None
    for v in sorted(variants):
        if not v or v.startswith(" ") or v.endswith(" ") or "  " in v:
            continue
        k = hash_canon(v)
        if k not in pack.keys:
            continue
        t = turkish_of(k)
        if t is None:
            continue
        if found is None:
            found = t
        elif found != t:
            return None
    return found


def _select(cands, th, turkish_of):
    """(anahtar, belirsiz mi)."""
    if not cands:
        return None, False
    best = max(cands, key=lambda c: (c[0], c[1]))
    if best[0] < th:
        return None, False
    bt = turkish_of(best[2])
    for score, num, key in cands:
        if key != best[2] and score > best[0] - MARGIN and turkish_of(key) != bt:
            return None, True
    return best[2], False


def nearest_key(text, pack, turkish_of):
    f = fold(text)
    if len(f) < MIN_LENGTH or not pack.fuzzy:
        return None
    length = min(len(f), 255)
    th = threshold(length, looks_damaged(text))
    base = th - MARGIN
    tri = trigrams(f)
    qb = {b: bloom(tri, b) for b in (64, 128, 256)}
    near = []
    lo, hi = length - length // 4, min(255, length + length // 4)
    for (cl, num, key, words) in pack.fuzzy:
        if lo <= cl <= hi:
            q = qb[len(words) * 64]
            sim = similarity(q, words)
            if sim >= base:
                near.append((sim, num, key))
    key, ambiguous = _select(near, th, turkish_of)
    if key is not None:
        return key
    if ambiguous or length < 22:
        return None
    one_way = []
    lo2, hi2 = max(22, length * 11 // 20), min(255, length * 5 // 2)
    for (cl, num, key, words) in pack.fuzzy:
        if not lo2 <= cl <= hi2 or cl < 22 or cl == length:
            continue
        q = qb[len(words) * 64]
        common = common_bits(q, words)
        longer = cl > length
        short_pop = popcount(q) if longer else popcount(words)
        if common * 10 < 9 * short_pop:
            continue
        qcov, ccov = coverages(q, words)
        if longer:
            inner, outer, floor = qcov, ccov, 25
        else:
            inner, outer, floor = ccov, qcov, 55
        if inner < 90 or outer < floor or inner - 10 < base:
            continue
        if not longer and not clauses_covered(text, words):
            continue
        one_way.append((inner - 10, num, key))
    if not one_way:
        return None
    key, _ = _select(near + one_way, th, turkish_of)
    return key


def _single_line(text, find):
    pieces = split_subtitle(text)
    lead = 0
    while lead < len(pieces) and not pieces[lead][1]:
        lead += 1
    if 0 < lead < len(pieces) and not any(p[0] == "\n" for p in pieces):
        body = "".join(p[0] for p in pieces[lead:])
        t = find(body)
        if t is not None:
            return "".join(p[0] for p in pieces[:lead]) + t
    t = find(text)
    if t is not None:
        return t
    loose = loose_label(text)
    if loose is not None:
        t = find(loose[1])
        if t is not None:
            return loose[0] + t
    return None


def _stage(text, find):
    t = _single_line(text, find)
    if t is not None:
        return t
    lines = [l.strip() for l in text.replace("\r\n", "\n").split("\n")]
    lines = [l for l in lines if l]
    if len(lines) > 1:
        found = []
        failed = False
        for line in lines:
            t = _single_line(line, find)
            if t is not None:
                found.append(t)
            elif not is_corner_text(line):
                failed = True
                break
        if not failed and found:
            return "\n".join(found)
    pieces = split_subtitle(text)
    if sum(1 for p in pieces if p[1]) <= 1:
        return None
    out = []
    for piece, translatable in pieces:
        if not translatable:
            out.append(piece)
            continue
        t = find(piece)
        if t is None:
            return None
        out.append(t)
    return "".join(out)


def pack_lookup(text, exact, nearest):
    trimmed = text.strip()
    if not trimmed:
        return None
    t = _stage(trimmed, exact)
    if t is not None:
        return t
    memo = {}

    def exact_or_nearest(s):
        e = exact(s)
        if e is not None:
            return e
        if s not in memo:
            memo[s] = nearest(s)
        return memo[s]

    return _stage(trimmed, exact_or_nearest)


# ---------------------------------------------------------------------------------------------------------------------
# ceviri.md §5 Sözlük izi
# ---------------------------------------------------------------------------------------------------------------------


def _collapse(s):
    return " ".join(s.split())


def _line_key(s):
    s = _collapse(s.lower().replace("’", "'").replace("‘", "'"))
    start, end = 0, len(s)
    while start < end and not (is_letter(s[start]) or is_digit(s[start])):
        start += 1
    while end > start and not (is_letter(s[end - 1]) or is_digit(s[end - 1])):
        end -= 1
    return s[start:end]


def glossary_fingerprint(doc):
    terms = {}

    def add(english, turkish, exact):
        e, t = _collapse(english), _collapse(turkish)
        if not any(is_letter(c) for c in e) or not t or len(e.encode("utf-16-le")) // 2 > 80:
            return
        terms[e.lower()] = (t, exact)

    for e, t in doc.get("terms", {}).items():
        if isinstance(t, str):
            add(e, t, False)
    for e in doc.get("keep", []):
        if isinstance(e, str):
            add(e, e, False)
    for e in doc.get("keepExact", []):
        if isinstance(e, str):
            add(e, e, True)
    phrases = {k: v for k, v in doc.get("phrases", {}).items() if k and v}
    lines = {}
    for k, v in doc.get("lines", {}).items():
        lk, lv = _line_key(k), _collapse(v)
        if lk and lv:
            lines[lk] = lv
    data = []
    for e in sorted(terms):
        t, exact = terms[e]
        data.append(e + "\x01" + t + ("\x03" if exact else "") + "\x02")
    for k in sorted(phrases):
        data.append(k + "\x04" + phrases[k] + "\x05")
    for k in sorted(lines):
        data.append(k + "\x06" + lines[k] + "\x07")
    h = 2166136261
    for b in "".join(data).encode("utf-8"):
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return "g%08x" % h, len(terms)


# ---------------------------------------------------------------------------------------------------------------------
# Veri: kendi cümlelerimiz
# ---------------------------------------------------------------------------------------------------------------------

GOLDEN_INPUTS = [
    "Raise the drawbridge!",
    "It’s a trap, run!",
    "<b><c>DARK LANTERN</c></b> UNLOCKED",
    "Señor Álvarez… wait.",
    "  Who   left\nthe door open?  ",
    "Ｓａｖｅ　ｐｏｉｎｔ ７",
    "İzmir Harbor",
    "Æther straße",
    "...",
    "",
    "MARISOL: Raise the sails!",
    "“Fire!” — Duck!",
    "ﬁnal boss ﬂoor",
    "<" + "x" * 40 + ">Gate 3",
    "<" + "x" * 41 + ">",
    "<<b>>Run",
    "Naïve café, 2nd floor?!",
    "Level 99 ★ unlocked",
]

SIGNATURE_INPUTS = [
    "The lighthouse keeper said the storm would pass before the morning tide.",
    "MARISOL: The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.",
    "Hand me the brass compass.",
    "Ahoy, the n0rth pier is fIooded!",
    "We sail at first light.",
    "DOCKHAND: Ropes are•tight, captain.",
    "Café au lait for the whole crew.",
    "Ｌｏｗ ｔｉｄｅ ａｔ １０ ｐｍ",
    "Keep the l1ght burning 0n the c1iffs tonight!",
    "z" * 300,
    "tiny line",
    "Check the u hold below deck.",
    "The harbormastership is vacant again.",
    "ægir øster straße œuvre jjjj",
    "Short of rope.",
    "Down the stairs… then left — quickly!",
]

SIMILARITY_PAIRS = [
    (SIGNATURE_INPUTS[0], SIGNATURE_INPUTS[1], 256),
    (SIGNATURE_INPUTS[0], "Hand me the brass compass.", 64),
    ("Hand me the brasscompass.", "Hand me the brass compass.", 64),
    ("DOCKHAND: Ropes are•tight, captain.", "Ropes are tight, captain.", 64),
    ("Who left the lantern on?", "Who left the lanterns on?", 64),
    ("We sail at first light.", "We sail at last light.", 64),
]

LOOSE_LABEL_INPUTS = [
    "-MARISOL: Raise the sails",
    "K]: Is anyone on deck?",
    "ii TOMAS: easy now",
    "· rq„.. ODALYS: As I said, no",
    "BARTOLO Where is the cargo",
    "O'HARA Leave it here.",
    "He said: wait",
    "İNA DOCKHAND• Any news?",
    "-, • VERA: all hands",
    "Pull the rope!",
    "OK Fine",
    "CAPTAIN: ...",
]

# Biçim 1 sarılı deneme paketi (5 satır) ve düz biçim (2 satır; biri sarılıyla çakışır).
WRAPPED = [
    ("Raise the drawbridge!", "Köprüyü kaldır!"),
    ("Where did the caravan go?", "Kervan nereye gitti?"),
    ("<b><c>DARK LANTERN</c></b> UNLOCKED", "<b><c>KARANLIK FENER</c></b> AÇILDI"),
    ("The bridge is out, take the river path.", "Köprü yıkılmış, nehir yolundan git."),
    ("Who left the door open?", "Kapıyı kim açık bıraktı?"),
]
BARE = [
    ("Raise the drawbridge!", "Köprüyü hemen kaldır!"),
    ("Light the beacon!", "İşaret ateşini yak!"),
]

# Biçim 2 deneme paketi: kurgusal bir kıyı oyunu.
SAMPLE_ID, SAMPLE_TITLE = "lantern-coast", "Lantern Coast"
SAMPLE_ENTRIES = [
    ("Bring me the map.", "Haritayı bana getir."),
    ("I can't feel my hands.", "Ellerimi hissedemiyorum."),
    ("Hold the line!", "Hattı tutun!"),
    ("Light the lantern, quickly.", "Feneri yak, çabuk."),
    ("The tide is turning, we have to leave now.", "Gelgit dönüyor, hemen gitmeliyiz."),
    ("Nobody crosses the reef after dark.", "Karanlıktan sonra kimse resifi geçmez."),
    ("Marisol, take the wheel while I check the sails.", "Marisol, ben yelkenlere bakarken dümene geç."),
    ("You promised me a ship, not a rowing boat.", "Bana bir gemi söz vermiştin, kayık değil."),
    ("The lighthouse keeper said the storm would pass before the morning tide.",
     "Fener bekçisi fırtınanın sabah gelgitinden önce geçeceğini söyledi."),
    ("Every smuggler on this coast owes the harbor master a favor.",
     "Bu kıyıdaki her kaçakçının liman başkanına bir borcu var."),
    ("If the guards find the crates, we're all going to hang.", "Muhafızlar sandıkları bulursa hepimiz asılırız."),
    ("Keep your voice down, the walls have ears in this town.", "Sesini alçalt, bu kasabada duvarların kulağı var."),
    ("I sold my grandfather's watch to pay for this voyage.",
     "Bu yolculuğun parasını ödemek için dedemin saatini sattım."),
    ("Take the north road to the old mill.", "Eski değirmene kuzey yolundan git."),
    ("Take the south road to the old mill.", "Eski değirmene güney yolundan git."),
    ("We need more rope before the next storm.", "Bir sonraki fırtınadan önce daha fazla halat lazım."),
    ("The cannon is loaded and ready to fire.", "Top dolu ve ateşe hazır."),
    ("She left the island without saying goodbye.", "Adadan veda etmeden ayrıldı."),
    ("Who left the lantern on?", "Feneri kim açık bıraktı?"),
    ("Don't trust the man with the silver hook.", "Gümüş kancalı adama güvenme."),
    ("The fish market opens at dawn, so we sleep on the boat tonight.",
     "Balık pazarı şafakta açılıyor, bu gece teknede uyuyoruz."),
    ("My father built this lighthouse with his own hands.", "Babam bu feneri kendi elleriyle inşa etti."),
    ("There's a hidden cove behind the waterfall.", "Şelalenin arkasında gizli bir koy var."),
    ("Row faster, they're gaining on us!", "Daha hızlı kürek çek, bize yetişiyorlar!"),
    ("I told you the compass was broken.", "Sana pusulanın bozuk olduğunu söylemiştim."),
    ("Wake up, the harbor is on fire!", "Uyan, liman yanıyor!"),
    ("Pull the anchor and raise the main sail.", "Demiri çek ve ana yelkeni kaldır."),
    ("The old captain never returned from the fog.", "Yaşlı kaptan sisten hiç dönmedi."),
    ("If you see a green flare, run to the docks.", "Yeşil işaret fişeği görürsen iskeleye koş."),
    ("We trade salt for medicine with the mountain villages.", "Dağ köyleriyle tuz karşılığında ilaç takas ediyoruz."),
    ("Nobody remembers who built the sea wall.", "Dalgakıranı kimin yaptığını kimse hatırlamıyor."),
    ("This key opens the chest in the captain's cabin.", "Bu anahtar kaptan kamarasındaki sandığı açar."),
    ("Stay behind me and don't make a sound.", "Arkamda kal ve hiç ses çıkarma."),
    ("The storm took three boats last winter.", "Fırtına geçen kış üç tekneyi aldı."),
    ("I can smell the rain coming from the west.", "Batıdan gelen yağmurun kokusunu alabiliyorum."),
    ("Your brother owes me forty silver coins.", "Kardeşinin bana kırk gümüş borcu var."),
    ("We'll wait for the fog to lift before we sail.", "Yola çıkmadan önce sisin kalkmasını bekleyeceğiz."),
    ("Somebody cut the ropes on purpose.", "Biri halatları bilerek kesmiş."),
    ("The harbor master wants to see you in his office.", "Liman başkanı seni ofisinde görmek istiyor."),
    ("Tell the crew we leave at sunrise.", "Mürettebata gün doğarken çıkacağımızı söyle."),
    ("I've never seen the sea this calm.", "Denizi hiç bu kadar sakin görmemiştim."),
    ("Watch your step, the planks are rotten.", "Adımına dikkat et, tahtalar çürük."),
    ("The bell rings when a ship enters the bay.", "Körfeze bir gemi girince çan çalar."),
    ("Leave the cargo and save yourselves!", "Yükü bırakın ve kendinizi kurtarın!"),
    ("Hand me the brass compass.", "Pirinç pusulayı bana uzat."),
    ("We sail at first light.", "İlk ışıkla yola çıkıyoruz."),
    ("Ropes are tight, captain.", "Halatlar gergin, kaptan."),
    ("Marisol!", "Marisol!"),
    ("Get to the boats!", "Teknelere koşun!"),
    ("Close the shutters, the wind is picking up.", "Kepenkleri kapat, rüzgâr sertleşiyor."),
    ("The map shows a second entrance under the chapel.", "Harita şapelin altında ikinci bir giriş gösteriyor."),
    ("Look, the lights on the cliffs are signalling us.", "Bak, yamaçlardaki ışıklar bize işaret veriyor."),
    ("Nobody leaves the ship until the inspector is gone.", "Müfettiş gidene kadar kimse gemiden ayrılmıyor."),
    ("I think the cook is hiding something in the pantry.", "Bence aşçı kilerde bir şey saklıyor."),
    ("Bring the wounded below deck and keep them warm.", "Yaralıları güverte altına indirin ve sıcak tutun."),
]
# Biçim 2 parçaları: çok cümleli satırların cümleleri, Türkçesi İngilizcesiyle aynı satırlar.
SAMPLE_SEGMENTS = [
    ("Buon viaggio.", "Buon viaggio."),
    ("Run!", "Kaç!"),
    ("The tide is turning.", "Gelgit dönüyor."),
    ("Hold the line!", "Hattı koruyun!"),
]
# Anahtar kümesinde olup Türkçesi boş kalan satır (dizin sayısına girer, sözlüğe girmez).
SAMPLE_BLANK = ("Untranslated sailor chatter in the background.", "   ")


def sample_cases():
    """(ekran okuması, kurgu gereği beklenen sonuç) çiftleri. Beklenen sonuç başvuru uygulamasıyla da doğrulanır."""
    tr = dict(SAMPLE_ENTRIES)
    seg = dict(SAMPLE_SEGMENTS)
    return [
        # Tam: noktalama, büyük/küçük harf, boşluk, etiket, satır sonu.
        ("BRING ME THE MAP!!", tr["Bring me the map."]),
        ("  Hold   the\nline!  ", tr["Hold the line!"]),
        ("MARISOL: Bring me the map.", "MARISOL: " + tr["Bring me the map."]),
        ("- Bring me the map.\n- Who left the lantern on?",
         "- " + tr["Bring me the map."] + "\n- " + tr["Who left the lantern on?"]),
        ("Buon viaggio.", seg["Buon viaggio."]),
        ("Run! Get to the boats!", seg["Run!"] + " " + tr["Get to the boats!"]),
        ("TOMAS: Run! Get to the boats!", "TOMAS: " + seg["Run!"] + " " + tr["Get to the boats!"]),
        # Tek düzeltme (rn→m, kesme işaretsiz, fazladan harf, 1→l, sözcük bitişik).
        ("Bring rne the map.", tr["Bring me the map."]),
        ("I cant feel my hands.", tr["I can't feel my hands."]),
        ("Who left thee lantern on?", tr["Who left the lantern on?"]),
        ("Who 1eft the lantern on?", tr["Who left the lantern on?"]),
        ("Hand me the brasscompass.", tr["Hand me the brass compass."]),
        ("Get to the boatz!", None),
        # Bloom: birden çok OCR hatası.
        ("The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.",
         tr["The lighthouse keeper said the storm would pass before the morning tide."]),
        ("MARISOL: The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.",
         "MARISOL: " + tr["The lighthouse keeper said the storm would pass before the morning tide."]),
        ("Every smugg1er on thls coast owes the harb0r master a fav0r.",
         tr["Every smuggler on this coast owes the harbor master a favor."]),
        ("If the guards f1nd the crates, were all go1ng to hang.",
         tr["If the guards find the crates, we're all going to hang."]),
        ("Keep yovr voice d0wn, the walIs have ears in thls town.",
         tr["Keep your voice down, the walls have ears in this town."]),
        ("I so1d my grandfathers watch to pay f0r this voyage.",
         tr["I sold my grandfather's watch to pay for this voyage."]),
        ("The flsh market opens at dawn, so we sleep 0n the boat tonlght.",
         tr["The fish market opens at dawn, so we sleep on the boat tonight."]),
        ("We trade sa1t for medicine with the mountaln vi1lages.",
         tr["We trade salt for medicine with the mountain villages."]),
        ("Marisol, take the whee1 whi1e I check the saiIs.",
         tr["Marisol, take the wheel while I check the sails."]),
        ("You promlsed me a shlp, not a rowlng boat.", tr["You promised me a ship, not a rowing boat."]),
        ("The harb0r master wants to see y0u in hls office.",
         tr["The harbor master wants to see you in his office."]),
        ("Bring the w0unded below deck and keep them wam.",
         tr["Bring the wounded below deck and keep them warm."]),
        ("I thlnk the cook is hidlng somethlng in the pantry.",
         tr["I think the cook is hiding something in the pantry."]),
        ("The map shows a sec0nd entrance under the chape1.",
         tr["The map shows a second entrance under the chapel."]),
        # Bozuk etiket + Bloom.
        ("-ODALYS: Every smugg1er on thls coast owes the harb0r master a fav0r.",
         "- ODALYS: " + tr["Every smuggler on this coast owes the harbor master a favor."]),
        ("K]: Nobody crosses the reef after dark.", "K]: " + tr["Nobody crosses the reef after dark."]),
        ("ii TOMAS: Wake up, the harbor is on fire!", "ii TOMAS: " + tr["Wake up, the harbor is on fire!"]),
        ("BARTOLO Tell the crew we leave at sunrise.", "BARTOLO " + tr["Tell the crew we leave at sunrise."]),
        # Yarım okunmuş (aday uzun).
        ("The lighthouse keeper said the storm would pass",
         tr["The lighthouse keeper said the storm would pass before the morning tide."]),
        ("Every smuggler on this coast owes the harbor",
         tr["Every smuggler on this coast owes the harbor master a favor."]),
        # Fazlalıklı okuma (aday kısa): köşe yazısı, çöp.
        ("Saltmarsh Docks Somebody cut the ropes on purpose.", tr["Somebody cut the ropes on purpose."]),
        ("Saltmarsh Docks\nSomebody cut the ropes on purpose.", tr["Somebody cut the ropes on purpose."]),
        ("Saltmarsh Docks\nBring me the map.", tr["Bring me the map."]),
        ("Bring me the map.\nFirst Mate • Tomas", tr["Bring me the map."]),
        ("Old Quarter West Gate Nobody remembers who built the sea wall.",
         tr["Nobody remembers who built the sea wall."]),
        # Yan cümle denetimi (§3.6): köşe yazısı yan cümlesi atlanır; baştaki büyük harfli sözcükler atılınca kısa
        # kalan yan cümle denetlenmez; adayda olmayan yan cümle eşleşmeyi düşürür.
        ("Somebody cut the ropes on purpose. Saltmarsh Docks", tr["Somebody cut the ropes on purpose."]),
        ("The storm took three boats last winter. North Pier", tr["The storm took three boats last winter."]),
        ("Tomas Vera Run! Somebody cut the ropes on purpose.", tr["Somebody cut the ropes on purpose."]),
        ("Somebody cut the ropes on purpose. Go now, Tomas.", None),
        ("Nobody remembers who built the sea wall, Tomas said.", None),
        ("The harbor master wants to see you in his office. Bring wine.", None),
        # Belirsiz: iki aday birbirine çok yakın, Türkçeleri farklı.
        ("Take the n0uth road to the old mill.", None),
        ("Take the road to the old mill.", None),
        # İki altyazı yan yana: yarım çeviri gösterilmez.
        ("Somebody cut the ropes on purpose. Tell the crew we leave at sunrise.",
         tr["Somebody cut the ropes on purpose."] + " " + tr["Tell the crew we leave at sunrise."]),
        ("Watch your step, the planks are rotten. I've never seen the sea this calm.",
         tr["Watch your step, the planks are rotten."] + " " + tr["I've never seen the sea this calm."]),
        ("The storm took three boats last winter. Your brother owes me ten silver coins.", None),
        # Bulunmaması gerekenler.
        ("Pack my box with five dozen jugs near the old pier.", None),
        ("Somewhere beyond the hills a wolf howls at the moon.", None),
        ("Bring me the sword.", None),
        ("The cannon is broken and ready to sink.", None),
        ("I can feel my hands.", None),
        ("Saltmarsh Docks", None),
        ("Bring me the map.\nWhere is the cook", None),
        ("...", None),
        ("", None),
    ]


# ---------------------------------------------------------------------------------------------------------------------
# Sözlük verisi (ceviri.md §5.6 biçimi; terimler bu proje için seçildi)
# ---------------------------------------------------------------------------------------------------------------------

GLOSSARY = {
    "game": "Genel",
    "terms": {
        "save point": "kayıt noktası",
        "fast travel": "hızlı yolculuk",
        "side quest": "yan görev",
        "skill tree": "beceri ağacı",
        "skill point": "beceri puanı",
        "skill points": "beceri puanları",
        "healing potion": "şifa iksiri",
        "healing potions": "şifa iksirleri",
        "mana potion": "mana iksiri",
        "boss fight": "boss savaşı",
        "hit points": "can puanı",
        "stamina bar": "dayanıklılık çubuğu",
        "crafting table": "üretim tezgâhı",
        "loot chest": "ganimet sandığı",
        "respawn point": "yeniden doğma noktası",
        "difficulty level": "zorluk seviyesi",
        "new game plus": "yeni oyun artı",
        "mini map": "mini harita",
        "waypoint": "yol işareti",
        "quick save": "hızlı kayıt",
        "auto save": "otomatik kayıt",
        "dodge roll": "kaçış yuvarlanması",
        "stealth kill": "sessiz infaz",
        "rocket launcher": "roket atar",
        "supply drop": "ikmal paketi",
        "grappling hook": "kancalı halat",
    },
    "keep": [],
    "keepExact": ["Raven"],
    "phrases": {
        "(?:drink|chug|pop|use) (?:a |some |the |your )?pots?(?! of)": "drink a healing potion",
        "(?:grab|snag) (?:the |all the )?loot": "collect the items",
        "rez me": "revive me",
        "mobs": "monsters",
        "aggro": "attention",
        "noobs": "beginners",
        "noob": "beginner",
        "brb": "be right back",
        "afk": "away from keyboard",
        "gg": "good game",
    },
    "lines": {
        "checkpoint reached": "Kontrol noktasına ulaşıldı",
        "game saved": "Oyun kaydedildi",
        "saving": "Kaydediliyor",
        "loading": "Yükleniyor",
        "mission complete": "Görev tamamlandı",
        "mission failed": "Görev başarısız",
        "quest updated": "Görev güncellendi",
        "objective updated": "Hedef güncellendi",
        "new objective": "Yeni hedef",
        "level up": "Seviye atladın",
        "you died": "Öldün",
        "try again": "Yeniden dene",
        "game over": "Oyun bitti",
        "victory": "Zafer",
        "defeat": "Yenilgi",
        "inventory full": "Envanter dolu",
        "item acquired": "Eşya alındı",
        "not enough gold": "Yeterli altın yok",
        "not enough mana": "Yeterli mana yok",
        "i'm out of potions": "İksirim kalmadı",
        "heal me": "Beni iyileştir",
        "i need healing": "İyileşmem lazım",
        "i need a medic": "Sıhhiye lazım",
        "watch out": "Dikkat et",
        "behind you": "Arkanda",
        "look out": "Dikkat",
        "over here": "Buraya",
        "this way": "Bu taraftan",
        "follow me": "Beni takip et",
        "let's go": "Hadi gidelim",
        "let's move": "Hadi ilerleyelim",
        "hurry up": "Acele et",
        "keep moving": "Durma, devam et",
        "hold on": "Bekle",
        "run for it": "Kaçın",
        "retreat": "Geri çekilin",
        "charge": "Saldırın",
        "they're coming": "Geliyorlar",
        "here they come": "İşte geliyorlar",
        "more enemies": "Daha fazla düşman",
        "enemy ahead": "Önde düşman",
        "ambush": "Pusu",
        "it's a trap": "Bu bir tuzak",
        "boss incoming": "Boss geliyor",
        "the boss is down": "Boss yenildi",
        "nice shot": "Güzel atış",
        "good job": "Aferin",
        "well done": "Aferin",
        "thanks for the help": "Yardımın için sağ ol",
        "i'm on it": "Hallediyorum",
        "on my way": "Geliyorum",
        "wait for me": "Beni bekle",
        "we did it": "Başardık",
        "area secured": "Bölge güvende",
        "all quiet": "Ortalık sakin",
        "out of arrows": "Ok kalmadı",
        "need arrows": "Ok lazım",
        "low health": "Can az",
        "shield's down": "Kalkan düştü",
        "open the gate": "Kapıyı aç",
        "close the gate": "Kapıyı kapat",
        "find the key": "Anahtarı bul",
    },
}


# ---------------------------------------------------------------------------------------------------------------------
# Yazma
# ---------------------------------------------------------------------------------------------------------------------


def dump_json(obj):
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def gz(data):
    buf = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buf, mtime=0) as f:
        f.write(data)
    return buf.getvalue()


def write(path, data):
    with open(path, "wb") as f:
        f.write(data)
    print("yazıldı:", os.path.relpath(path, ROOT), len(data), "bayt")


def compact(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def build_sample_pack():
    english = {}
    entries, segments = {}, {}
    for en, t in SAMPLE_ENTRIES + [SAMPLE_BLANK]:
        k = line_key(en)
        assert k not in entries, en
        english[k], entries[k] = en, t
    for en, t in SAMPLE_SEGMENTS:
        k = line_key(en)
        english.setdefault(k, en)
        segments[k] = t
    pack = Pack(SAMPLE_ID, SAMPLE_TITLE, entries, segments, english)
    doc = {"format": 2, "id": SAMPLE_ID, "title": SAMPLE_TITLE,
           "entries": dict(sorted(entries.items())), "segments": dict(sorted(segments.items())),
           "fuzzy": pack.fuzzy_json()}
    return pack, doc


def main():
    golden = []
    for text in GOLDEN_INPUTS:
        golden.append({"input": text, "canon": canon(text), "key": line_key(text)})
    write(os.path.join(FIXTURES, "golden-vectors.json"), dump_json(golden))

    sigs = []
    for text in SIGNATURE_INPUTS:
        sig = signature(text)
        sigs.append({"input": text, "folded": fold(text), "damaged": looks_damaged(text),
                     "length": None if sig is None else sig[0], "bits": None if sig is None else sig[1],
                     "bloom": None if sig is None else bloom_bytes(sig[2]).hex()})
    sims = []
    for q, e, bits in SIMILARITY_PAIRS:
        sims.append({"query": q, "entry": e, "bits": bits,
                     "similarity": similarity(bloom(trigrams(fold(q)), bits), bloom(trigrams(fold(e)), bits))})
    labels = []
    for text in LOOSE_LABEL_INPUTS:
        r = loose_label(text)
        labels.append({"input": text, "label": None if r is None else r[0], "body": None if r is None else r[1]})
    fuzzy = {"signatures": sigs, "similarities": sims, "looseLabels": labels,
             "thresholds": {"clean": THRESHOLDS["clean"], "damaged": THRESHOLDS["damaged"],
                            "margin": MARGIN, "minLength": MIN_LENGTH}}
    write(os.path.join(FIXTURES, "fuzzy-vectors.json"), dump_json(fuzzy))

    wrapped = {"format": 1, "id": "test-game", "title": "Test Game",
               "entries": {line_key(en): t for en, t in sorted(WRAPPED, key=lambda r: line_key(r[0]))}}
    write(os.path.join(FIXTURES, "pack-wrapped.json.gz"), gz(compact(wrapped)))
    bare = {line_key(en): t for en, t in sorted(BARE, key=lambda r: line_key(r[0]))}
    write(os.path.join(FIXTURES, "pack-bare.json.gz"), gz(compact(bare)))

    pack, doc = build_sample_pack()
    write(os.path.join(FIXTURES, "pack-sample.json.gz"), gz(compact(doc)))

    warm_up = "Light the lantern, quickly."
    lib = Library([pack])
    assert lib.lookup(SAMPLE_BLANK[0]) is None
    assert lib.lookup(warm_up) == dict(SAMPLE_ENTRIES)[warm_up]
    cases = []
    wrong = []
    for screen, intended in sample_cases():
        actual = lib.lookup(screen)
        if actual != intended:
            wrong.append((screen, intended, actual))
        cases.append({"screen": screen, "turkish": actual})
    if wrong:
        for screen, intended, actual in wrong:
            print("KURGUYLA UYUŞMUYOR:", repr(screen), "beklenen", repr(intended), "bulunan", repr(actual),
                  file=sys.stderr)
        sys.exit(1)
    write(os.path.join(FIXTURES, "pack-matches.json"),
          dump_json({"pack": "pack-sample.json.gz", "warmUp": warm_up, "cases": cases}))

    write(GLOSSARY_PATH, dump_json(GLOSSARY))
    fp, count = glossary_fingerprint(GLOSSARY)
    with open(GLOSSARY_PATH, "rb") as f:
        size = len(f.read())
    print("sözlük izi:", fp, "terim:", count, "bayt:", size)
    print("dizin: anahtar", len(pack.keys), "imzalı", len(pack.fuzzy))
    for en, _ in WRAPPED + BARE:
        print("anahtar:", line_key(en), en)


if __name__ == "__main__":
    main()
