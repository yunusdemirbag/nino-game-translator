// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Telefon sözlüğü (tarif §6.6)

extension GameReading {
    /// Telefon uygulamalarının sabit yazıları (yalnız Türkçe hedef).
    public enum PhoneDictionary {
        /// Sadeleştirilmiş İngilizce → Türkçe. Aynı kalanlar (yayın adları) kendisiyle eşlenir.
        static let entries: [String: String] = {
            let pairs: [(String, String)] = [
                ("Vice City Horn", "Vice City Horn"), ("The Leonida Journal", "The Leonida Journal"),
                ("Leonida Journal", "Leonida Journal"),
                ("Ripped", "Kaslı"), ("Toned", "Sıkı"), ("Average", "Ortalama"),
                ("Body & Nutrition", "Beden ve Beslenme"), ("Strength Workout", "Kuvvet Antrenmanı"),
                ("Cardio Workout", "Kardiyo Çalışması"), ("Workout Window", "Antrenman Saati"),
                ("Focus", "Odak"), ("Fitness", "Fitness"), ("Calorie Balance", "Kalori Hesabı"),
                ("You will maintain weight", "Kilon sabit kalacak"), ("You will gain weight", "Kilon artacak"),
                ("You will lose weight", "Kilon azalacak"), ("Hungry", "Aç"), ("Full", "Tok"),
                ("Trip Details", "Yolculuk Ayrıntıları"), ("Cost", "Ücret"),
                ("Choose Ryde", "Ryde Seç"), ("Standard Ryde", "Normal Ryde"),
                ("Change Destination", "Gidilecek Yeri Değiştir"),
                ("Book Ryde", "Ryde Çağır"), ("Cancel Ryde", "Yolculuğu İptal Et"),
                ("Checking Account", "Cari Hesap"), ("Savings Account", "Tasarruf Hesabı"),
                ("Family Savings", "Aile Tasarrufu"), ("Family Savings Video", "Aile Tasarrufu Videosu"),
                ("ATM Finder", "ATM Bulucu"), ("FAQs", "SSS"), ("Savings", "Tasarruf"), ("Balance", "Bakiye"),
                ("Deposit", "Para Yatır"), ("Withdraw", "Para Çek"), ("Transfer", "Transfer"),
                ("Transactions", "İşlemler"), ("Recent Transactions", "Son İşlemler"),
                ("Set a Goal", "Hedef Koy"), ("Messages encrypted", "Mesajlar şifrelendi"),
                ("New message", "Yeni mesaj"), ("All Contacts", "Tüm Kişiler"), ("Suggested", "Önerilenler"),
                ("Messages", "Mesajlar"), ("Map pin expired", "Harita işaretinin süresi bitti"),
            ]
            var d: [String: String] = [:]
            for (en, tr) in pairs { d[Text.key(en)] = tr }
            return d
        }()

        static let statNames: [(String, String)] = [
            ("body fat", "Vücut Yağı"), ("muscle", "Kas"), ("stamina", "Dayanıklılık"), ("strength", "Güç"), ("fat", "Yağ"),
        ]
        static let statLevels: [String: String] = [
            "high": "Yüksek", "low": "Düşük", "medium": "Orta", "average": "Ortalama",
            "very high": "Çok Yüksek", "very low": "Çok Düşük",
        ]

        /// Sözlükte tam (kalıpsız) var mı?
        public static func exact(_ text: String) -> String? { entries[Text.key(text)] }

        /// Sözlük ya da kalıplarla Türkçesi. Yoksa `nil`.
        public static func turkish(_ text: String) -> String? {
            let t = text.trimmingCharacters(in: .whitespaces)
            if let e = exact(t) { return e }
            return pattern(t)
        }

        /// Yalnız kalıplar (sondaki parantezli tutar, `Ad - Seviye`, `Level 3/4`, hedef satırı).
        public static func pattern(_ text: String) -> String? {
            let t = text.trimmingCharacters(in: .whitespaces)
            // Sonda parantezli tutar korunur.
            if let r = t.range(of: #"\s*\([^()]*\)$"#, options: .regularExpression), r.lowerBound > t.startIndex {
                let head = String(t[..<r.lowerBound]), tail = t[r].trimmingCharacters(in: .whitespaces)
                if let h = turkish(head) { return "\(h) \(tail)" }
            }
            // Level 3/4
            if let m = match(#"^level\s+(\d+\s*/\s*\d+)$"#, t) { return "Seviye \(m[1].replacingOccurrences(of: " ", with: ""))" }
            // $4,900 to next goal
            if let m = match(#"^([$€£]\s?[\d.,]+)\s+to\s+next\s+goal$"#, t) {
                return "Sonraki hedefe \(m[1].replacingOccurrences(of: ",", with: "."))"
            }
            // Ad - Seviye (tire düşmüş olabilir).
            let key = Text.key(t)
            for (name, tr) in statNames where key.hasPrefix(name + " ") {
                let rest = String(key.dropFirst(name.count + 1))
                if let level = statLevels[rest] { return "\(tr) - \(level)" }
            }
            return nil
        }

        static func match(_ pattern: String, _ text: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let ns = text as NSString
            guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
}

// MARK: - Telefon uygulaması yazısı (tarif §7)

extension GameReading.PhoneDictionary {
    static let appRoots = [
        "trip detail", "change destinat", "destinatio", "messages encrypt", "map pin expir", "checking accoun",
        "family saving", "workout window", "strength workout", "cardio workout", "calorie balanc",
        "maintain weight", "gain weight", "lose weight",
    ]
    static let appWords: Set<String> = ["ryde", "rydeme", "buckme"]

    /// Telefon uygulamasının kendi yazısı mı (telefon bulunamasa da)?
    public static func isAppText(_ text: String) -> Bool {
        let key = GameReading.Text.key(text)
        guard !key.isEmpty else { return false }
        let padded = " " + key
        if appRoots.contains(where: { padded.contains(" " + $0) }) { return true }
        let words = key.split(separator: " ").map(String.init)
        if words.contains(where: appWords.contains) { return true }
        // Tek sözcükler (`Focus`, `Cost`) diyalogda da geçer, sayılmaz.
        guard words.count >= 2 else { return false }
        let plain = text.replacingOccurrences(of: #"\([^()]*\)"#, with: " ", options: .regularExpression)
        if exact(plain) != nil { return true }
        return pattern(text) != nil
    }
}

// MARK: - Çeviri sonucu temizliği (tarif §6.5)

extension GameReading {
    public enum PhoneText {
        static let entities: [(String, String)] = [
            ("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'"),
        ]

        public static func decodeEntities(_ text: String) -> String {
            var t = text
            for (e, c) in entities { t = t.replacingOccurrences(of: e, with: c) }
            return t
        }

        /// Simge (ve emoji) mi? Para birimi ve matematik işaretleri kalır.
        static func isSymbol(_ s: Unicode.Scalar) -> Bool {
            if s.properties.generalCategory == .otherSymbol { return true }
            if s.properties.isEmojiPresentation { return true }
            if (0xFE00...0xFE0F).contains(s.value) || s.value == 0x200D { return true }
            return false
        }

        public static func stripSymbols(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.filter { !isSymbol($0) }))
        }

        /// Simgeler ve HTML varlıkları temizlenir, boşluklar sadeleşir, art arda aynı sözcük teke iner.
        public static func clean(_ text: String) -> String {
            let t = stripSymbols(decodeEntities(text))
            var out: [String] = []
            for w in Text.words(t) {
                if let last = out.last, last.lowercased() == w.lowercased(), w.contains(where: \.isLetter) { continue }
                out.append(w)
            }
            return out.joined(separator: " ")
        }
    }
}
