#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Ortak web uygulamasından iki TV paketi üretir (yalnız Python'un kendi kütüphanesiyle):
#   dist/com.ninotranslator.tv_<sürüm>_all.ipk   LG webOS (geliştirici modundaki TV'ye kurulur)
#   dist/nino-samsung_<sürüm>.wgt                Samsung Tizen, imzasız (gönderici kurarken TV'ye özel sertifikayla imzalar)
# Sürüm tek yerden gelir: src/js/main.js içindeki VERSION.
#
# Kullanım: python3 apps/tv-web/tools/package.py
import gzip
import io
import json
import os
import re
import shutil
import tarfile
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.dirname(HERE)
SRC = os.path.join(APP, 'src')
PACK = os.path.join(APP, 'packaging')
BUILD = os.path.join(APP, 'build')
DIST = os.path.join(APP, 'dist')
LG_ID = 'com.ninotranslator.tv'


def version():
    with open(os.path.join(SRC, 'js', 'main.js'), encoding='utf-8') as f:
        return re.search(r"var VERSION = '([0-9.]+)';", f.read()).group(1)


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


# Kaynağı hedef klasöre kopyalar; tarayıcı önizlemesinin sahte platform.js'i yerine TV'ninki konur.
def assemble(target, ver):
    out = os.path.join(BUILD, target)
    shutil.rmtree(out, ignore_errors=True)
    shutil.copytree(SRC, out)
    platform = read(os.path.join(APP, 'platform', 'common.js')) + '\n' + read(os.path.join(APP, 'platform', target + '.js'))
    write(os.path.join(out, 'platform.js'), platform)
    index = os.path.join(out, 'index.html')
    if target == 'tizen':
        # Samsung'un ürün API'leri (ekran koruyucu) platform.js'ten önce yüklenir.
        html = read(index).replace('<script src="platform.js"></script>',
                                   '<script src="$WEBAPIS/webapis/webapis.js"></script>\n  <script src="platform.js"></script>')
        write(index, html)
        write(os.path.join(out, 'config.xml'), read(os.path.join(PACK, 'tizen', 'config.xml')).replace('@VERSION@', ver))
        shutil.copy(os.path.join(PACK, 'tizen', 'icon.png'), os.path.join(out, 'icon.png'))
    else:
        write(os.path.join(out, 'appinfo.json'), read(os.path.join(PACK, 'webos', 'appinfo.json')).replace('@VERSION@', ver))
        for name in ('icon.png', 'largeIcon.png'):
            shutil.copy(os.path.join(PACK, 'webos', name), os.path.join(out, name))
    return out


def files_under(root):
    for base, dirs, names in os.walk(root):
        dirs.sort()
        for name in sorted(names):
            path = os.path.join(base, name)
            yield path, os.path.relpath(path, root).replace(os.sep, '/')


def tar_gz(entries):
    """entries: [(arcname, bytes or None for dir)] → .tar.gz baytları."""
    raw = io.BytesIO()
    stamp = int(time.time())
    with tarfile.open(fileobj=raw, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.mtime = stamp
            if data is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                tar.addfile(info)
            else:
                info.size = len(data)
                info.mode = 0o644
                tar.addfile(info, io.BytesIO(data))
    return gzip.compress(raw.getvalue(), mtime=stamp)


def ar(members):
    """Debian paketleri gibi 'ar' arşivi (webOS .ipk biçimi)."""
    out = io.BytesIO()
    out.write(b'!<arch>\n')
    stamp = int(time.time())
    for name, data in members:
        header = '%-16s%-12d%-6d%-6d%-8s%-10d`\n' % (name, stamp, 0, 0, '100644', len(data))
        out.write(header.encode('ascii'))
        out.write(data)
        if len(data) % 2:
            out.write(b'\n')
    return out.getvalue()


def ipk(src, ver):
    app_dir = 'usr/palm/applications/' + LG_ID + '/'
    pkg_dir = 'usr/palm/packages/' + LG_ID + '/'
    entries = [('usr/', None), ('usr/palm/', None), ('usr/palm/applications/', None), ('usr/palm/packages/', None),
               (app_dir, None), (pkg_dir, None)]
    size = 0
    seen_dirs = set()
    for path, rel in files_under(src):
        parts = rel.split('/')[:-1]
        for i in range(len(parts)):
            d = app_dir + '/'.join(parts[:i + 1]) + '/'
            if d not in seen_dirs:
                seen_dirs.add(d)
                entries.append((d, None))
        with open(path, 'rb') as f:
            data = f.read()
        size += len(data)
        entries.append((app_dir + rel, data))
    info = json.dumps({'id': LG_ID, 'version': ver, 'app': LG_ID}, indent=2).encode('utf-8')
    entries.append((pkg_dir + 'packageinfo.json', info))
    control = ('Package: %s\nVersion: %s\nSection: misc\nPriority: optional\nArchitecture: all\n'
               'Installed-Size: %d\nMaintainer: Nino contributors\nDescription: Nino Game Translator\n'
               'webOS-Package-Format-Version: 2\nwebOS-Packager-Version: x.y.x\n') % (LG_ID, ver, size)
    data = ar([('debian-binary', b'2.0\n'),
               ('control.tar.gz', tar_gz([('control', control.encode('utf-8'))])),
               ('data.tar.gz', tar_gz(entries))])
    path = os.path.join(DIST, '%s_%s_all.ipk' % (LG_ID, ver))
    with open(path, 'wb') as f:
        f.write(data)
    return path


def wgt(src, ver):
    path = os.path.join(DIST, 'nino-samsung_%s.wgt' % ver)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for file, rel in files_under(src):
            z.write(file, rel)
    return path


def main():
    ver = version()
    os.makedirs(DIST, exist_ok=True)
    # Önceki sürümlerin paketleri karışmasın: dist/ yalnız bu aracın ürettiği dosyaları tutar.
    for name in os.listdir(DIST):
        if name.endswith(('.ipk', '.wgt')) and ('_' + ver) not in name:
            os.remove(os.path.join(DIST, name))
    print(ipk(assemble('webos', ver), ver))
    print(wgt(assemble('tizen', ver), ver))


if __name__ == '__main__':
    main()
