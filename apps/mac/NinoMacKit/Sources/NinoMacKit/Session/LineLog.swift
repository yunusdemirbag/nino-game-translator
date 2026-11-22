// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import NinoCore

/// `altyazi.log` satırları: her altyazı satırının yolculuğu aynı `#n` numarasıyla (okundu → çeviri → gösterildi →
/// kalktı ya da atıldı) ve ekran öğeleri için kısa tek satır. Bu metinler yalnız yerel günlüğe yazılır; ölçüme ve
/// otomatik teşhise hiçbir zaman girmez.
enum LineLogText {
    static func read(id: Int, text: String, kind: LineTrace.ReadKind) -> String {
        switch kind {
        case .new: return "#\(id) okundu \(RotatingLog.quote(text)) → çeviriye"
        case .updated: return "#\(id) okundu (uzadı) \(RotatingLog.quote(text)) → çeviriye"
        case .corrected: return "#\(id) okundu (düzeldi) \(RotatingLog.quote(text)) → çeviriye"
        case .restored: return "#\(id) yeniden okundu \(RotatingLog.quote(text)) (önceki çeviri)"
        }
    }

    /// Kaynak adı: paket, havuz, önbellek, seçili motor (deepl, gemini…) ya da cihaz içi çeviri.
    static func origin(_ o: LiveLine.Origin, engine: MacSettings.OnlineEngine?) -> String {
        switch o {
        case .pack: return "paket"
        case .pool: return "havuz"
        case .cache: return "önbellek"
        case .engine: return engine?.rawValue ?? "cihaz"
        case .untranslated: return "yok"
        }
    }

    static func translated(id: Int, origin: String, ms: Int, text: String) -> String {
        "#\(id) çeviri: \(origin) \(ms) ms \(RotatingLog.quote(text))"
    }

    /// Çeviri başarısız: hiçbir kaynak sonuç vermedi; çevrimiçi motorun bilinen sorunu varsa o da yazılır.
    static func failed(id: Int, ms: Int, problem: OnlineEngineProblem?) -> String {
        var why = "hiçbir kaynak çeviremedi"
        if let problem { why += ", \(problem.engine.rawValue) sorunu: \(problem.kind)" }
        return "#\(id) çeviri: başarısız \(ms) ms (\(why))"
    }

    static func shown(id: Int, tvCount: Int, computer: Bool) -> String {
        var places = ["TV \(tvCount)"]
        if computer { places.append("bilgisayar") }
        return "#\(id) gösterildi (\(places.joined(separator: ", ")))"
    }

    static func cleared(id: Int, shownMs: Int?) -> String {
        guard let shownMs else { return "#\(id) kalktı" }
        return "#\(id) kalktı (\(shownMs) ms)"
    }

    static func dropped(id: Int, reason: LineTrace.DropReason) -> String {
        let why: String
        switch reason {
        case .newerShown: why = "daha yeni satır gösterildi"
        case .late: why = "satır ekrandan kalktı, çeviri geç kaldı"
        case .superseded: why = "yerine düzelmiş ya da uzamış okuma geçti"
        case .noTranslation: why = "çeviri yok"
        case .alreadyTarget: why = "zaten hedef dilde"
        case .reset: why = "hat sıfırlandı"
        }
        return "#\(id) atıldı (\(why))"
    }

    static func kind(_ k: GameReading.ScreenElement.Kind) -> String {
        switch k {
        case .corner: return "köşe"
        case .questStrip: return "görev şeridi"
        case .hint: return "tuş ipucu"
        case .messageCard: return "mesaj kartı"
        case .callCard: return "arama kartı"
        case .extraArea: return "ek alan"
        case .menu: return "menü"
        case .phone: return "telefon"
        case .map: return "harita"
        }
    }

    /// Ekran öğeleri tek satırda: türler ve kısa metinler.
    static func elements(_ list: [GameReading.ScreenElement]) -> String {
        guard !list.isEmpty else { return "Ekran öğeleri kalktı" }
        // Tuş simgesi yer tutucusu okunur biçimde (`⟦T1⟧` → `[→]`).
        let items = list.prefix(6).map { "\(kind($0.kind)) \(RotatingLog.quote(IconPlaceholders.readable($0.text, icons: $0.icons), limit: 40))" }
        let more = list.count > 6 ? " +\(list.count - 6)" : ""
        return "Ekran öğeleri (\(list.count)): " + items.joined(separator: ", ") + more
    }

    static func region(id: String, text: String) -> String {
        text.isEmpty ? "Ek alan \(id) kalktı" : "Ek alan \(id): \(RotatingLog.quote(text, limit: 60))"
    }
}

extension LiveEngine {
    /// Satırın yolculuğunu `altyazi.log`'a yazar.
    func logTrace(_ t: LineTrace) {
        switch t {
        case let .read(id, text, kind):
            subtitleLog.write(LineLogText.read(id: id, text: text, kind: kind))
        case let .translated(id, origin, ms, text):
            subtitleLog.write(LineLogText.translated(id: id, origin: LineLogText.origin(origin, engine: activeOnlineEngine),
                                                     ms: ms, text: text))
        case let .translationFailed(id, ms):
            subtitleLog.write(LineLogText.failed(id: id, ms: ms, problem: state.onlineEngineProblem))
        case let .cleared(id, shownMs):
            subtitleLog.write(LineLogText.cleared(id: id, shownMs: shownMs))
        case let .dropped(id, reason):
            subtitleLog.write(LineLogText.dropped(id: id, reason: reason))
        case let .note(text):
            subtitleLog.write(text)
        }
    }

    /// "#n gösterildi": kaç TV'ye ve bilgisayardaki pencereye.
    func logShown(id: Int) {
        let computer = state.settings.output != .tv
        subtitleLog.write(LineLogText.shown(id: id, tvCount: state.connectedDisplays, computer: computer))
    }
}
