// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

/**
 * Sabit kovalı süre histogramı (ms). Kova sınırları bütün platformlarda aynı; sunucu yüzdelikleri bu kovalardan
 * hesaplar. Satır başına olay gönderilmez, oturum sonunda tek olayda gider.
 */
class LatencyHistogram {
    val counts = LongArray(EDGES.size + 1)
    var count = 0L; private set
    var sum = 0L; private set
    var max = 0L; private set

    fun record(ms: Long) {
        val v = ms.coerceAtLeast(0)
        counts[bucketOf(v)]++
        count++
        sum += v
        if (v > max) max = v
    }

    /** `{"n", "sum", "max", "h"}`; sondaki sıfır kovalar atılır. */
    fun toWire(): Map<String, Any?> {
        var last = counts.size - 1
        while (last >= 0 && counts[last] == 0L) last--
        return linkedMapOf("n" to count, "sum" to sum, "max" to max, "h" to (0..last).map { counts[it] })
    }

    companion object {
        /** Kova üst sınırları (ms). Son kova (dizinin boyu) 10 000 ms'den uzunlar: toplam 19 kova. */
        val EDGES = longArrayOf(5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000)

        /** `v ≤ sınır` olan ilk kova; hepsinden büyükse son kova. */
        fun bucketOf(ms: Long): Int {
            for (i in EDGES.indices) if (ms <= EDGES[i]) return i
            return EDGES.size
        }
    }
}

/**
 * Bir çeviri oturumunun süre ölçümleri. Birden çok iş parçacığından çağrılabilir.
 * Ölçüm adları: [Metric]; en çok 24 ölçüm.
 */
class SessionTimings {
    object Metric {
        const val OCR = "ocr"
        const val CACHE = "tr.cache"
        const val PACK = "tr.pack"
        const val POOL = "tr.pool"
        const val PROVIDER = "tr.provider"
        const val TOTAL = "tr.total"
        const val FIRST_FRAME = "first_frame"
        const val FIRST_SUBTITLE = "first_subtitle"
        private val NAME = Regex("^[a-z0-9_-]{1,24}$")

        /** `tr.provider:deepl` gibi; ad geçersizse yalnız `tr.provider`. */
        fun provider(name: String): String = name.lowercase().let { if (NAME.matches(it)) "$PROVIDER:$it" else PROVIDER }
    }

    private val histograms = LinkedHashMap<String, LatencyHistogram>()

    /** Süreyi ekler. Geçersiz ad ya da 24 ölçümden fazlası sessizce atlanır. */
    @Synchronized
    fun record(metric: String, ms: Long) {
        if (!METRIC.matches(metric)) return
        val h = histograms[metric] ?: run {
            if (histograms.size >= MAX_METRICS) return
            LatencyHistogram().also { histograms[metric] = it }
        }
        h.record(ms)
    }

    /** Çevirmenden gelen satır: hem genel `tr.provider` hem adıyla ayrı tutulur. */
    @Synchronized
    fun recordProvider(name: String, ms: Long) {
        record(Metric.PROVIDER, ms)
        val named = Metric.provider(name)
        if (named != Metric.PROVIDER) record(named, ms)
    }

    @get:Synchronized
    val isEmpty: Boolean get() = histograms.values.none { it.count > 0 }

    @Synchronized
    fun count(metric: String): Long = histograms[metric]?.count ?: 0

    @Synchronized
    fun toWire(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        for ((k, v) in histograms) if (v.count > 0) out[k] = v.toWire()
        return out
    }

    companion object {
        const val MAX_METRICS = 24
        private val METRIC = Regex("^[a-z0-9_.]{1,32}(:[a-z0-9_-]{1,24})?$")
    }
}
