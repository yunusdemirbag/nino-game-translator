// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.remoteplay

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Eşlenmiş PS5: veri katmanı bunu `secrets/console` olarak saklar (ikili alanlar base64). */
class PairedPs5(
    val host: String,
    val name: String,
    /** 16 bayt; içi sıfır baytla biten ASCII onaltılık sayı. */
    val registKey: ByteArray,
    /** 16 bayt ("morning"). */
    val morning: ByteArray,
) {
    val isValid: Boolean get() = host.isNotBlank() && registKey.isNotEmpty() && registKey.size <= 16 && morning.size == 16
}

sealed interface PairResult {
    data class Success(val console: PairedPs5) : PairResult
    /** [reasonKey]: strings anahtarı (`pair_failed` içinde gösterilir); [detail] parantez içinde eklenir. */
    data class Failure(val reasonKey: String, val detail: String?) : PairResult
}

/** PS5 eşleme: 8 haneli kod + 8 baytlık hesap kimliği. "PS5 yanıt vermedi" durumunda 500 ms arayla en çok 3 deneme. */
class Ps5Pairing {
    suspend fun pair(host: String, accountId: ByteArray, codeText: String): PairResult = withContext(Dispatchers.IO) {
        if (!RemotePlayNative.isReady) return@withContext PairResult.Failure("error_native", null)
        val address = NetworkAddresses.cleanManualAddress(host)
            ?: return@withContext PairResult.Failure("address_invalid", null)
        if (!PsnAccountId.isValid(accountId)) return@withContext PairResult.Failure("error_not_paired", null)
        val pin = PairingPin.parse(codeText) ?: return@withContext PairResult.Failure("regist_wrong_code", null)
        var attempt = 0
        while (true) {
            attempt++
            val r = RemotePlayNative.nativeRegister(address, accountId, pin)
            val key = r.registKey
            val morning = r.morning
            if (r.code == NativeRegistResult.SUCCESS && key != null && morning != null) {
                val name = r.nickname?.trim().orEmpty().ifEmpty { "PS5" }
                return@withContext PairResult.Success(PairedPs5(address, name, key, morning))
            }
            val f = RegistReasons.classify(r.code, r.appReason, r.errorLines.toList())
            if (!f.retryable || attempt >= RegistReasons.MAX_ATTEMPTS) {
                return@withContext PairResult.Failure(f.reasonKey, f.detail)
            }
            delay(RegistReasons.RETRY_DELAY_MS)
        }
        @Suppress("UNREACHABLE_CODE")
        PairResult.Failure("regist_failed", null)
    }
}
