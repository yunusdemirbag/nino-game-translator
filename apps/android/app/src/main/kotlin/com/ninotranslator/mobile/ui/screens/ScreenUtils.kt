// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.data.TvBrand
import com.ninotranslator.mobile.support.HealthLevel
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoType

/** Ekranların ortak küçük işleri: tarayıcı, pano, paylaşım, kısa bildirim. */
object Screens {
    /** Adresi tarayıcıda açar; tarayıcı yoksa false (sessizce). */
    fun openUrl(context: Context, url: String): Boolean = runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    }.getOrDefault(false)

    fun copy(context: Context, text: String, label: String = "Nino") {
        runCatching {
            context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(label, text))
        }
    }

    fun clipboardText(context: Context): String? = runCatching {
        context.getSystemService(ClipboardManager::class.java)?.primaryClip?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(context)?.toString()
    }.getOrNull()

    /** Panoyu temizler (Android 9+). */
    fun clearClipboard(context: Context) {
        if (android.os.Build.VERSION.SDK_INT >= 28) runCatching { context.getSystemService(ClipboardManager::class.java)?.clearPrimaryClip() }
    }

    fun shareText(context: Context, text: String, subject: String? = null) {
        runCatching {
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            if (subject != null) send.putExtra(Intent.EXTRA_SUBJECT, subject)
            context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    fun toast(context: Context, text: String, long: Boolean = false) {
        Toast.makeText(context, text, if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()
    }

    fun brandName(b: TvBrand): String = when (b) { TvBrand.LG -> "LG"; TvBrand.SAMSUNG -> "Samsung"; TvBrand.ANDROID_TV -> "Android TV" }

    /** Sağlık noktası rengi: iyi, uyarı, sorun, bilinmiyor. */
    fun healthColor(l: HealthLevel): Color = when (l) {
        HealthLevel.GOOD -> Color(0xFF2EA043)
        HealthLevel.WARNING -> Color(0xFFE3A008)
        HealthLevel.PROBLEM -> Color(0xFFD93025)
        HealthLevel.UNKNOWN -> Color(0xFFB0B8C8)
    }
}

/** Dolu renkli nokta. */
@Composable
fun Dot(color: Color, size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) { drawCircle(color) }
}

/**
 * Onay kutusu (ikinci yüzey zemini): [confirm] kırmızı, "Vazgeç" ile kapanır. [enabled] false iken düğmeler pasif ve
 * dışına dokununca kapanmaz.
 */
@Composable
fun ConfirmDialog(
    title: String,
    body: String,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = true,
    enabled: Boolean = true,
) {
    AlertDialog(
        onDismissRequest = { if (enabled) onDismiss() },
        containerColor = NinoColors.Surface2,
        title = { Text(title, style = NinoType.Headline) },
        text = { Text(body, style = NinoType.Body, color = NinoColors.InkSecondary) },
        confirmButton = {
            TextButton(onClick = onConfirm, enabled = enabled) {
                Text(confirm, style = NinoType.Headline, color = if (destructive) NinoColors.Danger else NinoColors.AccentText)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = enabled) {
                Text(stringResource(R.string.cancel), style = NinoType.Headline, color = NinoColors.AccentText)
            }
        },
    )
}

/** Küçük ikincil yazı (13 sp). */
@Composable
fun SmallNote(text: String, modifier: Modifier = Modifier, color: Color = NinoColors.InkSecondary) {
    Text(text, modifier, style = NinoType.Caption.copy(fontWeight = null), color = color)
}

/** 8 dp ara için. */
val TinySpace = 8.dp
