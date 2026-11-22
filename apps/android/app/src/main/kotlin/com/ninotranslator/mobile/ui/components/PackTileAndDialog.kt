// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType

/**
 * Paket karosu (§2.12): üst satırda 44 dp [abbreviation] kutusu ve sağda isteğe bağlı [status]; altında [name]
 * (17 sp 600 tek satır) ve [lines] (13 sp ikincil). [dimmed] = %40 opak. [selected] etkin kenar.
 */
@Composable
fun PackTile(
    abbreviation: String,
    name: String,
    lines: String,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    dimmed: Boolean = false,
    onClick: (() -> Unit)? = null,
    status: (@Composable () -> Unit)? = null,
) {
    NinoTile(modifier, selected = selected, dimmed = dimmed, onClick = onClick, spacing = 4.dp) {
        Row(verticalAlignment = Alignment.Top) {
            Box(Modifier.size(44.dp).clip(NinoDimens.BoxShape).background(NinoColors.Surface2), contentAlignment = Alignment.Center) {
                Text(abbreviation, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = NinoColors.Ink, maxLines = 1)
            }
            Spacer(Modifier.weight(1f))
            status?.invoke()
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(name, style = NinoType.Headline, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(lines, fontSize = 13.sp, color = NinoColors.InkSecondary)
        }
    }
}

/**
 * Bilgi iletişim kutusu (§2.13): ikinci yüzey zemini; başlık 17 sp 600, gövde 15 sp ikincil; tek düğme "Tamam".
 */
@Composable
fun InfoDialog(title: String, body: String, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = NinoColors.Surface2,
        title = { Text(title, style = NinoType.Headline) },
        text = { Text(body, style = NinoType.Body, color = NinoColors.InkSecondary) },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.ok), style = NinoType.Headline, color = NinoColors.AccentText)
            }
        },
    )
}
