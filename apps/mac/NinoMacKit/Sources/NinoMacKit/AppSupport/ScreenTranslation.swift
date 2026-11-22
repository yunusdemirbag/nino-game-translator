// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import Foundation
import NinoCore

// ⌥⌘T "Ekranı çevir" (guncelleme-admin.md §5, okuma-hatti.md §16): oyunun son karesindeki bütün yazılar bir kez
// okunur, NinoCore'un ekranı çevir gruplamasıyla gruplanır, her grup ayrı çevrilir ve TV'de kendi yerinde gösterilir.

public extension AppEngine {
    /// Ekranı çevir (kısayol). Süren iş varsa iptal eder, çeviriler ekrandaysa kaldırır.
    func translateScreen() {}
    /// Çeviri durdu: süren işi iptal eder, çevirileri kaldırır.
    func cancelScreenTranslation() {}
}

public extension AppState {
    func translateScreen() { engine?.translateScreen() }
}

extension LiveEngine {
    public func translateScreen() { support?.screen.toggle() }
    public func cancelScreenTranslation() { support?.screen.cancel() }
}

/// Ekranı çevirin saf kuralları.
public enum ScreenTranslationRules {
    /// TV'ye giden bilgi satırlarının kimliği (altyazılarla karışmasın).
    public static let messageID = 900_001

    public enum Message: Equatable, Sendable {
        case noPicture, translating, noText, failed(String)

        public var key: String {
            switch self {
            case .noPicture: return "support.screen.noPicture"
            case .translating: return "support.screen.translating"
            case .noText: return "support.screen.noText"
            case .failed: return "support.screen.failed %@"
            }
        }

        public var durationMs: Int {
            switch self {
            case .noPicture: return 4_000
            case .translating, .noText: return 2_500
            case .failed: return 4_000
            }
        }
    }

    /// Basınca ne yapılır.
    public enum Press: Equatable, Sendable { case start, cancelRunning, removeShown }

    public static func press(running: Bool, showing: Bool) -> Press {
        if running { return .cancelRunning }
        if showing { return .removeShown }
        return .start
    }

    /// Çevirisi kaynağa (her parçada) ≥ 0,90 benzeyen grup gösterilmez.
    public static func isUnchanged(source: [String], translated: [String]) -> Bool {
        guard !source.isEmpty, source.count == translated.count else { return false }
        return zip(source, translated).allSatisfy { similarity($0, $1) >= 0.90 }
    }

    /// Büyük/küçük harf ve boşluk farkını saymayan düzenleme uzaklığı oranı (1 = aynı).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.lowercased().filter { !$0.isWhitespace }), y = Array(b.lowercased().filter { !$0.isWhitespace })
        if x.isEmpty && y.isEmpty { return 1 }
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = Array(0...y.count), cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Bir grubun parçalarını çevirir: simgeler yer tutucuyla korunur, yalnız simgeden oluşan parça çevrilmez.
    public static func translateGroup(_ group: GameReading.ScreenGroups.Group,
                                      translate: (String) async -> String?) async -> (source: [String], text: [String])? {
        let parts = GameReading.ScreenGroups.parts(group.lines.map(\.text))
        var out: [String] = []
        for part in parts {
            if Task.isCancelled { return nil }
            guard let protected = GameReading.ScreenGroups.protectIcons(part) else {
                out.append(part)
                continue
            }
            guard let t = await translate(protected.text) else { return nil }
            out.append(GameReading.ScreenGroups.restoreIcons(t, icons: protected.icons))
        }
        return (parts, out)
    }
}

/// Ekranı çevir işi (motor başına bir tane).
@MainActor
public final class ScreenTranslator {
    private weak var engine: LiveEngine?
    private var task: Task<Void, Never>?
    public private(set) var showing = false

    public init(engine: LiveEngine) { self.engine = engine }

    public var isRunning: Bool { task != nil }

    public func toggle() {
        guard let engine, engine.state.translation == .on else { return }
        switch ScreenTranslationRules.press(running: task != nil, showing: showing) {
        case .cancelRunning, .removeShown:
            cancel()
        case .start:
            guard let image = engine.state.settingsStatus.lastFrame else {
                message(.noPicture)
                return
            }
            message(.translating)
            task = Task { [weak self] in
                await self?.run(image)
                self?.task = nil
            }
        }
    }

    /// Süren işi iptal eder ve TV'deki çevirileri kaldırır.
    public func cancel() {
        task?.cancel()
        task = nil
        guard let hub = engine?.links.hub else { return }
        showing = false
        Task {
            try? await hub.send(.screenClear)
            try? await hub.clear(id: ScreenTranslationRules.messageID)
        }
    }

    private func run(_ image: CGImage) async {
        guard let engine else { return }
        let ocr = GameReading.OCR(reader: engine.env.textReader, minConfidence: 0.4)
        let lines: [GameReading.Line]
        do {
            lines = try await ocr.read(GameReading.ImageFrame(image), area: .full, deep: false)
        } catch {
            if !Task.isCancelled { message(.failed("\(error)")) }
            return
        }
        guard !Task.isCancelled else { return }
        let groups = GameReading.ScreenGroups.groups(lines)
        guard !groups.isEmpty else {
            message(.noText)
            return
        }
        guard let translator = await engine.session?.currentTranslator else { return }
        // TODO: yapay zekâ motorunda bütün yazılar tek istekte (SubtitleTranslating'de toplu çeviri yok; şimdilik parça parça).
        var items: [ScreenItem] = []
        var letters = 0
        for group in groups {
            let result = await ScreenTranslationRules.translateGroup(group) { text in
                let t = await translator.translate(text)
                return t.failed ? nil : t.text
            }
            if Task.isCancelled { return }
            guard let result, !ScreenTranslationRules.isUnchanged(source: result.source, translated: result.text) else { continue }
            let text = result.text.joined(separator: "\n")
            letters += text.filter(\.isLetter).count
            items.append(ScreenItem(box: NinoBox(group.box), text: text, line: group.lineHeight,
                                    paragraphs: result.text.count > 1 ? true : nil))
        }
        guard !Task.isCancelled else { return }
        guard !items.isEmpty else {
            message(.noText)
            return
        }
        let payload = ScreenPayload(items: items, durationMs: GameReading.ScreenGroups.durationMs(letters: letters))
        do {
            try await engine.links.hub.clear(id: ScreenTranslationRules.messageID)
            try await engine.links.hub.send(.screen(payload))
            showing = true
            engine.subtitleLog.write("Ekranı çevir: \(items.count) grup")
            let duration = payload.durationMs
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(duration))
                self?.showing = false
            }
        } catch {
            message(.failed("\(error)"))
        }
    }

    private func message(_ m: ScreenTranslationRules.Message) {
        guard let engine else { return }
        let language = MainWindowView.interfaceLanguage(for: engine.state.settings.targetLanguage)
        var args: [CVarArg] = []
        if case let .failed(detail) = m { args = [detail] }
        let text = NinoL10n.string(m.key, table: "AppSupport", language: language, arguments: args)
        let payload = ShowPayload(id: ScreenTranslationRules.messageID, text: text, durationMs: m.durationMs)
        let hub = engine.links.hub
        Task { try? await hub.show(payload) }
    }
}
