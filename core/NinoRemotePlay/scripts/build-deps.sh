#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# OpenSSL (yalnız libcrypto), json-c, libevent ve miniupnpc'yi kaynaktan,
# statik olarak derler. Homebrew kütüphanelerine bağlı kalınmaz.
#   ./scripts/build-deps.sh [macos|macos-x86_64|ios|iossim ...]   (varsayılan: dördü)
# macos: Apple Silicon (arm64), macos-x86_64: Intel Mac. build-c.sh ikisini tek
# (universal) macOS diliminde birleştirir.
# Çıktı: .build-deps/<platform>/{include,lib}
# Gereken araçlar: Xcode, cmake, pkgconf (yalnız derleme sırasında).
# Hedef sürümden yeni bir sistem işlevi kullanılırsa derleme hata verir
# (-Werror=unguarded-availability-new); böylece eski sistemde çökme olmaz.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
JOBS=$(sysctl -n hw.ncpu)
if (( $# )); then PLATFORMS=("$@"); else PLATFORMS=(macos macos-x86_64 ios iossim); fi

for p in $PLATFORMS; do
  case $p in
    macos)        SDK=macosx;          SYS=Darwin; ARCH=arm64;  MIN=14.0; OSSL=darwin64-arm64-cc;        VFLAG=-mmacosx-version-min=$MIN ;;
    macos-x86_64) SDK=macosx;          SYS=Darwin; ARCH=x86_64; MIN=14.0; OSSL=darwin64-x86_64-cc;       VFLAG=-mmacosx-version-min=$MIN ;;
    ios)          SDK=iphoneos;        SYS=iOS;    ARCH=arm64;  MIN=17.0; OSSL=ios64-xcrun;              VFLAG=-mios-version-min=$MIN ;;
    iossim)       SDK=iphonesimulator; SYS=iOS;    ARCH=arm64;  MIN=17.0; OSSL=iossimulator-arm64-xcrun; VFLAG=-mios-simulator-version-min=$MIN ;;
    *) echo "Bilinmeyen platform: $p"; exit 1 ;;
  esac
  PREFIX=$ROOT/.build-deps/$p
  WORK=$ROOT/.build-deps/work/$p
  SYSROOT=$(xcrun --sdk $SDK --show-sdk-path)
  mkdir -p $PREFIX $WORK
  echo "== $p ($SDK $ARCH, en az $MIN)"

  CMAKE_COMMON=(-G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PREFIX
    -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN -DCMAKE_OSX_SYSROOT=$SYSROOT
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_C_FLAGS=-Werror=unguarded-availability-new)
  [[ $SYS == iOS ]] && CMAKE_COMMON+=(-DCMAKE_SYSTEM_NAME=iOS)

  # OpenSSL: yalnız libcrypto.
  if [[ ! -f $PREFIX/lib/libcrypto.a ]]; then
    rm -rf $WORK/openssl && cp -R $ROOT/Vendor/openssl $WORK/openssl
    (cd $WORK/openssl &&
      env CROSS_TOP= CROSS_SDK= ./Configure $OSSL no-shared no-tests no-apps no-docs no-engine no-module no-dso \
        no-ssl no-dtls no-comp no-async --prefix=$PREFIX --libdir=lib $VFLAG \
        -Werror=unguarded-availability-new >/dev/null &&
      make -j$JOBS build_libs >/dev/null &&
      make install_dev >/dev/null)
    echo "   openssl tamam"
  fi

  # json-c
  if [[ ! -f $PREFIX/lib/libjson-c.a ]]; then
    cmake -S $ROOT/Vendor/json-c -B $WORK/json-c $CMAKE_COMMON -DBUILD_STATIC_LIBS=ON -DBUILD_APPS=OFF \
      -DBUILD_TESTING=OFF -DDISABLE_WERROR=ON -DDISABLE_EXTRA_LIBS=ON >/dev/null
    cmake --build $WORK/json-c -j$JOBS >/dev/null && cmake --install $WORK/json-c >/dev/null
    echo "   json-c tamam"
  fi

  # libevent
  if [[ ! -f $PREFIX/lib/libevent.a ]]; then
    cmake -S $ROOT/Vendor/libevent -B $WORK/libevent $CMAKE_COMMON -DEVENT__LIBRARY_TYPE=STATIC \
      -DEVENT__DISABLE_OPENSSL=ON -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON \
      -DEVENT__DISABLE_REGRESS=ON -DEVENT__DISABLE_SAMPLES=ON -DEVENT__DISABLE_BENCHMARK=ON \
      -DEVENT__HAVE_PIPE2=OFF >/dev/null  # pipe2 yalnız iOS/macOS 27+; eski sistemde çökerdi
    cmake --build $WORK/libevent -j$JOBS >/dev/null && cmake --install $WORK/libevent >/dev/null
    echo "   libevent tamam"
  fi

  # miniupnpc
  if [[ ! -f $PREFIX/lib/libminiupnpc.a ]]; then
    cmake -S $ROOT/Vendor/miniupnp/miniupnpc -B $WORK/miniupnpc $CMAKE_COMMON -DUPNPC_BUILD_STATIC=ON \
      -DUPNPC_BUILD_SHARED=OFF -DUPNPC_BUILD_TESTS=OFF -DUPNPC_BUILD_SAMPLE=OFF >/dev/null
    cmake --build $WORK/miniupnpc -j$JOBS >/dev/null && cmake --install $WORK/miniupnpc >/dev/null
    echo "   miniupnpc tamam"
  fi
done
echo "Bağımlılıklar hazır: $ROOT/.build-deps"
