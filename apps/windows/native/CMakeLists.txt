# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# nino_native: chiaki-ng v1.10.1 üstünde ince C köprüsü.
#   Windows (MSYS2 mingw64): nino_native.dll   Linux: nino_native.so   Mac (yalnız test): nino_native.dylib
#
# Değişkenler:
#   NINO_CHIAKI_DIR     chiaki-ng v1.10.1 kaynak klasörü (dokunulmadan kullanılır)
#   NINO_FFMPEG_PREFIX  FFmpeg kurulumu (include/, lib/); boşsa sistemde aranır
#   NINO_NATIVE_TESTS   yerel test yürütücüsü (varsayılan açık)
#   NINO_NATIVE_ASAN    her şeyi (chiaki dahil) AddressSanitizer ile derle; yalnız test için (Windows dışı)

cmake_minimum_required(VERSION 3.20)
project(nino_native C)

set(NINO_CHIAKI_DIR "" CACHE PATH "chiaki-ng v1.10.1 kaynak klasörü")
set(NINO_FFMPEG_PREFIX "" CACHE PATH "FFmpeg kurulum öneki")
option(NINO_NATIVE_TESTS "native_tests programını da üret" ON)
option(NINO_NATIVE_ASAN "Her şeyi AddressSanitizer ile derle (yalnız test)" OFF)

if(NOT NINO_CHIAKI_DIR OR NOT EXISTS "${NINO_CHIAKI_DIR}/lib/include/chiaki/session.h")
  message(FATAL_ERROR "NINO_CHIAKI_DIR chiaki-ng v1.10.1 kaynak klasörünü göstermeli")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)

if(NOT WIN32)
  # Statik libchiaki paylaşımlı kütüphanenin içine bağlanır.
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

if(NINO_NATIVE_ASAN AND NOT WIN32)
  add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
  add_link_options(-fsanitize=address)
endif()

if(WIN32)
  # Yalnız statik kütüphaneler; OpenSSL statik; miniupnpc başlıkları dllimport bildirmesin.
  set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
  set(OPENSSL_USE_STATIC_LIBS TRUE)
  set(PKG_CONFIG_ARGN --static)   # json-c, libevent, miniupnpc: statik bağımlılıklarıyla
  add_compile_definitions(MINIUPNP_STATICLIB)
endif()

# ---- chiaki seçenekleri: yalnız kütüphane, gerisi kapalı ----
macro(nino_force name value)
  set(${name} ${value} CACHE STRING "" FORCE)
endmacro()
nino_force(CHIAKI_ENABLE_GUI OFF)
nino_force(CHIAKI_ENABLE_CLI OFF)
nino_force(CHIAKI_ENABLE_TESTS OFF)
nino_force(CHIAKI_ENABLE_FFMPEG_DECODER OFF)
nino_force(CHIAKI_ENABLE_PI_DECODER OFF)
nino_force(CHIAKI_LIB_ENABLE_OPUS OFF)
nino_force(CHIAKI_ENABLE_SPEEX OFF)
nino_force(CHIAKI_ENABLE_SETSU OFF)
nino_force(CHIAKI_ENABLE_STEAMDECK_NATIVE OFF)
nino_force(CHIAKI_ENABLE_STEAM_SHORTCUT OFF)
nino_force(CHIAKI_ENABLE_BOREALIS OFF)
nino_force(CHIAKI_ENABLE_RUDP OFF)            # internet üzerinden Remote Play yok
nino_force(CHIAKI_LIB_ENABLE_MBEDTLS OFF)
nino_force(BUILD_SHARED_LIBS OFF)
# chiaki'nin getirdiği curl: ek bağımlılıklar kapalı
nino_force(USE_NGHTTP2 OFF)
nino_force(USE_LIBIDN2 OFF)
nino_force(CURL_ZSTD OFF)
nino_force(CURL_BROTLI OFF)
nino_force(CURL_USE_LIBPSL OFF)
nino_force(CURL_USE_LIBSSH2 OFF)
nino_force(USE_LIBRTMP OFF)
nino_force(CURL_ZLIB OFF)
nino_force(CURL_DISABLE_LDAP ON)
nino_force(CURL_DISABLE_LDAPS ON)
if(NOT WIN32)
  # Windows'ta chiaki curl'ü schannel ile kurar; başka yerde TLS gerekmez (PSN ve internet bağlantısı kullanılmaz).
  nino_force(CURL_ENABLE_SSL OFF)
endif()

add_subdirectory("${NINO_CHIAKI_DIR}" chiaki EXCLUDE_FROM_ALL)

# ---- FFmpeg: avcodec, swscale, avutil ----
set(NINO_FFMPEG_LIBS)
foreach(part avcodec swscale avutil)
  find_path(NINO_${part}_INCLUDE NAMES lib${part}/${part}.h
            HINTS "${NINO_FFMPEG_PREFIX}/include" NO_CACHE)
  if(NINO_FFMPEG_PREFIX)
    find_library(NINO_${part}_LIB NAMES ${part} HINTS "${NINO_FFMPEG_PREFIX}/lib" NO_DEFAULT_PATH NO_CACHE)
  endif()
  if(NOT NINO_${part}_LIB)
    find_library(NINO_${part}_LIB NAMES ${part} NO_CACHE)
  endif()
  if(NOT NINO_${part}_INCLUDE OR NOT NINO_${part}_LIB)
    message(FATAL_ERROR "FFmpeg ${part} bulunamadı (NINO_FFMPEG_PREFIX=${NINO_FFMPEG_PREFIX})")
  endif()
  list(APPEND NINO_FFMPEG_LIBS "${NINO_${part}_LIB}")
  list(APPEND NINO_FFMPEG_INCLUDES "${NINO_${part}_INCLUDE}")
endforeach()
list(REMOVE_DUPLICATES NINO_FFMPEG_INCLUDES)

set(NINO_SOURCES src/nino_native.c src/h264.c src/util.c)

set(NINO_PLATFORM_LIBS)
if(WIN32)
  list(APPEND NINO_PLATFORM_LIBS ws2_32 wsock32 iphlpapi bcrypt crypt32 secur32 advapi32 user32 shell32 ole32 gdi32 normaliz)
elseif(UNIX AND NOT APPLE)
  list(APPEND NINO_PLATFORM_LIBS m)   # statik FFmpeg matematik işlevleri
endif()
if(APPLE)
  list(APPEND NINO_PLATFORM_LIBS z "-framework CoreFoundation" "-framework Security"
       "-framework SystemConfiguration" "-framework CoreServices")
endif()

add_library(nino_native SHARED ${NINO_SOURCES})
set_target_properties(nino_native PROPERTIES PREFIX "" OUTPUT_NAME nino_native)
if(APPLE)
  set_target_properties(nino_native PROPERTIES SUFFIX ".dylib")
elseif(UNIX)
  set_target_properties(nino_native PROPERTIES SUFFIX ".so")
endif()
target_include_directories(nino_native PRIVATE include src ${NINO_FFMPEG_INCLUDES})
target_link_libraries(nino_native PRIVATE chiaki-lib ${NINO_FFMPEG_LIBS} ${NINO_PLATFORM_LIBS})
target_compile_options(nino_native PRIVATE -Wall -Wextra)

# Dışa yalnız nino_rp_* işlevleri açılır (statik chiaki/FFmpeg simgeleri dışarı sızmaz).
if(WIN32)
  target_link_options(nino_native PRIVATE -static -static-libgcc -Wl,--no-undefined -Wl,--exclude-all-symbols -s)
elseif(APPLE)
  target_link_options(nino_native PRIVATE "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/exports/macos.txt")
else()
  target_link_options(nino_native PRIVATE -Wl,--no-undefined -Wl,--exclude-libs,ALL
                      "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/exports/linux.map")
endif()

if(NINO_NATIVE_TESTS)
  # Yürütücü kaynakları doğrudan içerir (iç işlevlere erişim).
  add_executable(native_tests tests/native_tests.c)
  target_include_directories(native_tests PRIVATE include src ${NINO_FFMPEG_INCLUDES})
  target_link_libraries(native_tests PRIVATE chiaki-lib ${NINO_FFMPEG_LIBS} ${NINO_PLATFORM_LIBS})
  if(WIN32)
    target_link_options(native_tests PRIVATE -static -static-libgcc)
  endif()
endif()
