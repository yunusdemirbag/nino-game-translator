// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// Kullanıcının kendi anahtarıyla çalışan çevrimiçi çeviri motorları. Çevrimiçi çeviri kapalıysa ya da anahtar yoksa
/// yalnız Apple'ın cihaz içi çevirisi kullanılır.
enum TranslationEngines {
    static func keyAccount(_ engine: TranslationEngine) -> String {
        switch engine {
        case .deepL: Keys.deepLKey
        case .gemini: Keys.geminiKey
        case .openAI: Keys.openAIKey
        case .claude: Keys.claudeKey
        case .local: Keys.localAIKey
        }
    }

    static func displayName(_ engine: TranslationEngine) -> String {
        switch engine {
        case .deepL: "DeepL"
        case .gemini: "Gemini"
        case .openAI: "OpenAI"
        case .claude: "Claude"
        case .local: L("engine.local")
        }
    }

    static func key(_ engine: TranslationEngine, store: SecureStore) -> String? {
        guard let k = store.load(String.self, for: keyAccount(engine)), !k.isEmpty else { return nil }
        return k
    }

    private static func prompt(_ settings: AppSettings) -> String {
        let name = Languages.choice(settings.targetLanguage)?.englishName ?? "Turkish"
        return "Translate this English video game subtitle into natural \(name). Reply with the translation only.\\n\\n{text}"
    }

    /// Seçili motorun HTTP tarifi (yalnız çevrimiçi çeviri açık ve anahtar kayıtlıysa).
    static func configurations(for settings: AppSettings, store: SecureStore) -> [HTTPTranslationProvider.Configuration] {
        guard settings.onlineTranslation else { return [] }
        let engine = settings.onlineEngine
        guard engine == .local || key(engine, store: store) != nil else { return [] }
        let target = Languages.normalized(settings.targetLanguage)
        switch engine {
        case .deepL:
            let free = key(.deepL, store: store)?.hasSuffix(":fx") ?? true
            return [.init(name: "deepl",
                          urlTemplate: free ? "https://api-free.deepl.com/v2/translate" : "https://api.deepl.com/v2/translate",
                          headers: ["Content-Type": "application/json", "Authorization": "DeepL-Auth-Key {key}"],
                          bodyTemplate: #"{"text":["{text}"],"source_lang":"EN","target_lang":"\#(target.uppercased())"}"#,
                          responsePath: ["translations", "0", "text"])]
        case .gemini:
            return [.init(name: "gemini",
                          urlTemplate: "https://generativelanguage.googleapis.com/v1beta/models/\(settings.geminiModel):generateContent?key={key}",
                          bodyTemplate: #"{"contents":[{"parts":[{"text":"\#(prompt(settings))"}]}]}"#,
                          responsePath: ["candidates", "0", "content", "parts", "0", "text"])]
        case .openAI:
            return [.init(name: "openai",
                          urlTemplate: "https://api.openai.com/v1/chat/completions",
                          headers: ["Content-Type": "application/json", "Authorization": "Bearer {key}"],
                          bodyTemplate: #"{"model":"\#(settings.openAIModel)","messages":[{"role":"user","content":"\#(prompt(settings))"}]}"#,
                          responsePath: ["choices", "0", "message", "content"])]
        case .local:
            let base = settings.localAIBaseURL.hasSuffix("/") ? String(settings.localAIBaseURL.dropLast()) : settings.localAIBaseURL
            return [.init(name: "local",
                          urlTemplate: base + "/chat/completions",
                          headers: ["Content-Type": "application/json", "Authorization": "Bearer {key}"],
                          bodyTemplate: #"{"model":"\#(settings.localAIModel)","messages":[{"role":"user","content":"\#(prompt(settings))"}]}"#,
                          responsePath: ["choices", "0", "message", "content"])]
        case .claude:
            // Bu sürümde henüz yok; cihaz içi çeviri kullanılır.
            return []
        }
    }

    /// Anahtarı kısa bir deneme çevirisiyle sınar. "Kota dolu" (429) da kabul edilir.
    static func check(key: String, engine: TranslationEngine, settings: AppSettings) async -> Bool {
        var s = settings
        s.onlineTranslation = true
        s.onlineEngine = engine
        let store = MemoryStore()
        store.save(key, for: keyAccount(engine))
        guard let config = configurations(for: s, store: store).first else { return false }
        let provider = HTTPTranslationProvider(configuration: config, apiKey: key)
        do {
            _ = try await provider.translate("Hello", from: "en", to: Languages.normalized(s.targetLanguage))
            return true
        } catch TranslationProviderError.http(let code) {
            return code == 429
        } catch {
            return false
        }
    }

    /// Çekirdeğin sağlayıcı anahtarlarını okuduğu depo.
    static func secrets(for settings: AppSettings, store: SecureStore) -> SecretStore {
        var values: [String: String] = [:]
        for config in configurations(for: settings, store: store) {
            values[NinoSettings.secretAccount(forProvider: config.name)] = key(settings.onlineEngine, store: store) ?? ""
        }
        return MemorySecretStore(values)
    }
}
