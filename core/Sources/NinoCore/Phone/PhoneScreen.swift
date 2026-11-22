// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// MARK: - Telefonun yeri (tarif §3)

extension GameReading {
    /// Karede bulunan telefon ekranı: eğik tutulunca bir paralelkenar.
    public struct PhoneLocation: Equatable, Sendable {
        /// Çevreleyen kutu (kare oranı).
        public var box: Box
        /// Üst kenardaki sol x.
        public var topLeft: Double
        /// Bir kare yüksekliği aşağı inince sol kenarın x kayması (kare oranı).
        public var slope: Double
        /// Ekran genişliği (kare oranı).
        public var screenWidth: Double
        /// Yalnız şekliyle (dikdörtgen bulucusu) bulundu.
        public var shapeOnly: Bool
        /// Koyu temalı ekran.
        public var dark: Bool

        public init(box: Box, topLeft: Double? = nil, slope: Double = 0, screenWidth: Double? = nil,
                    shapeOnly: Bool = false, dark: Bool = false) {
            self.box = box; self.topLeft = topLeft ?? box.left; self.slope = slope
            self.screenWidth = screenWidth ?? box.width; self.shapeOnly = shapeOnly; self.dark = dark
        }

        public func left(at y: Double) -> Double { topLeft + slope * (y - box.top) }
        public func right(at y: Double) -> Double { left(at: y) + screenWidth }
        public func mid(at y: Double) -> Double { left(at: y) + screenWidth / 2 }
        public var centerX: Double { mid(at: box.midY) }
        public var centerY: Double { box.midY }
        /// Dönme açısı (derece, saat yönü artı).
        public var angle: Double { atan(-slope * 16 / 9) * 180 / .pi }
        /// Satırın ekran sol kenarına göre girintisi.
        public func indent(_ b: Box) -> Double { b.left - left(at: b.midY) }

        /// Bütün yeri kaydırılmış kopya.
        public func shifted(dx: Double, dy: Double) -> PhoneLocation {
            var c = self
            c.box = Box(left: box.left + dx, top: box.top + dy, right: box.right + dx, bottom: box.bottom + dy)
            c.topLeft += dx
            return c
        }
    }
}

// MARK: - Ekran türü (tarif §5)

extension GameReading {
    /// Telefonda okunan bir mesaj ya da uygulama satırı.
    public struct PhoneMessage: Equatable, Sendable {
        public var text: String
        /// Kare oranında kutu.
        public var box: Box
        /// Mesajın satır boyu.
        public var lineHeight: Double
        public var lineCount: Int
        /// Grup sohbetinde balonun üstündeki gönderen adı (çevrilmez; hafıza/havuz anahtarına girmez).
        public var sender: String?

        public init(text: String, box: Box, lineHeight: Double, lineCount: Int = 1, sender: String? = nil) {
            self.text = text; self.box = box; self.lineHeight = lineHeight; self.lineCount = lineCount; self.sender = sender
        }
    }

    public enum PhoneScreenKind: String, Equatable, Sendable { case chat, app }

    public struct PhoneScreenReading: Equatable, Sendable {
        public var kind: PhoneScreenKind
        /// Sohbet başlığı (kişi/yer adı; çevrilmez).
        public var header: String?
        public var headerBox: Box?
        public var messages: [PhoneMessage]
    }

    public enum PhoneScreenResult: Equatable, Sendable {
        /// Okunacak satır yok.
        case empty
        /// Sohbet ya da mesaj listesi (çevrilmez).
        case list
        /// Telefon değil (yalnız şekille bulunup sohbet çıkmadı ya da kapı ipucu).
        case notPhone
        case screen(PhoneScreenReading)
    }

    public enum PhoneScreen {
        static let navButtons: Set<String> = ["back", "geri", "done", "close", "cancel", "edit"]
        static let statusWords = ["new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted"]
        static let linkNames: Set<String> = ["ryde", "rydeme", "buckme"]
        static let attachmentSmall: Set<String> = ["del", "de", "la", "of", "the", "&"]
        static let nameBanned = Set(".,!?:…")

        // MARK: Cümle (§5.4)

        public static func isSentence(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespaces)
            let words = Text.words(t)
            if let last = words.last, last.filter(\.isLetter).count >= 2, let c = last.last, ".!?".contains(c) { return true }
            if (t.contains("!") || t.contains("?")), words.count >= 2 { return true }
            if words.count >= 3, words.dropFirst().contains(where: { $0.first?.isLowercase == true }) { return true }
            return false
        }

        // MARK: Liste (§5.1)

        static func isListName(_ t: String) -> Bool {
            let words = Text.words(t)
            guard (1...3).contains(words.count) else { return false }
            return words.allSatisfy { $0.first?.isUppercase == true } && !t.contains(where: { nameBanned.contains($0) })
        }

        /// En az 3 kez "ad + hemen altında önizleme".
        public static func isChatList(_ lines: [Line]) -> Bool {
            let ls = lines.filter { $0.box != nil }.sorted { $0.box!.top < $1.box!.top }
            var pairs = 0, i = 0
            while i + 1 < ls.count {
                let a = ls[i].box!, b = ls[i + 1].box!
                if isListName(ls[i].text), b.top - a.bottom < 1.2 * a.height, abs(b.left - a.left) < 0.03 {
                    pairs += 1; i += 2
                } else {
                    i += 1
                }
            }
            return pairs >= 3
        }

        public static func isMessageList(_ lines: [Line]) -> Bool {
            if isChatList(lines) { return true }
            return Cards.isList(lines) && lines.contains { $0.text.hasSuffix("...") || $0.text.hasSuffix("…") }
        }

        // MARK: Başlık (§5.2)

        static func isHeaderName(_ t: String) -> Bool {
            if Cards.isName(t) { return true }
            guard t.count >= 2, Text.words(t).count <= 5, t.contains(where: \.isLetter) else { return false }
            return t.allSatisfy { $0.isLetter || $0 == " " || ",.'’&-".contains($0) }
        }

        static func isNavButton(_ t: String) -> Bool {
            var s = Substring(t.trimmingCharacters(in: .whitespaces))
            while let f = s.first, f == "<" || f == "‹" { s = s.dropFirst() }
            return navButtons.contains(Text.key(String(s)))
        }

        public static func header(_ lines: [Line], phone: PhoneLocation) -> Line? {
            let ls = lines.filter { $0.box != nil }.sorted { $0.box!.top < $1.box!.top }
            guard let minTop = ls.first?.box?.top else { return nil }
            let strip = phone.box.top + phone.box.height * 0.07
            for l in ls {
                let b = l.box!
                guard b.top < strip || b.top <= minTop + 0.002 else { continue }
                let t = l.text.trimmingCharacters(in: .whitespaces)
                guard isHeaderName(t), !isNavButton(t) else { continue }
                guard abs(b.midX - phone.mid(at: b.midY)) < phone.screenWidth * 0.12 else { continue }
                let indent = phone.indent(b)
                let hasPreview = ls.contains { o in
                    guard o != l, let ob = o.box else { return false }
                    let gap = ob.top - b.bottom
                    return gap >= 0.008 && gap <= 0.05 && abs(phone.indent(ob) - indent) < 0.015
                }
                if !hasPreview { return l }
            }
            return nil
        }

        // MARK: Mesajlar (§5.3)

        /// Aynı satırdaki parçaları birleştirir (emoji satırı böler).
        static func mergeRow(_ lines: [Line]) -> [Line] {
            var out: [Line] = []
            for l in lines.filter({ $0.box != nil }).sorted(by: { ($0.box!.top, $0.box!.left) < ($1.box!.top, $1.box!.left) }) {
                let b = l.box!
                if let i = out.firstIndex(where: { o in
                    let ob = o.box!
                    let overlap = min(ob.bottom, b.bottom) - max(ob.top, b.top)
                    let (lb, rb) = ob.left <= b.left ? (ob, b) : (b, ob)
                    let gap = rb.left - lb.right
                    return overlap >= 0.75 * min(ob.height, b.height) && gap <= 0.03 && rb.left >= lb.right - 0.005
                }) {
                    let o = out[i]
                    let leftFirst = o.box!.left <= b.left
                    let text = leftFirst ? o.text + " " + l.text : l.text + " " + o.text
                    out[i] = Line(text, confidence: min(o.confidence, l.confidence), box: o.box!.union(b))
                } else {
                    out.append(l)
                }
            }
            return out.sorted { $0.box!.top < $1.box!.top }
        }

        static func isStatus(_ t: String) -> Bool {
            let k = Text.key(t)
            return statusWords.contains { k == $0 || k.hasSuffix(" " + $0) }
        }

        static func isAttachment(_ t: String) -> Bool {
            let words = Text.words(t)
            guard words.count >= 2, !t.contains(where: { ".,!?:;…\"".contains($0) }) else { return false }
            return words.allSatisfy { $0.first?.isUppercase == true || attachmentSmall.contains($0.lowercased()) }
        }

        static func isSenderName(_ t: String) -> Bool {
            let words = Text.words(t)
            guard (1...2).contains(words.count), !t.contains(where: { ".,!?:;…\"'’".contains($0) }) else { return false }
            return words.allSatisfy { $0.first?.isUppercase == true && $0.allSatisfy(\.isLetter) }
        }

        static func endsWithEllipsis(_ t: String) -> Bool {
            let s = t.trimmingCharacters(in: .whitespaces)
            return s.hasSuffix("...") || s.hasSuffix("…")
        }

        /// Sohbetteki bağlantı kartı: "…" ile kesilmiş ve ya başlık satırıyla (ad gibi) başlıyor ya da başlığın hemen
        /// altında (üstten kesik) duruyor.
        static func isLinkCard(_ p: [Line], top: Double) -> Bool {
            guard let last = p.last, endsWithEllipsis(last.text) else { return false }
            if p.count >= 2, isSenderName(p[0].text) { return true }
            return p[0].box!.top < top + 0.05
        }

        public static func messages(_ lines: [Line], phone: PhoneLocation, header: Line?) -> [PhoneMessage] {
            let stripBottom = max(phone.box.top + phone.box.height * 0.07, header?.box?.bottom ?? 0)
            let rows = mergeRow(lines.filter { $0 != header }).filter { l in
                let b = l.box!
                return Text.letterCount(l.text) >= 2 && b.top > stripBottom + 0.012 && b.bottom < phone.box.bottom - 0.01
            }
            guard !rows.isEmpty else { return [] }
            var tops = zip(rows.dropFirst(), rows).map { $0.box!.top - $1.box!.top }.filter { $0 >= 0.012 && $0 <= 0.04 }
            tops.sort()
            let spacing = tops.first ?? (rows.map { $0.box!.height }.min()! * 1.2)

            var paragraphs: [[Line]] = []
            for l in rows {
                if var p = paragraphs.last, let first = p.first?.box, let prev = p.last?.box,
                   l.box!.top - prev.top < 1.6 * spacing || l.box!.top - prev.bottom < 0.4 * spacing,
                   abs(phone.indent(l.box!) - phone.indent(first)) < 0.02 {
                    p.append(l); paragraphs[paragraphs.count - 1] = p
                } else {
                    paragraphs.append([l])
                }
            }
            var out: [PhoneMessage] = []
            var pendingSender: (line: Line, bottom: Double)?
            func plain(_ p: [Line]) -> PhoneMessage? {
                let text = p.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let key = Text.key(text)
                guard !key.isEmpty, !isStatus(text), !linkNames.contains(key), !isAttachment(text) else { return nil }
                return PhoneMessage(text: text, box: Box.union(p.map(\.box!))!, lineHeight: spacing * 0.85, lineCount: p.count)
            }
            for var p in paragraphs {
                // Bağlantı kartı (başlık + "…" ile kesilmiş önizleme, yanında görsel) ya da üstte kesik önizleme: çevrilmez.
                if isLinkCard(p, top: stripBottom) { pendingSender = nil; continue }
                // Grup sohbetinde balonun üstündeki gönderen adı: balonla aynı paragrafta ya da (avatar yüzünden
                // girintisi farklı) tek satırlık ayrı paragraf olarak gelir; ikisinde de sonraki mesajın başlığı olur.
                var sender: String?
                if p.count >= 2, isSenderName(p[0].text) {
                    sender = p[0].text.trimmingCharacters(in: .whitespaces)
                    p.removeFirst()
                }
                if let ps = pendingSender {
                    // Ad hemen altındaki balona yapışıktır (balonlar arası boşluk daha büyük); değilse tek kelimelik mesajdır.
                    if sender == nil, p[0].box!.top - ps.bottom < 0.9 * spacing {
                        sender = ps.line.text.trimmingCharacters(in: .whitespaces)
                    } else if let m = plain([ps.line]) {
                        out.append(m)
                    }
                    pendingSender = nil
                }
                if sender == nil, p.count == 1, isSenderName(p[0].text) {
                    pendingSender = (p[0], p[0].box!.bottom)
                    continue
                }
                let text = p.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let key = Text.key(text)
                guard !key.isEmpty, !isStatus(text), !linkNames.contains(key), !isAttachment(text) else { continue }
                out.append(PhoneMessage(text: text, box: Box.union(p.map(\.box!))!, lineHeight: spacing * 0.85, lineCount: p.count,
                                        sender: sender))
            }
            if let ps = pendingSender, let m = plain([ps.line]) { out.append(m) }
            return out
        }

        // MARK: Uygulama satırları (§5.5)

        static func stripLeadingIcons(_ t: String) -> String {
            var s = Substring(t)
            while let f = s.first, !(f.isLetter || f.isNumber || "$€£".contains(f)) { s = s.dropFirst() }
            return String(s).trimmingCharacters(in: .whitespaces)
        }

        static func isShortUpperLabel(_ t: String) -> Bool {
            let letters = t.filter(\.isLetter)
            return !letters.isEmpty && letters.allSatisfy(\.isUppercase) && Text.words(t).count <= 3
        }

        /// Sohbet olmayan ekranın satırları. Hepsi BÜYÜK kısa etiketse `nil` (telefon değil).
        public static func appLines(_ lines: [Line], phone: PhoneLocation) -> [PhoneMessage]? {
            let stripBottom = phone.box.top + phone.box.height * 0.07
            let rows = lines.filter { $0.box != nil }.sorted { $0.box!.top < $1.box!.top }.compactMap { l -> Line? in
                let t = stripLeadingIcons(l.text)
                let k = Text.key(t)
                if k.hasSuffix("messages encrypted") || k.hasSuffix("message encrypted") { return nil }
                guard Text.letterCount(t) >= 3, l.box!.top > stripBottom, l.box!.bottom < phone.box.bottom - 0.01 else { return nil }
                return Line(t, confidence: l.confidence, box: l.box)
            }
            guard !rows.isEmpty else { return [] }
            if rows.allSatisfy({ isShortUpperLabel($0.text) }) { return nil }
            var groups: [[Line]] = []
            for l in rows {
                let b = l.box!
                let author = Text.words(l.text).first?.lowercased() == "by" && Text.words(l.text).count <= 4
                if !author, var g = groups.last, let prev = g.last {
                    let pb = prev.box!
                    let lower = l.text.first?.isLowercase == true
                    let unfinished = !Text.endsSentence(prev.text) && Text.words(prev.text).count >= 3
                    if b.top - pb.bottom < 0.6 * b.height, abs(b.left - pb.left) < 0.02, lower || unfinished {
                        g.append(l); groups[groups.count - 1] = g
                        continue
                    }
                }
                groups.append([l])
            }
            return groups.map { g in
                PhoneMessage(text: g.map(\.text).joined(separator: " "), box: Box.union(g.map(\.box!))!,
                             lineHeight: (Text.median(g.map { $0.box!.height }) ?? 0.02) * 0.85, lineCount: g.count)
            }
        }

        // MARK: Karar (§5.4)

        /// Telefondan okunan satırlar (kare oranında) → ekran türü.
        public static func classify(_ lines: [Line], phone: PhoneLocation) -> PhoneScreenResult {
            let ls = lines.filter { $0.box != nil && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !ls.isEmpty else { return .empty }
            let head = header(ls, phone: phone)
            // Ortada sohbet başlığı varsa zayıf liste işareti (2 ad ya da "…" ile biten satırlar: bağlantı kartı, kesik
            // önizleme) sohbeti liste yapmaz; yalnız "ad + altında önizleme" düzeni (en az 3) liste sayılır.
            if head != nil ? isChatList(ls) : isMessageList(ls) { return phone.shapeOnly ? .notPhone : .list }
            let msgs = messages(ls, phone: phone, header: head)
            if let head, msgs.contains(where: { isSentence($0.text) }) {
                return .screen(PhoneScreenReading(kind: .chat, header: head.text.trimmingCharacters(in: .whitespaces),
                                                  headerBox: head.box, messages: msgs))
            }
            if phone.shapeOnly { return .notPhone }
            guard let app = appLines(ls, phone: phone) else { return .notPhone }
            if app.isEmpty { return .empty }
            return .screen(PhoneScreenReading(kind: .app, header: nil, headerBox: nil, messages: app))
        }

        /// Harita tuşlarından biri okunduysa bu harita ekranıdır (tarif §4).
        public static func containsMapButton(_ lines: [Line]) -> Bool {
            lines.contains { MapScreen.phoneMapButtons.contains(MapScreen.buttonName($0.text)) }
        }
    }
}
