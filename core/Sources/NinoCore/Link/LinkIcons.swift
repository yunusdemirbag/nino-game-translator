// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Metindeki `⟦T1⟧` yer tutucusunun yerine çizilecek kumanda tuşu simgesi (protokol.md "Tuş simgeleri").
///
/// `name` bilinen bir PS5 tuşudur (TV temiz vektör çizer); bilinmeyen simge `png` (base64, oyundan kesilmiş)
/// olarak gider. İkisi de varsa TV `name`'i kullanır.
public struct LinkIcon: Equatable, Hashable, Sendable {
    public var id: String
    public var name: String?
    public var png: String?

    public init(id: String, name: String? = nil, png: String? = nil) {
        self.id = id
        self.name = name
        self.png = png
    }

    /// Bir mesajdaki en çok simge.
    public static let maxCount = 8
    public static let maxNameLength = 24
    public static let maxPNGLength = 200_000

    /// TV'nin vektörle çizdiği adlar (büyük/küçük harf farksız).
    public static let knownNames: [String] = [
        "cross", "circle", "square", "triangle", "dpad-up", "dpad-down", "dpad-left", "dpad-right", "dpad",
        "L1", "L2", "L3", "R1", "R2", "R3", "options", "create", "touchpad",
    ]

    /// `T1` … `T99`.
    public static func isValidID(_ id: String) -> Bool {
        id.range(of: #"^T\d{1,2}$"#, options: .regularExpression) != nil
    }

    /// Kurala uyan simge mi (kimlik, ad ya da görüntü, boylar)?
    public var isValid: Bool {
        guard Self.isValidID(id) else { return false }
        if let name, !name.isEmpty, name.count <= Self.maxNameLength { return true }
        if let png, !png.isEmpty, png.count <= Self.maxPNGLength { return true }
        return false
    }

    public var jsonObject: [String: Any] {
        var o: [String: Any] = ["id": id]
        if let name, !name.isEmpty, name.count <= Self.maxNameLength { o["name"] = name }
        if let png, !png.isEmpty, png.count <= Self.maxPNGLength { o["png"] = png }
        return o
    }

    public init?(json: Any?) {
        guard let o = json as? [String: Any], let id = o["id"] as? String else { return nil }
        self.init(id: id, name: (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                  png: (o["png"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        guard isValid else { return nil }
    }

    /// JSON'a yazılacak liste: geçersizler atılır, en çok 8; boşsa `nil` (alan hiç yazılmaz, eski JSON aynı kalır).
    public static func encode(_ icons: [LinkIcon]?) -> [[String: Any]]? {
        let ok = (icons ?? []).filter(\.isValid).prefix(maxCount)
        return ok.isEmpty ? nil : ok.map(\.jsonObject)
    }

    public static func decode(_ json: Any?) -> [LinkIcon]? {
        guard let raw = json as? [Any] else { return nil }
        let list = Array(raw.compactMap(LinkIcon.init(json:)).prefix(maxCount))
        return list.isEmpty ? nil : list
    }

    /// Eski göstericiler için okunur karşılık (`[→]`, `[✕]`, `[L2]`); görüntülü simgede `[■]`.
    public var readable: String {
        let symbol: String
        switch name?.lowercased() {
        case "cross": symbol = "✕"
        case "circle": symbol = "○"
        case "square": symbol = "□"
        case "triangle": symbol = "△"
        case "dpad-up": symbol = "↑"
        case "dpad-down": symbol = "↓"
        case "dpad-left": symbol = "←"
        case "dpad-right": symbol = "→"
        case "dpad": symbol = "✜"
        case "options": symbol = "OPTIONS"
        case "create": symbol = "CREATE"
        case "touchpad": symbol = "TOUCHPAD"
        case let n?: symbol = n.uppercased()
        case nil: symbol = "■"
        }
        return "[\(symbol)]"
    }
}

/// `⟦T1⟧` yer tutucuları: çeviride korunur, kaybolursa yerine konur, eski göstericide okunur metne döner.
public enum IconPlaceholders {
    public static let pattern = #"⟦T\d{1,2}⟧"#

    public static func tag(_ id: String) -> String { "⟦\(id)⟧" }
    public static func tag(_ n: Int) -> String { "⟦T\(n)⟧" }

    /// Metindeki yer tutucu kimlikleri (sırayla).
    public static func ids(in text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let r = rest.range(of: pattern, options: .regularExpression) {
            out.append(String(rest[r].dropFirst().dropLast()))
            rest = rest[r.upperBound...]
        }
        return out
    }

    public static func contains(_ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    /// Yer tutucuları okunur metne çevirir (`[→]`); simgesi olmayan yer tutucu atılır. Eski 8787 yolu ve Mac'in
    /// kendi pencereleri (geçmiş, günlük) için.
    public static func readable(_ text: String, icons: [LinkIcon]?) -> String {
        guard contains(text) else { return text }
        var out = text
        for id in ids(in: text) {
            let r = icons?.first { $0.id == id }?.readable ?? ""
            out = out.replacingOccurrences(of: tag(id), with: r)
        }
        // Atılan yer tutucunun bıraktığı çift boşluk.
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Çeviride kaybolan yer tutucu

    /// Türkçede tuşu anlatan genel sözcükler: yer tutucu bunların yerine geçer (`tuşu basılı tut` → `⟦T1⟧ basılı tut`).
    static let turkishButtonWords: Set<String> = [
        "tuş", "tuşu", "tuşunu", "tuşuna", "tuşa", "tuşla", "tuşuyla", "düğme", "düğmeyi", "düğmesini", "düğmeye",
        "düğmesine", "düğmeyle",
    ]
    /// Türkçe fiil kökleri: yer tutucu ilk fiilin önüne konur.
    static let turkishVerbStems: [String] = ["bas", "tıkla", "dokun", "çek", "kaydır", "çevir", "kullan"]
    /// Başka dillerde tuşu anlatan genel sözcükler.
    static let otherButtonWords: Set<String> = [
        "button", "key", "taste", "touche", "bouton", "botón", "boton", "tecla", "tasto", "pulsante", "botão", "knop",
        "przycisk", "кнопку", "кнопка", "клавишу", "زر", "الزر",
    ]

    /// Çeviride kaybolan yer tutucuları yerine koyar. Türkçede: tuşu anlatan genel sözcüğün (`tuşu`) yerine, yoksa ilk
    /// fiilin (`basılı tut`, `bas`) önüne, o da yoksa satır sonuna. Başka dillerde: genel sözcüğün yerine, yoksa satır
    /// başına. `ids` kaynaktaki sıradır.
    public static func ensure(_ translation: String, ids: [String], language: String) -> String {
        let missing = ids.filter { !translation.contains(tag($0)) }
        guard !missing.isEmpty else { return translation }
        var words = translation.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let tr = language.lowercased().hasPrefix("tr")
        let locale = Locale(identifier: tr ? "tr_TR" : "en_US")
        func core(_ w: String) -> String { w.lowercased(with: locale).trimmingCharacters(in: .punctuationCharacters) }
        for id in missing {
            let t = tag(id)
            let generic = tr ? turkishButtonWords : otherButtonWords
            if let i = words.firstIndex(where: { generic.contains(core($0)) }) {
                // Noktalama yerinde kalır.
                let w = words[i]
                let tail = String(w.reversed().prefix { $0.isPunctuation }.reversed())
                words[i] = t + tail
                continue
            }
            if tr {
                if let i = words.firstIndex(where: { w in
                    let c = core(w)
                    return turkishVerbStems.contains { c.hasPrefix($0) } && !c.hasPrefix("basit") && !c.hasPrefix("çeki")
                }) {
                    words.insert(t, at: i)
                } else if let last = words.indices.last {
                    // Sondaki noktalamanın önüne.
                    let w = words[last]
                    let tail = String(w.reversed().prefix { $0.isPunctuation }.reversed())
                    words[last] = String(w.dropLast(tail.count)) + " " + t + tail
                } else {
                    words = [t]
                }
            } else {
                words.insert(t, at: 0)
            }
        }
        return words.joined(separator: " ")
    }
}
