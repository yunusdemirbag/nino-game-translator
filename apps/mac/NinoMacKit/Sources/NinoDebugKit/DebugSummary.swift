// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// nino-debug zaman aralığı: `son 5dk`, `son 30sn`, `son 2sa`, `16:05-16:10`, `16:05:30-16:06`, `16:05` (o andan şimdiye).
public enum DebugRange {
    public static func parse(_ args: [String], now: Date, calendar: Calendar = .current) -> (from: Date, to: Date)? {
        let text = args.joined(separator: " ").lowercased().trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("son") {
            let rest = text.dropFirst(3).replacingOccurrences(of: " ", with: "")
            let digits = rest.prefix { $0.isNumber || $0 == "." || $0 == "," }
            guard let n = Double(digits.replacingOccurrences(of: ",", with: ".")), n > 0 else { return nil }
            let unit = rest.dropFirst(digits.count)
            let seconds: Double
            switch unit {
            case "sn", "s", "sec", "saniye": seconds = 1
            case "dk", "d", "m", "min", "dakika": seconds = 60
            case "sa", "h", "saat": seconds = 3600
            default: return nil
            }
            return (now.addingTimeInterval(-n * seconds), now)
        }
        let parts = text.replacingOccurrences(of: " ", with: "").split(separator: "-").map(String.init)
        guard (1...2).contains(parts.count), var from = clock(parts[0], on: now, calendar) else { return nil }
        var to = parts.count == 2 ? clock(parts[1], on: now, calendar) : now
        guard to != nil else { return nil }
        if to! < from { from = calendar.date(byAdding: .day, value: -1, to: from)! }
        if from > now {
            from = calendar.date(byAdding: .day, value: -1, to: from)!
            to = calendar.date(byAdding: .day, value: -1, to: to!)
        }
        return (from, to!)
    }

    /// `HH:mm` ya da `HH:mm:ss`, `now` gününde.
    static func clock(_ s: String, on now: Date, _ calendar: Calendar) -> Date? {
        let f = s.split(separator: ":").map { Int($0) }
        guard (2...3).contains(f.count), f.allSatisfy({ $0 != nil }) else { return nil }
        let h = f[0]!, m = f[1]!, sec = f.count == 3 ? f[2]! : 0
        guard (0..<24).contains(h), (0..<60).contains(m), (0..<60).contains(sec) else { return nil }
        return calendar.date(bySettingHour: h, minute: m, second: sec, of: now)
    }
}

/// Günlük satırı (`gunluk/*.jsonl`): `{"t":ms,"k":"altyazi|remoteplay|durum","m":"…"}`.
public struct DebugLogLine: Codable, Sendable, Equatable {
    public var t: Int64
    public var k: String
    public var m: String
    public init(t: Int64, k: String, m: String) {
        self.t = t
        self.k = k
        self.m = m
    }
}

/// TV mesajı (`mesaj/*.jsonl`): `{"t":ms,"tv":bağlı TV sayısı,"j":<protokol JSON'u>}`.
public struct DebugTVMessage: Sendable, Equatable {
    public var t: Int64
    public var tv: Int
    public var type: String
    public var line: String

    public static func parse(_ line: String) -> DebugTVMessage? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let t = (o["t"] as? NSNumber)?.int64Value else { return nil }
        let j = o["j"] as? [String: Any]
        return DebugTVMessage(t: t, tv: (o["tv"] as? NSNumber)?.intValue ?? 0, type: j?["type"] as? String ?? "?", line: line)
    }

    public static func line(t: Int64, tv: Int, json: String) -> String { "{\"t\":\(t),\"tv\":\(tv),\"j\":\(json)}" }
}

/// `ozet.md` hesapları (altyazı günlüğü satırlarının biçimi: LineLogText ve TVLinkText).
public struct DebugSummary: Sendable, Equatable {
    public struct Event: Sendable, Equatable {
        public var t: Int64
        public var text: String
    }

    public var readLines = 0
    public var readUpdates = 0
    public var restored = 0
    public var shown = 0
    /// Çeviri süreleri (ms), kaynağa göre.
    public var translationMs: [String: [Int]] = [:]
    public var translationFailed = 0
    /// Atılan satırlar: neden → sayı.
    public var dropped: [String: Int] = [:]
    /// Okunup hiç gösterilmeyen satırlar: neden → sayı.
    public var missed: [String: Int] = [:]
    public var tvConnects = 0
    public var tvDrops: [Event] = []
    public var ps5: [Event] = []
    public var games: [Event] = []
    public var tvMessages: [String: Int] = [:]
    /// Bir önceki `screen` ile aynı öğe listesini yeniden gönderen `screen` mesajları (değişmeyen liste).
    public var screenRepeats = 0

    public init() {}

    /// `screen` mesajının öğe listesi (karşılaştırma için sıralı anahtarlı JSON); başka tür nil.
    static func screenItems(_ line: String) -> String? {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let j = o["j"] as? [String: Any], (j["type"] as? String) == "screen" else { return nil }
        let items = j["items"] ?? []
        guard let d = try? JSONSerialization.data(withJSONObject: ["i": items], options: [.sortedKeys]) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    public var allTranslationMs: [Int] { translationMs.values.flatMap { $0 }.sorted() }
    public var averageMs: Int? {
        let a = allTranslationMs
        return a.isEmpty ? nil : Int((Double(a.reduce(0, +)) / Double(a.count)).rounded())
    }
    public var p95Ms: Int? { Self.percentile(allTranslationMs, 0.95) }

    /// En yakın sıra yöntemiyle yüzdelik (sıralı dizi).
    public static func percentile(_ sorted: [Int], _ p: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count, max(1, rank)) - 1]
    }

    public static func compute(lines: [DebugLogLine], messages: [DebugTVMessage]) -> DebugSummary {
        var s = DebugSummary()
        var read: [Int: Int64] = [:]
        var shown: Set<Int> = []
        var droppedWhy: [Int: String] = [:]
        var failed: Set<Int> = []
        for l in lines.sorted(by: { $0.t < $1.t }) {
            let m = l.m
            if let (id, rest) = lineID(m) {
                if rest.hasPrefix("okundu (uzadı)") || rest.hasPrefix("okundu (düzeldi)") {
                    s.readUpdates += 1
                    if read[id] == nil { read[id] = l.t }
                } else if rest.hasPrefix("okundu") {
                    s.readLines += 1
                    if read[id] == nil { read[id] = l.t }
                } else if rest.hasPrefix("yeniden okundu") {
                    s.restored += 1
                } else if rest.hasPrefix("çeviri: başarısız") {
                    s.translationFailed += 1
                    failed.insert(id)
                } else if rest.hasPrefix("çeviri: ") {
                    let f = rest.dropFirst("çeviri: ".count).split(separator: " ")
                    if f.count >= 3, f[2] == "ms", let ms = Int(f[1]) { s.translationMs[String(f[0]), default: []].append(ms) }
                } else if rest.hasPrefix("gösterildi") {
                    if shown.insert(id).inserted { s.shown += 1 }
                } else if rest.hasPrefix("atıldı") {
                    let why = paren(rest) ?? "?"
                    s.dropped[why, default: 0] += 1
                    droppedWhy[id] = why
                }
            } else if m.hasPrefix("TV bağlandı") {
                s.tvConnects += 1
            } else if m.hasPrefix("TV koptu") || m.hasPrefix("TV zaman aşımı") {
                s.tvDrops.append(Event(t: l.t, text: m))
            } else if m.hasPrefix("PS5:") || m.hasPrefix("durum: PS5") {
                s.ps5.append(Event(t: l.t, text: m))
            } else if m.hasPrefix("Oyun ekrandan tanındı") || m.hasPrefix("durum: oyun") {
                s.games.append(Event(t: l.t, text: m))
            }
        }
        for id in read.keys where !shown.contains(id) {
            let why = droppedWhy[id] ?? (failed.contains(id) ? "çeviri başarısız" : "gösterilmedi (aralık sonunda bekliyor olabilir)")
            s.missed[why, default: 0] += 1
        }
        var lastScreen: String?
        for m in messages.sorted(by: { $0.t < $1.t }) {
            s.tvMessages[m.type, default: 0] += 1
            switch m.type {
            case "screen":
                let items = screenItems(m.line)
                if let items, items == lastScreen { s.screenRepeats += 1 }
                lastScreen = items
            case "screen-clear", "stopped": lastScreen = nil
            default: break
            }
        }
        return s
    }

    /// `#12 okundu …` → (12, "okundu …").
    static func lineID(_ m: String) -> (Int, Substring)? {
        guard m.hasPrefix("#"), let space = m.firstIndex(of: " "), let id = Int(m[m.index(after: m.startIndex)..<space]) else { return nil }
        return (id, m[m.index(after: space)...])
    }

    static func paren(_ s: Substring) -> String? {
        guard let a = s.firstIndex(of: "("), let b = s.lastIndex(of: ")"), a < b else { return nil }
        return String(s[s.index(after: a)..<b])
    }

    // MARK: Markdown

    public struct Counts: Sendable, Equatable {
        public var ps5Frames = 0, macFrames = 0, eventFrames = 0, tvShots = 0, logLines = 0, tvMessages = 0
        public init() {}
    }

    public func markdown(from: Date, to: Date, counts: Counts, measurement: DebugMeasurement?,
                         timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let hf = DateFormatter()
        hf.timeZone = timeZone
        hf.dateFormat = "HH:mm:ss.SSS"
        func at(_ t: Int64) -> String { hf.string(from: Date(timeIntervalSince1970: TimeInterval(t) / 1000)) }
        func sortedCounts(_ d: [String: Int]) -> [(String, Int)] { d.sorted { ($1.value, $0.key) < ($0.value, $1.key) } }

        var o = "# Nino hata ayıklama özeti\n\n"
        o += "Aralık: \(f.string(from: from)) – \(f.string(from: to))\n\n"
        o += "## Çıkarılanlar\n\n"
        o += "- PS5 kareleri: \(counts.ps5Frames), pencere kareleri: \(counts.macFrames), olay kareleri: \(counts.eventFrames)\n"
        o += "- TV ekran görüntüleri: \(counts.tvShots), TV mesajları: \(counts.tvMessages), günlük satırları: \(counts.logLines)\n\n"
        o += "## Altyazı satırları\n\n"
        o += "- Okunan satır: \(readLines) (uzayan/düzelen okuma \(readUpdates), önceki çeviriyle yeniden okunan \(restored))\n"
        o += "- Gösterilen satır: \(shown)\n"
        let all = allTranslationMs
        if let avg = averageMs, let p95 = p95Ms {
            o += "- Çeviri süresi: ortalama \(avg) ms, p95 \(p95) ms, en uzun \(all.last ?? 0) ms (\(all.count) çeviri)\n"
            for (origin, list) in translationMs.sorted(by: { $0.key < $1.key }) {
                let sorted = list.sorted()
                let a = Int((Double(sorted.reduce(0, +)) / Double(sorted.count)).rounded())
                o += "  - \(origin): \(sorted.count) çeviri, ortalama \(a) ms, p95 \(Self.percentile(sorted, 0.95) ?? 0) ms\n"
            }
        } else {
            o += "- Çeviri süresi: bu aralıkta çeviri yok\n"
        }
        o += "- Başarısız çeviri: \(translationFailed)\n"
        let droppedTotal = dropped.values.reduce(0, +)
        o += "- Atılan satır: \(droppedTotal)\n"
        for (why, n) in sortedCounts(dropped) { o += "  - \(why): \(n)\n" }
        let missedTotal = missed.values.reduce(0, +)
        o += "- Okunup gösterilmeyen (kaçırılan) satır: \(missedTotal)\n"
        for (why, n) in sortedCounts(missed) { o += "  - \(why): \(n)\n" }
        o += "\n## TV\n\n"
        o += "- Bağlanma: \(tvConnects), kopma/zaman aşımı: \(tvDrops.count)\n"
        for e in tvDrops { o += "  - \(at(e.t)) \(e.text)\n" }
        if !tvMessages.isEmpty {
            o += "- Giden mesajlar: " + sortedCounts(tvMessages).map { "\($0.0) \($0.1)" }.joined(separator: ", ") + "\n"
        }
        o += "- Ekran öğeleri: screen \(tvMessages["screen"] ?? 0), screen-clear \(tvMessages["screen-clear"] ?? 0), "
            + "değişmeyen liste yeniden gönderimi \(screenRepeats)\n"
        o += "\n## PS5\n\n"
        if ps5.isEmpty { o += "- Bu aralıkta PS5 durum değişikliği yok\n" }
        for e in ps5 { o += "- \(at(e.t)) \(e.text)\n" }
        if !games.isEmpty {
            o += "\n## Oyun\n\n"
            for e in games { o += "- \(at(e.t)) \(e.text)\n" }
        }
        if let m = measurement {
            o += "\n## Kayıt bütçesi (son ölçüm)\n\n"
            o += "- CPU (kayıtçı, bir çekirdeğin oranı): ortalama %\(Self.pct(m.cpuAverage)), son pencere %\(Self.pct(m.cpuLast)), en yüksek %\(Self.pct(m.cpuPeak))\n"
            o += "- Kare aralığı çarpanı: \(m.scale)× (\(m.slowDowns) kez yavaşlatıldı)\n"
            o += "- Bellek: kayıtçı tamponları ~\(m.recorderBytes / 1_048_576) MB, Nino toplamı \(m.processFootprint / 1_048_576) MB\n"
            o += "- Disk: \(String(format: "%.1f", Double(m.bytesPerMinute) / 1_048_576)) MB/dk, halka \(m.ringTotal / 1_048_576) / \(m.ringLimit / 1_048_576) MB\n"
            let due = m.ps5Frames + m.ps5Dropped + m.ps5Busy
            let pctBusy = due > 0 ? Double(m.ps5Busy + m.ps5Dropped) / Double(due) : 0
            o += "- Kareler: PS5 \(m.ps5Frames), pencere \(m.macFrames) (pencere yoktu \(m.macMissing)), olay \(m.eventFrames), TV görüntüsü \(m.tvShots)\n"
            o += "- PS5 kaydının alamadığı kare: %\(Self.pct(pctBusy)) (yetişemedi \(m.ps5Busy), kodlayıcı almadı \(m.ps5Dropped); "
                + "kaydın kendi oranı içinde, okuma hattını etkilemez)\n"
        }
        return o
    }

    static func pct(_ x: Double) -> String { String(format: "%.2f", x * 100) }
}
