// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
package com.ninotranslator.core.packs

/**
 * Oyunların asıl kimliği (havuz sunucusundaki tabloyla aynı). Aynı oyun farklı kimliklerle gelebilir: tam addan
 * üretilen ("grand-theft-auto-vi"), paket kimliği ("gta-6", "pool-gta-6"), ekrandan okunan ("gta6"). Sunucuya her
 * zaman asıl kimlik gider; paket listelerinde aynı asıl kimliğe düşen paketler tek oyundur.
 */
object GameIds {
    /** Takma ad → asıl kimlik. Asıl kimlik gömülü paketin kimliği (gta-6, gta-v…). */
    val ALIASES: Map<String, String> = linkedMapOf(
        // GTA 6
        "grand-theft-auto-vi" to "gta-6",
        "gta-vi" to "gta-6",
        "gta6" to "gta-6",
        "gtavi" to "gta-6",
        "pool-gta-6" to "gta-6",
        // GTA 5 (gömülü paket: gta-v)
        "grand-theft-auto-v" to "gta-v",
        "gta-5" to "gta-v",
        "gta5" to "gta-v",
        "gtav" to "gta-v",
        "pool-gta-5" to "gta-v",
        "pool-gta-v" to "gta-v",
        // Kesme işaretinin tire olduğu yazılışlar ve aynı oyunun uzun adları
        "assassin-s-creed-shadows" to "assassins-creed-shadows",
        "marvel-s-spider-man-2" to "marvels-spider-man-2",
        "death-stranding-director-s-cut" to "death-stranding-directors-cut",
        "death-stranding-2-on-the-beach" to "death-stranding-2",
        "farcry6" to "far-cry-6",
        "ghost-of-y-tei" to "ghost-of-yotei",
    )

    /** Okunur adlar. Listede olmayan kimlik tirelerden ayrılıp büyük harfle yazılır. */
    val NAMES: Map<String, String> = linkedMapOf(
        "gta-6" to "GTA 6",
        "gta-v" to "GTA 5",
        "grand-theft-auto-iv" to "GTA 4",
        "gta-iv" to "GTA 4",
        "grand-theft-auto-online" to "GTA Online",
        "red-dead-redemption-2" to "Red Dead Redemption 2",
        "call-of-duty-modern-warfare-2019" to "Call of Duty: Modern Warfare (2019)",
        "assassins-creed-shadows" to "Assassin's Creed Shadows",
        "assassin-s-creed-mirage" to "Assassin's Creed Mirage",
        "mafia-the-old-country" to "Mafia: The Old Country",
        "death-stranding-2" to "Death Stranding 2",
        "death-stranding-directors-cut" to "Death Stranding Director's Cut",
        "elden-ring" to "Elden Ring",
        "elden-ring-shadow-of-the-erdtree" to "Elden Ring: Shadow of the Erdtree",
        "marvels-spider-man-2" to "Marvel's Spider-Man 2",
        "kingdom-come-deliverance-ii" to "Kingdom Come: Deliverance II",
        "the-last-of-us-part-ii" to "The Last of Us Part II",
        "the-last-of-us-part-ii-remastered" to "The Last of Us Part II Remastered",
        "wuchang-fallen-feathers" to "Wuchang: Fallen Feathers",
        "far-cry-6" to "Far Cry 6",
        "ghost-of-yotei" to "Ghost of Yōtei",
        "astro-s-playroom" to "Astro's Playroom",
        "final-fantasy.vii-remake" to "Final Fantasy VII Remake",
        "ea-sports-fc-26" to "EA Sports FC 26",
        "ea-sports-fc-27" to "EA Sports FC 27",
        "nba-2k26" to "NBA 2K26",
        "007-first-light" to "007 First Light",
    )

    const val POOL_PREFIX = "pool-"
    private val ROMAN = Regex("^(i|ii|iii|iv|v|vi|vii|viii|ix|x)$")
    private val DASHES = Regex("-{2,}")

    /** Kimliği asıl ada çevirir (küçük harf, art arda tireler teke). Takma ad değilse olduğu gibi döner. */
    fun canonical(id: String): String {
        if (id.isEmpty()) return id
        val clean = id.lowercase().replace(DASHES, "-")
        return ALIASES[clean] ?: clean
    }

    /** Kimliğin en çok uzunluğu (NinoCore `GameName.maxIDLength`). */
    const val MAX_ID_LENGTH = 64
    private val ID_TRIM = charArrayOf('-', '.', '_')

    /**
     * Addan havuz kimliği, NinoCore `GameName.id` ile birebir: küçük harf; ASCII harf, rakam, `.`, `_`, `-` kalır, öbür
     * her karakter (boşluk, noktalama, aksanlı harf) `-` olur; art arda tireler teke iner; baştan/sondan `-._` atılır;
     * en çok [MAX_ID_LENGTH] karakter (kesince yine atılır). Aksan atılmaz, Roma rakamı çevrilmez, `pool-` öneki
     * atılmaz. Boş kalırsa null: "Mafia: The Old Country" → "mafia-the-old-country", "!!!" → null.
     */
    fun slug(name: String?): String? {
        val out = StringBuilder()
        for (ch in (name ?: return null).lowercase()) {
            val c = if (ch in 'a'..'z' || ch in '0'..'9' || ch == '.' || ch == '_' || ch == '-') ch else '-'
            if (c == '-' && out.isNotEmpty() && out.last() == '-') continue
            out.append(c)
        }
        return out.toString().trim(*ID_TRIM).take(MAX_ID_LENGTH).trim(*ID_TRIM).ifEmpty { null }
    }

    /**
     * Asıl kimlik, NinoCore `GameIDs.id` ile birebir: [slug] takma adsa tablodaki asıl kimlik, değilse slug'ın kendisi
     * ("Grand Theft Auto VI", "gta6", "pool-gta-6" → "gta-6"; "Yeni Oyun" → "yeni-oyun"). Kimlik üretilemezse null.
     * Sunucuya giden her `game` alanı (havuz, kuyruk, ölçüm, teşhis) budur.
     */
    fun id(nameOrId: String?): String? = slug(nameOrId)?.let { ALIASES[it] ?: it }

    /**
     * Yerel eşleştirme anahtarı (paket listesi, oyun karşılaştırma): [id] ve paket kimliğinin `pool-` öneki atılmış
     * hali ("pool-elden-ring" → "elden-ring"). Sunucuya gitmez; sunucuya [id] gider.
     */
    fun fromAny(nameOrId: String?): String? = id(nameOrId)?.let(::ofPack)

    /** Paketin oyunu: `pool-` öneki atılmış kimliğin asıl adı ("pool-gta-6", "pool-grand-theft-auto-vi" → "gta-6"). */
    fun ofPack(packId: String): String {
        val c = canonical(packId)
        return if (c.startsWith(POOL_PREFIX)) canonical(c.removePrefix(POOL_PREFIX)) else c
    }

    /** Kayıtlı değer takma adsa asıl kimlik; değilse aynen (eski `lastGame`, altyazı yeri anahtarları). */
    fun upgradeStored(value: String?): String? {
        val v = value?.trim() ?: return value
        val clean = v.lowercase().replace(DASHES, "-")
        return ALIASES[clean] ?: value
    }

    /** Bir asıl kimliğin bütün takma adları. */
    fun aliasesOf(target: String): List<String> = ALIASES.filterValues { it == target }.keys.toList()

    /** Okunur ad: "gta-6" → "GTA 6", "some-new-game-ii" → "Some New Game II"; boşsa "". */
    fun name(id: String?): String {
        val game = canonical(id ?: return "")
        if (game.isEmpty()) return ""
        NAMES[game]?.let { return it }
        return game.split(Regex("[-_.]+")).filter { it.isNotEmpty() }
            .joinToString(" ") { w -> if (ROMAN.matches(w)) w.uppercase() else w.replaceFirstChar { it.uppercaseChar() } }
    }

    /** Aynı oyun mu (ad ya da kimlik). */
    fun same(a: String?, b: String?): Boolean {
        val x = fromAny(a) ?: return false
        return x == fromAny(b)
    }

    data class Count(val game: String, val n: Long, val name: String)

    /** (kimlik, sayı) satırlarını asıl kimlikte toplar; büyükten küçüğe. */
    fun mergeCounts(rows: List<Pair<String, Long>>): List<Count> {
        val out = LinkedHashMap<String, Long>()
        for ((g, n) in rows) { val c = canonical(g); out[c] = (out[c] ?: 0) + n }
        return out.entries.map { Count(it.key, it.value, name(it.key)) }.sortedByDescending { it.n }
    }

    /** Paketin oyun anahtarları: kimlikten ve başlıktan. */
    fun packKeys(packId: String, title: String?): Set<String> =
        setOfNotNull(ofPack(packId), title?.let(::fromAny), title?.let(PackKey::canonical)?.takeIf { it.isNotEmpty() }?.let { "t:$it" })

    /**
     * Aynı oyuna (kimlik ya da başlık) düşen paketleri gruplar: gruplar ilk görülme sırasında, grubun içinde havuz
     * paketi (`pool-`) başta. Listede grubun ilk öğesi gösterilir; aç/kapa bütün gruba uygulanır.
     */
    fun <T> groupPacks(items: List<T>, id: (T) -> String, title: (T) -> String?): List<List<T>> {
        val groups = ArrayList<Pair<MutableSet<String>, MutableList<T>>>()
        for (item in items) {
            val keys = packKeys(id(item), title(item))
            val g = groups.firstOrNull { (k, _) -> k.any { it in keys } }
            if (g == null) groups += keys.toMutableSet() to mutableListOf(item)
            else { g.first += keys; g.second += item }
        }
        return groups.map { (_, list) -> list.sortedBy { if (id(it).startsWith(POOL_PREFIX)) 0 else 1 } }
    }
}
