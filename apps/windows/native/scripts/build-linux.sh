#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# nino_native.so'yu Linux'ta derler, yerel testleri koşar, dışa aktarımı denetler ve native/bin/ altına koyar.
# (Bu betik henüz denenmedi.)
#
# Gerekli paketler (Debian/Ubuntu adlarıyla): build-essential cmake ninja-build pkg-config nasm python3
#   python3-protobuf protobuf-compiler libssl-dev libjson-c-dev libevent-dev libminiupnpc-dev curl xz-utils
# Ortam:
#   NINO_CHIAKI_DIR     chiaki-ng v1.10.1 kaynağı
#   NINO_FFMPEG_PREFIX  FFmpeg öneki; yoksa en küçük FFmpeg 7.1.2 PIC'li statik derlenir (.so sistem FFmpeg'ine bağlanmaz)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
native="$(cd "$here/.." && pwd)"
chiaki="${NINO_CHIAKI_DIR:?NINO_CHIAKI_DIR chiaki-ng v1.10.1 klasörünü göstermeli}"
# Ara çıktılar build/obj/ altında (başlık denetimi obj/ ve bin/ klasörlerini atlar).
ffmpeg="${NINO_FFMPEG_PREFIX:-$native/build/obj/ffmpeg-linux}"
build="$native/build/obj/linux"
out="$native/build/bin/linux"

"$here/build-ffmpeg.sh" "$ffmpeg" --enable-pic --enable-pthreads

cmake -S "$native" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DNINO_CHIAKI_DIR="$chiaki" -DNINO_FFMPEG_PREFIX="$ffmpeg" \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$out" -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$out"
cmake --build "$build" --target nino_native native_tests

"$out/native_tests" "$native/tests/data/sample-1080p.h264"

so="$out/nino_native.so"
leaked="$(nm -D --defined-only "$so" | awk '{print $3}' | grep -v '^nino_rp_' | grep -v '^$' || true)"
if [ -n "$leaked" ]; then
  echo "nino_rp_ dışında dışa açılan simgeler:"; echo "$leaked"; exit 1
fi

mkdir -p "$native/bin"
cp "$so" "$native/bin/nino_native.so"
echo "hazır: $native/bin/nino_native.so"
