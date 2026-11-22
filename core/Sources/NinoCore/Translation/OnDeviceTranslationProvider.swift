// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

#if canImport(Translation)
import Foundation
import Translation

/// Apple'ın cihaz içi çevirisi (Translation çerçevesi). Ücretsiz, internetsiz.
/// Dil paketi cihazda yüklü olmalıdır; değilse hata verir ve zincir sıradakine geçer.
@available(macOS 26.0, iOS 26.0, *)
public actor OnDeviceTranslationProvider: TranslationProvider {
    public nonisolated let name = "device"
    private var sessions: [String: TranslationSession] = [:]

    public init() {}

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let key = "\(source)>\(target)"
        let session: TranslationSession
        if let existing = sessions[key] {
            session = existing
        } else {
            session = TranslationSession(installedSource: Locale.Language(identifier: source),
                                         target: Locale.Language(identifier: target))
            sessions[key] = session
        }
        do {
            return try await session.translate(text).targetText
        } catch {
            sessions[key] = nil
            throw error
        }
    }

    /// Dil çifti bu cihazda kullanıma hazır mı?
    public static func isInstalled(from source: String, to target: String) async -> Bool {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                         to: Locale.Language(identifier: target))
        return status == .installed
    }
}
#endif

/// Bu cihazda varsa cihaz içi çevirmen.
public func makeOnDeviceTranslationProvider() -> TranslationProvider? {
    #if canImport(Translation)
    if #available(macOS 26.0, iOS 26.0, *) { return OnDeviceTranslationProvider() }
    #endif
    return nil
}
