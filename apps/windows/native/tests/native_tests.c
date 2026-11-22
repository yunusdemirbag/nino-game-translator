// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/*
 * Köprünün yerel testleri (PS5 gerekmez). Kullanım: native_tests <sample-1080p.h264>
 * Kaynaklar doğrudan içerilir; iç işlevlere erişilir.
 * NINO_STOP_LOOPS=<n> ortam değişkeni durdurma testlerini n kez yineler (ASan ile yarış aramak için).
 */

#include "../src/util.c"
#include "../src/h264.c"
#include "../src/nino_native.c"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond, ...)                                                   \
    do {                                                                   \
        if (!(cond)) {                                                     \
            failures++;                                                    \
            fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__);          \
            fprintf(stderr, __VA_ARGS__);                                  \
            fprintf(stderr, "\n");                                         \
        }                                                                  \
    } while (0)

static uint64_t now_ms(void) { return chiaki_time_now_monotonic_ms(); }

/* ---------------- Annex-B → erişim birimleri ---------------- */

typedef struct unit
{
    uint8_t *data;
    size_t size;
} unit;

typedef struct units
{
    unit items[64];
    int count;
} units;

static void unit_append(unit *u, const uint8_t *nal, size_t nal_size)
{
    static const uint8_t start[4] = { 0, 0, 0, 1 };
    u->data = realloc(u->data, u->size + 4 + nal_size + AV_INPUT_BUFFER_PADDING_SIZE);
    memcpy(u->data + u->size, start, 4);
    memcpy(u->data + u->size + 4, nal, nal_size);
    u->size += 4 + nal_size;
    memset(u->data + u->size, 0, AV_INPUT_BUFFER_PADDING_SIZE);
}

static void split_units(const uint8_t *buf, size_t len, units *out)
{
    memset(out, 0, sizeof(*out));
    size_t starts[4096];
    int n = 0;
    for (size_t i = 0; i + 3 <= len && n < 4096; i++)
    {
        if (buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1)
        {
            starts[n++] = i + 3;
            i += 2;
        }
    }
    bool has_slice = false;
    for (int k = 0; k < n; k++)
    {
        size_t begin = starts[k];
        size_t end = k + 1 < n ? starts[k + 1] - 3 : len;
        if (k + 1 < n && end > begin && buf[end - 1] == 0)
            end--;
        if (end <= begin)
            continue;
        int type = buf[begin] & 0x1f;
        bool is_slice = type == 1 || type == 5;
        if ((type == 7 || type == 9 || is_slice) && has_slice)
        {
            out->count++;
            has_slice = false;
        }
        if (out->count >= 64)
            break;
        unit_append(&out->items[out->count], buf + begin, end - begin);
        if (is_slice)
            has_slice = true;
    }
    if (has_slice || (out->count < 64 && out->items[out->count].size > 0))
        out->count++;
}

static void free_units(units *u)
{
    for (int i = 0; i < 64; i++)
        free(u->items[i].data);
}

/* ---------------- Testler ---------------- */

static void test_init_twice(void)
{
    CHECK(nino_rp_init() == 0, "first init");
    CHECK(nino_rp_init() == 0, "second init");
}

static void test_reason_line(void)
{
    uint32_t r = 0;
    CHECK(nino_parse_reason_line("Reported Application Reason: 0x80108b02 (Invalid PSN ID)", &r) && r == 0x80108b02,
          "reason line parsed");
    CHECK(!nino_parse_reason_line("Regist waiting for response", &r), "no reason in plain line");
    CHECK(!nino_parse_reason_line(NULL, &r), "NULL line");
    CHECK(!nino_parse_reason_line("Reported Application Reason: 0x (none)", &r), "no digits");
}

static void test_pacer(void)
{
    nino_pacer p;
    nino_pacer_init(&p, 4);
    int passed = 0;
    for (int i = 0; i < 30; i++)
        if (nino_pacer_admit(&p, (uint64_t)i * (1000000 / 30)))
            passed++;
    CHECK(passed == 4 || passed == 5, "4 fps pacer passed %d", passed);

    nino_pacer_init(&p, 0);
    CHECK(nino_pacer_admit(&p, 5) && nino_pacer_admit(&p, 5), "unlimited pacer passes both");
}

static void test_event_codes(void)
{
    CHECK(NINO_RP_EVENT_CONNECTED == 0 && NINO_RP_EVENT_QUIT == 1 && NINO_RP_EVENT_LOGIN_PASSCODE == 2, "event codes");
    CHECK(NINO_RP_QUIT_STOPPED == 0 && NINO_RP_QUIT_IN_USE == 1 && NINO_RP_QUIT_REFUSED == 2
          && NINO_RP_QUIT_NETWORK == 3 && NINO_RP_QUIT_OTHER == 4, "quit codes");
    CHECK(NINO_QUIT_CODE_OTHER == NINO_RP_QUIT_OTHER && NINO_QUIT_CODE_NETWORK == NINO_RP_QUIT_NETWORK, "internal codes");
    CHECK(NINO_RP_LOG_ERROR == 0 && NINO_RP_LOG_WARNING == 1 && NINO_RP_LOG_INFO == 2, "log levels");
    CHECK(NINO_RP_REGIST_OK == 0 && NINO_RP_REGIST_FAILED == 1 && NINO_RP_REGIST_CANCELED == 2, "regist codes");
}

static void test_quit_mapping(void)
{
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_STOPPED) == 0, "stopped");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_IN_USE) == 1, "in use");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_SESSION_REQUEST_CONNECTION_REFUSED) == 2, "session refused");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_CTRL_CONNECTION_REFUSED) == 2, "ctrl refused");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_PSN_REGIST_FAILED) == 2, "psn regist");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_DISCONNECTED) == 3, "remote disc");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_STREAM_CONNECTION_REMOTE_SHUTDOWN) == 3, "remote shutdown");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_CTRL_CONNECT_FAILED) == 3, "ctrl connect");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_STREAM_CONNECTION_UNKNOWN) == 3, "stream unknown");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_SESSION_REQUEST_RP_VERSION_MISMATCH) == 4, "version");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_SESSION_REQUEST_UNKNOWN) == 4, "session unknown");
    CHECK(nino_map_quit_reason(CHIAKI_QUIT_REASON_NONE) == 4, "none");
}

static void test_registration_layout(void)
{
    CHECK(sizeof(nino_rp_registration) == 0x40, "registration size %zu", sizeof(nino_rp_registration));
    CHECK(offsetof(nino_rp_registration, name) == 0x00, "name offset");
    CHECK(offsetof(nino_rp_registration, regist_key) == 0x20, "key offset");
    CHECK(offsetof(nino_rp_registration, morning) == 0x30, "morning offset");

    uint8_t account[8] = { 1, 1, 1, 1, 1, 1, 1, 1 };
    nino_rp_registration out;
    uint32_t reason = 77;
    CHECK(nino_rp_register(NULL, account, 1, &out, &reason, NULL, NULL) == -1, "NULL host");
    CHECK(reason == 0, "reason reset");
    CHECK(nino_rp_register("127.0.0.1", NULL, 1, &out, NULL, NULL, NULL) == -1, "NULL account");
    CHECK(nino_rp_register("127.0.0.1", account, 1, NULL, NULL, NULL, NULL) == -1, "NULL out");
}

typedef struct frame_check
{
    int frames;
    int bad;
} frame_check;

static void check_bgra(nino_h264 *dec, frame_check *fc)
{
    const uint8_t *bgra;
    int w, h, stride;
    if (!nino_h264_to_bgra(dec, &bgra, &w, &h, &stride))
    {
        fc->bad++;
        return;
    }
    fc->frames++;
    if (w != 1920 || h != 1080 || stride < 1920 * 4)
    {
        fc->bad++;
        return;
    }
    const uint8_t *row = bgra + (size_t)stride * 540;
    bool varied = false;
    for (int x = 1; x < w; x++)
    {
        if (memcmp(row, row + x * 4, 3) != 0)
            varied = true;
        if (row[x * 4 + 3] != 255)
        {
            fc->bad++;
            return;
        }
    }
    if (!varied || row[3] != 255)
        fc->bad++;
}

static void on_drained(nino_h264 *dec, void *user)
{
    check_bgra(dec, user);
}

static uint8_t *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)n);
    if (buf && fread(buf, 1, (size_t)n, f) != (size_t)n)
    {
        free(buf);
        buf = NULL;
    }
    fclose(f);
    *len = (size_t)n;
    return buf;
}

static void test_sample_decode(const uint8_t *file, size_t len)
{
    units u;
    split_units(file, len, &u);
    CHECK(u.count == 6, "expected 6 access units, got %d", u.count);
    if (u.count > 0)
    {
        int t0 = u.items[0].data[4] & 0x1f;
        bool has_idr = false;
        for (size_t i = 0; i + 4 < u.items[0].size; i++)
            if (u.items[0].data[i] == 0 && u.items[0].data[i + 1] == 0 && u.items[0].data[i + 2] == 0
                && u.items[0].data[i + 3] == 1 && (u.items[0].data[i + 4] & 0x1f) == 5)
                has_idr = true;
        CHECK((t0 == 7 || t0 == 9) && has_idr, "first unit is SPS/PPS + IDR");
    }

    nino_h264 *dec = nino_h264_open();
    CHECK(dec != NULL, "decoder opens");
    if (!dec)
    {
        free_units(&u);
        return;
    }
    frame_check fc = { 0, 0 };
    for (int i = 0; i < u.count; i++)
    {
        int r = nino_h264_decode(dec, u.items[i].data, u.items[i].size);
        CHECK(r >= 0, "unit %d decodes (r=%d)", i, r);
        if (r == 1)
            check_bgra(dec, &fc);
    }
    CHECK(fc.frames >= 4, "at least 4 frames in loop, got %d", fc.frames);
    int drained = nino_h264_drain(dec, on_drained, &fc);
    CHECK(drained >= 0, "drain ok");
    CHECK(fc.frames == 6, "6 frames after drain, got %d", fc.frames);
    CHECK(fc.bad == 0, "%d bad frames", fc.bad);
    nino_h264_close(dec);

    /* Yeni çözücü yalnız ilk birimle. */
    dec = nino_h264_open();
    if (dec && u.count > 0)
    {
        int r = nino_h264_decode(dec, u.items[0].data, u.items[0].size);
        CHECK(r >= 0, "first unit alone decodes");
        frame_check one = { 0, 0 };
        if (r == 1)
            check_bgra(dec, &one);
        nino_h264_drain(dec, on_drained, &one);
        CHECK(one.frames == 1 && one.bad == 0, "first unit gives exactly 1 frame, got %d", one.frames);
    }
    nino_h264_close(dec);
    free_units(&u);
}

static void test_garbage(void)
{
    nino_h264 *dec = nino_h264_open();
    CHECK(dec != NULL, "decoder opens");
    if (!dec)
        return;
    uint8_t junk[8 + AV_INPUT_BUFFER_PADDING_SIZE];
    memset(junk, 0, sizeof(junk));
    const uint8_t head[8] = { 0, 0, 0, 1, 0x65, 0xff, 0x00, 0x12 };
    memcpy(junk, head, 8);
    CHECK(nino_h264_decode(dec, junk, 8) <= 0, "garbage gives no frame");
    CHECK(nino_h264_decode(dec, NULL, 0) == 0, "NULL gives 0");
    CHECK(nino_h264_decode(dec, junk, 0) == 0, "size 0 gives 0");
    nino_h264_close(dec);
}

static int found_count = 0;

static void count_found(const char *host, const char *name, int awake, void *user)
{
    (void)host; (void)name; (void)awake; (void)user;
    found_count++;
}

static void count_found_ex(const char *host, const char *name, int awake, const char *id, const char *app, void *user)
{
    (void)host; (void)name; (void)awake; (void)id; (void)app; (void)user;
    found_count++;
}

static void test_discovery(void)
{
    const char *probe[2] = { "127.0.0.1", "not-an-address" };
    found_count = 0;
    uint64_t t0 = now_ms();
    int r = nino_rp_discover(probe, 2, 600, count_found, NULL);
    uint64_t took = now_ms() - t0;
    CHECK(r == 0, "discover returns 0 (%d)", r);
    CHECK(took >= 500 && took < 3000, "discover took %llu ms", (unsigned long long)took);
    CHECK(found_count == 0, "found nothing");
    CHECK(nino_rp_discover(NULL, 0, 600, count_found, NULL) != 0, "no targets");

    found_count = 0;
    r = nino_rp_discover_ex(probe, 1, 600, count_found_ex, NULL);
    CHECK(r == 0 && found_count == 0, "discover_ex returns 0, nothing found");
    CHECK(nino_rp_discover_ex(probe, 1, 600, NULL, NULL) != 0, "NULL callback");
    CHECK(nino_rp_wake(NULL, 1) == 1, "wake NULL host");
    /* Geçici keşif nesnesiyle gerçek gönderim (geri döngüye; yanıt beklenmez). */
    CHECK(nino_rp_wake("127.0.0.1", 0x1a2b3c4dULL) == 0, "wake loopback sends");
}

typedef struct quit_watch
{
    ChiakiMutex mutex;
    ChiakiCond cond;
    bool quit;
    int reason;
} quit_watch;

static void on_event(int event, int quit_reason, const char *text, void *user)
{
    (void)text;
    quit_watch *w = user;
    if (event != NINO_RP_EVENT_QUIT)
        return;
    chiaki_mutex_lock(&w->mutex);
    w->quit = true;
    w->reason = quit_reason;
    chiaki_cond_signal(&w->cond);
    chiaki_mutex_unlock(&w->mutex);
}

static bool quit_seen(void *user) { return ((quit_watch *)user)->quit; }

static void quiet_log(int level, const char *msg, void *user) { (void)level; (void)msg; (void)user; }

static void test_closed_port_session(void)
{
    uint8_t rkey[16];
    uint8_t mkey[16];
    uint8_t acct[8];
    memset(rkey, 0x31, sizeof rkey);
    memset(mkey, 0x01, sizeof mkey);
    memset(acct, 0x01, sizeof acct);
    quit_watch w;
    memset(&w, 0, sizeof(w));
    chiaki_mutex_init(&w.mutex, false);
    chiaki_cond_init(&w.cond);

    nino_rp_session *s = nino_rp_session_start("127.0.0.1", rkey, mkey, acct, 15, NULL, on_event, quiet_log, &w);
    CHECK(s != NULL, "session handle");
    if (s)
    {
        chiaki_mutex_lock(&w.mutex);
        chiaki_cond_timedwait_pred(&w.cond, &w.mutex, 15000, quit_seen, &w);
        bool quit = w.quit;
        int reason = w.reason;
        chiaki_mutex_unlock(&w.mutex);
        CHECK(quit, "quit event within 15 s");
        CHECK(reason != NINO_RP_QUIT_STOPPED, "quit reason is not 'stopped' (%d)", reason);
        uint64_t t0 = now_ms();
        nino_rp_session_stop(s);
        uint64_t took = now_ms() - t0;
        CHECK(took < 2000, "stop took %llu ms", (unsigned long long)took);
    }
    chiaki_cond_fini(&w.cond);
    chiaki_mutex_fini(&w.mutex);
}

static void test_start_then_stop(void)
{
    uint8_t zero16[16] = { 0 }, zero8[8] = { 0 };
    nino_rp_session *s = nino_rp_session_start("127.0.0.1", zero16, zero16, zero8, 0, NULL, NULL, NULL, NULL);
    CHECK(s != NULL, "session handle");
    nino_rp_session_stop(s);
    nino_rp_session_stop(NULL);
    CHECK(nino_rp_session_set_login_pin(NULL, (const uint8_t *)"1234", 4) == CHIAKI_ERR_INVALID_DATA, "pin on NULL");
}

int main(int argc, char **argv)
{
    if (argc < 2)
    {
        fprintf(stderr, "kullanım: %s <örnek H.264 dosyası (sample-1080p.h264)>\n", argv[0]);
        return 2;
    }
    size_t len = 0;
    uint8_t *sample = read_file(argv[1], &len);
    if (!sample)
    {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 2;
    }
    uint8_t *padded = calloc(1, len + AV_INPUT_BUFFER_PADDING_SIZE);
    memcpy(padded, sample, len);
    free(sample);

    test_init_twice();
    test_reason_line();
    test_pacer();
    test_event_codes();
    test_quit_mapping();
    test_registration_layout();
    test_sample_decode(padded, len);
    test_garbage();
    test_discovery();

    int loops = 1;
    const char *env = getenv("NINO_STOP_LOOPS");
    if (env && atoi(env) > 0)
        loops = atoi(env);
    for (int i = 0; i < loops; i++)
    {
        test_closed_port_session();
        test_start_then_stop();
    }
    free(padded);

    if (failures)
    {
        fprintf(stderr, "%d native test(s) failed\n", failures);
        return 1;
    }
    printf("all native tests passed\n");
    return 0;
}
