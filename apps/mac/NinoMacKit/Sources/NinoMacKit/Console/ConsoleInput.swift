// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Kullanıcının yazdığı PS5 adresi, eşleştirme kodu ve giriş şifresi (kurulum.md §6, ayarlar.md §5).
public enum ConsoleInput {
    // MARK: Adres

    /// Elle yazılan adresi temizler: "192.168.1.5:9295", "http://192.168.1.5/", "192,168,1,5".
    /// IPv4 değilse ya da kullanılamaz bir adresse (0.0.0.0, yayın, çok noktaya yayın) `nil`.
    public static func sanitizeAddress(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["http://", "https://"] where s.hasPrefix(scheme) { s.removeFirst(scheme.count) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        s = s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(p), v <= 255 else {
                return nil
            }
            octets.append(v)
        }
        let address = octets.map(String.init).joined(separator: ".")
        return isUsableAddress(address) ? address : nil
    }

    /// Bağlanmak ve saklamak için kullanılabilir mi (0.0.0.0, boş, yayın ve çok noktaya yayın adresleri değil).
    public static func isUsableAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        if parts[0] == 0 || parts[0] >= 224 || parts[3] == 255 { return false }
        return true
    }

    // MARK: Eşleştirme kodu

    /// 8 haneli kodu okur. Boşluk, "-", "–", ".", "_" atlanır; başka yazı sistemlerinin onluk
    /// rakamları da kabul edilir. Başka karakter varsa ya da 8 hane değilse `nil`.
    public static func pairingCode(_ text: String) -> String? {
        let skipped: Set<Character> = [" ", "-", "–", ".", "_", "\u{00A0}"]
        var digits = ""
        for ch in text where !skipped.contains(ch) {
            guard let d = decimalDigit(ch) else { return nil }
            digits.append(d)
        }
        return digits.count == 8 ? digits : nil
    }

    /// Kod alanına yazılanı süzer: yalnız rakamlar (ASCII'ye çevrilmiş), en çok 8 hane.
    public static func filterCodeInput(_ text: String) -> String {
        String(text.compactMap(decimalDigit).prefix(8))
    }

    private static func decimalDigit(_ ch: Character) -> Character? {
        guard ch.unicodeScalars.count == 1, let scalar = ch.unicodeScalars.first,
              scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue,
              value >= 0, value <= 9 else { return nil }
        return Character(String(Int(value)))
    }

    // MARK: Giriş şifresi

    /// Boşluklar atılır; tam 4 ASCII rakam değilse `nil`.
    public static func loginPasscode(_ text: String) -> String? {
        let s = text.filter { !$0.isWhitespace }
        guard s.count == 4, s.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return s
    }
}
