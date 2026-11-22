#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Remote Play C çekirdeğini macOS (Apple Silicon + Intel), iOS ve iOS simülatörü
# için derler ve hepsini Frameworks/CRemotePlay.xcframework içinde toplar.
# macOS dilimi universal'dır (arm64 + x86_64, lipo ile tek kütüphane).
# Homebrew kütüphanesi kullanmaz.
#   ./scripts/fetch-deps.sh && ./scripts/build-deps.sh && ./scripts/build-c.sh
#   OUT_DIR=/bir/klasör ./scripts/build-c.sh   (çerçeveyi başka yere üretir)
# Çerçeve her zaman dört dilimle birlikte üretilir; başka uygulamalar aynı yola
# bağlı olduğundan eksik dilimli bir çerçeve yerine konmaz.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC=$ROOT/Vendor/chiaki-ng
OUT=${OUT_DIR:-$ROOT/Frameworks}
PY=$ROOT/.tools/venv/bin/python
JOBS=$(sysctl -n hw.ncpu)
PLATFORMS=(macos macos-x86_64 ios iossim)

[[ -d $SRC/lib ]] || { echo "Kaynak yok, önce: ./scripts/fetch-deps.sh"; exit 1; }
[[ -x $PY ]] || { python3 -m venv $ROOT/.tools/venv && $PY -m pip install -q protobuf; }

for p in $PLATFORMS; do
  case $p in
    macos)        SDK=macosx;          ARCH=arm64;  MIN=14.0; EXTRA=() ;;
    macos-x86_64) SDK=macosx;          ARCH=x86_64; MIN=14.0; EXTRA=() ;;
    ios)          SDK=iphoneos;        ARCH=arm64;  MIN=17.0; EXTRA=(-DCMAKE_SYSTEM_NAME=iOS) ;;
    iossim)       SDK=iphonesimulator; ARCH=arm64;  MIN=17.0; EXTRA=(-DCMAKE_SYSTEM_NAME=iOS) ;;
    *) echo "Bilinmeyen platform: $p"; exit 1 ;;
  esac
  DEPS=$ROOT/.build-deps/$p
  [[ -f $DEPS/lib/libcrypto.a ]] || { echo "Bağımlılık yok, önce: ./scripts/build-deps.sh $p"; exit 1; }
  BUILD=$ROOT/.build-c/$p; mkdir -p $BUILD
  SYSROOT=$(xcrun --sdk $SDK --show-sdk-path)
  echo "== $p ($ARCH)"

  env -u PKG_CONFIG_PATH PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig \
  cmake -S $SRC -B $BUILD -G "Unix Makefiles" $EXTRA \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN \
    -DCMAKE_OSX_SYSROOT=$SYSROOT -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_FIND_ROOT_PATH="$DEPS;$SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DCMAKE_SYSTEM_IGNORE_PREFIX_PATH=/opt/homebrew \
    -DCHIAKI_ENABLE_GUI=OFF -DCHIAKI_ENABLE_CLI=OFF -DCHIAKI_ENABLE_TESTS=OFF \
    -DCHIAKI_ENABLE_SETSU=OFF -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
    -DCHIAKI_ENABLE_SPEEX=OFF -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF -DCHIAKI_ENABLE_PI_DECODER=OFF \
    -DCHIAKI_LIB_ENABLE_OPUS=OFF -DCHIAKI_ENABLE_RUDP=OFF \
    -DOPENSSL_ROOT_DIR=$DEPS -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DCURL_ENABLE_SSL=OFF -DCURL_USE_OPENSSL=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF \
    -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF \
    -DPython3_EXECUTABLE=$PY -DPYTHON_EXECUTABLE=$PY >$BUILD.cmake.log 2>&1 || { tail -30 $BUILD.cmake.log; exit 1; }
  cmake --build $BUILD --target chiaki-lib -j$JOBS >$BUILD.build.log 2>&1 || { grep -E "error" $BUILD.build.log | head -30; exit 1; }

  # Homebrew kütüphanesine kaçak bağlantı olmasın (araçlar: cmake, pkg-config, protoc serbest).
  if grep -E "/opt/homebrew[^ ]*(\.a|\.dylib|/include)" $BUILD/CMakeCache.txt; then
    echo "HATA: Homebrew kütüphanesi kullanılmış ($p)"; exit 1
  fi

  STAGE=$BUILD/stage
  rm -rf $STAGE && mkdir -p $STAGE/include
  libtool -static -o $STAGE/libCRemotePlay.a \
    $BUILD/lib/libchiaki.a \
    $BUILD/third-party/libjerasure.a $BUILD/third-party/libgf_complete.a \
    $BUILD/third-party/nanopb/libprotobuf-nanopb.a $BUILD/third-party/curl/lib/libcurl.a \
    $DEPS/lib/libcrypto.a $DEPS/lib/libjson-c.a $DEPS/lib/libevent.a $DEPS/lib/libminiupnpc.a 2>/dev/null
  cp -R $SRC/lib/include/chiaki $STAGE/include/
  cp $BUILD/lib/include/chiaki/config.h $STAGE/include/chiaki/config.h
  cat > $STAGE/include/CRemotePlay.h <<'H'
#include <chiaki/common.h>
#include <chiaki/log.h>
#include <chiaki/discovery.h>
#include <chiaki/discoveryservice.h>
#include <chiaki/regist.h>
#include <chiaki/session.h>
H
  cat > $STAGE/include/module.modulemap <<'M'
module CRemotePlay {
    umbrella header "CRemotePlay.h"
    export *
}
M
done

# İki macOS mimarisi aynı başlıkları kullanır; üretilen ayarlar farklıysa durulur.
C=$ROOT/.build-c
diff -q $C/macos/stage/include/chiaki/config.h $C/macos-x86_64/stage/include/chiaki/config.h >/dev/null ||
  { echo "HATA: arm64 ve x86_64 config.h farklı"; exit 1; }
UNIVERSAL=$C/macos-universal
rm -rf $UNIVERSAL && mkdir -p $UNIVERSAL
lipo -create -output $UNIVERSAL/libCRemotePlay.a $C/macos/stage/libCRemotePlay.a $C/macos-x86_64/stage/libCRemotePlay.a
cp -R $C/macos/stage/include $UNIVERSAL/include

LIBRARIES=(-library $UNIVERSAL/libCRemotePlay.a -headers $UNIVERSAL/include)
for p in ios iossim; do LIBRARIES+=(-library $C/$p/stage/libCRemotePlay.a -headers $C/$p/stage/include); done

rm -rf $OUT/CRemotePlay.xcframework && mkdir -p $OUT
xcodebuild -create-xcframework $LIBRARIES -output $OUT/CRemotePlay.xcframework >/dev/null
echo "Hazır: $OUT/CRemotePlay.xcframework (macOS arm64+x86_64, iOS arm64, iOS simülatörü arm64)"
