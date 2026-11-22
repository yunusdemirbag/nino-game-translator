#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Köprü için en küçük FFmpeg (LGPL): statik, yalnız h264 çözücü + ayrıştırıcı, avcodec/avutil/swscale.
# Kullanım: build-ffmpeg.sh <önek> [ek configure seçenekleri...]
#   Windows (MSYS2 mingw64): build-ffmpeg.sh /c/ffmpeg --enable-w32threads
#   Linux:                   build-ffmpeg.sh "$HOME/.cache/nino-ffmpeg" --enable-pic --enable-pthreads
# Önekte kütüphaneler zaten varsa bir şey yapmaz.
set -euo pipefail

version="7.1.2"
prefix="${1:?önek gerekli}"
shift || true

if [ -f "$prefix/lib/libavcodec.a" ] && [ -f "$prefix/lib/libswscale.a" ] && [ -f "$prefix/lib/libavutil.a" ]; then
  echo "FFmpeg $version zaten hazır: $prefix"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="$work/ffmpeg-$version.tar.xz"

fetch() {
  local url="$1" out="$2"
  for attempt in 1 2 3 4 5; do
    if curl -fsSL --retry 0 -o "$out" "$url"; then
      return 0
    fi
    echo "indirme başarısız ($attempt/5): $url" >&2
    sleep 5
  done
  return 1
}

if ! fetch "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" "$archive"; then
  archive="$work/ffmpeg-n$version.tar.gz"
  fetch "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n$version.tar.gz" "$archive"
fi

mkdir -p "$work/src"
tar -xf "$archive" -C "$work/src" --strip-components=1
cd "$work/src"

./configure --prefix="$prefix" \
  --enable-static --disable-shared --disable-debug \
  --disable-everything --disable-autodetect \
  --disable-programs --disable-doc --disable-network \
  --disable-avdevice --disable-avformat --disable-avfilter --disable-swresample \
  --enable-avcodec --enable-avutil --enable-swscale \
  --enable-decoder=h264 --enable-parser=h264 \
  "$@"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
make install
echo "FFmpeg $version kuruldu: $prefix"
