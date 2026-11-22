#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# PS5 Remote Play C kütüphanesini (chiaki-ng v1.10.1) ve bağımlılıklarını (OpenSSL libcrypto, json-c, libevent,
# miniupnpc) Android NDK ile, kaynaktan ve statik olarak derler. Hiçbir şey indirmez: kaynaklar NinoCore'un
# resmî depolardan aldığı kopyadır (NINO_RP_VENDOR, varsayılan deponun core/NinoRemotePlay/Vendor klasörü; yoksa ~/Desktop/NinoCore/...).
#   ./scripts/build-remoteplay.sh [arm64-v8a x86_64 ...]   (varsayılan: arm64-v8a)
# Çıktı: apps/android/.remoteplay/<abi>/{include,lib}. Uygulamanın CMake'i buradan bağlar.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
RP_HOME=$(cd "$(dirname "$0")/../../../core/NinoRemotePlay" 2>/dev/null && pwd || true)
[[ -n $RP_HOME && -d $RP_HOME/Vendor ]] || RP_HOME=$HOME/Desktop/NinoCore/NinoRemotePlay
VENDOR=${NINO_RP_VENDOR:-$RP_HOME/Vendor}
NDK=${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/27.0.12077973}
API=26
PY=${NINO_PYTHON:-$RP_HOME/.tools/venv/bin/python}
JOBS=$(sysctl -n hw.ncpu)
TOOLCHAIN=$NDK/build/cmake/android.toolchain.cmake
BIN=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin
if (( $# )); then ABIS=("$@"); else ABIS=(arm64-v8a); fi

[[ -d $VENDOR/chiaki-ng/lib ]] || { echo "chiaki-ng kaynağı yok: $VENDOR"; exit 1; }
[[ -x $PY ]] || { echo "protobuf'lu Python yok: $PY (NINO_PYTHON ile verin)"; exit 1; }

for abi in $ABIS; do
  case $abi in
    arm64-v8a) OSSL=android-arm64 ;;
    x86_64)    OSSL=android-x86_64 ;;
    *) echo "Bilinmeyen ABI: $abi"; exit 1 ;;
  esac
  PREFIX=$ROOT/.remoteplay/$abi
  WORK=$ROOT/.remoteplay/work/$abi
  mkdir -p $PREFIX $WORK
  echo "== $abi (API $API)"
  COMMON=(-G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PREFIX
    -DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-$API
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_FIND_ROOT_PATH=$PREFIX -DCMAKE_PREFIX_PATH=$PREFIX
    # Android'de pthread libc'nin içinde; CMake'in Threads denemesi NDK ile tutmuyor.
    -DCMAKE_THREAD_LIBS_INIT=-pthread -DCMAKE_HAVE_THREADS_LIBRARY=1 -DCMAKE_USE_PTHREADS_INIT=1 -DThreads_FOUND=TRUE)

  if [[ ! -f $PREFIX/lib/libcrypto.a ]]; then
    rm -rf $WORK/openssl && cp -R $VENDOR/openssl $WORK/openssl
    (cd $WORK/openssl &&
      env ANDROID_NDK_ROOT=$NDK PATH=$BIN:$PATH ./Configure $OSSL -D__ANDROID_API__=$API no-shared no-tests no-apps \
        no-docs no-engine no-module no-dso no-ssl no-dtls no-comp no-async --prefix=$PREFIX --libdir=lib >/dev/null &&
      env ANDROID_NDK_ROOT=$NDK PATH=$BIN:$PATH make -j$JOBS build_libs >/dev/null &&
      env ANDROID_NDK_ROOT=$NDK PATH=$BIN:$PATH make install_dev >/dev/null)
    echo "   openssl tamam"
  fi
  if [[ ! -f $PREFIX/lib/libjson-c.a ]]; then
    cmake -S $VENDOR/json-c -B $WORK/json-c $COMMON -DBUILD_STATIC_LIBS=ON -DBUILD_APPS=OFF -DBUILD_TESTING=OFF \
      -DDISABLE_WERROR=ON -DDISABLE_EXTRA_LIBS=ON >/dev/null
    cmake --build $WORK/json-c -j$JOBS >/dev/null && cmake --install $WORK/json-c >/dev/null
    echo "   json-c tamam"
  fi
  if [[ ! -f $PREFIX/lib/libevent.a ]]; then
    cmake -S $VENDOR/libevent -B $WORK/libevent $COMMON -DEVENT__LIBRARY_TYPE=STATIC -DEVENT__DISABLE_OPENSSL=ON \
      -DEVENT__DISABLE_MBEDTLS=ON -DEVENT__DISABLE_TESTS=ON -DEVENT__DISABLE_REGRESS=ON -DEVENT__DISABLE_SAMPLES=ON \
      -DEVENT__DISABLE_BENCHMARK=ON >$WORK/libevent.log 2>&1 || { tail -20 $WORK/libevent.log; exit 1; }
    cmake --build $WORK/libevent -j$JOBS >/dev/null && cmake --install $WORK/libevent >/dev/null
    echo "   libevent tamam"
  fi
  if [[ ! -f $PREFIX/lib/libminiupnpc.a ]]; then
    cmake -S $VENDOR/miniupnp/miniupnpc -B $WORK/miniupnpc $COMMON -DUPNPC_BUILD_STATIC=ON -DUPNPC_BUILD_SHARED=OFF \
      -DUPNPC_BUILD_TESTS=OFF -DUPNPC_BUILD_SAMPLE=OFF >/dev/null
    cmake --build $WORK/miniupnpc -j$JOBS >/dev/null && cmake --install $WORK/miniupnpc >/dev/null
    echo "   miniupnpc tamam"
  fi

  # chiaki-ng C çekirdeği: arayüz, ses, kol, FFmpeg kapalı; curl şifrelemesiz.
  BUILD=$WORK/chiaki
  env -u PKG_CONFIG_PATH PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig PKG_CONFIG_SYSROOT_DIR= \
  cmake -S $VENDOR/chiaki-ng -B $BUILD $COMMON \
    -DCHIAKI_ENABLE_GUI=OFF -DCHIAKI_ENABLE_CLI=OFF -DCHIAKI_ENABLE_TESTS=OFF -DCHIAKI_ENABLE_ANDROID=OFF \
    -DCHIAKI_ENABLE_SETSU=OFF -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
    -DCHIAKI_ENABLE_SPEEX=OFF -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF -DCHIAKI_ENABLE_PI_DECODER=OFF \
    -DCHIAKI_LIB_ENABLE_OPUS=OFF -DCHIAKI_ENABLE_RUDP=OFF -DCHIAKI_ENABLE_BOREALIS=OFF \
    -DOPENSSL_ROOT_DIR=$PREFIX -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DCURL_ENABLE_SSL=OFF -DCURL_USE_OPENSSL=OFF -DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_DISABLE_LDAP=ON \
    -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF -DUSE_LIBRTMP=OFF \
    -DPKG_CONFIG_EXECUTABLE=$(command -v pkg-config) \
    -DPython3_EXECUTABLE=$PY -DPYTHON_EXECUTABLE=$PY >$BUILD.cmake.log 2>&1 || { tail -30 $BUILD.cmake.log; exit 1; }
  cmake --build $BUILD --target chiaki-lib -j$JOBS >$BUILD.build.log 2>&1 || { grep -E "error" $BUILD.build.log | head -30; exit 1; }
  for a in lib/libchiaki.a third-party/libjerasure.a third-party/libgf_complete.a third-party/nanopb/libprotobuf-nanopb.a \
           third-party/curl/lib/libcurl.a; do
    cp $BUILD/$a $PREFIX/lib/
  done
  rm -rf $PREFIX/include/chiaki && cp -R $VENDOR/chiaki-ng/lib/include/chiaki $PREFIX/include/
  cp $BUILD/lib/include/chiaki/config.h $PREFIX/include/chiaki/config.h
  echo "   chiaki-ng tamam"
done
echo "Hazır: $ROOT/.remoteplay"
