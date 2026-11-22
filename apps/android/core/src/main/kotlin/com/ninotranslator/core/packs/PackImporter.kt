// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.json.Json
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Topluluk çeviri dosyasını (JSON/TXT/SRT) community paketine çevirir (ceviri.md 11). Dosya hiçbir yere gitmez. */
object PackImporter {
    const val MAX_BYTES = 64L * 1024 * 1024
    const val MAX_DEPTH = 512

    enum class Kind { JSON, TXT, SRT }

    sealed class Failure(message: String) : Exception(message) {
        class Unsupported : Failure("desteklenmeyen dosya")
        class TooLarge : Failure("dosya çok büyük")
        class BadEncoding : Failure("UTF-8 değil")
        class Invalid(reason: String) : Failure(reason)
        class NoLines : Failure("kullanılabilir satır yok")
        class NameRequired : Failure("ad gerekli")
        class Exists(val id: String) : Failure("aynı kimlikte paket var")
    }

    data class Preview(
        val suggestedTitle: String?,
        /** 16 hex anahtar → Türkçe. */
        val entries: Map<String, String>,
        val invalid: Int,
        val duplicates: Int,
        val conflicts: Int,
    )

    fun kindOf(fileName: String): Kind? = when (fileName.substringAfterLast('.', "").lowercase()) {
        "json" -> Kind.JSON; "txt" -> Kind.TXT; "srt" -> Kind.SRT; else -> null
    }

    fun preview(fileName: String, bytes: ByteArray): Preview {
        val kind = kindOf(fileName) ?: throw Failure.Unsupported()
        if (bytes.size > MAX_BYTES) throw Failure.TooLarge()
        val text = decodeStrict(bytes)
        return when (kind) {
            Kind.JSON -> fromJson(text)
            Kind.TXT -> fromPairs(null, txtPairs(text))
            Kind.SRT -> fromPairs(null, srtPairs(text))
        }
    }

    private fun decodeStrict(bytes: ByteArray): String {
        var start = 0
        if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() && bytes[2] == 0xBF.toByte()) start = 3
        val dec = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        return try { dec.decode(ByteBuffer.wrap(bytes, start, bytes.size - start)).toString() } catch (e: CharacterCodingException) { throw Failure.BadEncoding() }
    }

    private class Acc {
        val out = LinkedHashMap<String, String>()
        val conflicted = HashSet<String>()
        var invalid = 0; var duplicates = 0; var conflicts = 0
        fun add(key: String?, tr: String?) {
            val t = tr?.trim()
            if (key == null || t.isNullOrEmpty()) { invalid++; return }
            if (key in conflicted) { conflicts++; return }
            val prev = out[key]
            when {
                prev == null -> out[key] = t
                prev == t -> duplicates++
                else -> { out.remove(key); conflicted += key; conflicts += 2 }
            }
        }
    }

    private fun fromPairs(title: String?, pairs: Sequence<Pair<String, String>?>): Preview {
        val a = Acc()
        for (p in pairs) if (p == null) a.invalid++ else a.add(PackKey.of(p.first), p.second)
        return Preview(title, a.out, a.invalid, a.duplicates, a.conflicts)
    }

    private fun fromJson(text: String): Preview {
        checkDepth(text)
        val root = try { Json.parse(text) } catch (e: Exception) { throw Failure.Invalid("bozuk JSON") } as? Map<*, *> ?: throw Failure.Invalid("kök nesne değil")
        val title = (root["title"] as? String ?: root["game"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        if (root.containsKey("format") || root.containsKey("entries")) {
            if ((root["format"] as? Number)?.toInt() != 1 || root["entries"] !is Map<*, *>) throw Failure.Unsupported()
            val a = Acc()
            for ((k, v) in root["entries"] as Map<*, *>) {
                val key = (k as? String)?.let(PackKey::parse)?.let(PackKey::hex)
                a.add(key, v as? String)
            }
            return Preview(title, a.out, a.invalid, a.duplicates, a.conflicts)
        }
        val subs = root["subtitles"]
        val source: Map<*, *> = if (subs is Map<*, *>) subs else root.filterKeys { it != "game" && it != "title" }
        return fromPairs(title, source.asSequence().map { (k, v) -> if (k is String && v is String) k to v else null })
    }

    private fun checkDepth(text: String) {
        var depth = 0; var inStr = false; var esc = false
        for (c in text) {
            if (inStr) { if (esc) esc = false else if (c == '\\') esc = true else if (c == '"') inStr = false; continue }
            when (c) {
                '"' -> inStr = true
                '{', '[' -> if (++depth > MAX_DEPTH) throw Failure.Invalid("çok derin")
                '}', ']' -> depth--
            }
        }
    }

    private fun txtPairs(text: String): Sequence<Pair<String, String>?> = sequence {
        for (raw in text.lineSequence()) {
            val l = raw.trimEnd('\r')
            if (l.isBlank() || l.trimStart().startsWith("#")) continue
            val tab = l.indexOf('\t')
            val eq = l.indexOf(" = ")
            val p = when {
                tab >= 0 -> l.substring(0, tab) to l.substring(tab + 1)
                eq >= 0 -> l.substring(0, eq) to l.substring(eq + 3)
                else -> null
            }
            yield(p?.let { it.first.trim() to it.second.trim() })
        }
    }

    private val TIME = Regex("^(\\d{2}):(\\d{2}):(\\d{2}),(\\d{3}) --> (\\d{2}):(\\d{2}):(\\d{2}),(\\d{3})$")

    private fun srtPairs(text: String): Sequence<Pair<String, String>?> {
        val blocks = text.replace("\r\n", "\n").replace('\r', '\n').split(Regex("\n[ \t]*\n")).map { it.trim('\n') }.filter { it.isNotBlank() }
        return blocks.asSequence().map { b ->
            val l = b.split('\n')
            if (l.size != 4 || l[0].trim().toLongOrNull() == null) return@map null
            val m = TIME.matchEntire(l[1].trim()) ?: return@map null
            val g = m.groupValues.drop(1).map { it.toLong() }
            val start = ((g[0] * 60 + g[1]) * 60 + g[2]) * 1000 + g[3]
            val end = ((g[4] * 60 + g[5]) * 60 + g[6]) * 1000 + g[7]
            if (start >= end) null else l[2].trim() to l[3].trim()
        }
    }

    /** `community-<ad>`: ASCII harfler küçültülür, rakamlar kalır, öbürü tek tire; en çok 80 karakter. */
    fun idFor(title: String): String {
        val b = StringBuilder()
        for (c in title) {
            if (c in 'a'..'z' || c in '0'..'9') b.append(c)
            else if (c in 'A'..'Z') b.append(c.lowercaseChar())
            else if (b.isNotEmpty() && b.last() != '-') b.append('-')
        }
        val slug = b.toString().trim('-').take(80).trimEnd('-')
        return "community-" + slug.ifEmpty { "game" }
    }

    /** Kaydeder: `packs-imported/<kimlik>.json` (biçim 1). Kimliği döner. */
    fun save(importedDir: File, title: String, preview: Preview, replace: Boolean = false): String {
        val name = title.trim()
        if (name.isEmpty()) throw Failure.NameRequired()
        if (preview.entries.isEmpty()) throw Failure.NoLines()
        val id = idFor(name)
        val file = File(importedDir, "$id.json")
        if (file.exists() && !replace) throw Failure.Exists(id)
        importedDir.mkdirs()
        val json = Json.write(linkedMapOf("format" to 1, "id" to id, "title" to name, "entries" to preview.entries))
        val tmp = File(importedDir, ".${java.util.UUID.randomUUID()}.tmp")
        tmp.writeText(json)
        PackStore.moveReplacing(tmp, file)
        return id
    }
}
