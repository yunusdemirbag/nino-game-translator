// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.screens.report

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.ninotranslator.mobile.support.ImageShrink
import com.ninotranslator.mobile.ui.theme.NinoColors

/**
 * Android'in fotoğraf seçicisi (izin istemez, yalnız görüntü). Çoklu seçici en az 2 ister ve sayısı kayıtta sabittir;
 * bu yüzden 3 ile kaydedilir, fazlası kırpılır; tek yer kaldıysa tekli seçici kullanılır.
 */
class PhotoPicker(private val single: () -> Unit, private val multi: () -> Unit) {
    fun pick(remaining: Int) { if (remaining <= 1) single() else multi() }
}

@Composable
fun rememberPhotoPicker(remaining: () -> Int, onPicked: (List<Uri>) -> Unit): PhotoPicker {
    val one = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) onPicked(listOf(uri)) }
    val many = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(3)) { uris ->
        onPicked(uris.take(remaining().coerceAtLeast(0)))
    }
    val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
    return remember(one, many) { PhotoPicker({ one.launch(request) }, { many.launch(request) }) }
}

/** Küçük resim; sağ üstte beyaz daire içinde ×. */
@Composable
fun PhotoThumb(bytes: ByteArray, size: Dp, corner: Dp, removeLabel: String, closeSize: Dp = 24.dp, onRemove: () -> Unit) {
    val bmp = remember(bytes) { ImageShrink.decodePreview(bytes)?.asImageBitmap() }
    Box(Modifier.size(size)) {
        if (bmp != null) {
            Image(bmp, null, Modifier.size(size).clip(RoundedCornerShape(corner)), contentScale = ContentScale.Crop)
        } else {
            Box(Modifier.size(size).clip(RoundedCornerShape(corner)).background(NinoColors.Surface2))
        }
        Box(
            Modifier.align(Alignment.TopEnd).padding(4.dp).size(closeSize).clip(CircleShape).background(Color.White)
                .semantics { contentDescription = removeLabel }.clickable(role = Role.Button, onClick = onRemove),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Close, null, Modifier.size(closeSize * 0.6f), tint = NinoColors.Ink) }
    }
}

/** "+" kutusu: düz 1 dp kenarlı. */
@Composable
fun AddPhotoBox(size: Dp, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(size).clip(RoundedCornerShape(14.dp)).border(1.dp, NinoColors.BorderStrong, RoundedCornerShape(14.dp))
            .semantics { contentDescription = label }.clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Filled.Add, null, Modifier.size(28.dp), tint = NinoColors.Accent) }
}
