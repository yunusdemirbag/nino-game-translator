#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Ekran metinleri kataloğunu denetler (Nino/Resources/Localizable.xcstrings).

- Koddaki her L("anahtar") katalogda olmalı.
- Her anahtarın 12 dilde çevirisi olmalı ve yer tutucuları İngilizcesiyle aynı olmalı.
- Kodda kullanılmayan anahtarlar listelenir.
Çıkış kodu: sorun varsa 1.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = ["en", "tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl"]
PH = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@)")


def placeholders(text):
    return sorted(re.sub(r"\d+\$", "", p) for p in PH.findall(text))


def main():
    catalog = json.loads((ROOT / "Nino/Resources/Localizable.xcstrings").read_text())["strings"]
    used = set()
    for f in (ROOT / "Nino").rglob("*.swift"):
        used |= set(re.findall(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', f.read_text()))
    problems = []
    for key in sorted(used - set(catalog)):
        problems.append(f"katalogda yok: {key}")
    for key, entry in catalog.items():
        loc = entry.get("localizations", {})
        en = loc.get("en", {}).get("stringUnit", {}).get("value")
        if en is None:
            problems.append(f"İngilizcesi yok: {key}")
            continue
        for lang in LANGS:
            value = loc.get(lang, {}).get("stringUnit", {}).get("value")
            if not value:
                problems.append(f"{lang} eksik: {key}")
            elif placeholders(value) != placeholders(en):
                problems.append(f"{lang} yer tutucu farklı: {key}")
    unused = sorted(set(catalog) - used)
    for p in problems:
        print(p)
    if unused:
        print(f"kullanılmayan {len(unused)} anahtar:", ", ".join(unused))
    print(f"{len(catalog)} anahtar, {len(problems)} sorun")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
