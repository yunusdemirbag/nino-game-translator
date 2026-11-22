// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Okuma neden atlandı / satır neden atıldı (oyun-okuma.md "Teşhis notları")

extension GameReading.Output {
    /// Bu karede okunan yazı neden altyazı olmadı. Yalnız yerel günlük içindir; metin kısaltılır.
    public struct Note: Equatable, Sendable {
        public enum Reason: Equatable, Hashable, Sendable {
            /// Menü bayrağı açık (menü ekranı tanındı).
            case menu
            /// Okuyucu meşguldü (bekçi): kare okunmadı.
            case busy
            /// İz aynı göründüğü için son okuma kullanıldı; yeni satır süre sınırıyla geç okundu (`delayMs`).
            case staticFrame(delayMs: Int)
            /// Telefon oyunu: küçük harfle başlayan blok (önceki altyazının devamı değil).
            case lowercase
            case messageList
            case callCard
            case callName
            case messageCard
            case cardRepeat
            case giant
            /// 9 sn'den uzun duran yazı (yanında yeni yazı varken).
            case stale
            /// Konuşmaya benzeyen satır sessiz bir süzgeçte kayboldu (adım adı).
            case filtered(String)
            /// Yazı tanıma hata verdi (bekçinin "meşgul"ü dışında); kare boş sayıldı.
            case readError
            /// Küçük harfle başlayan satır kararlı görünene dek bekletiliyor (belirirken kısmi okuma olabilir).
            case lowercaseWaiting
            /// "Yalnız altyazıyı çevir" bir satırı attı.
            case subtitlesOnly(GameReading.Filters.SubtitlesOnly.Drop)
        }

        public var reason: Reason
        /// Atılan yazı (en çok 60 karakter).
        public var text: String?

        public init(_ reason: Reason, text: String? = nil) {
            self.reason = reason
            self.text = text.map { $0.count > 60 ? String($0.prefix(59)) + "…" : $0 }
        }

        /// Günlükteki kısa ad.
        public var label: String {
            switch reason {
            case .menu: return "atlandı: menü"
            case .busy: return "atlandı: okuyucu meşgul"
            case let .staticFrame(ms): return "geç okundu: sabit görüntü (\(ms) ms)"
            case .lowercase: return "atıldı: küçük harfle başlayan blok"
            case .messageList: return "atıldı: mesaj listesi"
            case .callCard: return "atıldı: arama kartı"
            case .callName: return "atıldı: arama kartındaki ad"
            case .messageCard: return "atıldı: mesaj kartı"
            case .cardRepeat: return "atıldı: mesaj kartının tekrarı"
            case .giant: return "atıldı: dev blok"
            case .stale: return "atıldı: eski duran yazı"
            case let .subtitlesOnly(d): return "atıldı: yalnız-altyazı (\(d.label))"
            case let .filtered(stage): return "atıldı: \(stage)"
            case .readError: return "atlandı: okuma hatası"
            case .lowercaseWaiting: return "bekliyor: küçük harfle başlayan satır"
            }
        }

        /// Art arda aynı neden tek satırda toplanır (gecikme süresi farklı olsa da).
        var runKey: String {
            if case .staticFrame = reason { return "static" }
            return label
        }
    }
}

extension GameReading {
    /// Teşhis notlarını günlük satırına çevirir. Aynı neden art arda gelirse yalnız ilki yazılır; neden değişince ya da
    /// `gapMs` boyunca gelmeyince ilk metniyle birlikte "özet: … ×n" yazılır (n > 1 ise). Özet yalnız o akışın
    /// kendisidir (aynı neden ve ilk metin); sonraki satırlar hakkında bir şey söylemez. Günlük boğulmaz.
    public struct SkipJournal: Sendable {
        public var gapMs: Int
        private var run: (key: String, label: String, text: String?, count: Int, since: Int, lastAt: Int)?

        public init(gapMs: Int = 2_000) { self.gapMs = gapMs }

        /// Bir karenin notları (ilk not esas alınır). Yazılacak satırları döndürür.
        public mutating func observe(_ notes: [Output.Note], now: Int) -> [String] {
            var out: [String] = []
            guard let note = notes.first else {
                if let r = run, now - r.lastAt > gapMs { out += flush(); run = nil }
                return out
            }
            if var r = run, r.key == note.runKey {
                r.count += 1
                r.lastAt = now
                run = r
                return out
            }
            out += flush()
            run = (note.runKey, note.label, note.text, 1, now, now)
            var line = note.label
            if let t = note.text, !t.isEmpty { line += " \"" + t.replacingOccurrences(of: "\n", with: " / ") + "\"" }
            out.append(line)
            return out
        }

        /// Süren özetin satırı (durdurma ya da sıfırlamada da çağrılır).
        public mutating func flush() -> [String] {
            defer { run = nil }
            guard let r = run, r.count > 1 else { return [] }
            let secs = String(format: "%.1f", Double(r.lastAt - r.since) / 1_000).replacingOccurrences(of: ".", with: ",")
            let t = r.text.map { " \"" + $0.replacingOccurrences(of: "\n", with: " / ") + "\"" } ?? ""
            return ["özet: \(r.label)\(t) ×\(r.count), \(secs) sn"]
        }
    }
}
