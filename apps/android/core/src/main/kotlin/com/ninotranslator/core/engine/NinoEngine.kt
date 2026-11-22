// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.engine

import com.ninotranslator.core.link.NinoSender
import com.ninotranslator.core.link.ShowPayload
import com.ninotranslator.core.link.SubtitlePosition
import com.ninotranslator.core.reading.ReadingPipeline
import com.ninotranslator.core.reading.RecognizedLine
import com.ninotranslator.core.reading.Subtitle
import com.ninotranslator.core.reading.SubtitleEvent
import com.ninotranslator.core.reading.TextRecognizer
import com.ninotranslator.core.translation.Translation
import com.ninotranslator.core.translation.Translator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Altyazının gideceği yer (TV ya da telefon ekranı). */
interface SubtitleOutput {
    suspend fun show(payload: ShowPayload)
    suspend fun clear(id: Int?)
}

/** NinoSender'ı çıkış olarak kullanır. */
class SenderOutput(private val sender: NinoSender) : SubtitleOutput {
    override suspend fun show(payload: ShowPayload) = sender.show(payload)
    override suspend fun clear(id: Int?) = sender.clear(id)
}

sealed interface EngineEvent {
    data class SubtitleStarted(val subtitle: Subtitle) : EngineEvent
    data class Translated(val id: Int, val text: String, val translations: List<Translation>) : EngineEvent
    data class TranslationFailed(val id: Int) : EngineEvent
    data class Dropped(val id: Int) : EngineEvent
    data class Shown(val id: Int) : EngineEvent
    data class Cleared(val id: Int) : EngineEvent
    data class OutputFailed(val id: Int, val message: String) : EngineEvent
}

/**
 * Uçtan uca akış: kare → okuma hattı → çeviri → çıkış (motor.md).
 * Okuma çeviriyi beklemez; geç gelen çeviri, altyazı bitmişse ya da yenisi başlamışsa atılır.
 * Tüm durum tek iş parçacıklı bir bağlamda tutulur.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NinoEngine(
    private val pipeline: ReadingPipeline,
    private val translator: Translator,
    @Volatile var output: SubtitleOutput? = null,
    val options: Options = Options(),
    /** Gösterilmeden önce metne son biçim (ör. satır kaydırma); varsayılan dokunmaz. */
    private val payloadDecorator: (ShowPayload, Subtitle) -> ShowPayload = { p, _ -> p },
) {
    data class Options(
        val position: SubtitlePosition = SubtitlePosition.BOTTOM,
        val sendSource: Boolean = true,
        /** Çeviri olmazsa İngilizce metni göster. */
        val showUntranslated: Boolean = true,
    )

    private val confined = Dispatchers.Default.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + confined)
    private val _events = MutableSharedFlow<EngineEvent>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val events: SharedFlow<EngineEvent> = _events

    private var onScreen: Subtitle? = null
    private var shownId: Int? = null
    private var latestStartedId = 0
    private val inFlight = LinkedHashMap<Int, Job>()

    /** Kareler bitene ya da iptal edilene kadar işler. */
    suspend fun <F> run(frames: Flow<F>, recognizer: TextRecognizer<F>) {
        frames.collect { frame ->
            val lines = runCatching { recognizer.recognize(frame, pipeline.configuration.region) }.getOrNull() ?: return@collect
            processLines(lines)
        }
        waitUntilIdle()
        translator.flush()
    }

    /** Okunmuş satırları bir kare olarak işler. */
    suspend fun processLines(lines: List<RecognizedLine>) = withContext(confined) {
        for (e in pipeline.process(lines)) handle(e)
    }

    suspend fun waitUntilIdle() {
        while (true) {
            val job = withContext(confined) { inFlight.values.firstOrNull() } ?: return
            job.join()
        }
    }

    suspend fun flush() = translator.flush()

    fun close() = scope.cancel()

    private fun emit(e: EngineEvent) { _events.tryEmit(e) }

    private fun handle(event: SubtitleEvent) {
        when (event) {
            is SubtitleEvent.Started -> {
                val sub = event.subtitle
                latestStartedId = sub.id
                onScreen = sub
                emit(EngineEvent.SubtitleStarted(sub))
                val job = scope.launch { translateAndShow(sub) }
                inFlight[sub.id] = job
                job.invokeOnCompletion { scope.launch { inFlight.remove(sub.id) } }
            }
            is SubtitleEvent.Ended -> {
                val sub = event.subtitle
                if (onScreen?.id == sub.id) onScreen = null
                if (shownId == sub.id) {
                    shownId = null
                    val out = output
                    scope.launch {
                        try { out?.clear(sub.id); emit(EngineEvent.Cleared(sub.id)) }
                        catch (e: Exception) { if (isActive) emit(EngineEvent.OutputFailed(sub.id, e.toString())) }
                    }
                }
            }
        }
    }

    private suspend fun translateAndShow(sub: Subtitle) {
        val translations = translator.translate(sub.sentences)
        val allFailed = translations.isNotEmpty() && translations.all { it.failed }
        val text = translations.joinToString(" ") { it.text }
        if (allFailed) {
            emit(EngineEvent.TranslationFailed(sub.id))
            if (!options.showUntranslated) return
        } else {
            emit(EngineEvent.Translated(sub.id, text, translations))
        }
        if (onScreen?.id != sub.id || sub.id != latestStartedId) {
            emit(EngineEvent.Dropped(sub.id))
            return
        }
        val payload = payloadDecorator(ShowPayload(sub.id, text, if (options.sendSource) sub.text else null, options.position), sub)
        val out = output
        try {
            out?.show(payload)
            emit(EngineEvent.Shown(sub.id))
            if (onScreen?.id == sub.id) shownId = sub.id
            else { out?.clear(sub.id); emit(EngineEvent.Cleared(sub.id)) }
        } catch (e: Exception) {
            emit(EngineEvent.OutputFailed(sub.id, e.toString()))
        }
    }
}
