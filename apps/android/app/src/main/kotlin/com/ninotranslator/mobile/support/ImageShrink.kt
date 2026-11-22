// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Fotoğrafı gönderime uygun JPEG'e küçültür: EXIF yönü düzeltilir, uzun kenar en çok [maxEdge], en çok [maxBytes]
 * (önce kalite 70 → 55 → 40, sonra boy ×0,75; 320 px'in altına inilmez). Açılamazsa null.
 */
object ImageShrink {
    const val REPORT_BYTES = 900 * 1024
    const val CHAT_BYTES = 600 * 1024

    fun jpeg(context: Context, uri: Uri, maxBytes: Int, maxEdge: Int = 1600): ByteArray? =
        try { shrink(context, uri, maxBytes, maxEdge) } catch (e: Exception) { null } catch (e: OutOfMemoryError) { null }

    private fun shrink(context: Context, uri: Uri, maxBytes: Int, maxEdge: Int): ByteArray? {
        val cr = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        val stream = cr.openInputStream(uri) ?: return null
        stream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) sample *= 2
        val decoded = cr.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val rotation = cr.openInputStream(uri)?.use {
            when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } ?: 0f
        var bmp = if (rotation != 0f) {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply { postRotate(rotation) }, true)
        } else decoded
        bmp = scaleTo(bmp, maxEdge)
        while (true) {
            for (q in intArrayOf(70, 55, 40)) {
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, q, out)
                if (out.size() <= maxBytes) return out.toByteArray()
            }
            val edge = (max(bmp.width, bmp.height) * 0.75).roundToInt()
            if (edge < 320) return null
            bmp = scaleTo(bmp, edge)
        }
    }

    private fun scaleTo(b: Bitmap, edge: Int): Bitmap {
        val long = max(b.width, b.height)
        if (long <= edge) return b
        val f = edge.toDouble() / long
        return Bitmap.createScaledBitmap(b, (b.width * f).roundToInt().coerceAtLeast(1), (b.height * f).roundToInt().coerceAtLeast(1), true)
    }

    fun decodePreview(bytes: ByteArray): Bitmap? = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
}
