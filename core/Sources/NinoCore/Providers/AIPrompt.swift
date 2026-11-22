// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Bağlam satırı: bu satırdan önce gösterilen altyazı ve (biliniyorsa) çevirisi.
public struct ContextLine: Equatable, Sendable {
    public let english: String
    public let translation: String?

    public init(_ english: String, _ translation: String? = nil) {
        self.english = english
        self.translation = translation
    }
}

/// Yapay zekâ çevirmenlerine giden metinler.
public enum AIPrompt {
    /// Hedef dile göre sistem yönergesi.
    public static func system(for language: TargetLanguage) -> String {
        let name = language.promptName
        if language.code == "tr" {
            return """
            You translate video game subtitles into natural, everyday spoken Turkish.
            - Characters talk to each other with "sen" unless the scene is clearly formal.
            - Keep names of people and places, and speaker labels such as "NADIA:", exactly as written.
            - Keep the line breaks of each string.
            - Keep placeholders such as ⟦T1⟧ (controller button icons) exactly as written, once, where the button belongs.
            - Keep the meaning and the tone. Do not add or leave out anything.
            - Spell correctly. Game words written with a capital letter (Journal, Map, Camp) are ordinary nouns in \
            Turkish: write them in lower case with the suffix joined (günlüğüne, haritada). Use an apostrophe only \
            after real names of people or places (Arthur'a).
            - Follow vowel harmony and consonant changes in suffixes.
            - Output only the translation, never an explanation.
            """
        }
        var rules = """
        You translate video game subtitles into \(name).
        - Keep names of people and places, and speaker labels such as "NADIA:", exactly as written.
        - Keep the line breaks of each string.
        - Keep placeholders such as ⟦T1⟧ (controller button icons) exactly as written, once, where the button belongs.
        - Keep the meaning and the tone. Do not add or leave out anything.
        - Output only the translation, never an explanation.
        """
        if language.code == "ar" {
            rules = """
            You translate video game subtitles into short, easy to read Modern Standard Arabic.
            - Keep names and speaker labels such as "NADIA:" in Latin letters, exactly as written.
            - Use Arabic punctuation (، ؟ ؛) and Western digits.
            - Keep controller symbols (✕ ○ △ □, L1, R2) as they are.
            - Keep the line breaks of each string.
            - Keep placeholders such as ⟦T1⟧ (controller button icons) exactly as written, once, where the button belongs.
            - Keep the meaning and the tone. Do not add or leave out anything.
            - Output only the translation, never an explanation.
            """
        }
        return rules
    }

    /// Kullanıcı iletisi: oyun satırı, bağlam, istek ve JSON dizisi; bloklar arasında boş satır.
    public static func user(sentences: [String], context: [ContextLine], game: String?, language: TargetLanguage) -> String {
        var blocks: [String] = []
        if let game, !game.isEmpty { blocks.append("Game: \(game)") }
        if !context.isEmpty {
            var lines = ["Earlier subtitles, given only as context (do not translate these again):"]
            for c in context {
                lines.append("English: \(c.english)")
                if let t = c.translation { lines.append("\(language.promptName): \(t)") }
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        let json = String(decoding: ProviderJSON.body(sentences), as: UTF8.self)
        blocks.append("""
        Translate every string in the JSON array below into \(language.promptName). Answer with a JSON array of \
        exactly \(sentences.count) \(language.promptName) strings in the same order, and nothing else.
        \(json)
        """)
        return blocks.joined(separator: "\n\n")
    }

    /// Çeviri için eğitilmiş yerel model mi (yönerge ve JSON gönderilmez)?
    public static func isTranslationModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("translategemma") || m.contains("milmmt")
    }

    /// Çeviri modelinin kendi kalıbıyla tek metin.
    static func translationModelText(_ text: String, model: String, language: TargetLanguage) -> String {
        if model.lowercased().contains("milmmt") {
            return "Translate this from English to \(language.promptName):\nEnglish: \(text)\n\(language.promptName):"
        }
        return """
        You are a professional English (en) to \(language.promptName) (\(language.code)) translator. Carry over the \
        meaning and nuance of the English text faithfully. Reply with the \(language.promptName) translation only, \
        without any comment. Translate this text:


        \(text)
        """
    }

    /// Çeviri modeli iletileri: önceki satırlar soru/cevap çifti, sonra cümleler satır satır.
    static func translationModelMessages(sentences: [String], context: [ContextLine], model: String,
                                         language: TargetLanguage) -> [[String: String]] {
        var out: [[String: String]] = []
        for c in context {
            guard let t = c.translation else { continue }
            out.append(["role": "user", "content": translationModelText(c.english, model: model, language: language)])
            out.append(["role": "assistant", "content": t])
        }
        let text = sentences.map { $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
        out.append(["role": "user", "content": translationModelText(text, model: model, language: language)])
        return out
    }
}
