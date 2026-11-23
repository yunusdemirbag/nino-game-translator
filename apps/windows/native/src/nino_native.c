// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/* nino_native: chiaki-ng v1.10.1 üstünde PS5 arama, uyandırma, kayıt ve görüntü oturumu. */

#define NINO_NATIVE_BUILDING 1
#include "nino_native.h"
#include "bridge_internal.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <chiaki/common.h>
#include <chiaki/discovery.h>
#include <chiaki/log.h>
#include <chiaki/regist.h>
#include <chiaki/session.h>
#include <chiaki/thread.h>
#include <chiaki/time.h>

#include <libavutil/log.h>

#if defined(_WIN32)
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <mstcpip.h>
#  include <windows.h>
#  ifndef SIO_UDP_CONNRESET
#    define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12)
#  endif
#else
#  include <arpa/inet.h>
#  include <netdb.h>
#  include <netinet/in.h>
#  include <pthread.h>
#endif

/* ------------------------------------------------------------------ */
/* Günlük yardımcıları                                                 */
/* ------------------------------------------------------------------ */

static int level_of(ChiakiLogLevel level)
{
    if (level & CHIAKI_LOG_ERROR)
        return NINO_RP_LOG_ERROR;
    if (level & CHIAKI_LOG_WARNING)
        return NINO_RP_LOG_WARNING;
    return NINO_RP_LOG_INFO;
}

/* chiaki NULL geri çağrıda stdout'a yazar; satırları düşürmek için boş geri çağrı verilir. */
static void drop_log(ChiakiLogLevel level, const char *msg, void *user)
{
    (void)level;
    (void)msg;
    (void)user;
}

/* ------------------------------------------------------------------ */
/* Başlatma                                                            */
/* ------------------------------------------------------------------ */

static int init_result = -1;

static void init_once_body(void)
{
    av_log_set_level(AV_LOG_QUIET);
    init_result = (int)chiaki_lib_init();
}

#if defined(_WIN32)
static INIT_ONCE init_once_flag = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK init_once_win(PINIT_ONCE once, PVOID param, PVOID *context)
{
    (void)once;
    (void)param;
    (void)context;
    init_once_body();
    return TRUE;
}
#else
static pthread_once_t init_once_flag = PTHREAD_ONCE_INIT;
#endif

NINO_API int NINO_CALL nino_rp_init(void)
{
#if defined(_WIN32)
    InitOnceExecuteOnce(&init_once_flag, init_once_win, NULL, NULL);
#else
    pthread_once(&init_once_flag, init_once_body);
#endif
    return init_result;
}

/* ------------------------------------------------------------------ */
/* Arama                                                               */
/* ------------------------------------------------------------------ */

typedef struct discover_job
{
    nino_rp_found_cb found;
    nino_rp_found_ex_cb found_ex;
    void *user;
} discover_job;

static void on_discovered(ChiakiDiscoveryHost *host, void *user)
{
    discover_job *job = user;
    if (!host || !host->host_addr)
        return;
    if (!chiaki_discovery_host_is_ps5(host))
        return;
    const char *label = host->host_name;
    if (!label)
        label = "PS5";
    /* Yalnız READY "uyanık"; başka her durum dinlenme sayılır. */
    int ready = (host->state == CHIAKI_DISCOVERY_HOST_STATE_READY);
    if (job->found_ex)
        job->found_ex(host->host_addr, label, ready, host->running_app_titleid, host->running_app_name, job->user);
    else if (job->found)
        job->found(host->host_addr, label, ready, job->user);
}

static bool to_ipv4(const char *text, struct sockaddr_in *out)
{
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST; /* ad çözümü yok: hedefler hep IP adresidir */
    struct addrinfo *found = NULL;
    if (getaddrinfo(text, NULL, &hints, &found) != 0 || !found)
        return false;
    bool ok = false;
    for (struct addrinfo *ai = found; ai; ai = ai->ai_next)
    {
        if (ai->ai_family == AF_INET && ai->ai_addrlen <= sizeof(*out))
        {
            memset(out, 0, sizeof(*out));
            memcpy(out, ai->ai_addr, ai->ai_addrlen);
            out->sin_port = htons(CHIAKI_DISCOVERY_PORT_PS5);
            ok = true;
            break;
        }
    }
    freeaddrinfo(found);
    return ok;
}

static int run_discovery(const char *const *targets, int target_count, int timeout_ms, discover_job *job)
{
    ChiakiLog log;
    chiaki_log_init(&log, CHIAKI_LOG_ERROR, drop_log, NULL);

    struct sockaddr_in *addrs = calloc((size_t)target_count, sizeof(struct sockaddr_in));
    if (!addrs)
        return -1;
    int addr_count = 0;
    for (int i = 0; i < target_count; i++)
    {
        if (targets[i] && to_ipv4(targets[i], &addrs[addr_count]))
            addr_count++;
    }

    ChiakiDiscovery discovery;
    if (chiaki_discovery_init(&discovery, &log, AF_INET) != CHIAKI_ERR_SUCCESS)
    {
        free(addrs);
        return -1;
    }

#if defined(_WIN32)
    {
        /* Ulaşılamayan adresten gelen ICMP yanıtı recvfrom'u bozup arama döngüsünü bitirmesin. */
        BOOL connreset_on = FALSE;
        DWORD out_len = 0;
        WSAIoctl(discovery.socket, SIO_UDP_CONNRESET,
                 &connreset_on, sizeof connreset_on, NULL, 0, &out_len, NULL, NULL);
    }
#endif

    ChiakiDiscoveryThread thread;
    if (chiaki_discovery_thread_start(&thread, &discovery, on_discovered, job) != CHIAKI_ERR_SUCCESS)
    {
        chiaki_discovery_fini(&discovery);
        free(addrs);
        return -1;
    }

    ChiakiDiscoveryPacket packet;
    memset(&packet, 0, sizeof(packet));
    packet.cmd = CHIAKI_DISCOVERY_CMD_SRCH;
    packet.protocol_version = CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5;

    uint64_t deadline = chiaki_time_now_monotonic_ms() + (uint64_t)(timeout_ms > 0 ? timeout_ms : 0);
    do
    {
        for (int i = 0; i < addr_count; i++)
            chiaki_discovery_send(&discovery, &packet, (struct sockaddr *)&addrs[i], sizeof(addrs[i]));
        nino_sleep_ms(500);
    } while (chiaki_time_now_monotonic_ms() < deadline);

    chiaki_discovery_thread_stop(&thread);
    chiaki_discovery_fini(&discovery);
    free(addrs);
    return 0;
}

NINO_API int NINO_CALL nino_rp_discover(const char *const *targets, int target_count, int timeout_ms,
                                        nino_rp_found_cb cb, void *user)
{
    if (!targets || target_count <= 0 || !cb)
        return 1;
    discover_job job = { cb, NULL, user };
    return run_discovery(targets, target_count, timeout_ms, &job);
}

NINO_API int NINO_CALL nino_rp_discover_ex(const char *const *targets, int target_count, int timeout_ms,
                                           nino_rp_found_ex_cb cb, void *user)
{
    if (!targets || target_count <= 0 || !cb)
        return 1;
    discover_job job = { NULL, cb, user };
    return run_discovery(targets, target_count, timeout_ms, &job);
}

/* ------------------------------------------------------------------ */
/* Uyandırma                                                           */
/* ------------------------------------------------------------------ */

NINO_API int NINO_CALL nino_rp_wake(const char *host, uint64_t credential)
{
    if (!host)
        return 1;
    ChiakiLog log;
    chiaki_log_init(&log, 0, drop_log, NULL);
    return (int)chiaki_discovery_wakeup(&log, NULL, host, credential, true);
}

/* ------------------------------------------------------------------ */
/* Kayıt                                                               */
/* ------------------------------------------------------------------ */

typedef struct regist_job
{
    ChiakiMutex mutex;
    ChiakiCond cond;
    bool done;
    ChiakiRegistEventType outcome;
    bool has_host;
    ChiakiRegisteredHost host;
    uint32_t reason;
    ChiakiLog log;
    nino_rp_log_cb forward;
    void *user;
} regist_job;

static void regist_log(ChiakiLogLevel level, const char *msg, void *user)
{
    regist_job *job = user;
    uint32_t reason;
    if (nino_parse_reason_line(msg, &reason))
    {
        chiaki_mutex_lock(&job->mutex);
        job->reason = reason;
        chiaki_mutex_unlock(&job->mutex);
    }
    if (job->forward)
        job->forward(level_of(level), msg, job->user);
}

static void regist_event(ChiakiRegistEvent *event, void *user)
{
    regist_job *job = user;
    chiaki_mutex_lock(&job->mutex);
    if (!job->done)
    {
        job->outcome = event ? event->type : CHIAKI_REGIST_EVENT_TYPE_FINISHED_FAILED;
        if (event && event->type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS && event->registered_host)
        {
            job->host = *event->registered_host;
            job->has_host = true;
        }
        job->done = true;
        chiaki_cond_signal(&job->cond);
    }
    chiaki_mutex_unlock(&job->mutex);
}

static bool regist_finished(void *user)
{
    return ((regist_job *)user)->done;
}

NINO_API int NINO_CALL nino_rp_register(const char *host, const uint8_t account_id[8], uint32_t pin,
                                        nino_rp_registration *out, uint32_t *reason,
                                        nino_rp_log_cb log, void *user)
{
    if (reason)
        *reason = 0;
    if (!host || !account_id || !out)
        return -1;

    regist_job *job = calloc(1, sizeof(*job));
    if (!job)
        return -1;
    if (chiaki_mutex_init(&job->mutex, false) != CHIAKI_ERR_SUCCESS)
    {
        free(job);
        return -1;
    }
    if (chiaki_cond_init(&job->cond) != CHIAKI_ERR_SUCCESS)
    {
        chiaki_mutex_fini(&job->mutex);
        free(job);
        return -1;
    }
    job->forward = log;
    job->user = user;
    chiaki_log_init(&job->log, CHIAKI_LOG_ERROR | CHIAKI_LOG_WARNING | CHIAKI_LOG_INFO, regist_log, job);

    ChiakiRegistInfo ri;
    memset(&ri, 0, sizeof(ri));
    ri.target = CHIAKI_TARGET_PS5_1;
    ri.host = host;
    ri.broadcast = false;
    ri.psn_online_id = NULL;               /* çevrimiçi kimlik yok: yalnız 8 baytlık hesap kimliği */
    memcpy(ri.psn_account_id, account_id, sizeof ri.psn_account_id);
    ri.pin = pin;
    ri.console_pin = 0;
    ri.holepunch_info = NULL;              /* yalnız yerel ağ: internet üzerinden kayıt yok */
    ri.rudp = NULL;

    ChiakiRegist regist;
    ChiakiErrorCode err = chiaki_regist_start(&regist, &job->log, &ri, regist_event, job);
    if (err != CHIAKI_ERR_SUCCESS)
    {
        if (log)
        {
            char line[160];
            snprintf(line, sizeof(line), "Regist start failed: %s", chiaki_error_string(err));
            log(NINO_RP_LOG_ERROR, line, user);
        }
        chiaki_cond_fini(&job->cond);
        chiaki_mutex_fini(&job->mutex);
        free(job);
        return -1;
    }

    chiaki_mutex_lock(&job->mutex);
    err = chiaki_cond_timedwait_pred(&job->cond, &job->mutex, 30000, regist_finished, job);
    if (err == CHIAKI_ERR_TIMEOUT)
    {
        chiaki_mutex_unlock(&job->mutex);
        chiaki_regist_stop(&regist); /* "iptal" olayını üretir */
        chiaki_mutex_lock(&job->mutex);
        chiaki_cond_wait_pred(&job->cond, &job->mutex, regist_finished, job);
    }
    chiaki_mutex_unlock(&job->mutex);

    chiaki_regist_fini(&regist);

    int result;
    if (job->outcome == CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS && job->has_host)
    {
        memset(out, 0, sizeof(*out));
        memcpy(out->name, job->host.server_nickname, sizeof(out->name));
        out->name[sizeof(out->name) - 1] = 0;
        memcpy(out->regist_key, job->host.rp_regist_key, sizeof(out->regist_key));
        memcpy(out->morning, job->host.rp_key, sizeof(out->morning));
        result = NINO_RP_REGIST_OK;
    }
    else if (job->outcome == CHIAKI_REGIST_EVENT_TYPE_FINISHED_CANCELED)
    {
        result = NINO_RP_REGIST_CANCELED;
    }
    else
    {
        if (reason)
            *reason = job->reason;
        result = NINO_RP_REGIST_FAILED;
    }

    chiaki_cond_fini(&job->cond);
    chiaki_mutex_fini(&job->mutex);
    free(job);
    return result;
}

/* ------------------------------------------------------------------ */
/* Görüntü oturumu                                                     */
/* ------------------------------------------------------------------ */

struct nino_rp_session
{
    ChiakiSession chiaki;
    ChiakiLog log;

    /* Durdurma ile şifre gönderme aynı kilitte; durmuş oturuma bir şey gönderilmez. */
    ChiakiMutex guard;
    /* 1 olduktan sonra kare ve olay bildirilmez, çözülmez (kapanmış bağlantıya iş gitmez). */
    atomic_int closing;
    /* 1 olduktan sonra günlük de iletilmez (join bitti, bırakılıyor). */
    atomic_int released;

    nino_h264 *decoder;
    nino_pacer pacer;

    nino_rp_frame_cb frame_cb;
    nino_rp_event_cb event_cb;
    nino_rp_log_cb log_cb;
    void *user;
};

static void session_log(ChiakiLogLevel level, const char *msg, void *user)
{
    nino_rp_session *s = user;
    if (atomic_load(&s->released))
        return;
    if (s->log_cb)
        s->log_cb(level_of(level), msg, s->user);
}

static void session_error(nino_rp_log_cb log, void *user, const char *what, ChiakiErrorCode err)
{
    if (!log)
        return;
    char line[200];
    if (what && err != CHIAKI_ERR_SUCCESS)
        snprintf(line, sizeof(line), "%s: %s", what, chiaki_error_string(err));
    else
        snprintf(line, sizeof(line), "%s", what ? what : "error");
    log(NINO_RP_LOG_ERROR, line, user);
}

static bool session_video(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)
{
    (void)frames_lost;
    (void)frame_recovered;
    nino_rp_session *s = user;
    if (atomic_load(&s->closing) || !s->decoder)
        return true;

    /* Her örnek çözülmeli: sonraki kareler öncekilere dayanır. */
    int r = nino_h264_decode(s->decoder, buf, buf_size);
    if (r < 0)
        return false; /* chiaki bozuk kare sayar, yeni anahtar kare ister */
    if (r == 0 || !s->frame_cb)
        return true;
    if (!nino_pacer_admit(&s->pacer, chiaki_time_now_monotonic_us()))
        return true;

    const uint8_t *bgra;
    int w, h, stride;
    if (nino_h264_to_bgra(s->decoder, &bgra, &w, &h, &stride) && !atomic_load(&s->closing))
        s->frame_cb(bgra, w, h, stride, s->user);
    return true;
}

static void session_event(ChiakiEvent *event, void *user)
{
    nino_rp_session *s = user;
    if (!event || !s->event_cb || atomic_load(&s->closing))
        return;
    switch (event->type)
    {
        case CHIAKI_EVENT_CONNECTED:
            s->event_cb(NINO_RP_EVENT_CONNECTED, 0, NULL, s->user);
            break;
        case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
            s->event_cb(NINO_RP_EVENT_LOGIN_PASSCODE, event->login_pin_request.pin_incorrect ? 1 : 0, NULL, s->user);
            break;
        case CHIAKI_EVENT_QUIT:
        {
            int code = nino_map_quit_reason(event->quit.reason);
            const char *text = code == NINO_RP_QUIT_OTHER ? chiaki_quit_reason_string(event->quit.reason)
                                                          : event->quit.reason_str;
            s->event_cb(NINO_RP_EVENT_QUIT, code, text, s->user);
            break;
        }
        default:
            break;
    }
}

/* PS5 korumalı içerik bildirimi: chiaki bunu koşulsuz çağırır, atanmalıdır. Akış sürer. */
static void session_display(void *user, bool cant_display)
{
    nino_rp_session *s = user;
    chiaki_log(&s->log, CHIAKI_LOG_INFO, cant_display ? "PS5 stream can't display (protected content)"
                                                      : "PS5 stream can display again");
}

NINO_API nino_rp_session *NINO_CALL nino_rp_session_start(const char *host, const uint8_t regist_key[0x10],
                                                         const uint8_t morning[0x10], const uint8_t account_id[8],
                                                         int max_fps, nino_rp_frame_cb frame_cb,
                                                         nino_rp_event_cb event_cb, nino_rp_log_cb log_cb,
                                                         void *user)
{
    if (!host || !regist_key || !morning || !account_id)
        return NULL;

    nino_rp_session *s = calloc(1, sizeof(*s));
    if (!s)
        return NULL;
    s->frame_cb = frame_cb;
    s->event_cb = event_cb;
    s->log_cb = log_cb;
    s->user = user;
    atomic_init(&s->closing, 0);
    atomic_init(&s->released, 0);
    if (chiaki_mutex_init(&s->guard, false) != CHIAKI_ERR_SUCCESS)
    {
        free(s);
        return NULL;
    }
    /* Bilgi düzeyi gerekli: görüntü duraklaması satırları bilgi düzeyindedir. */
    chiaki_log_init(&s->log, CHIAKI_LOG_ERROR | CHIAKI_LOG_WARNING | CHIAKI_LOG_INFO, session_log, s);
    nino_pacer_init(&s->pacer, max_fps);

    s->decoder = nino_h264_open();
    if (!s->decoder)
    {
        session_error(log_cb, user, "H.264 decoder could not be opened", CHIAKI_ERR_SUCCESS);
        chiaki_mutex_fini(&s->guard);
        free(s);
        return NULL;
    }

    ChiakiConnectInfo ci;
    memset(&ci, 0, sizeof(ci));
    ci.ps5 = true;
    ci.host = host;
    memcpy(ci.regist_key, regist_key, sizeof ci.regist_key);
    memcpy(ci.morning, morning, sizeof ci.morning);
    /* 1080p / 30 kare/sn H.264; PS5 desteklemezse chiaki profili kendisi düşürür. */
    chiaki_connect_video_profile_preset(&ci.video_profile, CHIAKI_VIDEO_RESOLUTION_PRESET_1080p,
                                        CHIAKI_VIDEO_FPS_PRESET_30);
    ci.video_profile.codec = CHIAKI_CODEC_H264;
    ci.video_profile_auto_downgrade = true;
    ci.enable_keyboard = false;
    ci.enable_dualsense = false;
    ci.audio_video_disabled = CHIAKI_AUDIO_DISABLED;   /* ses kapalı, görüntü açık */
    ci.auto_regist = false;
    ci.holepunch_session = NULL;                       /* yalnız yerel ağ */
    ci.rudp_sock = NULL;
    memcpy(ci.psn_account_id, account_id, sizeof ci.psn_account_id);
    ci.packet_loss_max = 0.05;
    ci.enable_idr_on_fec_failure = true;

    ChiakiErrorCode err = chiaki_session_init(&s->chiaki, &ci, &s->log);
    if (err != CHIAKI_ERR_SUCCESS)
    {
        session_error(log_cb, user, "Session init failed", err);
        nino_h264_close(s->decoder);
        chiaki_mutex_fini(&s->guard);
        free(s);
        return NULL;
    }

    chiaki_session_set_event_cb(&s->chiaki, session_event, s);
    chiaki_session_set_video_sample_cb(&s->chiaki, session_video, s);
    ChiakiCtrlDisplaySink sink;
    sink.user = s;
    sink.cantdisplay_cb = session_display;
    chiaki_session_ctrl_set_display_sink(&s->chiaki, &sink);

    err = chiaki_session_start(&s->chiaki);
    if (err != CHIAKI_ERR_SUCCESS)
    {
        session_error(log_cb, user, "Session start failed", err);
        /* İş parçacığı başlamadı: beklenecek bir şey yok. */
        atomic_store(&s->released, 1);
        chiaki_session_fini(&s->chiaki);
        nino_h264_close(s->decoder);
        chiaki_mutex_fini(&s->guard);
        free(s);
        return NULL;
    }
    return s;
}

NINO_API int NINO_CALL nino_rp_session_set_login_pin(nino_rp_session *session, const uint8_t *pin, size_t pin_size)
{
    if (!session || !pin || pin_size == 0)
        return CHIAKI_ERR_INVALID_DATA;
    chiaki_mutex_lock(&session->guard);
    int r;
    if (atomic_load(&session->closing))
        r = CHIAKI_ERR_CANCELED;
    else
        r = (int)chiaki_session_set_login_pin(&session->chiaki, pin, pin_size);
    chiaki_mutex_unlock(&session->guard);
    return r;
}

NINO_API void NINO_CALL nino_rp_session_stop(nino_rp_session *session)
{
    if (!session)
        return;

    /* Sıra: bayrak → dur → bekle (join) → bırak. Bayraktan sonra kare/olay bildirilmez. */
    chiaki_mutex_lock(&session->guard);
    atomic_store(&session->closing, 1);
    chiaki_session_stop(&session->chiaki);
    chiaki_mutex_unlock(&session->guard);

    chiaki_session_join(&session->chiaki);
    atomic_store(&session->released, 1);

    chiaki_session_fini(&session->chiaki);
    nino_h264_close(session->decoder);
    session->decoder = NULL;
    chiaki_mutex_fini(&session->guard);
    free(session);
}
