# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# PS5 Remote Play yerel kütüphanesi: hazır derlenmiş chiaki-ng ve bağımlılıkları (scripts/build-remoteplay.sh)
# üstüne Nino'nun kendi JNI sarmalayıcısı ve MediaCodec çözücüsü.
cmake_minimum_required(VERSION 3.22.1)
project(nino_remoteplay C)

if(NOT NINO_REMOTEPLAY_DIR)
  message(FATAL_ERROR "NINO_REMOTEPLAY_DIR verilmedi (Gradle verir: apps/android/.remoteplay)")
endif()
set(RP_ROOT "${NINO_REMOTEPLAY_DIR}/${ANDROID_ABI}")
if(NOT EXISTS "${RP_ROOT}/lib/libchiaki.a")
  message(FATAL_ERROR "PS5 kütüphanesi yok: ${RP_ROOT}. Önce scripts/build-remoteplay.sh ${ANDROID_ABI} çalıştırın "
    "ya da -Pnino.skipNative=true ile derleyin.")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Bağlama sırası önemli: kullanan önce, kullanılan sonra.
set(RP_LIBS chiaki jerasure gf_complete protobuf-nanopb curl json-c miniupnpc
  event_pthreads event_extra event_core event ssl crypto)
set(RP_TARGETS)
foreach(name IN LISTS RP_LIBS)
  set(path "${RP_ROOT}/lib/lib${name}.a")
  if(EXISTS "${path}")
    add_library(rp_${name} STATIC IMPORTED)
    set_target_properties(rp_${name} PROPERTIES IMPORTED_LOCATION "${path}")
    list(APPEND RP_TARGETS rp_${name})
  endif()
endforeach()

add_library(nino-remoteplay SHARED
  nino_rp_jni.c
  nino_rp_log.c
  nino_rp_discovery.c
  nino_rp_regist.c
  nino_rp_session.c
  nino_rp_decoder.c)

target_include_directories(nino-remoteplay PRIVATE "${RP_ROOT}/include")
target_compile_options(nino-remoteplay PRIVATE -fvisibility=hidden -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(nino-remoteplay PRIVATE
  -Wl,--start-group ${RP_TARGETS} -Wl,--end-group
  mediandk android log)
# Android 15+ ve Play: 16 KB sayfa hizası. chiaki durağan bağlandığı için hizayı yalnız bu bağlama belirler.
target_link_options(nino-remoteplay PRIVATE
  -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -Wl,--gc-sections -Wl,--exclude-libs,ALL)
