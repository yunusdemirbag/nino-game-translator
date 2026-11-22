// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Satır süzgeçleri (tarif §5). Hangi sırayla uygulandıkları `FilterChain.swift`'tedir.
extension GameReading {
    public enum Filters {}
}

// MARK: - §5.1 Harfsiz satır

extension GameReading.Filters {
    public static func hasEnoughLetters(_ text: String) -> Bool {
        GameReading.Text.letterCount(text) >= 2
    }
}

// MARK: - §5.2 Tuş ipucu

extension GameReading.Filters {
    /// Omuz ve çubuk tuşları: L1–L3, R1–R3 (DualSense üzerindeki yazılar).
    static let shoulderButtons: [String] = ["L", "R"].flatMap { side in (1...3).map { "\(side)\($0)" } }
    /// Yüz tuşlarının OCR'de en sık çıkan biçimleri.
    static let faceButtons: [String] = ["✕", "○", "◯", "□", "△", "▲"]
    static let buttons: Set<String> = Set(shoulderButtons + ["TOUCHPAD", "OPTIONS"]).union([
        "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂",
        "&", "®", "©", "@", "⊗", "Ⓧ", "ⓧ", "L", "R", "LZ", "RZ", "LI", "RI", "L7", "R7", "*",
        "↑", "↓", "←", "→", "✜", "▦", "◆",
    ])
    static let strongButtons: Set<String> = Set(shoulderButtons + ["TOUCHPAD"] + faceButtons)
    static let hintVerbs: Set<String> = ["press", "hold", "tap", "push", "use", "mash", "release", "double", "pull", "click"]
    static let hintAdverbs: Set<String> = ["slowly", "quickly", "ouickly", "gently", "carefully", "rapidly", "repeatedly", "continuously", "briefly"]

    /// Satırı boşluk, `+` ve `/` ile parçalara ayırır; parantezleri atar.
    static func hintParts(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0 == "+" || $0 == "/" }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}")) }
            .filter { !$0.isEmpty }
    }

    static func isButton(_ part: String) -> Bool { buttons.contains(part.uppercased()) || buttons.contains(part) }

    static func isUpperWord(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLetter && $0.isUppercase }
    }

    /// Satır tuş ipucu mu (altyazı değil)?
    public static func isHint(_ text: String) -> Bool {
        let parts = hintParts(text)
        guard !parts.isEmpty else { return false }
        let ends = GameReading.Text.endsSentence(text)
        let lower = parts.map { $0.lowercased() }
        let hasLetters = text.contains(where: \.isLetter)

        // Tamamı büyük harf ve PHOTO MODE.
        if hasLetters, !GameReading.Text.hasLowercase(text), text.uppercased().contains("PHOTO MODE") { return true }

        // Başta 1–3 kırıntı, ardından noktalamasız 1–3 BÜYÜK HARFLİ sözcük.
        var i = 0
        while i < parts.count, i < 3, parts[i].count <= 2, !(parts[i].count == 2 && parts[i].allSatisfy(\.isLetter)) { i += 1 }
        let rest = parts[i...]
        if i >= 1, (1...3).contains(rest.count), rest.allSatisfy(isUpperWord), rest.first!.count >= 3 { return true }
        // Seçim menüsü satırı (`△ SPLIT UP & TAKE 🚗`): `&` sayılmaz, sondaki simge kırıntısı (≤ 2 harf) atılır.
        var choice = rest.filter { $0 != "&" }
        if choice.count >= 2, choice.last!.count <= 2 { choice.removeLast() }
        if i >= 1, (1...3).contains(choice.count), choice.allSatisfy(isUpperWord), choice.first!.count >= 3 { return true }

        // İlk parça düğme, düğme olmayan harfli sözcük ≤ 5.
        if isButton(parts[0]) {
            let words = parts.filter { !isButton($0) && $0.contains(where: \.isLetter) }.count
            if words <= 5 { return true }
        }
        // Son parça düğme, ≤ 4 sözcük, cümle bitmiyor.
        if isButton(parts.last!), parts.count <= 4, !ends { return true }
        // İlk parça X/O, 2–4 parça, ikinci büyük harfle, cümle bitmiyor.
        if ["X", "O"].contains(parts[0]), (2...4).contains(parts.count), parts[1].first?.isUppercase == true, !ends { return true }
        // Fiil ile başlıyor.
        if hintVerbs.contains(lower[0]) {
            if (2...10).contains(parts.count), isButton(parts[1]) || ["X", "O"].contains(parts[1]) { return true }
            if parts.count >= 4, lower[1] == "to" { return true }
            if parts.count <= 14, parts.contains(where: isButton), !ends { return true }
        }
        // Zarf ile başlıyor.
        if hintAdverbs.contains(lower[0]), (3...16).contains(parts.count), lower.dropFirst(3).contains("to"), !ends { return true }
        // Güçlü düğme ve "to".
        if parts.count <= 16, parts.contains(where: { strongButtons.contains($0.uppercased()) }), lower.contains("to"), !ends { return true }
        return false
    }
}

// MARK: - §5.3 Yol tarifi

extension GameReading.Filters {
    static let distance = #"[0-9oO]+(?:[.,][0-9]+)?\s?(?:ft|mi|yd|km|m)\b"#

    /// Yalnız yön + mesafeden oluşan satır.
    public static func isDirection(_ text: String) -> Bool {
        var t = Substring(text.trimmingCharacters(in: .whitespaces))
        while let f = t.first, !f.isLetter, !f.isNumber { t = t.dropFirst() }
        let s = String(t)
        let head = #"^(?:make an? )?(?:u-turn|uturn|turn|keep|bear)"#
        let full = head + #"(?: (?:left|right))?(?: \#(distance))*[.!]?$"#
        if GameReading.Text.regex(full, s) { return true }
        // Yön + sağ/sol, ardından en az bir mesafe; mesafeler silinince ≤ 2 harf/rakam kalıyor.
        guard let r = s.range(of: head + " (?:left|right)", options: [.regularExpression, .caseInsensitive]) else { return false }
        let rest = String(s[r.upperBound...])
        guard rest.range(of: distance, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        let stripped = rest.replacingOccurrences(of: distance, with: "", options: [.regularExpression, .caseInsensitive])
        return stripped.filter { $0.isLetter || $0.isNumber }.count <= 2
    }
}

// MARK: - §5.4 OCR çöpü temizliği

extension GameReading.Filters {
    static let junkSymbols = Set("$@#%^*_=|\\~<>{}¢£¥§©®°±µ¶¤")
    static let looseMarks = Set("?!.,;:")
    static let lAsI = try! NSRegularExpression(pattern: #"^([^\p{L}\p{N}|]*)[l|]('(?:m|ll|ve|d|s|re))?([^\p{L}\p{N}]*)$"#)

    struct Word {
        var lead: String
        var core: String
        var trail: String
        var text: String { lead + core + trail }

        init(_ s: String) {
            let chars = Array(s)
            var a = 0, b = chars.count
            while a < b, !(chars[a].isLetter || chars[a].isNumber) { a += 1 }
            while b > a, !(chars[b - 1].isLetter || chars[b - 1].isNumber) { b -= 1 }
            lead = String(chars[0..<a]); core = String(chars[a..<b]); trail = String(chars[b...])
            if core.isEmpty { lead = s; trail = "" }
        }
    }

    static func ordinaryMix(_ core: String) -> Bool {
        let patterns = [
            #"^[A-Za-z]{1,4}[0-9]{1,4}$"#,
            #"^[0-9]+(?:[.,][0-9]+)?(?:st|nd|rd|th|s|m|km|cm|mm|ft|yd|mi|kg|g|lb|lbs|k|fps|hz|p|x|h|min|sec|ms)$"#,
            #"^x[0-9]+$"#,
            #"^[0-9]+(?:[.,][0-9]+)+$"#,
            #"^[0-9]{1,2}:[0-9]{2}(?:am|pm)?$"#,
        ]
        return patterns.contains { GameReading.Text.regex($0, core) }
    }

    /// Bir sözcüğün çekirdeği temiz mi (atılmadan kalır mı)?
    static func coreIsClean(_ core: String) -> Bool {
        if !core.contains(where: \.isLetter) { return true }
        if core.contains("-") {
            return core.split(separator: "-").allSatisfy { coreIsClean(String($0)) }
        }
        let hasSymbol = core.contains { junkSymbols.contains($0) }
        let hasDigit = core.contains(where: \.isNumber)
        if !hasSymbol, !hasDigit { return true }
        if !hasSymbol, ordinaryMix(core) { return true }
        return false
    }

    /// `I` ile başlayan sözcükleri OCR'ın `l`'si yapışık okur: `lcan` → `I can`.
    static let glueAfterI: Set<String> = [
        "can", "can't", "cant", "could", "couldn't", "will", "won't", "would", "wouldn't", "should", "shouldn't",
        "have", "haven't", "had", "hadn't", "did", "didn't", "don't", "dont", "do", "know", "think", "want", "need",
        "got", "guess", "mean", "just", "was", "wasn't", "really", "never", "love", "hate", "told", "said", "saw",
        "see", "swear", "promise", "might", "must", "feel", "thought", "heard", "gotta", "gonna", "wanna",
    ]

    /// Büyük `I`'nın OCR okuyuşları: `i` / `i'm` → `I` / `I'm`, `I'II` → `I'll`, `lcan` → `I can`,
    /// `lm` / `Im` → `I'm`, `III-` (ardından `I'll`) → `I'll-`. Sonuç bir ya da iki sözcük olabilir.
    static func fixPronounI(_ w: String, next: String?) -> String {
        let word = Word(w)
        var core = word.core
        guard !core.isEmpty else { return w }
        // Kesmeden sonra `II` → `ll` (`I'II`, `you'II`).
        for ap in ["'", "’"] where core.hasSuffix(ap + "II") {
            core = String(core.dropLast(2)) + "ll"
        }
        if core == "i" { core = "I" }
        for ap in ["'", "’"] where core.hasPrefix("i" + ap) && ["m", "ll", "ve", "d"].contains(String(core.dropFirst(2))) {
            core = "I" + core.dropFirst()
        }
        if core == "lm" || core == "Im" { core = "I'm" }
        // `III-` ve ardında `I'll` (`III- I'II`): kekeleyen `I'll-`.
        if core == "III", word.trail.hasPrefix("-"), let n = next, Word(n).core.lowercased().hasPrefix("i'") || Word(n).core.lowercased().hasPrefix("l'") {
            core = "I'll"
        }
        // `lcan` → `I can`: küçük `l` + `I`'dan sonra gelen bilinen sözcük.
        if core.count >= 3, core.first == "l", glueAfterI.contains(String(core.dropFirst())) {
            core = "I " + core.dropFirst()
        } else if core.count >= 4, core.first == "I", glueAfterI.contains(String(core.dropFirst())) {
            core = "I " + core.dropFirst() // `Ican`
        }
        return word.lead + core + word.trail
    }

    /// Satır içindeki OCR çöpünü temizler.
    public static func cleanJunk(_ text: String) -> String {
        let split = GameReading.Text.words(text)
        let raw = split.indices.flatMap { i in
            GameReading.Text.words(fixPronounI(split[i], next: i + 1 < split.count ? split[i + 1] : nil))
        }
        var out: [String] = []
        for (i, w) in raw.enumerated() {
            let next = i + 1 < raw.count ? raw[i + 1] : nil
            // l / | → I
            let ns = w as NSString
            if let m = lAsI.firstMatch(in: w, range: NSRange(location: 0, length: ns.length)) {
                let lead = ns.substring(with: m.range(at: 1))
                let suffix = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
                let trail = ns.substring(with: m.range(at: 3))
                if !suffix.isEmpty { out.append(lead + "I" + suffix + trail); continue }
                let nextLower = next?.first(where: \.isLetter)?.isLowercase == true
                if nextLower || trail.contains("?") || trail.contains("!") { out.append(lead + "I" + trail) }
                continue
            }
            // Yalnız ? ! . , ; : işaretleri (üç nokta hariç).
            if !w.isEmpty, w.allSatisfy({ looseMarks.contains($0) }), w != "...", !w.hasPrefix("..") {
                if let last = out.last, !GameReading.Text.endsSentence(last),
                   let lc = last.last, lc.isLetter || lc.isNumber {
                    out[out.count - 1] = last + w
                }
                continue
            }
            let word = Word(w)
            if word.core.isEmpty || coreIsClean(word.core) { out.append(w); continue }
            // Baştaki harf/kesme/tire dizisinde en az 3 harf varsa o kalır.
            let prefix = String(word.core.prefix { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" })
            if prefix.filter(\.isLetter).count >= 3 {
                out.append(word.lead + prefix + word.trail)
            } else if !word.trail.isEmpty, let last = out.last {
                out[out.count - 1] = last + word.trail
            }
        }
        // Baştaki tek başına sayı (≥ 3 sözcük, ikinci büyük harfle).
        if out.count >= 3, GameReading.Text.regex(#"^[0-9]+(?:m|km|ft|yd)?[[:punct:]]?$"#, out[0]),
           out[1].first(where: { $0.isLetter })?.isUppercase == true, out[1].first?.isLetter == true {
            out.removeFirst()
        }
        return out.joined(separator: " ")
    }
}

// MARK: - §5.5 Okuma puanı

extension GameReading.Filters {
    static let vowels = Set("aeiouyAEIOUYâêîôûäëïöüàèìòùáéíóúıİ")
    static let interjections: Set<String> = ["hm", "m", "sh", "br", "gr", "pst", "pft", "tsk", "hrm", "z", "pht"]

    static func normalCase(_ letters: [Character]) -> Bool {
        guard !letters.isEmpty else { return true }
        let uppers = letters.filter(\.isUppercase).count
        if uppers == letters.count { return true }
        if uppers == 0 { return true }
        if uppers == 1, letters[0].isUppercase { return true }
        let inner = letters.dropFirst().filter(\.isUppercase).count
        let lowers = letters.filter(\.isLowercase).count
        return inner == 1 && lowers >= 2 && uppers <= 2
    }

    static func isVowelless(_ letters: [Character]) -> Bool {
        guard letters.count >= 3, !letters.allSatisfy(\.isUppercase), !letters.contains(where: { vowels.contains($0) }) else { return false }
        var collapsed: [Character] = []
        for c in letters.map({ Character($0.lowercased()) }) where collapsed.last != c { collapsed.append(c) }
        return !interjections.contains(String(collapsed))
    }

    static func wordIsClean(_ w: String) -> Bool {
        let letters = w.filter(\.isLetter).map { $0 }
        if cleanJunk(w) != w { return false }
        if w.contains(where: { "[]()".contains($0) }) { return false }
        if !normalCase(letters) { return false }
        if isVowelless(letters) { return false }
        return true
    }

    /// Temiz sözcük harfleri artı, kötü sözcük harflerinin iki katı eksi.
    public static func score(_ text: String) -> Int {
        GameReading.Text.words(text).reduce(0) { sum, w in
            let n = w.filter(\.isLetter).count
            return sum + (wordIsClean(w) ? n : -2 * n)
        }
    }

    /// Kötü harfler × 6 > tüm harfler.
    public static func looksLikeJunk(_ text: String) -> Bool {
        var bad = 0, all = 0
        for w in GameReading.Text.words(text) {
            let n = w.filter(\.isLetter).count
            all += n
            if !wordIsClean(w) { bad += n }
        }
        return bad * 6 > all
    }
}

// MARK: - §5.6 Eşya / tabela etiketi

extension GameReading.Filters {
    static let sentencePunctuation = Set(".,!?:;…\"")

    public static func isItemLabel(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if GameReading.Text.regex(#"\(\s*\d+\s*/\s*\d+\s*\)"#, t) { return true }
        let words = GameReading.Text.words(t)
        if words.filter(isButton).count >= 2 { return true }
        let lower = GameReading.Text.hasLowercase(t)
        let letters = t.contains(where: \.isLetter)
        // 1–2 sözcüklük noktalı/ünlemli/soru cevabı (`OK.`, `NO!`, `WHY?`) etiket değildir; etiketler noktalamasızdır.
        let shout = words.count <= 2 && (t.hasSuffix("!") || t.hasSuffix("?") || t.hasSuffix("."))
        // Konuşan etiketi ve üç nokta cümle işaretidir (`TOMAS: ...` etiket değil).
        if t.contains(":") || t.contains("…") || t.contains("...") { return false }
        if (1...6).contains(words.count), !lower, letters, !shout { return true }
        guard (1...4).contains(words.count) else { return false }
        if words.count == 1, t.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) { return true }
        if words.count <= 3, !lower, letters, !t.hasSuffix("!"), !t.hasSuffix("?"), !shout { return true }
        if t.contains(where: { sentencePunctuation.contains($0) }) { return false }
        return !lower && letters
    }
}

// MARK: - §5.7 İki kenar, §5.8 aynı sıra, §5.9 dev yazı, §5.10 blok, §5.11 ortalama

extension GameReading.Filters {
    /// Okunan alanın iki kenarına (0,015 payla) değen satır kesiktir.
    public static func touchesBothEdges(_ line: GameReading.Line) -> Bool {
        guard let b = line.box else { return false }
        return b.left <= 0.015 && b.right >= 0.985
    }

    /// Aynı sıradaki parçaları birleştirir (dikey örtüşme ≥ %60, yatay boşluk < 0,05).
    public static func mergeSameRow(_ lines: [GameReading.Line]) -> [GameReading.Line] {
        guard !lines.isEmpty, lines.allSatisfy({ $0.box != nil }) else { return lines }
        var rows: [GameReading.Line] = []
        for l in lines.sorted(by: { $0.box!.left < $1.box!.left }) {
            let b = l.box!
            if let i = rows.firstIndex(where: { r in
                let rb = r.box!
                let overlap = min(rb.bottom, b.bottom) - max(rb.top, b.top)
                return overlap >= 0.6 * min(rb.height, b.height) && b.left - rb.right < 0.05
                    && !signBesideSentence(r.text, l.text)
            }) {
                rows[i] = GameReading.Line(rows[i].text + " " + l.text, confidence: min(rows[i].confidence, l.confidence),
                                           box: rows[i].box!.union(b))
            } else {
                rows.append(l)
            }
        }
        return rows.sorted { $0.box!.top < $1.box!.top }
    }

    static func labelLike(_ text: String) -> Bool {
        GameReading.Text.words(text).count <= 4 && !text.contains(where: { ".,!?…".contains($0) })
    }

    /// Dev satırları atar (ölçü karenin tamamına göre).
    public static func dropGiantLines(_ lines: [GameReading.Line], area: GameReading.Box) -> [GameReading.Line] {
        lines.filter { l in
            guard let b = l.box else { return true }
            let h = b.height * area.height
            if h > 0.13 { return false }
            if h > 0.075, labelLike(l.text) { return false }
            return true
        }
    }

    /// Blok > 5 satır ya da blok yüksekliği > 0,26 (karede).
    public static func isGiantBlock(_ lines: [GameReading.Line], area: GameReading.Box) -> Bool {
        let boxes = lines.compactMap(\.box)
        if boxes.count > 5 { return true }
        guard let u = GameReading.Box.union(boxes) else { return false }
        return u.height * area.height > 0.26
    }

    static func isMenuBlock(_ block: [GameReading.Line]) -> Bool {
        block.count >= 3 && block.allSatisfy { GameReading.Text.words($0.text).count <= 3 && !GameReading.Text.endsSentence($0.text) }
    }

    /// Satırları bloklara ayırır (§5.10 adım 1).
    public static func blocks(_ lines: [GameReading.Line]) -> [[GameReading.Line]] {
        var blocks: [[GameReading.Line]] = []
        for l in lines.sorted(by: { $0.box!.top < $1.box!.top }) {
            let b = l.box!
            if let last = blocks.last?.last?.box {
                let gap = b.top - last.bottom
                let overlap = min(b.right, last.right) - max(b.left, last.left)
                if gap < 0.8 * max(b.height, last.height), b.top > last.top, overlap >= 0.5 * min(b.width, last.width) {
                    blocks[blocks.count - 1].append(l)
                    continue
                }
            }
            blocks.append([l])
        }
        return blocks
    }

    /// Altyazı bloğunu seçer. Kutusuz satır varsa okuma olduğu gibi kalır.
    public static func selectBlock(_ lines: [GameReading.Line], area: GameReading.Box) -> [GameReading.Line] {
        guard !lines.isEmpty, lines.allSatisfy({ $0.box != nil }) else { return lines }
        let candidates = blocks(lines).filter { !isMenuBlock($0) }
        func frameBox(_ b: [GameReading.Line]) -> GameReading.Box { GameReading.Box.union(b.map(\.box!))!.mapped(into: area) }
        let centered = candidates.filter { abs(frameBox($0).midX - 0.5) < 0.12 }
        if let pick = centered.max(by: { frameBox($0).bottom < frameBox($1).bottom }) { return pick }
        let wordy = candidates.filter { $0.reduce(0) { $0 + GameReading.Text.words($1.text).count } >= 3 }
        return wordy.max(by: { frameBox($0).bottom < frameBox($1).bottom }) ?? []
    }

    /// Ortası 0,3–0,7 arasındaki kutu ekran ortasına göre simetrik genişletilir (kare oranı).
    public static func centered(_ b: GameReading.Box) -> GameReading.Box {
        guard b.midX >= 0.3, b.midX <= 0.7 else { return b }
        return GameReading.Box(left: min(b.left, 1 - b.right), top: b.top, right: max(b.right, 1 - b.left), bottom: b.bottom)
    }
}

// MARK: - Canlı okuma kalitesi: madde imi, tabela parçası, kırpılmış ikinci satır

extension GameReading.Filters {
    /// Satır başındaki madde imi ya da OCR'ın gösterge iğnesinden okuduğu işaret (`• And…`, `/shut…`, `«Shut…`, `* Hey…`).
    /// Tire (`- Now? - Later.`) konuşan değişimidir; dokunulmaz.
    static let leadingBullets = Set("•·▪▫◦‣∙●○■□◆*/\\«»„‚›‹~¬>")

    public static func stripLeadingBullets(_ text: String) -> String {
        var t = Substring(text)
        while let f = t.first, leadingBullets.contains(f) || f.isWhitespace {
            if f == "«", t.contains("»") { break }
            t = t.dropFirst()
        }
        guard t.count < text.count, t.contains(where: \.isLetter) else { return text }
        return String(t)
    }

    /// Büyük/küçük harf düzeni olağan dışı sözcük (`ToWAr`).
    static func oddCase(_ word: String) -> Bool { !normalCase(word.filter(\.isLetter).map { $0 }) }

    /// Tabela/etiket parçası gibi: 1–3 sözcük, cümle işareti yok, en az 2 harf ve
    /// küçük harf yok ya da düzeni bozuk sözcük var (`FRATE PHYS`, `NO ALCOHOL ToWAr`).
    public static func signLike(_ text: String) -> Bool {
        let words = GameReading.Text.words(text).filter { $0.contains(where: \.isLetter) }
        guard (1...3).contains(words.count), GameReading.Text.letterCount(text) >= 2 else { return false }
        if text.contains(where: { sentencePunctuation.contains($0) }) { return false }
        // Tuş adı ya da ipucu fiili (`OPTIONS`, `HOLD`) ipucunun parçasıdır, tabela değil.
        if words.contains(where: { isButton($0) || hintVerbs.contains($0.lowercased()) }) { return false }
        return !GameReading.Text.hasLowercase(text) || words.contains(where: oddCase)
    }

    /// Konuşma satırı gibi: küçük harf var ve en az 3 sözcük (≥ 2 harf).
    static func sentenceLike(_ text: String) -> Bool {
        GameReading.Text.hasLowercase(text) && GameReading.Text.words(text).filter { $0.filter(\.isLetter).count >= 2 }.count >= 3
    }

    /// Aynı sıradaki iki parça birleşmez: biri tabela gibi, öteki konuşma satırı.
    public static func signBesideSentence(_ a: String, _ b: String) -> Bool {
        (signLike(a) && sentenceLike(b)) || (signLike(b) && sentenceLike(a))
    }

    /// Vision tabela yazısını satırla tek parça okuduysa baştaki tabela kısmı atılır (yalnız telefon oyunu):
    /// 1–3 sözcük, hepsi büyük harf ya da düzeni bozuk, noktalama yok, en az 5 harf ve bir sözcüğü ≥ 4 harf;
    /// ardından büyük harfle başlayıp küçük harfle süren sözcük ve en az 3 sözcüklük konuşma.
    public static func stripSignPrefix(_ text: String) -> String {
        let words = GameReading.Text.words(text)
        for n in stride(from: min(3, words.count - 3), through: 1, by: -1) where n >= 1 {
            let prefix = Array(words.prefix(n)), rest = Array(words.dropFirst(n))
            guard prefix.allSatisfy({ w in
                w.allSatisfy(\.isLetter) && w.count >= 2 && (!GameReading.Text.hasLowercase(w) || oddCase(w))
            }) else { continue }
            let letters = prefix.joined().count
            guard letters >= 5, prefix.contains(where: { $0.count >= 4 }) else { continue }
            let first = Array(rest[0].filter(\.isLetter))
            guard first.count >= 2, first[0].isUppercase, first[1].isLowercase else { continue }
            let body = rest.joined(separator: " ")
            guard sentenceLike(body) else { continue }
            return body
        }
        return text
    }

    /// Blokta cümle biten satırın altındaki küçük harfle başlayan satır, solu okunamamış bir satırın kuyruğudur
    /// (`…Peaches' head.` + `the best I can.`): o ve altındakiler atılır; tam okuma sonra uzama olarak gelir.
    public static func dropClippedTail(_ block: [GameReading.Line]) -> [GameReading.Line] {
        guard block.count >= 2 else { return block }
        for i in 1..<block.count {
            let starts = block[i].text.first(where: \.isLetter)
            let prev = block[i - 1].text.trimmingCharacters(in: .whitespaces)
            let ellipsis = prev.hasSuffix("...") || prev.hasSuffix("…")
            if starts?.isLowercase == true, GameReading.Text.endsSentence(prev), !ellipsis {
                return Array(block.prefix(i))
            }
        }
        return block
    }
}

extension GameReading.Filters {
    /// Telefon oyununda (GTA 6 altyazısında tireli konuşma yok) blokta tek satırın başındaki tire, göstergenin
    /// iğnesidir (`- Shut the damn dog up`): atılır. Birden çok satır tireyle başlıyorsa ya da satırın içinde
    /// ikinci bir ` - ` varsa konuşma tiresidir, dokunulmaz.
    public static func stripLoneDialogueDash(_ block: [GameReading.Line]) -> [GameReading.Line] {
        func dashed(_ t: String) -> Bool { t.hasPrefix("- ") || t.hasPrefix("– ") || t.hasPrefix("— ") }
        let dashedLines = block.indices.filter { dashed(block[$0].text) }
        guard dashedLines.count == 1, let i = dashedLines.first else { return block }
        let rest = String(block[i].text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !rest.contains(" - "), !rest.contains(" – "), !rest.contains(" — "), rest.contains(where: \.isLetter) else { return block }
        var out = block
        out[i].text = rest
        return out
    }
}
