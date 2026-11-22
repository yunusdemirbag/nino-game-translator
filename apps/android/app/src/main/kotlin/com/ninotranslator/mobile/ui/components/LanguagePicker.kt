// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.R
import com.ninotranslator.mobile.ui.theme.NinoColors

/** Çeviri dili: kod, bayrak, kendi dilindeki adı (§10). Sıra tarifteki gibidir. */
data class TargetLanguageItem(val code: String, val flag: String, val nativeName: String)

object TargetLanguages {
    val ALL = listOf(
        TargetLanguageItem("tr", "🇹🇷", "Türkçe"),
        TargetLanguageItem("ar", "🇸🇦", "العربية"),
        TargetLanguageItem("hi", "🇮🇳", "हिन्दी"),
        TargetLanguageItem("id", "🇮🇩", "Bahasa Indonesia"),
        TargetLanguageItem("th", "🇹🇭", "ไทย"),
        TargetLanguageItem("vi", "🇻🇳", "Tiếng Việt"),
        TargetLanguageItem("ur", "🇵🇰", "اردو"),
        TargetLanguageItem("bn", "🇧🇩", "বাংলা"),
        TargetLanguageItem("ms", "🇲🇾", "Bahasa Melayu"),
        TargetLanguageItem("tl", "🇵🇭", "Filipino"),
        TargetLanguageItem("nl", "🇳🇱", "Nederlands"),
    )

    /** Bilinmeyen dil: 🌐 ve kodun kendisi. */
    fun of(code: String): TargetLanguageItem = ALL.firstOrNull { it.code == code } ?: TargetLanguageItem(code, "🌐", code)
}

/**
 * Metin içinde kullanılan çeviri dili adı (ör. "Türkçe Altyazı"): Türkçe ve Arapça arayüz dilinde yazılır
 * (`nino_lang_tr`, `nino_lang_ar`), diğerleri kendi dilindeki adıyla.
 */
@Composable
fun languageDisplayName(code: String): String = when (code) {
    "tr" -> stringResource(R.string.nino_lang_tr)
    "ar" -> stringResource(R.string.nino_lang_ar)
    else -> TargetLanguages.of(code).nativeName
}

/** Seçim yapılmayan yer için [languageDisplayName]'in bağlam sürümü. */
fun languageDisplayName(context: android.content.Context, code: String): String = when (code) {
    "tr" -> context.getString(R.string.nino_lang_tr)
    "ar" -> context.getString(R.string.nino_lang_ar)
    else -> TargetLanguages.of(code).nativeName
}

/** Biçim seçimi (§10). */
enum class LanguagePickerStyle {
    /** Karşılama'nın sağ üstündeki küçük hap. */
    PILL,
    /** Ayarlar'daki tam genişlik satır. */
    ROW,
}

/**
 * Çeviri dili seçici (§10): seçili dilin bayrağı ve adı; basınca dil listesi açılır, seçince kapanır ve
 * [onSelect] çağrılır (kaydetmek çağıranın işidir). Ekran okuyucu dil adını okur.
 */
@Composable
fun LanguagePicker(
    selectedCode: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    style: LanguagePickerStyle = LanguagePickerStyle.PILL,
) {
    var open by remember { mutableStateOf(false) }
    val item = TargetLanguages.of(selectedCode)
    Box(modifier) {
        val shape = if (style == LanguagePickerStyle.PILL) RoundedCornerShape(50) else RoundedCornerShape(12.dp)
        val base = if (style == LanguagePickerStyle.PILL) {
            Modifier.height(36.dp).clip(shape).background(Color.White.copy(alpha = 0.10f))
                .border(1.dp, Color.White.copy(alpha = 0.18f), shape)
        } else {
            Modifier.fillMaxWidth().height(44.dp).clip(shape).background(NinoColors.Surface2)
        }
        Row(
            base.semantics { contentDescription = item.nativeName }
                .clickable(role = Role.DropdownList) { open = true }
                .padding(horizontal = if (style == LanguagePickerStyle.PILL) 12.dp else 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(item.flag, fontSize = if (style == LanguagePickerStyle.PILL) 18.sp else 20.sp)
            Text(item.nativeName, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = NinoColors.Ink, maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = if (style == LanguagePickerStyle.ROW) Modifier.weight(1f) else Modifier)
            Icon(Icons.Filled.KeyboardArrowDown, null, Modifier.size(20.dp), tint = NinoColors.InkSecondary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = NinoColors.Raised) {
            TargetLanguages.ALL.forEach { lang ->
                DropdownMenuItem(
                    text = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(lang.flag, fontSize = 20.sp)
                            Spacer(Modifier.width(12.dp))
                            Text(lang.nativeName, fontSize = 15.sp, color = NinoColors.Ink)
                        }
                    },
                    trailingIcon = if (lang.code == selectedCode) {
                        { Icon(Icons.Filled.Check, stringResource(R.string.selected), tint = NinoColors.Accent) }
                    } else null,
                    onClick = { open = false; if (lang.code != selectedCode) onSelect(lang.code) },
                )
            }
        }
    }
}
