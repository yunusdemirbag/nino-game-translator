// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

/** Sabitlenmiş bir altyazı. */
data class Subtitle(
    val id: Int,
    val text: String,
    val sentences: List<String>,
    /** Çevrilmesi gereken yeni cümleler. */
    val newSentences: List<String>,
    /** Yakın zamanda görülmüş mü (çeviri önbellekten gelir). */
    val isRepeat: Boolean,
    /** Önceki altyazının uzantısı mı. */
    val isContinuation: Boolean,
    /** Sabitlendiği kare sırası. */
    val startFrame: Int,
)

sealed interface SubtitleEvent {
    val subtitle: Subtitle
    data class Started(override val subtitle: Subtitle) : SubtitleEvent
    data class Ended(override val subtitle: Subtitle) : SubtitleEvent
}

data class ReadingConfiguration(
    val region: NormalizedRect = NormalizedRect.DEFAULT_SUBTITLE,
    val filter: NoiseFilter = NoiseFilter(),
    val stableFrames: Int = 3,
    val missingFrames: Int = 2,
    val similarity: Double = 0.85,
    val splitter: SentenceSplitter = SentenceSplitter(),
    val historySize: Int = 32,
)

/** Bir kareden satır okuyan her şey (gerçeği ML Kit, testlerde sahtesi). */
fun interface TextRecognizer<in F> {
    suspend fun recognize(frame: F, region: NormalizedRect): List<RecognizedLine>
}

/** Kareden altyazı olayına kadar okuma hattı. Tek iş parçacığında, sırayla kullanılır. */
class ReadingPipeline(val configuration: ReadingConfiguration = ReadingConfiguration()) {
    private val stabilizer = Stabilizer(configuration.stableFrames, configuration.missingFrames, configuration.similarity)
    private var current: Subtitle? = null
    private var previous: Subtitle? = null
    private val history = ArrayDeque<String>()
    private var nextId = 1
    private var frame = 0
    private var lastEndFrame: Int? = null

    /** Okuyucuyla bir kareyi okur ve işler. */
    suspend fun <F> process(frame: F, recognizer: TextRecognizer<F>): List<SubtitleEvent> =
        process(recognizer.recognize(frame, configuration.region))

    /** Önceden okunmuş satırları bir kare olarak işler. */
    fun process(lines: List<RecognizedLine>): List<SubtitleEvent> {
        frame++
        val text = configuration.filter.text(lines, configuration.region)
        return stabilizer.observe(text).mapNotNull(::handle)
    }

    private fun handle(event: StabilizerEvent): SubtitleEvent? = when (event) {
        is StabilizerEvent.Disappeared -> current?.let {
            current = null
            lastEndFrame = frame
            SubtitleEvent.Ended(it)
        }
        is StabilizerEvent.Stabilized -> {
            val subtitle = makeSubtitle(event.text, event.frame)
            previous = subtitle
            current = subtitle
            SubtitleEvent.Started(subtitle)
        }
    }

    private fun makeSubtitle(text: String, at: Int): Subtitle {
        val key = TextSimilarity.key(text)
        val sentences = configuration.splitter.split(text)
        var newSentences = sentences
        var continuation = false
        val window = configuration.stableFrames + configuration.missingFrames
        val recent = current != null || lastEndFrame?.let { at - it <= window } == true
        val prev = previous
        if (prev != null && recent) {
            val prevKey = TextSimilarity.key(prev.text)
            if (prevKey.isNotEmpty() && key.length > prevKey.length && key.startsWith(prevKey)) {
                continuation = true
                val seen = prev.sentences.map(TextSimilarity::key).toSet()
                newSentences = sentences.filter { TextSimilarity.key(it) !in seen }
            }
        }
        val repeat = history.any { TextSimilarity.isSame(it, key, configuration.similarity) }
        history.addLast(key)
        while (history.size > configuration.historySize) history.removeFirst()
        return Subtitle(nextId++, text, sentences, newSentences, repeat, continuation, at)
    }
}
