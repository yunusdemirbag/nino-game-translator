// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Uygulamayla gelen genel en→tr sözlüğü. Veri aşağıdaki JSON'dadır (paket
/// tanımına kaynak eklememek için Swift dosyasına gömülü).
public enum BuiltinGlossary {
    public static let enTr: Glossary = Glossary.parse(Data(json.utf8)) ?? Glossary()

    static let json = #"""
    {
      // Genel oyun terimleri.
      "terms": {
        "perk deck": "avantaj destesi",
        "safe house": "güvenli ev",
        "bounty board": "ödül panosu",
        "crafting bench": "üretim tezgâhı",
        "lock pick": "maymuncuk",
        "repair kit": "tamir seti",
        "stamina bar": "dayanıklılık çubuğu",
        "waypoint": "yol işareti",
        "loadout": "teçhizat seti",
        "pause menu": "duraklatma menüsü"
      },
      "keep": ["NPC", "DLC"],
      "keepExact": ["Ghost"],
      // Telsiz/oyuncu argosu → düz İngilizce.
      "phrases": {
        "(?:pop|light|crack) (?:a )?flares?(?! gun)": "fire a flare",
        "ten-four": "understood",
        "pull aggro": "draw their attention",
        "on the double": "quickly",
        "dead ahead": "straight ahead",
        "stand down": "stop fighting",
        "sitrep": "status report",
        "exfil": "extraction",
        "ready up": "get ready"
      },
      // Sık ünlemler: çevirmene gitmez.
      "lines": {
        "taking fire": "Ateş altındayım",
        "out of arrows": "Okum kalmadı",
        "follow me": "Beni takip et",
        "stay down": "Başını eğ",
        "behind you": "Arkanda",
        "watch out": "Gözünü dört aç",
        "hurry up": "Acele et",
        "let's go": "Gidelim",
        "over here": "Buraya",
        "almost there": "Az kaldı",
        "stay here": "Burada bekle",
        "target spotted": "Hedef görüldü",
        "they're flanking": "Bizi yandan sarıyorlar",
        "stay together": "Birbirimizden ayrılmayalım",
        "medic": "Sıhhiye"
      }
    }
    """#
}
