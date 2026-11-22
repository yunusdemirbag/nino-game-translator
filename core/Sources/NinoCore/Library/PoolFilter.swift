// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Hangi satırın ortak havuza gideceğine karar verir. Ön süzgeçtir: sunucu satırı kendi süzgecinden yeniden geçirir,
/// sözcük listeleri sunucununkiyle birebir aynı olmak zorunda değil.
public struct PoolFilter: Sendable {
    /// Okuma hattının OCR çöp denetimi (temizlik sonrası metin değişiyorsa çöp).
    /// Okuma hattı tarifine aittir; verilmezse yalnız harf oranına bakılır.
    public var isGarbage: @Sendable (String) -> Bool

    public init(isGarbage: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.isGarbage = isGarbage
    }

    static let maxLength = 500

    static let dangling: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "but", "with", "for", "from", "my", "your", "his", "her", "their",
        "our", "at", "in", "on", "by", "into", "than", "that", "if", "as", "is", "are", "was", "were",
    ]

    /// PS5'in Türkçe arayüzünde sık görülen sözcükler (aksansız, `fold` biçiminde). Kendi seçimimiz:
    /// satırda bunlardan ikisi varsa satır oyun altyazısı değil, Türkçe sistem yazısı sayılır.
    static let turkishUIWords: [String] = [
        // genel
        "lutfen", "bekleyin", "yukleniyor", "indiriliyor", "tamamlandi", "kaydedildi", "guncelleme", "ayarlar",
        // ekranlar ve kısımlar
        "ekran", "ekrani", "ekranda", "goruntusu", "medya", "galerisi", "kitaplik", "bildirim", "bildirimler",
        // oyun ve hesap
        "oyun", "oyunu", "oyunlar", "kupa", "kupalar", "kazandiniz", "oturum", "acti", "kapatti", "arkadaslar",
        // cihaz
        "denetleyici", "baglanti", "kesildi", "kapat", "baslat", "yeniden",
    ].map { fold($0) }

    /// PS5 bildirimlerinden ve oyun dışı ekranlardan sözcük öbekleri (tam öbek olarak aranır). Kendi seçimimiz.
    static let systemPhrases: [String] = [
        // hesap ve parti
        "signed in", "signed out", "is now online", "joined the party", "left the party",
        // kupa
        "trophy earned", "trophy unlocked", "earned a trophy",
        // yakalama
        "screenshot saved", "video clip saved", "media gallery",
        // sistem
        "download complete", "installation complete", "update available", "playstation network", "remote play",
        "ps button", "controller disconnected", "controller battery",
        // oyun dışı ekran
        "press any button", "photo mode", "cloud save",
        // Türkçe arayüz
        "lutfen bekleyin", "oturum acti", "oturum kapatti", "ana ekran", "kupa kazandiniz", "ekran goruntusu",
    ].map { fold($0) }

    /// Denetim ve sıfır genişlikli karakterler boşluk olur, boşluklar teklenir.
    public static func clean(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            let v = s.value
            let invisible = v <= 0x1f || (0x7f...0x9f).contains(v) || (0x200b...0x200f).contains(v)
                || v == 0x2028 || v == 0x2029 || v == 0xfeff
            out.append(invisible ? " " : s)
        }
        return String(out).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Kabul edilen satırın temiz hâli; reddedilirse `nil`.
    public func prepare(_ text: String) -> String? {
        let line = Self.clean(text)
        guard !line.isEmpty, line.unicodeScalars.count <= Self.maxLength, line.contains(where: \.isLetter) else { return nil }
        // Gürültü
        if isGarbage(line) { return nil }
        let visible = line.filter { !$0.isWhitespace }
        if visible.filter(\.isLetter).count * 2 < visible.count { return nil }
        // Yarım okuma
        if Self.isPartial(line) { return nil }
        // Türkçe ya da PS5 sistem yazısı
        if Self.isTurkish(line) || Self.isSystemText(line) { return nil }
        return line
    }

    public func accepts(_ text: String) -> Bool { prepare(text) != nil }

    static func isPartial(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)] "))
        let hasEnd = stripped.last.map { ".!?…".contains($0) } ?? false
        let words = line.split(separator: " ")
        let letterWords = words.filter { $0.contains(where: \.isLetter) }.count
        if !hasEnd, letterWords < 3 || line.count < 15 { return true }
        if let first = line.first(where: \.isLetter), first.isLowercase { return true }
        if !hasEnd, let last = words.last {
            let w = last.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if dangling.contains(w) { return true }
        }
        if !hasEnd, !line.contains(where: \.isLowercase), words.count <= 6 { return true }
        return false
    }

    static func isTurkish(_ line: String) -> Bool {
        if line.contains(where: { "ğĞşŞıİ".contains($0) }) { return true }
        if line.filter({ "üÜöÖçÇ".contains($0) }).count >= 2 { return true }
        var hits = 0
        for w in fold(line).split(separator: " ").map(String.init) where turkishUIWords.contains(where: { near(w, $0) }) {
            hits += 1
            if hits >= 2 { return true }
        }
        return false
    }

    static func isSystemText(_ line: String) -> Bool {
        let padded = " " + fold(line) + " "
        return systemPhrases.contains { padded.contains(" " + $0 + " ") }
    }

    /// 6+ harfli sözcükte bir harf farkı serbest.
    static func near(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 6, b.count >= 6, abs(a.count - b.count) <= 1 else { return false }
        return TextSimilarity.levenshtein(Array(a), Array(b)) <= 1
    }

    /// Küçük harf, `ı→i`, aksansız, `q→c`, `l`/`1`→`i`, harf/rakam dışı ayraç.
    static func fold(_ text: String) -> String {
        let base = text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .decomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        for s in base.unicodeScalars {
            let cat = s.properties.generalCategory
            if cat == .nonspacingMark { continue }
            if !LineKey.isLetterOrNumber(cat) { out.append(" "); continue }
            switch s {
            case "q": out.append("c")
            case "l", "1": out.append("i")
            default: out.unicodeScalars.append(s)
            }
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}
