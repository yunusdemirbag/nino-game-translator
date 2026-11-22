// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.service

import com.ninotranslator.core.reading.live.LiveShowKind
import com.ninotranslator.core.translation.LineResult

/** Canlı duruma satır işleme kuralları (servis.md 2, 3.3, 3.4). Saf; testlerde doğrudan denenir. */
object StatusBook {
    const val MAX_RECENT = 20

    fun originOf(line: ShownLine): TranslationOrigin = when {
        line.fromPack || line.origin == LineResult.Origin.PACK -> TranslationOrigin.PACK
        line.origin == LineResult.Origin.POOL -> TranslationOrigin.POOL
        else -> TranslationOrigin.ENGINE
    }

    /**
     * Gösterilen satır: son çeviriler listesine eklenir, sayaçlar artar, paket adı güncellenir. Yerine konan
     * (havuzdan gelen daha iyi) çeviri listedeki ilk satırı günceller, sayaçlar değişmez.
     */
    fun onShown(s: LiveSnapshot, line: ShownLine, packTitle: (String) -> String?): LiveSnapshot {
        val item = RecentTranslation(line.id, line.source, line.text, originOf(line), line.translateMs)
        if (line.kind == LiveShowKind.UPDATED) {
            val first = s.recent.firstOrNull()
            val list = if (first != null && first.source == line.source) listOf(item.copy(id = first.id)) + s.recent.drop(1)
            else (listOf(item) + s.recent).take(MAX_RECENT)
            return s.copy(recent = list, lastLine = line.text)
        }
        val pack = line.fromPack && line.engine != null
        return s.copy(
            recent = (listOf(item) + s.recent).take(MAX_RECENT),
            shownLines = s.shownLines + 1,
            packLines = s.packLines + if (line.fromPack) 1 else 0,
            lastLine = line.text,
            packId = if (pack) line.engine else s.packId,
            packTitle = if (pack) packTitle(line.engine!!) ?: line.engine else s.packTitle,
        )
    }

    fun withPhone(s: LiveSnapshot, p: PhoneLines.State, id: Int): LiveSnapshot =
        s.copy(currentLine = p.current, previousLine = p.previous, currentLineScale = p.scale.toFloat(), currentLineId = id)
}
