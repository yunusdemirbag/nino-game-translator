// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicLong

/** Yakalama kartının boy seçimi (remote-play.md 16). Saf. */
object CaptureSizes {
    /** 1920×1080 varsa o; yoksa 16:9 boylardan alanca 1080p'ye en yakını (eşitse büyüğü); 16:9 yoksa herhangi birinden. */
    fun choose(sizes: List<Pair<Int, Int>>): Pair<Int, Int>? {
        if (sizes.isEmpty()) return null
        sizes.firstOrNull { it.first == 1920 && it.second == 1080 }?.let { return it }
        val target = 1920L * 1080
        val wide = sizes.filter { it.first.toLong() * 9 == it.second.toLong() * 16 }
        val pool = wide.ifEmpty { sizes }
        return pool.sortedWith(compareBy<Pair<Int, Int>> { kotlin.math.abs(it.first.toLong() * it.second - target) }
            .thenByDescending { it.first.toLong() * it.second }).first()
    }
}

/**
 * Siyah görüntü bekçisi (remote-play.md 16): yarım saniyede bir Y'den 32 pikselde bir örnek; en parlak örnek bile
 * 24'ün altındaysa kare siyah. 4 sn siyah kalırsa [black] true olur; görüntü dönünce false.
 */
class BlackFrameWatch(private val holdMs: Long = 4_000) {
    private var lastCheck = Long.MIN_VALUE / 2
    private var blackSince: Long? = null
    var black = false; private set

    fun due(nowMs: Long) = nowMs - lastCheck >= 500

    /** Örneğin en parlağını verir; durum değiştiyse true. */
    fun onSample(maxLuma: Int, nowMs: Long): Boolean {
        lastCheck = nowMs
        val before = black
        if (maxLuma < 24) {
            val since = blackSince ?: nowMs.also { blackSince = it }
            if (nowMs - since >= holdMs) black = true
        } else { blackSince = null; black = false }
        return before != black
    }

    companion object {
        fun maxSample(luma: ByteBuffer, width: Int, height: Int, stride: Int): Int {
            var max = 0
            var y = 0
            while (y < height) {
                var x = 0
                while (x < width) {
                    val i = y * stride + x
                    if (i < luma.limit()) max = maxOf(max, luma.get(i).toInt() and 0xFF)
                    x += 32
                }
                y += 32
            }
            return max
        }
    }
}

/**
 * HDMI yakalama kartı (USB UVC, Camera2'de harici kamera; remote-play.md 16). Telefonun kendi kameraları asla
 * seçilmez. Bütün kamera işleri tek arka plan iş parçacığında yürür; kapatma bloklamaz. Kart takılınca ya da başka
 * uygulama kamerayı bırakınca kendiliğinden yeniden açılır; başarısız açılıştan sonra 2 sn dolmadan denenmez.
 */
class CaptureCardSource(context: Context) : FrameSource {
    override val kind = SourceKind.CAPTURE_CARD
    private val app = context.applicationContext
    private val _state = MutableStateFlow<SourceState>(SourceState.Idle)
    override val state: StateFlow<SourceState> = _state
    override val runningGame: StateFlow<String?> = MutableStateFlow(null)
    private val frames = AtomicLong()
    private val manager = app.getSystemService(CameraManager::class.java)
    private val thread = HandlerThread("nino-capture").apply { start() }
    private val handler = Handler(thread.looper)
    @Volatile private var sink: (VideoFrame) -> Unit = {}
    @Volatile private var closed = false

    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var opening = false
    private var lastFailAt = Long.MIN_VALUE / 2
    private var streamed = false
    private val black = BlackFrameWatch()

    private val availability = object : CameraManager.AvailabilityCallback() {
        override fun onCameraAvailable(cameraId: String) {
            if (!closed && device == null && !opening && isExternal(cameraId)) open()
        }
    }

    override fun start(sink: (VideoFrame) -> Unit) {
        this.sink = sink
        _state.value = SourceState.Connecting
        runCatching { manager.registerAvailabilityCallback(availability, handler) }
        handler.post { open() }
    }

    override fun stop() {
        closed = true
        sink = {}
        runCatching { manager.unregisterAvailabilityCallback(availability) }
        handler.post { closeCamera(); thread.quitSafely() }
    }

    override fun frameCount(): Long = frames.get()

    private fun report(s: SourceState) { if (_state.value != s) _state.value = s }

    private fun isExternal(id: String): Boolean = runCatching {
        manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_EXTERNAL
    }.getOrDefault(false)

    /** `YUV_420_888` veren ilk harici kamera ve boyu. */
    private fun pick(): Pair<String, Pair<Int, Int>>? {
        for (id in runCatching { manager.cameraIdList.toList() }.getOrDefault(emptyList())) {
            if (!isExternal(id)) continue
            val map = runCatching { manager.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) }.getOrNull() ?: continue
            val sizes = map.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty()
            val size = CaptureSizes.choose(sizes) ?: continue
            return id to size
        }
        return null
    }

    @SuppressLint("MissingPermission")
    private fun open() {
        if (closed || device != null || opening) return
        val wait = lastFailAt + RETRY_MS - SystemClock.elapsedRealtime()
        if (wait > 0) { handler.postDelayed({ open() }, wait); return }
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            fail(KEY_NO_PERMISSION, retry = false); return
        }
        val (id, size) = pick() ?: run { fail(KEY_NOT_FOUND, retry = false); return }
        opening = true
        streamed = false
        report(SourceState.Connecting)
        try {
            manager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    opening = false
                    if (closed) { camera.close(); return }
                    device = camera
                    configure(camera, size)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    opening = false
                    Log.i(TAG, "yakalama kartı çıkarıldı")
                    if (device === camera || device == null) closeCamera() else camera.close()
                    fail(KEY_NOT_FOUND, retry = false)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    opening = false
                    Log.w(TAG, "yakalama kartı hatası: $error")
                    if (device === camera || device == null) closeCamera() else camera.close()
                    fail(if (error == ERROR_CAMERA_DISABLED) KEY_NO_PERMISSION else KEY_NOT_FOUND, retry = true)
                }
            }, handler)
        } catch (e: SecurityException) {
            opening = false; fail(KEY_NO_PERMISSION, retry = false)
        } catch (e: Exception) {
            opening = false; Log.w(TAG, "yakalama kartı açılamadı", e); fail(KEY_NOT_FOUND, retry = true)
        }
    }

    private fun configure(camera: CameraDevice, size: Pair<Int, Int>) {
        try {
            val r = ImageReader.newInstance(size.first, size.second, ImageFormat.YUV_420_888, 3)
            reader = r
            r.setOnImageAvailableListener({ ir ->
                // Her zaman en son kare; işlenince hemen kapatılır.
                val img = runCatching { ir.acquireLatestImage() }.getOrNull() ?: return@setOnImageAvailableListener
                try { deliver(img) } catch (e: Exception) { Log.w(TAG, "kare işlenemedi", e) } finally { img.close() }
            }, handler)
            @Suppress("DEPRECATION")
            camera.createCaptureSession(listOf(r.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    if (closed || device !== camera) { s.close(); return }
                    session = s
                    runCatching {
                        val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply { addTarget(r.surface) }
                        s.setRepeatingRequest(req.build(), null, handler)
                    }.onFailure { Log.w(TAG, "yakalama isteği başlamadı", it); closeCamera(); fail(KEY_NOT_FOUND, retry = true) }
                }

                override fun onConfigureFailed(s: CameraCaptureSession) {
                    closeCamera(); fail(KEY_NOT_FOUND, retry = true)
                }
            }, handler)
        } catch (e: Exception) {
            Log.w(TAG, "yakalama oturumu kurulamadı", e); closeCamera(); fail(KEY_NOT_FOUND, retry = true)
        }
    }

    private fun deliver(img: Image) {
        val planes = img.planes
        if (planes.size < 3) return
        val crop = img.cropRect
        val y = planes[0]; val u = planes[1]; val v = planes[2]
        fun from(b: ByteBuffer, offset: Int): ByteBuffer = b.duplicate().apply { position(offset.coerceIn(0, b.limit())) }.slice()
        val luma = from(y.buffer, crop.top * y.rowStride + crop.left * y.pixelStride)
        val cOff = { p: Image.Plane -> (crop.top / 2) * p.rowStride + (crop.left / 2) * p.pixelStride }
        val chroma = ChromaPlanes(from(u.buffer, cOff(u)), from(v.buffer, cOff(v)), u.rowStride, u.pixelStride)
        val w = crop.width(); val h = crop.height()
        val now = SystemClock.elapsedRealtime()
        if (!streamed) { streamed = true; report(SourceState.Streaming) }
        if (black.due(now) && black.onSample(BlackFrameWatch.maxSample(luma, w, h, y.rowStride), now)) {
            report(if (black.black) SourceState.Reconnecting(KEY_BLACK) else SourceState.Streaming)
        }
        frames.incrementAndGet()
        sink(VideoFrame(luma, w, h, y.rowStride, now, chroma))
    }

    private fun fail(key: String, retry: Boolean) {
        lastFailAt = SystemClock.elapsedRealtime()
        report(SourceState.Failed(key))
        if (retry && !closed) handler.postDelayed({ open() }, RETRY_MS)
    }

    private fun closeCamera() {
        runCatching { session?.close() }; session = null
        runCatching { device?.close() }; device = null
        runCatching { reader?.close() }; reader = null
        opening = false
    }

    companion object {
        private const val TAG = "NinoCapture"
        const val RETRY_MS = 2_000L
        const val KEY_NOT_FOUND = "capture_not_found"
        const val KEY_NO_PERMISSION = "capture_no_permission"
        const val KEY_BLACK = "capture_black"

        fun hasPermission(context: Context) =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
}
