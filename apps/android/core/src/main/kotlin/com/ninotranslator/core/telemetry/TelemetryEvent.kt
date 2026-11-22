// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry

import com.ninotranslator.core.packs.GameIds

/**
 * Bir ölçüm olayı: `{"k": tür, "t": zaman (Unix sn), ...alanlar}`. Hazır kurucular tarifteki alanları doldurur;
 * ölçülmeyen alan konmaz (0 gönderilmez). Sayılar Long tutulur (diskten okununca da aynı).
 */
data class TelemetryEvent(val kind: Kind, val time: Long = 0, val fields: Map<String, Any?> = emptyMap()) {
    enum class Kind(val wire: String) {
        LAUNCH("launch"), SESSION("session"), CRASH("crash"), ERROR("error"),
        PS5_CONNECT("ps5_connect"), PS5_DROP("ps5_drop"), TV_CONNECT("tv_connect"), TV_DROP("tv_drop"),
        /** Otomatik teşhis (tarif: otomatik-teshis.md); günlük olay sınırından muaf. */
        DIAG("diag");

        companion object {
            fun of(wire: String?): Kind? = entries.firstOrNull { it.wire == wire }
        }
    }

    enum class Ps5Route(val wire: String) { LAN("lan"), REMOTE("remote"), XBOX("xbox") }
    enum class TvBrand(val wire: String) { ANDROID_TV("androidtv"), SAMSUNG("samsung"), LG("lg") }
    enum class TvProtocol(val wire: String) { NINO("nino"), LEGACY("legacy") }
    enum class Severity(val wire: String) { INFO("info"), WARN("warn"), ERROR("error") }

    /** Teşhis iz adımı: kaç saniye önce (−3600…0), kod, sayı?. */
    data class DiagStep(val seconds: Long, val code: String, val value: Long? = null)

    enum class SessionSource(val wire: String) { REMOTE_PLAY("remoteplay"), CAPTURE("capture"), XBOX("xbox"), SCREEN("screen") }

    fun toWire(): Map<String, Any?> = LinkedHashMap<String, Any?>().apply {
        put("k", kind.wire)
        put("t", time)
        for ((k, v) in fields) if (k != "k" && k != "t") put(k, v)
    }

    companion object {
        private val GAME = Regex("^[a-z0-9][a-z0-9._-]{0,63}$")

        /**
         * Oyun alanı: PS5'in bildirdiği, elle seçilen ya da ekrandan tanınan ad/kimlik [GameIds.id] ile kimliğe
         * çevrilebiliyorsa yalnız o kimlik (Mac/NinoCore ile aynı: takma ad asıl kimliğe, "Grand Theft Auto VI" → "gta-6";
         * tabloda olmayan yeni oyun slug'la, "Yeni Oyun" → "yeni-oyun"); çevrilemiyorsa ("!!!", boş) null ve alan hiç
         * konmaz (serbest metin gitmez).
         */
        fun gameField(game: String?): String? = GameIds.id(game)?.takeIf(GAME::matches)
        private val RULE = Regex("^[a-z0-9_.]{1,40}$")
        private val SHORT = Regex("^[A-Za-z0-9_.$-]{1,40}$")
        private val KEY = Regex("^[A-Za-z0-9_]{1,24}$")
        private val VERSION = Regex("^[0-9A-Za-z.+-]{1,24}$")
        private val MODEL = Regex("^[A-Za-z0-9][A-Za-z0-9 ,._()+-]{0,59}$")

        /**
         * Otomatik teşhis olayı. Yalnız kod, sayı ve doğru/yanlış: kurala uymayan alan atılır, kural geçersizse null.
         * `tv`: marka, model (ad değil), TV'deki Nino sürümü.
         */
        fun diag(
            rule: String, cause: String, severity: Severity = Severity.WARN,
            state: Map<String, Any?> = emptyMap(), trail: List<DiagStep> = emptyList(),
            tvBrand: TvBrand? = null, tvModel: String? = null, tvApp: String? = null,
            game: String? = null, versions: Map<String, String> = emptyMap(),
        ): TelemetryEvent? {
            if (!RULE.matches(rule)) return null
            val f = linkedMapOf<String, Any?>("rule" to rule, "cause" to (cause.takeIf { SHORT.matches(it) } ?: "unknown"), "sev" to severity.wire)
            val s = LinkedHashMap<String, Any?>()
            for ((k, v) in state.entries.sortedBy { it.key }) {
                if (s.size >= 30) break
                if (!KEY.matches(k)) continue
                when (v) {
                    is Boolean -> s[k] = v
                    is Double, is Float -> (v as Number).toDouble().takeIf { it.isFinite() && kotlin.math.abs(it) < 1e12 }?.let { s[k] = it }
                    is Number -> v.toLong().takeIf { kotlin.math.abs(it) < 1_000_000_000_000L }?.let { s[k] = it }
                    is String -> if (SHORT.matches(v)) s[k] = v
                    else -> Unit
                }
            }
            if (s.isNotEmpty()) f["state"] = s
            val steps = trail.takeLast(40).mapNotNull { st ->
                val code = TelemetryCode.clean(st.code) ?: return@mapNotNull null
                if (st.seconds !in -3600L..0L) return@mapNotNull null
                if (st.value != null) listOf(st.seconds, code, st.value) else listOf(st.seconds, code)
            }
            if (steps.isNotEmpty()) f["trail"] = steps
            val tv = LinkedHashMap<String, Any?>()
            if (tvBrand != null) tv["brand"] = tvBrand.wire
            tvModel?.trim()?.takeIf { MODEL.matches(it) }?.let { tv["model"] = it }
            tvApp?.takeIf { VERSION.matches(it) }?.let { tv["app"] = it }
            if (tv.isNotEmpty()) f["tv"] = tv
            gameField(game)?.let { f["game"] = it }
            val ver = versions.entries.sortedBy { it.key }.filter { KEY.matches(it.key) && VERSION.matches(it.value) }.take(6)
            if (ver.isNotEmpty()) f["ver"] = ver.associateTo(LinkedHashMap()) { it.key to it.value }
            return TelemetryEvent(Kind.DIAG, fields = f)
        }

        fun fromWire(m: Map<*, *>): TelemetryEvent? {
            val kind = Kind.of(m["k"] as? String) ?: return null
            val t = (m["t"] as? Number)?.toLong() ?: return null
            val f = LinkedHashMap<String, Any?>()
            for ((k, v) in m) if (k is String && k != "k" && k != "t") f[k] = v
            return TelemetryEvent(kind, t, f)
        }

        /** Uygulama açıldı. `ms`: soğuk açılış süresi (biliniyorsa). */
        fun launch(ms: Long? = null) = TelemetryEvent(Kind.LAUNCH, fields = if (ms != null) mapOf("ms" to ms.coerceAtLeast(0)) else emptyMap())

        /** Önceki çalışma çöktü. `code` geçersizse `unclean_exit`, `where` geçersizse atılır. `version`: çöken sürüm. */
        fun crash(code: String?, where: String? = null, version: String, uptime: Long? = null): TelemetryEvent {
            val f = linkedMapOf<String, Any?>("code" to (TelemetryCode.clean(code) ?: TelemetryCode.UNCLEAN_EXIT))
            TelemetryCode.cleanWhere(where)?.let { f["where"] = it }
            f["ver"] = version
            if (uptime != null && uptime >= 0) f["up"] = uptime
            return TelemetryEvent(Kind.CRASH, fields = f)
        }

        /** Yakalanan hata. Kod geçersizse (boşluk, yol, mesaj) null: serbest yazı gönderilmez. */
        fun error(code: String, http: Int? = null, count: Int = 1): TelemetryEvent? {
            val c = TelemetryCode.clean(code) ?: return null
            val f = linkedMapOf<String, Any?>("code" to c)
            if (http != null && http in 100..599) f["http"] = http.toLong()
            if (count > 1) f["n"] = count.toLong()
            return TelemetryEvent(Kind.ERROR, fields = f)
        }

        /** PS5 bağlantı denemesi bitti. `result`: "ok" ya da hata kodu. */
        fun ps5Connect(result: String, ms: Long?, via: Ps5Route) = TelemetryEvent(Kind.PS5_CONNECT, fields = linkedMapOf<String, Any?>().apply {
            put("r", if (result == "ok") "ok" else TelemetryCode.clean(result) ?: TelemetryCode.PS5_OTHER)
            if (ms != null) put("ms", ms.coerceAtLeast(0))
            put("via", via.wire)
        })

        /** Bağlıyken PS5 koptu. `after`: kaç saniyedir bağlıydı. */
        fun ps5Drop(reason: String, after: Long) = TelemetryEvent(Kind.PS5_DROP, fields = linkedMapOf(
            "code" to (TelemetryCode.clean(reason) ?: TelemetryCode.Drop.OTHER), "after" to after.coerceAtLeast(0),
        ))

        fun tvConnect(result: String, ms: Long?, brand: TvBrand?, proto: TvProtocol) = TelemetryEvent(Kind.TV_CONNECT, fields = linkedMapOf<String, Any?>().apply {
            put("r", if (result == "ok") "ok" else TelemetryCode.clean(result) ?: TelemetryCode.TV_OTHER)
            if (ms != null) put("ms", ms.coerceAtLeast(0))
            if (brand != null) put("brand", brand.wire)
            put("proto", proto.wire)
        })

        fun tvDrop(reason: String, brand: TvBrand?, after: Long) = TelemetryEvent(Kind.TV_DROP, fields = linkedMapOf<String, Any?>().apply {
            put("code", TelemetryCode.clean(reason) ?: TelemetryCode.Drop.OTHER)
            if (brand != null) put("brand", brand.wire)
            put("after", after.coerceAtLeast(0))
        })

        /** Çeviri oturumu bitti. `game` asıl kimlikle ([gameField]); kimliğe çevrilemeyen metinde alan konmaz. */
        fun session(durationS: Long, game: String?, source: SessionSource, lines: Long, timings: SessionTimings? = null): TelemetryEvent {
            val f = linkedMapOf<String, Any?>("dur" to durationS.coerceAtLeast(0))
            gameField(game)?.let { f["game"] = it }
            f["src"] = source.wire
            f["lines"] = lines.coerceAtLeast(0)
            val h = timings?.toWire().orEmpty()
            if (h.isNotEmpty()) f["h"] = h
            return TelemetryEvent(Kind.SESSION, fields = f)
        }
    }
}
