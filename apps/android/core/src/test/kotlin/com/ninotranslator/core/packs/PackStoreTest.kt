// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

import com.ninotranslator.core.http.HttpResponse
import com.ninotranslator.core.translation.FakeClock
import com.ninotranslator.core.translation.FakeHttp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.GZIPOutputStream

class PackStoreTest {
    private val clock = FakeClock(10_000_000)
    private fun gz(s: String) = TestFiles.gz(s)
    /** Havuzun ürettiği biçim: `{"format":1,id,title,lang,entries}`. */
    private fun pack(id: String, line: String, tr: String) = gz("""{"format":1,"id":"$id","title":"$id","lang":"tr","entries":{"${PackKey.of(line)}":"$tr"}}""")

    private val server = HashMap<String, ByteArray>()
    private var listJson: String? = null
    private val http = FakeHttp { r ->
        val path = r.url.substringBefore('?')
        when {
            path.endsWith("/v1/packs") -> listJson?.let { FakeHttp.json(200, it) } ?: FakeHttp.json(500, "")
            else -> server[path.substringAfterLast('/')]?.let { body ->
                val sha = PackStore.sha256(body)
                if (r.headers["If-None-Match"] == "\"$sha\"") HttpResponse(304, mapOf("etag" to "\"$sha\""))
                else HttpResponse(200, mapOf("etag" to "\"$sha\"", "x-pack-sha256" to sha), body)
            } ?: FakeHttp.json(404, "")
        }
    }

    private fun list(vararg p: Pair<String, Long>) {
        listJson = "{\"ok\":true,\"packs\":[" + p.joinToString(",") { (id, v) -> """{"id":"$id","title":"T $id","version":$v,"sha256":"${PackStore.sha256(server[id]!!)}","size":1,"entries":1,"game":"$id","lang":"tr"}""" } + "]}"
    }

    private fun store(files: java.io.File) = PackStore(files, emptyList(), http, "https://havuz.example", clock.now, userAgent = "nino-pool/1 (android; test)")

    @Test fun downloadUpdateRemoveAndLoad() {
        val files = TestFiles.tempDir()
        val store = store(files)
        // Paket yokken kütüphane boş, hata yok.
        assertTrue(store.loadLibrary().packs.isEmpty()); assertTrue(store.lastFailures.isEmpty())
        assertTrue(store.isDue(PackStore.Reason.APP_START))
        server["pool-oyun"] = pack("pool-oyun", "Hello there.", "Merhaba."); server["pool-iki"] = pack("pool-iki", "Bye.", "Hoşça kal")
        list("pool-oyun" to 3L, "pool-iki" to 1L)
        val r = store.refresh()
        assertTrue(r.ok); assertEquals(listOf("pool-oyun", "pool-iki"), r.downloaded)
        // İstekler: dil gider, tanıtım başlığı gider.
        assertEquals("https://havuz.example/v1/packs?lang=tr", http.requests[0].url)
        assertEquals("https://havuz.example/v1/packs/pool-oyun?lang=tr", http.requests[1].url)
        assertEquals("nino-pool/1 (android; test)", http.requests[1].headers["User-Agent"])
        assertNull(http.requests[1].headers["If-None-Match"])
        assertTrue(File(files, "packs-remote/pool-oyun.json.gz").isFile)
        assertFalse(store.isDue(PackStore.Reason.DAILY)); assertFalse(store.isDue(PackStore.Reason.NEW_GAME))
        clock.advance(11 * 60_000); assertTrue(store.isDue(PackStore.Reason.NEW_GAME))
        val lib = store.loadLibrary()
        assertEquals("Merhaba.", lib.find("Hello there.")?.text)
        // Kapalı paket yüklenmez.
        assertNull(store.loadLibrary(setOf("pool-oyun")).find("Hello there."))
        // İçerik (sha) aynıysa sürüm değişse de indirilmez.
        val before = http.requests.size
        list("pool-oyun" to 5L, "pool-iki" to 1L)
        assertTrue(store.refresh().downloaded.isEmpty()); assertEquals(before + 1, http.requests.size)
        assertEquals(5L, store.readState().packs.first { it.id == "pool-oyun" }.version)
        // Liste yeni sha derken sunucu 304 derse elimizdeki doğrulanmış dosya kalır.
        val stale = listJson!!.replace(PackStore.sha256(server["pool-oyun"]!!), "1".repeat(64))
        listJson = stale
        val nm = store.refresh()
        assertTrue(nm.ok); assertTrue(nm.failed.isEmpty()); assertTrue(nm.downloaded.isEmpty())
        assertEquals("\"${PackStore.sha256(server["pool-oyun"]!!)}\"", http.requests.last().headers["If-None-Match"])
        assertEquals("Merhaba.", store.loadLibrary().find("Hello there.")?.text)
        // Bozuk indirme: eski sürüm kalır, sürüm −1, son bakış ilerlemez.
        val checked = store.readState().checked
        clock.advance(1000)
        server["pool-oyun"] = pack("pool-oyun", "Hello there.", "Bozuk")
        list("pool-oyun" to 6L, "pool-iki" to 1L)
        listJson = listJson!!.replace(PackStore.sha256(server["pool-oyun"]!!), "0".repeat(64))
        val bad = store.refresh()
        assertEquals(listOf("pool-oyun"), bad.failed)
        assertEquals(-1L, store.readState().packs.first { it.id == "pool-oyun" }.version)
        assertEquals(checked, store.readState().checked)
        assertEquals("Merhaba.", store.loadLibrary().find("Hello there.")?.text)
        // Yeni içerik iner.
        server["pool-oyun"] = pack("pool-oyun", "Hello there.", "Selam."); list("pool-oyun" to 7L)
        val upd = store.refresh()
        assertEquals(listOf("pool-oyun"), upd.downloaded)
        // Sunucudan kalkan paket silinir.
        assertEquals(listOf("pool-iki"), upd.removed)
        assertFalse(File(files, "packs-remote/pool-iki.json.gz").exists())
        assertEquals("Selam.", store.loadLibrary().find("Hello there.")?.text)
        // Bozuk liste hata sayılır, paketler silinmez.
        listJson = """{"packs":null}"""
        assertFalse(store.refresh().ok)
        assertTrue(File(files, "packs-remote/pool-oyun.json.gz").isFile)
        // Başka dilin paketi listeye girmez.
        listJson = """{"ok":true,"packs":[{"id":"pool-ar","title":"x","version":1,"sha256":"${"2".repeat(64)}","lang":"ar"}]}"""
        assertTrue(store.refresh().ok); assertTrue(store.serverPacks.isEmpty())
        // Listede olmayan dosya yüklenmez.
        File(files, "packs-remote/yabanci.json.gz").writeBytes(pack("yabanci", "Alien.", "Yabancı"))
        assertNull(store.loadLibrary().find("Alien."))
    }

    @Test fun tamperedFileIsNotLoaded() {
        val files = TestFiles.tempDir()
        val store = store(files)
        server["pool-oyun"] = pack("pool-oyun", "Hello there.", "Merhaba."); list("pool-oyun" to 1L)
        assertTrue(store.refresh().ok)
        File(files, "packs-remote/pool-oyun.json.gz").writeBytes(pack("pool-oyun", "Hello there.", "Kurcalanmış"))
        assertNull(store.loadLibrary().find("Hello there."))
        assertTrue(store.lastFailures.any { it.name == "pool-oyun.json.gz" })
        // Kurcalanan dosya bir sonraki bakışta yeniden iner (304 sorulmaz).
        assertEquals(listOf("pool-oyun"), store.refresh().downloaded)
        assertEquals("Merhaba.", store.loadLibrary().find("Hello there.")?.text)
    }

    @Test fun earlierDownloadsAreKept() {
        // Eski paket sunucusundan inmiş (pool- olmayan) paket havuz listesinde yok: silinmez, okunur.
        val files = TestFiles.tempDir()
        val old = pack("eski-oyun", "Old line here.", "Eski satır.")
        File(files, "packs-remote").mkdirs()
        File(files, "packs-remote/eski-oyun.json.gz").writeBytes(old)
        File(files, "packs-remote/packs.state").writeText("""{"checked":1,"packs":[{"id":"eski-oyun","title":"Eski","version":4,"sha256":"${PackStore.sha256(old)}"}]}""")
        val store = store(files)
        assertEquals("Eski satır.", store.loadLibrary().find("Old line here.")?.text)
        server["pool-x"] = pack("pool-x", "Hello there.", "Merhaba."); list("pool-x" to 1L)
        val r = store.refresh()
        assertTrue(r.ok); assertTrue(r.removed.isEmpty())
        val lib = store.loadLibrary()
        assertEquals("Eski satır.", lib.find("Old line here.")?.text)
        assertEquals("Merhaba.", lib.find("Hello there.")?.text)
    }

    @Test fun noServerMeansNoDownload() {
        val store = PackStore(TestFiles.tempDir(), emptyList(), http, null, clock.now)
        assertFalse(store.downloadEnabled); assertFalse(store.isDue(PackStore.Reason.APP_START))
        assertFalse(store.refresh().ok)
        assertTrue(store.loadLibrary().packs.isEmpty())
        assertTrue(http.requests.isEmpty())
    }

    @Test fun extraSourcesStillLoad() {
        val src = listOf(PackSource("harbor-lights.json.gz") { TestFiles.packBytes("harbor-lights").inputStream() })
        val store = PackStore(TestFiles.tempDir(), src, http, null, clock.now)
        assertNotNull(store.loadLibrary().pack("harbor-lights"))
    }

    @Test fun importFormats() {
        val json = """{"subtitles":{"Come here.":"Buraya gel.","Go!":"Git!","Again.":"","Same.":"Aynı."},"game":"Benim Oyunum"}"""
        val p = PackImporter.preview("ceviri.json", json.toByteArray())
        assertEquals("Benim Oyunum", p.suggestedTitle); assertEquals(3, p.entries.size); assertEquals(1, p.invalid)
        val txt = "# yorum\nCome here.\tBuraya gel.\nGo! = Git!\nGo! = Git!\nRun = Koş\nRun = Kaç\nbozuk satır\n\n"
        val t = PackImporter.preview("a.TXT", txt.toByteArray())
        assertEquals(2, t.entries.size); assertEquals(1, t.duplicates); assertEquals(2, t.conflicts); assertEquals(1, t.invalid)
        val srt = "1\n00:00:01,000 --> 00:00:02,000\nCome here.\nBuraya gel.\n\n2\n00:00:03,000 --> 00:00:02,000\nBad.\nKötü.\n\n3\nyanlış\n"
        val s = PackImporter.preview("a.srt", srt.toByteArray())
        assertEquals(1, s.entries.size); assertEquals(2, s.invalid)
        val keyed = """{"format":1,"title":"Hazır","entries":{"${PackKey.of("Come here.")}":"Gel."}}"""
        assertEquals(1, PackImporter.preview("k.json", keyed.toByteArray()).entries.size)
        assertTrue(runCatching { PackImporter.preview("k.json", """{"format":2,"entries":{}}""".toByteArray()) }.exceptionOrNull() is PackImporter.Failure.Unsupported)
        assertTrue(runCatching { PackImporter.preview("k.ass", ByteArray(0)) }.exceptionOrNull() is PackImporter.Failure.Unsupported)
        assertTrue(runCatching { PackImporter.preview("k.txt", byteArrayOf(0xC3.toByte(), 0x28)) }.exceptionOrNull() is PackImporter.Failure.BadEncoding)
        assertTrue(runCatching { PackImporter.preview("k.json", ("[".repeat(600) + "]".repeat(600)).toByteArray()) }.isFailure)
        // BOM atlanır.
        assertEquals(1, PackImporter.preview("b.txt", byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "Hi\tSelam".toByteArray()).entries.size)
    }

    @Test fun importSaveAndLoad() {
        assertEquals("community-god-of-war-2", PackImporter.idFor("God of War: 2 ✨"))
        assertEquals("community-game", PackImporter.idFor("✨✨"))
        assertEquals("community-" + "a".repeat(80), PackImporter.idFor("A".repeat(100)))
        val files = TestFiles.tempDir()
        val p = PackImporter.preview("x.txt", "Come here.\tBuraya gel.".toByteArray())
        val store = PackStore(files, emptyList(), http, null, clock.now)
        val id = PackImporter.save(store.importedDir, "Oyunum", p)
        assertEquals("community-oyunum", id)
        assertTrue(runCatching { PackImporter.save(store.importedDir, "Oyunum", p) }.exceptionOrNull() is PackImporter.Failure.Exists)
        PackImporter.save(store.importedDir, "Oyunum", p, replace = true)
        assertTrue(runCatching { PackImporter.save(store.importedDir, " ", p) }.exceptionOrNull() is PackImporter.Failure.NameRequired)
        val lib = store.loadLibrary()
        assertEquals("Buraya gel.", lib.find("COME HERE")?.text)
        assertEquals("Oyunum", lib.pack(id)!!.title)
    }
}
