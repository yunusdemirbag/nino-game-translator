// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

/* FFmpeg ile H.264 çözme ve BGRA'ya çevirme. */

#include "bridge_internal.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>

struct nino_h264
{
    AVCodecContext *ctx;
    AVPacket *packet;
    AVFrame *scratch;   /* çözücüden alınan her kare buraya */
    AVFrame *latest;    /* tutulan son kare */
    bool has_latest;

    struct SwsContext *scaler;
    struct SwsContext *colors_for;   /* renk ayrıntılarının kurulduğu ölçekleyici */
    int src_format;                  /* -1: bilinmiyor */
    int src_space;
    int src_range;

    uint8_t *bgra;
    int bgra_width;
    int bgra_height;
    int bgra_stride;
};

nino_h264 *nino_h264_open(void)
{
    const AVCodec *h264 = avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!h264)
        return NULL;

    nino_h264 *dec = calloc(1, sizeof(*dec));
    if (!dec)
        return NULL;
    dec->src_format = -1;
    dec->src_space = -1;
    dec->src_range = -1;

    dec->ctx = avcodec_alloc_context3(h264);
    dec->packet = av_packet_alloc();
    dec->scratch = av_frame_alloc();
    dec->latest = av_frame_alloc();
    if (!dec->ctx || !dec->packet || !dec->scratch || !dec->latest)
        goto fail;

    dec->ctx->flags |= AV_CODEC_FLAG_LOW_DELAY;
    /* Yalnız dilim düzeyinde iş parçacığı: kare düzeyindeki iş parçacıkları her kareye gecikme katar. */
    dec->ctx->thread_type = FF_THREAD_SLICE;
    dec->ctx->thread_count = 0;

    if (avcodec_open2(dec->ctx, h264, NULL) < 0)
        goto fail;
    return dec;

fail:
    nino_h264_close(dec);
    return NULL;
}

void nino_h264_close(nino_h264 *dec)
{
    if (!dec)
        return;
    avcodec_free_context(&dec->ctx);
    av_packet_free(&dec->packet);
    av_frame_free(&dec->scratch);
    av_frame_free(&dec->latest);
    sws_freeContext(dec->scaler);
    free(dec->bgra);
    free(dec);
}

/* Çözücüden çıkan bütün kareleri alır; yalnız sonuncusu tutulur. Alınan kare sayısı. */
static int collect_frames(nino_h264 *dec, void (*each)(nino_h264 *, void *), void *user)
{
    int count = 0;
    for (;;)
    {
        int r = avcodec_receive_frame(dec->ctx, dec->scratch);
        if (r < 0)
            break;
        av_frame_unref(dec->latest);
        av_frame_move_ref(dec->latest, dec->scratch);
        dec->has_latest = true;
        count++;
        if (each)
            each(dec, user);
    }
    return count;
}

int nino_h264_decode(nino_h264 *dec, const uint8_t *data, size_t size)
{
    if (!dec || !data || size == 0)
        return 0;
    dec->has_latest = false;

    dec->packet->data = (uint8_t *)data;
    dec->packet->size = (int)size;

    int r = avcodec_send_packet(dec->ctx, dec->packet);
    if (r == AVERROR(EAGAIN))
    {
        /* Çözücü dolu: bekleyen kareleri atıp bir kez daha dene. */
        while (avcodec_receive_frame(dec->ctx, dec->scratch) >= 0)
            av_frame_unref(dec->scratch);
        r = avcodec_send_packet(dec->ctx, dec->packet);
    }
    dec->packet->data = NULL;
    dec->packet->size = 0;
    if (r < 0)
        return -1;

    return collect_frames(dec, NULL, NULL) > 0 ? 1 : 0;
}

int nino_h264_drain(nino_h264 *dec, void (*each)(nino_h264 *, void *), void *user)
{
    if (!dec)
        return -1;
    dec->has_latest = false;
    int r = avcodec_send_packet(dec->ctx, NULL);
    if (r < 0 && r != AVERROR_EOF)
        return -1;
    return collect_frames(dec, each, user);
}

static bool is_full_range(const AVFrame *frame)
{
    return frame->color_range == AVCOL_RANGE_JPEG || frame->format == AV_PIX_FMT_YUVJ420P;
}

bool nino_h264_to_bgra(nino_h264 *dec, const uint8_t **bgra, int *width, int *height, int *stride)
{
    if (!dec || !dec->has_latest)
        return false;
    AVFrame *frame = dec->latest;
    int w = frame->width;
    int h = frame->height;
    if (w <= 0 || h <= 0)
        return false;

    if (!dec->bgra || w != dec->bgra_width || h != dec->bgra_height)
    {
        int line = ((w * 4) + 63) & ~63;
        uint8_t *buf = malloc((size_t)line * (size_t)h);
        if (!buf)
            return false;
        free(dec->bgra);
        dec->bgra = buf;
        dec->bgra_width = w;
        dec->bgra_height = h;
        dec->bgra_stride = line;
    }

    dec->scaler = sws_getCachedContext(dec->scaler, w, h, (enum AVPixelFormat)frame->format,
                                       w, h, AV_PIX_FMT_BGRA, SWS_POINT, NULL, NULL, NULL);
    if (!dec->scaler)
        return false;

    if (dec->colors_for != dec->scaler || dec->src_format != frame->format
        || dec->src_space != (int)frame->colorspace || dec->src_range != (int)frame->color_range)
    {
        /* PS5 709 kullanır; akış renk alanını söylemediğinde HD için 709 seçilir. */
        int space = (frame->colorspace == AVCOL_SPC_BT470BG || frame->colorspace == AVCOL_SPC_SMPTE170M)
                        ? SWS_CS_ITU601 : SWS_CS_ITU709;
        const int *src_table = sws_getCoefficients(space);
        const int *dst_table = sws_getCoefficients(SWS_CS_ITU709);
        sws_setColorspaceDetails(dec->scaler, src_table, is_full_range(frame) ? 1 : 0, dst_table, 1,
                                 0, 1 << 16, 1 << 16);
        dec->colors_for = dec->scaler;
        dec->src_format = frame->format;
        dec->src_space = (int)frame->colorspace;
        dec->src_range = (int)frame->color_range;
    }

    uint8_t *dst[4] = { dec->bgra, NULL, NULL, NULL };
    int dst_stride[4] = { dec->bgra_stride, 0, 0, 0 };
    int rows = sws_scale(dec->scaler, (const uint8_t *const *)frame->data, frame->linesize, 0, h, dst, dst_stride);
    if (rows != h)
        return false;

    *bgra = dec->bgra;
    *width = w;
    *height = h;
    *stride = dec->bgra_stride;
    return true;
}
