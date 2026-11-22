// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log

/**
 * [TextRef]'i uygulamanın strings kaynağından (arayüz dilinde) yerelleştirir. Metinlerin tek kaynağı `res/values*`;
 * anahtar bulunamazsa (olmaması gerekir, `ServiceStringsTest` denetler) anahtarın kendisi döner.
 */
class ServiceStrings(private val context: Context) {
    @SuppressLint("DiscouragedApi")
    fun get(ref: TextRef): String {
        val id = context.resources.getIdentifier(ref.key, "string", context.packageName)
        if (id == 0) { Log.w("Nino", "metin yok: ${ref.key}"); return ref.key }
        // Değer yoksa biçimlenmez (düz "%" bozulmasın); biçimli metinde yer tutucu boş kalır.
        val text = runCatching { if (ref.arg != null) context.getString(id, ref.arg) else context.getString(id) }.getOrNull() ?: return ref.key
        return if (ref.arg == null) text.replace("%1\$s", "").replace("%%", "%") else text
    }

    fun get(key: String) = get(TextRef(key))
}
