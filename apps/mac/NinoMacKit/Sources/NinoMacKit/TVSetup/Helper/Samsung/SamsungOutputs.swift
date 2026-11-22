// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// TV'nin sdb yanıtlarını okuma ve kurulum çıktısını sınıflama (tv-kurulumu.md §9.4, §9.10).
public enum SamsungOutputs {
    public static let appID = "NinoTVApps.Nino"
    public static let packageID = "NinoTVApps"
    public static let defaultToolPath = "/opt/usr/apps/tmp"

    // MARK: Tizen sürümü

    /// En eski desteklenen Tizen 3.0. Sürüm boşsa kurulum denenir.
    public static func isTooOld(_ platform: String?) -> Bool {
        guard let p = platform?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return false }
        return TVVersion(p) < TVVersion("3.0")
    }

    /// Tizen 3.0–4.0 (ikisi dahil) cihaz profili ister.
    public static func needsDeviceProfile(_ platform: String?) -> Bool {
        guard let p = platform?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return false }
        let v = TVVersion(p)
        return !(v < TVVersion("3.0")) && !(TVVersion("4.0") < v)
    }

    public static func isExperimental(_ platform: String?) -> Bool {
        guard let p = platform?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return false }
        return TVVersion(p) < TVVersion("5.0")
    }

    // MARK: vd_applist

    /// TV'deki Nino sürümü; yoksa nil.
    public static func installedVersion(applist: String) -> String? {
        guard let v = version(applist: applist, ids: [appID, packageID]), !v.isEmpty else { return nil }
        return v
    }

    /// Sahadaki eski kimlikli TV uygulamasının sürümü: kurulu değilse nil, kurulu ama sürümü yazmıyorsa boş.
    public static func legacyVersion(applist: String) -> String? {
        version(applist: applist, ids: [TVApp.legacySamsungID, LegacyNames.samsungTVPackageID])
    }

    /// `ids`'den birinin bloğundaki sürüm. Sürümlü blok öncelikli; yalnız sürümsüz blok varsa boş metin.
    static func version(applist: String, ids: [String]) -> String? {
        let wanted = Set(ids.map { $0.lowercased() })
        var block: [String: String] = [:]
        var presentWithoutVersion = false
        func check() -> String? {
            let id = (block["app_tizen_id"] ?? block["app_id"] ?? "").lowercased()
            let other = (block["app_id"] ?? "").lowercased()
            guard wanted.contains(id) || wanted.contains(other) else { return nil }
            if let v = block["app_version"], !v.isEmpty { return v }
            presentWithoutVersion = true
            return nil
        }
        for raw in applist.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if !line.contains("="), line.contains("----") {
                if let v = check() { return v }
                block = [:]
                continue
            }
            if let (k, v) = field(line) { block[k] = v }
        }
        if let v = check() { return v }
        return presentWithoutVersion ? "" : nil
    }

    /// `[ \t-]*anahtar = değer` satırı; değerin sonundaki boşluk ve tireler atılır.
    static func field(_ line: String) -> (String, String)? {
        let s = line.drop(while: { $0 == " " || $0 == "\t" || $0 == "-" })
        guard let eq = s.firstIndex(of: "=") else { return nil }
        let key = s[..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ ($0.isASCII && $0.isLetter) || $0 == "_" }) else { return nil }
        var value = s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        while let last = value.last, last == "-" || last == " " || last == "\t" { value.removeLast() }
        return (key, value)
    }

    // MARK: DUID

    /// `0 getduid` çıktısının ilk satırı kalıba uyuyorsa DUID.
    public static func duid(from output: String) -> String? {
        let first = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-+=/")
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return t
    }

    /// Profil klasörü adı: `[A-Za-z0-9_-]` dışı `_`.
    public static func safeDUID(_ duid: String) -> String {
        String(duid.map { c -> Character in
            (c.isASCII && (c.isLetter || c.isNumber)) || c == "_" || c == "-" ? c : "_"
        })
    }

    // MARK: Kurulum çıktısı

    public enum InstallClass: Equatable, Sendable {
        case success
        case connectionLost      // 1
        case notEligible         // 2
        case noSpace             // 3
        case certificateInvalid  // 4 (reddedildi)
        case clockBehind         // 4 (not valid yet)
        case certificateMismatch // 5
        case packageBlocked      // 6
        case other               // 7

        public var code: String {
            switch self {
            case .success: return ""
            case .connectionLost: return "ConnectionLost"
            case .notEligible, .other: return "InstallFailed"
            case .noSpace: return "NotEnoughSpace"
            case .certificateInvalid: return "CertificateRejected"
            case .clockBehind: return "TvClockWrong"
            case .certificateMismatch: return "CertificateMismatch"
            case .packageBlocked: return "PackageBlocked"
            }
        }

        /// Kaldırıp bir kez daha denenir mi (5, 6, 7).
        public var retriesAfterUninstall: Bool { [.certificateMismatch, .packageBlocked, .other].contains(self) }
    }

    static let lostMarkers = ["transport connection", "connection reset by peer", "broken pipe"]

    public static func classify(_ output: String) -> InstallClass {
        let o = output.lowercased()
        let failed = o.contains("install failed") || o.contains("val[fail]") || o.contains("not enough space")
            || o.contains("download failed[116]") || lostMarkers.contains(where: o.contains)
        guard failed else { return .success }
        if lostMarkers.contains(where: o.contains) { return .connectionLost }
        if ["install failed[118, -4]", "install failed[118, -19]", "install failed[118019]"].contains(where: o.contains) {
            return .notEligible
        }
        if o.contains("download failed[116]") || o.contains("not enough space") { return .noSpace }
        let certCode = ["install failed[118, -12]", "[118012]", "[118, -11]", "[118011]"].contains(where: o.contains)
        if certCode, o.contains("check certificate error"), !o.contains("same id and different certificate") {
            return o.contains("not valid yet") ? .clockBehind : .certificateInvalid
        }
        if certCode || o.contains("author certificate not match") { return .certificateMismatch }
        if o.contains("install failed[118, -22]") || o.contains("[118022]") { return .packageBlocked }
        return .other
    }

    /// Kullanıcıya gösterilen ayrıntı: ilgili ilk 3 farklı satır ya da son 3 satır; en çok 400 karakter.
    public static func failureDetail(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty { return "TV'den yanıt gelmedi" }
        var picked: [String] = []
        for l in lines where picked.count < 3 {
            let low = l.lowercased()
            guard ["fail", "error", "reason", "not match", "space"].contains(where: low.contains) else { continue }
            if !picked.contains(l) { picked.append(l) }
        }
        if picked.isEmpty { picked = Array(lines.suffix(3)) }
        let joined = picked.joined(separator: " | ")
        return joined.count > 400 ? String(joined.prefix(400)) + "…" : joined
    }
}
