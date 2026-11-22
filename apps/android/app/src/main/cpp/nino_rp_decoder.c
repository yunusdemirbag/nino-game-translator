// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// H.264 çözücü: AMediaCodec, yüzeysiz (ByteBuffer çıkışı). Görünür Y düzlemi sıkıştırılır, arkasına yarım
// çözünürlüklü renk NV12 sırasıyla eklenir. Donanım çözücü sorun çıkarırsa yazılım çözücüye geçilir.
#include "nino_rp.h"

#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define MIME "video/avc"
#define COLOR_FLEXIBLE 0x7F420888
#define COLOR_I420 19
#define COLOR_PACKED_PLANAR 20
#define COLOR_NV12 21
#define COLOR_PACKED_SEMI 39
#define COLOR_QCOM_NV12 0x7FA30C04
#define COLOR_YV12 0x32315659
#define COLOR_NV21 0x11
#define COLOR_FLEX_ALT 0x23
#define HEADER_WAIT_US 500000
#define SAMPLE_WAIT_US 10000
#define OUTPUT_WAIT_US 100000
#define MAX_ERRORS 30
#define MAX_STRIDE 16384
#define MIN_SIDE 16

static const char *const SOFTWARE_NAMES[] = { "c2.android.avc.decoder", "OMX.google.h264.decoder" };

enum { LAYOUT_SEMI, LAYOUT_SEMI_VU, LAYOUT_PLANAR, LAYOUT_YV12 };

typedef struct {
	bool known;
	bool readable;
	int color, width, height, stride, slice;
	int left, top, vis_w, vis_h;
	int layout;
} OutFormat;

struct nino_decoder_t {
	pthread_mutex_t codec_lock; // giriş ve çözücünün ömrü (kilit sırası: önce bu)
	pthread_mutex_t out_lock;   // çıkış arabelleği okuması (sonra bu)
	AMediaCodec *codec;
	bool software;
	bool tried_software_fallback;
	pthread_t out_thread;
	bool out_running;
	atomic_bool out_stop;
	atomic_bool want_software;
	atomic_int errors;
	atomic_llong frames;

	int width, height;
	uint8_t *header;
	size_t header_size;
	bool header_fed;
	int64_t pts;

	OutFormat fmt;
	uint8_t *out_buf;
	size_t out_cap;
	bool warned_small;
	bool warned_format;

	int min_interval_ms;
	uint64_t last_emit_ms;
	NinoFrameCb cb;
	void *user;
};

static void *output_thread(void *arg);

static AMediaCodec *create_codec(bool software)
{
	if(!software)
		return AMediaCodec_createDecoderByType(MIME);
	for(size_t i = 0; i < sizeof(SOFTWARE_NAMES) / sizeof(SOFTWARE_NAMES[0]); i++)
	{
		AMediaCodec *c = AMediaCodec_createCodecByName(SOFTWARE_NAMES[i]);
		if(c)
			return c;
	}
	return NULL;
}

static bool open_kind(NinoDecoder *d, bool software)
{
	AMediaCodec *c = create_codec(software);
	if(!c)
		return false;
	AMediaFormat *f = AMediaFormat_new();
	AMediaFormat_setString(f, AMEDIAFORMAT_KEY_MIME, MIME);
	AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_WIDTH, d->width);
	AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_HEIGHT, d->height);
	AMediaFormat_setInt32(f, AMEDIAFORMAT_KEY_COLOR_FORMAT, COLOR_FLEXIBLE);
	AMediaFormat_setInt32(f, "low-latency", 1); // Android 11+; desteklemeyen yok sayar
	media_status_t st = AMediaCodec_configure(c, f, NULL, NULL, 0);
	AMediaFormat_delete(f);
	if(st == AMEDIA_OK)
		st = AMediaCodec_start(c);
	if(st != AMEDIA_OK)
	{
		AMediaCodec_delete(c);
		return false;
	}
	d->codec = c;
	d->software = software;
	d->header_fed = false;
	memset(&d->fmt, 0, sizeof(d->fmt));
	d->warned_small = false;
	d->warned_format = false;
	atomic_store(&d->errors, 0);
	atomic_store(&d->want_software, false);
	atomic_store(&d->out_stop, false);
	d->out_running = pthread_create(&d->out_thread, NULL, output_thread, d) == 0;
	if(!d->out_running)
	{
		AMediaCodec_stop(c);
		AMediaCodec_delete(c);
		d->codec = NULL;
		return false;
	}
	nino_logi("Çözücü açıldı: %s", software ? "yazılım" : "donanım");
	return true;
}

// codec_lock tutulurken çağrılır.
static void close_codec(NinoDecoder *d)
{
	if(!d->codec)
		return;
	atomic_store(&d->out_stop, true);
	// Çıkış arabelleği okunurken durdurulmaz: okuma kilidini al, sonra durdur.
	pthread_mutex_lock(&d->out_lock);
	AMediaCodec_stop(d->codec);
	pthread_mutex_unlock(&d->out_lock);
	if(d->out_running)
		pthread_join(d->out_thread, NULL);
	d->out_running = false;
	AMediaCodec_delete(d->codec);
	d->codec = NULL;
}

// codec_lock tutulurken çağrılır.
static void switch_to_software(NinoDecoder *d, const char *why)
{
	if(d->software)
		return;
	nino_loge("Donanım çözücü bırakılıyor (%s), yazılım çözücüye geçiliyor", why);
	close_codec(d);
	d->tried_software_fallback = true;
	if(!open_kind(d, true))
		nino_loge("Yazılım çözücü açılamadı; görüntü gelmeyecek");
}

NinoDecoder *nino_decoder_create(int width, int height, bool software, int min_interval_ms, NinoFrameCb cb, void *user)
{
	NinoDecoder *d = calloc(1, sizeof(*d));
	if(!d)
		return NULL;
	pthread_mutex_init(&d->codec_lock, NULL);
	pthread_mutex_init(&d->out_lock, NULL);
	d->width = width;
	d->height = height;
	d->min_interval_ms = min_interval_ms > 0 ? min_interval_ms : 0;
	d->cb = cb;
	d->user = user;
	pthread_mutex_lock(&d->codec_lock);
	// Seçilen tür açılamazsa öbür tür denenir.
	bool ok = open_kind(d, software) || open_kind(d, !software);
	pthread_mutex_unlock(&d->codec_lock);
	if(!ok)
	{
		nino_loge("H.264 çözücü açılamadı");
		pthread_mutex_destroy(&d->codec_lock);
		pthread_mutex_destroy(&d->out_lock);
		free(d);
		return NULL;
	}
	return d;
}

void nino_decoder_destroy(NinoDecoder *d)
{
	if(!d)
		return;
	pthread_mutex_lock(&d->codec_lock);
	close_codec(d);
	pthread_mutex_unlock(&d->codec_lock);
	pthread_mutex_destroy(&d->codec_lock);
	pthread_mutex_destroy(&d->out_lock);
	free(d->header);
	free(d->out_buf);
	free(d);
}

int64_t nino_decoder_frames(NinoDecoder *d)
{
	return d ? (int64_t)atomic_load(&d->frames) : 0;
}

bool nino_decoder_is_software(NinoDecoder *d)
{
	if(!d)
		return false;
	pthread_mutex_lock(&d->codec_lock);
	bool s = d->software;
	pthread_mutex_unlock(&d->codec_lock);
	return s;
}

// Annex-B başlangıç kodundan sonraki ilk NAL türü 7 (SPS) ise örnek akış başlığıdır.
static bool is_stream_header(const uint8_t *b, size_t n)
{
	size_t i = 0;
	if(n >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 1)
		i = 4;
	else if(n >= 3 && b[0] == 0 && b[1] == 0 && b[2] == 1)
		i = 3;
	else
		return false;
	return i < n && (b[i] & 0x1f) == 7;
}

static bool feed(NinoDecoder *d, const uint8_t *buf, size_t size, int64_t wait_us)
{
	ssize_t idx = AMediaCodec_dequeueInputBuffer(d->codec, wait_us);
	if(idx < 0)
		return false;
	size_t cap = 0;
	uint8_t *in = AMediaCodec_getInputBuffer(d->codec, (size_t)idx, &cap);
	if(!in || cap < size)
	{
		AMediaCodec_queueInputBuffer(d->codec, (size_t)idx, 0, 0, (uint64_t)d->pts++, 0);
		return false;
	}
	memcpy(in, buf, size);
	return AMediaCodec_queueInputBuffer(d->codec, (size_t)idx, 0, size, (uint64_t)d->pts++, 0) == AMEDIA_OK;
}

bool nino_decoder_push(NinoDecoder *d, const uint8_t *buf, size_t size)
{
	if(!d)
		return false;
	if(!buf || size == 0)
		return true; // boş örnek: çökmeden atla
	bool header = is_stream_header(buf, size);
	pthread_mutex_lock(&d->codec_lock);
	if(header)
	{
		// Kütüphane başlığı profil başında bir kez verir: sakla, her yeni çözücüye ilk örnekten önce ver.
		uint8_t *copy = malloc(size);
		if(copy)
		{
			memcpy(copy, buf, size);
			free(d->header);
			d->header = copy;
			d->header_size = size;
		}
	}
	if(atomic_load(&d->want_software))
		switch_to_software(d, "okunamayan çıkış biçimi");
	if(!d->codec)
	{
		pthread_mutex_unlock(&d->codec_lock);
		return false;
	}
	if(!header && !d->header_fed && d->header)
		d->header_fed = feed(d, d->header, d->header_size, HEADER_WAIT_US);
	bool ok = feed(d, buf, size, header ? HEADER_WAIT_US : SAMPLE_WAIT_US);
	if(ok && header)
		d->header_fed = true;
	if(!ok && atomic_fetch_add(&d->errors, 1) + 1 >= MAX_ERRORS && !d->software)
		switch_to_software(d, "art arda hata");
	pthread_mutex_unlock(&d->codec_lock);
	return ok;
}

static bool readable_color(int c)
{
	switch(c)
	{
		case COLOR_I420: case COLOR_PACKED_PLANAR: case COLOR_NV12: case COLOR_PACKED_SEMI: case COLOR_FLEXIBLE:
		case COLOR_QCOM_NV12: case COLOR_YV12: case COLOR_NV21: case COLOR_FLEX_ALT:
			return true;
		default:
			return false;
	}
}

static int layout_of(int c)
{
	switch(c)
	{
		case COLOR_I420: case COLOR_PACKED_PLANAR: return LAYOUT_PLANAR;
		case COLOR_YV12: return LAYOUT_YV12;
		case COLOR_NV21: return LAYOUT_SEMI_VU;
		default: return LAYOUT_SEMI; // esnek biçimlerde NV12 varsayılır
	}
}

static void read_format(NinoDecoder *d, AMediaFormat *f)
{
	OutFormat o;
	memset(&o, 0, sizeof(o));
	o.known = true;
	int32_t v;
	o.color = AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_COLOR_FORMAT, &v) ? v : 0;
	o.width = AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_WIDTH, &v) ? v : d->width;
	o.height = AMediaFormat_getInt32(f, AMEDIAFORMAT_KEY_HEIGHT, &v) ? v : d->height;
	o.stride = AMediaFormat_getInt32(f, "stride", &v) && v > 0 ? v : o.width;
	o.slice = AMediaFormat_getInt32(f, "slice-height", &v) && v > 0 ? v : o.height;
	int32_t l, t, r, b;
	if(AMediaFormat_getInt32(f, "crop-left", &l) && AMediaFormat_getInt32(f, "crop-top", &t)
		&& AMediaFormat_getInt32(f, "crop-right", &r) && AMediaFormat_getInt32(f, "crop-bottom", &b)
		&& r >= l && b >= t)
	{
		o.left = l;
		o.top = t;
		o.vis_w = r - l + 1;
		o.vis_h = b - t + 1;
	}
	else
	{
		o.vis_w = o.width;
		o.vis_h = o.height;
	}
	o.layout = layout_of(o.color);
	o.readable = readable_color(o.color) && o.stride >= o.width && o.stride <= MAX_STRIDE
		&& o.vis_w >= MIN_SIDE && o.vis_h >= MIN_SIDE && o.left + o.vis_w <= o.stride && o.top + o.vis_h <= o.slice;
	d->fmt = o;
	nino_logi("Çıkış biçimi: renk 0x%x, %dx%d, adım %d, dilim %d, görünür %dx%d+%d+%d", o.color, o.width, o.height,
		o.stride, o.slice, o.vis_w, o.vis_h, o.left, o.top);
	if(!o.readable)
	{
		nino_loge("Çıkış biçimi okunamıyor (renk 0x%x)", o.color);
		if(!d->software)
			atomic_store(&d->want_software, true);
	}
}

// Renk: yarım çözünürlük, NV12 sırası (U, V). Sınır dışı okuma yapılmaz; sığmazsa false.
static bool copy_chroma(const OutFormat *o, const uint8_t *src, size_t avail, uint8_t *dst)
{
	int cw = o->vis_w / 2, ch = o->vis_h / 2;
	int ct = o->top / 2, cl = o->left / 2;
	size_t ybytes = (size_t)o->stride * (size_t)o->slice;
	if(o->layout == LAYOUT_SEMI || o->layout == LAYOUT_SEMI_VU)
	{
		size_t last = ybytes + (size_t)(ct + ch - 1) * o->stride + (size_t)cl * 2 + (size_t)cw * 2;
		if(ch <= 0 || last > avail)
			return false;
		for(int r = 0; r < ch; r++)
		{
			const uint8_t *row = src + ybytes + (size_t)(ct + r) * o->stride + (size_t)cl * 2;
			uint8_t *out = dst + (size_t)r * cw * 2;
			if(o->layout == LAYOUT_SEMI)
				memcpy(out, row, (size_t)cw * 2);
			else
				for(int x = 0; x < cw; x++) { out[2 * x] = row[2 * x + 1]; out[2 * x + 1] = row[2 * x]; }
		}
		return true;
	}
	size_t cstride = o->layout == LAYOUT_YV12 ? (((size_t)o->stride / 2 + 15) & ~(size_t)15) : (size_t)o->stride / 2;
	size_t cplane = cstride * (size_t)(o->slice / 2);
	size_t first = ybytes, second = ybytes + cplane;
	size_t u_base = o->layout == LAYOUT_YV12 ? second : first;
	size_t v_base = o->layout == LAYOUT_YV12 ? first : second;
	size_t end_off = (size_t)(ct + ch - 1) * cstride + (size_t)cl + (size_t)cw;
	if(ch <= 0 || u_base + end_off > avail || v_base + end_off > avail)
		return false;
	for(int r = 0; r < ch; r++)
	{
		const uint8_t *u = src + u_base + (size_t)(ct + r) * cstride + cl;
		const uint8_t *v = src + v_base + (size_t)(ct + r) * cstride + cl;
		uint8_t *out = dst + (size_t)r * cw * 2;
		for(int x = 0; x < cw; x++) { out[2 * x] = u[x]; out[2 * x + 1] = v[x]; }
	}
	return true;
}

static void deliver(NinoDecoder *d, const uint8_t *src, size_t avail, int64_t pts)
{
	const OutFormat *o = &d->fmt;
	size_t ysize = (size_t)o->vis_w * o->vis_h;
	size_t csize = (size_t)(o->vis_w / 2) * 2 * (size_t)(o->vis_h / 2);
	size_t ylast = (size_t)(o->top + o->vis_h - 1) * o->stride + (size_t)o->left + (size_t)o->vis_w;
	if(ylast > avail)
	{
		if(!d->warned_small)
			nino_loge("Çıkış arabelleği biçimden küçük (%zu < %zu), kare atlandı", avail, ylast);
		d->warned_small = true;
		return;
	}
	if(d->out_cap < ysize + csize)
	{
		uint8_t *nb = realloc(d->out_buf, ysize + csize);
		if(!nb)
			return; // bellek yetmedi: kare atlanır
		d->out_buf = nb;
		d->out_cap = ysize + csize;
	}
	for(int r = 0; r < o->vis_h; r++)
		memcpy(d->out_buf + (size_t)r * o->vis_w, src + (size_t)(o->top + r) * o->stride + o->left, (size_t)o->vis_w);
	bool chroma = copy_chroma(o, src, avail, d->out_buf + ysize);
	if(d->cb)
		d->cb(d->user, d->out_buf, chroma ? ysize + csize : ysize, o->vis_w, o->vis_h, o->color, chroma, pts);
}

static void *output_thread(void *arg)
{
	NinoDecoder *d = arg;
	AMediaCodec *codec = d->codec;
	while(!atomic_load(&d->out_stop))
	{
		pthread_mutex_lock(&d->out_lock);
		if(atomic_load(&d->out_stop))
		{
			pthread_mutex_unlock(&d->out_lock);
			break;
		}
		AMediaCodecBufferInfo info;
		ssize_t idx = AMediaCodec_dequeueOutputBuffer(codec, &info, OUTPUT_WAIT_US);
		if(idx >= 0)
		{
			if(!d->fmt.known)
			{
				AMediaFormat *f = AMediaCodec_getOutputFormat(codec);
				if(f)
				{
					read_format(d, f);
					AMediaFormat_delete(f);
				}
			}
			size_t out_size = 0;
			uint8_t *buf = AMediaCodec_getOutputBuffer(codec, (size_t)idx, &out_size);
			if(buf && d->fmt.readable && info.size > 0 && (size_t)info.offset < out_size)
			{
				atomic_store(&d->errors, 0);
				atomic_fetch_add(&d->frames, 1);
				uint64_t now = nino_now_ms();
				// Kotlin'e en çok saniyede 1000/min_interval_ms kare: fazlası kopyalanmadan atlanır.
				if(d->min_interval_ms == 0 || d->last_emit_ms == 0 || now - d->last_emit_ms >= (uint64_t)d->min_interval_ms)
				{
					d->last_emit_ms = now;
					deliver(d, buf + info.offset, out_size - (size_t)info.offset, (int64_t)info.presentationTimeUs);
				}
			}
			AMediaCodec_releaseOutputBuffer(codec, (size_t)idx, false);
			pthread_mutex_unlock(&d->out_lock);
		}
		else if(idx == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED)
		{
			AMediaFormat *f = AMediaCodec_getOutputFormat(codec);
			if(f)
			{
				read_format(d, f);
				AMediaFormat_delete(f);
			}
			pthread_mutex_unlock(&d->out_lock);
		}
		else if(idx == AMEDIACODEC_INFO_TRY_AGAIN_LATER || idx == AMEDIACODEC_INFO_OUTPUT_BUFFERS_CHANGED)
		{
			pthread_mutex_unlock(&d->out_lock);
		}
		else
		{
			pthread_mutex_unlock(&d->out_lock);
			if(atomic_fetch_add(&d->errors, 1) + 1 >= MAX_ERRORS && !d->software)
				atomic_store(&d->want_software, true);
			struct timespec ts = { 0, 10 * 1000000L }; // hatalı çözücüde işlemciyi yakma
			nanosleep(&ts, NULL);
		}
	}
	return NULL;
}
