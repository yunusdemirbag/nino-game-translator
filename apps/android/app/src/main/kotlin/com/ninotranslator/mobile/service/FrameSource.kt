// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer

/** Görüntü kaynağının türü; oturum başında bir kez seçilir, oturum boyunca değişmez (servis.md 1.1). */
enum class SourceKind {
    REMOTE_PLAY, CAPTURE_CARD, XBOX,
    /** Yalnız geliştirme yapısı: klasördeki kareler ya da çizilmiş örnek altyazılar. */
    DEBUG_FRAMES,
}

/**
 * Kaynaktan gelen kare: yalnız parlaklık (gri) düzlemi. [luma] yalnız dinleyici çağrısı süresince geçerlidir
 * (Remote Play aynı belleği yeniden kullanır); okuma hattı gereken parçayı çağrının içinde kopyalar.
 * [timestampMs] tekdüze saat (gecikme ölçümü için).
 */
class VideoFrame(
    val luma: ByteBuffer,
    val width: Int,
    val height: Int,
    val stride: Int,
    val timestampMs: Long,
    /** Yarım çözünürlüklü renk düzlemleri; kaynak vermiyorsa null (oyun içi telefon renk ister). */
    val chroma: ChromaPlanes? = null,
)

/**
 * Yarım çözünürlüklü U ve V düzlemleri, kaynağın satır ve piksel adımlarıyla. NV12'de [u] ve [v] aynı belleğin
 * 0 ve 1 kaydırmalı görünümleridir, [pixelStride] 2'dir. Kare gibi yalnız çağrı süresince geçerlidir.
 */
class ChromaPlanes(val u: ByteBuffer, val v: ByteBuffer, val rowStride: Int, val pixelStride: Int) {
    companion object {
        /** NV12 (U, V, U, V…) tek arabellekten. */
        fun nv12(buffer: ByteBuffer, width: Int): ChromaPlanes {
            val u = buffer.duplicate().apply { position(0) }.slice()
            val v = buffer.duplicate().apply { position(minOf(1, buffer.limit())) }.slice()
            return ChromaPlanes(u, v, (width / 2) * 2, 2)
        }
    }
}

/** Kaynağın durumu. Nedenler metin anahtarıdır (`phase_network` gibi); [detail] anahtarın %1$s değeri. */
sealed interface SourceState {
    data object Idle : SourceState
    data object Preparing : SourceState
    data object Connecting : SourceState
    data object Streaming : SourceState
    data class Reconnecting(val reasonKey: String, val detail: String? = null) : SourceState
    data class Failed(val reasonKey: String, val detail: String? = null) : SourceState
}

/** Görüntü kaynağı (PS5 Remote Play, deneme kareleri; ileride yakalama kartı ve Xbox). */
interface FrameSource {
    val kind: SourceKind
    val state: StateFlow<SourceState>
    /** Konsolun bildirdiği çalışan oyunun adı (yalnız PS5); bilinmiyorsa null. */
    val runningGame: StateFlow<String?>
    /** Kareler [sink]'e gelir (kaynağın kendi iş parçacığında). */
    fun start(sink: (VideoFrame) -> Unit)
    fun stop()
    /** Bu oturumda gelen toplam kare (tanı). */
    fun frameCount(): Long
}
