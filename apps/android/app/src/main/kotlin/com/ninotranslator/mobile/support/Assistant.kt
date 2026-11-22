// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.support

import com.ninotranslator.core.json.Json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** "Nino'ya Sor" uyarı türleri (sunucuya gitmez). */
enum class AssistantWarning(val retryable: Boolean) {
    DISABLED(false), RATE_LIMITED(false), BUSY(true), NETWORK(true), TOO_LARGE(false), INVALID(false)
}

/** Sohbetteki bir öğe. */
sealed interface ChatItem {
    val id: Long

    data class Nino(override val id: Long, val text: String, val reportSent: Boolean) : ChatItem

    enum class Status { PENDING, SENT, FAILED_RETRY, FAILED_FINAL }

    data class User(override val id: Long, val text: String, val images: List<ByteArray>, val status: Status) : ChatItem

    /** [forUser] bu uyarının ait olduğu kullanıcı mesajı. */
    data class Warning(override val id: Long, val kind: AssistantWarning, val forUser: Long) : ChatItem
}

/** Sohbetin durumu. */
data class ChatState(val items: List<ChatItem> = emptyList(), val waiting: Boolean = false)

/**
 * Sohbet (servis.md §13). Uygulama açık kaldıkça sürer (ekrandan çıkılsa da bekleyen yanıt gelir); süreç yeniden
 * başlayınca sıfırlanır. Kendi kapsamı vardır, ekranın değil.
 */
object AssistantChat {
    const val MAX_TEXT = 2000
    const val MAX_IMAGES = 3
    const val MAX_MESSAGES = 24
    const val MAX_BODY = 6 * 1024 * 1024

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(ChatState())
    val state: StateFlow<ChatState> = _state.asStateFlow()
    private var nextId = 1L

    /** Sunucu çağrısı; testte değiştirilir. Dönen: (durum, gövde). */
    @Volatile var transport: (String) -> Pair<Int, String> = { body ->
        val r = NinoServer.post("/v1/assistant", body, 90_000)
        r.status to r.text
    }

    /** Cihaz özeti; her mesajda yeniden okunur. */
    @Volatile var device: () -> String = { DeviceSummary.line() }

    fun newChat() {
        if (_state.value.waiting) return
        _state.value = ChatState()
    }

    fun send(text: String, images: List<ByteArray>) {
        val t = text.trim().take(MAX_TEXT)
        if (_state.value.waiting || (t.isEmpty() && images.isEmpty())) return
        val msg = ChatItem.User(id(), t, images.take(MAX_IMAGES), ChatItem.Status.PENDING)
        _state.update { it.copy(items = it.items + msg, waiting = true) }
        launch(msg)
    }

    /** Yeniden denenebilir hatada: mesaj sona taşınır, uyarı silinir, yeniden gönderilir. */
    fun retry(userId: Long) {
        val s = _state.value
        if (s.waiting) return
        val msg = s.items.firstOrNull { it.id == userId } as? ChatItem.User ?: return
        if (msg.status != ChatItem.Status.FAILED_RETRY) return
        val again = msg.copy(status = ChatItem.Status.PENDING)
        val rest = s.items.filterNot { it.id == userId || (it is ChatItem.Warning && it.forUser == userId) }
        _state.value = ChatState(rest + again, waiting = true)
        launch(again)
    }

    private fun launch(msg: ChatItem.User) {
        scope.launch {
            val history = _state.value.items.filter { it.id != msg.id }
            val body = AssistantRequest.build(history, msg, device())
            val outcome = if (body == null) AssistantOutcome.Failed(AssistantWarning.TOO_LARGE)
            else try { AssistantRequest.parse(transport(body)) } catch (e: Exception) { AssistantOutcome.Failed(AssistantWarning.NETWORK) }
            _state.update { s ->
                val items = s.items.map { item ->
                    if (item.id != msg.id) item else msg.copy(status = when (outcome) {
                        is AssistantOutcome.Reply -> ChatItem.Status.SENT
                        is AssistantOutcome.Failed -> if (outcome.kind.retryable) ChatItem.Status.FAILED_RETRY else ChatItem.Status.FAILED_FINAL
                    })
                }
                val extra = when (outcome) {
                    is AssistantOutcome.Reply -> ChatItem.Nino(id(), outcome.text, outcome.reportSent)
                    is AssistantOutcome.Failed -> ChatItem.Warning(id(), outcome.kind, msg.id)
                }
                ChatState(items + extra, waiting = false)
            }
        }
    }

    @Synchronized private fun id() = nextId++
}

sealed interface AssistantOutcome {
    data class Reply(val text: String, val reportSent: Boolean) : AssistantOutcome
    data class Failed(val kind: AssistantWarning) : AssistantOutcome
}

/** İstek gövdesi ve yanıt çözümü. Saf; birim testi var. */
object AssistantRequest {
    const val SCREENSHOT = "[screenshot]"

    /** Gövde; sığmazsa null ("çok büyük"). */
    fun build(history: List<ChatItem>, current: ChatItem.User, device: String): String? {
        val msgs = (history.filter { it is ChatItem.Nino || (it is ChatItem.User && it.status == ChatItem.Status.SENT) } + current)
            .filter { it !is ChatItem.User || it.text.isNotEmpty() || it.images.isNotEmpty() }
            .takeLast(AssistantChat.MAX_MESSAGES)
        // Kaç fotoğraflı mesaj fotoğrafıyla gitsin: 2 → 1 → 0.
        for (keep in intArrayOf(2, 1, 0)) {
            val body = encode(msgs, keep, device)
            if (body.toByteArray(Charsets.UTF_8).size <= AssistantChat.MAX_BODY) return body
        }
        return null
    }

    private fun encode(msgs: List<ChatItem>, keepImages: Int, device: String): String {
        val withImages = msgs.filterIsInstance<ChatItem.User>().filter { it.images.isNotEmpty() }.takeLast(keepImages).map { it.id }.toSet()
        val list = msgs.map { m ->
            when (m) {
                is ChatItem.Nino -> linkedMapOf<String, Any?>("role" to "assistant", "text" to m.text.take(AssistantChat.MAX_TEXT))
                is ChatItem.User -> {
                    val send = m.id in withImages
                    val text = if (m.images.isNotEmpty() && !send) (m.text + " " + SCREENSHOT).trim() else m.text
                    linkedMapOf<String, Any?>("role" to "user", "text" to text.take(AssistantChat.MAX_TEXT)).apply {
                        if (send) put("images", m.images.map { NinoServer.image(it) })
                    }
                }
                is ChatItem.Warning -> error("uyarı gitmez")
            }
        }
        val body = NinoServer.baseBody()
        body["messages"] = list
        if (device.isNotEmpty()) body["device"] = device
        return Json.write(body)
    }

    fun parse(response: Pair<Int, String>): AssistantOutcome {
        val (status, text) = response
        val m = runCatching { Json.parseObject(text) }.getOrNull()
        val error = (m?.get("error") as? String).orEmpty()
        return when {
            status in 200..299 -> {
                val reply = (m?.get("reply") as? String)?.takeIf { it.isNotBlank() }
                if (m?.get("ok") == true && reply != null) AssistantOutcome.Reply(reply, m["report"] != null)
                else AssistantOutcome.Failed(AssistantWarning.NETWORK)
            }
            status == 503 && (error == "assistant_disabled" || text.contains("assistant_disabled")) -> AssistantOutcome.Failed(AssistantWarning.DISABLED)
            status == 429 && (error == "busy" || text.contains("\"busy\"")) -> AssistantOutcome.Failed(AssistantWarning.BUSY)
            status == 429 -> AssistantOutcome.Failed(AssistantWarning.RATE_LIMITED)
            status == 413 -> AssistantOutcome.Failed(AssistantWarning.TOO_LARGE)
            status == 400 -> AssistantOutcome.Failed(AssistantWarning.INVALID)
            else -> AssistantOutcome.Failed(AssistantWarning.NETWORK)
        }
    }
}

/** Yanıt blokları (servis.md §13 "Yanıt gösterimi"). */
sealed interface ReplyBlock {
    data class Paragraph(val text: String) : ReplyBlock
    data class Step(val number: Int, val text: String) : ReplyBlock
    data class Bullet(val text: String) : ReplyBlock
}

object ReplyParser {
    private val STEP = Regex("""^\s*(\d{1,2})[.)]\s+(.*)$""")
    private val BULLET = Regex("""^\s*[-•*]\s+(.*)$""")
    private val LINK = Regex("""https?://[^\s<>"]+""")

    fun parse(text: String): List<ReplyBlock> {
        val out = ArrayList<ReplyBlock>()
        for (chunk in text.replace("\r\n", "\n").split(Regex("""\n\s*\n"""))) {
            var para: StringBuilder? = null
            fun flush() { para?.let { out += ReplyBlock.Paragraph(it.toString().trim()) }; para = null }
            for (line in chunk.split('\n')) {
                if (line.isBlank()) continue
                val step = STEP.matchEntire(line)
                val bullet = BULLET.matchEntire(line)
                when {
                    step != null -> { flush(); out += ReplyBlock.Step(step.groupValues[1].toInt(), step.groupValues[2].trim()) }
                    bullet != null -> { flush(); out += ReplyBlock.Bullet(bullet.groupValues[1].trim()) }
                    line.startsWith(" ") || line.startsWith("\t") -> {
                        val last = out.lastOrNull()
                        if (para == null && last is ReplyBlock.Step) out[out.size - 1] = last.copy(text = last.text + "\n" + line.trim())
                        else if (para == null && last is ReplyBlock.Bullet) out[out.size - 1] = last.copy(text = last.text + "\n" + line.trim())
                        else para = (para ?: StringBuilder()).also { if (it.isNotEmpty()) it.append('\n') }.append(line.trim())
                    }
                    else -> para = (para ?: StringBuilder()).also { if (it.isNotEmpty()) it.append('\n') }.append(line.trim())
                }
            }
            flush()
        }
        return out.filter { it !is ReplyBlock.Paragraph || it.text.isNotEmpty() }
    }

    /** Metindeki bağlantılar (başlangıç, bitiş); sondaki noktalama bağlantıya katılmaz. */
    fun links(text: String): List<IntRange> = LINK.findAll(text).map { m ->
        var end = m.range.last
        while (end > m.range.first && text[end] in ".,;:!?)]}'\"") end--
        m.range.first..end
    }.toList()
}
