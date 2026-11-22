// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bir çevirmen sağlayıcısı. Metni bir dilden ötekine çevirir.
public protocol TranslationProvider: Sendable {
    /// Genel ad (ör. "http-1"). Marka adı kullanılmaz.
    var name: String { get }
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}

public enum TranslationProviderError: Error, Equatable {
    case timeout
    case emptyResult
    case badResponse
    case http(Int)
}

/// Sağlayıcıları sırayla dener. Başarısız olan sıradakine bırakır; art arda
/// hata veren ya da zaman aşımına uğrayan bir süre dinlenmeye alınır.
public actor ProviderChain {
    public let providers: [TranslationProvider]
    public let timeout: Duration
    public let failureLimit: Int
    public let cooldown: TimeInterval
    private let now: @Sendable () -> Date
    private var failures: [String: Int] = [:]
    private var restingUntil: [String: Date] = [:]

    public init(providers: [TranslationProvider],
                timeout: Duration = .seconds(3),
                failureLimit: Int = 3,
                cooldown: TimeInterval = 60,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.providers = providers
        self.timeout = timeout
        self.failureLimit = failureLimit
        self.cooldown = cooldown
        self.now = now
    }

    /// Şu an dinlenmekte olan sağlayıcılar.
    public func resting() -> [String] {
        let t = now()
        return providers.map(\.name).filter { (restingUntil[$0] ?? .distantPast) > t }
    }

    /// İlk geçerli çeviriyi ve sağlayıcının adını döner. `accept` sonucu
    /// reddederse (ör. yer tutucu kayıp) sıradakine geçilir.
    public func translate(_ text: String, from source: String, to target: String,
                          accept: @Sendable (String) -> Bool = { _ in true }) async -> (text: String, provider: String)? {
        for provider in providers {
            if let until = restingUntil[provider.name], until > now() { continue }
            do {
                let result = try await withTimeout(timeout) {
                    try await provider.translate(text, from: source, to: target)
                }
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                // Boş, aynı ya da reddedilen sonuç sıradakine bırakılır ama sağlayıcıyı
                // dinlenmeye almaz ("Hmm." gibi satırlar haklı olarak aynı dönebilir).
                guard !trimmed.isEmpty, trimmed != text.trimmingCharacters(in: .whitespacesAndNewlines),
                      accept(trimmed) else {
                    continue
                }
                failures[provider.name] = 0
                return (trimmed, provider.name)
            } catch {
                recordFailure(provider.name)
            }
        }
        return nil
    }

    private func recordFailure(_ name: String) {
        let n = (failures[name] ?? 0) + 1
        failures[name] = n
        if n >= failureLimit {
            restingUntil[name] = now().addingTimeInterval(cooldown)
            failures[name] = 0
        }
    }
}

/// İşi süre sınırıyla çalıştırır; süre dolarsa `timeout` hatası verir.
func withTimeout<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw TranslationProviderError.timeout
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TranslationProviderError.timeout }
        return first
    }
}
