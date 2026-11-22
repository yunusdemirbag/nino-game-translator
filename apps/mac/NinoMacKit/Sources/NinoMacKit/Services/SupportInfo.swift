// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation

// Destek metinleri (gecmis-hakkinda-saglik.md §3.5, §3.6): cihaz bilgileri ve "Ayrıntılar".
// Değerler destek içindir: ekran dili değişse de Türkçe ve sabittir. Ad, seri numarası ya da adres içermez
// (Host PC IP uyuşmazlığındaki ev ağı adresleri yalnız "Ayrıntılar"da durur; o metin gönderilmez).

/// Bu Mac'in değişmeyen bilgileri. Testlerde elle verilir.
public struct DeviceFacts: Equatable, Sendable {
    public var appVersion: String
    public var build: String?
    public var model: String
    public var systemVersion: String
    public var processor: String
    public var memoryGB: Int

    public init(appVersion: String, build: String?, model: String, systemVersion: String, processor: String,
                memoryGB: Int) {
        self.appVersion = appVersion
        self.build = build
        self.model = model
        self.systemVersion = systemVersion
        self.processor = processor
        self.memoryGB = memoryGB
    }

    /// Çalışan Mac'ten okunur.
    public static func current(bundle: Bundle = .main) -> DeviceFacts {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info["CFBundleVersion"] as? String
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceFacts(appVersion: version, build: build == version ? nil : build,
                           model: sysctlString("hw.model") ?? "Mac",
                           systemVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                           processor: sysctlString("machdep.cpu.brand_string") ?? "?",
                           memoryGB: Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()))
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Cihaz bilgileri kartının satırları ve düz metin özeti.
public struct DeviceInfo: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        /// Sheets tablosundaki etiket anahtarı.
        public var labelKey: String
        /// Türkçe, sabit değer.
        public var value: String
        public var id: String { labelKey }
    }

    public var rows: [Row]

    /// Düz metin özeti (panoya kopyalanır, sorun bildirimine eklenir): "Uygulama: … · Mac: …".
    public var summary: String {
        rows.map { "\(Self.summaryLabel[$0.labelKey] ?? $0.labelKey): \($0.value)" }.joined(separator: "\n")
    }

    /// Nino'ya Sor'un `device` alanı: tek satır, en çok 600 karakter.
    public var compactSummary: String {
        let text = rows.map(\.value).joined(separator: " | ")
        return text.count > 600 ? String(text.prefix(600)) : text
    }

    static let summaryLabel = [
        "sheets.device.appVersion": "Nino sürümü",
        "sheets.device.model": "Bilgisayar modeli",
        "sheets.device.system": "macOS sürümü",
        "sheets.device.tv": "TV",
        "sheets.device.console": "Konsol",
        "sheets.device.status": "Anlık durum",
    ]

    @MainActor
    public static func make(state: AppState, facts: DeviceFacts, tvApp: TVAppHealth) -> DeviceInfo {
        var rows: [Row] = []
        let version = facts.appVersion + (facts.build.map { " (\($0))" } ?? "")
        rows.append(Row(labelKey: "sheets.device.appVersion", value: version))
        rows.append(Row(labelKey: "sheets.device.model", value: facts.model))
        rows.append(Row(labelKey: "sheets.device.system", value: facts.systemVersion))
        if let tv = state.pairedTV {
            var parts = [brandName(tv.brand)]
            if let status = tvAppStatus(tvApp) { parts.append(status) }
            parts.append(state.connectedDisplays > 0 ? "bağlı" : "bağlı değil")
            rows.append(Row(labelKey: "sheets.device.tv", value: parts.joined(separator: " · ")))
        }
        let console = state.settings.gameConsole == .xbox ? "Xbox" : "PS5"
        let path: String
        switch state.settings.videoSource {
        case .ps5: path = "Remote Play (Nino bağlanıyor)"
        case .window: path = "oyun penceresi"
        case .card: path = "yakalama kartı"
        }
        rows.append(Row(labelKey: "sheets.device.console", value: "\(console) · \(path)"))
        var status = state.translation == .off ? "çeviri durdu" : "çeviri sürüyor"
        if let game = state.game {
            status += ", oyun: \(game.name) (\(evidenceName(game.evidence)))"
        } else {
            status += ", oyun: tanınmadı"
        }
        if case .ps5(let link) = state.source { status += ", PS5: \(sessionName(link))" }
        rows.append(Row(labelKey: "sheets.device.status", value: status))
        return DeviceInfo(rows: rows)
    }

    static func dropReasonName(_ reason: HealthDropReason) -> String {
        switch reason {
        case .asleep: return "uykuda"
        case .inUseElsewhere: return "başka cihazda"
        case .passcode: return "giriş şifresi"
        case .remotePlayDisabled: return "Remote Play kapalı"
        case .pairingInvalid: return "eşleşme geçersiz"
        case .notFound: return "bulunamadı"
        case .other: return "diğer"
        }
    }

    static func brandName(_ brand: PairedTV.Brand) -> String {
        switch brand {
        case .lg: return "LG webOS"
        case .samsung: return "Samsung Tizen"
        case .androidTV: return "Android TV"
        }
    }

    static func tvAppStatus(_ app: TVAppHealth) -> String? {
        switch app {
        case .unknown: return nil
        case .installing: return "TV uygulaması yükleniyor"
        case .installed(let version): return "TV uygulaması \(version)"
        case .waitingForApproval: return "TV'deki onay bekleniyor"
        case .developerModeOff: return "geliştirici modu açık değil"
        case .waitingForPassword: return "parola girilmedi"
        case .samsungSignIn: return "Samsung hesabı girişi bekleniyor"
        case .failed(let code, let reason, _): return "kurulum hatası \(code) (\(reason))"
        case .hostIPMismatch: return "Host PC IP farklı"
        }
    }

    static func evidenceName(_ evidence: RecognizedGame.Evidence) -> String {
        switch evidence {
        case .console: return "PS5 bildirdi"
        case .user: return "kullanıcı seçti"
        case .pack: return "paketten"
        case .screen: return "ekrandan"
        case .lastPlayed: return "son oynanan (doğrulanmadı)"
        }
    }

    static func sessionName(_ link: SourceStatus.ConsoleLink) -> String {
        switch link {
        case .idle: return "boşta"
        case .connecting: return "bağlanıyor"
        case .streaming: return "akış var"
        case .dropped(let reason): return "koptu (\(dropReasonName(HealthDropReason(reason))))"
        }
    }
}

/// "Ayrıntılar" kutusunun metni (§3.6).
public enum DetailsText {
    /// Günlük dosyasının en çok son 64 KB'si okunur.
    static let tailBytes = 64 * 1024

    @MainActor
    public static func make(state: AppState, facts: DeviceFacts, metrics m: HealthMetrics, tvApp: TVAppHealth,
                            folder: DataFolder) -> String {
        var lines: [String] = []
        lines.append("Nino \(facts.appVersion), \(facts.systemVersion), \(facts.processor), \(facts.memoryGB) GB")
        let engine = state.settings.onlineTranslation ? state.settings.onlineEngine.rawValue : "ücretsiz"
        var session = "yok"
        if case .ps5(let link) = state.source { session = DeviceInfo.sessionName(link) }
        lines.append("motor: \(engine), çeviri: \(state.translation == .off ? "durdu" : "sürüyor"), PS5: \(session)")
        let brand = state.pairedTV.map { DeviceInfo.brandName($0.brand) } ?? "yok"
        lines.append("TV: \(brand), bağlı TV uygulaması \(state.connectedDisplays), TV uygulaması: \(tvAppDetail(tvApp))")
        lines.append(contentsOf: metricsSummary(m))
        lines.append("")
        lines.append("— altyazi.log, son 40 satır —")
        lines.append(tail(of: folder.subtitleLog, lines: 40))
        lines.append("")
        lines.append("— tvinstall.log, son 8 satır —")
        lines.append(tail(of: folder.tvInstallLog, lines: 8))
        return lines.joined(separator: "\n")
    }

    static func tvAppDetail(_ app: TVAppHealth) -> String {
        switch app {
        case .unknown: return "bilinmiyor"
        case .installing: return "kuruluyor"
        case .installed(let v): return "kurulu \(v)"
        case .developerModeOff: return "geliştirici modu açık değil"
        case .waitingForPassword: return "parola girilmedi"
        case .failed(let code, let reason, _): return "hata \(code) (\(reason))"
        case .samsungSignIn: return "Samsung hesabı girişi bekleniyor"
        case .waitingForApproval: return "TV'deki onay bekleniyor"
        case .hostIPMismatch(let tv, let mac): return "Host PC IP uyuşmuyor (TV'de \(tv), bu Mac \(mac))"
        }
    }

    /// Ölçüm özeti: altı satır.
    public static func metricsSummary(_ m: HealthMetrics, now: Date = Date()) -> [String] {
        let down = m.ps5DownSince.map { "\(Int(now.timeIntervalSince($0))) sn" } ?? "-"
        let loss = m.lossPerMinute.map { String(format: "%.0f", $0) } ?? "-"
        let stalls = m.stallsPerMinute.map { String(format: "%.1f", $0) } ?? "-"
        return [
            "ağ: \(m.network.rawValue), oturumda ağ kopması \(m.networkDrops), TV kopması \(m.tvDrops), PS5 kopuk: \(down)",
            String(format: "akış %.0f sn, bağlanma denemesi %d, bağlanma %d, akışta kopma %d", m.streamedSeconds,
                   m.connectAttempts, m.connections, m.dropsWhileStreaming),
            "son kopma sebebi: \(m.lastDropReason.map(DeviceInfo.dropReasonName) ?? "-")",
            "yeniden gönderim \(m.retransmissions), tampon taşması \(m.bufferOverflows) (dakikada kayıp \(loss))",
            "görüntü durması (dakikada) \(stalls), bozuk kare \(m.corruptFrames)",
            "altyazı satırı \(m.subtitleLines), çeviri \(m.translatedLines), ortanca \(m.medianTranslationMs.map(String.init) ?? "-") ms, en uzun \(m.maxTranslationMs.map(String.init) ?? "-") ms",
        ]
    }

    /// Dosyanın son `lines` satırı; dosya yoksa "-".
    public static func tail(of url: URL, lines count: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "-" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "-" }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return "-" }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() } // yarım ilk satır
        let picked = lines.suffix(count)
        return picked.isEmpty ? "-" : picked.joined(separator: "\n")
    }
}

// MARK: - Kayıtları zip olarak kaydet

/// Günlük klasöründeki ".log" dosyalarını ve ayrıntılar metnini zip'ler (§3.6).
/// Ses kayıtları ve görüntü kareleri (alt klasörler, `.jpg`, `.f32`) girmez.
public struct LogExporter: Sendable {
    public var logsFolder: URL
    /// Zip'in konacağı yerler, sırayla denenir (İndirilenler, sonra geçici klasör).
    public var destinations: [URL]
    public var now: @Sendable () -> Date

    public init(logsFolder: URL, destinations: [URL], now: @escaping @Sendable () -> Date = Date.init) {
        self.logsFolder = logsFolder
        self.destinations = destinations
        self.now = now
    }

    public static func live(folder: DataFolder) -> LogExporter {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        return LogExporter(logsFolder: folder.logs, destinations: downloads + [FileManager.default.temporaryDirectory])
    }

    /// Zip adı: "Nino-kayitlar-<tarih-saat, ':' yerine '-'>.zip".
    public func fileName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return "Nino-kayitlar-" + formatter.string(from: now()).replacingOccurrences(of: ":", with: "-") + ".zip"
    }

    /// Hangi dosyalar girer: adında ".log" geçen düz dosyalar (".1" yedekleri dahil).
    public func logFiles() -> [URL] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: logsFolder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return items.filter { url in
            url.lastPathComponent.contains(".log")
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Zip'i yazar ve yerini döner.
    public func export(details: String) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("nino-kayitlar-\(UUID().uuidString)", isDirectory: true)
        let content = staging.appendingPathComponent("Nino-kayitlar", isDirectory: true)
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for file in logFiles() {
            try fm.copyItem(at: file, to: content.appendingPathComponent(file.lastPathComponent))
        }
        try Data(details.utf8).write(to: content.appendingPathComponent("ayrintilar.txt"))
        let zipped = try Self.zip(content)
        defer { try? fm.removeItem(at: zipped) }
        var lastError: Error = CocoaError(.fileWriteUnknown)
        for folder in destinations {
            let target = folder.appendingPathComponent(fileName())
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: zipped, to: target)
                return target
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Klasörü sistemin kendi yoluyla zip'ler (ek program çalıştırmadan).
    static func zip(_ folder: URL) throws -> URL {
        var result: Result<URL, Error> = .failure(CocoaError(.fileWriteUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
            result = Result { try FileManager.default.copyItem(at: zip, to: copy); return copy }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
