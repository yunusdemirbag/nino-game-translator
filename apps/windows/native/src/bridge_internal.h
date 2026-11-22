// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/* Köprünün iç parçaları: testler bunlara doğrudan erişir (dışa açılmaz). */

#ifndef NINO_BRIDGE_INTERNAL_H
#define NINO_BRIDGE_INTERNAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <chiaki/session.h>

/* ---- Kare sınırlayıcı ---- */

typedef struct nino_pacer
{
    uint64_t min_gap_us; /* 0: sınır yok */
    uint64_t last_us;
    bool has_last;
} nino_pacer;

void nino_pacer_init(nino_pacer *pacer, int max_fps);

/* now_us anında bir kare geçirilsin mi; geçerse son an güncellenir. */
bool nino_pacer_admit(nino_pacer *pacer, uint64_t now_us);

/* ---- chiaki günlük satırı okuyucusu ---- */

/* "Reported Application Reason: 0x<hex>" satırından neden kodunu okur; yoksa false. */
bool nino_parse_reason_line(const char *line, uint32_t *reason);

/* chiaki'nin kapanma nedenini köprünün 0..4 kodlarına çevirir (nino_native.h'deki NINO_RP_QUIT_* ile aynı). */
#define NINO_QUIT_CODE_STOPPED 0
#define NINO_QUIT_CODE_IN_USE  1
#define NINO_QUIT_CODE_REFUSED 2
#define NINO_QUIT_CODE_NETWORK 3
#define NINO_QUIT_CODE_OTHER   4
int nino_map_quit_reason(ChiakiQuitReason reason);

/* ---- H.264 çözücü (FFmpeg) ---- */

typedef struct nino_h264 nino_h264;

nino_h264 *nino_h264_open(void);
void nino_h264_close(nino_h264 *dec);

/* Bir erişim birimi çözer: 1 kare hazır, 0 kare yok, -1 hata. data NULL ya da size 0 ise 0. */
int nino_h264_decode(nino_h264 *dec, const uint8_t *data, size_t size);

/* Son çözülen kareyi BGRA'ya çevirir; başarıda true ve çıktı alanları doldurulur. */
bool nino_h264_to_bgra(nino_h264 *dec, const uint8_t **bgra, int *width, int *height, int *stride);

/* Çözücüyü boşaltır (NULL paket); çıkan her kare için each çağrılır. Çıkan kare sayısı ya da -1. */
int nino_h264_drain(nino_h264 *dec, void (*each)(nino_h264 *dec, void *user), void *user);

/* ---- Platform ---- */

void nino_sleep_ms(unsigned int ms);

#endif /* NINO_BRIDGE_INTERNAL_H */
