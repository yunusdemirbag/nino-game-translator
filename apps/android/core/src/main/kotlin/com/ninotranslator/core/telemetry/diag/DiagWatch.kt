// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.telemetry.diag

import com.ninotranslator.core.telemetry.TelemetryEvent
import com.ninotranslator.core.telemetry.TelemetryEvent.DiagStep
import com.ninotranslator.core.telemetry.TelemetryEvent.Severity
import com.ninotranslator.core.telemetry.TelemetryEvent.TvBrand
import com.ninotranslator.core.telemetry.diag.DiagConfig.Limit

/**
 * Otomatik teşhis bekçisi (tarif: NinoCore docs/tarif/otomatik-teshis.md). Saf: saat dışarıdan verilir, uygulama
 * yalnız yapılandırılmış adım ([step]) ve sayı ([set]) yazar; [tick] saniyede bir çağrılır. Bir kural tetiklenince
 * `diag` olayı [sink]'e gider (ölçüm kuyruğu). Olayda serbest metin, ad, adres hiç yoktur: yalnız kod ve sayı.
 *
 * Genel kurallar: susturma (son 2 dk'da uyku/uyanma, arka plana geçiş ya da kullanıcı durdurması; açılışın ilk 60 sn'si;
 * ağ yokken ağ dışı kurallar), tek kök (5 dk içindeki tetiklerden yalnız önceliği en yüksek olan gider, öbürleri iz
 * adımı olur), aynı kural oturumda bir kez, günde 5 / kural başına 2 ([DiagBudget]).
 */
class DiagWatch(
    private val clock: () -> Long,
    private val sink: (TelemetryEvent) -> Unit,
    private val config: () -> DiagConfig = { DiagConfig() },
    private val budget: DiagBudget = DiagBudget(),
    /** Bellek eşiği (MB): telefon 800, TV 400, masaüstü 1500. Sunucu `app.resources.memMB` ile değiştirebilir. */
    private val memHighMb: Double = 800.0,
    private val context: () -> Context = { Context() },
) {
    /** Bildirime eklenen bağlam: bağlı TV (marka, model, TV'deki sürüm), oyun kimliği, bileşen sürümleri. */
    data class Context(
        val tvBrand: TvBrand? = null,
        val tvModel: String? = null,
        val tvApp: String? = null,
        val game: String? = null,
        val versions: Map<String, String> = emptyMap(),
    )

    /** Kurallar; [priority] büyük olan tek kök kuralında kazanır. [network]: ağ yokken de çalışır. [session]: oturum gerekir. */
    enum class Rule(val code: String, val priority: Int, val severity: Severity, val network: Boolean, val session: Boolean) {
        APP_HANG("app.hang", 9, Severity.ERROR, false, false),
        PS5_NO_RETURN("ps5.no_return", 8, Severity.ERROR, true, true),
        TV_FLAPPING("tv.flapping", 7, Severity.WARN, true, true),
        OCR_STALLED("ocr.stalled", 6, Severity.ERROR, false, true),
        TR_ERRORS("tr.errors", 5, Severity.WARN, true, true),
        TR_SLOW("tr.slow", 4, Severity.WARN, false, true),
        OCR_SILENT("ocr.silent", 3, Severity.INFO, false, true),
        APP_RESOURCES("app.resources", 2, Severity.WARN, false, false),
        PACK_DOWNLOAD("pack.download", 1, Severity.WARN, true, false),
    }

    /** Tetiklenen (gönderilmiş ya da tek kök kuralıyla ize düşmüş) bir teşhis; uygulamanın kendi ekranı için. */
    data class Finding(val rule: String, val cause: String, val atMs: Long, val sent: Boolean)

    private class Candidate(val rule: Rule, val cause: String, val atMs: Long, val state: Map<String, Any?>, val trail: List<DiagStep>)
    private class Group(val startMs: Long) { val items = ArrayList<Candidate>() }
    private class TrResult(val ok: Boolean, val http: Long?, val kind: String?)
    private class Line(val totalMs: Long, val origin: String?)
    private class PackFail(var count: Int, val firstMs: Long, var http: Long?, var kind: String?, var sizeKb: Long?)

    private val lock = Any()
    private val trail = DiagTrail()
    private val facts = HashMap<String, Any>()
    private val fired = HashSet<Rule>()
    private val out = ArrayList<TelemetryEvent>()
    private val recent = ArrayDeque<Finding>()
    private var group: Group? = null

    private val launchMs = clock()
    private var muteMs: Long? = null
    private var asleep = false
    private var session = false
    private var sessionMs = 0L
    private var netDown = false

    // PS5
    private var ps5Up = false
    private var dropMs: Long? = null
    private var dropReason: String? = null
    private var dropNetDown = false
    private var retries = 0L
    private var fps: Long? = null
    private var lastFps: Long? = null
    private var framesSince: Long? = null
    private var stallSince: Long? = null
    private var decoderMs: Long? = null

    // Okuma
    private var textMs: Long? = null
    private var silentBase: Long? = null
    private var ocrSince: Long? = null
    private var ocrCounted = false
    private var ocrMs: Long? = null
    private val ocrStalls = ArrayDeque<Long>()
    private val ocrTimes = ArrayDeque<Long>()

    // TV
    private var tvCount = 0
    private val tvUpSince = ArrayDeque<Long>()
    private val tvDrops = ArrayDeque<Triple<Long, String, Long?>>()

    // Çeviri
    private val results = ArrayDeque<TrResult>()
    private val lines = ArrayDeque<Line>()

    // Kaynaklar ve paketler
    private var highSince: Long? = null
    private val packs = HashMap<String, PackFail>()

    /** Son teşhisler (en yeni sonda, en çok 20). */
    val findings: List<Finding> get() = synchronized(lock) { recent.toList() }

    /** İzin şimdiki hâli (testler ve Sistem sağlığı ekranı için). */
    fun trailNow(): List<DiagStep> = synchronized(lock) { trail.snapshot(clock()) }

    // ---- girişler ----

    /** Bekçinin sayı/kod durumu (`frameLuma`, `region`, `net`, `proto`…). `null` siler. Yalnız sayı, doğru/yanlış, kısa kod. */
    fun set(key: String, value: Any?) = run {
        if (value == null) { facts.remove(key) } else { facts[key] = value }
    }

    /**
     * Yapılandırılmış adım (tarifteki iz kodları: `session.start`, `ps5.drop`, `tv.drop`, `tr.error`…).
     * [reason]: adımın sebep kodu (ör. TV kopma nedeni `write_error`); ize girmez, yalnız sebep seçiminde kullanılır.
     */
    fun step(code: String, value: Long? = null, reason: String? = null) = run {
        val now = clock()
        if (code != "ps5.frame" || frameStepWorthy(value)) trail.add(now, code, value)
        when (code) {
            "session.start" -> startSession(now)
            "session.stop" -> { resolve(); session = false; mute(now) }
            "sys.sleep" -> { asleep = true; mute(now) }
            "sys.wake" -> { asleep = false; mute(now) }
            "app.background" -> mute(now)
            "net.down" -> { netDown = true; facts["net"] = "none"; if (dropMs != null) dropNetDown = true }
            "net.up", "net.change" -> netDown = false
            "ps5.connect" -> { ps5Up = true; dropMs = null; stallSince = null }
            "ps5.drop" -> onPs5Drop(now, reason)
            "ps5.retry" -> retries = value ?: (retries + 1)
            "ps5.frame" -> onFps(now, value ?: 0)
            "tv.connect" -> { tvCount++; tvUpSince.addLast(now) }
            "tv.drop" -> onTvDrop(now, reason)
            "ocr.text" -> textMs = now
            "tr.ok" -> onResult(now, TrResult(true, null, null))
            "tr.error" -> onResult(now, TrResult(false, value, reason))
            "mem.high" -> fire(Rule.APP_RESOURCES, "memory_high", now, resourceState(value))
            "pack.fail" -> onPackFail(now, "", value, reason, null)
            else -> if (code == STREAM_DECODER) decoderMs = now
        }
        evaluate(now)
    }

    /** Saniyede bir: süreye bağlı kurallar ve tek kök penceresinin kapanması. */
    fun tick() = run { evaluate(clock()) }

    /** Bekleyen teşhisi beklemeden gönderir (uygulama kapanırken). */
    fun flush() = run { resolve() }

    /** Yazı tanıma isteği başladı (10 sn'de dönmezse takılma sayılır). */
    fun ocrStarted() = run { ocrSince = clock(); ocrCounted = false }

    /** Yazı tanıma döndü: süre ve yazı okundu mu. Okunduysa sessizlik sayacı sıfırlanır. */
    fun ocrDone(ms: Long, text: Boolean) = run {
        val now = clock()
        if (ocrSince != null && !ocrCounted && ms >= limitMs(Limit.OCR_STALL_SEC, 1000)) countOcrStall(now)
        ocrSince = null
        ocrMs = ms
        ocrTimes.addLast(ms); while (ocrTimes.size > 50) ocrTimes.removeFirst()
        if (ms >= OCR_SLOW_MS) trail.add(now, "ocr.slow", ms)
        trail.add(now, if (text) "ocr.text" else "ocr.empty")
        if (text) textMs = now
        evaluate(now)
    }

    /**
     * Ekranda yeni çeviri satırı: `tr.total` süresi ve kaynağı (`pack` `pool` `provider` `device`). [request]: satır
     * ağdan (havuz ya da çevirmen) geldiyse istek başarısı sayılır.
     */
    fun line(totalMs: Long?, origin: String?, request: Boolean) = run {
        val now = clock()
        if (totalMs != null && totalMs >= 0) {
            lines.addLast(Line(totalMs, origin)); while (lines.size > 50) lines.removeFirst()
            if (totalMs > config().limit(Limit.TR_SLOW_P90_MS)) trail.add(now, "tr.slow", totalMs)
        }
        if (request) { trail.add(now, "tr.ok"); onResult(now, TrResult(true, null, null)) }
        checkSlow(now)
        evaluate(now)
    }

    /** Bellek (MB), işlemci (%), ısı durumu (`nominal` `fair` `serious` `critical`); düzenli örnek. */
    fun resources(memMb: Long?, cpuPct: Long?, thermal: String?) = run {
        val now = clock()
        memMb?.let { facts["memMB"] = it }; cpuPct?.let { facts["cpu"] = it }; thermal?.let { facts["thermal"] = it }
        val c = config()
        val memHigh = memMb != null && memMb > (c.limits[Limit.MEM_HIGH_MB.key] ?: c.limits[Limit.MEM_HIGH_MB.alias] ?: memHighMb)
        val cpuHigh = cpuPct != null && cpuPct > c.limit(Limit.CPU_HIGH_PCT)
        val hot = thermal == "serious" || thermal == "critical"
        if (!memHigh && !cpuHigh && !hot) highSince = null
        else {
            val since = highSince ?: now.also { highSince = it }
            if (now - since >= RESOURCES_MS) {
                if (fire(Rule.APP_RESOURCES, if (memHigh) "memory_high" else if (cpuHigh) "cpu_high" else "thermal", now, resourceState(memMb))) {
                    if (memHigh) trail.add(now, "mem.high", memMb) else if (cpuHigh) trail.add(now, "cpu.high", cpuPct)
                }
            }
        }
        evaluate(now)
    }

    /** Ana iş parçacığı [blockedSec] saniye yanıt vermedi (izleyici iş parçacığından). */
    fun mainBlocked(blockedSec: Long) = run {
        val now = clock()
        if (blockedSec < config().limit(Limit.HANG_SEC)) return@run
        trail.add(now, "app.blocked", blockedSec)
        val s = linkedMapOf<String, Any?>("blockedSec" to blockedSec, "memMB" to facts["memMB"], "cpu" to facts["cpu"])
        if (session) s["sessionMin"] = (now - sessionMs) / 60_000
        fire(Rule.APP_HANG, "main_thread", now, s)
        evaluate(now)
    }

    /** Oyun paketi inmedi. [key] yalnız saymak için (gönderilmez). [reason]: `offline` `corrupt` `storage_full`. */
    fun packFailed(key: String, http: Long?, reason: String?, sizeKb: Long? = null) = run {
        val now = clock()
        trail.add(now, "pack.fail", http)
        onPackFail(now, key, http, reason, sizeKb)
        evaluate(now)
    }

    fun packOk(key: String) = run { packs.remove(key) }

    // ---- kurallar ----

    private fun startSession(now: Long) {
        session = true
        sessionMs = now
        fired.clear()
        ps5Up = false; dropMs = null; retries = 0; fps = null; lastFps = null; framesSince = null; stallSince = null
        textMs = null; silentBase = null; ocrStalls.clear(); tvDrops.clear(); results.clear(); lines.clear()
    }

    /** Susturma olayı: kural sayaçları sıfırlanır, 2 dk tetik yok. */
    private fun mute(now: Long) {
        muteMs = now
        dropMs = null
        tvDrops.clear()
        silentBase = now
        stallSince = null
        ocrStalls.clear()
        results.clear()
        highSince = null
    }

    private fun eventMuted(now: Long) = asleep || muteMs?.let { now - it < MUTE_MS } == true

    private fun onPs5Drop(now: Long, reason: String?) {
        ps5Up = false
        fps = null; framesSince = null; stallSince = null
        if (!session || eventMuted(now) || dropMs != null) return
        dropMs = now
        dropReason = reason
        dropNetDown = netDown
        retries = 0
    }

    private fun onFps(now: Long, value: Long) {
        fps = value
        if (value >= 1) {
            lastFps = value
            if (framesSince == null) framesSince = now
            stallSince = null
            dropMs = null
        } else {
            framesSince = null
            if (ps5Up && stallSince == null) stallSince = now
        }
    }

    private fun frameStepWorthy(value: Long?): Boolean {
        val v = value ?: 0
        val last = fps ?: return true
        if ((v >= 1) != (last >= 1)) return true
        return v >= 1 && (v * 2 < last || v > last * 2)
    }

    private fun onTvDrop(now: Long, reason: String?) {
        tvCount = (tvCount - 1).coerceAtLeast(0)
        val up = tvUpSince.removeFirstOrNull()?.let { (now - it) / 1000 }
        if (!session || eventMuted(now)) return
        tvDrops.addLast(Triple(now, tvCause(reason), up))
        val window = limitMs(Limit.TV_FLAP_WINDOW_MIN, 60_000)
        while (tvDrops.isNotEmpty() && now - tvDrops.first().first > window) tvDrops.removeFirst()
        if (tvDrops.size < config().limit(Limit.TV_FLAP_COUNT).toInt().coerceAtLeast(1)) return
        val counts = tvDrops.groupingBy { it.second }.eachCount()
        val top = counts.maxByOrNull { it.value }!!
        val cause = when {
            top.value * 2 <= tvDrops.size -> "mixed"
            top.key in TV_CAUSES -> top.key
            else -> "unknown"
        }
        val ups = tvDrops.mapNotNull { it.third }
        val s = base(now, "drops" to tvDrops.size.toLong(), "tvCount" to tvCount.toLong(), "proto" to facts["proto"])
        if (ups.isNotEmpty()) s["avgUpSec"] = ups.sum() / ups.size
        fire(Rule.TV_FLAPPING, cause, now, s)
    }

    private fun onResult(now: Long, r: TrResult) {
        results.addLast(r); while (results.size > TR_WINDOW) results.removeFirst()
        if (results.size < TR_MIN) return
        val errors = results.filter { !it.ok }
        if (errors.size.toDouble() / results.size <= config().limit(Limit.TR_ERROR_RATE)) return
        val classes = errors.map { trClass(it) }
        val cause = classes.groupingBy { it }.eachCount().maxByOrNull { it.value }!!.key
        val http = errors.mapNotNull { it.http }.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
        val s = base(now, "errors" to errors.size.toLong(), "requests" to results.size.toLong(), "provider" to facts["provider"], "http" to http)
        fire(Rule.TR_ERRORS, cause, now, s)
    }

    private fun trClass(r: TrResult): String {
        r.kind?.takeIf { it in TR_CAUSES }?.let { return it }
        val h = r.http ?: 0
        return when {
            h == 429L -> "quota"
            h == 401L || h == 403L -> "auth"
            h == 408L -> "timeout"
            h in 500..599 -> "server"
            netDown -> "offline"
            else -> "unknown"
        }
    }

    private fun checkSlow(now: Long) {
        if (lines.size < SLOW_MIN) return
        val limit = config().limit(Limit.TR_SLOW_P90_MS)
        val totals = lines.map { it.totalMs }
        val p90 = pct(totals, 0.9)
        if (p90 <= limit) return
        val n = lines.size.toDouble()
        val provider = lines.filter { it.origin == "provider" }
        val pool = lines.filter { it.origin == "pool" }
        val ocrP90 = if (ocrTimes.isEmpty()) null else pct(ocrTimes.toList(), 0.9)
        val cause = when {
            provider.size / n >= 0.5 && pct(provider.map { it.totalMs }, 0.9) > limit -> "provider_slow"
            pool.size / n >= 0.5 && pct(pool.map { it.totalMs }, 0.9) > limit -> "pool_slow"
            ocrP90 != null && ocrP90 >= OCR_BUSY_MS -> "device_busy"
            else -> "network_slow"
        }
        val s = base(now, "p50" to pct(totals, 0.5), "p90" to p90, "provider" to facts["provider"],
            "poolShare" to round2(pool.size / n), "providerShare" to round2(provider.size / n), "ocrP90" to ocrP90)
        fire(Rule.TR_SLOW, cause, now, s)
    }

    private fun countOcrStall(now: Long) {
        ocrCounted = true
        ocrStalls.addLast(now)
        while (ocrStalls.isNotEmpty() && now - ocrStalls.first() > STALL_WINDOW_MS) ocrStalls.removeFirst()
        if (ocrStalls.size >= 3) fire(Rule.OCR_STALLED, "ocr_hang", now, stallState(now))
    }

    private fun onPackFail(now: Long, key: String, http: Long?, reason: String?, sizeKb: Long?) {
        val p = packs.getOrPut(key) { PackFail(0, now, null, null, null) }
        p.count++; p.http = http ?: p.http; p.kind = reason ?: p.kind; p.sizeKb = sizeKb ?: p.sizeKb
        val attempts = config().limit(Limit.PACK_ATTEMPTS).toInt().coerceAtLeast(1)
        if (p.count < attempts && now - p.firstMs < DAY_MS) return
        val h = p.http ?: 0
        val cause = when {
            p.kind in PACK_CAUSES -> p.kind!!
            h in 400..499 -> "http_4xx"
            h in 500..599 -> "http_5xx"
            netDown -> "offline"
            else -> "unknown"
        }
        val s = linkedMapOf<String, Any?>("attempts" to p.count.toLong(), "http" to p.http, "sizeKB" to p.sizeKb)
        if (fire(Rule.PACK_DOWNLOAD, cause, now, s)) packs.remove(key)
    }

    /** Süreye bağlı kurallar ve tek kök penceresi. */
    private fun evaluate(now: Long) {
        val d = dropMs
        if (d != null && now - d >= limitMs(Limit.PS5_NO_RETURN_SEC, 1000)) {
            dropMs = null
            val cause = if (dropNetDown || netDown) "network_lost" else when (dropReason) {
                "network_lost" -> "network_lost"
                "standby", "ps5_standby" -> "ps5_standby"
                "ps5_closed", "closed" -> "ps5_closed"
                "kicked" -> "kicked"
                "stalled" -> "stalled"
                else -> "timeout"
            }
            val s = base(now, "ps5" to "down", "tv" to if (tvCount > 0) "up" else "down",
                "retries" to retries, "lastFps" to lastFps, "lostPackets" to facts["lostPackets"])
            fire(Rule.PS5_NO_RETURN, cause, now, s)
        }
        val f = framesSince
        if (session && f != null && (fps ?: 0) >= 1) {
            val from = maxOf(f, sessionMs, textMs ?: Long.MIN_VALUE, silentBase ?: Long.MIN_VALUE)
            if (now - from >= limitMs(Limit.OCR_SILENT_MIN, 60_000)) {
                val luma = (facts["frameLuma"] as? Number)?.toDouble()
                val cause = when {
                    (luma != null && luma <= 16) || facts["frameSame"] == true -> "video_black"
                    facts["region"] == "manual" -> "region_wrong"
                    else -> "no_text"
                }
                val s = base(now, "fps" to fps, "frameLuma" to facts["frameLuma"], "frameSame" to facts["frameSame"],
                    "region" to facts["region"], "ocrMs" to ocrMs)
                fire(Rule.OCR_SILENT, cause, now, s)
            }
        }
        val st = stallSince
        if (session && ps5Up && st != null && now - st >= limitMs(Limit.FRAMES_STALL_SEC, 1000)) {
            val decoder = decoderMs?.let { now - it <= STALL_WINDOW_MS } == true
            fire(Rule.OCR_STALLED, if (decoder) "decoder" else "frames_stopped", now, stallState(now))
        }
        val o = ocrSince
        if (o != null && !ocrCounted && now - o >= limitMs(Limit.OCR_STALL_SEC, 1000)) countOcrStall(now)
        val g = group
        if (g != null && now - g.startMs >= GROUP_MS) resolve()
    }

    private fun stallState(now: Long) = base(now, "ocrMs" to ocrMs, "queue" to facts["queue"], "fps" to fps,
        "memMB" to facts["memMB"], "cpu" to facts["cpu"])

    private fun resourceState(memMb: Long?): LinkedHashMap<String, Any?> {
        val s = linkedMapOf<String, Any?>("memMB" to (memMb ?: facts["memMB"]), "cpu" to facts["cpu"], "thermal" to facts["thermal"])
        if (session) s["sessionMin"] = (clock() - sessionMs) / 60_000
        return s
    }

    /** Her bildirimde: ağ ve oturum süresi. */
    private fun base(now: Long, vararg more: Pair<String, Any?>): LinkedHashMap<String, Any?> = linkedMapOf<String, Any?>(
        "net" to (if (netDown) "none" else facts["net"]), "sessionMin" to (now - sessionMs) / 60_000,
    ).also { it.putAll(more) }

    // ---- tetik, tek kök, gönderim ----

    /** Kural tetiklenebiliyorsa adaylara ekler (önce iz alınır, sonra kural iz adımı olur). */
    private fun fire(rule: Rule, cause: String, now: Long, state: Map<String, Any?>): Boolean {
        if (config().isOff(rule.code) || rule in fired) return false
        if (rule.session && !session) return false
        if (asleep || muteMs?.let { now - it < MUTE_MS } == true || now - launchMs < LAUNCH_MUTE_MS) return false
        if (netDown && !rule.network) return false
        fired += rule
        val c = Candidate(rule, cause, now, state.filterValues { it != null }, trail.snapshot(now))
        trail.add(now, rule.code)
        val g = group ?: Group(now).also { group = it }
        g.items += c
        // Askı en yüksek öncelikli: beklemeden gönderilir (süreç çoğu zaman ardından kapanır).
        if (rule == Rule.APP_HANG) resolve()
        return true
    }

    private fun resolve() {
        val g = group ?: return
        group = null
        val win = g.items.maxWithOrNull(compareBy<Candidate> { it.rule.priority }.thenByDescending { it.atMs }) ?: return
        for (c in g.items) if (c !== win) remember(Finding(c.rule.code, c.cause, c.atMs, false))
        val ctx = runCatching(context).getOrDefault(Context())
        val e = TelemetryEvent.diag(win.rule.code, win.cause, win.rule.severity, win.state, win.trail,
            ctx.tvBrand, ctx.tvModel, ctx.tvApp, ctx.game, ctx.versions)?.copy(time = Math.floorDiv(win.atMs, 1000L)) ?: return
        val sent = budget.take(win.rule.code, win.atMs)
        remember(Finding(win.rule.code, win.cause, win.atMs, sent))
        if (sent) out += e
    }

    private fun remember(f: Finding) {
        recent.addLast(f)
        while (recent.size > 20) recent.removeFirst()
    }

    /** Kilit içinde çalıştırır; çıkan olaylar kilit dışında gönderilir. */
    private inline fun run(block: () -> Unit) {
        val events = synchronized(lock) { block(); out.toList().also { out.clear() } }
        events.forEach { runCatching { sink(it) } }
    }

    private fun limitMs(l: Limit, unit: Long): Long = (config().limit(l) * unit).toLong()

    private companion object {
        const val MUTE_MS = 120_000L
        const val LAUNCH_MUTE_MS = 60_000L
        const val GROUP_MS = 300_000L
        const val STALL_WINDOW_MS = 300_000L
        const val RESOURCES_MS = 120_000L
        const val DAY_MS = 86_400_000L
        const val TR_WINDOW = 40
        const val TR_MIN = 10
        const val SLOW_MIN = 20
        const val OCR_SLOW_MS = 2_000L
        const val OCR_BUSY_MS = 1_500L
        const val STREAM_DECODER = "ps5.stream.decoder"
        val TV_CAUSES = setOf("write_error", "timeout", "closed", "resume", "network_change")
        val TR_CAUSES = setOf("quota", "auth", "offline", "server", "timeout")
        val PACK_CAUSES = setOf("offline", "corrupt", "storage_full")

        fun tvCause(reason: String?): String = when (reason) {
            "tv_closed" -> "closed"
            "network_lost" -> "network_change"
            null -> "unknown"
            else -> reason
        }

        fun pct(values: List<Long>, p: Double): Long {
            if (values.isEmpty()) return 0
            val s = values.sorted()
            return s[(kotlin.math.ceil(p * s.size).toInt() - 1).coerceIn(0, s.size - 1)]
        }

        fun round2(d: Double) = Math.round(d * 100) / 100.0
    }
}
