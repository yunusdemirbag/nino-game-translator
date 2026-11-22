// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
@testable import NinoCore

/// Testler için sahte çevirmen: sözlükten çevirir ya da istenen şekilde başarısız olur.
final class FakeProvider: TranslationProvider, @unchecked Sendable {
    enum Mode { case dictionary([String: String]), fail, echo, empty, slow(Duration), transform(@Sendable (String) -> String) }

    let name: String
    private let mode: Mode
    private let lock = NSLock()
    private var _calls: [String] = []

    var calls: [String] { lock.withLock { _calls } }

    init(_ name: String, _ mode: Mode) {
        self.name = name
        self.mode = mode
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        lock.withLock { _calls.append(text) }
        switch mode {
        case let .dictionary(d):
            guard let t = d[text] else { throw TranslationProviderError.badResponse }
            return t
        case .fail: throw TranslationProviderError.http(500)
        case .echo: return text
        case .empty: return "  "
        case let .slow(d):
            try await Task.sleep(for: d)
            return "geç"
        case let .transform(f): return f(text)
        }
    }
}
