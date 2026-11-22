// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.mobile.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Her `values-*` çevirisi Türkçe kaynağın çevrilebilir anahtarlarının hepsini taşır, yer tutucuları aynıdır,
 * kesme işaretleri kaçışlıdır. Klasörler kendiliğinden bulunur; yeni dil eklenince test de onu denetler.
 */
class StringResourcesTest {
    private val res = File("src/main/res")
    private val placeholder = Regex("%(\\d+\\$)?[sd]")

    private class Entry(val raw: String, val translatable: Boolean)

    private fun read(dir: String): Map<String, Entry> {
        val file = File(res, "$dir/strings.xml")
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        val out = LinkedHashMap<String, Entry>()
        for (i in 0 until nodes.length) {
            val el = nodes.item(i) as org.w3c.dom.Element
            out[el.getAttribute("name")] = Entry(el.textContent, el.getAttribute("translatable") != "false")
        }
        return out
    }

    private fun placeholders(text: String) = placeholder.findAll(text).map { it.value }.sorted().toList()

    private val translations: List<String>
        get() = res.listFiles().orEmpty()
            .filter { it.isDirectory && it.name.startsWith("values-") && File(it, "strings.xml").exists() }
            .map { it.name }.sorted()

    @Test fun expectedLanguagesExist() {
        val dirs = translations
        for (d in listOf("values-en", "values-in", "values-vi", "values-ms", "values-b+fil", "values-tl", "values-nl")) {
            assertTrue("$d yok", d in dirs)
        }
    }

    @Test fun everyTranslationHasSameKeysAndPlaceholders() {
        val source = read("values").filterValues { it.translatable }
        for (dir in translations) {
            val target = read(dir)
            assertEquals("$dir: eksik anahtar", emptySet<String>(), source.keys - target.keys)
            assertEquals("$dir: fazla anahtar", emptySet<String>(), target.keys - source.keys)
            for ((k, e) in source) {
                assertEquals("$dir: $k yer tutucuları", placeholders(e.raw), placeholders(target.getValue(k).raw))
            }
        }
    }

    @Test fun quotesAreEscapedAndHeaderPresent() {
        val text = Regex("<string name=\"([^\"]+)\"[^>]*>(.*?)</string>", RegexOption.DOT_MATCHES_ALL)
        for (dir in translations + "values") {
            val xml = File(res, "$dir/strings.xml").readText()
            assertTrue("$dir: lisans satırı yok", xml.contains("<!-- SPDX-License-Identifier: AGPL-3.0-only -->"))
            assertTrue("$dir: telif satırı yok", xml.contains("<!-- Copyright (C) 2026 Nino contributors -->"))
            for (m in text.findAll(xml)) {
                val body = m.groupValues[2]
                assertTrue("$dir: ${m.groupValues[1]} kaçışsız kesme işareti", !Regex("(?<!\\\\)['\"]").containsMatchIn(body))
            }
        }
    }

    @Test fun filipinoFoldersMatch() {
        assertEquals(File(res, "values-b+fil/strings.xml").readText(), File(res, "values-tl/strings.xml").readText())
    }
}
