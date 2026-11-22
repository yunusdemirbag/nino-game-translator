// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

/// Bir TV'nin (DUID) imza profili: `samsung/<güvenli DUID>/` (tv-kurulumu.md §9.5, §9.12). Eski Mac/Windows
/// sürümlerinin yazdığı biçimle aynıdır; o dosyalar okunur, kullanıcı yeniden giriş yapmaz.
public struct SamsungProfile {
    public static let authorFile = "author.p12"
    public static let distributorFile = "distributor.p12"
    public static let passwordFile = "password.txt"
    public static let duidFile = "duid.txt"
    public static let deviceProfileFile = "device-profile.xml"

    public let folder: URL
    public let author: PKCS12.Contents
    public let distributor: PKCS12.Contents

    public enum Status: Equatable {
        case missing
        case valid
        case expired
        case otherTV
        case unreadable(String)

        var logText: String {
            switch self {
            case .missing: return "yok"
            case .valid: return "geçerli"
            case .expired: return "süresi dolmuş"
            case .otherTV: return "başka TV'nin"
            case let .unreadable(m): return "okunamadı (\(m))"
            }
        }
    }

    public static func folder(profiles: URL, duid: String) -> URL {
        profiles.appendingPathComponent(SamsungOutputs.safeDUID(duid), isDirectory: true)
    }

    /// Profili okur ve durumunu söyler (geçerli değilse de okunabildiyse profil döner, günlük için).
    public static func load(profiles: URL, duid: String, now: Date,
                            log: (String) -> Void) -> (SamsungProfile?, Status) {
        let dir = folder(profiles: profiles, duid: duid)
        let fm = FileManager.default
        let a = dir.appendingPathComponent(authorFile), d = dir.appendingPathComponent(distributorFile)
        let pw = (try? String(contentsOf: dir.appendingPathComponent(passwordFile), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard fm.fileExists(atPath: a.path), fm.fileExists(atPath: d.path), !pw.isEmpty else {
            log("Kayıtlı sertifika: yok")
            return (nil, .missing)
        }
        let author: PKCS12.Contents, distributor: PKCS12.Contents
        do {
            author = try PKCS12.parse(try Data(contentsOf: a), password: pw)
            distributor = try PKCS12.parse(try Data(contentsOf: d), password: pw)
        } catch {
            log("Kayıtlı sertifika: okunamadı (\(error))")
            return (nil, .unreadable("\(error)"))
        }
        let profile = SamsungProfile(folder: dir, author: author, distributor: distributor)
        let ai = author.certificates.first.flatMap { X509Info(der: $0) }
        let di = distributor.certificates.first.flatMap { X509Info(der: $0) }
        let status: Status
        if ai == nil || di == nil {
            status = .unreadable("sertifika")
        } else {
            let limit = now.addingTimeInterval(86400)
            let ok = [ai!, di!].allSatisfy { $0.notBefore <= limit && $0.notAfter >= limit }
            let saved = (try? String(contentsOf: dir.appendingPathComponent(duidFile), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved, !saved.isEmpty, saved != duid { status = .otherTV } else { status = ok ? .valid : .expired }
        }
        log("Kayıtlı sertifika: \(status.logText); yazar \(range(ai)) UTC, dağıtıcı \(range(di)) UTC, "
            + "dağıtıcıyı veren \(di?.issuerCN ?? "?")")
        return (profile, status)
    }

    static func range(_ i: X509Info?) -> String {
        guard let i else { return "?" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(f.string(from: i.notBefore))–\(f.string(from: i.notAfter))"
    }

    func identity(_ c: PKCS12.Contents) throws -> WidgetSigner.Identity {
        let key = try ADBKey(pkcs1: c.privateKey).privateKey
        return WidgetSigner.Identity(key: key, certificates: c.certificates)
    }

    public func authorIdentity() throws -> WidgetSigner.Identity { try identity(author) }
    public func distributorIdentity() throws -> WidgetSigner.Identity { try identity(distributor) }

    /// Yeni profili yazar (parola: 16 rastgele baytın büyük harfli onaltılığı).
    public static func save(profiles: URL, duid: String, keyPKCS1: Data, authorChain: [Data], distributorChain: [Data],
                            deviceProfile: Data) throws -> SamsungProfile {
        let dir = folder(profiles: profiles, duid: duid)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let password = PKCS12.random(16).map { String(format: "%02X", $0) }.joined()
        let a = try PKCS12.build(privateKeyPKCS1: keyPKCS1, certificates: authorChain, password: password)
        let d = try PKCS12.build(privateKeyPKCS1: keyPKCS1, certificates: distributorChain, password: password)
        func write(_ name: String, _ data: Data) throws {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        try write(authorFile, a)
        try write(distributorFile, d)
        try write(deviceProfileFile, deviceProfile)
        try write(passwordFile, Data(password.utf8))
        try write(duidFile, Data(duid.utf8))
        return SamsungProfile(folder: dir,
                              author: PKCS12.Contents(privateKey: keyPKCS1, certificates: authorChain),
                              distributor: PKCS12.Contents(privateKey: keyPKCS1, certificates: distributorChain))
    }

    /// TV'nin reddettiği profili `<klasör>.rejected-<yyyyMMddHHmmss UTC>` olarak kenara koyar; olmazsa siler.
    public static func setAside(_ dir: URL, now: Date) -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmmss"
        let target = dir.deletingLastPathComponent()
            .appendingPathComponent(dir.lastPathComponent + ".rejected-" + f.string(from: now), isDirectory: true)
        do {
            try FileManager.default.moveItem(at: dir, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }
}
