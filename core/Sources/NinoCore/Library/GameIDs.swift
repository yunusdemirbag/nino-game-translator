// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Oyunun asıl kimliği. Aynı oyun farklı kimliklerle gelebiliyor: tam addan üretilen (`grand-theft-auto-vi`), paket
/// kimliği (`gta-6`), havuz paketi (`pool-gta-6`), ekrandan okunan yazılış (`gta6`). Sunucuya (havuz, ölçüm, tanıma,
/// rapor) her zaman asıl kimlik gider; karşılaştırmalar da asıl kimlikle yapılır. Paket dosya kimlikleri değişmez.
///
/// Tablo sunucuyla birebir aynıdır: `nino-pool/src/games.js` (`GAME_ALIASES`, `GAME_NAMES`), NinoTranslator deposu
/// commit f04fb555. Sunucuda değişirse burası da değişir.
public enum GameIDs {
    /// takma ad → asıl kimlik (sunucudaki `GAME_ALIASES`).
    public static let aliases: [String: String] = [
        // GTA 6
        "grand-theft-auto-vi": "gta-6",
        "gta-vi": "gta-6",
        "gta6": "gta-6",
        "gtavi": "gta-6",
        "pool-gta-6": "gta-6",
        // GTA 5 (gömülü paket: gta-v)
        "grand-theft-auto-v": "gta-v",
        "gta-5": "gta-v",
        "gta5": "gta-v",
        "gtav": "gta-v",
        "pool-gta-5": "gta-v",
        "pool-gta-v": "gta-v",
        // Kesme işaretinin tire olduğu yazılışlar ve aynı oyunun uzun adları
        "assassin-s-creed-shadows": "assassins-creed-shadows",
        "marvel-s-spider-man-2": "marvels-spider-man-2",
        "death-stranding-director-s-cut": "death-stranding-directors-cut",
        "death-stranding-2-on-the-beach": "death-stranding-2",
        "farcry6": "far-cry-6",
        "ghost-of-y-tei": "ghost-of-yotei",
    ]

    /// Okunur adlar (sunucudaki `GAME_NAMES`).
    public static let names: [String: String] = [
        "gta-6": "GTA 6",
        "gta-v": "GTA 5",
        "grand-theft-auto-iv": "GTA 4",
        "gta-iv": "GTA 4",
        "grand-theft-auto-online": "GTA Online",
        "red-dead-redemption-2": "Red Dead Redemption 2",
        "call-of-duty-modern-warfare-2019": "Call of Duty: Modern Warfare (2019)",
        "assassins-creed-shadows": "Assassin's Creed Shadows",
        "assassin-s-creed-mirage": "Assassin's Creed Mirage",
        "mafia-the-old-country": "Mafia: The Old Country",
        "death-stranding-2": "Death Stranding 2",
        "death-stranding-directors-cut": "Death Stranding Director's Cut",
        "elden-ring": "Elden Ring",
        "elden-ring-shadow-of-the-erdtree": "Elden Ring: Shadow of the Erdtree",
        "marvels-spider-man-2": "Marvel's Spider-Man 2",
        "kingdom-come-deliverance-ii": "Kingdom Come: Deliverance II",
        "the-last-of-us-part-ii": "The Last of Us Part II",
        "the-last-of-us-part-ii-remastered": "The Last of Us Part II Remastered",
        "wuchang-fallen-feathers": "Wuchang: Fallen Feathers",
        "far-cry-6": "Far Cry 6",
        "ghost-of-yotei": "Ghost of Yōtei",
        "astro-s-playroom": "Astro's Playroom",
        "final-fantasy.vii-remake": "Final Fantasy VII Remake",
        "ea-sports-fc-26": "EA Sports FC 26",
        "ea-sports-fc-27": "EA Sports FC 27",
        "nba-2k26": "NBA 2K26",
        "007-first-light": "007 First Light",
    ]

    /// Asıl kimlik; ad da kimlik de verilebilir: `Grand Theft Auto VI`, `gta6`, `pool-gta-6` → `gta-6`.
    /// Kimlik üretilemezse `nil`.
    public static func id(_ nameOrID: String) -> String? {
        guard let slug = GameName.id(nameOrID) else { return nil }
        return aliases[slug] ?? slug
    }

    /// Asıl kimlik; üretilemezse boş metin.
    public static func canonical(_ nameOrID: String) -> String { id(nameOrID) ?? "" }

    /// İki ad/kimlik aynı oyun mu (asıl kimlik ya da ad anahtarı aynıysa).
    public static func sameGame(_ a: String, _ b: String) -> Bool {
        if let ia = id(a), ia == id(b) { return true }
        let ka = GameName.key(a)
        return !ka.isEmpty && ka == GameName.key(b)
    }

    /// Tablodaki okunur ad (`gta-6`, `pool-gta-6`, `Grand Theft Auto VI` → `GTA 6`); tabloda yoksa `nil`.
    public static func knownName(_ nameOrID: String) -> String? {
        id(nameOrID).flatMap { names[$0] }
    }

    /// Görünen ad: tablodaki ad, yoksa verilen ad olduğu gibi (ad uydurulmaz).
    public static func displayName(_ nameOrID: String) -> String { knownName(nameOrID) ?? nameOrID }
}
