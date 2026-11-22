// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Köşe, ipucu, kart (`ElementTranslator`) ile telefon ve harita kartı (`PhoneTranslator`) çevirileri.
/// Paketteki hazır çeviri önce; kalanı oturumun çevirmeni (önbellek → seçili çeviri zinciri). iOS'ta havuza soru
/// sorulmaz ve bilinmeyen satır havuza bildirilmez (telefon paketi ve kalıcı telefon hafızası yine çalışır).
final class ElementTranslation: GameReading.ElementTranslator, GameReading.PhoneTranslator, @unchecked Sendable {
    private let translator: Translator
    private let packLookup: (@Sendable (String) -> String?)?
    let targetLanguage: String

    init(translator: Translator, packLookup: (@Sendable (String) -> String?)?, targetLanguage: String) {
        self.translator = translator
        self.packLookup = packLookup
        self.targetLanguage = targetLanguage
    }

    // MARK: ElementTranslator

    func known(_ text: String) -> String? { packLookup?(text) }

    /// Hepsi çevrilemezse hata (aday yeniden denenir); çevrilemeyen parça aslıyla kalır.
    func translate(_ texts: [String]) async throws -> [String] {
        var out: [String] = []
        var any = false
        for text in texts {
            let r = await translator.translate(text)
            if r.failed { out.append(text) } else { out.append(r.text); any = true }
        }
        guard any || texts.isEmpty else { throw TranslationProviderError.emptyResult }
        return out
    }

    // MARK: PhoneTranslator

    func known(_ text: String) async -> String? { packLookup?(text) }
    var reportsToPool: Bool { false }
    func report(_ texts: [String]) async {}
    var asksPool: Bool { false }
    func askPool(_ texts: [String], context: [String]) async -> [String?] { texts.map { _ in nil } }

    func translateOnDevice(_ text: String) async throws -> String {
        let r = await translator.translate(text)
        if r.failed { throw TranslationProviderError.emptyResult }
        return r.text
    }
}

/// Yazı tanımayı sarar: süreyi ve "yazı okundu" bilgisini otomatik teşhis bekçisine verir.
struct WatchedTextReader: GameReading.TextReader {
    let base: GameReading.TextReader

    func read(_ frame: GameReading.Frame, area: GameReading.Box, scale: Double) async throws -> [GameReading.Line] {
        let started = ProcessInfo.processInfo.systemUptime
        AppDiagnosis.shared.ocrStarted()
        do {
            let lines = try await base.read(frame, area: area, scale: scale)
            AppDiagnosis.shared.ocrFinished(ms: Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
            if lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) { AppDiagnosis.shared.textSeen() }
            return lines
        } catch {
            AppDiagnosis.shared.ocrFinished(ms: Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
            throw error
        }
    }
}
