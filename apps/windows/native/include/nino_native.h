// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/*
 * nino_native: PS5 Remote Play için ince C arayüzü (chiaki-ng v1.10.1 üstünde).
 *
 * Kurallar:
 *  - Düz C, cdecl. Dizgeler UTF-8 ve sıfırla biter. Bütün işlevler iş parçacığı güvenlidir.
 *  - Dönüş 0 = başarı (istisnalar her işlevde yazılı).
 *  - Geri çağrılar köprünün ya da chiaki'nin iş parçacığında gelir; hızlı dönmelidir.
 *  - C# tarafı bu dosyadaki sayı, sıra ve boyutlara göre P/Invoke bildirimi yapar; değiştirme.
 */

#ifndef NINO_NATIVE_H
#define NINO_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  if defined(NINO_NATIVE_BUILDING)
#    define NINO_API __declspec(dllexport)
#  else
#    define NINO_API __declspec(dllimport)
#  endif
#  define NINO_CALL __cdecl
#else
#  define NINO_API __attribute__((visibility("default")))
#  define NINO_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Günlük düzeyleri (geri çağrıdaki level). */
#define NINO_RP_LOG_ERROR   0
#define NINO_RP_LOG_WARNING 1
#define NINO_RP_LOG_INFO    2

/* Oturum olayları (olay geri çağrısındaki event). */
#define NINO_RP_EVENT_CONNECTED     0
#define NINO_RP_EVENT_QUIT          1
#define NINO_RP_EVENT_LOGIN_PASSCODE 2

/* Kapanma nedenleri (NINO_RP_EVENT_QUIT için quit_reason). */
#define NINO_RP_QUIT_STOPPED  0
#define NINO_RP_QUIT_IN_USE   1
#define NINO_RP_QUIT_REFUSED  2
#define NINO_RP_QUIT_NETWORK  3
#define NINO_RP_QUIT_OTHER    4

/* Kayıt dönüşleri. */
#define NINO_RP_REGIST_OK       0
#define NINO_RP_REGIST_FAILED   1
#define NINO_RP_REGIST_CANCELED 2

typedef void (NINO_CALL *nino_rp_log_cb)(int level, const char *message, void *user);

typedef void (NINO_CALL *nino_rp_found_cb)(const char *host, const char *name, int awake, void *user);

typedef void (NINO_CALL *nino_rp_found_ex_cb)(const char *host, const char *name, int awake,
                                              const char *running_app_titleid, const char *running_app_name,
                                              void *user);

/* bgra yalnız çağrı süresince geçerlidir. */
typedef void (NINO_CALL *nino_rp_frame_cb)(const uint8_t *bgra, int width, int height, int stride, void *user);

typedef void (NINO_CALL *nino_rp_event_cb)(int event, int quit_reason, const char *reason_text, void *user);

/* Kayıt çıktısı: toplam 0x40 bayt, dolgu yok. */
#pragma pack(push, 1)
typedef struct nino_rp_registration
{
    char name[0x20];          /* sıfırla biten PS5 adı; son bayt her zaman 0 */
    char regist_key[0x10];    /* ASCII onaltılık, sıfırla doldurulmuş */
    uint8_t morning[0x10];    /* ham oturum anahtarı */
} nino_rp_registration;
#pragma pack(pop)

typedef struct nino_rp_session nino_rp_session;

/* Ağ yığınını hazırlar. Birden çok kez çağrılabilir; her çağrı ilk çağrının sonucunu döner. */
NINO_API int NINO_CALL nino_rp_init(void);

/*
 * PS5 arar; timeout_ms boyunca 500 ms'de bir sorar (bloklar). Hedef yoksa ya da geri çağrı NULL ise 1,
 * soket/iş parçacığı/bellek hatasında -1, değilse 0.
 */
NINO_API int NINO_CALL nino_rp_discover(const char *const *targets, int target_count, int timeout_ms,
                                        nino_rp_found_cb cb, void *user);

NINO_API int NINO_CALL nino_rp_discover_ex(const char *const *targets, int target_count, int timeout_ms,
                                           nino_rp_found_ex_cb cb, void *user);

/* Dinlenmedeki PS5'i uyandırır. host NULL ise 1; chiaki hatasında hata kodu. */
NINO_API int NINO_CALL nino_rp_wake(const char *host, uint64_t credential);

/*
 * PS5 ekranındaki 8 rakamlı eşleştirme koduyla kayıt olur (en çok ~30 sn bloklar).
 * 0 başarı, 1 başarısız (reason'a PS5'in neden kodu), 2 iptal (süre doldu), <0 başlatılamadı ya da geçersiz girdi.
 */
NINO_API int NINO_CALL nino_rp_register(const char *host, const uint8_t account_id[8], uint32_t pin,
                                        nino_rp_registration *out, uint32_t *reason,
                                        nino_rp_log_cb log, void *user);

/*
 * Görüntü oturumu açar (1080p, 30 kare/sn H.264 ister; ses ve kumanda kapalı). Kareler en çok max_fps kez
 * BGRA'ya çevrilip verilir (<= 0 sınırsız). Hata olursa NULL (neden günlüğe hata düzeyinde yazılır).
 */
NINO_API nino_rp_session *NINO_CALL nino_rp_session_start(const char *host, const uint8_t regist_key[0x10],
                                                         const uint8_t morning[0x10], const uint8_t account_id[8],
                                                         int max_fps, nino_rp_frame_cb frame_cb,
                                                         nino_rp_event_cb event_cb, nino_rp_log_cb log_cb,
                                                         void *user);

/* PS5 oturum parolasını (ASCII rakamlar) gönderir. Olay geri çağrısının içinden çağrılmamalı. */
NINO_API int NINO_CALL nino_rp_session_set_login_pin(nino_rp_session *session, const uint8_t *pin, size_t pin_size);

/* Oturumu durdurur, iş parçacıklarını bekler, belleği bırakır. Döndükten sonra geri çağrı gelmez. */
NINO_API void NINO_CALL nino_rp_session_stop(nino_rp_session *session);

#ifdef __cplusplus
}
#endif

#endif /* NINO_NATIVE_H */
