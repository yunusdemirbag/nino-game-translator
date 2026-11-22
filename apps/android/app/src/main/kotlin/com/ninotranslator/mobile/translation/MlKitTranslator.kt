// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.translation

import android.util.Log
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import com.ninotranslator.core.translation.OnDeviceTranslator
import com.ninotranslator.core.translation.TargetLanguage
import com.ninotranslator.mobile.service.ModelRetry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/** Modelin durumu: ana ekrandaki "model inemedi" uyarısı için. */
enum class ModelState { UNKNOWN, DOWNLOADING, READY, FAILED }

/**
 * ML Kit cihaz içi çeviri (ceviri.md 3): İngilizceden hedef dile. Model (~30 MB) ilk kullanımda iner, sonra internetsiz
 * çalışır. Çeviri süre sınırı çekirdekteki [com.ninotranslator.core.translation.OnDeviceLineTranslator]'da (10 sn).
 */
class MlKitTranslator : OnDeviceTranslator, AutoCloseable {
    private val clients = HashMap<TargetLanguage, Translator>()
    private val _model = MutableStateFlow(ModelState.UNKNOWN)
    val model: StateFlow<ModelState> = _model
    /** Ardışık başarısız indirme sayısı (2. hatadan sonra uyarı). */
    @Volatile var failedDownloads = 0; private set

    private fun client(target: TargetLanguage): Translator = synchronized(clients) {
        clients.getOrPut(target) {
            val lang = TranslateLanguage.fromLanguageTag(target.code) ?: error("ML Kit bu dili çeviremiyor: ${target.code}")
            Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.ENGLISH).setTargetLanguage(lang).build())
        }
    }

    override suspend fun translate(text: String, target: TargetLanguage): String = client(target).translate(text).await()

    /**
     * Modeli indirir: bir deneme en çok 300 sn; en çok 6 deneme, aralar 10, 20, 30, 40, 50 sn. Hücresel veride de iner.
     * [onWarning] 2. başarısız denemeden sonra true, model inince false.
     */
    suspend fun ensureModel(target: TargetLanguage, onWarning: (Boolean) -> Unit): Boolean {
        val c = try { client(target) } catch (e: Exception) { _model.value = ModelState.FAILED; onWarning(true); return false }
        _model.value = ModelState.DOWNLOADING
        failedDownloads = 0
        while (true) {
            try {
                withTimeout(ModelRetry.ATTEMPT_TIMEOUT_MS) { c.downloadModelIfNeeded(DownloadConditions.Builder().build()).await() }
                _model.value = ModelState.READY
                failedDownloads = 0
                onWarning(false)
                return true
            } catch (e: CancellationException) {
                if (e is kotlinx.coroutines.TimeoutCancellationException) Unit else throw e
            } catch (e: Exception) {
                Log.w(TAG, "çeviri modeli inemedi: ${e.message}")
            }
            failedDownloads++
            if (ModelRetry.showWarning(failedDownloads)) onWarning(true)
            val wait = ModelRetry.delayAfter(failedDownloads) ?: break
            delay(wait)
        }
        _model.value = ModelState.FAILED
        return false
    }

    override fun close() = synchronized(clients) { clients.values.forEach { it.close() }; clients.clear() }

    private companion object { const val TAG = "Nino" }
}
