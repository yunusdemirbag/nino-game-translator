// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.reading

sealed interface StabilizerEvent {
    data class Stabilized(val text: String, val frame: Int) : StabilizerEvent
    data class Disappeared(val text: String) : StabilizerEvent
}

/**
 * Her karedeki yazıyı alır; yazı yeterince kare sabit kalınca bir kez "sabitlendi",
 * kaybolunca "kayboldu" der. Zaman kare sayısıyla ölçülür (okuma-hatti.md, bölüm 5).
 */
class Stabilizer(val stableFrames: Int = 3, val missingFrames: Int = 2, val similarity: Double = 0.85) {
    init { require(stableFrames >= 1 && missingFrames >= 1) }

    private var frame = 0
    private var shown: String? = null
    private var shownMissing = 0
    private var candidate: String? = null
    private var candidateCount = 0
    private var emptyRun = 0

    /** null ya da boş yazı, boş kare demektir. */
    fun observe(input: String?): List<StabilizerEvent> {
        frame++
        val events = ArrayList<StabilizerEvent>(2)
        val text = input?.takeIf { it.isNotEmpty() }
        val current = shown
        if (current != null) {
            if (text != null && similar(text, current)) {
                shownMissing = 0; candidate = null; candidateCount = 0; emptyRun = 0
                return events
            }
            shownMissing++
            if (shownMissing >= missingFrames) {
                events += StabilizerEvent.Disappeared(current)
                shown = null
                shownMissing = 0
            }
        }
        if (text == null) {
            emptyRun++
            if (emptyRun >= missingFrames) { candidate = null; candidateCount = 0 }
            return events
        }
        emptyRun = 0
        val existing = candidate
        candidateCount = if (existing != null && similar(text, existing)) candidateCount + 1 else 1
        candidate = text
        if (candidateCount >= stableFrames) {
            shown?.let { events += StabilizerEvent.Disappeared(it) }
            events += StabilizerEvent.Stabilized(text, frame)
            shown = text
            shownMissing = 0
            candidate = null
            candidateCount = 0
        }
        return events
    }

    private fun similar(a: String, b: String) = TextSimilarity.isSame(a, b, similarity)
}
