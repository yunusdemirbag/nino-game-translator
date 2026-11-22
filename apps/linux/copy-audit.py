#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Eski Linux kodu (linux/Nino.Linux) ile yeni kod (apps/linux/src) arasında ortak satır ve metin arar.

Ortak satır: boşlukları atılmış, 25 karakterden uzun aynı satır. Ortak metin: 12 karakterden uzun aynı tırnak içi
metin. Dış kaynağın dayattıkları (C arayüzü adları, rotalar, ortam değişkenleri, renkler) hariç tutulur.
Bulunursa çıkış 1."""
import pathlib, re, sys

here = pathlib.Path(__file__).resolve().parent
old = here.parent.parent / "linux" / "Nino.Linux"
new = here / "src"
if not old.exists():
    sys.exit(0)

ALLOWED = re.compile(r"(Tess[A-Za-z]+|\[LibraryImport|/api/|NINO_|--[a-z]|#[0-9A-Fa-f]{6}|libtesseract|application/|text/html|image/|SPDX|0xEDB88320|"
                     r"remoteplay\.dl\.playstation|InternalsVisibleTo|LogicalName|GetManifestResourceStream|<meta |<!doctype|"
                     # dil ve platform kalıpları
                     r"^\s*using |SetSynchronizationContext\(this\)|public override void (Send|Post)\(|static async Task<int> Main\(|"
                     r"Directory\.CreateDirectory\(|prefers-color-scheme|rel=\"icon\"|width=device-width|Content-Type|"
                     # veri ve sayfa sözleşmesi: dosya adları, adım ve durum adları, ürün adları
                     r"\.json$|\.log$|^\[chiaki info\]$|^(Welcome|SecondAccount|PsnLogin|Console|Tv|Translation|Test|BetterTranslation|Done)$|^Claude Haiku$|"
                     # sayfa sözleşmesindeki tek sözcüklük durum adları (KeyServerOff, NeedsPassphrase…)
                     r"^[A-Za-z]+$|^(Dev Mode Status|Developer Mode)$)")

def files(root, suffixes):
    return [p for p in root.rglob("*") if p.suffix in suffixes and "bin" not in p.parts and "obj" not in p.parts]

def lines(path):
    for raw in path.read_text(encoding="utf-8").splitlines():
        flat = re.sub(r"\s+", "", raw)
        if len(flat) >= 25 and not ALLOWED.search(raw):
            yield flat, raw.strip()

# HTML öznitelik parçaları (` aria-valuenow="`, `"><span class="`): sayfa yapısı, metin değil.
MARKUP = re.compile(r"""^[\s"'<>/]*([a-z-]+ ?)+=\s*$|^\s*>\s*<[a-z]+ [a-z-]+=\s*$""")


def literals(path):
    text = path.read_text(encoding="utf-8")
    # Tek ve çift tırnaklılar ayrı taranır: HTML şablonunda biri ötekinin içinde durur ve tek desen içtekini yutar.
    for pattern in (r"'((?:[^'\\\n]|\\.){12,})'", r"\"((?:[^\"\\\n]|\\.){12,})\""):
        for match in re.finditer(pattern, text):
            value = match.group(1)
            if not ALLOWED.search(value) and not MARKUP.search(value):
                yield value

kinds = {".cs", ".html"}
old_lines = {flat for p in files(old, kinds) for flat, _ in lines(p)}
old_literals = {v for p in files(old, kinds) for v in literals(p)}
hits = []
for p in files(new, kinds):
    for flat, raw in lines(p):
        if flat in old_lines:
            hits.append(f"satır  {p.relative_to(here)}: {raw}")
    for value in literals(p):
        if value in old_literals:
            hits.append(f"metin  {p.relative_to(here)}: {value}")
for hit in sorted(set(hits)):
    print(hit)
sys.exit(1 if hits else 0)
