// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import com.ninotranslator.core.http.HttpRequest
import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.http.HttpTransport
import com.ninotranslator.core.http.UrlConnectionTransport
import com.ninotranslator.core.json.Json
import com.ninotranslator.core.pool.PoolEndpoint
import com.ninotranslator.mobile.BuildConfig
import com.ninotranslator.mobile.data.HealthIssue
import com.ninotranslator.mobile.data.HealthIssueKind
import com.ninotranslator.mobile.data.Nino
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.Locale

/** Nino'nun havuz sunucusu (Sorun Bildir, Nino'ya Sor). Adres `pool/endpoint.txt` kuralıyla. */
object NinoServer {
    @Volatile var http: HttpTransport = UrlConnectionTransport

    fun endpoint(): String = PoolEndpoint.resolve(Nino.filesDir)

    @Throws(IOException::class)
    fun post(path: String, body: String, timeoutMs: Int): HttpResponse =
        http.send(HttpRequest.json(endpoint() + path, body, mapOf("User-Agent" to PoolEndpoint.userAgent(BuildConfig.VERSION_NAME)),
            connectTimeoutMs = 15_000, readTimeoutMs = timeoutMs))

    /** Ortak alanlar: `v`, `install`, `app`, `platform`, `language`. */
    fun baseBody(): LinkedHashMap<String, Any?> = base(Nino.installId, BuildConfig.VERSION_NAME, Nino.settings.targetLanguage)

    fun base(install: String, app: String, language: String): LinkedHashMap<String, Any?> = linkedMapOf(
        "v" to 1, "install" to install, "app" to app, "platform" to "android", "language" to language,
    )

    fun image(jpeg: ByteArray): Map<String, Any?> = linkedMapOf("mime" to "image/jpeg", "data" to Base64.getEncoder().encodeToString(jpeg))
}

/** Sorun kayıtlarının destek satırı ve "Nino'nun tespitleri" metni (dilden bağımsız Türkçe). */
object Findings {
    private val STAMP = DateTimeFormatter.ofPattern("dd.MM HH:mm", Locale.ROOT)
    const val THREE_DAYS_MS = 3L * 24 * 60 * 60 * 1000

    fun kindName(k: HealthIssueKind): String = when (k) {
        HealthIssueKind.PS5_DROPPED -> "PS5 bağlantısı koptu"
        HealthIssueKind.PS5_UNREACHABLE -> "PS5 dakikalardır geri gelmiyor"
        HealthIssueKind.NETWORK_LOST -> "Telefonun ağ bağlantısı gitti"
        HealthIssueKind.TV_DROPPED -> "TV bağlantısı koptu"
    }

    fun causeName(c: HealthCause): String = when (c) {
        HealthCause.OFFLINE -> "Bu telefonun ağ bağlantısı yok"
        HealthCause.PS5_AFTER_NETWORK -> "Telefon ağdan düşünce PS5 de koptu"
        HealthCause.PS5_ASLEEP -> "PS5 kapatıldı veya dinlenme moduna girdi"
        HealthCause.PS5_IN_USE -> "Remote Play'i başka bir cihaz devraldı"
        HealthCause.PS5_LOST -> "PS5 koptu, bir daha bağlanamadı"
        HealthCause.PS5_NEVER -> "Nino PS5'e bağlanamadı"
        HealthCause.NETWORK_DROPPED -> "Oyun sırasında telefon ağdan düştü"
        HealthCause.PICTURE_WIFI -> "PS5 görüntüsü Wi-Fi üzerinde kayboluyor"
        HealthCause.PICTURE -> "PS5 görüntüsü ağda veri kaybediyor"
        HealthCause.DROPS -> "PS5 bağlantısı sık kopuyor"
        HealthCause.SLOW -> "Çeviri yavaş"
        HealthCause.TV -> "TV uygulaması bu telefondan ayrıldı"
    }

    fun supportLine(i: HealthIssue, zone: ZoneId = ZoneId.systemDefault()): String {
        val parts = ArrayList<String>()
        parts += STAMP.withZone(zone).format(Instant.ofEpochMilli(i.dateMs)) + " " + kindName(i.kind) +
            (i.reason?.let { " ($it)" } ?: "")
        i.streamedMinutes?.let { parts += "${it.toInt()} dk oynandı" }
        if (i.network.isNotEmpty()) parts += "ağ ${i.network}"
        i.framesPerSecond?.let { parts += "${it.toInt()} kare/sn" }
        i.game?.let { parts += it }
        return parts.joinToString(" · ")
    }

    /** Son üç günün sorunları, en yeni başta. */
    fun recent(nowMs: Long): List<HealthIssue> = recent(Nino.health.newestFirst(), nowMs)

    fun recent(newestFirst: List<HealthIssue>, nowMs: Long): List<HealthIssue> = newestFirst.filter { nowMs - it.dateMs <= THREE_DAYS_MS }

    /** Bildirim metninin altına eklenen bölüm (elle ve otomatik bildirim aynısını kullanır). */
    fun section(input: HealthInput, nowMs: Long, newestFirst: List<HealthIssue> = Nino.health.newestFirst()): String = buildString {
        append("— Nino'nun tespitleri —\n")
        val causes = HealthEval.causes(input)
        if (causes.isNotEmpty()) append("Muhtemel sebep: ").append(causes.joinToString("; ") { causeName(it) }).append('\n')
        val issues = recent(newestFirst, nowMs).take(12)
        if (issues.isNotEmpty()) {
            append("Son sorunlar:\n")
            issues.forEach { append("• ").append(supportLine(it)).append('\n') }
        }
        append(HealthEval.summaryLine(input))
    }
}

/** Elle sorun bildirimi (servis.md §7). */
object ReportSender {
    const val MAX_TEXT = 4000
    const val MAX_CONTACT = 200
    const val MAX_BODY = 4 * 1024 * 1024
    const val NO_TEXT = "[Hataları gönder] Açıklama alanı boş bırakıldı; ayrıntılar aşağıdaki bölümde."

    enum class Result { SENT, INVALID, TOO_LARGE, RATE_LIMITED, FAILED }

    /** Açıklama + tespitler, 4000'de kırpılmış. */
    fun composeText(userText: String, findings: String): String {
        val head = userText.trim().ifEmpty { NO_TEXT }
        return DeviceSummary.clip("$head\n\n$findings", MAX_TEXT)
    }

    fun buildBody(text: String, contact: String, log: String?, device: String, images: List<ByteArray>): String {
        val body = NinoServer.baseBody()
        body["text"] = text
        contact.trim().take(MAX_CONTACT).takeIf { it.isNotEmpty() }?.let { body["contact"] = it }
        log?.takeIf { it.isNotEmpty() }?.let { body["log"] = it }
        device.takeIf { it.isNotEmpty() }?.let { body["device"] = it }
        if (images.isNotEmpty()) body["images"] = images.take(3).map { NinoServer.image(it) }
        return Json.write(body)
    }

    fun resultOf(status: Int): Result = when {
        status in 200..299 -> Result.SENT
        status == 400 -> Result.INVALID
        status == 413 -> Result.TOO_LARGE
        status == 429 -> Result.RATE_LIMITED
        else -> Result.FAILED
    }

    /** Engelleyici; IO iş parçacığında. */
    fun send(body: String): Result {
        if (body.toByteArray(Charsets.UTF_8).size > MAX_BODY) return Result.TOO_LARGE
        return try { resultOf(NinoServer.post("/v1/reports", body, 30_000).status) } catch (e: Exception) { Result.FAILED }
    }
}

/** Otomatik sorun bildirimi (servis.md 6.2): elle bildirimle aynı gövde ve tespitler, `kind: auto`. */
object AutoReport {
    const val HEAD = "[Otomatik] Bu bildirimi Nino kendisi gönderdi, kullanıcı metni yok."

    fun text(findings: String): String = DeviceSummary.clip("$HEAD\n\n$findings", ReportSender.MAX_TEXT)

    fun body(findings: String, device: String): String =
        bodyOf(Nino.installId, BuildConfig.VERSION_NAME, Nino.settings.targetLanguage, text(findings), device)

    fun bodyOf(install: String, app: String, language: String, text: String, device: String?): String {
        val b = NinoServer.base(install, app, language)
        b["text"] = text
        device?.takeIf { it.isNotEmpty() }?.let { b["device"] = DeviceSummary.clip(it, DeviceSummary.MAX) }
        b["kind"] = "auto"
        return Json.write(b)
    }

    /** Sunucu reddederse (geçersiz, çok büyük, sınır) ya da kabul ettiyse yeniden denenmez. */
    fun retryable(status: Int?): Boolean = status == null || status !in setOf(400, 413, 429) && status !in 200..299
}
