// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import CoreGraphics
import Foundation
import NinoCore

/// Ekrandan oyun tanımanın zamanlaması (havuz-paketler.md §6 "Ekrandan oyun tanıma", ninoya-sor.md §6 madde 4).
/// - Oyun bilinmiyorsa (ya da yalnız son oynanan tahmini varsa): çeviri başladıktan 8 sn sonra, sonra 60 sn arayla,
///   en çok 6 deneme. Hızlı yerel tanıma ayrıca ilk 10 sn her karede yapılır (`QuickGameSense`, GameAuto.swift).
/// - Ekrandan tanındıysa: 5 dk sonra bir kez doğrulama, sonra 20 dk'da bir (en çok 12).
/// - Konsol, kullanıcı ya da paket söylüyorsa bakılmaz.
public struct IdentifySchedule: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case unknown, screen, none }

    public static let firstDelay: TimeInterval = 8
    public static let unknownInterval: TimeInterval = 60
    public static let unknownLimit = 6
    public static let verifyDelay: TimeInterval = 300
    public static let verifyInterval: TimeInterval = 1_200
    public static let verifyLimit = 12

    public private(set) var started: Date?
    public private(set) var unknownAttempts = 0
    public private(set) var verifyAttempts = 0
    public private(set) var lastAttempt: Date?
    public private(set) var screenSince: Date?

    public init() {}

    public mutating func start(at date: Date) {
        self = IdentifySchedule()
        started = date
    }

    /// Oyun ekrandan tanındı (yerel işaretler ya da sunucu): doğrulama sayacı baştan.
    public mutating func noteScreenRecognized(at date: Date) {
        screenSince = date
        verifyAttempts = 0
    }

    public func isDue(_ mode: Mode, now: Date) -> Bool {
        guard let started else { return false }
        switch mode {
        case .none: return false
        case .unknown:
            guard unknownAttempts < Self.unknownLimit else { return false }
            if unknownAttempts == 0 { return now.timeIntervalSince(started) >= Self.firstDelay }
            return now.timeIntervalSince(lastAttempt ?? started) >= Self.unknownInterval
        case .screen:
            guard verifyAttempts < Self.verifyLimit else { return false }
            let since = screenSince ?? started
            if verifyAttempts == 0 { return now.timeIntervalSince(since) >= Self.verifyDelay }
            return now.timeIntervalSince(lastAttempt ?? since) >= Self.verifyInterval
        }
    }

    public mutating func markAttempt(_ mode: Mode, at date: Date) {
        lastAttempt = date
        switch mode {
        case .unknown: unknownAttempts += 1
        case .screen: verifyAttempts += 1
        case .none: break
        }
    }
}

/// `POST /v1/identify`: Remote Play karesi → oyunun adı (30 sn).
public struct GameIdentifyClient: Sendable {
    public static let timeout: TimeInterval = 30
    public static let maxWidth = 768
    /// Sunucu (`IDENTIFY_LIMITS`): gövde en çok 600 KB, resim en çok 450 KB. 440 KB'lık JPEG base64 ile ~587 KB olur;
    /// JSON zarfıyla birlikte 600 KB'ın altında kalır (450 KB'lık JPEG tek başına 600 KB eder, 413 alırdı).
    public static let maxBytes = 440 * 1024
    public static let maxBodyBytes = 600 * 1024

    public var network: NetworkClient
    public var baseURL: URL
    public var appVersion: String
    public var install: String

    public init(network: NetworkClient, baseURL: URL, appVersion: String, install: String) {
        self.network = network
        self.baseURL = baseURL
        self.appVersion = appVersion
        self.install = install
    }

    /// Kare en çok 768 px genişliğe küçültülür, JPEG 0,6; 440 KB'ı aşarsa kalite düşürülür, yine aşarsa gönderilmez.
    public static func jpeg(_ image: CGImage) -> Data? {
        let scale = min(1, Double(maxWidth) / Double(max(1, image.width)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: small)
        for quality in [0.6, 0.45, 0.3] {
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]), data.count <= maxBytes {
                return data
            }
        }
        return nil
    }

    public func body(jpeg: Data) throws -> Data {
        try ContractJSON.encode(["v": 1, "install": install, "app": appVersion, "platform": "mac",
                                 "image": jpeg.base64EncodedString()])
    }

    /// Tanınan oyunun adı; tanınamazsa ya da ulaşılamazsa nil.
    public func identify(_ image: CGImage) async -> String? {
        guard let data = Self.jpeg(image), let body = try? body(jpeg: data), body.count <= Self.maxBodyBytes else { return nil }
        var request = URLRequest(url: PoolServer.endpoint(baseURL, "v1/identify"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await network.send(request), response.statusCode == 200 else { return nil }
        return Self.game(from: data)
    }

    public static func game(from data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (o["game"] as? String).map(GameTracker.cleanName), !name.isEmpty else { return nil }
        return name
    }
}

extension LiveEngine {
    /// Bu an hangi tanıma işi (oyun bilinmiyor / ekrandan tanındı / bakılmaz).
    var identifyMode: IdentifySchedule.Mode {
        let s = state.settings
        guard s.sharePool, s.sourceLanguage == "en", env.network != nil, env.poolBaseURL != nil else { return .none }
        switch games.evidence {
        case nil, .lastPlayed?: return .unknown
        default: break
        }
        if Self.packsEnabled(s), state.game?.poolFirst == true { return .none }
        switch games.evidence {
        case .screen?: return .screen
        default: return .none
        }
    }

    /// Zamanı geldiyse son kare sunucuya gönderilir.
    func identifyIfDue(now: Date = Date()) {
        let mode = identifyMode
        guard identifySchedule.isDue(mode, now: now), let network = env.network, let base = env.poolBaseURL,
              let frame = state.settingsStatus.lastFrame else { return }
        identifySchedule.markAttempt(mode, at: now)
        let client = GameIdentifyClient(network: network, baseURL: base, appVersion: env.appVersion, install: installID)
        let token = sessionToken
        Task {
            guard let name = await client.identify(frame), token == self.sessionToken else { return }
            self.screenIdentified(name)
        }
    }

    /// Ekran oyunu söyledi (sunucu, menü/telefon ya da hızlı işaretler): aynıysa doğrulandı, değilse sessizce geçilir.
    func screenIdentified(_ name: String, how: String? = nil) {
        let before = games.current, beforeEvidence = games.evidence
        games.screenRecognized(name)
        if before?.id != games.current?.id || before == nil || beforeEvidence != games.evidence {
            identifySchedule.noteScreenRecognized(at: Date())
            let detail = how.map { " (\($0))" } ?? ""
            if let b = before, b.id != games.current?.id {
                subtitleLog.write("Oyun ekrandan tanındı: \(name)\(detail); \(b.name) yerine geçildi")
            } else {
                subtitleLog.write("Oyun ekrandan tanındı: \(name)\(detail)")
            }
            gameChanged()
        }
    }
}
