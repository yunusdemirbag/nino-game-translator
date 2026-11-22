// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bir yapay zekâ hizmetinin modeli.
public struct AIModel: Equatable, Hashable, Sendable {
    /// Hizmetteki model adı.
    public let id: String
    /// Ayarlarda görünen ad (yerelleştirme anahtarı).
    public let label: String
    /// OpenAI'da `reasoning_effort`, Claude'da `output_config.effort`.
    public let effort: String?
    /// Gemini'de `thinkingConfig.thinkingLevel`, Claude'da `thinking.type`.
    public let thinking: String?
    /// Ücretsiz anahtarla kullanılabilir mi?
    public let freeTier: Bool
    /// Uygulamanın dakikada gönderdiği en çok istek; `nil` sınırsız.
    public let requestsPerMinute: Int?

    public init(id: String, label: String? = nil, effort: String? = nil, thinking: String? = nil,
                freeTier: Bool = false, requestsPerMinute: Int? = nil) {
        self.id = id
        self.label = label ?? id
        self.effort = effort
        self.thinking = thinking
        self.freeTier = freeTier
        self.requestsPerMinute = requestsPerMinute
    }
}

/// Hizmet → model listesi. İlk model varsayılandır. Kullanıcı bulut modelinin
/// adını yazamaz, listeden seçer.
public struct ModelCatalog: Equatable, Sendable {
    public let services: [String: [AIModel]]

    public init(services: [String: [AIModel]]) { self.services = services }

    /// Biçim: `{"nino-models":1,"services":{"<hizmet>":[{"id":…},…]}}`. Dizi olmayan
    /// alanlar (`_note` gibi) ve `id`'siz modeller atlanır.
    public static func parse(_ data: Data) -> ModelCatalog? {
        guard let root = ProviderJSON.object(Data(Glossary.relaxedJSON(String(decoding: data, as: UTF8.self)).utf8)) as? [String: Any],
              let services = root["services"] as? [String: Any] else { return nil }
        var out: [String: [AIModel]] = [:]
        for (name, value) in services {
            guard let list = value as? [Any] else { continue }
            out[name] = list.compactMap { item in
                guard let m = item as? [String: Any], let id = m["id"] as? String, !id.isEmpty else { return nil }
                return AIModel(id: id, label: m["label"] as? String, effort: m["effort"] as? String,
                               thinking: m["thinking"] as? String, freeTier: m["freeTier"] as? Bool ?? false,
                               requestsPerMinute: m["requestsPerMinute"] as? Int)
            }
        }
        return ModelCatalog(services: out)
    }

    public func models(for service: AIService) -> [AIModel] { services[service.rawValue] ?? [] }

    public func defaultModel(for service: AIService) -> AIModel? { models(for: service).first }

    /// Kayıtlı model listede yoksa varsayılan.
    public func resolve(_ service: AIService, saved: String?) -> AIModel? {
        let list = models(for: service)
        return list.first { $0.id == saved } ?? list.first
    }

    public static let builtin: ModelCatalog = parse(Data(builtinJSON.utf8)) ?? ModelCatalog(services: [:])

    static let builtinJSON = #"""
    {
      "nino-models": 1,
      "services": {
        "_note": "İlk model varsayılandır. requestsPerMinute uygulamanın kendi sınırıdır.",
        "gemini": [
          { "id": "gemini-3.5-flash-lite", "label": "models.gemini.flashLite", "freeTier": true, "requestsPerMinute": 15 },
          { "id": "gemini-3.6-flash", "label": "models.gemini.flash", "thinking": "LOW", "freeTier": true, "requestsPerMinute": 10 }
        ],
        "openai": [],
        "claude": [
          { "id": "claude-haiku-5-5", "label": "models.claude.haiku", "effort": "low" },
          { "id": "claude-sonnet-5-5", "label": "models.claude.sonnet", "effort": "low" }
        ]
      }
    }
    """#
}
