// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/* Kare sınırlayıcı, günlük satırı okuyucusu, kapanma nedeni eşlemesi, uyuma. */

#include "bridge_internal.h"

#include <string.h>

#if defined(_WIN32)
#  include <windows.h>
#else
#  include <time.h>
#endif

void nino_pacer_init(nino_pacer *pacer, int max_fps)
{
    pacer->min_gap_us = max_fps > 0 ? (uint64_t)(1000000 / max_fps) : 0;
    pacer->last_us = 0;
    pacer->has_last = false;
}

bool nino_pacer_admit(nino_pacer *pacer, uint64_t now_us)
{
    if (pacer->has_last && now_us - pacer->last_us < pacer->min_gap_us)
        return false;
    pacer->last_us = now_us;
    pacer->has_last = true;
    return true;
}

static int hex_digit(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

bool nino_parse_reason_line(const char *line, uint32_t *reason)
{
    static const char marker[] = "Reported Application Reason: 0x";
    if (!line)
        return false;
    const char *at = strstr(line, marker);
    if (!at)
        return false;
    at += sizeof(marker) - 1;

    uint32_t value = 0;
    int digits = 0;
    for (; hex_digit(*at) >= 0; at++, digits++)
        value = (value << 4) | (uint32_t)hex_digit(*at);
    if (digits == 0)
        return false;
    if (reason)
        *reason = value;
    return true;
}

int nino_map_quit_reason(ChiakiQuitReason reason)
{
    static const struct
    {
        ChiakiQuitReason chiaki;
        int nino;
    } table[] = {
        { CHIAKI_QUIT_REASON_STOPPED, NINO_QUIT_CODE_STOPPED },
        { CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE, NINO_QUIT_CODE_IN_USE },
        { CHIAKI_QUIT_REASON_SESSION_REQUEST_CONNECTION_REFUSED, NINO_QUIT_CODE_REFUSED },
        { CHIAKI_QUIT_REASON_CTRL_CONNECTION_REFUSED, NINO_QUIT_CODE_REFUSED },
        { CHIAKI_QUIT_REASON_PSN_REGIST_FAILED, NINO_QUIT_CODE_REFUSED },
        { CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_DISCONNECTED, NINO_QUIT_CODE_NETWORK },
        { CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_SHUTDOWN, NINO_QUIT_CODE_NETWORK },
        { CHIAKI_QUIT_REASON_CTRL_CONNECT_FAILED, NINO_QUIT_CODE_NETWORK },
        { CHIAKI_QUIT_REASON_STREAM_CONNECTION_UNKNOWN, NINO_QUIT_CODE_NETWORK },
    };
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++)
        if (table[i].chiaki == reason)
            return table[i].nino;
    return NINO_QUIT_CODE_OTHER; /* sürüm uyuşmazlığı, RP çöktü, bilinmeyenler… */
}

void nino_sleep_ms(unsigned int ms)
{
#if defined(_WIN32)
    Sleep(ms);
#else
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    while (nanosleep(&ts, &ts) != 0)
        ;
#endif
}
