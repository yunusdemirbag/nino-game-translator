// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.tv.install

import java.io.File

/** Kurucuların dış dünyası: dosyalar, paketler, günlük, LG oturum zamanı (testte elle kurulur). */
class TvInstallEnv(
    /** `no_backup/`: anahtarlar ve sertifikalar. */
    val noBackupDir: File,
    /** `cache/`: geçici paket kopyaları. */
    val cacheDir: File,
    val packages: TvPackageSource,
    val log: (String) -> Unit,
    val lgRenewedAt: (String) -> Long? = { null },
    val setLgRenewedAt: (String, Long) -> Unit = { _, _ -> },
    val now: () -> Long = System::currentTimeMillis,
) {
    fun file(vararg parts: String): File = parts.fold(noBackupDir) { d, p -> File(d, p) }

    companion object {
        /** Dosya adı için güvenli: harf, rakam, `.`, `_`, `-` dışı `_` olur. */
        fun safeName(s: String, allowDot: Boolean = true): String =
            s.trim().map { if (it.isLetterOrDigit() && it.code < 128 || it == '_' || it == '-' || (allowDot && it == '.')) it else '_' }.joinToString("")
    }
}
