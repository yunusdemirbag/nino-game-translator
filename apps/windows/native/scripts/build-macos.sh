#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Yalnız test için: nino_native.dylib'i Homebrew kütüphaneleriyle (ffmpeg, openssl@3, json-c, libevent, miniupnpc)
# derler, yerel testleri koşar ve native/build/bin/ altına koyar. C# testleri oradaki .dylib'i kullanır.
#
# Ortam:
#   NINO_CHIAKI_DIR   chiaki-ng v1.10.1 kaynağı (varsayılan ~/Desktop/NinoCore/NinoRemotePlay/Vendor/chiaki-ng)
#   NINO_PYTHON       google.protobuf modülü olan Python (nanopb üreteci için)
#   NINO_BUILD_DIR    ara derleme klasörü (varsayılan geçici klasör). Not: macOS'ta Masaüstü klasörünün kendisi
#                     gizlilik izni beklerken "cmake -E" takılabildiği için ara derleme Masaüstü dışında yapılır;
#                     kaynaklara da Masaüstü dışındaki bir bağlantı (symlink) üzerinden erişilir.
#   NINO_ASAN=1       her şeyi AddressSanitizer ile derler; NINO_STOP_LOOPS durdurma testlerini yineler
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
native="$(cd "$here/.." && pwd)"
chiaki="${NINO_CHIAKI_DIR:-$HOME/Desktop/NinoCore/NinoRemotePlay/Vendor/chiaki-ng}"
python="${NINO_PYTHON:-python3}"
work="${NINO_BUILD_DIR:-$(mktemp -d /tmp/nino-native.XXXXXX)}"
brew="/opt/homebrew/opt"

"$python" -c "import google.protobuf" 2>/dev/null || { echo "$python içinde google.protobuf yok (NINO_PYTHON verin)"; exit 1; }

mkdir -p "$work"
ln -sfn "$native" "$work/native-src"
ln -sfn "$chiaki" "$work/chiaki-src"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$python")" > "$work/python"
chmod +x "$work/python"

export PKG_CONFIG_PATH="$brew/openssl@3/lib/pkgconfig:$brew/json-c/lib/pkgconfig:$brew/libevent/lib/pkgconfig:$brew/miniupnpc/lib/pkgconfig"
asan=OFF
[ "${NINO_ASAN:-0}" = 1 ] && asan=ON

cd "$work"
cmake -S "$work/native-src" -B "$work/obj" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DNINO_CHIAKI_DIR="$work/chiaki-src" -DNINO_FFMPEG_PREFIX="$brew/ffmpeg" \
  -DOPENSSL_ROOT_DIR="$brew/openssl@3" -DPYTHON_EXECUTABLE="$work/python" -DNINO_NATIVE_ASAN=$asan \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$work/bin" -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$work/bin"
cmake --build "$work/obj" --target nino_native native_tests

"$work/bin/native_tests" "$native/tests/data/sample-1080p.h264"

leaked="$(nm -gU "$work/bin/nino_native.dylib" | awk '{print $3}' | grep -v '^_nino_rp_' || true)"
if [ -n "$leaked" ]; then
  echo "nino_rp_ dışında dışa açılan simgeler:"; echo "$leaked"; exit 1
fi

mkdir -p "$native/build/bin"
cp "$work/bin/nino_native.dylib" "$work/bin/native_tests" "$native/build/bin/"
echo "hazır: $native/build/bin/nino_native.dylib"
