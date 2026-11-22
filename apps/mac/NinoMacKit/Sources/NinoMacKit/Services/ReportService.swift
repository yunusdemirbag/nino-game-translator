// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Sorun Bildir ve otomatik bildirim (gecmis-hakkinda-saglik.md §3.3, §4).
//
// `POST v1/reports` gövdesi havuz sunucusunun `receiveReport` doğrulamasına göre (docs/yeni/mac/sunucu-uyumu.md):
// `v` 1, `install` 8–64 karakter, `platform` "mac", boş olmayan `text` (en çok 4000), `log` (en çok 60 000),
// `contact` (200), `device` (600), `images` en çok 3 × {mime, data}; bütün gövde en çok 4 MB. Yazı dosyası ekleri
// `log`un sonuna eklenir (ReportAttachment.swift). Otomatik bildirim bu yoldan gitmez: teşhis özeti ölçümün `diag`
// olayıdır (DiagMonitor; kayıt dosyası taşımaz).

public struct ProblemReport: Equatable, Sendable {
    public enum Kind: String, Sendable { case user, auto }
    public var kind: Kind
    /// Kullanıcının yazdığı (boş olabilir).
    public var description: String
    /// Nino'nun tespitleri: muhtemel sebep, son 3 günün sorunları, ölçüm özeti.
    public var findings: String
    public var contact: String
    public var photos: [PhotoAttachment]
    /// Günlük sonları (Sorun Bildir her zaman ekler); yoksa nil.
    public var logs: String?
    /// Kullanıcının eklediği yazı dosyaları (`log`un sonuna gider).
    public var textFiles: [ReportTextFile]
    public var device: String

    public init(kind: Kind, description: String, findings: String, contact: String = "",
                photos: [PhotoAttachment] = [], logs: String? = nil, textFiles: [ReportTextFile] = [],
                device: String) {
        self.kind = kind
        self.description = description
        self.findings = findings
        self.contact = contact
        self.photos = photos
        self.logs = logs
        self.textFiles = textFiles
        self.device = device
    }

    /// Verilen gizli değerler (kayıtlı API anahtarları) bütün metin alanlarından silinir.
    public func redacting(_ secrets: [String]) -> ProblemReport {
        let list = secrets.filter { $0.count >= 8 }
        guard !list.isEmpty else { return self }
        func clean(_ text: String) -> String {
            list.reduce(text) { $0.replacingOccurrences(of: $1, with: "[gizli]") }
        }
        var copy = self
        copy.description = clean(description)
        copy.findings = clean(findings)
        copy.contact = clean(contact)
        copy.logs = logs.map(clean)
        copy.textFiles = textFiles.map { ReportTextFile(name: clean($0.name), text: clean($0.text)) }
        copy.device = clean(device)
        return copy
    }
}

public enum ReportError: String, Error, Equatable, Sendable {
    /// Bugün çok bildirim gönderildi.
    case dailyLimit
    /// İnternet yok ya da adres yok.
    case offline
    case tooLarge
    /// Reddedildi ya da sunucu hatası.
    case server
}

public struct ReportContext: Equatable, Sendable {
    public var install: String
    public var app: String
    public var language: String

    public init(install: String, app: String, language: String) {
        self.install = install
        self.app = app
        self.language = language
    }
}

public enum ReportContract {
    /// Sunucunun `REPORT_LIMITS.maxBodyBytes` sınırı.
    public static let maxBodyBytes = 4 * 1024 * 1024
    public static let timeout: TimeInterval = 60
    /// Sunucu `log`un ilk 60 000 UTF-16 birimini tutar; en yeni satırlar kalsın diye sonundan bu kadarı gönderilir.
    public static let maxLogUnits = 60_000
    /// Sunucu `text`in ilk 4000 UTF-16 birimini tutar; tespitler kesilmesin diye açıklama kısaltılır.
    public static let maxTextUnits = 4000

    /// Metnin sonundan en çok `limit` UTF-16 birimi; karakterin ortasından kesmez.
    static func tail(_ text: String, limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var units = 0
        var start = text.endIndex
        for index in text.indices.reversed() {
            let n = String(text[index]).utf16.count
            if units + n > limit { break }
            units += n
            start = index
        }
        return String(text[start...])
    }

    public static func body(_ report: ProblemReport, context: ReportContext) throws -> Data {
        let findings = AssistantContract.clip(report.findings, limit: maxTextUnits)
        let room = maxTextUnits - findings.utf16.count - (findings.isEmpty ? 0 : 2)
        var text = AssistantContract.clip(report.description, limit: max(0, room))
        if !findings.isEmpty { text += (text.isEmpty ? "" : "\n\n") + findings }
        var object: [String: Any] = [
            "v": 1, "kind": report.kind.rawValue, "install": context.install, "app": context.app,
            "platform": "mac", "language": context.language, "text": text,
        ]
        if !report.device.isEmpty { object["device"] = report.device }
        let contact = report.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty { object["contact"] = contact }
        let files = ReportAttachments.textBlock(report.textFiles)
        if files.isEmpty {
            if let logs = report.logs { object["log"] = tail(logs, limit: maxLogUnits) }
        } else {
            // Ekler sonda ve kesilmeden; günlüğün kalan payı sonundan.
            let room = maxLogUnits - files.utf16.count - 2
            let logs = report.logs.map { tail($0, limit: max(0, room)) } ?? ""
            object["log"] = logs.isEmpty ? files : logs + "\n\n" + files
        }
        if !report.photos.isEmpty { object["images"] = report.photos.prefix(PhotoAttachment.maxCount).map(\.json) }
        let data = try ContractJSON.encode(object)
        if data.count > maxBodyBytes { throw ReportError.tooLarge }
        return data
    }

    public static func interpret(status: Int, data: Data) -> Result<Void, ReportError> {
        switch status {
        case 200..<300:
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let ok = json?["ok"] as? Bool, !ok { return .failure(.server) }
            return .success(())
        case 429: return .failure(.dailyLimit)
        case 413: return .failure(.tooLarge)
        default: return .failure(.server)
        }
    }
}

/// `POST v1/reports` istemcisi. Ağ `NetworkClient` arkasındadır.
public struct ReportClient: Sendable {
    public var network: NetworkClient
    public var baseURL: URL?
    public var appVersion: String

    public init(network: NetworkClient, baseURL: URL?, appVersion: String) {
        self.network = network
        self.baseURL = baseURL
        self.appVersion = appVersion
    }

    public func send(_ report: ProblemReport, context: ReportContext) async -> Result<Void, ReportError> {
        guard let baseURL else { return .failure(.offline) }
        let body: Data
        do { body = try ReportContract.body(report, context: context) } catch { return .failure(.tooLarge) }
        return await send(body: body, to: baseURL)
    }

    /// Hazır gövdeyi gönderir (bekleyen otomatik bildirim).
    public func send(body: Data, to baseURL: URL) async -> Result<Void, ReportError> {
        var request = URLRequest(url: PoolServer.endpoint(baseURL, "v1/reports"), timeoutInterval: ReportContract.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-report/1 (mac; \(appVersion))", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await network.send(request)
            return ReportContract.interpret(status: response.statusCode, data: data)
        } catch {
            return .failure(.offline)
        }
    }
}

/// Sorun Bildir'deki ve otomatik bildirimdeki "Nino'nun tespitleri" metni (Türkçe, sabit).
public enum ReportFindings {
    public static func text(causeTitle: String?, problems: [ProblemRecord], metrics: HealthMetrics,
                            now: Date = Date()) -> String {
        var lines = ["— Nino'nun bulguları —"]
        lines.append("muhtemel sebep: \(causeTitle ?? "yok")")
        if problems.isEmpty {
            lines.append("son 3 günün sorunları: yok")
        } else {
            let formatter = ISO8601DateFormatter()
            lines.append("son 3 günün sorunları:")
            lines += problems.map { "• \(formatter.string(from: $0.date)) \($0.logLine)" }
        }
        lines.append(contentsOf: DetailsText.metricsSummary(metrics, now: now))
        return lines.joined(separator: "\n")
    }
}

/// Sorun Bildir'e eklenen günlük sonları: başta "Nino <sürüm>, macOS <sürüm>", sonra Remote Play, altyazı ve
/// TV kurulum günlüklerinin son kısmı.
public enum ReportLogs {
    public static func collect(folder: DataFolder, facts: DeviceFacts, linesPerLog: Int = 200) -> String {
        var parts = ["Nino \(facts.appVersion), \(facts.systemVersion)"]
        for (name, url) in [("remoteplay.log", folder.remotePlayLog), ("altyazi.log", folder.subtitleLog),
                            ("tvinstall.log", folder.tvInstallLog)] {
            parts.append("")
            parts.append("— \(name) —")
            parts.append(DetailsText.tail(of: url, lines: linesPerLog))
        }
        return parts.joined(separator: "\n")
    }
}
