// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Zincirin son halkası: satırı ortak havuzun sunucusuna sorar (sunucudaki ücretsiz çeviri, ceviri.md §1.2).
///
/// Anahtar yokken ya da cihaz içi çeviri çalışmazken (dil paketi eksik, macOS 26'dan eski) çeviri durmasın diye
/// vardır. `LibraryTranslator` havuz öncelikli olmayan oyunlarda sunucuya yalnız arka planda sorar; cevap ancak satır
/// bir daha gelince işe yarar. Bu halka aynı soruyu (uçuştaki istek paylaşılır) süreli bekler.
///
/// - "Ortak havuz" kapalıysa `PoolClient.ask` sormaz (kullanıcının kararı korunur).
/// - Cevap gelmezse boş döner: `ProviderChain` boş sonucu atlar ama halkayı dinlenmeye almaz.
/// - Yer tutuculu metin (`⟦0⟧`) sunucuya gitmez: sunucu onları bilmez.
public struct PoolFallbackProvider: TranslationProvider {
    public let pool: PoolClient
    /// Sorunun en çok bekleyeceği süre; nil ise sunucunun havuz öncelikli süresi (varsayılan 1,5 sn).
    public let deadline: Duration?

    public var name: String { "pool" }

    public init(pool: PoolClient, deadline: Duration? = nil) {
        self.pool = pool
        self.deadline = deadline
    }

    public func translate(_ text: String, from source: String, to target: String) async throws -> String {
        guard source == "en", !text.contains("⟦") else { return "" }
        let wait: Duration
        if let deadline { wait = deadline } else { wait = await pool.poolFirstDeadline }
        return await pool.ask(text, game: nil, deadline: wait) ?? ""
    }
}
