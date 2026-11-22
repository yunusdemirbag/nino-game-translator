// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ninotranslator.mobile.ui.theme.NinoColors
import com.ninotranslator.mobile.ui.theme.NinoDimens
import com.ninotranslator.mobile.ui.theme.NinoType

/**
 * Metin alanı (§2.9): çerçeveli, 16 dp köşe, beyaz zemin; kenar güçlü kenar rengi, odakta mavi; etiket 13 sp ikincil.
 * Tek satırlıkta 17 sp 600, çok satırlıkta 15 sp. [secret] true ise karakterler noktalanır.
 */
@Composable
fun NinoTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    secret: Boolean = false,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: androidx.compose.foundation.text.KeyboardActions = androidx.compose.foundation.text.KeyboardActions.Default,
    enabled: Boolean = true,
    minLines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label, fontSize = 13.sp) },
        singleLine = singleLine,
        minLines = minLines,
        enabled = enabled,
        textStyle = if (singleLine) NinoType.Headline else NinoType.Body,
        visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        shape = NinoDimens.ControlShape,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = NinoColors.Accent,
            unfocusedBorderColor = NinoColors.BorderStrong,
            cursorColor = NinoColors.Accent,
            focusedContainerColor = NinoColors.Raised,
            unfocusedContainerColor = NinoColors.Raised,
            disabledContainerColor = NinoColors.Raised,
            focusedLabelColor = NinoColors.InkSecondary,
            unfocusedLabelColor = NinoColors.InkSecondary,
            focusedTextColor = NinoColors.Ink,
            unfocusedTextColor = NinoColors.Ink,
        ),
    )
}

/**
 * Segmentli seçim (§2.10): tam genişlik ray (ikinci yüzey, 16 dp köşe, 4 dp iç boşluk, parçalar arası 4 dp). Her
 * parça eşit, 36 dp, 8 dp köşe; seçili beyaz zemin 15 sp 600 mürekkep, diğerleri saydam 15 sp 500 ikincil.
 * [selectedIndex] −1 ise hiçbiri seçili görünmez.
 */
@Composable
fun SegmentedPicker(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier.fillMaxWidth().clip(NinoDimens.ControlShape).background(NinoColors.Surface2).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEachIndexed { i, label ->
            val sel = i == selectedIndex
            Box(
                Modifier.weight(1f).height(36.dp).clip(NinoDimens.BoxShape)
                    .background(if (sel) NinoColors.Raised else Color.Transparent)
                    .semantics { selected = sel }
                    .clickable(role = Role.Tab) { onSelect(i) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label, fontSize = 15.sp, fontWeight = if (sel) FontWeight.SemiBold else FontWeight.Medium,
                    color = if (sel) NinoColors.Ink else NinoColors.InkSecondary, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
    }
}

/**
 * Kod kutuları (§2.11): tam genişlikte [length] eşit kutu, aralar 6 dp, 48 dp, 8 dp köşe. Sıradaki kutu 2 dp mavi
 * kenarlı. Görünmez alan yalnız rakam alır (en çok [length]); kutulara dokununca sayısal gizli klavye açılır.
 */
@Composable
fun CodeBoxes(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    length: Int = 8,
    contentDescription: String? = null,
    enabled: Boolean = true,
) {
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    Box(modifier.fillMaxWidth()) {
        BasicTextField(
            value = value,
            onValueChange = { s -> onValueChange(s.filter { it in '0'..'9' }.take(length)) },
            enabled = enabled,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            modifier = Modifier.matchParentSize().alpha(0f).focusRequester(focus)
                .let { m -> if (contentDescription != null) m.semantics { this.contentDescription = contentDescription } else m },
        )
        Row(
            Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, indication = null, enabled = enabled) {
                focus.requestFocus(); keyboard?.show()
            },
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            for (i in 0 until length) {
                val next = i == value.length
                Box(
                    Modifier.weight(1f).height(48.dp).clip(NinoDimens.BoxShape).background(NinoColors.Surface2)
                        .border(if (next) 2.dp else 1.5.dp,
                            if (next) NinoColors.Accent else NinoColors.InkSecondary.copy(alpha = 0.4f), NinoDimens.BoxShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(value.getOrNull(i)?.toString().orEmpty(),
                        style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = NinoColors.Ink,
                            textAlign = TextAlign.Center))
                }
            }
        }
    }
}

/** Açık/kapalı anahtarı: açıkken mavi iz, beyaz düğme; kapalıyken ikinci yüzey ve güçlü kenar. */
@Composable
fun NinoSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Switch(checked, onCheckedChange, modifier, enabled = enabled, colors = SwitchDefaults.colors(
        checkedTrackColor = NinoColors.Accent, checkedThumbColor = NinoColors.Raised, checkedBorderColor = NinoColors.Accent,
        uncheckedTrackColor = NinoColors.Surface2, uncheckedThumbColor = NinoColors.InkSecondary,
        uncheckedBorderColor = NinoColors.BorderStrong,
    ))
}

/** Kaydırıcı (§12.1): tutamaç mürekkep, dolu iz mavi, boş iz güçlü kenar rengi. */
@Composable
fun NinoSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    steps: Int = 0,
    onValueChangeFinished: (() -> Unit)? = null,
) {
    Slider(value, onValueChange, modifier, valueRange = valueRange, steps = steps, onValueChangeFinished = onValueChangeFinished,
        colors = SliderDefaults.colors(thumbColor = NinoColors.Ink, activeTrackColor = NinoColors.Accent,
            inactiveTrackColor = NinoColors.BorderStrong, activeTickColor = NinoColors.Raised, inactiveTickColor = NinoColors.InkSecondary))
}
