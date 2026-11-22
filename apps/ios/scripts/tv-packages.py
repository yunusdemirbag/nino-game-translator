#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
"""Telefondan TV kurulumu için TV paketlerini hazırlayıp uygulama paketine koyar.

Kullanım: tv-packages.py <çıktı klasörü>   (Xcode derleme adımı; <çıktı>/tv/ altına yazar)

- nino-samsung.wgt ve nino-lg.ipk: ortak TV web uygulamasının (apps/tv-web) kendi paketleyicisi
  apps/tv-web/tools/package.py çalıştırılır, apps/tv-web/dist içindeki .wgt ve .ipk buraya kopyalanır.
  Samsung paketi imzasızdır; telefon kurarken TV'ye özel Samsung sertifikasıyla imzalar.
- nino-tv.apk: NINO_TV_APK ortam değişkeni bir APK gösteriyorsa, yoksa dist/tv-app/nino-androidtv_*.apk ya da
  apps/android-tv/app/build/outputs/apk altında bulunan ilk APK; paket kimliği com.ninotranslator.tv olmalı.
  Uygulama Android TV paketini normalde GitHub'daki son sürümden indirir.
İnternet gerekmez.
"""
import glob
import os
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TV_WEB = os.path.join(ROOT, "apps", "tv-web")
APP_ID = "com.ninotranslator.tv"


def read(path):
    with open(path, "rb") as f:
        return f.read()


def build_web_packages(out):
    """apps/tv-web paketleyicisini çalıştırır; (Samsung sürümü, LG sürümü) döner."""
    subprocess.run([sys.executable, os.path.join(TV_WEB, "tools", "package.py")], check=True,
                   stdout=subprocess.DEVNULL)
    dist = os.path.join(TV_WEB, "dist")

    def newest(pattern):
        found = sorted(glob.glob(os.path.join(dist, pattern)), key=os.path.getmtime, reverse=True)
        if not found:
            raise SystemExit(f"error: {dist} içinde {pattern} yok (apps/tv-web/tools/package.py çıktı vermedi)")
        return found[0]

    wgt = newest("nino-samsung_*.wgt")
    ipk = newest(f"{APP_ID}_*_all.ipk")
    shutil.copyfile(wgt, os.path.join(out, "nino-samsung.wgt"))
    shutil.copyfile(ipk, os.path.join(out, "nino-lg.ipk"))
    samsung = os.path.basename(wgt)[len("nino-samsung_"):-len(".wgt")]
    lg = os.path.basename(ipk)[len(APP_ID) + 1:-len("_all.ipk")]
    return samsung, lg


def apk_package(path):
    """İkili AndroidManifest.xml'den paket kimliği (yoksa None)."""
    try:
        data = zipfile.ZipFile(path).read("AndroidManifest.xml")
    except Exception:
        return None
    u16 = lambda o: struct.unpack_from("<H", data, o)[0]
    u32 = lambda o: struct.unpack_from("<I", data, o)[0]
    strings, p = [], 8
    while p + 8 <= len(data):
        kind, header, size = u16(p), u16(p + 2), u32(p + 4)
        if size == 0:
            break
        if kind == 0x0001:
            count, flags, start = u32(p + 8), u32(p + 16), u32(p + 20)
            for i in range(count):
                q = p + start + u32(p + header + 4 * i)
                if flags & 0x100:
                    q += 2 if data[q] & 0x80 else 1
                    n = data[q]
                    if n & 0x80:
                        n, q = ((n & 0x7F) << 8) | data[q + 1], q + 2
                    else:
                        q += 1
                    strings.append(data[q:q + n].decode("utf-8", "replace"))
                else:
                    n = u16(q)
                    strings.append(data[q + 2:q + 2 + 2 * n].decode("utf-16-le", "replace"))
        elif kind == 0x0102:
            body = p + header
            if strings[u32(body + 4)] == "manifest":
                start, step, count = u16(body + 8), u16(body + 10), u16(body + 12)
                for i in range(count):
                    a = body + start + i * step
                    if strings[u32(a + 4)] == "package":
                        raw = u32(a + 8)
                        return strings[raw] if raw != 0xFFFFFFFF else None
        p += size
    return None


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    out = os.path.join(sys.argv[1], "tv")
    os.makedirs(out, exist_ok=True)
    samsung, lg = build_web_packages(out)
    print("TV paketleri:", "Samsung", samsung, "· LG", lg)
    apk = os.environ.get("NINO_TV_APK")
    target = os.path.join(out, "nino-tv.apk")
    if not apk:
        # Xcode'dan derlerken ortam değişkeni gelmez: depodaki bilinen yerlere bakılır (kimliği doğru olan ilk APK).
        found = sorted(glob.glob(os.path.join(ROOT, "dist", "tv-app", "nino-androidtv_*.apk")), reverse=True)
        found += sorted(glob.glob(os.path.join(ROOT, "apps", "android-tv", "app", "build", "outputs", "apk", "*", "release", "*.apk")))
        apk = next((p for p in found if apk_package(p) == APP_ID), None)
    if apk:
        package = apk_package(apk)
        if package == APP_ID:
            with open(target, "wb") as f:
                f.write(read(apk))
            print("Android TV paketi gömüldü:", apk)
        else:
            print(f"warning: NINO_TV_APK paketi {package!r}, {APP_ID} değil; gömülmedi")
    elif os.path.exists(target):
        os.remove(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
