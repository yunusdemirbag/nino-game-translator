#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Yeni metin kataloğunu eski kataloglarla karşılaştırır: birebir eşleşme (12+ karakter) ve 4-gram (dört kelimelik)
örtüşme. Kelimeler boşluktan bölünür, noktalama atılır, küçük harfe çevrilir. Tek başına marka/ürün adı ve yer tutucu
içeren dört kelimelik gruplar sayılmaz.

    check-overlap.py <eski.xcstrings> [<eski2.xcstrings> ...]   → bulunanları JSON olarak yazar (stdout özet)
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUNCT = re.compile(r"^[\W_]+|[\W_]+$", re.UNICODE)


def words(text):
    out = []
    for w in text.lower().split():
        w = PUNCT.sub("", w)
        if w and not w.startswith("%"):
            out.append(w)
    return out


def grams(text):
    w = words(text)
    return {" ".join(w[i:i + 4]) for i in range(len(w) - 3)}


def main(paths):
    old_grams, old_exact = {}, {}
    for p in paths:
        for key, entry in json.loads(pathlib.Path(p).read_text())["strings"].items():
            values = [("en", key)] + [(l, u.get("stringUnit", {}).get("value")) for l, u in entry.get("localizations", {}).items()]
            for lang, value in values:
                if not value:
                    continue
                old_grams.setdefault(lang, set()).update(grams(value))
                if len(value) >= 12:
                    old_exact.setdefault(lang, set()).add(value)
    new = json.loads((ROOT / "Nino/Resources/Localizable.xcstrings").read_text())["strings"]
    hits = {}
    for key, entry in new.items():
        for lang, unit in entry["localizations"].items():
            value = unit["stringUnit"]["value"]
            found = sorted(grams(value) & old_grams.get(lang, set()))
            exact = value in old_exact.get(lang, set())
            if found or exact:
                hits.setdefault(key, {})[lang] = {"exact": exact, "grams": found}
    json.dump(hits, sys.stdout, ensure_ascii=False, indent=1)
    sys.stderr.write(f"{len(hits)} anahtarda örtüşme, {sum(len(h) for h in hits.values())} dil girdisi\n")


if __name__ == "__main__":
    main(sys.argv[1:])
