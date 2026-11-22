#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Derlenmis siniflarda minSdk (26) uzerindeki Java/Android API cagrilarini bulur.
Lint, saf Kotlin :core icin NewApi denetimi yapmaz; bu betik bayt kodundan bakar.
Kullanim (JDK 17 javap PATH te): api-tarama.py ~/Library/Android/sdk/platforms/android-36/data/api-versions.xml 26 \
  core/build/classes/kotlin/main app/build/tmp/kotlin-classes/debug
Android API cikanlar SDK_INT korumali olmali; java/* cikan her satir eski telefonda cokme demektir.
"""
import sys, os, re, subprocess, xml.etree.ElementTree as ET
xmlp, minsdk, dirs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
root = ET.parse(xmlp).getroot()
classes = {}
for c in root.findall('class'):
    since = int(c.get('since', '1'))
    mem = {}
    for m in c:
        if m.tag in ('method', 'field'):
            mem[m.get('name')] = int(m.get('since', since))
    sup = [e.get('name') for e in c if e.tag in ('extends', 'implements')]
    classes[c.get('name')] = (since, mem, sup)
def lookup(cls, member, seen=None):
    seen = seen or set()
    if cls in seen or cls not in classes: return None
    seen.add(cls)
    since, mem, sup = classes[cls]
    if member in mem: return max(mem[member], since)
    for s in sup:
        r = lookup(s, member, seen)
        if r is not None: return r
    return None
files = [os.path.join(d, f) for dd in dirs for d, _, fs in os.walk(dd) for f in fs if f.endswith('.class')]
pat = re.compile(r'//\s*(Method|InterfaceMethod|Field|class)\s+("?)([\w/$\[;]+)"?(?:\.("?)([\w<>$]+)"?:(\S+))?')
hits = {}
for i in range(0, len(files), 200):
    out = subprocess.run(['javap', '-c', '-p'] + files[i:i+200], capture_output=True, text=True).stdout
    cur = None
    for line in out.splitlines():
        if line.startswith('Compiled from'): cur = line
        m = pat.search(line)
        if not m: continue
        kind, cls = m.group(1), m.group(3)
        if not re.match(r'(java|javax|android|org/json|org/xml|org/w3c)/', cls): continue
        if kind == 'class':
            c = cls.lstrip('[').removeprefix('L').rstrip(';')
            s = classes.get(c, (None,))[0]
            if s is None: key = (c, '<missing class>')
            elif s > minsdk: key = (c, f'class since {s}')
            else: continue
        else:
            name, desc = m.group(5), m.group(6)
            member = name + desc if kind != 'Field' else name
            if cls not in classes: key = (cls, f'{member} <missing class>')
            else:
                s = lookup(cls, member)
                if s is None: key = (cls, f'{member} <not found>')
                elif s > minsdk: key = (cls, f'{member} since {s}')
                else: continue
        hits.setdefault(key, set()).add(cur)
for (c, w), srcs in sorted(hits.items()):
    print(f'{c} {w}  <- {", ".join(sorted(s.replace("Compiled from ","") for s in srcs if s))[:200]}')
