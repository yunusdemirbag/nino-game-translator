// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Okuyucuyu sarar ve macOS'in yazıyı hiç okuyamadığını fark eder (ana-ekran.md §8.2 madde 4: "macOS ekrandaki yazıyı
/// okuyamıyor"). Art arda `threshold` okuma hata verirse (bekçinin "meşgul" / "takıldı" hataları sayılmaz) uyarı açılır;
/// bir okuma başarılı olunca kapanır. Çoğu zaman sebep dolu disktir: Vision boş alan olmadan model açamıyor.
public final class ReadingWatch: GameReading.TextReader, @unchecked Sendable {
    public static let defaultThreshold = 5

    private let base: GameReading.TextReader
    private let threshold: Int
    private let onChange: @Sendable (Bool) -> Void
    private let onText: (@Sendable () -> Void)?
    private var lastTextReport: UInt64 = 0
    private let lock = NSLock()
    private var failures = 0
    private var failing = false

    /// `onText`: okuma boş olmayan metin döndürdü (saniyede en çok bir kez çağrılır).
    public init(base: GameReading.TextReader, threshold: Int = ReadingWatch.defaultThreshold,
                onText: (@Sendable () -> Void)? = nil, onChange: @escaping @Sendable (Bool) -> Void) {
        self.base = base
        self.onText = onText
        self.threshold = max(1, threshold)
        self.onChange = onChange
    }

    public var isFailing: Bool { lock.withLock { failing } }

    public func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        do {
            let lines = try await base.read(frame, area: area, scale: scale)
            note(success: true)
            if let onText, lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let now = DispatchTime.now().uptimeNanoseconds
                let due: Bool = lock.withLock {
                    guard now - lastTextReport >= 1_000_000_000 else { return false }
                    lastTextReport = now
                    return true
                }
                if due { onText() }
            }
            return lines
        } catch let e as GameReading.WatchdogError {
            throw e
        } catch let e as HelperOCRReader.HelperError where Self.isHelperHiccup(e) {
            // Yedek OCR süreci ısınıyor ya da yeniden açılıyor: macOS'in okuyamadığı anlamına gelmez.
            throw e
        } catch {
            note(success: false)
            throw error
        }
    }

    static func isHelperHiccup(_ e: HelperOCRReader.HelperError) -> Bool {
        switch e {
        case .notWarm, .timedOut, .crashed: return true
        case .gaveUp, .badImage, .failed: return false
        }
    }

    private func note(success: Bool) {
        let changed: Bool? = lock.withLock {
            if success {
                failures = 0
                guard failing else { return nil }
                failing = false
                return false
            }
            failures += 1
            guard !failing, failures >= threshold else { return nil }
            failing = true
            return true
        }
        if let changed { onChange(changed) }
    }

    /// Ev klasörünün diskindeki boş alan (GB, önemli kullanım için; ölçülemezse nil).
    public static func freeDiskGB(at url: URL = URL(fileURLWithPath: NSHomeDirectory())) -> Double? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(bytes) / 1_000_000_000
    }
}
