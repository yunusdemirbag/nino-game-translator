#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Kullanıcıya görünen yeni Linux metinlerini (panel, komut satırı, hata iletileri, README) eski metinlerle karşılaştırır.

Eski: linux/Nino.Linux (panel + kod), windows/src (kod + Windows.xcstrings), mac/Nino/Resources/Localizable.xcstrings.
Ölçüt: birebir eşleşme (12+ karakter) ve dört sözcüklük örtüşme (4-gram). Bulunursa çıkış 1."""
import json, pathlib, re, sys

here = pathlib.Path(__file__).resolve().parent
root = here.parent.parent
QUOTED = [r"'((?:[^'\\\n]|\\.){4,})'", r'"((?:[^"\\\n]|\\.){4,})"', r"`((?:[^`\\]|\\.){4,})`"]


def quoted(text):
    for pattern in QUOTED:
        for m in re.finditer(pattern, text):
            yield m.group(1)


def catalog(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    for key, entry in data.get("strings", {}).items():
        yield key
        for loc in entry.get("localizations", {}).values():
            value = loc.get("stringUnit", {}).get("value")
            if value:
                yield value


def is_text(s):
    # Kullanıcı metni: en az iki sözcük ve harf içerir; kod parçası ya da yol değil.
    return len(re.findall(r"[^\W\d_]{2,}", s)) >= 2 and not re.search(r"[{};=]|=>|\(\)|/api/|\.cs$", s)


# Olgular: başkasının koyduğu adlar (PS5 menü yolu, LG uygulama ve ayar adları, ürün terimleri), dosya/ortam adları,
# HTTP adları. Karşılaştırmadan önce iki taraftan da çıkarılır; kalan liste docs/yeni/linux/ilerleme.md'de.
FACTS = [
    "Settings › System › Remote Play › Link Device", "Settings › System › Remote Play",
    "Ayarlar › Sistem › Uzaktan Oynatma › Cihaz Bağla", "Ayarlar › Sistem › Uzaktan Oynatma",
    "LG Content Store", "Developer Mode", "Dev Mode Status", "Key Server", "Host PC IP", "Claude Haiku",
    "API anahtarı", "API key", "TV uygulaması", "Content-Type", "application/json", "image/svg+xml",
    "[chiaki info]", "pool-translations", "settings.json", "remoteplay.log", "tvinstall.log",
]
FACT_RE = re.compile("|".join(re.escape(f) for f in sorted(FACTS, key=len, reverse=True)), re.I)


def scrub(s):
    s = FACT_RE.sub(" ", s)
    return re.sub(r"\bNINO_[A-Z_]+\b|\blibtesseract[\w.]*", " ", s)


def words(s):
    return re.findall(r"[^\W\d_]+", scrub(s).lower())


old = set()
for p in list((root / "linux/Nino.Linux").rglob("*")) + list((root / "windows/src").rglob("*.cs")):
    if p.is_file() and p.suffix in (".cs", ".html") and "bin" not in p.parts and "obj" not in p.parts:
        old.update(s for s in quoted(p.read_text(encoding="utf-8", errors="ignore")) if is_text(s))
for p in [root / "windows/src/Nino.Core/Resources/Windows.xcstrings", root / "mac/Nino/Resources/Localizable.xcstrings"]:
    old.update(s for s in catalog(p) if is_text(s))
old_grams = {}
for s in old:
    w = words(s)
    for i in range(len(w) - 3):
        old_grams.setdefault(tuple(w[i:i + 4]), s)

new = []
src = root / "apps/linux/src/Nino.Linux"
for p in sorted(src.rglob("*")):
    if p.is_file() and p.suffix in (".cs", ".html") and "bin" not in p.parts and "obj" not in p.parts:
        new += [(p, s) for s in quoted(p.read_text(encoding="utf-8")) if is_text(s)]
readme = root / "apps/linux/README.md"
new += [(readme, line) for line in readme.read_text(encoding="utf-8").splitlines() if is_text(line)]

hits = set()
for p, s in new:
    rel = p.relative_to(root)
    for o in old:
        o = scrub(o).strip()
        if len(o) >= 12 and o in scrub(s):
            hits.add(f"birebir  {rel}: {o}")
    w = words(s)
    for i in range(len(w) - 3):
        gram = tuple(w[i:i + 4])
        if gram in old_grams:
            hits.add(f"4-gram   {rel}: {' '.join(gram)}  ← {old_grams[gram][:70]}")
for h in sorted(hits):
    print(h)
print(f"{len(hits)} örtüşme", file=sys.stderr)
sys.exit(1 if hits else 0)
