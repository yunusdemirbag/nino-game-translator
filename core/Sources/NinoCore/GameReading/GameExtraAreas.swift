// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import ImageIO
import Foundation
#if canImport(CoreImage)
import CoreImage
#endif

// MARK: - Ek alanlar (§11)

extension GameReading {
    public struct ExtraArea: Equatable, Sendable, Codable {
        public enum Preset: String, Sendable, Codable, CaseIterable {
            case quest, notification, phone
            public var box: Box {
                switch self {
                case .quest: return Box(left: 0.66, top: 0.03, right: 0.98, bottom: 0.30)
                case .notification: return Box(left: 0.02, top: 0.58, right: 0.30, bottom: 0.88)
                case .phone: return Box(left: 0.72, top: 0.50, right: 0.98, bottom: 0.95)
                }
            }
        }

        public static let maxCount = 3

        public var id: String
        public var name: String
        public var box: Box
        public var enabled: Bool

        public init(id: String = UUID().uuidString, name: String, box: Box, enabled: Bool = true) {
            self.id = id; self.name = name; self.box = box; self.enabled = enabled
        }

        enum CodingKeys: String, CodingKey { case id, name, box, enabled }

        /// Okunamayan eski kayıtta bölge yoksa görev bölgesi verilir.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            box = (try? c.decode(Box.self, forKey: .box)) ?? Preset.quest.box
            enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        }
    }

    /// Ek alanları okur ve çevirir. En çok 1 000 ms'de bir tur.
    public actor ExtraAreaReader {
        public enum Change: Equatable, Sendable {
            case show(ScreenElement)
            case remove(id: String)
        }

        struct Candidate: Equatable {
            var key: String
            var parts: [String]
            var box: Box?
            var lineHeight: Double
        }

        struct State {
            var fingerprint: Fingerprint?
            var pending: Candidate?
            var lastKey: String?
            var onScreen: (key: String, box: Box?, text: String)?
        }

        private let ocr: OCR
        private let translator: ElementTranslator
        private let clock: Clock
        public var intervalMs = 1_000
        private var states: [String: State] = [:]
        private var lastRound = Int.min / 2
        private var running = false

        public init(ocr: OCR, translator: ElementTranslator, clock: Clock) {
            self.ocr = ocr; self.translator = translator; self.clock = clock
        }

        /// Bir tur. Önceki tur sürüyorsa ya da süre dolmadıysa boş döner.
        public func round(_ frame: Frame, areas: [ExtraArea]) async -> [Change] {
            let now = clock.nowMs
            guard !running, now - lastRound >= intervalMs else { return [] }
            let active = areas.prefix(ExtraArea.maxCount).filter(\.enabled)
            var out: [Change] = []
            // Kaldırılan ya da kapatılan alanın kutusu kalkar.
            for id in states.keys where !active.contains(where: { $0.id == id }) {
                if states[id]?.onScreen != nil { out.append(.remove(id: id)) }
                states[id] = nil
            }
            guard !active.isEmpty else { return out }
            running = true
            lastRound = now
            defer { running = false }
            for area in active {
                var s = states[area.id] ?? State()
                let fp = frame.fingerprint(of: area.box)
                var stable: Candidate?
                if let last = s.fingerprint, !fp.changed(from: last), s.pending != nil {
                    stable = s.pending
                } else if s.fingerprint == nil || fp.changed(from: s.fingerprint!) || s.pending == nil && s.fingerprint == nil {
                    do {
                        let lines = try await ocr.read(frame, area: area.box, deep: false)
                        let c = Self.candidate(lines, area: area.box)
                        if c.key == s.lastKey { stable = c } else { s.pending = c }
                        s.lastKey = c.key
                    } catch {
                        s.fingerprint = nil
                        s.pending = nil
                        states[area.id] = s
                        continue
                    }
                }
                s.fingerprint = fp
                if let c = stable {
                    s.pending = nil
                    let (changes, retry) = await process(c, area: area, state: &s)
                    out += changes
                    if retry { s.pending = c }
                }
                states[area.id] = s
            }
            return out
        }

        public func reset() -> [Change] {
            let out = states.filter { $0.value.onScreen != nil }.map { Change.remove(id: $0.key) }
            states = [:]
            return out
        }

        static func candidate(_ lines: [Line], area: Box) -> Candidate {
            let kept = lines.compactMap { l -> Line? in
                guard !Filters.isHint(l.text) else { return nil }
                let t = Filters.cleanJunk(l.text)
                return ScreenGroups.isText(t) ? Line(t, confidence: l.confidence, box: l.box?.mapped(into: area)) : nil
            }
            let parts = ScreenGroups.parts(kept.map(\.text))
            return Candidate(key: Text.key(parts.joined(separator: " ")), parts: parts,
                             box: Box.union(kept.compactMap(\.box)),
                             lineHeight: Text.median(kept.compactMap { $0.box?.height }) ?? 0.03)
        }

        private func process(_ c: Candidate, area: ExtraArea, state s: inout State) async -> ([Change], Bool) {
            let id = area.id
            if let on = s.onScreen, on.key == c.key {
                if let nb = c.box, nb != on.box {
                    s.onScreen = (on.key, nb, on.text)
                    return ([.show(element(id, nb, on.text, c.lineHeight))], false)
                }
                return ([], false)
            }
            if c.key.isEmpty {
                if s.onScreen != nil { s.onScreen = nil; return ([.remove(id: id)], false) }
                return ([], false)
            }
            var result = c.parts.map { translator.known($0) }
            let missing = result.indices.filter { result[$0] == nil }
            if !missing.isEmpty {
                do {
                    let tr = try await translator.translate(missing.map { c.parts[$0] })
                    for (i, idx) in missing.enumerated() {
                        let t = i < tr.count ? tr[i] : ""
                        result[idx] = t.trimmingCharacters(in: .whitespaces).isEmpty ? c.parts[idx] : t
                    }
                } catch {
                    return ([], true)
                }
            }
            let texts = result.map { $0 ?? "" }
            if zip(texts, c.parts).allSatisfy({ Text.ratio($0, $1) >= 0.90 }) {
                if s.onScreen != nil { s.onScreen = nil; return ([.remove(id: id)], false) }
                return ([], false)
            }
            let text = texts.joined(separator: "\n")
            let box = c.box ?? area.box
            s.onScreen = (c.key, box, text)
            return ([.show(element(id, box, text, c.lineHeight))], false)
        }

        private func element(_ id: String, _ box: Box, _ text: String, _ h: Double) -> ScreenElement {
            ScreenElement(kind: .extraArea, id: id, box: box, text: text, style: .init(lineHeight: h))
        }
    }
}

// MARK: - Buzlu zemin (§15)

extension GameReading {
    public enum Frost {
        /// Kutu x'te 0,04, y'de 0,035 genişletilir (kare dışına taşmaz).
        public static func expanded(_ b: Box) -> Box {
            Box(left: b.left - 0.04, top: b.top - 0.035, right: b.right + 0.04, bottom: b.bottom + 0.035).clamped
        }

        /// Son kareden buzlu zemin: base64 JPEG. Görüntü yoksa `nil`.
        public static func background(_ image: CGImage, box: Box) -> String? {
            #if canImport(CoreImage)
            let frame = ImageFrame(image)
            let e = expanded(box)
            guard let cut = frame.crop(e, scale: 1) else { return nil }
            let scale = min(1, 360 / Double(cut.width))
            var ci = CIImage(cgImage: cut)
            if scale < 1 { ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            let extent = ci.extent
            let radius = max(8, Double(cut.height) * scale * 0.55)
            guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
            blur.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(radius, forKey: kCIInputRadiusKey)
            guard let blurred = blur.outputImage?.cropped(to: extent), let color = CIFilter(name: "CIColorControls") else { return nil }
            color.setValue(blurred, forKey: kCIInputImageKey)
            color.setValue(-0.12, forKey: kCIInputBrightnessKey)
            color.setValue(1.15, forKey: kCIInputSaturationKey)
            color.setValue(0.9, forKey: kCIInputContrastKey)
            guard let out = color.outputImage else { return nil }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let data = ctx.jpegRepresentation(of: out, colorSpace: space,
                                                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.55]) else { return nil }
            return data.base64EncodedString()
            #else
            return nil
            #endif
        }
    }
}
