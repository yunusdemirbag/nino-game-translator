// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Anahtar denemesinin sonucu.
public enum KeyCheckResult: String, Equatable, Sendable {
    case valid, quotaExhausted, modelRejected, invalidKey, unreachable

    /// Geçerli, kotası bitmiş ya da modeli reddedilmiş anahtar kaydedilir.
    public var shouldSave: Bool { self == .valid || self == .quotaExhausted || self == .modelRejected }
}

/// Kaydetmeden önce anahtarı örnek satırla dener. Dakikalık hak yemez,
/// hizmeti dinlenmeye almaz.
public enum KeyCheck {
    /// Etiket çevrilmez; yalnız cümle gider.
    public static let sampleLine = "BATMAN: I'm Batman."
    public static let sampleSentence = "I'm Batman."

    public static func result(for error: Error) -> KeyCheckResult {
        switch error as? ProviderFailure {
        case .invalidKey?: return .invalidKey
        case .quotaExhausted?: return .quotaExhausted
        case .minuteLimit?: return .valid  // anahtar çalışıyor, yalnız şu dakika dolu
        case .modelRejected?: return .modelRejected
        default: return .unreachable
        }
    }

    /// Yapay zekâ anahtarı. Yerel model denemesinde zaman aşımı 90 sn.
    public static func run(_ provider: AIProvider, target: String = "tr") async -> KeyCheckResult {
        do {
            _ = try await provider.translate(sentences: [sampleSentence], context: [], game: nil, target: target, probe: true)
            return .valid
        } catch {
            return result(for: error)
        }
    }

    public static func run(_ provider: DeepLProvider, target: String = "tr") async -> KeyCheckResult {
        do {
            _ = try await provider.translate(sentences: [sampleSentence], context: [], target: target, probe: true)
            return .valid
        } catch {
            return result(for: error)
        }
    }

    /// Yerel model denemesi için yapılandırma (90 sn).
    public static func probeConfig(_ config: AIProviderConfig) -> AIProviderConfig {
        var c = config
        if c.service == .local { c.timeout = 90 }
        return c
    }
}
