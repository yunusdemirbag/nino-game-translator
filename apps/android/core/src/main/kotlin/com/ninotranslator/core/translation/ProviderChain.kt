// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.translation

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout

/**
 * Sağlayıcıları sırayla dener. Hata ya da zaman aşımı sayılır; art arda [failureLimit] kez olursa
 * sağlayıcı [cooldownMs] dinlenir. Boş/aynı/reddedilen sonuç sıradakine geçer ama sayılmaz.
 */
class ProviderChain(
    val providers: List<TranslationProvider>,
    val timeoutMs: Long = 3_000,
    val failureLimit: Int = 3,
    val cooldownMs: Long = 60_000,
    private val now: () -> Long = System::currentTimeMillis,
) {
    data class Result(val text: String, val provider: String)

    private val lock = Mutex()
    private val failures = HashMap<String, Int>()
    private val restingUntil = HashMap<String, Long>()

    suspend fun resting(): List<String> = lock.withLock {
        val t = now()
        providers.map { it.name }.filter { (restingUntil[it] ?: 0) > t }
    }

    suspend fun translate(text: String, source: String, target: String, accept: (String) -> Boolean = { true }): Result? {
        for (provider in providers) {
            val skip = lock.withLock { (restingUntil[provider.name] ?: 0) > now() }
            if (skip) continue
            try {
                val result = withTimeout(timeoutMs) { provider.translate(text, source, target) }.trim()
                if (result.isEmpty() || result == text.trim() || !accept(result)) continue
                lock.withLock { failures[provider.name] = 0 }
                return Result(result, provider.name)
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                recordFailure(provider.name)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                recordFailure(provider.name)
            }
        }
        return null
    }

    private suspend fun recordFailure(name: String) = lock.withLock {
        val n = (failures[name] ?: 0) + 1
        failures[name] = n
        if (n >= failureLimit) {
            restingUntil[name] = now() + cooldownMs
            failures[name] = 0
        }
    }
}
