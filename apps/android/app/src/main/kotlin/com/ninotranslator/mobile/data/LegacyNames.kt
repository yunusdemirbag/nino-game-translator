// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import java.util.Base64

/**
 * Eski sürümlerin kimlik adları. Proje kuralı: yalnız burada ve base64 kodlu durur (veri taşıma için).
 */
object LegacyNames {
    private const val SECRETS_KEY_ALIAS_B64 = "Y291Y2hzdWJzLXNlY3JldHM="

    /** Eski kurulumlarda `secrets` değerlerini şifreleyen Keystore takma adı. */
    val secretsKeyAlias: String by lazy { decode(SECRETS_KEY_ALIAS_B64) }

    private fun decode(b64: String) = String(Base64.getDecoder().decode(b64), Charsets.UTF_8)
}
