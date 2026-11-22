// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// Nino Remote Play yerel köprüsünün ortak tanımları.
#ifndef NINO_RP_H
#define NINO_RP_H

#include <jni.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <time.h>

#include <chiaki/log.h>

#define NINO_TAG "NinoRP"
#define NINO_LOG_LINES 8
#define NINO_LOG_LINE_MAX 256

static inline uint64_t nino_now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

// --- JNI yardımcıları (nino_rp_jni.c) ---

// Çağıran iş parçacığının JNIEnv'i. Bağlı değilse JVM'e bağlar; iş parçacığı bitince kendiliğinden ayrılır.
JNIEnv *nino_env(void);
// ASCII dışı baytları '?' yapıp Java dizesi oluşturur (NewStringUTF geçersiz UTF-8'de bozulur).
jstring nino_jstring(JNIEnv *env, const char *s);
// Tek seferlik kütüphane başlatma; 0 değilse Remote Play kullanılamaz.
int nino_lib_ready(void);

// --- Günlük (nino_rp_log.c) ---

typedef struct nino_rp_log_t {
	ChiakiLog log;
	pthread_mutex_t lock;
	char lines[NINO_LOG_LINES][NINO_LOG_LINE_MAX]; // son hata satırları, eskiden yeniye
	int line_count;
	int line_start;
	uint32_t app_reason; // "Reported Application Reason" kodu, yoksa 0
	const char *what;
} NinoRpLog;

void nino_log_init(NinoRpLog *l, const char *what);
void nino_log_fini(NinoRpLog *l);
void nino_log_clear(NinoRpLog *l);
// Hata satırlarını eskiden yeniye Java dize dizisi olarak verir.
jobjectArray nino_log_lines(JNIEnv *env, NinoRpLog *l);
uint32_t nino_log_app_reason(NinoRpLog *l);
// Kütüphane dışı genel günlük (keşif, uyandırma).
NinoRpLog *nino_log_global(void);
// Kendi iletilerimiz.
void nino_logi(const char *fmt, ...);
void nino_loge(const char *fmt, ...);

// --- Çözücü (nino_rp_decoder.c) ---

typedef struct nino_decoder_t NinoDecoder;

// Kare dinleyicisi: çıkış iş parçacığında çağrılır, veri yalnız çağrı süresince geçerlidir.
// data = sıkıştırılmış Y (satır = en) + hemen arkasında NV12 sırasıyla yarım çözünürlüklü renk (has_chroma ise).
typedef void (*NinoFrameCb)(void *user, uint8_t *data, size_t size, int width, int height, int color_format,
	bool has_chroma, int64_t pts);

// Çözücüyü kurar. software: yazılım çözücüyle başla. min_interval_ms: dinleyiciye en sık kare aralığı.
NinoDecoder *nino_decoder_create(int width, int height, bool software, int min_interval_ms, NinoFrameCb cb, void *user);
// Sıkıştırılmış örneği verir (kütüphanenin görüntü iş parçacığı). false: örnek bırakıldı.
bool nino_decoder_push(NinoDecoder *d, const uint8_t *buf, size_t size);
// Durdurur ve siler. Dönünce bir daha kare gelmez.
void nino_decoder_destroy(NinoDecoder *d);
// Çözülen toplam kare sayısı (seyreltmeden önce).
int64_t nino_decoder_frames(NinoDecoder *d);
bool nino_decoder_is_software(NinoDecoder *d);

#endif
