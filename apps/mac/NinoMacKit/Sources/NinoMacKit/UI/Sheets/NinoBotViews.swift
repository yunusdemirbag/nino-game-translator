// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Nino'ya Sor robotu (ninoya-sor.md §1): göz kırpma, süzülme, düşünme; üçü ayrı açılıp kapanır.
/// "Hareketi azalt" açıksa ya da ekran görüntüsünde hareketsiz durur. Ekran okuyucudan gizli (süs).
struct NinoBotView: View {
    let size: CGFloat
    var blinks = true
    var floats = false
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic
    @State private var eyesClosed = false
    @State private var floatUp = false
    @State private var rockRight = false

    private var animated: Bool { !reduceMotion && !isStatic }

    var body: some View {
        (eyesClosed ? NinoBotImage.blink : NinoBotImage.open).image
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(animated && thinking ? (rockRight ? 6 : -6) : 0))
            .offset(y: animated && floats ? (floatUp ? -size * 0.05 : size * 0.05) : 0)
            .accessibilityHidden(true)
            .task(id: blinks) { await blinkLoop() }
            .onChange(of: thinking, initial: true) { _, on in
                guard animated else { return }
                if on {
                    rockRight = false
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { rockRight = true }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { rockRight = false }
                }
            }
            .onAppear {
                guard animated, floats else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { floatUp = true }
            }
    }

    private func blinkLoop() async {
        guard animated, blinks else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 4...5)))
            eyesClosed = true
            try? await Task.sleep(for: .milliseconds(150))
            eyesClosed = false
        }
    }
}

/// "Yazıyor" noktaları: üç küçük daire sırayla büyüyüp küçülür.
struct TypingDots: View {
    private let diameter: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ninoStaticRendering) private var isStatic

    var body: some View {
        if reduceMotion || isStatic {
            dots(phase: nil)
        } else {
            TimelineView(.animation) { context in
                dots(phase: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dots(phase: Double?) -> some View {
        HStack(spacing: diameter * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                let wave: Double = {
                    guard let phase else { return 0.5 }
                    let t = (phase - Double(index) * 0.18).truncatingRemainder(dividingBy: 1.2) / 1.2
                    return (sin(t * 2 * .pi) + 1) / 2
                }()
                Circle()
                    .fill(NinoColor.textSecondary)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(0.75 + 0.35 * wave)
                    .opacity(0.35 + 0.65 * wave)
            }
        }
    }
}

/// Sığmayanı alt satıra geçiren basit akış düzeni (öneri hapları).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
