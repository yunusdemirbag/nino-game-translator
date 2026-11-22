// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.app.Activity
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicLong

/** Yalnız geliştirme yapısı: deneme kaynağının ayarları (`nino-debug` tercihleri). */
object DebugFrames {
    const val PREFS = "nino-debug"
    const val KEY_MODE = "source"
    const val KEY_HOLD = "holdMs"
    const val KEY_GAP = "gapMs"
    const val MODE_FRAMES = "frames"
    const val MODE_SAMPLE = "sample"
    const val FOLDER = "demo-frames"

    fun folder(context: Context): File? = context.getExternalFilesDir(null)?.let { File(it, FOLDER) }

    fun frameFiles(context: Context): List<File> = folder(context)?.listFiles().orEmpty()
        .filter { it.isFile && it.extension.lowercase() in setOf("png", "jpg", "jpeg") }.sortedBy { it.name }

    fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    fun mode(context: Context): String? = prefs(context).getString(KEY_MODE, null)
}

/**
 * PS5 yerine deneme görüntüsü: `files/demo-frames/` klasöründeki PNG/JPG kareleri sırayla ya da (klasör boşsa)
 * siyah zemine çizilmiş örnek İngilizce altyazılar. Okuma, çeviri ve TV gerçekteki gibi çalışır.
 * Her kare [holdMs] boyunca saniyede 10 kez verilir, aralarda [gapMs] boş kare; bitince baştan.
 */
class DebugFrameSource(private val context: Context, private val scope: CoroutineScope) : FrameSource {
    override val kind = SourceKind.DEBUG_FRAMES
    private val _state = MutableStateFlow<SourceState>(SourceState.Idle)
    override val state: StateFlow<SourceState> = _state
    override val runningGame: StateFlow<String?> = MutableStateFlow(null)
    private val frames = AtomicLong()
    private var job: Job? = null

    /** Kare: video aralığında BT.601 Y ve yarım çözünürlüklü U/V (Remote Play gibi; oyun içi telefon renk ister). */
    private class Luma(val data: ByteArray, val w: Int, val h: Int, val u: ByteArray, val v: ByteArray)

    override fun start(sink: (VideoFrame) -> Unit) {
        val prefs = DebugFrames.prefs(context)
        val hold = prefs.getLong(DebugFrames.KEY_HOLD, 3_000L).coerceIn(400, 60_000)
        val gap = prefs.getLong(DebugFrames.KEY_GAP, 1_000L).coerceIn(0, 60_000)
        val files = if (DebugFrames.mode(context) == DebugFrames.MODE_SAMPLE) emptyList() else DebugFrames.frameFiles(context)
        _state.value = SourceState.Connecting
        job = scope.launch(Dispatchers.Default) {
            val images: List<Luma> = if (files.isNotEmpty()) files.mapNotNull(::decode) else DemoLines.ENGLISH.map(::render)
            Log.i(TAG, "deneme kaynağı: ${images.size} kare (${if (files.isNotEmpty()) "klasör" else "örnek altyazı"})")
            if (images.isEmpty()) { _state.value = SourceState.Failed("capture_black"); return@launch }
            delay(1_500)
            _state.value = SourceState.Streaming
            val blanks = HashMap<Long, Luma>()
            while (isActive) {
                for (img in images) {
                    emit(img, hold, sink)
                    if (gap > 0) emit(blanks.getOrPut(img.w.toLong() shl 32 or img.h.toLong()) { blank(img.w, img.h) }, gap, sink)
                }
            }
        }
    }

    private suspend fun emit(img: Luma, durationMs: Long, sink: (VideoFrame) -> Unit) {
        val end = SystemClock.elapsedRealtime() + durationMs
        val buf = ByteBuffer.wrap(img.data)
        val chroma = ChromaPlanes(ByteBuffer.wrap(img.u), ByteBuffer.wrap(img.v), img.w / 2, 1)
        while (SystemClock.elapsedRealtime() < end) {
            frames.incrementAndGet()
            sink(VideoFrame(buf, img.w, img.h, img.w, SystemClock.elapsedRealtime(), chroma))
            delay(100)
        }
    }

    override fun stop() { job?.cancel(); job = null; _state.value = SourceState.Idle }

    override fun frameCount(): Long = frames.get()

    /** Siyah kare. */
    private fun blank(w: Int, h: Int) = Luma(ByteArray(w * h) { 16 }, w, h, ByteArray(w / 2 * (h / 2)) { -128 }, ByteArray(w / 2 * (h / 2)) { -128 })

    /** Kareyi video aralığında YUV 4:2:0'a çevirir (BT.601); en ve boy çift sayı. */
    private fun decode(f: File): Luma? {
        val bmp = runCatching { BitmapFactory.decodeFile(f.absolutePath) }.getOrNull() ?: run { Log.w(TAG, "okunamadı: ${f.name}"); return null }
        return toLuma(bmp).also { bmp.recycle() }
    }

    private fun toLuma(bmp: Bitmap): Luma {
        val w = bmp.width / 2 * 2; val h = bmp.height / 2 * 2
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        val out = ByteArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            out[i] = (16 + (Color.red(c) * 257 + Color.green(c) * 504 + Color.blue(c) * 98) / 1000).coerceIn(0, 255).toByte()
        }
        val cw = w / 2; val ch = h / 2
        val u = ByteArray(cw * ch); val v = ByteArray(cw * ch)
        for (cy in 0 until ch) for (cx in 0 until cw) {
            var r = 0; var g = 0; var b = 0
            for (dy in 0..1) for (dx in 0..1) { val c = px[(cy * 2 + dy) * w + cx * 2 + dx]; r += Color.red(c); g += Color.green(c); b += Color.blue(c) }
            r /= 4; g /= 4; b /= 4
            u[cy * cw + cx] = (128 + (-148 * r - 291 * g + 439 * b) / 1000).coerceIn(0, 255).toByte()
            v[cy * cw + cx] = (128 + (439 * r - 368 * g - 71 * b) / 1000).coerceIn(0, 255).toByte()
        }
        return Luma(out, w, h, u, v)
    }

    /** Siyah zemine, alt bölgeye beyaz örnek altyazı. */
    private fun render(text: String): Luma {
        val w = 1280; val h = 720
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.BLACK)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = 38f; typeface = Typeface.DEFAULT_BOLD; textAlign = Paint.Align.CENTER
        }
        c.drawText(text, w / 2f, h * 0.86f, p)
        return toLuma(bmp).also { bmp.recycle() }
    }

    private companion object { const val TAG = "NinoDebug" }
}

/** Debug yapısında süreç açılırken deneme kaynağını kaydeder (yayın yapısında bu sınıf yoktur). */
class DebugSourcesInstaller : ContentProvider() {
    override fun onCreate(): Boolean {
        DebugSources.factory = object : DebugSources.Factory {
            override fun available(context: Context) =
                DebugFrames.mode(context) == DebugFrames.MODE_SAMPLE || DebugFrames.frameFiles(context).isNotEmpty()
            override fun create(context: Context, scope: CoroutineScope): FrameSource = DebugFrameSource(context.applicationContext, scope)
        }
        return true
    }
    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?) = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}

/**
 * adb ile açılan saydam deneme etkinliği (yalnız debug). Ekstralar:
 * `demo` (true aç, false kapat; varsayılan true), `source` (`frames` | `sample`; boşsa klasörde kare varsa frames),
 * `holdMs`, `gapMs`.
 */
class DebugDemoActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val i = intent
        val prefs = DebugFrames.prefs(this)
        if (i.getBooleanExtra("rpcheck", false)) {
            // PS5 kütüphanesi denetimi: yüklenir mi, ağ araması döner mi (sonuç günlükte, etiket NinoRpCheck).
            val addr = i.getStringExtra("host")
            Thread {
                val status = com.ninotranslator.mobile.remoteplay.RemotePlayNative.status
                android.util.Log.i("NinoRpCheck", "yerel kütüphane: $status")
                val found = runCatching { com.ninotranslator.mobile.remoteplay.Ps5Finder().findBlocking(addr, 2_500) }
                android.util.Log.i("NinoRpCheck", "arama: $found")
            }.start()
            finish()
            return
        }
        if (!i.getBooleanExtra("demo", true)) {
            prefs.edit().clear().apply()
            TranslationService.stop(this)
        } else {
            val mode = i.getStringExtra("source")
                ?: if (DebugFrames.frameFiles(this).isNotEmpty()) DebugFrames.MODE_FRAMES else DebugFrames.MODE_SAMPLE
            prefs.edit().apply {
                putString(DebugFrames.KEY_MODE, mode)
                if (i.hasExtra("holdMs")) putLong(DebugFrames.KEY_HOLD, i.getLongExtra("holdMs", 3_000L))
                if (i.hasExtra("gapMs")) putLong(DebugFrames.KEY_GAP, i.getLongExtra("gapMs", 1_000L))
            }.commit()
            DebugFrames.folder(this)?.mkdirs()
            TranslationService.start(this, debugFrames = true)
        }
        finish()
    }
}
