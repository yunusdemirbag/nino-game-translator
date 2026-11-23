#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# nino_native.dll'i MSYS2 mingw64 kabuğunda derler, yerel testleri koşar, içe/dışa aktarımları denetler ve
# DLL'i native/bin/ altına koyar. (Bu betik henüz Windows'ta denenmedi.)
#
# Gerekli MSYS2 paketleri (mingw-w64-x86_64-…): cc cmake ninja pkgconf nasm python python-protobuf protobuf
#   openssl json-c libevent miniupnpc; ayrıca make diffutils tar xz.
# Ortam:
#   NINO_CHIAKI_DIR     chiaki-ng v1.10.1 kaynağı (alt modülleri: nanopb, jerasure, gf-complete, curl)
#   NINO_FFMPEG_PREFIX  FFmpeg 7.1.2 öneki (yoksa build-ffmpeg.sh ile derlenir; önbelleğe alınabilir)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
native="$(cd "$here/.." && pwd)"
chiaki="${NINO_CHIAKI_DIR:?NINO_CHIAKI_DIR chiaki-ng v1.10.1 klasörünü göstermeli}"
# Ara çıktılar build/obj/ altında (başlık denetimi obj/ ve bin/ klasörlerini atlar).
ffmpeg="${NINO_FFMPEG_PREFIX:-$native/build/obj/ffmpeg-mingw64}"
build="$native/build/obj/windows"
out="$native/build/bin/windows"

case "${MSYSTEM:-}" in
  MINGW64) ;;
  *) echo "Bu betik MSYS2 mingw64 kabuğunda çalışır (MSYSTEM=MINGW64)"; exit 2 ;;
esac

"$here/build-ffmpeg.sh" "$ffmpeg" --enable-w32threads --arch=x86_64 --target-os=mingw32

prefix_sys="${MINGW_PREFIX:-/mingw64}"
for lib in libcrypto.a libjson-c.a libevent.a libminiupnpc.a; do
  [ -f "$prefix_sys/lib/$lib" ] || { echo "statik bağımlılık yok: $prefix_sys/lib/$lib"; exit 1; }
done
for lib in libavcodec.a libswscale.a libavutil.a; do
  [ -f "$ffmpeg/lib/$lib" ] || { echo "FFmpeg kütüphanesi yok: $ffmpeg/lib/$lib"; exit 1; }
done

cmake -S "$native" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DNINO_CHIAKI_DIR="$chiaki" -DNINO_FFMPEG_PREFIX="$ffmpeg" \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$out" -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$out"
cmake --build "$build" --target nino_native native_tests

"$out/native_tests.exe" "$native/tests/data/sample-1080p.h264"

dll="$out/nino_native.dll"

# İçe aktarma denetimi: yalnız Windows'un kendi DLL'leri.
allowed='^(kernel32|user32|advapi32|shell32|ole32|oleaut32|gdi32|ws2_32|wsock32|iphlpapi|bcrypt|bcryptprimitives|crypt32|secur32|normaliz|msvcrt|ntdll|ucrtbase|api-ms-win-.*)\.dll$'
bad=0
while read -r name; do
  lower="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  if ! echo "$lower" | grep -Eq "$allowed"; then
    echo "izin verilmeyen bağımlılık: $name"
    bad=1
  fi
done < <(objdump -p "$dll" | sed -n 's/^[[:space:]]*DLL Name: //p')
[ $bad -eq 0 ] || exit 1

# Dışa aktarım denetimi (çıktı dosyaya yazılır; büyük metinde bash yerine koyma çok yavaş).
exports_file="$build/exports.txt"
objdump -p "$dll" | tr -d '\r' > "$exports_file"
for fn in nino_rp_init nino_rp_discover nino_rp_discover_ex nino_rp_wake nino_rp_register \
          nino_rp_session_start nino_rp_session_set_login_pin nino_rp_session_stop; do
  grep -q "[[:space:]]$fn\$" "$exports_file" || {
    echo "dışa aktarım yok: $fn"
    sed -n '/Export Address Table/,/^$/p;/\[Ordinal\/Name Pointer\] Table/,/^$/p' "$exports_file"
    exit 1
  }
done

mkdir -p "$native/bin"
cp "$dll" "$native/bin/nino_native.dll"
echo "hazır: $native/bin/nino_native.dll"
